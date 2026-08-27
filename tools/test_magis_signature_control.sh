#!/usr/bin/env bash
set -euo pipefail
mkdir -p diagnostics-signature

echo '=== ORIGINAL ==='
adb install -r -g magis-original.apk
adb logcat -c
adb shell am force-stop com.msandroid.mobile
adb shell monkey -p com.msandroid.mobile -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
sleep 20
ORIG_PID="$(adb shell pidof com.msandroid.mobile | tr -d '\r' || true)"
echo "ORIGINAL_PID=$ORIG_PID" | tee diagnostics-signature/original.txt
adb logcat -d > diagnostics-signature/original-logcat.txt || true
adb uninstall com.msandroid.mobile >/dev/null 2>&1 || true

echo '=== RESIGNED, PAYLOAD IDENTICAL ==='
adb install -r -g magis-resigned.apk
adb logcat -c
adb shell am force-stop com.msandroid.mobile
adb shell monkey -p com.msandroid.mobile -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
sleep 20
RESIGNED_PID="$(adb shell pidof com.msandroid.mobile | tr -d '\r' || true)"
echo "RESIGNED_PID=$RESIGNED_PID" | tee diagnostics-signature/resigned.txt
adb logcat -d > diagnostics-signature/resigned-logcat.txt || true
grep -Ei 'EXIT_SELF|signature|certificate|tamper|verify|protect|shell|kill|finish' diagnostics-signature/resigned-logcat.txt | tail -300 > diagnostics-signature/resigned-interesting.txt || true

echo "ORIGINAL=$ORIG_PID RESIGNED=$RESIGNED_PID"
if [[ -z "$ORIG_PID" ]]; then
  echo 'CONTROL_INVALID_ORIGINAL_NOT_ALIVE'
  exit 2
fi
if [[ -n "$RESIGNED_PID" ]]; then
  echo 'RESIGNED_PAYLOAD_ALIVE'
else
  echo 'SIGNATURE_ONLY_SELF_TERMINATION_CONFIRMED'
fi
