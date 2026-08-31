#!/usr/bin/env bash
set -euo pipefail

# Build the existing patched runtime DEX first, then use that recovered runtime
# as the primary classes.dex instead of adding it as classes2.dex. This avoids
# loading duplicate app classes beside the protected shell DEX.
bash tools/build_vod_media_fallback.sh

OUT='diagnostics-vod-direct-runtime'
WORK='/tmp/xuper-vod-direct-runtime'
BASE='xuper-stable.apk'
SRC='diagnostics-vod-media-fallback/Xuper-6.2.4-VOD-StaticFallback-NoFrida.apk'
rm -rf "$OUT" "$WORK"
mkdir -p "$OUT" "$WORK"

test -s "$BASE"
test -s "$SRC"
unzip -p "$SRC" classes2.dex > "$WORK/classes.dex"
test -s "$WORK/classes.dex"
sha256sum "$WORK/classes.dex" | tee "$OUT/runtime-primary-dex-sha256.txt"

cp "$BASE" "$WORK/unsigned.apk"
zip -q -d "$WORK/unsigned.apk" 'META-INF/*.RSA' 'META-INF/*.DSA' 'META-INF/*.EC' 'META-INF/*.SF' 'META-INF/MANIFEST.MF' >/dev/null 2>&1 || true
zip -q -d "$WORK/unsigned.apk" classes.dex classes2.dex >/dev/null 2>&1 || true
(cd "$WORK" && zip -q -u unsigned.apk classes.dex)

KEYSTORE="$WORK/test.jks"
keytool -genkeypair -noprompt -keystore "$KEYSTORE" -storepass android -keypass android -alias androiddebugkey -dname 'CN=Xuper Direct Runtime VOD,O=Android,C=MX' -keyalg RSA -keysize 2048 -validity 10000 >/dev/null 2>&1
APKSIGNER="$(command -v apksigner || true)"
ZIPALIGN="$(command -v zipalign || true)"
if [ -z "$APKSIGNER" ]; then APKSIGNER=$(find "$ANDROID_HOME/build-tools" -type f -name apksigner | sort -V | tail -1); fi
if [ -z "$ZIPALIGN" ]; then ZIPALIGN=$(find "$ANDROID_HOME/build-tools" -type f -name zipalign | sort -V | tail -1); fi
test -n "$APKSIGNER"; test -n "$ZIPALIGN"
"$ZIPALIGN" -f 4 "$WORK/unsigned.apk" "$WORK/aligned.apk"
CANDIDATE="$OUT/Xuper-6.2.4-VOD-DirectRuntime-NoFrida.apk"
"$APKSIGNER" sign --ks "$KEYSTORE" --ks-pass pass:android --key-pass pass:android --ks-key-alias androiddebugkey --out "$CANDIDATE" "$WORK/aligned.apk"
"$APKSIGNER" verify --verbose --print-certs "$CANDIDATE" > "$OUT/signing.txt"
sha256sum "$CANDIDATE" | tee "$OUT/candidate-sha256.txt"
unzip -l "$CANDIDATE" > "$OUT/package-files.txt"
if unzip -l "$CANDIDATE" | grep -q 'classes2.dex'; then
  echo 'UNEXPECTED_CLASSES2_DEX' >&2
  exit 51
fi
if grep -Eqi 'libgadget|VodFixProvider' "$OUT/package-files.txt"; then
  echo 'FRIDA_COMPONENT_FOUND' >&2
  exit 52
fi
echo 'DIRECT_RUNTIME_PRIMARY_DEX_BUILD_OK' | tee "$OUT/build-result.txt"
