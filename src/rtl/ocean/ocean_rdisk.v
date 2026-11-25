`timescale 1ns / 1ps
`default_nettype wire

/*
 ocean_rdisk.v — the RAM disk of the Ocean kept on the sd card (docs/PLAN.md Ф2).

 Both CP/M of the core (REL.5 of the 240/7 monitor, REL.7 of MONITOR+) keep their drive A: in page 1 of the RAM
 (64 KB: SPT 16, 1 KB blocks, DSM 63, DRM 31, OFF 0 — the same DPB). kg_bk_ram (modules) keeps that page in a file:
 the firmware opens or creates <core dir>/saves/ramdisk.sav (core.json loader save_name), it is read into the SRAM
 at 010000 before the CPU starts, and the sectors the CPU writes there are written back a second after the last write.

 A cold boot of CP/M formats the RAM disk unless the word at 0006 is its BDOS (BC06 for REL.5, BA06 for REL.7): the
 check of the real machine that keeps the RAM disk over the reset button. So when the file has data the word is
 written before the CPU starts (as if the power had stayed on), and again on a change of the model (the CPU is reset,
 the other CP/M looks for its own BDOS). A new file (zeros) gets no word: CP/M formats it and it is saved.
 The test ROM (model 2) writes all the RAM: no file then (kg_bk_ram held in reset, its writes not saved).

 Two masters of the aux port of ocean_sram (ocean_aux): the word (mk_*) and kg_bk_ram (bk_*).
*/

module ocean_rdisk #(
	parameter CLK_HZ = 49200000
) (
	input  wire        clk,
	input  wire        areset,
	input  wire  [1:0] model,
	input  wire        ld_busy,        // the ROMs of the core file are being loaded
	output wire        hold,           // keep the CPU in reset
	output wire        mounted,
	output wire        saving,

	input  wire        ram_wr,         // ocean_system: a CPU write of the RAM
	input  wire [18:0] ram_wr_a,

	// two masters of ocean_aux: the word, kg_bk_ram
	output reg         mk_req = 1'b0,
	output reg  [21:0] mk_addr = 22'd0,
	output reg   [7:0] mk_din = 8'd0,
	input  wire        mk_ack,
	output wire        bk_req,
	output wire        bk_we,
	output wire [21:0] bk_addr,
	output wire  [7:0] bk_din,
	input  wire        bk_ack,
	input  wire  [7:0] aux_dout,

	// the mounter of kg_mcu2 (SDC_*, slot 0), its BK_* inputs and IMG_FLUSH
	input  wire  [7:0] sdc_img_mounted,
	input  wire [63:0] sdc_img_size,
	output wire  [7:0] sdc_rd,
	output wire  [7:0] sdc_wr,
	output wire [31:0] sdc_sector,
	input  wire        sdc_busy,
	input  wire        sdc_done,
	input  wire        sdc_error,
	input  wire  [2:0] sdc_slot,
	input  wire        sdc_byte_in_strobe,
	input  wire  [8:0] sdc_byte_addr,
	input  wire  [7:0] sdc_byte_in_data,
	output wire  [7:0] sdc_byte_out_data,
	input  wire  [7:0] img_flush,
	output wire        bk_mount,
	output wire        bk_flushed,
	output wire [31:0] bk_size,
	output wire  [7:0] bk_kind,
	output wire  [7:0] bk_result
);

wire use_disk = (model != 2'd2);

// ---------------------------------------------------------------- the start of kg_bk_ram
reg  ld_busy_d = 1'b1;
reg  [1:0] model_d = 2'd0;
reg  started = 1'b0;
reg  bk_start = 1'b0;
reg  bk_reset = 1'b1;
always @(posedge clk) begin
	ld_busy_d <= ld_busy;
	model_d <= model;
	bk_start <= 1'b0;
	bk_reset <= 1'b0;
	if (areset) begin started <= 1'b0; bk_reset <= 1'b1; end
	else if (!use_disk) begin started <= 1'b0; bk_reset <= 1'b1; end
	else if (!started && !ld_busy && !ld_busy_d) begin started <= 1'b1; bk_start <= 1'b1; end
end

wire bk_busy;
wire [15:0] bk_a;
assign bk_addr = {6'b000001, bk_a};   // page 1: 010000
wire bk_wr = ram_wr && ram_wr_a[18:16] == 3'b001;

kg_bk_ram #(.SLOT(3'd0), .IDLE_CLOCKS(CLK_HZ), .MAX_CLOCKS(27'd120000000), .MOUNT_CLOCKS(CLK_HZ),
	.GRACE_CLOCKS(CLK_HZ / 100), .TIMEOUT(CLK_HZ / 5), .LINK(2), .SBITS(7)) bk (
	.clk(clk), .reset(bk_reset),
	.start(bk_start), .size(8'd128), .kind(8'h00), .busy(bk_busy), .mounted(mounted), .saving(saving), .save_error(),
	.wr(bk_wr), .wr_addr(ram_wr_a[15:0]),
	.mem_req(bk_req), .mem_we(bk_we), .mem_addr(bk_a), .mem_din(bk_din), .mem_ack(bk_ack), .mem_dout(aux_dout),
	.img_mounted(8'd0), .img_size(64'd0), .img_data_wr(1'b0), .img_data_addr(9'd0), .img_data(8'd0),
	.img_result_wr(1'b0), .img_result(8'd0), .img_sum(16'd0), .img_flush(img_flush), .img_q_wr(), .img_q_di(), .img_q_ack(1'b0),
	.sdc_img_mounted_i(sdc_img_mounted), .sdc_img_size_i(sdc_img_size), .sdc_rd_o(sdc_rd), .sdc_wr_o(sdc_wr),
	.sdc_sector_o(sdc_sector), .sdc_busy_i(sdc_busy), .sdc_done_i(sdc_done), .sdc_error_i(sdc_error), .sdc_slot_i(sdc_slot),
	.sdc_byte_in_strobe_i(sdc_byte_in_strobe), .sdc_byte_addr_i(sdc_byte_addr), .sdc_byte_in_data_i(sdc_byte_in_data),
	.sdc_byte_out_data_o(sdc_byte_out_data),
	.bk_mount(bk_mount), .bk_flushed(bk_flushed), .bk_size(bk_size), .bk_kind(bk_kind), .bk_result(bk_result)
);

// ---------------------------------------------------------------- the BDOS word at 0006 / 0007
reg  data_seen = 1'b0;       // the file had a non-zero byte
reg  bk_busy_d = 1'b0;
reg  [1:0] mk = 2'd0;        // the word to write: 0 none, 1 the low byte next, 2 the high byte next
wire [7:0] bdos_hi = (model == 2'd1) ? 8'hBA : 8'hBC;
always @(posedge clk) begin
	bk_busy_d <= bk_busy;
	if (bk_start) data_seen <= 1'b0;
	if (bk_req && bk_we && bk_ack && bk_din != 8'd0) data_seen <= 1'b1;
	// after the file is read, or on a change between the CP/M models while it is mounted
	if ((bk_busy_d && !bk_busy && mounted && data_seen) ||
	    (model != model_d && use_disk && mounted && data_seen && started)) mk <= 2'd1;
	if (mk_ack) begin
		mk_req <= 1'b0;
		mk <= (mk == 2'd1) ? 2'd2 : 2'd0;
	end else if (mk != 2'd0 && !mk_req) begin
		mk_req <= 1'b1;
		mk_addr <= (mk == 2'd1) ? 22'h000006 : 22'h000007;
		mk_din <= (mk == 2'd1) ? 8'h06 : bdos_hi;
	end
end
assign hold = bk_busy | bk_busy_d | (mk != 2'd0);   // bk_busy_d: no gap before the word

endmodule
