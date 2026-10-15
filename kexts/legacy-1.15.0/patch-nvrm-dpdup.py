#!/usr/bin/env python3 -I
# NVRM 1.15.0 (+ patch-nvrm-1150.py, sha 9794974b): DisplayPort::GroupImpl::insert() never checks whether the device is
# already a member. NVKMS inserts a device at every head attach (DPAttachBeginOneHead) and again when the DP library reports
# it anew (nvDPAddDeviceToActiveGroup), so the group can hold [A, A]. LinkedList::next(A) then always finds the first A and
# returns the second: every loop over the group's devices (ConnectorImpl::notifyDetachEnd's first one) spins forever.
# WindowServer's main thread hung there at login on 2026-10-15 (4 watchdog reports, external DP monitor, mode set at login).
# Fix: insert() skips the list insertion when the device is already a member (the rest of insert() runs as before - the
# same path it takes when its allocation fails). The check lives in the zero slack at the end of __TEXT (r-x, in file).
# Usage: patch-nvrm-dpdup.py <NVRM in> <NVRM out>
import sys, struct
d = bytearray(open(sys.argv[1], 'rb').read())
INS_MOV = 0x38c4ae            # movl $0x20,%edi  (before callq _dpMalloc at 0x38c4b3)
AFTER_MOV = 0x38c4b3
SKIP = 0x38c50b               # after the list insertion (where a failed allocation goes)
CAVE = 0xd7ef00               # zero slack after __TEXT,__ustring (ends 0xd7e4ec); __TEXT ends 0xd7f000
assert d[INS_MOV:INS_MOV + 5] == bytes.fromhex('bf20000000'), 'insert(): unexpected bytes'
assert d[AFTER_MOV:AFTER_MOV + 1] == b'\xe8' and d[SKIP:SKIP + 4] == bytes.fromhex('48c74424'), 'insert(): layout'
assert not any(d[CAVE - 0x100:0xd7f000]), 'cave area is not zero'
rel = lambda src_end, dst: struct.pack('<i', dst - src_end)
c = bytearray()
c += bytes.fromhex('4d8d4638')           # lea r8,[r14+0x38]        the group's member list (sentinel)
c += bytes.fromhex('4c89c1')             # mov rcx,r8
L = len(c)
c += bytes.fromhex('488b4908')           # L: mov rcx,[rcx+8]       next element
c += bytes.fromhex('4c39c1')             # cmp rcx,r8
c += bytes.fromhex('740c')               # je ORIG                   end of list: not a member
c += bytes.fromhex('48395918')           # cmp [rcx+0x18],rbx        element's device == this device?
p = len(c); c += b'\x0f\x84' + b'\0\0\0\0'   # je SKIP
c += b'\xeb' + bytes([(L - (len(c) + 2)) & 0xff])  # jmp L
ORIG = len(c)
assert c[L + 7 + 1] + (L + 9) == ORIG, 'je ORIG displacement'
c += bytes.fromhex('bf20000000')         # ORIG: mov edi,0x20        (the displaced instruction)
q = len(c); c += b'\xe9' + b'\0\0\0\0'   # jmp AFTER_MOV
c[p + 2:p + 6] = rel(CAVE + p + 6, SKIP)
c[q + 1:q + 5] = rel(CAVE + q + 5, AFTER_MOV)
d[CAVE:CAVE + len(c)] = c
d[INS_MOV:INS_MOV + 5] = b'\xe9' + rel(INS_MOV + 5, CAVE)
open(sys.argv[2], 'wb').write(d)
print(f'patched: insert() at {INS_MOV:#x} -> cave {CAVE:#x} ({len(c)} bytes)')
