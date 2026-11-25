// Testbench of the schematic model (the generated schem.v): crystal, reset button, RS-232 terminal on the 8251,
// timing report of the clocks and the raster, frames as PPM of the digital video signals.
//   plusargs: +ms=N (run time, default 25), +frames=PREFIX (write PREFIX_N.ppm), +key=XX (send byte XX to RXD at +keyms=N)
`timescale 1ns/100ps

// КР580ВМ80А adapter: vm80a (Vslav, CC-BY 3.0) with the package pin numbers
module cpu8080(input clk, input p12, p13, p14, p15, p22, p23,
	output p1, p25, p26, p27, p29, p30, p31, p32, p33, p34, p35, p36, p37, p38, p39, p40,
	inout p3, p4, p5, p6, p7, p8, p9, p10,
	output p16, p17, p18, p19, p21, p24);
	wire [15:0] a;
	assign {p36, p39, p38, p37, p40, p1, p35, p34, p33, p32, p31, p30, p29, p27, p26, p25} = a;
	vm80a cpu(.pin_clk(clk), .pin_f1(p22), .pin_f2(p15), .pin_reset(p12), .pin_a(a),
		.pin_d({p6, p5, p4, p3, p7, p8, p9, p10}), .pin_hold(p13), .pin_hlda(p21), .pin_ready(p23), .pin_wait(p24),
		.pin_int(p14), .pin_inte(p16), .pin_sync(p19), .pin_dbin(p17), .pin_wr_n(p18));
endmodule

module tb_schem;
	reg osc = 0, clk_cpu = 0, rst_btn = 0, rxd = 1;
	always #(1000.0 / 12.288 / 2) osc = ~osc;
	always #10 clk_cpu = ~clk_cpu; // 50 MHz: vm80a samples F1 / F2 (81 ns pulses) 4 times
	schem #(.ROM0("build/rom0.hex"), .ROM1("build/rom1.hex"), .PROM_VC("build/prom_vc.hex")) dut(
		.osc(osc), .clk_cpu(clk_cpu), .rst_btn(rst_btn), .rxd(rxd));

	integer ms = 25;
	initial begin
		if (!$value$plusargs("ms=%d", ms)) ms = 25;
		#(2000) rst_btn = 1; // the RC of the button: about 2 us low here
		#(ms * 1000000.0);
		report();
		$finish;
	end

	// ---- clock / raster timing ----
	realtime t_f1 = 0, p_f1 = 0, t_hs = 0, p_hs = 0, w_hs = 0, t_vs = 0, p_vs = 0, w_vs = 0, t_gc = 0, w_gc = 0, t_gk = 0, w_gk = 0;
	realtime t_vsr = 0, t_hsr = 0, t_gcr = 0, t_gkr = 0;
	integer hs_in_frame = 0, lines_frame = 0, n_vs = 0;
	always @(posedge dut.pr_F1) begin p_f1 = $realtime - t_f1; t_f1 = $realtime; end
	// sync polarity is found from the duty: the short phase is the pulse
	always @(posedge dut.pr_HS) begin p_hs = $realtime - t_hsr; t_hsr = $realtime; hs_in_frame = hs_in_frame + 1; end
	always @(negedge dut.pr_HS) w_hs = $realtime - t_hsr;
	always @(posedge dut.pr_VS) begin p_vs = $realtime - t_vsr; t_vsr = $realtime; lines_frame = hs_in_frame; hs_in_frame = 0; n_vs = n_vs + 1; end
	always @(negedge dut.pr_VS) w_vs = $realtime - t_vsr;
	always @(posedge dut.pr_GC) t_gcr = $realtime;
	always @(negedge dut.pr_GC) w_gc = $realtime - t_gcr;
	always @(posedge dut.pr_GK) t_gkr = $realtime;
	always @(negedge dut.pr_GK) w_gk = $realtime - t_gkr;
	task report; begin
		$display("F1 period %0.1f ns (%0.4f MHz)", p_f1, 1000.0 / p_f1);
		$display("HS period %0.3f us, high %0.3f us", p_hs / 1000.0, w_hs / 1000.0);
		$display("VS period %0.3f ms (%0.3f Hz), high %0.3f us, HS per frame %0d, frames %0d", p_vs / 1e6, 1e9 / p_vs, w_vs / 1000.0, lines_frame, n_vs);
		$display("GC high %0.3f us, GK high %0.3f us", w_gc / 1000.0, w_gk / 1000.0);
		$display("PC at end %h, PB of DD17 %b", dut.pr_A, dut.pr_PB17);
	end endtask

	// ---- IO trace (+iotrace): every port read / write with both data buses ----
	reg iotrace = 0; integer nio = 0;
	initial iotrace = $test$plusargs("iotrace");
	always @(posedge dut.pr_IOR) if (iotrace && nio < 400) begin nio = nio + 1; $display("%0t IN  %h -> BD %h D %h", $time, dut.pr_A[7:0], dut.pr_BD, dut.pr_D); end
	always @(posedge dut.pr_IOW) if (iotrace && nio < 400) begin nio = nio + 1; $display("%0t OUT %h <- BD %h D %h", $time, dut.pr_A[7:0], dut.pr_BD, dut.pr_D); end

	// ---- terminal: 8251 TXD at 4800 baud ----
	localparam real BIT = 1e9 / 4800.0;
	reg [7:0] ch; integer i;
	initial begin
		forever begin
			@(negedge dut.pr_TXD);
			if ($realtime > 10000) begin
				#(BIT * 1.5);
				for (i = 0; i < 8; i = i + 1) begin ch[i] = dut.pr_TXD; #(BIT); end
				if (ch == 8'h0D) $write("\n"); else if (ch >= 8'h20 && ch < 8'h7F) $write("%c", ch); else if (ch != 8'h0A) $write("<%h>", ch);
				$fflush;
			end
		end
	end
	// ---- terminal: one byte to RXD ----
	integer key = -1, keyms = 0, k;
	initial begin
		if ($value$plusargs("key=%h", key)) begin
			if (!$value$plusargs("keyms=%d", keyms)) keyms = 10;
			#(keyms * 1000000.0);
			rxd = 0; #(BIT);
			for (k = 0; k < 8; k = k + 1) begin rxd = key[k]; #(BIT); end
			rxd = 1; #(BIT * 2);
			$display("\n[tb] sent %h at %0d ms", key[7:0], keyms);
		end
	end

	// ---- frames: one PPM per VS, 12 MHz samples of the whole raster (768 x lines) ----
	reg [8*64-1:0] prefix; integer fd = 0, nfr = 0, x = 0, y = 0;
	reg want = 0;
	initial want = $value$plusargs("frames=%s", prefix);
	// X1: RED = PROM D3 | FL1 & BLANC, GREEN = D1 | FL3 & BLANC, BLUE = D2 | FL2 & BLANC (emitter followers, VD1-VD3 OR the background in)
	wire vr = dut.pr_P3 | (dut.pr_FL1 & dut.pr_BLANC);
	wire vg = dut.pr_P1 | (dut.pr_FL3 & dut.pr_BLANC);
	wire vb = dut.pr_P2 | (dut.pr_FL2 & dut.pr_BLANC);
	always @(posedge dut.pr_VS) if (want) begin
		if (fd) $fclose(fd);
		fd = $fopen($sformatf("%0s_%0d.ppm", prefix, nfr), "wb");
		$fwrite(fd, "P6\n768 320\n255\n");
		nfr = nfr + 1; y = 0;
	end
	always @(posedge dut.pr_HS) begin x = 0; y = y + 1; end
	always @(posedge dut.pr_M12) if (want && fd && x < 768 && y < 320) begin
		$fwrite(fd, "%c%c%c", vr ? 8'd255 : (dut.pr_GC | dut.pr_GK) ? 8'd40 : 8'd0,
			vg ? 8'd255 : (dut.pr_GC | dut.pr_GK) ? 8'd40 : 8'd0, vb ? 8'd255 : 8'd0);
		x = x + 1;
	end
endmodule
