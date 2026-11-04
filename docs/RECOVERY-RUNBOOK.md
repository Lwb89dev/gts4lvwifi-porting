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

The screen can stay black even if that shell exists: `CONFIG_DRM_SIMPLEDRM`
is off. Do not treat a black panel alone as proof the kernel is dead.
Do treat a minute with no USB device as a failed boot.

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

## What the 2026-11-04 attempt showed

The image was the GCC 15.3.0 nolibc build, sha256
`ffe87fe60cffc74e3770ad9e57a7861a17bb89b7756bcf430fe138bb02cc8ee7`.
The readback matched. After `adb reboot recovery` the panel stayed black
and the host saw no USB device until Download mode. Heimdall restored the
backup. Lineage completed boot. The mainline shell was not reached, so the
same image must not be flashed again unchanged.
