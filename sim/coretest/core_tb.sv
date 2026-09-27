module core_tb #(
	parameter ROM_FILE = "sim/gen/apple3.rom.hex"
) (
	input  logic              clk,
	input  logic              reset,
	input  logic              serial_rx,
	input  logic              serial_cts_n,
	input  logic              serial_dsr_n,
	input  logic              serial_dcd_n,
	output wire               serial_tx,
	output wire               serial_rts_n,
	output wire               serial_dtr_n,
	input  logic       [10:0] ps2_key,
	// The card in each slot, three bits each from slot 1 up, in apple3_cards'
	// codes (--slotN), and MiSTer's mouse report for the mouse card.
	input  logic       [11:0] slot_cards,
	input  logic       [24:0] ps2_mouse,
	input  logic              plus_keymap,
	input  logic              ram_128k,
	// The ON THREE 512K board: banks 7-14 in the SDRAM model (--ram512k).
	input  logic              ram_512k,
	// The OSD's Boot ROM option: Rob Justice's soshdboot ROM.
	input  logic              soshdboot,
	// The Apple /// Plus text interlace switch, and the field it is showing.
	input  logic              interlace,
	// A Euro system's 50 Hz scan PROM.
	input  logic              euro,
	output wire               field,
	// The OSD's Video option: 0 RGB, 1 colour composite, 2 mono composite,
	// and its Display option for the composite ones: 0 RGB Monitor,
	// 1 Monitor /// Green, 2 Amber, 3 Color TV.
	input  logic       [ 1:0] video_source,
	input  logic       [ 1:0] video_monitor,
	input  logic       [64:0] host_rtc,
	input  logic       [ 7:0] joy_a_x,
	input  logic       [ 7:0] joy_a_y,
	input  logic       [ 7:0] joy_b_x,
	input  logic       [ 7:0] joy_b_y,
	input  logic              joy_a_button,
	input  logic              joy_a_switch,
	input  logic              joy_b_button,
	input  logic              joy_b_switch,
	input  logic       [17:0] probe_addr,
	output logic       [15:0] probe_word,
	input  logic       [ 9:0] probe_font_addr,
	output logic       [ 7:0] probe_font,
	// Images 0-3 are the Disk III drives, 4 and 5 the block card's disks and
	// 6 and 7 the ProFile cards'.
	input  logic       [ 7:0] image_change,
	input  logic       [63:0] image_size,
	input  logic              image_readonly,
	output wire        [31:0] sd_lba         [8],
	output wire        [ 5:0] sd_blk_cnt     [8],
	output wire        [ 7:0] sd_rd,
	sd_wr,
	input  logic       [ 7:0] sd_ack,
	input  logic       [13:0] sd_buff_addr,
	input  logic       [ 7:0] sd_buff_dout,
	output wire        [ 7:0] sd_buff_din    [8],
	input  logic              sd_buff_wr,
	output wire               card_activity,
	// Rendered picture for --frame-out.
	output wire        [ 7:0] frame_r,
	frame_g,
	frame_b,
	output wire               frame_hblank,
	// Drive 1's write-protect terms for --wp-trace: host read-only, WOZ INFO
	// flag, not ready, flux track, and no track data.
	output wire        [ 4:0] wp_terms1,
	output logic       [15:0] cpu_addr,
	output logic       [15:0] pc,
	output logic       [ 7:0] environment,
	output logic       [ 7:0] zero_page,
	output logic       [ 7:0] bank,
	output logic       [ 3:0] video_mode,
	output logic              cpu_enable,
	output logic              cpu_sync,
	output logic              cpu_rwn,
	output logic       [ 7:0] cpu_din,
	output logic       [ 7:0] cpu_dout,
	output logic       [ 7:0] e_pa_o,
	output logic       [ 7:0] e_pa_ddr,
	output logic       [ 7:0] a,
	output logic       [ 7:0] x,
	output logic       [ 7:0] y,
	output logic       [ 7:0] sp,
	output logic       [ 7:0] p,
	output logic       [18:0] ram_byte_addr,
	output logic              ram_write,
	output logic              vblank,
	output logic              disk_activity,
	output logic       [ 5:0] track1,
	output logic       [12:0] track1_addr,
	output logic       [ 7:0] qtrack1,
	output logic              valid1,
	output logic              write_mode1,
	// The core's audio output for --audio-out.
	output wire signed [15:0] audio
);

	wire [7:0] video_r, video_g, video_b;
	wire [3:0] video_colour;
	wire [1:0] video_colour_phase;
	wire       video_colour_burst;
	wire hblank, hsync, vsync;
	wire [3:0] disk_active, disk_motors, disk_ready, disk_wp, disk_flux;
	wire [3:0] disk_phases;
	wire disk_write_mode, disk_write_bit, disk_write_strobe;
	for (genvar i = 0; i < 4; i++) begin : drives
		apple3_woz_drive woz (
			.clk,
			.reset,
			.change       (image_change[i]),
			.enabled      (1'b1),
			.image_size,
			.image_readonly,
			.protect      (1'b0),
			.active       (disk_active[i]),
			.motor_on     (disk_motors[i]),
			.phases       (disk_phases),
			.write_mode   (disk_write_mode),
			.write_bit    (disk_write_bit),
			.write_strobe (disk_write_strobe),
			.flux         (disk_flux[i]),
			.ready        (disk_ready[i]),
			.write_protect(disk_wp[i]),
			.sd_lba       (sd_lba[i]),
			.sd_blk_cnt   (sd_blk_cnt[i]),
			.sd_rd        (sd_rd[i]),
			.sd_wr        (sd_wr[i]),
			.sd_ack       (sd_ack[i]),
			.sd_buff_addr,
			.sd_buff_dout,
			.sd_buff_din  (sd_buff_din[i]),
			.sd_buff_wr
		);
	end
	assign wp_terms1 = {
		drives[0].woz.readonly,
		drives[0].woz.info_wp,
		!drives[0].woz.ready,
		drives[0].woz.is_flux,
		drives[0].woz.bit_count == 0
	};
	apple3_composite monitor (
		.clk         (clk),
		.source      (video_source),
		.monitor     (video_monitor),
		.colour      (video_colour),
		.colour_phase(video_colour_phase),
		.colour_burst(video_colour_burst),
		.rgb_in      ({video_r, video_g, video_b}),
		.hblank_in   (hblank),
		.vblank_in   (vblank),
		.hsync_in    (hsync),
		.vsync_in    (vsync),
		.red         (frame_r),
		.green       (frame_g),
		.blue        (frame_b),
		.hblank      (frame_hblank),
		.vblank      (),
		.hsync       (),
		.vsync       ()
	);
	assign track1      = drives[0].woz.track_id[7:2];
	assign track1_addr = drives[0].woz.bit_addr[12:0];
	assign qtrack1     = drives[0].woz.track_id;
	assign write_mode1 = disk_write_mode && disk_active[0];
	assign valid1      = drives[0].woz.valid && drives[0].woz.ready && (drives[0].woz.bit_count != 0);

	// The card cage, as in the MiSTer top.
	wire [15:0]      slot_addr;
	wire [ 3:0][7:0] slot_data_in;
	wire [3:0] slot_device_select, slot_io_select, slot_data_oe, slot_irq_n, slot_ready;
	wire [3:0] slot_dma_req, slot_dma_write;
	wire [7:0] slot_data_out, slot_dma_data;
	wire slot_cpu_read, slot_cycle, slot_reset, slot_rom_deselect, slot_dma_ok;
	wire [3:0][31:0] hd_lba;
	wire [3:0][ 7:0] hd_din;
	apple3_cards cards (
		.clk,
		.reset        (slot_reset),
		.cycle        (slot_cycle),
		.slot_card    (slot_cards),
		.addr         (slot_addr[7:0]),
		.cpu_read     (slot_cpu_read),
		.data_in      (slot_data_out),
		.device_select(slot_device_select),
		.io_select    (slot_io_select),
		.rom_deselect (slot_rom_deselect),
		.dma_ok       (slot_dma_ok),
		.dma_data     (slot_dma_data),
		.data_out     (slot_data_in),
		.data_oe      (slot_data_oe),
		.irq_n        (slot_irq_n),
		.ready        (slot_ready),
		.dma_req      (slot_dma_req),
		.dma_write    (slot_dma_write),
		.activity     (card_activity),
		.ps2_mouse,
		.mouse_speed  (2'd3),
		.image_change (image_change[7:4]),
		.image_size,
		.image_readonly,
		.sd_lba       (hd_lba),
		.sd_rd        (sd_rd[7:4]),
		.sd_wr        (sd_wr[7:4]),
		.sd_ack       (sd_ack[7:4]),
		.sd_buff_addr (sd_buff_addr[8:0]),
		.sd_buff_dout,
		.sd_buff_din  (hd_din),
		.sd_buff_wr
	);
	for (genvar i = 4; i < 8; i++) begin : hard_disks
		assign sd_lba[i]      = hd_lba[i-4];
		assign sd_blk_cnt[i]  = 6'd0;
		assign sd_buff_din[i] = hd_din[i-4];
	end

	// External memory as on the MiSTer: apple3_sdram and a chip on the
	// inverted clock, which checks the controller's timing.
	wire ext_ram_cycle, ext_ram_select, ext_ram_write, ext_ram_lane;
	wire [16:0] ext_ram_addr;
	wire [ 7:0] ext_ram_din;
	wire [15:0] ext_ram_q;
	wire sdram_ready, sdram_cke, sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n, sdram_dq_oe, chip_dq_valid;
	wire [ 1:0] sdram_ba;
	wire [12:0] sdram_a;
	wire [15:0] sdram_dq_out, chip_dq;
	integer chip_errors, chip_refreshes;
	logic sdram_init = 1'b1;
	always @(posedge clk) sdram_init <= 1'b0;
	apple3_sdram sdram (
		.clk,
		.init       (sdram_init),
		.ready      (sdram_ready),
		.cycle      (ext_ram_cycle),
		.select     (ext_ram_select),
		.addr       ({7'd0, ext_ram_addr}),
		.we         (ext_ram_write),
		.lane       (ext_ram_lane),
		.din        (ext_ram_din),
		.q          (ext_ram_q),
		.sdram_cke,
		.sdram_cs_n,
		.sdram_ras_n,
		.sdram_cas_n,
		.sdram_we_n,
		.sdram_ba,
		.sdram_a,
		.sdram_dq_out,
		.sdram_dq_oe,
		.sdram_dq_in(chip_dq_valid ? chip_dq : 16'hffff)
	);
	sdram_model chip (
		.clk         (!clk),
		.cke         (sdram_cke),
		.cs_n        (sdram_cs_n),
		.ras_n       (sdram_ras_n),
		.cas_n       (sdram_cas_n),
		.we_n        (sdram_we_n),
		.ba          (sdram_ba),
		.a           (sdram_a),
		.dqm         (sdram_a[12:11]),  // wired as on a MiSTer module
		.dq_in       (sdram_dq_out),
		.dq_in_valid (sdram_dq_oe),
		.dq_out      (chip_dq),
		.dq_out_valid(chip_dq_valid),
		.errors      (chip_errors),
		.refreshes   (chip_refreshes)
	);
	always @(posedge clk) if (chip_errors != 0) $fatal(1, "SDRAM model: protocol error");
	integer ext_reads = 0, ext_writes = 0;
	always @(posedge clk)
		if (ext_ram_cycle && ext_request[19] && ram_512k && !dut.machine_reset) begin
			if (ext_request[1]) ext_writes <= ext_writes + 1;
			else ext_reads <= ext_reads + 1;
		end
	final
		if (ram_512k)
			$display(
				"512K: %0d reads and %0d writes of banks 7-14 in SDRAM, %0d refreshes",
				ext_reads,
				ext_writes,
				chip_refreshes
			);

	// The external-memory contract of apple3_core: a request holds from the
	// clock after ext_ram_cycle to the next one, its byte from the clock
	// after that, and cycles are seven or more clocks apart.
	logic          ext_start = 1'b0;
	logic   [19:0] ext_request;
	logic   [ 7:0] ext_byte;
	integer        ext_age = 0;
	always @(posedge clk) begin
		ext_start <= ext_ram_cycle;
		// ext_age counts from 1 in the second clock of a cycle.
		if (ext_ram_cycle && ext_age + 1 < 7 && !dut.machine_reset && ram_512k)
			$fatal(1, "CPU cycle of %0d clocks", ext_age + 1);
		if (ext_start) begin
			ext_request <= {ext_ram_select, ext_ram_addr, ext_ram_write, ext_ram_lane};
			ext_age     <= 1;
		end else begin
			ext_age <= ext_age + 1;
			if (ext_age == 1) ext_byte <= ext_ram_din;
			if (ram_512k && !dut.machine_reset && ext_request[19]) begin
				if ({ext_ram_select, ext_ram_addr, ext_ram_write, ext_ram_lane} != ext_request)
					$fatal(1, "external RAM request changed %0d clocks into a cycle, PC %04x", ext_age, pc);
				if (ext_age > 1 && ext_request[1] && ext_ram_din != ext_byte)
					$fatal(1, "external RAM write byte changed %0d clocks into a cycle, PC %04x", ext_age, pc);
			end
		end
	end

	apple3_core #(
		.ROM_INIT_FILE (ROM_FILE),
		.ROM_INIT_START(4096)
	) dut (
		.clk_14m            (clk),
		.reset              (reset || !sdram_ready),
		.ps2_key            (ps2_key),
		.plus_keymap        (plus_keymap),
		.ram_128k           (ram_128k),
		.ram_512k           (ram_512k),
		.soshdboot          (soshdboot),
		.interlace,
		.euro,
		.host_rtc,
		.ext_ram_cycle,
		.ext_ram_select,
		.ext_ram_addr,
		.ext_ram_write,
		.ext_ram_lane,
		.ext_ram_din,
		.ext_ram_q,
		.serial_rx,
		.serial_cts_n,
		.serial_dsr_n,
		.serial_dcd_n,
		.serial_tx,
		.serial_rts_n,
		.serial_dtr_n,
		.joy_a_x,
		.joy_a_y,
		.joy_b_x,
		.joy_b_y,
		.joy_a_button,
		.joy_a_switch,
		.joy_b_button,
		.joy_b_switch,
		.slot_data_in       (slot_data_in),
		.slot_data_oe       (slot_data_oe),
		.slot_irq_n         (slot_irq_n),
		.slot_nmi_n         (4'b1111),
		.slot_ready         (slot_ready),
		.slot_addr          (slot_addr),
		.slot_data_out      (slot_data_out),
		.slot_cpu_read      (slot_cpu_read),
		.slot_cycle         (slot_cycle),
		.slot_reset         (slot_reset),
		.slot_device_select (slot_device_select),
		.slot_io_select     (slot_io_select),
		.slot_io_strobe     (),
		.slot_rom_deselect  (slot_rom_deselect),
		.slot_bus_conflict  (),
		.slot_dma_ok        (slot_dma_ok),
		.slot_dma_req       (slot_dma_req),
		.slot_dma_write     (slot_dma_write),
		.slot_dma_data      (slot_dma_data),
		.rom_we             (1'b0),
		.rom_host_addr      (13'd0),
		.rom_host_data      (8'd0),
		.disk_ready         (disk_ready),
		.disk_write_protect (disk_wp),
		.disk_flux,
		.disk_media_change  (image_change[3:0]),
		.disk_motors,
		.disk_phases,
		.disk_write_mode,
		.disk_write_bit,
		.disk_write_strobe,
		.video_r,
		.video_g,
		.video_b,
		.video_hblank       (hblank),
		.video_vblank       (vblank),
		.video_hsync        (hsync),
		.video_vsync        (vsync),
		.video_field        (field),
		.video_colour,
		.video_colour_phase,
		.video_colour_burst,
		.audio,
		.disk_activity,
		.disk_active,
		.debug_pc           (pc),
		.debug_cpu_addr     (cpu_addr),
		.debug_environment  (environment),
		.debug_zero_page    (zero_page),
		.debug_bank         (bank),
		.debug_video_mode   (video_mode),
		.debug_cpu_enable   (cpu_enable),
		.debug_cpu_sync     (cpu_sync),
		.debug_cpu_rwn      (cpu_rwn),
		.debug_cpu_din      (cpu_din),
		.debug_cpu_dout     (cpu_dout),
		.debug_e_pa_o       (e_pa_o),
		.debug_e_pa_ddr     (e_pa_ddr),
		.debug_a            (a),
		.debug_x            (x),
		.debug_y            (y),
		.debug_sp           (sp),
		.debug_p            (p),
		.debug_ram_byte_addr(ram_byte_addr),
		.debug_ram_write    (ram_write)
	);

	// Simulation probe into the sister-byte RAM so the harness can decode the
	// text page after injecting keystrokes, and into the character generator so
	// it can compare the downloaded font with the set SOS keeps at $0C00.
	assign probe_word = dut.ram.mem[probe_addr];
	assign probe_font = dut.video.character_ram[probe_font_addr];

endmodule
