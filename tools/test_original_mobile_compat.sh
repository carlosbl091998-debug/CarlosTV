#!/usr/bin/env bash
set -u

PKG='com.android.mgstv'
ACT='com.interactive.brasiliptv.ui.activity.WelcomeActivity'
mkdir -p diagnostics

adb install -r base.apk

# Do not let Android's first-time immersive-mode tutorial cover Xuper.
adb shell settings put secure immersive_mode_confirmations confirmed >/dev/null 2>&1 || true

# Record and grant every requested runtime permission that can legally be granted.
adb shell dumpsys package "$PKG" > diagnostics/package-before.txt || true
awk '/requested permissions:/{f=1;next}/install permissions:/{f=0}f && /android\.permission\./{gsub(":",""); print $1}' diagnostics/package-before.txt | sort -u > diagnostics/requested-permissions.txt || true
while IFS= read -r p; do
  [ -n "$p" ] && adb shell pm grant "$PKG" "$p" >/dev/null 2>&1 || true
done < diagnostics/requested-permissions.txt

# Click only standard positive Android system-dialog buttons. This is used to
# expose the app UI in screenshots; it does not alter the APK.
dismiss_system_dialogs() {
  local i xy
  for i in 1 2 3 4 5 6 7 8; do
    adb shell uiautomator dump /sdcard/dialog.xml >/dev/null 2>&1 || true
    adb pull /sdcard/dialog.xml /tmp/dialog.xml >/dev/null 2>&1 || true
    xy=$(python3 - <<'PY'
import re, xml.etree.ElementTree as ET
try:
    root=ET.parse('/tmp/dialog.xml').getroot()
except Exception:
    raise SystemExit
wanted=(
    'allow','while using the app','only this time','ok','got it','continue',
    'permitir','mientras se usa la app','solo esta vez','aceptar','entendido','continuar'
)
for n in root.iter('node'):
    text=(n.attrib.get('text') or '').strip().lower()
    if text in wanted:
        m=re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]',n.attrib.get('bounds',''))
        if m:
            x1,y1,x2,y2=map(int,m.groups())
            print((x1+x2)//2,(y1+y2)//2)
            break
PY
)
    [ -z "$xy" ] && break
    adb shell input tap $xy >/dev/null 2>&1 || true
    sleep 1
  done
}

capture() {
  local name="$1"
  adb shell am force-stop "$PKG" || true
  adb shell am start -W -n "$PKG/$ACT" > "diagnostics/${name}-start.txt" 2>&1 || true
  sleep 5
  dismiss_system_dialogs
  sleep 6
  adb exec-out screencap -p > "diagnostics/${name}.png" || true
  adb shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1 || true
  adb pull /sdcard/window.xml "diagnostics/${name}-ui.xml" >/dev/null 2>&1 || true
  adb shell dumpsys activity activities | grep -E 'mResumedActivity|topResumedActivity' > "diagnostics/${name}-focus.txt" || true
  adb shell dumpsys display > "diagnostics/${name}-display.txt" || true
  local pid
  pid=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true)
  printf '%s pid=%s\n' "$name" "${pid:-DEAD}" | tee -a diagnostics/results.txt
}

# Baseline untouched APK.
adb shell am compat reset-all "$PKG" >/dev/null 2>&1 || true
adb shell settings put system accelerometer_rotation 0
adb shell settings put system user_rotation 1
capture baseline_landscape

# Android system resize override, APK remains untouched.
adb shell am compat enable FORCE_RESIZE_APP "$PKG" || true
capture force_resize_landscape

# Let user/device orientation override the TV app and test portrait.
adb shell am compat enable OVERRIDE_ANY_ORIENTATION_TO_USER "$PKG" || true
adb shell settings put system user_rotation 0
capture resize_user_portrait

# Try full portrait surface / aspect-ratio compatibility.
adb shell am compat enable OVERRIDE_MIN_ASPECT_RATIO "$PKG" || true
adb shell am compat enable OVERRIDE_MIN_ASPECT_RATIO_EXCLUDE_PORTRAIT_FULLSCREEN "$PKG" || true
capture resize_portrait_fullscreen

cat diagnostics/results.txt
