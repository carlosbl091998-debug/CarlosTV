#!/usr/bin/env bash
set -euo pipefail
PKG='com.msandroid.mobile'; OUT='diagnostics-magis-5136-force-dismiss'; mkdir -p "$OUT"
rt(){ local s="$1"; shift; timeout "$s" "$@"; }
dump(){ local t="$1" r="/sdcard/${t}.xml"; rt 10s adb shell uiautomator dump "$r" >/dev/null 2>&1||true; rt 10s adb pull "$r" "$OUT/ui-${t}.xml" >/dev/null 2>&1||true; rt 10s adb exec-out screencap -p >"$OUT/screen-${t}.png"||true; }
center(){ python3 - "$1" "$2" <<'PY'
import re,sys,xml.etree.ElementTree as E
p,r=sys.argv[1:]
try:q=E.parse(p).getroot()
except:raise SystemExit(1)
for n in q.iter('node'):
 if n.attrib.get('resource-id')==r:
  m=re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]',n.attrib.get('bounds',''))
  if m:
   a,b,c,d=map(int,m.groups());print((a+c)//2,(b+d)//2);raise SystemExit
raise SystemExit(1)
PY
}
contains(){ grep -Eqi "$2" "$1" 2>/dev/null; }

rt 45s adb install -r -g magis-5136.apk >"$OUT/install.txt"
for p in android.permission.POST_NOTIFICATIONS android.permission.READ_MEDIA_AUDIO android.permission.READ_MEDIA_IMAGES android.permission.CAMERA; do adb shell pm grant "$PKG" "$p" >/dev/null 2>&1||true; done
adb shell am force-stop "$PKG"||true; rt 20s adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1||true
sleep 15; dump initial
X="$OUT/ui-initial.xml"; xy=$(center "$X" 'com.msandroid.mobile:id/ivClose'); echo "close_optional=$xy"|tee "$OUT/result.txt"; adb shell input tap $xy; sleep 6; dump force
F="$OUT/ui-force.xml"; contains "$F" 'This version has been discontinued' || { echo 'force_gate_not_seen'|tee -a "$OUT/result.txt"; exit 40; }
echo 'force_gate_seen=1'|tee -a "$OUT/result.txt"

# Normal Android Back
adb shell input keyevent 4; sleep 5; dump after_back
if contains "$OUT/ui-after_back.xml" 'This version has been discontinued'; then echo 'back_dismissed=0'|tee -a "$OUT/result.txt"; else echo 'back_dismissed=1'|tee -a "$OUT/result.txt"; fi

# If still visible, tap well outside dialog in normal app area.
if contains "$OUT/ui-after_back.xml" 'This version has been discontinued'; then adb shell input tap 50 400; sleep 5; dump after_outside; else cp "$OUT/ui-after_back.xml" "$OUT/ui-after_outside.xml"; fi
if contains "$OUT/ui-after_outside.xml" 'This version has been discontinued'; then echo 'outside_dismissed=0'|tee -a "$OUT/result.txt"; else echo 'outside_dismissed=1'|tee -a "$OUT/result.txt"; fi

# Restart app to see whether gate is persistently returned.
adb shell am force-stop "$PKG"||true; rt 20s adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1||true; sleep 15; dump restart
if contains "$OUT/ui-restart.xml" 'Version Upgrade|This version has been discontinued'; then echo 'gate_returns_on_restart=1'|tee -a "$OUT/result.txt"; else echo 'gate_returns_on_restart=0'|tee -a "$OUT/result.txt"; fi
PID=$(adb shell pidof "$PKG" 2>/dev/null|tr -d '\r'||true); echo "pid=${PID:-DEAD}"|tee -a "$OUT/result.txt"; [[ -n "$PID" ]]
VC=$(adb shell dumpsys package "$PKG"|sed -n 's/.*versionCode=\([0-9]*\).*/\1/p'|head -1|tr -d '\r'); echo "versionCode=$VC"|tee -a "$OUT/result.txt"; [[ "$VC" == 51306 ]]
echo 'MAGIS_5136_FORCE_DIALOG_NORMAL_PATHS_TESTED'|tee -a "$OUT/result.txt"
