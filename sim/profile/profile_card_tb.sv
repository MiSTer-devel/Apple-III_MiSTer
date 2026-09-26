// Register-level test of the ProFile card with a modelled host image and slot
// bus. It drives the card the way Apple's .PROFILE driver does: the CMD/BSY
// handshakes through the soft switches, command bytes and data through
// WBUF/RBUF, and page transfers as pseudo-DMA cycles.
`timescale 1ns / 1ps
module profile_card_tb;
	logic clk = 0;
	always #5 clk = ~clk;
	logic reset = 1, cycle = 0, cpu_read = 1, device_select = 0, io_select = 0, rom_deselect = 0;
	logic [15:0] addr = 0;
	logic [ 7:0] data_in = 0;
	wire  [ 7:0] data_out;
	wire data_oe, activity, dma_req, dma_write;
	logic        dma_ok = 0;
	logic [ 7:0] dma_data = 0;
	logic        image_change = 0;
	logic [63:0] image_size = 0;
	logic        image_readonly = 0;
	wire  [31:0] sd_lba;
	wire sd_rd, sd_wr;
	logic       sd_ack = 0;
	logic [8:0] sd_buff_addr = 0;
	logic [7:0] sd_buff_dout = 0;
	wire  [7:0] sd_buff_din;
	logic       sd_buff_wr = 0;
	apple3_profile_card dut (
		.addr(addr[3:0]),
		.*
	);

	localparam int BLOCKS = 40;
	logic [7:0] image[BLOCKS*512];
	logic [7:0] page [       512];
	integer host_latency = 20, host_transfers = 0, last_lba = -1, checks = 0, waited;
	logic [7:0] value;
	logic       host_pause = 0;

	initial begin
		for (int i = 0; i < BLOCKS * 512; i++) image[i] = 8'(i * 7 + (i >> 9));
	end

	// Host model: acknowledges one request at a time after a latency, then
	// moves 512 bytes at four clocks per byte, as hps_io does over SPI.
	always begin
		@(negedge clk);
		if (!host_pause && (sd_rd || sd_wr)) begin
			last_lba = sd_lba;
			repeat (host_latency) @(negedge clk);
			sd_ack = 1;
			repeat (4) @(negedge clk);
			for (int i = 0; i < 512; i++) begin
				sd_buff_addr = i[8:0];
				if (sd_rd) begin
					sd_buff_dout = (sd_lba * 512 + i < BLOCKS * 512) ? image[sd_lba*512+i] : 8'h00;
					repeat (3) @(negedge clk);
					sd_buff_wr = 1;
					@(negedge clk);
					sd_buff_wr = 0;
				end else begin
					repeat (4) @(negedge clk);
					if (sd_lba * 512 + i < BLOCKS * 512) image[sd_lba*512+i] = sd_buff_din;
				end
			end
			repeat (4) @(negedge clk);
			sd_ack = 0;
			host_transfers++;
		end
	end

	// The card sits in slot 4: $C0C0 device select, $C400 I/O select.
	task automatic bus_read(input logic [15:0] a, output logic [7:0] d);
		@(negedge clk);
		addr          = a;
		cpu_read      = 1;
		device_select = (a[15:4] == 12'hc0c);
		io_select     = (a[15:8] == 8'hc4);
		rom_deselect  = (a[15:4] == 12'hc02);
		repeat (3) @(negedge clk);
		cycle = 1;
		#1;
		d = data_oe ? data_out : 8'hff;
		@(negedge clk);
		cycle         = 0;
		device_select = 0;
		io_select     = 0;
		rom_deselect  = 0;
	endtask

	task automatic bus_write(input logic [15:0] a, input logic [7:0] d);
		@(negedge clk);
		addr          = a;
		data_in       = d;
		cpu_read      = 0;
		device_select = (a[15:4] == 12'hc0c);
		io_select     = (a[15:8] == 8'hc4);
		rom_deselect  = (a[15:4] == 12'hc02);
		repeat (3) @(negedge clk);
		cycle = 1;
		#1;
		if (data_oe) $fatal(1, "write of %04x drives the bus", a);
		@(negedge clk);
		cycle         = 0;
		cpu_read      = 1;
		device_select = 0;
		io_select     = 0;
		rom_deselect  = 0;
	endtask

	// A pseudo-DMA cycle: a ROM fetch the card has claimed.
	task automatic dma_cycle(input logic to_drive, input logic [7:0] out, output logic [7:0] in);
		@(negedge clk);
		dma_ok   = 1;
		dma_data = out;
		repeat (3) @(negedge clk);
		if (!dma_req) $fatal(1, "DMA cycle without a request");
		if (dma_write == to_drive) $fatal(1, "DMA direction wrong");
		cycle = 1;
		#1;
		in = data_out;
		@(negedge clk);
		cycle  = 0;
		dma_ok = 0;
	endtask

	task automatic expect_value(input logic [7:0] got, input logic [7:0] want, input string what);
		checks++;
		if (got !== want) $fatal(1, "%s: got %02x, want %02x", what, got, want);
	endtask

	task automatic rstat(output logic [7:0] d);
		bus_read(16'hc0c2, d);
	endtask

	// The driver's soft-switch accesses are reads of $Cn0x.
	task automatic switch(input logic [3:0] offset);
		logic [7:0] d;
		bus_read(16'hc400 | 16'(offset), d);
	endtask

	task automatic wait_idle(input string what);
		logic [7:0] d;
		waited = 0;
		forever begin
			rstat(d);
			if (d[7]) break;
			waited++;
			if (waited > 20000) $fatal(1, "%s: drive stays busy", what);
		end
	endtask

	task automatic wait_busy(input string what);
		logic [7:0] d;
		waited = 0;
		forever begin
			rstat(d);
			if (!d[7]) break;
			waited++;
			if (waited > 100) $fatal(1, "%s: drive never goes busy", what);
		end
	endtask

	// SNDCMD: CMD up, response, answer, CMD down. Returns the response.
	task automatic handshake(input logic [7:0] answer, output logic [7:0] response);
		wait_idle("handshake");
		switch(4'h4);  // CMD high
		wait_busy("handshake");
		bus_read(16'hc0c1, response);
		bus_write(16'hc0c0, answer);
		switch(4'h1);  // CRW low
		switch(4'h3);  // DATARW low
		switch(4'h0);  // CMD low
		wait_idle("handshake");
		switch(4'h5);  // CRW high
		switch(4'h7);  // DATARW high
	endtask

	task automatic send_command(input logic [7:0] command, input logic [23:0] block);
		switch(4'h1);
		switch(4'h3);
		bus_write(16'hc0c0, command);
		bus_write(16'hc0c0, block[23:16]);
		bus_write(16'hc0c0, block[15:8]);
		bus_write(16'hc0c0, block[7:0]);
		bus_write(16'hc0c0, 8'h0a);
		bus_write(16'hc0c0, 8'h03);
		switch(4'h5);
		switch(4'h7);
	endtask

	task automatic read_status(output logic [3:0][7:0] s);
		logic [7:0] b;
		for (int i = 0; i < 4; i++) begin
			bus_read(16'hc0c1, b);
			s[i] = b;
		end
	endtask

	// A read: two handshakes, status, then 512 bytes by RBUF or by DMA.
	task automatic read_block(input logic [23:0] block, input logic by_dma, output logic [3:0][7:0] s);
		logic [7:0] r;
		handshake(8'h55, r);
		expect_value(r, 8'h01, "read: first response");
		send_command(8'h00, block);
		handshake(8'h55, r);
		expect_value(r, 8'h02, "read: second response");
		read_status(s);
		for (int i = 0; i < 512; i++) begin
			logic [7:0] b;
			if (by_dma) dma_cycle(1'b0, 8'h00, b);
			else bus_read(16'hc0c1, b);
			page[i] = b;
		end
	endtask

	// A write/verify: three handshakes, 512 data bytes and six tag bytes.
	task automatic write_block(input logic [23:0] block, input logic by_dma, output logic [3:0][7:0] s);
		logic [7:0] r, d;
		handshake(8'h55, r);
		expect_value(r, 8'h01, "write: first response");
		send_command(8'h02, block);
		handshake(8'h55, r);
		expect_value(r, 8'h04, "write: second response");
		switch(4'h1);
		switch(4'h3);
		for (int i = 0; i < 512; i++) begin
			if (by_dma) dma_cycle(1'b1, page[i], d);
			else bus_write(16'hc0c0, page[i]);
		end
		for (int i = 0; i < 6; i++) bus_write(16'hc0c0, 8'(i));
		switch(4'h5);
		switch(4'h7);
		handshake(8'h55, r);
		expect_value(r, 8'h06, "write: third response");
		read_status(s);
	endtask

	task automatic expect_status(input logic [3:0][7:0] s, input logic [7:0] s1, input logic [7:0] s3,
								 input string what);
		expect_value(s[0], s1, {what, ": status 1"});
		expect_value(s[1], 8'h00, {what, ": status 2"});
		expect_value(s[2], s3, {what, ": status 3"});
		expect_value(s[3], 8'h00, {what, ": status 4"});
	endtask

	logic [3:0][7:0] s;
	logic [7:0] r, d;

	initial begin
		repeat (5) @(negedge clk);
		reset = 0;
		repeat (5) @(negedge clk);

		// No image: idle, no drive; I/O select reads return nothing.
		rstat(d);
		expect_value(d, 8'h81, "empty drive status");
		bus_read(16'hc4ff, d);
		expect_value(d, 8'hff, "I/O select read");

		// Mount 40 blocks.
		@(negedge clk);
		image_size   = BLOCKS * 512;
		image_change = 1;
		@(negedge clk);
		image_change = 0;
		rstat(d);
		expect_value(d, 8'h80, "mounted drive status");
		// The status register mirrors every four bytes.
		bus_read(16'hc0c6, d);
		expect_value(d, 8'h80, "RSTAT mirror at +6");
		bus_read(16'hc0ce, d);
		expect_value(d, 8'h80, "RSTAT mirror at +E");
		bus_read(16'hc0c0, d);
		expect_value(d, 8'hff, "offset 0 read drives nothing");

		// Read block 5 byte by byte.
		read_block(24'd5, 1'b0, s);
		expect_status(s, 8'h00, 8'h00, "read 5");
		for (int i = 0; i < 512; i++) expect_value(page[i], image[5*512+i], "read 5 data");
		expect_value(8'(host_transfers), 8'd1, "one host transfer");
		expect_value(8'(last_lba), 8'd5, "host block");
		// The soft-switch accesses selected the card; C02x deselects it, and
		// the next handshake's accesses select it again.
		checks++;
		if (!dma_req) $fatal(1, "DMA not claimed after switch accesses");
		bus_read(16'hc020, d);
		checks++;
		if (dma_req) $fatal(1, "DMA claimed after C02x");

		// The same block by pseudo-DMA.
		read_block(24'd5, 1'b1, s);
		expect_status(s, 8'h00, 8'h00, "read 5 by DMA");
		for (int i = 0; i < 512; i++) expect_value(page[i], image[5*512+i], "DMA read data");
		checks++;
		if (!dma_req) $fatal(1, "DMA not claimed while selected");
		bus_read(16'hc020, d);
		checks++;
		if (dma_req) $fatal(1, "C02x did not deselect the card");
		bus_read(16'hc4ff, d);  // SELC800's select access
		checks++;
		if (!dma_req) $fatal(1, "$CnFF did not select the card");
		bus_read(16'hc020, d);

		// Write block 7 through WBUF, read it back through DMA.
		for (int i = 0; i < 512; i++) page[i] = 8'(255 - i);
		write_block(24'd7, 1'b0, s);
		expect_status(s, 8'h00, 8'h00, "write 7");
		for (int i = 0; i < 512; i++) expect_value(image[7*512+i], 8'(255 - i), "host image after write");
		read_block(24'd7, 1'b1, s);
		for (int i = 0; i < 512; i++) expect_value(page[i], 8'(255 - i), "read back 7");

		// Write block 8 by DMA, the tag bytes still by WBUF.
		for (int i = 0; i < 512; i++) page[i] = 8'(i * 3 + 1);
		write_block(24'd8, 1'b1, s);
		expect_status(s, 8'h00, 8'h00, "write 8 by DMA");
		for (int i = 0; i < 512; i++) expect_value(image[8*512+i], 8'(i * 3 + 1), "host image after DMA write");
		bus_read(16'hc020, d);

		// Block $FFFFFE is the buffer as it stands; $FFFFFF the spare table.
		read_block(24'hfffffe, 1'b0, s);
		expect_status(s, 8'h00, 8'h00, "buffer block");
		for (int i = 0; i < 512; i++) expect_value(page[i], 8'(i * 3 + 1), "buffer block data");
		read_block(24'hffffff, 1'b0, s);
		expect_status(s, 8'h00, 8'h00, "spare table");
		expect_value(page[0], "P", "spare table name");
		expect_value(page[6], "E", "spare table name end");
		expect_value(page[12], " ", "spare table name padding");
		expect_value(page[14], 8'h00, "5 MB device type");
		expect_value(page[16], 8'h03, "firmware 3.98");
		expect_value(page[17], 8'h98, "firmware 3.98");
		expect_value(page[18], 8'h00, "blocks high");
		expect_value(page[19], 8'h00, "blocks middle");
		expect_value(page[20], 8'd40, "blocks low");
		expect_value(page[21], 8'h02, "532 bytes per block");
		expect_value(page[22], 8'h14, "532 bytes per block");
		expect_value(page[40], 8'h00, "spare table tail");
		expect_value(8'(host_transfers), 8'd5, "no host transfer for special blocks");

		// A block beyond the drive fails without a host transfer.
		read_block(24'd40, 1'b0, s);
		expect_status(s, 8'h01, 8'h40, "block 40");
		write_block(24'd1000, 1'b0, s);
		expect_status(s, 8'h01, 8'h40, "block 1000 write");
		expect_value(8'(host_transfers), 8'd5, "no host transfer for bad blocks");

		// An answer other than $55 aborts; the drive is back at the start.
		handshake(8'haa, r);
		expect_value(r, 8'h01, "nack: response");
		handshake(8'h55, r);
		expect_value(r, 8'h01, "after nack: response");
		send_command(8'h00, 24'd3);
		handshake(8'haa, r);
		expect_value(r, 8'h02, "nack after command bytes");
		expect_value(8'(host_transfers), 8'd5, "nacked read not executed");
		read_block(24'd3, 1'b0, s);
		for (int i = 0; i < 512; i++) expect_value(page[i], image[3*512+i], "read 3 after nack");

		// GOODEXIT: a handshake, an invalid command, CMD up and down with no
		// waiting. The next operation still works.
		handshake(8'h55, r);
		send_command(8'hff, 24'd0);
		switch(4'h4);
		switch(4'h4);
		switch(4'h0);
		bus_read(16'hc020, d);
		read_block(24'd2, 1'b1, s);
		expect_status(s, 8'h00, 8'h00, "read 2 after GOODEXIT");
		for (int i = 0; i < 512; i++) expect_value(page[i], image[2*512+i], "read 2 data");

		// CRES resets the drive mid-command.
		handshake(8'h55, r);
		send_command(8'h00, 24'd4);
		switch(4'hc);
		repeat (20) @(negedge clk);
		rstat(d);
		expect_value(d, 8'h80, "idle while CRES held");
		switch(4'h8);
		handshake(8'h55, r);
		expect_value(r, 8'h01, "after CRES: first handshake");
		switch(4'h4);
		switch(4'h0);

		// A slot reset clears the card and the drive; the mount stays.
		handshake(8'h55, r);
		send_command(8'h00, 24'd6);
		@(negedge clk);
		reset = 1;
		repeat (3) @(negedge clk);
		reset = 0;
		checks++;
		if (dma_req) $fatal(1, "DMA claimed after reset");
		rstat(d);
		expect_value(d, 8'h80, "idle after reset, still mounted");
		read_block(24'd6, 1'b0, s);
		for (int i = 0; i < 512; i++) expect_value(page[i], image[6*512+i], "read 6 after reset");

		// A reset during a host transfer: the next command waits for the
		// abandoned acknowledgement before it starts its own.
		host_latency = 2000;
		handshake(8'h55, r);
		send_command(8'h00, 24'd9);
		switch(4'h4);
		wait_busy("read 9");
		bus_read(16'hc0c1, r);
		bus_write(16'hc0c0, 8'h55);
		switch(4'h0);
		repeat (2100) @(negedge clk);
		checks++;
		if (!sd_ack) $fatal(1, "host transfer not in progress");
		@(negedge clk);
		reset = 1;
		repeat (3) @(negedge clk);
		reset        = 0;
		host_latency = 20;
		read_block(24'd10, 1'b0, s);
		expect_status(s, 8'h00, 8'h00, "read 10 after abandoned transfer");
		for (int i = 0; i < 512; i++) expect_value(page[i], image[10*512+i], "read 10 data");

		// A read-only image refuses writes and reports it in status 1.
		@(negedge clk);
		image_readonly = 1;
		image_change   = 1;
		@(negedge clk);
		image_change = 0;
		for (int i = 0; i < 512; i++) page[i] = 8'h5a;
		write_block(24'd1, 1'b0, s);
		expect_status(s, 8'h01, 8'h00, "write to a read-only image");
		expect_value(image[512], 8'(512 * 7 + 1), "read-only image untouched");
		read_block(24'd1, 1'b0, s);
		expect_status(s, 8'h00, 8'h00, "read from a read-only image");

		// Unmounting: no drive again.
		@(negedge clk);
		image_size   = 0;
		image_change = 1;
		@(negedge clk);
		image_change = 0;
		rstat(d);
		expect_value(d, 8'h81, "unmounted drive status");
		read_block(24'd1, 1'b0, s);
		expect_status(s, 8'h01, 8'h40, "read with no image");

		$display("PASS apple3_profile_card (%0d checks, %0d host transfers)", checks, host_transfers);
		$finish;
	end

	initial begin
		#400ms;
		$fatal(1, "timeout");
	end
endmodule
