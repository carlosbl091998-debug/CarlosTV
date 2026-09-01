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
old=s
s=re.sub(r'(?m)^\.class\s+(.+?)\bfinal\s+(Lcom/mobile/brasiltv/app/App;)$', r'.class \1\2', s, count=1)
if s==old:
    raise SystemExit('App class was not final or class declaration not matched')
p.write_text(s)
PY
      cp "$target" "$PATCH/App-patched.smali"
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
echo 'APP_FINAL_REMOVED_OK'
sha256sum "$APK"
