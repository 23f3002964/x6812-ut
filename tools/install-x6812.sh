#!/system/bin/sh
# Build the Ubuntu Touch images for the Infinix Hot 11s (X6812) ON the device.
#
# Inputs (pushed to /data by tools/push-install.ps1):
#   /data/ut-rootfs.tar.gz      Ubuntu Touch 20.04 arm64 rootfs (payload under system/)
#   /data/ut-overlay/           device/infinix/X6812/overlay/ content
#   /data/ut-modules/           the 11 stock .ko files
#   /data/android-rootfs.img    Halium 11 Android 11 root image
#   /data/vendor.img            raw ext4 dump of the device's vendor partition
#
# Usage (as root):
#   sh /data/install-x6812.sh /data          # real install (rootfs.img on userdata)
#   sh /data/install-x6812.sh /mnt/sd 12G    # test install on an ext4 SD card
#   KEEP_STAGE=0 sh ...                      # force a fresh extraction
#
# Nothing here touches the Android partitions. It only creates files.

set -e

TARGET=${1:-/data}
SIZE=${2:-8G}
KVER=4.14.186-g8ed8f1a9884b-dirty
KEEP_STAGE=${KEEP_STAGE:-1}

OVERLAY=/data/ut-overlay
MODULES=/data/ut-modules
ANDROID=/data/android-rootfs.img
VENDOR=/data/vendor.img
STAGE=/data/ut-stage

if [ -e /data/ut-rootfs.tar.gz ]; then
    SRC=/data/ut-rootfs.tar.gz
elif [ -e /data/ut-rootfs.tar.xz ]; then
    SRC=/data/ut-rootfs.tar.xz
else
    echo "missing /data/ut-rootfs.tar.gz"; exit 1
fi

say() { echo "==> $*"; }

for f in "$SRC" "$ANDROID" "$VENDOR"; do
    [ -e "$f" ] || { echo "missing $f"; exit 1; }
done
[ -d "$OVERLAY" ] || { echo "missing $OVERLAY"; exit 1; }
[ -d "$MODULES" ] || { echo "missing $MODULES"; exit 1; }
[ -d "$TARGET" ] || { echo "missing target dir $TARGET"; exit 1; }

# toybox tar refuses to create a symlink whose target is not below -C, and the
# rootfs is full of them (/data -> /android/data and so on). It still extracts
# every file and creates those symlinks from the duplicate "./" entries, then
# exits 2. Treat that as success if the tree is there and fix up the rest below.
if [ "$KEEP_STAGE" = "1" ] && [ -x "$STAGE/system/usr/bin/bash" ]; then
    say "staging tree already extracted, keeping it"
else
    say "cleaning staging area"
    rm -rf "$STAGE"
    mkdir -p "$STAGE"

    say "extracting Ubuntu Touch rootfs (this takes a few minutes)"
    tar_rc=0
    case "$SRC" in
        *.gz) tar -xzf "$SRC" -C "$STAGE" --numeric-owner || tar_rc=$? ;;
        *)    tar -xJf "$SRC" -C "$STAGE" --numeric-owner || tar_rc=$? ;;
    esac
    [ "$tar_rc" = "0" ] || say "tar exited $tar_rc (expected 2 for absolute symlinks)"

    [ -x "$STAGE/system/usr/bin/bash" ] || { echo "rootfs extraction incomplete"; exit 1; }
    [ -s "$STAGE/system/etc/passwd" ]   || { echo "rootfs extraction incomplete"; exit 1; }
fi

[ -d "$STAGE/system" ] || { echo "rootfs payload is not under system/"; exit 1; }

say "fixing the Android mount-point symlinks"
cd "$STAGE/system"
for l in cache data factory firmware persist system odm vendor product metadata mnt apex; do
    [ -L "$l" ] || ln -sfn "/android/$l" "$l"
done
cd /
ln -sfn /proc/mounts "$STAGE/system/etc/mtab"

say "installing device overlay"
# `adb push <dir> <existing dir>` creates <dir>/<dir>/... - heal that instead of
# silently installing nothing (which is what a plain delete would do).
if [ -d "$OVERLAY/overlay" ]; then
    say "fixing nested $OVERLAY/overlay (adb push layout)"
    cp -a "$OVERLAY/overlay"/. "$OVERLAY"/
    rm -rf "$OVERLAY/overlay"
fi
cp -a "$OVERLAY"/. "$STAGE/system"/

# adb push leaves everything 0644; the overlay files that get executed.
chmod 755 "$STAGE/system/usr/lib/x6812/mount-vendor.sh" \
          "$STAGE/system/usr/lib/x6812/backlight.sh" \
          "$STAGE/system/usr/bin/aa-exec" \
          "$STAGE/system/usr/bin/aa-exec.real" \
          "$STAGE/system/usr/share/halium-overlay/usr/libexec/lxc-android-config/device-hacks"

# adb push cannot create the symlink that enables a unit, so make it here.
mkdir -p "$STAGE/system/etc/systemd/system/multi-user.target.wants"
for unit in x6812-log.service x6812-backlight.service; do
    [ -f "$STAGE/system/etc/systemd/system/$unit" ] || continue
    say "enabling $unit"
    ln -sf "../$unit" \
        "$STAGE/system/etc/systemd/system/multi-user.target.wants/$unit"
done

# The stock rootfs ships a comment-only placeholder here. deviceinfo uses it as
# a bind-mount target for device ports; shipping a real config in it silently
# overrides every device profile, so keep it empty.
say "restoring the stock deviceinfo fallback"
mkdir -p "$STAGE/system/etc/deviceinfo/devices"
printf '# Empty device config\n# Intended for use as a bind-mount overlay target, like device-specific Halium ports.\n' \
    > "$STAGE/system/etc/deviceinfo/devices/halium.yaml"

# The focal arm64 rootfs is built without a user: /home/phablet exists with the
# right numeric owner and every group names phablet, but passwd/group/shadow
# have no entry. /etc is read-only at runtime, so it has to be created here.
say "creating the phablet account"
ETC="$STAGE/system/etc"
grep -q '^phablet:' "$ETC/passwd" || \
    echo 'phablet:x:32011:32011:Phablet,,,:/home/phablet:/bin/bash' >> "$ETC/passwd"
grep -q '^phablet:' "$ETC/group"  || echo 'phablet:x:32011:' >> "$ETC/group"
grep -q '^phablet:' "$ETC/shadow" || echo 'phablet:!:19000:0:99999:7:::' >> "$ETC/shadow"
[ -f "$ETC/subuid" ] && { grep -q '^phablet:' "$ETC/subuid" || echo 'phablet:100000:65536' >> "$ETC/subuid"; } || true
[ -f "$ETC/subgid" ] && { grep -q '^phablet:' "$ETC/subgid" || echo 'phablet:100000:65536' >> "$ETC/subgid"; } || true
mkdir -p "$STAGE/system/etc/sudoers.d"
printf 'phablet ALL=(ALL) NOPASSWD:ALL\n' > "$STAGE/system/etc/sudoers.d/90-phablet"
chmod 440 "$STAGE/system/etc/sudoers.d/90-phablet"
mkdir -p "$STAGE/system/home/phablet"
chown 32011:32011 "$STAGE/system/home/phablet"
chmod 755 "$STAGE/system/home/phablet"

say "installing kernel modules"
mkdir -p "$STAGE/system/lib/modules/$KVER"
cp "$MODULES"/*.ko "$STAGE/system/lib/modules/$KVER"/
chmod 644 "$STAGE/system/lib/modules/$KVER"/*.ko

say "patching the Android container config"
LXC_CFG="$STAGE/system/var/lib/lxc/android/config"
if [ -f "$LXC_CFG" ]; then
    # The stock kernel has no CONFIG_IPC_NS, so LXC must share the IPC ns.
    grep -q '^lxc.namespace.keep' "$LXC_CFG" || echo 'lxc.namespace.keep = ipc' >> "$LXC_CFG"
    # The kernel has no CGROUP_DEVICE; these lines would only produce errors.
    if grep -q 'lxc.cgroup.devices' "$LXC_CFG"; then
        echo "WARNING: $LXC_CFG uses lxc.cgroup.devices, kernel has no CGROUP_DEVICE"
    fi
else
    echo "WARNING: $LXC_CFG not found"
fi

say "creating $TARGET/rootfs.img ($SIZE)"
rm -f "$TARGET/rootfs.img"
mke2fs -t ext4 -L rootfs -m 0 -d "$STAGE/system" "$TARGET/rootfs.img" "$SIZE"

if [ "$TARGET" != "/data" ]; then
    say "copying android-rootfs.img and vendor.img to $TARGET"
    cp "$ANDROID" "$TARGET/android-rootfs.img"
    cp "$VENDOR"  "$TARGET/vendor.img"
fi

say "checking the new image"
e2fsck -fn "$TARGET/rootfs.img" | tail -3

say "done"
ls -l "$TARGET"/rootfs.img "$TARGET"/android-rootfs.img "$TARGET"/vendor.img

if [ "$KEEP_STAGE" != "1" ]; then
    say "removing staging tree"
    rm -rf "$STAGE"
fi
