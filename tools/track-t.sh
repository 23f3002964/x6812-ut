#!/system/bin/sh
# Track T: prepare a microSD card for a non-destructive Ubuntu Touch test boot.
#
#   sh /data/track-t.sh [/dev/block/mmcblk1] [size]
#
# Wipes the WHOLE card (no partition table) and builds rootfs.img on it.
# Nothing on the phone's own partitions is touched, and Android keeps working
# as long as the card is not booted into.
#
# The card is formatted as a single ext4 filesystem on purpose: the Halium
# initramfs resize helper parses /proc/partitions and gets confused by
# mmcblk1 + mmcblk1p1 pairs.

set -e

CARD=${1:-/dev/block/mmcblk1}
SIZE=${2:-8G}
MOUNT=/mnt/sd

say() { echo "==> $*"; }

[ -b "$CARD" ] || {
    echo "$CARD is not a block device. Cards present:"
    ls -l /dev/block/mmcblk* 2>/dev/null || echo "  (none - insert a microSD)"
    exit 1
}

name=$(basename "$CARD")
sectors=$(cat "/sys/class/block/$name/size" 2>/dev/null || echo 0)
gb=$((sectors / 2 / 1024 / 1024))
say "card $CARD is ${gb} GiB"
# 8 GiB rootfs.img + 470 MB android-rootfs + 839 MB vendor.img + slack.
[ "$gb" -ge 11 ] || { echo "need at least 11 GiB on the card (rootfs.img is $SIZE)"; exit 1; }

# Pre-flight: everything install-x6812.sh needs must be on /data before the
# card is wiped, otherwise we destroy it for nothing.
missing=0
for f in /data/install-x6812.sh /data/android-rootfs.img /data/vendor.img; do
    [ -e "$f" ] || { echo "missing $f"; missing=1; }
done
[ -d /data/ut-overlay ] || { echo "missing /data/ut-overlay"; missing=1; }
[ -d /data/ut-modules ] || { echo "missing /data/ut-modules"; missing=1; }
[ -e /data/ut-rootfs.tar.gz ] || [ -e /data/ut-rootfs.tar.xz ] || { echo "missing /data/ut-rootfs.tar.gz"; missing=1; }
[ -x /data/ut-stage/system/usr/bin/bash ] || { echo "missing staging tree /data/ut-stage (run install-x6812.sh first)"; missing=1; }
[ "$missing" = "0" ] || { echo "not formatting anything"; exit 1; }

# Android's vold mounts the card's first partition, and shows it in /proc/mounts
# as /dev/block/vold/public:MAJ,MIN - a plain "mount | grep $CARD" misses that,
# so mke2fs would wipe a filesystem that is still mounted (vold then keeps
# writing to it). Unmount by device name and by major:minor.
say "unmounting anything that uses $CARD"
for src in $(awk -v c="$name" '$1 ~ c {print $1}' /proc/mounts); do
    umount -l "$src" 2>/dev/null || umount "$src" 2>/dev/null || true
done
for d in /sys/class/block/"$name" /sys/class/block/"$name"p*; do
    [ -r "$d/dev" ] || continue
    mm=$(cat "$d/dev")
    maj=${mm%:*}
    min=${mm#*:}
    for mp in $(awk -v p="public:$maj,$min" '$1 ~ p {print $2}' /proc/mounts); do
        umount -l "$mp" 2>/dev/null || umount "$mp" 2>/dev/null || true
    done
done
grep -q "$name" /proc/mounts && say "warning: $name still appears in /proc/mounts" || true

say "formatting the whole card (this erases it)"
mke2fs -F -t ext4 -L utdata -m 0 "$CARD"

mkdir -p "$MOUNT"
mount -t ext4 "$CARD" "$MOUNT"

say "building the images on the card (10-20 min)"
sh /data/install-x6812.sh "$MOUNT" "$SIZE"

sync
say "done - card is ready"
df -h "$MOUNT" | tail -1
ls -l "$MOUNT"/rootfs.img "$MOUNT"/android-rootfs.img "$MOUNT"/vendor.img

say "next steps:"
echo "  1. powershell -File tools\\flash-track-t.ps1      (flash boot_a, reboot, wait)"
echo "  2. the card must stay inserted - cmdline is datapart=/dev/mmcblk1"
echo "  3. if nothing comes up: -Restore, then tools\\pull-card-log.ps1"
