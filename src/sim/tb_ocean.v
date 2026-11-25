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
	// an FL file of slot 6 (the tape .wav) as the mcu sends it, the tape line out
	input  wire        file_active,
	input  wire [31:0] file_addr,
	input  wire  [7:0] file_data,
	input  wire        file_wr,
	output wire        tape_out,
	output wire        tape_playing,
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
	input  wire  [7:0] pl_data,
	// the mounter of kg_mcu2 (sdc_* of kg_l2_img) for the floppy images, slots 4 / 5 (the model in sim_ocean.cpp)
	input  wire  [7:0] sdc_img_mounted,
	input  wire [63:0] sdc_img_size,
	output wire  [7:0] sdc_rd,
	output wire  [7:0] sdc_wr,
	output wire [31:0] sdc_sector,
	input  wire        sdc_busy,
	input  wire        sdc_done,
	input  wire  [2:0] sdc_slot,
	input  wire        sdc_byte_in_strobe,
	input  wire  [8:0] sdc_byte_addr,
	input  wire  [7:0] sdc_byte_in_data,
	output wire  [7:0] sdc_byte_out_data,
	input  wire  [7:0] img_wp,
	output wire        fdd_motor
);

wire [2:0] rgb_pt, rgb_bg;
wire [20:0] MA;
wire [15:0] MD;
wire [1:0] MWR_N;

ocean_system sys (
	.clk(clk), .reset(reset),
	.aux_req(aux_req), .aux_we(aux_we), .aux_addr(aux_addr), .aux_din(aux_din), .aux_ack(aux_ack), .aux_dout(aux_dout),
	.model(model), .kb_strobe(kb_strobe), .kb_pa(kb_pa), .kb_pc(kb_pc), .kb_mods(kb_mods),
	.rxd(rxd), .txd(txd), .uart_tx_wr(), .uart_tx_data(), .uart_rx_wr(1'b0), .uart_rx_data(8'd0), .uart_rx_ready(),
	.tape_out(tape_out), .tape_in(tape_bit), .tape_dac(), .bell(bell),
	.fdc_cs(fdc_cs), .fdc_a(fdc_a), .fdc_din(fdc_din), .fdc_rd(fdc_rd), .fdc_wr(fdc_wr), .fdc_in24(fdc_in24),
	.fdc_ce(fdc_ce), .fdc_reset(fdc_reset), .fdc_dout(fdc_dout), .fdc_ready(fdc_ready),
	.ce_pix(ce_pix), .rgb(rgb), .rgb_pt(rgb_pt), .rgb_bg(rgb_bg), .blank(blank), .hsync(hsync), .vsync(vsync), .hc(), .vc(),
	.running(running), .cpu_addr(cpu_addr), .dbg_io_wr(dbg_io_wr), .dbg_io_rd(dbg_io_rd),
	.dbg_dout(dbg_dout), .dbg_din(dbg_din), .dbg_m1(dbg_m1), .dbg_c1(dbg_c1),
	.MA(MA), .MD(MD), .MWR_N(MWR_N)
);
assign gc_raw = sys.video.gc;

// the loader (the tape file), the tape player and the aux port as in the tops
wire aux_req, aux_we, aux_ack, l_req, l_we, l_ack, t_req, t_ack, tape_bit;
wire [21:0] aux_addr, l_addr, t_addr;
wire [7:0] aux_din, aux_dout, l_din;
wire [5:0] acks;
wire fdc_cs, fdc_rd, fdc_wr, fdc_in24, fdc_ce, fdc_reset, fdc_ready;
wire [2:0] fdc_a;
wire [7:0] fdc_din, fdc_dout;
wire f0_req, f0_we, f0_ack, f1_req, f1_we, f1_ack;
wire [21:0] f0_addr, f1_addr;
wire [7:0] f0_din, f1_din;
// the motor stops after 1 s here (3 on the board): shorter runs
ocean_fdd #(.CLK_HZ(49152000), .MOTOR_S(1)) fdd (.clk(clk), .reset(fdc_reset), .ce(fdc_ce),
	.cs(fdc_cs), .a(fdc_a), .din(fdc_din), .rd(fdc_rd), .wr(fdc_wr), .dout(fdc_dout), .in24(fdc_in24), .ready(fdc_ready),
	.img_wp(img_wp), .sdc_img_mounted(sdc_img_mounted), .sdc_img_size(sdc_img_size), .sdc_rd(sdc_rd), .sdc_wr(sdc_wr),
	.sdc_sector(sdc_sector), .sdc_busy(sdc_busy), .sdc_done(sdc_done), .sdc_error(1'b0), .sdc_slot(sdc_slot),
	.sdc_byte_in_strobe(sdc_byte_in_strobe), .sdc_byte_addr(sdc_byte_addr), .sdc_byte_in_data(sdc_byte_in_data),
	.sdc_byte_out_data(sdc_byte_out_data), .pause(file_active),
	.a0_req(f0_req), .a0_we(f0_we), .a0_addr(f0_addr), .a0_din(f0_din), .a0_ack(f0_ack),
	.a1_req(f1_req), .a1_we(f1_we), .a1_addr(f1_addr), .a1_din(f1_din), .a1_ack(f1_ack), .aux_dout(aux_dout),
	.motor(fdd_motor), .mounted());
ocean_loader loader (.clk(clk), .rom_active(1'b0), .rom_addr(22'd0), .rom_data(8'd0), .rom_wr(1'b0),
	.file_active(file_active), .file_slot(8'd6), .file_addr(file_addr), .file_data(file_data), .file_wr(file_wr), .busy(),
	.aux_req(l_req), .aux_we(l_we), .aux_addr(l_addr), .aux_din(l_din), .aux_ack(l_ack));
ocean_tape #(.CLK_HZ(49152000)) tape (.clk(clk), .play(1'b0), .stop(1'b0),
	.file_active(file_active), .file_addr(file_addr), .file_data(file_data), .file_wr(file_wr),
	.aux_req(t_req), .aux_addr(t_addr), .aux_ack(t_ack), .aux_dout(aux_dout), .bit_out(tape_bit), .playing(tape_playing));
ocean_aux #(.N(6)) arb (.clk(clk), .req({f1_req, f0_req, t_req, 1'b0, 1'b0, l_req}),
	.we({f1_we, f0_we, 1'b0, 1'b0, 1'b0, l_we}),
	.addr({f1_addr, f0_addr, t_addr, 22'd0, 22'd0, l_addr}), .din({f1_din, f0_din, 8'd0, 8'd0, 8'd0, l_din}), .ack(acks),
	.aux_req(aux_req), .aux_we(aux_we), .aux_addr(aux_addr), .aux_din(aux_din), .aux_ack(aux_ack));
assign l_ack = acks[0];
assign t_ack = acks[3];
assign f0_ack = acks[4];
assign f1_ack = acks[5];

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
ocean_scan2x s2x (.clk(clk), .ce_pix(ce_pix), .hc(hc), .vc(vc), .pt_i(rgb_pt), .bg_i(rgb_bg), .colour_mpss(colour_mpss),
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
