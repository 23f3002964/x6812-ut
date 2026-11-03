#!/usr/bin/env python3
"""Read files out of an ext4 filesystem - local image or a live block device.

The X6812 has no working pstore, so the Halium initramfs and a systemd unit
write the boot log to the data partition (which is ext4).  Reading it back
should not require pulling 12 GB over USB, so this tool fetches only the
blocks it needs, either from a local image or through `adb exec-out dd`.

    python tools/ext4-get.py --image out/rootfs/merlin-dev/.../android-rootfs.img list /
    python tools/ext4-get.py --adb /dev/block/mmcblk1 cat /x6812-boot.log
"""
import argparse
import struct
import subprocess
import sys


class FileReader:
    def __init__(self, path):
        self.f = open(path, "rb")

    def read(self, off, n):
        self.f.seek(off)
        return self.f.read(n)


class AdbReader:
    """Block-addressed reader over `adb exec-out dd`, with a cache."""

    def __init__(self, dev, bs=4096):
        self.dev = dev
        self.bs = bs
        self.cache = {}
        self.fetched = 0

    def read(self, off, n):
        bs = self.bs
        first = off // bs
        last = (off + n + bs - 1) // bs
        out = bytearray()
        for blk in range(first, last):
            if blk not in self.cache:
                cmd = f"dd if={self.dev} bs={bs} skip={blk} count=1 2>/dev/null"
                p = subprocess.run(["adb", "exec-out", cmd], capture_output=True)
                data = p.stdout
                if len(data) < bs:
                    data += b"\0" * (bs - len(data))
                self.cache[blk] = data
                self.fetched += 1
            out += self.cache[blk]
        start = off - first * bs
        return bytes(out[start:start + n])


class Ext4:
    def __init__(self, reader):
        self.r = reader
        sb = reader.read(1024, 1024)
        magic = struct.unpack_from("<H", sb, 0x38)[0]
        if magic != 0xEF53:
            raise SystemExit("not an ext4 filesystem (bad superblock magic)")
        self.bs = 1024 << struct.unpack_from("<I", sb, 0x18)[0]
        self.first_data = struct.unpack_from("<I", sb, 0x14)[0]
        self.ipg = struct.unpack_from("<I", sb, 0x28)[0]
        self.isize = struct.unpack_from("<H", sb, 0x58)[0] or 128
        self.desc_size = max(32, struct.unpack_from("<H", sb, 0xFE)[0])
        self.gdt = (self.first_data + 1) * self.bs

    # -- inodes ---------------------------------------------------------
    def inode_off(self, ino):
        grp = (ino - 1) // self.ipg
        idx = (ino - 1) % self.ipg
        itab = struct.unpack_from("<I", self.r.read(self.gdt + grp * self.desc_size + 8, 4))[0]
        return itab * self.bs + idx * self.isize

    def inode(self, ino):
        raw = self.r.read(self.inode_off(ino), self.isize)
        mode = struct.unpack_from("<H", raw, 0)[0]
        size = struct.unpack_from("<I", raw, 4)[0]
        flags = struct.unpack_from("<I", raw, 0x20)[0]
        blocks = list(struct.unpack_from("<15I", raw, 0x28))
        if mode & 0xF000 == 0x8000:
            size |= struct.unpack_from("<I", raw, 0x6C)[0] << 32
        return {"ino": ino, "mode": mode, "size": size, "flags": flags,
                "blocks": blocks, "raw": raw}

    # -- file data ------------------------------------------------------
    def _extent_runs(self, node_off):
        runs = []
        hdr = self.r.read(node_off, 12)
        magic, entries, _max, depth = struct.unpack_from("<HHHH", hdr, 0)
        if magic != 0xF30A:
            return None
        body = self.r.read(node_off + 12, entries * 12)
        for i in range(entries):
            e = body[i * 12:(i + 1) * 12]
            if depth == 0:
                lb, ln, hi, lo = struct.unpack("<IHHI", e)
                unwritten = ln > 32768
                ln = ln - 32768 if unwritten else ln
                runs.append((lb, (hi << 32) | lo, ln))
            else:
                _lb, lo, hi = struct.unpack_from("<IIH", e, 0)
                child = (hi << 32) | lo
                sub = self._extent_runs(child * self.bs)
                if sub:
                    runs.extend(sub)
        return runs

    def read_file(self, ino):
        node = self.inode(ino)
        size = node["size"]
        if node["flags"] & 0x10000000:  # inline data
            return node["raw"][0x28:0x28 + size]
        if node["mode"] & 0xF000 == 0xA000 and size <= 60 and node["blocks"][0] & 0xFFFF != 0xF30A:
            return node["raw"][0x28:0x28 + size]
        runs = self._extent_runs(self.inode_off(ino) + 0x28)
        data = bytearray()
        if runs is None:
            # classic block map: 12 direct + single indirect
            for blk in node["blocks"][:12]:
                if blk:
                    data += self.r.read(blk * self.bs, self.bs)
            if node["blocks"][12]:
                ptrs = struct.unpack_from("<%dI" % (self.bs // 4),
                                          self.r.read(node["blocks"][12] * self.bs, self.bs))
                for blk in ptrs:
                    if blk:
                        data += self.r.read(blk * self.bs, self.bs)
        else:
            for _lb, phys, ln in sorted(runs):
                data += self.r.read(phys * self.bs, ln * self.bs)
        return bytes(data[:size])

    # -- directories and paths -----------------------------------------
    def listdir(self, ino):
        data = self.read_file(ino)
        out = []
        off = 0
        while off + 8 <= len(data):
            e_ino, rec_len = struct.unpack_from("<IH", data, off)
            name_len, ftype = data[off + 6], data[off + 7]
            if rec_len < 8:
                break
            if e_ino:
                name = data[off + 8:off + 8 + name_len].decode("utf-8", "replace")
                out.append((name, ftype, e_ino))
            off += rec_len
        return out

    def resolve(self, path, depth=0):
        if depth > 8:
            raise SystemExit(f"too many levels of symbolic links: {path}")
        parts = [p for p in path.split("/") if p and p != "."]
        ino = 2
        prefix = []
        for i, part in enumerate(parts):
            if part == "..":
                prefix = prefix[:-1]
                ino = self.resolve("/" + "/".join(prefix)) if prefix else 2
                continue
            hit = None
            for name, _ft, e_ino in self.listdir(ino):
                if name == part:
                    hit = e_ino
                    break
            if hit is None:
                raise SystemExit(f"no such file or directory: {path} (at {part})")
            node = self.inode(hit)
            if node["mode"] & 0xF000 == 0xA000:
                target = self.read_file(hit).decode("utf-8", "replace")
                base = "/" + "/".join(prefix)
                if not target.startswith("/"):
                    target = base.rstrip("/") + "/" + target
                rest = "/".join(parts[i + 1:])
                return self.resolve(target + ("/" + rest if rest else ""), depth + 1)
            prefix.append(part)
            ino = hit
        return ino


def main():
    ap = argparse.ArgumentParser()
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--image", help="local ext4 image")
    src.add_argument("--adb", help="block device on the phone, e.g. /dev/block/mmcblk1")
    ap.add_argument("--bs", type=int, default=4096, help="adb read block size")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p_ls = sub.add_parser("list")
    p_ls.add_argument("path", nargs="?", default="/")
    p_cat = sub.add_parser("cat")
    p_cat.add_argument("path")
    p_stat = sub.add_parser("stat")
    p_stat.add_argument("path")
    args = ap.parse_args()

    reader = FileReader(args.image) if args.image else AdbReader(args.adb, args.bs)
    fs = Ext4(reader)
    ino = fs.resolve(args.path)

    if args.cmd == "list":
        for name, ftype, e_ino in fs.listdir(ino):
            print(f"{'d' if ftype == 2 else '-'} {e_ino:>8}  {name}")
    elif args.cmd == "stat":
        node = fs.inode(ino)
        print(f"inode {node['ino']} mode {oct(node['mode'])} size {node['size']} bytes")
    else:
        data = fs.read_file(ino)
        sys.stdout.buffer.write(data)


if __name__ == "__main__":
    main()
