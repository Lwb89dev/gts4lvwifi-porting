#!/bin/bash
# Build the Arch packages under packages/ for aarch64 in a container
# (docker + qemu-user), into out/repo/aarch64 with a repository database.
# Does not touch the tablet and installs nothing on this PC.
#
#   scripts/build-packages.sh
#
# The build image is made once from the verified Arch Linux ARM tarball: the
# keyring, base-devel and meson, and an unprivileged user. Sources are
# downloaded by makepkg and checked against the sha256 in each PKGBUILD.
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
cd "$root"
out=$root/out/repo/aarch64

sha=$(awk '$1 == "ArchLinuxARM-aarch64-latest.tar.gz" { print $3 }' rootfs.lock)
base=gts4lv-alarm-base:${sha%"${sha#????????}"}
build=gts4lv-alarm-build:${sha%"${sha#????????}"}

# docker may not be usable from a session that predates the docker group
if docker info >/dev/null 2>&1; then
	d() { docker "$@"; }
else
	d() { sg docker -c "$(printf '%q ' docker "$@")"; }
fi

d image inspect "$base" >/dev/null 2>&1 ||
	{ echo "no $base: run scripts/build-rootfs.sh once first" >&2; exit 1; }

make_build_image() {
	echo "==> build image $build"
	d rm -f gts4lv-build-prep >/dev/null 2>&1 || true
	d run --name gts4lv-build-prep --platform linux/arm64 \
		-v gts4lv-pkgcache:/var/cache/pacman/pkg \
		-v "$root/packages/prepare-build-image.sh:/prepare.sh:ro" \
		"$base" bash /prepare.sh
	d commit gts4lv-build-prep "$build" >/dev/null
	d rm gts4lv-build-prep >/dev/null
}

d image inspect "$build" >/dev/null 2>&1 || make_build_image

mkdir -p "$out"
d run --rm --platform linux/arm64 \
	-v "$root/packages:/packages:ro" \
	-v "$out:/out" \
	-v gts4lv-pkgcache:/var/cache/pacman/pkg \
	-v gts4lv-srccache:/srccache \
	"$build" bash /packages/build-inside.sh "$(id -u):$(id -g)"

(cd "$out" && sha256sum ./*.pkg.tar.zst > SHA256)
cat "$out/SHA256"
echo "not copied to the tablet"
