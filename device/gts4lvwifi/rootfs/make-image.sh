#!/bin/bash
# Runs inside the Arch Linux ARM container, as root, with /out mounted.
# Turns /out/rootfs.tar (a docker export) into the ext4 image /out/rootfs.img.
# $1 is the image size in MiB, $2 the owner uid:gid of the result.
set -euo pipefail

size_mb=${1:?size in MiB}
owner=${2:?uid:gid}

say() { printf '==> %s\n' "$*"; }

say "unpack"
mkdir /stage
bsdtar -xpf /out/rootfs.tar -C /stage --same-owner --xattrs

say "remove what docker added"
rm -f /stage/.dockerenv
rmdir /stage/overlay /stage/keys /stage/kmods /stage/out 2>/dev/null || true
rm -f /stage/etc/hostname /stage/etc/hosts /stage/etc/resolv.conf
echo gts4lvwifi > /stage/etc/hostname
cat > /stage/etc/hosts <<'EOF'
127.0.0.1 localhost
::1       localhost
EOF
ln -s ../run/systemd/resolve/stub-resolv.conf /stage/etc/resolv.conf

say "ext4 image of $size_mb MiB"
rm -f /out/rootfs.img
truncate -s "${size_mb}M" /out/rootfs.img
mke2fs -q -F -t ext4 -L gts4lv-root -m 1 -d /stage /out/rootfs.img
e2fsck -fn /out/rootfs.img
chown "$owner" /out/rootfs.img /out/rootfs.tar /out/packages.txt
ls -l /out/rootfs.img
