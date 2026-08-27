#!/usr/bin/env bash
set -euxo pipefail

PKG='com.android.mgstv'
OUT='network-observation'
mkdir -p "$OUT"

adb install -r base.apk
adb root >/dev/null 2>&1 || true
adb wait-for-device
sleep 2

adb shell settings put secure immersive_mode_confirmations confirmed >/dev/null 2>&1 || true

# Grant only normal runtime permissions requested by the app so Android's own
# permission dialogs do not block the observation. Unsupported/legacy grants are ignored.
adb shell dumpsys package "$PKG" > "$OUT/package.txt" || true
awk '/requested permissions:/{f=1;next}/install permissions:/{f=0}f && /android\.permission\./{gsub(":",""); print $1}' "$OUT/package.txt" \
  | sort -u > "$OUT/requested-permissions.txt" || true
while IFS= read -r p; do
  [ -n "$p" ] || continue
  adb shell pm grant "$PKG" "$p" </dev/null >/dev/null 2>&1 || true
done < "$OUT/requested-permissions.txt"

uid=$(adb shell cmd package list packages -U 2>/dev/null | sed -n "s/^package:${PKG}[[:space:]]*uid:\([0-9]*\).*/\1/p" | head -1 | tr -d '\r')
if [ -z "${uid:-}" ]; then
  uid=$(adb shell dumpsys package "$PKG" | sed -n 's/^[[:space:]]*userId=\([0-9]*\).*/\1/p' | head -1 | tr -d '\r')
fi
echo "package=$PKG" | tee "$OUT/runtime-summary.txt"
echo "uid=${uid:-unknown}" | tee -a "$OUT/runtime-summary.txt"

adb logcat -c || true
adb shell am force-stop "$PKG" || true
date +%s > "$OUT/launch-epoch.txt"

# Launch the untouched application. No proxy, certificate injection, pinning bypass,
# hook, or traffic decryption is used in this observation.
adb shell am start -W -n "$PKG/com.interactive.brasiliptv.ui.activity.WelcomeActivity" \
  > "$OUT/start.txt" 2>&1 || true

# Dismiss ordinary Android permission/tutorial dialogs if the OEM image still shows one.
for i in $(seq 1 12); do
  adb shell uiautomator dump /sdcard/dialog.xml >/dev/null 2>&1 || true
  adb pull /sdcard/dialog.xml /tmp/dialog.xml >/dev/null 2>&1 || true
  xy=$(python3 - <<'PY'
import re, xml.etree.ElementTree as ET
try:
    root=ET.parse('/tmp/dialog.xml').getroot()
except Exception:
    raise SystemExit
wanted={
 'allow','while using the app','only this time','ok','got it','continue','permitir',
 'mientras se usa la app','solo esta vez','aceptar','entendido','continuar'
}
for n in root.iter('node'):
    text=(n.attrib.get('text') or '').strip().lower()
    if text in wanted:
        m=re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', n.attrib.get('bounds',''))
        if m:
            x1,y1,x2,y2=map(int,m.groups())
            print((x1+x2)//2,(y1+y2)//2)
            break
PY
)
  if [ -n "${xy:-}" ]; then
    adb shell input tap $xy </dev/null >/dev/null 2>&1 || true
    sleep 1
  else
    break
  fi
done

# Sample kernel connection tables while the app initializes. Rows are later
# filtered by the Linux UID assigned to the package, so no payload is captured.
: > "$OUT/app-sockets-raw.txt"
for i in $(seq 1 50); do
  echo "--- sample $i ---" >> "$OUT/app-sockets-raw.txt"
  if [ -n "${uid:-}" ]; then
    adb shell "cat /proc/net/tcp /proc/net/tcp6 2>/dev/null" \
      | awk -v u="$uid" 'NR==1 || $8==u {print}' >> "$OUT/app-sockets-raw.txt" || true
  fi
  sleep 1
done

pid=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true)
echo "pid_after_50s=${pid:-DEAD}" | tee -a "$OUT/runtime-summary.txt"
adb shell dumpsys activity activities | grep -E 'mResumedActivity|topResumedActivity' | tail -3 > "$OUT/top-activity.txt" || true

adb shell uiautomator dump /sdcard/xuper-ui.xml >/dev/null 2>&1 || true
adb pull /sdcard/xuper-ui.xml "$OUT/ui.xml" >/dev/null 2>&1 || true
adb exec-out screencap -p > "$OUT/screen.png" || true
adb logcat -d -v threadtime > "$OUT/logcat-full.txt" || true

# Keep only networking-related log lines and redact obvious token/password query values.
python3 - <<'PY'
import re
from pathlib import Path
src=Path('network-observation/logcat-full.txt')
out=Path('network-observation/logcat-network.txt')
text=src.read_text(errors='ignore') if src.exists() else ''
lines=[]
for line in text.splitlines():
    low=line.lower()
    if any(k in low for k in ('http://','https://',' dns','dnsresolver','okhttp','retrofit','socket','connect','host','ssl','tls','portal','stream','mgstv','brasiltv','xuper')):
        line=re.sub(r'(?i)(token|password|passwd|pwd|username|usertoken|session|auth)=([^&\s]+)', r'\1=<redacted>', line)
        lines.append(line)
out.write_text('\n'.join(lines), encoding='utf-8')
PY

# Decode only remote endpoints from UID-filtered /proc rows.
python3 - <<'PY'
from pathlib import Path
import ipaddress, socket
raw=Path('network-observation/app-sockets-raw.txt').read_text(errors='ignore').splitlines()
seen=set(); out=[]

def dec4(h):
    b=bytes.fromhex(h)
    return socket.inet_ntoa(b[::-1])

def dec6(h):
    b=bytes.fromhex(h)
    b=b''.join(b[i:i+4][::-1] for i in range(0,16,4))
    return str(ipaddress.IPv6Address(b))

for line in raw:
    parts=line.split()
    if len(parts) < 8 or ':' not in parts[2]:
        continue
    rem=parts[2]
    ah,ph=rem.split(':',1)
    try:
        ip=dec4(ah) if len(ah)==8 else dec6(ah)
        port=int(ph,16)
    except Exception:
        continue
    if port==0 or ip in ('0.0.0.0','::'):
        continue
    key=(ip,port)
    if key not in seen:
        seen.add(key); out.append(f'{ip}:{port}')
Path('network-observation/app-remote-endpoints.txt').write_text('\n'.join(out), encoding='utf-8')
PY

rm -f "$OUT/logcat-full.txt"
