#!/bin/bash
# Boot hang with the external DisplayPort monitor (2026-10-15: two boots in a row, WindowServer watchdog x4, then reboot).
# WindowServer's main thread spun forever in NVRM: ConnectorImpl::notifyDetachEnd -> GroupImpl::enumDevices, during the
# mode set it does at login on the external monitor. Cause (NVIDIA DP library): GroupImpl::insert() adds a device to a
# group even when it is already a member; NVKMS inserts at every head attach and again when the DP library reports the
# device anew, so a group can hold [A, A] - and LinkedList::next(A) then returns A forever.
# NVRM = installed 9794974b (1.15.0 + patch-nvrm-1150.py) + patch-nvrm-dpdup.py: insert() skips the list insertion for a
# device that is already a member (38-byte check in the zero slack at the end of __TEXT), re-signed ad hoc -> a99adf1e.
#   sudo bash stage20-dpdup.sh    then reboot   |   sudo bash stage20-dpdup.sh undo    then reboot
# If the system does not come up: OpenCore entry "Start once without NVIDIA driver", then: sudo bash <this file> undo
set -u
H=${HACK:-$HOME/hackintosh}; D=$H/dpdup
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
NEW=$D/NVRM.kext; NEWSHA=a99adf1ef0b6a217; OLDSHA=9794974b35966a89
HDA_DST=/Library/Apple/System/Library/Extensions/AppleHDA.kext
HDA=(com.apple.driver.AppleHDA com.apple.driver.AppleHDAController com.apple.driver.AppleHDAHardwareConfigDriver com.apple.driver.DspFuncLib com.apple.iokit.IOHDAFamily)
NV=(com.nullmoth.NVRM com.nullmoth.NVAccel com.nullmoth.NVRMFB com.nullmoth.NVRMAGDC)
die() { echo "STOP: $*"; exit 1; }
sha16() { shasum -a 256 "$1" | cut -c1-16; }
build_kc() {  # same recipe as stage13/14/18 (AppleHDA from the Apple repository named with -b)
  local KARG=(--allow-missing-kdk) BARG=(); [ -f /System/Library/Kernels/kernel ] && KARG+=(--kernel /System/Library/Kernels/kernel)
  [ -d "$HDA_DST" ] && for b in "${HDA[@]}"; do BARG+=(-b "$b"); done
  kmutil create -n aux --volume-root / "${KARG[@]}" "${BARG[@]}" -B /System/Library/KernelCollections/BootKernelExtensions.kc \
    -S /System/Library/KernelCollections/SystemKernelExtensions.kc --repository /Library/Extensions \
    --repository /Library/Apple/System/Library/Extensions -A "$1" -z; }
has_all() { local INS; INS=$(kmutil inspect -a x86_64 -A "$1" 2>/dev/null); shift
  for k in "$@"; do printf '%s\n' "$INS" | grep -oE '[A-Za-z0-9.]+' | grep -Fxq "$k" || { echo "missing: $k"; return 1; }; done; }
hda_ids() { [ -d "$HDA_DST" ] && printf '%s\n' "${HDA[@]}"; }
put_nvrm() {  # put_nvrm <kext> <log>: replace NVRM and rebuild the auxiliary kernel collection
  rm -rf /Library/Extensions/NVRM.kext && ditto "$1" /Library/Extensions/NVRM.kext && chown -R root:wheel /Library/Extensions/NVRM.kext || return 1
  local N="$KC.s20-new"; rm -f "$N"
  if ! build_kc "$N" > "$2" 2>&1 || ! has_all "$N" "${NV[@]}" $(hda_ids); then tail -12 "$2"; rm -f "$N"; return 1; fi
  mv -f "$N" "$KC"; }

[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
[ "$(sw_vers -productVersion | cut -d. -f1)" = 26 ] || die "this is for macOS 26"

if [ "${1:-}" = undo ]; then
  BK=$(ls -d /Library/NullMoth/before-dpdup-* 2>/dev/null | sort | tail -1)   # the newest backup
  [ -n "$BK" ] && [ -d "$BK/NVRM.kext" ] || die "no backup in /Library/NullMoth/before-dpdup-*"
  echo "== restoring NVRM from $BK ($(sha16 "$BK/NVRM.kext/Contents/MacOS/NVRM"))"
  put_nvrm "$BK/NVRM.kext" "$BK/kmutil-undo.log" || die "kernel collection build failed ($BK/kmutil-undo.log) - put the old one back: cp $BK/AuxiliaryKernelExtensions.kc $KC"
  echo "DONE (undo). Reboot."; exit 0
fi

[ "$(sha16 "$NEW/Contents/MacOS/NVRM")" = $NEWSHA ] || die "$NEW is not the tested build"
[ "$(sha16 /Library/Extensions/NVRM.kext/Contents/MacOS/NVRM)" = $OLDSHA ] || die "installed NVRM is not $OLDSHA (the build this patch was made from)"
BK=/Library/NullMoth/before-dpdup-$(date +%Y%m%d-%H%M%S); mkdir -p "$BK" || die "backup dir"
ditto /Library/Extensions/NVRM.kext "$BK/NVRM.kext" && cp -p "$KC" "$BK/" || die "backup failed"
echo "== backup: $BK"
if ! put_nvrm "$NEW" "$BK/kmutil.log"; then
  rm -rf /Library/Extensions/NVRM.kext; ditto "$BK/NVRM.kext" /Library/Extensions/NVRM.kext; chown -R root:wheel /Library/Extensions/NVRM.kext
  die "kernel collection build failed ($BK/kmutil.log) - NVRM put back, old collection unchanged"
fi
echo "== kernel collection rebuilt with NVRM $NEWSHA:"
kmutil inspect -a x86_64 -A "$KC" 2>/dev/null | grep -E 'nullmoth|AppleHDA' | sed 's/^/   /'
echo; echo "DONE. Reboot now."
echo "Undo (no other arguments needed): sudo bash $0 undo   then reboot"
echo "If the system does not come up: OpenCore entry 'Start once without NVIDIA driver', then the undo above."
