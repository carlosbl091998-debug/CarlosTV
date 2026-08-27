#!/usr/bin/env bash
set -u
mkdir -p diagnostics
PKG='com.android.mgstv'
ACT='com.interactive.brasiliptv.ui.activity.WelcomeActivity'

adb wait-for-device
adb shell getprop ro.build.version.release | tee diagnostics/android_version.txt
adb shell getprop ro.build.version.sdk | tee diagnostics/android_sdk.txt

run_case() {
  NAME="$1"
  APK="$2"
  echo "========== $NAME ==========" | tee "diagnostics/${NAME}.summary.txt"
  adb uninstall "$PKG" >/dev/null 2>&1 || true
  adb logcat -c || true

  if ! adb install "$APK" >"diagnostics/${NAME}.install.txt" 2>&1; then
    echo "INSTALL_FAILED" | tee -a "diagnostics/${NAME}.summary.txt"
    cat "diagnostics/${NAME}.install.txt"
    return 20
  fi
  cat "diagnostics/${NAME}.install.txt"

  adb shell am force-stop "$PKG" || true
  adb shell am start -W -n "$PKG/$ACT" >"diagnostics/${NAME}.start.txt" 2>&1 || true
  cat "diagnostics/${NAME}.start.txt"
  sleep 12

  PID="$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true)"
  adb shell dumpsys activity activities >"diagnostics/${NAME}.activities.txt" 2>&1 || true
  adb logcat -d -v threadtime >"diagnostics/${NAME}.logcat.txt" 2>&1 || true

  if [ -n "$PID" ]; then
    echo "RUNNING pid=$PID after 12s" | tee -a "diagnostics/${NAME}.summary.txt"
    adb exec-out screencap -p >"diagnostics/${NAME}.png" || true
    return 0
  fi

  echo "PROCESS_DIED within 12s" | tee -a "diagnostics/${NAME}.summary.txt"
  grep -E -i 'FATAL EXCEPTION|AndroidRuntime|SIG(SEGV|ABRT)|crash|Process: com.android.mgstv|ijiami|UnsatisfiedLinkError|SecurityException|VerifyError|ClassNotFoundException|NoClassDefFoundError' \
    "diagnostics/${NAME}.logcat.txt" | tail -n 180 | tee -a "diagnostics/${NAME}.summary.txt" || true
  return 30
}

BASE_RC=0
NOOP_RC=0
SENSOR_RC=0
run_case original base.apk || BASE_RC=$?
run_case noop_resigned noop-resigned.apk || NOOP_RC=$?
run_case sensor_mobile sensor-mobile.apk || SENSOR_RC=$?

{
  echo "original=$BASE_RC"
  echo "noop_resigned=$NOOP_RC"
  echo "sensor_mobile=$SENSOR_RC"
} | tee diagnostics/results.txt

# Diagnostic workflow should fail only when the original itself cannot launch,
# because then the emulator is not a valid reference environment.
if [ "$BASE_RC" -ne 0 ]; then
  echo 'Original APK did not survive launch; emulator result is not a valid comparison.'
  exit 1
fi

# Keep the job green when modified variants fail: those failures are the result we need to inspect.
exit 0
