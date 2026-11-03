#!/usr/bin/env python3
"""Unpack an Android boot image (header v0-v2) and extract its ramdisk (gzip/lz4/cpio)."""
import sys, os, struct, gzip, io, subprocess

def parse_boot(path):
    with open(path, 'rb') as f:
        data = f.read()
    assert data[:8] == b'ANDROID!', 'not an android boot image'
    hdr = {}
    hdr['kernel_size'] = struct.unpack_from('<I', data, 8)[0]
    hdr['kernel_addr'] = struct.unpack_from('<I', data, 12)[0]
    hdr['ramdisk_size'] = struct.unpack_from('<I', data, 16)[0]
    hdr['ramdisk_addr'] = struct.unpack_from('<I', data, 20)[0]
    hdr['second_size'] = struct.unpack_from('<I', data, 24)[0]
    hdr['second_addr'] = struct.unpack_from('<I', data, 28)[0]
    hdr['tags_addr'] = struct.unpack_from('<I', data, 32)[0]
    hdr['page_size'] = struct.unpack_from('<I', data, 36)[0]
    hdr['header_version'] = struct.unpack_from('<I', data, 40)[0]
    hdr['os_version'] = struct.unpack_from('<I', data, 44)[0]
    hdr['name'] = data[48:64].split(b'\x00')[0].decode('ascii', 'replace')
    ps = hdr['page_size']

    def pages(n):
        return (n + ps - 1) // ps

    off = ps
    kernel = data[off:off + hdr['kernel_size']]
    off += pages(hdr['kernel_size']) * ps
    ramdisk = data[off:off + hdr['ramdisk_size']]
    off += pages(hdr['ramdisk_size']) * ps
    second = data[off:off + hdr['second_size']]

    if hdr['header_version'] >= 2:
        # v2 adds dtb after second stage
        pass
    return hdr, kernel, ramdisk, second, data

def decompress(blob):
    if blob[:2] == b'\x1f\x8b':
        return gzip.decompress(blob), 'gzip'
    if blob[:4] == b'\x02\x21\x4c\x18' or blob[:4] == b'\x04\x22\x4d\x18':
        return None, 'lz4'
    if blob[:4] == b'\x28\xb5\x2f\xfd':
        return None, 'zstd'
    if blob[:6] == b'070701' or blob[:6] == b'070702':
        return blob, 'cpio(plain)'
    return None, 'unknown(%s)' % blob[:4].hex()

def cpio_entries(buf):
    """Parse newc cpio. Returns list of (name, mode, data)."""
    out = []
    i = 0
    while True:
        if buf[i:i+6] not in (b'070701', b'070702'):
            break
        fields = [buf[i+6+k*8:i+6+(k+1)*8] for k in range(13)]
        namesize = int(fields[11], 16)
        filesize = int(fields[6], 16)
        mode = int(fields[1], 16)
        base = i + 110
        name = buf[base:base+namesize-1].decode('utf-8', 'replace')
        i = base + namesize
        i = (i + 3) & ~3
        fdata = buf[i:i+filesize]
        i += filesize
        i = (i + 3) & ~3
        if name == 'TRAILER!!!':
            break
        out.append((name, mode, fdata))
    return out

def main():
    boot = sys.argv[1]
    outdir = sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    hdr, kernel, ramdisk, second, data = parse_boot(boot)
    print('== boot header ==')
    for k, v in hdr.items():
        print(f'  {k:16} = {v}')
    open(os.path.join(outdir, 'kernel.gz'), 'wb').write(kernel)
    open(os.path.join(outdir, 'ramdisk.raw'), 'wb').write(ramdisk)
    if second:
        open(os.path.join(outdir, 'second.bin'), 'wb').write(second)

    raw, kind = decompress(ramdisk)
    print(f'\n== ramdisk ==  size={len(ramdisk)} compression={kind}')
    if raw is None:
        print('  cannot decompress in pure python, left as ramdisk.raw')
        return
    entries = cpio_entries(raw)
    print(f'  cpio entries: {len(entries)}')
    root = os.path.join(outdir, 'ramdisk')
    os.makedirs(root, exist_ok=True)
    import stat as statmod
    symlinks = {}
    skipped = 0
    for name, mode, fdata in entries:
        safe = name.lstrip('/').replace('..', '_')
        if not safe:
            continue
        p = os.path.join(root, safe)
        ftype = statmod.S_IFMT(mode)
        if name.endswith('/') or ftype == statmod.S_IFDIR:
            try:
                os.makedirs(p, exist_ok=True)
            except (FileExistsError, NotADirectoryError):
                pass
            continue
        try:
            d = os.path.dirname(p)
            if d:
                os.makedirs(d, exist_ok=True)
        except (FileExistsError, NotADirectoryError):
            skipped += 1
            continue
        if ftype == statmod.S_IFLNK:
            symlinks[name] = fdata.decode('utf-8', 'replace')
            continue
        if os.path.isdir(p):
            skipped += 1
            continue
        try:
            with open(p, 'wb') as f:
                f.write(fdata)
        except OSError:
            skipped += 1
    import json
    if symlinks:
        with open(os.path.join(outdir, 'symlinks.json'), 'w', encoding='utf-8') as f:
            json.dump(symlinks, f, indent=1)
    print(f'  extracted to {root}  (symlinks={len(symlinks)}, skipped={skipped})')
    # quick listing of interesting files
    for name, mode, fdata in entries:
        n = name.lower()
        if any(x in n for x in ('fstab', 'init.rc', 'init.mt', 'ueventd', 'recovery.fstab')):
            print(f'    {name}  ({len(fdata)} bytes)')

if __name__ == '__main__':
    main()
