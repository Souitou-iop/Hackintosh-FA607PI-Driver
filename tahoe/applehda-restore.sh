#!/bin/bash
# macOS 26 only: put back macOS 15.8.1's AppleHDA.kext (complete, with executables, from the 15.8.1 KDK - the copy in a
# running system's /System/Library/Extensions has no executables, they live in the kernel collection) into the system
# volume, rebuild the system kernel collections and boot a new snapshot. AppleALC (already in OpenCore) then patches it
# as on macOS 15. Needs SIP bits 0x803 (this Mac has 0xA43) and AMFIPass (in OpenCore). A macOS update replaces the
# system volume: run this again after each update.
#   sudo bash applehda-restore.sh          then reboot
#   sudo bash applehda-restore.sh undo     boot Apple's last sealed snapshot again (no AppleHDA), then reboot
set -u
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
die() { echo "STOP: $*"; exit 1; }
if [ "${1:-}" = undo ]; then bless --mount / --bootefi --last-sealed-snapshot || die "bless --last-sealed-snapshot"; echo "DONE (undo). Reboot."; exit 0; fi
[ "$(sw_vers -productVersion | cut -d. -f1)" = 26 ] || die "this is for macOS 26"
SRC=$(cd "$(dirname "$0")" && pwd)/AppleHDA.kext
[ -f "$SRC/Contents/MacOS/AppleHDA" ] && [ -f "$SRC/Contents/PlugIns/AppleHDAController.kext/Contents/MacOS/AppleHDAController" ] \
	&& [ -f "$SRC/Contents/PlugIns/IOHDAFamily.kext/Contents/MacOS/IOHDAFamily" ] || die "$SRC is not the complete KDK AppleHDA.kext"
CSR=$(nvram 7C436110-AB2A-4BBB-A880-FE41995C9F82:csr-active-config 2>/dev/null | awk '{print $2}')
csrutil status | grep -qi 'disabled\|unknown\|custom' || die "SIP is fully on - csr-active-config must allow 0x803 (now: $CSR)"
DEV=$(diskutil info / | awk -F': *' '/Device Node/{print $2}'); DEV=${DEV%s[0-9]}   # the snapshot's parent volume
[ -b "$DEV" ] || die "cannot find the system volume ($DEV)"
M=/System/Volumes/Update/mnt1; mkdir -p "$M"
mount | grep -q " $M " || mount -o nobrowse -t apfs "$DEV" "$M" || die "mount $DEV read-write at $M"
[ -d "$M/System/Library/Extensions" ] || die "$M is not a system volume"
[ -e "$M/System/Library/Extensions/AppleHDA.kext/Contents/MacOS/AppleHDA" ] && echo "   AppleHDA already on the volume - refreshing it"
rm -rf "$M/System/Library/Extensions/AppleHDA.kext"
ditto "$SRC" "$M/System/Library/Extensions/AppleHDA.kext" && chown -R root:wheel "$M/System/Library/Extensions/AppleHDA.kext" \
	&& chmod -R 755 "$M/System/Library/Extensions/AppleHDA.kext" || die "copy AppleHDA.kext"
echo "== rebuilding the kernel collections of $M"
kmutil install --volume-root "$M" --update-all --allow-missing-kdk || die "kmutil install failed - nothing is blessed; reboot to drop the change"
kmutil inspect -V release --no-header -B "$M/System/Library/KernelCollections/BootKernelExtensions.kc" 2>/dev/null | grep -q . || true
kmutil inspect --no-header -S "$M/System/Library/KernelCollections/SystemKernelExtensions.kc" 2>/dev/null | grep -q 'com.apple.driver.AppleHDA ' \
	|| die "AppleHDA is not in the rebuilt system collection - nothing is blessed; reboot to drop the change"
bless --folder "$M/System/Library/CoreServices" --bootefi --create-snapshot || die "bless --create-snapshot failed"
echo; echo "DONE. Reboot; then: kextstat | grep -i hda   (AppleHDA, AppleHDAController, IOHDAFamily). Undo: sudo bash $0 undo"
