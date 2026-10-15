#!/usr/bin/env python3
# Ada (RTX 40) fixes for NullMoth 1.14.2's libnvenc_h264.dylib, ported from macOS-4060-laptop-driver-fix fix 15
# (that repo ships only the source fragments; its offsets are for 1.9.0 — this region of 1.14.2 sits 0x140 later).
#   NotSync      0x1665  keyframes no longer get kCMSampleAttachmentKey_NotSync=false (UU waits for a keyframe forever)
#   luma   t2d   0x63aa  bw8 copy loop -> Ada t2d GOB layout (luma.s), back to 0x6330
#   chroma t2d   0x64d9  bw16 copy loop -> t2d (chroma.s), back to 0x6450
#   zeroing      0x3939  call ___bzero on the BAR mapping -> AVX zeroing in the dead enctest_main at 0x1d00
import sys, subprocess, struct, hashlib, os, tempfile
src, dst = sys.argv[1], sys.argv[2]
d = bytearray(open(src, 'rb').read())
EXPECT = 'c78e21aae60f746c'
h = hashlib.sha256(d).hexdigest()
assert h.startswith(EXPECT), f'unexpected input {h[:16]} (want 1.14.2 stock {EXPECT})'
def asm(path):
    t = tempfile.mkdtemp(); o = t + '/a.o'; b = t + '/a.bin'
    subprocess.check_call(['xcrun', 'clang', '-c', '-arch', 'x86_64', path, '-o', o])
    l = subprocess.check_output(['otool', '-l', o], text=True).split('\n')
    i = next(k for k, x in enumerate(l) if x.strip() == 'sectname __text')
    f = {x.split()[0]: x.split()[1] for x in l[i:i + 8] if len(x.split()) == 2}
    off, size = int(f['offset']), int(f['size'], 16)
    return open(o, 'rb').read()[off:off + size]
def jmp(at, to): return b'\xe9' + struct.pack('<i', to - (at + 5))
def put(off, old, new):
    assert d[off:off + len(old)] == old, f'bytes at {off:#x} differ: {d[off:off+len(old)].hex()} != {old.hex()}'
    d[off:off + len(new)] = new
def region(start, end, body, back):
    code = body + jmp(start + len(body), back)
    assert len(code) <= end - start, f'{len(code)} bytes > region {end-start}'
    d[start:end] = code + b'\x90' * (end - start - len(code))
# NotSync (friend's uu-nvenc-patch.sh, same offset and bytes in 1.14.2)
put(0x1665, bytes.fromhex('4c89fa490f44d44889df'), bytes.fromhex('4c89e24889df75079090'))
# luma: original region 0x63aa..0x640e ends with `jmp 0x6330`; chroma 0x64d9..0x6540 ends with `jmp 0x6450`
assert d[0x6409:0x640e] == jmp(0x6409, 0x6330)[:2] + d[0x640b:0x640e] or d[0x6409] in (0xe9, 0xeb)
assert d[0x6540:0x6547] == bytes.fromhex('4c8b3d794c0000'), 'chroma region end moved'
region(0x63aa, 0x640e, asm('luma.s'), 0x6330)
region(0x64d9, 0x6540, asm('chroma.s'), 0x6450)
# zeroing: cave at 0x1d00 (inside enctest_main, an exported test entry nothing calls)
fz = asm('fz.s'); assert len(fz) <= 0x40
d[0x1d00:0x1d00 + len(fz)] = fz
put(0x3939, b'\xe8' + struct.pack('<i', 0x8312 - 0x393e), b'\xe8' + struct.pack('<i', 0x1d00 - 0x393e))
open(dst, 'wb').write(d)
subprocess.check_call(['codesign', '-f', '-s', '-', dst], stderr=subprocess.DEVNULL)
print('patched', dst, hashlib.sha256(open(dst, 'rb').read()).hexdigest()[:16])
