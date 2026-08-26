#!/usr/bin/env bash
set -euxo pipefail

mkdir -p diagnostics-baseline
adb wait-for-device
adb shell getprop ro.product.cpu.abilist | tee diagnostics-baseline/emulator-abilist.txt
adb shell getprop ro.dalvik.vm.native.bridge | tee diagnostics-baseline/native-bridge.txt
adb install -r Magis-6.2.4.apk | tee diagnostics-baseline/install.txt
adb shell pm clear com.msandroid.mobile || true
adb emu geo fix -99.1332 19.4326 >/dev/null 2>&1 || true
adb logcat -c || true

adb shell am start -n com.msandroid.mobile/com.mobile.brasiltv.activity.SplashAty \
  | tee diagnostics-baseline/am-start.txt || true

seen=0
for i in $(seq 1 200); do
  p=$(adb shell pidof com.msandroid.mobile 2>/dev/null | tr -d '\r' || true)
  if [ -n "$p" ]; then
    echo "iteration=$i pid=$p" | tee -a diagnostics-baseline/pid-history.txt
    seen=1
  fi
  sleep 0.1
done

sleep 10
p30=$(adb shell pidof com.msandroid.mobile 2>/dev/null | tr -d '\r' || true)
echo "pid_after_30s=${p30:-DEAD}" | tee diagnostics-baseline/result.txt
adb shell dumpsys activity activities | grep -E 'mResumedActivity|topResumedActivity' \
  | tee diagnostics-baseline/resumed.txt || true
adb shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1 || true
adb pull /sdcard/window.xml diagnostics-baseline/window.xml >/dev/null 2>&1 || true
adb exec-out screencap -p > diagnostics-baseline/screen.png || true
adb logcat -d -v threadtime > diagnostics-baseline/logcat.txt || true
grep -E 'FATAL EXCEPTION|zygote64|ZygoteFailure|Fatal signal|AndroidRuntime|com.msandroid.mobile|SplashAty|SIGABRT|SIGSEGV|UnsatisfiedLinkError|Upgrade|upgrade' \
  diagnostics-baseline/logcat.txt > diagnostics-baseline/logcat-focus.txt || true

# Strict baseline: official APK must have appeared and remain alive after ~30 s.
test "$seen" -eq 1
test -n "$p30"
