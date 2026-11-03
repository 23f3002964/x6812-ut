#!/usr/bin/env python3
"""Replace the content of one file inside a newc cpio initramfs, keeping every
other entry's metadata (mode, uid, gid, mtime, rdev) byte-identical.

Usage: patch_initramfs.py <src.gz> <dst.gz> <entry-name> <new-content-file>
"""
import gzip
import sys


def read_entries(buf):
    out = []
    i = 0
    while True:
        if buf[i:i + 6] not in (b"070701", b"070702"):
            break
        raw = [buf[i + 6 + k * 8:i + 6 + (k + 1) * 8] for k in range(13)]
        fields = [int(x, 16) for x in raw]
        namesize = fields[11]
        filesize = fields[6]
        name = buf[i + 110:i + 110 + namesize - 1].decode("utf-8", "replace")
        i += 110 + namesize
        i = (i + 3) & ~3
        data = buf[i:i + filesize]
        i += filesize
        i = (i + 3) & ~3
        if name == "TRAILER!!!":
            break
        out.append({"fields": fields, "name": name, "data": data})
    return out


def emit(entries):
    parts = []
    for e in entries:
        f = list(e["fields"])
        # keep the original ino: hardlinked entries share it and must stay equal
        f[6] = len(e["data"])  # filesize
        name_b = e["name"].encode() + b"\x00"
        f[11] = len(name_b)
        hdr = b"070701" + b"".join(b"%08X" % x for x in f)
        parts.append(hdr)
        parts.append(name_b)
        pad = (-len(hdr) - len(name_b)) % 4
        parts.append(b"\x00" * pad)
        parts.append(e["data"])
        parts.append(b"\x00" * ((-len(e["data"])) % 4))
    # trailer
    name_b = b"TRAILER!!!\x00"
    f = [0] * 13
    f[0] = len(entries) + 1
    f[11] = len(name_b)
    hdr = b"070701" + b"".join(b"%08X" % x for x in f)
    parts.append(hdr)
    parts.append(name_b)
    parts.append(b"\x00" * ((-len(hdr) - len(name_b)) % 4))
    return b"".join(parts)


def main():
    src, dst, entry, content = sys.argv[1:5]
    raw = gzip.decompress(open(src, "rb").read())
    entries = read_entries(raw)
    new_data = open(content, "rb").read()
    hit = 0
    for e in entries:
        if e["name"] == entry:
            print(f"replacing {entry}: {len(e['data'])} -> {len(new_data)} bytes")
            e["data"] = new_data
            hit += 1
    if not hit:
        raise SystemExit(f"entry {entry!r} not found")
    out = emit(entries)
    with open(dst, "wb") as raw_out:
        with gzip.GzipFile(fileobj=raw_out, mode="wb", compresslevel=9, mtime=0) as f:
            f.write(out)
    print(f"wrote {dst}: {len(entries)} entries, {len(out)} bytes uncompressed")


if __name__ == "__main__":
    main()
