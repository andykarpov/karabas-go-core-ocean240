`timescale 1ns / 1ps
`default_nettype wire

/*
 ocean_scan2x.v — the raster of the Ocean (768 x 320 points of 12.288 MHz, 62.5 us a line, 49.99 Hz) for HDMI without a
 frame buffer, as v06c_scan2x of the Vector-06C core: 768 x 640 pixels of 24.576 MHz (31.25 us a line), active
 640 x 576, negative syncs; every line of the machine is shown twice while the next one is written.

 Everything is on clk (49.152 MHz) and locked to the counters of the machine: an output pixel every two clocks, the
 outputs change on those clocks only, the top takes them on clk_pix (clk / 2 of the same PLL).

 A display line is the points hc 719..767 of one line of the machine and 0..718 of the next (the 49 points of the
 left border at the end of the line before): wx = hc - 719 mod 768 is the write address, the half of the line buffer
 toggles at wx 0. While one half is written the other is read twice: output line A at wx 0..383, B at wx 384..767,
 x = 2 * (wx mod 384) + the half of the 12.288 MHz period. The display line dl = the line of the machine at its
 point 0; shown as output lines 2 * vy, 2 * vy + 1 with vy = dl + 16 mod 320: active vy 0..287 (lines 304..319 and
 0..271 of the machine): the screen (lines 0..255) at output y 32..543, its 512 points (hc 15..526) at x 64..575.

 colour_mpss: the wiring of MPSS 1986/4 for the outputs of the colour PROM (D1 R, D2 G, D3 B) instead of the one of
 the replica (R D3, G D1, B D2): the machine gives rgb = {D3 | bg, D1 | bg, D2 | bg} of the replica, so MPSS is
 R = G_rep, G = B_rep, B = R_rep (docs/HARDWARE.md).
*/

module ocean_scan2x (
	input  wire        clk,
	input  wire        ce_pix,      // ocean_video: hc / vc / rgb change after it
	input  wire  [9:0] hc,
	input  wire  [8:0] vc,
	input  wire  [2:0] rgb_i,       // R G B of the replica wiring
	input  wire        colour_mpss,

	output reg  [23:0] rgb = 24'd0,
	output reg         hs = 1'b1,   // negative
	output reg         vs = 1'b1,
	output reg         de = 1'b0
);

localparam H_ACTIVE = 640, H_SYNC = 656, H_SYNC_END = 720;
localparam V_ACTIVE = 576, V_SYNC = 581, V_SYNC_END = 586;

// the phase in the 12.288 MHz point (4 clocks): 0 at the clock after ce_pix
reg [1:0] ph = 2'd0;
always @(posedge clk) ph <= ce_pix ? 2'd0 : ph + 1'd1;

wire [2:0] c = colour_mpss ? {rgb_i[1], rgb_i[0], rgb_i[2]} : rgb_i;

// write: at ce_pix the value of the last point
wire [9:0] wx = (hc >= 10'd719) ? hc - 10'd719 : hc + 10'd49;
reg bank = 1'b0;
reg [8:0] dl = 9'd0;          // the display line being written
reg [8:0] dl_show = 9'd0;     // the one shown
reg [2:0] lbuf [0:2047];
always @(posedge clk) begin
	if (ce_pix) begin
		if (wx == 10'd0) begin
			bank <= ~bank;
			dl_show <= dl;
			dl <= (vc == 9'd319) ? 9'd0 : vc + 1'd1;   // its points from hc 0 on are of the next machine line
		end
		lbuf[{(wx == 10'd0) ? ~bank : bank, wx}] <= c;
	end
end

// read: output x / y from the write position
wire       half = (wx >= 10'd384);
wire [9:0] ox = {(half ? wx - 10'd384 : wx), 1'b0} | {9'd0, ph[1]};
wire       rbank = (wx == 10'd0) ? bank : ~bank;
wire [8:0] shown = (wx == 10'd0) ? dl : dl_show;
wire [9:0] vy0 = {1'b0, shown} + 10'd16;
wire [8:0] vy = (vy0 >= 10'd320) ? vy0 - 10'd320 : vy0[8:0];
wire [9:0] oy = {vy, half};

reg  [2:0] p = 3'd0;
reg  [9:0] ox_d = 10'd0, oy_d = 10'd0;
reg        ph_d = 1'b0;
always @(posedge clk) begin
	p <= lbuf[{rbank, ox}];
	ox_d <= ox; oy_d <= oy;
	ph_d <= ph[0];
	if (ph_d) begin           // the clock after the second clock of each half: an output pixel
		de <= (ox_d < H_ACTIVE) && (oy_d < V_ACTIVE);
		hs <= ~((ox_d >= H_SYNC) && (ox_d < H_SYNC_END));
		vs <= ~((oy_d >= V_SYNC) && (oy_d < V_SYNC_END));
		rgb <= ((ox_d < H_ACTIVE) && (oy_d < V_ACTIVE)) ? {{8{p[2]}}, {8{p[1]}}, {8{p[0]}}} : 24'd0;
	end
end

endmodule
