#!/bin/sh
# Offline check of the first-light initramfs. Does not flash.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
archive=$root/out/initramfs.cpio.gz
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

gzip -dc "$archive" | (cd "$work" && cpio -id --quiet)
for path in init bin/busybox usr/sbin/muic-usb \
	lib/modules/backlight.ko lib/modules/drm.ko \
	lib/modules/drm_kms_helper.ko lib/modules/drm_client_lib.ko \
	lib/modules/drm_sysfb_helper.ko lib/modules/drm_shmem_helper.ko \
	lib/modules/simpledrm.ko \
	lib/modules/libcomposite.ko lib/modules/u_serial.ko \
	lib/modules/usb_f_acm.ko lib/modules/u_ether.ko \
	lib/modules/usb_f_ncm.ko lib/modules/usb_f_rndis.ko
do
	if [ ! -e "$work/$path" ]; then
		echo "initramfs missing $path" >&2
		exit 1
	fi
done
file "$work/bin/busybox" | grep -q "ARM aarch64"
file "$work/bin/busybox" | grep -q "statically linked"
file "$work/usr/sbin/muic-usb" | grep -q "ARM aarch64"
file "$work/usr/sbin/muic-usb" | grep -q "statically linked"
grep -q 'fw_devlink' "$root/device/gts4lvwifi/device.conf"
grep -q '172.16.42.1' "$work/init"
grep -q 'Does not write eMMC' "$work/init"
grep -q 'simpledrm' "$work/init"
echo "initramfs ok  $(stat -c %s "$archive") bytes"
