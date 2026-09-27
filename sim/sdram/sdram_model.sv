`timescale 1ns / 10ps

// A single-data-rate SDRAM for simulation, with the checks a MiSTer module's
// chip would impose: the power-up sequence, row and bank timing, auto
// precharge, refresh interval, CAS latency 2 or 3 from the mode register,
// DQM byte masks and DQ bus contention.  Timings are the slowest of the
// AS4C16M16SA, AS4C32M16SB and W9825G6KH data sheets: a controller that
// meets them meets every module.  Rows beyond ROW_BITS are not modelled.
//
// Everything happens on the chip's own clock (clk), so a controller whose
// commands or read capture sit on the wrong phase of its clock fails here.

module sdram_model #(
	parameter real    T_CK     = 69.84,  // ns
	parameter integer ROW_BITS = 9,
	parameter integer COL_BITS = 9
) (
	input  logic          clk,
	input  logic          cke,
	input  logic          cs_n,
	input  logic          ras_n,
	input  logic          cas_n,
	input  logic          we_n,
	input  logic   [ 1:0] ba,
	input  logic   [12:0] a,
	input  logic   [ 1:0] dqm,           // {DQMH, DQML}: A12:A11 on a MiSTer module
	input  logic   [15:0] dq_in,         // the controller's drive
	input  logic          dq_in_valid,   // the controller is driving
	output logic   [15:0] dq_out,
	output logic          dq_out_valid,
	output integer        errors,
	output integer        refreshes
);
	localparam real T_POWER_UP = 200000.0;
	localparam real T_RCD      = 20.0;
	localparam real T_RP       = 20.0;
	localparam real T_RAS      = 45.0;
	localparam real T_RC       = 70.0;
	localparam real T_RFC      = 70.0;
	localparam real T_WR       = 15.0;        // and at least two clocks
	localparam real T_MRD      = 2.0 * T_CK;
	localparam real T_REFI     = 7812.5;      // 8,192 rows in 64 ms

	logic [15:0] mem[4][1 << ROW_BITS][1 << COL_BITS];

	typedef enum logic [1:0] {
		IDLE,
		ACTIVE,
		PRECHARGING
	} bank_t;
	bank_t  bank_state[4];
	integer open_row  [4];
	real act_time[4], ready_time[4], precharge_at[4];

	real now, last_refresh, mode_time, refresh_busy_until;
	// 64 bits: a 32-bit count wraps after 2^31 clocks (150 s at 14.318 MHz).
	longint cycle_count;
	integer cas_latency, init_refreshes;
	bit mode_set, precharged_all, started;

	// Read data in flight: [0] leaves on the next clock.
	logic [15:0] pipe_data [4];
	logic        pipe_valid[4];

	task automatic fail(input string what);
		errors++;
		if (errors <= 20) $display("SDRAM ERROR at %0.1f ns: %s", now, what);
	endtask

	initial begin
		errors             = 0;
		refreshes          = 0;
		cycle_count        = 0;
		cas_latency        = 0;
		init_refreshes     = 0;
		mode_set           = 0;
		precharged_all     = 0;
		started            = 0;
		last_refresh       = 0.0;
		refresh_busy_until = 0.0;
		mode_time          = -1.0e9;
		dq_out             = 16'h0000;
		dq_out_valid       = 1'b0;
		for (int b = 0; b < 4; b++) begin
			bank_state[b]   = IDLE;
			act_time[b]     = -1.0e9;
			ready_time[b]   = 0.0;
			precharge_at[b] = -1.0;
			pipe_data[b]    = '0;
			pipe_valid[b]   = 1'b0;
			for (int r = 0; r < (1 << ROW_BITS); r++) for (int c = 0; c < (1 << COL_BITS); c++) mem[b][r][c] = 16'h0000;
		end
	end

	function automatic bit all_idle();
		for (int b = 0; b < 4; b++) if (bank_state[b] != IDLE || ready_time[b] > now + 0.01) return 0;
		return 1;
	endfunction

	always @(posedge clk) begin
		logic [2:0] command;
		integer b, row, col;
		now = cycle_count * T_CK;
		cycle_count++;
		command = {ras_n, cas_n, we_n};
		b       = ba;

		// Auto precharges that begin at this edge.
		for (int k = 0; k < 4; k++)
		if (bank_state[k] == ACTIVE && precharge_at[k] >= 0.0 && now + 0.01 >= precharge_at[k]) begin
			if (now + 0.01 < act_time[k] + T_RAS) fail("auto precharge before tRAS");
			bank_state[k]   = PRECHARGING;
			ready_time[k]   = now + T_RP;
			precharge_at[k] = -1.0;
		end
		for (int k = 0; k < 4; k++)
		if (bank_state[k] == PRECHARGING && now + 0.01 >= ready_time[k]) bank_state[k] = IDLE;

		// Read data moves one clock nearer the pins.
		dq_out_valid = pipe_valid[0];
		dq_out       = pipe_data[0];
		for (int k = 0; k < 3; k++) begin
			pipe_valid[k] = pipe_valid[k+1];
			pipe_data[k]  = pipe_data[k+1];
		end
		pipe_valid[3] = 1'b0;

		if (!cke) fail("CKE low");
		if (started && mode_set && now - last_refresh > T_REFI + 0.01) begin
			fail($sformatf("%0.0f ns without a refresh", now - last_refresh));
			last_refresh = now;
		end

		if (!cs_n && command != 3'b111) begin
			if (!started) begin
				if (now < T_POWER_UP) fail("command before 200 us of NOPs");
				started = 1;
			end
			if (now + 0.01 < refresh_busy_until) fail("command inside tRFC");
			if (now + 0.01 < mode_time + T_MRD) fail("command inside tMRD");
			case (command)
				3'b011: begin  // ACTIVE
					row = a;
					if (!mode_set) fail("ACTIVE before the mode register");
					if (bank_state[b] != IDLE || now + 0.01 < ready_time[b])
						fail($sformatf("ACTIVE to busy bank %0d", b));
					if (now + 0.01 < act_time[b] + T_RC) fail("ACTIVE inside tRC");
					if (row >= (1 << ROW_BITS)) fail($sformatf("row %0d is not modelled", row));
					bank_state[b] = ACTIVE;
					open_row[b]   = row;
					act_time[b]   = now;
				end
				3'b101, 3'b100: begin  // READ, WRITE
					col = a[COL_BITS-1:0];
					if (bank_state[b] != ACTIVE) fail($sformatf("%s to a closed bank", command[0] ? "READ" : "WRITE"));
					else if (now + 0.01 < act_time[b] + T_RCD) fail("READ/WRITE inside tRCD");
					else if (a[9] != 1'b0) fail("column beyond a 512-column chip");
					else if (!command[0]) begin
						if (!dq_in_valid) fail("WRITE without data driven");
						if (!dqm[0]) mem[b][open_row[b]][col][7:0] = dq_in[7:0];
						if (!dqm[1]) mem[b][open_row[b]][col][15:8] = dq_in[15:8];
						if (a[10]) precharge_at[b] = now + ((2.0 * T_CK > T_WR) ? 2.0 * T_CK : T_WR);
					end else begin
						if (cas_latency < 2) fail("READ with no CAS latency");
						else begin
							pipe_valid[cas_latency-2] = 1'b1;
							pipe_data[cas_latency-2]  = mem[b][open_row[b]][col];
						end
						if (dqm != 2'b00) fail("masked read: the controller reads both bytes");
						if (a[10]) precharge_at[b] = now + T_CK;
					end
				end
				3'b010: begin  // PRECHARGE
					for (int k = 0; k < 4; k++)
					if (a[10] || k == b) begin
						if (bank_state[k] == ACTIVE) begin
							if (now + 0.01 < act_time[k] + T_RAS) fail("PRECHARGE inside tRAS");
							bank_state[k] = PRECHARGING;
							ready_time[k] = now + T_RP;
						end
					end
					if (a[10]) precharged_all = 1;
				end
				3'b001: begin  // AUTO REFRESH
					if (!precharged_all) fail("REFRESH before PRECHARGE ALL");
					if (!all_idle()) fail("REFRESH with a bank open");
					refresh_busy_until = now + T_RFC;
					last_refresh       = now;
					refreshes++;
					if (!mode_set) init_refreshes++;
				end
				3'b000: begin  // LOAD MODE REGISTER
					if (!all_idle()) fail("mode register with a bank open");
					if (init_refreshes < 2) fail("mode register before two refreshes");
					if (a[2:0] != 3'b000) fail("burst length other than 1");
					cas_latency = a[6:4];
					if (cas_latency != 2 && cas_latency != 3) fail("CAS latency other than 2 or 3");
					mode_set  = 1;
					mode_time = now;
				end
				default: fail("BURST TERMINATE");
			endcase
		end
	end

	// The chip drives from a clock edge to the next; so does the controller.
	always @(dq_out_valid or dq_in_valid) if (dq_out_valid && dq_in_valid) fail("DQ driven by both");

endmodule
