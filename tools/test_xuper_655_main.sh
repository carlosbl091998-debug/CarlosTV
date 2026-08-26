#!/usr/bin/env bash
set -euo pipefail

# Reused by the existing Android-16 runner, but this pass is intentionally
# MAGIS 6.2.4 ONLY. We do not install or download 6.5.5 here.
PKG='com.msandroid.mobile'
OUT='diagnostics-update'
TARGET_CODE='60204'
TARGET_NAME='6.2.4'
mkdir -p "$OUT/candidates" "$OUT/dexdump"

AAPT=$(find "$ANDROID_HOME/build-tools" -type f -name aapt | sort -V | tail -1)
APKSIGNER=$(find "$ANDROID_HOME/build-tools" -type f -name apksigner | sort -V | tail -1)

# The workflow already downloads an older official signed bootstrap. We only use
# its signer as the trust anchor; it is never used as the final app.
EXPECTED_CERT=$($APKSIGNER verify --print-certs magis-current.apk 2>/dev/null | sed -n 's/.*certificate SHA-256 digest: //p' | head -1 | tr -d ':[:space:]' | tr '[:upper:]' '[:lower:]')
echo "expected_cert=$EXPECTED_CERT" | tee "$OUT/expected-cert.txt"
[[ "$EXPECTED_CERT" == 'd30dc60fd8625d49fa4e82eb442c9307743f9621004b94e229dcc01f6a9035ff' ]] || {
  echo 'UNEXPECTED_OFFICIAL_SIGNER' >&2
  exit 70
}

validate_624() {
  local f="$1" tag="$2"
  unzip -t "$f" >/dev/null 2>&1 || return 1
  "$AAPT" dump badging "$f" > "$OUT/candidates/${tag}-badging.txt" 2>&1 || return 1
  grep -q "package: name='$PKG' versionCode='$TARGET_CODE' versionName='$TARGET_NAME'" "$OUT/candidates/${tag}-badging.txt" || return 1
  "$APKSIGNER" verify --verbose --print-certs "$f" > "$OUT/candidates/${tag}-signing.txt" 2>&1 || return 1
  local cert
  cert=$($APKSIGNER verify --print-certs "$f" 2>/dev/null | sed -n 's/.*certificate SHA-256 digest: //p' | head -1 | tr -d ':[:space:]' | tr '[:upper:]' '[:lower:]')
  echo "$cert" > "$OUT/candidates/${tag}-cert.txt"
  [[ "$cert" == "$EXPECTED_CERT" ]] || return 1
  sha256sum "$f" > "$OUT/candidates/${tag}-sha256.txt"
  return 0
}

SOURCES=(
  'https://aftv.news/4721725'
  'https://aftvnews.com/4721725'
  'https://www.aftvnews.com/4721725'
  'https://go.aftvnews.com/4721725'
  'https://appteka.store/apps/cb8r309715/download'
)

APK624='Magis-6.2.4.apk'
rm -f "$APK624"
for i in "${!SOURCES[@]}"; do
  src="${SOURCES[$i]}"
  tag="source-$((i+1))"
  f="$OUT/candidates/${tag}.bin"
  echo "TRY_624 $src" | tee -a "$OUT/actions.txt"
  if curl -fL --retry 3 --retry-all-errors --connect-timeout 15 --max-time 180 \
      -A 'Mozilla/5.0 (Linux; Android 16; Pixel 6)' "$src" -o "$f" \
      >"$OUT/candidates/${tag}-curl-stdout.txt" 2>"$OUT/candidates/${tag}-curl-stderr.txt"; then
    if validate_624 "$f" "$tag"; then
      cp "$f" "$APK624"
      echo "ACCEPTED_624 $src" | tee -a "$OUT/actions.txt"
      break
    fi
  fi
done

[[ -s "$APK624" ]] || { echo 'NO_OFFICIAL_624_SOURCE_FOUND' >&2; exit 71; }
"$AAPT" dump badging "$APK624" | tee "$OUT/magis624-badging.txt"
"$APKSIGNER" verify --verbose --print-certs "$APK624" | tee "$OUT/magis624-signing.txt"
sha256sum "$APK624" | tee "$OUT/magis624-sha256.txt"

# Install the old 6.2.4 itself. No upgrade is performed after this point.
adb root || true
adb wait-for-device
adb install -r -g "$APK624" | tee "$OUT/install-624.txt"
adb shell pm clear "$PKG" || true
adb shell settings put global window_animation_scale 0 || true
adb shell settings put global transition_animation_scale 0 || true
adb shell settings put global animator_duration_scale 0 || true

adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
sleep 18
adb shell pidof "$PKG" | tee "$OUT/pid-before-frida.txt" || true
adb shell uiautomator dump /sdcard/magis624.xml >/dev/null 2>&1 || true
adb pull /sdcard/magis624.xml "$OUT/ui-624.xml" >/dev/null 2>&1 || true
adb exec-out screencap -p > "$OUT/screen-624.png" || true
adb logcat -d -v threadtime | grep -Ei 'com\.msandroid\.mobile|SecNeo|DexHelper|AndroidRuntime|FATAL EXCEPTION' | tail -1500 > "$OUT/logcat-before-frida.txt" || true

# The APK is SecNeo/Bangcle packed. Static edits touch the protected container,
# so dump the already-decrypted DEX from the live 6.2.4 process instead.
FRIDA_VERSION='17.2.17'
python3 -m venv /tmp/frida-venv
source /tmp/frida-venv/bin/activate
python -m pip install --upgrade pip
python -m pip install "frida==$FRIDA_VERSION" frida-tools frida-dexdump
frida --version | tee "$OUT/frida-version.txt"

curl -fL --retry 3 --retry-all-errors \
  "https://github.com/frida/frida/releases/download/${FRIDA_VERSION}/frida-server-${FRIDA_VERSION}-android-x86_64.xz" \
  -o /tmp/frida-server.xz
xz -dc /tmp/frida-server.xz > /tmp/frida-server
chmod +x /tmp/frida-server
adb push /tmp/frida-server /data/local/tmp/frida-server >/dev/null
adb shell chmod 755 /data/local/tmp/frida-server
adb shell 'pkill -9 frida-server || true; nohup /data/local/tmp/frida-server >/data/local/tmp/frida-server.log 2>&1 &' || true
sleep 4
frida-ps -Uai | tee "$OUT/frida-ps.txt" || true

# Ensure Magis is alive after the instrumentation server starts.
adb shell am force-stop "$PKG" || true
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
sleep 15
PID=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true)
echo "pid=$PID" | tee "$OUT/pid-frida.txt"
[[ -n "$PID" ]] || { adb shell cat /data/local/tmp/frida-server.log > "$OUT/frida-server.log" || true; exit 72; }

set +e
frida-dexdump -U -n "$PKG" -o "$OUT/dexdump" 2>&1 | tee "$OUT/frida-dexdump.txt"
DEX_RC=${PIPESTATUS[0]}
set -e
echo "frida_dexdump_rc=$DEX_RC" | tee "$OUT/frida-dexdump-rc.txt"
adb shell cat /data/local/tmp/frida-server.log > "$OUT/frida-server.log" 2>/dev/null || true

find "$OUT/dexdump" -type f -name '*.dex' -print -exec sha256sum {} \; | tee "$OUT/dex-files.txt" || true
COUNT=$(find "$OUT/dexdump" -type f -name '*.dex' | wc -l | tr -d ' ')
echo "dex_count=$COUNT" | tee "$OUT/dex-count.txt"

# Locate the exact update implementation in the decrypted payload.
grep -RIna --binary-files=text -E \
  'handleForceUpgrade|handleUpgradeBussiness|CommonUpgradeDialog|UpgradeDialog|forceUpdate|getForceUpdate|hasNewVersion|dialog_common_upgrade|upgradeVerCode|getUpgradeVerCode' \
  "$OUT/dexdump" > "$OUT/upgrade-symbol-hits.txt" || true
head -300 "$OUT/upgrade-symbol-hits.txt" | tee "$OUT/upgrade-symbol-hits-head.txt" || true

if [[ "$COUNT" -eq 0 ]]; then
  echo 'RUNTIME_DEX_DUMP_EMPTY' >&2
  exit 73
fi

# Stop intentionally here. The old workflow has a later 6.5.5 verification step;
# failing this reused job prevents it from ever installing or validating 6.5.5.
echo 'MAGIS_624_RUNTIME_DEX_DUMP_COMPLETE_NO_UPDATE_PERFORMED' | tee "$OUT/result.txt"
exit 86
