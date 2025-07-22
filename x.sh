#!/bin/bash
set -e

# === CONFIG ===
ROOT_PART="/dev/nvme0n1p2"
EFI_PART="/dev/nvme0n1p1"
ROOT_SUBVOL="@"

echo "[1/7] Mounting root subvolume..."
mount -o subvol=$ROOT_SUBVOL "$ROOT_PART" /mnt

echo "[2/7] Mounting EFI partition..."
mkdir -p /mnt/boot/efi
mount -t vfat "$EFI_PART" /mnt/boot/efi

echo "[3/7] Mounting essential system directories..."
for dir in dev proc sys run; do
  mount --bind /$dir /mnt/$dir
done
cp /etc/resolv.conf /mnt/etc/resolv.conf

echo "[4/7] Entering chroot and fixing everything..."
cat <<'EOF' | chroot /mnt /bin/bash
set -e

echo "[chroot] Updating package database..."
pacman -Sy --noconfirm

echo "[chroot] Reinstalling kernel and bootloader tools..."
pacman -S --noconfirm linux grub btrfs-progs base linux-firmware

echo "[chroot] Rebuilding initramfs..."
mkinitcpio -P

echo "[chroot] Installing GRUB to EFI..."
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB || true

echo "[chroot] Setting up GRUB config..."
sed -i 's|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX="rootflags=subvol=@ quiet"|' /etc/default/grub
sed -i 's|^GRUB_TIMEOUT=.*|GRUB_TIMEOUT=0|' /etc/default/grub
sed -i 's|^#\?GRUB_TIMEOUT_STYLE=.*|GRUB_TIMEOUT_STYLE=hidden|' /etc/default/grub

grub-mkconfig -o /boot/grub/grub.cfg

echo "[chroot] ✅ Done inside chroot."
EOF

echo "[5/7] Unmounting everything..."
umount -R /mnt || true

echo "[6/7] ✅ All done!"
echo "[7/7] Rebooting in 5 seconds — remove USB now..."
sleep 5
reboot
