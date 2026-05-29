// =============================================================================
// tb_accelerator_ctrl.v -- Self-checking testbench for Module 4.1
// -----------------------------------------------------------------------------
// / Figure 5.70
//
// Tests the 5-state FSM transitions:
// 1. IDLE -> G1 on photo_ready
// 2. G1 -> G1_2 on group1_done (with and without photo_ready)
// 3. G1_2 -> G1_2_3 on group2_done
// 4. G1_2_3 -> IDLE on group3_done (no new image)
// 5. G1_2_3 -> G1_3 -> G1_2 (full pipeline with new images)
// 6. busy assertion/deassertion
// 7. ping_pong_sel toggle
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module tb_accelerator_ctrl;

    reg clk, rst;
    initial clk = 1'b0;
    always #5 clk = ~clk;

    reg photo_ready;
    reg group1_done, group2_done, group3_done;

    wire group1_start, group2_start, group3_start;
    wire busy, ping_pong_sel;
    wire [2:0] fsm_state;

    accelerator_ctrl dut (
        .clk         (clk),
        .rst         (rst),
        .photo_ready (photo_ready),
        .busy        (busy),
        .group1_start(group1_start),
        .group2_start(group2_start),
        .group3_start(group3_start),
        .group1_done (group1_done),
        .group2_done (group2_done),
        .group3_done (group3_done),
        .ping_pong_sel(ping_pong_sel),
        .fsm_state   (fsm_state)
    );

    // State name constants
    localparam S_IDLE   = 3'd0;
    localparam S_G1     = 3'd1;
    localparam S_G1_2   = 3'd2;
    localparam S_G1_2_3 = 3'd3;
    localparam S_G1_3   = 3'd4;

    integer pass_count, fail_count, dump_count;

    task check;
        input integer cond;
        input [8*80-1:0] msg;
        begin
            if (cond)
                pass_count = pass_count + 1;
            else begin
                fail_count = fail_count + 1;
                if (dump_count < 16) begin
                    $display("FAIL: %0s  (state=%0d)", msg, fsm_state);
                    dump_count = dump_count + 1;
                end
            end
        end
    endtask

    // Helper: pulse a done signal for 1 cycle
    task pulse_done;
        input integer which;  // 1=g1, 2=g2, 3=g3
        begin
            @(negedge clk);
            if (which == 1) group1_done = 1'b1;
            if (which == 2) group2_done = 1'b1;
            if (which == 3) group3_done = 1'b1;
            @(posedge clk); #1;
            group1_done = 1'b0;
            group2_done = 1'b0;
            group3_done = 1'b0;
        end
    endtask

    initial begin
        pass_count  = 0; fail_count = 0; dump_count = 0;
        rst         = 1'b1;
        photo_ready = 1'b0;
        group1_done = 1'b0;
        group2_done = 1'b0;
        group3_done = 1'b0;

        $display("=========================================================");
        $display("accelerator_ctrl Testbench");
        $display("=========================================================");

        #20; @(negedge clk); rst = 1'b0;
        @(posedge clk); #1;

        // ---- Test 1: IDLE after reset ----
        check((fsm_state === S_IDLE),   "T1: IDLE after reset");
        check((busy       === 1'b0),    "T1: busy=0 in IDLE");
        check((group1_start=== 1'b0),   "T1: group1_start=0 in IDLE");

        // ---- Test 2: IDLE -> G1 on photo_ready ----
        @(negedge clk); photo_ready = 1'b1;
        @(posedge clk); #1;
        photo_ready = 1'b0;

        check((fsm_state   === S_G1),   "T2: G1 after photo_ready");
        check((group1_start=== 1'b1),   "T2: group1_start=1 on IDLE->G1");
        check((busy        === 1'b1),   "T2: busy=1 in G1");
        check((ping_pong_sel=== 1'b1),  "T2: ping_pong_sel toggled to 1");

        // ---- Test 3: G1 -> G1_2 on group1_done (no new image) ----
        @(posedge clk); #1;  // wait 1 cycle (start pulse gone)
        check((group1_start === 1'b0),  "T3: group1_start=0 cycle after pulse");

        pulse_done(1);  // assert group1_done for 1 cycle
        check((fsm_state    === S_G1_2),"T3: G1_2 after group1_done");
        check((group2_start === 1'b1),  "T3: group2_start=1 on G1->G1_2");

        // ---- Test 4: G1_2 -> G1_2_3 on group2_done ----
        @(posedge clk); #1;
        check((group2_start === 1'b0),  "T4: group2_start=0 after pulse");

        pulse_done(2);  // assert group2_done
        check((fsm_state    === S_G1_2_3), "T4: G1_2_3 after group2_done");
        check((group3_start === 1'b1),  "T4: group3_start=1 on G1_2->G1_2_3");

        // ---- Test 5: G1_2_3 -> IDLE on group3_done (no new image) ----
        @(posedge clk); #1;
        check((group3_start === 1'b0),  "T5: group3_start=0 after pulse");

        pulse_done(3);  // group3_done, photo_ready=0
        check((fsm_state  === S_IDLE),  "T5: IDLE after group3_done (no photo)");
        check((busy       === 1'b0),    "T5: busy=0 in IDLE");

        // ---- Test 6: Full pipeline (photo_ready keeps arriving) ----
        // Start fresh: G1
        @(negedge clk); photo_ready = 1'b1;
        @(posedge clk); #1;
        photo_ready = 1'b0;
        check((fsm_state   === S_G1),   "T6a: G1 started");

        // G1 done, photo_ready -> G1_2 (G1 restarts)
        @(negedge clk);
        photo_ready  = 1'b1;
        group1_done  = 1'b1;
        @(posedge clk); #1;
        photo_ready = 1'b0;
        group1_done = 1'b0;
        check((fsm_state    === S_G1_2),"T6b: G1_2 after G1 done + photo_ready");
        check((group2_start === 1'b1),  "T6b: group2_start fired");
        check((group1_start === 1'b1),  "T6b: group1_start fired (new image)");

        // G2 done -> G1_2_3
        pulse_done(2);
        check((fsm_state    === S_G1_2_3),"T6c: G1_2_3 after G2 done");
        check((group3_start === 1'b1),  "T6c: group3_start fired");

        // G3 done + photo_ready -> G1_3
        @(negedge clk);
        photo_ready  = 1'b1;
        group3_done  = 1'b1;
        @(posedge clk); #1;
        photo_ready = 1'b0;
        group3_done = 1'b0;
        check((fsm_state    === S_G1_3),"T6d: G1_3 after G3 done + photo_ready");
        check((group1_start === 1'b1),  "T6d: group1_start for new image");

        // G1 done, then G3 done (sequential) -> G1_2
        pulse_done(1);
        check((fsm_state !== S_G1_2),   "T6e: still G1_3 (waiting for G3)");
        @(negedge clk); photo_ready = 1'b1;
        group3_done = 1'b1;
        @(posedge clk); #1;
        photo_ready = 1'b0;
        group3_done = 1'b0;
        check((fsm_state    === S_G1_2),"T6f: G1_2 after both done in G1_3");
        check((group2_start === 1'b1),  "T6f: group2_start for queued image");

        // ---- Test 7: G1_3 with both done arriving same cycle ----
        // Wind down to IDLE
        pulse_done(2);  // finish G2
        pulse_done(3);  // finish G3 (no photo_ready) -> IDLE
        @(posedge clk); #1;
        check((fsm_state === S_IDLE),   "T7a: back to IDLE");

        // New image -> G1
        @(negedge clk); photo_ready = 1'b1;
        @(posedge clk); #1; photo_ready = 1'b0;
        // G1 done + photo -> G1_2; G2 done -> G1_2_3; G3 done + photo -> G1_3
        @(negedge clk); photo_ready = 1'b1; group1_done = 1'b1;
        @(posedge clk); #1; photo_ready = 1'b0; group1_done = 1'b0;
        pulse_done(2);
        @(negedge clk); photo_ready = 1'b1; group3_done = 1'b1;
        @(posedge clk); #1; photo_ready = 1'b0; group3_done = 1'b0;
        // Now in G1_3; drive G1 and G3 done simultaneously
        @(negedge clk);
        group1_done = 1'b1;
        group3_done = 1'b1;
        @(posedge clk); #1;
        group1_done = 1'b0;
        group3_done = 1'b0;
        check((fsm_state !== S_G1_3),   "T7b: left G1_3 after simultaneous done");

        // ---- Summary ----
        $display("---------------------------------------------------------");
        $display("Tested %0d checks", pass_count + fail_count);
        $display("PASS: %0d / %0d", pass_count, pass_count + fail_count);
        $display("FAIL: %0d / %0d", fail_count, pass_count + fail_count);
        if (fail_count == 0) $display("RESULT: *** ALL TESTS PASSED ***");
        else                 $display("RESULT: *** %0d TESTS FAILED ***", fail_count);
        $display("=========================================================");
        $finish;
    end

endmodule

`default_nettype wire
// =============================================================================
// END tb_accelerator_ctrl.v
// =============================================================================
