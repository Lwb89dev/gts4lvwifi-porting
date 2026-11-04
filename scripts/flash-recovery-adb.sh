#!/bin/bash
# Write out/recovery.img into the tablet's recovery partition from running
# Android (adb, as root), and read it back before anything is rebooted.
# Writes only /dev/block/by-name/recovery and a temporary file in
# /data/local/tmp. Does not reboot. adb is put back to the shell user.
#
#   scripts/flash-recovery-adb.sh [image]
#
# Needs "Rooted debugging" on. The rollback copy of the Lineage recovery has
# to exist and match its recorded sha256 first. TABLET_SERIAL picks the device
# (default: the Tab S5e); a Galaxy S24 may be on the same host.
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
cd "$root"
serial=${TABLET_SERIAL:-R52M410RCVR}
image=${1:-out/recovery.img}
rollback=out/lineage-recovery-before-mainline.img
rollback_sha=81f4d19e4d9d3ba37c2044d57b77c72f01487dbaaa3a24173b14bacc161b14a7
part=/dev/block/by-name/recovery
part_bytes=72744960
tmp=/data/local/tmp/recovery-new.img

a() { adb -s "$serial" "$@"; }
prop() { a shell getprop "$1" | tr -d '\r'; }
die() { echo "flash-recovery-adb: $*" >&2; exit 1; }

check_files() {
	local size
	[ -f "$image" ] || die "no $image"
	python3 -I scripts/verify-recovery.py "$image" >/dev/null || die "$image fails verify-recovery.py"
	size=$(stat -c %s "$image")
	[ $((size % 4096)) = 0 ] || die "$image is not a whole number of pages"
	[ "$size" -le "$part_bytes" ] || die "$image is larger than the partition"
	[ -f "$rollback" ] || die "no rollback copy $rollback"
	[ "$(sha256sum "$rollback" | cut -d' ' -f1)" = "$rollback_sha" ] || die "$rollback does not match its recorded sha256"
}

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
	[ "$(a shell "blockdev --getsize64 $part" | tr -d '\r')" = "$part_bytes" ] ||
		die "$part is not $part_bytes bytes: wrong partition or wrong device"
}

write_and_read_back() {
	local pages want have
	pages=$(($(stat -c %s "$image") / 4096))
	want=$(sha256sum "$image" | cut -d' ' -f1)
	a push "$image" "$tmp" >/dev/null
	have=$(a shell "sha256sum $tmp" | tr -d '\r' | cut -d' ' -f1)
	[ "$want" = "$have" ] || die "the copy in /data/local/tmp differs, nothing was written"
	a shell "dd if=$tmp of=$part bs=4096 conv=fsync 2>/dev/null; sync"
	have=$(a shell "dd if=$part bs=4096 count=$pages 2>/dev/null | sha256sum" | tr -d '\r' | cut -d' ' -f1)
	a shell "rm -f $tmp"
	[ "$want" = "$have" ] || die "READBACK DIFFERS ($have, wanted $want): write the rollback copy and do not reboot"
	echo "written and read back: $pages pages, sha256 $want"
}

check_files
check_device
become_root
write_and_read_back
a unroot >/dev/null 2>&1 || true
echo "not rebooted"
