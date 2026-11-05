#!/bin/bash
# Smoke test of the Arch Linux ARM system on the tablet, over the USB cable:
# systemd state, the clock, then the package manager end to end (database sync,
# install of one small package, integrity check). Changes the tablet's clock
# and installs one package in its rootfs; nothing else.
#
#   scripts/arch-smoke.sh [package]      default package: tree
#
# Needs the tablet running Arch (sshd on 172.16.42.1, the key from
# scripts/build-rootfs.sh). Starts scripts/usb-http-proxy.py for the duration
# and stops it again.
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
cd "$root"
host=${TABLET_IP:-172.16.42.1}
# the host's address on the cable is whatever the tablet's DHCP gave it
bind=${HOST_USB_IP:-$(ip -4 route get "$host" 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i == "src") print $(i + 1) }')}
[ -n "$bind" ] || { echo "arch-smoke: no route to $host" >&2; exit 1; }
pkg=${1:-tree}
key=out/keys/gts4lv_ed25519
proxy_pid=

die() { echo "arch-smoke: $*" >&2; exit 1; }

sshc() {
	ssh -F /dev/null -i "$key" -o IdentitiesOnly=yes -o BatchMode=yes \
		-o ConnectTimeout=10 -o UserKnownHostsFile=out/keys/known_hosts \
		-o StrictHostKeyChecking=accept-new "root@$host" "$@"
}

cleanup() {
	[ -z "$proxy_pid" ] || kill "$proxy_pid" 2>/dev/null || true
}
trap cleanup EXIT

[ -f "$key" ] || die "no $key: run scripts/build-rootfs.sh first"

echo "== system"
# single quotes on purpose: the command substitutions run on the tablet
# shellcheck disable=SC2016
sshc 'echo "state: $(systemctl is-system-running)"; echo "failed: $(systemctl --failed --no-legend | wc -l)"'

echo "== clock (its RTC cannot be set: it boots in 1977 and pacman would reject the signatures)"
sshc "date -u -s @$(date -u +%s) >/dev/null && date -u"

echo "== proxy on $bind"
python3 -I scripts/usb-http-proxy.py --bind "$bind" > out/usb-http-proxy.log 2>&1 &
proxy_pid=$!
sleep 1
kill -0 "$proxy_pid" 2>/dev/null || die "the proxy did not start: $(cat out/usb-http-proxy.log)"

echo "== pacman -Sy"
sshc "http_proxy=http://$bind:3128 pacman -Sy --noconfirm"
echo "== pacman -S $pkg"
sshc "http_proxy=http://$bind:3128 pacman -S --needed --noconfirm $pkg"
echo "== check"
sshc "pacman -Q $pkg && pacman -Qk $pkg"
echo "ok: the package manager works over USB. Requests logged in out/usb-http-proxy.log"
