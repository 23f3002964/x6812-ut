# Stage 2 — Halium 11 bring-up for Infinix Hot 11s (X6812)

Status: **boot images built and verified; the Android side is solved with a
prebuilt Halium 11 image, so no Linux build host is needed.** The current plan,
options and probabilities live in [`ROM-PLAN.md`](ROM-PLAN.md). This file keeps
the Stage 2 build/verification reference values.

---

## 1. What is already done

| Item | State |
|---|---|
| Stock `boot_a.img` backup | `out/stock-boot_a.img` (32 MB, sha256 `2E5E01A8…EBC310`) |
| Stock kernel `Image.gz` (in boot header) | `out/boot-unpacked/kernel.gz`, 9 658 619 B, gzip → 26 699 776 B `Image` |
| Stock DTBO table from boot header | `out/dtb.bin`, 118 458 B, 1 entry `mediatek,MT6768-mcdi` |
| Kernel modules | `device/infinix/X6812/prebuilt/modules/` (10 used + `kheaders.ko`) |
| Vendor blobs | `out/vendor.tar`, 843 MB, 2110 files |
| Kernel config | `out/kconfig.txt` (5324 lines, `CONFIG_IKCONFIG=y`) |
| Halium initramfs | `tools/initramfs/halium-initramfs.gz` (4 106 247 B, arm64, 347 cpio entries) |
| Patched initramfs | `out/halium-initramfs-x6812.gz` — devtmpfs fallback (see §5) |
| **halium-boot.img** | **`out/halium-boot.img`, 13 881 344 B, sha256 `3F26C419…C2C6C0`** |
| Verification | `tools/verify_boot.py` → **PASS** (kernel + dtb byte-identical, header fields identical) |

Build/verify commands (pure Windows, no WSL needed):

```powershell
python tools\mkbootimg.py `
  --kernel out\boot-unpacked\kernel.gz `
  --ramdisk out\halium-initramfs-x6812.gz `
  --dtb out\dtb.bin `
  --cmdline "bootopt=64S3,32N2,64N2 buildvariant=user" `
  --base 0x40078000 --kernel_offset 0x8000 --ramdisk_offset 0x07c08000 `
  --tags_offset 0x0bc08000 --dtb_offset 0x0bc08000 `
  --pagesize 2048 --header_version 2 `
  --os_version 11.0.0 --os_patch_level 2023-08 `
  --board CY-X6812-H6912- `
  --output out\halium-boot.img

python tools\verify_boot.py out\stock-boot_a.img out\halium-boot.img
```

Why this is safe: the kernel and DTB are copied bit-for-bit from the stock
boot image. Only the ramdisk (Android recovery ramdisk → Halium initramfs) is
replaced. Reverting means `fastboot flash boot out\stock-boot_a.img`.

---

## 2. Device tree layout

```
device/infinix/X6812/
├── AndroidProducts.mk        # lunch choices
├── BoardConfig.mk            # addresses, partitions, prebuilt kernel/modules
├── device.mk                 # module/firmware copies
├── halium_X6812.mk           # product definition
├── system.prop               # vendor API level 30, A/B, mt6768
├── prebuilt/
│   ├── Image                 # stock decompressed kernel (reference)
│   ├── dtbo.img              # 118 458 B DTBO table from boot header
│   └── modules/*.ko          # vermagic 4.14.186-g8ed8f1a9884b-dirty
├── rootdir/etc/fstab.mt6768  # stock layout, reference only
├── sepolicy/                 # empty on purpose (see README)
└── setup-build-tree.sh       # WSL/Linux: repo init + sync + build
```

`BoardConfig.mk` deliberately does **not** enable `BOARD_USES_VENDOR_BOOT`:
`vendor_boot_a` (64 MB) is entirely zeroed on this device, the vendor ramdisk
lives inside `boot_a`.

---

## 3. How the Halium initramfs finds the rootfs

From `out/halium-initramfs/scripts/halium` (347-entry prebuilt arm64 initramfs):

* `/data` is found by name (`userdata`, `UDA`, `DATAFS`, `USERDATA`) — the
  plain `userdata` entry exists on this device (`/dev/block/mmcblk0p47`).
* Three layouts are supported:
  1. **`/data/rootfs.img`** → `rootfs.img` + Android `system.img` stored as
     files (`file_layout=halium`)
  2. `/data/halium-rootfs/` directory (`file_layout=subdir`)
  3. rootfs on the `system` partition (`systempart=` on the cmdline)
* `/dev/loop` must exist for layout 1; the stock cmdline already contains
  `loop.max_part=7`, so loop support is compiled in.

**Chosen first bring-up path: layout 1 (`/data/rootfs.img`).** It needs no
change to `super`, so the Android GSI on slot A stays intact and restoring is
just reflashing `boot_a`.

Caveat: `/data` is currently f2fs + Android FBE. Halium expects a plain ext4
`userdata`, so the real install will format `userdata` (wipes apps/photos —
back them up first). That is a one-way step, do it only after the boot image
has been test-booted.

---

## 4. Remaining work

### 4.1 Linux build host (needed for `system.img`)

Halium runs Android in an LXC container; `system.img` is built from the Halium
11 tree. This cannot be done on Windows.

State: `wsl --install --no-distribution` ran elevated and enabled the optional
features, but Windows reports `RebootPending = True`. **One PC reboot is
required** before WSL2 can start (VT-x is on: VBS/HVCI is already running).

```powershell
# after reboot
wsl --install -d Ubuntu-22.04 --no-launch
wsl -l -v                        # expect VERSION 2
```

Inside WSL:

```bash
bash /mnt/c/Users/tanisha/projects/x6812-ut/device/infinix/X6812/setup-build-tree.sh
```

Budget: ~35–60 GB disk, 4–8 GB RAM for the build (15.7 GB host is fine, use
`-j4`..`-j6`), several hours on first sync+build.

Produces:
* `out/target/product/X6812/halium-boot.img` (should match the Windows build —
  same kernel, same dtb, same cmdline; only the initramfs download may differ
  by release)
* `out/target/product/X6812/system.img` → goes to
  `/data/system.img` or the rootfs' `/var/lib/lxc/android/system.img`

### 4.2 Ubuntu Touch rootfs (arm64, halium)

Rootfs tarball from the UBports system-image server (20.04 focal arm64,
`pool/rootfs-*.tar.xz`, 471 MB, signed), unpacked into an ext4 image:

```bash
sudo bash tools/make-rootfs-img.sh
# -> out/rootfs/focal-arm64-rootfs.tar.xz (download)
# -> out/rootfs/rootfs.img            (ext4, label rootfs, ~3 GB)
```

The script also drops the 10 stock `.ko` files into
`/lib/modules/4.14.186-g8ed8f1a9884b-dirty/` and runs `depmod`.

### 4.3 First boot test (no flashing)

```powershell
adb reboot bootloader
fastboot devices
fastboot boot out\halium-boot.img      # temporary, does not write flash
```

Expected on success: Halium initramfs starts, `/init.log` on the ramdisk,
telnet debug on `192.168.2.15:23` (RNDIS/USB net) with `break=premount` style
debugging. Without `rootfs.img` it will stop at "Couldn't find data partition"
or fail the rootfs mount — that still proves kernel+initramfs work.

If `fastboot boot` is rejected by MTK LK, fall back to:

```powershell
fastboot flash boot out\halium-boot.img
fastboot reboot
# restore:
fastboot flash boot out\stock-boot_a.img
```

### 4.4 Modules inside the rootfs

The kernel has no published source, so modules cannot be rebuilt. Ship the
stock ones at the versioned path inside the rootfs:

```
/lib/modules/4.14.186-g8ed8f1a9884b-dirty/
    bt_drv.ko fmradio_drv.ko fpsgo.ko gps_drv.ko met.ko tran_fre.ko
    udc_lib.ko wlan_drv_gen4m.ko wmt_chrdev_wifi.ko wmt_drv.ko
    modules.dep modules.alias modules.load modules.softdep
```

`modules.dep` must be regenerated inside Linux (`depmod -b <rootfs> 4.14.186-g8ed8f1a9884b-dirty`).

---

## 5. Stock kernel feature audit (important)

The kernel cannot be rebuilt (no source), so its config is a hard limit.
Checked against `out/kconfig.txt`:

| Option | State | Consequence |
|---|---|---|
| `CONFIG_DEVTMPFS` | **not set** | Halium initramfs mounts devtmpfs unconditionally → **patched** (tmpfs /dev + static nodes, udev populates the rest) |
| `CONFIG_SYSVIPC` | **not set** | no System V IPC → `CONFIG_IPC_NS` is therefore absent too |
| `CONFIG_IPC_NS` | absent | LXC normally clones an IPC namespace for the Android container |
| `CONFIG_CGROUP_DEVICE` | not set | Android init / LXC device cgroup unavailable |
| `CONFIG_CGROUP_PIDS` | not set | Android init pids cgroup unavailable |
| `CONFIG_FHANDLE` | absent | systemd lists it as required; it does have a mountinfo fallback |
| `CONFIG_POSIX_MQUEUE` | not set | some userspace services degrade |
| `CONFIG_CGROUP_BPF`, `MEMCG`, `CPUSETS`, `BLK_CGROUP` | y | good |
| `CONFIG_ANDROID_BINDER_IPC`, `ASHMEM`, `ION`, `DMA_SHARED_BUFFER` | y | Android container plumbing present |
| `CONFIG_SECCOMP`, `SECCOMP_FILTER` | y | good |

**Realistic expectation:** the Ubuntu Touch rootfs itself should reach userspace
(the devtmpfs gap is patched). The Android LXC container — which provides
camera, RIL/VoLTE, sensors and the vendor WiFi HAL — may fail to start because
`IPC_NS`/`SYSVIPC` and the device cgroup are missing. That would leave a
UI-only port until a kernel with those options can be built.

Possible mitigations to try at boot time (no kernel change):
* `lxc.namespace.keep = ipc` in the container config (LXC ≥ 4.0), if UT's LXC
  version supports it;
* dropping device-cgroup rules from the container config;
* accepting a degraded container (binder/ashmem still work).

This is the single biggest unknown left; it can only be answered by booting.

## 6. Risk list

| Risk | Impact | Mitigation |
|---|---|---|
| MTK LK ignores header-v2 boot dtb and expects dtbo partition | no boot | `dtbo_a` is untouched stock; it already contains the same table |
| `fastboot boot` unsupported | can't test-boot | flash `boot_a`, restore from `stock-boot_a.img` |
| AVB / vbmeta mismatch | bootloop, orange state | bootloader already unlocked (`verifiedbootstate=orange`); reflash stock boot on failure |
| Formatting `userdata` for ext4 | data loss | last step, after backup; not needed to test initramfs |
| Dynamic `super` untouched | Android GSI keeps working | chosen on purpose |
| No kernel source | can't fix kernel bugs | prebuilt-kernel port; document as limitation |

---

## 7. Reference values (verified on device, 2026-11-03)

```
SoC              MediaTek Helio G88 (MT6768 / MT6769H)
Kernel           4.14.186-g8ed8f1a9884b-dirty  (gzip Image.gz in boot_a)
Vendor build     230921V645, patch 2023-08-05, API level 30
Boot header v2   kernel 0x40080000  ramdisk 0x47C80000  tags/dtb 0x4BC80000
                 page 2048  name CY-X6812-H6912-  dtb 118458 B
Partitions       boot_a 33554432  dtbo_a 8388608  vbmeta_a 8388608
                 super 7345774592  vendor_boot_a 67108864 (all zeros)
Block nodes      userdata mmcblk0p47  super mmcblk0p45  metadata mmcblk0p14
                 md_udc   mmcblk0p13  boot_a mmcblk0p28  dtbo_a mmcblk0p30
```
