#!/usr/bin/env bash
set -euo pipefail
PROFILE=${1:-edge}
OUT=/etc/modprobe.d/openaios-blacklist.conf

cat > "$OUT" <<'BLACKLIST'
# Open AI OS module blacklist
# Generated for small-footprint AI appliance profile.

# Legacy storage/media/filesystems
blacklist floppy
blacklist pata_acpi
blacklist cramfs
blacklist freevxfs
blacklist hfs
blacklist hfsplus
blacklist jfs
blacklist udf

# Legacy networking
blacklist appletalk
blacklist ipx
blacklist decnet
blacklist atm

# Desktop/consumer peripherals; remove these from enterprise profile if needed.
blacklist bluetooth
blacklist btusb
blacklist uvcvideo
blacklist snd_hda_intel
blacklist snd_usb_audio
BLACKLIST

echo "Installed $OUT"
echo "Review before reboot, especially if this system needs Wi-Fi, Bluetooth, audio, or camera support."
