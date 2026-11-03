# sepolicy — Infinix Hot 11s (X6812)

Halium system images run Android in an LXC container, so device-specific
SELinux policy is only needed if a vendor blob refuses to run under the
generic `halium` policy.

Placeholder layout (BoardConfig.mk already points here):

    sepolicy/vendor/*.te   -> BOARD_SEPOLICY_DIRS
    sepolicy/system/*.te   -> BOARD_PLAT_POLICY_DIRS

Start empty. Add rules only after a real `dmesg`/`logcat` denial appears while
testing, and always with the exact `avc: denied` line as the commit message.
