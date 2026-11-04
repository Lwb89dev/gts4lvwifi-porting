#!/bin/bash
# Runs once inside the Arch Linux ARM container, as root, to make the build
# image: keyring, base-devel, meson and an unprivileged user for makepkg.
# Called by scripts/build-packages.sh, which commits the container.
set -euo pipefail

# qemu-user has no landlock and the container has no mount table. These two
# settings stay in the build image only; nothing built here ships them.
sed -i 's/^CheckSpace/#CheckSpace/' /etc/pacman.conf
sed -i 's/^\[options\]/[options]\nDisableSandbox/' /etc/pacman.conf

pacman-key --init
pacman-key --populate archlinuxarm
pacman -Syu --noconfirm --needed base-devel meson
useradd -m builder
