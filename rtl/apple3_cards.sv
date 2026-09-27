// The card cage: the peripheral cards and the slot each one is in.
//
// The OSD names a card for each of the four slots (docs/SLOTS.md):
//
//   0 empty
//   1 the block-storage card, with Block Disks 1 and 2 (Problock3, soshdboot)
//   2 Apple's ProFile card, with ProFile Disk 1 (the stock .PROFILE driver)
//   3 a second ProFile card, with ProFile Disk 2
//   4 the Apple II mouse card
//
// Like a board change on the machine, the choice takes effect at the next
// slot reset. There is one of each card, so a card named for more than one
// slot goes in the lowest of them and the others stay empty. Each disk
// image belongs to one card.
module apple3_cards (
	input logic clk,
	input logic reset,  // the slot reset, /IORESET
	input logic cycle,

	// The card for each slot, slot 1 first, in the codes above.
	input logic [3:0][2:0] slot_card,

	// Slot bus (docs/SLOTS.md).
	input logic [7:0] addr,
	input logic       cpu_read,
	input logic [7:0] data_in,
	input logic [3:0] device_select,
	input logic [3:0] io_select,
	input logic       rom_deselect,
	input logic       dma_ok,
	input logic [7:0] dma_data,

	// Each slot's lines to the machine, slot 1 first.
	output logic [3:0][7:0] data_out,
	output logic [3:0]      data_oe,
	output logic [3:0]      irq_n,
	output logic [3:0]      ready,
	output logic [3:0]      dma_req,
	output logic [3:0]      dma_write,
	output logic            activity,

	// MiSTer's mouse and the Mouse Speed option (apple3_mouse_card).
	input logic [24:0] ps2_mouse,
	input logic [ 1:0] mouse_speed,

	// The disk images, Main's S4 to S7: Block Disks 1 and 2, then ProFile
	// Disks 1 and 2.
	input  logic [ 3:0]       image_change,
	input  logic [63:0]       image_size,
	input  logic              image_readonly,
	output logic [ 3:0][31:0] sd_lba,
	output logic [ 3:0]       sd_rd,
	output logic [ 3:0]       sd_wr,
	input  logic [ 3:0]       sd_ack,
	input  logic [ 8:0]       sd_buff_addr,
	input  logic [ 7:0]       sd_buff_dout,
	output logic [ 3:0][ 7:0] sd_buff_din,
	input  logic              sd_buff_wr
);

	localparam logic [2:0] CARD_BLOCK     = 3'd1;
	localparam logic [2:0] CARD_PROFILE_1 = 3'd2;
	localparam logic [2:0] CARD_PROFILE_2 = 3'd3;
	localparam logic [2:0] CARD_MOUSE     = 3'd4;

	logic [3:0][2:0] installed = '0;
	always_ff @(posedge clk) if (reset) installed <= slot_card;

	// The one slot a card goes in, as a one-hot mask, or none.
	function automatic logic [3:0] slot_of(input logic [3:0][2:0] cards, input logic [2:0] card);
		logic [3:0] named;
		for (int i = 0; i < 4; i++) named[i] = cards[i] == card;
		slot_of = named & (~named + 4'd1);
	endfunction

	wire [3:0]      block_here = slot_of(installed, CARD_BLOCK);
	wire [3:0]      mouse_here = slot_of(installed, CARD_MOUSE);
	wire [1:0][3:0] profile_here = {slot_of(installed, CARD_PROFILE_2), slot_of(installed, CARD_PROFILE_1)};

	// The block card asks for one drive at a time, so its two images share
	// its block number and buffer.
	wire [31:0] block_lba;
	wire [ 7:0] block_din;
	assign sd_lba[1:0]      = {block_lba, block_lba};
	assign sd_buff_din[1:0] = {block_din, block_din};

	wire [7:0] block_data;
	wire block_oe, block_ready, block_activity;

	apple3_block_card block_card (
		.clk,
		.reset        (reset || (block_here == 4'b0000)),
		.cycle,
		.addr,
		.cpu_read,
		.data_in,
		.device_select(|(device_select & block_here)),
		.io_select    (|(io_select & block_here)),
		.data_out     (block_data),
		.data_oe      (block_oe),
		.ready        (block_ready),
		.activity     (block_activity),
		.image_change (image_change[1:0]),
		.image_size,
		.image_readonly,
		.sd_lba       (block_lba),
		.sd_rd        (sd_rd[1:0]),
		.sd_wr        (sd_wr[1:0]),
		.sd_ack       (sd_ack[1:0]),
		.sd_buff_addr,
		.sd_buff_dout,
		.sd_buff_din  (block_din),
		.sd_buff_wr
	);

	genvar disk, slot;

	wire [1:0][7:0] profile_data;
	wire [1:0] profile_oe, profile_activity, profile_dma_req, profile_dma_write;

	generate
		for (disk = 0; disk < 2; disk++) begin : profiles
			apple3_profile_card card (
				.clk,
				.reset        (reset || (profile_here[disk] == 4'b0000)),
				.cycle,
				.addr         (addr[3:0]),
				.cpu_read,
				.data_in,
				.device_select(|(device_select & profile_here[disk])),
				.io_select    (|(io_select & profile_here[disk])),
				.rom_deselect,
				.data_out     (profile_data[disk]),
				.data_oe      (profile_oe[disk]),
				.activity     (profile_activity[disk]),
				.dma_ok,
				.dma_data,
				.dma_req      (profile_dma_req[disk]),
				.dma_write    (profile_dma_write[disk]),
				.image_change (image_change[2+disk]),
				.image_size,
				.image_readonly,
				.sd_lba       (sd_lba[2+disk]),
				.sd_rd        (sd_rd[2+disk]),
				.sd_wr        (sd_wr[2+disk]),
				.sd_ack       (sd_ack[2+disk]),
				.sd_buff_addr,
				.sd_buff_dout,
				.sd_buff_din  (sd_buff_din[2+disk]),
				.sd_buff_wr
			);
		end
	endgenerate

	wire [7:0] mouse_data;
	wire mouse_oe, mouse_irq_n;

	apple3_mouse_card mouse_card (
		.clk,
		.reset        (reset || (mouse_here == 4'b0000)),
		.cycle,
		.addr,
		.cpu_read,
		.data_in,
		.device_select(|(device_select & mouse_here)),
		.io_select    (|(io_select & mouse_here)),
		.data_out     (mouse_data),
		.data_oe      (mouse_oe),
		.irq_n        (mouse_irq_n),
		.ps2_mouse,
		.speed        (mouse_speed)
	);

	generate
		for (slot = 0; slot < 4; slot++) begin : slots
			assign data_out[slot] = block_here[slot] ? block_data :
									profile_here[0][slot] ? profile_data[0] :
									profile_here[1][slot] ? profile_data[1] : mouse_data;
			assign data_oe[slot] = (block_here[slot] && block_oe) || (profile_here[0][slot] && profile_oe[0]) ||
								   (profile_here[1][slot] && profile_oe[1]) || (mouse_here[slot] && mouse_oe);
			assign irq_n[slot] = !mouse_here[slot] || mouse_irq_n;
			assign ready[slot] = !block_here[slot] || block_ready;
			assign dma_req[slot] = (profile_here[0][slot] && profile_dma_req[0]) ||
								   (profile_here[1][slot] && profile_dma_req[1]);
			assign dma_write[slot] = (profile_here[0][slot] && profile_dma_write[0]) ||
									 (profile_here[1][slot] && profile_dma_write[1]);
		end
	endgenerate

	assign activity = block_activity || (|profile_activity);

endmodule
