#!/usr/bin/env python3 -I
# NullMoth 2.0.0 NVRMFB (stock sha bf7a67be): our two NVRMFB patches, redone for 2.0.0.
#  1. Scanout ceilings (computeScanoutCaps, 0x6c10): 2.0.0 sizes the scaler/raster ceilings and the scanout allocation from
#     the panel's largest NVKMS-validated mode (2x boot only when that list is empty). A HiDPI backing larger than the
#     panel - 3840x2160 for "looks like 1920x1080" on the 2560x1440 external, 3840x2400 on the 2560x1600 panel - is then
#     never offered. Before 2.0.0 the ceiling was 2x boot (capped 3840x2160; our 1.14/1.15 patch raised the height to 2400).
#     Now: max(panel's largest mode, 2x boot) per axis; 2.0.0's own floor (boot) and limit (7680x4320) still apply after.
#     Replaces 0x6d6e..0x6da5 (both entries kept: 0x6d6e loop exit, 0x6d79 early path with r15d = 0, r12d undefined).
#  2. vramGrant(): skip the uncached BAR1 clear of every new VRAM block (rep stosq -> nop; canary write kept) at 0x11ffc.
# Accepts the stock binary or an already-patched one; every byte is asserted first.
import sys
f = sys.argv[1]; d = bytearray(open(f, 'rb').read())
def want(off, orig, new, what):
    orig, new = bytes.fromhex(orig), bytes.fromhex(new); cur = bytes(d[off:off+len(orig)])
    assert len(orig) == len(new) and cur in (orig, new), f'{what}: {off:#x} has {cur.hex()}'
    d[off:off+len(orig)] = new
want(0x6d6e,
     '4585e48bb570ffffff750a448ba3940200004501e48b83980200008d0c004585ff410f45cf8b93940200004139d4410f47d439c10f46c8',
     '8bb570ffffff'          # movl -0x90(%rbp),%esi       loop exit (as the original)
     'eb06' '909090'         # jmp 0x6d7c; pad
     '4531e4'                # 0x6d79: xorl %r12d,%r12d    early path: no mode list
     '8b9394020000' '01d2'   # movl 0x294(%rbx),%edx; addl %edx,%edx      2*fW
     '4439e2' '410f42d4'     # cmpl %r12d,%edx; cmovbl %r12d,%edx         max(2*fW, widest mode)
     '8b8b98020000' '01c9'   # movl 0x298(%rbx),%ecx; addl %ecx,%ecx      2*fH
     '4439f9' '410f42cf'     # cmpl %r15d,%ecx; cmovbl %r15d,%ecx         max(2*fH, tallest mode)
     '0f1f440000' '660f1f440000',  # nops up to 0x6da5 (cmpl $7680,%edx: 2.0.0's own limits follow)
     'computeScanoutCaps')
want(0x11ffc, 'f348ab31c031c9f3aa48b801eeffc0a5a55a5a', '0f1f0031c031c9f3aa48b801eeffc0a5a55a5a', 'vramGrant BAR clear -> nop')
open(f, 'wb').write(d); print('patched', f)
