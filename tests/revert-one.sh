#!/bin/bash
# revert-one.sh <upstream commit>...: our v200 plugin with those upstream commits reverted -> build -> sarray PASS/FAIL
R=~/Documents/Projects/nvidia-macos-driver; A=~/hackintosh/plugin-work/a; N=$(echo "$@" | tr ' ' '_')
W=${TMPDIR:-/tmp}/fa607pi/rev/$N
rm -rf $W; mkdir -p $W/src; git -C $A archive v200 plugin | tar -x -C $W/src
cd $W/src; git init -q . && git add -A && git commit -qm base
for c in "$@"; do git -C $R diff $c^ $c -- plugin > $W/$c.diff; git apply -R $W/$c.diff 2>$W/apply.err || { echo "$N REVERT-CONFLICT ($c)"; exit 4; }; done
cp -R ~/hackintosh/port200/bundle $W/b
(cd plugin && xcrun clang -arch x86_64 -mmacosx-version-min=15.0 -bundle -fobjc-arc -O1 -Wno-protocol -Wno-incomplete-implementation -I$HOME/hackintosh/Vulkan-Headers/include \
  -o $W/b/Contents/MacOS/NVMTLDriver NVMTLDevice.m -framework Foundation -framework Metal -framework IOSurface -framework IOKit -framework CoreVideo 2>$W/err) || { echo "$N BUILD-FAIL"; grep -m3 error: $W/err; exit 3; }
cd ~/hackintosh/catest-1015
r=$(SHIM_ICD=~/hackintosh/nm-2.0.0/pkgroot/pkgroot/Library/GPUBundles/nvmtl/libvulkan_nouveau.dylib DYLD_INSERT_LIBRARIES=$PWD/plugshim.dylib NVMTL_TEST_PLUGIN=$W/b/Contents/MacOS/NVMTLDriver ./sarray 2>&1 | grep -v '^nvrm\|MESA\|plugshim' | tail -1)
echo "$N $r"
