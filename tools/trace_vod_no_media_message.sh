#!/usr/bin/env bash
set -euo pipefail
APK='Magis-6.2.4.apk'
OUT='diagnostics-vod-message-trace'
WORK='/tmp/xuper-vod-message-trace'
rm -rf "$WORK" "$OUT"
mkdir -p "$WORK" "$OUT"

APKTOOL="$RUNNER_TEMP/apktool.jar"
curl -fL --retry 4 --retry-all-errors https://github.com/iBotPeaches/Apktool/releases/download/v3.0.3/apktool_3.0.3.jar -o "$APKTOOL"
java -jar "$APKTOOL" d -f "$APK" -o "$WORK/proj" > "$OUT/apktool-decode.txt" 2>&1

# Search decoded resources/smali for exact and partial variants of the visible error.
python3 - "$WORK/proj" "$OUT" <<'PY'
import os,re,sys
root,out=sys.argv[1:]
terms=[
 'No se encontró ninguna secuencia de medios para reproducir',
 'No se encontro ninguna secuencia de medios para reproducir',
 'secuencia de medios', 'medios para reproducir',
 'media sequence', 'media sequences', 'sequence of media',
 'no media', 'media source', 'media sources'
]
hits=[]
for dp,_,fs in os.walk(root):
  for fn in fs:
    p=os.path.join(dp,fn)
    if not fn.endswith(('.xml','.smali','.json','.txt','.yml')): continue
    try:s=open(p,encoding='utf-8',errors='ignore').read()
    except:continue
    lo=s.lower()
    for t in terms:
      if t.lower() in lo:
        for m in re.finditer(re.escape(t),s,re.I):
          a=max(0,m.start()-1200); b=min(len(s),m.end()+1200)
          hits.append((p,t,s[a:b]))
          if len(hits)>200: break
      if len(hits)>200: break
    if len(hits)>200: break
  if len(hits)>200: break
with open(os.path.join(out,'decoded-message-hits.txt'),'w',encoding='utf-8') as w:
  for p,t,c in hits:
    w.write('\n===== %s | %s =====\n%s\n'%(p,t,c))
print('DECODED_HITS=%d'%len(hits))
PY

# JADX gives cleaner control-flow when decompilation succeeds.
curl -fL --retry 3 --retry-all-errors https://github.com/skylot/jadx/releases/download/v1.5.6/jadx-1.5.6.zip -o /tmp/jadx.zip
rm -rf /tmp/jadx && unzip -q /tmp/jadx.zip -d /tmp/jadx
/tmp/jadx/bin/jadx --show-bad-code -d "$OUT/jadx" "$APK" > "$OUT/jadx.log" 2>&1 || true

python3 - "$OUT/jadx" "$OUT" <<'PY'
import os,re,sys
root,out=sys.argv[1:]
terms=['secuencia de medios','medios para reproducir','media sequence','no media','media source','getMedias','StartPlayVOD','PlayAty']
with open(os.path.join(out,'jadx-vod-hits.txt'),'w',encoding='utf-8') as w:
  n=0
  for dp,_,fs in os.walk(root):
    for fn in fs:
      if not fn.endswith(('.java','.xml')): continue
      p=os.path.join(dp,fn)
      try:lines=open(p,encoding='utf-8',errors='ignore').read().splitlines()
      except:continue
      for i,line in enumerate(lines):
        if any(t.lower() in line.lower() for t in terms):
          n+=1
          w.write(f'\n===== {p}:{i+1} =====\n')
          for j in range(max(0,i-30),min(len(lines),i+31)):
            w.write(f'{j+1:05d}: {lines[j]}\n')
          if n>=160: break
      if n>=160: break
    if n>=160: break
print('JADX_CONTEXTS=%d'%n)
PY

# Find resource IDs of matching strings and then references to those IDs in smali.
python3 - "$WORK/proj" "$OUT" <<'PY'
import os,re,sys
root,out=sys.argv[1:]
strings=[]
for dp,_,fs in os.walk(os.path.join(root,'res')):
  for fn in fs:
    if not fn.endswith('.xml'): continue
    p=os.path.join(dp,fn)
    try:s=open(p,encoding='utf-8',errors='ignore').read()
    except:continue
    if 'secuencia de medios' in s.lower() or 'medios para reproducir' in s.lower() or 'media sequence' in s.lower():
      for m in re.finditer(r'<string\s+name="([^"]+)"[^>]*>(.*?)</string>',s,re.S):
        if any(x in m.group(2).lower() for x in ['secuencia de medios','medios para reproducir','media sequence']):
          strings.append((m.group(1),m.group(2),p))
with open(os.path.join(out,'matching-strings.txt'),'w',encoding='utf-8') as w:
  for x in strings:w.write(repr(x)+'\n')
# public.xml -> numeric IDs
pub=os.path.join(root,'res','values','public.xml')
ids=[]
if os.path.exists(pub):
  s=open(pub,encoding='utf-8',errors='ignore').read()
  for name,text,p in strings:
    m=re.search(r'<public type="string" name="'+re.escape(name)+r'" id="(0x[0-9a-fA-F]+)"',s)
    if m: ids.append((name,m.group(1)))
with open(os.path.join(out,'matching-resource-ids.txt'),'w') as w:
  for x in ids:w.write('%s %s\n'%x)
# references
with open(os.path.join(out,'resource-id-smali-context.txt'),'w',encoding='utf-8') as w:
  for name,rid in ids:
    for dp,_,fs in os.walk(root):
      if '/smali' not in dp.replace('\\','/'): continue
      for fn in fs:
        if not fn.endswith('.smali'):continue
        p=os.path.join(dp,fn)
        try:lines=open(p,encoding='utf-8',errors='ignore').read().splitlines()
        except:continue
        for i,line in enumerate(lines):
          if rid.lower() in line.lower():
            w.write(f'\n===== {name} {rid} {p}:{i+1} =====\n')
            for j in range(max(0,i-35),min(len(lines),i+36)):
              w.write(f'{j+1:05d}: {lines[j]}\n')
print('RESOURCE_IDS=%d'%len(ids))
PY

# Compact summary for Actions log.
{
 echo '=== MATCHING STRINGS ==='; cat "$OUT/matching-strings.txt" 2>/dev/null || true
 echo '=== RESOURCE IDS ==='; cat "$OUT/matching-resource-ids.txt" 2>/dev/null || true
 echo '=== DECODED HITS (head) ==='; head -180 "$OUT/decoded-message-hits.txt" 2>/dev/null || true
 echo '=== JADX HITS (head) ==='; head -500 "$OUT/jadx-vod-hits.txt" 2>/dev/null || true
 echo '=== RESOURCE REFS (head) ==='; head -500 "$OUT/resource-id-smali-context.txt" 2>/dev/null || true
} > "$OUT/summary.txt"
cat "$OUT/summary.txt"
