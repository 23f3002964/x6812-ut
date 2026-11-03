#!/usr/bin/env python3
"""Extract a gzip'd newc cpio initramfs, preserving symlinks as a json map."""
import gzip
import json
import os
import stat as statmod
import sys


def entries(buf):
    out = []
    i = 0
    while True:
        if buf[i:i + 6] not in (b"070701", b"070702"):
            break
        f = [buf[i + 6 + k * 8:i + 6 + (k + 1) * 8] for k in range(13)]
        mode = int(f[1], 16)
        filesize = int(f[6], 16)
        namesize = int(f[11], 16)
        name = buf[i + 110:i + 110 + namesize - 1].decode("utf-8", "replace")
        i += 110 + namesize
        i = (i + 3) & ~3
        data = buf[i:i + filesize]
        i += filesize
        i = (i + 3) & ~3
        if name == "TRAILER!!!":
            break
        out.append((name, mode, data))
    return out


def main():
    src, dst = sys.argv[1], sys.argv[2]
    raw = gzip.open(src, "rb").read()
    ents = entries(raw)
    os.makedirs(dst, exist_ok=True)
    symlinks = {}
    skipped = 0
    for name, mode, data in ents:
        safe = name.lstrip("/").replace("..", "_")
        if not safe:
            continue
        p = os.path.join(dst, safe)
        ftype = statmod.S_IFMT(mode)
        if name.endswith("/") or ftype == statmod.S_IFDIR:
            os.makedirs(p, exist_ok=True)
            continue
        d = os.path.dirname(p)
        if d:
            try:
                os.makedirs(d, exist_ok=True)
            except (FileExistsError, NotADirectoryError):
                skipped += 1
                continue
        if ftype == statmod.S_IFLNK:
            symlinks[name] = data.decode("utf-8", "replace")
            continue
        try:
            with open(p, "wb") as f:
                f.write(data)
        except OSError:
            skipped += 1
    with open(os.path.join(dst, "..", "symlinks.json"), "w", encoding="utf-8") as f:
        json.dump(symlinks, f, indent=1)
    print(f"extracted {len(ents)} entries -> {dst} (symlinks={len(symlinks)}, skipped={skipped})")


if __name__ == "__main__":
    main()
