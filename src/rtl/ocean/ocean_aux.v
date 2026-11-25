`timescale 1ns / 1ps
`default_nettype wire

/*
 ocean_aux.v — the aux port of ocean_sram shared by up to four masters (0 first): a master holds req with its address /
 data until its ack (one clock; dout valid with it), as ocean_sram wants. The grant is taken when no master owns the
 port and is kept until the ack, so an address never changes under a request in flight.
*/

module ocean_aux (
	input  wire        clk,
	input  wire  [3:0] req,
	input  wire  [3:0] we,
	input  wire [87:0] addr,           // 4 x 22
	input  wire [31:0] din,            // 4 x 8
	output wire  [3:0] ack,

	output wire        aux_req,
	output wire        aux_we,
	output wire [21:0] aux_addr,
	output wire  [7:0] aux_din,
	input  wire        aux_ack
);

reg       busy = 1'b0;
reg [1:0] g = 2'd0;
wire [1:0] pick = req[0] ? 2'd0 : req[1] ? 2'd1 : req[2] ? 2'd2 : 2'd3;
wire [1:0] cur = busy ? g : pick;

always @(posedge clk) begin
	if (!busy) begin
		if (req != 4'd0) begin busy <= 1'b1; g <= pick; end
	end else if (aux_ack) busy <= 1'b0;
end

assign aux_req = busy & req[g];
assign aux_we = we[cur];
assign aux_addr = addr[cur * 22 +: 22];
assign aux_din = din[cur * 8 +: 8];
assign ack = busy ? ({3'b000, aux_ack} << g) : 4'b0000;

endmodule
