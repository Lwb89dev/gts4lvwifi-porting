#!/bin/bash
# Runs inside the Arch Linux ARM aarch64 container (qemu-user), as root.
# Called by scripts/build-rootfs.sh with the kernel release as $1.
# Mounts: /overlay (files to copy over /), /keys (authorized_keys),
# /kmods (the kernel's modules for that release), /out (results).
set -euo pipefail

release=${1:?kernel release}

say() { printf '==> %s\n' "$*"; }

say "pacman for a container under qemu-user"
# qemu-user has no landlock and the container has no mount table for
# CheckSpace. Both are put back before the image is made.
cp /etc/pacman.conf /tmp/pacman.conf.orig
sed -i 's/^CheckSpace/#CheckSpace/' /etc/pacman.conf
sed -i 's/^\[options\]/[options]\nDisableSandbox/' /etc/pacman.conf

say "keyring"
pacman-key --init
pacman-key --populate archlinuxarm

say "remove Arch's kernel, mkinitcpio and the firmware this tablet never uses"
pacman -Rdd --noconfirm linux-aarch64 mkinitcpio mkinitcpio-busybox \
	linux-firmware linux-firmware-amdgpu linux-firmware-broadcom \
	linux-firmware-intel linux-firmware-mediatek linux-firmware-nvidia \
	linux-firmware-other linux-firmware-radeon linux-firmware-realtek

say "upgrade and add the Qualcomm firmware and the tools of the bring-up"
pacman -Syu --noconfirm
pacman -S --noconfirm --needed linux-firmware-qcom
# shellcheck disable=SC2046
pacman -S --noconfirm --needed $(grep -v '^#' /overlay-packages.txt)

# Packages built here (scripts/build-packages.sh): the Qualcomm services Arch
# Linux ARM does not carry. Skipped when the directory is not mounted.
if ls /pkgs/*.pkg.tar.zst >/dev/null 2>&1; then
	say "local packages"
	pacman -U --noconfirm --needed /pkgs/*.pkg.tar.zst
fi

say "our modules for $release"
rm -rf "/usr/lib/modules/$release"
mkdir -p "/usr/lib/modules/$release"
cp -a /kmods/. "/usr/lib/modules/$release/"
# modules_install leaves links to the build and source trees on the host
rm -f "/usr/lib/modules/$release/build" "/usr/lib/modules/$release/source"
depmod -a "$release"

say "configuration"
cp -a /overlay/. /
passwd -l root
passwd -l alarm
install -d -m 700 /root/.ssh
install -m 600 /keys/authorized_keys /root/.ssh/authorized_keys
systemctl enable systemd-networkd.service sshd.service gts4lv-boot-ok.service \
	gts4lv-firmware.service gts4lv-adsp-stop.service
# qrtr-ns is the name service every Qualcomm remote service needs
if [ -e /usr/lib/systemd/system/qrtr-ns.service ]; then
	systemctl enable qrtr-ns.service
fi

say "undo the container-only pacman settings"
cp /tmp/pacman.conf.orig /etc/pacman.conf
pacman -Scc --noconfirm >/dev/null || true

say "package list"
pacman -Q > /out/packages.txt
wc -l /out/packages.txt
