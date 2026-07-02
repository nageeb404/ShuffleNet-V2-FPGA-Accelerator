# run_all_sims_v2.ps1
# Runs all 48 testbenches using the individual per-TB TCL scripts.
# Each TB gets its own fresh Vivado batch process in its own work dir,
# calling xvlog/xelab/xsim directly -- avoids launch_simulation entirely.
#
# Usage (from N:\GP\shufflenet_v2_fpga\):
#   powershell -ExecutionPolicy Bypass -File vivado\scripts\run_all_sims_v2.ps1
#
# Output: vivado\scripts\run_all_sims_v2.log  (per-TB output for failed TBs)

$vivado    = "N:\Xilinx\Vivado\2024.2\bin\vivado.bat"
$base      = "N:\GP\shufflenet_v2_fpga\vivado\scripts"
$log_file  = "$base\run_all_sims_v2.log"

$tb_scripts = @(
    # --- common ---
    "common\sim_tb_Adder3.tcl",
    "common\sim_tb_adder_tree_9.tcl",
    "common\sim_tb_adder_tree_29.tcl",
    "common\sim_tb_adder_tree_32.tcl",
    "common\sim_tb_adder_tree_12.tcl",
    "common\sim_tb_fifo_3x3.tcl",
    "common\sim_tb_fifo_ctrl.tcl",
    "common\sim_tb_mac_unit.tcl",
    "common\sim_tb_quantizer.tcl",
    # --- group1 ---
    "group1\sim_tb_bias_rom_3x3.tcl",
    "group1\sim_tb_conv3x3_core.tcl",
    "group1\sim_tb_conv3x3_filter_unit.tcl",
    "group1\sim_tb_fifo_pool.tcl",
    "group1\sim_tb_group1_ctrl.tcl",
    "group1\sim_tb_group1_top.tcl",
    "group1\sim_tb_maxpool_core.tcl",
    "group1\sim_tb_maxpool_mem.tcl",
    "group1\sim_tb_photo_mem.tcl",
    "group1\sim_tb_weights_rom_3x3.tcl",
    # --- group2 ---
    "group2\sim_tb_conv1x1_core.tcl",
    "group2\sim_tb_conv1x1_ctrl.tcl",
    "group2\sim_tb_conv1x1_filter_unit.tcl",
    "group2\sim_tb_dw_conv3x3_core.tcl",
    "group2\sim_tb_dw_conv3x3_ctrl.tcl",
    "group2\sim_tb_dw_conv3x3_filter_unit.tcl",
    "group2\sim_tb_g2_dw_bias_rom.tcl",
    "group2\sim_tb_g2_dw_weight_rom.tcl",
    "group2\sim_tb_g2_pw_bias_rom.tcl",
    "group2\sim_tb_g2_pw_weight_rom.tcl",
    "group2\sim_tb_group2_ctrl.tcl",
    "group2\sim_tb_group2_fifo.tcl",
    "group2\sim_tb_group2_fifo_ctrl.tcl",
    "group2\sim_tb_group2_top.tcl",
    # --- group3 ---
    "group3\sim_tb_avg_pool_core.tcl",
    "group3\sim_tb_conv1x1_g3_core.tcl",
    "group3\sim_tb_conv1x1_g3_filter_unit.tcl",
    "group3\sim_tb_fc_core.tcl",
    "group3\sim_tb_fc_filter_unit.tcl",
    "group3\sim_tb_g3_fc_bias_rom.tcl",
    "group3\sim_tb_g3_fc_weight_rom.tcl",
    "group3\sim_tb_g3_pw_bias_rom.tcl",
    "group3\sim_tb_g3_pw_weight_rom.tcl",
    "group3\sim_tb_group3_ctrl.tcl",
    "group3\sim_tb_group3_top.tcl",
    # --- misc ---
    "memories\sim_tb_extra_mem.tcl",
    "axi\sim_tb_axi_photo_mem_slave.tcl",
    "sim_tb_accelerator_ctrl.tcl",
    "sim_tb_accelerator_top.tcl"
)

$pass_list  = @()
$fail_list  = @()
$error_list = @()
$total = $tb_scripts.Count
$idx   = 0

"" | Out-File $log_file -Encoding utf8
"run_all_sims_v2.ps1  $(Get-Date)" | Out-File $log_file -Encoding utf8 -Append
"=" * 60 | Out-File $log_file -Encoding utf8 -Append

foreach ($script in $tb_scripts) {
    $idx++
    $leaf    = [System.IO.Path]::GetFileNameWithoutExtension($script)
    $tb_name = $leaf -replace "^sim_", ""
    $full    = Join-Path $base $script

    Write-Host ""
    Write-Host "[SIM $idx/$total] $tb_name ..." -NoNewline

    $output  = & $vivado -mode batch -source $full -nojournal -nolog
    $out_str = $output -join "`n"

    if     ($out_str -match "ALL TESTS PASSED")           { $status = "PASS" }
    elseif ($out_str -match "TESTS FAILED|TEST FAILED|FAIL") { $status = "FAIL" }
    elseif ($out_str -match "xvlog failed|xelab failed|xsim failed") { $status = "ERROR" }
    elseif ($out_str -match "ERROR:")                     { $status = "ERROR" }
    else                                                  { $status = "UNKNOWN" }

    Write-Host "  --> $status"

    switch ($status) {
        "PASS"  { $pass_list  += $tb_name }
        "FAIL"  { $fail_list  += $tb_name; "[FAIL] $tb_name" | Out-File $log_file -Append; $out_str | Out-File $log_file -Append; "-"*60 | Out-File $log_file -Append }
        default { $error_list += $tb_name; "[ERROR/$status] $tb_name" | Out-File $log_file -Append; $out_str | Out-File $log_file -Append; "-"*60 | Out-File $log_file -Append }
    }
}

$summary = @"

============================================================
  SIMULATION SUMMARY  ($total TBs)  -- $(Get-Date)
============================================================
  PASS  : $($pass_list.Count)
$(($pass_list | ForEach-Object { "    + $_" }) -join "`n")
  FAIL  : $($fail_list.Count)
$(($fail_list | ForEach-Object { "    - $_" }) -join "`n")
  ERROR : $($error_list.Count)
$(($error_list | ForEach-Object { "    ! $_" }) -join "`n")
============================================================
"@

Write-Host $summary
$summary | Out-File $log_file -Encoding utf8 -Append
