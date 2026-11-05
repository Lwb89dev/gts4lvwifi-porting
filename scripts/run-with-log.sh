#!/bin/bash
# Run one command on the tablet over ssh while its kernel log is streamed to
# the PC, then sample the tablet for a while. For a step that may reset it: the
# last lines that reached the PC are what is left of the log, and a lost
# connection is reported. Writes only under the output directory on the PC.
#
#   scripts/run-with-log.sh <dir> '<command on the tablet>' [seconds]
#
# <dir>/dmesg.log   the kernel log, streamed
# <dir>/samples.log what the command printed, then one line every 4 s
# Exits 2 if the connection was lost while sampling.
set -uo pipefail

root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
cd "$root" || exit 1
host=${TABLET_IP:-172.16.42.1}
key=out/keys/gts4lv_ed25519

[ $# -ge 2 ] || { sed -n '2,13p' "$0" >&2; exit 1; }
dir=$1
cmd=$2
secs=${3:-60}
[ -f "$key" ] || { echo "run-with-log: no $key" >&2; exit 1; }

tablet() {
	ssh -F /dev/null -i "$key" -o IdentitiesOnly=yes -o BatchMode=yes \
		-o ConnectTimeout=5 -o ServerAliveInterval=2 -o ServerAliveCountMax=2 \
		-o UserKnownHostsFile=out/keys/known_hosts "root@$host" "$@"
}

mkdir -p "$dir"
: > "$dir/dmesg.log"
: > "$dir/samples.log"

tablet 'dmesg -w' >> "$dir/dmesg.log" 2>&1 &
stream=$!
trap 'kill $stream 2>/dev/null' EXIT
sleep 2

echo "$(date +%T) run: $cmd" | tee -a "$dir/samples.log"
tablet "$cmd" 2>&1 | tee -a "$dir/samples.log"

end=$(( $(date +%s) + secs ))
status=0
while [ "$(date +%s)" -lt "$end" ]; do
	# single quotes on purpose: the substitutions run on the tablet
	# shellcheck disable=SC2016
	# the remoteproc numbers change from boot to boot: ask by name
	out=$(tablet 'echo "up=$(cut -d. -f1 /proc/uptime) $(/usr/local/sbin/gts4lv-dsp status modem | cut -d" " -f1-2 | tr "\n" " ")$(/usr/local/sbin/gts4lv-dsp status adsp | cut -d" " -f1-2 | tr "\n" " ")"' 2>&1 | tail -1)
	echo "$(date +%T) $out" | tee -a "$dir/samples.log"
	case $out in
	up=*) ;;
	*)
		echo "$(date +%T) CONNECTION LOST" | tee -a "$dir/samples.log"
		status=2
		break
		;;
	esac
	sleep 4
done
echo "done"
exit "$status"
