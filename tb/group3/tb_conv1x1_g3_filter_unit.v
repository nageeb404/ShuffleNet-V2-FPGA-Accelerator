`timescale 1ns/1ps
`default_nettype none
`include "shufflenet_pkg.vh"

// Self-contained testbench for conv1x1_g3_filter_unit (Group 3 PW filter)
// N_CHAN=29, IN_W=12, W_W=9, OUT_W=27 (full precision, NO quantizer).
// DROP_LSB=7, MAC_OUT_W=14. Timing: nacc steps + wait (acc not gated on en).

module tb_conv1x1_g3_filter_unit;

    localparam N_CHAN   = `G3_PW_PAR_CHAN;  // 29
    localparam IN_W    = `G2_FM_W;          // 12
    localparam W_W     = `G3_PW_WW;         // 9
    localparam BIAS_WD = `DATA_W;           // 15
    localparam DROP_LSB = 7;
    localparam OUT_W   = `G3_CONV_OUT_W;    // 27

    reg clk=0; always #5 clk=~clk;
    reg rst=1; reg en=0, acc_clr=0;

    reg signed [IN_W-1:0]   d0,d1,d2,d3,d4,d5,d6,d7,d8,d9,d10,d11,d12,d13,d14,
                             d15,d16,d17,d18,d19,d20,d21,d22,d23,d24,d25,d26,d27,d28;
    reg signed [W_W-1:0]    w0,w1,w2,w3,w4,w5,w6,w7,w8,w9,w10,w11,w12,w13,w14,
                             w15,w16,w17,w18,w19,w20,w21,w22,w23,w24,w25,w26,w27,w28;
    reg signed [BIAS_WD-1:0] bias;
    wire signed [OUT_W-1:0]  result;

    conv1x1_g3_filter_unit dut(
        .clk(clk),.rst(rst),.en(en),.acc_clr(acc_clr),
        .d0(d0),.d1(d1),.d2(d2),.d3(d3),.d4(d4),.d5(d5),.d6(d6),.d7(d7),.d8(d8),
        .d9(d9),.d10(d10),.d11(d11),.d12(d12),.d13(d13),.d14(d14),.d15(d15),
        .d16(d16),.d17(d17),.d18(d18),.d19(d19),.d20(d20),.d21(d21),.d22(d22),
        .d23(d23),.d24(d24),.d25(d25),.d26(d26),.d27(d27),.d28(d28),
        .w0(w0),.w1(w1),.w2(w2),.w3(w3),.w4(w4),.w5(w5),.w6(w6),.w7(w7),.w8(w8),
        .w9(w9),.w10(w10),.w11(w11),.w12(w12),.w13(w13),.w14(w14),.w15(w15),
        .w16(w16),.w17(w17),.w18(w18),.w19(w19),.w20(w20),.w21(w21),.w22(w22),
        .w23(w23),.w24(w24),.w25(w25),.w26(w26),.w27(w27),.w28(w28),
        .bias(bias),.result(result));

    integer pass_cnt=0, fail_cnt=0, total=0, s;

    task do_reset;
        begin rst=1; en=0; acc_clr=0;
              repeat(4) @(posedge clk); rst=0; @(posedge clk); end
    endtask

    task set_all_d; input signed [IN_W-1:0] v;
        begin {d0,d1,d2,d3,d4,d5,d6,d7,d8,d9,d10,d11,d12,d13,d14,
               d15,d16,d17,d18,d19,d20,d21,d22,d23,d24,d25,d26,d27,d28}={29{v}}; end
    endtask
    task set_all_w; input signed [W_W-1:0] v;
        begin {w0,w1,w2,w3,w4,w5,w6,w7,w8,w9,w10,w11,w12,w13,w14,
               w15,w16,w17,w18,w19,w20,w21,w22,w23,w24,w25,w26,w27,w28}={29{v}}; end
    endtask

    // Golden: (nacc+1) accumulations (wait step adds one more), no quantizer
    function signed [OUT_W-1:0] golden;
        input signed [IN_W-1:0]   dv;
        input signed [W_W-1:0]    wv;
        input signed [BIAS_WD-1:0] bv;
        input integer nacc;
        reg signed [47:0] mac_v, acc_v;
        begin
            mac_v = ($signed(dv)*$signed(wv)) >>> DROP_LSB;
            acc_v = (nacc+1) * (N_CHAN * mac_v) + bv;
            // one-sided: negative → 0 (ReLU applied in group3 PW layer)
        if (acc_v <= 0) golden = {OUT_W{1'b0}};
        else            golden = acc_v[OUT_W-1:0];
        end
    endfunction

    task run_test;
        input signed [IN_W-1:0]   dv;
        input signed [W_W-1:0]    wv;
        input signed [BIAS_WD-1:0] bv;
        input integer nacc;
        input signed [OUT_W-1:0]   exp;
        begin
            set_all_d(dv); set_all_w(wv); bias=bv;
            for (s=0; s<=nacc; s=s+1) begin
                @(negedge clk); en=1; acc_clr=(s<=1)?1'b1:1'b0;
            end
            @(negedge clk); en=0; acc_clr=0;
            @(posedge clk); #1;
            total=total+1;
            if (result!==exp) begin
                $display("FAIL d=%0d w=%0d b=%0d nacc=%0d: got=%0d exp=%0d",
                    $signed(dv),$signed(wv),$signed(bv),nacc,$signed(result),$signed(exp));
                fail_cnt=fail_cnt+1;
            end else pass_cnt=pass_cnt+1;
            en=0; acc_clr=0; do_reset;
        end
    endtask

    initial begin
        $display("=== tb_conv1x1_g3_filter_unit ===");
        do_reset;
        run_test(0, 0, 0, 2, 0);
        run_test(4, 1, 0, 2, golden(4, 1, 0, 2));
        run_test(1, 4, 0, 2, golden(1, 4, 0, 2));
        run_test(8, 2, 100, 4, golden(8, 2, 100, 4));
        run_test(-4, 1, 0, 2, golden(-4, 1, 0, 2)); // negative output (no ReLU)

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
