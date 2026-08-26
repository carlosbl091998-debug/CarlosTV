#!/usr/bin/env bash
set -euo pipefail
APK='Magis-6.2.4.apk'
OUT='diagnostics-update-smali'
mkdir -p "$OUT"

curl -fL --retry 3 --retry-all-errors \
  https://github.com/iBotPeaches/Apktool/releases/download/v2.12.1/apktool_2.12.1.jar \
  -o /tmp/apktool.jar
java -jar /tmp/apktool.jar d -f -r "$APK" -o "$OUT/decoded" > "$OUT/apktool.log" 2>&1 || true

for term in 'forceUpdate' 'hasNewVersion' 'upgradeVerCode' 'api/portalCore/box/update'; do
  echo "===== $term =====" >> "$OUT/hits.txt"
  grep -R -n -F "$term" "$OUT/decoded" --include='*.smali' 2>/dev/null | head -100 >> "$OUT/hits.txt" || true
done

python3 - "$OUT/hits.txt" "$OUT/context.txt" <<'PY'
import re,sys
hits,out=sys.argv[1:]
seen=[]
for line in open(hits,errors='ignore'):
    m=re.match(r'([^:]+):(\d+):',line)
    if m:
        k=(m.group(1),int(m.group(2)))
        if k not in seen: seen.append(k)
with open(out,'w') as w:
    for p,n in seen[:100]:
        try: lines=open(p,errors='ignore').read().splitlines()
        except: continue
        w.write(f'\n===== {p}:{n} =====\n')
        for i in range(max(1,n-35),min(len(lines),n+45)+1):
            w.write(f'{i:05d}: {lines[i-1]}\n')
PY
cat "$OUT/hits.txt"
echo '=== CONTEXT ==='
cat "$OUT/context.txt"
