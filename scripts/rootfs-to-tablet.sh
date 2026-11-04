#!/bin/bash
# Copy out/rootfs/rootfs.img into Android's userdata on the tablet (adb, as
# root) and record where its blocks are: out/rootfs/rootfs-extents.txt.
# Writes one file under /data/lost+found/gts4lv/ and nothing else on the
# tablet; adb is put back to the shell user at the end.
#
#   scripts/rootfs-to-tablet.sh
#
# Needs LineageOS running, USB debugging authorized and "Rooted debugging"
# on. TABLET_SERIAL picks the device (default: the Tab S5e); adb is always
# called with it because a Galaxy S24 may be on the same host.
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
cd "$root"
serial=${TABLET_SERIAL:-R52M410RCVR}
image=out/rootfs/rootfs.img
extents=out/rootfs/rootfs-extents.txt
dir=/data/lost+found/gts4lv
remote=$dir/rootfs.img

a() { adb -s "$serial" "$@"; }
prop() { a shell getprop "$1" | tr -d '\r'; }
die() { echo "rootfs-to-tablet: $*" >&2; exit 1; }

check_device() {
	[ "$(a get-state 2>/dev/null)" = device ] || die "$serial is not a connected adb device"
	[ "$(prop ro.product.device)" = gts4lvwifi ] || die "$serial is not a gts4lvwifi"
	[ "$(prop ro.product.model)" = SM-T720 ] || die "$serial is not an SM-T720"
	[ "$(prop sys.boot_completed)" = 1 ] || die "Android has not finished booting"
}

become_root() {
	a root >/dev/null 2>&1 || true
	a wait-for-device
	[ "$(a shell id -u | tr -d '\r')" = 0 ] ||
		die "adb is not root: turn on Rooted debugging in Developer options"
}

check_userdata() {
	local mount
	mount=$(a shell "mount | grep ' /data '" | tr -d '\r')
	echo "mount: $mount"
	case $mount in
	*"/dev/block/mmcblk0p57 "* | *"/dev/block/by-name/userdata "*) ;;
	*) die "/data is not directly on userdata: a layer below it would be mapped as ciphertext" ;;
	esac
	case $mount in
	*" type ext4 "*) ;;
	*) die "/data is not ext4" ;;
	esac
}

check_space() {
	local need_kb free_kb
	need_kb=$(($(stat -c %s "$image") / 1024))
	free_kb=$(a shell "df -k /data | tail -n 1" | tr -d '\r' | awk '{ print $4 }')
	echo "need ${need_kb} KiB, /data has ${free_kb} KiB free"
	[ "$free_kb" -gt $((need_kb + 4 * 1024 * 1024)) ] || die "not enough free space in /data"
}

copy_image() {
	local want have
	a shell "mkdir -p $dir"
	a shell "rm -f $remote"
	a push "$image" "$remote"
	a shell sync
	want=$(sha256sum "$image" | cut -d' ' -f1)
	have=$(a shell "sha256sum $remote" | tr -d '\r' | cut -d' ' -f1)
	[ "$want" = "$have" ] || die "the copy on the tablet differs ($have, wanted $want)"
	echo "copy verified, sha256 $have"
}

record_extents() {
	local total
	a push out/tools/fiemap /data/local/tmp/fiemap >/dev/null
	a shell chmod 755 /data/local/tmp/fiemap
	a shell "/data/local/tmp/fiemap $remote" > "$extents.raw" || die "fiemap refused the file"
	tr -d '\r' < "$extents.raw" > "$extents"
	rm -f "$extents.raw"
	a shell rm -f /data/local/tmp/fiemap
	total=$(awk '{ s += $3 } END { print s }' "$extents")
	[ "$total" = "$(stat -c %s "$image")" ] || die "extents cover $total bytes, not the image size"
	echo "$(wc -l < "$extents") extents covering $total bytes: $extents"
}

check_device
become_root
check_userdata
check_space
copy_image
record_extents
a unroot >/dev/null 2>&1 || true
echo "done. The image is $remote on the tablet."
