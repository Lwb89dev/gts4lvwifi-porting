# Porting roadmap: M7 and after

Written 2026-11-04 night, after M6 passed. What is known comes from
`HARDWARE-MATRIX.md`, the pinned trees and pulpoff's published scripts, which
were read for ordering and parameters only (their licence is unstated, see
`LICENSES.md`, so none of their code is copied). Nothing below has been run
unless it says so.

## 0. Where this stands (2026-11-07)

Sections 1 to 6 below are the plan as written on 2026-11-04; this table is the result. Details and
measurements: `HARDWARE-MATRIX.md` and `PROGRESS.md`.

| Step | Subsystem | State |
| --- | --- | --- |
| 0 | Lineage rewriting `recovery`, firmware access, services | done: `recovery` is written after the last Android boot (as for the v6 image); firmware is read from the tablet's partitions; `rmtfs` and `tqftpserv` start the modem at boot |
| 1 | M7.7 battery | done |
| 2 | M7.5 Wi-Fi | done, reconnects by itself after a reboot |
| 3 | M7.1 microSD | not started (needs a card and a `sdhc_2` node) |
| 4 | M7.4 touch | done through evdev and Hyprland (own driver); the DSI panel uses persistent touch transform 3. Resume after display-off remains open |
| 5 | M7.6 audio | speakers done and automatic before SDDM (ADSP, LPI pins, protection firmware, -12 dB hardware ceiling, PipeWire and WirePlumber rules); microphones and headphones blocked by the ADSP crash in the internal codec |
| 6 | M7.2 display | done (colour bars, brightness, about 63 Hz); text console on msm and compositor behaviour open |
| 7 | M7.3 GPU | done: Freedreno `FD615` (OpenGL 4.6 / ES 3.2), Turnip `Adreno 615` (Vulkan 1.3) and Hyprland mobile scan-out on DSI-1 |
| 8 | M7.8 sensors | working for light, magnetometer, compass and LSM6DSM motion through ADSP SSC; synchronized movement changed both raw acceleration and the proxy orientation. Proximity is not advertised. Device-specific Omarchy autorotation and its touch compensation passed live tests |
| 9 | M7.9 suspend | tested once: s2idle powered down but could not resume. Suspend/hibernate are blocked by systemd and removed from the Omamobile menu until kernel resume support exists |
| 10 | M7.10 cameras, video codec | not started; Venus loads |
| not in the plan | M8 Omarchy Mobile | running on the tablet: the 12-plugin mobile profile, hardware GPU, Hyprland, Quickshell, squeekboard and calibrated touch. The rebuilt image passed its offline verifiers and a full reinstall/reboot; SDDM autologin starts the Wayland session hands-off |
| not in the plan | poweroff | working with USB connected: the PON driver selects PMIC shutdown and masks USB_CHG/CBLPWR, while preserving the power-key and RTC triggers |
| not in the plan | Bluetooth | done: phone music through the speakers; reconnection after a reboot untested, and the phone must be paired again on v6 |

Open hazards still true: the ADSP must not be running at a reset; hardware numbers (`remoteprocN`, I2C
bus, interfaces) change between boots; the amplifiers are never played without the protection firmware
loaded and a volume read back (`gts4lv-audio`, `gts4lv-tone`).

## 1. Rules for the hardware work

- One subsystem per attempt, and the kernel stays bootable: new drivers are
  modules, loaded by hand over ssh, and listed in
  `/etc/modprobe.d/gts4lv-blacklist.conf` so udev does not load them at boot.
  A crash then costs one reboot into the same Arch.
- Nothing writes an Android partition. The modem's storage goes to RAM copies;
  `modem`, `apnhlos` and `vendor` are mounted read-only.
- Firmware is never copied into the image or the repository. It is read from the
  tablet's own partitions at each boot.
- Every test is a command over ssh with a number or a state as its result.
  There is no one at the screen, so "the panel lit up" is not a test until a
  person is there.

## 2. Hazards found in the references

Taken from pulpoff's scripts and README; each is a reason for an ordering rule,
not yet confirmed on this tablet.

| Hazard | Rule |
| --- | --- |
| The LPASS LPI pins are dead until the ADSP runs, and touching them hangs the bus | `pinctrl_sdm670_lpass_lpi` stays blacklisted, loaded by the audio unit after `remoteproc` `adsp` is `running` |
| With the ADSP running at reboot, the bootloader loops until a Power + Volume-down reset | the audio unit stops the ADSP before any restart, including `boot-android` |
| `hci_uart` and `venus_core` ask for firmware in probe and fail for good if the firmware path is not set yet | both blacklisted, loaded after `firmware_class.path` points at the firmware directory |
| `msm` is a module and the panel must survive until it loads | pulpoff adds `regulator_ignore_unused` for that. We keep `clk_ignore_unused pd_ignore_unused` and change nothing else until display is the subject of an attempt |
| A previous boot that died starting the modem would loop | keep the "start marker" idea of `/boot-attempt`: a flag written before the risky step and cleared after it |
| ath10k prefers linux-firmware's generic `board-2.bin` to Samsung's `board.bin`, and with it the WLAN firmware resets the whole SoC (measured 2026-11-05) | the image never carries `board-2.bin` (pacman `NoExtract`); `gts4lv-firmware` warns if it comes back; `gts4lv-modem` keeps a start marker |

### A safety net to measure, not to rely on

pulpoff's README says the bootloader leaves the APSS watchdog running and that
the kernel's own worker pings it once `qcom-wdt` is loaded
(`CONFIG_WATCHDOG_HANDLE_BOOT_ENABLED=y` here, `qcom_wdt` is a module). If so,
a hard kernel hang stops the pings and the tablet resets itself instead of
waiting for a person at the keys. A hang in userspace would not trip it, because
the kernel keeps the pings going. Not measured on this tablet. Until it is,
every risky module load is announced in `PROGRESS.md` before it is tried and
done only when someone can press the keys.

Upstream's rules are worth keeping: a dead-man switch (`systemd-run
--on-active=90 <undo>`) before anything that can cut the USB link, a log stream
to the PC, and a hang marker for anything at boot.

## 3. What blocks the start

1. **Lineage rewrites `recovery`.** After a Lineage boot, `adb reboot recovery`
   started Lineage's recovery instead of Arch (observed 2026-11-04 22:45; the
   cause is a hypothesis: AOSP `install-recovery.sh` restoring the partition).
   Until this is understood and switched off, every trip through Android costs
   a rewrite of `recovery`. See `PROGRESS.md`, "The Lineage → Arch cycle is
   not closed".
2. **Userspace the distribution does not have.** Arch Linux ARM carries
   `libssc`, `iio-sensor-proxy`, `iw`, `wpa_supplicant`, `alsa-ucm-conf`,
   `pipewire`, `bluez`, `upower`, `hyprland`, `libcamera`. It does not carry
   `qrtr`, `rmtfs`, `tqftpserv` or `hexagonrpcd`, which the modem
   and sensor paths need. They become packages under `packages/`, built in the
   aarch64 container.
3. **Kernel options.** `INPUT_UINPUT` (touch), `DRM_PANEL_SAMSUNG_ANA38401`,
   `SND_SOC_CS35L41_I2C`, `BATTERY_SM5705`, `VIDEO_S5K3M5` and `VIDEO_S5K4HA`
   are absent from the build. All are modules, so one kernel build covers them.

## 4. Order

| Step | Subsystem | Why here | Test over ssh |
| --- | --- | --- | --- |
| 0 | Lineage recovery rewrite, firmware access, services | everything below needs them | `dd` of `recovery` equals what was written after a Lineage boot; the three partitions mount read-only |
| 1 | M7.7 battery | a battery that cannot be read is a risk overnight and for every later test | `power_supply` shows capacity, status, temperature; level falls under load and rises on charge |
| 2 | M7.5 Wi-Fi | no display, no sound, the most useful result: a network that is not the cable | `iw dev wlan0 scan` lists networks (**passed 2026-11-05**, 4 networks, 2.4 and 5 GHz); association needs the owner's credentials, which are never stored in the repository (**done 2026-11-05 21:20**: associated on 5 GHz, DHCP, internet, reconnect and reconnect after reboot) |
| 3 | M7.1 microSD | a persistent root that does not live in Android's data | a card reads and writes. Needs a card and a device-tree node for `sdhc_2` |
| 4 | M7.4 touch | needs `uinput`, no kernel driver | `evtest` shows slots and positions when someone touches the glass |
| 5 | M7.6 audio | needs the ADSP, the LPI pins in order, the amplifiers | `aplay -l` lists cards; a quiet tone at a low level with the owner present |
| 6 | M7.2 display | highest risk of a dark or hung system | `modetest` lists a 2560x1600 connector; the owner sees a picture |
| 7 | M7.3 GPU | after the display for a compositor, but a render node can be tested earlier | **passed 2026-11-05**: `/dev/dri/renderD128`, Freedreno `FD615`, Turnip `Adreno 615`, not `llvmpipe`; `scripts/gpu-smoke.sh` |
| 8 | M7.8 sensors | needs the ADSP and `hexagonrpcd` | `iio-sensor-proxy` reports accelerometer and light |
| 9 | M7.9 suspend | last; start with suspend off | measured step by step, each one tried over ssh with a timer wake |
| 10 | M7.10 cameras, video codec | later | `cam -l`, a decode of a test clip |

## 5. Packages to build

Small open-source projects, to be pinned by tag and sha256, built in the
aarch64 container by `makepkg` as a normal user, and kept in a local
repository (`out/repo`), never in git:

| Package | Needed by |
| --- | --- |
| `qrtr` (the name service) | every Qualcomm remote service |
| `rmtfs` | the modem's storage, on RAM copies |
| `tqftpserv` | firmware requests from the modem |
| ~~`pd-mapper`~~ | not built: this kernel has `qcom_pd_mapper` (checked: the module is loaded), and a second mapper would answer the same service |
| `hexagonrpcd` | the sensor core on the ADSP, with `libssc` from Arch |

The device package, `omamobile-device-gts4lvwifi`, follows upstream's layout
(`PKGBUILD`, `install`, `bin/`) and carries the units that start the DSPs in
the order of section 2, the blacklist, and `boot-android`.

## 6. Kernel changes this plan wants

One build, all modules, none loaded at boot:

```
CONFIG_INPUT_UINPUT=m
CONFIG_DRM_PANEL_SAMSUNG_ANA38401=m
CONFIG_SND_SOC_CS35L41_I2C=m
CONFIG_BATTERY_SM5705=m
CONFIG_VIDEO_S5K3M5=m
CONFIG_VIDEO_S5K4HA=m
```

A device-tree node for the microSD (`sdhc_2`, card-detect `tlmm 3` active low
in Samsung's 4.9 tree) is a separate change, after the card is confirmed.
