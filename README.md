# Omarchy on the Galaxy Tab S5e (SM-T720)

Mainline Linux and, later, Omarchy for the Samsung Galaxy Tab S5e Wi-Fi
(`gts4lvwifi`, SM-T720 / SM-T720N, Snapdragon 670). The LTE models
(SM-T725) are a different board and are out of scope.

This tree is the port notes, the device descriptor and the kernel build.
It does not contain the kernel, and it does not flash the tablet.

## Layout

| Path | What it is |
| --- | --- |
| `device/gts4lvwifi/device.conf` | Board facts the image has to match |
| `device/gts4lvwifi/kernel.config` | Tablet config fragment (`CONFIG_LOCALVERSION`) |
| `device/gts4lvwifi/BRINGUP-M1.md` | First-light plan. No flashing in this stage |
| `device/gts4lvwifi/NOTES.md` | What has actually been checked |
| `PROCESS.md` | Handoff: decisions, measurements, where to resume |
| `sources.lock` | Commits `scripts/fetch-sources.sh` checks out under `src/` |
| `scripts/build-kernel.sh` | Cross-build of `Image.gz` plus the board DTB |
| `scripts/build-initramfs.sh` | First-light initramfs and `out/recovery.img` |
| `scripts/pack-recovery.py` | Header v1 packer. It does not flash |
| `scripts/verify-recovery.py` | Inverse check of a packed image |
| `docs/RECOVERY-RUNBOOK.md` | Manual recovery boot and rollback. Needs a fresh approval |
| `.github/workflows/kernel.yml` | Manual Actions build of `Image.gz` and the DTB, without modules |

`src/` and `out/` are local. They are gitignored.

## Build on the other machine

The kernel is Linux 7.2.13 from [pulpoff/linux-gts4lv](https://github.com/pulpoff/linux-gts4lv)
at the commit in `sources.lock`, configured with `defconfig` plus
`arch/arm64/configs/sdm670.config` plus `device/gts4lvwifi/kernel.config`.

```sh
scripts/fetch-sources.sh
# Pop!_OS / Debian:
sudo apt-get install -y gcc-aarch64-linux-gnu bc bison flex libssl-dev
# Arch:
sudo pacman -S --needed aarch64-linux-gnu-gcc aarch64-linux-gnu-binutils bc bison flex openssl
scripts/build-kernel.sh
scripts/build-initramfs.sh
```

The result is `out/kernel/arch/arm64/boot/Image.gz-dtb`. On a machine with
less than 12 GB of RAM the script uses `-j2`. Modules land in
`out/kernel/modules`. `scripts/build-kernel.sh --no-modules` skips them.

GitHub Actions (workflow **kernel**, started by hand) builds the same
image without modules. A full modules build does not fit the default
runner disk. Signing keys never go into Actions.

## Boot, when an image exists

The tablet has one slot and eMMC. Linux goes in the `recovery` partition.
LineageOS stays in `boot`. The bootloader wants boot header v1 and
Lineage's own `recovery_dtbo`; it rejects an overlay that does not apply.
The packer for that image is not written yet. See `BRINGUP-M1.md`.

Do not point Omarchy's `tools/install-phone` at this tablet. That tool
writes a fastboot slot B.
