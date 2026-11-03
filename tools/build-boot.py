#!/usr/bin/env python3
"""Rebuild an Android boot image in place, keeping the kernel and DTB.

The X6812 port only ever changes the ramdisk (Halium initramfs) and the kernel
cmdline, so instead of re-deriving every mkbootimg argument we keep the
original header, kernel and DTB byte-for-byte and swap the ramdisk.

    python tools/build-boot.py --base out/stock-boot_a.img \
        --ramdisk out/halium-initramfs-x6812.gz \
        --cmdline "bootopt=64S3,32N2,64N2 buildvariant=user androidboot.hardware=mt6768 ..." \
        --out out/halium-boot.img

    # add one word to the existing cmdline of a boot image
    python tools/build-boot.py --base out/halium-boot.img \
        --add-cmdline datapart=/dev/mmcblk1 --out out/halium-boot-sd.img
"""
import argparse
import hashlib
import struct
import sys

MAGIC = b"ANDROID!"
HDR_KERNEL_SIZE = 0x08
HDR_RAMDISK_SIZE = 0x10
HDR_PAGE_SIZE = 0x24
HDR_HEADER_VERSION = 0x28
HDR_NAME = 0x30
HDR_NAME_LEN = 16
HDR_CMDLINE = 0x40
HDR_CMDLINE_LEN = 512


def align(n, page):
    return (n + page - 1) // page * page


def parse_header(data):
    if data[:8] != MAGIC:
        raise SystemExit("not an Android boot image (bad magic)")
    u32 = lambda off: struct.unpack_from("<I", data, off)[0]
    hdr = {
        "kernel_size": u32(HDR_KERNEL_SIZE),
        "ramdisk_size": u32(HDR_RAMDISK_SIZE),
        "page_size": u32(HDR_PAGE_SIZE),
        "header_version": u32(HDR_HEADER_VERSION),
        "name": data[HDR_NAME:HDR_NAME + HDR_NAME_LEN].split(b"\0")[0].decode("ascii", "replace"),
        "cmdline": data[HDR_CMDLINE:HDR_CMDLINE + HDR_CMDLINE_LEN].split(b"\0")[0].decode("ascii", "replace"),
    }
    return hdr


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True, help="boot image to copy the kernel/DTB from")
    ap.add_argument("--out", required=True, help="output boot image")
    ap.add_argument("--ramdisk", help="new ramdisk (gzip cpio); default: base ramdisk")
    ap.add_argument("--cmdline", help="replace the kernel cmdline")
    ap.add_argument("--add-cmdline", action="append", default=[],
                    help="append words to the cmdline (repeatable)")
    args = ap.parse_args()

    data = bytearray(open(args.base, "rb").read())
    hdr = parse_header(data)
    ps = hdr["page_size"]
    if hdr["header_version"] not in (0, 1, 2):
        raise SystemExit(f"unsupported header version {hdr['header_version']}")

    k_off = ps
    r_off = k_off + align(hdr["kernel_size"], ps)
    d_off = r_off + align(hdr["ramdisk_size"], ps)

    kernel = bytes(data[k_off:k_off + hdr["kernel_size"]])
    if len(kernel) != hdr["kernel_size"]:
        raise SystemExit("base image is truncated in the kernel section")

    if args.ramdisk:
        ramdisk = open(args.ramdisk, "rb").read()
    else:
        ramdisk = bytes(data[r_off:r_off + hdr["ramdisk_size"]])
    if len(ramdisk) != (len(ramdisk) if args.ramdisk else hdr["ramdisk_size"]):
        raise SystemExit("base image is truncated in the ramdisk section")

    # Header v2 stores dtb_size at 0x670 (after recovery_dtbo_size/offset and
    # header_size). v0/v1 images have no DTB section.
    if hdr["header_version"] >= 2:
        dtb_size = struct.unpack_from("<I", data, 0x670)[0]
        if dtb_size and d_off + dtb_size > len(data):
            raise SystemExit("base image is truncated in the DTB section")
        dtb = bytes(data[d_off:d_off + dtb_size])
    else:
        dtb = b""

    cmdline = hdr["cmdline"]
    if args.cmdline:
        cmdline = args.cmdline.strip() + " "
    elif args.add_cmdline:
        cmdline = cmdline.rstrip() + " "
    for extra in args.add_cmdline:
        extra = extra.strip()
        if extra and extra not in cmdline.split():
            cmdline += extra + " "
    cmdline = cmdline.strip()

    if len(cmdline.encode()) >= HDR_CMDLINE_LEN:
        raise SystemExit(f"cmdline too long for the v{hdr['header_version']} header: {len(cmdline)} bytes")

    out = bytearray()
    out += data[:ps]                                  # header page, patched below
    out += kernel + b"\0" * (align(len(kernel), ps) - len(kernel))
    out += ramdisk + b"\0" * (align(len(ramdisk), ps) - len(ramdisk))
    if dtb:
        out += dtb + b"\0" * (align(len(dtb), ps) - len(dtb))

    struct.pack_into("<I", out, HDR_RAMDISK_SIZE, len(ramdisk))
    out[HDR_CMDLINE:HDR_CMDLINE + HDR_CMDLINE_LEN] = cmdline.encode().ljust(HDR_CMDLINE_LEN, b"\0")

    open(args.out, "wb").write(out)
    sha = hashlib.sha256(out).hexdigest()
    print(f"wrote {args.out}")
    print(f"  size        {len(out)} B")
    print(f"  kernel      {len(kernel)} B  (from {args.base})")
    print(f"  ramdisk     {len(ramdisk)} B")
    print(f"  dtb         {len(dtb)} B")
    print(f"  cmdline     {cmdline}")
    print(f"  sha256      {sha}")


if __name__ == "__main__":
    sys.exit(main())
