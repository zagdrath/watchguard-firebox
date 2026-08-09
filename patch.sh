#!/bin/bash
set -e

# ========== CONFIGURATION ==========
SERIAL=FVE117F24D510
PART_SYS=/dev/sdb2
PART_SERIAL=/dev/sdb5
MNT=/mnt/firebox
WORK=$HOME/firebox-build

# ========== DEPENDENCY CHECK ==========
for cmd in python3 radare2 zopfli; do
    if ! command -v $cmd &>/dev/null; then
        echo "Missing required tool: $cmd. Install it first."
        exit 1
    fi
done

# ========== CREATE CERTIFICATE ==========
mkdir -p "$WORK" && cd "$WORK"
mkdir -p cert
if [ ! -f cert/private_key.pem ]; then
    openssl ecparam -name sect163k1 -genkey -noout -out cert/private_key.pem
    openssl ec -in cert/private_key.pem -pubout -out cert/public_key.pem
fi

# ========== MOUNT SYSTEM PARTITION ==========
for m in $(findmnt -nr -S "$PART_SYS" -o TARGET | grep '^/run/media/'); do
    sudo fuser -km "$m" 2>/dev/null
    udisksctl unmount -b "$PART_SYS" 2>/dev/null || sudo umount -l "$m" 2>/dev/null
done
sudo mkdir -p "$MNT"
sudo mount "$PART_SYS" "$MNT"

# Copy public key (needed for license verification)
sudo cp cert/public_key.pem "$MNT/etc/lickey.pem"

# ========== PATCH THE KERNEL ==========
rm -rf watchguard-kernel-patcher
git clone https://github.com/zagdrath/watchguard-kernel-patcher.git

sudo cp "$MNT/bzImage" watchguard-kernel-patcher/bzImage

pushd watchguard-kernel-patcher

# Extract kernel components (setup.bin, vmlinux, initramfs, codeverf)
python3 extract_bzimage.py

# Force codeverf to always return success (xor eax, eax; ret)
r2 -w -c 's entry0; wx 31c0c3; q' output/codeverf

# Rebuild initramfs with patched codeverf, size‑matched
python3 repack_initramfs.py --prefer-zopfli

# Rebuild the full bzImage
python3 repack_bzimage.py

# Sanity checks
if [ ! -f bzImage.patched ]; then
    echo "ERROR: bzImage.patched not generated!"
    exit 1
fi
cmp bzImage bzImage.patched && { echo "ERROR: patched kernel identical to original"; exit 1; }

# Install the patched kernel
sudo cp bzImage.patched "$MNT/bzImage"

popd

# ========== UNMOUNT SYSTEM PARTITION ==========
sync
sudo fuser -km "$MNT" 2>/dev/null || true
sudo umount "$MNT" || sudo umount -l "$MNT"
mountpoint -q "$MNT" && echo "!! still mounted" || echo "unmounted ok"

# ========== SET SERIAL NUMBER ==========
sudo mount "$PART_SERIAL" "$MNT"
echo "$SERIAL" | sudo tee "$MNT/serial"
sync
sudo fuser -km "$MNT" 2>/dev/null || true
sudo umount "$MNT" || sudo umount -l "$MNT"
mountpoint -q "$MNT" && echo "!! still mounted" || echo "unmounted ok"

# ========== GENERATE & VERIFY LICENSE ==========
cd "$WORK"
rm -rf wg_firebox
git clone https://github.com/amnemonic/wg_firebox
cd wg_firebox
python3 sign_feature_key.py aftermarket_lic.txt ../cert/private_key.pem
python3 verify_feature_key.py aftermarket_lic.txt ../cert/public_key.pem

echo "All done. License file generated: $WORK/wg_firebox/aftermarket_lic.txt"
