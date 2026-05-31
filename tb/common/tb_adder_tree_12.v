`timescale 1ns/1ps
`default_nettype none
`include "shufflenet_pkg.vh"

// Self-contained testbench for adder_tree_12 (added for G2 PW conv, PAR_CHAN=12)
// Combinational: 12 signed inputs -> 1 signed sum (+6 bits growth, 3 Adder3 levels)

module tb_adder_tree_12;

    localparam IN_W  = 15;
    localparam OUT_W = IN_W + 6; // 21

    reg signed [IN_W-1:0] in0,in1,in2,in3,in4,in5,in6,in7,in8,in9,in10,in11;
    wire signed [OUT_W-1:0] sum_out;

    adder_tree_12 #(.IN_W(IN_W)) dut(
        .in0(in0),.in1(in1),.in2(in2),.in3(in3),
        .in4(in4),.in5(in5),.in6(in6),.in7(in7),
        .in8(in8),.in9(in9),.in10(in10),.in11(in11),
        .sum_out(sum_out));

    integer pass_cnt=0, fail_cnt=0, total=0;

    task chk;
        input signed [OUT_W-1:0] exp;
        input [255:0] tag;
        begin
            #1;
            total=total+1;
            if (sum_out!==exp) begin
                $display("FAIL [%0s]: got=%0d exp=%0d",tag,$signed(sum_out),$signed(exp));
                fail_cnt=fail_cnt+1;
            end else pass_cnt=pass_cnt+1;
        end
    endtask

    task set_all; input signed [IN_W-1:0] v;
        begin {in0,in1,in2,in3,in4,in5,in6,in7,in8,in9,in10,in11}={12{v}}; end
    endtask

    initial begin
        $display("=== tb_adder_tree_12 ===");

        set_all(0); chk(0,"all_zero");
        set_all(1); chk(12,"all_one");
        set_all(100); chk(1200,"all_100");
        set_all(-1); chk(-12,"all_neg1");
        set_all(16383); chk(12*16383,"max_pos"); // 196596

        // Mixed: alternating 10 and -10
        {in0,in2,in4,in6,in8,in10} = {6{15'sd10}};
        {in1,in3,in5,in7,in9,in11} = {6{-15'sd10}};
        chk(0,"alternating");

        // Single non-zero: in0=50, rest 0
        set_all(0); in0=50; chk(50,"single_50");
        set_all(0); in11=75; chk(75,"last_75");

        // Known sum: 1+2+3+4+5+6+7+8+9+10+11+12=78
        in0=1;in1=2;in2=3;in3=4;in4=5;in5=6;
        in6=7;in7=8;in8=9;in9=10;in10=11;in11=12;
        chk(78,"seq_1to12");

        $display("---------------------------------------------------------");
        $display("PASS: %0d / %0d", pass_cnt, total);
        $display("FAIL: %0d / %0d", fail_cnt, total);
        if (fail_cnt==0) $display("RESULT: *** ALL TESTS PASSED ***");
        else             $display("RESULT: *** %0d TESTS FAILED ***", fail_cnt);
        $display("=========================================================");
        $finish;
    end
endmodule
`default_nettype wire
