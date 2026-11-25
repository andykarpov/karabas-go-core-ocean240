`timescale 1ns / 1ps
`default_nettype wire

/*
 ocean_video.v — the video processor of the Ocean-240.2 (docs/HARDWARE.md, the replica of romychs).

 In the 12.288 MHz points of the machine (ce_pix, one clock in 4 of clk 49.152 MHz):
 - pc 0..15: DD42 (the point in the word); VR at 15. wc 0..47: the word counter (C1-C5, GC = wc[5]), it moves at
   pc 15 (DD24.A counts on the falling edge of VR); rc 0..319: the line counter (K1-K8, GK = rc[8]), it moves when
   GC falls (wc 47 -> 0).
 - the word read at wc = n (column SC = n + HS[7:3], line SK = rc + VS) waits in the latches DD38-DD41 and is loaded
   into the shifters DD34-DD37 at the end of the next pc 15: column n is on the screen while wc = n + 1.
 - the shifters move at the falling edges of 6M (pc odd -> even): RG1 / RG2 = MD / DB bits in the order of the
   KP13 latches (mono: RG1 = MD0 2 4 6 DB0 2 4 6, RG2 = MD1 3 5 7 DB1 3 5 7; colour: RG1 = MD0..7, RG2 = DB0..7),
   MD = the byte with A8 = 0, DB = A8 = 1.
 - the colour PROM DD66 (RT4, ocean_prom_vc): {BLNK, C/~M, COL3-1, RG2, RG1, 6M} -> {R (D3), B (D2), G (D1), BLANC (D0)};
   the background: R |= FL1 & BLANC, G |= FL3 & BLANC, B |= FL2 & BLANC.
 - DD43 + DD64: at pc = 2 * SB + 1 (SB = HS[2:0]) the flip-flops take GC (-> the delayed blank) and the line sync
   (low while C3 & ~C4 in the blank, set while GC = 0); BLNK = ~(GK | GC delayed). VS = K5 & GK & ~K6.
 - the video RAM: a copy of C000-FFFF of pages 0 / 1 (A16 = VSU = E1 B7) in block RAM, two banks of 16 KB (A8).
*/

module ocean_video (
	input  wire        clk,
	input  wire  [7:0] vs_reg,       // C0: VS
	input  wire  [7:0] hs_reg,       // C2: HS (HS[7:3] words, HS[2:0] = SB)
	input  wire  [7:0] vctl,         // E1: COL (2:0), FL (5:3), C/~M (6), VSU (7)

	input  wire        vw,           // a write into the copy
	input  wire        vw_page,      // A16
	input  wire [13:0] vw_addr,      // A13..A0
	input  wire  [7:0] vw_data,

	output reg         ce_pix = 1'b0,
	output reg   [2:0] rgb = 3'd0,
	output reg         blank = 1'b1,
	output reg         hsync = 1'b0,
	output reg         vsync = 1'b0,
	output wire        gc,
	output wire        gk,
	output wire  [9:0] hc,
	output wire  [8:0] vc
);

reg [1:0] div = 2'd0;
always @(posedge clk) begin
	div <= div + 1'd1;
	ce_pix <= (div == 2'd3);
end

// ---------------------------------------------------------------- counters
reg [3:0] pc = 4'd0;
reg [5:0] wc = 6'd0;
reg [8:0] rc = 9'd0;
assign gc = wc[5];
assign gk = rc[8];
assign hc = {wc, pc};
assign vc = rc;

// ---------------------------------------------------------------- the copy of the video RAM
reg [7:0] bank0 [0:16383];   // A8 = 0 (MD)
reg [7:0] bank1 [0:16383];   // A8 = 1 (DB)
wire [13:0] widx = {vw_page, vw_addr[13:9], vw_addr[7:0]};
always @(posedge clk) begin
	if (vw & ~vw_addr[8]) bank0[widx] <= vw_data;
	if (vw &  vw_addr[8]) bank1[widx] <= vw_data;
end

wire [4:0] sc = wc[4:0] + hs_reg[7:3];
wire [7:0] sk = rc[7:0] + vs_reg;
reg  [13:0] ridx = 14'd0;
reg  [7:0] md = 8'd0, db = 8'd0;
always @(posedge clk) begin
	ridx <= {vctl[7], sc, sk};
	md <= bank0[ridx];
	db <= bank1[ridx];
end

// ---------------------------------------------------------------- shifters, PROM, blanks, syncs
reg [7:0] lat_md = 8'd0, lat_db = 8'd0;   // DD38-DD41 (taken in the middle of the word)
reg [7:0] rg1 = 8'd0, rg2 = 8'd0;          // the chains DD34->DD35, DD36->DD37 (bit 0 goes out first)
reg gc_d = 1'b0, hs_n = 1'b1;
wire       cm = vctl[6];
wire [7:0] prom_a = {~(gk | gc_d), cm, vctl[2:0], rg2[0], rg1[0], pc[0]};
wire [3:0] prom_d;
ocean_prom_vc prom (.a(prom_a), .d(prom_d));
wire blanc = prom_d[0];

always @(posedge clk) if (ce_pix) begin
	// the point on the screen (the PROM and the output stage; DD66 is fast, one register here)
	rgb <= {prom_d[3] | (vctl[3] & blanc), prom_d[1] | (vctl[5] & blanc), prom_d[2] | (vctl[4] & blanc)};
	blank <= gk | gc_d;
	hsync <= ~hs_n;
	vsync <= gk & rc[4] & ~rc[5];

	pc <= pc + 1'd1;
	if (pc == 4'd7) begin
		// the word of this wc is in the latches (S1 of the read comes within the word)
		lat_md <= md;
		lat_db <= db;
	end
	if (pc[0]) begin
		// a falling edge of 6M: shift, or load at the end of the word
		if (pc == 4'd15) begin
			rg1 <= cm ? lat_md : {lat_db[6], lat_db[4], lat_db[2], lat_db[0], lat_md[6], lat_md[4], lat_md[2], lat_md[0]};
			rg2 <= cm ? lat_db : {lat_db[7], lat_db[5], lat_db[3], lat_db[1], lat_md[7], lat_md[5], lat_md[3], lat_md[1]};
		end else begin
			rg1 <= {1'b1, rg1[7:1]};
			rg2 <= {1'b1, rg2[7:1]};
		end
	end
	if (pc == 4'd15) begin
		if (wc == 6'd47) begin
			wc <= 6'd0;
			rc <= (rc == 9'd319) ? 9'd0 : rc + 1'd1;
		end else wc <= wc + 1'd1;
	end
	// DD43 = DD64: the delayed blank and the line sync, clocked at the start of the point 2 * SB + 1 of the word
	// (they count from that point on: taken here, a point before)
	if (pc == {hs_reg[2:0], 1'b0}) begin
		gc_d <= gc;
		hs_n <= ~gc | ~(wc[2] & ~wc[3]);
	end
	if (~gc) hs_n <= 1'b1;
end

endmodule
