#!/usr/bin/env bash
set -euo pipefail

PKG='com.msandroid.mobile'
OUT='diagnostics-update'
TARGET_CODE='60505'
TARGET_NAME='6.5.5'
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

click_label() {
  local xml="$1" label="$2"
  python3 - "$xml" "$label" <<'PY' > /tmp/xy.txt || return 1
import re,sys,xml.etree.ElementTree as ET
root=ET.parse(sys.argv[1]).getroot(); needle=sys.argv[2].casefold()
for n in root.iter('node'):
    text=(n.attrib.get('text','')+' '+n.attrib.get('content-desc','')).strip().casefold()
    if needle not in text: continue
    m=re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]',n.attrib.get('bounds',''))
    if m:
        x1,y1,x2,y2=map(int,m.groups()); print((x1+x2)//2,(y1+y2)//2); raise SystemExit(0)
raise SystemExit(1)
PY
  read -r x y < /tmp/xy.txt
  echo "tap label=$label x=$x y=$y" | tee -a "$OUT/actions.txt"
  adb shell input tap "$x" "$y"
}

is_update_gate() {
  local xml="$1"
  xml_has "$xml" 'Actualización de versión' || \
  xml_has "$xml" 'Version Upgrade' || \
  xml_has "$xml" 'V6.5.5' || \
  xml_has "$xml" 'Actualizar'
}

handle_installer() {
  local before="$1" cycle="$2"
  for n in $(seq 1 30); do
    sleep 3
    dump_ui "c${cycle}-installer-${n}"
    local xml="$OUT/ui-c${cycle}-installer-${n}.xml"
    click_label "$xml" 'Update' 2>/dev/null || true
    click_label "$xml" 'Actualizar' 2>/dev/null || true
    click_label "$xml" 'Install' 2>/dev/null || true
    click_label "$xml" 'Instalar' 2>/dev/null || true
    click_label "$xml" 'Done' 2>/dev/null || true
    click_label "$xml" 'Listo' 2>/dev/null || true
    local now; now=$(version_code || true)
    if [[ -n "$now" && "$now" != "$before" ]]; then
      echo "cycle=$cycle version_changed $before->$now" | tee -a "$OUT/actions.txt"
      return 0
    fi
  done
  return 1
}

echo '=== install signed bootstrap ===' | tee "$OUT/actions.txt"
run_timeout 45s adb install -r -g magis-current.apk | tee "$OUT/install-bootstrap.txt"
adb shell appops set "$PKG" REQUEST_INSTALL_PACKAGES allow >/dev/null 2>&1 || true

APKSIGNER=$(find "$ANDROID_HOME/build-tools" -type f -name apksigner | sort -V | tail -1)
EXPECTED_CERT=$($APKSIGNER verify --print-certs magis-current.apk 2>/dev/null | sed -n 's/.*certificate SHA-256 digest: //p' | head -1 | tr -d ':[:space:]' | tr '[:upper:]' '[:lower:]')
echo "expected_cert=$EXPECTED_CERT" | tee "$OUT/expected-cert.txt"

# Give the emulator a Mexico GPS position. The app may still use IP geolocation,
# but this avoids failing any normal GPS-based regional check.
adb emu geo fix -99.1332 19.4326 >/dev/null 2>&1 || true

for cycle in 1 2 3 4 5 6; do
  launch_app
  sleep 15
  code=$(version_code || true); name=$(version_name || true)
  echo "cycle=$cycle code=$code name=$name" | tee -a "$OUT/versions.txt"
  dump_ui "c${cycle}-before"
  xml="$OUT/ui-c${cycle}-before.xml"

  if [[ "$code" == "$TARGET_CODE" || "$name" == "$TARGET_NAME" ]]; then
    echo "target_reached cycle=$cycle" | tee -a "$OUT/actions.txt"
    break
  fi

  if ! is_update_gate "$xml"; then
    echo "TARGET_NOT_REACHED_AND_NO_UPDATE_GATE code=$code name=$name" >&2
    exit 50
  fi

  before="$code"
  click_label "$xml" 'Actualizar' || click_label "$xml" 'Update' || {
    echo 'UPDATE_BUTTON_NOT_FOUND' >&2; exit 51;
  }
  handle_installer "$before" "$cycle" || { echo 'UPDATE_DID_NOT_INSTALL' >&2; exit 52; }
done

FINAL_CODE=$(version_code || true)
FINAL_NAME=$(version_name || true)
echo "final_code=$FINAL_CODE final_name=$FINAL_NAME" | tee "$OUT/final.txt"
[[ "$FINAL_CODE" == "$TARGET_CODE" || "$FINAL_NAME" == "$TARGET_NAME" ]] || {
  echo "WRONG_FINAL_VERSION expected=$TARGET_NAME/$TARGET_CODE got=$FINAL_NAME/$FINAL_CODE" >&2; exit 53;
}

launch_app
sleep 20
PID20=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true)
dump_ui final20
sleep 40
PID60=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true)
dump_ui final60
echo "pid20=${PID20:-DEAD} pid60=${PID60:-DEAD}" | tee -a "$OUT/final.txt"
[[ -n "$PID20" && -n "$PID60" ]] || { echo 'FINAL_RUNTIME_FAIL' >&2; exit 54; }

FINAL_XML="$OUT/ui-final60.xml"
if is_update_gate "$FINAL_XML"; then
  echo 'FINAL_UPDATE_GATE_STILL_PRESENT' >&2
  exit 55
fi

APK_PATH=$(adb shell pm path "$PKG" | sed -n 's/^package://p' | head -1 | tr -d '\r')
run_timeout 30s adb pull "$APK_PATH" "$OUT/Xuper-6.5.5-Final-Tested.apk" >/dev/null
FINAL_CERT=$($APKSIGNER verify --print-certs "$OUT/Xuper-6.5.5-Final-Tested.apk" 2>/dev/null | sed -n 's/.*certificate SHA-256 digest: //p' | head -1 | tr -d ':[:space:]' | tr '[:upper:]' '[:lower:]')
echo "final_cert=$FINAL_CERT" | tee -a "$OUT/final.txt"
[[ "$FINAL_CERT" == "$EXPECTED_CERT" ]] || { echo 'FINAL_SIGNER_MISMATCH' >&2; exit 56; }

adb logcat -d -v threadtime | grep -Ei 'com\.msandroid\.mobile|FATAL EXCEPTION|AndroidRuntime|SIGKILL|EXIT_SELF|UnsatisfiedLinkError' | tail -1200 > "$OUT/logcat-final.txt" || true
sha256sum "$OUT/Xuper-6.5.5-Final-Tested.apk" | tee "$OUT/final-sha256.txt"
echo 'XUPER_655_SIGNED_RUNTIME_NO_UPDATE_GATE_OK'
