#!/bin/bash
# Read-only. With LineageOS running and "Rooted debugging" on, say what is in
# the recovery partition and what could rewrite it: compare its sha256 with the
# images this project knows, and list the AOSP recovery-restore script and the
# properties that name it. Writes nothing on the tablet; adb is put back to the
# shell user at the end.
#
#   scripts/lineage-recovery-check.sh
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
cd "$root"
serial=${TABLET_SERIAL:-R52M410RCVR}
part=/dev/block/by-name/recovery
part_bytes=72744960

a() { adb -s "$serial" "$@"; }
die() { echo "lineage-recovery-check: $*" >&2; exit 1; }

[ "$(a get-state 2>/dev/null)" = device ] || die "$serial is not an authorized adb device (state: $(a get-state 2>&1 | tail -1))"
[ "$(a shell getprop ro.product.device | tr -d '\r')" = gts4lvwifi ] || die "not a gts4lvwifi"
[ "$(a shell getprop sys.boot_completed | tr -d '\r')" = 1 ] || die "Android has not finished booting"
a root >/dev/null 2>&1 || true
a wait-for-device
[ "$(a shell id -u | tr -d '\r')" = 0 ] || die "adb is not root: turn on Rooted debugging"

echo "== recovery partition"
size=$(a shell "blockdev --getsize64 $part" | tr -d '\r')
echo "size $size (expected $part_bytes)"
sum=$(a shell "sha256sum $part" | tr -d '\r' | cut -d' ' -f1)
echo "sha256 of the whole partition: $sum"
echo "magic: $(a shell "dd if=$part bs=8 count=1 2>/dev/null" | tr -d '\r\000')"

echo "== the same bytes as each image this project knows (first N bytes)"
for img in out/lineage-recovery-before-mainline.img out/prev/*.img out/recovery.img; do
	[ -f "$img" ] || continue
	n=$(stat -c %s "$img")
	want=$(sha256sum "$img" | cut -d' ' -f1)
	have=$(a shell "dd if=$part bs=4096 count=$((n / 4096)) 2>/dev/null | sha256sum" | tr -d '\r' | cut -d' ' -f1)
	if [ $((n % 4096)) = 0 ] && [ "$want" = "$have" ]; then
		echo "MATCH   $img"
	else
		echo "differs $img"
	fi
done

echo "== what could restore it"
a shell 'ls -l /system/bin/install-recovery.sh /vendor/bin/install-recovery.sh /system/etc/recovery-from-boot.p /system/recovery-from-boot.p 2>&1 | head -6'
a shell 'getprop | grep -i -E "recovery|flash_recovery" | head -10'
echo "-- services that mention recovery in init"
a shell 'grep -rl -i "install-recovery\|flash_recovery" /system/etc/init /vendor/etc/init /system_ext/etc/init /product/etc/init 2>/dev/null | head -6'
echo "-- install-recovery.sh (first lines)"
a shell 'cat /system/bin/install-recovery.sh 2>/dev/null | head -30'
a unroot >/dev/null 2>&1 || true
