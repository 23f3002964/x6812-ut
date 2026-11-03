#!/usr/bin/env python3
"""Print modinfo fields (depends, vermagic, name) for .ko files without modinfo.

    python tools/modinfo.py device/infinix/X6812/prebuilt/modules/*.ko
"""
import struct
import sys
import os

SHT_STRTAB = 3


def sections(data):
    if data[:4] != b"\x7fELF":
        raise SystemExit("not an ELF file")
    is64 = data[4] == 2
    if is64:
        e_shoff = struct.unpack_from("<Q", data, 0x28)[0]
        e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", data, 0x3A)
        fmt = "<IIQQQQIIQQ"
    else:
        e_shoff = struct.unpack_from("<I", data, 0x20)[0]
        e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", data, 0x2E)
        fmt = "<IIIIIIIIII"
    raw = []
    for i in range(e_shnum):
        f = struct.unpack_from(fmt, data, e_shoff + i * e_shentsize)
        raw.append({"name_off": f[0], "type": f[1], "offset": f[4], "size": f[5]})
    strtab = raw[e_shstrndx]
    names = data[strtab["offset"]:strtab["offset"] + strtab["size"]]
    for s in raw:
        end = names.find(b"\0", s["name_off"])
        s["name"] = names[s["name_off"]:end].decode("ascii", "replace")
    return raw


def modinfo(path):
    data = open(path, "rb").read()
    out = {}
    for s in sections(data):
        # .modinfo is SHT_PROGBITS in kernel modules, not a strtab
        if s["name"] == ".modinfo":
            blob = data[s["offset"]:s["offset"] + s["size"]]
            for item in blob.split(b"\0"):
                if b"=" in item:
                    k, v = item.split(b"=", 1)
                    out[k.decode()] = v.decode("ascii", "replace")
    return out


def main():
    for path in sys.argv[1:]:
        mi = modinfo(path)
        print("%-22s depends=%-28s vermagic=%s" % (
            os.path.basename(path), mi.get("depends", "") or "-", mi.get("vermagic", "?")))


if __name__ == "__main__":
    main()
