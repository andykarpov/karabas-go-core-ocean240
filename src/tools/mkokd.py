#!/usr/bin/env python3
"""The .okd floppy images of CP/M REL.7/2D of the Ocean (docs/HARDWARE.md, the floppy).

The image (Emu80): 80 tracks x 2 sides x 9 sectors of 512 bytes, track, side, sector order. CP/M sees side 0 as B:
and side 1 as C: (DPB D94C of the ROM: 2 KB blocks, DSM 179: 180 blocks = 80 tracks x 9 sectors, DRM 63: the
directory is block 0, 8-bit block numbers, EXM 1). The data starts at track 0 of the side; the 512-byte sectors of a
track go in the order of the interleave of the BIOS (D8B2): logical sector i is the sector with the number
ILV[i] (image index ILV[i] - 1). Checked on disk1.okd of alemorf (BASIC.COM: its first block is the sector 2).

  mkokd.py ls IMAGE                          the files of B: and C:
  mkokd.py get IMAGE B|C NAME OUT            a file out
  mkokd.py new IMAGE [B:FILE ...] [C:FILE ...]  a new image with these files (E5 elsewhere); B:a* C:b* globs
"""
import os
import sys

TRACKS, SECT, SSIZE = 80, 9, 512
ILV = [1, 8, 6, 4, 2, 9, 7, 5, 3]
BLOCK = 2048
BLOCKS = 180
DIRENT = 64
SIZE = TRACKS * 2 * SECT * SSIZE


def sec_off(side, n):
    """the image offset of logical 512-byte sector n of a side"""
    t, i = divmod(n, SECT)
    return ((t * 2 + side) * SECT + ILV[i] - 1) * SSIZE


def block_read(img, side, b):
    return b"".join(img[sec_off(side, b * 4 + k):sec_off(side, b * 4 + k) + SSIZE] for k in range(4))


def block_write(img, side, b, data):
    data = data.ljust(BLOCK, b"\x1a")
    for k in range(4):
        o = sec_off(side, b * 4 + k)
        img[o:o + SSIZE] = data[k * SSIZE:(k + 1) * SSIZE]


def entries(img, side):
    d = block_read(img, side, 0)
    for j in range(DIRENT):
        e = d[j * 32:(j + 1) * 32]
        if e[0] != 0xE5:
            yield e


def name83(e):
    n = bytes(c & 0x7F for c in e[1:9]).decode("ascii", "replace").rstrip()
    x = bytes(c & 0x7F for c in e[9:12]).decode("ascii", "replace").rstrip()
    return n + ("." + x if x else "")


def files(img, side):
    fs = {}
    for e in entries(img, side):
        fs.setdefault((e[0], name83(e)), []).append(e)
    out = {}
    for (user, name), es in fs.items():
        es.sort(key=lambda e: e[12] + 32 * e[14])
        data = b""
        for e in es:
            ext = e[12] + 32 * e[14]
            recs = (ext & 1) * 128 + e[15]   # EXM 1: the entry ends in its second logical extent
            blocks = [b for b in e[16:32] if b]
            raw = b"".join(block_read(img, side, b) for b in blocks)
            data += raw[:recs * 128]
        out[name] = data
    return out


def new(path, specs):
    img = bytearray(b"\xE5" * SIZE)
    for side in (0, 1):
        names = [f for s, f in specs if s == side]
        dirb = bytearray(b"\xE5" * BLOCK)
        nb, ne = 1, 0
        for f in names:
            data = open(f, "rb").read()
            base = os.path.basename(f).upper()
            n, _, x = base.partition(".")
            fname = n[:8].ljust(8).encode() + x[:3].ljust(3).encode()
            recs = (len(data) + 127) // 128
            # an entry covers 32 KB (16 blocks, logical extents 2k and 2k + 1)
            for ext in range(0, max(1, (recs + 255) // 256)):
                part = data[ext * 32768:(ext + 1) * 32768]
                prec = (len(part) + 127) // 128
                blocks = []
                for k in range(0, len(part), BLOCK):
                    if nb >= BLOCKS:
                        sys.exit("mkokd.py: side %d full at %s" % (side, f))
                    block_write(img, side, nb, part[k:k + BLOCK])
                    blocks.append(nb)
                    nb += 1
                if ne >= DIRENT:
                    sys.exit("mkokd.py: directory of side %d full" % side)
                lext = ext * 2 + (1 if prec > 128 else 0)
                rc = prec - 128 if prec > 128 else prec
                e = bytes([0]) + fname + bytes([lext & 31, 0, lext >> 5, rc]) + bytes(blocks).ljust(16, b"\0")
                dirb[ne * 32:(ne + 1) * 32] = e
                ne += 1
        block_write(img, side, 0, bytes(dirb))
    open(path, "wb").write(img)


def main(a):
    if len(a) >= 2 and a[0] == "ls":
        img = bytearray(open(a[1], "rb").read())
        for side, drv in ((0, "B"), (1, "C")):
            for name, data in sorted(files(img, side).items()):
                print("%s: %-12s %6d" % (drv, name, len(data)))
    elif len(a) == 5 and a[0] == "get":
        img = bytearray(open(a[1], "rb").read())
        open(a[4], "wb").write(files(img, 0 if a[2].upper() == "B" else 1)[a[3].upper()])
    elif len(a) >= 2 and a[0] == "new":
        specs = []
        import glob
        for s in a[2:]:
            d, _, f = s.partition(":")
            for g in sorted(glob.glob(f)) or [f]:
                specs.append((0 if d.upper() == "B" else 1, g))
        new(a[1], specs)
    else:
        sys.exit(__doc__)


main(sys.argv[1:])
