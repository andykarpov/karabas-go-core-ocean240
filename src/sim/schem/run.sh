#!/bin/sh
# Schematic model of the Ocean-240.2 replica in Icarus: netlist -> schem.v -> run.
#   run.sh [ROM0.bin [ROM1.bin]] [plusargs...]   defaults: the test ROM (E000) in DD1, CP/M without floppy in DD2
# Needs kicad-cli (netlist) and upstream/ (tools/fetch_upstream.sh).
set -eu
cd "$(dirname "$0")"
R=../../..
U=$R/upstream/ocean-240.2
mkdir -p build
ROM0=$U/ROMs/Ocean_240_ROM_E000_Tests.bin
ROM1="$U/ROMs/Ocean_240_ROM_C000_СPM_without_floppy.bin"
case "${1:-}" in *.bin) ROM0=$1; shift;; esac
case "${1:-}" in *.bin) ROM1=$1; shift;; esac
SCH="$U/KiCAD/Океан-240.2.kicad_sch"
if [ ! -f build/ocean.xml ] || [ "$SCH" -nt build/ocean.xml ]; then
	kicad-cli sch export netlist --format kicadxml -o build/ocean.xml "$SCH" >/dev/null 2>&1
fi
python3 -I gen_schem.py build/ocean.xml build/schem.v
# the test ROM beeps ~150 ms before each message: shorten the beep loops (E4FA, E522) in sim only
case "$ROM0" in *Tests*) P0="4fa=01 522=01";; *) P0="";; esac
python3 -I mkhex.py rom "$ROM0" build/rom0.hex $P0
python3 -I mkhex.py rom "$ROM1" build/rom1.hex
python3 -I mkhex.py prom "$U/ROMs/Ocean_240_RT4_VC.bin" build/prom_vc.hex
iverilog -g2012 -o build/tb_schem.vvp -s tb_schem tb_schem.v build/schem.v ttl.v lsi.v $R/src/rtl/vm80a/vm80a.v
vvp -n build/tb_schem.vvp "$@"
