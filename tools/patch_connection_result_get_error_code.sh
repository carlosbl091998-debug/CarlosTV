#!/usr/bin/env bash
set -euo pipefail
APK="${1:?apk path required}"
WORK='/tmp/xuper-vod-direct'
SMALI_JAR="$WORK/smali-fat.jar"
BAKSMALI_JAR="$WORK/baksmali-fat.jar"
KEYSTORE="$WORK/test.jks"
PATCH="$WORK/connection-result-patch"
for f in "$APK" "$SMALI_JAR" "$BAKSMALI_JAR" "$KEYSTORE"; do test -s "$f"; done
rm -rf "$PATCH"; mkdir -p "$PATCH"
FOUND=''
for entry in $(unzip -Z1 "$APK" | grep -E '^classes([0-9]+)?[.]dex$' | sort -V); do
  dex="$PATCH/$entry"
  dir="$PATCH/smali-${entry%.dex}"
  unzip -p "$APK" "$entry" > "$dex"
  rm -rf "$dir"
  if ! java -jar "$BAKSMALI_JAR" disassemble "$dex" -o "$dir" >/dev/null 2>&1; then
    continue
  fi
  target="$dir/com/google/android/gms/common/ConnectionResult.smali"
  [ -s "$target" ] || continue
  FOUND="$entry"
  cp "$target" "$PATCH/ConnectionResult-original.smali"
  python3 - "$target" <<'PY'
import pathlib,re,sys
p=pathlib.Path(sys.argv[1])
s=p.read_text()
if re.search(r'(?m)^\.method\s+[^\n]*\bgetErrorCode\(\)I$', s):
    print('GET_ERROR_CODE_ALREADY_PRESENT')
else:
    # Standard Google Play Services ConnectionResult stores the connection error code
    # in its second int instance field (normally named zzb). Resolve that field from
    # the class instead of assuming an obfuscation-stable name.
    fields=[]
    for m in re.finditer(r'(?m)^\.field\s+([^\n]*)\s+([A-Za-z0-9_$]+):I$', s):
        mods,name=m.group(1),m.group(2)
        if ' static ' in (' '+mods+' '):
            continue
        fields.append(name)
    if len(fields) < 2:
        raise SystemExit(f'Expected at least two instance int fields in ConnectionResult, got {fields!r}')
    field=fields[1]
    method=("\n.method public getErrorCode()I\n"
            "    .locals 1\n"
            f"    iget v0, p0, Lcom/google/android/gms/common/ConnectionResult;->{field}:I\n"
            "    return v0\n"
            ".end method\n")
    s=s.rstrip()+"\n"+method
    p.write_text(s)
    print('CONNECTION_RESULT_GET_ERROR_CODE_INJECTED field='+field)
PY
  cp "$target" "$PATCH/ConnectionResult-patched.smali"
  java -jar "$SMALI_JAR" assemble "$dir" -o "$PATCH/$entry.new"
  test -s "$PATCH/$entry.new"
  break
done
test -n "$FOUND"
echo "CONNECTION_RESULT_DEX=$FOUND"
cp "$APK" "$PATCH/unsigned.apk"
zip -q -d "$PATCH/unsigned.apk" 'META-INF/*.RSA' 'META-INF/*.DSA' 'META-INF/*.EC' 'META-INF/*.SF' 'META-INF/MANIFEST.MF' "$FOUND" >/dev/null 2>&1 || true
cp "$PATCH/$FOUND.new" "$PATCH/$FOUND"
(cd "$PATCH" && zip -q -u unsigned.apk "$FOUND")
zipalign -f 4 "$PATCH/unsigned.apk" "$PATCH/aligned.apk"
apksigner sign --ks "$KEYSTORE" --ks-pass pass:android --key-pass pass:android --ks-key-alias androiddebugkey --out "$PATCH/signed.apk" "$PATCH/aligned.apk"
apksigner verify --verbose "$PATCH/signed.apk" >/dev/null
cp "$PATCH/signed.apk" "$APK"
echo 'CONNECTION_RESULT_GET_ERROR_CODE_PATCH_OK'
sha256sum "$APK"
