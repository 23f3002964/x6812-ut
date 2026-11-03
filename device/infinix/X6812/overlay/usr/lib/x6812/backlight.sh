#!/bin/sh
# Raise the panel backlight at boot.
#
# Stock Android leaves the MTK backlight at a very low value (225 of 4095 on
# this device) and libdeviceinfo 0.1 has no backlight key, so nothing in Ubuntu
# Touch raises it on its own. Without this the desktop can be up and still look
# black in daylight. Lomiri/repowerd can change the level afterwards; this only
# lifts a too-dim panel once, at boot.

for b in /sys/class/leds/lcd-backlight /sys/class/backlight/*; do
    [ -w "$b/brightness" ] || continue

    max=$(cat "$b/max_brightness" 2>/dev/null)
    case "$max" in
        ''|*[!0-9]*) max=255 ;;
    esac
    [ "$max" -gt 0 ] || max=255

    cur=$(cat "$b/brightness" 2>/dev/null)
    case "$cur" in
        ''|*[!0-9]*) cur=0 ;;
    esac

    target=$((max / 2))
    [ "$cur" -lt "$target" ] || continue

    echo "$target" > "$b/brightness" 2>/dev/null || continue
    echo "x6812: backlight $b $cur -> $target (max $max)"
done

exit 0
