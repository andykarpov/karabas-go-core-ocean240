`timescale 1ns / 1ps
`default_nettype wire

/*
 ocean_kbd.v — a PC keyboard (PS/2 set 2 scancodes of kg_mcu2) as the keyboard controllers of the Ocean.

 Both keyboards of the Ocean have a controller: a key comes as a code on DD78 with a strobe on IR1 (RST_1) that
 stays until the program acks it (ocean_system).
 - positional = 0 (the 240/7 monitor, CP/M REL.5): a 7-bit ASCII code on PA; Shift the second code, Ctrl -> & 1F.
 - positional = 1 (HARDWARE MONITOR+, CP/M REL.7): PA = one bit of the column, PC0-PC3 = the row 0..10 (the matrix of
   MAME okean240a); Ctrl and Shift are levels on PB5 / PB6 while held.
 F12 is the reset of the core (not a key of the machine).
*/

module ocean_kbd (
	input  wire       clk,
	input  wire       reset,
	input  wire       positional,
	input  wire [7:0] ps2_code,
	input  wire       ps2_wr,          // a byte of the keyboard (kind 0)
	output reg        strobe = 1'b0,   // a pulse: a key
	output reg  [7:0] pa = 8'd0,
	output reg  [3:0] pc = 4'd0,
	output wire [1:0] mods,            // {Shift, Ctrl}
	output reg        f12 = 1'b0       // a pulse
);

reg e0 = 1'b0, rel = 1'b0;
reg lshift = 1'b0, rshift = 1'b0, lctrl = 1'b0, rctrl = 1'b0;
wire shift = lshift | rshift;
wire ctrl = lctrl | rctrl;
assign mods = {shift, ctrl};

reg  [8:0] code = 9'd0;
reg        go = 1'b0;
wire       valid, pos;
wire [6:0] ascii, ascii_sh;
wire [3:0] row;
wire [2:0] col;
ocean_kbd_map map (.code(code), .valid(valid), .ascii(ascii), .ascii_sh(ascii_sh), .pos(pos), .row(row), .col(col));

wire [6:0] a = shift ? ascii_sh : ascii;

always @(posedge clk) begin
	strobe <= 1'b0;
	f12 <= 1'b0;
	go <= 1'b0;
	if (reset) begin
		e0 <= 1'b0; rel <= 1'b0; lshift <= 1'b0; rshift <= 1'b0; lctrl <= 1'b0; rctrl <= 1'b0;
	end else begin
		if (ps2_wr) begin
			if (ps2_code == 8'hE0) e0 <= 1'b1;
			else if (ps2_code == 8'hF0) rel <= 1'b1;
			else begin
				e0 <= 1'b0; rel <= 1'b0;
				case ({e0, ps2_code})
					9'h012: lshift <= ~rel;
					9'h059: rshift <= ~rel;
					9'h014: lctrl <= ~rel;
					9'h114: rctrl <= ~rel;
					9'h007: if (!rel) f12 <= 1'b1;
					default: if (!rel) begin code <= {e0, ps2_code}; go <= 1'b1; end
				endcase
			end
		end
		// the map answers a clock after the code
		if (go && valid) begin
			if (positional) begin
				if (pos) begin pa <= 8'd1 << col; pc <= row; strobe <= 1'b1; end
			end else begin
				pa <= {1'b0, ctrl ? {2'b00, a[4:0]} : a};
				strobe <= 1'b1;
			end
		end
	end
end

endmodule
