Frames of the schematic model of the replica (src/sim/schem), the reference of `src/sim/run.sh`.
Made by `schem/run.sh build/<rom>.bin +ms=65 +frames=build/<p>` with `<rom>.bin` from `schem/mkrom_vidtest.py`
(`vidtest` -> `vt`, `vidscroll` (argument `scroll`) -> `vs`), then `gzip -9 -c build/<p>_N.ppm > ../ref/<p>_N.ppm.gz`.
Frame 0 is mono, frame 2 colour. Make them again after a change of the schematic model or the test ROM (~2 min each).
