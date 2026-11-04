#!/bin/sh
# Download and verify the Arch Linux ARM aarch64 root tarball under src/alarm/.
# Checks the MD5 file and the detached signature against the pinned Arch
# Linux ARM build key. Needs curl, gpg and md5sum. Writes only to src/alarm/
# (gitignored) and to a temporary GNUPGHOME. Does not touch the tablet and
# does not extract the archive.
#
#   scripts/fetch-alarm-rootfs.sh
#
# Override ALARM_DIR, ALARM_URL, ALARM_KEYSERVER. The "latest" tarball moves,
# so the sha256 that was verified is written to src/alarm/SHA256; copy it to
# rootfs.lock when a build must be reproducible.
set -eu

root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
dest=${ALARM_DIR:-$root/src/alarm}
url=${ALARM_URL:-http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz}
# Arch Linux ARM Build System <builder@archlinuxarm.org>, same pin as
# omarchy-mobile tools/lib/alarm.sh.
key=68B3537F39A313B3E574D06777193F152BDBE6A6
keyserver=${ALARM_KEYSERVER:-hkps://keyserver.ubuntu.com}
name=${url##*/}
tarball=$dest/$name

for tool in curl gpg md5sum sha256sum; do
	if ! command -v "$tool" >/dev/null 2>&1; then
		echo "missing tool: $tool" >&2
		exit 1
	fi
done

mkdir -p "$dest"

fetch_missing() {
	if [ -f "$tarball" ] && [ "${ALARM_REFRESH:-}" != 1 ]; then
		echo "have $tarball, set ALARM_REFRESH=1 to fetch again"
		return 0
	fi
	echo "downloading $url"
	curl -fL --retry 3 -C - -o "$tarball.part" "$url"
	curl -fL --retry 3 -o "$tarball.md5" "$url.md5"
	curl -fL --retry 3 -o "$tarball.sig" "$url.sig"
	mv "$tarball.part" "$tarball"
}

check_md5() {
	(cd "$dest" && md5sum -c --quiet "$name.md5") || {
		echo "MD5 mismatch for $tarball" >&2
		return 1
	}
	echo "md5 ok"
}

check_signature() {
	gnupg=$(mktemp -d)
	chmod 700 "$gnupg"
	trap 'rm -rf "$gnupg"' EXIT
	gpg --homedir "$gnupg" --batch --quiet --keyserver "$keyserver" \
		--recv-keys "$key"
	status=$(gpg --homedir "$gnupg" --batch --status-fd 1 \
		--verify "$tarball.sig" "$tarball" 2>/dev/null) || {
		echo "signature check failed for $tarball" >&2
		return 1
	}
	if ! echo "$status" | grep -E '^\[GNUPG:\] VALIDSIG ' | grep -q "$key"; then
		echo "valid signature, but not from the pinned key $key" >&2
		return 1
	fi
	echo "signature ok, key $key"
}

fetch_missing
check_md5
check_signature
sum=$(sha256sum "$tarball" | cut -d' ' -f1)
echo "$sum  $name" > "$dest/SHA256"
echo "sha256 $sum"
echo "size   $(stat -c %s "$tarball") bytes"
