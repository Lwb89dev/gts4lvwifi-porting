# Audit — 2026-11-04

Branch `feat/gts4lvwifi-mainline-bringup`. `sources.lock` was not moved.
The tablet is back on LineageOS. This audit does not authorize another flash.

## Host

HP OMEN 16, Pop!_OS 24.04, x86_64, 32 threads, 32 GB RAM, hundreds of GB free.
It is not Arch Linux. The cross compiler used for the reproducible build is
`aarch64-linux-gnu-gcc` 13.3.0 from apt, together with `bc`, `bison`, `flex`
and `libssl-dev`. `shellcheck` and `dt-validate` are not installed, so `dtbs_check` was not
run. The kernel's own `dtc` decompiled the DTB and confirmed
`compatible = "samsung,gts4lvwifi", "qcom,sdm670"`. The decompiler also
printed existing unit-address warnings from the pinned DTS. They were not
introduced here.

## Pins

| Tree | Commit |
| --- | --- |
| pulpoff/linux-gts4lv | `36f309c07087` (Linux 7.2.13, not vanilla mainline) |
| Lineage device Wi-Fi | `b54236c99ffb` |
| Lineage device common | `d1b339be7abe` |
| Lineage kernel 4.9, sparse DTS and defconfig | `a30605a54f3b` |
| derekross/omarchy-mobile | `e7ad2759cb73` |

`tools/install-phone` from Omarchy Mobile targets Pixel slot B. It must not
be run on this single-slot tablet.

## What is real

| Item | State |
| --- | --- |
| `scripts/fetch-sources.sh` | Ran. Trees match `sources.lock`. |
| `scripts/build-kernel.sh` | Ran on this machine. Produces `Image.gz-dtb` and modules. |
| `device/gts4lvwifi/device.conf` | Holds the measured header fields, including `OS_VERSION=0x1e0001a8`. |
| `scripts/pack-recovery.py` | Packs a v1 image, checks the dtbo sha256, refuses an oversize file. No flash command. |
| `scripts/verify-recovery.py` | Inverse check of that image. |
| `scripts/build-initramfs.sh` | BusyBox 1.36.1 static, simpledrm plus its DRM dependencies, six gadget modules, `muic-usb`. |
| `tests/test-pack-recovery.py` | Offline. Passed on this machine. |
| GitHub `kernel.yml` | Manual dispatch, `Image.gz` and DTB only, no modules. Left as it is. |
| Arch rootfs, Hyprland, Omarchy | Not started. |
| Shell on the tablet | Not achieved. |

`lineage-recovery-dtbo.img` is the recovery dtbo copied from this tablet on
2026-11-04. sha256 `bca502bdea00d1e629fb3b04f8a0734d0e4bb47b5ff220e6539f7abc33efe3f4`.
It is the overlay the Samsung bootloader already accepts. It is device-specific
and should not be treated as a generic redistributable firmware blob. A later
checkout can extract the same bytes from the tablet's `recovery` or `dtbo`
partition instead of relying on the copy in git.

## Kernel config after `olddefconfig`

Present and relevant: `CONFIG_DEVTMPFS`, `CONFIG_MMC_SDHCI_MSM`,
`CONFIG_USB_DWC3`, `CONFIG_USB_GADGET`, `CONFIG_EXT4_FS`, `CONFIG_TMPFS`,
`CONFIG_CONFIGFS_FS`, `CONFIG_I2C_CHARDEV`, `CONFIG_INPUT`, `CONFIG_DRM`,
`CONFIG_DRM_MSM`. `CONFIG_LOCALVERSION` is `-gts4lvwifi`.

The USB functions used by the initramfs are modules, not built-in:
`CONFIG_USB_LIBCOMPOSITE`, `CONFIG_USB_F_ACM`, `CONFIG_USB_F_NCM`,
`CONFIG_USB_F_RNDIS`, `CONFIG_USB_CONFIGFS`. The initramfs insmods them.

`CONFIG_DRM` stays `=m`. `CONFIG_DRM_SIMPLEDRM=m` is set in
`device/gts4lvwifi/kernel.config`. The initramfs insmods, in `modules.dep`
order and before the gadget: `backlight`, `drm`, `drm_kms_helper`,
`drm_client_lib`, `drm_sysfb_helper`, `drm_shmem_helper`, `simpledrm`.

Still off: `CONFIG_FB_SIMPLE` and `CONFIG_DRM_PANEL_SAMSUNG_ANA38401`.

`CONFIG_PSTORE` was already `=y` and `CONFIG_PSTORE_RAM` was `=m`. The
fragment now sets `CONFIG_PSTORE_RAM=y` and `CONFIG_PSTORE_CONSOLE=y`.
The resulting recovery image is on the PC only. Reading it back from
Lineage after a warm reset is section 4 of `docs/RECOVERY-RUNBOOK.md`.

The image that was flashed had simpledrm off, so a black panel on that
boot was expected. The rebuilt image has not been written to the tablet.
A black panel is still not proof that USB came up.

## First boot attempt

An image packed from the GCC 15.3.0 nolibc build (not the distro compiler)
was written to `recovery` only, with the user's go-ahead, then the tablet
was rebooted into recovery.

| Fact | Value |
| --- | --- |
| Image sha256 | `ffe87fe60cffc74e3770ad9e57a7861a17bb89b7756bcf430fe138bb02cc8ee7` |
| Size | 15839232 bytes, read back and compared before the reboot |
| Screen | Black |
| USB | Disconnect at 14:01:43, then no `04e8` and no `18d1` device |
| `boot` | Not written |
| Rollback | Download mode `04e8:685d`, Heimdall 2.0.2, PIT partition `RECOVERY` (142080 blocks of 512 bytes = 72744960). The pre-flash partition copy was restored. |
| After reboot | Lineage 15, kernel `4.9.337-ga30605a54f3b`, `sys.boot_completed=1`, `misc` empty |

No `uname` was collected from the mainline kernel. M5 is failed, not skipped.

A second image, the distro-gcc build with simpledrm, was written the same
way on 2026-11-04 at 19:50. sha256
`71e09d2993306753e0ce4ebafb27b4fd83cc1e195438dd25dc7b4b55f3c2477a`,
16715776 bytes, readback matched. `adb reboot recovery` dropped
`04e8:6860` at 19:50:43. Nothing re-enumerated for 90 seconds, and
`172.16.42.1` did not answer. The panel was not observed from the host.

Download mode `04e8:685d` came back. Heimdall 2.0.2 wrote
`out/lineage-recovery-before-mainline.img` to `RECOVERY` and rebooted.
The following boot was Lineage: `uname -r` = `4.9.337-ga30605a54f3b`,
`sys.boot_completed=1`. The recovery bytes matched the backup, sha256
`81f4d19e4d9d3ba37c2044d57b77c72f01487dbaaa3a24173b14bacc161b14a7`.
`misc` was empty. adbd was returned to uid 2000. There is still no stock
firmware package on this machine.

The ramoops image was then written to `recovery` and booted with the
volume keys, not with `adb reboot recovery`. The owner saw terminal text
on a black panel, then the tablet powered itself off. The host never saw
the initramfs USB id. The console means the kernel reached the framebuffer.
The log in RAM is not available after that power-off.

## Milestone status

| Milestone | Status |
| --- | --- |
| M0 audit and host | Passed for this machine |
| M1 kernel artifacts | Passed offline. Hashes are in `out/MANIFEST.sha256` after `scripts/hash-artifacts.sh`. |
| M2 initramfs | Passed offline. Not proven on the tablet. |
| M3 recovery image | Passed offline. Two images were flashed. Neither yielded a shell. |
| M4 recovery plan | Written in `docs/RECOVERY-RUNBOOK.md`. Another flash needs a new approval. |
| M5 shell on device | Failed, rolled back |
| M6–M9 | Not started |
