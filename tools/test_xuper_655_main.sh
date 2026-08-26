#!/usr/bin/env bash
set -euo pipefail

PKG='com.msandroid.mobile'
OUT='diagnostics-update'
TARGET_CODE='60505'
TARGET_NAME='6.5.5'
UPDATE_URL='https://gaeg.xvmobdes.com/download'
mkdir -p "$OUT"

run_timeout() { local secs="$1"; shift; timeout "$secs" "$@"; }
version_code() { adb shell dumpsys package "$PKG" 2>/dev/null | sed -n 's/.*versionCode=\([0-9]*\).*/\1/p' | head -1 | tr -d '\r'; }
version_name() { adb shell dumpsys package "$PKG" 2>/dev/null | sed -n 's/.*versionName=\(.*\)/\1/p' | head -1 | tr -d '\r'; }
launch_app() {
  adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
  run_timeout 20s adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
}
dump_ui() {
  local tag="$1" remote="/sdcard/ui-${1}.xml"
  run_timeout 10s adb shell uiautomator dump "$remote" >/dev/null 2>&1 || true
  run_timeout 10s adb pull "$remote" "$OUT/ui-${tag}.xml" >/dev/null 2>&1 || true
  run_timeout 10s adb exec-out screencap -p > "$OUT/screen-${tag}.png" || true
}
xml_has() {
  local xml="$1" needle="$2"
  python3 - "$xml" "$needle" <<'PY'
import sys, xml.etree.ElementTree as ET
try: root=ET.parse(sys.argv[1]).getroot()
except Exception: raise SystemExit(1)
needle=sys.argv[2].casefold()
text='\n'.join((n.attrib.get('text','')+' '+n.attrib.get('content-desc','')) for n in root.iter('node')).casefold()
raise SystemExit(0 if needle in text else 1)
PY
}
is_update_gate() {
  local xml="$1"
  xml_has "$xml" 'Actualización de versión' || \
  xml_has "$xml" 'Version Upgrade' || \
  xml_has "$xml" 'V6.5.5' || \
  xml_has "$xml" 'Current version:' || \
  xml_has "$xml" 'Versión actual:'
}

AAPT=$(find "$ANDROID_HOME/build-tools" -type f -name aapt | sort -V | tail -1)
APKSIGNER=$(find "$ANDROID_HOME/build-tools" -type f -name apksigner | sort -V | tail -1)

echo '=== install official signed bootstrap ===' | tee "$OUT/actions.txt"
run_timeout 45s adb install -r -g magis-current.apk | tee "$OUT/install-bootstrap.txt"
EXPECTED_CERT=$($APKSIGNER verify --print-certs magis-current.apk 2>/dev/null | sed -n 's/.*certificate SHA-256 digest: //p' | head -1 | tr -d ':[:space:]' | tr '[:upper:]' '[:lower:]')
echo "expected_cert=$EXPECTED_CERT" | tee "$OUT/expected-cert.txt"
[[ -n "$EXPECTED_CERT" ]] || { echo 'BOOTSTRAP_CERT_NOT_FOUND' >&2; exit 60; }

launch_app
sleep 15
dump_ui bootstrap-before-update
echo "bootstrap_code=$(version_code || true) bootstrap_name=$(version_name || true)" | tee "$OUT/bootstrap-version.txt"

echo "update_url=$UPDATE_URL" | tee "$OUT/update-url.txt"
curl -fL --retry 5 --retry-all-errors --connect-timeout 20 --max-time 180 \
  -A 'Mozilla/5.0 (Linux; Android 16; Pixel 6) AppleWebKit/537.36 Chrome/140 Mobile Safari/537.36' \
  -D "$OUT/update-response-headers.txt" \
  -w '%{url_effective}\n%{http_code}\n%{content_type}\n' \
  "$UPDATE_URL" -o "$OUT/update-download.bin" > "$OUT/update-response-meta.txt"
file "$OUT/update-download.bin" | tee "$OUT/update-file-type.txt"
ls -lh "$OUT/update-download.bin" | tee "$OUT/update-size.txt"

if ! unzip -t "$OUT/update-download.bin" >/dev/null 2>&1; then
  python3 - "$OUT/update-download.bin" > "$OUT/discovered-url.txt" <<'PY' || true
import re, sys, html
raw=open(sys.argv[1],'rb').read(2_000_000).decode('utf-8','ignore')
raw=html.unescape(raw).replace('\\/','/')
patterns=[r'https?://[^\"\'<>\s]+?\.apk(?:\?[^\"\'<>\s]*)?',r'https?://[^\"\'<>\s]+?/download[^\"\'<>\s]*',r'(?:href|src)=[\"\']([^\"\']+)[\"\']']
for pat in patterns:
    for m in re.finditer(pat, raw, re.I):
        u=m.group(1) if m.lastindex else m.group(0)
        if u.startswith('//'): u='https:'+u
        if u.startswith('/'): u='https://gaeg.xvmobdes.com'+u
        if u.startswith('http') and u != 'https://gaeg.xvmobdes.com/download':
            print(u); raise SystemExit(0)
raise SystemExit(1)
PY
  DISCOVERED=$(head -1 "$OUT/discovered-url.txt" 2>/dev/null || true)
  if [[ -n "$DISCOVERED" ]]; then
    echo "following_discovered_url=$DISCOVERED" | tee -a "$OUT/actions.txt"
    curl -fL --retry 5 --retry-all-errors --connect-timeout 20 --max-time 180 \
      -A 'Mozilla/5.0 (Linux; Android 16; Pixel 6)' -e "$UPDATE_URL" "$DISCOVERED" -o "$OUT/update-download.bin"
  fi
fi

unzip -t "$OUT/update-download.bin" >/dev/null 2>&1 || {
  echo 'UPDATE_ENDPOINT_DID_NOT_RETURN_APK' >&2
  head -c 4096 "$OUT/update-download.bin" > "$OUT/update-download-prefix.bin" || true
  exit 61
}
mv "$OUT/update-download.bin" "$OUT/Xuper-6.5.5-Downloaded.apk"

$AAPT dump badging "$OUT/Xuper-6.5.5-Downloaded.apk" | tee "$OUT/downloaded-badging.txt"
grep -q "package: name='$PKG' versionCode='$TARGET_CODE' versionName='$TARGET_NAME'" "$OUT/downloaded-badging.txt" || { echo 'DOWNLOADED_APK_IS_NOT_XUPER_655' >&2; exit 62; }
$APKSIGNER verify --verbose --print-certs "$OUT/Xuper-6.5.5-Downloaded.apk" | tee "$OUT/downloaded-signing.txt"
DOWNLOADED_CERT=$($APKSIGNER verify --print-certs "$OUT/Xuper-6.5.5-Downloaded.apk" 2>/dev/null | sed -n 's/.*certificate SHA-256 digest: //p' | head -1 | tr -d ':[:space:]' | tr '[:upper:]' '[:lower:]')
echo "downloaded_cert=$DOWNLOADED_CERT" | tee "$OUT/downloaded-cert.txt"
[[ "$DOWNLOADED_CERT" == "$EXPECTED_CERT" ]] || { echo "DOWNLOADED_SIGNER_MISMATCH expected=$EXPECTED_CERT got=$DOWNLOADED_CERT" >&2; exit 63; }
sha256sum "$OUT/Xuper-6.5.5-Downloaded.apk" | tee "$OUT/downloaded-sha256.txt"

run_timeout 90s adb install -r -g "$OUT/Xuper-6.5.5-Downloaded.apk" | tee "$OUT/install-655.txt"
FINAL_CODE=$(version_code || true); FINAL_NAME=$(version_name || true)
echo "installed_code=$FINAL_CODE installed_name=$FINAL_NAME" | tee "$OUT/final.txt"
[[ "$FINAL_CODE" == "$TARGET_CODE" && "$FINAL_NAME" == "$TARGET_NAME" ]] || { echo 'ANDROID_UPDATE_DID_NOT_REACH_655' >&2; exit 64; }

adb emu geo fix -99.1332 19.4326 >/dev/null 2>&1 || true
launch_app
sleep 20
PID20=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true)
dump_ui final20
sleep 40
PID60=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true)
dump_ui final60
echo "pid20=${PID20:-DEAD} pid60=${PID60:-DEAD}" | tee -a "$OUT/final.txt"
[[ -n "$PID20" && -n "$PID60" ]] || { echo 'FINAL_RUNTIME_FAIL' >&2; exit 65; }
if is_update_gate "$OUT/ui-final20.xml" || is_update_gate "$OUT/ui-final60.xml"; then echo 'FINAL_UPDATE_GATE_STILL_PRESENT' >&2; exit 66; fi

APK_PATH=$(adb shell pm path "$PKG" | sed -n 's/^package://p' | head -1 | tr -d '\r')
run_timeout 30s adb pull "$APK_PATH" "$OUT/Xuper-6.5.5-Final-Tested.apk" >/dev/null
FINAL_CERT=$($APKSIGNER verify --print-certs "$OUT/Xuper-6.5.5-Final-Tested.apk" 2>/dev/null | sed -n 's/.*certificate SHA-256 digest: //p' | head -1 | tr -d ':[:space:]' | tr '[:upper:]' '[:lower:]')
echo "final_cert=$FINAL_CERT" | tee -a "$OUT/final.txt"
[[ "$FINAL_CERT" == "$EXPECTED_CERT" ]] || { echo 'FINAL_SIGNER_MISMATCH' >&2; exit 67; }
sha256sum "$OUT/Xuper-6.5.5-Final-Tested.apk" | tee "$OUT/final-sha256.txt"
adb logcat -d -v threadtime | grep -Ei 'com\.msandroid\.mobile|FATAL EXCEPTION|AndroidRuntime|SIGKILL|EXIT_SELF|UnsatisfiedLinkError' | tail -1200 > "$OUT/logcat-final.txt" || true

echo 'XUPER_655_OFFICIAL_UPDATE_RUNTIME_NO_UPDATE_GATE_OK'
