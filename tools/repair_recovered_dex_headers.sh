#!/usr/bin/env bash
set -euo pipefail
APK="${1:?apk path required}"
TMP='/tmp/xuper-dex-header-repair'
rm -rf "$TMP"; mkdir -p "$TMP"
(cd "$TMP" && unzip -q "$OLDPWD/$APK" 'classes*.dex')
python3 - "$TMP" <<'PY'
import glob, hashlib, os, struct, sys, zlib
root=sys.argv[1]
files=sorted(glob.glob(os.path.join(root,'classes*.dex')))
assert files
for p in files:
    b=bytearray(open(p,'rb').read())
    if len(b)<0x70 or not b.startswith(b'dex\n'):
        raise SystemExit(f'not dex: {p}')
    # DEX SHA-1 covers bytes 32..EOF; Adler32 covers bytes 12..EOF.
    b[12:32]=hashlib.sha1(b[32:]).digest()
    b[8:12]=struct.pack('<I', zlib.adler32(b[12:]) & 0xffffffff)
    open(p,'wb').write(b)
print(f'REPAIRED_DEX_HEADERS={len(files)}')
PY
# Existing APK signatures are intentionally invalidated here; the next patch step re-signs.
(cd "$TMP" && zip -q -u "$OLDPWD/$APK" classes*.dex)
echo 'RECOVERED_DEX_HEADERS_REPAIRED_OK'
