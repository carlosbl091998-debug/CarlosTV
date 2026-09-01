#!/usr/bin/env bash
set -euo pipefail
APK="${1:?apk path required}"
TMP='/tmp/xuper-dex-header-repair'
rm -rf "$TMP"; mkdir -p "$TMP"
(cd "$TMP" && unzip -q "$OLDPWD/$APK" 'classes*.dex')
python3 - "$TMP" <<'PY'
import glob, hashlib, os, re, struct, sys, zlib
root=sys.argv[1]

def dex_index(path):
    name=os.path.basename(path)
    m=re.fullmatch(r'classes(\d*)\.dex', name)
    if not m:
        return 10**9
    return 1 if m.group(1)=='' else int(m.group(1))

files=sorted(glob.glob(os.path.join(root,'classes*.dex')), key=dex_index)
assert files
valid=[]
rejected=[]
for p in files:
    b=bytearray(open(p,'rb').read())
    reason=None
    if len(b)<0x70 or not b.startswith(b'dex\n'):
        reason='bad magic/header'
    else:
        file_size=struct.unpack_from('<I', b, 0x20)[0]
        map_off=struct.unpack_from('<I', b, 0x34)[0]
        if file_size != len(b):
            reason=f'file_size={file_size} actual={len(b)}'
        elif map_off+4 > len(b):
            reason=f'map_off=0x{map_off:x} outside file'
        else:
            map_size=struct.unpack_from('<I', b, map_off)[0]
            if map_off+4+map_size*12 > len(b):
                reason=f'map list overrun: off=0x{map_off:x} size={map_size}'
    if reason:
        rejected.append((p,reason))
        continue
    # DEX SHA-1 covers bytes 32..EOF; Adler32 covers bytes 12..EOF.
    b[12:32]=hashlib.sha1(b[32:]).digest()
    b[8:12]=struct.pack('<I', zlib.adler32(b[12:]) & 0xffffffff)
    open(p,'wb').write(b)
    valid.append(p)

if not valid:
    raise SystemExit('no structurally valid dex files remain')

# Remove invalid recovered dumps and make the multidex sequence contiguous. ART stops
# scanning at malformed early entries, which previously hid SplashAty in later DEX files.
stage=os.path.join(root,'stage')
os.makedirs(stage, exist_ok=True)
for i,p in enumerate(valid, start=1):
    name='classes.dex' if i==1 else f'classes{i}.dex'
    os.replace(p, os.path.join(stage,name))

with open(os.path.join(root,'dex-prune-report.txt'),'w') as f:
    f.write(f'VALID={len(valid)}\nREJECTED={len(rejected)}\n')
    for p,reason in rejected:
        f.write(f'REJECT {os.path.basename(p)}: {reason}\n')
print(f'REPAIRED_VALID_DEX={len(valid)} REJECTED_INVALID_DEX={len(rejected)}')
for p,reason in rejected:
    print(f'REJECT {os.path.basename(p)}: {reason}')
PY
# Existing APK signatures are intentionally invalidated here; the next patch step re-signs.
zip -q -d "$APK" 'classes*.dex' || true
(cd "$TMP/stage" && zip -q "$OLDPWD/$APK" classes*.dex)
cp "$TMP/dex-prune-report.txt" "$(dirname "$APK")/dex-prune-report.txt"
echo 'RECOVERED_DEX_HEADERS_REPAIRED_AND_INVALID_PRUNED_OK'
