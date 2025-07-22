#!/bin/bash

# === Setup ===
set -euo pipefail

ERROR_ID="7001999"  # Default unknown error
EXIT_WITH_ERROR() {
  echo -e "\n❌ Failed. Error ID: $ERROR_ID"
  echo "Tell ChatGPT: Error ID $ERROR_ID"
  exit 1
}
trap EXIT_WITH_ERROR ERR

# === CONFIG ===
ROOT_PART="/dev/nvme0n1p2"
EFI_PART="/dev/nvme0n1p1"
DISK="/dev/nvme0n1"
ROOT_SUBVOL="@"

echo "[1/7] Mounting Btrfs root subvolume..."
if ! mount -o subvol=$ROOT_SUBVOL "$ROOT_PART" /mnt; then
  ERROR_ID="7001204"; false
fi

echo "[2/7] Mounting EFI partition..."
mkdir -p /mnt/boot/efi
if ! mount -t vfat "$EFI_PART" /mnt/boot/efi; then
  ERROR_ID="7001205"; false
fi

echo "[3/7] Mounting system directories..."
for dir in dev proc sys run; do
  mkdir -p /mnt/$dir
  mount --bind /$dir /mnt/$dir
done
cp /etc/resolv.conf /mnt/etc/resolv.conf

echo "[4/7] Chrooting and repairing system..."
cat <<'EOF' > /mnt/tmp/grubfix.sh
#!/bin/bash
set -euo pipefail

ERROR_ID="7001999"

function fail() {
  echo -e "\n❌ Failed inside chroot. Error ID: \$ERROR_ID"
  echo "Tell ChatGPT: Error ID \$ERROR_ID"
  exit 1
}
trap fail ERR

echo "[chroot] Installing grub and btrfs tools..."
if ! pacman -Sy --noconfirm grub btrfs-progs; then
  ERROR_ID="7001206"; false
fi

echo "[chroot] Installing GRUB..."
if ! grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB; then
  echo "[chroot] ⚠️ grub-install failed — possibly no EFI var support. Continuing anyway."
  ERROR_ID="7001201"
fi

echo "[chroot] Configuring GRUB kernel command line..."
sed -i 's|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX="rootflags=subvol=@ quiet"|' /etc/default/grub
sed -i 's|^GRUB_TIMEOUT=.*|GRUB_TIMEOUT=0|' /etc/default/grub
sed -i 's|^#\?GRUB_TIMEOUT_STYLE=.*|GRUB_TIMEOUT_STYLE=hidden|' /etc/default/grub

echo "[chroot] Generating GRUB config..."
if ! grub-mkconfig -o /boot/grub/grub.cfg; then
  ERROR_ID="7001202"; false
fi

echo "[chroot] Rebuilding initramfs..."
if ! mkinitcpio -P; then
  ERROR_ID="7001203"; false
fi

echo "[chroot] Done."
exit 0
EOF

chmod +x /mnt/tmp/grubfix.sh

arch-chroot /mnt /tmp/grubfix.sh || exit 1

echo "[5/7] Cleaning up..."
umount -R /mnt || true

echo "[6/7] ✅ Success! GRUB is installed and configured."
echo "[7/7] Rebooting in 5 seconds... remove USB now."
sleep 5
reboot
