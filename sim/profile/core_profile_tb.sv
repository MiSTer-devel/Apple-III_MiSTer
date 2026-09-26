// Run the ProFile diagnostic on the real T65, MMU, slot bus and pseudo-DMA
// path with the card in slot 4 and a modelled host serving one image.
`timescale 1ns / 1ps
module core_profile_tb;
	logic clk = 0, reset = 1;
	logic [10:0] ps2_key = 0;
	wire [15:0] slot_addr, cpu_addr, pc;
	wire [7:0] slot_data_out, cpu_dout, card_data, dma_data;
	wire [3:0] slot_device_select, slot_io_select;
	wire card_oe, card_activity, dma_ok, dma_req, dma_write;
	wire slot_cpu_read, slot_cycle, slot_reset, slot_io_strobe, slot_rom_deselect, slot_bus_conflict;
	wire cpu_enable, cpu_rwn;
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
	integer phase = 0, cycles = 0, host_transfers = 0, dma_cycles = 0;
	logic completed = 0;
	always #5 clk = ~clk;

	apple3_core #(
		.ROM_INIT_FILE("sim/profile/obj_dir/diagnostic.hex")
	) dut (
		.clk_14m            (clk),
		.reset,
		.ps2_key,
		.plus_keymap        (1'b0),
		.ram_128k           (1'b0),
		.soshdboot          (1'b0),
		.interlace          (1'b0),
		.euro               (1'b0),
		.host_rtc           (65'd0),
		.joy_a_x            (8'd128),
		.joy_a_y            (8'd128),
		.joy_b_x            (8'd128),
		.joy_b_y            (8'd128),
		.joy_a_button       (1'b0),
		.joy_a_switch       (1'b0),
		.joy_b_button       (1'b0),
		.joy_b_switch       (1'b0),
		.slot_data_in       ({card_data, 24'hffffff}),
		.slot_data_oe       ({card_oe, 3'b000}),
		.slot_irq_n         (4'b1111),
		.slot_nmi_n         (4'b1111),
		.slot_ready         (4'b1111),
		.slot_addr,
		.slot_data_out,
		.slot_cpu_read,
		.slot_cycle,
		.slot_reset,
		.slot_device_select,
		.slot_io_select,
		.slot_io_strobe,
		.slot_rom_deselect,
		.slot_bus_conflict,
		.slot_dma_ok        (dma_ok),
		.slot_dma_req       ({dma_req, 3'b000}),
		.slot_dma_write     ({dma_write, 3'b000}),
		.slot_dma_data      (dma_data),
		.serial_rx          (1'b1),
		.serial_cts_n       (1'b0),
		.serial_dsr_n       (1'b0),
		.serial_dcd_n       (1'b0),
		.serial_tx          (),
		.serial_rts_n       (),
		.serial_dtr_n       (),
		.rom_we             (1'b0),
		.rom_host_addr      (13'd0),
		.rom_host_data      (8'd0),
		.disk_ready         (4'd0),
		.disk_write_protect (4'hf),
		.disk_flux          (4'd0),
		.disk_media_change  (4'd0),
		.disk_phases        (),
		.disk_write_mode    (),
		.disk_write_bit     (),
		.disk_write_strobe  (),
		.disk_motors        (),
		.video_r            (),
		.video_g            (),
		.video_b            (),
		.video_hblank       (),
		.video_vblank       (),
		.video_hsync        (),
		.video_vsync        (),
		.video_field        (),
		.video_colour       (),
		.video_colour_phase (),
		.video_colour_burst (),
		.audio              (),
		.disk_activity      (),
		.disk_active        (),
		.debug_pc           (pc),
		.debug_cpu_addr     (cpu_addr),
		.debug_cpu_enable   (cpu_enable),
		.debug_cpu_rwn      (cpu_rwn),
		.debug_cpu_dout     (cpu_dout),
		.debug_environment  (),
		.debug_zero_page    (),
		.debug_bank         (),
		.debug_video_mode   (),
		.debug_cpu_sync     (),
		.debug_cpu_din      (),
		.debug_e_pa_o       (),
		.debug_e_pa_ddr     (),
		.debug_a            (),
		.debug_x            (),
		.debug_y            (),
		.debug_sp           (),
		.debug_p            (),
		.debug_ram_byte_addr(),
		.debug_ram_write    ()
	);

	apple3_profile_card card (
		.clk,
		.reset        (slot_reset),
		.cycle        (slot_cycle),
		.addr         (slot_addr[3:0]),
		.cpu_read     (slot_cpu_read),
		.data_in      (slot_data_out),
		.device_select(slot_device_select[3]),
		.io_select    (slot_io_select[3]),
		.rom_deselect (slot_rom_deselect),
		.data_out     (card_data),
		.data_oe      (card_oe),
		.activity     (card_activity),
		.dma_ok,
		.dma_data,
		.dma_req,
		.dma_write,
		.image_change,
		.image_size,
		.image_readonly,
		.sd_lba,
		.sd_rd,
		.sd_wr,
		.sd_ack,
		.sd_buff_addr,
		.sd_buff_dout,
		.sd_buff_din,
		.sd_buff_wr
	);

	// 40 blocks; byte i of block b = b * 17 + i * 3.
	logic [7:0] image[40*512];
	initial begin
		for (int b = 0; b < 40; b++) for (int i = 0; i < 512; i++) image[b*512+i] = 8'(b * 17 + i * 3);
	end

	// Host model with 5,000 clocks of latency per request and four clocks
	// per byte, roughly MiSTer's SD path.
	always begin
		integer base;
		logic   read;
		@(negedge clk);
		if (sd_rd | sd_wr) begin
			read = sd_rd;
			base = sd_lba * 512;
			repeat (5000) @(negedge clk);
			sd_ack = 1;
			repeat (4) @(negedge clk);
			for (int i = 0; i < 512; i++) begin
				sd_buff_addr = i[8:0];
				if (read) begin
					sd_buff_dout = base + i < 40 * 512 ? image[base+i] : 8'h00;
					repeat (3) @(negedge clk);
					sd_buff_wr = 1;
					@(negedge clk);
					sd_buff_wr = 0;
				end else begin
					repeat (4) @(negedge clk);
					if (base + i < 40 * 512) image[base+i] = sd_buff_din;
				end
			end
			repeat (4) @(negedge clk);
			sd_ack = 0;
			host_transfers++;
		end
	end

	always @(posedge clk) begin
		cycles <= cycles + 1;
		if (slot_bus_conflict) $fatal(1, "bus contention at PC %04x", pc);
		if (slot_cycle && dma_ok && dma_req) begin
			dma_cycles++;
			if (phase == 5 && $test$plusargs("trace"))
				$display("dma %04x -> %02x", cpu_addr, dma_write ? card_data : dma_data);
		end
		// A pseudo-DMA cycle is a ROM fetch: the CPU must read the ladder.
		if (slot_cycle && dma_ok && (cpu_addr[15:8] != 8'hf8)) $fatal(1, "DMAOK outside $F8xx at %04x", cpu_addr);
		if (cpu_enable && !cpu_rwn && !dut.machine_reset) begin
			if (cpu_addr == 16'h0201) begin
				phase <= int'(cpu_dout);
				$display("ProFile diagnostic phase %0d at %0d clocks", cpu_dout, cycles);
			end
			if (cpu_addr == 16'h0202) begin
				case (cpu_dout)
					8'd6: begin
						// The write of block 9 must already be in the host image.
						for (int i = 0; i < 256; i++) begin
							if (image[9*512+i] != 8'(i ^ 8'h5a) || image[9*512+256+i] != 8'(i ^ 8'ha5))
								$fatal(1, "host block 9 byte %0d not written", i);
						end
					end
					default: $fatal(1, "unknown bench request %0d", cpu_dout);
				endcase
			end
			if (cpu_addr == 16'h0200) begin
				if (cpu_dout != 8'h5a) $fatal(1, "diagnostic failed in phase %0d at PC %04x", phase, pc);
				completed <= 1;
			end
		end
		if (cycles > 4000000) $fatal(1, "timeout phase=%0d PC=%04x", phase, pc);
	end

	initial begin
		// Mount the image while the machine is still in reset.
		repeat (10) @(negedge clk);
		image_size   = 64'd40 * 512;
		image_change = 1;
		@(negedge clk);
		image_change = 0;
		image_size   = 0;
		repeat (100) @(negedge clk);
		reset = 0;
		wait (completed != 0);
		// Four reads and one write reach the host. Pseudo-DMA moves two whole
		// pages of block 6, 200 + 256 bytes of block 7, 60 + 188 of block 8
		// and two pages of block 9; the deselected run moves nothing.
		if (host_transfers != 5) $fatal(1, "expected 5 host transfers, saw %0d", host_transfers);
		if (dma_cycles != 512 + 456 + 248 + 512)
			$fatal(1, "expected %0d pseudo-DMA cycles, saw %0d", 512 + 456 + 248 + 512, dma_cycles);
		$display("PASS real CPU ProFile driver protocol: handshakes, RBUF/WBUF, whole and partial",
				 " pseudo-DMA pages, write, deselect (%0d clocks, %0d host transfers, %0d DMA cycles)", cycles,
				 host_transfers, dma_cycles);
		$finish;
	end
endmodule
