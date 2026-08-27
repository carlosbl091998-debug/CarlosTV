#!/usr/bin/env bash
set -euo pipefail

PKG='com.msandroid.mobile'
OUT='diagnostics-magis-630'
mkdir -p "$OUT"

run_timeout() { local secs="$1"; shift; timeout "$secs" "$@"; }

version_code() { adb shell dumpsys package "$PKG" 2>/dev/null | sed -n 's/.*versionCode=\([0-9]*\).*/\1/p' | head -1 | tr -d '\r'; }
version_name() { adb shell dumpsys package "$PKG" 2>/dev/null | sed -n 's/.*versionName=\(.*\)/\1/p' | head -1 | tr -d '\r'; }

grant_common_permissions() {
  for perm in \
    android.permission.POST_NOTIFICATIONS \
    android.permission.READ_MEDIA_AUDIO \
    android.permission.READ_MEDIA_IMAGES \
    android.permission.CAMERA \
    android.permission.RECORD_AUDIO; do
    adb shell pm grant "$PKG" "$perm" >/dev/null 2>&1 || true
  done
}

launch_app() {
  adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
  run_timeout 20s adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
}

dump_ui() {
  local tag="$1" remote="/sdcard/ui-${1}.xml"
  run_timeout 10s adb shell uiautomator dump "$remote" >/dev/null 2>&1 || true
  run_timeout 10s adb pull "$remote" "$OUT/ui-${tag}.xml" >/dev/null 2>&1 || true
  run_timeout 10s adb exec-out screencap -p > "$OUT/screen-${tag}.png" || true
  adb shell dumpsys activity activities | grep -E 'mResumedActivity|topResumedActivity|ResumedActivity' | head -8 > "$OUT/focus-${tag}.txt" || true
  adb shell pidof "$PKG" > "$OUT/pid-${tag}.txt" 2>/dev/null || true
}

xml_text() {
  local xml="$1"
  python3 - "$xml" <<'PY'
import sys, xml.etree.ElementTree as ET
try: root=ET.parse(sys.argv[1]).getroot()
except Exception: raise SystemExit(1)
for n in root.iter('node'):
    t=(n.attrib.get('text','') or '').strip()
    d=(n.attrib.get('content-desc','') or '').strip()
    if t or d: print((t+' '+d).strip())
PY
}

xml_contains() {
  local xml="$1" needle="$2"
  xml_text "$xml" 2>/dev/null | tr '[:upper:]' '[:lower:]' | grep -Fq "$(printf '%s' "$needle" | tr '[:upper:]' '[:lower:]')"
}

find_text_center() {
  local xml="$1" text="$2"
  python3 - "$xml" "$text" <<'PY'
import re, sys, xml.etree.ElementTree as ET
path, needle=sys.argv[1:]
try: root=ET.parse(path).getroot()
except Exception: raise SystemExit(1)
n=needle.casefold()
for x in root.iter('node'):
    vals=[x.attrib.get('text',''), x.attrib.get('content-desc','')]
    if not any((v or '').strip().casefold()==n for v in vals): continue
    m=re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', x.attrib.get('bounds',''))
    if not m: continue
    x1,y1,x2,y2=map(int,m.groups())
    print((x1+x2)//2,(y1+y2)//2)
    raise SystemExit(0)
raise SystemExit(1)
PY
}

click_text() {
  local xml="$1" label="$2" xy
  xy=$(find_text_center "$xml" "$label" 2>/dev/null || true)
  [[ -n "$xy" ]] || return 1
  echo "tap [$label] at $xy" | tee -a "$OUT/actions.txt"
  adb shell input tap $xy
  return 0
}

echo '=== Install exact Magis 6.3.0 ===' | tee "$OUT/actions.txt"
run_timeout 45s adb install -r -g magis-630.apk | tee "$OUT/install.txt"
grant_common_permissions

echo "installed_code=$(version_code) installed_name=$(version_name)" | tee "$OUT/version.txt"
launch_app
sleep 15
dump_ui initial15
XML="$OUT/ui-initial15.xml"
xml_text "$XML" > "$OUT/text-initial15.txt" 2>/dev/null || true

PID15=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true)
echo "pid15=${PID15:-DEAD}" | tee -a "$OUT/result.txt"
[[ -n "$PID15" ]] || { echo 'MAGIS_630_CRASHED_INITIAL' >&2; exit 20; }

UPDATE_GATE=0
if xml_contains "$XML" 'Version Upgrade' || xml_contains "$XML" 'update' || xml_contains "$XML" 'discontinued' || xml_contains "$XML" 'actualiza'; then
  UPDATE_GATE=1
  echo 'update_gate_visible=1' | tee -a "$OUT/result.txt"
fi

# Only try normal user-visible ways to dismiss an optional dialog. Never press Update.
if [[ "$UPDATE_GATE" == 1 ]]; then
  DISMISSED_BY_BUTTON=0
  for label in Cancel Later 'Not now' Close Skip Cancelar Después Cerrar Omitir; do
    if click_text "$XML" "$label"; then
      DISMISSED_BY_BUTTON=1
      sleep 5
      break
    fi
  done

  if [[ "$DISMISSED_BY_BUTTON" == 0 ]]; then
    echo 'no_cancel_button; trying Android Back' | tee -a "$OUT/actions.txt"
    adb shell input keyevent 4 || true
    sleep 5
  fi
fi

dump_ui after_dismiss
AFTER="$OUT/ui-after_dismiss.xml"
xml_text "$AFTER" > "$OUT/text-after_dismiss.txt" 2>/dev/null || true

PID_AFTER=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true)
echo "pid_after_dismiss=${PID_AFTER:-DEAD}" | tee -a "$OUT/result.txt"
[[ -n "$PID_AFTER" ]] || { echo 'MAGIS_630_DIED_AFTER_DISMISS' >&2; exit 21; }

GATE_REMAINS=0
if xml_contains "$AFTER" 'Version Upgrade' || xml_contains "$AFTER" 'discontinued'; then
  GATE_REMAINS=1
fi
echo "update_gate_after_dismiss=$GATE_REMAINS" | tee -a "$OUT/result.txt"

LOGIN_HINT=0
for needle in Login Password Username Usuario Contraseña Ingresar Email; do
  if xml_contains "$AFTER" "$needle"; then LOGIN_HINT=1; break; fi
done
echo "login_ui_visible=$LOGIN_HINT" | tee -a "$OUT/result.txt"

REGION_BLOCK=0
if xml_contains "$AFTER" 'copyright restrictions' || xml_contains "$AFTER" 'cannot login in this location'; then REGION_BLOCK=1; fi
echo "region_block_visible=$REGION_BLOCK" | tee -a "$OUT/result.txt"

sleep 30
dump_ui final45
FINAL="$OUT/ui-final45.xml"
xml_text "$FINAL" > "$OUT/text-final45.txt" 2>/dev/null || true
PID45=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true)
echo "pid45=${PID45:-DEAD}" | tee -a "$OUT/result.txt"
[[ -n "$PID45" ]] || { echo 'MAGIS_630_RUNTIME_FAIL' >&2; exit 22; }

adb logcat -d -v threadtime | grep -Ei 'com\.msandroid\.mobile|FATAL EXCEPTION|AndroidRuntime|SIGKILL|EXIT_SELF|UnsatisfiedLinkError' | tail -1200 > "$OUT/logcat-final.txt" || true

if [[ "$GATE_REMAINS" == 0 ]]; then
  echo 'MAGIS_630_OPTIONAL_UPDATE_DISMISSIBLE' | tee -a "$OUT/result.txt"
else
  echo 'MAGIS_630_UPDATE_GATE_NOT_DISMISSIBLE_NORMALLY' | tee -a "$OUT/result.txt"
fi
