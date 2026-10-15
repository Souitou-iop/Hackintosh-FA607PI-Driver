#!/bin/bash
# macOS 26.7.1 post-upgrade fixes, one reboot (2026-10-14):
#   1. Built-in audio: AppleHDA (15.8.1 KDK 24H32 build, ~/hackintosh/tahoe/AppleHDA.kext) into
#      /Library/Apple/System/Library/Extensions + auxiliary kernel collection with -b for the Apple bundle ids
#      (friend's fix 33 recipe; the sealed system volume is not touched).
#   2. AACELDOff 1.1.0 on the ESP (MaxKernel lifted): AirPods AAC-ELD patch for the 26 bluetoothd + the AppleHDA
#      OSKextRequestResource answer that 1. needs (friend's BTLEFix 1.0.6 part 5).
#   3. GPU sensors: NVAccel = our 1.15.0 macOS 26 build with GPU temperature/utilisation (gpusens/out115/26).
#   4. Boot picker "Start once without NVIDIA driver" (upstream NullMothSafe.efi, Arguments once).
#   5. OpenCore SysReport on for ONE boot: dumps the ACPI tables to the ESP (needed for the AC _PSR fix - on 26 the
#      tables are not readable from macOS; ADP0._PSR fails because \_SB.ALIB returns no value).
#   6. pmset SleepDisabled 1 (no GPU suspend/resume in NullMoth: waking from sleep = black screen).
#   then refreshes the Recovery rescue config (tahoe/install-rescue.sh).
# Usage: sudo bash stage13-tahoe-fixes.sh    then reboot      |   sudo bash stage13-tahoe-fixes.sh undo <backup dir>
set -u
H=${HACK:-$HOME/hackintosh}; PB=/usr/libexec/PlistBuddy; ESPUUID=${ESP_UUID:?set ESP_UUID to your EFI partition UUID: diskutil info disk0s1 | grep "Partition UUID"}
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
HDA_SRC=$H/tahoe/AppleHDA.kext; HDA_DST=/Library/Apple/System/Library/Extensions/AppleHDA.kext
AAC=$H/AACELDOff/build/AACELDOff.kext; AACSHA=f2c9177fb6ea535b
NVA=$H/gpusens/out115/26/NVAccel.kext; NVASHA=4e248c302d627ce3
SAFE=$H/tahoe/NullMothSafe.efi; SAFESHA=f99c1fa37693521d
HDA=(com.apple.driver.AppleHDA com.apple.driver.AppleHDAController com.apple.driver.AppleHDAHardwareConfigDriver com.apple.driver.DspFuncLib com.apple.iokit.IOHDAFamily)
NV=(com.nullmoth.NVRM com.nullmoth.NVAccel com.nullmoth.NVRMFB com.nullmoth.NVRMAGDC)
MP=""; DEV=""
die() { echo "STOP: $*"; esp_off; exit 1; }
sha16() { shasum -a 256 "$1" | cut -c1-16; }
esp_on() {
  DEV=$(for d in $(diskutil list | awk '/ EFI /{print $NF}'); do [ "$(diskutil info $d | awk -F': *' '/Partition UUID/{print $2}')" = $ESPUUID ] && { echo $d; break; }; done)
  [ -n "$DEV" ] || die "OpenCore ESP not found"
  diskutil unmount "$DEV" >/dev/null 2>&1 || true
  MP=$(mktemp -d /private/var/tmp/esp.XXXX)
  mount -t msdos /dev/$DEV "$MP" 2>/dev/null || mount -F -t msdos /dev/$DEV "$MP" || { rmdir "$MP"; MP=""; die "cannot mount $DEV"; }
  C="$MP/EFI/OC/config.plist"; [ -f "$MP/EFI/OC/OpenCore.efi" ] && plutil -lint "$C" >/dev/null || die "unexpected ESP layout"; }
esp_off() { [ -n "$MP" ] || return 0; sync; umount "$MP" 2>/dev/null || diskutil unmount force "$DEV" >/dev/null 2>&1; rmdir "$MP" 2>/dev/null; MP=""; }
build_kc() {  # build_kc <out>: auxiliary collection from /Library/Extensions + the Apple repository, Apple HDA ids named
  local KARG=(--allow-missing-kdk) BARG=(); [ -f /System/Library/Kernels/kernel ] && KARG+=(--kernel /System/Library/Kernels/kernel)
  [ -d "$HDA_DST" ] && for b in "${HDA[@]}"; do BARG+=(-b "$b"); done
  kmutil create -n aux --volume-root / "${KARG[@]}" "${BARG[@]}" -B /System/Library/KernelCollections/BootKernelExtensions.kc \
    -S /System/Library/KernelCollections/SystemKernelExtensions.kc --repository /Library/Extensions \
    --repository /Library/Apple/System/Library/Extensions -A "$1" -z; }
has_all() { local INS; INS=$(kmutil inspect -a x86_64 -A "$1" 2>/dev/null); shift
  for k in "$@"; do printf '%s\n' "$INS" | grep -oE '[A-Za-z0-9.]+' | grep -Fxq "$k" || { echo "missing: $k"; return 1; }; done; }

[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
[ "$(sw_vers -productVersion | cut -d. -f1)" = 26 ] || { echo "this is for macOS 26"; exit 1; }

if [ "${1:-}" = undo ]; then
  B=${2:?usage: undo <backup dir>}; [ -f "$B/config.plist" ] || die "no backup in $B"
  esp_on; [ -f "$MP/EFI/OC/rescue/ACTIVE" ] && die "rescue config active - restore it first"
  cp "$B/config.plist" "$C" && rm -rf "$MP/EFI/OC/Kexts/AACELDOff.kext" && ditto "$B/AACELDOff.kext" "$MP/EFI/OC/Kexts/AACELDOff.kext" || die "ESP restore failed"
  esp_off; echo "== ESP config + AACELDOff restored"
  rm -rf /Library/Extensions/NVAccel.kext && ditto "$B/NVAccel.kext" /Library/Extensions/NVAccel.kext && chown -R root:wheel /Library/Extensions/NVAccel.kext
  rm -rf "$HDA_DST"
  N="$KC.s13-new"; rm -f "$N"; build_kc "$N" > "$B/kmutil-undo.log" 2>&1 || die "kmutil failed ($B/kmutil-undo.log) - put back: cp $B/AuxiliaryKernelExtensions.kc $KC"
  has_all "$N" "${NV[@]}" || die "NullMoth kexts missing in the new collection - put back: cp $B/AuxiliaryKernelExtensions.kc $KC"
  mv -f "$N" "$KC"; pmset -a SleepDisabled 0; echo "DONE (undo). Reboot."; exit 0
fi

# ---- checks before anything changes
[ "$(sha16 "$AAC/Contents/MacOS/AACELDOff")" = $AACSHA ] || die "$AAC is not the built 1.1.0"
[ "$(sha16 "$NVA/Contents/MacOS/NVAccel")" = $NVASHA ] || die "$NVA is not the GPU-sensors 26 build"
[ "$(sha16 "$SAFE")" = $SAFESHA ] || die "$SAFE is not upstream's NullMothSafe.efi"
[ -f "$HDA_SRC/Contents/MacOS/AppleHDA" ] && [ -d "$HDA_SRC/Contents/PlugIns/IOHDAFamily.kext" ] || die "missing $HDA_SRC"
B=/Library/NullMoth/backup-stage13-$(date +%Y%m%d-%H%M%S); mkdir -p "$B" || die "backup dir"
ditto /Library/Extensions/NVAccel.kext "$B/NVAccel.kext" && cp -p "$KC" "$B/" || die "backup of NVAccel / kernel collection"
echo "== backup: $B"

# ---- 1+3: kexts on the system volume, one new kernel collection
rm -rf /Library/Extensions/NVAccel.kext && ditto "$NVA" /Library/Extensions/NVAccel.kext || die "NVAccel copy (put back: ditto $B/NVAccel.kext /Library/Extensions/NVAccel.kext)"
chown -R root:wheel /Library/Extensions/NV*.kext; chmod -R go-w /Library/Extensions/NV*.kext
mkdir -p /Library/Apple/System/Library/Extensions; rm -rf "$HDA_DST" /Library/Extensions/AppleHDA.kext
ditto "$HDA_SRC" "$HDA_DST" && chown -R root:wheel "$HDA_DST" && chmod -R go-w "$HDA_DST" && xattr -cr "$HDA_DST" || die "AppleHDA copy"
N="$KC.s13-new"; rm -f "$N"
if ! build_kc "$N" > "$B/kmutil.log" 2>&1 || ! has_all "$N" "${HDA[@]}" "${NV[@]}"; then
  tail -12 "$B/kmutil.log"
  rm -rf "$HDA_DST" "$N"; rm -rf /Library/Extensions/NVAccel.kext; ditto "$B/NVAccel.kext" /Library/Extensions/NVAccel.kext
  die "kernel collection build failed ($B/kmutil.log) - AppleHDA removed, NVAccel put back, old collection unchanged"
fi
mv -f "$N" "$KC" || die "cannot publish the collection (backup $B)"
echo "== kernel collection: NullMoth (NVAccel $NVASHA) + AppleHDA:"
kmutil inspect -a x86_64 -A "$KC" 2>/dev/null | grep -E 'AppleHDA|IOHDAFamily|DspFuncLib|nullmoth' | sed 's/^/   /'

# ---- 2, 4, 5: ESP
esp_on
[ -f "$MP/EFI/OC/rescue/ACTIVE" ] && die "the rescue config is active - restore it first (kexts/collection already updated; ESP unchanged)"
cp -p "$C" "$B/config.plist" && ditto "$MP/EFI/OC/Kexts/AACELDOff.kext" "$B/AACELDOff.kext" || die "ESP backup"
T=$(mktemp /var/tmp/s13-cfg.XXXX); cp "$C" "$T"
i=0; ai=""; while p=$($PB -c "Print :Kernel:Add:$i:BundlePath" "$T" 2>/dev/null); do [ "$p" = AACELDOff.kext ] && ai=$i; i=$((i+1)); done
[ -n "$ai" ] || die "AACELDOff.kext not in Kernel > Add"
$PB -c "Set :Kernel:Add:$ai:MaxKernel 25.99.99" -c "Set :Kernel:Add:$ai:Enabled true" "$T" || die "PlistBuddy AACELDOff"
$PB -c "Set :Misc:Debug:SysReport true" "$T" || die "PlistBuddy SysReport"
[ -e "$MP/SysReport" ] && { mv "$MP/SysReport" "$MP/SysReport.old-$(date +%Y%m%d%H%M%S)" || die "cannot move the old SysReport"; }
once=""; i=0; while p=$($PB -c "Print :Misc:Tools:$i:Path" "$T" 2>/dev/null); do
  [ "$p" = NullMothSafe.efi ] && [ "$($PB -c "Print :Misc:Tools:$i:Arguments" "$T")" = once ] && once=$i; i=$((i+1)); done
if [ -z "$once" ]; then
  $PB -c "Print :Misc:Tools" "$T" >/dev/null 2>&1 || $PB -c "Add :Misc:Tools array" "$T"
  plutil -insert Misc.Tools -json '{"Arguments":"once","Auxiliary":false,"Comment":"NullMoth: start macOS once without the NVIDIA driver","Enabled":true,"Flavour":"Auto","FullNvramAccess":true,"Name":"Start once without NVIDIA driver","Path":"NullMothSafe.efi","RealPath":false,"TextMode":true}' -append "$T" || die "plutil Tools"
fi
plutil -lint "$T" >/dev/null || die "edited config does not parse (ESP unchanged)"
mkdir -p "$MP/EFI/OC/Tools" && cp "$SAFE" "$MP/EFI/OC/Tools/NullMothSafe.efi" || die "copy NullMothSafe.efi"
rm -rf "$MP/EFI/OC/Kexts/AACELDOff.kext" && ditto "$AAC" "$MP/EFI/OC/Kexts/AACELDOff.kext" || { ditto "$B/AACELDOff.kext" "$MP/EFI/OC/Kexts/AACELDOff.kext"; die "copy AACELDOff"; }
cp "$T" "$C" && sync && cmp -s "$T" "$C" || { cp "$B/config.plist" "$C"; die "config write/read-back failed - previous config put back"; }
cmp -s "$AAC/Contents/MacOS/AACELDOff" "$MP/EFI/OC/Kexts/AACELDOff.kext/Contents/MacOS/AACELDOff" || die "AACELDOff read-back differs"
rm -f "$T"; esp_off
echo "== ESP: AACELDOff 1.1.0 (MaxKernel 25.99.99), picker entry 'Start once without NVIDIA driver', SysReport on for the next boot"

# ---- 6 + rescue refresh
pmset -a SleepDisabled 1 && echo "== sleep disabled (pmset SleepDisabled 1)"
bash "$H/tahoe/install-rescue.sh" 2>&1 | sed 's/^/   /'
echo
echo "DONE. Reboot now (one restart). Undo: sudo bash $0 undo $B"
