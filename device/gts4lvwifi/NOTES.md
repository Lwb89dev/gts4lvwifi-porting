# gts4lvwifi notes

Newest first. Only facts checked against a tree or a document in this checkout.

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
