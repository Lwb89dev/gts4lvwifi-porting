#!/bin/bash
# Runs inside the Arch Linux ARM aarch64 container (qemu-user), as root.
# Called by scripts/build-rootfs.sh with the kernel release as $1.
# Mounts: /overlay (files to copy over /), /keys (authorized_keys),
# /kmods (the kernel's modules for that release), /out (results).
set -euo pipefail

release=${1:?kernel release}

say() { printf '==> %s\n' "$*"; }

# Copy a tree so that everything it creates is owned by root with no group or
# world write, whoever owns it on the host: a bind mount shows the host user
# (uid 1000, which is "alarm" in this image). cp -a would copy that owner and
# mode onto directories that already exist, /etc among them. Existing
# directories keep what they have.
install_tree() { # <from> <to>
	tar -C "$1" --owner=0 --group=0 --numeric-owner --mode='go-w' -cf - . |
		tar -C "$2" --no-overwrite-dir --no-same-owner -xf -
}

say "pacman settings that stay in the image"
# linux-firmware's generic ath10k board data for this chip (the entry
# "bus=snoc,qmi-board-id=ff") makes the WLAN firmware reset the whole SoC about
# ten seconds after the QMI handshake; Samsung's own bdwlan.bin, which
# gts4lv-firmware links as board.bin, does not. ath10k asks for board-2.bin
# first, so that file must never be on the disk.
sed -i 's|^\[options\]|[options]\nNoExtract = usr/lib/firmware/ath10k/WCN3990/hw1.0/board-2.bin|' /etc/pacman.conf

say "pacman for a container under qemu-user"
# qemu-user has no landlock and the container has no mount table for
# CheckSpace. Both are put back before the image is made.
cp /etc/pacman.conf /tmp/pacman.conf.orig
cp /etc/pacman.d/mirrorlist /tmp/mirrorlist.orig
sed -i 's/^CheckSpace/#CheckSpace/' /etc/pacman.conf
sed -i 's/^\[options\]/[options]\nDisableSandbox/' /etc/pacman.conf
if [ -n "${ALARM_BUILD_MIRROR:-}" ]; then
	build_mirror=${ALARM_BUILD_MIRROR%/}
	case $build_mirror in
		http://*|https://*) ;;
		*) printf 'invalid ALARM_BUILD_MIRROR: %s\n' "$build_mirror" >&2; exit 1 ;;
	esac
	case $build_mirror in
		*[[:space:]\$\|]*) printf 'unsafe ALARM_BUILD_MIRROR: %s\n' "$build_mirror" >&2; exit 1 ;;
	esac
	sed -i "0,/^Server = /s|^Server = .*|Server = $build_mirror/\$arch/\$repo|" \
		/etc/pacman.d/mirrorlist
fi

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
install_tree /kmods "/usr/lib/modules/$release"
# modules_install leaves links to the build and source trees on the host
rm -f "/usr/lib/modules/$release/build" "/usr/lib/modules/$release/source"
depmod -a "$release"

say "configuration"
install_tree /overlay /
passwd -l root
passwd -l alarm
# A test build may explicitly supply a local, bind-mounted password file.  It
# is deliberately opt-in: release images keep both interactive accounts
# locked, and the secret never becomes a tracked repository file.
if [ "${GTS4LV_TEST_ALARM_PASSWORD:-0}" = 1 ]; then
	test -r /tmp/gts4lv-test-alarm-password || {
		printf 'test password file is unavailable\n' >&2
		exit 1
	}
	test_password=$(head -n 1 /tmp/gts4lv-test-alarm-password)
	case $test_password in
	''|*:*|*[[:cntrl:]]*)
		printf 'test password must be one non-empty line without a colon\n' >&2
		exit 1
		;;
	esac
	printf 'alarm:%s\n' "$test_password" | chpasswd
	unset test_password
	say "enabled the local test password for alarm"
fi
# The audio server refuses to run as root: it runs for "alarm", with a user session that
# stays up without a login (linger). Keep the account in every group needed by a local
# graphical session; in particular, Omarchy Mobile also expects direct input access.
usermod -aG audio,input,lp,render,video alarm
mkdir -p /var/lib/systemd/linger
touch /var/lib/systemd/linger/alarm
install -d -m 700 /root/.ssh
install -m 600 /keys/authorized_keys /root/.ssh/authorized_keys
systemctl enable systemd-networkd.service sshd.service gts4lv-boot-ok.service \
	gts4lv-firmware.service gts4lv-adsp-stop.service gts4lv-modem.service \
	gts4lv-bluetooth.service gts4lv-sensors.service gts4lv-cpu-stability.service \
	NetworkManager.service \
	bluetooth.service \
	systemd-timesyncd.service
# Keep the recovery unit available, but never expose an unauthenticated root
# console during a normal boot.
systemctl disable gts4lv-debug-console.service >/dev/null 2>&1 || true
# The qrtr name service is in the kernel (net/qrtr/ns.c). qrtr-ns.service from
# the package is left disabled: it only reports "nameserver already running".

say "undo the container-only pacman settings"
cp /tmp/pacman.conf.orig /etc/pacman.conf

if [ "${OMARCHY_MOBILE:-0}" = 1 ]; then
	say "Omarchy Mobile packages and automatic graphical session"
	bash /customize-omarchy.sh /omarchy-repos.lock /omarchy-packages.txt \
		/omarchy-packages.lock
fi

# A build-time mirror override must not become a device update policy.
cp /tmp/mirrorlist.orig /etc/pacman.d/mirrorlist

pacman -Scc --noconfirm >/dev/null || true

say "package list"
pacman -Q > /out/packages.txt
wc -l /out/packages.txt
