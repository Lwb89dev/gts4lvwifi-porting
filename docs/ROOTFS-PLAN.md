# M6 plan: Arch Linux ARM rootfs

> Status 2026-11-05 evening: written for M6, which passed. The image is now v6 (PipeWire, WirePlumber rules, display and audio helpers, touch module not blacklisted); how it is built, deployed and rolled back is in `PROGRESS.md` (last sections) and `RECOVERY-RUNBOOK.md`. The text below is the plan, not the current state.

Written 2026-11-04, after M5 passed. Nothing here has been run on the
tablet. "Checked" means read from a file or a command on this PC today;
"expected" means not checked.

Acceptance, from the assignment: Arch Linux ARM running on the tablet with
systemd, a shell, USB networking and a working package manager. No Omarchy,
no GPU and no touch are needed for M6 itself.

## 1. What upstream does, and where it does not fit

`src/omarchy-mobile` (pin `e7ad275`) builds the root image with
`tools/build-rootfs`. Checked in `tools/build-rootfs`, `tools/lib/alarm.sh`
and `rootfs/`:

| Upstream assumption | Our situation |
| --- | --- |
| Docker plus an aarch64 `binfmt_misc` handler (`qemu-aarch64`), so an Arch Linux ARM container runs on x86 | This PC has no `docker`, `podman`, `systemd-nspawn`, `qemu-aarch64*` or binfmt entry for aarch64. `sudo` asks for a password |
| The [omarchy] keyring is copied from the host's `/usr/share/pacman/keyrings` (an Omarchy laptop already trusts it) | Pop!_OS has no such directory. The key has to come from somewhere else and be pinned |
| The image is ext4, label `omamobile-root`, and "the initramfs grows it to the whole userdata partition on the first boot" after `tools/install-phone` erased `userdata` | `install-phone` is forbidden here and `userdata` stays untouched. The storage model has to be different (section 4) |
| Package lists for a Pixel: `linux-firmware-other` and `vulkan-panfrost` (Mali) | Adreno 615: `vulkan-freedreno` and `linux-firmware-qcom`, plus firmware that is Samsung's and cannot be redistributed (section 5) |
| The kernel comes from the upstream's own tree and a `modules-<release>.tar.zst` | Ours: `out/kernel/modules/lib/modules/7.2.13-gts4lvwifi-g36f309c07087`, from `scripts/build-kernel.sh` |
| A device package, `omamobile-device-<codename>`, with `PKGBUILD`, `install`, `bin/` and a `version` file | There is none for gts4lvwifi yet. `omamobile-device-cheetah` is the model: boot-slot success, storage guard, USB networking, `omamobile-usb-rescue` |

Upstream's package lists are in `rootfs/packages.base`,
`rootfs/packages.omamobile` and `rootfs/packages.omarchy-skip`. They are
M8 material. M6 needs only the base system.

## 2. What Arch Linux ARM already offers

Directory listings of `http://mirror.archlinuxarm.org/aarch64/` on
2026-11-04 (package names and versions as listed, nothing installed):

| Repo | Packages relevant to this tablet |
| --- | --- |
| core | `systemd 262.1`, `pacman 7.1.0`, `openssh 10.6p1`, `archlinuxarm-keyring`, `wpa_supplicant 2.12`, `linux-firmware`, `linux-firmware-qcom`, `linux-firmware-atheros` (all `20261019`) |
| extra | `mesa 26.2.6` and `vulkan-freedreno 26.2.6`, `hyprland 0.57.1`, `aquamarine 0.16.0`, `wlroots0.20`, `networkmanager 1.58.1`, `iwd 3.12`, `bluez 5.87`, `pipewire 1.6.10`, `wireplumber 0.5.18`, `libinput 1.32.0`, `iio-sensor-proxy 3.9`, `seatd`, `xorg-xwayland` |

That covers the compile policy of the assignment: nothing in this list
needs to be built from source. Omarchy Mobile ships its own patched `mesa`
and `hyprland` (`packages/mesa`, `packages/hyprland`); whether those patches
are needed on Adreno is an M8 question and is not answered.

The root tarball is
`http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz`,
829367415 bytes, `Last-Modified` 2026-08-05. "latest" moves, so the
verified sha256 is recorded (section 6).

## 3. Kernel readiness (checked in `out/kernel/.config`)

systemd's required options are all built in: `CGROUPS`, `CGROUP_BPF`,
`MEMCG`, `CGROUP_PIDS`, `BPF_SYSCALL`, `DEVTMPFS`, `TMPFS_POSIX_ACL`,
`TMPFS_XATTR`, `FHANDLE`, `SIGNALFD`, `TIMERFD`, `EPOLL`, `INOTIFY_USER`,
`AUTOFS_FS`, `SECCOMP_FILTER`, `NAMESPACES` with user, pid, net, uts and ipc,
`IPV6`, `EXT4_FS_POSIX_ACL`, `EXT4_FS_SECURITY`. `UEVENT_HELPER` is off, as
recommended. `ZRAM=m`, `ZSWAP=y`, `SQUASHFS=y`, `OVERLAY_FS=m`, `VFAT_FS=y`,
`BLK_DEV_LOOP=y`, `MMC_SDHCI_MSM=y`.

Gaps and notes:

- `CONFIG_BLK_DEV_DM=m`: the device-mapper is a module and the initramfs
  does not carry `dm-mod.ko`. The `linear` target is part of `dm-mod`
  (`drivers/md/Makefile`, `dm-mod-y += ... dm-linear.o`), so there is no
  separate `DM_LINEAR` option and its absence in `.config` is not a gap.
- `CONFIG_BINFMT_MISC` and `CONFIG_CRYPTO_USER_API_HASH` are not set.
  Neither blocks systemd. `iwd` needs AF_ALG (`CRYPTO_USER_API_*`), so
  choose `wpa_supplicant` with NetworkManager or add those options before
  Wi-Fi (M7.5). Waydroid is a later goal and its kernel needs were not
  examined.
- The board DTS describes only `&sdhc_1` (the eMMC). `sdhc_2` appears in
  the tree only as a masked name in `sdm670-samsung-gts4lvwifi-dtbo-mask.dtsi`.
  Samsung's 4.9 DTS (`sdm670-sec-gts4lv-common.dtsi`) has `&sdhc_2` with
  `cd-gpios = <&tlmm 3 0x1>`. So the microSD slot needs a new DT node (clocks,
  pinctrl, supplies from the 4.9 tree) and a kernel build: it is M7.1 work,
  not a configuration switch.

## 4. Where the root filesystem lives

| | A. microSD | B. file in `userdata` via dm-linear | C. repartition | D. RAM only, streamed over USB |
| --- | --- | --- | --- | --- |
| Needs | a card, a DT node for `sdhc_2`, a kernel build | writing one file into Lineage's `/data`; `dm-mod.ko` and pulpoff's `dmlinear` in the initramfs | rewriting the partition table | nothing new: `switch_root` into a tmpfs filled over the USB network |
| Touches | the card only | `/data` (one new file in `/data/lost+found/`, which pulpoff says is never encrypted) | everything | nothing persistent |
| Risk to Lineage | none | low if the file is not moved; the extent list is a snapshot, so a defrag or file move would corrupt the rootfs. Not examined whether Lineage ever does that | high | none |
| Persistent | yes | yes | yes | no, lost at every reboot |
| Known to work | not yet (no node) | per pulpoff's README on its own tablet, not measured by us | not considered | not yet |
| Needs the owner | a microSD card | approval to write into `/data` | explicit consent | nothing |

`/data` is ext4 with file-based encryption (`fileencryption=ice`). B never
mounts it: `kit/init` in pulpoff maps the file's physical extents (from a
FIEMAP list made on Android) with `dm-linear` on the raw `userdata` node.
That avoids encryption only because the file sits in a directory Android
does not encrypt; the claim about `lost+found` comes from pulpoff and has
not been checked on this tablet.

Recommendation: do D first. It proves everything M6 asks for except
persistence (systemd, shell, USB network, pacman) with no storage risk and
no new flash decision beyond one initramfs change. Then choose A or B for
persistence once the owner decides about a card or about writing to `/data`.

## 5. Firmware and licences

The kernel DTS asks for names under `qcom/sdm670/gts4lv/` (for example the
modem `mba.mbn` and `modem.mdt`). pulpoff's README says the Adreno zap
shader and the modem files come from Samsung's own `vendor` partition.
Those files are Samsung's or Qualcomm's and are not redistributable: M7 needs
an extraction step run on the owner's tablet, writing into a local
directory that is gitignored, as upstream does for the Pixel
(`tools/extract-vendor-firmware`). `linux-firmware-qcom` and
`linux-firmware-atheros` in Arch Linux ARM are distributed by Arch under
their own terms and are not Samsung blobs.

## 6. Steps

M6.0, no sudo and no tablet:

1. `scripts/fetch-alarm-rootfs.sh` downloads the root tarball under
   `src/alarm/`, checks the MD5 file and the detached signature against the
   Arch Linux ARM build key (fingerprint
   `68B3537F39A313B3E574D06777193F152BDBE6A6`, the same pin as upstream) and
   writes the verified sha256 to `src/alarm/SHA256`.
2. Inspect the tarball without extracting it: package set, default users,
   whether `openssh` is in it, uncompressed size against the 3.5 GiB of RAM.

M6.0 result, 2026-11-04 21:53, done. MD5 ok, signature ok with the pinned
key, sha256 `42a4eeaa038994ffd31fa173256ef2f0ef511358eeb41b9ea1f8626391b9b319`,
829367415 bytes, recorded in `rootfs.lock`. 49104 members, 165 packages in
`var/lib/pacman/local`. Read from the member list and a few small files:

| Item | Finding |
| --- | --- |
| Uncompressed size | 2015 MiB: `boot/` 190, `usr/lib/modules` 178, `usr/lib/firmware` 950, docs/man/locale 132, the rest 565 |
| Packages that matter | `systemd 261.2`, `pacman 7.1.0.r9`, `openssh 10.4p1`, `dhcpcd 10.3.2`, `iproute2 7.1.0`, `linux-aarch64 7.1.6`, `linux-firmware 20260622`, `archlinuxarm-keyring 20240419`, `e2fsprogs`, `kmod`, `nano` |
| Arch's own kernel | in the tarball: `boot/Image` (44 MB), `Image.gz`, `initramfs-linux.img` and `usr/lib/modules`. Not used: our kernel is `7.2.13-gts4lvwifi-g36f309c07087` |
| Accounts | `root` and `alarm` (uid 1000). **Both passwords are the published defaults**: `root`/`root` and `alarm`/`alarm` match the shipped hashes (checked locally by hashing, nothing printed) |
| `sshd` | enabled in `multi-user.target.wants`; `sshd_config` is the stock file with only `AuthorizedKeysFile` and `sftp`, so password login for `alarm` is on by default |
| Network | `systemd-networkd` enabled with `en.network` and `eth.network` only; nothing matches `usb0`. `systemd-resolved` and `timesyncd` enabled |
| Machine id, host keys | `/etc/machine-id` empty; no SSH host keys in the archive |
| Adreno firmware | no `usr/lib/firmware/qcom/` and no `a6xx`/`gmu` files in the tarball: they come from `linux-firmware-qcom` in `core`. `ath10k/WCN3990` is there |
| tar | GNU tar warns "unknown extended header keyword LIBARCHIVE.xattr.security.capability" and would drop it, so a repack with GNU tar loses file capabilities (for example on `ping`). `bsdtar` (`libarchive-tools`, apt candidate `3.7.2`, not installed) keeps them |

Memory for option D: after removing `boot/`, Arch's modules and all firmware
except `ath10k` and the files we add, the tree is about 585 MiB (565 plus
about 20 MiB of `ath10k` firmware), about 715 MiB with docs and man pages. The tablet has 3.47 GiB (`MemTotal` 3635968 kB), so a
tmpfs rootfs fits with room for pacman. This is an estimate from the file
sizes in the member list, not a measurement.

M6.1, option D. Expected, not done:

- A rootfs tarball made with `fakeroot` (or `bsdtar`, to keep capabilities)
  from the verified one: both accounts locked (the published passwords must
  not survive), key-only SSH through a drop-in in `sshd_config.d`, an SSH
  key from the owner's own `~/.ssh` (never committed), a `usb0.network`
  giving `usb0` the address init already uses (`172.16.42.1/24`) with a DHCP
  server for the single lease the host gets, Arch's kernel, `/boot` and
  modules removed and our modules from `out/kernel/modules` added, no
  machine id and no host keys. The first boot of the real tablet runs
  `pacman-key --init` and `--populate archlinuxarm`, so no emulation is
  needed to build the image. Removing files without pacman leaves its
  database claiming they exist: fine for a RAM proof, not for a persistent
  system.
- A change to the initramfs: receive the tarball on the USB network
  (`nc | tar`) into a tmpfs, then `switch_root` to `/lib/systemd/systemd`.
  Everything the init set up before that (gadget, MUIC, `qcom-pon`) stays.
  A new `recovery.img` and a flash, which need the owner's yes.
- Acceptance on the tablet: systemd reaches multi-user, `ssh` over USB gives
  a shell, `pacman -V` runs, `pacman-key --init` completes. `pacman -Sy`
  needs the tablet to reach a mirror: through the host (NAT, which needs
  `sudo` on this PC) or from a mirror directory served by the host. No Wi-Fi
  yet, M7.5.

M6.2: the persistent root, A or B, after the owner chooses.

M6.3, reproducible build with upstream's tooling, after the owner installs
the prerequisites: `docker.io`, `qemu-user-static` and `binfmt-support`
(apt candidates exist: `docker.io 29.1.3`, `qemu-user-static 8.2.2`,
`binfmt-support 2.2.2`; `podman 4.9.3` is the alternative), and the user in
the `docker` group. This is only needed to build the [omamobile] packages
and an image the way upstream does; M6.1 does not need it.

## 7. Decisions that belong to the owner

1. Does a microSD card exist for the tablet, and is a DT and kernel change
   for the slot acceptable (A)?
2. May a file be written into Lineage's `/data` (B)? It needs `adb root`
   on Lineage for a moment and a free-space check (29 GB were free on
   2026-11-04).
3. May the prerequisites for M6.3 be installed with `sudo apt`?
