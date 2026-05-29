`timescale 1ns / 1ps
`default_nettype none
`include "shufflenet_pkg.vh"

// Black-box stub for fc_core -- used only for group3_no_fc OOC synthesis run.
// Provides the port declaration so Vivado resolves parameterized widths without
// elaborating fc_core's internals (1000x1024 weight logic kills RAM during opt).
module fc_core #(
    parameter integer N_PAR  = `G3_FC_PAR_CHAN,
    parameter integer DATA_W = `DATA_W
) (
    input  wire clk,
    input  wire rst,
    input  wire en,
    input  wire acc_clr,

    input  wire signed [DATA_W-1:0] d0,  d1,  d2,  d3,  d4,  d5,  d6,  d7,
    input  wire signed [DATA_W-1:0] d8,  d9,  d10, d11, d12, d13, d14, d15,
    input  wire signed [DATA_W-1:0] d16, d17, d18, d19, d20, d21, d22, d23,
    input  wire signed [DATA_W-1:0] d24, d25, d26, d27, d28, d29, d30, d31,

    input  wire signed [DATA_W-1:0] w0,  w1,  w2,  w3,  w4,  w5,  w6,  w7,
    input  wire signed [DATA_W-1:0] w8,  w9,  w10, w11, w12, w13, w14, w15,
    input  wire signed [DATA_W-1:0] w16, w17, w18, w19, w20, w21, w22, w23,
    input  wire signed [DATA_W-1:0] w24, w25, w26, w27, w28, w29, w30, w31,

    input  wire signed [DATA_W-1:0] bias,
    output wire signed [DATA_W-1:0] result
);
    // result must depend on inputs to prevent Vivado from pruning upstream logic
    assign result = d0 ^ w0 ^ bias;
endmodule

`default_nettype wire
