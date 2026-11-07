#!/bin/bash
# Add the signed Omarchy and Omarchy Mobile repositories and install the first
# M8 userspace without enabling a graphical session. This runs only inside the
# rootfs build container, never on the tablet.
set -euo pipefail

lock=${1:?repository lock file}
packages=${2:?package list}
pinned=${3:?pinned package lock file}

say() { printf '==> %s\n' "$*"; }
die() { printf 'customize-omarchy: %s\n' "$*" >&2; exit 1; }

key_fingerprint() {
	local pkg=$1 name=$2 key
	key="usr/share/pacman/keyrings/${name%-keyring}.gpg"
	bsdtar -xOf "$pkg" "$key" |
		gpg --show-keys --with-colons 2>/dev/null |
		awk -F: '$1 == "fpr" && !found { value = $10; found = 1 } END { print value }'
}

bootstrap_keyrings() {
	local name url sha fingerprint pkg got
	while read -r name url sha fingerprint extra; do
		case $name in ""|'#'*) continue ;; esac
		[ -z "${extra:-}" ] || die "bad line in $lock for $name"
		pkg="/tmp/$name.pkg.tar.zst"
		curl --fail --location --proto '=https' --tlsv1.2 \
			--connect-timeout 15 --max-time 120 --output "$pkg" "$url"
		echo "$sha  $pkg" | sha256sum -c --quiet - || die "$name checksum mismatch"
		got=$(key_fingerprint "$pkg" "$name")
		[ "$got" = "$fingerprint" ] || die "$name fingerprint $got, expected $fingerprint"
		pacman -U --noconfirm "$pkg"
	done < "$lock"
	pacman-key --populate omarchy omamobile
}

add_repositories() {
	local tmp
	tmp=$(mktemp)
	awk '
		/^\[core\]$/ && !done {
			print "[omamobile]"
			print "Server = https://pkgs.omamobile.org/stable/$arch"
			print ""
			print "[omarchy]"
			print "Server = https://pkgs.omarchy.org/stable/$arch"
			print ""
			done = 1
		}
		{ print }
	' /etc/pacman.conf > "$tmp"
	install -m 644 "$tmp" /etc/pacman.conf
	rm -f "$tmp"
}

install_pinned_packages() {
	local name version sha url extra pkg got i
	local files=() expected_names=() expected_versions=()
	while read -r name version sha url extra; do
		case $name in ""|'#'*) continue ;; esac
		[ -z "${extra:-}" ] || die "bad line in $pinned for $name"
		[[ $sha =~ ^[0-9a-f]{64}$ ]] || die "bad checksum in $pinned for $name"
		case $url in https://*.pkg.tar.zst) ;; *) die "bad package URL in $pinned for $name" ;; esac
		pkg="/tmp/${url##*/}"
		curl --fail --location --proto '=https' --tlsv1.2 \
			--connect-timeout 15 --max-time 300 --output "$pkg" "$url"
		curl --fail --location --proto '=https' --tlsv1.2 \
			--connect-timeout 15 --max-time 120 --output "$pkg.sig" "$url.sig"
		echo "$sha  $pkg" | sha256sum -c --quiet - || die "$name checksum mismatch"
		pacman-key --verify "$pkg.sig" "$pkg" >/dev/null 2>&1 ||
			die "$name package signature is not trusted"
		files+=("$pkg")
		expected_names+=("$name")
		expected_versions+=("$version")
	done < "$pinned"
	[ "${#files[@]}" -gt 0 ] || die "empty pinned package lock"
	pacman -U --noconfirm --needed "${files[@]}"
	for ((i = 0; i < ${#expected_names[@]}; i++)); do
		got=$(pacman -Q "${expected_names[$i]}" | awk '{ print $2 }')
		[ "$got" = "${expected_versions[$i]}" ] ||
			die "${expected_names[$i]} $got, expected ${expected_versions[$i]}"
	done
}

protect_pinned_omarchy() {
	local file=$1 tmp
	tmp=$(mktemp)
	awk '
		/^\[options\]$/ {
			print
			print "# Omarchy Mobile patches target the signed, pinned 4.0.6 packages."
			print "IgnorePkg = omarchy omarchy-settings"
			next
		}
		{ print }
	' "$file" > "$tmp"
	install -m 644 "$tmp" "$file"
	rm -f "$tmp"
}

protect_arch_graphics() {
	local file=$1 tmp
	tmp=$(mktemp)
	awk '
		/^\[options\]$/ {
			print
			print "# Keep the Arch Linux ARM Freedreno and Hyprland 0.57 ABI stack."
			print "IgnorePkg = mesa vulkan-mesa-implicit-layers vulkan-panfrost aquamarine hyprtoolkit hyprland-guiutils xdg-desktop-portal-hyprland"
			next
		}
		{ print }
	' "$file" > "$tmp"
	install -m 644 "$tmp" "$file"
	rm -f "$tmp"
}

check_repo_package() {
	local repo=$1 name=$2 selected
	# Query the qualified target. An older package with the same name may
	# legitimately exist in a higher-priority repository; the explicit package
	# list below must still select the requested repository.
	selected=$(pacman -Sp --print-format '%r' "$repo/$name" 2>/dev/null | tail -1)
	[ "$selected" = "$repo" ] || die "$name resolves from [$selected], expected [$repo]"
}

check_extra_version() {
	local name=$1 installed available
	installed=$(pacman -Q "$name" | awk '{ print $2 }')
	available=$(pacman -Sl extra | awk -v name="$name" \
		'$2 == name && !found { value = $3; found = 1 } END { print value }')
	[ "$installed" = "$available" ] ||
		die "installed $name $installed is not [extra] version $available"
}

check_freedreno() {
	local implicit
	check_extra_version mesa
	pacman -Q vulkan-freedreno libglvnd >/dev/null
	[ -e /usr/lib/dri/msm_dri.so ] || die "Mesa has no Freedreno msm_dri.so"
	[ -e /usr/lib/libvulkan_freedreno.so ] || die "vulkan-freedreno is missing"
	[ -e /usr/share/vulkan/icd.d/freedreno_icd.json ] || die "Turnip ICD is missing"
	if pacman -Q vulkan-panfrost >/dev/null 2>&1; then
		die "the Mali-only vulkan-panfrost package was installed"
	fi
	if implicit=$(pacman -Qq vulkan-mesa-implicit-layers 2>/dev/null); then
		check_extra_version "$implicit"
	fi
}

install_omarchy_base() {
	local list package skipped targets=() unavailable=()
	list=/usr/share/omarchy/install/omarchy-base.packages
	[ -f "$list" ] || die "Omarchy package list is missing: $list"
	# Match Omarchy Mobile's own rootfs builder. qemu-user-static-binfmt is a
	# laptop facility; titlebars is still pinned to Hyprland 0.56 / ABI 14 and
	# cannot coexist with the mobile Hyprland 0.57 / ABI 15 stack.
	skipped=' qemu-user-static-binfmt omarchy-hyprland-titlebars '
	while read -r package; do
		case $package in ""|'#'*) continue ;; esac
		package=${package%%#*}
		package=${package//[[:space:]]/}
		[ -n "$package" ] || continue
		case $skipped in *" $package "*) continue ;; esac
		# Explicit mobile targets are installed before the generic Omarchy base
		# list. Do not let an unqualified duplicate from a higher-priority repo
		# replace or downgrade one of those packages.
		if pacman -Q "$package" >/dev/null 2>&1; then
			continue
		fi
		if pacman -Sp --print-format '%n' "$package" >/dev/null 2>&1; then
			targets+=("$package")
		else
			unavailable+=("$package")
		fi
	done < "$list"
	say "Omarchy base packages: ${#targets[@]} available, ${#unavailable[@]} unavailable"
	[ "${#unavailable[@]}" -eq 0 ] || say "not built for aarch64: ${unavailable[*]}"
	pacman -S --noconfirm --needed "${targets[@]}"
}

mapfile -t wanted < <(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$packages")
[ "${#wanted[@]}" -gt 0 ] || die "empty package list"

bootstrap_keyrings
add_repositories

# pacman under qemu-user cannot use Landlock and cannot see the container's
# mount table for CheckSpace. Keep these two build-only changes out of the
# image by restoring the canonical configuration after the transaction.
cp /etc/pacman.conf /tmp/pacman.omarchy.conf
sed -i 's/^CheckSpace/#CheckSpace/' /etc/pacman.conf
sed -i 's/^\[options\]/[options]\nDisableSandbox\nDisableDownloadTimeout/' /etc/pacman.conf

pacman -Sy --noconfirm

# Omarchy stable still carries the Hyprland 0.56 / Aquamarine ABI 14 stack,
# while Omarchy Mobile's patched Hyprland 0.57 needs ABI 15. Install the
# coherent current stack explicitly from Arch extra, then protect it from a
# later replacement by the older [omarchy] packages.
abi_packages=(aquamarine hyprtoolkit hyprland-guiutils xdg-desktop-portal-hyprland)
abi_targets=()
for package in "${abi_packages[@]}"; do abi_targets+=("extra/$package"); done
pacman -S --noconfirm --needed "${abi_targets[@]}"
for package in "${abi_packages[@]}"; do check_extra_version "$package"; done
protect_arch_graphics /etc/pacman.conf
protect_arch_graphics /tmp/pacman.omarchy.conf

check_repo_package omamobile hyprland
check_freedreno
install_pinned_packages
protect_pinned_omarchy /etc/pacman.conf
protect_pinned_omarchy /tmp/pacman.omarchy.conf
pacman -S --noconfirm --needed "${wanted[@]}"
/usr/bin/omamobile-omarchy-patches apply --hook
install_omarchy_base

cp /tmp/pacman.omarchy.conf /etc/pacman.conf
check_freedreno
pacman -Q omarchy omamobile-omarchy omamobile-shell hyprland

# ALARM already ships the alarm account, so installing Omarchy cannot seed it
# through useradd(8). Copy the package-owned skeleton now; the runtime
# provisioners then perform only the per-user steps that require a session bus.
say "seed Omarchy configuration for alarm"
cp -a /etc/skel/. /home/alarm/
# The stock lock is too aggressive while bringing up a tablet. Ten minutes
# remains finite; Stay awake is still available as a quick toggle. Match the
# current nested idle object as well as older one-line profiles.
sed -Ei 's/"lock":[[:space:]]*[0-9]+/"lock": 600/' /home/alarm/.config/omarchy/shell.json
grep -q '"lock": 600' /home/alarm/.config/omarchy/shell.json ||
	die "could not set the Omarchy lock timeout"
# Keep device calibration outside the package-owned user files, then load it
# last so Omarchy defaults cannot overwrite the touchscreen mapping.
sed -i '$a dofile("/usr/lib/gts4lv/hypr/tablet.lua")' /home/alarm/.config/hypr/hyprland.lua
chown -R alarm:alarm /home/alarm

# The shell's rotation tile expects this exact unit name. Enable the
# device-specific implementation globally so it follows alarm's graphical
# session from the first login; the tile can still lock it via its state file.
systemctl --global enable omamobile-autorotate.service
systemctl --global enable gts4lv-initial-speaker-volume.service
systemctl enable gts4lv-mark-poweroff.service

# The tablet has now completed the observable bring-up test. Start the same
# UWSM-managed Omarchy session automatically on every boot.
systemctl enable gts4lv-audio.service sddm.service
[ -L /etc/systemd/system/display-manager.service ] ||
	die "SDDM did not create display-manager.service"
/usr/bin/omamobile-omarchy-patches verify

say "Omarchy Mobile installed; SDDM autologin enabled"
