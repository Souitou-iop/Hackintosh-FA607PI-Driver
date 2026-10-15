#!/bin/bash
# Adds upstream NullMoth's boot-picker entry "Start once without NVIDIA driver" (NullMothSafe.efi, Arguments "once",
# from nvidia-macos-driver app/Resources, sha f99c1fa3) to the OpenCore ESP. Choosing it, pressing Y and then the macOS disk
# (or Recovery) in the SAME picker session starts macOS one time with -nvoff (firmware framebuffer, no NVIDIA driver);
# OpenCore rewrites boot-args at the next start (boot-args is in NVRAM Delete), so the driver is back by itself. It works with
# DisableVariableWrite because the tool writes NVRAM before macOS runs. Only the "once" entry is added - NOT upstream's
# "Remove NVIDIA driver" entry (that one uninstalls the driver).
#   sudo bash add-safe-entry.sh          undo: sudo bash add-safe-entry.sh undo
# Re-run install-rescue.sh afterwards so the rescue config-safe.plist follows the changed config.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ESPUUID=${ESP_UUID:?set ESP_UUID to your EFI partition UUID: diskutil info disk0s1 | grep "Partition UUID"}; PB=/usr/libexec/PlistBuddy
EFI=$HERE/NullMothSafe.efi; ESHA=f99c1fa37693521d414c000059d69f991740bce9d33507da8f7b5113689d3f70
NAME="Start once without NVIDIA driver"; MP=""; T=""
die() { echo "STOP: $*"; exit 1; }
cleanup() { [ -n "$MP" ] && { sync; umount "$MP" 2>/dev/null || diskutil unmount force "$DEV" >/dev/null 2>&1; rmdir "$MP" 2>/dev/null; }; [ -n "$T" ] && rm -f "$T"; }
trap cleanup EXIT
[ "$(id -u)" -eq 0 ] || die "run with sudo"
DEV=$(for d in $(diskutil list | awk '/ EFI /{print $NF}'); do [ "$(diskutil info $d | awk -F': *' '/Partition UUID/{print $2}')" = $ESPUUID ] && { echo $d; break; }; done)
[ -n "$DEV" ] || die "OpenCore ESP ($ESPUUID) not found"
diskutil unmount "$DEV" >/dev/null 2>&1 || true
MP=$(mktemp -d /private/var/tmp/esp.XXXX)
mount -t msdos /dev/$DEV "$MP" 2>/dev/null || mount -F -t msdos /dev/$DEV "$MP" || { rmdir "$MP"; MP=""; die "cannot mount $DEV"; }
C="$MP/EFI/OC/config.plist"; [ -f "$MP/EFI/OC/OpenCore.efi" ] && plutil -lint "$C" >/dev/null || die "unexpected ESP layout"
[ -f "$MP/EFI/OC/rescue/ACTIVE" ] && die "the rescue config is active - restore it first"
idx() { local i=0 p; while p=$($PB -c "Print :Misc:Tools:$i:Path" "$1" 2>/dev/null); do
  [ "$p" = NullMothSafe.efi ] && [ "$($PB -c "Print :Misc:Tools:$i:Arguments" "$1" 2>/dev/null)" = once ] && { echo $i; return; }; i=$((i+1)); done; }
T=$(mktemp /var/tmp/safe-cfg.XXXX); cp "$C" "$T"
if [ "${1:-}" = undo ]; then
  i=$(idx "$T"); [ -n "$i" ] || die "no start-once entry in config.plist"
  $PB -c "Delete :Misc:Tools:$i" "$T" || die "PlistBuddy"
else
  [ "$(shasum -a 256 "$EFI" | cut -d' ' -f1)" = $ESHA ] || die "$EFI is not the expected NullMothSafe.efi"
  [ -n "$(idx "$T")" ] && die "the start-once entry is already there"
  mkdir -p "$MP/EFI/OC/Tools" && cp "$EFI" "$MP/EFI/OC/Tools/NullMothSafe.efi" && sync && cmp -s "$EFI" "$MP/EFI/OC/Tools/NullMothSafe.efi" || die "copy to ESP failed"
  $PB -c "Print :Misc:Tools" "$T" >/dev/null 2>&1 || $PB -c "Add :Misc:Tools array" "$T"
  plutil -insert Misc.Tools -json "{\"Arguments\":\"once\",\"Auxiliary\":false,\"Comment\":\"NullMoth: start macOS once without the NVIDIA driver\",\"Enabled\":true,\"Flavour\":\"Auto\",\"FullNvramAccess\":true,\"Name\":\"$NAME\",\"Path\":\"NullMothSafe.efi\",\"RealPath\":false,\"TextMode\":true}" -append "$T" || die "plutil insert"
fi
plutil -lint "$T" >/dev/null || die "edited config does not parse (nothing written)"
BK="$HERE/backup-config-safeentry-$(date +%Y%m%d-%H%M%S).plist"; cp "$C" "$BK" || die "backup"
cp "$T" "$C" && sync && cmp -s "$T" "$C" || { cp "$BK" "$C"; die "write/read-back failed - previous config put back"; }
echo "OK: config.plist written (previous: $BK)"
[ "${1:-}" = undo ] && echo "Start-once entry removed (Tools/NullMothSafe.efi left on the ESP, harmless)." \
  || echo "Boot picker now has \"$NAME\". Use: choose it, press Y, then choose macOS (or Recovery) in the same picker."
echo "Next: sudo bash $HERE/install-rescue.sh   (refresh the rescue config)"
