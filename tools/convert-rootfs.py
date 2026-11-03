#!/usr/bin/env python3
"""Recompress the Ubuntu Touch rootfs tarball from .tar.xz to .tar.gz.

The phone's toybox tar can only decompress gzip/bzip2 itself; for xz it tries
to exec an `xz` binary, which the Android 11 system does not ship. Decompressing
on Windows keeps every bit of metadata (uid, gid, mode, symlinks, device nodes,
hardlinks) intact, which a filesystem-level extraction on Windows would not.

Usage:
    python tools/convert-rootfs.py [src.tar.xz] [dst.tar.gz]
"""
import os
import sys
import tarfile
import time

src = sys.argv[1] if len(sys.argv) > 1 else r"out\rootfs\focal-arm64-rootfs.tar.xz"
dst = sys.argv[2] if len(sys.argv) > 2 else r"out\rootfs\focal-arm64-rootfs.tar.gz"

if not os.path.exists(src):
    sys.exit(f"missing {src}")

start = time.time()
count = 0

# compresslevel=1 keeps the conversion fast; the phone decompresses it once.
with tarfile.open(src, "r:xz") as ti, tarfile.open(dst, "w:gz", compresslevel=1) as to:
    for m in ti:
        f = ti.extractfile(m) if m.isreg() else None
        to.addfile(m, f)
        count += 1
        if count % 5000 == 0:
            print(f"  {count} members, {time.time() - start:.0f}s", flush=True)

print(f"done: {count} members -> {dst} ({os.path.getsize(dst)} bytes, {time.time() - start:.0f}s)")
