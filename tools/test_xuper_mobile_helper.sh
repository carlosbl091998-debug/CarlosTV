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

# Capture the combined UI and WindowManager state. Screenshot comes first so
# its PNG dimensions give the real logical surface after Xuper rotates it.
adb exec-out screencap -p > "$OUT/helper-visible.png"
adb shell uiautomator dump /sdcard/all.xml >/dev/null 2>&1 || true
adb pull /sdcard/all.xml "$OUT/ui-before.xml" >/dev/null 2>&1 || true
adb shell dumpsys window windows > "$OUT/windows-before.txt" || true
adb shell dumpsys accessibility > "$OUT/accessibility-after-launch.txt" || true

# Require an actual accessibility overlay owned by our helper.
grep -q 'com.carlostv.mobilehelper' "$OUT/windows-before.txt"
grep -q 'ACCESSIBILITY_OVERLAY' "$OUT/windows-before.txt"

# Get the logical screenshot size directly from PNG IHDR. This is critical:
# wm size can report the natural portrait dimensions while Xuper is rendered
# on a 2400x1080 logical landscape surface.
read -r logical_w logical_h < <(python3 - "$OUT/helper-visible.png" <<'PY'
import struct,sys
p=sys.argv[1]
with open(p,'rb') as f:
    sig=f.read(24)
if sig[:8] != b'\x89PNG\r\n\x1a\n':
    raise SystemExit('not a PNG screenshot')
w,h=struct.unpack('>II',sig[16:24])
print(w,h)
PY
)
printf 'logical_surface=%sx%s\n' "$logical_w" "$logical_h" | tee -a "$OUT/results.txt"

density=$(adb shell wm density | sed -n 's/.*: \([0-9]*\).*/\1/p' | tail -1)
density=${density:-420}

# Compact helper geometry from RemoteAccessibilityService:
# overlay 150x184dp; margins 6dp right / 12dp bottom; padding 6dp;
# top row 34dp; D-pad cells 46dp.
python3 - "$logical_w" "$logical_h" "$density" > /tmp/remote_taps.txt <<'PY'
import sys
w,h,d=map(int,sys.argv[1:])
s=d/160.0
def px(dp): return int(round(dp*s))
ow,oh=px(150),px(184)
left=w-px(6)-ow
top=h-px(12)-oh
# cell center y = padding 6 + top row 34 + second D-pad row start 46 + half cell 23
ymid=top+px(6+34+46+23)
# RIGHT = padding 6 + two cells + half cell
xright=left+px(6+46*2+23)
# OK = padding 6 + one cell + half cell
xok=left+px(6+46+23)
print(xright,ymid,'RIGHT')
print(xok,ymid,'OK')
PY
cat /tmp/remote_taps.txt | tee "$OUT/remote-tap-coordinates.txt"

# Clear logcat and tap the ACTUAL overlay buttons. The helper itself logs every
# button press, so the test cannot pass merely because both processes survived.
adb logcat -c
while read -r x y label; do
  adb shell input tap "$x" "$y"
  sleep 1
  echo "tapped=$label x=$x y=$y" | tee -a "$OUT/results.txt"
done < /tmp/remote_taps.txt
sleep 3
adb logcat -d -v brief | grep 'XuperMobileHelper' > "$OUT/remote-log.txt" || true
cat "$OUT/remote-log.txt" || true
grep -q 'PRESS:Mover derecha' "$OUT/remote-log.txt"
grep -q 'PRESS:Aceptar' "$OUT/remote-log.txt"

# Both apps must remain alive after real overlay interaction.
xpid2=$(adb shell pidof "$XUPER" 2>/dev/null | tr -d '\r' || true)
hpid2=$(adb shell pidof "$HELPER" 2>/dev/null | tr -d '\r' || true)
printf 'after_buttons xuper_pid=%s helper_pid=%s\n' "${xpid2:-DEAD}" "${hpid2:-DEAD}" | tee -a "$OUT/results.txt"
test -n "$xpid2"
test -n "$hpid2"

# Capture visual and WindowManager evidence immediately after interaction.
adb exec-out screencap -p > "$OUT/helper-after-buttons.png"
adb shell dumpsys window windows > "$OUT/windows-after.txt" || true
grep -q 'com.carlostv.mobilehelper' "$OUT/windows-after.txt"
grep -q 'ACCESSIBILITY_OVERLAY' "$OUT/windows-after.txt"
adb shell uiautomator dump /sdcard/after.xml >/dev/null 2>&1 || true
adb pull /sdcard/after.xml "$OUT/ui-after.xml" >/dev/null 2>&1 || true

echo 'HELPER_REAL_BUTTON_TEST_OK' | tee -a "$OUT/results.txt"
