#!/usr/bin/env python3
"""Compare a newly built boot image against the stock one it was derived from.

Checks the Android boot header fields and the sha256 of every section that must
stay bit-identical (kernel, dtb). The ramdisk is expected to differ.
"""
import hashlib
import struct
import sys


def sha(b):
    return hashlib.sha256(b).hexdigest().upper()


def parse(path):
    with open(path, "rb") as f:
        data = f.read()
    assert data[:8] == b"ANDROID!", path
    h = {}
    (h["kernel_size"], h["kernel_addr"], h["ramdisk_size"], h["ramdisk_addr"],
     h["second_size"], h["second_addr"], h["tags_addr"], h["page_size"],
     h["header_version"], h["os_version"]) = struct.unpack_from("<10I", data, 8)
    h["name"] = data[48:64].split(b"\x00")[0].decode("ascii", "replace")
    h["cmdline"] = data[64:576].split(b"\x00")[0].decode("ascii", "replace")
    h["extra_cmdline"] = data[608:1632].split(b"\x00")[0].decode("ascii", "replace")
    h["recovery_dtbo_size"] = struct.unpack_from("<I", data, 1632)[0]
    h["header_size"] = struct.unpack_from("<I", data, 1644)[0]
    h["dtb_size"] = struct.unpack_from("<I", data, 1648)[0]
    h["dtb_addr"] = struct.unpack_from("<Q", data, 1652)[0]
    h["file_size"] = len(data)

    ps = h["page_size"]
    def pages(n):
        return (n + ps - 1) // ps

    off = ps
    h["kernel"] = data[off:off + h["kernel_size"]]
    off += pages(h["kernel_size"]) * ps
    h["ramdisk"] = data[off:off + h["ramdisk_size"]]
    off += pages(h["ramdisk_size"]) * ps
    if h["header_version"] >= 2:
        h["dtb"] = data[off:off + h["dtb_size"]]
    else:
        h["dtb"] = b""
    return h


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    allow_cmdline = "--allow-cmdline" in sys.argv

    stock = parse(args[0])
    new = parse(args[1])

    fields = ["kernel_addr", "ramdisk_addr", "tags_addr", "page_size",
              "header_version", "os_version", "name", "cmdline",
              "extra_cmdline", "dtb_addr", "dtb_size", "second_size",
              "second_addr", "recovery_dtbo_size"]
    intentional = {"cmdline", "extra_cmdline"} if allow_cmdline else set()
    ok = True
    print(f"{'field':20} {'stock':>14} {'new':>14}  status")
    print("-" * 62)
    for f in fields:
        a, b = stock[f], new[f]
        same = a == b
        ok &= same or f in intentional
        status = "OK" if same else ("DIFF (allowed)" if f in intentional else "DIFF")
        print(f"{f:20} {str(a):>14} {str(b):>14}  {status}")

    print()
    for name in ("kernel", "dtb"):
        a, b = stock[name], new[name]
        same = a == b
        ok &= same
        print(f"{name:8} stock {len(a):>9} B {sha(a)}")
        print(f"{name:8} new   {len(b):>9} B {sha(b)}  -> {'IDENTICAL' if same else 'DIFFERENT'}")

    print()
    print(f"ramdisk  stock {stock['ramdisk_size']:>9} B {sha(stock['ramdisk'])}")
    print(f"ramdisk  new   {new['ramdisk_size']:>9} B {sha(new['ramdisk'])}")
    print(f"\nfile size stock {stock['file_size']} / new {new['file_size']}")
    print("\nRESULT:", "PASS - safe to flash" if ok else "FAIL - do not flash")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
