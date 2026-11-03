#!/bin/sh
# Give the Android container a real /vendor partition.
#
# This device is a dynamic-partition (super) device: vendor_a has no
# /dev/disk/by-name node, so Halium cannot mount it as a partition. Instead we
# use the raw ext4 image dumped from the running Android (/data/vendor.img) and
# mount it as a loop file.
#
# Runs from lxc-android-config.service (ExecStartPre), i.e. after
# mount-android-partitions.service and right before the container starts.

set -e

img=/userdata/vendor.img

if [ ! -e "$img" ]; then
    echo "x6812: $img not found, Android container will have no /vendor" >&2
    exit 0
fi

if ! mountpoint -q /android/vendor; then
    mkdir -p /android/vendor
    if ! mount -o ro,loop "$img" /android/vendor; then
        echo "x6812: failed to mount $img on /android/vendor" >&2
        exit 0
    fi
fi

# The UT host loads the WiFi/BT/GPS kernel modules itself, and the kernel
# firmware loader resolves firmware_class.path=/vendor/firmware in the *host*
# mount namespace, not the container's.
mkdir -p /vendor
mountpoint -q /vendor || mount --bind /android/vendor /vendor || true

# Load the vendor kernel modules only now: wlan_drv_gen4m, bt_drv, gps_drv and
# wmt_chrdev_wifi call request_firmware() at insmod time, and the firmware
# loader resolves /vendor/firmware in the host namespace, which only exists
# after the bind above. modules-load.d loads them too, but that unit may run
# earlier and fail on the missing firmware.
KVER=4.14.186-g8ed8f1a9884b-dirty
if [ -d "/lib/modules/$KVER" ]; then
    for m in wmt_drv bt_drv fmradio_drv gps_drv wmt_chrdev_wifi wlan_drv_gen4m tran_fre fpsgo udc_lib; do
        grep -q "^$m " /proc/modules && continue
        modprobe "/lib/modules/$KVER/$m.ko" >/dev/null 2>&1 || \
            echo "x6812: could not load $m" >&2
    done
fi

# The stock fstab is full of fs_mgr-only flags (wait, check, formattable,
# first_stage_mount, slotselect, avb, ...). mount(8) passes unknown options to
# the filesystem driver, which rejects them, so mount-android-partitions would
# silently fail to mount metadata, persist, nvdata, nvcfg and protect_f/s -
# and without nvdata/nvcfg the MTK radio and NVRAM daemons cannot start.
# Bind a copy with only real mount options over the fstab before re-running it.
fstab=/android/vendor/etc/fstab.mt6768
clean=/run/x6812/fstab.mt6768
if [ -e "$fstab" ]; then
    mkdir -p /run/x6812
    awk '
        /^[[:space:]]*#/ { print; next }
        NF >= 4 && $1 !~ /^\/devices\// {
            if ($4 ~ /(^|,)ro(,|$)/) {
                $4 = "ro,nosuid,nodev,noatime"
            } else {
                $4 = "rw,nosuid,nodev,noatime,noauto_da_alloc"
            }
            print $1, $2, $3, $4
            next
        }
        { print }
    ' "$fstab" > "$clean"
    mount --bind "$clean" "$fstab" || echo "x6812: could not bind $clean over $fstab" >&2
fi

# Now that /android/vendor/etc/fstab.mt6768 exists, let the upstream script
# mount the remaining partitions (persist, nvdata, nvcfg, protect_f/s) and
# refresh the rbind into /var/lib/lxc/android/rootfs, so the container sees
# everything that was mounted after the unit's first pass.
/usr/libexec/lxc-android-config/mount-android-partitions || true

exit 0
