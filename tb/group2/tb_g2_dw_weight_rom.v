`timescale 1ns/1ps
`default_nettype none
// ROM test: g2_dw_weight_rom (distributed/combinational, 16 entries, 7830 bits)
// No clk — purely combinational. Check non-X outputs for all 16 addresses.
module tb_g2_dw_weight_rom;
    reg [3:0] addr;
    wire [7829:0] data_out;
    g2_dw_weight_rom dut(.addr(addr),.data_out(data_out));
    integer pass_cnt=0, fail_cnt=0, total=0, a;
    initial begin
        $display("=== tb_g2_dw_weight_rom ===");
        for (a=0; a<16; a=a+1) begin
            addr=a; #2;
            total=total+1;
            if (^data_out===1'bx) begin
                $display("FAIL addr=%0d: X output",a);
                fail_cnt=fail_cnt+1;
            end else pass_cnt=pass_cnt+1;
        end
        $display("PASS: %0d / %0d", pass_cnt, total);
        $display("FAIL: %0d / %0d", fail_cnt, total);
        if (fail_cnt==0) $display("RESULT: *** ALL TESTS PASSED ***");
        else             $display("RESULT: *** %0d TESTS FAILED ***", fail_cnt);
        $display("=========================================================");
        $finish;
    end
endmodule
`default_nettype wire
