#!/usr/bin/env bash
set -euxo pipefail

mkdir -p diagnostics624/dexdump

adb root || true
adb wait-for-device
adb install -r Magis-6.2.4.apk | tee diagnostics624/install-spawn.txt
adb shell pm clear com.msandroid.mobile || true

FRIDA_VERSION=17.2.17
curl -fL --retry 3 --retry-all-errors \
  "https://github.com/frida/frida/releases/download/${FRIDA_VERSION}/frida-server-${FRIDA_VERSION}-android-x86_64.xz" \
  -o /tmp/frida-server.xz
xz -dc /tmp/frida-server.xz > /tmp/frida-server
chmod +x /tmp/frida-server
adb push /tmp/frida-server /data/local/tmp/frida-server
adb shell chmod 755 /data/local/tmp/frida-server
adb shell 'pkill -9 frida-server || true; nohup /data/local/tmp/frida-server >/data/local/tmp/frida.log 2>&1 &'
sleep 3
frida-ps -Uai | tee diagnostics624/frida-ps-spawn.txt

# Spawn the package suspended so Frida attaches before app code runs.
python - <<'PY' | tee diagnostics624/spawn-driver.txt
import frida, time, os, sys, subprocess
pkg='com.msandroid.mobile'
dev=frida.get_usb_device(timeout=15)
pid=dev.spawn([pkg])
print('spawned', pid, flush=True)
session=dev.attach(pid)
# Resume immediately after attach; frida-dexdump will attach to the now-live process.
dev.resume(pid)
print('resumed', pid, flush=True)
time.sleep(2)
open('diagnostics624/spawn-pid.txt','w').write(str(pid))
PY

# Capture as early as possible after spawn.
set +e
frida-dexdump -U -p "$(cat diagnostics624/spawn-pid.txt)" -o diagnostics624/dexdump \
  2>&1 | tee diagnostics624/frida-dexdump-spawn.txt
rc=${PIPESTATUS[0]}
set -e
echo "frida-dexdump rc=${rc}" | tee diagnostics624/frida-dexdump-spawn-rc.txt

adb shell pidof com.msandroid.mobile | tee diagnostics624/pid-after-dump.txt || true
adb shell dumpsys activity activities | grep -E 'mResumedActivity|topResumedActivity' | tee diagnostics624/resumed-after-dump.txt || true
adb exec-out screencap -p > diagnostics624/screen-after-dump.png || true
adb logcat -d -v threadtime > diagnostics624/logcat-spawn.txt || true

find diagnostics624/dexdump -type f -name '*.dex' -print -exec sha256sum '{}' ';' \
  | tee diagnostics624/dex-files-spawn.txt

grep -RIna --binary-files=text -E \
  'handleForceUpgrade|handleUpgradeBussiness|CommonUpgradeDialog|UpgradeDialog|forceUpdate|getForceUpdate|hasNewVersion|upgradeVerCode|dialog_common_upgrade|api/portalCore/box/update' \
  diagnostics624/dexdump > diagnostics624/upgrade-symbol-hits-spawn.txt || true
head -200 diagnostics624/upgrade-symbol-hits-spawn.txt || true

# Fail only if no DEX was captured, so a green workflow means the dump is usable.
if ! find diagnostics624/dexdump -type f -name '*.dex' -print -quit | grep -q .; then
  echo 'NO_DEX_CAPTURED'
  exit 2
fi
