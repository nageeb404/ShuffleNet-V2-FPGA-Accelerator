# =============================================================================
# shufflenet.xdc -- Constraints for ShuffleNet V2 on iWave ZU19EG (BD flow)
# =============================================================================
# NOTE: In the Block Design flow, the PS XDC automatically constrains pl_clk0
# at 100 MHz. The MMCM inside shufflenet_board_top takes that 100 MHz input
# and Vivado auto-derives the CLKOUT0 generated clock. No create_clock needed.
#
# s_axi_aclk and s_axi_aresetn are INTERNAL BD signals connected from the PS,
# NOT top-level ports -- any get_ports constraint on them will fail and is omitted.
# =============================================================================

# MMCM output clock: auto-derived by Vivado BD from the PS pl_clk0 input.
# No create_generated_clock needed here -- the BD XDC already defines it.
