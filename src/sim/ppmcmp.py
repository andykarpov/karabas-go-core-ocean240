#!/usr/bin/env python3
"""Compare two frames of the raster (768 x 320 PPM of tb_schem / sim_ocean): the picture only.
The grey (40) of the blanks is drawn from the raw GC / GK by both testbenches and is not compared; the shorter
frame bounds the compare (a frame ends at the next VS).  ppmcmp.py A.ppm B.ppm  -> exit 1 on a difference."""
import gzip
import sys


def load(f):
    d = (gzip.open(f) if f.endswith('.gz') else open(f, 'rb')).read().split(b'\n', 3)[3]
    return bytes(0 if v == 40 else v for v in d)


a, b = load(sys.argv[1]), load(sys.argv[2])
n = min(len(a), len(b)) // 3 * 3
w = 768
bad = [i // 3 for i in range(0, n, 3) if a[i:i + 3] != b[i:i + 3]]
if bad:
    for p in bad[:5]:
        y, x = divmod(p, w)
        print(f'  y {y} x {x}: {tuple(a[p * 3:p * 3 + 3])} vs {tuple(b[p * 3:p * 3 + 3])}')
    print(f'  {len(bad)} points differ of {n // 3}')
    sys.exit(1)
print(f'  {n // 3} points equal')
