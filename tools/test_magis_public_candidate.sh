#!/usr/bin/env bash
set -euo pipefail

APK="magis-public.apk"
PKG="com.msandroid.mobile"
OUT="magis-public-diagnostics"
mkdir -p "$OUT"

adb install -r "$APK" | tee "$OUT/install.txt"
adb shell dumpsys package "$PKG" > "$OUT/package.txt" || true

for p in android.permission.CAMERA android.permission.POST_NOTIFICATIONS android.permission.READ_MEDIA_IMAGES android.permission.READ_MEDIA_AUDIO android.permission.READ_EXTERNAL_STORAGE android.permission.WRITE_EXTERNAL_STORAGE android.permission.RECORD_AUDIO; do
  adb shell pm grant "$PKG" "$p" >/dev/null 2>&1 || true
done

capture() {
  local tag="$1"
  adb shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1 || true
  adb pull /sdcard/window.xml "$OUT/${tag}.xml" >/dev/null 2>&1 || true
  adb exec-out screencap -p > "$OUT/${tag}.png" || true
  adb shell pidof "$PKG" > "$OUT/${tag}.pid" 2>/dev/null || true
  adb shell dumpsys window windows | grep -E 'mCurrentFocus|mFocusedApp' > "$OUT/${tag}-focus.txt" 2>/dev/null || true
}

adb logcat -c
adb shell am force-stop "$PKG" || true
adb shell am start -W -n "$PKG/com.mobile.brasiltv.activity.SplashAty" | tee "$OUT/start-splash.txt" || true
sleep 15
capture splash15
sleep 25
capture splash40
adb logcat -d > "$OUT/logcat-splash.txt" || true

# If the normal update dialog exposes its legitimate close control, exercise it only.
python3 - "$OUT/splash40.xml" > "$OUT/close-coords.txt" <<'PY' || true
import re,sys
p=sys.argv[1]
s=open(p,encoding='utf-8',errors='ignore').read()
m=re.search(r'resource-id="com\.msandroid\.mobile:id/ivClose"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',s)
if m:
    x1,y1,x2,y2=map(int,m.groups()); print((x1+x2)//2,(y1+y2)//2)
PY
if [ -s "$OUT/close-coords.txt" ]; then
  read X Y < "$OUT/close-coords.txt"
  adb shell input tap "$X" "$Y" || true
  sleep 10
  capture after-normal-close
fi

# Diagnostic only: determine whether app screens can be entered by their declared activities.
for target in \
  com.mobile.brasiltv.mine.activity.LoginAty \
  com.mobile.brasiltv.activity.MainAty; do
  safe="$(echo "$target" | tr '.-' '__')"
  adb shell am force-stop "$PKG" || true
  adb shell am start -W -n "$PKG/$target" > "$OUT/start-${safe}.txt" 2>&1 || true
  sleep 12
  capture "direct-${safe}"
done

adb logcat -d > "$OUT/logcat-final.txt" || true

printf '\n=== UI TEXT SUMMARY ===\n' | tee "$OUT/summary.txt"
for f in "$OUT"/*.xml; do
  echo "--- $(basename "$f") ---" | tee -a "$OUT/summary.txt"
  sed 's/></>\n</g' "$f" | grep -oE 'text="[^"]*"|resource-id="[^"]*"' | grep -Ei 'version|upgrade|update|discontinued|forbidden|login|email|user|password|close|exit|continue|account' | head -80 | tee -a "$OUT/summary.txt" || true
done

PID="$(adb shell pidof "$PKG" 2>/dev/null || true)"
echo "final_pid=$PID" | tee -a "$OUT/summary.txt"
