#!/usr/bin/env bash
set -euxo pipefail
mkdir -p diagnostics624/dexdump
adb root || true
adb wait-for-device
adb install -r Magis-6.2.4.apk | tee diagnostics624/install.txt
adb shell pm clear com.msandroid.mobile || true
adb emu geo fix -99.1332 19.4326 >/dev/null 2>&1 || true

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

adb shell monkey -p com.msandroid.mobile -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
sleep 20
adb shell dumpsys activity activities | grep -E 'mResumedActivity|topResumedActivity' | tee diagnostics624/resumed.txt || true
adb shell pidof com.msandroid.mobile | tee diagnostics624/pid.txt || true
adb shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1 || true
adb pull /sdcard/window.xml diagnostics624/window-before.xml >/dev/null 2>&1 || true
adb exec-out screencap -p > diagnostics624/screen-before.png || true

set +e
frida-dexdump -U -n com.msandroid.mobile -o diagnostics624/dexdump 2>&1 | tee diagnostics624/frida-dexdump.txt
rc=${PIPESTATUS[0]}
set -e
echo "frida-dexdump rc=$rc" | tee diagnostics624/frida-dexdump-rc.txt

find diagnostics624/dexdump -type f -name '*.dex' -print -exec sha256sum {} \; | tee diagnostics624/dex-files.txt || true
grep -RIna --binary-files=text -E 'handleForceUpgrade|handleUpgradeBussiness|CommonUpgradeDialog|UpgradeDialog|forceUpdate|getForceUpdate|hasNewVersion|dialog_common_upgrade|api/portalCore/box/update' diagnostics624/dexdump \
  > diagnostics624/upgrade-symbol-hits.txt || true
head -200 diagnostics624/upgrade-symbol-hits.txt || true
test -n "$(find diagnostics624/dexdump -type f -name '*.dex' -print -quit)"
