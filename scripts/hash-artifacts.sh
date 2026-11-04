#!/bin/sh
# Write SHA-256 sums for the bring-up artifacts. Does not flash.
set -eu

root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
out=$root/out/MANIFEST.sha256
cd "$root"
files="
out/kernel/arch/arm64/boot/Image.gz
out/kernel/arch/arm64/boot/dts/qcom/sdm670-samsung-gts4lvwifi.dtb
out/kernel/arch/arm64/boot/Image.gz-dtb
out/initramfs.cpio.gz
out/recovery.img
"
for file in $files; do
	if [ ! -f "$file" ]; then
		echo "missing $file" >&2
		exit 1
	fi
done
# shellcheck disable=SC2086
sha256sum $files > "$out"
if [ -f out/kernel/include/config/kernel.release ]; then
	echo "# kernel $(cat out/kernel/include/config/kernel.release)" >> "$out"
fi
cat "$out"
