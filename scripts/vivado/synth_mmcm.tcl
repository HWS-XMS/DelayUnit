set outputDir ./build
file mkdir $outputDir

# Set project root relative to script location  
set projRoot [file normalize [file dirname [info script]]/../..]

# Read design sources
read_verilog -sv $projRoot/rtl/trigger_delay_defs.vh
read_verilog -sv $projRoot/rtl/core/CDC_EDGE_DETECT.sv
read_verilog -sv $projRoot/rtl/core/CONFIGURABLE_DELAY.sv
read_verilog -sv $projRoot/rtl/core/TRIGGER_DELAY_ENHANCED.sv
read_verilog -sv $projRoot/rtl/mmcm/MMCM_FINE_DELAY.sv
read_verilog -sv $projRoot/rtl/uart/UART_RX.sv
read_verilog -sv $projRoot/rtl/uart/UART_TX.sv
read_verilog -sv $projRoot/rtl/TRIGGER_DELAY_TOP_MMCM.sv

read_xdc $projRoot/constraints/trigger_delay_arty.xdc

# Synthesis with MMCM
synth_design -top TRIGGER_DELAY_TOP_MMCM -part xc7a35ticsg324-1L

write_checkpoint -force $outputDir/post_synth_mmcm.dcp
report_timing_summary -file $outputDir/post_synth_mmcm_timing_summary.rpt
report_utilization -file $outputDir/post_synth_mmcm_util.rpt

# Implementation
opt_design
place_design
report_clock_utilization -file $outputDir/clock_util_mmcm.rpt

if {[get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]] < 0} {
    puts "Found setup timing violations => running physical optimization"
    phys_opt_design
}

write_checkpoint -force $outputDir/post_place_mmcm.dcp
report_utilization -file $outputDir/post_place_mmcm_util.rpt
report_timing_summary -file $outputDir/post_place_mmcm_timing_summary.rpt

# Route
route_design
write_checkpoint -force $outputDir/post_route_mmcm.dcp
report_route_status -file $outputDir/post_route_mmcm_status.rpt
report_timing_summary -file $outputDir/post_route_mmcm_timing_summary.rpt
report_power -file $outputDir/post_route_mmcm_power.rpt
report_drc -file $outputDir/post_imp_mmcm_drc.rpt
write_verilog -force $outputDir/impl_netlist_mmcm.v -mode timesim -sdf_anno true

# Generate bitstream
write_bitstream -force $outputDir/trigger_delay_mmcm.bit