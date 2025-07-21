#!/bin/bash

set -e

# ==== CONFIG ====
ROOT_PART="/dev/nvme0n1p2"
EFI_PART="/dev/nvme0n1p1"
DISK="/dev/nvme0n1"
ROOT_SUBVOL="@"
# =================

echo "[1/8] Mounting Btrfs root subvolume..."
mount -o subvol=$ROOT_SUBVOL "$ROOT_PART" /mnt

echo "[2/8] Mounting EFI partition..."
mkdir -p /mnt/boot/efi
mount -t vfat "$EFI_PART" /mnt/boot/efi

echo "[3/8] Binding system directories..."
for dir in dev proc sys run; do
    mkdir -p /mnt/$dir
    mount --bind /$dir /mnt/$dir
done

echo "[4/8] Copying DNS settings..."
cp /etc/resolv.conf /mnt/etc/resolv.conf

echo "[5/8] Entering chroot and reinstalling GRUB..."
cat <<'EOF' | chroot /mnt /bin/bash
set -e

echo "[chroot] Updating pacman..."
pacman -Sy --noconfirm

echo "[chroot] Installing grub and btrfs-progs..."
pacman -S --noconfirm grub btrfs-progs

echo "[chroot] Installing GRUB for UEFI..."
if ! grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB; then
    echo "[chroot] grub-install failed to register boot entry. Trying efibootmgr manually..."
    efibootmgr --create --disk /dev/nvme0n1 --part 1 --label "GRUB" --loader /EFI/GRUB/grubx64.efi || echo "[WARNING] efibootmgr failed. Make sure GRUB is registered in your UEFI settings."
fi

echo "[chroot] Configuring GRUB to boot silently..."
cat > /etc/default/grub <<GRUBCFG
GRUB_TIMEOUT_STYLE=hidden
GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR=Arch
GRUB_CMDLINE_LINUX_DEFAULT="quiet"
GRUB_CMDLINE_LINUX=""
GRUBCFG

echo "[chroot] Generating GRUB config..."
grub-mkconfig -o /boot/grub/grub.cfg

echo "[chroot] Done."
EOF

echo "[6/8] Cleaning up mounts..."
umount -R /mnt

echo "[7/8] Rebooting..."
echo "Remove the USB now. Rebooting in 5 seconds..."
sleep 5
reboot
