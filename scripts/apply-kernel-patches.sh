#!/bin/sh
# Put this repository's changes into the pinned kernel tree under src/: the
# touchscreen driver (copied) and the patches in device/gts4lvwifi/kernel/patches
# (applied with git apply). Safe to run again: what is already applied is skipped.
# The tree stays what the pinned commit is, plus these changes, uncommitted.
#
#   scripts/apply-kernel-patches.sh
#
# Override KERNEL_SRC.
set -eu

root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
kernel=${KERNEL_SRC:-$root/src/linux-gts4lv}
dir=$root/device/gts4lvwifi/kernel

[ -f "$kernel/Makefile" ] || { echo "kernel tree missing: $kernel" >&2; exit 1; }

install -m 644 "$dir/fts1ba90a/fts1ba90a.c" "$kernel/drivers/input/touchscreen/fts1ba90a.c"
echo "copied: fts1ba90a.c"

for patch in "$dir"/patches/*.patch; do
	name=$(basename "$patch")
	if git -C "$kernel" apply --reverse --check "$patch" >/dev/null 2>&1; then
		echo "already applied: $name"
		continue
	fi
	git -C "$kernel" apply --check "$patch"
	git -C "$kernel" apply "$patch"
	echo "applied: $name"
done
