#!/usr/bin/env python3 -I
# NullMoth 1.15.0 NVRMFB: the two 1.14.2 patches, re-found in the 1.15.0 binary.
#  1. scaler / scanout-allocation height cap 2160 -> 2400 (HiDPI backings taller than 2160). 1.15 computes 2H in %esi
#     (1.14.2: %ecx): cmpl $2160,%esi; movl $2160,%r12d at 0x3b10.
#  2. vramGrant(): skip the uncached BAR1 clear of every new VRAM block (rep stosq -> nop; canary write kept) at 0x10bd5.
# Accepts the stock binary or an already-patched one; every byte is asserted first.
import sys
f = sys.argv[1]; d = bytearray(open(f, 'rb').read())
def want(off, orig, new, what):
    orig, new = bytes.fromhex(orig), bytes.fromhex(new); cur = bytes(d[off:off+len(orig)])
    assert cur in (orig, new), f'{what}: {off:#x} has {cur.hex()}'
    d[off:off+len(orig)] = new
want(0x3b10, '81fe70080000', '81fe60090000', 'cmpl $2160,%esi -> $2400')
want(0x3b16, '41bc70080000', '41bc60090000', 'movl $2160,%r12d -> $2400')
want(0x10bd5, '4c89e148c1e90331c04c89eff348ab31c031c9f3aa48b801eeffc0a5a55a5a', '4c89e148c1e90331c04c89ef0f1f0031c031c9669048b801eeffc0a5a55a5a', 'vramGrant BAR clear -> nop')
open(f, 'wb').write(d); print('patched', f)
