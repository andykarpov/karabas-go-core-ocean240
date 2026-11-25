`timescale 1ns / 1ps
`default_nettype wire

// ocean_system with a model of the SRAM of the board (two lanes of 2M x 8), for sim_ocean.cpp (verilator).
module tb_ocean (
	input  wire        clk,
	input  wire        reset,
	input  wire  [1:0] model,
	input  wire  [7:0] ps2_code,       // a PS/2 set 2 byte to ocean_kbd
	input  wire        ps2_wr,
	input  wire        colour_mpss,
	output wire [23:0] o_rgb,          // ocean_scan2x (an output pixel every two clocks: o_ce)
	output wire        o_hs,
	output wire        o_vs,
	output wire        o_de,
	output reg         o_ce,
	input  wire        rxd,
	output wire        txd,
	output wire        ce_pix,
	output wire  [2:0] rgb,
	output wire        blank,
	output wire        hsync,
	output wire        vsync,
	output wire        gc_raw,
	output wire        gk_raw,
	output wire        bell,
	output wire        running,
	output wire [15:0] cpu_addr,
	output wire        dbg_io_wr,
	output wire        dbg_io_rd,
	output wire  [7:0] dbg_dout,
	output wire  [7:0] dbg_din,
	output wire        dbg_m1,
	output wire  [7:0] dbg_c1,
	input  wire [21:0] dbg_addr,
	output wire  [7:0] dbg_q,
	// the SRAM preload of the C++ side: a byte at a time, before the reset ends
	input  wire        pl_we,
	input  wire [21:0] pl_addr,
	input  wire  [7:0] pl_data
);

wire [20:0] MA;
wire [15:0] MD;
wire [1:0] MWR_N;

ocean_system sys (
	.clk(clk), .reset(reset),
	.aux_req(1'b0), .aux_we(1'b0), .aux_addr(22'd0), .aux_din(8'd0), .aux_ack(), .aux_dout(),
	.model(model), .kb_strobe(kb_strobe), .kb_pa(kb_pa), .kb_pc(kb_pc), .kb_mods(kb_mods),
	.rxd(rxd), .txd(txd), .uart_tx_wr(), .uart_tx_data(), .uart_rx_wr(1'b0), .uart_rx_data(8'd0), .uart_rx_ready(),
	.tape_out(), .tape_in(1'b0), .tape_dac(), .bell(bell),
	.ce_pix(ce_pix), .rgb(rgb), .blank(blank), .hsync(hsync), .vsync(vsync), .hc(), .vc(),
	.running(running), .cpu_addr(cpu_addr), .dbg_io_wr(dbg_io_wr), .dbg_io_rd(dbg_io_rd),
	.dbg_dout(dbg_dout), .dbg_din(dbg_din), .dbg_m1(dbg_m1), .dbg_c1(dbg_c1),
	.MA(MA), .MD(MD), .MWR_N(MWR_N)
);
assign gc_raw = sys.video.gc;

wire kb_strobe;
wire [7:0] kb_pa;
wire [3:0] kb_pc;
wire [1:0] kb_mods;
ocean_kbd kbd (.clk(clk), .reset(reset), .positional(model == 2'd1), .ps2_code(ps2_code), .ps2_wr(ps2_wr),
	.strobe(kb_strobe), .pa(kb_pa), .pc(kb_pc), .mods(kb_mods), .f12());

wire [9:0] hc;
wire [8:0] vc;
assign hc = sys.video.hc;
assign vc = sys.video.vc;
ocean_scan2x s2x (.clk(clk), .ce_pix(ce_pix), .hc(hc), .vc(vc), .rgb_i(rgb), .colour_mpss(colour_mpss),
	.rgb(o_rgb), .hs(o_hs), .vs(o_vs), .de(o_de));
// the clocks where the outputs of s2x change (every second clock, as clk_pix of the top takes them)
reg o_ph = 1'b0;
always @(posedge clk) begin o_ph <= ~o_ph; o_ce <= o_ph; end
assign gk_raw = sys.video.gk;

reg [7:0] lo [0:2097151];
reg [7:0] hi [0:2097151];
assign MD = (MWR_N == 2'b11) ? { hi[MA], lo[MA] } : 16'bz;
assign dbg_q = dbg_addr[0] ? hi[dbg_addr[21:1]] : lo[dbg_addr[21:1]];

always @(posedge clk) begin
	if (!MWR_N[0]) lo[MA] <= MD[7:0];
	if (!MWR_N[1]) hi[MA] <= MD[15:8];
	if (pl_we) begin
		if (pl_addr[0]) hi[pl_addr[21:1]] <= pl_data; else lo[pl_addr[21:1]] <= pl_data;
	end
end

endmodule
