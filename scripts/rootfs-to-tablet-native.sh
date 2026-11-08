#!/bin/bash
# Install an Omarchy rootfs image directly on userdata. This deliberately
# replaces Android/Lineage userdata; it is only for a recovery image built
# with GTS4LV_ROOT_MODE=native. The recovery USB shell remains available if
# the copy is interrupted, so rerunning this script is safe.
#
#   TABLET_BIND=172.16.42.3 ROOTFS_VARIANT=omarchy \
#     scripts/rootfs-to-tablet-native.sh [--reboot]
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
cd "$root"
host=${TABLET_IP:-172.16.42.1}
bind=${TABLET_BIND:-}
variant=${ROOTFS_VARIANT:-}
image_port=${ROOTFS_IMAGE_PORT:-9004}
transfer_timeout=${ROOTFS_TRANSFER_TIMEOUT:-1800}
case $variant in
"") image_dir=out/rootfs ;;
*[!a-z0-9-]*) echo "ROOTFS_VARIANT may contain only a-z, 0-9 and -" >&2; exit 1 ;;
*) image_dir=out/rootfs-$variant ;;
esac
image=$image_dir/rootfs.img
listener_pid=/tmp/gts4lv-native-rootfs-listener.pid
reboot=0

if [ "${1:-}" = --reboot ]; then
	reboot=1
	shift
fi
[ "$#" -eq 0 ] || { echo "usage: rootfs-to-tablet-native.sh [--reboot]" >&2; exit 1; }

die() { echo "rootfs-to-tablet-native: $*" >&2; exit 1; }

ncc() {
	if [ -n "$bind" ]; then
		nc -s "$bind" "$@"
	else
		nc "$@"
	fi
}

# Run a command in the unauthenticated recovery shell and retain only its
# delimited output. This must never be used after switch_root.
t() {
	printf 'echo __BEGIN__; %s\necho __END__\nexit\n' "$1" |
		ncc -w "${2:-30}" "$host" 23 |
		LC_ALL=C tr -d '\r\000' |
		LC_ALL=C sed 's/\x1b\[[0-9;]*m//g' |
		sed -n '/^__BEGIN__$/,/^__END__$/p' | sed '1d;$d' |
		grep -v '^~ # ' || true
}

case $image_port in
""|*[!0-9]*|0) die "ROOTFS_IMAGE_PORT must be a TCP port number" ;;
esac
[ "$image_port" -le 65535 ] || die "ROOTFS_IMAGE_PORT must be at most 65535"
case $transfer_timeout in
""|*[!0-9]*|0) die "ROOTFS_TRANSFER_TIMEOUT must be a positive integer" ;;
esac
[ -f "$image" ] || die "no $image"
image_bytes=$(stat -c %s "$image")
[ "$image_bytes" -gt 0 ] || die "$image is empty"
[ $((image_bytes % 4194304)) -eq 0 ] || die "$image must be a multiple of 4 MiB"
if [ -n "$bind" ]; then
	ip -4 addr show | grep -Fq " $bind/" || die "TABLET_BIND $bind is not a local IPv4 address"
fi
ncc -z -w2 "$host" 23 2>/dev/null || die "the recovery shell does not answer on $host:23"

info=$(t 'uname -r; tr "\0" " " < /proc/device-tree/model; echo; test -f /etc/gts4lv-root-mode && cat /etc/gts4lv-root-mode; test ! -d /run/systemd/system && echo initramfs')
echo "$info"
echo "$info" | grep -q gts4lvwifi || die "this is not the gts4lvwifi kernel"
echo "$info" | grep -q GTS4LVWIFI || die "the device tree is not GTS4LVWIFI"
echo "$info" | grep -qx native || die "the recovery image is not in native-root mode"
echo "$info" | grep -q initramfs || die "the tablet has already switched to a rootfs"

# Discover exactly one GPT userdata partition. Never accept a shell-provided
# node name: this script will overwrite the returned block device.
# shellcheck disable=SC2016
userdata=$(t 'for u in /sys/class/block/mmcblk0p*/uevent; do grep -q "^PARTNAME=userdata$" "$u" && basename "$(dirname "$u")"; done')
if [ -z "$userdata" ] || [ "$(printf '%s\n' "$userdata" | wc -l)" -ne 1 ]; then
	die "userdata partition not found or not unique ($userdata)"
fi
capacity=$(t "echo \$((\$(cat /sys/class/block/$userdata/size) * 512))" | tail -n 1)
case $capacity in
""|*[!0-9]*) die "could not read userdata capacity ($capacity)" ;;
esac
[ "$image_bytes" -le "$capacity" ] || die "$image is larger than userdata"

want=$(sha256sum "$image" | cut -d' ' -f1)
echo "WARNING: writing $image_bytes bytes directly to /dev/$userdata; Android/Lineage userdata will be destroyed."
echo "sending $image ($want)"
t "rm -f $listener_pid; (setsid nc -l -p $image_port > /dev/$userdata </dev/null 2>&1 & echo \$! > $listener_pid); sleep 1" >/dev/null
dd if="$image" bs=4M status=progress | ncc -w "$transfer_timeout" "$host" "$image_port"
t "test -r $listener_pid && kill \$(cat $listener_pid) 2>/dev/null || true; rm -f $listener_pid; sync" 120 >/dev/null
have=$(t "dd if=/dev/$userdata bs=4M count=$((image_bytes / 4194304)) 2>/dev/null | sha256sum" 1800 | awk '{print $1}')
[ "$have" = "$want" ] || die "tablet rootfs hash is $have, wanted $want"
echo "native root written and verified: $have"
if [ "$reboot" = 1 ]; then
	echo "restarting into native recovery"
	t 'rebootmode recovery' 5 >/dev/null || true
else
	echo "Reboot into recovery to start the native root."
fi
echo "On the first native Arch boot, grow the filesystem with: resize2fs /dev/$userdata"
