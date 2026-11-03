# ROM-PLAN - a working Ubuntu Touch build for the Infinix Hot 11s (X6812)

*Written 2026-11-03, after Stage 1 (dump), Stage 2 (boot images) and the
on-device build of `/data/rootfs.img`.*

**Status:** everything that can be built without the phone's microSD card is
done - boot images rebuilt and verified, `rootfs.img` rebuilt and checked
(`RESULT: PASS`), `track-t.sh` on the phone. Today's audit fixed every software
limitation that could be fixed without booting: the SELinux lever is
`enforcing=0` (`androidboot.selinux=` is compiled out), `/dev/kmsg` is created by
the patched init (the boot log was silent without it), a oneshot unit raises
the panel backlight, `70-x6812.rules` gives the host the same MTK device
permissions Android has (without it `/dev/mali0` is unreadable to Lomiri), and
an `aa-exec` shim lets click apps start without AppArmor. The full list,
including the things that genuinely
cannot be fixed here - **Bluetooth** (`CONFIG_BT` off) and the missing microSD -
is in #4.5. The next action is physical: insert a card and run
`tools\flash-track-t.ps1`.

One thing must be true on the phone before Track T: a microSD of **11 GB or
more** (or a USB stick in an OTG adapter). **Rooted debugging** is enabled right
now (`adb shell id` is `uid=0`), but it resets on every reboot - re-enable it and
run `adb root` after a reboot.

**Short answer:** yes, a working Ubuntu Touch ROM is achievable on this phone, and
the realistic route is **Ubuntu Touch 20.04 + Halium 11 running on the phone's own
stock 4.14.186 kernel** - no AOSP build, no kernel port. That route has roughly a
**50 % chance of reaching a usable desktop** and about **25 % of becoming a daily
driver**. Everything is reversible until we format `userdata`.

---

## 0. The plan in ten lines

1. Boot image with the stock kernel + a Halium initramfs - **already built and verified**.
2. Ubuntu Touch 20.04 arm64 root filesystem, packed as `rootfs.img` - **built on the phone, checker PASS**.
3. A prebuilt Halium 11 Android 11 image as the container's `/system` - **already downloaded and verified**.
4. The phone's real `vendor` partition, dumped to `vendor.img` - **already dumped (839 MB, ext4)**.
5. A small device overlay: deviceinfo, ofono radio@1.5, HWC2, kernel modules, vendor loop mount, backlight - **installed in the image**.
6. **Test boot from a microSD card** (`datapart=`), so `userdata` is not touched.
7. Read the logs, fix the first thing that breaks, repeat.
8. Only after it boots: format `userdata` to ext4 and move the images there.
9. Rollback is always: flash the stock boot image + `fastboot -w`.
10. If Halium 11 stalls on display/audio, choose option C (kernel port) or D (stay on Android).

---

## 1. What "working" means - the gates

We count progress in gates, not in "% done". Each gate is testable.

| Gate | Meaning | How we know |
|---|---|---|
| **G0** | Kernel + Halium initramfs start | `/x6812-boot.log` appears on the data partition; `/proc/last_kmsg` has the initramfs lines (no VT, so nothing on screen) |
| **G1** | UT rootfs mounts and systemd starts | `journalctl` exists, `systemctl` works, ssh/ping answers |
| **G2** | Android 11 container starts with a real `/vendor` | `lxc-info -n android` shows RUNNING, HAL services log |
| **G3** | Lomiri paints something on the panel | display lights up, no black screen |
| **G4** | Touch + WiFi + audio | can unlock, connect, hear sound |
| **G5** | Calls/SMS/data, camera, sensors | daily-driver features |

The plan below optimises for **G3 first**, because that is the gate that decides
whether this is worth continuing.

---

## 2. The four options

| | Option | What it is | Work | Chance it runs | Verdict |
|---|---|---|---|---|---|
| **A** | **UT 20.04 + Halium 11, stock kernel** | prebuilt UT rootfs + prebuilt Halium 11 Android 11 + the phone's own vendor image | 2-4 h to first boot, then 1-3 evenings of fixes | **G3 ~ 50 %**, G4 ~ 30 %, daily ~ 20-25 % | **Do this** |
| **B** | UT "UI-first" slice | same as A, but we stop at G3 and accept no radio/camera | same as A | G3 ~ 55 % | the practical fallback inside A |
| **C** | Port a newer MTK kernel | take merlin/lancelot's 4.14.355 openela kernel + port the X6812 device tree | 3-8 weeks | 20-30 % for a fully working kernel | only if A dies on a kernel limitation |
| **D** | Keep Android | Android 15 GSI as it is now (or a clean AOSP/Lineage build) | 0 | 100 % | always available |

**Why not C now:** the stock kernel is missing `DEVTMPFS`, `SYSVIPC`, `IPC_NS`,
`CGROUP_DEVICE`, `CGROUP_PIDS`, `FHANDLE`, `POSIX_MQUEUE`, `USER_NS` and - the
one that cannot be worked around - **`CONFIG_BT`** (no Bluetooth stack at all).
Only `DEVTMPFS` would block boot, and it is already replaced in the initramfs;
the Bluetooth gap costs a feature, not the desktop. Porting a kernel to fix the
others before we know which ones matter would be weeks of work on a device tree
we cannot test quickly.

---

## 3. Why option A is not wishful thinking

Every row below is evidence from this phone, not a guess.

| Piece | Evidence on this device | Risk |
|---|---|---|
| SoC family | MT6768/MT6769H. Merlin (Redmi Note 9) and lancelot (Redmi 9) are the **same MT6769 family** and both have official UT ports | low |
| Kernel | stock 4.14.186 boots, has `BINDERFS`, `BINDER_IPC`, `ASHMEM`, `ION`, `DMA_SHARED_BUFFER`, `EXT4`, `F2FS`, `LOOP`, `OVERLAY_FS`, `SECCOMP`, `PID/NET/UTS_NS`, `MTK_FB`, `INPUT_EVDEV` | low |
| Android version match | vendor is API 30 (Android 11); the Halium image is AOSP 11 / SDK 30 -> **same VNDK** | low |
| Display | vendor exposes `android.hardware.graphics.composer@2.1`, allocator/mapper 4.0 | **medium** - this is the most likely place to lose |
| Touch | `mtk-tpd` is a **kernel input device** (`/dev/input/event2`), not an Android HAL -> UT reads it directly | low |
| Backlight | `/sys/class/leds/lcd-backlight` exists (max 4095, stock leaves 225); `x6812-backlight.service` lifts it at boot | low |
| Radio | vendor manifest has `android.hardware.radio@1.2` and `@1.5` for `slot1`/`slot2`, plus `ISap` | medium |
| WiFi/GPS | `wlan_drv_gen4m`, `wmt_drv`, `wmt_chrdev_wifi`, `gps_drv` - **real kernel modules**, so UT's normal `wpa_supplicant` can drive WiFi | medium |
| Bluetooth | `bt_drv`/`BT_FW.cfg` exist, but the kernel has **`CONFIG_BT` off** - no HCI core, so no Bluetooth in this port | **unsupported** (needs a kernel rebuild) |
| Firmware | `/vendor/firmware` still on the phone (we never wipe vendor) | low |
| Bootloader | unlocked (`verifiedbootstate=orange`), `fastboot flash` works; `fastboot boot` crashes this LK, so flashing is the only way in | low |

**What is genuinely uncertain:** whether the stock MTK composer 2.1 + libhybris in
UT 20.04 produce a working EGL surface, and whether the vendor's Android 11 init
scripts are happy inside the container. Both are "fix or give up" issues that only
a boot will answer.

---

## 4. What is already built

| Artifact | Path | Size | SHA-256 |
|---|---|---|---|
| **Boot image** | `out/halium-boot.img` | 13 881 344 B | `30AD3A7E...C80341A8` |
| **Boot image (SD test)** | `out/halium-boot-sd.img` | 13 881 344 B | `8777C765...07784F3B` |
| Stock boot (rollback) | `out/stock-boot_a.img` | 33 554 432 B | `2E5E01A8...EBC310` |
| Patched initramfs | `out/halium-initramfs-x6812.gz` | 4 099 919 B | `AE4F61A2...C0EBB9A4` |
| UT 20.04 rootfs | `out/rootfs/focal-arm64-rootfs.tar.xz` | 471 726 476 B | `F2B91478...F9C8784` |
| UT rootfs, phone format | `out/rootfs/focal-arm64-rootfs.tar.gz` | 783 862 802 B | 64 386 members, gzip |
| Halium 11 Android image | `out/rootfs/merlin-dev/.../android-rootfs.img` | 470 220 800 B | `0736B0B2...64503DC` |
| Vendor image (dumped today) | on phone `/data/vendor.img` | 839 405 568 B | ext4, label `vendor`, 2119 files |
| Kernel modules | `device/infinix/X6812/prebuilt/modules/` | 11 `.ko` | vermagic `4.14.186-g8ed8f1a9884b-dirty` |
| Device overlay | `device/infinix/X6812/overlay/` | 16 files | see #4.3 |
| **UT rootfs image** | on phone `/data/rootfs.img` | 8 GiB ext4, 64 273 inodes, 557 023/2 097 152 blocks | `D267B3F3...9EAAF7E`, checker PASS |

Both boot images were re-verified after the initramfs change:
`tools/verify_boot.py --allow-cmdline` -> **PASS**, kernel and DTB byte-identical
to stock, only the cmdline differs on purpose.

They are reproducible now: `tools/build-boot.py` takes the stock image, keeps the
kernel and DTB bit-for-bit, swaps the ramdisk and writes the cmdline, and
`python tools\build-images.py` runs the whole chain (pristine initramfs + the two
patched files -> ramdisk -> both boot images) in one command. Running it again
today reproduced `30AD3A7E...`, `8777C765...` and `AE4F61A2...` exactly, so every
future initramfs iteration is one command instead of a re-derived mkbootimg call.

The patched `init` and `scripts/halium` are tracked in
`tools/initramfs/patched/`, because the extracted tree in `out/` is only build
output and at one point carried an unpatched `init`.

The initramfs carries exactly four changes against the stock Halium one, all
tracked in `tools/initramfs/patched/`:

| Change | File | Why |
|---|---|---|
| tmpfs `/dev` + static nodes when `devtmpfs` cannot mount | `init` | this kernel has no `CONFIG_DEVTMPFS` |
| `/dev/kmsg` node in that tmpfs | `init` | nothing else creates it; udevd and every `tell_kmsg` line write there, so the whole boot log was silent |
| every `tell_kmsg` line also appended to `/x6812-boot.log` on the data partition | `scripts/halium` | no usable pstore (see #4.4) |
| `resize_userdata_if_needed` returns unless `blkid` says `ext4` | `scripts/halium` | without the guard a f2fs `userdata` makes `dumpe2fs` print nothing and the function runs `resize2fs` on a filesystem it does not understand |

The new cmdline adds the parameters Halium needs:

```
androidboot.hardware=mt6768        # so Android init loads init.mt6768.rc
androidboot.selinux=permissive     # read by Android init only; compiled out here
enforcing=0                        # the working SELinux lever (see #7.6)
androidboot.slot_suffix=_a         # A/B partition resolution
```

`androidboot.selinux=` is **not** the lever on this kernel: the vendor build has
`CONFIG_SECURITY_SELINUX_BOOTPARAM`, `_DEVELOP` and `_DISABLE` all off, so the
parameter is compiled out and `/sys/fs/selinux/enforce` is read-only
(`setenforce` fails). `enforcing=` is a plain `__setup` in
`security/selinux/hooks.c` (`enforcing_setup`, v4.14.186) and is not guarded by
those options, so `enforcing=0` keeps the kernel permissive even if a policy is
loaded later. Halium starts the container with `init second_stage`, which skips
the policy load entirely, but this makes the state explicit and safe.

`halium-boot-sd.img` additionally carries `datapart=/dev/mmcblk1`.

### 4.1 How the two filesystem images are produced

Both are built **on the phone itself**, from files pushed over USB. No Linux
host, no AOSP tree.

```
/data/ut-rootfs.tar.gz      -> extracted to /data/ut-stage/system
/data/ut-overlay/           -> copied on top (16 files, see #4.3)
/data/ut-modules/           -> /lib/modules/4.14.186-.../
lxc config patched          -> lxc.namespace.keep = ipc
mke2fs -d /data/ut-stage/system /data/rootfs.img 8G
```

`android-rootfs.img` (470 MB, AOSP 11) and `vendor.img` (839 MB, ext4) are
already files on `/data`; the initramfs picks them up from `/userdata` by name.

Three details that cost time and are now handled in `tools/install-x6812.sh`:

* The UT rootfs is full of absolute symlinks (`/data -> /android/data`, ...).
  Android's toybox `tar` refuses those and exits **2**, even though every file
  is extracted. The script treats exit 2 as success, verifies `/usr/bin/bash`
  and `/etc/passwd`, then re-creates the symlinks itself.
* The phone's `tar` has no xz support, so the rootfs is converted to `.tar.gz`
  on Windows first (`tools/convert-rootfs.py`, metadata preserved).
* Re-running the script reuses `/data/ut-stage` (`KEEP_STAGE=1`), so a failed or
  interrupted build does not re-extract 2.5 GB.

Two defects in the downloaded rootfs are fixed at build time, because `/etc` is
read-only once the image is mounted:

* **`phablet` does not exist.** Every group lists it as a member, `/home/phablet`
  exists with uid/gid 32011 and lightdm is set to autologin as `phablet`, but
  `passwd`, `group` and `shadow` have no entry. The script appends uid 32011,
  a locked password, `subuid`/`subgid` ranges and `/etc/sudoers.d/90-phablet`.
* **`/etc/deviceinfo/devices/halium.yaml` is a comment-only placeholder** that
  deviceinfo uses as a bind-mount target. Shipping a real config there would
  override every device profile, so the stock placeholder is restored.

`adb push` cannot carry the executable bit, so the script also `chmod 755`s the
three overlay scripts (`mount-vendor.sh`, `backlight.sh`, `device-hacks`).

Verified with `tools/check-rootfs.sh --dir /data/ut-stage/system` -> **PASS**
(45 914 files, 64 410 entries), including the backlight files, the host udev
rules, the `aa-exec` shim and the `android_input` group check. The image itself cannot be loop-mounted on the
running Android: SELinux is permanently enforcing (`setenforce` -> `EINVAL`) and
the loop worker is denied read on `system_data_root_file`, so the check runs
against the exact tree `mke2fs -d` packs.

At runtime the rootfs is **read-only**, by design: there is no `/.writable_image`
marker, so `scripts/halium` remounts `/halium-system` `ro` and bind-mounts every
path listed in `/etc/system-image/writable-paths` from `/userdata/system-data/`.
That is normal Ubuntu Touch and the reason the image can be an 8 GiB ext4 file
with a journal and nothing else.

Two consequences for debugging:

* Anything in `/etc`, `/usr`, `/lib` must be changed **in the image** and
  re-flashed; `sudo nano /etc/...` on the phone will fail with `Read-only file
  system`. The writable copies live in `/userdata/system-data/etc/...`.
* `/etc/systemd/system` is a `synced` path: on every boot the initramfs copies
  files that exist in the image but not yet in `/userdata/system-data`. It never
  overwrites, so after changing a unit or a drop-in you must delete the stale
  copy under `/userdata/system-data/etc/systemd/system/` (or wipe data).

### 4.2 The vendor partition, which is the real port

X6812 uses dynamic partitions: `vendor_a` lives inside `super` and has **no**
`/dev/disk/by-name/vendor` node, and `vendor_boot_a` is all zeros. Halium's
`mount-android-partitions` therefore logs

```
Hmm... can't guess a partition for /android/vendor.
```

and the container would start with an empty `/vendor`, i.e. no HALs at all.
The port solves this with a file instead of a partition:

```
/data/vendor.img       raw ext4 dump of vendor (839 405 568 B, e2fsck clean)
  -> loop-mounted ro at /android/vendor      (usr/lib/x6812/mount-vendor.sh)
  -> host /vendor is a symlink to /android/vendor, so /vendor/firmware works
  -> mount-android-partitions is re-run, now with a vendor fstab
  -> umount + rbind /android -> /var/lib/lxc/android/rootfs, container sees it
```

`mount-vendor.sh` runs as `ExecStartPre` of `lxc-android-config.service`, i.e.
after the first `mount-android-partitions` pass and before `lxc-start`.

The second problem it fixes is the fstab itself. `/vendor/etc/fstab.mt6768`
carries fs_mgr-only flags:

```
persist /mnt/vendor/persist ext4 noatime,... wait,check,formattable
```

`mount(8)` hands unknown options to ext4, which rejects them, so `metadata`,
`persist`, `nvdata`, `nvcfg` and `protect_f/s` would all fail to mount - and
without `nvdata`/`nvcfg` the MTK NVRAM daemon and the radio never come up. The
script bind-mounts a cleaned copy (only `ro/rw,nosuid,nodev,noatime,
noauto_da_alloc` in field 4) over the vendor fstab, so the stock script can do
the mounts. `/mnt/vendor/*` lands on a tmpfs because `/android/mnt` is on a
read-only filesystem, which the script already handles.

The same script also loads the nine vendor modules **after** `/vendor` exists,
because `wlan_drv_gen4m`, `bt_drv`, `gps_drv` and `wmt_chrdev_wifi` call
`request_firmware()` at insmod time and the firmware loader resolves
`/vendor/firmware` in the host namespace. `modules-load.d/x6812.conf` stays as
the fallback for a boot where `vendor.img` is missing.

One more check, done by reading the ext4 directory tree of the Android image
directly: `/system` in `android-rootfs.img` contains no `halium` or `ubuntu`
directory, so the host overlay really is taken from
`/usr/share/halium-overlay/` (the last source `mount-halium-overlay` tries),
not silently replaced by something inside the Android image.

### 4.3 The device overlay - 16 files

Everything lives in `device/infinix/X6812/overlay/` and is copied over the rootfs
by `install-x6812.sh`.

| Path in the image | Purpose |
|---|---|
| `etc/deviceinfo/devices/Infinix-X6812.yaml` | device profile: phone, GridUnit 21, portrait, sensorfw hybris config, Mir HWC2 keys |
| `etc/ubuntu-touch-session.d/android.conf` | `GRID_UNIT_PX=21`, `QTWEBKIT_DPR=2.2`, `FORM_FACTOR=handset` for the session |
| `etc/ofono/ril_subscription.d/mtk.conf` | ofono RIL: `radio@1.5` on `slot1`/`slot2` (merlin's was 1.4) |
| `etc/gbinder.conf` | `ApiLevel = 30`, so libgbinder speaks the vendor's HIDL layout |
| `etc/default/lsc-wrapper.d/10-force-hwc2.conf` | `MIR_ANDROID_FORCE_HWC2=1` (no-op on the HWC2-only platform, kept as a hint) |
| `etc/modules-load.d/x6812.conf` | nine `wmt_*`/`wlan_*`/`bt_*`/`gps_*` modules by absolute path, `wmt_drv` first, no depmod needed |
| `etc/systemd/system/lxc-android-config.service.d/50-x6812-vendor.conf` | adds `ExecStartPre=/bin/sh /usr/lib/x6812/mount-vendor.sh` |
| `etc/systemd/system/x6812-log.service` | mirrors the journal to `/userdata/x6812-journal.log` (see #6); enabled by a symlink the install script creates |
| `etc/systemd/system/x6812-backlight.service` | oneshot that raises the panel backlight at boot; enabled by the install script |
| `etc/systemd/journald.conf.d/x6812-debug.conf` | `ForwardToKMsg=yes` for bring-up, so early messages also land in `/dev/kmsg` |
| `usr/lib/x6812/mount-vendor.sh` | mounts `vendor.img`, loads modules, cleans the fstab, re-runs the mount script |
| `usr/lib/x6812/backlight.sh` | raises `/sys/class/leds/lcd-backlight` from the stock 225/4095 to half; libdeviceinfo 0.1 has no backlight key |
| `usr/lib/udev/rules.d/70-x6812.rules` | host permissions for the MTK nodes: `mali0`/`ion` at 0666 (libhybris opens them from the phablet session), plus WMT, CCCI, GPS, audio and camera nodes. Only `OWNER`/`GROUP` names that exist on the UT host are kept - udev silently drops a whole rule when a name does not resolve |
| `usr/bin/aa-exec` | shim: the kernel has no AppArmor, so it drops UAL's `-p <profile>` and execs the app unconfined; the real binary is used if AppArmor ever appears |
| `usr/bin/aa-exec.real` | the original `aa-exec`, kept so the shim can hand over on a kernel with AppArmor |
| `usr/share/halium-overlay/usr/libexec/lxc-android-config/device-hacks` | waits for NVRAM/property service, flips WMT to station mode, sets `wifi.interface` |

`device-hacks` is bind-mounted over the rootfs placeholder at
`/usr/libexec/lxc-android-config/device-hacks` by `mount-halium-overlay`, which
is how a port injects code into the host without touching the rootfs.

### 4.4 How the boot is logged

This device has **no usable pstore**: `/sys/fs/pstore` is empty, `ramoops` never
registers (no `ramoops` device tree node, only MTK's reserved-memory blocks), and
`CONFIG_ACCESS_RAMOOPS` is off. Checking it now saved a wasted debugging round
later. The two persistent logs go to the data partition, which is the only
writable place during bring-up:

| Log | Written by | Content |
|---|---|---|
| `/x6812-boot.log` | patched `scripts/halium` in the initramfs | every `tell_kmsg` line after the data partition mounts, plus the cmdline header |
| `/x6812-journal.log` | `x6812-log.service` | the whole journal of the boot (`journalctl -b -f`), i.e. systemd, LXC, Lomiri |

Both land in the root of the data partition: the microSD card in Track T,
`userdata` after Track F. Reading them does not need rootfs or a loop mount:

```powershell
powershell -File tools\pull-card-log.ps1
```

It also saves `/proc/last_kmsg` into the same folder, so one command collects
all three channels.

`tools/ext4-get.py` resolves the path inside ext4 and fetches only the blocks
that hold the file, over `adb exec-out dd`, so it is a few hundred kilobytes
instead of a 12 GB card image. It also works on a local image with `--image`.

There is **no on-screen console**: the bootloader passes `console=tty0`, but this
kernel is built without `CONFIG_VT`, so tty0 never exists and nothing is printed
to the panel. The first real channel is `/proc/last_kmsg` (MTK `ram_console`,
`CONFIG_MTK_RAM_CONSOLE=y`): it is 262 206 B on this device, survives a reboot
and can be read from Android after a failed boot. For that to work `/dev/kmsg`
must exist, which is why the patched `init` creates it (see #4).

### 4.5 Limitations - the complete list

Everything found while auditing the device, what it costs and whether it is
fixed. "Kernel" rows would need a rebuild of the vendor kernel from source; this
port deliberately keeps the stock prebuilt kernel (see #3).

| # | Limitation | Effect | Status |
|---|---|---|---|
| L1 | `CONFIG_DEVTMPFS` off | no `/dev` nodes from the kernel | **fixed**: patched `init` mounts tmpfs `/dev` and creates the static nodes; udev adds the rest |
| L2 | `/dev/kmsg` missing with L1 | udevd and `tell_kmsg` lines were silently lost | **fixed**: `init` creates `mknod /dev/kmsg c 1 11` |
| L3 | `CONFIG_SECURITY_SELINUX_BOOTPARAM`/`_DEVELOP` off | `androidboot.selinux=` is compiled out and `setenforce` fails | **fixed**: unguarded `enforcing=0` in the cmdline, verified against v4.14.186 `hooks.c` |
| L4 | No `CONFIG_VT` | no console on the panel, no getty | **worked around**: `/dev/kmsg` -> `/proc/last_kmsg` + `/x6812-boot.log`; no getty needed |
| L5 | libdeviceinfo 0.1 has no backlight key, stock leaves 225/4095 | panel readable only in the dark | **fixed**: `x6812-backlight.service` sets half brightness at boot |
| L6 | `resize2fs` run on a f2fs `userdata` | `dumpe2fs` prints nothing and `resize2fs` gets a filesystem it does not understand | **fixed**: the helper returns unless `blkid` says ext4 |
| L7 | `CONFIG_TMPFS_POSIX_ACL` off | logind's `uaccess` ACLs on `/dev/input/event*` fail | **handled**: UT's `65-android.rules` puts `event*` in `android_input` (gid 1004, `phablet` is a member); the checker asserts both. Log noise only |
| L8 | `CONFIG_CGROUP_DEVICE`/`CGROUP_PIDS` off | LXC warnings; no `DeviceAllow`/`TasksMax` | **handled**: the LXC config uses neither; systemd runs without them |
| L9 | `CONFIG_IPC_NS`/`USER_NS` off | LXC cannot create IPC/user namespaces | **handled**: `lxc.namespace.keep = ipc`; the container runs as root so user namespaces are unused |
| L10 | `CONFIG_FHANDLE`/`FANOTIFY`/`SECURITYFS` off | some systemd/AppArmor features unavailable | **not used** by this stack; the container is explicitly `apparmor.profile = unconfined` |
| L11 | `CONFIG_NF_TABLES` off | `iptables-nft` does not work | **already fine**: `/etc/alternatives/iptables` -> `iptables-legacy` |
| L12 | **`CONFIG_BT` off** | no Bluetooth at all - no HCI core and no `BT_HCIVHCI` for bluebinder/vhci | **not fixable here**: needs a kernel rebuild. The BT HAL and `BT_FW.cfg` exist, the kernel side does not |
| L13 | `CONFIG_SQUASHFS` off | no squashfs mounts | **not used**: click 0.5 packages are ar+tar, preinstalled apps are plain directories |
| L14 | `CONFIG_RFKILL` off | no rfkill switch for WiFi | cosmetic; the WMT driver does not need it |
| L15 | MTK `ramoops` params ignored (`CONFIG_ACCESS_RAMOOPS` off, no DT node) | `/sys/fs/pstore` stays empty | **worked around**: MTK `ram_console` -> `/proc/last_kmsg` |
| L16 | `fastboot boot` crashes LK (`lk_crash`) | cannot boot an image without flashing | **worked around**: Track T flashes `boot_a`; stock image is the rollback |
| L17 | Internal `userdata` is f2fs + FBE | initramfs/Android without keys cannot read it | **avoided**: Track T uses the SD as `/userdata`; Track F formats it ext4 (data loss, back up first) |
| L18 | No microSD >= 11 GiB (payload ~9.3 GB) | Track T cannot start | **blocked on hardware**; a USB stick + OTG works (`USB_STORAGE=y`, image with `datapart=/dev/sda`) |
| L19 | `adb root` resets on every reboot | push/build scripts get permission denied | tooling checks `id` first and prints the Developer-options path |
| L20 | PowerShell 5.1 strips inner double quotes | `adb shell` one-liners break | scripts are pushed as files instead of echoed |
| L21 | LK adds `slub_debug=OFZPU`, `page_owner=on`, `console=tty0`, UART off | slower kernel, no serial, noisy cmdline | cannot be changed from the boot image; acceptable for bring-up |
| L22 | Display/touch/WiFi/audio/RIL/camera/GPS/sensors | unverified until first boot | HALs, firmware, modules and permissions pre-checked; see #6 |
| L23 | Host udev has no vendor permissions (Android gets them from `ueventd.rc`) | `/dev/mali0` and `/dev/ion` default to root:root 0660, so libhybris in the phablet session cannot open them - a guaranteed black screen | **fixed**: `usr/lib/udev/rules.d/70-x6812.rules` sets both to 0666 like stock Android, plus the MTK node modes for WMT/CCCI/GPS/audio. Android-only names (`graphics`, `uhid`, `gps`, `log`, `wifi`, `usb`, `vpn`, `nfc`, `media`) were stripped because udev skips a rule whose `OWNER`/`GROUP` does not resolve; `check-rootfs.sh` asserts both the modes and that every remaining name exists |
| L24 | **`CONFIG_SECURITY_APPARMOR` off** | Lomiri App Launch wraps every click app in `aa-exec -p <appid> --`, which fails without apparmorfs - no click app can start. No app confinement either | **worked around**: `usr/bin/aa-exec` shim drops the profile and execs unconfined; the real binary stays at `aa-exec.real` and is used automatically if AppArmor appears. A kernel rebuild is the only way to restore confinement |

---

## 5. The install

Two tracks. **Track T first, always** - it cannot destroy anything except the
test card.

> **`fastboot boot` does not work on this device.** Tested: it downloads the
> image, prints `Booting  FAILED (usb_read failed ...)`, sets
> `ro.boot.bootreason=lk_crash` and falls back to `boot_a`. It does that with
> the stock image too, so it is the bootloader, not our image. Track T therefore
> **flashes** `boot_a`; the stock image is the rollback.

### 5.1 Track T - test boot from a microSD card

Requirements: one spare microSD (**11 GB+**, it will be wiped; 32 GB is the
comfortable size because the card also holds all writable UT data), USB cable,
~30 minutes, and **Rooted debugging** enabled so `adb shell` is root.

No card? A USB stick in an OTG adapter works the same way: the kernel has
`USB_MTK_HDRC`, `USB_MTK_OTG`, `USB_STORAGE`, `SCSI` and `BLK_DEV_SD`, so the
stick shows up as `/dev/sda` in the initramfs. Build a boot image whose cmdline
says `datapart=/dev/sda` instead of `/dev/mmcblk1` (`tools/build-boot.py` takes
`--cmdline`), and prepare the stick with `tools/track-t.sh /dev/block/sda` from
Android. If you have neither card nor stick, skip to #5.2 - but back up first.

```powershell
# on Windows, in C:\Users\tanisha\projects\x6812-ut
python tools\convert-rootfs.py        # .tar.xz -> .tar.gz (Android tar has no xz)
powershell -File tools\push-install.ps1 -NoRun
```

`/data` is only writable by a root adbd, and the setting is lost on every reboot:
**Settings -> System -> Developer options -> Rooted debugging**, then `adb root`.
`tools/push-install.ps1` checks this first and stops with that message.

```sh
# on the phone (adb shell, root) - formats the whole card and builds the images
sh /data/track-t.sh /dev/block/mmcblk1
```

`tools/track-t.sh` checks that the card is really there, refuses anything under
11 GiB, formats it, mounts it and calls `install-x6812.sh` with the card as the
target (which also copies `android-rootfs.img` and `vendor.img` onto it).

Format the **whole card**, not a partition: the initramfs resize helper reads
`/proc/partitions`, and a card with a partition table makes it see both
`mmcblk1` and `mmcblk1p1`.

```powershell
powershell -File tools\flash-track-t.ps1     # flash + reboot + wait
```

That is just `fastboot flash boot out\halium-boot-sd.img` plus the waiting, and
it is the only way in, because `fastboot boot` crashes this bootloader. The card
must stay inserted: the image's cmdline says `datapart=/dev/mmcblk1`, so it still
boots from the card.

If the initramfs does not get far enough to mount the card it panics and does
**not** reboot by itself. Because there is no VT, the panel shows nothing; boot
Android again and read `/proc/last_kmsg` (see #6). Get back to fastboot with:
hold **Volume Down**, then connect USB / press power (or `adb reboot
bootloader` when Android is up), and run:

```powershell
powershell -File tools\flash-track-t.ps1 -Restore
```

### 5.2 Track F - real install on `userdata`

Only after Track T reaches **G3**.

```sh
# from a terminal on the running UT system (ssh or the Lomiri terminal)
sudo mkfs.ext4 -L userdata -m 0 /dev/disk/by-name/userdata
sudo mount /dev/disk/by-name/userdata /mnt
sudo cp /media/$USER/utdata/{rootfs.img,android-rootfs.img,vendor.img} /mnt/
sync
sudo umount /mnt
sudo poweroff
```

```powershell
# remove the SD card first
adb reboot bootloader
fastboot flash boot out\halium-boot.img
fastboot reboot
```

### 5.3 What we will not touch

- `super`, `system`, `vendor`, `product`, `system_ext` - read-only, untouched.
- `boot_b`, `vbmeta*`, `dtbo*`, `persist`, `nvram`, `nvdata`, `nvcfg` - untouched.
- The stock `boot_a` stays in `out/stock-boot_a.img` for rollback.

---

## 6. First boot - how to read the result

The phone has no UART and **no usable pstore**, so the logs go to the data
partition (see #4.4). After a failed boot: power the phone off and on normally,
let Android come up, keep the card inserted, then:

```powershell
powershell -File tools\pull-card-log.ps1
```

That pulls the two card logs plus `last_kmsg.txt` into
`out\boot-logs\<timestamp>\`. The channels, in order of usefulness:

1. **`/proc/last_kmsg`** - MTK `ram_console`, survives the failed boot and holds
   the kernel log, the initramfs `tell_kmsg` lines (through `/dev/kmsg`) and the
   journald `ForwardToKMsg` lines. Read it from Android after `adb root`.
2. **`/x6812-boot.log`** on the card - every Halium initramfs message after the
   data partition mounts, including the panic reason.
3. **`/x6812-journal.log`** on the card - the full systemd/LXC/Lomiri journal,
   written by `x6812-log.service` from the moment journald is up.
4. **Screen** - nothing. `console=tty0` has no effect because `CONFIG_VT` is off.

```powershell
adb root
adb shell cat /proc/last_kmsg
```

If the boot dies before the data partition mounts, `/x6812-boot.log` has nothing
and `last_kmsg` is the only source - which is exactly why the `/dev/kmsg` node
was added. Do **not** expect anything in `/sys/fs/pstore`; it stays empty on this
kernel.

| Symptom | Meaning | Next action |
|---|---|---|
| `fastboot boot` fails or returns immediately | normal on this device: this LK crashes with `lk_crash` | always flash: `powershell -File tools\flash-track-t.ps1` |
| Kernel log stops before "Halium rootfs is ..." | initramfs problem (devtmpfs patch) | `/proc/last_kmsg`, then `x6812-boot.log` |
| `PANIC: Couldn't find data partition` | the SD card is not inserted or enumerated as another node | reinsert, check `/dev/block/mmcblk1`, then `halium-boot-sd.img` |
| `Failed to mount Android system.img` | `android-rootfs.img` missing / not ext4 | verify `/mnt/sd/android-rootfs.img` |
| Rootfs boots, no UI, but `ping 192.168.2.15` answers | display stack failed | `x6812-journal.log`, then `journalctl -b -u lxc-android-config` |
| `lxc-start` errors | LXC/cgroup/binder | `lxc-checkconfig`, `ls /dev/binder*` |
| Container runs, no vendor | HALs missing | `ls /android/vendor/etc/init/hw/init.mt6768.rc` |
| UI up, touch dead | udev did not put `event*` in `android_input` | `ls -l /dev/input/event*` (root:android_input 0660), `id phablet` |
| UI up, screen very dim / looks black | backlight left at the stock 225/4095 | `systemctl status x6812-backlight`, `cat /sys/class/leds/lcd-backlight/brightness` |

First boot is slow: 5-15 minutes (container first start + dexopt). Do not judge
before 15 minutes.

---

## 7. Risk register

| # | Risk | Why it bites | Mitigation / knob |
|---|---|---|---|
| 1 | No `CONFIG_DEVTMPFS` | `/dev` empty -> nothing mounts | **done**: patched `/init` creates tmpfs `/dev` + static nodes; udev creates the rest |
| 2 | No `SYSVIPC` / `IPC_NS` | Android and LXC want IPC namespaces | **done**: `lxc.namespace.keep = ipc` appended by `install-x6812.sh` |
| 3 | No `CGROUP_DEVICE` / `CGROUP_PIDS` | LXC prints warnings | UT's container config does not use them; ignore |
| 4 | Dynamic partitions | no `/dev/disk/by-name/vendor` | **done**: `vendor.img` loop-mounted at `/android/vendor` by `mount-vendor.sh`, then partitions re-scanned |
| 5 | VNDK mismatch | system/vendor ABI break | both are API 30 - do not upgrade the Android image to 12/13 |
| 6 | SELinux enforcing | vendor policy blocks the Halium system; `androidboot.selinux=` is compiled out and `setenforce` fails | **done**: `enforcing=0` in the cmdline (unguarded `__setup`, verified in v4.14.186 source) |
| 7 | Radio interface | merlin uses `radio@1.4`, this vendor has `@1.5` | `mtk.conf` already points at `radio@1.5` |
| 8 | Composer 2.1 + libhybris | black screen | UT 20.04 uses Mir's `graphics-android2` (HWC2 native), so no HWC1 fallback is needed; `MIR_ANDROID_FORCE_HWC2=1` is kept as a no-op hint |
| 9 | cgroup v2 only | LXC 4.0 needs care | no `devices` cgroup rules in the UT config; verify with `lxc-checkconfig` |
| 10 | WiFi firmware path | kernel looks in `/vendor/firmware` on the **host** | **done**: `/vendor` is a symlink to `/android/vendor`, and the modules are loaded from `mount-vendor.sh` *after* it is mounted |
| 11 | Modules not loaded | WiFi/BT/GPS dead | **done**: `mount-vendor.sh` modprobes the nine modules; `modules-load.d/x6812.conf` remains as fallback |
| 11a | fs_mgr-only fstab flags | `metadata`/`persist`/`nvdata`/`nvcfg`/`protect*` never mount -> no radio | **done**: `mount-vendor.sh` bind-mounts a cleaned fstab over `/vendor/etc/fstab.mt6768` |
| 11b | Rootfs has no `phablet` user | lightdm autologin loops back to the greeter, no session | **done**: `install-x6812.sh` creates uid 32011 in `passwd`/`group`/`shadow` |
| 12 | Touch not tagged | pointer but no touch; `CONFIG_TMPFS_POSIX_ACL` is off, so logind `uaccess` ACLs fail | UT's `65-android.rules` maps `event*` to group `android_input` (gid 1004, `phablet` is a member); `check-rootfs.sh` asserts rule + membership |
| 13 | Audio policy | no sound | start with the **stock vendor** policy; merlin's MTK policy is the fallback |
| 14 | Camera / GPS | least likely to work | accept, or port later |
| 15 | Wrong deviceinfo profile | wrong grid unit / no backlight | selection is `ro.product.vendor.device`, which this vendor sets to `Infinix-X6812` - the yaml is named exactly that |
| 16 | No pstore | after a failed boot there is no kernel log | **done**: `/dev/kmsg` node -> `/proc/last_kmsg`, plus `/x6812-boot.log` and `/x6812-journal.log` on the data partition; `tools/pull-card-log.ps1` reads them block-by-block |
| 17 | `fastboot boot` rejected | **confirmed**: this LK crashes with `lk_crash` even for the stock image and falls back to `boot_a` | Track T flashes `boot_a` instead (`tools/flash-track-t.ps1`), rollback `-Restore` |
| 18 | **Bluetooth unsupported** | `CONFIG_BT` and `CONFIG_BT_HCIVHCI` are off, so bluebinder/vhci cannot create an HCI device | not fixable in a prebuilt-kernel port; needs a kernel rebuild (see L12) |
| 19 | No on-screen log | a failed boot looks like a dead phone | **done**: `/dev/kmsg` -> `/proc/last_kmsg` + card logs; see #4.4 |
| 20 | Backlight too dim | UI invisible in daylight | **done**: `x6812-backlight.service` sets half brightness |
| 21 | Black screen from node permissions | host udev defaults `/dev/mali0` and `/dev/ion` to root:root 0660; stock Android has 0666 | **done**: `70-x6812.rules` sets both to 0666 (and restores the other MTK node modes); Android-only owner/group names were removed so udev actually applies each rule; checker asserts both |
| 22 | No app starts | kernel has no AppArmor, so UAL's `aa-exec -p <appid>` fails | **done**: `aa-exec` shim strips the profile and execs unconfined; real binary kept for a future kernel. Apps are unconfined - acceptable for bring-up |

**Most likely first failure: the display (row 8).** That is the gate to attack
first, and the reason Track T exists.

---

## 8. Rollback

```powershell
# Track T: nothing to roll back, just remove the SD card and reboot
adb reboot

# Track F
fastboot flash boot out\stock-boot_a.img
fastboot -w                 # reformats userdata the way Android expects
fastboot reboot
```

`fastboot -w` erases `userdata`. **Back up photos/files before Track F.**
Track T never needs this.

---

## 9. Effort

| Milestone | Time |
|---|---|
| Track T images built | 30-45 min (mostly on-device extraction) |
| First boot attempt + logs | 1 h |
| G3 (something on screen) | 1-3 evenings, if it happens at all |
| G4 (touch/WiFi/audio) | +2-5 evenings |
| G5 (calls, camera) | weeks, uncertain |

---

## 10. Next three actions

1. Insert a microSD card (11 GB+, it will be wiped), enable **Rooted debugging**
   (Settings -> System -> Developer options), run `adb root`, then
   `powershell -File tools\push-install.ps1 -NoRun` (refreshes the on-phone
   scripts) and `adb shell sh /data/track-t.sh` - it formats the card as one
   ext4 filesystem and builds `rootfs.img` + copies the two images onto it.
2. `powershell -File tools\flash-track-t.ps1` - flashes `boot_a` (the only way
   in, `fastboot boot` crashes this LK), reboots, waits. The panel stays dark
   until Lomiri paints, so do not read anything into a black screen; first boot
   needs 5-15 minutes.
3. If nothing comes up after ~15 minutes: `-Restore` to get Android back, then
   `adb root` + `adb shell cat /proc/last_kmsg` and
   `powershell -File tools\pull-card-log.ps1`; fix exactly one thing at a time
   from #6.

Everything that can be prepared without the card is already done: the boot
images are built and verified, `/data/rootfs.img` is built and the checker
passes, `track-t.sh` is on the phone, and the boot log has a place to go.

Nothing in this plan touches `userdata` until #5.2, and `boot_a` is restored by
one flash of `out/stock-boot_a.img`.
