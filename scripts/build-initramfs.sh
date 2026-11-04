#!/bin/sh
# Build the first-light initramfs and pack it as a recovery image.
# Does not flash the tablet.
#
#   scripts/build-initramfs.sh
#
# Needs the kernel modules from scripts/build-kernel.sh and aarch64-linux-gnu-gcc.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cross=${CROSS_COMPILE:-aarch64-linux-gnu-}
bb=$root/src/busybox
stage=$root/out/initramfs
modroot=$root/out/kernel/modules/lib/modules
bb_ver=1.36.1
bb_sha=b8cc24c9574d809e7279c3be349795c5d5ceb6fdf19ca709f80cde50e47de314
bb_url=https://busybox.net/downloads/busybox-$bb_ver.tar.bz2

if ! command -v "${cross}gcc" >/dev/null 2>&1; then
	echo "compiler not found: ${cross}gcc" >&2
	exit 1
fi

set_opt() {
	key=$1
	file=$bb/.config
	if grep -q "^$key=y" "$file"; then
		return 0
	fi
	if grep -q "^# $key is not set" "$file"; then
		sed -i "s/^# $key is not set/$key=y/" "$file"
		return 0
	fi
	echo "$key=y" >> "$file"
}

set_off() {
	key=$1
	file=$bb/.config
	if grep -q "^# $key is not set" "$file"; then
		return 0
	fi
	if grep -q "^$key=y" "$file"; then
		sed -i "s/^$key=y/# $key is not set/" "$file"
		return 0
	fi
	echo "# $key is not set" >> "$file"
}

if [ ! -x "$bb/busybox" ]; then
	rm -rf "$bb"
	mkdir -p "$bb"
	archive=$root/src/busybox-$bb_ver.tar.bz2
	if [ ! -f "$archive" ]; then
		curl -fL --retry 3 -o "$archive" "$bb_url"
	fi
	echo "$bb_sha  $archive" | sha256sum -c -
	tar -C "$bb" --strip-components=1 -xf "$archive"
	make -C "$bb" CROSS_COMPILE="$cross" defconfig >/dev/null
	set_opt CONFIG_STATIC
	set_opt CONFIG_ASH
	set_opt CONFIG_TELNETD
	set_opt CONFIG_UDHCPD
	set_opt CONFIG_IP
	set_opt CONFIG_IPADDR
	set_opt CONFIG_IPLINK
	set_opt CONFIG_INSMOD
	# Ubuntu 24.04 headers dropped the CBQ structs this tc applet still uses.
	set_off CONFIG_TC
	yes '' | make -C "$bb" CROSS_COMPILE="$cross" oldconfig >/dev/null
	make -C "$bb" CROSS_COMPILE="$cross" -j"$(nproc)"
fi

for key in CONFIG_STATIC CONFIG_ASH CONFIG_TELNETD CONFIG_UDHCPD CONFIG_IP CONFIG_INSMOD; do
	grep -q "^$key=y" "$bb/.config"
done
file "$bb/busybox" | grep -q "ARM aarch64"
file "$bb/busybox" | grep -q "statically linked"

rels=$modroot/*
set -- $rels
if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
	echo "kernel modules missing: $modroot" >&2
	echo "run scripts/build-kernel.sh first" >&2
	exit 1
fi
rel=$1

rm -rf "$stage"
mkdir -p "$stage/bin" "$stage/usr/sbin" "$stage/lib/modules"
cp "$bb/busybox" "$stage/bin/busybox"
cp "$root/device/gts4lvwifi/initramfs/init" "$stage/init"
"${cross}gcc" -static -Os -s -o "$stage/usr/sbin/muic-usb" \
	"$root/device/gts4lvwifi/initramfs/muic-usb.c"
for name in libcomposite u_serial usb_f_acm u_ether usb_f_ncm usb_f_rndis; do
	found=$(find "$rel" -name "$name.ko" -print)
	if [ -z "$found" ]; then
		echo "module missing: $name.ko" >&2
		exit 1
	fi
	cp "$found" "$stage/lib/modules/$name.ko"
done
chmod 755 "$stage/bin/busybox" "$stage/init" "$stage/usr/sbin/muic-usb"

archive=$root/out/initramfs.cpio.gz
(cd "$stage" && find . | cpio -o -H newc -R 0:0 --quiet) | gzip -9 > "$archive"

"$root/scripts/pack-recovery.py" \
	--kernel "$root/out/kernel/arch/arm64/boot/Image.gz-dtb" \
	--ramdisk "$archive" \
	-o "$root/out/recovery.img"
echo "initramfs      $(stat -c %s "$archive") bytes  $archive"
echo "not flashed"
