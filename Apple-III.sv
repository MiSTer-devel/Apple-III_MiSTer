//============================================================================
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;  

assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;

assign AUDIO_MIX = 0;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[122:121];

`include "build_id.v" 
localparam CONF_STR = {
	"Apple-III;UART19200:9600:4800:2400:1200:600:300:150:110:75:50;",
	"-;",
	"S0,WOZDSKDO PO NIB2MG,Mount Drive 1;",
	"S1,WOZDSKDO PO NIB2MG,Mount Drive 2;",
	"S2,WOZDSKDO PO NIB2MG,Mount Drive 3;",
	"S3,WOZDSKDO PO NIB2MG,Mount Drive 4;",
	"O6,Write Protect 1,Off,On;",
	"O7,Write Protect 2,Off,On;",
	"OB,Write Protect 3,Off,On;",
	"OC,Write Protect 4,Off,On;",
	"-;",
	"h5S6,PO HDV2MG,ProFile Disk 1;",
	"h6S7,PO HDV2MG,ProFile Disk 2;",
	"h4S4,PO HDV2MG,Block Disk 1;",
	"h4S5,PO HDV2MG,Block Disk 2;",
	"-;",
	"O8,Model,Apple ///,/// Plus;",
	"h0OF,Text Interlace,Off,On;",
	"ODE,Video,RGB,Color Composite,Mono Composite;",
	"H1OGH,Display,RGB Monitor,Monitor /// Green,Amber,Color TV;",
	"-;",
	"P1,System & ROM;",
	"P1-;",
	"h7P1O[31:30],Memory,256K,128K,512K;",
	"H7P1O[31:30],Memory,256K,128K;",
	"P1OJ,Video Standard,NTSC,PAL;",
	"P1-;",
	"P1O[26],Boot ROM,Apple,soshdboot;",
	"P1F2,ROMBIN,Load Boot ROM;",
	"P2,Scaling & Filters;",
	"P2-;",
	"P2O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"P2O[21:20],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"P2-;",
	"P2O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"h2P2O[22],Deinterlacing,Weave,Bob;",
	"P3,Hardware;",
	"P3-;",
	"P3O[34:32],Slot 1,Block Card,ProFile 1,ProFile 2,Mouse Card,Empty;",
	"P3O[37:35],Slot 2,Empty,Block Card,ProFile 1,ProFile 2,Mouse Card;",
	"P3O[40:38],Slot 3,Empty,Block Card,ProFile 1,ProFile 2,Mouse Card;",
	"P3O[43:41],Slot 4,ProFile 1,ProFile 2,Mouse Card,Empty,Block Card;",
	"h3P3O[25:24],Mouse Speed,Normal,Fast,Faster,Fastest;",
	"P3-;",
	"P3OA,Joystick 1 on,Port B,Port A;",
	"P3O9,Serial CTS,Always ready,Host RTS;",
	"P3O[29],Serial DSR,Always ready,Host DTR;",
	"P3O[28:27],Serial DCD,Always on,Host DTR,Off;",
	"-;",
	"R0,Reset;",
	"J,Button,Switch;",
	"jn,A,B;",
	"jp,Y,B;",
	"v,0;", // [optional] config version 0-99. 
	        // If CONF_STR options are changed in incompatible way, then change version number too,
			  // so all options will get default values on first start.
	"V,v",`BUILD_DATE 
};

wire forced_scandoubler;
wire   [1:0] buttons;
wire [127:0] status;
wire  [10:0] ps2_key;

hps_io #(.CONF_STR(CONF_STR), .VDNUM(8)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(ext_bus),
	.gamma_bus(gamma_bus),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	.status_menumask({8'd0, sdram_present, profile_2_chosen, profile_1_chosen, block_chosen, mouse_chosen, interlace, !composite_source, plus_model && !euro}),
	
	.ps2_key(ps2_key),

	.video_rotated(1'b0),
	.new_vmode(euro),
	.status_in(status),
	.status_set(1'b0),
	.info_req(1'b0),
	.info(8'd0),
	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.joystick_l_analog_0(joystick_analog_0),
	.joystick_l_analog_1(joystick_analog_1),
	.joystick_0_rumble(16'd0),
	.joystick_1_rumble(16'd0),
	.joystick_2_rumble(16'd0),
	.joystick_3_rumble(16'd0),
	.joystick_4_rumble(16'd0),
	.joystick_5_rumble(16'd0),
	.ps2_mouse(ps2_mouse),
	.ps2_kbd_led_status(3'd0),
	.ps2_kbd_led_use(3'd0),
	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),
	.sd_lba(sd_lba),
	.sd_blk_cnt(sd_blk_cnt),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),
	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_upload_req(1'b0),
	.ioctl_upload_index(8'd0),
	.ioctl_din(8'd0),
	.ioctl_wait(1'b0),
	.sdram_sz(sdram_sz),
	.RTC(host_rtc)
);

///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(CLK_VIDEO),
	.outclk_1(clk_sys),
	.locked(pll_locked)
);

wire reset = RESET | status[0] | buttons[1] | !pll_locked | rom_download | !sdram_ready;

wire HBlank;
wire HSync;
wire VBlank;
wire VSync;
wire ce_pix;
wire hvcnt_atzero;

// Leave H/V sync always on. This stabilizes the video output while the core
// is in reset. This example releases the reset when H/V counters are at zero.
reg reset_core = 1;
always @(posedge clk_sys) begin
	if(reset) reset_core <= 1;
	else if(hvcnt_atzero) reset_core <= 0;
end

apple3_system system
(
	.clk_sys(clk_sys),
	.reset_core(reset_core),
	.sdram_init(!pll_locked),
	.sdram_ready(sdram_ready),
	.plus_model(plus_model),
	.memory_board(status[31:30]),
	.sdram_present(sdram_present),
	.soshdboot(status[26]),
	.interlace(interlace),
	.euro(euro),
	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse),
	.mouse_speed(status[25:24]),
	.joystick_0(joystick_0[5:0]),
	.joystick_1(joystick_1[5:0]),
	.joystick_analog_0(joystick_analog_0),
	.joystick_analog_1(joystick_analog_1),
	.port_b(status[10]),
	.host_rtc(host_rtc),
	.serial_rx(UART_RXD),
	.serial_cts_n(status[9] && UART_CTS),
	.serial_dsr_n(status[29] && UART_DSR),
	.serial_dcd_n((status[28:27] == 2'd1) ? UART_DSR : (status[28:27] == 2'd2)),
	.serial_tx(UART_TXD),
	.serial_rts_n(UART_RTS),
	.serial_dtr_n(UART_DTR),
	.rom_write(rom_write),
	.rom_addr(ioctl_addr[12:0]),
	.rom_data(ioctl_dout),
	.slot_config(status[43:32]),
	.disk_protect({status[12:11], status[7:6]}),
	.mouse_chosen(mouse_chosen),
	.block_chosen(block_chosen),
	.profile_1_chosen(profile_1_chosen),
	.profile_2_chosen(profile_2_chosen),
	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),
	.sd_lba(sd_lba),
	.sd_blk_cnt(sd_blk_cnt),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),
	.activity(system_activity),
	.sdram_clk(SDRAM_CLK),
	.sdram_a(SDRAM_A),
	.sdram_ba(SDRAM_BA),
	.sdram_dq(SDRAM_DQ),
	.sdram_cke(SDRAM_CKE),
	.sdram_dqml(SDRAM_DQML),
	.sdram_dqmh(SDRAM_DQMH),
	.sdram_cs_n(SDRAM_nCS),
	.sdram_cas_n(SDRAM_nCAS),
	.sdram_ras_n(SDRAM_nRAS),
	.sdram_we_n(SDRAM_nWE),
	.core_r(core_r),
	.core_g(core_g),
	.core_b(core_b),
	.video_hblank(HBlank),
	.video_hsync(HSync),
	.video_vblank(VBlank),
	.video_vsync(VSync),
	.hvcnt_atzero(hvcnt_atzero),
	.core_field(core_field),
	.core_colour(core_colour),
	.core_colour_phase(core_colour_phase),
	.core_colour_burst(core_colour_burst),
	.core_audio(core_audio)
);

assign AUDIO_S = 1;
assign AUDIO_L = core_audio;
assign AUDIO_R = core_audio;

apple3_composite monitor
(
	.clk(clk_sys),
	.source(video_source),
	.monitor(status[17:16]),
	.colour(core_colour),
	.colour_phase(core_colour_phase),
	.colour_burst(core_colour_burst),
	.rgb_in({core_r, core_g, core_b}),
	.hblank_in(HBlank),
	.vblank_in(VBlank),
	.hsync_in(HSync),
	.vsync_in(VSync),
	.red(core_r_q),
	.green(core_g_q),
	.blue(core_b_q),
	.hblank(core_hblank_q),
	.vblank(core_vblank_q),
	.hsync(core_hsync_q),
	.vsync(core_vsync_q)
);

logic field_q = 1'b0;
always_ff @(posedge clk_sys) field_q <= interlace && !core_field;
assign VGA_F1 = field_q;
assign HDMI_BOB_DEINT = status[22];

video_freak video_freak
(
	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.VGA_VS(VGA_VS && !VGA_F1),
	.HDMI_WIDTH(HDMI_WIDTH),
	.HDMI_HEIGHT(HDMI_HEIGHT),
	.VGA_DE(VGA_DE),
	.VIDEO_ARX(VIDEO_ARX),
	.VIDEO_ARY(VIDEO_ARY),
	.VGA_DE_IN(mixer_de),
	.ARX((ar == 2'd0) ? 12'd4 : {10'd0, ar - 2'd1}),
	.ARY((ar == 2'd0) ? 12'd3 : 12'd0),
	.CROP_SIZE(12'd0),
	.CROP_OFF(5'd0),
	.SCALE({1'b0, status[21:20]})
);

wire [2:0] video_effect = status[5:3];
wire [2:0] scanline_level = video_effect ? video_effect - 1'b1 : 3'd0;
wire use_scandoubler = forced_scandoubler || (video_effect != 0);
assign VGA_SL = scanline_level[1:0];

video_mixer #(.LINE_LENGTH(560), .GAMMA(1)) video_out
(
	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.ce_pix(ce_pix),
	.scandoubler(use_scandoubler),
	.hq2x(video_effect == 3'd1),
	.gamma_bus(gamma_bus),
	.R(core_r_q),
	.G(core_g_q),
	.B(core_b_q),
	.HSync(core_hsync_q),
	.VSync(core_vsync_q),
	.HBlank(core_hblank_q),
	.VBlank(core_vblank_q),
	.HDMI_FREEZE(HDMI_FREEZE),
	.freeze_sync(),
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_VS(VGA_VS),
	.VGA_HS(VGA_HS),
	.VGA_DE(mixer_de)
);

assign LED_USER = system_activity;

wire [21:0] gamma_bus;
wire [31:0] joystick_0;
wire [31:0] joystick_1;
wire [15:0] joystick_analog_0;
wire [15:0] joystick_analog_1;
wire [24:0] ps2_mouse;
wire [64:0] host_rtc;
wire [15:0] sdram_sz;

wire euro = status[19];

wire plus_model = status[8];
wire interlace = plus_model && status[15] && !euro;

wire [1:0] video_source = status[14:13];
wire composite_source = (video_source == 2'd1) || (video_source == 2'd2);

wire [7:0] img_mounted;
wire img_readonly;
wire [63:0] img_size;
wire [31:0] sd_lba [8];
wire [5:0] sd_blk_cnt [8];
wire [7:0] sd_rd;
wire [7:0] sd_wr;
wire [7:0] sd_ack;
wire [13:0] sd_buff_addr;
wire [7:0] sd_buff_dout;
wire [7:0] sd_buff_din [8];
wire sd_buff_wr;

wire mouse_chosen, block_chosen, profile_1_chosen, profile_2_chosen;

wire ioctl_download;
wire [15:0] ioctl_index;
wire ioctl_wr;
wire [26:0] ioctl_addr;
wire [7:0] ioctl_dout;

tri [35:0] ext_bus;
assign ext_bus[32] = 1'b0;

wire pll_locked;
logic [1:0] pixel_divider = 2'd0;
always_ff @(posedge CLK_VIDEO) pixel_divider <= pixel_divider + 1'b1;
assign ce_pix = &pixel_divider;

wire rom_download = ioctl_download && ((ioctl_index == 16'd0) || (ioctl_index[5:0] == 6'd2));
wire rom_write = rom_download && ioctl_wr && (ioctl_addr < 27'd8192);

wire [7:0] core_r_q, core_g_q, core_b_q;
wire core_hblank_q, core_vblank_q, core_hsync_q, core_vsync_q;

wire mixer_de;

wire [7:0] core_r;
wire [7:0] core_g;
wire [7:0] core_b;
wire core_field;
wire [3:0] core_colour;
wire [1:0] core_colour_phase;
wire core_colour_burst;
wire signed [15:0] core_audio;

wire system_activity;
wire sdram_ready;
wire sdram_present = sdram_sz[15] && (sdram_sz[1:0] != 2'd0);

`ifdef MISTER_DUAL_SDRAM
assign {SDRAM2_CLK, SDRAM2_A, SDRAM2_BA, SDRAM2_DQ, SDRAM2_nCS, SDRAM2_nCAS, SDRAM2_nRAS, SDRAM2_nWE} = 'Z;
`endif

endmodule
