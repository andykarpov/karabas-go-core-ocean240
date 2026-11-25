`timescale 1ns / 1ps
`default_nettype wire

/*
 ocean_loader.v — the loads of the firmware into the SRAM through the aux port (ocean_aux):
 - the ROMs of the core file (LD kind 0): a byte at rom_addr (the "address" of core.json: 080000 + 2000 * image,
   ocean_system); busy while it runs or a byte waits: the machine is held in reset meanwhile;
 - the tape (an FL item of slot 6, LD kind 2): the .wav at 200000 + its offset (up to 2 MB); the machine runs.
 The mcu writes a byte in ten clocks or less often; a write here takes four to six.
*/

module ocean_loader (
	input  wire        clk,
	input  wire        rom_active,
	input  wire [21:0] rom_addr,
	input  wire  [7:0] rom_data,
	input  wire        rom_wr,
	input  wire        file_active,
	input  wire  [7:0] file_slot,
	input  wire [31:0] file_addr,
	input  wire  [7:0] file_data,
	input  wire        file_wr,
	output wire        busy,

	output reg         aux_req = 1'b0,
	output wire        aux_we,
	output reg  [21:0] aux_addr = 22'd0,
	output reg   [7:0] aux_din = 8'd0,
	input  wire        aux_ack
);

assign aux_we = 1'b1;
reg        pend = 1'b0;
reg [21:0] pend_addr = 22'd0;
reg  [7:0] pend_data = 8'd0;

always @(posedge clk) begin
	if (rom_wr) begin
		pend <= 1'b1;
		pend_addr <= rom_addr;
		pend_data <= rom_data;
	end
	if (file_wr && file_slot == 8'd6 && file_addr < 32'h00200000) begin
		pend <= 1'b1;
		pend_addr <= {1'b1, file_addr[20:0]};   // 200000 + the offset
		pend_data <= file_data;
	end
	if (aux_ack) aux_req <= 1'b0;
	else if (!aux_req && pend && !rom_wr && !file_wr) begin
		aux_req <= 1'b1;
		aux_addr <= pend_addr;
		aux_din <= pend_data;
		pend <= 1'b0;
	end
end
assign busy = rom_active | (pend | aux_req) & ~file_active;

endmodule
