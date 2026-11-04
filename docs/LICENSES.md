# Licences and provenance

Written 2026-11-04. This is what is known about the licence of each thing the
project uses or ships, and the rule that follows. It is not legal advice.

## Rule

Nothing is copied from a file that has no stated licence. The facts such a file
shows (an order of start, a parameter, a register) are learned from it and the
code is written again.

## Third-party code in this repository

| Item | Where | Licence and provenance |
| --- | --- | --- |
| `lineage-recovery-dtbo.img` | `device/gts4lvwifi/` | The first 1305887 bytes of the `dtbo` partition of the owner's tablet, identical to the overlay inside Lineage's recovery. A compiled device tree overlay. It is probably built from the Samsung kernel device trees that LineageOS publishes under GPL-2.0 (`android_kernel_samsung_sdm670`), but that was not checked against this exact blob. sha256 `bca502bd…efe3f4`. If its redistribution is ever questioned, the alternative is a local extraction from the owner's own tablet, which the repository does not do yet |
| BusyBox 1.36.1 | built into the initramfs, source not committed | GPL-2.0. Downloaded by `scripts/build-initramfs.sh` with its sha256 checked |
| `src/` trees | not committed | `.gitignore` covers them. Pins in `sources.lock` |

## Code written for this project

`dmlinear.c`, `fiemap.c`, `rebootmode.c`, `muic-usb.c`, the init, the shell
scripts and the Python tools are written here. They have no SPDX header yet and
no repository licence file; the owner has to choose one (the upstream Omarchy
Mobile uses MIT, the Linux kernel GPL-2.0-only). Until then nothing here is
published for reuse by anyone else.

## References read but not copied

| Source | What it is | Licence state |
| --- | --- | --- |
| pulpoff `mobian/` (touch daemon, USB role daemon, audio and modem scripts, sensor units, `kit/` tools) | userspace for this tablet | **no licence header in any file and no licence file in the directory.** The kernel tree it sits in is GPL-2.0 (`COPYING`), but that does not license files that do not say so. Used for ordering and parameters only. To reuse code, ask the author to add a licence |
| pulpoff kernel patches and drivers (`sm5705_battery.c`, `panel-samsung-ana38401.c`, the device tree) | kernel sources | GPL-2.0, as the tree. These are the kernel we build |
| Samsung kernel 4.9 (LineageOS `android_kernel_samsung_sdm670`) | register and timing reference | GPL-2.0. The tree is checked out sparse (device trees and defconfig only), so the touch driver would have to be fetched; it is the legitimate starting point for a touch daemon of our own |
| omarchy-mobile | packaging layout, rootfs method | MIT (SPDX headers) except where a file says otherwise |

## Firmware

Never redistributed, never in the repository or the image.

| Firmware | Whose | How it is used |
| --- | --- | --- |
| `modem` and `apnhlos` images, `vendor/firmware` (modem DSP, Wi-Fi board data, Bluetooth, video, ADSP, GPU zap shader) | Samsung and Qualcomm, signed, device-specific | read at each boot from the tablet's own partitions, mounted read-only. The DT names `qcom/sdm670/gts4lv/*` are symlinks made at runtime into `/run` |
| `linux-firmware-qcom`, `-atheros`, `-cirrus` | distributed by Arch Linux ARM under its own terms | installed from the distribution, not from this repository |

## Keys and identifiers

The bring-up SSH key lives in `out/keys/` (gitignored, no passphrase, for a
USB cable to a test tablet). Serial numbers, MAC addresses and calibration are
not committed: the serial of the tablet is already in `NOTES.md` from before
this file, and `CONSOLE-LOG.txt` leaves gadget MAC addresses out.
