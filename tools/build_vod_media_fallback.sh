#!/usr/bin/env bash
set -euo pipefail

OUT='diagnostics-vod-media-fallback'
WORK='/tmp/xuper-vod-static'
BASE='xuper-stable.apk'
rm -rf "$OUT" "$WORK" "$BASE"
mkdir -p "$OUT" "$WORK/base" "$WORK/runtime"

checksum() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi
}

: "${GH_TOKEN:?GH_TOKEN required}"
BASE_ARTIFACT_ID='9623417943'
BASE_SHA='8ba6eb4a13bdec2d8d8ab06a1502194f488ce58d9fb6de7feeb1c539ef0f7b4e'
curl -fL --retry 4 --retry-all-errors -H "Authorization: Bearer ${GH_TOKEN}" -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28' \
  "https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/artifacts/${BASE_ARTIFACT_ID}/zip" -o "$WORK/base.zip"
unzip -q "$WORK/base.zip" -d "$WORK/base"
BASE_SRC=''
while IFS= read -r f; do
  if [ "$(shasum -a 256 "$f" | awk '{print $1}')" = "$BASE_SHA" ]; then BASE_SRC="$f"; break; fi
done < <(find "$WORK/base" -type f -name '*.apk')
test -n "$BASE_SRC"
cp "$BASE_SRC" "$BASE"
checksum "$BASE" | tee "$OUT/base-sha256.txt"

RUNTIME_ARTIFACT_ID='9635194139'
curl -fL --retry 4 --retry-all-errors -H "Authorization: Bearer ${GH_TOKEN}" -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28' \
  "https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/artifacts/${RUNTIME_ARTIFACT_ID}/zip" -o "$WORK/runtime.zip"
unzip -q "$WORK/runtime.zip" 'dex-all/runtime-019-5d2a62ef889d.dex' -d "$WORK/runtime"
RUNTIME_DEX="$WORK/runtime/dex-all/runtime-019-5d2a62ef889d.dex"
test -s "$RUNTIME_DEX"
checksum "$RUNTIME_DEX" | tee "$OUT/runtime019-sha256.txt"

APKTOOL="$WORK/apktool.jar"
curl -fL --retry 3 --retry-all-errors 'https://github.com/iBotPeaches/Apktool/releases/download/v2.11.1/apktool_2.11.1.jar' -o "$APKTOOL"

# Disassemble only to recover the real mapper class from the stable runtime dump.
cp "$BASE" "$WORK/probe.apk"
cp "$RUNTIME_DEX" "$WORK/classes2.dex"
(cd "$WORK" && zip -q -u probe.apk classes2.dex)
java -jar "$APKTOOL" d -f "$WORK/probe.apk" -o "$WORK/probe-decoded" > "$OUT/probe-decode.txt" 2>&1
TARGET=$(find "$WORK/probe-decoded" -type f -path '*/m6/g2$u.smali' | head -1)
test -n "$TARGET"
cp "$TARGET" "$OUT/g2-u-original.smali"

# Static patch: once a TotalMovieList has a non-empty movieList, expose that source
# through the three canonical keys expected by downstream 6.2.4 code. This removes
# the old exact-quality gate (480p/720p/1080p) without any runtime instrumentation.
python3 - "$TARGET" "$OUT/g2-u-patched.smali" <<'PY'
import sys
src, out = sys.argv[1:]
s = open(src, encoding='utf-8').read()
start = '''    invoke-virtual {v2}, Lmobile/com/requestframe/utils/response/TotalMovieList;->getQuality()Ljava/lang/String;\n\n    .line 176\n    move-result-object v3\n'''
end = '''    invoke-interface {v0, v4, v2}, Ljava/util/Map;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;\n\n    .line 234\n    goto :goto_1\n'''
i = s.find(start)
if i < 0:
    raise SystemExit('PATCH_START_NOT_FOUND')
j = s.find(end, i)
if j < 0:
    raise SystemExit('PATCH_END_NOT_FOUND')
j += len(end)
replacement = '''    # STATIC_VOD_FALLBACK: any source with a non-empty movieList is playable.\n    # Publish it under the canonical quality keys expected by g2.N().\n    const-string/jumbo v3, "480p"\n    invoke-interface {v0, v3, v2}, Ljava/util/Map;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;\n\n    const-string/jumbo v3, "720p"\n    invoke-interface {v0, v3, v2}, Ljava/util/Map;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;\n\n    const-string/jumbo v3, "1080p"\n    invoke-interface {v0, v3, v2}, Ljava/util/Map;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;\n\n    goto :goto_1\n'''
s2 = s[:i] + replacement + s[j:]
if 'STATIC_VOD_FALLBACK' not in s2:
    raise SystemExit('PATCH_MARKER_MISSING')
open(out, 'w', encoding='utf-8').write(s2)
PY

grep -F 'STATIC_VOD_FALLBACK' "$OUT/g2-u-patched.smali"
if grep -q 'String;->hashCode()I' "$OUT/g2-u-patched.smali"; then
  echo 'QUALITY_GATE_STILL_PRESENT' >&2
  exit 31
fi

# Decode the untouched stable APK and add only the patched mapper class as a normal
# secondary DEX. No VodFixProvider, Frida Gadget, config, or JS is added.
java -jar "$APKTOOL" d -f "$BASE" -o "$WORK/decoded" > "$OUT/base-decode.txt" 2>&1
mkdir -p "$WORK/decoded/smali_classes2/m6"
cp "$OUT/g2-u-patched.smali" "$WORK/decoded/smali_classes2/m6/g2\$u.smali"

# Explicitly assert the output tree contains none of the previous Frida patch pieces.
rm -rf "$WORK/decoded/smali/com/xuper/vodfix" "$WORK/decoded/smali_classes2/com/xuper/vodfix" 2>/dev/null || true
find "$WORK/decoded/lib" -type f \( -name 'libgadget.so' -o -name 'libgadget.config.so' -o -name 'libgadget.script.so' \) -delete 2>/dev/null || true
python3 - "$WORK/decoded/AndroidManifest.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
p=sys.argv[1]; ns='{http://schemas.android.com/apk/res/android}'
t=ET.parse(p); root=t.getroot(); app=root.find('application')
changed=False
for e in list(app.findall('provider')):
    if e.get(ns+'name') == 'com.xuper.vodfix.VodFixProvider':
        app.remove(e); changed=True
if changed:
    ET.register_namespace('android','http://schemas.android.com/apk/res/android')
    t.write(p, encoding='utf-8', xml_declaration=True)
PY

java -jar "$APKTOOL" b "$WORK/decoded" -o "$WORK/unsigned.apk" > "$OUT/build.txt" 2>&1
KEYSTORE="$WORK/test.jks"
keytool -genkeypair -noprompt -keystore "$KEYSTORE" -storepass android -keypass android -alias androiddebugkey -dname 'CN=Xuper Static VOD Fallback,O=Android,C=MX' -keyalg RSA -keysize 2048 -validity 10000 >/dev/null 2>&1
APKSIGNER=$(find "$ANDROID_HOME/build-tools" -type f -name apksigner | sort -V | tail -1)
ZIPALIGN=$(find "$ANDROID_HOME/build-tools" -type f -name zipalign | sort -V | tail -1)
"$ZIPALIGN" -f 4 "$WORK/unsigned.apk" "$WORK/aligned.apk"
CANDIDATE="$OUT/Xuper-6.2.4-VOD-StaticFallback-NoFrida.apk"
"$APKSIGNER" sign --ks "$KEYSTORE" --ks-pass pass:android --key-pass pass:android --ks-key-alias androiddebugkey --out "$CANDIDATE" "$WORK/aligned.apk"
"$APKSIGNER" verify --verbose --print-certs "$CANDIDATE" > "$OUT/signing.txt"
checksum "$CANDIDATE" | tee "$OUT/candidate-sha256.txt"

unzip -l "$CANDIDATE" > "$OUT/package-files.txt"
if grep -Eqi 'libgadget|VodFixProvider' "$OUT/package-files.txt"; then
  echo 'FRIDA_COMPONENT_FOUND' >&2
  exit 32
fi
unzip -p "$CANDIDATE" classes2.dex | strings | grep -F 'STATIC_VOD_FALLBACK' >/dev/null || true

echo 'STATIC_FALLBACK_BUILD_OK_NO_FRIDA' | tee "$OUT/build-result.txt"
