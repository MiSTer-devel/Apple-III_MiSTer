// apple3_cards: which card answers in which slot, a card named twice, the
// choice taken at reset, and apple3_sd_arbiter's sharing of one image.
`timescale 1ns / 1ps
module cards_tb;
	localparam logic [2:0] EMPTY = 3'd0, BLOCK = 3'd1, PROFILE_1 = 3'd2, PROFILE_2 = 3'd3, MOUSE = 3'd4;

	logic clk = 1'b0;
	always #35 clk = !clk;

	logic            reset = 1'b1;
	logic [3:0][2:0] slot_card = '0;
	logic [7:0]      addr = 8'h00;
	logic [3:0] device_select = 4'b0000, io_select = 4'b0000;
	logic [ 1:0]      image_change = 2'b00;
	logic [63:0]      image_size = 64'd0;
	wire  [ 3:0][7:0] data_out;
	wire [3:0] data_oe, irq_n, ready, dma_req, dma_write;
	wire [1:0][31:0] sd_lba;
	wire [1:0][ 7:0] sd_buff_din;
	wire [1:0] sd_rd, sd_wr;

	apple3_cards dut (
		.clk,
		.reset,
		.cycle         (1'b0),
		.slot_card,
		.addr,
		.cpu_read      (1'b1),
		.data_in       (8'h00),
		.device_select,
		.io_select,
		.rom_deselect  (1'b0),
		.dma_ok        (1'b0),
		.dma_data      (8'h00),
		.data_out,
		.data_oe,
		.irq_n,
		.ready,
		.dma_req,
		.dma_write,
		.activity      (),
		.ps2_mouse     (25'd0),
		.mouse_speed   (2'd0),
		.image_change,
		.image_size,
		.image_readonly(1'b0),
		.sd_lba,
		.sd_rd,
		.sd_wr,
		.sd_ack        (2'b00),
		.sd_buff_addr  (9'd0),
		.sd_buff_dout  (8'h00),
		.sd_buff_din,
		.sd_buff_wr    (1'b0)
	);

	int checks = 0, errors = 0;
	task automatic check(input bit ok, input string what);
		checks++;
		if (!ok) begin
			errors++;
			$display("FAIL %s", what);
		end
	endtask

	task automatic install(input logic [3:0][2:0] cards);
		slot_card = cards;
		reset     = 1'b1;
		repeat (3) @(posedge clk);
		reset = 1'b0;
		repeat (3) @(posedge clk);
	endtask

	// What answers a read of a slot's device page at offset 2 (the ProFile's
	// RSTAT) and of its I/O page at offset 0 (the block card's first ROM
	// byte), and which slots drive the bus while it does.
	typedef struct {
		logic       dev_oe;
		logic [7:0] dev_data;
		logic       io_oe;
		logic [7:0] io_data;
		logic [3:0] dev_drivers;
		logic [3:0] io_drivers;
	} probe_t;

	task automatic probe(input int slot, output probe_t result);
		@(negedge clk);
		addr          = 8'h02;
		device_select = 4'b0001 << slot;
		@(negedge clk);
		result.dev_oe      = data_oe[slot];
		result.dev_data    = data_out[slot];
		result.dev_drivers = data_oe;
		device_select      = 4'b0000;
		addr               = 8'h00;
		io_select          = 4'b0001 << slot;
		@(negedge clk);
		result.io_oe      = data_oe[slot];
		result.io_data    = data_out[slot];
		result.io_drivers = data_oe;
		io_select         = 4'b0000;
	endtask

	// Checks that only `slot` holds a card, and that it is `card`.
	task automatic expect_card(input int slot, input logic [2:0] card, input string what);
		probe_t p;
		for (int t = 0; t < 4; t++) begin
			probe(t, p);
			if (t != slot || card == EMPTY) begin
				check(p.dev_drivers == 4'b0000 && p.io_drivers == 4'b0000, $sformatf(
					  "%s: slot %0d answers (dev %b, io %b)", what, t + 1, p.dev_drivers, p.io_drivers));
			end else begin
				check(p.dev_drivers == (4'b0001 << t), $sformatf("%s: device page drivers %b", what, p.dev_drivers));
				case (card)
					BLOCK: begin
						check(p.dev_oe && p.io_oe && p.io_data == 8'ha9, $sformatf(
							  "%s: block card in slot %0d (io %b %h)", what, t + 1, p.io_oe, p.io_data));
					end
					PROFILE_1, PROFILE_2: begin
						// Hard disk 1 holds an image and hard disk 2 none, so
						// RSTAT's no-drive bit tells the two ProFile cards apart.
						check(p.dev_oe && !p.io_oe && p.dev_data == ((card == PROFILE_1) ? 8'h80 : 8'h81), $sformatf(
							  "%s: ProFile %0d in slot %0d (dev %b %h, io %b)",
							  what,
							  card - 1,
							  t + 1,
							  p.dev_oe,
							  p.dev_data,
							  p.io_oe
							  ));
					end
					MOUSE: begin
						check(p.dev_oe && p.io_oe, $sformatf("%s: mouse card in slot %0d", what, t + 1));
					end
					default: ;
				endcase
			end
		end
	endtask

	// apple3_sd_arbiter with two requesting cards and a host.
	logic [31:0] a_lba = 32'h11, b_lba = 32'h22;
	logic a_rd = 1'b0, a_wr = 1'b0, b_rd = 1'b0, b_wr = 1'b0, host_ack = 1'b0;
	wire a_ack, b_ack, arb_rd, arb_wr;
	wire [31:0] arb_lba;
	wire [ 7:0] arb_din;

	apple3_sd_arbiter arbiter (
		.clk,
		.a_lba,
		.a_rd,
		.a_wr,
		.a_buff_din (8'haa),
		.a_ack,
		.b_lba,
		.b_rd,
		.b_wr,
		.b_buff_din (8'hbb),
		.b_ack,
		.sd_lba     (arb_lba),
		.sd_rd      (arb_rd),
		.sd_wr      (arb_wr),
		.sd_buff_din(arb_din),
		.sd_ack     (host_ack)
	);

	// Main: serve each request in turn, recording its block, direction and
	// the byte it would write, and holding the acknowledge a few clocks.
	int          served = 0;
	logic [31:0] served_lba  [8];
	logic        served_write[8];
	logic [ 7:0] served_din  [8];
	logic a_saw_ack = 1'b0, b_saw_ack = 1'b0, both_acked = 1'b0;
	always @(posedge clk) begin
		if (a_ack) a_saw_ack <= 1'b1;
		if (b_ack) b_saw_ack <= 1'b1;
		if (a_ack && b_ack) both_acked <= 1'b1;
	end
	initial begin
		forever begin
			@(posedge clk);
			if ((arb_rd || arb_wr) && !host_ack) begin
				repeat (2) @(posedge clk);
				served_lba[served]   = arb_lba;
				served_write[served] = arb_wr;
				host_ack <= 1'b1;
				repeat (6) @(posedge clk);
				served_din[served] = arb_din;
				served++;
				host_ack <= 1'b0;
			end
		end
	end

	// A card's side of the handshake: raise the request while the
	// acknowledge is low, drop it when it rises, finish when it falls.
	task automatic request_a(input logic write);
		while (a_ack) @(posedge clk);
		a_rd <= !write;
		a_wr <= write;
		while (!a_ack) @(posedge clk);
		a_rd <= 1'b0;
		a_wr <= 1'b0;
		while (a_ack) @(posedge clk);
	endtask
	task automatic request_b(input logic write);
		while (b_ack) @(posedge clk);
		b_rd <= !write;
		b_wr <= write;
		while (!b_ack) @(posedge clk);
		b_rd <= 1'b0;
		b_wr <= 1'b0;
		while (b_ack) @(posedge clk);
	endtask

	initial begin
		// Hard disk 1 holds an image, hard disk 2 none.
		@(negedge clk);
		image_size   = 64'd9728 * 512;
		image_change = 2'b01;
		@(negedge clk);
		image_change = 2'b00;

		// Each card in each slot, alone.
		for (int card = 0; card < 5; card++) begin
			for (int slot = 0; slot < 4; slot++) begin
				logic [3:0][2:0] cards;
				cards       = '0;
				cards[slot] = 3'(card);
				install(cards);
				expect_card(slot, 3'(card), $sformatf("card %0d alone in slot %0d", card, slot + 1));
			end
		end

		// As the core ships: the block card in slot 1, the mouse card in 4.
		install({MOUSE, EMPTY, EMPTY, BLOCK});
		begin
			probe_t p;
			probe(0, p);
			check(p.dev_drivers == 4'b0001 && p.io_data == 8'ha9, "shipped: block card in slot 1");
			probe(3, p);
			check(p.dev_drivers == 4'b1000 && p.io_drivers == 4'b1000, "shipped: mouse card in slot 4");
			probe(1, p);
			check(p.dev_drivers == 4'b0000 && p.io_drivers == 4'b0000, "shipped: slot 2 empty");
		end
		check(irq_n == 4'b1111 && ready == 4'b1111 && dma_req == 4'b0000, "idle cards hold no line");

		// Both ProFile cards at once, one per hard disk.
		install({EMPTY, PROFILE_2, PROFILE_1, EMPTY});
		begin
			probe_t p;
			probe(1, p);
			check(p.dev_oe && p.dev_data == 8'h80, "two ProFiles: hard disk 1's in slot 2");
			probe(2, p);
			check(p.dev_oe && p.dev_data == 8'h81, "two ProFiles: hard disk 2's in slot 3");
		end

		// A card named for several slots goes in the lowest.
		install({BLOCK, BLOCK, BLOCK, BLOCK});
		expect_card(0, BLOCK, "block card named four times");
		install({MOUSE, EMPTY, MOUSE, EMPTY});
		expect_card(1, MOUSE, "mouse card named for slots 2 and 4");
		install({PROFILE_1, PROFILE_1, EMPTY, EMPTY});
		expect_card(2, PROFILE_1, "ProFile 1 named for slots 3 and 4");

		// Codes past the mouse card leave the slot empty.
		install({3'd7, 3'd6, 3'd5, 3'd7});
		expect_card(0, EMPTY, "codes 5 to 7");

		// The choice is taken at reset, not when the option changes.
		install({EMPTY, EMPTY, EMPTY, BLOCK});
		slot_card = {BLOCK, EMPTY, EMPTY, EMPTY};
		repeat (4) @(posedge clk);
		expect_card(0, BLOCK, "option changed, no reset yet");
		install({BLOCK, EMPTY, EMPTY, EMPTY});
		expect_card(3, BLOCK, "after the reset");

		// Arbiter: one card alone.
		request_a(1'b0);
		repeat (2) @(posedge clk);
		check(served == 1 && served_lba[0] == 32'h11 && !served_write[0] && a_saw_ack && !b_saw_ack,
			  "arbiter: card A alone reads its block");

		// Both ask in the same clock: A first, B's request waits for it.
		fork
			request_a(1'b1);
			request_b(1'b1);
		join
		repeat (2) @(posedge clk);
		check(served == 3, $sformatf("arbiter: two requests, %0d served", served));
		check(served_lba[1] == 32'h11 && served_write[1] && served_din[1] == 8'haa, "arbiter: A's write goes first");
		check(served_lba[2] == 32'h22 && served_write[2] && served_din[2] == 8'hbb, "arbiter: then B's");
		check(b_saw_ack && !both_acked, "arbiter: never both acknowledged");

		// B holds the image; A asks during B's transfer and waits.
		fork
			request_b(1'b0);
			begin
				repeat (4) @(posedge clk);
				request_a(1'b0);
			end
		join
		repeat (2) @(posedge clk);
		check(served == 5 && served_lba[3] == 32'h22 && served_lba[4] == 32'h11,
			  "arbiter: a later request waits for the one in progress");
		check(!both_acked, "arbiter: still never both acknowledged");

		if (errors == 0) $display("PASS apple3_cards (%0d checks)", checks);
		else $display("FAIL apple3_cards: %0d of %0d checks", errors, checks);
		$finish;
	end
endmodule
