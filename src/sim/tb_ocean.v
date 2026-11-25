`timescale 1ns / 1ps
`default_nettype wire

// ocean_system with a model of the SRAM of the board (two lanes of 2M x 8), for sim_ocean.cpp (verilator).
module tb_ocean (
	input  wire        clk,
	input  wire        reset,
	input  wire  [6:0] kb_code,
	input  wire        kb_strobe,
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
	.kb_code(kb_code), .kb_strobe(kb_strobe), .rxd(rxd), .txd(txd), .tape_in(1'b0), .tape_dac(), .bell(bell),
	.ce_pix(ce_pix), .rgb(rgb), .blank(blank), .hsync(hsync), .vsync(vsync), .hc(), .vc(),
	.running(running), .cpu_addr(cpu_addr), .dbg_io_wr(dbg_io_wr), .dbg_io_rd(dbg_io_rd),
	.dbg_dout(dbg_dout), .dbg_din(dbg_din), .dbg_m1(dbg_m1), .dbg_c1(dbg_c1),
	.MA(MA), .MD(MD), .MWR_N(MWR_N)
);
assign gc_raw = sys.video.gc;
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
