#!/bin/bash
# Replace the root image while the tablet is deliberately stopped in the
# project's initramfs shell. Unlike rootfs-to-tablet.sh, this does not boot
# Android and therefore cannot let Android rewrite recovery.
#
#   TABLET_BIND=172.16.42.3 ROOTFS_VARIANT=omarchy \
#     scripts/rootfs-to-tablet-shell.sh
#
# The old image is removed before transfer when userdata cannot hold both.
# A failed transfer is recoverable by rerunning this script: the initramfs
# shell and recovery partition do not depend on that file.
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
cd "$root"
host=${TABLET_IP:-172.16.42.1}
bind=${TABLET_BIND:-}
min_free_mb=${ROOTFS_MIN_FREE_MB:-4096}
variant=${ROOTFS_VARIANT:-}
case $variant in
"") image_dir=out/rootfs ;;
*[!a-z0-9-]*) echo "ROOTFS_VARIANT may contain only a-z, 0-9 and -" >&2; exit 1 ;;
*) image_dir=out/rootfs-$variant ;;
esac
image=$image_dir/rootfs.img
extents=$image_dir/rootfs-extents.txt
remote_dir=/mnt/data/lost+found/gts4lv
remote=$remote_dir/rootfs.img
fiemap=/tmp/gts4lv-fiemap
image_port=${ROOTFS_IMAGE_PORT:-9004}
fiemap_port=9005
transfer=${ROOTFS_TRANSFER:-pv}
transfer_timeout=${ROOTFS_TRANSFER_TIMEOUT:-900}
chunk_mb=${ROOTFS_CHUNK_MB:-64}
chunk_start=${ROOTFS_CHUNK_START:-0}
chunk_count=${ROOTFS_CHUNK_COUNT:-0}

die() { echo "rootfs-to-tablet-shell: $*" >&2; exit 1; }

ncc() {
	if [ -n "$bind" ]; then
		nc -s "$bind" "$@"
	else
		nc "$@"
	fi
}

# Run one command in the unauthenticated initramfs shell and keep only the
# delimited command output. This transport must never be used after switch_root.
t() {
	printf 'echo __BEGIN__; %s\necho __END__\nexit\n' "$1" |
		ncc -w "${2:-30}" "$host" 23 |
		LC_ALL=C tr -d '\r\000' |
		LC_ALL=C sed 's/\x1b\[[0-9;]*m//g' |
		sed -n '/^__BEGIN__$/,/^__END__$/p' | sed '1d;$d' |
		grep -v '^~ # ' || true
}

listener_pid=/tmp/gts4lv-rootfs-listener.pid
start_listener() {
	local port=$1 redirect=$2
	# The tiny initramfs telnet daemon starts a new shell for every t() call.
	# Keep nc in the background and record its PID, then use the next shell to
	# poll the written byte count and stop exactly that receiver.
	t "rm -f $listener_pid; (setsid nc -l -p $port $redirect $remote </dev/null 2>&1 & echo \$! > $listener_pid); sleep 1" >/dev/null
}

finish_listener() {
	local expected=$1 have attempt
	attempt=0
	while [ "$attempt" -lt 15 ]; do
		have=$(t "stat -c %s $remote" | tail -n 1)
		[ "$have" = "$expected" ] && break
		attempt=$((attempt + 1))
		sleep 1
	done
	t "test -r $listener_pid && kill \$(cat $listener_pid) 2>/dev/null || true; rm -f $listener_pid; sync" >/dev/null
	[ "${have:-}" = "$expected" ] || die "receiver wrote ${have:-nothing} bytes, expected $expected"
}

case $min_free_mb in
""|*[!0-9]*) die "ROOTFS_MIN_FREE_MB must be a non-negative integer" ;;
esac
case $image_port in
""|*[!0-9]*|0|*[!0-9]*) die "ROOTFS_IMAGE_PORT must be a TCP port number" ;;
esac
[ "$image_port" -le 65535 ] || die "ROOTFS_IMAGE_PORT must be at most 65535"
case $transfer in
pv|dd|chunked) ;;
*) die "ROOTFS_TRANSFER must be pv, dd or chunked" ;;
esac
case $transfer_timeout in
""|*[!0-9]*|0) die "ROOTFS_TRANSFER_TIMEOUT must be a positive integer" ;;
esac
case $chunk_mb in
""|*[!0-9]*|0) die "ROOTFS_CHUNK_MB must be a positive integer" ;;
esac
[ $((chunk_mb % 4)) -eq 0 ] || die "ROOTFS_CHUNK_MB must be a multiple of 4"
case $chunk_start:$chunk_count in
*[!0-9:]*|*:*:*) die "ROOTFS_CHUNK_START and ROOTFS_CHUNK_COUNT must be non-negative integers" ;;
esac
[ -f "$image" ] || die "no $image"
[ -x out/tools/fiemap ] || die "no static out/tools/fiemap"
[ "$(stat -c %s "$image")" -gt 0 ] || die "$image is empty"
if [ -n "$bind" ]; then
	ip -4 addr show | grep -Fq " $bind/" || die "TABLET_BIND $bind is not a local IPv4 address"
fi
ncc -z -w2 "$host" 23 2>/dev/null || die "the initramfs shell does not answer on $host:23"

info=$(t 'uname -r; tr "\0" " " < /proc/device-tree/model; echo; test ! -d /run/systemd/system && echo initramfs')
echo "$info"
echo "$info" | grep -q gts4lvwifi || die "this is not the gts4lvwifi kernel"
echo "$info" | grep -q GTS4LVWIFI || die "the device tree is not GTS4LVWIFI"
echo "$info" | grep -q initramfs || die "the tablet has already switched to the rootfs"

# Discover userdata by its GPT name and mount it directly. There must be one
# matching block device, and it must be ext4 on this installation model.
# The command is single-quoted because its variables expand on the tablet.
# shellcheck disable=SC2016
userdata=$(t 'for u in /sys/class/block/mmcblk0p*/uevent; do grep -q "^PARTNAME=userdata$" "$u" && basename "$(dirname "$u")"; done')
if [ -z "$userdata" ] || [ "$(printf '%s\n' "$userdata" | wc -l)" -ne 1 ]; then
	die "userdata partition not found or not unique ($userdata)"
fi
t "mkdir -p /mnt/data; mountpoint -q /mnt/data || mount -t ext4 -o rw,noatime /dev/$userdata /mnt/data; grep ' /mnt/data ' /proc/mounts" | grep -q ' ext4 ' ||
	die "could not mount userdata as ext4"

need_kb=$(($(stat -c %s "$image") / 1024))
space=$(t "free=\$(df -k /mnt/data | tail -n 1 | awk '{print \$4}'); reclaim=0; if [ -L $remote ]; then echo bad; elif [ -f $remote ]; then reclaim=\$(du -k $remote | awk '{print \$1}'); elif [ -e $remote ]; then echo bad; fi; echo \$free \$reclaim")
echo "$space" | grep -qx bad && die "$remote is neither a regular file nor missing"
free_kb=$(printf '%s\n' "$space" | tail -n 1 | awk '{print $1}')
reclaim_kb=$(printf '%s\n' "$space" | tail -n 1 | awk '{print $2}')
case ${free_kb:-}:${reclaim_kb:-} in
*[!0-9:]*|:*|*:) die "could not read userdata free space ($space)" ;;
esac
echo "need ${need_kb} KiB plus ${min_free_mb} MiB reserve; userdata has ${free_kb} KiB free and ${reclaim_kb} KiB reclaimable"
[ $((free_kb + reclaim_kb)) -gt $((need_kb + min_free_mb * 1024)) ] || die "not enough replaceable space"

want=$(sha256sum "$image" | cut -d' ' -f1)
echo "sending $image ($want)"
if [ "$transfer" = chunked ]; then
	chunk_bytes=$((chunk_mb * 1024 * 1024))
	image_bytes=$(stat -c %s "$image")
	chunks=$(((image_bytes + chunk_bytes - 1) / chunk_bytes))
	[ "$chunk_start" -lt "$chunks" ] || die "ROOTFS_CHUNK_START is beyond the image"
	if [ "$chunk_start" -eq 0 ]; then
		t "mkdir -p $remote_dir; rm -f $remote" >/dev/null
	else
		expected_start=$((chunk_start * chunk_bytes))
		[ "$expected_start" -gt "$image_bytes" ] && expected_start=$image_bytes
		have_start=$(t "stat -c %s $remote" | tail -n 1)
		[ "$have_start" = "$expected_start" ] || die "resume point has $have_start bytes, expected $expected_start"
	fi
	chunk_end=$chunks
	if [ "$chunk_count" -gt 0 ]; then
		chunk_end=$((chunk_start + chunk_count))
		[ "$chunk_end" -le "$chunks" ] || chunk_end=$chunks
	fi
	for n in $(seq "$chunk_start" $((chunk_end - 1))); do
		offset=$((n * chunk_bytes))
		remaining=$((image_bytes - offset))
		this_chunk=$chunk_bytes
		[ "$remaining" -lt "$this_chunk" ] && this_chunk=$remaining
		count=$(((this_chunk + 4194303) / 4194304))
		start_listener "$image_port" '>>'
		dd if="$image" bs=4M skip=$((offset / 4194304)) count="$count" status=none |
			ncc -w "$transfer_timeout" "$host" "$image_port" || true
		expected=$((offset + this_chunk))
		finish_listener "$expected"
		echo "chunk $((n + 1))/$chunks: $expected bytes"
	done
	if [ "$chunk_end" -lt "$chunks" ]; then
		echo "batch complete; resume with ROOTFS_CHUNK_START=$chunk_end"
		exit 0
	fi
else
	t "mkdir -p $remote_dir; rm -f $remote" >/dev/null
	start_listener "$image_port" '>'
if [ "$transfer" = pv ] && command -v pv >/dev/null 2>&1; then
	pv -ptearb "$image" | ncc -w "$transfer_timeout" "$host" "$image_port" || true
else
	dd if="$image" bs=4M status=progress | ncc -w "$transfer_timeout" "$host" "$image_port" || true
fi
	finish_listener "$(stat -c %s "$image")"
fi
t 'sync' 120 >/dev/null
have=$(t "sha256sum $remote" 600 | awk '{print $1}')
[ "$have" = "$want" ] || die "tablet image hash is $have, wanted $want"
echo "copy verified, sha256 $have"

fiemap_want=$(sha256sum out/tools/fiemap | cut -d' ' -f1)
t "rm -f $fiemap" >/dev/null
remote=$fiemap
start_listener "$fiemap_port" '>'
ncc -w 10 "$host" "$fiemap_port" < out/tools/fiemap
finish_listener "$(stat -c %s out/tools/fiemap)"
remote=$remote_dir/rootfs.img
t "chmod 755 $fiemap"
[ "$(t "sha256sum $fiemap" | awk '{print $1}')" = "$fiemap_want" ] || die "fiemap copy differs"
t "$fiemap $remote" 600 > "$extents.raw"
tr -d '\r' < "$extents.raw" > "$extents"
rm -f "$extents.raw"
total=$(awk '{ sum += $3 } END { print sum }' "$extents")
[ "$total" = "$(stat -c %s "$image")" ] || die "extents cover $total bytes, not the image size"
echo "$(wc -l < "$extents") extents covering $total bytes: $extents"
t "rm -f $fiemap; sync; umount /mnt/data" 120 >/dev/null
echo "done. Rebuild initramfs before rebooting the tablet."
