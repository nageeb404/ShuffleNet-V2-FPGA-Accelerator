`timescale 1ns/1ps
`default_nettype none
// ROM test: g3_pw_weight_rom (BRAM, 1024 entries, 4176 bits each)
module tb_g3_pw_weight_rom;
    reg clk=0; always #5 clk=~clk;
    reg [9:0] addr=0;
    wire [4175:0] data_out;
    g3_pw_weight_rom dut(.clk(clk),.addr(addr),.data_out(data_out));
    integer pass_cnt=0, fail_cnt=0, total=0;
    initial begin
        $display("=== tb_g3_pw_weight_rom ===");
        @(posedge clk); @(posedge clk); #1;
        total=total+1;
        if (^data_out===1'bx) begin $display("FAIL addr=0 X"); fail_cnt=fail_cnt+1; end
        else pass_cnt=pass_cnt+1;
        $display("PASS: %0d / %0d", pass_cnt, total);
        $display("FAIL: %0d / %0d", fail_cnt, total);
        if (fail_cnt==0) $display("RESULT: *** ALL TESTS PASSED ***");
        else             $display("RESULT: *** %0d TESTS FAILED ***", fail_cnt);
        $display("=========================================================");
        $finish;
    end
endmodule
`default_nettype wire
