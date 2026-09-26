// Apple /// address translation and overlay decode.
//
// This is kept combinational so the mapping can be tested independently of the
// CPU and RAM implementation.  It follows the main logic board (drawing
// 050-0039-H): the zero-page substitution of sheet 4, the ROM, VIA and I/O
// decode of sheet 5 with 342-0045 and 342-0046, and the RAM decode of the
// address PROMs on sheet 3 for Apple's 128 and 256 KiB memory boards.
// sim/memmap checks every page of it against those PROM dumps; see
// docs/MEMORY_MAP.md.  The Level 2 Service Reference Manual, SOS 1.3,
// Jeppson's "III BITS" and the July 1981 "Funny Mode" memo describe the same
// map; MAME is a compatibility cross-check, not the specification.
//
// A pseudo-DMA cycle (dma_cycle) is a CPU fetch from the ROM's $F800 block
// that a card has claimed through DMAI.  The CPU still reads its ROM byte;
// the RAM side of the cycle goes to the zero page instead, so the card's byte
// lands where a zero-page access to the same low address would, in the page
// the zero-page register names and the bank the bank register selects.
// That is the transfer Apple's ProFile driver sets up (docs/PROFILE.md).
//
// RAM_BANKS is 8 for Apple's boards, where ram_128k selects the 128 KiB board
// at run time, or 16 for a third-party 512 KiB upgrade, which Apple's PROMs do
// not cover.  The system bank is always the last one in the FPGA's RAM.

module apple3_mmu #(
	parameter integer RAM_BANKS = 16
) (
	input logic [15:0] cpu_addr,
	input logic        cpu_read,
	input logic [ 7:0] environment,
	input logic [ 7:0] zero_page,
	// The bank latch's outputs (apple3_extaddr): the word it holds, and
	// whether that word is an X byte.
	input logic [ 7:0] bank_register,
	input logic        native_mode,
	input logic        extended_active,
	input logic [ 7:0] extended_bank,
	input logic        ram_128k,
	input logic        dma_cycle,

	output logic [15:0] bus_addr,
	output logic [18:0] ram_byte_addr,
	output logic [17:0] ram_word_addr,
	output logic        ram_lane,
	output logic        ram_select,
	output logic        ram_read,
	output logic        ram_write_allowed,
	output logic        dma_read_allowed,
	output logic        dma_write_allowed,
	output logic        rom_read,
	output logic [12:0] rom_addr,
	output logic        io_select,
	output logic        slot_rom_select,
	output logic        via_d_select,
	output logic        via_e_select
);

	localparam bit         STOCK       = (RAM_BANKS != 16);
	localparam logic [3:0] SYSTEM_BANK = STOCK ? 4'd7 : 4'd15;
	// The main board's bank latch (A9) takes three bits of the bank register
	// and of the X byte, so a stock machine cannot tell $87 from $8F.  A
	// 512 KiB upgrade adds the fourth along with its own decoder PROMs.
	localparam logic [3:0] BANK_MASK   = STOCK ? 4'h7 : 4'hf;

	logic [ 3:0] top_bank;
	logic [ 3:0] window_bank;
	logic [ 3:0] extended_pair;
	logic [ 4:0] linear_bank;
	logic [ 3:0] mapped_bank;
	logic [14:0] bank_offset;
	logic        zero_page_select;
	logic        indirect;
	logic        special_map;
	logic        window;
	logic        present;
	logic [15:0] ram_addr;
	logic        c_fxxx;
	logic        ff_page;
	logic        ffcx;
	logic        cxxx;
	logic        always_ram;
	logic        io_space;
	logic        fspace;
	logic        ramen;
	logic        dma_c_fxxx;
	logic        dma_ff_page;
	logic        dma_cxxx;
	logic        dma_io_space;
	logic        dma_fspace;
	logic        dma_rom;
	logic        dma_ramen;
	logic [18:0] translated_addr;

	always_comb begin
		// Sheet 4.  -ZPAGE: page $00, or page $01 with the alternate stack
		// selected and no X byte latched (E7 and J8 gate it with ABK4).  D7 and
		// D8 then drive the zero-page register onto A15-A9 and D4 makes A8 =
		// Z0 xor PA8.  Everything below decodes this substituted address.
		zero_page_select = (cpu_addr[15:9] == 7'd0) &&
						   (!cpu_addr[8] || (!environment[2] && !(extended_active && extended_bank[7])));
		bus_addr = zero_page_select ? {zero_page ^ {7'd0, cpu_addr[8]}, cpu_addr[7:0]} : cpu_addr;
		// The RAM side of a pseudo-DMA cycle takes the zero page's address.
		ram_addr = dma_cycle ? {zero_page, cpu_addr[7:0]} : bus_addr;

		// 342-0043: -IND = /PA8*/-ZPAGE + /ABK4.
		indirect      = extended_active && extended_bank[7] && (cpu_addr[15:8] != 8'h00);
		extended_pair = extended_bank[3:0] & BANK_MASK;
		special_map   = indirect && (extended_pair == BANK_MASK);
		linear_bank   = {1'b0, extended_pair} + {4'b0000, ram_addr[15]};

		// Apple's boards: banks 0-2 or 0-6, then the system bank.  Bank
		// register 7 reaches bank 2 on the 256 KiB board and bank 0 on the
		// 128 KiB one; 3-6 on the latter, and the upper half of the last
		// pair on either, strobe no CAS at all.
		top_bank    = !STOCK ? 4'd14 : ram_128k ? 4'd2 : 4'd6;
		window_bank = bank_register[3:0] & BANK_MASK;
		window      = (ram_addr >= 16'h2000) && (ram_addr < 16'ha000);
		present     = 1'b1;

		if (indirect && !special_map) begin
			// X=$80+n supplies the high 32-K bank number.  A15 selects n/n+1.
			mapped_bank = linear_bank[3:0] & BANK_MASK;
			bank_offset = ram_addr[14:0];
			present     = !STOCK || (linear_bank <= {1'b0, top_bank});
		end else if (window) begin
			bank_offset = ram_addr[14:0] - 15'h2000;
			if (special_map) mapped_bank = 4'd0;
			else if (window_bank == SYSTEM_BANK) mapped_bank = (STOCK && ram_128k) ? 4'd0 : 4'd2;
			else begin
				mapped_bank = window_bank;
				present     = (window_bank <= top_bank);
			end
		end else begin
			mapped_bank = SYSTEM_BANK;
			bank_offset = ram_addr[14:0];
		end

		translated_addr = {mapped_bank, bank_offset};
		ram_byte_addr   = translated_addr;
		// The DRAM datapath fetches A and A xor $0c00 together.  Canonicalise
		// that pair into one 16-bit word; lane identifies the requested byte.
		ram_word_addr   = {translated_addr[18:12], translated_addr[10] ^ translated_addr[11], translated_addr[9:0]};
		ram_lane        = translated_addr[11];

		// Sheet 5.  K8: C-FXXX = A15*A14*-IND, so a latched X byte switches
		// the ROM, the VIAs, I/O and write protection off together.
		c_fxxx = (bus_addr[15:14] == 2'b11) && !indirect;
		// G7/G8: $FFCx, $FFDx and $FFEx, in native mode only.
		ff_page = c_fxxx && (&bus_addr[13:6]) && native_mode;
		ffcx = ff_page && (bus_addr[5:4] == 2'b00);
		via_d_select = ff_page && (bus_addr[5:4] == 2'b01);
		via_e_select = ff_page && (bus_addr[5:4] == 2'b10);
		// K8/D9/J6: $Cxxx with IOEN; $C500-$C7FF stays RAM (342-0045).
		cxxx = c_fxxx && environment[6] && (bus_addr[13:12] == 2'b00);
		always_ram = cxxx && !bus_addr[11] && (bus_addr[10:8] >= 3'd5);
		io_space = cxxx && !always_ram;
		io_select = io_space && (bus_addr[11:8] == 4'h0);
		slot_rom_select = io_space && !io_select;
		// J4: the VIAs, the ACIA at $C0Fx and the clock at $C07x.
		fspace = via_d_select || via_e_select || (io_select && ((bus_addr[7:4] == 4'hf) || (bus_addr[7:4] == 4'h7)));
		// J7: reads of $F000-$FFFF with ROMSEL1, outside $FFCx and FSPACE.  It
		// takes -AIISW too, so Apple II mode never sees the ROM.
		rom_read = c_fxxx && (bus_addr[13:12] == 2'b11) && native_mode && !ffcx && environment[0] &&
				   cpu_read && !fspace;
		rom_addr = {environment[1], bus_addr[11:0]};

		// 342-0045 RAMEN, and 342-0046 WRAMEN with RWPROT over C-FXXX.  RAMEN
		// does not depend on write protection or on a chip being there: the
		// clock PROM reserves the RAM slot either way.
		ramen             = !rom_read && !fspace && !io_space;
		ram_select        = ramen;
		ram_read          = ramen && cpu_read && present;
		ram_write_allowed = ramen && !cpu_read && present && !(environment[3] && c_fxxx);

		// The same decode for the zero page a pseudo-DMA cycle reaches: the
		// byte goes to RAM where a zero-page access would, and nowhere else.
		dma_c_fxxx = (ram_addr[15:14] == 2'b11);
		dma_ff_page = dma_c_fxxx && (&ram_addr[13:6]) && native_mode;
		dma_cxxx = dma_c_fxxx && environment[6] && (ram_addr[13:12] == 2'b00);
		dma_io_space = dma_cxxx && !(!ram_addr[11] && (ram_addr[10:8] >= 3'd5));
		dma_fspace   = (dma_ff_page && (ram_addr[5:4] != 2'b11) && (ram_addr[5:4] != 2'b00)) ||
					   (dma_io_space && (ram_addr[11:8] == 4'h0) && ((ram_addr[7:4] == 4'hf) || (ram_addr[7:4] == 4'h7)));
		dma_rom      = dma_c_fxxx && (ram_addr[13:12] == 2'b11) && native_mode && environment[0] &&
					   !(dma_ff_page && (ram_addr[5:4] == 2'b00)) && !dma_fspace;
		dma_ramen = !dma_rom && !dma_fspace && !dma_io_space;
		dma_read_allowed = dma_cycle && dma_ramen && present;
		dma_write_allowed = dma_read_allowed && !(environment[3] && dma_c_fxxx);
	end

endmodule
