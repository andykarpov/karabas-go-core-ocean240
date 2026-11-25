`timescale 1ns / 1ps
`default_nettype wire

/*
 ocean_system.v — the Ocean-240.2 machine (our model of the replica of romychs, docs/HARDWARE.md).

 - one clock, clk = 49.152 MHz = 4 x the crystal of 12.288 MHz. ce_pix: the 12.288 MHz point; the CPU
   phases ce_f1 / ce_f2 once in 20 clocks (2.4576 MHz, the crystal / 5 as DD15); clk_pit 1.536 MHz (/32, DD42).
 - the CPU never waits (READY = 1): the video reads its own copy of the video RAM (ocean_vram, block RAM),
   written together with the SRAM.
 - the memory in the SRAM of the board (ocean_sram): RAM 512 KB at 000000 (8 pages of 64 KB: C1 B1-B3),
   ROM0 (DD1, E000) at 080000, ROM1 (DD2, C000) at 088000, 32 KB each (27256; banks of 8 KB by C1 B6 / B7).
   C1 (DD17 port B): B0 32K (A15 | B0), B1-B3 page, B4 ~ENROM, B5 REST (ROM0 everywhere; the port reads FF
   after a reset: its pins are inputs with pull-ups), B6 / B7 the ROM bank.
 - the I/O decode of DD11 by A7-A5 (A15-A13 on the bus): 00 DD79 (user), 20 the floppy connector (free, reads FF),
   40 DD78 (keyboard, blanks, tape in), 60 the 8253, 80 the 8259 (KF8259, MCS-80 CALL), A0 the 8251, C0 DD17, E0 DD67.
 - the 8259 inputs as the schematic: IR1 the keyboard strobe, IR2 RxRDY, IR4 counter 0; IR0, IR3, IR5-IR7 quiet.
*/

module ocean_system (
	input  wire        clk,            // 49.152 MHz
	input  wire        reset,          // a cold / board reset (RESET of the machine)

	// the ROMs and the files: the aux port of the SRAM (the loaders of the top / the sim)
	input  wire        aux_req,
	input  wire        aux_we,
	input  wire [21:0] aux_addr,
	input  wire  [7:0] aux_din,
	output wire        aux_ack,
	output wire  [7:0] aux_dout,

	// the keyboard of the 240/7 monitor: a 7-bit code with a strobe (IR1) until the ack (a PC7 pulse)
	input  wire  [6:0] kb_code,
	input  wire        kb_strobe,      // a pulse: a key
	// the RS-232 of the 8251
	input  wire        rxd,
	output wire        txd,
	input  wire        tape_in,        // PB2 of DD78
	output wire  [2:0] tape_dac,       // E2 C0-C2
	output wire        bell,           // E2 C3

	// the raster of the machine (768 x 320 points of 12.288 MHz)
	output wire        ce_pix,
	output wire  [2:0] rgb,            // R, G, B
	output wire        blank,          // ~BLNK
	output wire        hsync,          // active high
	output wire        vsync,          // active high
	output wire  [9:0] hc,
	output wire  [8:0] vc,

	// sim
	output wire        running,
	output wire [15:0] cpu_addr,
	output wire        dbg_io_wr,
	output wire        dbg_io_rd,
	output wire  [7:0] dbg_dout,
	output wire  [7:0] dbg_din,
	output wire        dbg_m1,
	output wire  [7:0] dbg_c1,

	output wire [20:0] MA,
	inout  wire [15:0] MD,
	output wire  [1:0] MWR_N
);

// ---------------------------------------------------------------- clocks
reg [4:0] div20 = 5'd0;
reg [4:0] div32 = 5'd0;
reg       ce_f1 = 1'b0, ce_f2 = 1'b0;
reg       clk_pit = 1'b0;
always @(posedge clk) begin
	div20 <= (div20 == 5'd19) ? 5'd0 : div20 + 1'd1;
	ce_f1 <= (div20 == 5'd19);
	ce_f2 <= (div20 == 5'd7);
	div32 <= div32 + 1'd1;
	clk_pit <= div32[4];
end

// ---------------------------------------------------------------- reset
reg [7:0] rst_cnt = 8'hFF;
reg cpu_reset = 1'b1;
always @(posedge clk) begin
	if (reset) rst_cnt <= 8'hFF;
	else if (rst_cnt != 8'd0) rst_cnt <= rst_cnt - 1'd1;
	cpu_reset <= (rst_cnt != 8'd0);
end
assign running = ~cpu_reset;

// ---------------------------------------------------------------- CPU
wire [15:0] addr;
wire  [7:0] cpu_o;
reg   [7:0] cpu_i;
wire        cpu_sync, cpu_rd, cpu_wr_n, cpu_inte;
wire        cpu_int;

vm80a_core cpu (
	.pin_clk(clk), .pin_f1(ce_f1), .pin_f2(ce_f2), .pin_reset(cpu_reset),
	.pin_a(addr), .pin_dout(cpu_o), .pin_din(cpu_i), .pin_aena(), .pin_dena(),
	.pin_hold(1'b0), .pin_hlda(), .pin_ready(1'b1), .pin_wait(),
	.pin_int(cpu_int), .pin_inte(cpu_inte), .pin_sync(cpu_sync), .pin_dbin(cpu_rd), .pin_wr_n(cpu_wr_n)
);
assign cpu_addr = addr;

// the status word (8228 DD3)
reg [7:0] st = 8'd0;
reg old_sync = 1'b0;
always @(posedge clk) begin
	old_sync <= cpu_sync;
	if (~old_sync & cpu_sync) st <= cpu_o;
end
wire st_inta = st[0];
wire st_out  = st[4];
wire st_inp  = st[6];
wire st_memr = st[7];

wire io_rd  = st_inp & cpu_rd;
wire io_wr  = st_out & ~cpu_wr_n;
wire inta_n = ~(st_inta & cpu_rd);
wire mem_rd = st_memr & cpu_rd;
wire mem_wr = ~st_out & ~cpu_wr_n & ~cpu_reset;
assign dbg_io_wr = io_wr;
assign dbg_io_rd = io_rd;
assign dbg_dout = cpu_o;
assign dbg_din = cpu_i;
assign dbg_m1 = cpu_sync & cpu_o[5];

// ---------------------------------------------------------------- I/O (DD11: A7-A5)
wire [2:0] io_grp = addr[7:5];
wire sel00 = io_grp == 3'd0, sel40 = io_grp == 3'd2, sel60 = io_grp == 3'd3, sel80 = io_grp == 3'd4;
wire selA0 = io_grp == 3'd5, selC0 = io_grp == 3'd6, selE0 = io_grp == 3'd7;

// the PPIs write at the end of ~IOW (k580vv55 takes the falling edge of its we_n)
wire [7:0] p00_o, p40_o, pC0_o, pE0_o;
wire [7:0] c1_pa, c1_pb, c1_pc;      // DD17: VS, the memory, HS
wire [7:0] e1_pa, e1_pb, e1_pc;      // DD67: printer, video control, tape / bell
wire [7:0] k_pc;                     // DD78 port C (C4 KBD_ACK, C7 the ack of the 240/7 monitor)
wire gc, gk;                         // the blanks (DD78 PB0 / PB1)

k580vv55 dd79 (.reset(cpu_reset), .clk_sys(clk), .addr(addr[1:0]), .we_n(~(io_wr & sel00)), .idata(cpu_o), .odata(p00_o),
	.ipa(8'hFF), .opa(), .ipb(8'hFF), .opb(), .ipc(8'hFF), .opc());

// the keyboard of the 240/7 monitor: the code waits on PA with IR1 high until the ack
reg  [6:0] kb_q = 7'd0;
reg        kb_irq = 1'b0;
reg        kpc7_d = 1'b0;
always @(posedge clk) begin
	kpc7_d <= k_pc[7];
	if (cpu_reset) kb_irq <= 1'b0;
	else if (kb_strobe) begin kb_q <= kb_code; kb_irq <= 1'b1; end
	else if (k_pc[7] & ~kpc7_d) kb_irq <= 1'b0;
end
k580vv55 dd78 (.reset(cpu_reset), .clk_sys(clk), .addr(addr[1:0]), .we_n(~(io_wr & sel40)), .idata(cpu_o), .odata(p40_o),
	.ipa({1'b0, kb_q}), .opa(),
	.ipb({3'b111, 1'b1, 1'b1, tape_in, gk, gc}), .opb(),
	.ipc(8'hFF), .opc(k_pc));

k580vv55 dd17 (.reset(cpu_reset), .clk_sys(clk), .addr(addr[1:0]), .we_n(~(io_wr & selC0)), .idata(cpu_o), .odata(pC0_o),
	.ipa(8'hFF), .opa(c1_pa), .ipb(8'hFF), .opb(c1_pb), .ipc(8'hFF), .opc(c1_pc));
k580vv55 dd67 (.reset(cpu_reset), .clk_sys(clk), .addr(addr[1:0]), .we_n(~(io_wr & selE0)), .idata(cpu_o), .odata(pE0_o),
	.ipa(8'hFF), .opa(e1_pa), .ipb(8'hFF), .opb(e1_pb), .ipc(8'hFF), .opc(e1_pc));
assign dbg_c1 = c1_pb;
assign tape_dac = e1_pc[2:0];
assign bell = e1_pc[3];

// 8253: CLK0 = CLK1 = 1.536 MHz, gates 0 / 1 high; counter 2 is the user's (GATE2 = ~TIM_EN = 0 on the board)
wire [7:0] pit_o;
wire [2:0] pit_out;
k580vi53 dd70 (.reset(cpu_reset), .clk_sys(clk), .addr(addr[1:0]), .din(cpu_o), .dout(pit_o),
	.wr(io_wr & sel60), .rd(io_rd & sel60), .clk_timer({1'b0, clk_pit, clk_pit}), .gate(3'b011), .out(pit_out), .sound_active());

// 8251
wire [7:0] uart_o;
wire       rxrdy;
ocean_vv51 dd72 (.clk(clk), .reset(cpu_reset), .cs(selA0), .cd(addr[0]), .wr(io_wr), .rd(io_rd), .din(cpu_o), .dout(uart_o),
	.txc(pit_out[1]), .rxc(pit_out[1]), .txd(txd), .rxd(rxd), .rxrdy(rxrdy));

// 8259 (MCS-80: the CALL and its address in three INTA cycles)
wire [7:0] pic_o;
KF8259 dd75 (
	.clock(clk), .reset(cpu_reset),
	.chip_select_n(~sel80), .read_enable_n(~io_rd), .write_enable_n(~io_wr), .address(addr[0]),
	.data_bus_in(cpu_o), .data_bus_out(pic_o), .data_bus_io(),
	.cascade_in(3'b000), .cascade_out(), .cascade_io(), .slave_program_n(1'b1),
	.buffer_enable(), .slave_program_or_enable_buffer(),
	.interrupt_acknowledge_n(inta_n), .interrupt_to_cpu(cpu_int),
	.interrupt_request({3'b000, pit_out[0], 1'b0, rxrdy, kb_irq, 1'b0})
);

reg [7:0] io_data;
always @(*) begin
	case (io_grp)
		3'd0: io_data = p00_o;
		3'd2: io_data = p40_o;
		3'd3: io_data = pit_o;
		3'd4: io_data = pic_o;
		3'd5: io_data = uart_o;
		3'd6: io_data = pC0_o;
		3'd7: io_data = pE0_o;
		default: io_data = 8'hFF;      // 20-3F: the floppy connector, nothing there
	endcase
end

// ---------------------------------------------------------------- memory (C1 = DD17 port B)
wire b_32k = c1_pb[0];
wire [2:0] b_page = c1_pb[3:1];
wire enrom_n = c1_pb[4];
wire rest = c1_pb[5];
wire [1:0] rom_bank = c1_pb[7:6];
wire rom0_sel = rest | (~enrom_n & (addr[15:13] == 3'b111));
wire rom1_sel = ~rest & ~enrom_n & (addr[15:13] == 3'b110);
wire rom_sel = rom0_sel | rom1_sel;
wire [18:0] ram_a = {b_page, addr[15] | b_32k, addr[14:0]};
// 080000 + rom1 * 8000 + bank * 2000 + a
wire [21:0] rom_a = 22'h080000 | {6'd0, rom1_sel, 15'd0} | {7'd0, rom_bank, addr[12:0]};
wire [21:0] sram_a = rom_sel ? rom_a : {3'b000, ram_a};
wire        ram_we = mem_wr & ~rom_sel;
wire  [7:0] ram_o;

ocean_sram sram (
	.clk(clk), .addr(sram_a), .we(ram_we), .din(cpu_o), .din_hi(8'd0), .wr16(1'b0), .dout(ram_o), .rd_ok(),
	.aux_req(aux_req), .aux_we(aux_we), .aux_addr(aux_addr), .aux_din(aux_din), .aux_ack(aux_ack), .aux_dout(aux_dout),
	.vid_req(1'b0), .vid_addr(21'd0), .vid_dout(), .vid_valid(),
	.MA(MA), .MD(MD), .MWR_N(MWR_N)
);

always @(*) begin
	if (st_inta) cpu_i = pic_o;
	else if (st_inp) cpu_i = io_data;
	else cpu_i = ram_o;
end

// ---------------------------------------------------------------- video RAM copy: C000-FFFF of pages 0 / 1
// (the video address: A15 = A14 = 1, A16 = VSU, A17 = A18 = 0); the loaders write it too (aux, RAM part)
wire vram_cpu = ram_we & (ram_a[18:17] == 2'b00) & (ram_a[15:14] == 2'b11);
wire vram_aux = aux_req & aux_we & (aux_addr[21:17] == 5'd0) & (aux_addr[15:14] == 2'b11);
reg  we_d = 1'b0;
always @(posedge clk) we_d <= vram_cpu;
wire        vw = (vram_cpu & ~we_d) | (vram_aux & aux_ack);
wire        vw_p = vram_aux ? aux_addr[16] : ram_a[16];
wire [13:0] vw_a = vram_aux ? aux_addr[13:0] : ram_a[13:0];
wire  [7:0] vw_d = vram_aux ? aux_din : cpu_o;

ocean_video video (
	.clk(clk), .vs_reg(c1_pa), .hs_reg(c1_pc), .vctl(e1_pb),
	.vw(vw), .vw_page(vw_p), .vw_addr(vw_a), .vw_data(vw_d),
	.ce_pix(ce_pix), .rgb(rgb), .blank(blank), .hsync(hsync), .vsync(vsync), .gc(gc), .gk(gk), .hc(hc), .vc(vc)
);

endmodule
