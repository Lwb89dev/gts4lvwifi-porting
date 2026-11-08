#!/bin/bash
# Build the Arch Linux ARM root image for the tablet: out/rootfs/rootfs.img.
# Runs aarch64 containers on this x86 PC (docker + the qemu-aarch64 binfmt
# handler). Does not touch the tablet and does not flash anything.
#
#   scripts/build-rootfs.sh
#
# Needs: scripts/fetch-alarm-rootfs.sh already run, scripts/build-kernel.sh
# already run (the modules), docker, qemu-user-static, binfmt-support.
# ROOTFS_MB sets the image size (default 6144). ROOTFS_VARIANT writes to a
# separate out/rootfs-<variant> directory (for example the Omarchy image), so
# an experimental build cannot replace the known-good bring-up image.
# GTS4LV_TEST_ALARM_PASSWORD_FILE is an explicit, ignored local file used only
# for test images.  Its one-line value becomes alarm's graphical-unlock
# password;
# leave it unset for a release image, where both interactive accounts remain
# locked.
# The upgrade step takes
# whatever Arch Linux ARM ships that day, so two builds differ: the package
# list of each is written to out/rootfs/packages.txt.
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
cd "$root"
dev=device/gts4lvwifi
variant=${ROOTFS_VARIANT:-}
case $variant in
"") out=$root/out/rootfs ;;
*[!a-z0-9-]*) echo "ROOTFS_VARIANT may contain only a-z, 0-9 and -" >&2; exit 1 ;;
*) out=$root/out/rootfs-$variant ;;
esac
size_mb=${ROOTFS_MB:-6144}
tarball=src/alarm/ArchLinuxARM-aarch64-latest.tar.gz

sha=$(awk '$1 == "ArchLinuxARM-aarch64-latest.tar.gz" { print $3 }' rootfs.lock)
tag=gts4lv-alarm-base:${sha%"${sha#????????}"}
release=$(cat out/kernel/include/config/kernel.release)
modules=$root/out/kernel/modules/lib/modules/$release
key=$root/out/keys/gts4lv_ed25519
test_password_file=${GTS4LV_TEST_ALARM_PASSWORD_FILE:-}

# docker may not be usable from a session that predates the docker group
if docker info >/dev/null 2>&1; then
	d() { docker "$@"; }
else
	d() { sg docker -c "$(printf '%q ' docker "$@")"; }
fi

[ -f "$tarball" ] || { echo "run scripts/fetch-alarm-rootfs.sh first" >&2; exit 1; }
echo "$sha  $tarball" | sha256sum -c --quiet - || {
	echo "$tarball does not match rootfs.lock" >&2
	exit 1
}
[ -d "$modules" ] || { echo "no modules for $release, run scripts/build-kernel.sh" >&2; exit 1; }

mkdir -p "$out/keys" "$root/out/keys"
if [ ! -f "$key" ]; then
	ssh-keygen -q -t ed25519 -N '' -C gts4lvwifi-bringup -f "$key"
fi
cp "$key.pub" "$out/keys/authorized_keys"

test_password_mount=()
test_password_env=()
if [ -n "$test_password_file" ]; then
	[ -f "$test_password_file" ] || {
		echo "GTS4LV_TEST_ALARM_PASSWORD_FILE is not a regular file" >&2
		exit 1
	}
	[ -r "$test_password_file" ] || {
		echo "GTS4LV_TEST_ALARM_PASSWORD_FILE is not readable" >&2
		exit 1
	}
	test_password_mount=(-v "$test_password_file:/tmp/gts4lv-test-alarm-password:ro")
	test_password_env=(-e GTS4LV_TEST_ALARM_PASSWORD=1)
fi

if ! d image inspect "$tag" >/dev/null 2>&1; then
	echo "==> import $tarball as $tag"
	d import --platform linux/arm64 "$tarball" "$tag" >/dev/null
fi

# the packages of scripts/build-packages.sh, when it has been run
pkgs_mount=()
if ls "$root"/out/repo/aarch64/*.pkg.tar.zst >/dev/null 2>&1; then
	pkgs_mount=(-v "$root/out/repo/aarch64:/pkgs:ro")
fi

echo "==> customize ($release)"
d rm -f gts4lv-rootfs-build >/dev/null 2>&1 || true
d run --name gts4lv-rootfs-build --platform linux/arm64 \
	-v "$root/$dev/rootfs/overlay:/overlay:ro" \
	-v "$out/keys:/keys:ro" \
	-v "$modules:/kmods:ro" \
	-v "$out:/out" \
	-v gts4lv-pkgcache:/var/cache/pacman/pkg \
	-v "$root/$dev/rootfs/customize.sh:/customize.sh:ro" \
	-v "$root/$dev/rootfs/packages.txt:/overlay-packages.txt:ro" \
	-v "$root/$dev/rootfs/customize-omarchy.sh:/customize-omarchy.sh:ro" \
	-v "$root/$dev/rootfs/packages-omarchy.txt:/omarchy-packages.txt:ro" \
	-v "$root/$dev/rootfs/omarchy-repos.lock:/omarchy-repos.lock:ro" \
	-v "$root/$dev/rootfs/omarchy-packages.lock:/omarchy-packages.lock:ro" \
	"${test_password_mount[@]}" \
	"${test_password_env[@]}" \
	-e OMARCHY_MOBILE="${OMARCHY_MOBILE:-0}" \
	-e ALARM_BUILD_MIRROR="${ALARM_BUILD_MIRROR:-}" \
	"${pkgs_mount[@]}" \
	"$tag" bash /customize.sh "$release"
d export gts4lv-rootfs-build -o "$out/rootfs.tar"
d rm gts4lv-rootfs-build >/dev/null

echo "==> image of $size_mb MiB"
d run --rm --platform linux/arm64 \
	-v "$out:/out" \
	-v "$root/$dev/rootfs/make-image.sh:/make-image.sh:ro" \
	"$tag" bash /make-image.sh "$size_mb" "$(id -u):$(id -g)"

(cd "$out" && sha256sum rootfs.img rootfs.tar packages.txt > SHA256)
cat "$out/SHA256"
echo "not copied to the tablet"
