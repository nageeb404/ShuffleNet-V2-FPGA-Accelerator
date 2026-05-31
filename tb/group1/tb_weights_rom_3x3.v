`timescale 1ns/1ps
`default_nettype none
`include "shufflenet_pkg.vh"

// Self-contained testbench for weights_rom_3x3 (Module 1.8)
// G1_CONV_WW=12 (was 15). Combinational LUT ROM, addr[1:0] selects column.
// Test: all 3 column addresses produce non-X outputs.

module tb_weights_rom_3x3;
    localparam N_FILT = `G1_CONV_PAR_FILT;
    localparam W_W    = `G1_CONV_WW;
    localparam FLAT_W = N_FILT * 9 * W_W;

    reg [1:0] addr;
    wire signed [FLAT_W-1:0] weights_flat;
    weights_rom_3x3 dut(.addr(addr),.weights_flat(weights_flat));

    integer pass_cnt=0, fail_cnt=0, total=0, f, t;

    task chk_col;
        input [1:0] col;
        begin
            addr=col; #2;
            for (f=0; f<N_FILT; f=f+1)
                for (t=0; t<9; t=t+1) begin
                    total=total+1;
                    if (^weights_flat[(f*9+t)*W_W +:W_W]===1'bx) begin
                        $display("FAIL col=%0d f=%0d t=%0d X",col,f,t);
                        fail_cnt=fail_cnt+1;
                    end else pass_cnt=pass_cnt+1;
                end
        end
    endtask

    initial begin
        $display("=== tb_weights_rom_3x3 ===");
        chk_col(0); chk_col(1); chk_col(2);
        $display("PASS: %0d / %0d", pass_cnt, total);
        $display("FAIL: %0d / %0d", fail_cnt, total);
        if (fail_cnt==0) $display("RESULT: *** ALL TESTS PASSED ***");
        else             $display("RESULT: *** %0d TESTS FAILED ***", fail_cnt);
        $display("=========================================================");
        $finish;
    end
endmodule
`default_nettype wire
