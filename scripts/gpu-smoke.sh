#!/bin/bash
# Verify that the tablet renders with Freedreno/Turnip, never llvmpipe.
# Use --start-display after a boot to load msm and create renderD128.
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
cd "$root"
host=${TABLET_IP:-172.16.42.1}
key=out/keys/gts4lv_ed25519
start=0
[ "${1:-}" != --start-display ] || start=1
[ $# -le "$start" ] || { echo "usage: $0 [--start-display]" >&2; exit 1; }

tablet() {
	ssh -F /dev/null -i "$key" -o IdentitiesOnly=yes -o BatchMode=yes \
		-o ConnectTimeout=8 -o UserKnownHostsFile=out/keys/known_hosts \
		"root@$host" "$@"
}

if [ "$start" = 1 ]; then
	tablet gts4lv-display start
fi
tablet 'test -c /dev/dri/renderD128' || {
	echo "gpu-smoke: no renderD128; run with --start-display after boot" >&2
	exit 1
}

egl=$(tablet "timeout 20 runuser -u alarm -- env XDG_RUNTIME_DIR=/run/user/1000 eglinfo -B -p surfaceless")
printf '%s\n' "$egl"
grep -q 'OpenGL core profile vendor: freedreno' <<<"$egl"
grep -q 'OpenGL core profile renderer: FD615' <<<"$egl"
if grep -qi llvmpipe <<<"$egl"; then
	echo "gpu-smoke: software rendering detected" >&2
	exit 1
fi

vk=$(tablet "timeout 25 runuser -u alarm -- env XDG_RUNTIME_DIR=/run/user/1000 vulkaninfo --summary" 2>&1)
printf '%s\n' "$vk"
grep -q 'deviceName.*Turnip Adreno (TM) 615' <<<"$vk"
grep -q 'driverName.*turnip Mesa driver' <<<"$vk"
echo "gpu-smoke: PASS (Freedreno FD615, Turnip Adreno 615)"
