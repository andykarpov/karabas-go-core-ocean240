# Ocean-240 core for Karabas Go / Mini / Mini G

[Русская версия](README.ru.md)

A core of the Soviet personal computer Ocean-240.2 («Океан-240.2», D. A. Tilinin, the Institute of Oceanology of the USSR Academy of Sciences, 1985–1986) for the Karabas Go board family (Xilinx Spartan-6 XC6SLX25): KR580VM80A at 2.4576 MHz, 128 KB of RAM (the main 64 KB and a 64 KB RAM disk), 512 × 256 monochrome or 256 × 256 graphics in 4 colours of 8 palettes, the hardware screen scrolling of the 240.2, KR580VV55 × 3, KR580VI53, KR580VN59, KR580VV51, the KR1818VG93 floppy controller with two drives, the tape, the bell.

| Board | Video | Sound |
|---|---|---|
| Karabas Go | VGA | I2S DAC (PCM5102) |
| Karabas Mini | HDMI | HDMI, analog output (sigma-delta) |
| Karabas Mini G | HDMI | HDMI, I2S DAC |

The core file `src/ocean240.kg` is one file for all three boards; all the ROMs are inside it.

Status: checked on Mini G (both CP/M, both keyboards, the RAM disk kept on the card, the test program of MPSS with the tape loop, the serial port). The floppy reads and writes `.okd` images (checked on Mini G). The Go and Mini builds have not been run on a board yet.

Contents: [Getting started](#getting-started) · [Models](#models) · [OSD menu](#osd-menu) · [Keys](#keys) · [Files](#files) · [The serial port](#the-serial-port) · [Where to get software](#where-to-get-software) · [How the core works](#how-the-core-works) · [Building](#building) · [Tests](#tests) · [Licence and sources](#licence-and-sources)

## Getting started

1. Copy `src/ocean240.kg` to the root of the SD card. The firmware makes `/ocean240/saves` for the RAM disk by itself; put tape recordings (`.wav`) into `/ocean240`.
2. Choose Ocean-240 in the core menu. The model 240.2 starts: the 240/7 monitor boots CP/M, `OKEAH-240 CP/M (V2.2) REL.5` and `A>`.
3. `DIR` lists drive A:, the RAM disk. What is written there stays: the core saves it to the card a second after the last write and reads it back when the core is loaded again.

"Menu" is the Windows key of the keyboard.

## Models

The OSD item Model picks the ROMs and the keyboard; all the models have the screen scrolling of the 240.2.

| Model | ROMs | Keyboard |
|---|---|---|
| 240.2 | the 240/7 monitor + CP/M V2.2 REL.5 | the ASCII keyboard of the 240 |
| Turbo | HARDWARE MONITOR+ + CP/M V2.2 REL.7/2D with the floppy: B: and C: are the two sides of Floppy 1 | the positional keyboard of the 240.2 |
| Test | the test program of MPSS 1987/3 (its menu and results on the serial port) | the ASCII keyboard |

Both CP/M keep drive A: in the same place and format: the RAM disk is shared by 240.2 and Turbo. The model Test does not use it (the tests write all the RAM).

## OSD menu

| Item | Values | Hotkey |
|---|---|---|
| Model | 240.2 / Turbo / Test: a change resets the machine | Menu+M |
| Colours | Replica / MPSS: the wiring of the colour PROM outputs of the replica of Roman Boykov, or that of the colour table in MPSS | |
| Tape monitor | Off / In / Out / Both: the tape signals heard in the sound | Menu+T |
| Reset | the reset button of the machine (the RAM disk stays) | F12 |
| Tape | a `.wav` recording: it plays at once into the tape input (the machine keeps running) | Menu+F4 |
| Tape play, Tape stop | the `.wav` from its start again / stop | |
| Floppy 1, Floppy 2 | a `.okd` floppy image in drive 0 / 1 (read and write) | Menu+F7, Menu+F8 |

While no recording plays, the tape input of the board (TAPE_IN) is the input of the machine. The tape output goes to TAPE_OUT of the board.

## Keys

The keys are those of a US PC keyboard. The monitor and CP/M work in capital letters: a letter gives the capital, Shift+letter the small one.

| Host key | Ocean |
|---|---|
| Enter | ВК (0D) |
| Backspace | ← (08) |
| Esc | АР2 (1B) |
| Tab | ТАБ (09) |
| ←, →, ↑, ↓ | 08, 18, 19, 1A: the cursor keys of the 240/7 monitor (240.2 keyboard) |
| Delete | 7F (240.2 keyboard) |
| End | `_` (Turbo keyboard) |
| Ctrl+letter | the control code 01–1A; on the Turbo keyboard Ctrl and Shift are its own УС / РЕГ keys |
| F12 | reset |

The Turbo keyboard is positional (the matrix of MAME `okean240a`): the program reads the row and the column; the keypad digits are separate keys there. There is no РУС/ЛАТ key yet.

## Files

- `/ocean240/saves/ramdisk.sav`: the RAM disk, a raw image of the 64 KB of page 1 of the RAM, made by the firmware (zeros: CP/M formats it on the first start). In CP/M terms: 128-byte sectors, 16 sectors a track, 32 tracks, 1 KB blocks (64), 32 directory entries, no system tracks. Delete the file for an empty disk.
- `.okd`: a floppy image (the format of Emu80): 80 tracks × 2 sides × 9 sectors of 512 bytes, 737 280 bytes. CP/M REL.7 sees side 0 as B: and side 1 as C:, 360 KB each. The writes go to the image on the card at once.
- `.wav`: a tape recording, PCM 8 or 16 bit, mono or stereo (the left channel), any sample rate, up to 2 MB.
- The ROMs (`src/roms/`, the dumps of the replica of Roman Boykov): `mon240_7.rom` and `cpm_rel5.rom` (240.2), `monplus.rom` and `cpm_rel7.rom` (Turbo), `tests.rom` (Test). The colour PROM is in `src/rtl/ocean/ocean_prom_vc.v`.

## The serial port

The KR580VV51 of the Ocean is connected to the USB serial port of the board (port 0 of the firmware: on Mini G the second interface of the USB-UART). The bytes pass as they are, the speed set in the terminal does not matter. The model Test prints `TEST 1 PASSED` … there and takes its keys from there.

## Where to get software

- [romychs/ocean-240.2](https://github.com/romychs/ocean-240.2): the replica of the 240.2 by Roman Boykov: the schematic, the ROMs, the articles of MPSS, CP/M sources.
- `software/` of this repo: floppy images `.okd` with programs and games (`software/README.md`).
- [alemorf/retro_computers](https://github.com/alemorf/retro_computers), directory `Ocean_240`: scans of MPSS, the BIOS sources, floppy images `.okd` (`software/fdd`), a JS emulator of the 240.2.
- The emulators: MAME (`okean240`, `okean240a`), [Emu80](https://emu80.org/) (its `.okd` floppy images are those of the core).

## How the core works

The core is written from the schematic of the replica of Roman Boykov (KiCad) and the articles of D. A. Tilinin in «Микропроцессорные средства и системы» (1986/2, 1986/4, 1987/3):

- a model of the whole schematic made from its netlist (`src/sim/schem`, Icarus) is the reference: the frames of the core are those of the schematic, point for point;
- one clock of 49.2 MHz (4 × the 12.288 MHz crystal, +0.1 %) with enables: the CPU (the KR580VM80A model of Vslav) at 2.4576 MHz;
- the memory is the SRAM of the board: 512 KB of RAM (the pages of port C1) and the ROMs; the video RAM (C000–FFFF of its page) is also copied into block RAM, so the video never waits;
- the video keeps the frame of the Ocean: 768 × 320 points of 12.288 MHz (49.99 Hz), each line shown twice: 768 × 640 at 24.6 MHz (50.05 Hz, 31.25 kHz), 640 × 576 visible, the 512 × 256 screen in its middle. No frame buffer;
- the controllers of both keyboards: a PC key becomes the code (ASCII for the 240/7 monitor, the row and column for HARDWARE MONITOR+) with the strobe on IR1 of the KR580VN59;
- the RAM disk on the card: `kg_bk_ram` of karabas-go-modules keeps page 1 in a file. A cold start of CP/M formats the RAM disk unless 0006 holds the address of its BDOS (the check that keeps the disk over the reset button of the real machine): the core writes it before the CPU starts when the file has data;
- the floppy controller: the KR1818VG93 (the wd1793 of vector06cc / MiSTer) at 20–23, the wait of port 24 (the CPU stops until DRQ or INTRQ, as READY of the original controller), port 25 (the drive, the side, the motor); the images are copied into the SRAM in the background and written through to the card;
- the tape output is the 3-bit DAC of the schematic (E2 C0–C2) with its differentiating circuit; the input takes a `.wav` from the card or TAPE_IN.

Sources: `src/rtl/ocean/` (the machine), `src/rtl/karabas_*_top.v` (the boards: Go and Mini are made from the Mini G top by `src/tools/mktops.py`), `docs/PLAN.md` and `docs/HARDWARE.md` (in Russian: the plan, the ports, the memory, the video).

## Building

ISE 14.7. `cd src && make` builds all three boards and `ocean240.kg`; `make minig` (or `go`, `mini`) one board, `make minig-report` its size and timing. `make ocean-xst` synthesises the machine alone. Clone with `--recursive` (the `modules` submodule). The upstream sources for reference: `tools/fetch_upstream.sh`.

## Tests

`src/sim/run.sh` (Verilator, about a minute): the test program of MPSS (`TEST 1 PASSED`, the timer and interrupt test 8), the video frames against the frames of the schematic model (`src/sim/ref`), the RAM disk unit test. `CPM=1` adds both CP/M up to `A>` and `DIR` typed through the keyboard controller; `TAPE=1` the tape loop (test 5 into a `.wav`, test 6 reads it); `FDD=1` (`software/fdd/disk1.okd`) or `FDD=<an .okd image>` CP/M REL.7 writing a file onto C: of it (some 3 minutes). `src/sim/schem/run.sh` runs the schematic model itself.

## Licence and sources

The core is GPL v3 (`LICENSE`). Its parts keep their licences: the schematic and the ROM dumps of the replica of Roman Boykov (BSD-3), the KR580VM80A model of Vslav / 1801BM1 (CC BY 3.0), the KR580VV55 of Dmitry Tselikov (BSD), the KR580VI53 of Sorgelig (GPL-3), the wd1793 of Viacheslav Slavinsky and Sorgelig (GPL-2+), KF8259 of Kitune-san (MIT), the modules of karabas-go-modules.
