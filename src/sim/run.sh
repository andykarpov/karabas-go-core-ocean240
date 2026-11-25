#!/bin/bash
# The Ocean-240.2 machine (src/rtl/ocean) in simulation (verilator). Builds sim_ocean into src/sim/build.
#  1. the test ROM of MPSS (E000_Tests, beeps shortened as in src/sim/schem): "TEST 1 PASSED" on the 8251 at 4800 baud,
#     a key on the terminal, then the tests that follow.
#  2. the video (schem/mkrom_vidtest.py, plain and with the scrollers): the mono and the colour frames are point for
#     point the frames of the schematic model kept in src/sim/ref.
#  3. CPM=1: the 240/7 monitor with CP/M: A>, DIR typed through ocean_kbd.
#  4. TAPE=1: the tape out of test 5 played back into test 6 (all "+").
#  5. ocean_rdisk (the RAM disk file) with a model of the mounter (Icarus).
set -eu
H=$(cd "$(dirname "$0")" && pwd)
S=$(cd "$H/.." && pwd)
B=$H/build
U=$S/../upstream/ocean-240.2/ROMs
mkdir -p "$B"
R=$S/rtl
python3 -I "$S/tools/mkprom.py" "$U/Ocean_240_RT4_VC.bin" "$R/ocean/ocean_prom_vc.v"
python3 -I "$S/tools/mkkbd.py" "$R/ocean/ocean_kbd_map.v"
SRC="$H/tb_ocean.v $R/ocean/ocean_system.v $R/ocean/ocean_video.v $R/ocean/ocean_prom_vc.v $R/ocean/ocean_vv51.v $R/ocean/ocean_sram.v $R/ocean/ocean_kbd.v $R/ocean/ocean_kbd_map.v $R/ocean/ocean_scan2x.v $R/ocean/ocean_loader.v $R/ocean/ocean_aux.v $R/ocean/ocean_tape.v $R/ocean/k580vv55.v $R/ocean/k580vi53.v $R/vm80a/vm80a.v $R/kf8259/KF8259.v $R/kf8259/KF8259_Bus_Control_Logic.v $R/kf8259/KF8259_Control_Logic.v $R/kf8259/KF8259_In_Service.v $R/kf8259/KF8259_Interrupt_Request.v $R/kf8259/KF8259_Priority_Resolver.v"
verilator --language 1364-2005 --cc --exe --build -j 8 -O3 --top-module tb_ocean -Mdir "$B/obj" -o sim_ocean \
	-Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-PINMISSING -Wno-PINNOTFOUND \
	--x-initial fast -CFLAGS -O2 $SRC "$H/sim_ocean.cpp" > "$B/build.log" 2>&1 || { grep -E "Error|error" "$B/build.log" | head -30; exit 1; }
[ -z "${BUILD_ONLY:-}" ] || exit 0
SIM=$B/obj/sim_ocean
err=0
fail() { echo "FAIL: $*"; err=1; }

echo "== test ROM"
"$SIM" --rom0 "$U/Ocean_240_ROM_E000_Tests.bin:4fa=01,522=01" --rom1 "$U/Ocean_240_ROM_C000_СPM_without_floppy.bin" \
	--ms 60 --rxkey 45:20 --expect-tx "TEST 1 PASSED" > "$B/test.txt" || fail "test ROM"
cat "$B/test.txt"

echo "== test 8 (the 8253 counter 0 -> IR4 -> the 8259 CALL 0020h): test 1 returns to E41F, the delays cut (sim only)"
"$SIM" --rom0 "$U/Ocean_240_ROM_E000_Tests.bin:4fa=01,522=01,065=1f,066=e4,4e7=01,4e8=00" --ms 400 --rxkey 45:20 \
	--expect-tx "TEST 8 PASSED" > "$B/test8.txt" || fail "test 8"
grep PASSED "$B/test8.txt"

if [ -n "${CPM:-}" ]; then
	echo "== 240/7 monitor + CP/M REL.5 (~40 s): A>, DIR from the keyboard"
	"$SIM" --rom0 "$U/Ocean_240_ROM_E000_Monitor.bin" --rom1 "$U/Ocean_240_ROM_C000_СPM_without_floppy.bin" --ms 2600 \
		--type "1600:DIR|" --vram --frames "$B/cpm" > "$B/cpm.txt" || err=1
	n=$(sed -n 's/video RAM page 0: \([0-9]*\).*/\1/p' "$B/cpm.txt")
	[ "$n" -gt 500 ] || fail "CP/M: $n bytes on the screen"
	f=$(ls "$B"/cpm_*.ppm | sort -t_ -k2 -n | tail -2 | head -1); python3 -I "$H/ppm2png.py" "$f" "$B/cpm.png"
	echo "CP/M: $n bytes on the screen, $B/cpm.png"
fi

echo "== video: frames against the schematic model (src/sim/ref, made by schem/run.sh; ref/README)"
for t in vidtest:vt vidscroll:vs; do
	rom=${t%%:*}; p=${t##*:}
	python3 -I "$H/schem/mkrom_vidtest.py" "$B/$rom.bin" $([ "$rom" = vidscroll ] && echo scroll)
	"$SIM" --rom0 "$B/$rom.bin" --ms 65 --frames "$B/$p" > /dev/null || err=1
	for n in 0 2; do
		python3 -I "$H/ppmcmp.py" "$B/${p}_$n.ppm" "$H/ref/${p}_$n.ppm.gz" && echo "$rom frame $n = schematic" || fail "$rom frame $n differs from the schematic model"
	done
done

if [ -n "${TAPE:-}" ]; then
	echo "== tape (~1 min): test 5 writes its signal (TAPE_OUT -> .wav), test 6 reads it back through ocean_tape (FL .wav)"
	T="$U/Ocean_240_ROM_E000_Tests.bin:4fa=01,522=01,4e7=01,4e8=00"
	"$SIM" --rom0 "$T,065=9a,066=e2" --ms 700 --rxkey 45:20 --wav-out "$B/t5.wav" > /dev/null || err=1
	"$SIM" --rom0 "$T,065=d3,066=e2" --ms 1300 --rxkey 45:20 --wav-in 50:"$B/t5.wav" > "$B/t6.txt" || err=1
	n=$(grep -o "+" "$B/t6.txt" | wc -l); m=$(grep -o -- "-" "$B/t6.txt" | wc -l)
	echo "tape: $n +, $m -"
	[ "$n" -gt 100 ] && [ "$m" -lt 5 ] || fail "tape: $n +, $m -"
fi

echo "== the RAM disk on the card (rdisk/tb_rdisk.v: ocean_rdisk + kg_bk_ram, a model of the mounter)"
iverilog -g2012 -o "$B/tb_rdisk.vvp" "$H/rdisk/tb_rdisk.v" "$R/ocean/ocean_rdisk.v" "$R/ocean/ocean_aux.v" "$S/../modules/rtl/mcu/kg_bk_ram.v" "$S/../modules/rtl/mem/kg_sdpram.v"
vvp -n "$B/tb_rdisk.vvp" | tail -2 | tee "$B/rdisk.txt"
grep -q "rdisk ok" "$B/rdisk.txt" || fail "RAM disk"

[ $err = 0 ] && echo "sim ok" || echo "sim FAILED"
exit $err
