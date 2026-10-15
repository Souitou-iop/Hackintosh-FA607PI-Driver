#!/bin/bash
# NullMoth 2.0.0 with everything we carry (one reboot). Package: ~/hackintosh/nm-2.0.0/pkgroot-patched, installed by its own
# install.sh (test kernel collection first, full backup in /Library/NullMoth/backup-*, rollback on any failure).
#   NVRM    : 2.0.0 + patch-nvrm-200.py (head-scaler HiDPI, flip at boot) + patch-nvrm-dpdup-200.py (stage20 boot-loop fix)
#   NVRMFB  : 2.0.0 + patch-nvrmfb-200.py (HiDPI ceiling = max(panel's largest mode, 2x boot); no BAR clear in vramGrant)
#   NVAccel : 2.0.0 source (gpusens/src15 branch v200) + GPU sensors + #196 frame fence + Dock-preview fix, macOS 15 and 26
#   plugin  : upstream 2.0.0 merged into ours (plugin-work/a v200): friend fixes, #196/Dock, VRAM import cache, xsurf-sync;
#             robustBufferAccess opt-in (with it 2.0.0 breaks texture arrays: Claude terminal text)
#   translator: upstream 2.0.0 + friend fixes 25/29/35 (xlate-work v200)
#   H.264 encoder: our RTX 40 build (UU remote)        NVRMAGDC, NVK, firmware: stock 2.0.0
# The package's install.sh only differs from upstream in naming AppleHDA (built-in audio) for the kernel collection.
# Your nvrm610.conf is put back afterwards (the installer replaces /Library/GPUBundles/nvmtl wholesale).
#   sudo bash stage21-200.sh        then reboot
#   sudo bash stage21-200.sh undo   then reboot   (back to exactly what is installed now: 1.15.0 + stage18/19/20)
# If the system does not come up: OpenCore entry "Start once without NVIDIA driver", then the undo above.
set -u
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
H=${HACK:-$HOME/hackintosh}; P=${PKG:-$H/nm-2.0.0/pkgroot-patched}; CONF=/Library/GPUBundles/nvmtl/nvrm610.conf
REC=/Library/NullMoth/stage21-backup; KEEP=/Library/NullMoth/conf-before-200
EXT=/Library/Extensions; GB=/Library/GPUBundles; KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
HDA="com.apple.driver.AppleHDA com.apple.driver.AppleHDAController com.apple.driver.AppleHDAHardwareConfigDriver com.apple.driver.DspFuncLib com.apple.iokit.IOHDAFamily"
die() { echo "STOP: $*"; exit 1; }
sha16() { shasum -a 256 "$1" | cut -c1-16; }
kc_has() { local INS; INS=$(kmutil inspect -a x86_64 -A "$KC" 2>/dev/null) || return 1
  for k in com.nullmoth.NVRM com.nullmoth.NVAccel com.nullmoth.NVRMFB com.nullmoth.NVRMAGDC $([ -d /Library/Apple/System/Library/Extensions/AppleHDA.kext ] && echo $HDA); do
    printf '%s\n' "$INS" | grep -oE '[A-Za-z0-9.]+' | grep -Fxq "$k" || { echo "   missing from the kernel collection: $k"; return 1; }; done; }
[ "$(sw_vers -productVersion | cut -d. -f1)" = 26 ] || die "this is for macOS 26"

if [ "${1:-}" = undo ]; then
  BK=$(cat "$REC" 2>/dev/null); [ -n "$BK" ] && [ -d "$BK" ] && [ -f "$BK/AuxiliaryKernelExtensions.kc" ] || die "no recorded backup ($REC)"
  echo "== restoring 1.15.0 from $BK"
  for k in NVRM NVAccel NVRMFB NVRMAGDC; do [ -d "$BK/$k.kext" ] || die "$BK lacks $k.kext"; done
  for k in NVRM NVAccel NVRMFB NVRMAGDC; do rm -rf "$EXT/$k.kext" && ditto "$BK/$k.kext" "$EXT/$k.kext" || die "restore $k"; done
  for b in NVMTLDriver.bundle NVIDIAShared.bundle nvmtl nvmtl-allow.txt; do [ -e "$BK/$b" ] && { rm -rf "$GB/$b"; ditto "$BK/$b" "$GB/$b" || die "restore $b"; }; done
  [ -d "$BK/kexts" ] && { rm -rf /Library/NullMoth/kexts; ditto "$BK/kexts" /Library/NullMoth/kexts; }
  [ -d "$BK/nvfw" ] && { rm -rf /Users/Shared/nvfw; ditto "$BK/nvfw" /Users/Shared/nvfw; }
  [ -f "$BK/os-major" ] && cp -p "$BK/os-major" /Library/NullMoth/os-major
  [ -f "$KEEP/nvrm610.conf" ] && cp "$KEEP/nvrm610.conf" "$CONF"
  chown -R root:wheel "$EXT"/NV*.kext "$GB/NVMTLDriver.bundle" "$GB/NVIDIAShared.bundle" "$GB/nvmtl" "$GB/nvmtl-allow.txt"
  [ -d "$GB/nvmtl/aircache" ] && chown -R _windowserver:wheel "$GB/nvmtl/aircache" "$GB/nvmtl/spvcache" 2>/dev/null
  cp -p "$BK/AuxiliaryKernelExtensions.kc" "$KC" || die "restore the kernel collection"
  echo 1.15.0 > /Library/NullMoth/driver-version
  kc_has || die "the restored kernel collection is incomplete - boot with 'Start once without NVIDIA driver' and tell Claude"
  codesign -v --deep "$GB/NVMTLDriver.bundle" || echo "WARNING: bundle signature does not verify"
  echo "   NVRM $(sha16 $EXT/NVRM.kext/Contents/MacOS/NVRM) (1.15 + dpdup = a99adf1ef0b6a217), plugin $(sha16 $GB/NVMTLDriver.bundle/Contents/MacOS/NVMTLDriver)"
  echo "DONE (undo). Reboot."; exit 0
fi

# the tested payload (port200), and the state it was prepared against
# The hashes are the author's tested builds. A build from install/build-payload.sh on another Mac differs (compiler, paths,
# signatures) - then this only prints a note; set STRICT=1 to require the exact files.
want() { [ "$(sha16 "$P/$1")" = "$2" ] && return 0
  [ "${STRICT:-0}" = 1 ] && die "$1 is not the tested build"; echo "note: $1 differs from the author's tested build ($2)"; }
(cd "$P" && shasum -a 256 -c SHA256SUMS --quiet) || die "the package does not match its SHA256SUMS"
want Library/Extensions/NVRM.kext/Contents/MacOS/NVRM                                2a98c0008330e5fe
want Library/Extensions/NVRMFB.kext/Contents/MacOS/NVRMFB                            4e5265db00803157
want Library/NullMoth/kexts/26/NVAccel.kext/Contents/MacOS/NVAccel                   dd0f14fe30c30f5c
want Library/GPUBundles/NVMTLDriver.bundle/Contents/MacOS/NVMTLDriver                281cda933f2a5293
want Library/GPUBundles/NVMTLDriver.bundle/Contents/MacOS/libnvmtl_translate.dylib   4a29e2463319e68b
want Library/GPUBundles/NVMTLDriver.bundle/Contents/MacOS/libnvenc_h264.dylib        33cc5eca388885fd
codesign -v --deep --strict "$P/Library/GPUBundles/NVMTLDriver.bundle" || die "the package's driver bundle signature does not verify"
[ "$(sha16 $EXT/NVRM.kext/Contents/MacOS/NVRM)" = a99adf1ef0b6a217 ] || echo "NOTE: installed NVRM is not the stage20 build (fine; the backup keeps whatever is there)"
mkdir -p "$KEEP" && cp -p "$CONF" "$KEEP/nvrm610.conf" || die "save nvrm610.conf"
echo "1.15.0" > "$KEEP/version"

echo "== NullMoth 2.0.0 installer (with our patches)"
bash "$P/install.sh" || die "the installer stopped (it restores the previous driver itself when it had started changing files)"
BK=$(ls -dt /Library/NullMoth/backup-* | head -1); [ -f "$BK/AuxiliaryKernelExtensions.kc" ] || die "cannot find the installer's backup"
echo "$BK" > "$REC"
cp "$KEEP/nvrm610.conf" "$CONF" && chown root:wheel "$CONF" && chmod 644 "$CONF" || die "restore nvrm610.conf (saved in $KEEP)"
echo "   nvrm610.conf restored ($(grep -c . "$CONF") lines)"
kc_has || { echo "kernel collection incomplete - undoing"; exec bash "$0" undo; }
echo "== kernel collection:"; kmutil inspect -a x86_64 -A "$KC" 2>/dev/null | grep -E 'nullmoth|AppleHDA' | sed 's/^/   /'
echo; echo "DONE. Reboot now."
echo "Undo (no other arguments needed): sudo bash $0 undo   then reboot"
echo "If the system does not come up: OpenCore entry 'Start once without NVIDIA driver', then the undo above."
