`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

(* black_box *)
module group2_top (
    input  wire clk,
    input  wire rst,
    input  wire start_group,
    output wire group2_done,
    input  wire [`G2_DW_PAR_FILT*`G1_FM_W-1:0] fm_data_in,
    output wire [11:0]                          fm_rd_addr,
    output wire [`G2_PW_PAR_FILT*`G2_FM_W-1:0] pw_results_flat,
    output wire [11:0]                          pw_wr_addr,
    output wire                                 pw_we,
    output wire [4:0]                           loops,
    output wire [1:0]                           fsm_state
);
endmodule
