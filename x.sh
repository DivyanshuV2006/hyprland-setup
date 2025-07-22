#!/bin/bash

set -e

# === CONFIG ===
ROOT_PART="/dev/nvme0n1p2"
EFI_PART="/dev/nvme0n1p1"
ROOT_SUBVOL="@"
# ==============

echo "[1/6] Mounting root subvolume..."
mount -o subvol=$ROOT_SUBVOL "$ROOT_PART" /mnt

echo "[2/6] Mounting EFI..."
mkdir -p /mnt/boot/efi
mount -t vfat "$EFI_PART" /mnt/boot/efi

echo "[3/6] Mounting system dirs..."
for dir in dev proc sys run; do
  mount --bind /$dir /mnt/$dir
done
cp /etc/resolv.conf /mnt/etc/resolv.conf

echo "[4/6] Chrooting into system to fix boot config..."
cat <<'EOF' | chroot /mnt /bin/bash
set -e

echo "[chroot] Fixing GRUB kernel parameters..."
sed -i 's|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX="rootflags=subvol=@ quiet"|' /etc/default/grub

echo "[chroot] Regenerating GRUB config..."
grub-mkconfig -o /boot/grub/grub.cfg

echo "[chroot] Rebuilding initramfs..."
mkinitcpio -P
EOF

echo "[5/6] Cleaning up..."
umount -R /mnt

echo "[6/6] Rebooting in 5 seconds... Remove USB now."
sleep 5
reboot
