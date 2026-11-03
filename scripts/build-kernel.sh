#!/bin/sh
# Cross-build Image.gz, the gts4lvwifi DTB and (unless --no-modules) modules.
# Does not pack a boot image and does not flash anything.
#
#   scripts/build-kernel.sh              # full build
#   scripts/build-kernel.sh --no-modules # Image.gz + DTB, smaller disk use
#
# Override KERNEL_SRC, OUT, CROSS_COMPILE, JOBS.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
kernel=${KERNEL_SRC:-$root/src/linux-gts4lv}
out=${OUT:-$root/out/kernel}
cross=${CROSS_COMPILE:-aarch64-linux-gnu-}
fragment=$root/device/gts4lvwifi/kernel.config
dtb_rel=qcom/sdm670-samsung-gts4lvwifi.dtb
modules=yes

for arg in "$@"; do
	case $arg in
	--no-modules) modules=no ;;
	-h | --help)
		sed -n '2,8p' "$0"
		exit 0
		;;
	*)
		echo "unknown argument: $arg" >&2
		exit 1
		;;
	esac
done

if [ ! -f "$kernel/Makefile" ]; then
	echo "kernel tree missing: $kernel" >&2
	echo "run scripts/fetch-sources.sh first" >&2
	exit 1
fi

if ! command -v "${cross}gcc" >/dev/null 2>&1; then
	echo "compiler not found: ${cross}gcc" >&2
	echo "Arch: sudo pacman -S --needed aarch64-linux-gnu-gcc aarch64-linux-gnu-binutils bc" >&2
	echo "Debian/Ubuntu: sudo apt install gcc-aarch64-linux-gnu bc bison flex" >&2
	exit 1
fi

if [ -z "${JOBS:-}" ]; then
	mem_kb=$(awk '/MemTotal/ { print $2 }' /proc/meminfo)
	cpus=$(nproc)
	# Linking vmlinux wants about 2 GB per heavy job. Under 12 GB, stay at 2.
	if [ "$mem_kb" -lt 12582912 ]; then
		JOBS=2
	else
		JOBS=$cpus
	fi
fi

echo "kernel  $kernel"
echo "out     $out"
echo "cross   $cross"
echo "jobs    $JOBS"
mkdir -p "$out"

make -C "$kernel" O="$out" ARCH=arm64 CROSS_COMPILE="$cross" defconfig
"$kernel/scripts/kconfig/merge_config.sh" -O "$out" -m "$out/.config" \
	"$kernel/arch/arm64/configs/sdm670.config" \
	"$fragment"
make -C "$kernel" O="$out" ARCH=arm64 CROSS_COMPILE="$cross" olddefconfig

targets="Image.gz dtbs"
if [ "$modules" = yes ]; then
	targets="$targets modules"
fi

make -C "$kernel" O="$out" ARCH=arm64 CROSS_COMPILE="$cross" -j"$JOBS" $targets

dtb=$out/arch/arm64/boot/dts/$dtb_rel
image=$out/arch/arm64/boot/Image.gz
if [ ! -f "$dtb" ] || [ ! -f "$image" ]; then
	echo "build finished without $image or $dtb" >&2
	exit 1
fi

cat "$image" "$dtb" > "$out/arch/arm64/boot/Image.gz-dtb"
echo
echo "Image.gz       $(stat -c %s "$image") bytes"
echo "DTB            $(stat -c %s "$dtb") bytes"
echo "Image.gz-dtb   $(stat -c %s "$out/arch/arm64/boot/Image.gz-dtb") bytes  $out/arch/arm64/boot/Image.gz-dtb"
if [ "$modules" = yes ]; then
	moddir=$out/modules
	rm -rf "$moddir"
	make -C "$kernel" O="$out" ARCH=arm64 CROSS_COMPILE="$cross" \
		INSTALL_MOD_PATH="$moddir" INSTALL_MOD_STRIP=1 modules_install
	echo "modules        $moddir"
fi
