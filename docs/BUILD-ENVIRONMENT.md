# Build environment

The development machine for this checkout is the HP OMEN 16 running
Pop!_OS 24.04 (Ubuntu noble), not Arch Linux. Use apt here. The pacman
line in the README is for an Arch host.

## Packages

```sh
sudo apt-get update
sudo apt-get install -y gcc-aarch64-linux-gnu bc bison flex libssl-dev
```

Already present on this machine after that install: `aarch64-linux-gnu-gcc`
13.3.0, binutils 2.42, bison 3.8.2, flex 2.6.4, bc 1.07.1, libssl, Python
3.12, git, curl, cpio, gzip, make. A static userspace link works
(`aarch64-linux-gnu-gcc -static`).

Not installed, and not required for the current scripts: `shellcheck`,
host `dtc`, `dt-validate`, `heimdall-flash`. Heimdall 2.0.2 was unpacked
under `src/_host` for the rollback and was not committed.

## Checklist

- [x] `sources.lock` trees checked out under `src/`
- [x] `aarch64-linux-gnu-gcc` on `PATH`
- [x] At least 30 GB free (the kernel tree is about 2 GB, the build about 10–15 GB)
- [x] `scripts/build-kernel.sh` uses `ARCH=arm64` and `CROSS_COMPILE=aarch64-linux-gnu-`
- [x] Config order is `defconfig`, then `sdm670.config`, then `device/gts4lvwifi/kernel.config`
- [ ] `shellcheck` and `dtbs_check` (tools missing)

## Commands

```sh
scripts/fetch-sources.sh
scripts/build-kernel.sh
scripts/build-initramfs.sh
python3 tests/test-pack-recovery.py
scripts/verify-initramfs.sh
scripts/verify-recovery.py out/recovery.img
scripts/hash-artifacts.sh
```

`build-initramfs.sh` downloads BusyBox 1.36.1
(sha256 `b8cc24c9574d809e7279c3be349795c5d5ceb6fdf19ca709f80cde50e47de314`)
into `src/busybox` and disables `CONFIG_TC`, because the Ubuntu 24.04 kernel
headers no longer provide the CBQ structs that applet still references.
BusyBox's `tc` is not used.

None of these commands write a partition.
