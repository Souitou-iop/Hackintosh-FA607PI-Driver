#!/bin/bash
# UU远程 stuck at "正在传输画面": the H.264 hardware encoder in the bundle is NullMoth's stock one again (c78e21aa) - the
# 1.15.0 install (stage10) put it back and lost our Ada fix (friend fix 15 port, 33cc5eca: NotSync + t2d layout + zeroing).
# On this RTX 4070 the stock encoder's output is garbage: rctest 7 dB PSNR at 110 Mbps; with the fix 42 dB at 4.9 Mbps.
# 1.15.0's stock encoder is byte-identical to 1.14.2's, so the same fixed file applies.
# The bundle is signed as a whole: the fixed encoder goes in together with the plugin re-signed over it (only its
# signature changes: the stage18 Dock-fix plugin code). No reboot: UU is restarted (WindowServer keeps the old file mapped).
#   sudo bash stage19-nvenc.sh        |   sudo bash stage19-nvenc.sh undo
set -u
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
H=${HACK:-$HOME/hackintosh}/nvenc; B=/Library/GPUBundles/NVMTLDriver.bundle; M=$B/Contents/MacOS; BK=/Library/NullMoth/before-nvenc115
NEWP=$H/bundle-115/Contents/MacOS/NVMTLDriver; NEWP_SHA=5bbca3e47aaade78
NEWE=$H/bundle-115/Contents/MacOS/libnvenc_h264.dylib; NEWE_SHA=33cc5eca388885fd
# the bundle seal (_CodeSignature/CodeResources) lists every file's hash, so it has to go in with the two files
CR=Contents/_CodeSignature/CodeResources; NEWC=$H/bundle-115/$CR; NEWC_SHA=bccd4590dd8d3738
die() { echo "STOP: $*"; exit 1; }
sha16() { shasum -a 256 "$1" | cut -c1-16; }
put() { cp "$1" "$2.new.$$" && chown root:wheel "$2.new.$$" && chmod "${3:-755}" "$2.new.$$" && mv -f "$2.new.$$" "$2"; }
put_all() {  # put_all <encoder> <plugin> <CodeResources>
  put "$1" "$M/libnvenc_h264.dylib" && put "$2" "$M/NVMTLDriver" && put "$3" "$B/$CR" 644; }
restore() { put_all "$BK/libnvenc_h264.dylib" "$BK/NVMTLDriver" "$BK/CodeResources"; }
if [ "${1:-}" = undo ]; then
  [ -f "$BK/NVMTLDriver" ] && [ -f "$BK/libnvenc_h264.dylib" ] && [ -f "$BK/CodeResources" ] || die "no backup in $BK"
  restore || die "restore failed"
  codesign -v --deep "$B" || echo "WARNING: bundle signature does not verify"
  zsh ${HACK:-$HOME/hackintosh}/uu/uu-restart.sh; echo "DONE (undo)"; exit 0
fi
[ "$(sha16 "$NEWP")" = $NEWP_SHA ] && [ "$(sha16 "$NEWE")" = $NEWE_SHA ] && [ "$(sha16 "$NEWC")" = $NEWC_SHA ] || die "payload is not the tested build"
[ "$(sha16 "$M/NVMTLDriver")" = 26c698aa8e150aab ] || die "installed plugin is $(sha16 "$M/NVMTLDriver"), not the stage18 build this was signed over"
codesign -v --deep "$B" || die "installed bundle does not verify before the change"
# fresh backup of the current (verified) state every run; the earlier attempt's backup lacked CodeResources
rm -rf "$BK"; mkdir -p "$BK" && cp -p "$M/NVMTLDriver" "$M/libnvenc_h264.dylib" "$B/$CR" "$BK/" || die "backup"
put_all "$NEWE" "$NEWP" "$NEWC" || { restore; die "copy failed - old files put back"; }
codesign -v --deep "$B" || { restore; die "bundle signature invalid - old files put back"; }
echo "encoder $(sha16 "$M/libnvenc_h264.dylib"), plugin $(sha16 "$M/NVMTLDriver"), bundle signature valid"; grep -n NVENC /Library/GPUBundles/nvmtl/nvrm610.conf
zsh ${HACK:-$HOME/hackintosh}/uu/uu-restart.sh
echo "DONE. Try connecting with UU again.   Undo: sudo bash $0 undo"
