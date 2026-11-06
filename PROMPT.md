# PROJECT: OMARCHY MOBILE — SAMSUNG GALAXY TAB S5e (SM-T720)
## Engineering assignment: Mainline Linux bring-up, Arch Linux ARM integration and complete Omarchy Mobile port

### 0. ROLE AND MISSION

Act as a team made up of:

- A Linux ARM64 kernel engineer specialised in Qualcomm Snapdragon.
- A Device Tree and platform-driver engineer.
- An Android/Samsung boot-chain and recovery specialist.
- An Arch Linux ARM distribution engineer.
- A Wayland, Mesa, Freedreno and Hyprland engineer.
- An embedded Linux integration and release engineer.
- A QA engineer for hardware bring-up.

Do not limit yourself to theoretical analysis. Examine the sources, continue the existing work, write
code, compile when possible, fix errors, prepare repeatable tests and document every result.

**Final goal:** port Derek Ross's Omarchy Mobile to the Samsung Galaxy Tab S5e Wi-Fi SM-T720, running
Arch Linux ARM and Hyprland directly on the hardware, without Android as the underlying operating system.

The initial goal is narrower: obtain a compiled mainline-based kernel, a verifiable recovery image and,
later, a working Linux shell over USB.

Do not consider a phase complete merely because the code compiles. Every milestone must have measurable
acceptance criteria.

---

### 1. REPOSITORY AND SOURCES

**Required main repository:**

https://github.com/Lwb89dev/gts4lvwifi-porting

This is the working repository. Do not create a new repository for the project or arbitrarily replace
its structure.

**Omarchy Mobile upstream:**

https://github.com/derekross/omarchy-mobile

**Tablet-specific mainline-based kernel:**

https://github.com/pulpoff/linux-gts4lv

**Additional references:**

- https://github.com/LineageOS/android_device_samsung_gts4lvwifi
- https://github.com/LineageOS/android_device_samsung_gts4lv-common
- https://github.com/LineageOS/android_kernel_samsung_sdm670
- https://archlinuxarm.org/
- https://www.kernel.org/
- https://docs.kernel.org/

Read the following documents before modifying code.

In this repository:

- `README.md`
- `PROCESS.md`
- `sources.lock`
- `device/gts4lvwifi/device.conf`
- `device/gts4lvwifi/kernel.config`
- `device/gts4lvwifi/BRINGUP-M1.md`
- `device/gts4lvwifi/NOTES.md`
- `scripts/fetch-sources.sh`
- `scripts/build-kernel.sh`
- `.github/workflows/kernel.yml`

In Omarchy Mobile upstream:

- `README.md`
- `AGENTS.md`
- `CONTRIBUTING.md`
- `docs/DEVICES.md`
- `docs/ROADMAP.md`
- `docs/RELEASES.md`
- `tools/build-packages`
- `tools/build-rootfs`
- The `omamobile-shell`, `omamobile-apps` and device-specific packages.

In pulpoff's kernel:

- `README.md`
- `arch/arm64/configs/sdm670.config`
- `arch/arm64/boot/dts/qcom/sdm670-samsung-gts4lvwifi.dts`
- `arch/arm64/boot/dts/qcom/sdm670-samsung-gts4lvwifi-dtbo-mask.dtsi`
- The `mobian/` directory, especially the boot, touchscreen, USB, firmware and power-management tools.

Check the current repository state before working: branch, latest commits, local changes, licences and
any incompatibilities.

Use `sources.lock` for reproducible revisions. Do not update revisions merely because a newer commit
exists: document the reason and impact first.

### 2. HARDWARE TARGET AND STARTING STATE

The device is:

| Field | Value |
|---|---|
| Model | Samsung Galaxy Tab S5e Wi-Fi |
| Codename | `gts4lvwifi` |
| Model number | SM-T720 |
| SoC | Qualcomm Snapdragon 670 / SDM670 |
| CPU architecture | ARM64 / AArch64 |
| GPU | Qualcomm Adreno 615 |
| Device RAM | 4 GB |
| Display | AMOLED 2560×1600 |
| Storage | eMMC |
| Boot partitioning | Single-slot, not A/B |
| Current system | LineageOS 22.2, Android 15 |
| Current Android kernel | Linux 4.9.337 |
| Bootloader | Unlocked, according to previous checks |

The data is documented in the repository, but must be reconfirmed before any procedure that could
affect the device.

The LTE SM-T725 model is explicitly out of scope.

The main development PC is an HP OMEN 16 x86_64 running Pop!_OS 24.04 LTS.

It can cross-compile for AArch64. Check the actual machine capabilities, compilers, RAM and free space
instead of assuming it is Arch Linux. Use `apt` for native Pop!_OS dependencies, except in separate
isolated environments.

### 3. ARCHITECTURAL CONSTRAINTS

#### 3.1 Kernel

The chosen base is `pulpoff/linux-gts4lv`, not `derekross/linux-omarchy-mobile`.

Reason: Derek Ross's kernel is primarily aimed at Tensor/Pixel devices, while pulpoff already integrated
support specific to SDM670 and the Tab S5e.

Pulpoff's kernel is mainline-based, with additional patches. Do not present it as a completely vanilla,
fully upstream kernel.

The Samsung 4.9 kernel is only a reference for registers, initialisation, timing and hardware settings.

Our long-term goal is to reduce out-of-tree patches and submit appropriate changes upstream.

#### 3.2 Bootloader

The Samsung tablet is single-slot.

Do not use Omarchy Mobile's Pixel installation commands.

**Running `tools/install-phone` on the Tab S5e is forbidden.**

The project path is:

- LineageOS remains in the `boot` partition.
- Linux is booted through `recovery`.
- The Samsung bootloader requires an Android boot header v1 image.
- The DTB is concatenated to `Image.gz`.
- `recovery_dtbo` must be compatible with the Samsung bootloader.

The measured recovery partition is **72,744,960 bytes**. Do not confuse it with the boot size,
67,108,864 bytes.

Check the measurements in `PROCESS.md` and `device.conf`; do not use generic values found on the Internet.

#### 3.3 Root filesystem

The final system must use Arch Linux ARM AArch64.

Do not delete or reformat `userdata` to install it.

The current LineageOS data partition is ext4 with file-based encryption. Do not assume it can be mounted
directly from Linux or that an image file can be created without handling encryption and extent mapping.

Study pulpoff's `dm-linear` method, but treat it as a candidate solution to verify, not as automatically safe.

Also evaluate an initial rootfs on microSD if the hardware support and boot modes are verified.

### 4. SAFETY RULES — NON-NEGOTIABLE

Before every change affecting real hardware, give absolute priority to recoverability.

Without explicit user approval, it is forbidden to:

- Flash any partition.
- Reboot or forcibly power off the tablet.
- Modify `boot`, `dtbo`, `vbmeta`, `userdata`, `misc`, the bootloader or calibration partitions.
- Perform raw writes with `dd`, Heimdall, Odin or other programs.
- Change boot-verification states.
- Apply persistent changes to the existing LineageOS system.

For every activity that could become destructive, provide first:

1. The exact command to use.
2. Verified device identification.
3. The affected partition.
4. Concrete risks.
5. Expected result.
6. Rollback procedure.
7. Conditions that require stopping.
8. A request for authorisation.

Keep local backups of the information and partitions needed for recovery. Do not upload partition images
or personal data to GitHub.

Do not distribute proprietary firmware, NV data, MAC addresses, serial numbers or calibration information.

Also inspect binary files already present in the repository, including `lineage-recovery-dtbo.img`:
document their origin, checksum and redistribution conditions. If necessary, prepare a local extraction
mechanism from the owner's firmware instead of distributing the blob.

Automated tests must be non-destructive.

---

## 5. MILESTONE M0 — AUDIT AND ENVIRONMENT PREPARATION

### Activities

1. Retrieve the main repository or use the existing local checkout.
2. Check `git status`, branch, remote and commits.
3. Do not delete uncommitted changes.
4. Create a dedicated branch, for example `feat/gts4lvwifi-mainline-bringup`, unless an appropriate development branch already exists.
5. Verify `sources.lock` and source hashes.
6. Check build prerequisites.
7. Check available CPU, RAM, disk and ARM64 toolchain.
8. Check the GitHub Actions configuration.
9. Identify problems and duplication in the current repository structure.
10. Produce a technical status report distinguishing implemented, compiled, tested and still-missing work.

In particular, verify that these files are usable:

- `scripts/fetch-sources.sh`
- `scripts/build-kernel.sh`
- `device/gts4lvwifi/device.conf`
- `sources.lock`

Do not rewrite these components if they already work. Fix only documented problems.

### Deliverables

- `docs/AUDIT.md`
- `docs/BUILD-ENVIRONMENT.md`
- A summary of missing prerequisites.
- A verifiable build-environment checklist.

**M0 acceptance criterion:** sources identified, environment ready and a reproducible build planned
without modifying the tablet.

---

## 6. MILESTONE M1 — KERNEL CROSS-COMPILATION

### Objective

Produce ARM64 artifacts for the Galaxy Tab S5e using the kernel fixed by the repository.

### Procedure

Start with the existing scripts:

```bash
scripts/fetch-sources.sh
scripts/build-kernel.sh
```

Verify that the build uses:

- `ARCH=arm64`
- The `aarch64-linux-gnu-` cross compiler.
- `defconfig`
- `arch/arm64/configs/sdm670.config`
- `device/gts4lvwifi/kernel.config`

Check the required tools, including Kconfig and OpenSSL dependencies.

Do not assume `scripts/build-kernel.sh` is correct without checking its behaviour.

### Required artifacts

- `Image.gz`
- `sdm670-samsung-gts4lvwifi.dtb`
- `Image.gz-dtb`
- Kernel modules compatible with the same build.
- Final `.config`.
- SHA-256 manifest of the artifacts.

The combined image must be at the project path:

`out/kernel/arch/arm64/boot/Image.gz-dtb`

### Mandatory checks

- Confirm that the required DTS is compiled.
- Check the `compatible` property.
- Verify that critical kernel options are enabled after `olddefconfig`.
- Check eMMC, USB gadget, DRM, input, devtmpfs and required filesystem support.
- Check the `make` result and any relevant warnings.
- Run Device Tree validation (`dtbs_check`/`dt-validate`) when supported by the tree.
- Do not confuse a pre-existing warning with a new error introduced by the port.
- Check that `Image.gz-dtb` is actually the correct concatenation of the two artifacts.
- Document the kernel version and exact source hashes.

Do not present hardware as working merely because its driver appears in the configuration.

**M1 acceptance criterion:** build completed, artifacts verified and no change made to the tablet.

---

## 7. MILESTONE M2 — MINIMAL BRING-UP INITRAMFS

### Objective

Create a minimal Linux initramfs capable of booting the kernel and providing diagnostic access.

Do not install Omarchy yet.

### Required functionality

- Working PID 1.
- Mounting `/proc`, `/sys`, `/dev` and required temporary filesystems.
- Diagnostic shell.
- Kernel identification.
- Boot-log collection.
- Emergency mode on error.
- USB gadget support if it works on the device.
- Remote access over USB networking and SSH/Dropbear, or a USB serial console when supported.
- Explicit handling of initialisation errors.

Remote access must not depend on Wi-Fi.

Check available gadget drivers, compatibility with the host PC and whether specific modules or tools
must be included in the initramfs.

Configure a predictable local USB address only after verifying which interface is exposed.

Do not assume Android ADB works automatically on Linux.

### Technical requirements

- Self-contained initramfs for the first test.
- No dependency on `/data`.
- No read/write mount of Android partitions.
- No automatic modification of `misc` or recovery state.
- Reasonable timeouts and fallbacks.
- Logs accessible for diagnosing a failed boot.
- Keys and credentials not embedded in public code.

Document which components are built into the kernel and which require modules.

### Expected diagnostics after boot

```bash
uname -a
cat /proc/cmdline
cat /proc/cpuinfo
cat /proc/mounts
dmesg
ls /sys/class/
ls /dev/
```

Adapt the set to the tools actually present in the initramfs.

### Deliverables

- Initramfs sources and build scripts.
- Minimal configuration.
- Offline verification script.
- USB-access documentation.
- First-boot checklist.

**M2 acceptance criterion:** initramfs built and checked offline; hardware boot remains a separate phase.

---

## 8. MILESTONE M3 — SAMSUNG RECOVERY PACKAGING

### Objective

Implement the missing component needed to produce a recovery image usable by the Samsung bootloader.

Start from the parameters actually documented in `device.conf`.

### Required parameters

| Field | Value |
|---|---|
| Android boot header | v1 |
| Page size | 4096 |
| Kernel offset | `0x8000` |
| Ramdisk offset | `0x02000000` |
| Tags offset | `0x01e00000` |
| Maximum size | 72,744,960 bytes |
| Kernel payload | `Image.gz` + DTB |
| Recovery DTBO | Verified LineageOS overlay |

Read values from the descriptor instead of duplicating constants in multiple scripts.

### Packer requirements

1. Accept only artifacts that are present and valid.
2. Verify hashes of components that require exact correspondence.
3. Check header, paging, sizes and offsets.
4. Include `recovery_dtbo` in the expected position and format.
5. Do not alter bytes in the original overlay.
6. Fail if the image exceeds the physical partition limit.
7. Write the image only to the PC output directory.
8. Contain no flash command.
9. Produce a manifest with versions, checksums and sizes.
10. Support inverse checks through Android unpacking tools.

Also compare the result with the packaging script behaviour in pulpoff's project.

Examine the existing command line:

`console=tty0 fw_devlink.sync_state=timeout clk_ignore_unused pd_ignore_unused panic=10`

In particular, preserve `fw_devlink.sync_state=timeout` until there is enough evidence to change it.

Avoid changing power-management parameters or panel-initialisation sequences simultaneously.

### Tests

Create automated tests that check:

- Valid header.
- Size within the limit.
- Correct DTB.
- Recovery DTBO integrity.
- Packaging repeatability.
- Controlled failure for missing or corrupt input.
- Rejection of a different hardware target.

### Deliverables

- Packaging script.
- Packaging tests.
- Manifest.
- Image ready for a possible manual test.

**M3 acceptance criterion:** recovery image buildable and verifiable offline, with no flash.

---

## 9. MILESTONE M4 — RECOVERY PLAN AND FIRST-BOOT PREPARATION

Before touching `recovery`, verify and document:

- Accessibility of Samsung Download Mode.
- Reliable method to restore a compatible recovery.
- Availability of official firmware for the matching model.
- Practical ability to use Heimdall or Odin for restoration.
- Compatibility of the chosen method with the installed bootloader.
- Read-only backup of the current recovery.
- Backup integrity using SHA-256.
- Procedure to return to LineageOS.
- Bootloader behaviour when recovery does not start.
- Behaviour of the `misc` partition and recovery-boot requests.

Do not treat Download Mode as an absolute recovery guarantee.

The documentation must explicitly state situations where recovery could require more complex intervention.

Do not modify the `boot` partition.

For the first test, prefer a manual recovery boot instead of persistently changing the boot destination.

### Deliverable

`docs/RECOVERY-RUNBOOK.md`

The document must contain a step-by-step procedure with:

- Exact commands.
- Expected output.
- Stop conditions.
- Rollback.
- Risk level.

**M4 acceptance criterion:** plan validated, backups available and explicit user approval before proceeding.

---

## 10. MILESTONE M5 — FIRST MAINLINE BOOT ON THE TABLET

This milestone requires access to the physical device and specific authorisation.

Do not simulate completion.

### Verification sequence

1. Identify the device again.
2. Confirm the model and partition map.
3. Confirm artifact correspondence.
4. Perform only the authorised boot operation.
5. Verify that the bootloader loads the image.
6. Verify the transition to the Linux kernel.
7. Verify essential initialisation.
8. Verify shell access.
9. Collect logs.
10. Test returning to LineageOS.

### First meaningful result

Obtain:

- `uname -a` from the tablet's Linux kernel.
- Reachable Linux shell.
- Readable `dmesg` log.
- Device Tree identification.
- No damage to the Android system kept in `boot`.

Display, GPU and touchscreen do not need to work yet.

### Debugging

If the tablet does not start, investigate separately:

- Samsung boot-image header.
- Recovery DTBO.
- Device Tree selection.
- Early console.
- Memory reservations.
- Clocks and regulators.
- eMMC initialisation.
- USB gadget.
- Initramfs.
- Kernel panic.
- Watchdog/reset.

Do not change several subsystems at once.

For every attempt, identify exactly which difference was introduced compared with the previous artifact.

**M5 acceptance criterion:** real shell on the device and verified return to LineageOS.

---

## 11. MILESTONE M6 — ARCH LINUX ARM ROOTFS

### Objective

Replace the minimal environment with a working Arch Linux ARM AArch64 distribution.

### Build policy

**Do not rebuild the entire distribution.**

First use packages already available in the official Arch Linux ARM repositories.

Identify precisely which components require device-specific compilation:

| Component | Approach |
|---|---|
| Core system | Arch Linux ARM packages |
| systemd, pacman and common libraries | Prebuilt packages |
| Mesa | Prefer an existing AArch64 package |
| Hyprland | Existing AArch64 package unless patches are required |
| SDM670 kernel | Device-specific compilation |
| Samsung DTB | Device-specific compilation |
| Kernel modules | Same kernel version |
| Custom Omarchy Mobile packages | Reuse compatible binaries or compile them |
| Device integration | Package specific to `gts4lvwifi` |

Arch Linux ARM already provides AArch64 Hyprland packages. Still verify version, dependencies and
compatibility with Omarchy Mobile patches.

Do not indiscriminately mix Arch Linux x86_64 repositories with Arch Linux ARM.

### Build and provisioning

Analyse upstream Omarchy Mobile's `tools/build-packages` and `tools/build-rootfs` to determine what can
be reused.

If the build system assumes an Arch host, implement a reproducible method on Pop!_OS, for example through
a container or a suitable AArch64 environment.

Verify that scripts do not execute AArch64 code directly on x86_64 without an appropriate mechanism.

The rootfs must include:

- Correctly initialised pacman and keyring.
- systemd.
- Networking.
- OpenSSH.
- Udev.
- Local user management.
- Persistent logs where appropriate.
- Kernel-module handling.
- Compatible Omarchy Mobile repositories and packages.
- Firmware handling that respects licences.

### Storage

Analyse three possibilities:

A. Rootfs on microSD.

B. Rootfs in an image file on eMMC.

C. A dedicated repartition, only as a future option and with explicit approval.

Compare them by risk, performance, complexity, compatibility with LineageOS and recoverability.

The Android data partition is encrypted: determine precisely whether pulpoff's `dm-linear` method can
be reused safely and with which prerequisites.

Do not modify `userdata` without approval.

### M6 acceptance criterion

Arch Linux ARM booted on the tablet with systemd, shell, USB networking and package management working.

---

## 12. MILESTONE M7 — HARDWARE ENABLEMENT

Create a real evidence-based hardware matrix.

Every subsystem must have one of these states:

- Not verified.
- Present in the sources.
- Compiled.
- Detected by the kernel.
- Partly working.
- Working and tested.
- Regression.
- Blocked.

Do not simply say “supported” without specifying what that means.

### Implementation order

**M7.1 — Storage and USB**

Verify eMMC, microSD, USB gadget, USB networking and OTG.

Use pulpoff's DWC3 controller reference and userspace USB-role code.

Do not enable VBUS or change the USB role without checking the controller and power conditions.

**M7.2 — Display**

Known hardware from the reference kernel:

- AMOLED 2560×1600.
- Samsung AMSA05RB01 panel.
- Anapass ANA38401 bridge.
- Dual DSI in command mode.

Start with a simple framebuffer and simpledrm, then verify the real DRM/KMS driver.

Pay attention to handover from the bootloader framebuffer to the panel driver.

Explicitly test:

- 2560×1600 mode.
- Integrity of both panel halves.
- Stable refresh.
- Backlight/brightness.
- Display off/on.
- No flickering or tearing.

**M7.3 — GPU**

Adreno 615 GPU.

Reuse Freedreno for OpenGL and Turnip for Vulkan where available and working.

Verify firmware, zap shader and MSM DRM driver loading.

Tests:

- Render node present.
- Correct real renderer.
- Hardware OpenGL ES.
- Vulkan, if usable.
- Wayland rendering without software fallback.
- Temperature and stability under sustained load.

Do not accept llvmpipe as proof of GPU acceleration.

**M7.4 — Touchscreen**

STM FTS1BA90A controller.

Pulpoff uses a userspace daemon in `mobian/gts4lv-touchd.c`.

Study its protocol, licence and dependencies before reusing it.

Implement correct integration with libinput and Wayland.

Test taps, multitouch, scrolling, gestures, rotation and recovery after display-off.

**M7.5 — Wi-Fi and Bluetooth**

Qualcomm WCN3990 chipset.

Identify:

- Kernel driver.
- Required firmware.
- Tablet-specific calibration data.
- Dependencies on Qualcomm services.
- NetworkManager or equivalent configuration.

Test Wi-Fi association, persistent connections, reconnect, Bluetooth pairing and Bluetooth audio.

**M7.6 — Audio**

Four Cirrus Logic CS35L41 amplifiers.

Verify codec, TDM interface, four-amplifier configuration, channel routing and microphones.

Integrate ALSA, UCM and PipeWire.

Start with limited volumes and active protection to avoid speaker damage.

Do not import Android mixers without adaptation.

**M7.7 — Battery and power**

SM5705 fuel gauge.

Verify charging, battery level, temperature, USB power, charging state and controlled shutdown.

Integrate UPower and the interface's power management.

Do not assume correct battery readings prove that every charging path is safe.

**M7.8 — Sensors and rotation**

Verify accelerometer, light sensor, magnetometer and Hall sensor.

Study Qualcomm ADSP components and the `hexagonrpcd`/`libssc` userspace code in the reference project.

Integrate automatic rotation without copying unnecessary GNOME-specific services.

**M7.9 — Suspend and resume**

The pulpoff project reports s2idle support with watchdog and ADSP-service workarounds.

Do not automatically consider suspend working with our rootfs and userspace.

Start with suspend disabled until reliable tests exist.

Progressive tests:

- Display off/on.
- Short suspend.
- Resume with the power key.
- Long suspend.
- Battery consumption during standby.
- Wi-Fi and Bluetooth after resume.
- USB networking after resume.

**M7.10 — Multimedia and secondary peripherals**

Only afterwards:

- Qualcomm Venus video acceleration.
- H.264/H.265 decoding.
- Cameras and libcamera.
- Autofocus, if supportable.
- Magnetic cover.
- Other peripherals actually present.

Do not implement cellular modem or phone functions for a Wi-Fi model.

---

## 13. MILESTONE M8 — OMARCHY MOBILE INTEGRATION

### Objective

Boot the real Omarchy Mobile experience, not a Linux desktop that resembles it.

The base must remain Derek Ross's upstream.

### Requirements

1. Study how Omarchy Mobile integrates Hyprland and the mobile shell.
2. Reuse existing cross-platform packages.
3. Separate tablet-specific configuration.
4. Introduce the `omamobile-device-gts4lvwifi` package.
5. Do not indiscriminately copy Pixel-specific services.
6. Keep as many components as possible updateable from upstream.
7. Avoid gratuitous Omarchy and Hyprland forks.
8. Keep a documented patch directory only where real differences are required.

### Tablet interface

Unlike a smartphone, this device has a 10.5-inch 2560×1600 display.

The experience must support:

- Portrait and landscape.
- Correct scaling.
- Touchscreen as the primary input.
- Virtual keyboard.
- Gesture navigation.
- Touch-friendly quick settings.
- Brightness and audio management.
- Lock screen.
- Notification bar.
- Application launching.
- Tablet-appropriate multitasking.
- External keyboard and mouse.
- Display rotation when the sensor is available.

Evaluate whether to keep the mobile one-application-per-screen paradigm or provide tablet-specific behaviour.

Do not turn Omarchy Mobile into GNOME, Phosh or Plasma Mobile.

### Performance

The tablet has 4 GB of RAM.

Optimise:

- Memory at startup.
- Shell RAM usage.
- Background processes.
- ZRAM.
- Graphics caches.
- Application launch times.
- Standby consumption.
- Animation smoothness.

Do not apply unmeasured optimisations.

### M8 acceptance criterion

The tablet must show Omarchy Mobile with hardware graphics acceleration, working touchscreen and
working application management.

---

## 14. MILESTONE M9 — DISTRIBUTION, UPDATES AND CI

### Objective

Make the port reproducible and maintainable.

Implement a build process capable of generating:

- Kernel.
- DTB.
- Modules.
- Initramfs.
- Recovery image.
- Arch Linux ARM rootfs.
- Device-specific packages.
- Version and checksum manifest.

### GitHub Actions

Reuse the existing `kernel.yml` workflow.

Do not replace it without a reason.

Consider separate workflows for:

- Static tests.
- Kernel and DTB build.
- Initramfs.
- Recovery packaging.
- AArch64 package builds.
- Rootfs.
- Artifact verification.
- Release candidate.

Check runner space, memory and time limits.

Do not expose firmware, private keys or personal content in public artifacts.

### Updates

Study integration with pacman and `omarchy update`.

On this single-slot Samsung, Pixel slot-B image updates cannot be reused automatically.

Kernel and recovery updates need a dedicated, verifiable and initially manual procedure.

Do not configure automatic updates that write recovery without a demonstrated recovery path.

### M9 acceptance criterion

Builds reproducible, documented and verifiable from a clean Linux machine.

---

## 15. LICENCES, FIRMWARE AND UPSTREAM

Every introduced file must respect the applicable licences.

Distinguish:

- Open-source kernel drivers.
- GPL kernel patches.
- Device Tree configurations.
- Proprietary binary firmware.
- Vendor Android libraries.
- Open-source userspace components.

Android kernel drivers cannot simply be moved as binaries into a modern Linux kernel.

Prefer mainline drivers and original firmware extracted from the owner's installation.

Do not distribute Samsung or Qualcomm firmware without checking its licence conditions.

If kernel patches are needed, keep them small and split by subsystem, preparing them for possible upstream submission.

For every change record:

- Modified file.
- Reason.
- Information provenance.
- Tests performed.
- Dependencies.
- Any regressions.

---

## 16. REPOSITORY ORGANISATION

Keep the existing structure and expand it only when necessary.

A possible evolution, to be adapted to the actual structure, is:

```text
gts4lvwifi-porting/
├── .github/workflows/
├── device/gts4lvwifi/
│   ├── device.conf
│   ├── kernel.config
│   ├── BRINGUP-M1.md
│   ├── NOTES.md
│   └── ...
├── scripts/
│   ├── fetch-sources.sh
│   ├── build-kernel.sh
│   ├── build-initramfs.sh
│   ├── pack-recovery.sh
│   ├── verify-recovery.sh
│   └── ...
├── initramfs/
├── packages/
│   └── omamobile-device-gts4lvwifi/
├── rootfs/
├── tests/
├── docs/
│   ├── AUDIT.md
│   ├── BUILD-ENVIRONMENT.md
│   ├── HARDWARE-MATRIX.md
│   ├── RECOVERY-RUNBOOK.md
│   ├── PORTING-ROADMAP.md
│   └── ...
├── PROCESS.md
├── sources.lock
├── README.md
├── src/           # gitignored
└── out/           # gitignored
```

This is a proposal, not an instruction to rewrite what already exists.

Do not commit vendored external sources, huge images, firmware, temporary filesystems or
non-redistributable binaries.

---

## 17. QUALITY AND TESTING

Implement real checks.

### Static tests

- ShellCheck on shell scripts, when available.
- Syntax checks.
- YAML validation for workflows.
- Device Tree validation.
- Input checksums.
- Config-fragment verification.
- Size checks.
- Packaging-tool tests.
- Behaviour tests on invalid input.

### Integration tests

When a rootfs exists:

- systemd boot.
- Networking.
- SSH.
- Modules.
- Pacman.
- DRM.
- Input.
- PipeWire.
- Hyprland.
- Omarchy Mobile.

### Hardware tests

Every verification must state:

- Kernel used.
- Exact commit.
- Command or procedure.
- Result.
- Log.
- Final state.
- Any rollback.

Keep `docs/HARDWARE-MATRIX.md` updated.

A driver present in the sources is not equivalent to verified hardware.

---

## 18. WORKING METHOD AND REPORTS

Do not merely explain what should be done.

For every work cycle:

1. Analyse the existing code.
2. Identify the most important open problem.
3. Implement the required change.
4. Run available tests.
5. Fix detected errors.
6. Update documentation.
7. Produce a coherent commit.
8. Report results and blockers.

Do not claim builds or hardware tests that were not actually run.

When the environment prevents execution, prepare code and tests for the user's PC, clearly distinguishing
verified results from expected results.

Every report must contain:

| Field | Content |
|---|---|
| Milestone | Current phase |
| Status | Not started / WIP / Passed / Blocked |
| Commit | Exact hash |
| Changes | Files actually modified |
| Build | Pass / Fail / Not run |
| Offline tests | Pass / Fail / Not run |
| Tablet tests | Pass / Fail / Not run |
| Problems | List of blockers |
| Next action | One concrete action |

Do not proceed to the next milestone if the previous one has blocking errors.

For physical-device work, always provide an approvable runbook and wait for user authorisation.

Do not force-push or rewrite repository history.

Keep `PROCESS.md` as an up-to-date handoff document so another developer or agent can resume without losing context.

---

## 19. IMMEDIATE EXECUTION — FIRST WORK CYCLE

Start now.

The first session must focus on milestones **M0, M1, M2 and M3**, all executable without flashing the device.

### Operational priorities

**First:** examine `Lwb89dev/gts4lvwifi-porting` thoroughly and describe its real state, not the assumed state.

**Second:** verify that the kernel fixed in `sources.lock` contains the correct DTS and that the cross-compilation
script produces the expected artifacts.

**Third:** compile the kernel if the environment allows it. Record errors and warnings.

**Fourth:** implement or complete the minimal initramfs for the first diagnostic boot.

**Fifth:** implement the Samsung recovery header-v1 packer and its offline tests.

**Sixth:** verify checksums, sizes, formats and artifact reproducibility.

**Seventh:** prepare the first-boot runbook, specifying what the tablet owner must do manually.

**Eighth:** update `PROCESS.md`, the roadmap and the documentation.

### Stop conditions

Stop and ask for confirmation before:

- Modifying the tablet.
- Writing partitions.
- Flashing.
- Rebooting the device.
- Altering LineageOS.
- Attempting persistent boot.
- Modifying firmware or calibration data.

The complete analysis, programming, compilation and offline testing of available sources is allowed.

### Required result at the end of the first cycle

I want to receive:

1. Documented initial technical state.
2. Implemented or modified files.
3. Actual kernel-compilation result.
4. Initramfs status.
5. Recovery-packer status.
6. Offline tests passed and failed.
7. Commits produced on the working branch.
8. Problems preventing the first boot.
9. Concrete and safe procedure for the next session.
10. Exact list of operations requiring my authorisation.

Do not claim Omarchy Mobile works until it has actually booted on the tablet.

**The first milestone is a Linux shell on Snapdragon 670. The second is Arch Linux ARM with essential
hardware support. The third is Omarchy Mobile with Hyprland, touchscreen and graphics acceleration working.**

Work in this order, continue the existing project and preserve the ability to return to LineageOS.
