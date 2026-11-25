# Software for the Ocean-240 core

Copy the `.okd` images into `/ocean240` on the SD card and mount one with Floppy 1 (Menu+F7) in the model Turbo: CP/M REL.7 sees side 0 as B: and side 1 as C:.

| File | What is there |
|---|---|
| `programs.okd` | B: the 17 programs of `programs/` (`.COM`: 2048, CATCHUM, JACK, SOL, TET, MB (BASIC), M80 / L80, WM, PW, RES, TM, ZNG, TYPE, FORMAT, PCGET / PCPUT); C: the 6 BASIC programs (`.BAS`) |
| `fdd/disketa.okd` | most of these programs, with some `.MAC` sources |
| `fdd/disk1.okd` | BASIC.COM; C: BBB.DAT |
| `fdd/oce1_2.okd`, `fdd/oce2_2.okd` | M80 / L80, WM, PW, RES, TM, SUB, DTEST; the second also SID, PRN, G |

`fdd/` and `programs/` come from [alemorf/retro_computers](https://github.com/alemorf/retro_computers) (`Ocean_240/software`, commit 22fc95c), which collected them; the programs are of their authors. `programs.okd` is made of `programs/` by `src/tools/mkokd.py`:

```
python3 src/tools/mkokd.py new software/programs.okd B:software/programs/*.COM C:software/programs/*.BAS
python3 src/tools/mkokd.py ls software/programs.okd
```
