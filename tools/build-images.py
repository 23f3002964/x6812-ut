#!/usr/bin/env python3
"""Rebuild every boot artifact in one step, from tracked inputs.

    python tools/build-images.py

Inputs (tracked):
    tools/initramfs/halium-initramfs.gz          pristine Halium initramfs
    tools/initramfs/patched/init                 tmpfs /dev + /dev/kmsg (no CONFIG_DEVTMPFS)
    tools/initramfs/patched/scripts/halium        boot log on data part, resize guard
    out/stock-boot_a.img                         stock boot image (kernel + DTB)

Outputs:
    out/halium-initramfs-x6812.gz                the ramdisk
    out/halium-boot.img                          boot_a for a real install
    out/halium-boot-sd.img                       same, cmdline datapart=/dev/mmcblk1

Only the ramdisk and the cmdline differ from stock; kernel and DTB are copied
byte for byte. Verify afterwards with:

    python tools/verify_boot.py --allow-cmdline out/stock-boot_a.img out/halium-boot.img
"""
import hashlib
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

PRISTINE = os.path.join(HERE, "initramfs", "halium-initramfs.gz")
PATCH_INIT = os.path.join(HERE, "initramfs", "patched", "init")
PATCH_HALIUM = os.path.join(HERE, "initramfs", "patched", "scripts", "halium")
STOCK = os.path.join(ROOT, "out", "stock-boot_a.img")

RAMDISK = os.path.join(ROOT, "out", "halium-initramfs-x6812.gz")
BOOT = os.path.join(ROOT, "out", "halium-boot.img")
BOOT_SD = os.path.join(ROOT, "out", "halium-boot-sd.img")
STEP1 = os.path.join(ROOT, "out", "_initramfs-step1.gz")

# The cmdline the stock image carries, plus the words Halium needs.
#
# Security note: this vendor kernel is built without
# CONFIG_SECURITY_SELINUX_BOOTPARAM / _DEVELOP / _DISABLE, so
# androidboot.selinux= is compiled out and /sys/fs/selinux/enforce is
# read-only (setenforce fails with EACCES). The unguarded kernel parameter
# "enforcing=" (security/selinux/hooks.c, __setup) still works and keeps the
# kernel permissive even after a policy is loaded, which is what the Android
# container needs when it is started straight into second_stage.
CMDLINE = ("bootopt=64S3,32N2,64N2 buildvariant=user "
           "androidboot.hardware=mt6768 "
           "androidboot.selinux=permissive enforcing=0 "
           "androidboot.slot_suffix=_a androidboot.slot=a")
SD_CMDLINE = CMDLINE + " datapart=/dev/mmcblk1"


def run(*args):
    cmd = [sys.executable] + list(args)
    print("$ " + " ".join(os.path.basename(a) if a.endswith(".py") else a for a in cmd[1:]))
    subprocess.run(cmd, check=True)


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    for p in (PRISTINE, PATCH_INIT, PATCH_HALIUM, STOCK):
        if not os.path.exists(p):
            raise SystemExit("missing input: " + p)

    patch = os.path.join(HERE, "patch_initramfs.py")
    build = os.path.join(HERE, "build-boot.py")

    run(patch, PRISTINE, STEP1, "init", PATCH_INIT)
    run(patch, STEP1, RAMDISK, "scripts/halium", PATCH_HALIUM)
    os.remove(STEP1)

    run(build, "--base", STOCK, "--ramdisk", RAMDISK, "--cmdline", CMDLINE, "--out", BOOT)
    run(build, "--base", STOCK, "--ramdisk", RAMDISK, "--cmdline", SD_CMDLINE, "--out", BOOT_SD)

    print("")
    for p in (RAMDISK, BOOT, BOOT_SD):
        print("%-34s %10d B  %s" % (os.path.relpath(p, ROOT), os.path.getsize(p), sha(p)))


if __name__ == "__main__":
    main()
