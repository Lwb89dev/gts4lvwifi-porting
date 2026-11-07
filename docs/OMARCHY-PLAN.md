# M8 plan: Omarchy Mobile on the tablet

> Status 2026-11-07: the 12 GiB M8 image was rebuilt and verified. The pre-audio image and the live-deployed audio changes passed reboot tests, but the exact audio-inclusive artifact still needs a clean recovery reflash and boot: an intervening LineageOS boot may have rewritten recovery before the first attempt entered a bootloop. The 12-plugin Omamobile profile, hardware OpenGL/Vulkan, Hyprland, Quickshell, squeekboard, calibrated touch, sensors and autorotation have live evidence. Suspend is safely disabled; reboot and real poweroff work. SSH is key-only and the bring-up debug console is disabled.

Written 2026-11-04 night. Everything here was read from the repositories'
published databases and packages, or measured with `pacman` in print-only mode
in a throw-away container. Nothing was installed on the tablet and no Omarchy
package has been run on it.

## 1. What is published (checked 2026-11-04)

Fetched the `.db` files over HTTPS and read the package descriptions.

| Repository | URL | Packages | Notes |
| --- | --- | --- | --- |
| `[omarchy]` stable | `https://pkgs.omarchy.org/stable/aarch64` | 187 | `omarchy 4.0.6` (115 MiB download), `omarchy-settings`, `omarchy-keyring`, `quickshell`, `walker`, its own `hyprland 0.56.2` |
| `[omarchy]` edge | `https://pkgs.omarchy.org/edge/aarch64` | 279 | `omarchy 4.5.0`, `hyprland 0.57.1`. The upstream tooling follows stable |
| `[omamobile]` | `https://pkgs.omamobile.org/stable/aarch64` | 43 | `omamobile-shell 0.2.100`, `omamobile-apps`, `omamobile-omarchy 0.1.32`, `omamobile-firstboot`, `omacam`, libcamera, a patched `hyprland 0.57.0-3.1` and `mesa`. Device packages for Pixels only |
| Arch Linux ARM | `mirror.archlinuxarm.org/aarch64` | thousands | `hyprland 0.57.1`, `mesa 26.2.6` with Freedreno, `vulkan-freedreno` |

Licences read from the databases: Omarchy and the omamobile packages are MIT
(the shell also GPL-3.0-or-later), Hyprland BSD-3-Clause, quickshell
LGPL-3.0, walker GPL. That fits the assignment's rule to reuse binaries rather
than rebuild them.

## 2. A finding that changes the repository order

The `mesa` in `[omamobile]` is described as "Open-source OpenGL drivers
(Omarchy Mobile: Mali-G710, Mali-G78, Mali-G715)". Its `libgallium` has no
trace of Freedreno (`strings` finds none) while Arch Linux ARM's has it.
Upstream's `rootfs/pacman.conf` puts `[omamobile]` and `[omarchy]` before the
distribution, and resolving Omarchy's mobile set that way pulls
`omamobile mesa 1:26.2.4-1.4`: on the Adreno 615 that would remove GPU
acceleration, at the first install or at a later upgrade.

Rule for this port: `mesa`, `vulkan-freedreno` and `libglvnd` come from Arch
Linux ARM. Either `[omamobile]` goes after the distribution repositories, or
the packages are installed with an explicit `extra/` prefix and `mesa`,
`vulkan-mesa-implicit-layers` and `vulkan-panfrost` are listed in `IgnorePkg`
of the image, with the reason in a comment. Which one needs a test: whether
the patched `hyprland 0.57.0-3.1` carries changes the mobile shell depends on
(touch gestures are the likely ones) decides if `[omamobile]` must come first
for that one package.

## 3. What it costs

Resolved, not installed, with upstream's repository order on top of the
current base image:

| | |
| --- | --- |
| Packages | 443 (415 from `extra`, 13 `omamobile`, 8 `omarchy`, 7 `core`) |
| Download | 748 MiB |
| Installed | not obtained by this method; typically about three times the download, so 2 to 3 GiB. To be measured when it is installed |
| Largest | `maplemono-nf-cn` 145 MiB, `omarchy` 115, `omarchy-themes-intros` 92, `hyprland` 48, `llvm-libs` 36 |

The current root image is 6144 MiB with about 1.5 GiB used. This set does not
leave room for pacman's cache, logs or apps. The next image is 12 GiB (the
tablet's `/data` had 27 GiB free on 2026-11-04) and the pacman cache stays
off the root (`CacheDir` on the host side through the proxy, or cleaned after
each install). RAM is 3.47 GiB: the size of the desktop in memory is a
measurement for after the display works, not a number to quote now.

## 4. Trust

Upstream's `pacman.conf` has `SigLevel = Required DatabaseOptional`, so the
signing keys of `omarchy-keyring` and `omamobile-keyring` must be in pacman's
keyring first. Upstream copies Omarchy's from an Omarchy laptop, which this PC
is not. Plan: download both keyring packages over TLS from their own
repositories, record their sha256 and the key fingerprints in the repository
after reading them, and add them with `pacman-key --add` and `--lsign-key` in
the image build. Fingerprints are recorded here once read; none is trusted from
memory.

## 5. What blocks it

| Needs | From |
| --- | --- |
| A display and a way to see it | M7.2: panel driver, `msm` handover, a person at the screen |
| Hardware GPU, not `llvmpipe` | **passed**: Freedreno `FD615` and Turnip `Adreno 615`; `scripts/gpu-smoke.sh` |
| Touch as the input | M7.4: a daemon of our own (pulpoff's has no licence) and `uinput` |
| Network for `pacman` | works today through `scripts/usb-http-proxy.py`; Wi-Fi is M7.5 |
| Rotation, brightness, battery in the shell | sensors, backlight, `power_supply` (M7.7, M7.8) |

Until the first two exist there is nothing Hyprland can draw on. An install
without a session is still useful: it shows whether the dependency set
resolves, how big it is on disk, and whether anything in it needs a service
the tablet lacks.

## 6. The device package

`omamobile-device-gts4lvwifi`, in `packages/`, after the layout of
`omamobile-device-cheetah` (`PKGBUILD`, `install`, `bin/`). It carries what is
specific to this tablet and is already written as overlay files:

- the module blacklist, `gts4lv-firmware`, `gts4lv-dsp` and the ADSP stop unit;
- `boot-android`;
- the USB network unit that gives `usb0` its fixed address;
- later: the touch daemon, the audio configuration for the four amplifiers, the
  rotation and the backlight rules.

It must not carry Samsung firmware, serial numbers, MAC addresses or keys.

## 7. Tablet behaviour

The shell is written for a phone. The tablet is 10.5 inch, 2560x1600, used in
both orientations, with a keyboard and mouse as options. Whether to keep one
application per screen or allow tiling is a decision for after the first
picture on the glass, taken by looking at the real device, and the upstream
shell's own handling of resolution and rotation has to be read first
(`packages/omamobile-shell`). It should not turn into GNOME, Phosh or Plasma
Mobile.

## 8. Order

1. M7.2 and M7.3 to a first picture and a hardware renderer.
2. Install the set without a session, check size and dependencies, apply the
   repository order of section 2.
3. Start Hyprland with the stock Omarchy session to see the GPU path work.
4. Add `omamobile-shell` and the device package; then touch, rotation and the
   keyboard.
5. Measure memory and start-up before any optimisation.

## 9. First M8 image (2026-11-05 night)

`scripts/build-omarchy-rootfs.sh` now builds into `out/rootfs-omarchy/`, never over the known-good
`out/rootfs/` v6 image. The result is a 12 GiB ext4 image with 631 packages. Relevant versions in this
build are Omarchy 4.5.0, Omarchy Mobile shell 0.2.100, the mobile-patched Hyprland 0.57.0, and Arch
Linux ARM Mesa / Turnip 26.2.6. Its hashes are kept locally in `out/rootfs-omarchy/SHA256`; both
`verify-rootfs.py` and `verify-omarchy-rootfs.py` pass.

The signed keyring packages, their sha256 values and primary fingerprints are pinned in
`device/gts4lvwifi/rootfs/omarchy-repos.lock`. `[omamobile]` stays first so its patched Hyprland wins,
but pacman protects Mesa, `vulkan-freedreno`'s supporting packages and the current Hyprland ABI stack
from replacement. A second incompatibility was found during the real build: Omarchy stable still
offers Aquamarine ABI 14, while the mobile Hyprland and current `hyprtoolkit` require ABI 15. Therefore
Aquamarine, `hyprtoolkit`, `hyprland-guiutils` and the Hyprland portal are installed explicitly from
Arch `extra` and protected together with Mesa.

The image deliberately has no enabled display manager. The next test is to boot this image, verify the
existing hardware services, then start Hyprland by hand with kernel logging and observe the panel and
touch before enabling any graphical boot path.

## 10. First live M8 session and sensors (2026-11-06)

The image has been deployed and boots without failed units. After provisioning `alarm`, a manual SDDM
session ran the mobile Hyprland 0.57 stack on DSI-1 at 2560x1600 and scale 3.2. Quickshell and
squeekboard were active, and the compositor used the Freedreno/Turnip path already proved by the GPU
smoke test. SDDM is still disabled at boot deliberately.

The device overlay now also carries a read-only SSC stack. `gts4lv-sensors` mounts the device's `dsp`
and `persist` partitions read-only and exposes only the registry/configuration paths that
`hexagonrpcd` needs below `/run`. Root-PD and sensors-PD start in order; `iio-sensor-proxy` waits for
the asynchronous SSC catalogue. Ambient light, magnetometer and compass stream, and accelerometer plus
light are available over `net.hadess.SensorProxy` immediately after reboot. Early captures appeared
frozen because physical movement and sampling were not synchronized. Repeating them while the owner
moved the tablet changed the direct gyroscope and accelerometer streams, and the D-Bus orientation
progressed through `normal`, `right-up` and back. No proximity sensor is published by SSC on this unit.
Udev supplies Samsung's `x=-y, y=-x, z=-z` matrix instead of the all-zero factory placement record.

Hyprland now receives full FTS1BA90A touch streams. The controller is mounted a quarter-turn from the
native-landscape DSI panel, so `/usr/lib/gts4lv/hypr/tablet.lua` pins it to DSI-1 with transform 3.
`/usr/lib/gts4lv/autorotate.py` retains that quarter-turn offset as the monitor rotates and is exposed
under the exact `omamobile-autorotate.service` name expected by the shell's rotation-lock tile. A live
test found that the native-landscape panel uses the opposite quarter-turn direction from the generic
phone mapping; swapping transforms 1 and 3 made both the image and touch follow every physical turn.
The image also changes the phone-oriented one-minute lock timeout to ten minutes; Stay awake remains a
quick-settings toggle for bring-up.

## 11. Reproducible final image and hands-off boot (2026-11-06)

The upstream Omarchy 4.5 packages were republished after the first image and no longer accept the
Omarchy Mobile 0.1.32 patch series. The final build therefore follows Omarchy Mobile's supported
combination and pins `omarchy` plus `omarchy-settings` at 4.0.6-1. Their official package URLs,
versions and SHA-256 sums are in `omarchy-packages.lock`; the build also verifies their pacman
signatures and refuses any version drift. Pacman keeps both packages in `IgnorePkg` so a routine
upgrade cannot silently replace the patched files.

A clean 2026-11-07 build installed 983 packages and applied all 27 mobile patches with no conflict.
Both rootfs verifiers passed. The final artifacts used for the live reinstall were:

- rootfs image: `2d18c316de543f6dd39bd208852afd5e2e94918dd04e2bd4314a939e9ad093f3`;
- rootfs tar: `6d984cce5cd2b41dda465b5ea32caa751b731817b9475a6d873f0945436b7d62`;
- package list: `8f9c804d5d33ce6aec07a4e8d8e0659ba43973ae149f58075e6dd567c0d939df`;
- recovery image: `0e7d18044942b3859422c24f6111d3232ad2b5344086550daa9be0b721881214`.

The copy in Android userdata matched the rootfs hash and FIEMAP covered all 12,884,901,888 bytes
in 5,314 extents.
The recovery write was read back with the same hash. The prior image had already completed a hands-off
boot and normal reboot with systemd `running`, zero failed units, active SDDM and an `alarm` Wayland
session on seat0. The graphical and autorotation units, CPU stability, sensor and IIO proxy services were
active, and the FTS1BA90A touchscreen appeared as `event3`. The protected speaker path was deployed live,
then survived a normal reboot: it starts before SDDM, caps all four amplifier channels at -12 dB and lets
WirePlumber publish `Tab S5e speakers` without a manual service restart.

The exact artifact listed above has not yet completed that test. The hardware-key attempt after flashing
instead booted LineageOS, which can rewrite `recovery`; a subsequent `adb reboot recovery` entered a
bootloop. Recovery must be flashed again after the last Android boot and entered directly with the
documented hardware-key sequence before treating the loop as a rootfs regression.

The image locks both account passwords by design. Root SSH accepts the installed key only
(`PasswordAuthentication no`, `KbdInteractiveAuthentication no`, `PermitRootLogin prohibit-password`).
The owner must set a private `alarm` password after installation to unlock the graphical lock screen;
that secret is never put in the image, repository or build log. The recovery debug console remains
installed for deliberate recovery work but is disabled and inactive during a normal boot.

## 12. Omamobile account provisioning and power policy (2026-11-07)

The packages alone were insufficient for the pre-existing ALARM `alarm` account: its shell still had
the desktop Omarchy bar and no mobile plugins because the vendor user unit required a marker normally
created by firstboot. A device drop-in clears that condition. The upstream idempotent setup now runs
before the graphical session and creates the 12-plugin profile, phone window rules, squeekboard setup
and suspend-off toggle. A device finalizer keeps the tablet's 600-second lock timeout.

The only s2idle test powered down without resuming. `/etc/systemd/sleep.conf.d` therefore rejects all
sleep and hibernate variants instead of presenting a destructive Suspend action. After the clean reinstall
and reboot, `systemctl suspend` failed as configured while the boot ID and running state stayed unchanged.

Poweroff required two PMIC changes. The Qualcomm PON notifier now programs `SHUTDOWN` rather than the
restart type for `SYS_POWER_OFF`. Live reason registers then proved that shutdown completed but the
connected cable immediately caused a new CBL power-on. The device policy now masks both external
USB_CHG and CBLPWR triggers, leaving RTC, the secondary PMIC and the power key enabled. With the live
trigger register at `0xa4`, the tablet remained off for more than one minute with USB still attached. The
same one-minute test passed again after the final clean image, recovery and normal-reboot cycle.
