#!/bin/bash
# Copy the kernel modules of the current build (out/kernel/modules) into the
# running Arch system on the tablet over ssh and run depmod there. The root
# image keeps the modules of the build it was made from; after a kernel
# rebuild with the same release string they must match the kernel in
# recovery, or insmod fails with "disagrees about version of symbol".
# Writes only /usr/lib/modules/<release> on the tablet.
#
#   scripts/sync-modules.sh
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
cd "$root"
host=${TABLET_IP:-172.16.42.1}
key=out/keys/gts4lv_ed25519
release=$(cat out/kernel/include/config/kernel.release)
src=out/kernel/modules/lib/modules/$release

die() { echo "sync-modules: $*" >&2; exit 1; }

sshc() {
	ssh -F /dev/null -i "$key" -o IdentitiesOnly=yes -o BatchMode=yes \
		-o ConnectTimeout=10 -o UserKnownHostsFile=out/keys/known_hosts \
		-o StrictHostKeyChecking=accept-new "root@$host" "$@"
}

[ -d "$src" ] || die "no modules for $release: run scripts/build-kernel.sh"
[ -f "$key" ] || die "no $key: run scripts/build-rootfs.sh first"

# the tablet must be the one that runs this release
running=$(sshc 'uname -r')
[ "$running" = "$release" ] || die "the tablet runs $running, the build is $release"

# root-owned, no group or world write, existing directories left as they are
tar -C "$src" --exclude=./build --exclude=./source --owner=0 --group=0 \
	--numeric-owner --mode='go-w' -cf - . |
	sshc "mkdir -p /usr/lib/modules/$release && tar -C /usr/lib/modules/$release --no-overwrite-dir --no-same-owner -xf - && depmod -a $release"
sshc "ls /usr/lib/modules/$release/kernel | head -3; find /usr/lib/modules/$release -name '*.ko' | wc -l"
echo "synced $release"
