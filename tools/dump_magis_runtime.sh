#!/usr/bin/env bash
set -euxo pipefail
mkdir -p diagnostics624/dexdump
adb root || true
adb wait-for-device
adb install -r Magis-6.2.4.apk | tee diagnostics624/install.txt
adb shell pm clear com.msandroid.mobile || true
adb emu geo fix -99.1332 19.4326 >/dev/null 2>&1 || true
adb shell getprop ro.product.cpu.abilist | tee diagnostics624/emulator-abilist.txt || true
adb shell getprop ro.dalvik.vm.native.bridge | tee diagnostics624/native-bridge.txt || true

FRIDA_VERSION=17.2.17
curl -fL --retry 3 --retry-all-errors \
  "https://github.com/frida/frida/releases/download/${FRIDA_VERSION}/frida-server-${FRIDA_VERSION}-android-x86_64.xz" \
  -o /tmp/frida-server.xz
xz -dc /tmp/frida-server.xz > /tmp/frida-server
chmod +x /tmp/frida-server
adb push /tmp/frida-server /data/local/tmp/frida-server >/dev/null
adb shell chmod 755 /data/local/tmp/frida-server
adb shell 'pkill -9 frida-server || true; nohup /data/local/tmp/frida-server >/data/local/tmp/frida.log 2>&1 &' || true
sleep 3
frida-ps -Uai | tee diagnostics624/frida-ps-before.txt || true
adb logcat -c || true

# Launch normally so the app is not held in Frida spawn. Attach as soon as PID exists.
adb shell am start -n com.msandroid.mobile/com.mobile.brasiltv.activity.SplashAty \
  | tee diagnostics624/am-start.txt || true
PID=""
for i in $(seq 1 100); do
  PID=$(adb shell pidof com.msandroid.mobile 2>/dev/null | tr -d '\r' || true)
  if [ -n "$PID" ]; then
    echo "pid_seen=$PID iteration=$i" | tee diagnostics624/pid-first-seen.txt
    break
  fi
  sleep 0.1
done

if [ -z "$PID" ]; then
  echo "PID never appeared" | tee diagnostics624/attach-result.txt
else
  set +e
  timeout --signal=INT --kill-after=5s 30s \
    frida-dexdump -U -p "$PID" -o diagnostics624/dexdump \
    2>&1 | tee diagnostics624/frida-dexdump.txt
  rc=${PIPESTATUS[0]}
  set -e
  echo "frida-dexdump rc=$rc pid=$PID" | tee diagnostics624/frida-dexdump-rc.txt
fi

adb shell pidof com.msandroid.mobile | tee diagnostics624/pid-after-dump.txt || true
adb shell dumpsys activity activities | grep -E 'mResumedActivity|topResumedActivity' | tee diagnostics624/resumed-after-dump.txt || true
adb shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1 || true
adb pull /sdcard/window.xml diagnostics624/window-after-dump.xml >/dev/null 2>&1 || true
adb exec-out screencap -p > diagnostics624/screen-after-dump.png || true
adb logcat -d -v threadtime > diagnostics624/logcat.txt || true
{
  grep -E 'FATAL EXCEPTION|AndroidRuntime|UnsatisfiedLinkError|SIGABRT|SIGSEGV|com.msandroid.mobile|SplashAty|Upgrade|upgrade' diagnostics624/logcat.txt || true
} > diagnostics624/logcat-focus.txt
adb shell cat /data/local/tmp/frida.log > diagnostics624/frida-server.log 2>/dev/null || true

find diagnostics624/dexdump -type f -name '*.dex' -print -exec sha256sum {} \; | tee diagnostics624/dex-files.txt || true
grep -RIna --binary-files=text -E 'handleForceUpgrade|handleUpgradeBussiness|CommonUpgradeDialog|UpgradeDialog|forceUpdate|getForceUpdate|hasNewVersion|dialog_common_upgrade|api/portalCore/box/update|upgradeVerCode' diagnostics624/dexdump \
  > diagnostics624/upgrade-symbol-hits.txt || true
head -300 diagnostics624/upgrade-symbol-hits.txt || true

test -n "$(find diagnostics624/dexdump -type f -name '*.dex' -print -quit)"
