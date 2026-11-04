# M8 plan: Omarchy Mobile on the tablet

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
| Hardware GPU, not `llvmpipe` | M7.3: render node, Freedreno or Turnip renderer string |
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
