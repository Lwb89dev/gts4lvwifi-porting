#!/bin/sh
# Offline check of the first-light initramfs. Does not flash.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
archive=$root/out/initramfs.cpio.gz
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

gzip -dc "$archive" | (cd "$work" && cpio -id --quiet)
for path in init bin/busybox usr/sbin/muic-usb usr/sbin/rebootmode \
	usr/sbin/boot-android lib/modules/qcom-pon.ko \
	lib/modules/backlight.ko lib/modules/drm.ko \
	lib/modules/drm_kms_helper.ko lib/modules/drm_client_lib.ko \
	lib/modules/drm_sysfb_helper.ko lib/modules/drm_shmem_helper.ko \
	lib/modules/simpledrm.ko lib/modules/phy-qcom-qusb2.ko \
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
file "$work/usr/sbin/rebootmode" | grep -q "ARM aarch64"
file "$work/usr/sbin/rebootmode" | grep -q "statically linked"
[ -x "$work/usr/sbin/boot-android" ]
head -n 1 "$work/usr/sbin/boot-android" | grep -q '^#!/bin/busybox sh'
grep -q 'qcom-pon' "$work/init"
# qcom-pon must load after the telnet is up, not in the early module list.
telnet_line=$(grep -n '^log "telnet' "$work/init" | head -n 1 | cut -d: -f1)
pon_line=$(grep -n 'insmod /lib/modules/qcom-pon.ko' "$work/init" | head -n 1 | cut -d: -f1)
[ -n "$telnet_line" ] && [ -n "$pon_line" ] && [ "$pon_line" -gt "$telnet_line" ]
grep -q 'fw_devlink' "$root/device/gts4lvwifi/device.conf"
grep -q '172.16.42.1' "$work/init"
grep -q 'Does not write eMMC' "$work/init"
grep -q 'simpledrm' "$work/init"
grep -q 'phy-qcom-qusb2' "$work/init"
echo "initramfs ok  $(stat -c %s "$archive") bytes"
