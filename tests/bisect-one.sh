#!/bin/bash
# bisect-one.sh <upstream commit>: build that commit's plugin (non-release, as upstream ships) into a copy of the stock
# 2.0.0 bundle and run catest sarray against the 2.0.0 NVK. Prints PASS/FAIL.
C=$1; R=~/Documents/Projects/nvidia-macos-driver; W=${TMPDIR:-/tmp}/fa607pi/bis/$C
rm -rf $W; mkdir -p $W/src && git -C $R archive $C plugin | tar -x -C $W/src || exit 2
cp -R ~/hackintosh/nm-2.0.0/pkgroot/pkgroot/Library/GPUBundles/NVMTLDriver.bundle $W/b
(cd $W/src/plugin && xcrun clang -arch x86_64 -mmacosx-version-min=15.0 -bundle -fobjc-arc -O1 -Wno-protocol -Wno-incomplete-implementation -I$HOME/hackintosh/Vulkan-Headers/include \
  -o $W/b/Contents/MacOS/NVMTLDriver NVMTLDevice.m -framework Foundation -framework Metal -framework IOSurface -framework IOKit -framework CoreVideo 2>$W/err) || { echo "$C BUILD-FAIL"; exit 3; }
cd ~/hackintosh/catest-1015
r=$(SHIM_ICD=~/hackintosh/nm-2.0.0/pkgroot/pkgroot/Library/GPUBundles/nvmtl/libvulkan_nouveau.dylib DYLD_INSERT_LIBRARIES=$PWD/plugshim.dylib NVMTL_TEST_PLUGIN=$W/b/Contents/MacOS/NVMTLDriver ./sarray 2>&1 | grep -v '^nvrm\|MESA\|plugshim' | tail -1)
echo "$C $r"
