// Unit test of ocean_rdisk (Icarus): kg_bk_ram with a model of the mounter of kg_mcu2 (kg_l2_img behaviour: a read
// streams 512 bytes with sdc_byte_in_strobe, a write takes sdc_byte_out_data two clocks after sdc_byte_addr) and of
// the aux port of the SRAM. CLK_HZ is small so that the timeouts of kg_bk_ram are short.
//  1. the file (a RAM disk with one directory entry) is read into 010000, the BDOS word BC06 goes to 0006, hold ends;
//  2. a CPU write into page 1 is saved: a write request of its sector with the new byte;
//  3. the model 240.2 -> Turbo: the word becomes BA06;
//  4. the model Test: kg_bk_ram off, a write into page 1 is not saved.
`timescale 1ns/1ps
module tb_rdisk;
	reg clk = 0; always #10 clk = ~clk;
	reg areset = 1, ld_busy = 1;
	reg [1:0] model = 0;
	reg ram_wr = 0; reg [18:0] ram_wr_a = 0;
	wire hold, mounted;
	wire aux_req, aux_we; wire [21:0] aux_addr; wire [7:0] aux_din;
	reg aux_ack = 0; reg [7:0] aux_dout = 0;
	wire [7:0] sdc_rd, sdc_wr, sdc_byte_out_data, bk_kind, bk_result;
	wire [31:0] sdc_sector, bk_size;
	wire bk_mount, bk_flushed;
	reg [7:0] sdc_img_mounted = 0; reg [63:0] sdc_img_size = 0;
	reg sdc_busy = 0, sdc_done = 0, sdc_strobe = 0; reg [8:0] sdc_addr = 0; reg [7:0] sdc_data = 0;

	wire mk_req, mk_ack, bk_req, bk_we, bk_ack;
	wire [21:0] mk_addr, bk_addr;
	wire [7:0] mk_din, bk_din;
	ocean_rdisk #(.CLK_HZ(20000)) dut (
		.clk(clk), .areset(areset), .model(model), .ld_busy(ld_busy), .hold(hold), .mounted(mounted), .saving(),
		.ram_wr(ram_wr), .ram_wr_a(ram_wr_a),
		.mk_req(mk_req), .mk_addr(mk_addr), .mk_din(mk_din), .mk_ack(mk_ack),
		.bk_req(bk_req), .bk_we(bk_we), .bk_addr(bk_addr), .bk_din(bk_din), .bk_ack(bk_ack), .aux_dout(aux_dout),
		.sdc_img_mounted(sdc_img_mounted), .sdc_img_size(sdc_img_size), .sdc_rd(sdc_rd), .sdc_wr(sdc_wr),
		.sdc_sector(sdc_sector), .sdc_busy(sdc_busy), .sdc_done(sdc_done), .sdc_error(1'b0), .sdc_slot(3'd0),
		.sdc_byte_in_strobe(sdc_strobe), .sdc_byte_addr(sdc_addr), .sdc_byte_in_data(sdc_data),
		.sdc_byte_out_data(sdc_byte_out_data), .img_flush(8'd0),
		.bk_mount(bk_mount), .bk_flushed(bk_flushed), .bk_size(bk_size), .bk_kind(bk_kind), .bk_result(bk_result));
	wire [3:0] acks;
	ocean_aux #(.N(4)) arb (.clk(clk), .req({1'b0, bk_req, mk_req, 1'b0}), .we({1'b0, bk_we, 1'b1, 1'b0}),
		.addr({22'd0, bk_addr, mk_addr, 22'd0}), .din({8'd0, bk_din, mk_din, 8'd0}), .ack(acks),
		.aux_req(aux_req), .aux_we(aux_we), .aux_addr(aux_addr), .aux_din(aux_din), .aux_ack(aux_ack));
	assign mk_ack = acks[1];
	assign bk_ack = acks[2];

	// the SRAM (128 KB is enough) on the aux port: ack two clocks after a request
	reg [7:0] mem [0:131071];
	reg [7:0] img [0:65535];      // the file
	integer i, writes = 0, errors = 0;
	initial begin
		for (i = 0; i < 131072; i = i + 1) mem[i] = 8'h00;
		mem[4] = 8'h5A;               // whatever another core left there
		for (i = 0; i < 65536; i = i + 1) img[i] = 8'hE5;
		img[0] = 8'h00; img[1] = "H"; img[2] = "E"; img[3] = "L"; img[4] = "L"; img[5] = "O";
	end
	reg [1:0] ad = 0;
	always @(posedge clk) begin
		aux_ack <= 0;
		if (aux_req && !aux_ack) begin
			ad <= ad + 1;
			if (ad == 2'd2) begin
				ad <= 0; aux_ack <= 1;
				if (aux_we) mem[aux_addr[16:0]] <= aux_din; else aux_dout <= mem[aux_addr[16:0]];
			end
		end
	end

	// the mounter: CMD_BK_MOUNT -> mount the file of 64 KB; read / write requests of slot 0
	integer pos; reg wr_kind; reg [31:0] lba;
	always @(posedge clk) begin
		sdc_img_mounted <= 0;
		if (bk_mount) begin
			$display("%0t bk_mount size %0d kind %0d", $time, bk_size, bk_kind);
			repeat (5) @(posedge clk);
			sdc_img_size <= 64'd65536; sdc_img_mounted <= 8'd1;
		end
	end
	initial begin
		forever begin
			@(posedge clk);
			if (!sdc_busy && (sdc_rd[0] || sdc_wr[0])) begin
				wr_kind = sdc_wr[0]; lba = sdc_sector;
				sdc_busy <= 1;
				repeat (3) @(posedge clk);
				for (pos = 0; pos < 512; pos = pos + 1) begin
					if (wr_kind) begin
						sdc_addr <= pos; repeat (3) @(posedge clk);
						img[lba * 512 + pos] = sdc_byte_out_data;
					end else begin
						sdc_addr <= pos; sdc_data <= img[lba * 512 + pos]; sdc_strobe <= 1;
						@(posedge clk); sdc_strobe <= 0;
					end
				end
				if (wr_kind) begin writes = writes + 1; $display("%0t write of sector %0d", $time, lba); end
				sdc_busy <= 0; sdc_done <= 1; @(posedge clk); sdc_done <= 0;
			end
		end
	end

	task check(input [16:0] a, input [7:0] v, input [8*24-1:0] what);
		if (mem[a] !== v) begin $display("FAIL: %0s: mem[%h] = %h, not %h", what, a, mem[a], v); errors = errors + 1; end
	endtask
	task cpu_write(input [18:0] a, input [7:0] v);
		begin @(posedge clk); mem[a[16:0]] = v; ram_wr_a <= a; ram_wr <= 1; @(posedge clk); ram_wr <= 0; end
	endtask

	initial begin
		repeat (10) @(posedge clk); areset <= 0;
		repeat (10) @(posedge clk); ld_busy <= 0;      // the ROMs of the core file are in
		// hold is sampled by the clock in the top: wait for it low at a clock edge (busy of kg_bk_ram is
		// combinational on its state, Icarus shows a zero-time dip when the state changes)
		wait (hold);
		@(posedge clk); while (hold) @(posedge clk);
		$display("%0t hold ended, mounted %b", $time, mounted);
		check(17'h10000, 8'h00, "file byte 0"); check(17'h10001, "H", "file byte 1"); check(17'h1FFFF, 8'hE5, "file end");
		check(17'h00004, 8'h00, "drive byte");
		check(17'h00006, 8'h06, "BDOS low"); check(17'h00007, 8'hBC, "BDOS 240.2");
		// 2. a CPU write into page 1, then idle: saved
		cpu_write(19'h10020, 8'h41);
		repeat (60000) @(posedge clk);
		if (img[32] !== 8'h41) begin $display("FAIL: the write was not saved (img[32] = %h)", img[32]); errors = errors + 1; end
		// 3. Turbo: its BDOS
		model <= 2'd1; repeat (200) @(posedge clk);
		check(17'h00007, 8'hBA, "BDOS Turbo");
		// 4. Test: no saving
		model <= 2'd2; repeat (200) @(posedge clk);
		i = writes;
		cpu_write(19'h10040, 8'h55);
		repeat (60000) @(posedge clk);
		if (writes != i || img[64] === 8'h55) begin $display("FAIL: a write of the test model was saved"); errors = errors + 1; end
		if (errors) $display("rdisk FAILED"); else $display("rdisk ok");
		$finish;
	end
	initial begin #200000000; $display("FAIL: timeout"); $finish; end
endmodule
