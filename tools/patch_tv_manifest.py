#!/usr/bin/env python3
import argparse
import io
import struct
import zipfile

RES_XML_START_ELEMENT_TYPE = 0x0102
TYPE_INT_DEC = 0x10


def u16(buf, off):
    return struct.unpack_from('<H', buf, off)[0]


def u32(buf, off):
    return struct.unpack_from('<I', buf, off)[0]


def put_u32(buf, off, value):
    struct.pack_into('<I', buf, off, value)


def read_string_pool(buf, off):
    header_size = u16(buf, off + 2)
    string_count = u32(buf, off + 8)
    flags = u32(buf, off + 16)
    strings_start = u32(buf, off + 20)
    offsets = [u32(buf, off + header_size + i * 4) for i in range(string_count)]
    base = off + strings_start
    utf8 = bool(flags & 0x100)
    out = []
    for rel in offsets:
        p = base + rel
        if utf8:
            c = buf[p]
            p += 2 if c & 0x80 else 1
            c = buf[p]
            p += 1
            if c & 0x80:
                byte_len = ((c & 0x7f) << 8) | buf[p]
                p += 1
            else:
                byte_len = c
            out.append(bytes(buf[p:p + byte_len]).decode('utf-8', 'replace'))
        else:
            length = u16(buf, p)
            p += 2
            if length & 0x8000:
                length = ((length & 0x7fff) << 16) | u16(buf, p)
                p += 2
            out.append(bytes(buf[p:p + length * 2]).decode('utf-16le', 'replace'))
    return out


def patch_manifest(data, orientation):
    buf = bytearray(data)
    strings = []
    off = 8
    changed = 0
    while off + 8 <= len(buf):
        chunk_type = u16(buf, off)
        chunk_size = u32(buf, off + 4)
        if chunk_size < 8:
            raise ValueError(f'Invalid chunk at 0x{off:x}')
        if chunk_type == 0x0001:
            strings = read_string_pool(buf, off)
        elif chunk_type == RES_XML_START_ELEMENT_TYPE and strings:
            ext = off + 16
            attr_start = u16(buf, ext + 8)
            attr_size = u16(buf, ext + 10)
            attr_count = u16(buf, ext + 12)
            first = ext + attr_start
            for i in range(attr_count):
                a = first + i * attr_size
                name_idx = u32(buf, a + 4)
                value_type = buf[a + 15]
                if name_idx < len(strings) and strings[name_idx] == 'screenOrientation' and value_type == TYPE_INT_DEC:
                    put_u32(buf, a + 16, orientation)
                    changed += 1
        off += chunk_size
    if changed == 0:
        raise ValueError('No screenOrientation attributes found')
    return bytes(buf), changed


def rewrite_apk(src, dst, orientation):
    with zipfile.ZipFile(src, 'r') as zin, zipfile.ZipFile(dst, 'w', allowZip64=True) as zout:
        manifest, changed = patch_manifest(zin.read('AndroidManifest.xml'), orientation)
        for item in zin.infolist():
            upper = item.filename.upper()
            if upper.startswith('META-INF/') and upper.endswith(('.RSA', '.DSA', '.EC', '.SF', 'MANIFEST.MF')):
                continue
            payload = manifest if item.filename == 'AndroidManifest.xml' else zin.read(item.filename)
            clone = zipfile.ZipInfo(item.filename, item.date_time)
            clone.compress_type = item.compress_type
            clone.comment = item.comment
            clone.extra = item.extra
            clone.create_system = item.create_system
            clone.external_attr = item.external_attr
            clone.internal_attr = item.internal_attr
            clone.flag_bits = item.flag_bits
            zout.writestr(clone, payload)
    return changed


def main():
    p = argparse.ArgumentParser()
    p.add_argument('src')
    p.add_argument('dst')
    p.add_argument('--orientation', type=int, default=4,
                   help='Android screenOrientation enum. 4=sensor, 1=portrait, 0=landscape')
    args = p.parse_args()
    changed = rewrite_apk(args.src, args.dst, args.orientation)
    print(f'Patched {changed} screenOrientation attributes to {args.orientation}.')


if __name__ == '__main__':
    main()
