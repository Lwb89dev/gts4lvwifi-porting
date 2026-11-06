#!/bin/bash
# Runs inside the Arch Linux ARM build container, as root. Builds every
# package under /packages, in dependency order, as the unprivileged user
# "builder" (makepkg refuses to run as root), and writes them with a pacman
# repository database into /out.
# Mounts: /packages (read-only), /out (results), /srccache (sources).
set -euo pipefail

owner=${1:?uid:gid for the results}
# dependency order: qrtr first, the rest need libqrtr. pd-mapper is not built:
# the kernel has its own (CONFIG_QCOM_PD_MAPPER, loaded as qcom_pd_mapper) and
# a second one would answer the same service.
order="qrtr rmtfs tqftpserv hexagonrpc"

say() { printf '==> %s\n' "$*"; }

# Arch Linux ARM's makepkg.conf still names its packages .pkg.tar.xz. The
# repository database and every script here use zstd.
sed -i "s/^PKGEXT=.*/PKGEXT='.pkg.tar.zst'/" /etc/makepkg.conf

install -d -o builder -g builder /work /pkgout /srccache

for name in $order; do
	[ -d "/packages/$name" ] || continue
	say "$name"
	rm -rf "/work/$name"
	cp -r "/packages/$name" "/work/$name"
	chown -R builder:builder "/work/$name"
	# what was built so far is a dependency of what follows
	if ls /pkgout/*.pkg.tar.zst >/dev/null 2>&1; then
		pacman -U --noconfirm --needed /pkgout/*.pkg.tar.zst
	fi
	su builder -c "cd /work/$name && MAKEFLAGS=-j$(nproc) SRCDEST=/srccache PKGDEST=/pkgout makepkg -f --noconfirm --skippgpcheck"
done

say "repository database"
# /out survives builds. Do not leave an older release of the same package
# beside the current one: the rootfs builder installs this directory with one
# pacman -U invocation, where duplicate package targets are an error.
rm -f /out/*.pkg.tar.zst
cp /pkgout/*.pkg.tar.zst /out/
cd /out
rm -f gts4lv.db* gts4lv.files*
repo-add -q gts4lv.db.tar.zst ./*.pkg.tar.zst
chown -R "$owner" /out
ls -l /out
