#!/usr/bin/env python3 -I
# findsites.py OLD NEW off[:name] ...  -> locate each OLD offset in NEW by the bytes around it (widest unique window)
import sys
old = open(sys.argv[1], 'rb').read(); new = open(sys.argv[2], 'rb').read()
for a in sys.argv[3:]:
    off, _, name = a.partition(':'); off = int(off, 16)
    found = None
    for before, after in ((32, 32), (24, 24), (16, 24), (8, 24), (16, 16), (0, 24), (12, 12), (0, 16)):
        pat = old[off - before:off + after]
        hits = []; i = new.find(pat)
        while i >= 0 and len(hits) < 3: hits.append(i + before); i = new.find(pat, i + 1)
        if len(hits) == 1: found = (hits[0], before, after); break
    if found: print(f'{name:28s} {off:#9x} -> {found[0]:#9x}  delta {found[0]-off:+#x}  (window -{found[1]}/+{found[2]})')
    else: print(f'{name:28s} {off:#9x} -> NOT UNIQUE/NOT FOUND')
