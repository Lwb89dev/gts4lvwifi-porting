# Omarchy on the Galaxy Tab S5e (SM-T720)

Mainline Linux, Arch Linux ARM and, next, Omarchy Mobile for the Samsung
Galaxy Tab S5e Wi-Fi (`gts4lvwifi`, SM-T720 / SM-T720N, Snapdragon 670). The
LTE models (SM-T725) are a different board and are out of scope.

## Status, 2026-11-05 (evening)

| Milestone | State |
| --- | --- |
| M0 to M3: audit, kernel, initramfs, recovery packer | passed, built and checked offline |
| M4, M5: recovery plan, first boot | passed: a Linux shell on the tablet, return to LineageOS verified |
| M6: Arch Linux ARM | passed: systemd, ssh over USB, `pacman`; the root image is now v6 |
| M7: hardware | in progress. Working and tested: USB networking, battery, modem DSP, Wi-Fi (reconnects by itself after a reboot), Bluetooth (phone music through the speakers), touch through evdev and Hyprland, display, Freedreno/Turnip, the four speakers through PipeWire, sensors through ADSP SSC, and Omarchy autorotation with calibrated touch. Open: microphones and headphones (the ADSP crashes in the internal codec), microSD, suspend, cameras and video decode. Per subsystem: `docs/HARDWARE-MATRIX.md`, `docs/PORTING-ROADMAP.md` |
| M8: Omarchy Mobile | in progress on the tablet: Omarchy 4.5, Hyprland mobile, Quickshell, squeekboard, hardware GL/Vulkan and calibrated touch run on DSI-1. SDDM remains disabled at boot during bring-up |
| M9: CI | a static workflow runs on every push; the kernel build stays manual |

The state in detail, with every measurement and what went wrong, is in
`PROGRESS.md`; its first section is the handoff (rules, how to work on the tablet, what to do
next). "Working" above means measured on the
tablet, with the owner's eyes and ears where a person is the instrument; the boot-time
display and audio need `gts4lv-display start` and `gts4lv-audio start` after each boot.

## How it boots

The tablet has one slot and eMMC. LineageOS stays in `boot`. Linux is in the
`recovery` partition as an Android boot image (header v1, `Image.gz` with the
DTB appended) together with Lineage's own `recovery_dtbo`, which the bootloader
insists on. The initramfs brings up USB networking (`172.16.42.1`), then maps a
root image that lives in a file in Android's `userdata` with dm-linear, without
mounting `/data`, and switches to Arch. Going back to LineageOS is
`boot-android`, from either system.

Do not point Omarchy's `tools/install-phone` at this tablet. That tool writes a
fastboot slot B.

Known: after a LineageOS boot, `recovery` may be rewritten by Android
(`PROGRESS.md`, last sections); write it after the last Android boot.

## Layout

| Path | What it is |
| --- | --- |
| `device/gts4lvwifi/device.conf`, `kernel.config` | board facts and the kernel config fragment |
| `device/gts4lvwifi/initramfs/` | `init`, `boot-android`, and the C tools of the initramfs |
| `device/gts4lvwifi/tools/` | `fiemap`, run on the tablet to map the root file |
| `device/gts4lvwifi/rootfs/` | overlay, package list and the in-container scripts of the root image |
| `packages/` | `PKGBUILD`s for the Qualcomm userspace Arch Linux ARM lacks |
| `scripts/` | build, flash, deploy and test scripts, listed below |
| `docs/` | audit, recovery runbook, hardware matrix, roadmap, plans, licences, console log |
| `sources.lock`, `rootfs.lock` | pinned git trees and the pinned Arch Linux ARM tarball |
| `PROGRESS.md` | the long account, with the handoff section at the top |

`src/` and `out/` are local and gitignored, as are the console photos.

## Scripts

| Script | Does | Touches the tablet |
| --- | --- | --- |
| `fetch-sources.sh`, `fetch-alarm-rootfs.sh` | fetch the pinned trees and the verified Arch Linux ARM tarball | no |
| `build-kernel.sh`, `build-initramfs.sh` | kernel and modules; initramfs and `out/recovery.img` | no |
| `pack-recovery.py`, `verify-recovery.py`, `verify-initramfs.sh` | packer and offline checks | no |
| `build-packages.sh`, `build-rootfs.sh` | packages and the root image, in aarch64 containers | no |
| `hw-matrix.py` | what the build has for every enabled device | no |
| `rootfs-to-tablet.sh` | copy the root image into userdata and record its extents | writes one file in `/data` |
| `flash-recovery-adb.sh`, `flash-recovery-shell.sh` | write `recovery` from Android, or from the running tablet | writes `recovery` |
| `lineage-recovery-check.sh` | read-only: what is in `recovery` and what could rewrite it | no writes (adb root, read) |
| `sync-modules.sh`, `tablet-deploy.sh` | put modules, overlay and packages on the running Arch | writes `/usr`, `/etc` |
| `arch-smoke.sh`, `usb-http-proxy.py` | test systemd and `pacman` over the cable | installs one package |

## Build

The kernel is Linux 7.2.13 from [pulpoff/linux-gts4lv](https://github.com/pulpoff/linux-gts4lv)
at the commit in `sources.lock`, configured with `defconfig`, then
`arch/arm64/configs/sdm670.config`, then `device/gts4lvwifi/kernel.config`.

```sh
scripts/fetch-sources.sh
sudo apt-get install -y gcc-aarch64-linux-gnu bc bison flex libssl-dev
scripts/build-kernel.sh                  # Image.gz, DTB, modules
scripts/build-initramfs.sh               # also writes out/recovery.img
python3 tests/test-pack-recovery.py
scripts/verify-initramfs.sh && scripts/verify-recovery.py out/recovery.img
```

The root image and the packages need Docker with the aarch64 binfmt handler
(`docker.io`, `qemu-user-static`, `binfmt-support`):

```sh
scripts/fetch-alarm-rootfs.sh
scripts/build-packages.sh
scripts/build-rootfs.sh
```

On a machine with less than 12 GB of RAM the kernel script uses `-j2`. GitHub
Actions has two workflows: `static` (shellcheck, yamllint, the C tools, the
packer tests, a guard against tracked photos, images and keys) and `kernel`
(started by hand, `Image.gz` and the DTB without modules).

## Safety

Flashing and rewriting a partition are for the owner's own tablet, with the
rollback copy in `out/` and the recovery steps in `docs/RECOVERY-RUNBOOK.md`.
The bootloader chain, calibration, `efs`, `persist` and the modem's firmware
are never written. Samsung firmware is read from the tablet's partitions at
boot and never copied into the image or this repository. Licences and where
each piece comes from: `docs/LICENSES.md`.
