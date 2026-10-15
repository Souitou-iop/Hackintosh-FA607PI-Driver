#!/usr/bin/env python3 -I
# 2.0.0 port of patch-nvrm-1150.py: the same bytes, re-found in the 2.0.0 binary (port200/findsites.py, 64-byte windows):
# kapi sites +0x280, autoGo +0x60. Accepts the stock binary or an already-patched one; every byte is asserted first.
# Offsets were re-derived 2026-10-12: same instruction shapes and spacing as 1.9.0, and NVRMFB 1.14.1 writes
# layerRequestedConfig[PRIMARY].config.srcWidth/srcHeight at 0x18e/0x190 of NvKmsKapiHeadRequestedConfig (mode at 0x48).
#  1. head-scaler (HiDPI): ViewPortIn = layer source size; sizeOut from the source size (0x4e/0x50) instead of 0x56/0x58
#  2. flip-at-boot: autoGo's IOSleep(60000) -> IOSleep(0) (zero-copy flip starts before WindowServer's first frame)
# Usage: patch-nvrm-1141.py NVRM
import sys
f = sys.argv[1]
d = bytearray(open(f, 'rb').read())
def want(off, orig, new, what):
    orig, new = bytes.fromhex(orig), bytes.fromhex(new)
    cur = bytes(d[off:off + len(orig)])
    assert cur == orig or cur == new, f'{what}: bytes at {off:#x} are neither original nor patched ({cur.hex()})'
    d[off:off + len(orig)] = new
# _ApplyModeSetConfig (0x3f8f70+0x280): movzwl 0x50(%r12)/0x64(%r12) -> 0x110/0x112(%rbx)  =>  movl 0x18e(%r12),%eax; movl %eax,0x110(%rbx)
want(0x3f9445, '410fb744245066898310010000410fb744246466898312010000',
     '418b84248e010000' + '898310010000' + '660f1f440000' * 2, 'viewport block')
# _NvKmsKapiLayerConfigToKms (0x3fa620+0x280): movzwl 0x56/0x58(%r15) -> 0x4e/0x50
for off, o, n in ((0x3faab8, 0x56, 0x4e), (0x3faacd, 0x58, 0x50), (0x3facbc, 0x56, 0x4e), (0x3facc9, 0x58, 0x50)):
    assert d[off - 2] == 0xb7, hex(off)
    want(off, f'{o:02x}', f'{n:02x}', f'sizeOut byte {off:#x}')
want(0x94c7, 'bf60ea0000', 'bf00000000', 'autoGo flip delay')          # movl $0xea60,%edi; call _IOSleep
want(0x48be43, '36302073', '20302073', 'autoGo flip log text')          # "(60 s after the release)" -> "( 0 s ..."
open(f, 'wb').write(d)
print('patched', f)
