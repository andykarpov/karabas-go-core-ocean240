// Pin-level behavioural models of the KR580 LSI parts for the schematic model (Icarus only, not for synthesis).
// Ports = package pin numbers as in the KiCad library of the replica.
`timescale 1ns/100ps

// КР580ВК28 (8228 system controller): 1 ~STSTB, 2 ~HLDA, 3 ~WR, 4 DBIN, 22 BUSEN (0 = on);
// CPU side D0..D7 = 15 17 12 10 6 19 21 8, system side DB0..DB7 = 13 16 11 9 5 18 20 7;
// 23 ~INTA, 24 ~MEMR, 25 ~IOR, 26 ~MEMW, 27 ~IOW
module vk28(input p1, p2, p3, p4, p22,
	inout p15, p17, p12, p10, p6, p19, p21, p8,
	inout p13, p16, p11, p9, p5, p18, p20, p7,
	output p23, p24, p25, p26, p27);
	wire [7:0] d  = {p8, p21, p19, p6, p10, p12, p17, p15};
	wire [7:0] db = {p7, p20, p18, p5, p9, p11, p16, p13};
	reg [7:0] st = 8'h00;
	always @(posedge p1) st <= d; // status is on D while ~STSTB is low, latched at its end
	wire inta = st[0], out = st[4], inp = st[6], memr = st[7];
	assign #8 p24 = ~(p4 & memr);
	assign #8 p25 = ~(p4 & inp);
	assign #8 p23 = ~(p4 & inta);
	assign #8 p26 = ~(~p3 & ~out);
	assign #8 p27 = ~(~p3 & out);
	wire rd = p4 & ~p22;
	wire wr = ~p4 & ~p22;
	assign #10 {p8, p21, p19, p6, p10, p12, p17, p15} = rd ? db : 8'hzz;
	assign #10 {p7, p20, p18, p5, p9, p11, p16, p13} = wr ? d : 8'hzz;
endmodule

// КР580ВВ55 (8255), mode 0 only (the Ocean uses mode 0): D0..D7 = 34..27, 5 ~RD, 6 ~CS, 9 A0, 8 A1, 36 ~WR, 35 RESET;
// PA0..7 = 4 3 2 1 40 39 38 37, PB0..7 = 18..25, PC0..7 = 14 15 16 17 13 12 11 10.
// Reset / mode set: ports are inputs (Z) after RESET; a mode word clears the output latches.
module vv55(input p5, p6, p8, p9, p35, p36,
	inout p27, p28, p29, p30, p31, p32, p33, p34,
	inout p4, p3, p2, p1, p40, p39, p38, p37,
	inout p18, p19, p20, p21, p22, p23, p24, p25,
	inout p14, p15, p16, p17, p13, p12, p11, p10);
	reg [7:0] la = 0, lb = 0, lc = 0;
	reg a_in = 1, b_in = 1, cl_in = 1, ch_in = 1;
	wire [7:0] pa = {p37, p38, p39, p40, p1, p2, p3, p4};
	wire [7:0] pb = {p25, p24, p23, p22, p21, p20, p19, p18};
	wire [7:0] pc = {p10, p11, p12, p13, p17, p16, p15, p14};
	wire [7:0] dbus = {p27, p28, p29, p30, p31, p32, p33, p34};
	wire [1:0] a = {p8, p9};
	always @(posedge p35 or posedge p36) begin
		if (p35) begin la <= 0; lb <= 0; lc <= 0; a_in <= 1; b_in <= 1; cl_in <= 1; ch_in <= 1; end
		else if (!p6) case (a)
			2'd0: la <= dbus;
			2'd1: lb <= dbus;
			2'd2: lc <= dbus;
			2'd3: if (dbus[7]) begin
					la <= 0; lb <= 0; lc <= 0;
					a_in <= dbus[4]; ch_in <= dbus[3]; b_in <= dbus[1]; cl_in <= dbus[0];
				end else lc[dbus[3:1]] <= dbus[0];
		endcase
	end
	wire [7:0] cval = {ch_in ? pc[7:4] : lc[7:4], cl_in ? pc[3:0] : lc[3:0]};
	wire [7:0] rdat = (a == 2'd0) ? (a_in ? pa : la) : (a == 2'd1) ? (b_in ? pb : lb) : (a == 2'd2) ? cval : 8'hFF;
	assign #20 {p27, p28, p29, p30, p31, p32, p33, p34} = (!p6 && !p5) ? rdat : 8'hzz;
	assign #20 {p37, p38, p39, p40, p1, p2, p3, p4} = a_in ? 8'hzz : la;
	assign #20 {p25, p24, p23, p22, p21, p20, p19, p18} = b_in ? 8'hzz : lb;
	assign #20 {p10, p11, p12, p13} = ch_in ? 4'hz : lc[7:4];
	assign #20 {p17, p16, p15, p14} = cl_in ? 4'hz : lc[3:0];
endmodule

// one counter of the 8253: modes 0, 2, 3 (others behave as 0); counts on the falling CLK edge
module vi53_ctr(input clk, input gate, input wr_ctl, input [7:0] ctl, input wr_cnt, input [7:0] din,
	input rd_cnt, output reg [7:0] dout, output reg out);
	reg [15:0] cnt = 0, init = 0, latch = 0;
	reg [1:0] rl = 2'd3; reg [2:0] mode = 0;
	reg wflip = 0, rflip = 0, latched = 0, armed = 0, load = 0, half = 0;
	initial out = 1'b1;
	always @(posedge wr_ctl) begin
		if (ctl[5:4] == 2'b00) begin latch <= cnt; latched <= 1; end
		else begin rl <= ctl[5:4]; mode <= ctl[3:1]; wflip <= 0; rflip <= 0; armed <= 0; out <= (ctl[3:1] == 3'd0) ? 1'b0 : 1'b1; end
	end
	always @(posedge wr_cnt) begin
		case (rl)
			2'd1: begin init[7:0] <= din; init[15:8] <= 0; load <= ~load; end
			2'd2: begin init[15:8] <= din; init[7:0] <= 0; load <= ~load; end
			default: if (!wflip) begin init[7:0] <= din; wflip <= 1; end
					else begin init[15:8] <= din; wflip <= 0; load <= ~load; end
		endcase
	end
	reg load_seen = 0;
	always @(negedge clk) begin
		if (load != load_seen) begin
			load_seen <= load; cnt <= init; armed <= 1; half <= 0;
			if (mode == 3'd0) out <= 1'b0;
		end else if (armed && gate) begin
			case (mode[1:0])
				2'd2: begin // rate generator
					if (cnt == 16'd2) begin cnt <= cnt - 1; out <= 1'b0; end
					else if (cnt == 16'd1) begin cnt <= init; out <= 1'b1; end
					else cnt <= cnt - 1;
				end
				2'd3: begin // square wave: count by 2
					if (cnt <= 16'd2 && cnt != 16'd0) begin cnt <= init; out <= ~out; end
					else cnt <= cnt - 2;
				end
				default: begin
					cnt <= cnt - 1;
					if (cnt == 16'd1) out <= 1'b1;
				end
			endcase
		end
	end
	wire [15:0] rv = latched ? latch : cnt;
	always @(*) dout = ((rl == 2'd2) || (rl == 2'd3 && rflip)) ? rv[15:8] : rv[7:0];
	always @(posedge rd_cnt) begin
		if (rl == 2'd3) begin rflip <= ~rflip; if (rflip) latched <= 0; end else latched <= 0;
	end
endmodule

// КР580ВИ53 (8253): D0..D7 = 8..1, 19 A0, 20 A1, 21 ~CS, 22 ~RD, 23 ~WR; CLK 9 15 18, GATE 11 14 16, OUT 10 13 17
module vi53(input p9, p11, p14, p15, p16, p18, p19, p20, p21, p22, p23,
	inout p1, p2, p3, p4, p5, p6, p7, p8, output p10, p13, p17);
	wire [7:0] d = {p1, p2, p3, p4, p5, p6, p7, p8};
	wire [1:0] a = {p20, p19};
	wire wr = ~p21 & ~p23, rd = ~p21 & ~p22;
	wire [7:0] q0, q1, q2;
	wire wr_ctl0 = wr & (a == 2'd3) & (d[7:6] == 2'd0);
	wire wr_ctl1 = wr & (a == 2'd3) & (d[7:6] == 2'd1);
	wire wr_ctl2 = wr & (a == 2'd3) & (d[7:6] == 2'd2);
	// counters take the data at the end of ~WR
	reg [7:0] dl; always @(*) if (wr) dl = d;
	vi53_ctr c0(.clk(p9),  .gate(p11), .wr_ctl(~(wr_ctl0)), .ctl(dl), .wr_cnt(~(wr & a == 2'd0)), .din(dl), .rd_cnt(~(rd & a == 2'd0)), .dout(q0), .out(p10));
	vi53_ctr c1(.clk(p15), .gate(p14), .wr_ctl(~(wr_ctl1)), .ctl(dl), .wr_cnt(~(wr & a == 2'd1)), .din(dl), .rd_cnt(~(rd & a == 2'd1)), .dout(q1), .out(p13));
	vi53_ctr c2(.clk(p18), .gate(p16), .wr_ctl(~(wr_ctl2)), .ctl(dl), .wr_cnt(~(wr & a == 2'd2)), .din(dl), .rd_cnt(~(rd & a == 2'd2)), .dout(q2), .out(p17));
	assign #30 {p1, p2, p3, p4, p5, p6, p7, p8} = rd ? (a == 2'd0 ? q0 : a == 2'd1 ? q1 : a == 2'd2 ? q2 : 8'hFF) : 8'hzz;
endmodule

// КР580ВН59 (8259), single, 8080 mode (CALL), fully nested, edge or level: 1 ~CS, 2 ~WR, 3 ~RD, 27 A0, 26 ~INTA, 17 INT;
// D0..D7 = 11..4 (the replica schematic numbers them correctly; MPSS notes the original drawing had them reversed); IR0..7 = 18..25
module vn59(input p1, p2, p3, p27, p26, p16, input p18, p19, p20, p21, p22, p23, p24, p25,
	inout p4, p5, p6, p7, p8, p9, p10, p11, output p12, p13, p15, output p17);
	wire [7:0] d = {p4, p5, p6, p7, p8, p9, p10, p11};
	wire [7:0] ir = {p25, p24, p23, p22, p21, p20, p19, p18};
	reg [7:0] irr = 0, isr = 0, imr = 8'hFF, icw1 = 0, icw2 = 0;
	reg [1:0] icw_step = 0; reg rr = 0, ris = 0, poll = 0;
	reg [7:0] ir_l = 0;
	reg [1:0] inta_n = 0; reg [7:0] cur = 0;
	integer k;
	// edge-triggered request (LTIM = 0): rising edge sets IRR, the request must stay high until the first INTA
	always @(ir) begin
		for (k = 0; k < 8; k = k + 1) begin
			if (icw1[3] ? ir[k] : (ir[k] & ~ir_l[k])) irr[k] = 1'b1;
			if (!ir[k] && !icw1[3]) irr[k] = 1'b0;
		end
		ir_l = ir;
	end
	function [2:0] pri; input [7:0] v; integer j; begin pri = 0; for (j = 7; j >= 0; j = j - 1) if (v[j]) pri = j; end endfunction
	wire [7:0] req = irr & ~imr;
	wire [2:0] rq = pri(req), is = pri(isr);
	wire intr = (req != 0) && (isr == 0 || rq < is);
	assign #20 p17 = intr;
	always @(posedge p2) if (!p1) begin
		if (!p27 && d[4]) begin icw1 <= d; icw_step <= 1; imr <= 0; isr <= 0; rr <= 0; ris <= 0; end
		else if (p27 && icw_step == 1) begin icw2 <= d; icw_step <= (icw1[0] ? 2 : 0); end
		else if (p27 && icw_step == 2) icw_step <= 0; // ICW4
		else if (p27) imr <= d;
		else if (!d[3]) begin // OCW2: non-specific / specific EOI
			if (d[5] && !d[6]) isr[is] <= 1'b0;
			else if (d[5] && d[6]) isr[d[2:0]] <= 1'b0;
		end else begin rr <= d[1]; ris <= d[0]; poll <= d[2]; end
	end
	// INTA sequence: CALL, low byte, high byte
	reg [7:0] inta_d;
	always @(negedge p26) begin
		if (inta_n == 0) begin cur <= rq; isr[rq] <= 1'b1; irr[rq] <= 1'b0; inta_d <= 8'hCD; end
		else if (inta_n == 1) inta_d <= icw1[2] ? {icw1[7:5], cur, 2'b00} : {icw1[7:6], cur, 3'b000};
		else inta_d <= icw2;
	end
	always @(posedge p26) inta_n <= (inta_n == 2) ? 0 : inta_n + 1;
	wire [7:0] rdat = poll ? {intr, 4'b0, rq} : p27 ? imr : (ris ? isr : irr);
	always @(posedge p3) if (!p1) poll <= 0;
	assign #30 {p4, p5, p6, p7, p8, p9, p10, p11} = !p26 ? inta_d : (!p1 && !p3) ? rdat : 8'hzz;
	assign p12 = 1'b0; assign p13 = 1'b0; assign p15 = 1'b0;
endmodule

// КР580ВВ51 (8251), asynchronous mode only: D0..D7 = 27 28 1 2 5 6 7 8, 12 C/~D, 10 ~WR, 13 ~RD, 11 ~CS, 21 RESET;
// 9 ~TXC, 25 ~RXC, 3 RXD, 19 TXD, 15 TXRDY, 14 RXRDY, 18 TXE, 17 ~CTS, 22 ~DSR
module vv51(input p3, p9, p10, p11, p12, p13, p17, p20, p21, p22, p25,
	inout p27, p28, p1, p2, p5, p6, p7, p8,
	output p14, p15, p16, p18, p19, p23, p24);
	wire [7:0] d = {p8, p7, p6, p5, p2, p1, p28, p27};
	reg [7:0] mode = 0, cmd = 0, txbuf = 0, rxbuf = 0;
	reg mode_next = 1, txfull = 0, rxrdy = 0;
	always @(posedge p10 or posedge p21) begin
		if (p21) begin mode_next <= 1; cmd <= 0; end
		else if (!p11 && p12) begin
			if (mode_next) begin mode <= d; mode_next <= 0; end
			else begin cmd <= d; if (d[6]) mode_next <= 1; end
		end
	end
	wire [9:0] div = (mode[1:0] == 2'd2) ? 16 : (mode[1:0] == 2'd3) ? 64 : 1;
	wire [3:0] nbits = 5 + mode[3:2];
	// transmitter
	reg [10:0] sh = 0; reg [3:0] bits = 0; reg [9:0] tc = 0; reg txd = 1, txbusy = 0;
	reg txw = 0, txw_seen = 0;
	always @(posedge p10) if (!p11 && !p12) begin txbuf <= d; txw <= ~txw; end
	always @(negedge p9) begin
		if (!txbusy) begin
			if (txw != txw_seen && cmd[0]) begin txw_seen <= txw; sh <= {2'b11, txbuf, 1'b0}; bits <= nbits + 3; tc <= 0; txbusy <= 1; txd <= 0; end
		end else begin
			tc <= tc + 1;
			if (tc == div - 1) begin tc <= 0; sh <= {1'b1, sh[10:1]}; txd <= sh[1]; bits <= bits - 1; if (bits == 1) txbusy <= 0; end
		end
	end
	wire txe = !txbusy && (txw == txw_seen);
	wire txrdy_s = (txw == txw_seen);
	// receiver
	reg [9:0] rc = 0; reg [3:0] rbits = 0; reg rbusy = 0; reg [7:0] rsh = 0;
	reg rdd = 0, rdd_seen = 0;
	always @(negedge p25) begin
		if (!rbusy) begin if (!p3) begin rc <= 0; rbusy <= 1; rbits <= 0; end end
		else begin
			rc <= rc + 1;
			if (rc == div / 2 + div * rbits - 1 + div) begin // middle of data bit rbits
				rsh <= {p3, rsh[7:1]}; rbits <= rbits + 1;
				if (rbits == nbits - 1) begin rbusy <= 0; rxbuf <= {p3, rsh[7:1]} >> (8 - nbits); rdd <= ~rdd; end
			end
		end
	end
	always @(posedge p13) if (!p11 && !p12) rdd_seen <= rdd;
	wire rxrdy_s = (rdd != rdd_seen) && cmd[2];
	wire [7:0] st = {~p22, 1'b0, 1'b0, 1'b0, 1'b0, txe, rxrdy_s, txrdy_s};
	assign #30 {p8, p7, p6, p5, p2, p1, p28, p27} = (!p11 && !p13) ? (p12 ? st : rxbuf) : 8'hzz;
	assign p19 = txd | cmd[3];
	assign p15 = txrdy_s & cmd[0] & ~p17;
	assign p14 = rxrdy_s;
	assign p18 = txe;
	assign p16 = 1'b0;
	assign p23 = ~cmd[5];
	assign p24 = ~cmd[1];
endmodule
