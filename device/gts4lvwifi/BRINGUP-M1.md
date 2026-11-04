# gts4lvwifi first light

Goal of this stage: a mainline `Image.gz` with `sdm670-samsung-gts4lvwifi.dtb`
appended, built from the pinned tree, small enough to sit in the recovery
partition later. No partition is written in this stage.

## What stays untouched

`boot`, `dtbo`, `system`, `vendor`, `userdata`, `efs`, `persist`, `modem` and
the bootloader stay as LineageOS left them. The only partition a later image
may write is `recovery`, and only after a stock firmware package is on hand
so Download mode can restore the tablet. This repo has no flash command.

## Hardware facts the image has to match

From Lineage `BoardConfigCommon.mk` on `lineage-22.2` and from the mainline
DTS:

| Item | Value |
| --- | --- |
| Models | SM-T720, SM-T720N. Not the LTE SM-T725. |
| SoC | SDM670, Adreno 615 |
| Storage | eMMC at `soc/7c4000.sdhci` |
| Slots | one |
| Boot header | v1, page 4096, kernel offset `0x8000`, ramdisk `0x2000000`, tags `0x1e00000` |
| Kernel image | `Image.gz` with the DTB concatenated |
| Recovery size | 72744960 bytes, measured on this tablet. `boot` is 64 MiB |
| Panel | 2560×1600, command mode, dual DSI through the ANA38401 bridge |
| Early console | `simple-framebuffer` at the bootloader splash |
| Required cmdline | `fw_devlink.sync_state=timeout` |

## Order

1. On the build machine, `scripts/fetch-sources.sh` then `scripts/build-kernel.sh`.
   Done when `out/kernel/arch/arm64/boot/Image.gz-dtb` exists and `uname` is
   not involved yet: this step never touches the tablet.
2. Done on 2026-11-04. Names and byte sizes are in NOTES. `recovery` is
   72744960 bytes. The dtbo the bootloader already accepts is
   `lineage-recovery-dtbo.img`.
3. Pack a header-v1 recovery image that reuses that dtbo byte for byte, with
   an initramfs that brings up USB networking and a shell. The packer is not
   written yet. It must refuse an image larger than 72744960 bytes.
4. Boot that image once, from recovery, with Lineage still in `boot`.
   First success is a shell over USB, then the splash framebuffer on
   `/dev/dri/card0` from simpledrm. Display, GPU and touch come after that
   shell exists on this tablet, even though the pinned tree already contains
   those drivers.

## Known from the pinned tree, not yet from our boot

pulpoff's README records, on his SM-T720: display, Adreno 615 (Freedreno and
Turnip), the FTS1BA90A touchscreen through a userspace daemon, WCN3990 Wi-Fi
and Bluetooth, four CS35L41 speakers, the SM5705 gauge, both cameras, Venus,
the ADSP sensors, USB gadget and host, and s2idle woken by the power key.
Those drivers are in the tree we build. They are not checked on our tablet
until step 4 has happened.
