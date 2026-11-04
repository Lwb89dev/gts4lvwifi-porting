#!/bin/sh
# Check out the trees pinned in sources.lock under src/. Safe to re-run.
set -eu

root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
lock=$root/sources.lock
mkdir -p "$root/src"

checkout() {
	name=$1
	url=$2
	rev=$3
	dest=$root/src/$name

	if [ ! -d "$dest/.git" ]; then
		git init -q "$dest"
		git -C "$dest" remote add origin "$url"
	fi

	if [ "$name" = android_kernel_samsung_sdm670 ]; then
		git -C "$dest" sparse-checkout init --cone >/dev/null 2>&1 || true
		git -C "$dest" sparse-checkout set arch/arm64/boot/dts/samsung arch/arm64/configs
	fi

	echo "fetch $name $rev"
	git -C "$dest" fetch --depth 1 -q origin "$rev"
	git -C "$dest" checkout --detach -q FETCH_HEAD
	echo "  $(git -C "$dest" rev-parse HEAD)  $dest"
}

while read -r name url rev rest; do
	case $name in
	"" | \#*) continue ;;
	esac
	if [ -n "${rest:-}" ]; then
		echo "sources.lock: extra fields on $name" >&2
		exit 1
	fi
	checkout "$name" "$url" "$rev"
done < "$lock"
