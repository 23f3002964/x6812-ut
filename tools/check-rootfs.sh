#!/system/bin/sh
# Verify the Ubuntu Touch rootfs before/after packing, without booting it.
#
#   sh /data/check-rootfs.sh                       # /data/rootfs.img (loop mount)
#   sh /data/check-rootfs.sh /data/rootfs.img
#   sh /data/check-rootfs.sh --dir /data/ut-stage/system
#
# In --dir mode it inspects the staging tree that mke2fs copies from, which is
# the only way to look at the content on a user build: Android runs SELinux in
# "always enforcing" mode (setenforce fails with EINVAL), and the loop driver is
# denied read on files under /data, so mounting the image needs a reboot into
# the Halium initramfs. Safe: never writes.

DIRMODE=0
if [ "$1" = "--dir" ]; then
    DIRMODE=1
    MNT=$2
    IMG=$MNT
else
    IMG=${1:-/data/rootfs.img}
    MNT=/mnt/utcheck
fi
KVER=4.14.186-g8ed8f1a9884b-dirty

fail=0
ok()   { echo "  ok    $*"; }
bad()  { echo "  FAIL  $*"; fail=$((fail + 1)); }
note() { echo "  ..    $*"; }

[ -d "$MNT" ] || [ -e "$IMG" ] || { echo "missing $IMG"; exit 1; }

OLD_MODE=Disabled
if [ "$DIRMODE" = "0" ]; then
    # Android runs SELinux enforcing: the loop driver (kernel domain) is denied
    # read on files labelled system_data_root_file, so mounting the image fails
    # with EIO. Relabelling is not possible without the policy, so switch to
    # permissive for the duration of the check and restore it afterwards.
    OLD_MODE=$(getenforce)
    [ "$OLD_MODE" = "Enforcing" ] && setenforce 0
    mkdir -p "$MNT"
    if ! mount -o ro,loop "$IMG" "$MNT"; then
        echo "cannot mount $IMG (loop mount failed - use --dir instead)"
        [ "$OLD_MODE" = "Enforcing" ] && setenforce 1
        exit 1
    fi
fi

restore_selinux() {
    [ "$DIRMODE" = "0" ] && [ "$OLD_MODE" = "Enforcing" ] && setenforce 1
}
trap restore_selinux EXIT INT TERM

echo "== source =="
note "$IMG"
[ "$DIRMODE" = "0" ] && { note "$(ls -l "$IMG")"; df -h "$MNT" | tail -1; }

echo "== basic layout =="
[ -x "$MNT/usr/bin/bash" ]           && ok "usr/bin/bash"            || bad "usr/bin/bash"
[ -e "$MNT/usr/lib/systemd/systemd" ] && ok "usr/lib/systemd/systemd" || bad "usr/lib/systemd/systemd"
[ "$(readlink "$MNT/sbin")" = "usr/sbin" ] && ok "/sbin -> usr/sbin" || bad "/sbin not usr-merged"
[ "$(readlink "$MNT/vendor")" = "/android/vendor" ] && ok "/vendor -> /android/vendor" || bad "/vendor symlink"
[ "$(readlink "$MNT/data")" = "/android/data" ] && ok "/data -> /android/data" || bad "/data symlink"
[ -d "$MNT/android" ] && ok "/android" || bad "/android"

echo "== kernel modules =="
n=$(ls "$MNT/lib/modules/$KVER"/*.ko 2>/dev/null | wc -l)
[ "$n" -ge 10 ] && ok "$n modules in /lib/modules/$KVER" || bad "only $n modules in /lib/modules/$KVER"
[ -e "$MNT/etc/modules-load.d/x6812.conf" ] && ok "modules-load.d/x6812.conf" || bad "modules-load.d/x6812.conf"
first_mod=$(grep -v -e '^#' -e '^$' "$MNT/etc/modules-load.d/x6812.conf" 2>/dev/null | head -1)
case "$first_mod" in
    *wmt_drv.ko) ok "wmt_drv first ($first_mod)" ;;
    '')          bad "modules-load.d/x6812.conf is empty" ;;
    *)           bad "first module is not wmt_drv: $first_mod" ;;
esac

echo "== accounts =="
if grep -q '^phablet:' "$MNT/etc/passwd" 2>/dev/null; then
    ok "passwd: $(grep '^phablet:' "$MNT/etc/passwd")"
else
    bad "no phablet entry in /etc/passwd"
fi
grep -q '^phablet:x:32011:' "$MNT/etc/group" 2>/dev/null && ok "group phablet (32011)" || bad "no phablet group"
grep -q '^phablet:' "$MNT/etc/shadow" 2>/dev/null && ok "shadow phablet" || bad "no phablet shadow entry"
[ -e "$MNT/etc/sudoers.d/90-phablet" ] && ok "sudoers.d/90-phablet" || note "no sudoers.d/90-phablet"
[ "$(stat -c %u "$MNT/home/phablet" 2>/dev/null)" = "32011" ] && ok "/home/phablet owned by 32011" || bad "/home/phablet owner"

echo "== deviceinfo =="
D="$MNT/etc/deviceinfo/devices/Infinix-X6812.yaml"
[ -e "$D" ] && ok "Infinix-X6812.yaml" || bad "Infinix-X6812.yaml"
grep -q "GridUnit: 21" "$D" 2>/dev/null && ok "GridUnit 21" || bad "GridUnit"
grep -q "DeviceType: phone" "$D" 2>/dev/null && ok "DeviceType phone" || bad "DeviceType"
grep -q "PrimaryOrientation: Portrait" "$D" 2>/dev/null && ok "PrimaryOrientation portrait" || bad "PrimaryOrientation"
grep -q "lcd-backlight" "$D" 2>/dev/null && ok "backlight path" || bad "backlight path"
H="$MNT/etc/deviceinfo/devices/halium.yaml"
if [ -e "$H" ]; then
    if grep -q "PrettyName" "$H" 2>/dev/null; then
        note "halium.yaml overrides the stock empty fallback ($(wc -c < "$H") bytes)"
    else
        ok "halium.yaml still the empty fallback"
    fi
fi

echo "== android container =="
CFG="$MNT/var/lib/lxc/android/config"
[ -e "$CFG" ] && ok "lxc config present" || bad "lxc config missing"
grep -q "^lxc.namespace.keep = ipc" "$CFG" 2>/dev/null && ok "namespace.keep ipc" || bad "namespace.keep ipc missing"
grep -q "lxc.cgroup.devices" "$CFG" 2>/dev/null && note "config uses cgroup devices (kernel has none)" || ok "no cgroup devices"

echo "== x6812 overlay =="
[ -x "$MNT/usr/lib/x6812/mount-vendor.sh" ] && ok "mount-vendor.sh" || bad "mount-vendor.sh"
[ -e "$MNT/etc/systemd/system/lxc-android-config.service.d/50-x6812-vendor.conf" ] && ok "vendor drop-in" || bad "vendor drop-in"
[ -x "$MNT/usr/share/halium-overlay/usr/libexec/lxc-android-config/device-hacks" ] && ok "halium-overlay device-hacks" || bad "halium-overlay device-hacks"
[ -e "$MNT/usr/libexec/lxc-android-config/device-hacks" ] && ok "placeholder device-hacks" || bad "placeholder device-hacks"
[ -e "$MNT/etc/ofono/ril_subscription.d/mtk.conf" ] && ok "mtk.conf" || bad "mtk.conf"
grep -q "radio@1.5" "$MNT/etc/ofono/ril_subscription.d/mtk.conf" 2>/dev/null && ok "radio@1.5" || bad "radio@1.5"
if [ -e "$MNT/etc/gbinder.conf" ] && grep -q "ApiLevel = 30" "$MNT/etc/gbinder.conf" 2>/dev/null; then
    ok "gbinder ApiLevel 30"
else
    bad "gbinder.conf"
fi
[ -e "$MNT/etc/ubuntu-touch-session.d/android.conf" ] && ok "session android.conf" || note "session android.conf missing"
[ -e "$MNT/etc/default/lsc-wrapper.d/10-force-hwc2.conf" ] && ok "lsc-wrapper hwc2" || note "lsc-wrapper hwc2 missing"
[ -e "$MNT/etc/systemd/journald.conf.d/x6812-debug.conf" ] && ok "journald -> kmsg (debug)" || note "journald debug conf missing"

# The host udev does not inherit Android's ueventd.rc modes. libhybris opens
# /dev/mali0 and /dev/ion from the phablet session, so without this file the
# panel never lights up (stock Android has both at 0666).
RULES="$MNT/usr/lib/udev/rules.d/70-x6812.rules"
[ -e "$RULES" ] && ok "udev 70-x6812.rules" || bad "udev 70-x6812.rules"
grep -q 'KERNEL=="mali0", MODE="0666"' "$RULES" 2>/dev/null \
    && ok "mali0 -> 0666" || bad "mali0 rule"
grep -q 'KERNEL=="ion", MODE="0666"' "$RULES" 2>/dev/null \
    && ok "ion -> 0666" || bad "ion rule"

# udev drops a whole rule (MODE included) when OWNER/GROUP does not resolve.
# Android's ueventd has names like graphics/uhid/gps/log, the UT host does not,
# so a copied vendor rule with such a name silently does nothing.
udev_missing=""
for n in $(sed -n 's/.*OWNER="\([^"]*\)".*/\1/p' "$RULES" 2>/dev/null | sort -u); do
    grep -q "^$n:" "$MNT/etc/passwd" 2>/dev/null || udev_missing="$udev_missing owner:$n"
done
for n in $(sed -n 's/.*GROUP="\([^"]*\)".*/\1/p' "$RULES" 2>/dev/null | sort -u); do
    grep -q "^$n:" "$MNT/etc/group" 2>/dev/null || udev_missing="$udev_missing group:$n"
done
[ -z "$udev_missing" ] && ok "udev owner/group names resolve" \
    || bad "udev names missing:$udev_missing"

# This kernel has CONFIG_SECURITY_APPARMOR=n. UAL still wraps every click app
# in "aa-exec -p <appid> --", so the shim must be in place or no app starts.
[ -x "$MNT/usr/bin/aa-exec" ] && ok "aa-exec shim" || bad "aa-exec shim"
[ -x "$MNT/usr/bin/aa-exec.real" ] && ok "aa-exec.real" || bad "aa-exec.real"
grep -q 'aa-exec.real' "$MNT/usr/bin/aa-exec" 2>/dev/null \
    && ok "aa-exec fallback" || bad "aa-exec fallback"

echo "== units that must exist =="
for u in lxc-android-config mount-android-system mount-android-partitions device-hacks x6812-log x6812-backlight; do
    if ls "$MNT/usr/lib/systemd/system/$u"* >/dev/null 2>&1 || ls "$MNT/etc/systemd/system/$u"* >/dev/null 2>&1; then
        ok "unit $u"
    else
        bad "unit $u"
    fi
done
for u in x6812-log x6812-backlight; do
    [ -L "$MNT/etc/systemd/system/multi-user.target.wants/$u.service" ] \
        && ok "$u enabled" || bad "$u not enabled"
done
[ -x "$MNT/usr/lib/x6812/backlight.sh" ] && ok "backlight.sh" || bad "backlight.sh"

# This kernel is built without CONFIG_TMPFS_POSIX_ACL, so logind's uaccess
# ACLs on /dev/input/event* fail. Touch/keyboard therefore rely on the
# android_input group: 65-android.rules sets it and phablet must be in it.
if grep -q 'KERNEL=="event\[0-9\]\*"' "$MNT/lib/udev/rules.d/65-android.rules" 2>/dev/null &&
   grep -q 'GROUP="android_input"' "$MNT/lib/udev/rules.d/65-android.rules" 2>/dev/null; then
    ok "input -> android_input"
else
    bad "input udev rule"
fi
grep -q '^android_input:.*phablet' "$MNT/etc/group" 2>/dev/null \
    && ok "phablet in android_input" || bad "phablet not in android_input"

echo "== counts =="
note "entries: $(find "$MNT" -xdev | wc -l)  files: $(find "$MNT" -xdev -type f | wc -l)"

if [ "$DIRMODE" = "0" ]; then
    sync
    umount "$MNT"
    rmdir "$MNT" 2>/dev/null
    restore_selinux
fi

echo
if [ "$fail" = "0" ]; then
    echo "RESULT: PASS"
else
    echo "RESULT: $fail check(s) failed"
fi
exit "$fail"
