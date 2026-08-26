#!/usr/bin/env bash
set -euo pipefail
APK='Magis-6.2.4.apk'
OUT='diagnostics-update-logic'
mkdir -p "$OUT"

curl -fL --retry 3 --retry-all-errors \
  https://github.com/skylot/jadx/releases/download/v1.5.6/jadx-1.5.6.zip \
  -o /tmp/jadx.zip
unzip -q /tmp/jadx.zip -d /tmp/jadx
/tmp/jadx/bin/jadx --no-res --show-bad-code -d "$OUT/jadx" "$APK" > "$OUT/jadx.log" 2>&1 || true

for term in 'forceUpdate' 'hasNewVersion' 'upgradeVerCode' 'portalCore/box/update' 'UpgradeDialog' 'handleForceUpgrade'; do
  echo "===== $term =====" >> "$OUT/hits.txt"
  grep -R -n -F "$term" "$OUT/jadx/sources" 2>/dev/null | head -80 >> "$OUT/hits.txt" || true
done

python3 - "$OUT/hits.txt" "$OUT/context.txt" <<'PY'
import os,re,sys
hits,out=sys.argv[1:]
seen=[]
for line in open(hits,errors='ignore'):
    m=re.match(r'([^:]+):(\d+):',line)
    if m:
        p,n=m.group(1),int(m.group(2))
        key=(p,n)
        if key not in seen: seen.append(key)
with open(out,'w') as w:
    for p,n in seen[:80]:
        try: lines=open(p,errors='ignore').read().splitlines()
        except: continue
        w.write(f'\n===== {p}:{n} =====\n')
        for i in range(max(1,n-18),min(len(lines),n+18)+1):
            w.write(f'{i:05d}: {lines[i-1]}\n')
PY

cat "$OUT/hits.txt"
echo '=== CONTEXT ==='
cat "$OUT/context.txt"
