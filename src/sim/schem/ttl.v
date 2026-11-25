// Behavioural models of the TTL / PROM / DRAM parts of the Ocean-240.2 replica, ports = package pin numbers.
// Used only by the schematic model (src/sim/schem, Icarus): gen_schem.py instantiates them from the KiCad netlist.
// Delays are rough 1533 / 555 values so that ripple counters and gated clocks behave as on the board.
`timescale 1ns/100ps

`define TG 6    // gate
`define TF 12   // flip-flop / counter / register clock -> Q
`define TM 10   // mux / adder / comparator

// quad 2-input gates, pins 1,2->3 4,5->6 9,10->8 12,13->11
module k1533la3(input p1,p2,p4,p5,p9,p10,p12,p13, output p3,p6,p8,p11);
	assign #`TG p3 = ~(p1 & p2); assign #`TG p6 = ~(p4 & p5); assign #`TG p8 = ~(p9 & p10); assign #`TG p11 = ~(p12 & p13);
endmodule
module k1533li1(input p1,p2,p4,p5,p9,p10,p12,p13, output p3,p6,p8,p11);
	assign #`TG p3 = p1 & p2; assign #`TG p6 = p4 & p5; assign #`TG p8 = p9 & p10; assign #`TG p11 = p12 & p13;
endmodule
module k1533ll1(input p1,p2,p4,p5,p9,p10,p12,p13, output p3,p6,p8,p11);
	assign #`TG p3 = p1 | p2; assign #`TG p6 = p4 | p5; assign #`TG p8 = p9 | p10; assign #`TG p11 = p12 | p13;
endmodule
module k1533lp5(input p1,p2,p4,p5,p9,p10,p12,p13, output p3,p6,p8,p11);
	assign #`TG p3 = p1 ^ p2; assign #`TG p6 = p4 ^ p5; assign #`TG p8 = p9 ^ p10; assign #`TG p11 = p12 ^ p13;
endmodule
// quad NOR '02: 2,3->1 5,6->4 8,9->10 11,12->13
module k1533le1(input p2,p3,p5,p6,p8,p9,p11,p12, output p1,p4,p10,p13);
	assign #`TG p1 = ~(p2 | p3); assign #`TG p4 = ~(p5 | p6); assign #`TG p10 = ~(p8 | p9); assign #`TG p13 = ~(p11 | p12);
endmodule
// hex inverters '04 / '14: 1->2 3->4 5->6 9->8 11->10 13->12
module k1533ln1(input p1,p3,p5,p9,p11,p13, output p2,p4,p6,p8,p10,p12);
	assign #`TG p2 = ~p1; assign #`TG p4 = ~p3; assign #`TG p6 = ~p5; assign #`TG p8 = ~p9; assign #`TG p10 = ~p11; assign #`TG p12 = ~p13;
endmodule
module k1533tl2(input p1,p3,p5,p9,p11,p13, output p2,p4,p6,p8,p10,p12);
	assign #`TG p2 = ~p1; assign #`TG p4 = ~p3; assign #`TG p6 = ~p5; assign #`TG p8 = ~p9; assign #`TG p10 = ~p11; assign #`TG p12 = ~p13;
endmodule
// open collector '05
module k1533ln3(input p1,p3,p5,p9,p11,p13, output p2,p4,p6,p8,p10,p12);
	assign #`TG p2 = p1 ? 1'b0 : 1'bz; assign #`TG p4 = p3 ? 1'b0 : 1'bz; assign #`TG p6 = p5 ? 1'b0 : 1'bz;
	assign #`TG p8 = p9 ? 1'b0 : 1'bz; assign #`TG p10 = p11 ? 1'b0 : 1'bz; assign #`TG p12 = p13 ? 1'b0 : 1'bz;
endmodule

// dual D flip-flop '74: 1 ~R 2 D 3 C 4 ~S 5 Q 6 ~Q | 13 ~R 12 D 11 C 10 ~S 9 Q 8 ~Q
module dff74(input r_n, s_n, d, c, output q, output q_n);
	reg s = 1'b0;
	always @(posedge c or negedge r_n or negedge s_n)
		if (!r_n) s <= 1'b0; else if (!s_n) s <= 1'b1; else s <= d;
	// both set and reset low: both outputs high
	assign #`TF q   = (!s_n) ? 1'b1 : (!r_n) ? 1'b0 : s;
	assign #`TF q_n = (!r_n) ? 1'b1 : (!s_n) ? 1'b0 : ~s;
endmodule
module k1533tm2(input p1,p2,p3,p4,p10,p11,p12,p13, output p5,p6,p8,p9);
	dff74 a(.r_n(p1), .s_n(p4), .d(p2), .c(p3), .q(p5), .q_n(p6));
	dff74 b(.r_n(p13), .s_n(p10), .d(p12), .c(p11), .q(p9), .q_n(p8));
endmodule

// '93 ripple counter: 14 CKA -> 12 QA; 1 CKB -> 9 QB, 8 QC, 11 QD; reset R0(1) 2 & R0(2) 3
module k1533ie5(input p1,p2,p3,p14, output p8,p9,p11,p12);
	reg qa = 1'b0; reg [2:0] qb = 3'd0;
	wire rst = p2 & p3;
	always @(negedge p14 or posedge rst) if (rst) qa <= 1'b0; else qa <= ~qa;
	always @(negedge p1  or posedge rst) if (rst) qb <= 3'd0; else qb <= qb + 3'd1;
	assign #`TF p12 = qa;
	assign #`TF p9 = qb[0]; assign #`TF p8 = qb[1]; assign #`TF p11 = qb[2];
endmodule

// '193 up / down counter: 5 UP, 4 DOWN, 11 ~LOAD, 14 CLR; D 15 1 10 9; Q 3 2 6 7; 12 ~CO, 13 ~BO
module k1533ie7(input p1,p4,p5,p9,p10,p11,p14,p15, output p2,p3,p6,p7,p12,p13);
	reg [3:0] q = 4'd0;
	wire [3:0] d = {p9, p10, p1, p15};
	// counting edges (the other clock input must be high); clear and load are asynchronous and level-held (sim-only model)
	always @(posedge p5) if (!p14 && p11 && p4) q <= q + 4'd1;
	always @(posedge p4) if (!p14 && p11 && p5) q <= q - 4'd1;
	always @(p14 or p11 or d) if (p14) q <= 4'd0; else if (!p11) q <= d;
	assign #`TF p3 = q[0]; assign #`TF p2 = q[1]; assign #`TF p6 = q[2]; assign #`TF p7 = q[3];
	// ~CO / ~BO after the clock ~17 ns ('193 typ.), later than Q: VR -> ~VR (ТЛ2) -> EL of the video shifters
	// must still be high at the falling edge of 6M (Q0) that ends the word, or the shifters never load
	assign #15 p12 = ~((q == 4'hF) & ~p5);
	assign #15 p13 = ~((q == 4'h0) & ~p4);
endmodule

// '295 4-bit shift register, 3-state: 1 SER, 2-5 A-D, 6 MODE (1 = load), 8 OC (1 = outputs on), 9 CLK (falling), 13..10 QA..QD
module k1533ir16(input p1,p2,p3,p4,p5,p6,p8,p9, output p10,p11,p12,p13);
	reg [3:0] q = 4'd0; // q[0] = QA
	always @(negedge p9) if (p6) q <= {p5, p4, p3, p2}; else q <= {q[2:0], p1};
	assign #`TF p13 = p8 ? q[0] : 1'bz; assign #`TF p12 = p8 ? q[1] : 1'bz;
	assign #`TF p11 = p8 ? q[2] : 1'bz; assign #`TF p10 = p8 ? q[3] : 1'bz;
endmodule

// '253 dual 4:1 mux, 3-state: 14 S0, 2 S1; 1 ~1G, 6 5 4 3 = 1C0..1C3, 7 1Y; 15 ~2G, 10..13 = 2C0..2C3, 9 2Y
module k1533kp12(input p1,p2,p3,p4,p5,p6,p10,p11,p12,p13,p14,p15, output p7,p9);
	wire [1:0] s = {p2, p14};
	wire [3:0] c1 = {p3, p4, p5, p6}, c2 = {p13, p12, p11, p10};
	assign #`TM p7 = p1  ? 1'bz : c1[s];
	assign #`TM p9 = p15 ? 1'bz : c2[s];
endmodule

// '298 quad 2-input mux with storage: 10 WS (0 = word 1 = A), 11 CLK (falling); A1..A4 3 4 9 7, B1..B4 2 1 5 6, Q1..Q4 15 14 13 12
module k1533kp13(input p1,p2,p3,p4,p5,p6,p7,p9,p10,p11, output p12,p13,p14,p15);
	reg [3:0] q = 4'd0;
	always @(negedge p11) q <= p10 ? {p6, p5, p1, p2} : {p7, p9, p4, p3};
	assign #`TF p15 = q[0]; assign #`TF p14 = q[1]; assign #`TF p13 = q[2]; assign #`TF p12 = q[3];
endmodule

// '257 quad 2:1 mux, 3-state: 1 SEL (0 = A), 15 ~OE; A 2 5 11 14, B 3 6 10 13, Y 4 7 9 12
module k1533kp11(input p1,p2,p3,p5,p6,p10,p11,p13,p14,p15, output p4,p7,p9,p12);
	assign #`TM p4  = p15 ? 1'bz : (p1 ? p3  : p2);
	assign #`TM p7  = p15 ? 1'bz : (p1 ? p6  : p5);
	assign #`TM p9  = p15 ? 1'bz : (p1 ? p10 : p11);
	assign #`TM p12 = p15 ? 1'bz : (p1 ? p13 : p14);
endmodule

// '283 4-bit adder: A 5 3 14 12, B 6 2 15 11, C0 7, S 4 1 13 10, C4 9
module k555im6(input p2,p3,p5,p6,p7,p11,p12,p14,p15, output p1,p4,p9,p10,p13);
	wire [4:0] s = {1'b0, p12, p14, p3, p5} + {1'b0, p11, p15, p2, p6} + p7;
	assign #`TM {p9, p10, p13, p1, p4} = s;
endmodule

// '85 comparator: A 10 12 13 15, B 9 11 14 1; in 2 A<B 3 A=B 4 A>B; out 5 A>B 6 A=B 7 A<B
module k555sp1(input p1,p2,p3,p4,p9,p10,p11,p12,p13,p14,p15, output p5,p6,p7);
	wire [3:0] a = {p15, p13, p12, p10}, b = {p1, p14, p11, p9};
	assign #`TM p5 = (a > b) | ((a == b) & p4);
	assign #`TM p6 = (a == b) & p3;
	assign #`TM p7 = (a < b) | ((a == b) & p2);
endmodule

// '155 dual 2-to-4 decoder: A 13, B 3; section 1: 1 1C (high), 2 ~1G, outs 7 6 5 4; section 2: 15 ~2C, 14 ~2G, outs 9 10 11 12
module k1533id4(input p1,p2,p3,p13,p14,p15, output p4,p5,p6,p7,p9,p10,p11,p12);
	wire [1:0] a = {p3, p13};
	wire e1 = p1 & ~p2, e2 = ~p15 & ~p14;
	assign #`TG p7 = ~(e1 & a == 2'd0); assign #`TG p6 = ~(e1 & a == 2'd1); assign #`TG p5 = ~(e1 & a == 2'd2); assign #`TG p4 = ~(e1 & a == 2'd3);
	assign #`TG p9 = ~(e2 & a == 2'd0); assign #`TG p10 = ~(e2 & a == 2'd1); assign #`TG p11 = ~(e2 & a == 2'd2); assign #`TG p12 = ~(e2 & a == 2'd3);
endmodule

// К170АП3: TTL -> MOS phase drivers (inverting), inputs AC-coupled in the schematic
module k170ap3(input p2, p4, output p5, p7);
	assign #`TG p7 = ~p2; assign #`TG p5 = ~p4;
endmodule

// 41256 (КР565РУ7): 9-bit row / column, early write, DO 3-state
module ru7(input p1,p2,p3,p4,p5,p6,p7,p9,p10,p11,p12,p13,p15, output p14);
	reg mem [0:262143];
	wire [8:0] a = {p1, p9, p13, p10, p11, p12, p6, p7, p5};
	reg [8:0] row; reg dout = 1'b0; reg oe = 1'b0;
	integer i;
	initial for (i = 0; i < 262144; i = i + 1) mem[i] = 1'b0;
	always @(negedge p4) row <= a;
	always @(negedge p15) if (!p4) begin
		if (!p3) begin mem[{row, a}] <= p2; oe <= 1'b0; end
		else begin dout <= mem[{row, a}]; oe <= 1'b1; end
	end
	// late write (WE falls while CAS low): write, output stays off
	always @(negedge p3) if (!p4 && !p15) begin mem[{row, a}] <= p2; oe <= 1'b0; end
	// t_CAC ~ 60 ns; the output stays valid t_OFF ~ 30 ns after ~CAS rises (the video latches DD38-DD41 count on it)
	always @(posedge p15) oe <= #30 1'b0;
	assign #60 p14 = oe ? dout : 1'bz;
endmodule

// 27256: A0..A14, 20 ~CE, 22 ~OE; image from a hex file
module m27256 #(parameter FILE = "") (input p1,p2,p3,p4,p5,p6,p7,p8,p9,p10,p21,p23,p24,p25,p26,p27,p20,p22,
	output p11,p12,p13,p15,p16,p17,p18,p19);
	reg [7:0] rom [0:32767];
	initial begin : load integer k; for (k = 0; k < 32768; k = k + 1) rom[k] = 8'hFF; if (FILE != "") $readmemh(FILE, rom); end
	wire [14:0] a = {p27, p26, p2, p23, p21, p24, p25, p3, p4, p5, p6, p7, p8, p9, p10};
	wire [7:0] d = rom[a];
	wire en = ~p20 & ~p22;
	assign #100 {p19, p18, p17, p16, p15, p13, p12, p11} = en ? d : 8'hzz;
endmodule

// К556РТ4 (82S126 256 x 4, open collector): A0..A7 = 5 6 7 4 3 2 1 15, 13 ~CS1, 14 ~CS2; D0..D3 = 12 11 10 9
module k556rt4 #(parameter FILE = "") (input p1,p2,p3,p4,p5,p6,p7,p13,p14,p15, output p9,p10,p11,p12);
	reg [3:0] rom [0:255];
	initial begin : load integer k; for (k = 0; k < 256; k = k + 1) rom[k] = 4'h0; if (FILE != "") $readmemh(FILE, rom); end
	wire [7:0] a = {p15, p1, p2, p3, p4, p7, p6, p5};
	wire [3:0] d = rom[a];
	wire en = ~p13 & ~p14;
	assign #`TM p12 = (en & ~d[0]) ? 1'b0 : 1'bz;
	assign #`TM p11 = (en & ~d[1]) ? 1'b0 : 1'bz;
	assign #`TM p10 = (en & ~d[2]) ? 1'b0 : 1'bz;
	assign #`TM p9  = (en & ~d[3]) ? 1'b0 : 1'bz;
endmodule
