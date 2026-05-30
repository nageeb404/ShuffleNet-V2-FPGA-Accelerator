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

# MMCM output: explicitly named so timing reports are readable.
# Vivado infers the master clock automatically from CLKIN1.
create_generated_clock -name clk_100m \
    -source [get_pins -hierarchical -filter {NAME =~ */u_mmcm/CLKIN1}] \
    -multiply_by 10 -divide_by 10 \
    [get_pins -hierarchical -filter {NAME =~ */u_mmcm/CLKOUT0}]
