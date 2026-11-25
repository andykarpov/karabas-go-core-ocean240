`timescale 1ns / 1ps
`default_nettype wire

/*
 ocean_vv51.v — the KR580VV51 (8251) of the Ocean in the asynchronous mode (all the monitors and CP/M use).

 Mode word after a reset or an internal reset (command bit 6): baud factor (1 / 16 / 64), 5-8 bits, parity
 (accepted, not sent / checked), stop bits. Command: TxEN (0), DTR (1), RxE (2), error reset (4), RTS (5),
 internal reset (6). Status: TxRDY (0), RxRDY (1), TxEMPTY (2), DSR (7) = 1.
 The bit clocks ~TxC / ~RxC (counter 1 of the 8253) come as levels: the falling edges are counted in clk.
*/

module ocean_vv51 (
	input  wire       clk,
	input  wire       reset,
	input  wire       cs,          // the port group A0
	input  wire       cd,          // A0: 1 control / status, 0 data
	input  wire       wr,          // the ~IOW level of the CPU cycle
	input  wire       rd,          // the ~IOR level
	input  wire [7:0] din,
	output reg  [7:0] dout,
	input  wire       txc,
	input  wire       rxc,
	output reg        txd = 1'b1,
	input  wire       rxd,
	output wire       rxrdy,
	// the bytes of the data register for a byte port (the USB-UART of the mcu): a byte that goes into the
	// transmitter, a byte that comes into the receiver buffer as if received
	output reg        tx_wr = 1'b0,
	output reg  [7:0] tx_data = 8'd0,
	input  wire       rx_wr,
	input  wire [7:0] rx_data,
	output wire       rx_ready
);

reg [7:0] mode = 8'd0, cmd = 8'd0;
reg       mode_next = 1'b1;
reg       wr_d = 1'b0, rd_d = 1'b0;
reg [7:0] txbuf = 8'd0;
reg       txfull = 1'b0;
reg [7:0] rxbuf = 8'd0;
reg       rxfull = 1'b0;

wire [6:0] div = (mode[1:0] == 2'd2) ? 7'd16 : (mode[1:0] == 2'd3) ? 7'd64 : 7'd1;
wire [3:0] nbits = 4'd5 + mode[3:2];

reg txc_d = 1'b1, rxc_d = 1'b1;
wire txc_fall = txc_d & ~txc;
wire rxc_rise = ~rxc_d & rxc;

// transmitter
reg [9:0] tsh = 10'h3FF;
reg [3:0] tbits = 4'd0;
reg [6:0] tcnt = 7'd0;
reg       tbusy = 1'b0;
// receiver
reg [6:0] rcnt = 7'd0;
reg [3:0] rbits = 4'd0;
reg       rbusy = 1'b0;
reg       rstop = 1'b0;   // after the data bits: wait for the stop bit (the line high) before a new start bit
reg [7:0] rsh = 8'd0;
reg [1:0] rxd_s = 2'b11;

always @(posedge clk) begin
	wr_d <= wr & cs;
	rd_d <= rd & cs;
	txc_d <= txc;
	rxc_d <= rxc;
	rxd_s <= {rxd_s[0], rxd};
	tx_wr <= 1'b0;
	if (rx_wr & cmd[2]) begin rxbuf <= rx_data; rxfull <= 1'b1; end
	if (reset) begin
		mode_next <= 1'b1; cmd <= 8'd0; txfull <= 1'b0; rxfull <= 1'b0; tbusy <= 1'b0; rbusy <= 1'b0; rstop <= 1'b0; txd <= 1'b1;
	end else begin
		// a write at the end of ~IOW
		if (wr_d & ~(wr & cs)) begin
			if (cd) begin
				if (mode_next) begin mode <= din; mode_next <= 1'b0; end
				else begin
					cmd <= din;
					if (din[6]) begin mode_next <= 1'b1; cmd <= 8'd0; end
				end
			end else begin
				txbuf <= din; txfull <= 1'b1;
			end
		end
		// a read of the data clears RxRDY
		if (rd_d & ~(rd & cs) & ~cd) rxfull <= 1'b0;

		// transmitter: start bit, data LSB first, stop bit(s)
		if (txc_fall) begin
			if (!tbusy) begin
				if (txfull & cmd[0]) begin
					txfull <= 1'b0;
					tx_wr <= 1'b1;
					tx_data <= txbuf;
					tsh <= {2'b11, txbuf} | (10'h3FF << nbits);   // the data, then stop bits (1)
					tbusy <= 1'b1;
					tbits <= nbits + 4'd1;
					tcnt <= 7'd0;
					txd <= 1'b0;
				end
			end else begin
				if (tcnt == div - 1'd1) begin
					tcnt <= 7'd0;
					txd <= tsh[0];
					tsh <= {1'b1, tsh[9:1]};
					if (tbits == 4'd0) tbusy <= 1'b0;
					tbits <= tbits - 1'd1;
				end else tcnt <= tcnt + 1'd1;
			end
		end

		// receiver: the middle of each bit
		if (rxc_rise & cmd[2]) begin
			if (rstop) begin
				if (rxd_s[1]) rstop <= 1'b0;
			end else if (!rbusy) begin
				if (!rxd_s[1]) begin rbusy <= 1'b1; rcnt <= 7'd0; rbits <= 4'd0; end
			end else begin
				rcnt <= rcnt + 1'd1;
				if (rcnt == (div >> 1) + div - 1'd1 || (rbits != 4'd0 && rcnt == div - 1'd1)) begin
					rcnt <= 7'd0;
					rsh <= {rxd_s[1], rsh[7:1]};
					rbits <= rbits + 1'd1;
					if (rbits == nbits - 1'd1) begin
						rbusy <= 1'b0;
						rstop <= 1'b1;
						rxbuf <= {rxd_s[1], rsh[7:1]} >> (4'd8 - nbits);
						rxfull <= 1'b1;
					end
				end
			end
		end
	end
end

wire txe = ~txfull & ~tbusy;
assign rxrdy = rxfull & cmd[2];
assign rx_ready = ~rxfull;
always @(*) dout = cd ? {1'b1, 4'd0, txe, rxrdy, ~txfull} : rxbuf;

endmodule
