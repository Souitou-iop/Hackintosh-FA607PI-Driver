#!/bin/bash
# Dock: a minimized window left only its app badge (the preview was blank). Cause: #196 (stage14) let EVERY WindowServer
# command buffer return from commitAndWaitUntilSubmitted before its GPU work finished; the snapshot WindowServer draws for
# the Dock is read right after that call, so it was read before it was drawn. (sysctl debug.nvaccel_wsw=0 brought it back.)
# Now only buffers that draw a surface the display is showing skip the wait:
#   - NVAccel (gpusens/src15 branch ws-scan 4c5a05e, 26 build ec09366b): performTransaction notes every surface it flips or
#     copies; new op SCANOUT answers "on a display in the last second?". Counters debug.nvaccel_wsw_scan_yes / _scan_no.
#   - Plugin (plugin-work/a branch ws-scan 4524ace = installed 196v build + this check, bundle-signed 26c698aa): before
#     tagging a WindowServer buffer it asks SCANOUT for the surfaces the buffer draws; none on a display -> CPU wait as before.
#     New plugin + old NVAccel = CPU wait for everything (correct, just the pre-#196 speed).
# Test (ws196/wswscan, fake kernel): old plugin 200/200 snapshots read before drawn, new 0/200; screen frames still return
# early 200/200. Regression set, library validation: PASS. Translator, Vulkan driver: unchanged.
#   sudo bash stage18-dockfix.sh    then reboot   |   sudo bash stage18-dockfix.sh undo    then reboot
set -u
H=${HACK:-$HOME/hackintosh}; W=$H/ws196
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
B=/Library/GPUBundles/NVMTLDriver.bundle; M=$B/Contents/MacOS
NVA=$W/out-scan/26/NVAccel.kext; NVASHA=ec09366b1af9ebd9; PLUG=$W/bundle-scan/Contents/MacOS/NVMTLDriver; PLUGSHA=26c698aa8e150aab
HDA_DST=/Library/Apple/System/Library/Extensions/AppleHDA.kext
HDA=(com.apple.driver.AppleHDA com.apple.driver.AppleHDAController com.apple.driver.AppleHDAHardwareConfigDriver com.apple.driver.DspFuncLib com.apple.iokit.IOHDAFamily)
NV=(com.nullmoth.NVRM com.nullmoth.NVAccel com.nullmoth.NVRMFB com.nullmoth.NVRMAGDC)
die() { echo "STOP: $*"; exit 1; }
sha16() { shasum -a 256 "$1" | cut -c1-16; }
build_kc() {  # same recipe as stage13/14 (AppleHDA from the Apple repository named with -b)
  local KARG=(--allow-missing-kdk) BARG=(); [ -f /System/Library/Kernels/kernel ] && KARG+=(--kernel /System/Library/Kernels/kernel)
  [ -d "$HDA_DST" ] && for b in "${HDA[@]}"; do BARG+=(-b "$b"); done
  kmutil create -n aux --volume-root / "${KARG[@]}" "${BARG[@]}" -B /System/Library/KernelCollections/BootKernelExtensions.kc \
    -S /System/Library/KernelCollections/SystemKernelExtensions.kc --repository /Library/Extensions \
    --repository /Library/Apple/System/Library/Extensions -A "$1" -z; }
has_all() { local INS; INS=$(kmutil inspect -a x86_64 -A "$1" 2>/dev/null); shift
  for k in "$@"; do printf '%s\n' "$INS" | grep -oE '[A-Za-z0-9.]+' | grep -Fxq "$k" || { echo "missing: $k"; return 1; }; done; }
hda_ids() { [ -d "$HDA_DST" ] && printf '%s\n' "${HDA[@]}"; }
put_plugin() {  # copy beside, then rename (never overwrite a loaded binary in place)
  cp "$1" "$M/NVMTLDriver.new.$$" && chown root:wheel "$M/NVMTLDriver.new.$$" && chmod 755 "$M/NVMTLDriver.new.$$" && mv -f "$M/NVMTLDriver.new.$$" "$M/NVMTLDriver" || return 1
  codesign -v --deep "$B" || return 1
  echo "   NVMTLDriver now $(sha16 "$M/NVMTLDriver"), bundle signature valid"; }
put_nva() {  # put_nva <kext> <log>: replace NVAccel and rebuild the auxiliary kernel collection
  rm -rf /Library/Extensions/NVAccel.kext && ditto "$1" /Library/Extensions/NVAccel.kext && chown -R root:wheel /Library/Extensions/NVAccel.kext || return 1
  local N="$KC.s18-new"; rm -f "$N"
  if ! build_kc "$N" > "$2" 2>&1 || ! has_all "$N" "${NV[@]}" $(hda_ids); then tail -12 "$2"; rm -f "$N"; return 1; fi
  mv -f "$N" "$KC"; }

[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
[ "$(sw_vers -productVersion | cut -d. -f1)" = 26 ] || die "this is for macOS 26"

if [ "${1:-}" = undo ]; then
  BK=$(ls -d /Library/NullMoth/before-dockfix-* 2>/dev/null | sort | tail -1)   # the newest backup
  [ -n "$BK" ] && [ -f "$BK/NVMTLDriver" ] && [ -d "$BK/NVAccel.kext" ] || die "no backup in /Library/NullMoth/before-dockfix-*"
  echo "== restoring from $BK"
  put_plugin "$BK/NVMTLDriver" || die "plugin restore failed"
  put_nva "$BK/NVAccel.kext" "$BK/kmutil-undo.log" || die "kernel collection build failed ($BK/kmutil-undo.log) - put the old one back: cp $BK/AuxiliaryKernelExtensions.kc $KC"
  echo "DONE (undo). Reboot."; exit 0
fi

[ "$(sha16 "$NVA/Contents/MacOS/NVAccel")" = $NVASHA ] || die "$NVA is not the tested build"
[ "$(sha16 "$PLUG")" = $PLUGSHA ] || die "$PLUG is not the tested build"
BK=/Library/NullMoth/before-dockfix-$(date +%Y%m%d-%H%M%S); mkdir -p "$BK" || die "backup dir"
ditto /Library/Extensions/NVAccel.kext "$BK/NVAccel.kext" && cp -p "$M/NVMTLDriver" "$BK/NVMTLDriver" && cp -p "$KC" "$BK/" || die "backup failed"
echo "== backup: $BK (NVAccel $(sha16 "$BK/NVAccel.kext/Contents/MacOS/NVAccel"), plugin $(sha16 "$BK/NVMTLDriver"))"

if ! put_nva "$NVA" "$BK/kmutil.log"; then
  rm -rf /Library/Extensions/NVAccel.kext; ditto "$BK/NVAccel.kext" /Library/Extensions/NVAccel.kext; chown -R root:wheel /Library/Extensions/NVAccel.kext
  die "kernel collection build failed ($BK/kmutil.log) - NVAccel put back, old collection unchanged"
fi
echo "== kernel collection rebuilt with NVAccel $NVASHA:"
kmutil inspect -a x86_64 -A "$KC" 2>/dev/null | grep -E 'nullmoth|AppleHDA' | sed 's/^/   /'
put_plugin "$PLUG" || { echo "plugin swap failed - undoing everything"; exec bash "$0" undo; }
echo; echo "DONE. Reboot now."
echo "After the reboot: minimize a window - the Dock should show its preview. Counters: sysctl debug | grep nvaccel_wsw_scan"
echo "Undo (no other arguments needed): sudo bash $0 undo   then reboot"
