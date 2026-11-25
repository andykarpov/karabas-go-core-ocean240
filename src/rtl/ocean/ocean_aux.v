`timescale 1ns / 1ps
`default_nettype wire

/*
 ocean_aux.v — the aux port of ocean_sram shared by N masters (0 first): a master holds req with its address /
 data until its ack (one clock; dout valid with it), as ocean_sram wants. The grant is taken when no master owns the
 port and is kept until the ack, so an address never changes under a request in flight.
 The top: 0 the loader, 1 the BDOS word, 2 kg_bk_ram, 3 the tape, 4 / 5 the floppy caches (ocean_fdd).
*/

module ocean_aux #(
	parameter N = 6
) (
	input  wire          clk,
	input  wire  [N-1:0] req,
	input  wire  [N-1:0] we,
	input  wire [N*22-1:0] addr,
	input  wire  [N*8-1:0] din,
	output wire  [N-1:0] ack,

	output wire          aux_req,
	output wire          aux_we,
	output wire   [21:0] aux_addr,
	output wire    [7:0] aux_din,
	input  wire          aux_ack
);

reg       busy = 1'b0;
reg [2:0] g = 3'd0;
reg [2:0] pick;
integer i;
always @(*) begin
	pick = 3'd0;
	for (i = N - 1; i >= 0; i = i - 1)
		if (req[i]) pick = i;
end
wire [2:0] cur = busy ? g : pick;

always @(posedge clk) begin
	if (!busy) begin
		if (req != {N{1'b0}}) begin busy <= 1'b1; g <= pick; end
	end else if (aux_ack) busy <= 1'b0;
end

assign aux_req = busy & req[g];
assign aux_we = we[cur];
assign aux_addr = addr[cur * 22 +: 22];
assign aux_din = din[cur * 8 +: 8];
assign ack = busy ? ({{(N-1){1'b0}}, aux_ack} << g) : {N{1'b0}};

endmodule
