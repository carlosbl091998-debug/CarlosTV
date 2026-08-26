#!/usr/bin/env bash
set -euxo pipefail

mkdir -p diagnostics624/dexdump diagnostics624/jadx-runtime

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

python - <<'PY' | tee diagnostics624/spawn-driver.txt
import frida, time
pkg='com.msandroid.mobile'
dev=frida.get_usb_device(timeout=15)
pid=dev.spawn([pkg])
print('spawned', pid, flush=True)
session=dev.attach(pid)
dev.resume(pid)
print('resumed', pid, flush=True)
time.sleep(4)
open('diagnostics624/spawn-pid.txt','w').write(str(pid))
PY

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
  'vod_no_media|No media found|media sequence|getMedias|StartPlayVOD|PlayAty|0x7f11049b|handleForceUpgrade|forceUpdate|upgradeVerCode' \
  diagnostics624/dexdump > diagnostics624/vod-symbol-hits-spawn.txt || true
head -300 diagnostics624/vod-symbol-hits-spawn.txt || true

# Decompile every captured runtime DEX together and trace the actual VOD failure branch.
curl -fL --retry 3 --retry-all-errors https://github.com/skylot/jadx/releases/download/v1.5.6/jadx-1.5.6.zip -o /tmp/jadx.zip
rm -rf /tmp/jadx-runtime-bin && unzip -q /tmp/jadx.zip -d /tmp/jadx-runtime-bin
mapfile -t DEXES < <(find diagnostics624/dexdump -type f -name '*.dex' | sort)
if [ ${#DEXES[@]} -gt 0 ]; then
  /tmp/jadx-runtime-bin/bin/jadx --no-res --show-bad-code -d diagnostics624/jadx-runtime "${DEXES[@]}" > diagnostics624/jadx-runtime.log 2>&1 || true
fi

grep -RIna -E \
  'vod_no_media|2131821723|0x7f11049b|getMedias\(|StartPlayVOD|PlayAty|No media found|media sequence' \
  diagnostics624/jadx-runtime/sources > diagnostics624/vod-jadx-hits.txt || true

python3 - <<'PY'
import os,re
hits='diagnostics624/vod-jadx-hits.txt'
out='diagnostics624/vod-jadx-context.txt'
seen=[]
if os.path.exists(hits):
 for line in open(hits,errors='ignore'):
  m=re.match(r'([^:]+):(\d+):',line)
  if m:
   key=(m.group(1),int(m.group(2)))
   if key not in seen: seen.append(key)
with open(out,'w') as w:
 for p,n in seen[:160]:
  try: lines=open(p,errors='ignore').read().splitlines()
  except: continue
  w.write(f'\n===== {p}:{n} =====\n')
  for i in range(max(1,n-35),min(len(lines),n+35)+1):
   w.write(f'{i:05d}: {lines[i-1]}\n')
PY
head -1000 diagnostics624/vod-jadx-context.txt || true

if ! find diagnostics624/dexdump -type f -name '*.dex' -print -quit | grep -q .; then
  echo 'NO_DEX_CAPTURED'
  exit 2
fi
