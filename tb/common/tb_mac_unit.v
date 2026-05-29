// =============================================================================
// tb_mac_unit.v - Self-checking testbench for mac_unit
// -----------------------------------------------------------------------------
// Methodology: (Python golden -> hex -> $readmemh -> compare)
// Differences from Phase 0 TBs (Adder3, quantizer):
// - mac_unit is SEQUENTIAL (it has a pipeline register on the output).
// - Need a clock and a reset.
// - Account for the 1-cycle latency between driving inputs and sampling
// the output.
// TB strategy:
// 1) Generate clock at 100 MHz (10 ns period -- matches the target
// from Sec 9.1.2.2).
// 2) Assert async reset for a few cycles, then deassert.
// 3) For each vector i, drive inputs at clock edge T_i.
// At T_{i+1}, sample p_out (it now holds the product of vector i).
// 4) Compare against the expected value.
// Run (with Vivado XSim):
// vivado -mode batch -source vivado/scripts/sim_tb_mac_unit.tcl
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "shufflenet_pkg.vh"

module tb_mac_unit;

 // ---- Parameters (must match the Python generator) ----
 localparam integer DATA_W = `DATA_W; // 15
 localparam integer MUL_OUT_W = `MUL_OUT_W; // 23
 localparam integer MAX_VEC = 4096;

 // ---- Clock and reset ----
 reg clk;
 reg rst;
 reg en;

 initial clk = 1'b0;
 always #5 clk = ~clk; // 100 MHz: 5 ns half-period

 // ---- Vector storage ----
 reg signed [DATA_W -1:0] v_a [0:MAX_VEC-1];
 reg signed [DATA_W -1:0] v_b [0:MAX_VEC-1];
 reg signed [MUL_OUT_W-1:0] v_exp [0:MAX_VEC-1];

 // ---- DUT instance ----
 reg signed [DATA_W -1:0] a_i, b_i;
 wire signed [MUL_OUT_W-1:0] p_o;

 mac_unit #(
 .DATA_W (DATA_W),
 .MUL_OUT_W(MUL_OUT_W)
 ) dut (
 .clk (clk),
 .rst (rst),
 .en (en),
 .a_data (a_i),
 .b_weight(b_i),
 .p_out (p_o)
 );

 // ---- Vector loading ----
 integer fd;
 integer scan_status;
 integer n_vectors;
 integer i;
 integer pass_count, fail_count;
 integer dump_count;

 reg [DATA_W -1:0] tmp_a, tmp_b;
 reg [MUL_OUT_W-1:0] tmp_exp;
 reg [1023:0] line;
 integer r;

 initial begin
 n_vectors = 0;
 pass_count = 0;
 fail_count = 0;
 dump_count = 0;
 rst = 1'b1; // assert reset at time 0
 en = 1'b0;
 a_i = {DATA_W{1'b0}};
 b_i = {DATA_W{1'b0}};

 $display("=========================================================");
 $display("mac_unit Self-Checking Testbench");
 $display("=========================================================");

 // ---- Open vector file ----
 begin : open_file
 reg [8*512-1:0] path_arg;
 integer have_arg;
 have_arg = $value$plusargs("VECTORS=%s", path_arg);
 if (have_arg)
 fd = $fopen(path_arg, "r");
 else
 fd = $fopen("tb/common/vectors/mac_unit_vectors.hex", "r");
 if (fd == 0)
 fd = $fopen("../tb/common/vectors/mac_unit_vectors.hex", "r");
 if (fd == 0)
 fd = $fopen("./mac_unit_vectors.hex", "r");
 end
 if (fd == 0) begin
 $display("ERROR: cannot open mac_unit_vectors.hex");
 $display("Hint: pass +VECTORS=/absolute/path/mac_unit_vectors.hex");
 $finish;
 end

 // ---- Parse the file ----
 begin : load_loop
 while (!$feof(fd)) begin
 r = $fgets(line, fd);
 if (r == 0) disable load_loop;
 scan_status = $sscanf(line, "%h %h %h",
 tmp_a, tmp_b, tmp_exp);
 if (scan_status == 3) begin
 v_a [n_vectors] = $signed(tmp_a);
 v_b [n_vectors] = $signed(tmp_b);
 v_exp[n_vectors] = $signed(tmp_exp);
 n_vectors = n_vectors + 1;
 if (n_vectors >= MAX_VEC) disable load_loop;
 end
 end
 end
 $fclose(fd);

 $display("Loaded %0d vectors.", n_vectors);
 if (n_vectors == 0) begin
 $display("ERROR: no vectors loaded");
 $finish;
 end

 // ---- Reset sequence ----
 // Hold reset for 3 clock cycles, then deassert.
 #20; // a couple of cycles
 @(negedge clk);
 rst = 1'b0;
 en = 1'b1;
 @(negedge clk); // small settle

 // ---- Drive and check, accounting for 1-cycle pipeline latency ----
 // Drive vector i on negedge T_i.
 // At posedge T_{i+1} the registered p_out updates to product of vec i.
 // We sample p_out just after that posedge (i.e. at the next negedge).
 for (i = 0; i < n_vectors; i = i + 1) begin
 @(negedge clk);
 a_i = v_a[i];
 b_i = v_b[i];

 // Wait one more clock for the result to propagate through the
 // pipeline register and become observable.
 @(negedge clk);

 if (p_o === v_exp[i]) begin
 pass_count = pass_count + 1;
 end else begin
 fail_count = fail_count + 1;
 if (dump_count < 10) begin
 $display("FAIL #%0d: a=%0d b=%0d got=%0d exp=%0d",
 i, v_a[i], v_b[i], p_o, v_exp[i]);
 dump_count = dump_count + 1;
 end
 end
 end

 $display("---------------------------------------------------------");
 $display("PASS: %0d / %0d", pass_count, n_vectors);
 $display("FAIL: %0d / %0d", fail_count, n_vectors);
 if (fail_count == 0)
 $display("RESULT: *** ALL TESTS PASSED ***");
 else
 $display("RESULT: *** %0d TESTS FAILED ***", fail_count);
 $display("=========================================================");
 $finish;
 end

endmodule

`default_nettype wire
// =============================================================================
// END tb_mac_unit.v
// =============================================================================
