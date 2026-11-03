#
# device.mk — Infinix Hot 11s (X6812)
#
LOCAL_PATH := device/infinix/X6812

# ---- Kernel modules (prebuilt, vermagic 4.14.186-g8ed8f1a9884b-dirty) ----
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/prebuilt/modules/bt_drv.ko:$(TARGET_COPY_OUT_VENDOR)/lib/modules/bt_drv.ko \
    $(LOCAL_PATH)/prebuilt/modules/fmradio_drv.ko:$(TARGET_COPY_OUT_VENDOR)/lib/modules/fmradio_drv.ko \
    $(LOCAL_PATH)/prebuilt/modules/fpsgo.ko:$(TARGET_COPY_OUT_VENDOR)/lib/modules/fpsgo.ko \
    $(LOCAL_PATH)/prebuilt/modules/gps_drv.ko:$(TARGET_COPY_OUT_VENDOR)/lib/modules/gps_drv.ko \
    $(LOCAL_PATH)/prebuilt/modules/met.ko:$(TARGET_COPY_OUT_VENDOR)/lib/modules/met.ko \
    $(LOCAL_PATH)/prebuilt/modules/tran_fre.ko:$(TARGET_COPY_OUT_VENDOR)/lib/modules/tran_fre.ko \
    $(LOCAL_PATH)/prebuilt/modules/udc_lib.ko:$(TARGET_COPY_OUT_VENDOR)/lib/modules/udc_lib.ko \
    $(LOCAL_PATH)/prebuilt/modules/wlan_drv_gen4m.ko:$(TARGET_COPY_OUT_VENDOR)/lib/modules/wlan_drv_gen4m.ko \
    $(LOCAL_PATH)/prebuilt/modules/wmt_chrdev_wifi.ko:$(TARGET_COPY_OUT_VENDOR)/lib/modules/wmt_chrdev_wifi.ko \
    $(LOCAL_PATH)/prebuilt/modules/wmt_drv.ko:$(TARGET_COPY_OUT_VENDOR)/lib/modules/wmt_drv.ko

# ---- Halium initramfs ----
# Nothing to copy: the `halium-boot` target downloads the generic Ubuntu Touch
# initramfs (initrd.img-touch-arm64) from Halium/initramfs-tools-halium.
# Only add BOARD_USE_LOCAL_INITRD + initramfs.gz here if that initramfs has to
# be patched for this device.

# ---- Firmware ----
# Stock firmware is inside out/vendor.tar (vendor/firmware). Halium needs it
# mounted from the real /vendor at runtime — do not duplicate it here.

# ---- Properties ----
PRODUCT_PROPERTY_OVERRIDES += \
    ro.halium.device=X6812 \
    ro.halium.soc=mt6768 \
    ro.halium.arch=arm64 \
    ro.halium.vendor_api_level=30
