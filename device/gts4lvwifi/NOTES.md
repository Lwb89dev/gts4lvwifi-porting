# gts4lvwifi notes

Newest first. Only facts checked against a tree or a document in this checkout.

## 2026-11-04 — gadget bound, MUIC did not switch

`photo_2026-11-04_21-00-39.jpg` is the second console. Lines read from it:

- `gts4lv-init: up, kernel 7.2.13-gts4lvwifi-g36f309c07087`
- `gts4lv-init: gadget bound to a600000.usb`
- `gts4lv-init: muic not switched`
- `gts4lv-init: usb0 172.16.42.1`
- `gts4lv-init: telnet 172.16.42.1`

The host still did not see `18d1:d001`. `CONFIG_I2C_GPIO` is not set, so
the bit-banged `i2c-charger` bus in the DTS does not exist and
`muic-usb` has nowhere to write `MANSW1=0x24`. The D+/D- pair stays off
the SoC. The USB PHY module did remove the earlier `dwc3` deferral.

## 2026-11-04 — USB PHY module packed and written, not booted

`CONFIG_PHY_QCOM_QUSB2=m` and the module has no dependencies. The
initramfs now insmods `phy-qcom-qusb2` after simpledrm and before the
gadget modules. The kernel image is unchanged.

Heimdall 2.0.2 wrote this `recovery.img` to `RECOVERY` with
`--no-reboot`. The only download-mode device was `04e8:685d`, product
`SDM710`. The tablet was still in download mode afterwards.

| File | Bytes | sha256 |
| --- | --- | --- |
| recovery.img | 16736256 | `cf1703154e13732b5040714980438527632ea75f7ec09106bd7c84d753c0d864` |
| initramfs.cpio.gz | 1861108 | `812e1aae8b0cd2c0cce0e4ea186f8c3d78b29fcaab7d76d5f40c78478e93a5c5` |

Readback count for a later `dd` check: `16736256 / 4096 = 4086`.

## 2026-11-04 — console photo: init ran, dwc3 did not

`photo_2026-11-04_20-40-21.jpg` is the framebuffer console. Lines read
from it:

- `gts4lv-init: up, kernel 7.2.13-gts4lvwifi-g36f309c07087` at about 1.06 s
- `clk: Not disabling unused clocks` and `PM: genpd: Not disabling unused power domains`
- `mmc0` on `7c4000.mmc`, HS400, `mmcblk0` `DH6DAB` 58.2 GiB, partitions through `p56`
- `[drm] Initialized simpledrm 1.0.0 for chosen/framebuffer@9c000000`
- `/init: line 40: can't open /proc/device-tree/serial-number: no such file`
- `platform a600000.usb: deferred probe pending: dwc3: failed to initialize core` at about 11.26 s
- then `Timed out, forcing sync_state()` from `gcc`, `qnoc-sdm670`, `gpucc`, `videocc`, `disp_cc` and `qcom-rpmhpd`
- `random: crng init done` at about 23.4 s

No `Kernel panic` in the frame. The initramfs USB id never appeared
because `dwc3` did not finish core init, so no UDC was registered.

## 2026-11-04 — same recovery rewritten from download mode, not booted

The owner asked to repeat the boot with a camera ready. Heimdall 2.0.2
wrote `out/recovery.img` (16728064 bytes, sha256
`d57f386497b67aec1de7a4386a5cd9a84e89d737763a3d9bd14ab77709fccb11`)
to `RECOVERY` with `--no-reboot`. The download-mode device was `04e8:685d`,
product `SDM710`, on bus 003. The other Samsung phone was left in MTP and
was not addressed. The tablet was still in download mode after the upload.

## 2026-11-04 — ramoops recovery showed a terminal, then powered off

The owner saw a black screen with terminal text, then the tablet powered
off by itself. The host USB log does not show `18d1:d001` or the product
string `gts4lvwifi first light` at any point. The last tablet enumeration
was Lineage at 20:22:38 (`04e8:6860`, `bcdDevice 4.09`, serial
`R52M410RCVR`, product `SAMSUNG_Android`). That port disconnected at
20:30:14 and did not come back. A full power-off drops the ramoops RAM
buffer. `boot` was not written.

## 2026-11-04 — ramoops recovery written, not booted yet

`out/recovery.img`, 16728064 bytes, sha256
`d57f386497b67aec1de7a4386a5cd9a84e89d737763a3d9bd14ab77709fccb11`,
was written only to `recovery` while Lineage was running. The readback
of `4084` pages matched. `boot` was not written. `misc` was empty before
the write and was not changed. `adb reboot recovery` was not used.
The running kernel was still `4.9.337-ga30605a54f3b`.

## 2026-11-04 — ramoops console built in, not flashed

The two flashed images used the same load addresses, page size, header
version, board name `SRPSA14B001` and `os_version` as the Lineage recovery
that boots. `CONFIG_PSTORE_RAM` was `=m`, so the DTS region `0xa1300000`
(1 MiB, same sizes as the Lineage 4.9 tree) never attached before init.
This build sets `CONFIG_PSTORE_RAM=y` and `CONFIG_PSTORE_CONSOLE=y`.
`ramoops` is in `modules.builtin` and there is no loadable `ramoops.ko`.
`CONFIG_DRM_SIMPLEDRM` stays `=m`. The DTB hash is unchanged. Compiler is
Ubuntu GCC 13.3.0. `Image.gz-dtb` is the concatenation of the two files.
Nothing was written to the tablet.

| File | Bytes | sha256 |
| --- | --- | --- |
| Image.gz | 13458503 | `efcf82d92cbee39558ff019254346bca54f3fed0dbb50e760ba5379c4f5673e8` |
| DTB | 101142 | `e496d21301ce3306f11a9bc0092e457b04ab585016c71dc97b19c22fb13e1212` |
| Image.gz-dtb | 13559645 | `997d6d975c2f43c17eaca0ab8cb100473c6aae36a3e58f761393efb1badaf8c9` |
| initramfs.cpio.gz | 1855217 | `b60c769fb5e1ac5387d884f9f8d28af7a7cc1580946a3e208082d3171b63ea12` |
| recovery.img | 16728064 | `d57f386497b67aec1de7a4386a5cd9a84e89d737763a3d9bd14ab77709fccb11` |

Readback count for this file only: `16728064 / 4096 = 4084`.

## 2026-11-04 — Lineage restored after the simpledrm recovery boot

Download mode was `04e8:685d`. Heimdall 2.0.2 uploaded `RECOVERY` to 100%
from `out/lineage-recovery-before-mainline.img` and rebooted. `boot` was
not written. After adb was authorized again:

| Fact | Value |
| --- | --- |
| Device | SM-T720, `gts4lvwifi`, serial `R52M410RCVR` |
| Kernel | `4.9.337-ga30605a54f3b` |
| `sys.boot_completed` | `1` |
| `recovery` | 72744960 bytes, sha256 `81f4d19e4d9d3ba37c2044d57b77c72f01487dbaaa3a24173b14bacc161b14a7`, identical to the backup, magic `ANDROID!` |
| `misc` | command, status, recovery and stage fields empty |
| adbd | returned to uid 2000 |

## 2026-11-04 — simpledrm recovery written, USB still absent

The distro-gcc image was written only to `recovery` while Lineage was
running. The readback matched. `boot` was not written. `misc` was empty
before `adb reboot recovery`.

| Fact | Value |
| --- | --- |
| Image sha256 | `71e09d2993306753e0ce4ebafb27b4fd83cc1e195438dd25dc7b4b55f3c2477a` |
| Size | 16715776 bytes |
| Reboot | `adb reboot recovery` at 19:50:41 |
| Host USB | disconnect of `04e8:6860` at 19:50:43, then no `04e8` and no `18d1` for 90 seconds |
| Ping | `172.16.42.1` did not answer |

The host cannot see the panel. No mainline `uname` was read. Rollback is
still `out/lineage-recovery-before-mainline.img`, sha256
`81f4d19e4d9d3ba37c2044d57b77c72f01487dbaaa3a24173b14bacc161b14a7`.
That file matched the live partition before this write.

## 2026-11-04 — simpledrm module packed, not flashed

`CONFIG_DRM=m` and `CONFIG_DRM_SIMPLEDRM=m`. `CONFIG_FB_SIMPLE` and
`CONFIG_DRM_PANEL_SAMSUNG_ANA38401` stay off. The initramfs insmods, in
`modules.dep` order, before the USB gadget: `backlight`, `drm`,
`drm_kms_helper`, `drm_client_lib`, `drm_sysfb_helper`, `drm_shmem_helper`,
`simpledrm`, then the six gadget modules.

This build used Ubuntu GCC 13.3.0. `Image.gz-dtb` is the concatenation of
`Image.gz` and the unchanged DTB. Nothing was written to the tablet.

| File | Bytes | sha256 |
| --- | --- | --- |
| Image.gz | 13447162 | `35404e2b0f4d439d424edde353d4aeff34131637588d4acf40eecf05242b8426` |
| DTB | 101142 | `e496d21301ce3306f11a9bc0092e457b04ab585016c71dc97b19c22fb13e1212` |
| Image.gz-dtb | 13548304 | `ca07119d914b06b89167f262ef94978716ef078190886f17aedfb8d1cafd76bd` |
| initramfs.cpio.gz | 1855221 | `ad9acb6670ffb3e05d5dbd592f874ad4c8b4b92588ba8a958c6e3f421badfedf` |
| recovery.img | 16715776 | `71e09d2993306753e0ce4ebafb27b4fd83cc1e195438dd25dc7b4b55f3c2477a` |

Release `7.2.13-gts4lvwifi-g36f309c07087`. The earlier distro-gcc image
without simpledrm is no longer the file at `out/recovery.img`. Do not flash
the GCC 15.3.0 image `ffe87fe60cffc74e3770ad9e57a7861a17bb89b7756bcf430fe138bb02cc8ee7`.

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
