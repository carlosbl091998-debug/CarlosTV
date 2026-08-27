#!/usr/bin/env bash
set -euo pipefail

PKG='com.msandroid.mobile'
APK='xuper-655-candidate.apk'
OUT='diagnostics-655-direct'
mkdir -p "$OUT"

run_timeout() { local secs="$1"; shift; timeout "$secs" "$@"; }
version_code() { adb shell dumpsys package "$PKG" 2>/dev/null | sed -n 's/.*versionCode=\([0-9]*\).*/\1/p' | head -1 | tr -d '\r'; }
version_name() { adb shell dumpsys package "$PKG" 2>/dev/null | sed -n 's/.*versionName=\(.*\)/\1/p' | head -1 | tr -d '\r'; }

dump_ui() {
  local tag="$1" remote="/sdcard/ui-${1}.xml"
  run_timeout 10s adb shell uiautomator dump "$remote" >/dev/null 2>&1 || true
  run_timeout 10s adb pull "$remote" "$OUT/ui-${tag}.xml" >/dev/null 2>&1 || true
  run_timeout 10s adb exec-out screencap -p > "$OUT/screen-${tag}.png" || true
}

ui_has_update_gate() {
  local xml="$1"
  python3 - "$xml" <<'PY'
import sys, xml.etree.ElementTree as ET
try:
    root=ET.parse(sys.argv[1]).getroot()
except Exception:
    raise SystemExit(1)
text='\n'.join((n.attrib.get('text','')+' '+n.attrib.get('content-desc','')) for n in root.iter('node')).casefold()
needles=['actualización de versión','version upgrade','v6.5.5','actualizar',' update ']
for n in needles:
    if n in (' update ',):
        if n in (' '+text+' '): raise SystemExit(0)
    elif n in text:
        raise SystemExit(0)
raise SystemExit(1)
PY
}

echo '=== install direct signed 6.5.5 candidate ===' | tee "$OUT/actions.txt"
run_timeout 45s adb install -r -g "$APK" | tee "$OUT/install.txt"
adb emu geo fix -99.1332 19.4326 >/dev/null 2>&1 || true
adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
run_timeout 20s adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true

sleep 20
CODE20=$(version_code || true); NAME20=$(version_name || true); PID20=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true)
dump_ui t20
sleep 40
CODE60=$(version_code || true); NAME60=$(version_name || true); PID60=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true)
dump_ui t60

echo "code20=$CODE20 name20=$NAME20 pid20=${PID20:-DEAD}" | tee -a "$OUT/result.txt"
echo "code60=$CODE60 name60=$NAME60 pid60=${PID60:-DEAD}" | tee -a "$OUT/result.txt"

[[ "$CODE20" == '60505' || "$NAME20" == '6.5.5' ]] || { echo 'WRONG_VERSION_AT_20S' >&2; exit 60; }
[[ "$CODE60" == '60505' || "$NAME60" == '6.5.5' ]] || { echo 'WRONG_VERSION_AT_60S' >&2; exit 61; }
[[ -n "$PID20" && -n "$PID60" ]] || { echo 'PROCESS_DIED' >&2; exit 62; }

if ui_has_update_gate "$OUT/ui-t20.xml" || ui_has_update_gate "$OUT/ui-t60.xml"; then
  echo 'UPDATE_GATE_PRESENT' >&2
  exit 63
fi

adb logcat -d -v threadtime | grep -Ei 'com\.msandroid\.mobile|FATAL EXCEPTION|AndroidRuntime|SIGKILL|EXIT_SELF|UnsatisfiedLinkError' | tail -1200 > "$OUT/logcat.txt" || true
if grep -Eqi 'FATAL EXCEPTION|UnsatisfiedLinkError|EXIT_SELF' "$OUT/logcat.txt"; then
  echo 'FATAL_LOG_DETECTED' >&2
  exit 64
fi

APK_PATH=$(adb shell pm path "$PKG" | sed -n 's/^package://p' | head -1 | tr -d '\r')
run_timeout 30s adb pull "$APK_PATH" "$OUT/Xuper-6.5.5-Final-Tested.apk" >/dev/null
sha256sum "$OUT/Xuper-6.5.5-Final-Tested.apk" | tee "$OUT/final-sha256.txt"
echo 'XUPER_655_DIRECT_ANDROID16_NO_UPDATE_GATE_OK' | tee -a "$OUT/result.txt"
