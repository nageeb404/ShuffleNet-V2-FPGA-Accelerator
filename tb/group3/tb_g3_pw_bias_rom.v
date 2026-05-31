`timescale 1ns/1ps
`default_nettype none
// ROM test: g3_pw_bias_rom (distributed, 64 entries, 240 bits)
module tb_g3_pw_bias_rom;
    reg [5:0] addr=0;
    wire [239:0] data_out;
    g3_pw_bias_rom dut(.addr(addr),.data_out(data_out));
    integer pass_cnt=0, fail_cnt=0, total=0;
    initial begin
        $display("=== tb_g3_pw_bias_rom ===");
        #2;
        total=total+1;
        if (^data_out===1'bx) begin $display("FAIL addr=0 X"); fail_cnt=fail_cnt+1; end
        else pass_cnt=pass_cnt+1;
        addr=63; #2;
        total=total+1;
        if (^data_out===1'bx) begin $display("FAIL addr=63 X"); fail_cnt=fail_cnt+1; end
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
