`timescale 1ns / 10ps

// apple3_sdram against sdram_model, driven the way apple3_core drives it: a
// CPU cycle of seven or more clocks, the address valid from the clock after
// cycle, the write byte only from the clock after that (a pseudo-DMA byte
// comes from a card's buffer a clock late), and the word read taken at the
// next cycle.  Runs of shortest cycles, slow cycles and long RDY waits, with
// every bank and byte lane, for longer than the chip's 64 ms refresh period.
module sdram_tb;
	logic clk = 1'b0;
	always #34.92 clk = ~clk;

	logic init = 1'b1;
	logic ready;
	logic cycle = 1'b0, select = 1'b0, we = 1'b0, lane = 1'b0;
	logic [23:0] addr = '0;
	logic [ 7:0] din = 8'h00;
	wire  [15:0] q;

	wire cke, cs_n, ras_n, cas_n, we_n, dq_oe, chip_valid;
	wire [ 1:0] ba;
	wire [12:0] a;
	wire [15:0] dq_out, chip_dq;
	integer chip_errors, refreshes;

	apple3_sdram dut (
		.clk,
		.init,
		.ready,
		.cycle,
		.select,
		.addr,
		.we,
		.lane,
		.din,
		.q,
		.sdram_cke   (cke),
		.sdram_cs_n  (cs_n),
		.sdram_ras_n (ras_n),
		.sdram_cas_n (cas_n),
		.sdram_we_n  (we_n),
		.sdram_ba    (ba),
		.sdram_a     (a),
		.sdram_dq_out(dq_out),
		.sdram_dq_oe (dq_oe),
		.sdram_dq_in (chip_valid ? chip_dq : 16'hzzzz)
	);

	sdram_model #(
		.ROW_BITS(9)
	) chip (
		.clk         (~clk),
		.cke,
		.cs_n,
		.ras_n,
		.cas_n,
		.we_n,
		.ba,
		.a,
		.dqm         (a[12:11]),    // wired as on a MiSTer module
		.dq_in       (dq_out),
		.dq_in_valid (dq_oe),
		.dq_out      (chip_dq),
		.dq_out_valid(chip_valid),
		.errors      (chip_errors),
		.refreshes
	);

	logic [15:0] expected[logic [23:0]];
	integer reads = 0, writes = 0, failures = 0, cycles = 0;

	function automatic logic [23:0] random_address();
		// Every bank, rows 0-511 (the CPU uses bank 0, rows 0-255).
		random_address = {$urandom_range(3, 0), 4'b0000, 9'($urandom), 9'($urandom)};
	endfunction

	// One CPU cycle of `length` clocks, starting just after a cycle strobe.
	task automatic cpu_cycle(input integer length, input logic sel, input logic write, input logic [23:0] where,
							 input logic byte_lane, input logic [7:0] value);
		logic [15:0] word;
		@(negedge clk);
		cycle  = 1'b0;
		select = sel;
		we     = write;
		addr   = where;
		lane   = byte_lane;
		din    = 8'($urandom);  // not yet valid
		@(negedge clk);
		din = value;
		repeat (length - 2) @(negedge clk);
		cycle = 1'b1;
		@(posedge clk);  // the CPU takes the word here
		cycles++;
		if (sel && !write) begin
			reads++;
			word = expected.exists(where) ? expected[where] : 16'h0000;
			if (q !== word) begin
				failures++;
				if (failures <= 10)
					$display("FAIL read %06x after %0d clocks: %04x, expected %04x", where, length, q, word);
			end
		end
		if (sel && write) begin
			writes++;
			word = expected.exists(where) ? expected[where] : 16'h0000;
			if (byte_lane) word[15:8] = value;
			else word[7:0] = value;
			expected[where] = word;
		end
	endtask

	task automatic random_cycles(input integer count, input integer min_length, input integer max_length);
		logic [23:0] where;
		for (integer i = 0; i < count; i++) begin
			// Re-read recent addresses often, so a write is read back at once.
			where        = (expected.num() != 0 && $urandom_range(2, 0) == 0) ? last_address : random_address();
			last_address = where;
			cpu_cycle($urandom_range(max_length, min_length), $urandom_range(9, 0) != 0, $urandom_range(1, 0), where,
					  $urandom_range(1, 0), 8'($urandom));
		end
	endtask
	logic [23:0] last_address = '0;

	initial begin
		repeat (20) @(negedge clk);
		init = 1'b0;
		wait (ready);
		@(negedge clk);
		cycle = 1'b1;
		@(negedge clk);

		random_cycles(20000, 7, 7);  // the fast CPU with no video slots
		random_cycles(20000, 7, 16);  // fast and slow cycles, the long state
		for (integer i = 0; i < 40; i++) begin
			random_cycles(500, 7, 8);
			cpu_cycle($urandom_range(3000, 100), 1'b1, 1'b0, last_address, 1'b0, 8'h00);  // RDY wait
		end
		random_cycles(60000, 7, 14);

		if (chip_errors != 0) $fatal(1, "SDRAM protocol: %0d errors", chip_errors);
		if (failures != 0) $fatal(1, "%0d of %0d reads wrong", failures, reads);
		if (refreshes * 7812.5 < $realtime - 250000.0)
			$fatal(1, "only %0d refreshes in %0.1f ms", refreshes, $realtime / 1.0e6);
		$display("PASS apple3_sdram: %0d reads, %0d writes over %0d CPU cycles, %0d refreshes in %0.1f ms", reads,
				 writes, cycles, refreshes, $realtime / 1.0e6);
		$finish;
	end
endmodule
