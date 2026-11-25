#!/usr/bin/env python3
"""PPM -> PNG (no libraries), each line doubled for a 4:3-ish look.  ppm2png.py IN.ppm OUT.png [scale_y]"""
import struct
import sys
import zlib

d = open(sys.argv[1], 'rb').read().split(b'\n', 3)
w, _ = map(int, d[1].split())
px = d[3]
h = len(px) // (w * 3)
sy = int(sys.argv[3]) if len(sys.argv) > 3 else 2
raw = b''.join((b'\x00' + px[y * w * 3:(y + 1) * w * 3]) * sy for y in range(h))


def chunk(t, b):
    return struct.pack('>I', len(b)) + t + b + struct.pack('>I', zlib.crc32(t + b) & 0xffffffff)


open(sys.argv[2], 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h * sy, 8, 2, 0, 0, 0))
                              + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))
