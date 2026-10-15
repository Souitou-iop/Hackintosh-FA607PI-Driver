#!/bin/bash
# 2.0.0 port check: NEW = port200/bundle plugin (2.0.0 + friend + #196/scan + vimp + xsurf-sync, translator 2.0.0 + fix 35)
# on the 2.0.0 NVK (SHIM_ICD); OLD = what is installed (1.15 stage18/19 plugin, 1.15 NVK).
cd ~/hackintosh/catest-1015; T=~/hackintosh/port200/bundle/Contents/MacOS/NVMTLDriver
ICD=~/hackintosh/nm-2.0.0/pkgroot/pkgroot/Library/GPUBundles/nvmtl/libvulkan_nouveau.dylib
new() { SHIM_ICD=$ICD DYLD_INSERT_LIBRARIES=$PWD/plugshim.dylib NVMTL_TEST_PLUGIN=$T "$@" 2>&1 | grep -v '^nvrm\|MESA\|plugshim'; }
old() { "$@" 2>&1 | grep -v '^nvrm\|MESA'; }
lim() { ( "$@" & p=$!; (sleep 120 >/dev/null 2>&1 </dev/null; kill $p 2>/dev/null) >/dev/null 2>&1 & w=$!; wait $p; kill $w 2>/dev/null ); }
echo "== sarray1 NEW"; lim new ./sarray1 | tail -1
echo "== sarray"; lim new ./sarray | tail -1
echo "== slib OLD"; lim old ./slib | tail -1; echo "== slib NEW"; lim new ./slib | tail -1
echo "== gfx4t NEW"; lim new ./gfx4t | tail -2
echo "== chainstress"; lim new ./chainstress $T $ICD | tail -2
for t in unitylock rparktest tiledmips; do echo "== $t"; lim new ./$t | tail -2; done
echo "== rtcheck OLD"; lim old ./rtcheck | tail -6; echo "== rtcheck NEW"; lim new ./rtcheck | tail -6
echo "== earlyz NEW"; lim new ./earlyz | tail -3
for t in drawbench upbench newsurf; do echo "== $t OLD"; lim old ./$t | tail -2; echo "== $t NEW"; lim new ./$t | tail -2; done
echo "== bench_vt_transfer OLD"; lim old ./bench_vt_transfer | tail -2; echo "== bench_vt_transfer NEW"; lim new ./bench_vt_transfer | tail -2
echo "== regression NEW"; SHIM_ICD=$ICD ./run2.sh $T 2>&1 | grep -v '^nvrm\|MESA'
echo ALLDONE
