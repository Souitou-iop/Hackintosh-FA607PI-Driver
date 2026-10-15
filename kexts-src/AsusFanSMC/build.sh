#!/bin/bash
# build AsusFanSMC.kext (VirtualSMC plugin). Headers: MacKernelSDK, Lilu, VirtualSMC SDK in ../deps.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); DEPS=$HERE/../deps
OUT="$HERE/build"; K="$OUT/AsusFanSMC.kext"; rm -rf "$OUT"; mkdir -p "$K/Contents/MacOS"
DEFS=(-DPRODUCT_NAME=AsusFanSMC -DMODULE_VERSION=1.0.0 -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT)
INC=(-nostdinc -I"$DEPS/MacKernelSDK/Headers" -I"$DEPS/Lilu/Lilu" -I"$DEPS/VirtualSMC")
CXX=(-arch x86_64 -fapple-kext -mkernel -std=c++17 -fno-rtti -fno-exceptions -fno-builtin -fno-common -fno-stack-protector -mno-red-zone -O2 -Wall -Wno-unused-parameter -Wno-inconsistent-missing-override -Wno-deprecated-declarations)
xcrun clang++ "${CXX[@]}" "${INC[@]}" "${DEFS[@]}" -c "$HERE/AsusFanSMC.cpp" -o "$OUT/a.o"
xcrun clang -arch x86_64 -mkernel -nostdinc -I"$DEPS/MacKernelSDK/Headers" -c "$HERE/kmod_info.c" -o "$OUT/ki.o"
xcrun clang++ -arch x86_64 -fapple-kext -nostdlib -Xlinker -kext -L"$DEPS/MacKernelSDK/Library/x86_64" -L"$DEPS/MacKernelSDK/Library/universal" -lkmodc++ -lkmod -lcc_kext "$OUT/a.o" "$OUT/ki.o" -o "$K/Contents/MacOS/AsusFanSMC"
cp "$HERE/Info.plist" "$K/Contents/Info.plist"
echo "built $K  $(shasum -a 256 "$K/Contents/MacOS/AsusFanSMC" | cut -c1-16)"
