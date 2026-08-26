#!/usr/bin/env bash
set -u
PKG=com.msandroid.mobile
OUT=diagnostics-official
mkdir -p "$OUT"

adb uninstall "$PKG" >/dev/null 2>&1 || true
adb logcat -c || true

echo '=== INSTALL OFFICIAL ===' | tee "$OUT/result.txt"
if adb install -r Magis-6.2.4.apk | tee "$OUT/install.txt" | grep -q Success; then
  echo 'INSTALL=PASS' | tee -a "$OUT/result.txt"
else
  echo 'INSTALL=FAIL' | tee -a "$OUT/result.txt"
  exit 0
fi

adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 | tee "$OUT/launch.txt" || true
sleep 7
adb shell pidof "$PKG" > "$OUT/t7.pid" 2>/dev/null || true
adb exec-out screencap -p > "$OUT/t7.png" || true
adb shell uiautomator dump /sdcard/t7.xml >/dev/null 2>&1 || true
adb pull /sdcard/t7.xml "$OUT/t7.xml" >/dev/null 2>&1 || true
if test -s "$OUT/t7.pid"; then echo 'ALIVE7=PASS' | tee -a "$OUT/result.txt"; else echo 'ALIVE7=FAIL' | tee -a "$OUT/result.txt"; fi

sleep 10
adb shell pidof "$PKG" > "$OUT/t17.pid" 2>/dev/null || true
adb exec-out screencap -p > "$OUT/t17.png" || true
adb shell uiautomator dump /sdcard/t17.xml >/dev/null 2>&1 || true
adb pull /sdcard/t17.xml "$OUT/t17.xml" >/dev/null 2>&1 || true
if test -s "$OUT/t17.pid"; then echo 'ALIVE17=PASS' | tee -a "$OUT/result.txt"; else echo 'ALIVE17=FAIL' | tee -a "$OUT/result.txt"; fi

adb logcat -d > "$OUT/logcat.txt" || true
grep -E 'F DEBUG|SIGSEGV|failed resume p2p|App crashed|Process com.msandroid.mobile|com.msandroid.mobile.*died' "$OUT/logcat.txt" > "$OUT/native-crash-summary.txt" || true
if grep -q 'failed resume p2p addr' "$OUT/logcat.txt"; then echo 'P2P_NATIVE_CRASH=YES' | tee -a "$OUT/result.txt"; else echo 'P2P_NATIVE_CRASH=NO' | tee -a "$OUT/result.txt"; fi
cat "$OUT/native-crash-summary.txt" || true
