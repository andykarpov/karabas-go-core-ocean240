# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A core of the Soviet personal computer Ocean-240 / Ocean-240.2 («Океан-240», D. A. Tilinin, 1985–1986: KR580VM80A 2.4 MHz, 128 KB RAM incl. the RAM disk, 16 KB ROM, 512 × 256 mono / 256 × 256 × 4 colours, hardware scrollers on 240.2, KR580VV55 × 4, VI53, VN59, VV51, tape, Bell; VG93 floppy later) for the Karabas Go, Mini and Mini G boards: Xilinx Spartan-6 XC6SLX25, ISE 14.7 (XST).

Status: Ф0 merged into local master (2026-11-25): schematic model of the replica (src/sim/schem), the machine in RTL (src/rtl/ocean), Verilator suite src/sim/run.sh; Ф1 (Mini G) next. All ROMs go into the repo and the `.kg` (user 2026-11-25). Docs, in Russian: `docs/PLAN.md` (sources, decisions, architecture, phases), `docs/HARDWARE.md` (ports, memory, video; a draft with a source per fact until Ф0 checks it on the schematic), `docs/BACKLOG.md`. Follow the phases; record a changed decision in PLAN.md.

All file work goes through the firmware (OSD, `FL` / `F` items, burst): no loader or soft CPU in the core. The core is our own model written from the schematic of the 240.2 replica by romychs (`upstream/ocean-240.2`, BSD-3) and the MPSS articles; MAME `okean240.cpp`, Emu80, the JS emulator of alemorf and the FPGA version of AndrejChoo are references only (alemorf's repo has no licence: copy nothing from it). Get them with `tools/fetch_upstream.sh` (git-ignored). The core is GPL v3 (`LICENSE`).

Pieces from our cores: `../karabas-go-core-vector06c` (8080 machine of the same kind: tops, Makefile, sram wrapper, k580vv55 / k580vi53, scan doubler, sim harness, tape), `../karabas-go-core-specialist` / `../karabas-go-core-rk` (vm80a), `../karabas-go-core-pcxt` (KF8259, MIT), `../karabas-go-core-orionpro` (8251 over `kg_mcu_uart`).

## Rules of the core

The rules of vector06c / specialist apply: one clock with enables (no `negedge`, no derived clocks), syncs always present, `FT_CLK_OUT` about 8 MHz on Mini / Mini G, Go `FDC_*` outputs 0 when unused, SDRAM idle (Mini G2 `~CS` = FLASH_CS_N, drive 1), OSD switch index = item position unless `"index"`, an OSD value shows 10 characters at most, Verilog-2001 for XST.

- The model is chosen in the OSD (user 2026-11-25): presets over scrollers, keyboard type, ROM set, ports 20–25, RAM size.
- The base board set goes into phase 1: audio peaks, tape in / out + tape monitor, MIDI_TX, ADC line in, FT_CLK_OUT.
- Floppy (VG93): after the v1 release, but keep ports 20–25 free in the decoder.
- `karabas-go-modules` is shared with other sessions: change it only in a git worktree, PR there, then move the submodule.
- Before a step that needs the board or the HDMI capture, tell the user; capture frames only after a yes; ask before a firmware flash. OSD look: a frame and the user's yes before a merge.
- One branch per phase of `docs/PLAN.md`, one PR at its end (local master until the repo is public; the repo stays local until the user says).

## Memory

The Claude Code memory of this repo is shared with all karabas-go repos: `~/.claude/projects/<this project>/memory` is a symlink to `../karabas-go-notes` (private repo `andykarpov/karabas-go-notes`, `link.sh` there makes the links). Its `MEMORY.md` is split by repo; commit and push it after every memory change.
