# gts4lvwifi notes

Newest first. Only facts checked against a tree or a document in this checkout.

## 2026-11-04 — mainline recovery booted to a black screen, then Lineage was restored

`out/recovery.img` from the GCC 15.3.0 nolibc kernel build, 15839232 bytes,
sha256 `ffe87fe60cffc74e3770ad9e57a7861a17bb89b7756bcf430fe138bb02cc8ee7`,
was written only to `recovery`. The readback matched. `boot` was not
written. `misc` was empty before the reboot. `adb reboot recovery` ran at
14:01. The panel stayed black. The host logged a USB disconnect at 14:01:43
and then no `04e8` or `18d1` device for more than a minute.

Download mode came up as `04e8:685d` (product string `SDM710`). Heimdall
2.0.2 flashed the pre-write partition copy to PIT partition `RECOVERY`
(142080 × 512 = 72744960 bytes) and rebooted. The following boot was
Lineage: `uname -r` = `4.9.337-ga30605a54f3b`, `sys.boot_completed=1`,
zygote running. The recovery header matched the backup. `misc` was empty
again. adbd was returned to the shell user.

A later USB id `18d1:d001` on that boot was still Android: `bcdDevice 4.09`,
product `SAMSUNG_Android`, ADB interface. It was not the initramfs, whose
product string is `gts4lvwifi first light`. No mainline `uname` was read.

## 2026-11-04 — recovery is 72744960 bytes, not 64 MiB

With adb root, `blockdev --getsize64` on this tablet:

| Partition | Bytes |
| --- | --- |
| boot | 67108864 |
| recovery | 72744960 |
| dtbo | 8388608 |
| system | 4932501504 |
| vendor | 939524096 |
| product | 629145600 |
| cache | 419430400 |
| userdata | 54951656960 |

`recovery` is the size pulpoff's image script already checks. The Lineage BoardConfig value of 67108864 is the `boot` partition. An image for `recovery` must be at most 72744960 bytes.

Both `boot` and `recovery` are Android boot header v1, page size 4096, kernel address `0x8000`, ramdisk `0x2000000`, tags `0x1e00000`, name `SRPSA14B001`. The cmdline is the Lineage one, including `androidboot.boot_devices=soc/7c4000.sdhci`. `boot` has no recovery dtbo. `recovery` carries a dtbo of 1305887 bytes at offset 29597696. That blob is byte-identical to the first 1305887 bytes of the `dtbo` partition (sha256 `bca502bdea00d1e629fb3b04f8a0734d0e4bb47b5ff220e6539f7abc33efe3f4`) and is saved as `lineage-recovery-dtbo.img`. The current recovery image occupies 30904320 bytes, so about 40 MiB of the partition is unused.

The system ext4 filesystem inside the 4932501504-byte partition has 1068292 blocks of 4096 bytes. adbd was returned to the shell user afterwards.

## 2026-11-04 — the connected tablet matches the port

Read over adb, nothing written. The device is an SM-T720, `ro.product.device=gts4lvwifi`, product `gts4lvwifixx`. LineageOS `22.2-20260909-NIGHTLY-gts4lvwifi`, Android 15, `userdebug`. The running kernel is `4.9.337-ga30605a54f3b`, the same commit as the pinned Lineage tree in `sources.lock`. `/proc/cpuinfo` reports `Qualcomm Technologies, Inc SDM670`. `MemTotal` is 3735364 kB, so this unit is the 4 GB model.

The bootloader is unlocked: `ro.boot.verifiedbootstate=orange`, `ro.boot.flash.locked=0`, `ro.boot.warranty_bit=1`. The bootloader string is `T720XXS2DUH1`. `ro.boot.slot_suffix` is empty. There is no A/B slot.

`/dev/block/by-name` is the eMMC map. The names the image cares about:

| Name | Node |
| --- | --- |
| boot | mmcblk0p48 |
| recovery | mmcblk0p49 |
| dtbo | mmcblk0p47 |
| vbmeta | mmcblk0p23 |
| misc | mmcblk0p34 |
| system | mmcblk0p50 |
| vendor | mmcblk0p51 |
| product | mmcblk0p52 |
| cache | mmcblk0p53 |
| userdata | mmcblk0p57 |

Shell cannot read `/sys/class/block/*/size` or the partition contents. Rooted debugging is off, and `su` is not on the shell path, so the byte size of `recovery` is still the Lineage BoardConfig value, 64 MiB. Filesystem sizes from `df`: system 4.0G, vendor 868M, cache 334M, userdata 49G with 29G free. `/data` is ext4 with file-based encryption (`ro.crypto.state=encrypted`, `ro.crypto.type=file`), matching `fstab.qcom` on the device (`fileencryption=ice`). The external card node in that fstab is `8804000.sdhci`; internal storage is the named eMMC partitions.

`/product` is a real partition. It was not mounted on its own in `df`.

## 2026-11-03 — sources pinned, nothing flashed

The tablet is a Samsung Galaxy Tab S5e Wi-Fi, SM-T720 / SM-T720N, Snapdragon 670,
eMMC, one slot. LineageOS 22.2 (`AB_OTA_UPDATER := false`, boot header v1,
`boot` and `recovery` 64 MiB each) is the Android reference. The kernel that
already boots this board on mainline is pulpoff/linux-gts4lv `36f309c07087`
(Linux 7.2.13 plus sdm670-mainline plus the tablet DTS). Its DTB is
`arch/arm64/boot/dts/qcom/sdm670-samsung-gts4lvwifi.dts`, compatible
`samsung,gts4lvwifi`, `qcom,msm-id = <336 0>`, simple-framebuffer 2560×1600.

Omarchy Mobile's installer writes a fastboot slot B and leaves stock on slot A.
This tablet has neither. The boot path that already works puts Linux in
`recovery` and leaves LineageOS in `boot`. Samsung's bootloader accepts
Lineage's own `recovery_dtbo` and rejects an overlay that does not apply; the
mainline DTB carries empty labels for that overlay
(`sdm670-samsung-gts4lvwifi-dtbo-mask.dtsi`).

`linux-omarchy-mobile` is a Tensor tree. It is not the base for this port.
The build machine for the kernel is the Omen 16. This checkout does not
contain a built Image.
