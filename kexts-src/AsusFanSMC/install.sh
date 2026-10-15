#!/bin/bash
# AsusFanSMC into OpenCore (one reboot).  sudo bash install.sh   |   ... update (new build of the kext)   |   ... undo
# Off for one boot without undoing: add -asusfanoff (or -asusfanro: read-only) to boot-args.
set -u
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
H=${HACK:-$HOME/hackintosh}/asusfan; K=$H/build/AsusFanSMC.kext; SHA=1739bbe27bb9408e0f6e3a8a5d95d16c475ca4ed504509be6ec392919c5a75ac
die() { echo "STOP: $*"; exit 1; }
PS=$(diskutil info / | awk -F': *' '/APFS Physical Store/{print $2}'); ESP=${PS%s*}s1
[ "$(diskutil info $ESP | awk -F': *' '/Partition Type/{print $2}')" = EFI ] || die "$ESP is not the EFI partition"
diskutil mount $ESP >/dev/null || die "mount $ESP"
MP=$(diskutil info $ESP | sed -n 's/^ *Mount Point: *//p'); C="$MP/EFI/OC/config.plist"; [ -f "$C" ] || die "no $C"
if [ "${1:-}" = undo ]; then
	[ -f "$MP/config.plist.before-asusfan" ] || die "no $MP/config.plist.before-asusfan"
	cp "$MP/config.plist.before-asusfan" "$C" && sync && cmp -s "$MP/config.plist.before-asusfan" "$C" || die "restore config.plist"
	rm -rf "$MP/EFI/OC/Kexts/AsusFanSMC.kext"; diskutil unmount $ESP >/dev/null; echo "DONE (undo). Reboot."; exit 0
fi
[ "$(shasum -a 256 "$K/Contents/MacOS/AsusFanSMC" | cut -d' ' -f1)" = "$SHA" ] || die "$K is not the reviewed build"
if [ "${1:-}" = update ]; then   # already in config.plist: replace only the kext
	[ -d "$MP/EFI/OC/Kexts/AsusFanSMC.kext" ] || die "not installed yet: run without 'update'"
	B=$H/backup-$(date +%Y%m%d-%H%M%S); mkdir -p "$B"; ditto "$MP/EFI/OC/Kexts/AsusFanSMC.kext" "$B/AsusFanSMC.kext"
	rm -rf "$MP/EFI/OC/Kexts/AsusFanSMC.kext"; ditto --norsrc "$K" "$MP/EFI/OC/Kexts/AsusFanSMC.kext" || die "copy the kext (previous one in $B)"
	cmp -s "$K/Contents/MacOS/AsusFanSMC" "$MP/EFI/OC/Kexts/AsusFanSMC.kext/Contents/MacOS/AsusFanSMC" || die "read-back mismatch"
	chown -R asus:staff "$B"; diskutil unmount $ESP >/dev/null || true; echo "DONE (kext updated, previous in $B). Reboot."; exit 0
fi
B=$H/backup-$(date +%Y%m%d-%H%M%S); mkdir -p "$B"
cp "$C" "$B/config.plist" && cp "$C" "$MP/config.plist.before-asusfan" && cmp -s "$C" "$MP/config.plist.before-asusfan" || die "backup (ESP untouched)"
W=$(mktemp); cp "$C" "$W"
python3 -I "$H/oc-add.py" "$W" || die "edit config (ESP untouched)"
plutil -lint "$W" >/dev/null || die "edited config.plist is invalid (ESP untouched)"
rm -rf "$MP/EFI/OC/Kexts/AsusFanSMC.kext"; ditto --norsrc "$K" "$MP/EFI/OC/Kexts/AsusFanSMC.kext" || die "copy the kext"
cp "$W" "$C" && sync && cmp -s "$W" "$C" || die "write config.plist - undo: sudo bash $0 undo"
rm -f "$W"; chown -R asus:staff "$B"; diskutil unmount $ESP >/dev/null || true
echo "DONE. Reboot. Backup: $B + ESP:/config.plist.before-asusfan. Undo: sudo bash $0 undo"
echo "After the reboot:  log show --last boot --predicate 'eventMessage CONTAINS \"AsusFanSMC\"' --style compact | cut -c1-220"
