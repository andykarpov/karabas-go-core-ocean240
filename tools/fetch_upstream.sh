#!/bin/sh
# Fetch the Ocean-240 reference sources into upstream/ (git-ignored), pinned commits.
#  - romychs/ocean-240.2 (BSD-3): KiCad schematic of the 240.2 replica, ROM dumps, the MPSS articles (.odt) — the base
#  - AndrejChoo/Ocean240_on_FPGA (GPL-3): a functional FPGA version (Cyclone 10LP) — reference for ports / palettes only
#  - alemorf/retro_computers (no licence file; reference, its fdd images and programs copied into software/ with the
#    user's leave 2026-11-25): Ocean_240 only — MPSS scans, ROM sources, JS emulator, fdd images
#  - MAME src/mame/ussr/okean240.cpp (BSD-3): one file, the ROM hashes and the keyboard tables
set -eu
cd "$(dirname "$0")/.."
mkdir -p upstream
get() { # dir url commit
	[ -d "upstream/$1/.git" ] || git clone -q "$2" "upstream/$1"
	git -C "upstream/$1" fetch -q origin
	git -C "upstream/$1" checkout -q "$3"
	echo "$1 $(git -C "upstream/$1" rev-parse --short HEAD)"
}
get ocean-240.2      https://github.com/romychs/ocean-240.2.git            22e51e00b02181af88369463d62c98623f5772c1
get ocean240_fpga    https://github.com/AndrejChoo/Ocean240_on_FPGA.git    c3f8f9a9f21e26f7dfaebf9af0b837213c7026a4
# alemorf: ~1.5 GB repo, take the Ocean_240 folder only
A=upstream/retro_computers
ALEMORF=22fc95ce322cb693c7f6b87249d568be334d1718
if [ ! -d "$A/.git" ]; then
	git clone -q --filter=blob:none --no-checkout https://github.com/alemorf/retro_computers.git "$A"
	git -C "$A" sparse-checkout set Ocean_240
fi
git -C "$A" fetch -q origin
git -C "$A" checkout -q "$ALEMORF"
echo "retro_computers/Ocean_240 $(git -C "$A" rev-parse --short HEAD)"
MAME=774a180df2b6ef9c53e48337792256817c50f768
mkdir -p upstream/mame
curl -fsSL "https://raw.githubusercontent.com/mamedev/mame/$MAME/src/mame/ussr/okean240.cpp" -o upstream/mame/okean240.cpp
echo "mame okean240.cpp $(echo $MAME | cut -c1-7)"
echo "upstream ok"
