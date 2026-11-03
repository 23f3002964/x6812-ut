#!/bin/bash
# =============================================================================
#  Build rootfs.img for Ubuntu Touch (Halium file layout)
#
#  RUN INSIDE WSL2 / native Linux, as root (sudo bash make-rootfs-img.sh).
#
#  Input : out/rootfs/focal-arm64-rootfs.tar.xz   (UBports 20.04 arm64 rootfs)
#          device/infinix/X6812/prebuilt/modules/*.ko
#  Output: out/rootfs/rootfs.img   (ext4, label "rootfs")
#
#  The resulting image goes to /data/rootfs.img on the phone. Halium's
#  initramfs mounts it read-write via loop (file_layout=halium), so no
#  partition table or super changes are needed.
# =============================================================================
set -euo pipefail

PROJ="${PROJ:-/mnt/c/Users/tanisha/projects/x6812-ut}"
TARBALL="${TARBALL:-$PROJ/out/rootfs/focal-arm64-rootfs.tar.xz}"
OUT="${OUT:-$PROJ/out/rootfs/rootfs.img}"
MODDIR="${MODDIR:-$PROJ/device/infinix/X6812/prebuilt/modules}"
KVER="4.14.186-g8ed8f1a9884b-dirty"
EXTRA_MB="${EXTRA_MB:-1024}"

[ "$(id -u)" = "0" ] || { echo "run as root: sudo bash $0"; exit 1; }
[ -f "$TARBALL" ] || { echo "missing rootfs tarball: $TARBALL"; exit 1; }

WORK="$(mktemp -d /tmp/ut-rootfs.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

echo "==> extracting $(basename "$TARBALL")"
tar -xpf "$TARBALL" -C "$WORK" --numeric-owner \
    --exclude='dev/*' --exclude='proc/*' --exclude='sys/*'

# ---- kernel modules (prebuilt, vermagic must match the stock kernel) --------
echo "==> installing kernel modules for $KVER"
install -d "$WORK/lib/modules/$KVER"
cp -a "$MODDIR"/*.ko "$WORK/lib/modules/$KVER"/
cp -a "$MODDIR"/modules.* "$WORK/lib/modules/$KVER"/ 2>/dev/null || true
if command -v depmod >/dev/null; then
    depmod -b "$WORK" "$KVER" || true
fi

# ---- sanity -----------------------------------------------------------------
[ -x "$WORK/usr/bin/lomiri" ] || [ -f "$WORK/usr/bin/lomiri" ] || \
    echo "WARNING: lomiri binary not found, is this really a UT rootfs?"
[ -f "$WORK/var/lib/lxc/android/android-rootfs.img" ] && \
    echo "note: rootfs already contains android-rootfs.img"

USED_MB=$(du -sm "$WORK" | cut -f1)
SIZE_MB=$(( USED_MB + EXTRA_MB ))
echo "==> content ${USED_MB} MB, image ${SIZE_MB} MB"

echo "==> creating ext4 image $OUT"
rm -f "$OUT"
truncate -s "${SIZE_MB}M" "$OUT"
mkfs.ext4 -F -L rootfs -m 0 -O ^metadata_csum_seed -d "$WORK" "$OUT"
e2fsck -fy "$OUT" || true

echo "==> done"
ls -lh "$OUT"
