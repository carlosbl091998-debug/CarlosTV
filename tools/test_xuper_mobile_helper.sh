#!/usr/bin/env bash
set -euxo pipefail

XUPER='com.android.mgstv'
HELPER='com.carlostv.mobilehelper'
SERVICE='com.carlostv.mobilehelper/com.carlostv.mobilehelper.RemoteAccessibilityService'
OUT='helper-diagnostics'
mkdir -p "$OUT"

adb install -r base.apk
adb install -r Xuper-Mobile-Helper.apk

# Enable the helper accessibility service for automated testing.
adb shell settings put secure enabled_accessibility_services "$SERVICE"
adb shell settings put secure accessibility_enabled 1
sleep 4
adb shell dumpsys accessibility > "$OUT/accessibility.txt"
grep -q 'com.carlostv.mobilehelper' "$OUT/accessibility.txt"

# Avoid first-run immersive-mode tutorials covering the UI.
adb shell settings put secure immersive_mode_confirmations confirmed >/dev/null 2>&1 || true

# Grant every Xuper runtime permission that Android allows us to grant.
adb shell dumpsys package "$XUPER" > "$OUT/xuper-package.txt"
awk '/requested permissions:/{f=1;next}/install permissions:/{f=0}f && /android\.permission\./{gsub(":",""); print $1}' "$OUT/xuper-package.txt" \
  | sort -u > "$OUT/xuper-permissions.txt" || true
while IFS= read -r p; do
  if [ -n "$p" ]; then
    adb shell pm grant "$XUPER" "$p" >/dev/null 2>&1 || true
  fi
done < "$OUT/xuper-permissions.txt"

dismiss_android_dialogs() {
  local i xy
  for i in 1 2 3 4 5 6; do
    adb shell uiautomator dump /sdcard/dialog.xml >/dev/null 2>&1 || true
    adb pull /sdcard/dialog.xml /tmp/dialog.xml >/dev/null 2>&1 || true
    xy=$(python3 - <<'PY'
import re, xml.etree.ElementTree as ET
try:
    root = ET.parse('/tmp/dialog.xml').getroot()
except Exception:
    raise SystemExit
wanted = {
    'allow','while using the app','only this time','ok','got it','continue',
    'permitir','mientras se usa la app','solo esta vez','aceptar','entendido','continuar'
}
for n in root.iter('node'):
    text = (n.attrib.get('text') or '').strip().lower()
    if text in wanted:
        m = re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', n.attrib.get('bounds',''))
        if m:
            x1,y1,x2,y2 = map(int,m.groups())
            print((x1+x2)//2, (y1+y2)//2)
            break
PY
)
    [ -z "${xy:-}" ] && break
    adb shell input tap $xy >/dev/null 2>&1 || true
    sleep 1
  done
}

# Launch the original, untouched Xuper.
adb shell am force-stop "$XUPER" || true
adb shell am start -W -n "$XUPER/com.interactive.brasiliptv.ui.activity.WelcomeActivity" > "$OUT/xuper-start.txt" 2>&1 || true
sleep 7
dismiss_android_dialogs
sleep 6

xpid=$(adb shell pidof "$XUPER" 2>/dev/null | tr -d '\r' || true)
hpid=$(adb shell pidof "$HELPER" 2>/dev/null | tr -d '\r' || true)
printf 'xuper_pid=%s helper_pid=%s\n' "${xpid:-DEAD}" "${hpid:-DEAD}" | tee "$OUT/results.txt"
test -n "$xpid"
test -n "$hpid"

# Capture the combined UI and WindowManager state.
adb shell uiautomator dump /sdcard/all.xml >/dev/null 2>&1 || true
adb pull /sdcard/all.xml "$OUT/ui-before.xml" >/dev/null 2>&1 || true
adb shell dumpsys window windows > "$OUT/windows-before.txt" || true
adb shell dumpsys accessibility > "$OUT/accessibility-after-launch.txt" || true
adb exec-out screencap -p > "$OUT/helper-visible.png" || true

# Verify that the accessibility overlay is really present. UIAutomator normally
# exposes its buttons; WindowManager is the fallback proof of the overlay window.
overlay_ui=0
if grep -q 'Mover derecha\|Aceptar\|Control táctil Xuper' "$OUT/ui-before.xml" 2>/dev/null; then
  overlay_ui=1
fi
if [ "$overlay_ui" -eq 0 ]; then
  grep -q 'com.carlostv.mobilehelper' "$OUT/windows-before.txt"
fi

# Locate two real controls in the accessibility overlay and tap them. If
# UIAutomator cannot see TYPE_ACCESSIBILITY_OVERLAY, use the known bottom-right
# D-pad geometry as a fallback and still exercise the overlay through touch.
python3 - <<'PY' > /tmp/taps.txt
import re, xml.etree.ElementTree as ET
try:
    root = ET.parse('helper-diagnostics/ui-before.xml').getroot()
except Exception:
    root = None
if root is not None:
    for wanted in ('Mover derecha','Aceptar'):
        for n in root.iter('node'):
            if (n.attrib.get('content-desc') or '') == wanted:
                m = re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', n.attrib.get('bounds',''))
                if m:
                    x1,y1,x2,y2 = map(int,m.groups())
                    print((x1+x2)//2, (y1+y2)//2)
                    break
PY

tap_count=0
while read -r x y; do
  if [ -n "${x:-}" ] && [ -n "${y:-}" ]; then
    adb shell input tap "$x" "$y"
    tap_count=$((tap_count+1))
    sleep 1
  fi
done < /tmp/taps.txt

if [ "$tap_count" -lt 2 ]; then
  # Pixel 6 test display is 1080x2400 at 420 dpi. Xuper rotates the display to
  # landscape; compute overlay coordinates from the current physical size so
  # the fallback remains valid if the emulator reports the rotation differently.
  read -r sw sh < <(adb shell wm size | sed -n 's/.*: \([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tail -1)
  density=$(adb shell wm density | sed -n 's/.*: \([0-9]*\).*/\1/p' | tail -1)
  density=${density:-420}
  # dp to px and bottom-right overlay origin. The D-pad starts 36dp below the top.
  python3 - "$sw" "$sh" "$density" > /tmp/fallback_taps.txt <<'PY'
import sys
w,h,d=map(int,sys.argv[1:])
scale=d/160.0
ow=int(round(186*scale)); oh=int(round(204*scale))
margin_x=int(round(8*scale)); margin_y=int(round(20*scale))
left=w-margin_x-ow; top=h-margin_y-oh
# D-pad cell centers: RIGHT is col2,row1; OK is col1,row1.
x_right=left+int(round((6+58*2+29)*scale))
x_ok=left+int(round((6+58+29)*scale))
y_mid=top+int(round((6+36+52+26)*scale))
print(x_right,y_mid)
print(x_ok,y_mid)
PY
  while read -r x y; do
    adb shell input tap "$x" "$y" || true
    sleep 1
  done < /tmp/fallback_taps.txt
fi

sleep 3
xpid2=$(adb shell pidof "$XUPER" 2>/dev/null | tr -d '\r' || true)
hpid2=$(adb shell pidof "$HELPER" 2>/dev/null | tr -d '\r' || true)
printf 'after_buttons xuper_pid=%s helper_pid=%s\n' "${xpid2:-DEAD}" "${hpid2:-DEAD}" | tee -a "$OUT/results.txt"
test -n "$xpid2"
test -n "$hpid2"

adb shell uiautomator dump /sdcard/after.xml >/dev/null 2>&1 || true
adb pull /sdcard/after.xml "$OUT/ui-after.xml" >/dev/null 2>&1 || true
adb shell dumpsys window windows > "$OUT/windows-after.txt" || true
adb exec-out screencap -p > "$OUT/helper-after-buttons.png" || true

echo 'HELPER_RUNTIME_TEST_OK' | tee -a "$OUT/results.txt"
