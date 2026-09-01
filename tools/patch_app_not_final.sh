#!/usr/bin/env bash
set -euo pipefail
APK="${1:-diagnostics-vod-media-fallback/Xuper-6.2.4-VOD-StaticFallback-NoFrida.apk}"
WORK='/tmp/xuper-vod-direct'
PATCH="$WORK/app-not-final-patch"
SMALI_JAR="$WORK/smali-fat.jar"
BAKSMALI_JAR="$WORK/baksmali-fat.jar"
KEYSTORE="$WORK/test.jks"
for f in "$APK" "$SMALI_JAR" "$BAKSMALI_JAR" "$KEYSTORE"; do test -s "$f"; done
rm -rf "$PATCH"; mkdir -p "$PATCH"
FOUND=''
for entry in $(unzip -Z1 "$APK" | grep -E '^classes([0-9]+)?[.]dex$' | sort -V); do
  tag=${entry%.dex}
  dex="$PATCH/$entry"
  dir="$PATCH/smali-$tag"
  unzip -p "$APK" "$entry" > "$dex"
  rm -rf "$dir"
  if java -jar "$BAKSMALI_JAR" disassemble "$dex" -o "$dir" >/dev/null 2>&1; then
    target="$dir/com/mobile/brasiltv/app/App.smali"
    if [ -s "$target" ]; then
      FOUND="$entry"
      cp "$target" "$PATCH/App-original.smali"
      python3 - "$target" <<'PY'
import pathlib,re,sys
p=pathlib.Path(sys.argv[1])
s=p.read_text()
# Allow the wrapper Application to subclass the recovered real App.
s,n1=re.subn(r'(?m)^\.class\s+(.+?)\bfinal\s+(Lcom/mobile/brasiltv/app/App;)$', r'.class \1\2', s, count=1)
if n1 != 1:
    raise SystemExit('App class final flag not matched exactly once')
# App.c() is the FirebaseInstallations startup hook seen in the native ARM64 crash stack.
# Keep the rest of App.onCreate intact, but make that optional telemetry/bootstrap hook a no-op.
pat=r'(?ms)^\.method\s+([^\n]*\s)?c\(\)V\n.*?^\.end method$'
m=re.search(pat,s)
if not m:
    raise SystemExit('App.c()V not found')
header=m.group(0).splitlines()[0]
replacement=header+'\n    .locals 0\n    return-void\n.end method'
s=s[:m.start()]+replacement+s[m.end():]
p.write_text(s)
print('APP_C_FIREBASE_HOOK_NOOP_OK')
PY
      zaad="$dir/com/google/android/gms/common/api/internal/zaad.smali"
      if [ -s "$zaad" ]; then
        cp "$zaad" "$PATCH/zaad-original.smali"
        python3 - "$zaad" <<'PY'
import pathlib,re,sys
p=pathlib.Path(sys.argv[1])
s=p.read_text()
# Android 15 rejects the recovered zaad.zac body because BasePendingResult is not
# verifier-compatible with PendingResult in this recovered multidex set. The hook
# only tracks pending results for GoogleApi cleanup, so make this specific method
# a no-op while preserving the rest of Google Play Services.
pat=r'(?ms)^\.method\s+([^\n]*\s)?zac\(Lcom/google/android/gms/common/api/internal/BasePendingResult;Z\)V\n.*?^\.end method$'
m=re.search(pat,s)
if not m:
    raise SystemExit('zaad.zac(BasePendingResult,Z)V not found')
header=m.group(0).splitlines()[0]
replacement=header+'\n    .locals 0\n    return-void\n.end method'
s=s[:m.start()]+replacement+s[m.end():]
p.write_text(s)
print('ZAAD_ZAC_VERIFYERROR_NOOP_OK')
PY
        cp "$zaad" "$PATCH/zaad-patched.smali"
      else
        echo 'zaad.smali not present in App dex' >&2
        exit 66
      fi
      java -jar "$SMALI_JAR" assemble "$dir" -o "$PATCH/$entry.new"
      test -s "$PATCH/$entry.new"
      break
    fi
  fi
done
test -n "$FOUND"
echo "APP_DEX=$FOUND"
cp "$APK" "$PATCH/unsigned.apk"
zip -q -d "$PATCH/unsigned.apk" 'META-INF/*.RSA' 'META-INF/*.DSA' 'META-INF/*.EC' 'META-INF/*.SF' 'META-INF/MANIFEST.MF' "$FOUND" >/dev/null 2>&1 || true
cp "$PATCH/$FOUND.new" "$PATCH/$FOUND"
(cd "$PATCH" && zip -q -u unsigned.apk "$FOUND")
zipalign -f 4 "$PATCH/unsigned.apk" "$PATCH/aligned.apk"
apksigner sign --ks "$KEYSTORE" --ks-pass pass:android --key-pass pass:android --ks-key-alias androiddebugkey --out "$PATCH/signed.apk" "$PATCH/aligned.apk"
apksigner verify --verbose "$PATCH/signed.apk" >/dev/null
cp "$PATCH/signed.apk" "$APK"
echo 'APP_FINAL_FIREBASE_AND_ZAAD_VERIFY_PATCH_OK'
sha256sum "$APK"
