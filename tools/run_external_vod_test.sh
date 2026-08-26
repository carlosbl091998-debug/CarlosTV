#!/usr/bin/env bash
set -euo pipefail
OUT=diagnostics-vod-v9-external
APK=stable-base/Xuper-base-stable.apk
PKG=com.msandroid.mobile
mkdir -p "$OUT"

wait_adb_stable() {
  echo "Waiting for stable ADB..."
  adb wait-for-device
  local ok=0
  for i in $(seq 1 30); do
    state="$(adb get-state 2>/dev/null || true)"
    boot="$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
    if [ "$state" = "device" ] && [ "$boot" = "1" ]; then
      ok=$((ok+1))
      if [ "$ok" -ge 5 ]; then
        adb shell true
        return 0
      fi
    else
      ok=0
    fi
    sleep 2
  done
  echo "ADB never became stable" >&2
  adb devices -l || true
  return 1
}

wait_adb_stable
adb root >/dev/null 2>&1 || true
wait_adb_stable

# Install first. Retry transient package-service/transport failures only after
# ADB has returned to a stable device state.
installed=0
for attempt in 1 2 3; do
  echo "APK install attempt $attempt"
  if adb install -r -g "$APK" 2>&1 | tee "$OUT/install-attempt-${attempt}.txt"; then
    installed=1
    cp "$OUT/install-attempt-${attempt}.txt" "$OUT/install.txt"
    break
  fi
  adb kill-server || true
  sleep 3
  adb start-server
  wait_adb_stable
  sleep 2
done
if [ "$installed" -ne 1 ]; then
  echo INSTALL_FAILED > "$OUT/result.txt"
  exit 20
fi

# Frida is deliberately started only after package installation is complete.
adb push /tmp/frida-server /data/local/tmp/frida-server >/dev/null
adb shell chmod 755 /data/local/tmp/frida-server
adb shell 'pkill -f frida-server || true' || true
adb shell 'nohup /data/local/tmp/frida-server -l 0.0.0.0:27042 >/data/local/tmp/frida.log 2>&1 </dev/null &' || true
sleep 3
wait_adb_stable
adb shell 'ps -A | grep frida || true' > "$OUT/frida-server-ps.txt"
adb shell 'cat /data/local/tmp/frida.log || true' > "$OUT/frida-server-log.txt"
adb forward --remove-all || true
adb forward tcp:27042 tcp:27042

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
