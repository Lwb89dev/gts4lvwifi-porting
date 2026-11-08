#!/bin/bash
# Build M8's first Omarchy Mobile image separately from the known-good v6
# bring-up image. This only builds and verifies files on the PC.
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
cd "$root"

ROOTFS_VARIANT=omarchy OMARCHY_MOBILE=1 ROOTFS_MB=${ROOTFS_MB:-12288} \
	scripts/build-rootfs.sh
verify_args=()
if [ -n "${GTS4LV_TEST_ALARM_PASSWORD_FILE:-}" ]; then
	verify_args=(--allow-test-alarm-password)
fi
scripts/verify-rootfs.py "${verify_args[@]}" out/rootfs-omarchy/rootfs.tar
scripts/verify-omarchy-rootfs.py out/rootfs-omarchy/rootfs.tar \
	out/rootfs-omarchy/packages.txt
