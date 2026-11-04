# gts4lvwifi notes

Newest first. Only facts checked against a tree or a document in this checkout.

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
