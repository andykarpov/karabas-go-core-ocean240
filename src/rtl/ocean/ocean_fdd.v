`timescale 1ns / 1ps
`default_nettype wire

/*
 ocean_fdd.v — the floppy controller of the Ocean at 20-3F (docs/HARDWARE.md, the floppy; docs/PLAN.md Ф4).

 The ports, as the driver of HARDWARE MONITOR+ (E030 read, E033 write; FBB2-FC8E) uses them (and Emu80 okean.conf):
 - 20-23: the KR1818VG93 (command / status, track, sector, data: A1 A0 straight);
 - 24 read: the wait of the controller: the CPU waits (READY) until DRQ or INTRQ, then reads B0 = DRQ (the driver
   moves a sector by "IN 24 / RRCA / IN 23 / JC"); a write does nothing;
 - 25 write: B2 the drive (1: drive 0, 0: drive 1), B5 the side, B3 the motor (a rise starts it), B0 B1 = 1;
   25 read: B0 = ~INTRQ, B1-B6 the bits 0-5 written (the driver reads, masks 4E, shifts right and writes them back
   to pulse B3), B7 = 1 while the motor stands (a monostable: MOTOR_S seconds after the start or the last command;
   the reads of the status do not keep it on: the driver polls the status until the motor stops).
 CP/M REL.7/2D asks the monitor for drive codes 1 and 2 only: B: is side 0 and C: side 1 of drive 0. The codes 3 / 4
 of the monitor are drive 1.

 The images: .okd (Emu80), 80 tracks x 2 sides x 9 sectors of 512 bytes (737 280 bytes), track, side, sector order;
 the CP/M BIOS keeps its interleave in the sector numbers (D8B2: 1 8 6 4 2 9 7 5 3). Each drive has its copy in the
 SRAM (ocean_fdd_cache: drive 0 at 090000, drive 1 at 144000, 1440 sectors each, up to 1F8000; the tape starts at
 200000) filled from the mounter of kg_mcu2 (slots 4 / 5: the F items).

 An empty drive: the VG93 says NOT READY (status B7), the monitor waits for the motor to stop and gives its error;
 a command of type II ends at once with INTRQ, so IN 24 never waits for long. In case it does (no DRQ, no INTRQ),
 READY comes back after WAIT_MAX clocks.
*/

module ocean_fdd #(
	parameter CLK_HZ = 49200000,
	parameter MOTOR_S = 3
) (
	input  wire        clk,
	input  wire        reset,          // the reset of the CPU
	input  wire        ce,             // the CPU clock (2.46 MHz): the VG93 runs on it

	// the CPU (ocean_system): the group 20-3F, the levels of ~IOR / ~IOW
	input  wire        cs,
	input  wire  [2:0] a,
	input  wire  [7:0] din,
	input  wire        rd,
	input  wire        wr,
	output reg   [7:0] dout,
	input  wire        in24,           // the CPU is in an IN 24 cycle
	output wire        ready,          // READY of the CPU

	// the mounter of kg_mcu2: slots 4 / 5
	input  wire  [7:0] img_wp,
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
	input  wire        pause,          // a file goes into the SRAM: no background fill

	// two masters of ocean_aux: the caches of drive 0 / 1
	output wire        a0_req,
	output wire        a0_we,
	output wire [21:0] a0_addr,
	output wire  [7:0] a0_din,
	input  wire        a0_ack,
	output wire        a1_req,
	output wire        a1_we,
	output wire [21:0] a1_addr,
	output wire  [7:0] a1_din,
	input  wire        a1_ack,
	input  wire  [7:0] aux_dout,

	output wire        motor,          // the motor runs (an LED)
	output wire  [1:0] mounted
);

// ---------------------------------------------------------------- port 25
reg  [5:0] lat = 6'b000111;
reg        wr_d = 1'b0;
wire       wr25 = cs & wr & a[2] & a[0];
wire       fdc_io = cs & ~a[2];
wire       drive = ~lat[2];
wire       side = lat[5];

localparam MOTOR_CLK = CLK_HZ * MOTOR_S;
reg [28:0] mtimer = 29'd0;
reg        acc_d = 1'b0;
wire       acc = fdc_io & wr & (a[1:0] == 2'd0);   // a command
always @(posedge clk) begin
	wr_d <= wr25;
	acc_d <= acc;
	if (reset) begin
		lat <= 6'b000111;
		mtimer <= 29'd0;
	end else begin
		if (wr25 & ~wr_d) lat <= din[5:0];
		if (wr25 & ~wr_d & din[3] & ~lat[3]) mtimer <= MOTOR_CLK[28:0];        // B3 rises: start
		else if (acc & ~acc_d & (mtimer != 29'd0)) mtimer <= MOTOR_CLK[28:0];  // a command keeps a running motor on
		else if (mtimer != 29'd0) mtimer <= mtimer - 1'd1;
	end
end
assign motor = mtimer != 29'd0;

// ---------------------------------------------------------------- the images
reg [1:0] disk = 2'b00;
always @(posedge clk) begin
	if (sdc_img_mounted[4]) disk[0] <= |sdc_img_size[31:0];
	if (sdc_img_mounted[5]) disk[1] <= |sdc_img_size[31:0];
end
assign mounted = disk;
wire fdd_ready = drive ? disk[1] : disk[0];

// ---------------------------------------------------------------- the VG93
wire [31:0] sd_lba;
wire sd_rd, sd_wr, sd_ack_0, sd_ack_1, sd_bwr_0, sd_bwr_1;
wire [8:0] sd_addr_0, sd_addr_1;
wire [7:0] sd_do_0, sd_do_1, sd_buff_din;
wire [7:0] fdc_do;
wire drq, intrq;

wd1793 #(.RWMODE(1), .EDSK(0)) fdc (
	.clk_sys(clk),
	.ce(ce),
	.reset(reset),
	.io_en(fdc_io),
	.rd(rd),
	.wr(wr),
	.addr(a[1:0]),
	.din(din),
	.dout(fdc_do),
	.drq(drq),
	.intrq(intrq),
	.busy(),
	.wp(drive ? img_wp[5] : img_wp[4]),
	.size_code(3'd2),         // 9 sectors of 512 bytes
	.layout(1'b0),            // track, side, sector
	.side(side),
	.ready(fdd_ready),
	.img_mounted(sdc_img_mounted[4] | sdc_img_mounted[5]),
	.img_size(sdc_img_size[19:0]),
	.prepare(),
	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack_0 | sd_ack_1),
	.sd_buff_addr(drive ? sd_addr_1 : sd_addr_0),
	.sd_buff_dout(drive ? sd_do_1 : sd_do_0),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_bwr_0 | sd_bwr_1),
	.input_active(1'b0),
	.input_addr(20'd0),
	.input_data(8'd0),
	.input_wr(1'b0),
	.buff_addr(),
	.buff_read(),
	.buff_din(8'd0)
);

always @(*) begin
	if (!a[2]) dout = fdc_do;
	else if (!a[0]) dout = {7'd0, drq};
	else dout = {~motor, lat, ~intrq};
end

// ---------------------------------------------------------------- IN 24: READY
localparam WAIT_MAX = CLK_HZ;      // a second
reg [25:0] wcnt = 26'd0;
wire       waiting = in24 & ~drq & ~intrq;
always @(posedge clk) begin
	if (!in24 || reset) wcnt <= 26'd0;
	else if (waiting && wcnt != WAIT_MAX[25:0]) wcnt <= wcnt + 1'd1;
end
assign ready = ~waiting | (wcnt == WAIT_MAX[25:0]) | reset;

// ---------------------------------------------------------------- the copies in the SRAM
wire [7:0] sdc_out_0, sdc_out_1;
wire [31:0] sdc_sector_0, sdc_sector_1;
wire sdc_rd_0, sdc_wr_0, sdc_rd_1, sdc_wr_1;

ocean_fdd_cache #(.BASE(22'h090000), .MAXSEC(1440), .SLOT(3'd4)) cache_0 (
	.clk(clk),
	.img_mounted(sdc_img_mounted[4]), .img_size(sdc_img_size[31:0]),
	.sd_rd(sd_rd & ~drive), .sd_wr(sd_wr & ~drive), .sd_lba(sd_lba), .sd_ack(sd_ack_0),
	.sd_buff_addr(sd_addr_0), .sd_buff_dout(sd_do_0), .sd_buff_wr(sd_bwr_0), .sd_buff_din(sd_buff_din),
	.sdc_rd(sdc_rd_0), .sdc_wr(sdc_wr_0), .sdc_sector(sdc_sector_0), .sdc_busy(sdc_busy), .sdc_done(sdc_done),
	.sdc_error(sdc_error), .sdc_slot(sdc_slot), .sdc_byte_in_strobe(sdc_byte_in_strobe),
	.sdc_byte_addr(sdc_byte_addr), .sdc_byte_in_data(sdc_byte_in_data), .sdc_byte_out_data(sdc_out_0),
	.pause(pause),
	.aux_req(a0_req), .aux_we(a0_we), .aux_addr(a0_addr), .aux_din(a0_din), .aux_ack(a0_ack), .aux_dout(aux_dout),
	.filling(), .filled()
);

ocean_fdd_cache #(.BASE(22'h144000), .MAXSEC(1440), .SLOT(3'd5)) cache_1 (
	.clk(clk),
	.img_mounted(sdc_img_mounted[5]), .img_size(sdc_img_size[31:0]),
	.sd_rd(sd_rd & drive), .sd_wr(sd_wr & drive), .sd_lba(sd_lba), .sd_ack(sd_ack_1),
	.sd_buff_addr(sd_addr_1), .sd_buff_dout(sd_do_1), .sd_buff_wr(sd_bwr_1), .sd_buff_din(sd_buff_din),
	.sdc_rd(sdc_rd_1), .sdc_wr(sdc_wr_1), .sdc_sector(sdc_sector_1), .sdc_busy(sdc_busy), .sdc_done(sdc_done),
	.sdc_error(sdc_error), .sdc_slot(sdc_slot), .sdc_byte_in_strobe(sdc_byte_in_strobe),
	.sdc_byte_addr(sdc_byte_addr), .sdc_byte_in_data(sdc_byte_in_data), .sdc_byte_out_data(sdc_out_1),
	.pause(pause),
	.aux_req(a1_req), .aux_we(a1_we), .aux_addr(a1_addr), .aux_din(a1_din), .aux_ack(a1_ack), .aux_dout(aux_dout),
	.filling(), .filled()
);

// the mounter takes the lowest slot first: the sector of slot 4 while it asks
assign sdc_rd = {2'b00, sdc_rd_1, sdc_rd_0, 4'd0};
assign sdc_wr = {2'b00, sdc_wr_1, sdc_wr_0, 4'd0};
assign sdc_sector = (sdc_rd_0 || sdc_wr_0) ? sdc_sector_0 : sdc_sector_1;
assign sdc_byte_out_data = (sdc_slot == 3'd5) ? sdc_out_1 : sdc_out_0;

endmodule
