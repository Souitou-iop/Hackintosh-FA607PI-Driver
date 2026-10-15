#!/bin/bash
# build nvddc (CLI) and NVBrightness.app. Headers: NVIDIA open-gpu-kernel-modules 610.57.04 (the RM NullMoth 1.14.x ships).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); O=$HERE/../deps/ogkm
[ -d "$O/src" ] || { git clone -q --depth 1 --branch 610.57.04 --filter=blob:none --sparse https://github.com/NVIDIA/open-gpu-kernel-modules.git "$O"; git -C "$O" sparse-checkout set src/common/sdk/nvidia/inc kernel-open/common/inc src/nvidia/arch/nvalloc/unix/include; }
INC=(-I"$O/src/common/sdk/nvidia/inc" -I"$O/kernel-open/common/inc" -I"$O/src/nvidia/arch/nvalloc/unix/include")
cd "$HERE"
xcrun clang -O2 -Wall -Wno-unused-function "${INC[@]}" -framework IOKit -o nvddc nvddc.c
A=NVBrightness.app; rm -rf $A; mkdir -p $A/Contents/MacOS
xcrun clang -O2 -fobjc-arc -Wall -Wno-unused-function -DNVDDC_LIB "${INC[@]}" -framework Cocoa -framework IOKit -framework ApplicationServices -o $A/Contents/MacOS/NVBrightness NVBrightness.m nvddc.c
cat > $A/Contents/Info.plist <<'PL'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.hackintosh.NVBrightness</string>
<key>CFBundleName</key><string>NVBrightness</string>
<key>CFBundleExecutable</key><string>NVBrightness</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PL
codesign -f -s - --identifier local.hackintosh.NVBrightness $A
echo "built $HERE/nvddc and $HERE/$A"
