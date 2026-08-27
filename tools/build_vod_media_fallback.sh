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
# Known stable APK that opens on the device.
BASE_ARTIFACT_ID='9623417943'
curl -fL --retry 4 --retry-all-errors -H "Authorization: Bearer ${GH_TOKEN}" -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28' \
  "https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/artifacts/${BASE_ARTIFACT_ID}/zip" -o "$WORK/base.zip"
unzip -q "$WORK/base.zip" -d "$WORK/base"
BASE_SRC=''
while IFS= read -r f; do
  if [ "$(shasum -a 256 "$f" | awk '{print $1}')" = '8ba6eb4a13bdec2d8d8ab06a1502194f488ce58d9fb6de7feeb1c539ef0f7b4e' ]; then BASE_SRC="$f"; break; fi
done < <(find "$WORK/base" -type f -name '*.apk')
test -n "$BASE_SRC"
cp "$BASE_SRC" "$BASE"
checksum "$BASE" | tee "$OUT/base-sha256.txt"

# Runtime DEX captured from this same stable build. No Frida/Gadget is embedded in the output APK.
RUNTIME_ARTIFACT_ID='9635194139'
curl -fL --retry 4 --retry-all-errors -H "Authorization: Bearer ${GH_TOKEN}" -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28' \
  "https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/artifacts/${RUNTIME_ARTIFACT_ID}/zip" -o "$WORK/runtime.zip"
unzip -q "$WORK/runtime.zip" 'dex-all/runtime-019-5d2a62ef889d.dex' -d "$WORK/runtime"
RUNTIME_DEX="$WORK/runtime/dex-all/runtime-019-5d2a62ef889d.dex"
test -s "$RUNTIME_DEX"
checksum "$RUNTIME_DEX" | tee "$OUT/runtime019-sha256.txt"

APKTOOL="$WORK/apktool.jar"
curl -fL --retry 3 --retry-all-errors 'https://github.com/iBotPeaches/Apktool/releases/download/v2.11.1/apktool_2.11.1.jar' -o "$APKTOOL"

# Make a temporary APK only so apktool disassembles runtime-019 as classes2.dex.
cp "$BASE" "$WORK/probe.apk"
cp "$RUNTIME_DEX" "$WORK/classes2.dex"
(cd "$WORK" && zip -q -u probe.apk classes2.dex)
java -jar "$APKTOOL" d -f "$WORK/probe.apk" -o "$WORK/probe-decoded" > "$OUT/probe-decode.txt" 2>&1
TARGET=$(find "$WORK/probe-decoded" -type f -path '*/m6/g2$u.smali' | head -1)
test -n "$TARGET"
cp "$TARGET" "$OUT/g2-u-original.smali"

echo 'STATIC_DEX_PROBE_OK' | tee "$OUT/build-result.txt"
