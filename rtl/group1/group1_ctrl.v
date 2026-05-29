// =============================================================================
// group1_ctrl.v -- Group 1 Controller (Module 1.12)
// -----------------------------------------------------------------------------
// "This controller purpose is to synchronize all the blocks operations
// together. To make sure that the data is read from the memory is correct
// and at the correct clock cycle to be stored in the FIFOs. And to give
// the starting signals to the FIFOs and the resets of the registers in the
// computation cores. And the addresses for the Filter memory." --
// "This controller is very simple that it is not even a state machine it
// uses only counters and logic based on the input signals from the FIFOs
// controllers." --
// FUNCTION:
// Receives fsm_state from fifo_ctrl (which runs the 4-state FSM for the
// 3x3 conv FIFOs). When fsm_state == S_PROCESS, the conv3x3 FIFO is
// shifting new window data into the taps every clock. group1_ctrl tracks
// which of the 4 accumulation clocks we are on (col_cnt = 0..3):
// col_cnt=0: first kernel column, addr=0, acc_clr=1, en=1
// col_cnt=1: second kernel column, addr=1, acc_clr=1, en=1
// (acc_clr=1 twice matches the MAC pipeline 1-cycle delay:
// the accumulator first sees a REAL partial sum at posedge after col1)
// col_cnt=2: third kernel column, addr=2, acc_clr=0, en=1
// col_cnt=3: drain (acc gets final sum), addr=0, acc_clr=0, en=1
// after posedge at col_cnt=3: results_flat of conv3x3_core is valid
// conv_valid pulses HIGH for one clock at col_cnt=3 (drain cycle).
// This signal is used by group1_top to gate the write to maxpool memory.
// PORT MAP:
// start -- from accelerator controller; relayed to FIFO controllers
// fsm_state -- from fifo_ctrl (IDLE=0, LDROW=1, LDWIN=2, PROCESS=3)
// en -- to conv3x3_core and maxpool_core (pipeline enable)
// acc_clr -- to conv3x3_core (accumulator MUX: 1=zero, 0=accumulate)
// addr -- to weights_rom_3x3 (2-bit column select: 0,1,2)
// start_fifo -- relay of start to fifo_ctrl instances
// conv_valid -- pulses at col_cnt=3 (conv output ready for maxpool write)
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

module group1_ctrl (
 input wire clk,
 input wire rst, // async active-high

 // From accelerator controller (or group1_top)
 input wire start, // begin processing; relayed to FIFO controllers

 // From fifo_ctrl (3x3 conv FIFO controller /)
 input wire [1:0] fsm_state, // IDLE=0, LDROW=1, LDWIN=2, PROCESS=3

 // To conv3x3_core
 output wire en, // pipeline enable: 1 while in PROCESS state
 output wire acc_clr, // 1 at col_cnt=0,1 (clear/first capture); 0 at 2,3

 // To weights_rom_3x3
 output wire [1:0] addr, // kernel column select: 0, 1, or 2

 // Relay to both fifo_ctrl instances (conv FIFO and pool FIFO)
 output wire start_fifo,

 // Strobes and status
 output wire conv_valid // high at drain cycle (col_cnt=3); conv output ready
);

 // -------------------------------------------------------------------------
 // FSM state codes from fifo_ctrl.v
 // -------------------------------------------------------------------------
 localparam [1:0] S_IDLE = 2'd0;
 localparam [1:0] S_PROCESS = 2'd3;

 // -------------------------------------------------------------------------
 // in_process: 1 when fifo_ctrl is actively shifting the conv window
 // -------------------------------------------------------------------------
 wire in_process = (fsm_state == S_PROCESS);

 // -------------------------------------------------------------------------
 // col_cnt: 2-bit counter cycling 0->1->2->3->0 during PROCESS state.
 // Advances every clock in PROCESS; holds at 0 when idle.
 // -------------------------------------------------------------------------
 reg [1:0] col_cnt;

 always @(posedge clk or posedge rst) begin
 if (rst)
 col_cnt <= 2'd0;
 else if (in_process)
 col_cnt <= col_cnt + 2'd1; // wraps 3->0 automatically (2-bit)
 else
 col_cnt <= 2'd0;
 end

 // -------------------------------------------------------------------------
 // Output assignments -- purely combinational (counters + logic)
 // -------------------------------------------------------------------------

 // Pipeline enable: asserted throughout PROCESS state
 assign en = in_process;

 // Accumulator clear:
 // col_cnt=0,1: acc_clr=1 (first two cycles; second is the real capture)
 // col_cnt=2,3: acc_clr=0 (accumulate + drain)
 assign acc_clr = in_process & (col_cnt[1] == 1'b0); // col_cnt<2 -> acc_clr=1

 // Weight ROM column address (wraps at 2; at drain col_cnt=3 → addr=0, don't care)
 assign addr = (col_cnt == 2'd3) ? 2'd0 : col_cnt;

 // start relay -- pass start signal directly to both FIFO controllers
 assign start_fifo = start;

 // conv_valid: pulses at the drain cycle (col_cnt=3); after this posedge
 // conv3x3_core.results_flat is combinationally valid.
 assign conv_valid = in_process & (col_cnt == 2'd3);

endmodule

`default_nettype wire
// =============================================================================
// END group1_ctrl.v
// =============================================================================
