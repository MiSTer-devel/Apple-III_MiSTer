// One of Main's images shared by two cards, a hard disk the block card and a
// ProFile card both reach (apple3_cards). Both follow MiSTer's handshake:
// raise sd_rd or sd_wr while the acknowledge is low, drop it when the
// acknowledge rises, and finish when it falls. The first card to ask holds
// the image until its request is gone and the acknowledge has fallen, and
// card A wins a tie. The other card's request waits, and it sees no
// acknowledge until its turn.
module apple3_sd_arbiter (
	input logic clk,

	input  logic [31:0] a_lba,
	input  logic        a_rd,
	input  logic        a_wr,
	input  logic [ 7:0] a_buff_din,
	output logic        a_ack,

	input  logic [31:0] b_lba,
	input  logic        b_rd,
	input  logic        b_wr,
	input  logic [ 7:0] b_buff_din,
	output logic        b_ack,

	output logic [31:0] sd_lba,
	output logic        sd_rd,
	output logic        sd_wr,
	output logic [ 7:0] sd_buff_din,
	input  logic        sd_ack
);

	logic held = 1'b0;
	logic b_holds = 1'b0;
	wire  a_asks = a_rd || a_wr;
	wire  b_asks = b_rd || b_wr;

	always_ff @(posedge clk) begin
		if (!held) begin
			held    <= a_asks || b_asks;
			b_holds <= !a_asks;
		end else if (!(b_holds ? b_asks : a_asks) && !sd_ack) begin
			held <= 1'b0;
		end
	end

	assign sd_lba      = b_holds ? b_lba : a_lba;
	assign sd_rd       = held && (b_holds ? b_rd : a_rd);
	assign sd_wr       = held && (b_holds ? b_wr : a_wr);
	assign sd_buff_din = b_holds ? b_buff_din : a_buff_din;
	assign a_ack       = held && !b_holds && sd_ack;
	assign b_ack       = held && b_holds && sd_ack;

endmodule
