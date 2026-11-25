`timescale 1ns / 1ps
`default_nettype wire

/*
 Ocean-240.2 core for Karabas Mini before rev.G (HDMI, sigma-delta audio, PCM1808). Made by tools/mktops.py
 from karabas_minig_top.v (do not edit: change that one and run it): the same except the pins,
 the MCU link (MCU_SCK not on a clock pin), the audio (AUDIO_L / AUDIO_R).

 The machine is ocean_system; all its ROMs come from the core file (core.json, ocean_loader): 080000 the 240/7
 monitor, 082000 CP/M REL.5, 084000 HARDWARE MONITOR+, 086000 CP/M REL.7, 088000 the test ROM of MPSS; the item
 Model picks ROM0 / ROM1 of them and the keyboard (ASCII / positional, ocean_kbd).

 Clocks: a DCM makes 48 MHz of the 50 MHz crystal (24 / 25), a PLL on it (/2, x41: VCO 984 MHz): clk_sys 49.2 MHz
 (/20: the machine, 4 x the 12.3 MHz point; the replica has 49.152, +0.1 %), clk_pix 24.6 MHz (/40: ocean_scan2x,
 768 x 640, 50.05 Hz), clk_hdmi 123 MHz and its inverse (/8: the HDMI serialiser, 5 x clk_pix), clk_8 8.0 MHz (/123:
 FT_CLK_OUT, every Mini / Mini G core drives it). clk_pix and clk_sys are of one PLL: the outputs of ocean_scan2x
 (on clk_sys, changing every second clock) are taken on clk_pix directly.

 The base set of the board: the sound (Bell E2 C3) + the tape monitor (kg_tape_monitor: TAPE_IN, TAPE_OUT = E2 C2)
 + the ADC (PCM1808: the line in and the MIDI synth) -> PCM5102, HDMI; the peaks of the mix to the mcu; MIDI_TX idle
 (the Ocean has no MIDI). The 8251 talks to the USB-UART of the mcu (port 0) by bytes of its data register.

 The RAM disk (page 1, CP/M drive A:) is kept in <core dir>/saves/ramdisk.sav (ocean_rdisk, kg_bk_ram).

 Soft switches (the index of the item in the osd of core.json):
   0 Model (240.2 / Turbo / Test)   1 Colours (replica / MPSS)   2 Tape monitor (off / in / out / both)   3 Reset
   4 Tape (FL slot 6: a .wav, played into PB2 at the end of its load)   5 Tape play (from the start)   6 Tape stop
*/

module karabas_mini_top (
	input wire CLK_50MHZ,

	inout wire UART_RX,
	inout wire UART_TX,
	inout wire UART_CTS,
	inout wire ESP_RESET_N,
	inout wire ESP_BOOT_N,

	output wire [20:0] MA,
	inout wire [15:0] MD,
	output wire [1:0] MWR_N,
	output wire [1:0] MRD_N,

	output wire [1:0] SDR_BA,
	output wire [12:0] SDR_A,
	output wire SDR_CLK,
	output wire [1:0] SDR_DQM,
	output wire SDR_WE_N,
	output wire SDR_CAS_N,
	output wire SDR_RAS_N,
	inout wire [15:0] SDR_DQ,

	output wire SD_CS_N,
	output wire SD_CLK,
	output wire SD_DI,
	input wire SD_DO,
	input wire SD_DET_N,

	input wire [7:0] VGA_R,
	input wire [7:0] VGA_G,
	input wire [7:0] VGA_B,
	input wire VGA_HS,
	input wire VGA_VS,

	output wire [3:0] TMDS_P,
	output wire [3:0] TMDS_N,

	output wire FT_SPI_CS_N,
	output wire FT_SPI_SCK,
	input wire FT_SPI_MISO,
	output wire FT_SPI_MOSI,
	input wire FT_INT_N,
	input wire FT_CLK,
	input wire FT_DE,
	input wire FT_AUDIO,
	input wire FT_DISP,
	output wire FT_RESET,
	output wire FT_CLK_OUT,

	output wire [2:0] WA,
	output wire [1:0] WCS_N,
	output wire WRD_N,
	output wire WWR_N,
	output wire WRESET_N,
	inout wire [15:0] WD,

	output wire TAPE_OUT,
	input wire TAPE_IN,

	output wire AUDIO_L,
	output wire AUDIO_R,

	output wire ADC_CLK,
	inout wire ADC_BCK,
	inout wire ADC_LRCK,
	input wire ADC_DOUT,

	input wire MCU_CS_N,
	input wire MCU_SCK,
	inout wire MCU_MOSI,
	output wire MCU_MISO,
	inout wire [3:0] MCU_IO, // [1] INT of link v2, [2] sd2 cs_n, [3] ft cs_n

	output wire MIDI_TX,

	output wire MIDI_CLK,
	output wire MIDI_RESET_N,

	output wire FLASH_CS_N,
	input wire FLASH_DO,
	output wire FLASH_DI,
	output wire FLASH_SCK,
	output wire FLASH_WP_N,
	output wire FLASH_HOLD_N
);

// ------------------------------------------------------------------ unused

assign SDR_BA = 2'b11;
assign SDR_A = 13'h1FFF;
assign SDR_CLK = 1'b1;
assign SDR_DQM = 2'b11;
assign SDR_WE_N = 1'b1;
assign SDR_CAS_N = 1'b1;
assign SDR_RAS_N = 1'b1;
assign SDR_DQ = 16'bz;

assign WA = 3'b000;
assign WCS_N = 2'b11;
assign WRD_N = 1'b1;
assign WWR_N = 1'b1;
assign WRESET_N = 1'b1;
assign WD = 16'bz;

assign ESP_RESET_N = 1'bz;
assign ESP_BOOT_N = 1'bz;
assign FT_RESET = 1'b1;
assign MIDI_CLK = 1'b1;
assign MIDI_RESET_N = 1'b1;
assign MIDI_TX = 1'b1;      // the Ocean has no MIDI out
assign UART_RX = 1'bz;
assign UART_TX = 1'bz;
assign UART_CTS = 1'bz;

assign FLASH_CS_N = 1'b1;   // Mini G2: also the SDRAM ~CS (SDRAM off)
assign FLASH_DI = 1'b1;
assign FLASH_SCK = 1'b0;
assign FLASH_WP_N = 1'b1;
assign FLASH_HOLD_N = 1'b1;

assign MRD_N = 2'b00;  // SRAM /OE: always on, ocean_sram drives MD only with /WE

// ------------------------------------------------------------------ clocks

wire clk48_dcm, locked_dcm;
kg_dcm #(
	.CLKIN_PERIOD(20.0),
	.CLKFX_MULTIPLY(24),
	.CLKFX_DIVIDE(25),
	.IBUFG(1)
) dcm (
	.clk_in(CLK_50MHZ),
	.rst(1'b0),
	.clk_fx(clk48_dcm),
	.clk_fx180(),
	.clk_0(),
	.locked(locked_dcm)
);

wire [5:0] pll_clk;
wire locked;
kg_pll #(
	.CLKIN_PERIOD(20.833),
	.DIVCLK_DIVIDE(2),
	.CLKFBOUT_MULT(41),      // VCO 984 MHz
	.CLKOUT0_DIVIDE(20),     // 49.2 MHz
	.CLKOUT1_DIVIDE(40),     // 24.6 MHz
	.CLKOUT2_DIVIDE(8),      // 123 MHz
	.CLKOUT3_DIVIDE(8),      // 123 MHz, 180
	.CLKOUT3_PHASE(180.0),
	.CLKOUT4_DIVIDE(123),    // 8.0 MHz
	.BUFG_MASK(6'b011111),
	.IBUFG(0)
) pll (
	.clk_in(clk48_dcm),
	.rst(~locked_dcm),
	.clk_out(pll_clk),
	.locked(locked)
);
wire clk_sys = pll_clk[0];
wire clk_pix = pll_clk[1];
wire clk_hdmi = pll_clk[2];
wire clk_hdmi_n = pll_clk[3];
wire clk_8 = pll_clk[4];
wire areset = ~locked;

// the clock of the FT812
ODDR2 oddr_ft_clk (.Q(FT_CLK_OUT), .C0(clk_8), .C1(~clk_8), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));

// ------------------------------------------------------------------ MCU

// MCU_SCK is not on a clock pin on this board (CLOCK_DEDICATED_ROUTE = FALSE in the ucf)
wire mcu_sck = MCU_SCK, mcu_sck_ibufg = MCU_SCK;

wire mcu_int;
assign MCU_IO[1] = mcu_int;
assign MCU_IO[0] = 1'bz;
assign MCU_IO[3:2] = 2'bzz;

localparam SW_N = 7;
wire [1:0] ld_kind;
wire [7:0] ld_slot, ld_data;
wire [31:0] ld_addr;
wire ld_active, ld_wr;
wire [SW_N*8-1:0] sw;
wire dvi_only;
wire ft_cs_n, ft_mosi, ft_spi_on, sd2_cs_n, sd2_mosi;
wire [7:0] ps2_code;
wire ps2_kind, ps2_wr;
wire osd_wr, osd_en, osd_zoom;
wire [11:0] osd_waddr;
wire [7:0] osd_wdata;
wire [23:0] osd_fg, osd_bg;
wire [1:0] osd_alpha, osd_place;
wire [4:0] osd_px, osd_ph;
wire [3:0] osd_py;
wire [5:0] osd_pw;
wire [31:0] port_out_data;
wire [3:0] port_out_wr;
wire uart_tx_wr, uart_rx_ready;
wire [7:0] uart_tx_data;
wire matrix_cmd_wr;
wire [23:0] matrix_cmd;

// the RAM disk file (ocean_rdisk: kg_bk_ram, img slot 0) on the mounter of kg_mcu2
wire [7:0] img_flush, sdc_img_mounted, sdc_rd, sdc_wr, sdc_byte_in_data, sdc_byte_out_data, bk_kind, bk_result;
wire [63:0] sdc_img_size;
wire [31:0] sdc_sector, bk_size;
wire sdc_busy, sdc_done, sdc_error, sdc_byte_in_strobe, bk_mount, bk_flushed;
wire [2:0] sdc_slot;
wire [8:0] sdc_byte_addr;

kg_mcu2 #(
	.CAPS(16'h0002),     // backup RAM: the firmware flushes ramdisk.sav before another core / a reboot
	.SW_N(SW_N),
	.CS_FILTER(3),
	.ENABLE_OSD(1),
	.ENABLE_IMG(1),      // ramdisk.sav of kg_bk_ram
	.IMG_OUT_LATENCY(2), // the sector buffer of kg_bk_ram
	.ENABLE_FT(1),
	.ENABLE_SD2(1),
	.ENABLE_PORTS(4'b0001),  // port 0: the USB serial port (the 8251)
	.ENABLE_AUX(1)           // MATRIX_CMD: the audio peaks
) mcu (
	.CLK(clk_sys),
	.N_RESET(~areset),

	.MCU_SCK(mcu_sck),
	.MCU_MOSI(MCU_MOSI),
	.MCU_MISO(MCU_MISO),
	.MCU_SS(MCU_CS_N),
	.MCU_INT(mcu_int),
	.MCU_SPI_FT_SS(MCU_IO[3]),
	.MCU_SPI_SD2_SS(MCU_IO[2]),

	.SW(sw), .SW_WR(), .SW_INDEX(), .SW_VALUE(), .HW_ID(), .DVI_ONLY(dvi_only), .CORE_BUILD(), .FW_BUILD(),
	.BUSY(), .BTNS(), .RELOAD_REQ(1'b0), .RELOAD_CORE(8'd0),

	.KBD(), .KBD_WR(), .PS2_CODE(ps2_code), .PS2_KIND(ps2_kind), .PS2_WR(ps2_wr),
	.MS_X(), .MS_Y(), .MS_Z(), .MS_B(), .MS_WR(),
	.JOY_L(), .JOY_R(), .JOY_WR(),
	.PS2_CMD(16'h0000), .PS2_CMD_WR(1'b0),

	.LD_KIND(ld_kind), .LD_SLOT(ld_slot), .LD_SIZE(), .LD_START(), .LD_ACTIVE(ld_active), .LD_END(),
	.LD_ADDR(ld_addr), .LD_DATA(ld_data), .LD_WR(ld_wr), .LD_READY(1'b1),

	.OSD_WR(osd_wr), .OSD_WADDR(osd_waddr), .OSD_WDATA(osd_wdata), .OSD_EN(osd_en),
	.OSD_FG(osd_fg), .OSD_BG(osd_bg), .OSD_ALPHA(osd_alpha), .OSD_PX(osd_px), .OSD_PY(osd_py),
	.OSD_PW(osd_pw), .OSD_PH(osd_ph), .OSD_PLACE(osd_place), .OSD_ZOOM(osd_zoom),

	.SDC_IMG_MOUNTED(sdc_img_mounted), .SDC_IMG_SIZE(sdc_img_size),
	.SDC_RD(sdc_rd), .SDC_WR(sdc_wr), .SDC_SECTOR(sdc_sector),
	.SDC_BUSY(sdc_busy), .SDC_DONE(sdc_done), .SDC_ERROR(sdc_error), .SDC_SLOT(sdc_slot),
	.SDC_BYTE_IN_STROBE(sdc_byte_in_strobe), .SDC_BYTE_ADDR(sdc_byte_addr),
	.SDC_BYTE_IN_DATA(sdc_byte_in_data), .SDC_BYTE_OUT_DATA(sdc_byte_out_data),
	.IMG_WP(), .IMG_PHYS_WR(), .IMG_PHYS(), .IMG_FLUSH(img_flush), .FDD_CHNG_WR(), .FDD_CHNG(),
	.FDD_CHNG_REQ(1'b0), .FDD_CHNG_DS(2'd0), .IMG_ACTIVE(),
	.BK_MOUNT(bk_mount), .BK_FLUSHED(bk_flushed), .BK_SLOT(3'd0), .BK_SIZE(bk_size),
	.BK_KIND(bk_kind), .BK_RESULT(bk_result),

	// port 0: the 8251 (bytes of its data register); the machine takes a byte only when its receiver is empty
	.PORT_OUT_DATA(port_out_data), .PORT_OUT_WR(port_out_wr), .PORT_OUT_READY({3'b111, uart_rx_ready}),
	.PORT_IN_DATA({24'd0, uart_tx_data}), .PORT_IN_WR({3'b000, uart_tx_wr}),
	.PORT_CFG(128'd0), .PORT_IN_FULL(), .PORT_STAT(), .PORT_STAT_WR(),
	.RTC_A(8'd0), .RTC_DI(8'd0), .RTC_CS(1'b0), .RTC_WR_N(1'b1), .MATRIX_CMD(matrix_cmd), .MATRIX_CMD_WR(matrix_cmd_wr),
	.DEBUG_ADDR(16'd0), .DEBUG_DATA(16'd0), .RTC_DO(),

	.FT_SPI_ON(ft_spi_on), .FT_VGA_ON(), .FT_RESET(), .FT_SCK(), .FT_MOSI(ft_mosi), .FT_MISO(FT_SPI_MISO),
	.FT_CS_N(ft_cs_n),
	.SD2_SCK(), .SD2_MOSI(sd2_mosi), .SD2_MISO(SD_DO), .SD2_CS_N(sd2_cs_n)
);

assign FT_SPI_CS_N = ft_spi_on ? ft_cs_n : 1'b1;
assign FT_SPI_SCK = ft_spi_on ? mcu_sck_ibufg : 1'b1;
assign FT_SPI_MOSI = ft_spi_on ? ft_mosi : 1'b1;
assign SD_CS_N = sd2_cs_n;
assign SD_DI = sd2_mosi;
assign SD_CLK = mcu_sck_ibufg;

// ------------------------------------------------------------------ soft switches, reset

wire [1:0] sw_model = sw[0*8 +: 2];
wire       sw_mpss = sw[1*8];
wire [1:0] tape_mon = sw[2*8 +: 2];
wire       sw_reset = sw[3*8];
wire       sw_tplay = sw[5*8];
wire       sw_tstop = sw[6*8];

// the ROMs of the core file (LD kind 0)
wire rom_active = ld_active && ld_kind == 2'd0;
wire rom_wr = ld_wr && ld_kind == 2'd0;
wire ld_busy;
wire l_req, l_we, l_ack;
wire [21:0] l_addr;
wire [7:0] l_din;
// the FL item of the tape (slot 6, LD kind 2)
wire tape_file = ld_active && ld_kind == 2'd2 && ld_slot == 8'd6;
wire tape_wr = ld_wr && ld_kind == 2'd2 && ld_slot == 8'd6;
ocean_loader loader (
	.clk(clk_sys), .rom_active(rom_active), .rom_addr(ld_addr[21:0]), .rom_data(ld_data), .rom_wr(rom_wr),
	.file_active(tape_file), .file_slot(ld_slot), .file_addr(ld_addr), .file_data(ld_data), .file_wr(tape_wr), .busy(ld_busy),
	.aux_req(l_req), .aux_we(l_we), .aux_addr(l_addr), .aux_din(l_din), .aux_ack(l_ack)
);

// the tape player (ocean_tape): the .wav of the FL item plays into PB2 at the end of its load / on Tape play
reg [1:0] tp_d = 2'b00;
always @(posedge clk_sys) tp_d <= {sw_tstop, sw_tplay};
wire t_req, t_ack, tape_bit, tape_playing;
wire [21:0] t_addr;
wire [7:0] aux_dout;   // the byte of an aux read (ocean_sram)
ocean_tape #(.CLK_HZ(49200000)) tape (
	.clk(clk_sys), .play(sw_tplay & ~tp_d[0]), .stop(sw_tstop & ~tp_d[1]),
	.file_active(tape_file), .file_addr(ld_addr), .file_data(ld_data), .file_wr(tape_wr),
	.aux_req(t_req), .aux_addr(t_addr), .aux_ack(t_ack), .aux_dout(aux_dout), .bit_out(tape_bit), .playing(tape_playing)
);

// the RAM disk on the card (ocean_rdisk) and the aux port of the SRAM (ocean_aux: loader, word, kg_bk_ram, tape)
wire aux_req, aux_we, aux_ack, rd_hold, ram_wr;
wire [21:0] aux_addr;
wire [7:0] aux_din;
wire [18:0] ram_wr_a;
wire mk_req, mk_ack, bk_req, bk_we, bk_ack;
wire [21:0] mk_addr, bk_addr;
wire [7:0] mk_din, bk_din;
wire [3:0] acks;
ocean_aux arb (.clk(clk_sys), .req({t_req, bk_req, mk_req, l_req}), .we({1'b0, bk_we, 1'b1, l_we}),
	.addr({t_addr, bk_addr, mk_addr, l_addr}), .din({8'd0, bk_din, mk_din, l_din}), .ack(acks),
	.aux_req(aux_req), .aux_we(aux_we), .aux_addr(aux_addr), .aux_din(aux_din), .aux_ack(aux_ack));
assign l_ack = acks[0];
assign mk_ack = acks[1];
assign bk_ack = acks[2];
assign t_ack = acks[3];
ocean_rdisk rdisk (
	.clk(clk_sys), .areset(areset), .model(sw_model), .ld_busy(ld_busy), .hold(rd_hold), .mounted(), .saving(),
	.ram_wr(ram_wr), .ram_wr_a(ram_wr_a),
	.mk_req(mk_req), .mk_addr(mk_addr), .mk_din(mk_din), .mk_ack(mk_ack),
	.bk_req(bk_req), .bk_we(bk_we), .bk_addr(bk_addr), .bk_din(bk_din), .bk_ack(bk_ack), .aux_dout(aux_dout),
	.sdc_img_mounted(sdc_img_mounted), .sdc_img_size(sdc_img_size), .sdc_rd(sdc_rd), .sdc_wr(sdc_wr),
	.sdc_sector(sdc_sector), .sdc_busy(sdc_busy), .sdc_done(sdc_done), .sdc_error(sdc_error), .sdc_slot(sdc_slot),
	.sdc_byte_in_strobe(sdc_byte_in_strobe), .sdc_byte_addr(sdc_byte_addr), .sdc_byte_in_data(sdc_byte_in_data),
	.sdc_byte_out_data(sdc_byte_out_data), .img_flush(img_flush),
	.bk_mount(bk_mount), .bk_flushed(bk_flushed), .bk_size(bk_size), .bk_kind(bk_kind), .bk_result(bk_result)
);

// the keyboard
wire kb_strobe, kb_f12;
wire [7:0] kb_pa;
wire [3:0] kb_pc;
wire [1:0] kb_mods;
ocean_kbd kbd (
	.clk(clk_sys), .reset(areset), .positional(sw_model == 2'd1),
	.ps2_code(ps2_code), .ps2_wr(ps2_wr && !ps2_kind),
	.strobe(kb_strobe), .pa(kb_pa), .pc(kb_pc), .mods(kb_mods), .f12(kb_f12)
);

// a reset of the machine: the PLL, a load, Reset (F12), a change of the model (its ROMs and keyboard)
reg sw_reset_d = 1'b0;
reg [1:0] model_d = 2'd0;
reg [15:0] rst_hold = 16'hFFFF;
always @(posedge clk_sys) begin
	sw_reset_d <= sw_reset;
	model_d <= sw_model;
	if (areset | ld_busy | rd_hold | (sw_reset & ~sw_reset_d) | kb_f12 | (sw_model != model_d)) rst_hold <= 16'hFFFF;
	else if (rst_hold != 16'd0) rst_hold <= rst_hold - 1'd1;
end
wire mach_reset = (rst_hold != 16'd0);

// the bytes of port 0 into the 8251
reg uart_rx_wr = 1'b0;
reg [7:0] uart_rx_data = 8'd0;
always @(posedge clk_sys) begin
	uart_rx_wr <= port_out_wr[0];
	if (port_out_wr[0]) uart_rx_data <= port_out_data[7:0];
end

// ------------------------------------------------------------------ the machine

reg tape_pin = 1'b0;   // TAPE_IN through a register
always @(posedge clk_sys) tape_pin <= TAPE_IN;
wire tape_in_r = tape_playing ? tape_bit : tape_pin;   // the .wav while it plays, else the line in

wire [9:0] hc;
wire [8:0] vc;
wire [2:0] rgb;
wire ce_pix, bell, tape_out;

ocean_system sys (
	.clk(clk_sys), .reset(mach_reset),
	.aux_req(aux_req), .aux_we(aux_we), .aux_addr(aux_addr), .aux_din(aux_din), .aux_ack(aux_ack), .aux_dout(aux_dout),
	.model(sw_model),
	.kb_strobe(kb_strobe), .kb_pa(kb_pa), .kb_pc(kb_pc), .kb_mods(kb_mods),
	.rxd(1'b1), .txd(),
	.uart_tx_wr(uart_tx_wr), .uart_tx_data(uart_tx_data), .uart_rx_wr(uart_rx_wr), .uart_rx_data(uart_rx_data),
	.uart_rx_ready(uart_rx_ready),
	.tape_out(tape_out), .tape_in(tape_in_r), .tape_dac(), .bell(bell),
	.ce_pix(ce_pix), .rgb(rgb), .blank(), .hsync(), .vsync(), .hc(hc), .vc(vc),
	.running(), .cpu_addr(), .dbg_io_wr(), .dbg_io_rd(), .dbg_dout(), .dbg_din(), .dbg_m1(), .dbg_c1(),
	.ram_wr(ram_wr), .ram_wr_a(ram_wr_a),
	.MA(MA), .MD(MD), .MWR_N(MWR_N)
);
assign TAPE_OUT = tape_out;

// ------------------------------------------------------------------ video

wire [23:0] s2_rgb;
wire s2_hs, s2_vs, s2_de;
ocean_scan2x s2x (
	.clk(clk_sys), .ce_pix(ce_pix), .hc(hc), .vc(vc), .rgb_i(rgb), .colour_mpss(sw_mpss),
	.rgb(s2_rgb), .hs(s2_hs), .vs(s2_vs), .de(s2_de)
);

// into clk_pix (of the same PLL; the outputs of s2x change every second clock of clk_sys)
reg [23:0] v_rgb = 24'd0;
reg v_hs = 1'b1, v_vs = 1'b1, v_de = 1'b0;
always @(posedge clk_pix) begin
	v_rgb <= s2_rgb;
	v_hs <= s2_hs;
	v_vs <= s2_vs;
	v_de <= s2_de;
end

// the bitmap OSD of link v2: written on clk_sys, shown on clk_pix, centred in de
wire [23:0] osd_rgb;
wire osd_hs, osd_vs, osd_de;
kg_l2_osd_overlay osd (
	.wclk(clk_sys),
	.osd_wr(osd_wr), .osd_waddr(osd_waddr), .osd_wdata(osd_wdata), .osd_en(osd_en),
	.osd_fg(osd_fg), .osd_bg(osd_bg), .osd_alpha(osd_alpha), .osd_px(osd_px), .osd_py(osd_py),
	.osd_pw(osd_pw), .osd_ph(osd_ph), .osd_place(osd_place), .osd_zoom(osd_zoom),
	.icon_on(8'd0), .icon_act(8'd0),
	.clk(clk_pix),
	.rgb_i(v_rgb), .hs_i(v_hs), .vs_i(v_vs), .de_i(v_de),
	.rgb_o(osd_rgb), .hs_o(osd_hs), .vs_o(osd_vs), .de_o(osd_de)
);

// ------------------------------------------------------------------ audio

// the Bell (E2 C3) of the machine: unipolar, the level of a beep (silence = 0)
reg [15:0] snd = 16'd0;
always @(posedge clk_sys) snd <= bell ? 16'd8192 : 16'd0;

// the tape monitor (modules kg_tape_monitor, as core-tsconf / core-sprinter): TAPE_IN and TAPE_OUT heard in the mix
wire signed [15:0] tape_mon_sample;
kg_tape_monitor #(.CLK_HZ(49200000), .HOLD_US(37000), .LEVEL_IN(4096), .LEVEL_OUT(2048)) tape_monitor (
	.clk(clk_sys), .mode(tape_mon), .tape_in(tape_in_r), .tape_out(tape_out), .in_on(), .out_on(),
	.sample(tape_mon_sample));

// the ADC (PCM1808: the line in and the MIDI synth SAM2695 of the board; as core-sprinter): i2s_transceiver is the
// master, SCKI = ADC_CLK = clk_sys 49.2 MHz, BCK = clk_sys / 8, LRCK = BCK / 64 (96 kHz, SCKI = 512 fs), 24 bits;
// half of the scale into the mix
wire [23:0] adc_l, adc_r;
i2s_transceiver #(.mclk_sclk_ratio(8), .sclk_ws_ratio(64), .d_width(24)) adc (
	.reset_n(~areset),
	.mclk(clk_sys),
	.sclk(ADC_BCK),
	.ws(ADC_LRCK),
	.sd_tx(),
	.sd_rx(ADC_DOUT),
	.l_data_tx(24'b0),
	.r_data_tx(24'b0),
	.l_data_rx(adc_l),
	.r_data_rx(adc_r)
);
ODDR2 oddr_adc (.Q(ADC_CLK), .C0(clk_sys), .C1(~clk_sys), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));
reg [15:0] adc_mix_l = 16'd0, adc_mix_r = 16'd0;
always @(posedge clk_sys) begin
	adc_mix_l <= {adc_l[23], adc_l[23:9]};
	adc_mix_r <= {adc_r[23], adc_r[23:9]};
end

// the final mix, saturated to 16 bits
function [15:0] sat16(input [17:0] v);
	sat16 = (v[17:15] == 3'b000 || v[17:15] == 3'b111) ? v[15:0] : v[17] ? 16'h8000 : 16'h7FFF;
endfunction
function [17:0] sx18(input [15:0] v);
	sx18 = {{2{v[15]}}, v};
endfunction
wire [17:0] mix_l = sx18(snd) + sx18(tape_mon_sample) + sx18(adc_mix_l);
wire [17:0] mix_r = sx18(snd) + sx18(tape_mon_sample) + sx18(adc_mix_r);
reg [15:0] audio_l = 16'd0, audio_r = 16'd0;
always @(posedge clk_sys) begin
	audio_l <= sat16(mix_l);
	audio_r <= sat16(mix_r);
end

// the level meters of the mcu: the peaks of the final mix (CMD_AUDIO_PEAKS_L / _R)
audio_peaks #(.PERIOD_BITS(20)) peaks (.clk(clk_sys), .audio_l(audio_l), .audio_r(audio_r), .cmd_wr(matrix_cmd_wr), .cmd(matrix_cmd));

// no I2S DAC on this board: sigma-delta outputs into an RC filter (offset binary)
kg_sigma_delta_dac dac_l (.clk(clk_sys), .reset(areset), .din(audio_l ^ 16'h8000), .dout(AUDIO_L));
kg_sigma_delta_dac dac_r (.clk(clk_sys), .reset(areset), .din(audio_r ^ 16'h8000), .dout(AUDIO_R));

// the HDMI audio: a sample every 1025 clocks of clk_sys (48 kHz), taken on clk_pix at the change of the synchronised
// toggle; the sample clock of hdmi_tx: every 512 clocks of clk_pix (48.05 kHz)
reg [15:0] smp_l = 16'd0, smp_r = 16'd0;
reg smp_tog = 1'b0;
reg [10:0] smp_cnt = 11'd0;
always @(posedge clk_sys) begin
	if (smp_cnt == 11'd1024) begin
		smp_cnt <= 11'd0;
		smp_l <= audio_l;
		smp_r <= audio_r;
		smp_tog <= ~smp_tog;
	end else
		smp_cnt <= smp_cnt + 1'd1;
end
wire smp_tog_pix;
kg_sync smp_sync (.clk(clk_pix), .d(smp_tog), .q(smp_tog_pix));
reg smp_tog_pix_d = 1'b0;
reg [23:0] hdmi_l = 24'd0, hdmi_r = 24'd0;
always @(posedge clk_pix) begin
	smp_tog_pix_d <= smp_tog_pix;
	if (smp_tog_pix != smp_tog_pix_d) begin
		hdmi_l <= { smp_l, 8'd0 };
		hdmi_r <= { smp_r, 8'd0 };
	end
end

reg [8:0] aud_cnt = 9'd0;
reg aud_stb = 1'b0;
always @(posedge clk_pix) begin
	aud_stb <= (aud_cnt == 9'd511);
	aud_cnt <= aud_cnt + 1'd1;
end
wire dvi_only_pix;
kg_sync dvi_sync (.clk(clk_pix), .d(dvi_only), .q(dvi_only_pix));

hdmi_tx #(.SAMPLE_FREQ(48000)) hdmi (
	.clk(clk_pix),
	.sclk(clk_hdmi),
	.sclk_n(clk_hdmi_n),
	.reset(areset),
	.rgb(osd_rgb),
	.vsync(osd_vs),
	.hsync(osd_hs),
	.de(osd_de),
	.audio_en(~dvi_only_pix),
	.audio_l(hdmi_l),
	.audio_r(hdmi_r),
	.audio_clk(aud_stb),
	.tx_clk_n(TMDS_N[3]),
	.tx_clk_p(TMDS_P[3]),
	.tx_d_n(TMDS_N[2:0]),
	.tx_d_p(TMDS_P[2:0])
);

endmodule
