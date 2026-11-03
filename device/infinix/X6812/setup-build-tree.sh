#!/bin/bash
# =============================================================================
#  X6812 Halium 11 build-tree setup  (run inside WSL2 / native Ubuntu Linux)
#
#  Usage:   bash setup-build-tree.sh
#  Result:  ~/halium/out/target/product/X6812/halium-boot.img
#           ~/halium/out/target/product/X6812/system.img
#
#  The device tree itself lives on the Windows side and is copied in, so this
#  script can be re-run at any time to refresh it.
# =============================================================================
set -euo pipefail

BUILDDIR="${BUILDDIR:-$HOME/halium}"
DEVICE_SRC="${DEVICE_SRC:-/mnt/c/Users/tanisha/projects/x6812-ut/device/infinix/X6812}"
JOBS="${JOBS:-$(nproc)}"

echo "==> build dir : $BUILDDIR"
echo "==> device tree: $DEVICE_SRC"
echo "==> jobs      : $JOBS"

# ---------------------------------------------------------------- dependencies
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
    bc bison build-essential ccache curl flex g++-multilib gcc-multilib git \
    gnupg gperf imagemagick lib32ncurses-dev lib32readline-dev lib32z1-dev \
    libelf-dev liblz4-tool libncurses-dev libsdl1.2-dev libssl-dev libxml2 \
    libxml2-utils lzop pngcrush rsync schedtool squashfs-tools xsltproc zip \
    zlib1g-dev python3 python-is-python3 openjdk-11-jdk-headless repo cpio \
    e2fsprogs android-sdk-libsparse-utils

# Ubuntu 22.04 dropped libncurses5; AOSP 11 host tools still link against it.
if ! ldconfig -p | grep -q libncurses.so.5; then
    echo "==> libncurses5 missing, adding focal repo (22.04 workaround)"
    echo "deb http://archive.ubuntu.com/ubuntu focal universe" \
        | sudo tee /etc/apt/sources.list.d/focal-universe.list
    sudo apt-get update
    sudo apt-get install -y libncurses5 libtinfo5 || true
fi

# ------------------------------------------------------------------ repo sync
mkdir -p "$BUILDDIR"
cd "$BUILDDIR"

# repo refuses to init without an identity
git config --global user.name  >/dev/null 2>&1 || git config --global user.name  "X6812 port"
git config --global user.email >/dev/null 2>&1 || git config --global user.email "port@localhost"

if [ ! -d .repo ]; then
    repo init -u https://github.com/Halium/android -b halium-11.0 --depth=1
fi
repo sync -c -j"$JOBS" --force-sync --no-clone-bundle --no-tags

# ------------------------------------------------------------- copy device tree
rm -rf device/infinix/X6812
mkdir -p device/infinix
cp -a "$DEVICE_SRC" device/infinix/X6812
echo "==> device tree copied: $(find device/infinix/X6812 -type f | wc -l) files"

# ------------------------------------------------------------- hybris patches
if [ -x hybris-patches/apply-patches.sh ]; then
    ( cd hybris-patches && ./apply-patches.sh --mb )
fi

# ---------------------------------------------------------------------- build
export USE_HOST_LEX=yes
export LC_ALL=C
source build/envsetup.sh
lunch halium_X6812-userdebug

echo "==> building halium-boot.img"
mka halium-boot -j"$JOBS"

echo "==> building system.img (Android side for the LXC container)"
mka systemimage -j"$JOBS"

echo
echo "==> done. artifacts:"
ls -lh out/target/product/X6812/halium-boot.img out/target/product/X6812/system.img
