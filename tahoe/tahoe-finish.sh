#!/bin/bash
# Runs at every boot (LaunchDaemon local.tahoe-finish) until macOS 26 is up, then once: puts the macOS 26 NVAccel
# (our 1.15.0 + GPU sensors build, /Library/NullMoth/kexts/26) in /Library/Extensions, rebuilds the auxiliary kernel
# collection, checks all four NullMoth kexts are in it, removes itself and restarts. On macOS 15 it does nothing.
# Log: /Library/NullMoth/tahoe-finish.log
exec >> /Library/NullMoth/tahoe-finish.log 2>&1
echo "== $(date) macOS $(sw_vers -productVersion)"
MAJ=$(sw_vers -productVersion | cut -d. -f1)
[ "$MAJ" = 26 ] || { echo "still on macOS $MAJ - waiting for the update"; exit 0; }
SRC=/Library/NullMoth/kexts/26/NVAccel.kext; EXT=/Library/Extensions; KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
[ -f "$SRC/Contents/MacOS/NVAccel" ] || { echo "STOP: no $SRC"; exit 1; }
B=/Library/NullMoth/tahoe-finish-backup-$(date +%Y%m%d-%H%M%S); mkdir -p "$B"
ditto "$EXT/NVAccel.kext" "$B/NVAccel.kext"; cp -p "$KC" "$B/AuxiliaryKernelExtensions.kc"
rm -rf "$EXT/NVAccel.kext" && ditto "$SRC" "$EXT/NVAccel.kext" && chown -R root:wheel "$EXT"/NV*.kext && chmod -R go-w "$EXT"/NV*.kext || { echo "STOP: copy"; exit 1; }
KARG=(--allow-missing-kdk); [ -f /System/Library/Kernels/kernel ] && KARG+=(--kernel /System/Library/Kernels/kernel)
kmutil create -n aux --volume-root / "${KARG[@]}" -B /System/Library/KernelCollections/BootKernelExtensions.kc \
  -S /System/Library/KernelCollections/SystemKernelExtensions.kc --repository "$EXT" -A "$KC.new" -z
INS=$(kmutil inspect -a x86_64 -A "$KC.new" 2>/dev/null)
for k in NVRM NVAccel NVRMFB NVRMAGDC; do echo "$INS" | grep -q "com.nullmoth.$k" || {
  echo "STOP: com.nullmoth.$k missing from the new collection - macOS 15 NVAccel put back"; rm -f "$KC.new"
  rm -rf "$EXT/NVAccel.kext"; ditto "$B/NVAccel.kext" "$EXT/NVAccel.kext"; exit 1; }; done
mv -f "$KC.new" "$KC"; echo 26 > /Library/NullMoth/os-major
echo "macOS 26 NVAccel installed (backup $B); restarting"
rm -f /Library/LaunchDaemons/local.tahoe-finish.plist
sleep 2; /sbin/shutdown -r now
