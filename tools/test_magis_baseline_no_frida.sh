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

sleep 3
p3=$(timeout 3s adb shell pidof com.msandroid.mobile 2>/dev/null | tr -d '\r' || true)
echo "pid_after_3s=${p3:-DEAD}" | tee diagnostics-baseline/pid-3s.txt

sleep 7
p10=$(timeout 3s adb shell pidof com.msandroid.mobile 2>/dev/null | tr -d '\r' || true)
echo "pid_after_10s=${p10:-DEAD}" | tee diagnostics-baseline/result.txt

timeout 5s adb shell dumpsys activity activities 2>/dev/null \
  | grep -E 'mResumedActivity|topResumedActivity' \
  | tee diagnostics-baseline/resumed.txt || true
timeout 5s adb exec-out screencap -p > diagnostics-baseline/screen.png || true
timeout 8s adb logcat -d -v threadtime > diagnostics-baseline/logcat.txt || true
grep -E 'FATAL EXCEPTION|zygote64|ZygoteFailure|Fatal signal|AndroidRuntime|com.msandroid.mobile|SplashAty|SIGABRT|SIGSEGV|UnsatisfiedLinkError|Upgrade|upgrade' \
  diagnostics-baseline/logcat.txt > diagnostics-baseline/logcat-focus.txt || true

# Strict baseline: official APK must remain alive at both checkpoints.
test -n "$p3"
test -n "$p10"
