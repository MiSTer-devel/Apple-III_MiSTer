// Apple /// machine and peripheral integration for MiSTer.

module apple3_system (
	// Clock and machine options.
	input  wire       clk_sys,
	input  wire       reset_core,
	input  wire       sdram_init,
	output wire       sdram_ready,
	input  wire       plus_model,
	input  wire [1:0] memory_board,
	input  wire       sdram_present,
	input  wire       soshdboot,
	input  wire       interlace,
	input  wire       euro,

	// Keyboard, mouse, joysticks and host clock.
	input wire [10:0] ps2_key,
	input wire [24:0] ps2_mouse,
	input wire [ 1:0] mouse_speed,
	input wire [ 5:0] joystick_0,
	input wire [ 5:0] joystick_1,
	input wire [15:0] joystick_analog_0,
	input wire [15:0] joystick_analog_1,
	input wire        port_b,
	input wire [64:0] host_rtc,

	// Serial port and ROM download.
	input  wire        serial_rx,
	input  wire        serial_cts_n,
	input  wire        serial_dsr_n,
	input  wire        serial_dcd_n,
	output wire        serial_tx,
	output wire        serial_rts_n,
	output wire        serial_dtr_n,
	input  wire        rom_write,
	input  wire [12:0] rom_addr,
	input  wire [ 7:0] rom_data,

	// Card selection and disk images.
	input  wire [ 3:0][2:0] slot_config,
	input  wire [ 3:0]      disk_protect,
	output wire             mouse_chosen,
	output wire             block_chosen,
	output wire             profile_1_chosen,
	output wire             profile_2_chosen,
	input  wire [ 7:0]      img_mounted,
	input  wire             img_readonly,
	input  wire [63:0]      img_size,
	output wire [31:0]      sd_lba          [8],
	output wire [ 5:0]      sd_blk_cnt      [8],
	output wire [ 7:0]      sd_rd,
	output wire [ 7:0]      sd_wr,
	input  wire [ 7:0]      sd_ack,
	input  wire [13:0]      sd_buff_addr,
	input  wire [ 7:0]      sd_buff_dout,
	output wire [ 7:0]      sd_buff_din     [8],
	input  wire             sd_buff_wr,
	output wire             activity,

	// SDRAM pins.
	output wire        sdram_clk,
	output wire [12:0] sdram_a,
	output wire [ 1:0] sdram_ba,
	inout  wire [15:0] sdram_dq,
	output wire        sdram_cke,
	output wire        sdram_dqml,
	output wire        sdram_dqmh,
	output wire        sdram_cs_n,
	output wire        sdram_cas_n,
	output wire        sdram_ras_n,
	output wire        sdram_we_n,

	// Raw video, frame boundary and audio.
	output wire        [ 7:0] core_r,
	output wire        [ 7:0] core_g,
	output wire        [ 7:0] core_b,
	output wire               video_hblank,
	output wire               video_hsync,
	output wire               video_vblank,
	output wire               video_vsync,
	output wire               hvcnt_atzero,
	output wire               core_field,
	output wire        [ 3:0] core_colour,
	output wire        [ 1:0] core_colour_phase,
	output wire               core_colour_burst,
	output wire signed [15:0] core_audio
);

	function automatic [7:0] controller_axis(input logic [7:0] analog_value, input logic negative,
											 input logic positive);
		if (negative) controller_axis = 8'h00;
		else if (positive) controller_axis = 8'hff;
		else controller_axis = analog_value ^ 8'h80;
	endfunction

	wire [7:0] stick_x[2], stick_y[2];
	assign stick_x[0] = controller_axis(joystick_analog_0[7:0], joystick_0[1], joystick_0[0]);
	assign stick_y[0] = ~controller_axis(joystick_analog_0[15:8], joystick_0[3], joystick_0[2]);
	assign stick_x[1] = controller_axis(joystick_analog_1[7:0], joystick_1[1], joystick_1[0]);
	assign stick_y[1] = ~controller_axis(joystick_analog_1[15:8], joystick_1[3], joystick_1[2]);
	wire  [1:0] stick_button = {joystick_1[4], joystick_0[4]};
	wire  [1:0] switch_button = {joystick_1[5], joystick_0[5]};
	// Joystick switches keep their state through machine reset.
	logic [1:0] switch_button_q = 2'b00;
	logic [1:0] stick_switch = 2'b00;
	always_ff @(posedge clk_sys) begin
		switch_button_q <= switch_button;
		stick_switch    <= stick_switch ^ (switch_button & ~switch_button_q);
	end

	wire ram_512k = (memory_board == 2'd2) && sdram_present;

	wire ext_ram_cycle, ext_ram_select, ext_ram_write, ext_ram_lane;
	wire [16:0] ext_ram_addr;
	wire [ 7:0] ext_ram_din;
	wire [15:0] ext_ram_q;
	wire [15:0] sdram_dq_out;
	wire        sdram_dq_oe;
	apple3_sdram sdram (
		.clk         (clk_sys),
		.init        (sdram_init),
		.ready       (sdram_ready),
		.cycle       (ext_ram_cycle),
		.select      (ext_ram_select),
		.addr        ({7'd0, ext_ram_addr}),
		.we          (ext_ram_write),
		.lane        (ext_ram_lane),
		.din         (ext_ram_din),
		.q           (ext_ram_q),
		.sdram_cke   (sdram_cke),
		.sdram_cs_n  (sdram_cs_n),
		.sdram_ras_n (sdram_ras_n),
		.sdram_cas_n (sdram_cas_n),
		.sdram_we_n  (sdram_we_n),
		.sdram_ba    (sdram_ba),
		.sdram_a     (sdram_a),
		.sdram_dq_out(sdram_dq_out),
		.sdram_dq_oe (sdram_dq_oe),
		.sdram_dq_in (sdram_dq)
	);

	assign {sdram_dqmh, sdram_dqml} = sdram_a[12:11];
	assign sdram_dq                 = sdram_dq_oe ? sdram_dq_out : 16'hzzzz;

	altddio_out #(
		.extend_oe_disable     ("OFF"),
		.intended_device_family("Cyclone V"),
		.invert_output         ("OFF"),
		.lpm_hint              ("UNUSED"),
		.lpm_type              ("altddio_out"),
		.oe_reg                ("UNREGISTERED"),
		.power_up_high         ("OFF"),
		.width                 (1)
	) sdram_clock (
		.datain_h  (1'b0),
		.datain_l  (1'b1),
		.outclock  (clk_sys),
		.dataout   (sdram_clk),
		.aclr      (1'b0),
		.aset      (1'b0),
		.oe        (1'b1),
		.outclocken(1'b1),
		.sclr      (1'b0),
		.sset      (1'b0)
	);

	wire [3:0] disk_ready, disk_write_protect, disk_flux, disk_motors, disk_active;
	wire [3:0] disk_phases;
	wire disk_write_mode, disk_write_bit, disk_write_strobe;
	wire disk_activity;

	genvar drive;
	generate
		for (drive = 0; drive < 4; drive = drive + 1) begin : woz_drives
			apple3_woz_drive woz (
				.clk           (clk_sys),
				.reset         (reset_core),
				.change        (img_mounted[drive]),
				.enabled       (1'b1),
				.image_size    (img_size),
				.image_readonly(img_readonly),
				.protect       (disk_protect[drive]),
				.active        (disk_active[drive]),
				.motor_on      (disk_motors[drive]),
				.phases        (disk_phases),
				.write_mode    (disk_write_mode),
				.write_bit     (disk_write_bit),
				.write_strobe  (disk_write_strobe),
				.flux          (disk_flux[drive]),
				.ready         (disk_ready[drive]),
				.write_protect (disk_write_protect[drive]),
				.sd_lba        (sd_lba[drive]),
				.sd_blk_cnt    (sd_blk_cnt[drive]),
				.sd_rd         (sd_rd[drive]),
				.sd_wr         (sd_wr[drive]),
				.sd_ack        (sd_ack[drive]),
				.sd_buff_addr,
				.sd_buff_dout,
				.sd_buff_din   (sd_buff_din[drive]),
				.sd_buff_wr
			);
		end
	endgenerate

	function automatic [2:0] slot_card(input [2:0] value, input [2:0] shipped);
		logic [3:0] sum;
		sum       = value + shipped;
		slot_card = (sum >= 4'd5) ? 3'(sum - 4'd5) : sum[2:0];
	endfunction
	wire [3:0][2:0] slot_cards = {
		slot_card(slot_config[3], 3'd2),
		slot_card(slot_config[2], 3'd0),
		slot_card(slot_config[1], 3'd0),
		slot_card(slot_config[0], 3'd1)
	};

	function automatic chosen(input [3:0][2:0] cards, input [2:0] card);
		chosen = (cards[0] == card) || (cards[1] == card) || (cards[2] == card) || (cards[3] == card);
	endfunction
	assign block_chosen     = chosen(slot_cards, 3'd1);
	assign profile_1_chosen = chosen(slot_cards, 3'd2);
	assign profile_2_chosen = chosen(slot_cards, 3'd3);
	assign mouse_chosen     = chosen(slot_cards, 3'd4);

	wire [15:0] slot_addr;

	wire [3:0][7:0] slot_data_in;
	wire [3:0] slot_device_select, slot_io_select, slot_data_oe, slot_irq_n, slot_ready;
	wire [3:0] slot_dma_req, slot_dma_write;
	wire [7:0] slot_data_out;
	wire slot_cpu_read, slot_cycle, slot_reset, slot_rom_deselect, slot_dma_ok;
	wire [7:0]       slot_dma_data;
	wire             card_activity;
	wire [3:0][31:0] hd_lba;
	wire [3:0][ 7:0] hd_din;

	apple3_cards cards (
		.clk           (clk_sys),
		.reset         (slot_reset),
		.cycle         (slot_cycle),
		.slot_card     (slot_cards),
		.addr          (slot_addr[7:0]),
		.cpu_read      (slot_cpu_read),
		.data_in       (slot_data_out),
		.device_select (slot_device_select),
		.io_select     (slot_io_select),
		.rom_deselect  (slot_rom_deselect),
		.dma_ok        (slot_dma_ok),
		.dma_data      (slot_dma_data),
		.data_out      (slot_data_in),
		.data_oe       (slot_data_oe),
		.irq_n         (slot_irq_n),
		.ready         (slot_ready),
		.dma_req       (slot_dma_req),
		.dma_write     (slot_dma_write),
		.activity      (card_activity),
		.ps2_mouse     (ps2_mouse),
		.mouse_speed   (mouse_speed),
		.image_change  (img_mounted[7:4]),
		.image_size    (img_size),
		.image_readonly(img_readonly),
		.sd_lba        (hd_lba),
		.sd_rd         (sd_rd[7:4]),
		.sd_wr         (sd_wr[7:4]),
		.sd_ack        (sd_ack[7:4]),
		.sd_buff_addr  (sd_buff_addr[8:0]),
		.sd_buff_dout,
		.sd_buff_din   (hd_din),
		.sd_buff_wr
	);
	generate
		for (drive = 4; drive < 8; drive = drive + 1) begin : hard_disks
			assign sd_lba[drive]      = hd_lba[drive-4];
			assign sd_blk_cnt[drive]  = 6'd0;
			assign sd_buff_din[drive] = hd_din[drive-4];
		end
	endgenerate

	apple3_core machine (
		.clk_14m(clk_sys),
		.reset  (reset_core),
		.ps2_key(ps2_key),

		.plus_keymap   (plus_model),
		.ram_128k      (memory_board == 2'd1),
		.ram_512k      (ram_512k),
		.soshdboot     (soshdboot),
		.interlace     (interlace),
		.euro          (euro),
		.ext_ram_cycle (ext_ram_cycle),
		.ext_ram_select(ext_ram_select),
		.ext_ram_addr  (ext_ram_addr),
		.ext_ram_write (ext_ram_write),
		.ext_ram_lane  (ext_ram_lane),
		.ext_ram_din   (ext_ram_din),
		.ext_ram_q     (ext_ram_q),
		.serial_rx     (serial_rx),

		.serial_cts_n(serial_cts_n),
		.serial_dsr_n(serial_dsr_n),

		.serial_dcd_n      (serial_dcd_n),
		.serial_tx         (serial_tx),
		.serial_rts_n      (serial_rts_n),
		.serial_dtr_n      (serial_dtr_n),
		.host_rtc          (host_rtc),
		.joy_a_x           (stick_x[!port_b]),
		.joy_a_y           (stick_y[!port_b]),
		.joy_b_x           (stick_x[port_b]),
		.joy_b_y           (stick_y[port_b]),
		.joy_a_button      (stick_button[!port_b]),
		.joy_a_switch      (stick_switch[!port_b]),
		.joy_b_button      (stick_button[port_b]),
		.joy_b_switch      (stick_switch[port_b]),
		.slot_data_in      (slot_data_in),
		.slot_data_oe      (slot_data_oe),
		.slot_irq_n        (slot_irq_n),
		.slot_nmi_n        (4'b1111),
		.slot_ready        (slot_ready),
		.slot_addr         (slot_addr),
		.slot_data_out     (slot_data_out),
		.slot_cpu_read     (slot_cpu_read),
		.slot_cycle        (slot_cycle),
		.slot_reset        (slot_reset),
		.slot_device_select(slot_device_select),
		.slot_io_select    (slot_io_select),
		.slot_io_strobe    (),
		.slot_rom_deselect (slot_rom_deselect),
		.slot_bus_conflict (),
		.slot_dma_ok       (slot_dma_ok),
		.slot_dma_req      (slot_dma_req),
		.slot_dma_write    (slot_dma_write),
		.slot_dma_data     (slot_dma_data),
		.rom_we            (rom_write),
		.rom_host_addr     (rom_addr),
		.rom_host_data     (rom_data),
		.disk_ready        (disk_ready),
		.disk_write_protect(disk_write_protect),
		.disk_flux,
		.disk_media_change (img_mounted[3:0]),
		.disk_motors,
		.disk_phases,
		.disk_write_mode,
		.disk_write_bit,
		.disk_write_strobe,
		.video_r           (core_r),
		.video_g           (core_g),
		.video_b           (core_b),
		.video_hblank      (video_hblank),
		.video_vblank      (video_vblank),
		.video_hsync       (video_hsync),
		.video_vsync       (video_vsync),
		.hvcnt_atzero      (hvcnt_atzero),
		.video_field       (core_field),
		.video_colour      (core_colour),
		.video_colour_phase(core_colour_phase),
		.video_colour_burst(core_colour_burst),
		.audio             (core_audio),
		.disk_activity     (disk_activity),
		.disk_active
	);

	assign activity = disk_activity || card_activity;

endmodule
