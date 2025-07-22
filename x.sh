#!/bin/bash
set -e

# === CONFIG ===
ROOT_PART="/dev/nvme0n1p2"
EFI_PART="/dev/nvme0n1p1"
DISK="/dev/nvme0n1"
ROOT_SUBVOL="@"

echo "[1/6] Mounting root subvolume..."
mount -o subvol=$ROOT_SUBVOL "$ROOT_PART" /mnt

echo "[2/6] Mounting EFI..."
mkdir -p /mnt/boot/efi
mount -t vfat "$EFI_PART" /mnt/boot/efi

echo "[3/6] Mounting system dirs..."
for dir in dev proc sys run; do
  mkdir -p /mnt/$dir
  mount --bind /$dir /mnt/$dir
done
cp /etc/resolv.conf /mnt/etc/resolv.conf

echo "[4/6] Running fix inside chroot..."
cat <<'EOF' | chroot /mnt /bin/bash
set -e

pacman -Sy --noconfirm grub btrfs-progs

grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB || true

# GRUB config to boot silently and support Btrfs subvol
sed -i 's|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX="rootflags=subvol=@ quiet"|' /etc/default/grub
sed -i 's|^GRUB_TIMEOUT=.*|GRUB_TIMEOUT=0|' /etc/default/grub
sed -i 's|^#\?GRUB_TIMEOUT_STYLE=.*|GRUB_TIMEOUT_STYLE=hidden|' /etc/default/grub

grub-mkconfig -o /boot/grub/grub.cfg
mkinitcpio -P
EOF

echo "[5/6] Cleaning up..."
umount -R /mnt || true

echo "[6/6] ✅ Done. Rebooting in 5 seconds..."
sleep 5
reboot
