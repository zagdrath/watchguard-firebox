# Set variables.
SERIAL=FVE117F24D510
PART_SYS=/dev/sdb2
PART_SERIAL=/dev/sdb5
MNT=/mnt/firebox
WORK=$HOME/firebox-build

# Create certificate.
mkdir -p "$WORK" && cd "$WORK"
mkdir -p cert
openssl ecparam -name sect163k1 -genkey -noout -out cert/private_key.pem
openssl ec -in cert/private_key.pem -pubout -out cert/public_key.pem

# Mount system partition, install key, and patch kernel.
for m in $(findmnt -nr -S "$PART_SYS" -o TARGET | grep '^/run/media/'); do sudo fuser -km "$m" 2>/dev/null; udisksctl unmount -b "$PART_SYS" 2>/dev/null || sudo umount -l "$m" 2>/dev/null; done
sudo mkdir -p "$MNT"
sudo mount "$PART_SYS" "$MNT"
sudo cp cert/public_key.pem "$MNT/etc/lickey.pem"
rm -rf watchguard-kernel-patcher
git clone https://github.com/zagdrath/watchguard-kernel-patcher.git
sudo cp "$MNT/bzImage" watchguard-kernel-patcher/bzImage
( cd watchguard-kernel-patcher && ./run.sh )

# Verify the patched kernel exists and then install it.
ls -la watchguard-kernel-patcher/bzImage.patched
cmp watchguard-kernel-patcher/bzImage watchguard-kernel-patcher/bzImage.patched && echo "identical (BAD - stop)" || echo "differs (good)"
sudo cp watchguard-kernel-patcher/bzImage.patched "$MNT/bzImage"

# Unmount system partition.
sync
sudo fuser -km "$MNT" 2>/dev/null
sudo umount "$MNT" || sudo umount -l "$MNT"
mountpoint -q "$MNT" && echo "!! still mounted" || echo "unmounted ok"

# Set serial on its parition and then unmount.
sudo mount "$PART_SERIAL" "$MNT"
echo "$SERIAL" | sudo tee "$MNT/serial"
sync
sudo fuser -km "$MNT" 2>/dev/null
sudo umount "$MNT" || sudo umount -l "$MNT"
mountpoint -q "$MNT" && echo "!! still mounted" || echo "unmounted ok"

# Generate and verify the license file.
cd "$WORK"
rm -rf wg_firebox
git clone https://github.com/amnemonic/wg_firebox
cd wg_firebox
python3 sign_feature_key.py aftermarket_lic.txt ../cert/private_key.pem
python3 verify_feature_key.py aftermarket_lic.txt ../cert/public_key.pem
