#!/bin/bash
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); DEPS=$HERE/../deps; LILU=$DEPS/Lilu; MKSDK=$DEPS/MacKernelSDK
OUT="$HERE/build"; K="$OUT/AACELDOff.kext"; rm -rf "$OUT"; mkdir -p "$K/Contents/MacOS"
DEFS=(-DPRODUCT_NAME=AACELDOff -DMODULE_VERSION=1.1.0 -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT -DLILU_KEXTPATCH_SUPPORT)
INC=(-nostdinc -I"$MKSDK/Headers" -I"$LILU/Lilu")
CXX=(-arch x86_64 -fapple-kext -mkernel -std=c++17 -fno-rtti -fno-exceptions -fno-builtin -fno-common -fno-stack-protector -mno-red-zone -O2 -Wall -Wno-unused-parameter -Wno-inconsistent-missing-override -Wno-deprecated-declarations)
xcrun clang++ "${CXX[@]}" "${INC[@]}" "${DEFS[@]}" -c "$HERE/kern_aaceldoff.cpp" -o "$OUT/a.o"
xcrun clang++ "${CXX[@]}" "${INC[@]}" "${DEFS[@]}" -c "$LILU/Lilu/Library/plugin_start.cpp" -o "$OUT/ps.o"
xcrun clang -arch x86_64 -mkernel -nostdinc -I"$MKSDK/Headers" -c "$HERE/kmod_info.c" -o "$OUT/ki.o"
xcrun clang++ -arch x86_64 -fapple-kext -nostdlib -Xlinker -kext -L"$MKSDK/Library/x86_64" -L"$MKSDK/Library/universal" -lkmodc++ -lkmod -lcc_kext "$OUT/a.o" "$OUT/ps.o" "$OUT/ki.o" -o "$K/Contents/MacOS/AACELDOff"
cp "$HERE/Info.plist" "$K/Contents/Info.plist"
echo "built $K"
