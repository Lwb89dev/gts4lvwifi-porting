# gts4lvwifi port progress

Updated 2026-11-08, branch `feat/gts4lvwifi-mainline-bringup`.
This is the single narrative of the work performed on the SM-T720. Line-by-line measurements are in
`device/gts4lvwifi/NOTES.md`; the rollback runbook is in `docs/RECOVERY-RUNBOOK.md`.

### Owner rules

- **The tablet is disposable, within limits.** `recovery`, `userdata` and files below `/data` (the
  rootfs) may be written and the tablet may be rebooted without asking every time. **Never** touch the
  bootloader, calibration, `efs`, `persist` or modem firmware: this PC cannot recover them. Verify the
  device identity before every write (`adb -s <tablet-serial>` when another phone may be connected),
  and keep rollback copies in `out/`.
- **One subsystem at a time**, one variable per attempt, and document what was written.
- **Do not operate independently outside the project** inside `/home`, `/etc`, `/root` or `/usr`
  (for example the owner's home directory): explicit permission is required each time. Destructive
  `rm -rf`-style commands against those paths always require a fresh yes. This also applies to diagnostics.
- **The repository is not covered by the hardware permission:** no push, history rewrite, photos or
  serials may be published without a request. Console photos (`photo_*.jpg` at the root) stay local and
  ignored by Git; transcribe their text into `docs/CONSOLE-LOG.txt` with date and time. Wi-Fi credentials
  and keys never belong in the repository.
- **Never in the repository:** Wi-Fi passwords, the home-network name, Bluetooth addresses (tablet or
  phone) and gadget MACs. Before every commit run a scan for `psk`, `passw` and MAC-like strings.
- **Code:** no more than three indentation levels (early returns and smaller functions). Do not copy
  code from pulpoff (licence is undeclared; see `docs/LICENSES.md`); consult it only for ordering and parameters.
- Do not read the host PC's system journal.
- The owner speaks Italian and is not a measuring instrument: do not ask for frequencies or technical
  terms. For sound ask only whether it is audible and from where; for the display ask what is visible.

### Working on the tablet

- Over USB the tablet is `172.16.42.1`; the PC address is assigned by the tablet's DHCP server:
  `ssh -F /dev/null -i out/keys/gts4lv_ed25519 -o IdentitiesOnly=yes root@172.16.42.1`.
  The key is under ignored `out/`. If Arch does not answer, the initramfs shell is on telnet port 23.
  To return to Android, run `boot-android` on the tablet.
- The clock starts in 1977 because the PMIC RTC is not writable. With Wi-Fi,
  `systemd-timesyncd` sets it from NTP in roughly ten seconds. Without Wi-Fi, set it from the PC before
  running `pacman`; traffic can go through `scripts/usb-http-proxy.py`.
- Wi-Fi credentials are only on the live tablet in `/etc/wpa_supplicant/wpa_supplicant-wlan0.conf`
  (mode 600, hashed). A new image needs the file recreated with `wpa_passphrase`; it is never committed.
  The unit is started by udev when `wlan0` appears, not enabled manually.
- `scripts/run-with-log.sh <dir> '<command>' [seconds]` runs a tablet command while streaming `dmesg -w`
  to the PC. Use it for attempts that could reset the tablet.
- Kernel workflow: `scripts/build-kernel.sh` applies the patches in `device/gts4lvwifi/kernel/`, then
  `scripts/build-initramfs.sh` packages recovery; use `scripts/verify-recovery.py` and
  `scripts/flash-recovery-shell.sh --reboot` from a live tablet. Before rebooting into a new release,
  stage modules with `scripts/sync-modules.sh --stage`.
- Rootfs workflow: `scripts/build-rootfs.sh` (Docker plus qemu-user) and `scripts/verify-rootfs.py`;
  `scripts/rootfs-to-tablet.sh` copies it into `/data` from Lineage. The guarded
  `scripts/rootfs-to-tablet-shell.sh` path performs the same replacement from the deliberately stopped
  initramfs, avoiding an Android boot; it requires an explicit run because the old image may be removed
  before the 12 GiB transfer.
- Tablet helpers under `device/gts4lvwifi/rootfs/overlay/usr/local/sbin/` include
  `gts4lv-firmware`, `gts4lv-modem`, `gts4lv-dsp`, `gts4lv-tone`, `gts4lv-audio`,
  `gts4lv-display` and `boot-android`.

### Subsystem status at the handoff

| Subsystem | State | Evidence |
|---|---|---|
| Arch boot, USB, SSH and networking | Working | Many boots and recovery tests |
| Wi-Fi (WCN3990) | **Working**: 5 GHz association, DHCP, HTTPS, about 60 Mbit/s, reconnect and automatic reconnect after reboot | Measured; held for five hours |
| Bluetooth | `hci0`, phone paired and trusted; phone music plays through tablet speakers via PipeWire A2DP | Owner; re-pairing is required on the new image; reconnect after reboot and source mode remain untested |
| Modem DSP | Stable and started by a unit | Measured |
| Battery/charging (SM5705) | Working | Measured |
| Touch (FTS1BA90A) | Custom interrupt-driven driver; 19,153 evdev events, 173 contacts, up to four fingers; persistent DSI-1 `transform=3` | Owner, `touch-summary.py`, Hyprland capture |
| Display (`msm` plus panel) | **Working**: complete SMPTE bars, no visible seam, brightness and refresh tested; text console and compositor off/on remain open | Owner |
| GPU | **Working**: Freedreno FD615, OpenGL 4.6/ES 3.2, Turnip Vulkan 1.3, no software fallback | `scripts/gpu-smoke.sh` |
| Speaker audio | **Working** with protection DSP and PipeWire; all four speakers produce sound; the automatic path starts before SDDM with a -12 dB hardware ceiling and 0 analog gain | Owner, PipeWire and I2C registers |
| Internal codec (microphones/headphones) | **Blocked**: every use crashes the ADSP with an AHB bus hang near `0x62…` | Six crashes measured |
| ADSP | Starts and stops cleanly when handled by name | Measured |
| SSC sensors | Working after synchronized testing: light, magnetometer, compass, accelerometer and autorotation; no proximity sensor | `ssccli`, D-Bus and live rotation tests |
| Suspend/resume | Unsupported: s2idle powered the tablet down but did not resume; all systemd sleep modes and the Omamobile menu action are disabled | Live test and `CanSuspend = no` |
| microSD | Partly working: the Samsung `sdhc_2` host now probes as `mmc1`; card insertion and read/write await a physical card | Live boot, `sdhci_msm 8804000.mmc` and `/sys/class/mmc_host/mmc1` |
| Cameras and video codec | Detected but not working: CAMSS and both sensors enumerate, but an unconfigured one-frame capture returns `-EPIPE`; Venus loads firmware and modules yet exposes no codec node | Live V4L2/media graph and one-frame `/dev/null` capture |
| Poweroff/reboot | Working: reboot returns normally; secure PS_HOLD performs a real shutdown, and a cable-triggered cold boot is intercepted in display-off/USB-off charging mode instead of restarting Omarchy | PMIC reason registers and live poweroff tests |
| M8 Omarchy | The exact audio-inclusive image passed a clean reinstall, hands-off boot and reboot with systemd running, zero failed units and the mobile graphical/audio stack active | Offline verifiers and live tablet |
| M9 packages/CI | Partial: build and verification scripts exist; final release workflow remains | Repository |

### Lessons that matter

- **Never play audio without reading the volume.** Amplifier scale: 817 = 0 dB, 497 = -40 dB,
  337 = -60 dB, 0.125 dB per step. `gts4lv-tone` limits playback to -12 dB (or -24 dB without DSP).
- **Do not leave the ADSP running across a reset.** The Samsung bootloader can loop until Power + Volume
  Down. `gts4lv-adsp-stop.service` stops it during shutdown; after a crash wait for `running` before stopping.
- **Wi-Fi needs Samsung board data.** `board-2.bin` from linux-firmware resets the SoC; Samsung's
  `bdwlan.bin` works and is protected with pacman's `NoExtract`.
- **Touch polling is unsafe.** Timed queue reads with the controller scanning reset the tablet in three
  of four trials; the interrupt path is stable.
- `msm` does not unload cleanly with `rmmod`; reboot returns to simpledrm.
- Remoteproc numbers and I2C bus numbers change between boots. Scripts must resolve by name or address.
- A wrongly enabled `wpa_supplicant@wlan0` delayed SSH by 90 seconds; udev now starts it after `wlan0` appears.
- WirePlumber must start the card in Pro Audio and present a stereo FL/FR sink; its logind seat check is
  disabled for the mobile session.

### Current practical state

The 12 GiB M8 rootfs installed in `/data` contains the patch-compatible,
cryptographically pinned Omarchy 4.0.6-1, Omarchy Mobile shell 0.2.100, mobile Hyprland 0.57 and
Mesa/Turnip ALARM 26.2.6. A live session uses DSI-1 at 2560×1600, mobile scale 3, with MSM/FD615,
Quickshell and squeekboard.

The display service runs before SDDM. SDDM is enabled and automatically starts the `alarm` Wayland
session; the clean hands-off reboot reached systemd `running` with zero failed units. The Omarchy lock
timeout is 600 seconds and Stay Awake remains available as a quick setting.

The ALARM account predates the Omamobile packages, so upstream firstboot had never created its mobile
profile marker. The image now removes that marker precondition from the idempotent user setup unit and
runs a device finalizer after it. The live account has all 13 Omamobile plugins, phone window rules,
squeekboard, the unsupported-suspend toggle and the ten-minute lock timeout.

Suspend is not exposed: the only s2idle attempt powered the tablet down without a working resume, so
systemd rejects suspend, hibernate and their hybrid variants. Poweroff is separate and now works. The
Qualcomm PON driver programs both PMICs for `SHUTDOWN`, Samsung firmware deasserts PS_HOLD through SCM,
and fresh reason registers prove the real shutdown. A full PMIC cycle restores CBLPWR and an attached
cable starts a new cold boot despite the runtime trigger mask. A rootfs marker lets initramfs recognize
that case and remain in display-off/USB-off charging mode instead of starting Omarchy; removing VBUS
completes shutdown and Power continues the normal boot.

The rebuilt image has no published or temporary password: both `root` and `alarm` are locked. SSH is
key-only. The owner still has to set a private `alarm` password locally to unlock the graphical lock
screen; it must never be sent through chat or committed.

### Next blocks, in order

1. Commit and publish the guarded initramfs-shell installer and final evidence.
2. Rebuild once from that exact published commit before declaring a release artifact.
3. Test Bluetooth reconnection after reboot.
4. Investigate microphone/headphone support only if the ADSP codec path can be made safe.
5. Optional hardware work: microSD card read/write, suspend/resume, cameras, video decode, display console and touch
   resume after display-off.

The following historical sections record the evidence that led here.

## Objective and constraints

Port Omarchy (Arch Linux ARM, Hyprland and a mainline kernel) to the Samsung Galaxy Tab S5e Wi-Fi,
SM-T720/SM-T720N, codename `gts4lvwifi`, Snapdragon 670, Adreno 615, 4 GB RAM, single-slot eMMC and
2560×1600 AMOLED. LTE SM-T725 is a different board and out of scope.

The first success was a USB shell; display, GPU and touch followed. Linux uses pulpoff's
`linux-gts4lv` pinned at `36f309c07087`; Derek Ross's Tensor/Pixel kernel is not used. The Samsung 4.9
Lineage kernel is reference only. `tools/install-phone` is forbidden because this tablet has no A/B slots.

Only `recovery` and files below `/data` were written. `boot`, `dtbo`, `vbmeta`, `misc`, `userdata`, the
bootloader and calibration data were not modified. `/data` remains ext4 with file-based encryption.

## Build machine and measured tablet

The host is an HP OMEN 16 running Pop!_OS 24.04. The distro cross compiler is
`aarch64-linux-gnu-gcc` 13.3.0 with binutils 2.42, `bc`, `bison`, `flex` and `libssl-dev`. `shellcheck`,
system `dtc` and `dt-validate` were initially absent, so `dtbs_check` was not run. The kernel `dtc`
confirmed `compatible = "samsung,gts4lvwifi", "qcom,sdm670"`.

Measured Android state on 2026-11-04:

| Fact | Value |
|---|---|
| Model | SM-T720, `ro.product.device=gts4lvwifi`, `gts4lvwifixx` |
| System | LineageOS `22.2-20260909-NIGHTLY-gts4lvwifi`, Android 15, userdebug |
| Android kernel | `4.9.337-ga30605a54f3b` |
| SoC | Qualcomm SDM670 |
| RAM | `MemTotal` 3735364 kB |
| Bootloader | `T720XXS2DUH1`, unlocked, `verifiedbootstate=orange`, `flash.locked=0` |
| Slot | Empty `ro.boot.slot_suffix` |
| `/data` | ext4, `fileencryption=ice`, about 49 GB with about 29 GB free |
| eMMC | `soc/7c4000.sdhci`; the SD fstab node is `8804000.sdhci` |

| Partition | Node | Bytes |
|---|---|---:|
| boot | mmcblk0p48 | 67108864 |
| recovery | mmcblk0p49 | 72744960 |
| dtbo | mmcblk0p47 | 8388608 |
| vbmeta | mmcblk0p23 | — |
| misc | mmcblk0p34 | — |
| system | mmcblk0p50 | 4932501504 |
| vendor | mmcblk0p51 | 939524096 |
| product | mmcblk0p52 | 629145600 |
| cache | mmcblk0p53 | 419430400 |
| userdata | mmcblk0p57 | 54951656960 |

`recovery` is not 64 MiB: 67,108,864 is `boot`. PIT calls recovery `RECOVERY`, id 49, 142080 512-byte
blocks. The tablet shell's arithmetic is 32-bit and overflows for `system` and `userdata`.

The safe recovery backup procedure writes with `dd` on the Android device to `/data/local/tmp`, pulls it,
then compares the reread; `adb exec-out dd` returned a 4,171-byte page and is not safe for this partition.

### Android boot header and DTBO

Lineage `boot` and `recovery` use header v1, page 4096, kernel offset `0x8000`, ramdisk offset
`0x02000000`, tags offset `0x01e00000`, no second stage and name `SRPSA14B001`. Live recovery `os_version`
is `0x1e0001a8` (Android 15.0.0, August 2026 patch). `boot` has no recovery DTBO; Lineage recovery has a
1,305,887-byte overlay at offset 29,597,696, identical to the first 1,305,887 bytes of `dtbo`.

The checked-in `device/gts4lvwifi/lineage-recovery-dtbo.img` has SHA-256
`bca502bdea00d1e629fb3b04f8a0734d0e4bb47b5ff220e6539f7abc33efe3f4`. The packer rejects wrong page,
header, DTBO or size. The command line is
`console=tty0 fw_devlink.sync_state=timeout clk_ignore_unused pd_ignore_unused panic=10`.

### Offline artifacts

The pinned source trees are:

| Tree | Commit | Role |
|---|---|---|
| pulpoff/linux-gts4lv | `36f309c0708764886b6528b9ef0603bb73cc4731` | Kernel and board DTS |
| Lineage `android_device_samsung_gts4lvwifi` | `b54236c99ffb18aab2387833274cca7009c6c17c` | Wi-Fi product, `lineage-22.2` |
| Lineage common device | `d1b339be7abea07f62fef2bee3b7a2006694df67` | Partitions, header, fstab |
| Lineage `android_kernel_samsung_sdm670` | `a30605a54f3b92627d868f169c72ef9c6ef82123` | Reference DTS/defconfig |
| derekross/omarchy-mobile | `e7ad2759cb73f4b6449234c94dbaf2428ac33cb9` | Userspace reference |

The PHY recovery image used `Image.gz` 13,458,503 bytes, DTB 101,142 bytes and combined image 13,559,645
bytes. The later I2C-GPIO image used `Image.gz` 13,463,509 bytes, combined image 13,564,651 bytes,
initramfs 1,861,094 bytes and recovery SHA-256 `63028e49dcf8c2f414223f961ac0d6f8b1e488bef28aa11544da336fca61e18e`.
The later qcom-pon image used initramfs 2,129,613 bytes and recovery SHA-256
`4908aecf34eaec7a5f3374f8b3f6e91d4125b101ecd425c5d52a97dc4930d4a5`.

Offline `tests/test-pack-recovery.py`, `scripts/verify-initramfs.sh` and `scripts/verify-recovery.py`
passed for these images.

## Initial boot history

The first GCC 15 image produced a black screen and no USB. The distro-GCC simpledrm image also lacked
USB. Built-in ramoops produced a terminal and then a power-off; the Samsung bootloader erased the RAM
buffer on a hard reset. The cause of the USB deferral was then identified: `dwc3` was built in but
`CONFIG_PHY_QCOM_QUSB2=m` was not in the initramfs. Adding it brought up the gadget, but the MUIC did not
switch because `CONFIG_I2C_GPIO` was disabled.

Enabling `CONFIG_I2C_GPIO=y` created `i2c-charger`; `muic-usb` wrote `MANSW1=0x24` at address `0x25`.
The first successful shell showed product `gts4lvwifi first light`, USB NCM/RNDIS/ACM, `usb0 172.16.42.1`,
8 CPUs, 3.6 GB RAM, eMMC partitions, simpledrm and no Android partition mounted. Recovery was reread and
matched byte-for-byte. `boot-android` returned to Lineage with `sys.boot_completed=1` and
`ro.boot.boot_recovery=0`, closing M5.

The permanent initramfs then loaded `qcom-pon` and included `rebootmode` and `boot-android`. This removed
the previous warm-reset ambiguity and made the Android return path independent of temporary files.

## M6: Arch Linux ARM rootfs

The rootfs is an ext4 image in `/data/lost+found/gts4lv/rootfs.img`, mapped through the custom `dmlinear`
path after the initramfs verifies extents. It uses Docker plus qemu-user, removes the Arch kernel and
unused firmware, adds `linux-firmware-qcom`, locks root and alarm passwords in the base image, installs
key-only SSH, configures USB DHCP and includes the matching kernel modules.

The first attempt failed because `switch_root` was not executed as PID 1; adding `exec` fixed it. The
kernel initially lacked Landlock, so pacman failed; `CONFIG_SECURITY_LANDLOCK=y` fixed pacman. The M6
acceptance test passed: systemd running, zero failed units, SSH over USB, package installation with keyring
and integrity checks, and a verified return to Lineage.

Storage options were compared: microSD, a file in `userdata` through dm-linear, repartitioning and a RAM
rootfs. RAM was recommended for the first experiment, but the working path became the verified file in
`userdata`; the partition itself was not reformatted.

## M7 hardware history

### Modem and Wi-Fi

The first modem tests reset the tablet only when `ath10k_snoc` used generic `board-2.bin`. Running the
modem without ath10k stayed stable for 167 seconds. With Samsung's `bdwlan.bin` as `board.bin`, ath10k
reported board API 1, firmware ready and `wlan0`; the tablet remained stable for 172 seconds. The image
therefore excludes `board-2.bin` with pacman's `NoExtract` and starts the modem through a guarded unit.

The final live test associated on 5 GHz in about 12 seconds, obtained DHCP, had DNS and HTTPS, pinged at
about 27 ms and downloaded at about 60 Mbit/s. Disconnect/reconnect worked, NTP set the clock and a reboot
restored SSH at 7 seconds and Wi-Fi at about 20–25 seconds. The modem and Wi-Fi survived 5.3 hours of uptime.

### Bluetooth and video

`hci_uart` loads the Qualcomm firmware and brings up `hci0`. BlueZ saw nearby devices and the owner's phone
was paired and trusted. After PipeWire and WirePlumber were corrected, phone music played through the tablet
speakers. Reconnection after tablet reboot, source/headphone mode and HFP remain untested.

`venus_core` loads `venus_dec` and `venus_enc` after `venus.mdt` is exposed from the tablet's own firmware
partition. On the current image this logs `non legacy binding` but creates no encoder/decoder node, so video
decode is not usable yet. CAMSS registers the `s5k4ha` front and `s5k3m5` rear sensors with a complete media
graph; a one-frame capture reaches it but returns `-EPIPE` until the raw media formats are configured.

### Touch

The FTS1BA90A answers Samsung's ID command (`53 54 39 36`) at I2C address `0x49`. The custom GPL-2.0
driver resets the controller, waits for ready, validates the ID, decodes events and reports native axes
0..1599 by 0..2559 through multitouch slots. The device-tree interrupt is GPIO 123, active low.

Polling queue reads reset the tablet in three of four trials. The interrupt path survived five minutes and
the owner's test produced 628 decoded events: 22 presses, 584 moves, 22 releases, up to three fingers,
no stuck slots and no error events. Later evdev testing produced 19,153 events, 173 contacts and four-finger
operation. Hyprland received the complete stream after the persistent `transform=3` calibration.

### Display and GPU

The panel driver needs `handover=1`; after MSM loads, one DPMS off/on cycle reinitialises the panel. The
owner confirmed complete SMPTE bars rotated 90 degrees, no seam between DSI halves, brightness values
160/100/40/255/160 without artifacts and roughly 63 Hz with frames (29 Hz at rest). `modetest -v` itself
flickers by design. Text fbcon on `msmdrmfb`, compositor off/on and tearing remain open.

After `gts4lv-display start`, render node `renderD128` reports Freedreno FD615, OpenGL 4.6/ES 3.2 and
Turnip Adreno 615 Vulkan 1.3. Hyprland, Quickshell and squeekboard run through this hardware path; no
llvmpipe fallback was observed.

### Audio

The ADSP starts in 0.4 seconds and exposes APR services and FastRPC. Loading `pinctrl_sdm670_lpass_lpi`
creates the S5e card with speaker, headphone and microphone backends. The four CS35L41 amplifiers load
Samsung's protection firmware and tuning when linked under `cirrus/` and `DSP1 Preload Switch` is enabled.

The first tone incident exposed an unsafe volume command; all later helpers set and reread the volume before
playing. The LPI driver must be unloaded after the ADSP stops because its registers reset with the ADSP.
With the protection DSP in the path, three tones at -24, -18 and -12 dB worked after an initial silence;
the owner heard two. All four speakers were independently confirmed to produce sound, but exact FL/FR/RL/RR
physical mapping is not fully established.

Every attempt to use the internal digital codec, including microphone capture and playback through `hw:0,1`,
caused an ADSP fatal error: `ABT_dal.c:269:ABTimeout: AHB Bus hang`, address near `0x62…`. Replacing the
fixed codec clock with the real internal codec clock made the firmware reject the command and removed the
card, so that patch was reverted. Microphones and headphones remain blocked pending a safe codec solution.

### Battery and firmware

The SM5705 reports charging, 96%, 4.27–4.29 V, +336…+468 mA, 28.5 °C and 7.04 Ah design capacity. The
tablet charges under Linux. `gts4lv-firmware` mounts modem, APNHLOS and vendor read-only and exposes the
required `mba.mbn`, `modem.mdt`, `adsp.mdt`, `venus.mdt` and `a615_zap.mdt` paths without copying firmware.

## M8 Omarchy Mobile

The first 12 GiB image installed 930 packages: Omarchy 4.5.0-3, Omarchy Mobile shell 0.2.100, mobile
Hyprland 0.57, Mesa/Turnip ALARM, Quickshell and squeekboard. The resolver exposed an ABI mismatch:
Omarchy stable carries Aquamarine ABI 14 while current mobile Hyprland needs ABI 15, so Aquamarine,
hyprtoolkit, hyprland-guiutils and the Hyprland portal are pinned to Arch `extra` together with Mesa.
Keyring checksums and fingerprints are in `device/gts4lvwifi/rootfs/omarchy-repos.lock`.

The display service is ordered before SDDM. SDDM remains disabled at boot by design. A manual session
showed DSI-1 2560×1600 at scale 3.2 with MSM/FD615, Quickshell, squeekboard and working touch.

The SSC stack initially appeared frozen because motion was not synchronised with capture. During synchronised
tests 263 accelerometer samples changed (X 6.364..7.185, Y -1.006..-0.239, Z 6.636..7.496 m/s²), the direct
gyroscope changed on all axes and D-Bus emitted `normal`, `right-up`, `normal`. The Samsung matrix
`x=-y, y=-x, z=-z` is supplied through udev; the read-only registry and `persist` were restored after tests.

Generic Omarchy autorotation used the wrong direction for the native-landscape panel. The device-specific
service maps `normal=0`, `left-up=3`, `bottom-up=2`, `right-up=1`, and keeps touch at `(monitor + 3) mod 4`.
The owner confirmed that image and touch are correct in every live rotation. `omamobile-autorotate.service`
is enabled and active for `alarm`.

### Final rebuild, reinstall and automatic graphical boot

The first image could not be reproduced unchanged after Omarchy 4.5 was republished: Omarchy Mobile
0.1.32's 27 patches no longer applied to it. The build now pins signed Omarchy 4.0.6-1 and settings
4.0.6-1 by exact URL and SHA-256 in `omarchy-packages.lock`, checks the installed versions and protects
them with `IgnorePkg`. A clean build installed 983 packages and all 27 patches applied without conflict;
both rootfs verifiers passed.

The final 2026-11-07 rebuild produced a 12 GiB image
(`2d18c316de543f6dd39bd208852afd5e2e94918dd04e2bd4314a939e9ad093f3`), which was copied to the
SM-T720 and verified there. FIEMAP produced 5,314 extents covering the full
12,884,901,888 bytes. The resulting recovery image
(`0e7d18044942b3859422c24f6111d3232ad2b5344086550daa9be0b721881214`) was written only to
`recovery` and read back exactly before the final boot.

The immediately preceding image completed a hands-off boot and normal reboot. Systemd reported
`running`, no units failed, SDDM was enabled and active, and `alarm` had an active Wayland session on
seat0 with the graphical and autorotation user units active. The CPU stability fix, sensor stack and IIO
proxy were active; the touchscreen reappeared as event3. The audio changes were then deployed live and
survived a normal reboot: the speaker service finished before SDDM, loaded protection on all four
CS35L41 amplifiers and exposed `Tab S5e speakers` automatically through PipeWire at a -12 dB hardware
ceiling. The debug console was disabled and inactive. Effective sshd policy was key-only: root
`prohibit-password`, password authentication off and keyboard-interactive authentication off.

The audio-inclusive artifacts above were subsequently rebuilt, copied and read back exactly. A later
clean recovery write proved that the apparent first bootloop was not a rootfs regression. The exact
rootfs reached systemd `running` with zero failed units; SDDM, Hyprland, Quickshell, Omamobile, touch,
sensors, autorotation, PipeWire and all four protected speakers were active. Wi-Fi credentials remain
private and are not part of the image.

A clean build from the contents published as `8568ef5` then produced the installed rootfs image
SHA-256 `02817fe573919a3252c48b57308817882af00fcc834483dccfc1f7bce81d1336`, rootfs tar
`88ba87f1e5c0fbb9ae4fa03b8749a18558871fa9be57f7c7f64eb7d9ef5492d8` and package list
`8ab98a56f9fb593eeb0df476814d913cf1df4cbf9ce1ee404793f57a55a880f4`. It contains 983 packages,
passed `e2fsck` and both rootfs verifiers, was mapped with 6,062 exact fiemap extents, and booted to
systemd `running` with zero failed units.

### Mobile profile, suspend policy and real poweroff (2026-11-07)

The installed packages were already Omamobile, but `alarm` still used the desktop Omarchy shell profile:
the vendor setup service only ran when a firstboot marker already existed, while this image seeds the
pre-existing ALARM user directly. A systemd user drop-in now lets the idempotent setup run before every
graphical session. Its first successful run enabled the 13 mobile plugins, phone rules and squeekboard;
the device finalizer preserves the 600-second lock timeout and the suspend-off menu toggle.

The suspend report was reproduced as a failed s2idle resume, not a working shutdown path. Systemd sleep
policy now returns `CanSuspend = no` and rejects suspend, hibernate, hybrid sleep and suspend-then-hibernate.
After the clean reinstall and reboot, an explicit `systemctl suspend` returned failure without changing
the boot ID or system state.

The original poweroff reached `systemd-poweroff`, but the primary PMIC retained its hard-reset type.
The PON reboot notifier now selects shutdown for `SYS_POWER_OFF` and uses Qualcomm's 500-microsecond
programming delay. Samsung's SDM670 firmware requires the secure SCM PS_HOLD deassert call; the direct
MMIO fallback alone ended in a watchdog restart. With SCM, fresh registers recorded PS_HOLD shutdown
(`POFF_REASON=0x02`) followed by CBL power-on (`PON_REASON=0x40`). The runtime USB_CHG/CBLPWR mask is
lost across that full PMIC cycle, so initramfs now handles an intentional cable-only cold boot as an
off/charge state: display and USB stay off, removing the cable finishes poweroff, and Power starts Arch.
The final recovery (`2301de23fb46eaabd49a1b6641d3388e0074b13a3079ec7c5769a349190d2e76`)
was written only to `recovery` and read back exactly. With USB attached, poweroff removed the gadget and
kept it absent for the 35-second observation. Initramfs later logged the cable-only wake, registered
`pm8941_pwrkey` as `/dev/input/event1`, accepted one Power press and switched to Arch. The new boot reached
systemd `running` with zero failed units and no display-manager restart; the marker was gone, all 13 mobile
plugins, touch `event3`, accelerometer, light sensor, protected speaker sink and saved 30 percent software
volume were present. The owner then confirmed that image rotation and calibrated touch still followed
the tablet correctly.

## Rollback

If a boot does not return a shell and Lineage is needed:

1. Power off with Power + Volume Down; avoid a hard power cut if ramoops must be preserved.
2. Enter Download Mode with Volume Up + Volume Down while inserting USB, then confirm with Volume Up.
3. Verify `04e8:685d` and product `SDM710`.
4. Use Heimdall 2.0.2 to write only `out/lineage-recovery-before-mainline.img` to `RECOVERY`.
5. To enter the custom recovery from power-off, use Volume Up + Power; do not use `adb reboot recovery`.

The full command sequence, stop conditions and risks are in `docs/RECOVERY-RUNBOOK.md`.

## Git and publication

The bring-up branch is `feat/gts4lvwifi-mainline-bringup`. The current porting work was committed and
pushed normally as `8568ef5e8614ab32323e2482c4396620aab6061d`, authored by
`Lwb89dev <luigi.antona89@protonmail.com>`. Ignored photos, `src/`, `out/`, temporary files and keys are
not in GitHub. Do not force-push or publish backup refs.

## Current handoff

The core Omarchy Mobile port is usable on the tablet. The exact audio-inclusive image, 13-plugin mobile
profile, touch, sensors, autorotation, rejected suspend, reboot, cable-aware poweroff, key-only SSH,
debug-console cleanup and automatic protected speaker path all have live evidence. The owner has a local
test `alarm` password; it is not recorded here or in Git. The reproducible-release rebuild and publication
remain, while optional hardware work can continue with Bluetooth reconnection, display-off touch resume,
microSD, cameras/video and the blocked internal codec.
