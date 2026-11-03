# ============================================================================
#  Halium 11 device tree — Infinix Hot 11s (X6812)
#  SoC: MediaTek Helio G88 (MT6768 / MT6769H, dacode 0x6768)
#
#  ALL VALUES BELOW ARE VERIFIED FROM THE DEVICE ITSELF (2026-11-03):
#    - boot_a.img header parsed  -> kernel/ramdisk/tags/dtb offsets, page size
#    - /proc/cmdline             -> runtime cmdline
#    - /dev/block/by-name        -> physical layout + partition sizes
#    - /proc/config.gz           -> 5324-line kernel config
#    - /vendor/lib/modules/*.ko  -> vermagic 4.14.186-g8ed8f1a9884b-dirty
# ============================================================================

DEVICE_PATH := device/infinix/X6812

# ---------------------------------------------------------------- Architecture
TARGET_ARCH          := arm64
TARGET_ARCH_VARIANT  := armv8-a
TARGET_CPU_ABI       := arm64-v8a
TARGET_CPU_ABI2      :=
TARGET_CPU_VARIANT   := generic
TARGET_2ND_ARCH      := arm
TARGET_2ND_ARCH_VARIANT := armv8-a
TARGET_2ND_CPU_ABI   := armeabi-v7a
TARGET_2ND_CPU_ABI2  := armeabi
TARGET_2ND_CPU_VARIANT := generic

TARGET_USES_64_BIT_BINDER := true
TARGET_SUPPORTS_32_BIT_APPS := true
TARGET_SUPPORTS_64_BIT_APPS := true

TARGET_BOARD_PLATFORM := mt6768
TARGET_BOOTLOADER_BOARD_NAME := mt6768
TARGET_OTA_ASSERT_DEVICE := X6812,Infinix-X6812,mt6768

# ------------------------------------------------------------------- Boot image
# Parsed from stock boot_a.img (header v2):
#   kernel_addr  = 0x40080000
#   ramdisk_addr = 0x47C80000
#   tags_addr    = 0x4BC80000
#   dtb_addr     = 0x4BC80000
#   page_size    = 2048
BOARD_KERNEL_BASE        := 0x40078000
BOARD_KERNEL_OFFSET      := 0x00008000
BOARD_RAMDISK_OFFSET     := 0x07c08000
BOARD_TAGS_OFFSET        := 0x0bc08000
BOARD_DTB_OFFSET         := 0x0bc08000
BOARD_KERNEL_PAGESIZE    := 2048
BOARD_BOOT_HEADER_VERSION := 2
# --dtb is required: the stock boot.img carries a 118458-byte DTBO table
# (1 entry, "mediatek,MT6768-mcdi") in its header-v2 dtb section. Without it
# the built image would differ from stock and LK may not pick the right DTB.
BOARD_MKBOOTIMG_ARGS     := --header_version $(BOARD_BOOT_HEADER_VERSION) \
                            --dtb $(DEVICE_PATH)/prebuilt/dtbo.img

# cmdline: from boot header (offset 64). Runtime /proc/cmdline has extra
# androidboot.* entries injected by LK -- those must NOT be baked in here.
BOARD_KERNEL_CMDLINE := bootopt=64S3,32N2,64N2 buildvariant=user

# ------------------------------------------------------------------- Partitions
# Sizes read with blockdev from /dev/block/by-name/<name>
BOARD_BOOTIMAGE_PARTITION_SIZE  := 33554432     # 32 MB
BOARD_DTBOIMG_PARTITION_SIZE    := 8388608      # 8 MB
BOARD_SUPER_PARTITION_SIZE      := 7345774592   # 7001 MB
BOARD_SUPER_PARTITION_GROUPS    := main
BOARD_MAIN_SIZE                 := 7345774592

BOARD_USES_METADATA_PARTITION   := true
BOARD_SUPER_PARTITION_METADATA_DEVICE := super

# Dynamic partitions (verified: ro.boot.dynamic_partitions=true)
BOARD_USES_DYNAMIC_PARTITIONS   := true
BOARD_DYNAMIC_PARTITION_ENABLE  := true

# A/B (verified: ro.build.ab_update=true, slot-count=2)
AB_OTA_UPDATER                  := true
BOARD_USES_RECOVERY_AS_BOOT     := false
BOARD_HAS_NO_SELECT_BUTTON      := true

# NOTE: vendor_boot_a exists (mmcblk0p29, 64 MB) but is COMPLETELY EMPTY
# (verified: all zeros). This device uses the legacy layout where the vendor
# ramdisk bits live inside boot_a. Do NOT enable BOARD_USES_VENDOR_BOOT.

# ----------------------------------------------------------------- Prebuilt bits
TARGET_PREBUILT_KERNEL  := $(DEVICE_PATH)/prebuilt/Image
BOARD_PREBUILT_DTBOIMAGE := $(DEVICE_PATH)/prebuilt/dtbo.img
BOARD_INCLUDE_DTB_IN_BOOTIMG := false

# Kernel modules (vermagic 4.14.186-g8ed8f1a9884b-dirty — must stay in sync)
BOARD_VENDOR_KERNEL_MODULES := \
    $(DEVICE_PATH)/prebuilt/modules/bt_drv.ko \
    $(DEVICE_PATH)/prebuilt/modules/fmradio_drv.ko \
    $(DEVICE_PATH)/prebuilt/modules/fpsgo.ko \
    $(DEVICE_PATH)/prebuilt/modules/gps_drv.ko \
    $(DEVICE_PATH)/prebuilt/modules/met.ko \
    $(DEVICE_PATH)/prebuilt/modules/tran_fre.ko \
    $(DEVICE_PATH)/prebuilt/modules/udc_lib.ko \
    $(DEVICE_PATH)/prebuilt/modules/wlan_drv_gen4m.ko \
    $(DEVICE_PATH)/prebuilt/modules/wmt_chrdev_wifi.ko \
    $(DEVICE_PATH)/prebuilt/modules/wmt_drv.ko

# ---------------------------------------------------------------------- System
BOARD_SYSTEMIMAGE_PARTITION_TYPE   := ext4
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE := ext4

TARGET_COPY_OUT_VENDOR  := vendor
TARGET_COPY_OUT_PRODUCT := product
TARGET_COPY_OUT_SYSTEM_EXT := system_ext

BOARD_PROPERTY_OVERRIDES_SPLIT_ENABLED := true
TARGET_SYSTEM_PROP := $(DEVICE_PATH)/system.prop

# -------------------------------------------------------------------- Recovery
TARGET_RECOVERY_PIXEL_FORMAT := "ABGR_8888"
BOARD_USE_FRAMEBUFFER_ALPHA_CHANNEL := true
TARGET_DISABLE_TRIPLE_BUFFERING := false

# ----------------------------------------------------------------------- SELinux
BOARD_SEPOLICY_DIRS += $(DEVICE_PATH)/sepolicy/vendor
BOARD_PLAT_POLICY_DIRS += $(DEVICE_PATH)/sepolicy/system

# ------------------------------------------------------------------ Halium
# Halium needs the vendor HAL bits from the stock /vendor (already dumped:
# out/vendor.tar, 843 MB). See STAGE2-PLAN.md.
TARGET_USES_HYBRIS := true
