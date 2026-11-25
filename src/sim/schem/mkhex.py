#!/usr/bin/env python3
"""ROM images -> $readmemh files for the schematic model.
  mkhex.py rom IN.bin OUT.hex    one byte per line, the image repeated to fill 32 KB (27256: A13 / A14 then do not matter)
  mkhex.py prom IN.bin OUT.hex   256 x 4 PROM, low nibble of each byte
  rom ... OFF=XX ...             sim-only patches of the image (offset in the file, hex)
"""
import sys

kind, src, dst = sys.argv[1:4]
data = bytearray(open(src, 'rb').read())
for p in sys.argv[4:]:
    off, val = p.split('=')
    data[int(off, 16)] = int(val, 16)
data = bytes(data)
if kind == 'rom':
    size = 32768
    assert size % len(data) == 0, len(data)
    out = (data * (size // len(data)))
    open(dst, 'w').write('\n'.join(f'{b:02x}' for b in out) + '\n')
elif kind == 'prom':
    assert len(data) == 256, len(data)
    open(dst, 'w').write('\n'.join(f'{b & 15:x}' for b in data) + '\n')
else:
    sys.exit(__doc__)
