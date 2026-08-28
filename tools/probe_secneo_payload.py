#!/usr/bin/env python3
import hashlib, math, os, struct, sys, zipfile

apk_path, runtime_path, out_dir = sys.argv[1:4]
os.makedirs(out_dir, exist_ok=True)

def sha256(b): return hashlib.sha256(b).hexdigest()
def entropy(b):
    if not b: return 0.0
    from collections import Counter
    n=len(b); c=Counter(b)
    return -sum((v/n)*math.log2(v/n) for v in c.values())

runtime=open(runtime_path,'rb').read()
rt_head=runtime[:4096]
rt_mid=runtime[len(runtime)//2:len(runtime)//2+4096]
rt_tail=runtime[-4096:]

lines=[]
lines.append(f'RUNTIME_SIZE={len(runtime)}')
lines.append(f'RUNTIME_SHA256={sha256(runtime)}')
lines.append(f'RUNTIME_ENTROPY={entropy(runtime):.4f}')

apk=open(apk_path,'rb').read()
lines.append(f'APK_SIZE={len(apk)}')
lines.append(f'APK_SHA256={sha256(apk)}')
for name, chunk in [('HEAD4K',rt_head),('MID4K',rt_mid),('TAIL4K',rt_tail),('HEAD512',runtime[:512]),('TAIL512',runtime[-512:])]:
    pos=apk.find(chunk)
    lines.append(f'APK_MATCH_{name}={pos}')

with zipfile.ZipFile(apk_path) as z:
    entries=[]
    for zi in z.infolist():
        data=z.read(zi.filename)
        ent=entropy(data[:min(len(data), 2_000_000)]) if data else 0.0
        hit_head=data.find(rt_head)
        hit_head512=data.find(runtime[:512])
        dex_magic=[]
        start=0
        while True:
            p=data.find(b'dex\n', start)
            if p<0: break
            dex_magic.append(p); start=p+1
        entries.append((zi.filename,len(data),zi.compress_type,ent,hit_head,hit_head512,dex_magic[:20]))
    with open(os.path.join(out_dir,'zip_entries.tsv'),'w',encoding='utf-8') as f:
        f.write('name\tsize\tcompress_type\tentropy_sample\truntime_head4k\truntime_head512\tdex_magic_offsets\n')
        for e in entries:
            f.write('\t'.join(map(str,e))+'\n')
    for e in entries:
        if e[4] >= 0 or e[5] >= 0 or e[6]:
            lines.append('ENTRY_INTERESTING=' + repr(e))

# classes.dex declared vs physical payload characteristics
with zipfile.ZipFile(apk_path) as z:
    if 'classes.dex' in z.namelist():
        c=z.read('classes.dex')
        lines.append(f'CLASSES_DEX_SIZE={len(c)}')
        if c.startswith(b'dex\n') and len(c)>=36:
            declared=struct.unpack_from('<I',c,32)[0]
            lines.append(f'CLASSES_DEX_DECLARED_FILE_SIZE={declared}')
            lines.append(f'CLASSES_DEX_TRAILING_BYTES={max(0,len(c)-declared)}')
            if len(c)>declared:
                tail=c[declared:]
                lines.append(f'CLASSES_DEX_TRAIL_ENTROPY={entropy(tail[:min(len(tail),2_000_000)]):.4f}')
                lines.append(f'CLASSES_DEX_TRAIL_SHA256={sha256(tail)}')
                for name,chunk in [('RT_HEAD4K',rt_head),('RT_HEAD512',runtime[:512]),('RT_TAIL512',runtime[-512:])]:
                    lines.append(f'CLASSES_DEX_TRAIL_MATCH_{name}={tail.find(chunk)}')
                with open(os.path.join(out_dir,'classes_dex_trailing.bin'),'wb') as f: f.write(tail)

open(os.path.join(out_dir,'summary.txt'),'w',encoding='utf-8').write('\n'.join(lines)+'\n')
print('\n'.join(lines))
