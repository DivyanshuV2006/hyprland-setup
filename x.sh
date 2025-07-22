#!/bin/bash
set -e

# === CONFIG ===
ROOT_PART="/dev/nvme0n1p2"
EFI_PART="/dev/nvme0n1p1"
ROOT_SUBVOL="@"
BOOT_MOUNT="/mnt/boot/efi"

echo "[1/7] Mounting Btrfs root subvolume..."
mount -o subvol=$ROOT_SUBVOL "$ROOT_PART" /mnt

echo "[2/7] Mounting EFI..."
mkdir -p $BOOT_MOUNT
mount -t vfat "$EFI_PART" $BOOT_MOUNT

echo "[3/7] Binding system directories..."
for dir in dev proc sys run; do
  mkdir -p /mnt/$dir
  mount --bind /$dir /mnt/$dir
done
cp /etc/resolv.conf /mnt/etc/resolv.conf

echo "[4/7] Entering chroot and repairing system..."
cat <<'EOF' | chroot /mnt /bin/bash
set -e

echo "[chroot] Updating system packages..."
pacman -Sy --noconfirm

echo "[chroot] Installing kernel, GRUB, and Btrfs support..."
pacman -S --noconfirm linux grub btrfs-progs base linux-firmware

echo "[chroot] Getting root partition UUID..."
ROOT_UUID=$(blkid -s UUID -o value /dev/nvme0n1p2)

echo "[chroot] Configuring GRUB with correct root and subvol..."
cat > /etc/default/grub <<EOF_GRUB
GRUB_TIMEOUT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_CMDLINE_LINUX_DEFAULT="quiet"
GRUB_CMDLINE_LINUX="root=UUID=$ROOT_UUID rootflags=subvol=@ rw"
EOF_GRUB

echo "[chroot] Rebuilding initramfs..."
mkinitcpio -P

echo "[chroot] Reinstalling GRUB..."
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB

echo "[chroot] Generating GRUB config..."
grub-mkconfig -o /boot/grub/grub.cfg

echo "[chroot] ✅ System ready."
EOF

echo "[5/7] Cleaning up mounts..."
umount -R /mnt || true

echo "[6/7] ✅ Boot repair complete!"
echo "[7/7] Rebooting in 5 seconds... Remove USB now."
sleep 5
reboot
