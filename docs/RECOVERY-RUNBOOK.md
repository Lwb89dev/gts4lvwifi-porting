# Recovery runbook

Do not run this until the owner of the tablet says so in that session.
The scripts in this repo do not flash. The sequence below is the manual
procedure, and it failed once already.

Risk: `recovery` is replaced. `boot` stays Lineage, but a kernel that
never opens USB leaves a black screen and no adb. Download mode is the
way back only if the key combination works and a recovery image is on disk.
There is no stock firmware tarball in this checkout. The rollback that
worked on 2026-11-04 was a full-partition copy plus Heimdall.

## Stop immediately if

- `adb shell getprop ro.product.model` is not `SM-T720`.
- `ro.product.device` is not `gts4lvwifi`. The LTE SM-T725 is out of scope.
- `scripts/verify-recovery.py` fails on the image.
- The image is larger than 72744960 bytes.
- The readback after the write does not match the file.
- `lsusb` is not `04e8:685d` before Heimdall runs.

## 0. Identify and back up

Lineage must be booted, USB debugging authorized, then:

```sh
adb root
adb shell getprop ro.product.model
adb shell getprop ro.product.device
adb shell blockdev --getsize64 /dev/block/by-name/recovery
```

Expected size: `72744960`.

```sh
adb shell 'dd if=/dev/block/by-name/recovery of=/data/local/tmp/recovery-backup.img bs=4096 status=none'
adb pull /data/local/tmp/recovery-backup.img out/lineage-recovery-before-mainline.img
```

Expected: file size 72744960, first bytes `ANDROID!`, sha256 recorded
before any write. `misc` should be read and left unchanged:

```sh
adb exec-out 'dd if=/dev/block/by-name/misc bs=32 count=1 status=none'
```

An empty command field means a normal power-on boots `boot`, not `recovery`.

## 1. Write only recovery

```sh
adb push out/recovery.img /data/local/tmp/recovery-new.img
adb shell 'dd if=/data/local/tmp/recovery-new.img of=/dev/block/by-name/recovery bs=4096 conv=fsync status=none && sync'
adb shell 'dd if=/dev/block/by-name/recovery of=/data/local/tmp/recovery-readback.img bs=4096 count=3867 status=none'
adb pull /data/local/tmp/recovery-readback.img /tmp/recovery-readback.img
cmp -n "$(stat -c %s out/recovery.img)" out/recovery.img /tmp/recovery-readback.img
```

`15839232 / 4096 = 3867` only for that particular image. Recompute `count`
from the new file size. If `cmp` fails, write the backup back to
`/dev/block/by-name/recovery` and do not reboot.

Delete the copies under `/data/local/tmp` after a match. They are not the
rollback copy. The rollback copy stays on the PC.

## 2. Boot

Prefer a one-shot recovery boot. On this tablet, Volume Up plus Power from
the powered-off state is the manual recovery entry. `adb reboot recovery`
was used on 2026-11-04. `misc` was empty before that reboot and empty again
after the rollback, so it did not stick, but a black screen with no USB
still required Download mode.

Expected if the kernel reaches the initramfs: a USB device `18d1:d001`
whose product string is `gts4lvwifi first light`, address `172.16.42.1`,
telnet to a shell. `bcdDevice 4.09` with product `SAMSUNG_Android` and an
ADB interface is Lineage, not this initramfs.

The current initramfs loads simpledrm before it binds the gadget. A
bootloader splash means that insmod ran. A black panel means it did not
bind the framebuffer, and that alone does not prove the kernel is dead.
`CONFIG_DRM_PANEL_SAMSUNG_ANA38401` stays off. A minute with no USB
device is a failed boot.

## 3. Rollback

Force power off: hold Power and Volume Down until it stays off.
Download mode: hold Volume Up and Volume Down, then plug in USB.
Confirm with Volume Up. `lsusb` must show `04e8:685d`.

```sh
heimdall detect
heimdall flash --RECOVERY out/lineage-recovery-before-mainline.img
```

That writes the PIT partition `RECOVERY` and reboots. It does not touch
`BOOT`. After Lineage is up, confirm:

```sh
adb shell uname -r
adb shell getprop sys.boot_completed
```

Expected kernel `4.9.337-ga30605a54f3b` and `sys.boot_completed` = `1`.
Then `adb unroot` if root was enabled.

## 3b. Back to Lineage from the mainline shell, no flash (tested 2026-11-04)

A key reset does **not** do this. On 2026-11-04 at 21:29 a Power plus Volume
Down reset from the running initramfs came back into the same recovery
(`androidboot.boot_recovery=1`), with `misc` empty before and after. What
worked is a software restart that asks the PMIC for Samsung's NORMALBOOT
(0x14, `mode-android` in the DTS), which starts the `boot` partition.

It needs the `qcom-pon` module, which is `=m` and which the initramfs init
does not load yet. Without it nothing writes `PON_SOFT_RB_SPARE`, and the
restart is a warm reset, which this tablet's ABL can hang on. Until the init
loads it, copy it into RAM from the PC (nothing touches the eMMC):

```sh
KO=out/kernel/modules/lib/modules/*/kernel/drivers/power/reset/qcom-pon.ko
# on the tablet, over telnet 172.16.42.1:
#   (nc -l -p 9001 > /tmp/qcom-pon.ko &); (nc -l -p 9002 > /tmp/rebootmode &)
nc -w 3 172.16.42.1 9001 < $KO
nc -w 3 172.16.42.1 9002 < rebootmode      # static aarch64, 15 lines of C
# on the tablet:
#   chmod +x /tmp/rebootmode; insmod /tmp/qcom-pon.ko
#   ls /sys/class/reboot-mode/qcom-pon     # must exist, else stop
#   dd if=/dev/mmcblk0p34 bs=4096 count=1 | tr -d '\0' | wc -c   # must be 0
#   /tmp/rebootmode android
```

Result on 2026-11-04: the command ran at 21:35:20, the host saw
`04e8:6860` (`SAMSUNG_Android`, `bcdDevice 4.09`) at 21:35:57 and
`sys.boot_completed=1` by 21:36:23. Lineage 22.2-20260909, kernel
`4.9.337-ga30605a54f3b`, `ro.boot.boot_recovery=0`, adbd as uid 2000.
`/proc/cmdline` is not readable from the shell user on this build, so use
the `ro.boot.*` properties. Always pass `adb -s R52M410RCVR`: a Galaxy S24
may be on the same host.

Stop and use section 3 if no USB id appears within about 90 seconds.

## 4. Read ramoops after a failed mainline boot

This applies only to an image built with `CONFIG_PSTORE_RAM=y` and
`CONFIG_PSTORE_CONSOLE=y`. The two images already flashed did not have
that, and their console is gone. Do not flash again until this section
is the approved attempt.

The DTS reserves `0xa1300000` for 1 MiB, with the same record, console,
ftrace and pmsg sizes as the Lineage 4.9 tree. Lineage has
`CONFIG_PSTORE_RAM=y`, so a warm boot back into Android can show the
mainline console under `/sys/fs/pstore/`.

`adb reboot recovery` writes `boot-recovery` into `misc`. A hang then
stays in the broken recovery, and Download mode is a power cut that
drops the RAM buffer. For this attempt, boot with Volume Up plus Power
from the powered-off state and do not use `adb reboot recovery`.

If no `18d1:d001` gadget appears within a minute:

1. Hold Power and Volume Down only until the tablet resets, then release.
   Do not hold the keys until it stays off. A full power-off clears ramoops.
2. Let it boot. `misc` was empty, but on 2026-11-04 this did **not** enter
   `boot`: it re-entered recovery (see section 3b).
3. If USB returns as Lineage (`04e8:6860` or `18d1:d001` with product
   `SAMSUNG_Android`), do not flash. Read the buffer:

```sh
adb root
adb shell ls -l /sys/fs/pstore
adb pull /sys/fs/pstore out/pstore
```

4. Download mode remains the rollback if that warm reset does not reach
   Lineage. Expect the ramoops contents to be gone in that case, then
   follow section 3.

## What the 2026-11-04 attempt showed

The image was the GCC 15.3.0 nolibc build, sha256
`ffe87fe60cffc74e3770ad9e57a7861a17bb89b7756bcf430fe138bb02cc8ee7`.
The readback matched. After `adb reboot recovery` the panel stayed black
and the host saw no USB device until Download mode. Heimdall restored the
backup. Lineage completed boot. The mainline shell was not reached, so the
same image must not be flashed again unchanged.
