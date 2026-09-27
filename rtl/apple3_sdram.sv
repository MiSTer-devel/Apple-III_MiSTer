// SDRAM for the external RAM port of apple3_core: the 512K board's banks
// 7-14 on the MiSTer's SDRAM module.
//
// The controller runs on the 14.318 MHz machine clock and follows the CPU
// cycle instead of arbitrating for it.  A cycle ends at every cpu_enable
// (cycle), at least seven clocks apart, and the address is valid from the
// clock after.  An access therefore always fits inside the cycle it serves:
//
//   clock  E    cycle high: the CPU cycle ends, the next address follows
//          E+1  ACTIVE with the row of the new address
//          E+2  READ or WRITE with auto precharge; a write drives its byte
//          E+4  the read word reaches the DQ input register (CAS latency 2)
//          E+5  q holds it, two clocks before the CPU takes it at E+7
//
// Both bytes of the word are read, so the sister byte comes with every read
// as it does from the block RAM.  A write masks the other byte with DQM,
// which MiSTer's modules take on A12 and A11 during READ and WRITE (the top
// level drives the DQM pins from them too, for modules that wire those).
// SDRAM_CLK is the inverted machine clock:
// the chip samples commands half a clock after they leave the FPGA, and the
// read word is captured a clock and a half after the chip drives it, with
// about 25 ns of setup and 40 ns of hold at this speed.  Every timing
// parameter of the MiSTer modules' chips (tRCD, tRP, tRAS, tWR 15-20 ns,
// tRC and tRFC up to 70 ns) fits in the one- and two-clock gaps used here.
//
// An auto refresh goes out after the access, in a clock that no ACTIVE can
// follow for two clocks: nothing is in flight and cycle is low, so the next
// ACTIVE comes at E+1 no sooner than two clocks on.  The first such clock is
// E+6 of the shortest cycle, and a CPU waiting on RDY leaves every clock free,
// so refresh is never late and never delays the CPU.
//
// The CPU's region uses bank 0, rows 0-255.  The rest of the module, and the
// commands the CPU leaves free (at least E+5 and E+6 of every cycle), are
// spare for other memory: docs/EXTERNAL_MEMORY.md has the budget.

module apple3_sdram (
	input  logic clk,
	// Restarts the power-up sequence; hold while the clock is unstable.
	input  logic init,
	// High once the chip is initialised. The CPU must not use it before.
	output logic ready,

	// The CPU port (apple3_core's ext_ram_*).
	input  logic        cycle,
	input  logic        select,
	input  logic [23:0] addr,
	input  logic        we,
	input  logic        lane,
	input  logic [ 7:0] din,
	output logic [15:0] q,

	// The chip.  SDRAM_CLK is ~clk, from a DDIO output in the top level.
	output logic        sdram_cke,
	output logic        sdram_cs_n,
	output logic        sdram_ras_n,
	output logic        sdram_cas_n,
	output logic        sdram_we_n,
	output logic [ 1:0] sdram_ba,
	// A12:A11 are DQMH:DQML during READ and WRITE.
	output logic [12:0] sdram_a,
	output logic [15:0] sdram_dq_out,
	output logic        sdram_dq_oe,
	input  logic [15:0] sdram_dq_in
);

	// {RAS, CAS, WE}, active low.
	localparam logic [2:0] CMD_NOP       = 3'b111;
	localparam logic [2:0] CMD_ACTIVE    = 3'b011;
	localparam logic [2:0] CMD_READ      = 3'b101;
	localparam logic [2:0] CMD_WRITE     = 3'b100;
	localparam logic [2:0] CMD_PRECHARGE = 3'b010;
	localparam logic [2:0] CMD_REFRESH   = 3'b001;
	localparam logic [2:0] CMD_MODE      = 3'b000;

	// Burst length 1, sequential, CAS latency 2, single-location writes.
	localparam logic [12:0] MODE = 13'b000_1_00_010_0_000;

	// 200 us of NOPs after the clock settles, then PRECHARGE ALL, eight
	// refreshes and the mode register.
	localparam integer POWER_UP_CLOCKS = 4096;  // 286 us
	// 8,192 rows every 64 ms is one refresh every 111 clocks. Asking every
	// 80 keeps a refresh that waits out a whole slow cycle inside that.
	localparam integer REFRESH_CLOCKS  = 80;

	typedef enum logic [2:0] {
		POWER_UP,
		PRECHARGE_ALL,
		REFRESH_INIT,
		LOAD_MODE,
		RUN
	} init_t;

	// Power-up values: the chip must see NOPs from the first clock, before
	// the power-up sequence begins, not the all-zero LOAD MODE REGISTER.
	init_t        init_state = POWER_UP;
	logic  [12:0] init_count = '0;
	logic  [ 3:0] init_refreshes = '0;

	logic       start = 1'b0;  // the clock after cycle: the new address is valid
	logic [2:0] step = '0;  // the access in flight: 1 after ACTIVE ... 4 as q loads
	logic       step_read;
	logic [8:0] column;
	logic write, write_lane;
	logic [ 6:0] refresh_count = '0;
	logic        refresh_due = 1'b0;
	logic [ 2:0] command = CMD_NOP;
	logic [ 2:0] quiet = '0;  // clocks to wait after an initialisation command
	logic [15:0] dq_in_q;
	logic        ready_q = 1'b0;
	logic        dq_oe = 1'b0;

	logic [12:0] a_q = '0;

	assign sdram_a                                = a_q;
	assign ready                                  = ready_q;
	assign sdram_dq_oe                            = dq_oe;
	assign sdram_cke                              = 1'b1;
	assign sdram_cs_n                             = 1'b0;
	assign {sdram_ras_n, sdram_cas_n, sdram_we_n} = command;

	always_ff @(posedge clk) begin
		// The DQ input register: every clock, so it maps to the I/O cell.
		dq_in_q <= sdram_dq_in;
		start   <= cycle;

		command <= CMD_NOP;
		dq_oe   <= 1'b0;

		if (refresh_count != REFRESH_CLOCKS[6:0]) refresh_count <= refresh_count + 1'b1;
		else refresh_due <= 1'b1;

		if (init) begin
			init_state     <= POWER_UP;
			init_count     <= '0;
			init_refreshes <= '0;
			quiet          <= '0;
			ready_q        <= 1'b0;
			step           <= '0;
			refresh_due    <= 1'b0;
			refresh_count  <= '0;
		end else if (init_state != RUN) begin
			if (quiet != 0) quiet <= quiet - 1'b1;
			else
				case (init_state)
					POWER_UP: begin
						init_count <= init_count + 1'b1;
						if (init_count == 13'(POWER_UP_CLOCKS - 1)) init_state <= PRECHARGE_ALL;
					end
					PRECHARGE_ALL: begin
						command    <= CMD_PRECHARGE;
						a_q[10]    <= 1'b1;
						quiet      <= 3'd2;
						init_state <= REFRESH_INIT;
					end
					REFRESH_INIT: begin
						command        <= CMD_REFRESH;
						quiet          <= 3'd2;
						init_refreshes <= init_refreshes + 1'b1;
						if (init_refreshes == 4'd7) init_state <= LOAD_MODE;
					end
					LOAD_MODE: begin
						command    <= CMD_MODE;
						sdram_ba   <= 2'b00;
						a_q        <= MODE;
						quiet      <= 3'd2;
						init_state <= RUN;
					end
					default: ;
				endcase
		end else begin
			ready_q <= (quiet == 0);
			if (quiet != 0) quiet <= quiet - 1'b1;

			if (step != 0) step <= (step == 3'd4) ? 3'd0 : step + 1'b1;
			case (step)
				3'd1: begin
					// Auto precharge: the bank is idle again by E+5. A write
					// masks the byte it leaves alone; a read takes both.
					command      <= write ? CMD_WRITE : CMD_READ;
					a_q          <= {write ? (write_lane ? 2'b01 : 2'b10) : 2'b00, 1'b1, 1'b0, column};
					sdram_dq_out <= {din, din};
					dq_oe        <= write;
				end
				3'd4:    if (step_read) q <= dq_in_q;
				default: ;
			endcase

			if (start && select && ready_q) begin
				command    <= CMD_ACTIVE;
				sdram_ba   <= addr[23:22];
				a_q        <= addr[21:9];
				column     <= addr[8:0];
				write      <= we;
				write_lane <= lane;
				step_read  <= !we;
				step       <= 3'd1;
			end else if (refresh_due && (step == 0) && !start && !cycle && ready_q) begin
				command       <= CMD_REFRESH;
				refresh_due   <= 1'b0;
				refresh_count <= '0;
			end
		end
	end

endmodule
