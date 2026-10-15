#!/bin/bash
# build-payload.sh: rebuild the patched NullMoth 2.0.0 package (what install/stage21-200.sh installs) from upstream sources
# and the patches in this repository. Needs: Xcode (clang), Rust (cargo), NVIDIA open-gpu-kernel-modules at tag 610.57.04,
# Vulkan-Headers, a clone of github.com/nullmoth/nvidia-macos-driver with tag v2.0.0, and the v2.0.0 release tarball.
#   UPSTREAM=<clone> PKGTAR=<nullmoth-nvidia-2.0.0.tar.gz> OGKM=<open-gpu-kernel-modules> VKH=<Vulkan-Headers> \
#     bash install/build-payload.sh <out dir>
# <out dir>/pkgroot-patched is the package; stage21-200.sh expects it at $HACK/nm-2.0.0/pkgroot-patched.
# No sudo needed: nothing outside <out dir> is touched.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd); P=$REPO/patches/nullmoth-2.0.0
OUT=${1:?usage: build-payload.sh <out dir>}; mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
: "${UPSTREAM:?set UPSTREAM to a clone of nullmoth/nvidia-macos-driver}" "${PKGTAR:?set PKGTAR to nullmoth-nvidia-2.0.0.tar.gz}"
: "${OGKM:?set OGKM to open-gpu-kernel-modules (tag 610.57.04)}" "${VKH:?set VKH to Vulkan-Headers}"
S=$OUT/src; rm -rf "$S" "$OUT/pkg" "$OUT/pkgroot-patched"; mkdir -p "$S" "$OUT/pkg"

echo "== sources: upstream v2.0.0 + patches 0001-0003"
git -C "$UPSTREAM" archive v2.0.0 plugin translator kexts/NVRM build | tar -x -C "$S"
(cd "$S" && git init -q && git apply "$P/0001-plugin.patch" "$P/0002-translator.patch" "$P/0003-nvaccel.patch")

echo "== plugin"
(cd "$S/plugin" && xcrun clang -arch x86_64 -mmacosx-version-min=15.0 -bundle -fobjc-arc -O1 -DNVMTL_RELEASE=1 -Wno-protocol \
  -Wno-incomplete-implementation -I"$VKH/include" -o "$OUT/NVMTLDriver" NVMTLDevice.m -framework Foundation -framework Metal \
  -framework IOSurface -framework IOKit -framework CoreVideo 2>"$OUT/plugin.log") || { grep -m5 ': error:' "$OUT/plugin.log"; exit 1; }

echo "== translator"
(cd "$S/translator/wrapper" && cargo build --release --target-dir "$OUT/target" >"$OUT/translator.log" 2>&1) || { tail -20 "$OUT/translator.log"; exit 1; }
cp "$OUT/target/release/libnvmtl_translate.dylib" "$OUT/" && codesign -f -s - "$OUT/libnvmtl_translate.dylib"

echo "== NVAccel (macOS 15 and 26)"
OGKM=$OGKM bash "$S/build/accel_build_all.sh" "$S/kexts/NVRM" "$OUT/nvaccel" >"$OUT/nvaccel.log" 2>&1 || { tail -20 "$OUT/nvaccel.log"; exit 1; }

echo "== package"
tar -xzf "$PKGTAR" -C "$OUT/pkg"; B=$OUT/pkgroot-patched; cp -R "$OUT/pkg/pkgroot" "$B"
(cd "$B" && shasum -a 256 -c SHA256SUMS --quiet) || { echo "the tarball does not match its SHA256SUMS"; exit 1; }
K=$B/Library/Extensions
python3 -I "$REPO/kexts/patch-nvrm-200.py" "$K/NVRM.kext/Contents/MacOS/NVRM"
python3 -I "$REPO/kexts/patch-nvrm-dpdup-200.py" "$K/NVRM.kext/Contents/MacOS/NVRM" "$OUT/NVRM.dpdup"
cp "$OUT/NVRM.dpdup" "$K/NVRM.kext/Contents/MacOS/NVRM" && codesign -f -s - "$K/NVRM.kext"
python3 -I "$REPO/kexts/patch-nvrmfb-200.py" "$K/NVRMFB.kext/Contents/MacOS/NVRMFB"
for m in 15 26; do cp "$OUT/nvaccel/$m/NVAccel.kext/Contents/MacOS/NVAccel" "$B/Library/NullMoth/kexts/$m/NVAccel.kext/Contents/MacOS/NVAccel"; done
cp "$OUT/nvaccel/15/NVAccel.kext/Contents/MacOS/NVAccel" "$K/NVAccel.kext/Contents/MacOS/NVAccel"
M=$B/Library/GPUBundles/NVMTLDriver.bundle/Contents/MacOS
(cd "$REPO/codec/nvenc" && python3 -I mk.py "$M/libnvenc_h264.dylib" "$OUT/libnvenc_h264.dylib") && codesign -f -s - "$OUT/libnvenc_h264.dylib"
cp "$OUT/libnvenc_h264.dylib" "$OUT/libnvmtl_translate.dylib" "$M/" && cp "$OUT/NVMTLDriver" "$M/NVMTLDriver"
codesign -f -s - -i com.nullmoth.NVMTLDriver "$B/Library/GPUBundles/NVMTLDriver.bundle"
codesign -v --deep --strict "$B/Library/GPUBundles/NVMTLDriver.bundle"
(cd "$B" && patch -s -p1 < "$P/0004-install-applehda.patch")
(cd "$B" && python3 -I -c '
import hashlib
L = [hashlib.sha256(open(p, "rb").read()).hexdigest() + "  " + p for p in (l.rstrip("\n").split("  ", 1)[1] for l in open("SHA256SUMS"))]
open("SHA256SUMS", "w").write("\n".join(L) + "\n")')
(cd "$B" && shasum -a 256 -c SHA256SUMS --quiet)
echo; echo "DONE: $B"
for f in Library/Extensions/NVRM.kext/Contents/MacOS/NVRM Library/Extensions/NVRMFB.kext/Contents/MacOS/NVRMFB \
         Library/NullMoth/kexts/26/NVAccel.kext/Contents/MacOS/NVAccel Library/GPUBundles/NVMTLDriver.bundle/Contents/MacOS/NVMTLDriver \
         Library/GPUBundles/NVMTLDriver.bundle/Contents/MacOS/libnvmtl_translate.dylib Library/GPUBundles/NVMTLDriver.bundle/Contents/MacOS/libnvenc_h264.dylib; do
  printf '   %s  %s\n' "$(shasum -a 256 "$B/$f" | cut -c1-16)" "$f"; done
echo "Your builds' plugin/translator/NVAccel hashes differ from stage21-200.sh's (other compiler); edit its want lines after testing."
