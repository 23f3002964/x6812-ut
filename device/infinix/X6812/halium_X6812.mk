#
# Halium 11 product definition — Infinix Hot 11s (X6812)
#
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/embedded.mk)

$(call inherit-product, $(DEVICE_PATH)/device.mk)

# Halium system image contents (Android 11 in the LXC container)
$(call inherit-product, vendor/halium/config/halium.mk)

PRODUCT_NAME        := halium_X6812
PRODUCT_DEVICE      := X6812
PRODUCT_BRAND       := Infinix
PRODUCT_MODEL       := Infinix X6812
PRODUCT_MANUFACTURER := Infinix

PRODUCT_GMS_CLIENTID_BASE := android-infinix
