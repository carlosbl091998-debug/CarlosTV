#!/usr/bin/env bash
set -euo pipefail

PKG='com.msandroid.mobile'
OUT='diagnostics-magis-5136-close'
mkdir -p "$OUT"

run_timeout() { local secs="$1"; shift; timeout "$secs" "$@"; }

dump_ui() {
  local tag="$1" remote="/sdcard/ui-${1}.xml"
  run_timeout 10s adb shell uiautomator dump "$remote" >/dev/null 2>&1 || true
  run_timeout 10s adb pull "$remote" "$OUT/ui-${tag}.xml" >/dev/null 2>&1 || true
  run_timeout 10s adb exec-out screencap -p > "$OUT/screen-${tag}.png" || true
  adb shell pidof "$PKG" > "$OUT/pid-${tag}.txt" 2>/dev/null || true
  adb shell dumpsys activity activities | grep -E 'mResumedActivity|topResumedActivity|ResumedActivity' | head -8 > "$OUT/focus-${tag}.txt" || true
}

node_center_by_resid() {
  local xml="$1" resid="$2"
  python3 - "$xml" "$resid" <<'PY'
import re,sys,xml.etree.ElementTree as ET
path,resid=sys.argv[1:]
try: root=ET.parse(path).getroot()
except Exception: raise SystemExit(1)
for n in root.iter('node'):
    if n.attrib.get('resource-id','') != resid: continue
    m=re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', n.attrib.get('bounds',''))
    if not m: continue
    x1,y1,x2,y2=map(int,m.groups()); print((x1+x2)//2,(y1+y2)//2); raise SystemExit(0)
raise SystemExit(1)
PY
}

has_text() {
  local xml="$1" pat="$2"
  grep -Eqi "$pat" "$xml" 2>/dev/null
}

echo '=== install original signed Magis 5.13.6 ===' | tee "$OUT/actions.txt"
run_timeout 45s adb install -r -g magis-5136.apk | tee "$OUT/install.txt"
for perm in android.permission.POST_NOTIFICATIONS android.permission.READ_MEDIA_AUDIO android.permission.READ_MEDIA_IMAGES android.permission.CAMERA; do
  adb shell pm grant "$PKG" "$perm" >/dev/null 2>&1 || true
done

adb shell am force-stop "$PKG" || true
run_timeout 20s adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
sleep 15
dump_ui before_close

PID=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true)
echo "pid_before=${PID:-DEAD}" | tee -a "$OUT/result.txt"
[[ -n "$PID" ]] || { echo 'MAGIS_DIED_BEFORE_DIALOG_TEST' >&2; exit 30; }

XML="$OUT/ui-before_close.xml"
if ! grep -q 'com.msandroid.mobile:id/ivClose' "$XML"; then
  echo 'ivClose_not_found' | tee -a "$OUT/result.txt"
  exit 31
fi
if ! has_text "$XML" 'Version Upgrade|Upgrade'; then
  echo 'upgrade_dialog_text_not_found' | tee -a "$OUT/result.txt"
  exit 32
fi

XY=$(node_center_by_resid "$XML" 'com.msandroid.mobile:id/ivClose')
echo "tap ivClose at $XY" | tee -a "$OUT/actions.txt"
adb shell input tap $XY
sleep 7
dump_ui after_close

AFTER="$OUT/ui-after_close.xml"
if grep -q 'com.msandroid.mobile:id/ivClose' "$AFTER" && has_text "$AFTER" 'Version Upgrade'; then
  echo 'update_dialog_still_visible=1' | tee -a "$OUT/result.txt"
  exit 33
fi
echo 'update_dialog_still_visible=0' | tee -a "$OUT/result.txt"

PID2=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true)
echo "pid_after_close=${PID2:-DEAD}" | tee -a "$OUT/result.txt"
[[ -n "$PID2" ]] || { echo 'MAGIS_DIED_AFTER_NORMAL_CLOSE' >&2; exit 34; }

# Record exposed UI and try only ordinary navigation: account/profile tab if it exists.
python3 - "$AFTER" > "$OUT/visible-after-close.txt" <<'PY'
import sys,xml.etree.ElementTree as ET
try: root=ET.parse(sys.argv[1]).getroot()
except Exception: raise SystemExit(0)
for n in root.iter('node'):
    t=(n.attrib.get('text','') or '').strip(); d=(n.attrib.get('content-desc','') or '').strip(); rid=n.attrib.get('resource-id','')
    if t or d or n.attrib.get('clickable')=='true': print(f"text={t!r} desc={d!r} id={rid!r} clickable={n.attrib.get('clickable')} bounds={n.attrib.get('bounds')}")
PY

# Search likely account/profile nodes by id/text and click one only if normal visible node exists.
PROFILE_XY=$(python3 - "$AFTER" <<'PY'
import re,sys,xml.etree.ElementTree as ET
try: root=ET.parse(sys.argv[1]).getroot()
except Exception: raise SystemExit(0)
terms=('mine','profile','account','me','user','login')
for n in root.iter('node'):
    blob=' '.join([n.attrib.get('resource-id',''),n.attrib.get('text',''),n.attrib.get('content-desc','')]).lower()
    if n.attrib.get('clickable')!='true' or not any(t in blob for t in terms): continue
    m=re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]',n.attrib.get('bounds',''))
    if m:
        x1,y1,x2,y2=map(int,m.groups()); print((x1+x2)//2,(y1+y2)//2); break
PY
)
if [[ -n "$PROFILE_XY" ]]; then
  echo "tap normal profile/account node at $PROFILE_XY" | tee -a "$OUT/actions.txt"
  adb shell input tap $PROFILE_XY
  sleep 7
  dump_ui profile
fi

sleep 30
dump_ui final
PID3=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true)
echo "pid_final=${PID3:-DEAD}" | tee -a "$OUT/result.txt"
[[ -n "$PID3" ]] || { echo 'MAGIS_RUNTIME_FAIL_AFTER_CLOSE' >&2; exit 35; }

# Ensure app was not silently replaced/updated.
VC=$(adb shell dumpsys package "$PKG" | sed -n 's/.*versionCode=\([0-9]*\).*/\1/p' | head -1 | tr -d '\r')
VN=$(adb shell dumpsys package "$PKG" | sed -n 's/.*versionName=\(.*\)/\1/p' | head -1 | tr -d '\r')
echo "final_version_code=$VC final_version_name=$VN" | tee -a "$OUT/result.txt"
[[ "$VC" == '51306' ]] || { echo 'MAGIS_WAS_UPDATED_UNEXPECTEDLY' >&2; exit 36; }

adb logcat -d -v threadtime | grep -Ei 'com\.msandroid\.mobile|FATAL EXCEPTION|AndroidRuntime|SIGKILL|EXIT_SELF' | tail -1200 > "$OUT/logcat-final.txt" || true
echo 'MAGIS_5136_NORMAL_UPDATE_CLOSE_OK' | tee -a "$OUT/result.txt"
