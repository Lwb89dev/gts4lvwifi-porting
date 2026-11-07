#!/bin/bash
# Put the rootfs overlay and the locally built packages onto the Arch system
# that is running on the tablet, over ssh, and enable the passive units. The
# quick way to try a change without rebuilding the 6 GiB image; scripts/
# build-rootfs.sh folds the same files into the next image.
# Writes /usr/local, /etc and the package database on the tablet. Does not
# start a DSP and does not reboot.
#
#   scripts/tablet-deploy.sh
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
cd "$root"
host=${TABLET_IP:-172.16.42.1}
key=out/keys/gts4lv_ed25519
known_hosts=${TABLET_KNOWN_HOSTS:-out/keys/known_hosts}
overlay=device/gts4lvwifi/rootfs/overlay
repo=out/repo/aarch64

die() { echo "tablet-deploy: $*" >&2; exit 1; }

sshc() {
	ssh -F /dev/null -i "$key" -o IdentitiesOnly=yes -o BatchMode=yes \
		-o ConnectTimeout=10 -o UserKnownHostsFile="$known_hosts" \
		-o StrictHostKeyChecking=accept-new "root@$host" "$@"
}

[ -f "$key" ] || die "no $key: run scripts/build-rootfs.sh first"
[ -d "$overlay" ] || die "no $overlay"
sshc 'test "$(uname -r)" = "'"$(cat out/kernel/include/config/kernel.release)"'"' ||
	die "the tablet does not answer, or runs another kernel than out/kernel"

echo "== overlay"
# root-owned, no group or world write, and existing directories (/, /etc, /usr)
# left as they are: the host's owner and umask must not reach the tablet
tar -C "$overlay" --owner=0 --group=0 --numeric-owner --mode='go-w' -cf - . |
	sshc 'tar -C / --no-overwrite-dir --no-same-owner -xf -'

if ls "$repo"/*.pkg.tar.zst >/dev/null 2>&1; then
	echo "== packages"
	sshc 'mkdir -p /root/pkgs && rm -f /root/pkgs/*.pkg.tar.zst'
	for pkg in "$repo"/*.pkg.tar.zst; do
		sshc "cat > /root/pkgs/$(basename "$pkg")" < "$pkg"
	done
	sshc 'pacman -U --noconfirm --needed /root/pkgs/*.pkg.tar.zst'
fi

echo "== units"
sshc 'systemctl daemon-reload && systemctl --global enable gts4lv-initial-speaker-volume.service && systemctl enable gts4lv-mark-poweroff.service && systemctl enable --now gts4lv-firmware.service gts4lv-adsp-stop.service && systemctl is-active gts4lv-firmware.service gts4lv-adsp-stop.service'
echo "deployed"
