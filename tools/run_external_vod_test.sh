#!/usr/bin/env bash
set -euo pipefail
OUT=diagnostics-vod-v9-external
APK=stable-base/Xuper-base-stable.apk
PKG=com.msandroid.mobile
mkdir -p "$OUT"
adb wait-for-device
adb root >/dev/null 2>&1 || true
adb wait-for-device
adb push /tmp/frida-server /data/local/tmp/frida-server >/dev/null
adb shell chmod 755 /data/local/tmp/frida-server
adb shell 'pkill -f frida-server || true' || true
adb shell 'nohup /data/local/tmp/frida-server -l 0.0.0.0:27042 >/data/local/tmp/frida.log 2>&1 </dev/null &' || true
sleep 3
adb shell 'ps -A | grep frida || true' > "$OUT/frida-server-ps.txt"
adb shell 'cat /data/local/tmp/frida.log || true' > "$OUT/frida-server-log.txt"
adb forward tcp:27042 tcp:27042
adb install -r -g "$APK" | tee "$OUT/install.txt"
adb logcat -c
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > "$OUT/launch.txt" 2>&1 || true
sleep 5
PID5=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true)
echo "$PID5" > "$OUT/pid5.txt"
if [ -z "$PID5" ]; then adb logcat -d -v threadtime > "$OUT/logcat.txt" || true; echo APP_DIED_BEFORE_ATTACH > "$OUT/result.txt"; exit 21; fi
(timeout 55s frida -H 127.0.0.1:27042 -p "$PID5" -l tools/vod_v9_external_hook.js -q > "$OUT/frida.txt" 2>&1 || true) &
FRIDA_PID=$!
sleep 15
PID20=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true); echo "$PID20" > "$OUT/pid20.txt"; adb exec-out screencap -p > "$OUT/screen20.png" || true
sleep 40
PID60=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true); echo "$PID60" > "$OUT/pid60.txt"; adb exec-out screencap -p > "$OUT/screen60.png" || true
wait "$FRIDA_PID" || true
adb logcat -d -v threadtime > "$OUT/logcat.txt" || true
if [ -z "$PID20" ] || [ -z "$PID60" ]; then echo APP_NOT_STABLE > "$OUT/result.txt"; exit 22; fi
if grep -Eqi 'FATAL EXCEPTION|UnsatisfiedLinkError|SIGABRT|Fatal signal' "$OUT/logcat.txt"; then echo CRASH_MARKER_FOUND > "$OUT/result.txt"; exit 23; fi
if grep -q '\[XUPER_VOD_FIX\] hook installed' "$OUT/frida.txt"; then echo EXTERNAL_HOOK_STABLE_OK > "$OUT/result.txt"; else echo APP_STABLE_HOOK_NOT_INSTALLED > "$OUT/result.txt"; exit 24; fi
