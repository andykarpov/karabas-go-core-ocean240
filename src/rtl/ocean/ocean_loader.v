`timescale 1ns / 1ps
`default_nettype wire

/*
 ocean_loader.v — the ROMs of the core file (the ROM loader of kg_mcu2, LD kind 0) into the SRAM through the aux
 port of ocean_sram: a byte at rom_addr (the "address" of core.json: 080000 + 2000 * image, ocean_system).
 busy while a load runs or a byte waits: the machine is held in reset meanwhile.
 The mcu writes a byte in ten clocks or less often; a write here takes four to six.
*/

module ocean_loader (
	input  wire        clk,
	input  wire        rom_active,
	input  wire [21:0] rom_addr,
	input  wire  [7:0] rom_data,
	input  wire        rom_wr,
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
	if (aux_ack) aux_req <= 1'b0;
	else if (!aux_req && pend && !rom_wr) begin
		aux_req <= 1'b1;
		aux_addr <= pend_addr;
		aux_din <= pend_data;
		pend <= 1'b0;
	end
end
assign busy = rom_active | pend | aux_req;

endmodule
