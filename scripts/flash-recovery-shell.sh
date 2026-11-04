#!/bin/bash
# Write out/recovery.img into the recovery partition from the tablet's own
# initramfs shell (telnet 172.16.42.1), and read it back. This is the loop for
# iterating without a trip through Android. Writes only the recovery partition
# and /tmp (RAM) on the tablet.
#
#   scripts/flash-recovery-shell.sh [--reboot] [image]
#
# --reboot restarts with the PMIC reason RECOVERY afterwards, so the new image
# starts at once. The running system lives in RAM, so overwriting the
# partition it was loaded from is safe. If the readback differs, nothing is
# rebooted: write the rollback copy (scripts/flash-recovery-adb.sh or Heimdall).
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
cd "$root"
host=${TABLET_IP:-172.16.42.1}
reboot=0
if [ "${1:-}" = --reboot ]; then
	reboot=1
	shift
fi
image=${1:-out/recovery.img}
part_bytes=72744960

die() { echo "flash-recovery-shell: $*" >&2; exit 1; }

# Run one command line on the tablet's shell and print only its output.
t() {
	printf 'echo __BEGIN__; %s\necho __END__\nexit\n' "$1" |
		nc -w "${2:-30}" "$host" 23 |
		LC_ALL=C tr -d '\r\000' |
		LC_ALL=C sed 's/\x1b\[[0-9;]*m//g' |
		sed -n '/^__BEGIN__$/,/^__END__$/p' | sed '1d;$d'
}

check_image() {
	local size
	[ -f "$image" ] || die "no $image"
	python3 -I scripts/verify-recovery.py "$image" >/dev/null || die "$image fails verify-recovery.py"
	size=$(stat -c %s "$image")
	[ $((size % 4096)) = 0 ] || die "$image is not a whole number of pages"
	[ "$size" -le "$part_bytes" ] || die "$image is larger than the partition"
}

check_tablet() {
	local info
	info=$(t 'uname -r; tr "\0" " " < /proc/device-tree/model; echo; grep -o "androidboot.em.model=[A-Z0-9-]*" /proc/cmdline')
	echo "$info"
	echo "$info" | grep -q 'gts4lvwifi' || die "this is not the gts4lvwifi kernel"
	echo "$info" | grep -q 'GTS4LVWIFI' || die "the device tree is not a GTS4LVWIFI"
	echo "$info" | grep -q 'androidboot.em.model=SM-T720' || die "the model is not SM-T720"
}

find_partition() {
	local node bytes
	# single quotes on purpose: the loop runs on the tablet
	# shellcheck disable=SC2016
	node=$(t 'for u in /sys/class/block/mmcblk0p*/uevent; do grep -q "^PARTNAME=recovery$" $u && basename $(dirname $u); done')
	if [ -z "$node" ] || [ "$(echo "$node" | wc -l)" != 1 ]; then
		die "recovery partition not found, or not unique ($node)"
	fi
	bytes=$(t "echo \$((\$(cat /sys/class/block/$node/size) * 512))")
	[ "$bytes" = "$part_bytes" ] || die "$node is $bytes bytes, not $part_bytes"
	echo "/dev/$node"
}

send_image() {
	local want have
	want=$(sha256sum "$image" | cut -d' ' -f1)
	t '(nc -l -p 9003 > /tmp/recovery-new.img &); sleep 1' >/dev/null
	nc -w 10 "$host" 9003 < "$image"
	sleep 2
	have=$(t 'sha256sum /tmp/recovery-new.img' | cut -d' ' -f1)
	[ "$want" = "$have" ] || die "the copy in RAM differs ($have, wanted $want), nothing was written"
	echo "$want"
}

write_and_read_back() {
	local dev=$1 want=$2 pages have
	pages=$(($(stat -c %s "$image") / 4096))
	t "dd if=/tmp/recovery-new.img of=$dev bs=4096 conv=fsync 2>/dev/null; sync" 120 >/dev/null
	have=$(t "dd if=$dev bs=4096 count=$pages 2>/dev/null | sha256sum" 60 | cut -d' ' -f1)
	t 'rm -f /tmp/recovery-new.img' >/dev/null
	[ "$want" = "$have" ] || die "READBACK DIFFERS ($have, wanted $want): not rebooting"
	echo "written to $dev and read back: $pages pages, sha256 $want"
}

check_image
check_tablet
dev=$(find_partition)
sum=$(send_image)
write_and_read_back "$dev" "$sum"
if [ "$reboot" = 1 ]; then
	echo "restarting into recovery"
	t 'rebootmode recovery' 5 >/dev/null || true
else
	echo "not rebooted"
fi
