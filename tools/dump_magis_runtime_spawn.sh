#!/usr/bin/env bash
set -euxo pipefail

PKG='com.msandroid.mobile'
rm -rf diagnostics624
mkdir -p diagnostics624/dexdump-early diagnostics624/dexdump-late diagnostics624/dexdump diagnostics624/jadx-runtime

adb root || true
adb wait-for-device
adb install -r Magis-6.2.4.apk | tee diagnostics624/install-spawn.txt
adb shell pm clear "$PKG" || true

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
frida-ps -Uai | tee diagnostics624/frida-ps-before-launch.txt

# Android 16 sometimes times out on Frida Device.spawn(). Launch normally, then attach.
adb shell am force-stop "$PKG" || true
adb logcat -c || true
timeout 20s adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 \
  > diagnostics624/launch-monkey.txt 2>&1 || true

PID=''
for i in $(seq 1 30); do
  PID=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r[:space:]' || true)
  [ -n "$PID" ] && break
  sleep 1
done
if [ -z "$PID" ]; then
  echo 'APP_PID_NOT_FOUND' | tee diagnostics624/result.txt
  adb logcat -d -v threadtime > diagnostics624/logcat-launch-fail.txt || true
  exit 3
fi
echo "$PID" | tee diagnostics624/app-pid.txt
frida-ps -Uai | tee diagnostics624/frida-ps-after-launch.txt
sleep 2

# Early dump: capture loader output shortly after startup.
set +e
frida-dexdump -U -p "$PID" -o diagnostics624/dexdump-early \
  2>&1 | tee diagnostics624/frida-dexdump-early.txt
EARLY_RC=${PIPESTATUS[0]}
set -e
echo "early_rc=${EARLY_RC}" | tee diagnostics624/frida-dexdump-early-rc.txt

# Let protected/dynamic classes load and dump again.
sleep 10
PID2=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r[:space:]' || true)
if [ -n "$PID2" ]; then
  set +e
  frida-dexdump -U -p "$PID2" -o diagnostics624/dexdump-late \
    2>&1 | tee diagnostics624/frida-dexdump-late.txt
  LATE_RC=${PIPESTATUS[0]}
  set -e
else
  LATE_RC=99
fi
echo "late_rc=${LATE_RC}" | tee diagnostics624/frida-dexdump-late-rc.txt

# Deduplicate all captured DEX files into one directory.
python3 - <<'PY'
import glob,hashlib,os,shutil
out='diagnostics624/dexdump'; os.makedirs(out,exist_ok=True)
seen={}; n=0
for p in sorted(glob.glob('diagnostics624/dexdump-*/*.dex')):
    b=open(p,'rb').read(); h=hashlib.sha256(b).hexdigest()
    if h in seen: continue
    n+=1; q=os.path.join(out,f'runtime-{n:03d}-{h[:12]}.dex')
    open(q,'wb').write(b); seen[h]=q
print('UNIQUE_DEX',n)
PY

adb shell dumpsys activity activities > diagnostics624/activities.txt || true
adb exec-out screencap -p > diagnostics624/screen-after-dump.png || true
adb logcat -d -v threadtime > diagnostics624/logcat-runtime.txt || true
find diagnostics624/dexdump -type f -name '*.dex' -print -exec sha256sum '{}' ';' \
  | tee diagnostics624/dex-files.txt

# Raw string/symbol scan first.
grep -RIna --binary-files=text -E \
  'vod_no_media|No media found|media sequence|getMedias|StartPlayVOD|PlayAty|0x7f11049b|2131821723|Media;->getName' \
  diagnostics624/dexdump > diagnostics624/vod-symbol-hits.txt || true

# Decompile runtime DEX set.
curl -fL --retry 3 --retry-all-errors https://github.com/skylot/jadx/releases/download/v1.5.6/jadx-1.5.6.zip -o /tmp/jadx.zip
rm -rf /tmp/jadx-runtime-bin && unzip -q /tmp/jadx.zip -d /tmp/jadx-runtime-bin
mapfile -t DEXES < <(find diagnostics624/dexdump -type f -name '*.dex' | sort)
if [ ${#DEXES[@]} -gt 0 ]; then
  /tmp/jadx-runtime-bin/bin/jadx --no-res --show-bad-code -d diagnostics624/jadx-runtime "${DEXES[@]}" \
    > diagnostics624/jadx-runtime.log 2>&1 || true
fi

grep -RIna -E \
  'vod_no_media|2131821723|0x7f11049b|getMedias\(|StartPlayVOD|PlayAty|No media found|media sequence|getName\(\)' \
  diagnostics624/jadx-runtime/sources > diagnostics624/vod-jadx-hits.txt || true

python3 - <<'PY'
import os,re
hits='diagnostics624/vod-jadx-hits.txt'; out='diagnostics624/vod-jadx-context.txt'; seen=[]
if os.path.exists(hits):
 for line in open(hits,errors='ignore'):
  m=re.match(r'([^:]+):(\d+):',line)
  if m:
   k=(m.group(1),int(m.group(2)))
   if k not in seen: seen.append(k)
with open(out,'w') as w:
 for p,n in seen[:200]:
  try: lines=open(p,errors='ignore').read().splitlines()
  except: continue
  w.write(f'\n===== {p}:{n} =====\n')
  for i in range(max(1,n-45),min(len(lines),n+45)+1):
   w.write(f'{i:05d}: {lines[i-1]}\n')
PY

{
 echo "PID=$PID"
 echo "EARLY_RC=$EARLY_RC"
 echo "LATE_RC=$LATE_RC"
 echo "DEX_COUNT=${#DEXES[@]}"
 echo '=== VOD HITS ==='
 head -300 diagnostics624/vod-jadx-hits.txt 2>/dev/null || true
 echo '=== VOD CONTEXT ==='
 head -1600 diagnostics624/vod-jadx-context.txt 2>/dev/null || true
} | tee diagnostics624/result.txt

if [ ${#DEXES[@]} -eq 0 ]; then
  echo 'NO_DEX_CAPTURED' | tee -a diagnostics624/result.txt
  exit 2
fi
