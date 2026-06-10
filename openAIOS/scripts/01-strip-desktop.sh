#!/usr/bin/env bash
# 01-strip-desktop.sh — Remove desktop environments, printing, bluetooth,
# and other components unnecessary for an AI appliance.
# Target: Ubuntu/Debian-based server. Run as root.

set -euo pipefail

echo "==> Stripping desktop and GUI components..."

DESKTOP_PKGS=(
    gnome-shell gnome-session gnome-terminal gdm3
    kde-plasma-desktop sddm
    xorg xserver-xorg x11-common x11-utils x11-xserver-utils
    wayland-protocols xwayland
    lightdm slim
    nautilus thunar dolphin
    gedit kate
    firefox chromium-browser
    libreoffice*
    evince eog totem
    cheese shotwell
    gnome-calculator gnome-calendar gnome-contacts gnome-weather
    gnome-maps gnome-music gnome-photos
    ubuntu-desktop ubuntu-desktop-minimal
)

PRINT_PKGS=(
    cups cups-browsed cups-daemon cups-client
    printer-driver-* foomatic-*
    system-config-printer
)

BLUETOOTH_PKGS=(
    bluez bluez-tools bluetooth
    pulseaudio-module-bluetooth
)

SOUND_PKGS=(
    pulseaudio pipewire pipewire-pulse
    alsa-utils alsa-base
)

for group in DESKTOP_PKGS PRINT_PKGS BLUETOOTH_PKGS SOUND_PKGS; do
    declare -n pkgs="$group"
    echo "  Removing $group..."
    apt-get purge -y --auto-remove "${pkgs[@]}" 2>/dev/null || true
done

apt-get autoremove -y
apt-get clean

systemctl set-default multi-user.target 2>/dev/null || true

echo "==> Desktop components stripped. System set to multi-user (CLI) mode."
