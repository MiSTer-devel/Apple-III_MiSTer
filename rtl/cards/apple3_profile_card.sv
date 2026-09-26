// Apple /// ProFile Interface card (schematic 050-5007-A) with a ProFile
// drive behind it, served from one of Main's block images.
//
// The card is four soft switches, a data latch and a status buffer; the
// drive's Z8 controller does the work. Both are modelled at the level
// Apple's .PROFILE driver (SOS 1.3, "ProFile Driver 1.30") and the ProFile
// Level 2 service manual describe (docs/PROFILE.md).
//
// Device select, $C0n0-$C0nF, decoded on R/W and A1-A0 (A3-A2 are ignored):
//   +0 write  WBUF   a byte to the drive; the write strobes it across
//   +1 read   RBUF   a byte from the drive; the read strobes the next one
//   +2 read   RSTAT  bit 7 = 1 drive not busy, bit 6 parity error,
//                    bit 0 = 1 no drive connected
//   +3 write  CLRPE  clear the parity error
// I/O select, $Cn00-$CnFF, is an addressable latch: A3, A1, A0 pick the
// switch and A2 is the value, on a read or a write:
//   0/4 CMD   1/5 CRW   2/6 INTEN   3/7 DATARW   8/C CRES (drive reset)
// Any $Cnxx access also selects the card for pseudo-DMA until a $C02x
// access (the C02X pin) deselects it, which SOS's SELC800 does.
//
// Pseudo-DMA: while selected, the card claims every DMAOK cycle, a CPU
// fetch from the ROM's $F800 block. With DATARW high the drive's next byte
// goes to RAM, with it low the RAM byte goes to the drive; one byte per
// cycle, so the ROM's ladder of SBC/BEQ pairs moves up to a page.
//
// Drive protocol, up to three CMD/BSY handshakes per operation:
//   CMD raised -> BSY, and a response on RBUF: $01 waiting for a command,
//   $02 reading, $03 or $04 ready for write or write/verify data, $06
//   write data received.
//   CMD dropped -> the last byte written to WBUF is the host's answer; $55
//   goes on, anything else aborts to idle.
//   Six command bytes follow the first handshake: command (0 read, 1 write,
//   2 write/verify), the block number high byte first, retries and sparing
//   threshold. A read completes with four status bytes then 512 data bytes
//   on RBUF. A write takes 512 data bytes and tag bytes on WBUF, then the
//   third handshake and four status bytes.
// The status bytes are zero when all went well. A block beyond the drive
// sets bit 0 of the first and bit 6 of the third; a write to a read-only
// image sets bit 0. Block $FFFFFF is the spare table, which names the drive
// and its size; $FFFFFE is the buffer as it stands.
`timescale 1ns / 1ps
module apple3_profile_card (
	input logic clk,
	input logic reset,
	input logic cycle,

	// Slot bus (docs/SLOTS.md); the card has only A0-A3.
	input  logic [3:0] addr,
	input  logic       cpu_read,
	input  logic [7:0] data_in,
	input  logic       device_select,
	input  logic       io_select,
	input  logic       rom_deselect,
	output logic [7:0] data_out,
	output logic       data_oe,
	output logic       activity,

	// Pseudo-DMA: DMAOK in, DMAI and the direction out; dma_data is the RAM
	// byte of a cycle that goes to the drive, data_out carries one to RAM.
	input  logic       dma_ok,
	input  logic [7:0] dma_data,
	output logic       dma_req,
	output logic       dma_write,

	// Host image.
	input  logic        image_change,
	input  logic [63:0] image_size,
	input  logic        image_readonly,
	output logic [31:0] sd_lba,
	output logic        sd_rd,
	output logic        sd_wr,
	input  logic        sd_ack,
	input  logic [ 8:0] sd_buff_addr,
	input  logic [ 7:0] sd_buff_dout,
	output logic [ 7:0] sd_buff_din,
	input  logic        sd_buff_wr
);
	localparam logic [ 7:0] RESPONSE_COMMAND  = 8'h01;
	localparam logic [ 7:0] RESPONSE_READ     = 8'h02;
	localparam logic [ 7:0] RESPONSE_WRITE    = 8'h03;
	localparam logic [ 7:0] RESPONSE_VERIFY   = 8'h04;
	localparam logic [ 7:0] RESPONSE_STATUS   = 8'h06;
	localparam logic [ 7:0] HOST_ACK          = 8'h55;
	localparam logic [ 7:0] STATUS1_FAILED    = 8'h01;
	localparam logic [ 7:0] STATUS3_BAD_BLOCK = 8'h40;
	localparam logic [23:0] BLOCK_SPARE_TABLE = 24'hffffff;
	localparam logic [23:0] BLOCK_BUFFER      = 24'hfffffe;
	localparam logic [23:0] MAX_BLOCKS        = 24'hfffffd;
	localparam logic [23:0] BLOCKS_5MB        = 24'd9728;

	typedef enum logic [2:0] {
		IDLE,
		RESPOND,
		EXECUTE,
		REQUEST,
		TRANSFER
	} state_t;

	// What the drive expects next: the first handshake, the command bytes,
	// or a write's data.
	typedef enum logic [1:0] {
		PHASE_COMMAND,
		PHASE_BYTES,
		PHASE_DATA
	} phase_t;

	// The card. CRW and INTEN are latched as on the board but drive nothing
	// here: the read path needs no direction buffer, and Apple's driver
	// leaves the interrupt disabled.
	/* verilator lint_off UNUSEDSIGNAL */
	logic crw, inten;
	/* verilator lint_on UNUSEDSIGNAL */
	logic cmd_line, cmd_line_q, datarw, cres;
	logic       selected;
	logic [7:0] wbuf;
	logic host_read, host_write, dma_active, strobe_in, strobe_out;
	logic [7:0] byte_out, read_byte, rstat;

	// The drive. Mount state survives reset, like a drive keeps its disk.
	logic          mounted = 1'b0;
	logic          readonly = 1'b1;
	logic   [23:0] blocks = '0;
	state_t        state;
	phase_t        phase;
	logic writing, spare_table, busy;
	logic [ 7:0]      response;
	// Command, block number, then the retry count and sparing threshold,
	// which an image needs no use for.
	/* verilator lint_off UNUSEDSIGNAL */
	logic [ 5:0][7:0] command;
	/* verilator lint_on UNUSEDSIGNAL */
	logic [23:0]      block;
	logic [9:0] index, data_index;
	logic [3:0][7:0] status;
	logic [7:0]      buffer [512];
	logic [7:0] buffer_q, buffer_din;
	logic [8:0] buffer_addr;
	logic buffer_we, host_transfer;

	// Bytes 0-12 name the drive, 13-15 are its type (5 or 10 MB ProFile),
	// 16-17 the firmware revision, 18-20 the block count high byte first,
	// 21-22 the 532-byte block size and 23 the spare blocks on hand.
	function automatic logic [7:0] spare_byte(input logic [9:0] at, input logic [23:0] size);
		case (at)
			10'd0:                                       spare_byte = "P";
			10'd1:                                       spare_byte = "R";
			10'd2:                                       spare_byte = "O";
			10'd3:                                       spare_byte = "F";
			10'd4:                                       spare_byte = "I";
			10'd5:                                       spare_byte = "L";
			10'd6:                                       spare_byte = "E";
			10'd7, 10'd8, 10'd9, 10'd10, 10'd11, 10'd12: spare_byte = " ";
			10'd14:                                      spare_byte = (size > BLOCKS_5MB) ? 8'h01 : 8'h00;
			10'd16:                                      spare_byte = 8'h03;
			10'd17:                                      spare_byte = 8'h98;
			10'd18:                                      spare_byte = size[23:16];
			10'd19:                                      spare_byte = size[15:8];
			10'd20:                                      spare_byte = size[7:0];
			10'd21:                                      spare_byte = 8'h02;
			10'd22:                                      spare_byte = 8'h14;
			10'd23:                                      spare_byte = 8'h20;
			default:                                     spare_byte = 8'h00;
		endcase
	endfunction

	// Any $Cnxx access selects the card for pseudo-DMA; $C02x deselects it.
	apple3_slot_rom #(
		.DESELECT_C02X(1'b1),
		.DESELECT_CFFF(1'b0)
	) select_latch (
		.clk,
		.reset,
		.cycle_strobe(cycle),
		.io_select,
		.io_strobe   (1'b0),
		.rom_deselect,
		.addr        (11'd0),
		.selected,
		.rom_select  ()
	);

	assign busy        = (state != IDLE);
	assign activity    = (state == EXECUTE) || (state == REQUEST) || (state == TRANSFER);
	assign host_read   = cycle && device_select && cpu_read && (addr[1:0] == 2'd1);
	assign host_write  = cycle && device_select && !cpu_read && (addr[1:0] == 2'd0);
	assign dma_req     = selected && !reset;
	assign dma_write   = datarw;
	assign dma_active  = dma_ok && dma_req;
	assign strobe_in   = host_read || (cycle && dma_active && datarw);
	assign strobe_out  = host_write || (cycle && dma_active && !datarw);
	assign byte_out    = host_write ? data_in : dma_data;
	assign rstat       = {!busy, 6'b000000, !mounted};
	assign sd_lba      = {8'd0, block};
	assign sd_buff_din = buffer_q;
	assign data_index  = index - 10'd4;

	// The buffer is the drive's: the host reaches it only while the drive
	// is idle, and Main only while it is executing a transfer.
	assign host_transfer = (state == REQUEST) || (state == TRANSFER);
	assign buffer_we     = host_transfer ? (sd_buff_wr && sd_ack) :
						   (strobe_out && (state == IDLE) && (phase == PHASE_DATA) && (index < 10'd512));
	assign buffer_addr = host_transfer ? sd_buff_addr : (phase == PHASE_DATA) ? index[8:0] : data_index[8:0];
	assign buffer_din = host_transfer ? sd_buff_dout : byte_out;

	always_ff @(posedge clk) begin
		if (buffer_we) buffer[buffer_addr] <= buffer_din;
		buffer_q <= buffer[buffer_addr];
	end

	always_comb begin
		if (state == RESPOND) read_byte = response;
		else if (state != IDLE) read_byte = 8'h00;
		else if (index < 10'd4) read_byte = status[index[1:0]];
		else if (index < 10'd516) read_byte = spare_table ? spare_byte(data_index, blocks) : buffer_q;
		else read_byte = 8'h00;

		data_oe  = !reset && cpu_read && device_select && ((addr[1:0] == 2'd1) || (addr[1:0] == 2'd2));
		data_out = (device_select && (addr[1:0] == 2'd2)) ? rstat : read_byte;
	end

	always_ff @(posedge clk) begin
		if (image_change) begin
			mounted  <= image_size != 64'd0;
			readonly <= image_readonly;
			blocks   <= ((image_size[63:33] != 0) || (image_size[32:9] > MAX_BLOCKS)) ? MAX_BLOCKS : image_size[32:9];
		end

		if (reset) begin
			cmd_line    <= 1'b0;
			cmd_line_q  <= 1'b0;
			crw         <= 1'b0;
			inten       <= 1'b0;
			datarw      <= 1'b0;
			cres        <= 1'b0;
			wbuf        <= 8'h00;
			state       <= IDLE;
			phase       <= PHASE_COMMAND;
			writing     <= 1'b0;
			spare_table <= 1'b0;
			response    <= RESPONSE_COMMAND;
			command     <= '0;
			block       <= '0;
			index       <= '0;
			status      <= '0;
			sd_rd       <= 1'b0;
			sd_wr       <= 1'b0;
		end else begin
			// The 9334 addressable latch behind I/O select.
			if (cycle && io_select) begin
				case ({
					addr[3], addr[1:0]
				})
					3'b000:  cmd_line <= addr[2];
					3'b001:  crw <= addr[2];
					3'b010:  inten <= addr[2];
					3'b011:  datarw <= addr[2];
					3'b100:  cres <= addr[2];
					default: ;
				endcase
			end
			if (strobe_out) wbuf <= byte_out;
			cmd_line_q <= cmd_line;

			if (cres) begin
				// CRES holds the drive in reset; it comes up idle.
				state <= IDLE;
				phase <= PHASE_COMMAND;
				index <= '0;
				sd_rd <= 1'b0;
				sd_wr <= 1'b0;
			end else begin
				case (state)
					IDLE: begin
						if (cmd_line && !cmd_line_q) begin
							state <= RESPOND;
							case (phase)
								PHASE_COMMAND: response <= RESPONSE_COMMAND;
								PHASE_BYTES: begin
									case (command[0])
										8'h00:   response <= RESPONSE_READ;
										8'h01:   response <= RESPONSE_WRITE;
										8'h02:   response <= RESPONSE_VERIFY;
										default: response <= RESPONSE_COMMAND;
									endcase
								end
								default:       response <= RESPONSE_STATUS;
							endcase
						end else begin
							if (strobe_out && (phase == PHASE_BYTES) && (index < 10'd6))
								command[index[2:0]] <= byte_out;
							if ((strobe_in || strobe_out) && (index != 10'h3ff)) index <= index + 10'd1;
						end
					end
					RESPOND: begin
						if (!cmd_line && cmd_line_q) begin
							index <= '0;
							if (wbuf != HOST_ACK) begin
								state <= IDLE;
								phase <= PHASE_COMMAND;
							end else begin
								case (phase)
									PHASE_COMMAND: begin
										state <= IDLE;
										phase <= PHASE_BYTES;
									end
									PHASE_BYTES: begin
										block <= {command[1], command[2], command[3]};
										if (response == RESPONSE_READ) begin
											writing <= 1'b0;
											state   <= EXECUTE;
										end else if ((response == RESPONSE_WRITE) || (response == RESPONSE_VERIFY)) begin
											writing <= 1'b1;
											state   <= IDLE;
											phase   <= PHASE_DATA;
										end else begin
											state <= IDLE;
											phase <= PHASE_COMMAND;
										end
									end
									default: state <= EXECUTE;
								endcase
							end
						end
					end
					EXECUTE: begin
						status      <= '0;
						spare_table <= 1'b0;
						index       <= '0;
						phase       <= PHASE_COMMAND;
						if (block == BLOCK_SPARE_TABLE) begin
							spare_table <= !writing;
							state       <= IDLE;
						end else if (block == BLOCK_BUFFER) begin
							state <= IDLE;
						end else if (!mounted || (block >= blocks)) begin
							status[0] <= STATUS1_FAILED;
							status[2] <= STATUS3_BAD_BLOCK;
							state     <= IDLE;
						end else if (writing && readonly) begin
							status[0] <= STATUS1_FAILED;
							state     <= IDLE;
						end else if (!sd_ack) begin
							// Wait out a transfer that a reset abandoned.
							sd_rd <= !writing;
							sd_wr <= writing;
							state <= REQUEST;
						end
					end
					REQUEST: begin
						if (sd_ack) begin
							sd_rd <= 1'b0;
							sd_wr <= 1'b0;
							state <= TRANSFER;
						end
					end
					TRANSFER: begin
						if (!sd_ack) state <= IDLE;
					end
					default: state <= IDLE;
				endcase
			end
		end
	end
endmodule
