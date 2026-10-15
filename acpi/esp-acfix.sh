#!/bin/bash
# Charger detection (ExternalConnected = No; FileVault encryption paused at 0%, so FileVault cannot be turned off either).
# The firmware's \_SB.PCI0.SBRG.ADP0._PSR reads the EC fine but then calls AMD's ALIB(1, ...), which fails on macOS
# (AE_AML_NO_RETURN_VALUE) and aborts _PSR every time. Reproduced with ACPICA acpiexec on this machine's own tables;
# with the fix, _PSR returns the EC value under _OSI("Darwin") and still runs the original method for other systems.
# OpenCore changes (EFI/OC/config.plist, backup kept):
#   ACPI > Add    SSDT-ADP0.aml (new _PSR without ALIB on macOS)
#   ACPI > Patch  DSDT: ADP0's _PSR -> XPSR (14 48 07 "_PSR" 00, the only _PSR in this DSDT, Count 1)
#   Misc > Debug  SysReport -> false (the ACPI dump it was enabled for is done)
#   sudo bash esp-acfix.sh   then reboot   |   sudo bash esp-acfix.sh undo   then reboot
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
H=${HACK:-$HOME/hackintosh}/acfix; SSDT=$H/SSDT-ADP0.aml; SSDTSHA=$(shasum -a 256 "$SSDT" | cut -c1-16)
die() { echo "STOP: $*"; diskutil unmount "${ESP:-x}" >/dev/null 2>&1; exit 1; }
PS=$(diskutil info / | awk -F': *' '/APFS Physical Store/{print $2}'); ESP=${PS%s*}s1
[ "$(diskutil info $ESP | awk -F': *' '/Partition Type/{print $2}')" = EFI ] || die "$ESP is not an EFI partition"
diskutil mount $ESP >/dev/null || die "mount $ESP"
MP=$(mount | awk -v e=$ESP '$1=="/dev/"e{print $3}'); C="$MP/EFI/OC/config.plist"; [ -f "$C" ] || die "ESP not mounted ($MP)"

if [ "${1:-}" = undo ]; then
  BK=$(ls -d $H/backup-* 2>/dev/null | sort | tail -1)
  [ -n "$BK" ] && [ -f "$BK/config.plist" ] || die "no backup in $H/backup-*"
  cp "$BK/config.plist" "$C" && sync && cmp -s "$BK/config.plist" "$C" || die "restore failed"
  rm -f "$MP/EFI/OC/ACPI/SSDT-ADP0.aml"
  diskutil unmount $ESP >/dev/null 2>&1; echo "DONE (undo, config from $BK). Reboot."; exit 0
fi

BK=$H/backup-$(date +%Y%m%d-%H%M%S); mkdir -p "$BK"; cp "$C" "$BK/config.plist" || die "backup"
cp "$C" "$MP/config.plist.before-acfix" || die "rescue copy on the ESP"
cp "$SSDT" "$MP/EFI/OC/ACPI/SSDT-ADP0.aml" || die "SSDT copy"
T=$(mktemp); /usr/bin/python3 -I - "$C" "$T" <<'EOF' || die "config edit"
import plistlib, sys
c = plistlib.load(open(sys.argv[1], 'rb'))
a = c['ACPI']
if not any(x.get('Path') == 'SSDT-ADP0.aml' for x in a['Add']):
    a['Add'].append({'Comment': 'AC adapter: ADP0._PSR without the ALIB call that fails on macOS (renamed original = XPSR)',
                     'Enabled': True, 'Path': 'SSDT-ADP0.aml'})
find = bytes.fromhex('1448075f50535200')
if not any(p.get('Find') == find for p in a['Patch']):
    a['Patch'].append({'Base': '', 'BaseSkip': 0, 'Comment': 'ADP0: _PSR to XPSR (SSDT-ADP0)', 'Count': 1, 'Enabled': True,
                       'Find': find, 'Limit': 0, 'Mask': b'', 'OemTableId': b'\0\0\0\0\0\0\0\0', 'Replace': bytes.fromhex('1448075850535200'),
                       'ReplaceMask': b'', 'Skip': 0, 'TableLength': 0, 'TableSignature': b'DSDT'})
c['Misc']['Debug']['SysReport'] = False
plistlib.dump(c, open(sys.argv[2], 'wb'))
EOF
plutil -lint "$T" >/dev/null || die "edited config does not lint"
cp "$T" "$C" && sync && cmp -s "$T" "$C" || die "write failed - restore $BK/config.plist"
echo "== ESP: SSDT-ADP0.aml ($SSDTSHA) added, _PSR->XPSR patch added, SysReport off (backup $BK, also $MP/config.plist.before-acfix)"
diskutil unmount $ESP >/dev/null 2>&1
echo "DONE. Reboot, then: pmset -g batt  (with the charger in: 'AC Power')"
echo "Undo (no other arguments needed): sudo bash $0 undo   then reboot"
