#!/usr/bin/env bash
set -euo pipefail

PROFILE=${1:-edge}
JOBS=${JOBS:-$(nproc)}
PKGREV=${PKGREV:-openaios1}

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This script is intended for Debian build hosts." >&2
  exit 1
fi

sudo apt-get update
sudo apt-get install -y build-essential fakeroot bc bison flex libssl-dev libelf-dev dwarves rsync git dpkg-dev debhelper-compat

mkdir -p ~/openaios-kernel-build
cd ~/openaios-kernel-build

apt-get source linux
cd linux-*/

/mnt/data/openaios-kernel/scripts/merge-config.sh /boot/config-$(uname -r) "$PROFILE" .config
make olddefconfig

scripts/config --set-str LOCALVERSION "-openaios-${PROFILE}"
make olddefconfig

fakeroot make -j"$JOBS" bindeb-pkg KDEB_PKGVERSION="$(make kernelversion)-${PKGREV}"

echo "Kernel packages created in: $(pwd)/.."
