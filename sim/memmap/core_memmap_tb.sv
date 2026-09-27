`timescale 1ns / 1ps
// diagnostic.s on the whole core: the stock 256 KiB machine, then the 128 KiB
// board, then the 512K board with its upper banks in apple3_sdram and the
// SDRAM model.
module core_memmap_tb;
	logic clk = 0, reset = 1, ram_128k = 0, ram_512k = 0;
	logic [7:0] next_board = 8'h00;
	wire ext_ram_cycle, ext_ram_select, ext_ram_write, ext_ram_lane;
	wire [16:0] ext_ram_addr;
	wire [ 7:0] ext_ram_din;
	wire [15:0] ext_ram_q;
	wire sdram_ready, cke, cs_n, ras_n, cas_n, we_n, dq_oe, chip_valid;
	wire [ 1:0] ba;
	wire [12:0] a;
	wire [15:0] dq_out, chip_dq;
	integer chip_errors, refreshes;
	// The last opcodes fetched: a failure prints the JMP that named the check.
	wire         sync;
	logic [15:0] history[8];
	always @(posedge clk)
		if (cpu_enable && sync) begin
			for (int i = 7; i > 0; i--) history[i] <= history[i-1];
			history[0] <= cpu_addr;
		end
	wire [3:0] slot_device_select;
	wire [15:0] cpu_addr, pc;
	wire [7:0] cpu_dout;
	wire cpu_enable, cpu_rwn;
	integer cycles = 0, phase = 0;
	always #5 clk = ~clk;
	apple3_core #(
		.ROM_INIT_FILE("sim/memmap/obj_dir/diagnostic.hex")
	) dut (
		.clk_14m            (clk),
		.reset              (reset || !sdram_ready),
		.ps2_key            (11'd0),
		.plus_keymap        (1'b0),
		.ram_128k,
		.ram_512k,
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
		.slot_data_in       ({8'h00, 8'h00, 8'h00, 8'h5a}),
		.slot_data_oe       (slot_device_select),
		.slot_irq_n         (4'hf),
		.slot_nmi_n         (4'hf),
		.slot_ready         (4'hf),
		.slot_addr          (),
		.slot_data_out      (),
		.slot_cpu_read      (),
		.slot_cycle         (),
		.slot_reset         (),
		.slot_device_select,
		.slot_io_select     (),
		.slot_io_strobe     (),
		.slot_rom_deselect  (),
		.slot_bus_conflict  (),
		.slot_dma_ok        (),
		.slot_dma_req       (4'b0000),
		.slot_dma_write     (4'b0000),
		.slot_dma_data      (),
		.ext_ram_cycle,
		.ext_ram_select,
		.ext_ram_addr,
		.ext_ram_write,
		.ext_ram_lane,
		.ext_ram_din,
		.ext_ram_q,
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
		.debug_cpu_sync     (sync),
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
	logic sdram_init = 1'b1;
	always @(posedge clk) sdram_init <= 1'b0;
	apple3_sdram sdram (
		.clk,
		.init        (sdram_init),
		.ready       (sdram_ready),
		.cycle       (ext_ram_cycle),
		.select      (ext_ram_select),
		.addr        ({7'd0, ext_ram_addr}),
		.we          (ext_ram_write),
		.lane        (ext_ram_lane),
		.din         (ext_ram_din),
		.q           (ext_ram_q),
		.sdram_cke   (cke),
		.sdram_cs_n  (cs_n),
		.sdram_ras_n (ras_n),
		.sdram_cas_n (cas_n),
		.sdram_we_n  (we_n),
		.sdram_ba    (ba),
		.sdram_a     (a),
		.sdram_dq_out(dq_out),
		.sdram_dq_oe (dq_oe),
		.sdram_dq_in (chip_valid ? chip_dq : 16'hffff)
	);
	sdram_model chip (
		.clk         (!clk),
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

	always @(posedge clk) begin
		cycles <= cycles + 1;
		if (chip_errors != 0) $fatal(1, "SDRAM protocol error in phase %0d", phase);
		if (cycles > 2000000) $fatal(1, "timeout phase=%0d PC=%04x", phase, pc);
		if (cpu_enable && !cpu_rwn && !dut.machine_reset) begin
			if (cpu_addr == 16'h0201) phase <= int'(cpu_dout);
			if (cpu_addr == 16'h0200) begin
				if (cpu_dout != 8'h5a)
					$fatal(
						1,
						"memory-map diagnostic failed in phase %0d; last opcodes %04x %04x %04x %04x %04x %04x %04x %04x",
						phase,
						history[0],
						history[1],
						history[2],
						history[3],
						history[4],
						history[5],
						history[6],
						history[7]
					);
				if (!ram_512k || phase != 19) $fatal(1, "diagnostic ended in phase %0d", phase);
				$display(
					"PASS real CPU memory map: pairs, $8F/$87, absent banks, stacks, latch timing, zero-page decode, 128K, 512K in SDRAM (%0d clocks)",
					cycles);
				$finish;
			end
			// The memory board is changed with the power off.
			if (cpu_addr == 16'h0203) begin
				swap       <= 1;
				next_board <= cpu_dout;
			end
		end
	end
	logic swap = 0;
	initial begin
		repeat (100) @(negedge clk);
		reset = 0;
		repeat (2) begin
			wait (swap);
			ram_128k = (next_board == 8'ha8);
			ram_512k = (next_board == 8'ha5);
			reset    = 1;
			@(negedge clk);
			swap = 0;
			repeat (100) @(negedge clk);
			reset = 0;
		end
	end
endmodule
