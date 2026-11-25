#!/usr/bin/env python3
"""Video bit-order test ROM (8 KB, at E000) for the schematic model and the core sim.

Writes known bytes into the video RAM (C000 of page 0, through C1 B0 = 32K at 4000), shows them in mono,
waits for two frame blanks (IN 41 bit 1 = GK) and switches to colour (E1 = 48h). The background is red (FL1),
so the frames show the window of BLNK too.
  pattern (address in video RAM: col = A13..A9, row = A7..A0, A8 = byte of the word):
    C000 = 01, C100 = 80   row 0, column 0
    C001 = F0, C101 = 0F   row 1, column 0
    C202 = FF              row 2, column 1, byte A8 = 0
    C303 = FF              row 3, column 1, byte A8 = 1
  mkrom_vidtest.py OUT.bin [scroll]
  scroll: more bytes (columns 0, 1, 15, 30, 31, lines at both ends) and the scrollers on: C0 = 05 (VS), C2 = 0B
  (HS[7:3] = 1 word, SB = 3): the words read in the blank, the wrap of the lines and the point shift.
"""
import sys


def lxi_mvi(addr, val):
    return [0x21, addr & 0xFF, addr >> 8, 0x36, val]


org = 0xE000
code = [0xC3, 0x03, 0xE0, 0xF3,
        0x3E, 0x80, 0xD3, 0xC3, 0xD3, 0xE3,
        0x3E, 0x93, 0xD3, 0x43,
        0x3E, 0x01, 0xD3, 0xC1]
scroll = len(sys.argv) > 2 and sys.argv[2] == 'scroll'
pat = [(0x4000, 0x01), (0x4100, 0x80), (0x4001, 0xF0), (0x4101, 0x0F), (0x4202, 0xFF), (0x4303, 0xFF)]
if scroll:
    def at(col, row, hi, v):
        return (0x4000 + col * 0x200 + hi * 0x100 + row, v)
    for r in range(8):
        pat.append(at(0, r + 8, 0, 0xFF))
        pat.append(at(15, r, 0, 0xAA))
        pat.append(at(31, r, 0, 0x0F))
        pat.append(at(31, r, 1, 0xF0))
        pat.append(at(30, r + 4, 1, 0xFF))
    for r in (0, 1, 2, 3, 252, 253, 254, 255):
        pat.append(at(1, r, 0, 0x3C))
for a, v in pat:
    code += lxi_mvi(a, v)
code += [0x3E, 0x00, 0xD3, 0xC1,
         0x3E, 0x0B if scroll else 0x07, 0xD3, 0xC2,
         0x3E, 0x05 if scroll else 0x00, 0xD3, 0xC0,
         0x3E, 0x08, 0xD3, 0xE1]   # mono, palette 0, background FL1 (red): the visible window shows


def wait(cond_jump):
    # L: IN 41; ANI 02; Jcc L
    here = org + len(code)
    return [0xDB, 0x41, 0xE6, 0x02, cond_jump, here & 0xFF, here >> 8]


code += wait(0xCA)  # JZ: wait GK = 1
code += wait(0xC2)  # JNZ: wait GK = 0
code += wait(0xCA)
code += [0x3E, 0x48, 0xD3, 0xE1]  # colour, palette 0, background red
here = org + len(code)
code += [0xC3, here & 0xFF, here >> 8]
img = bytes(code) + bytes([0xFF] * (8192 - len(code)))
open(sys.argv[1], 'wb').write(img)
