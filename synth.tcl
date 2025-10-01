set outputDir ./build
file mkdir $outputDir

# Read design sources
read_verilog -sv rtl/TRIGGER_DELAY_DEFS.vh
read_verilog -sv rtl/core/CDC_EDGE_DETECT.sv
read_verilog -sv rtl/core/CONFIGURABLE_DELAY.sv
read_verilog -sv rtl/core/TRIGGER_DELAY_ENHANCED.sv
read_verilog -sv rtl/mmcm/MMCM_FINE_DELAY.sv
read_verilog -sv rtl/uart/UART_RX.sv
read_verilog -sv rtl/uart/UART_TX.sv
read_verilog -sv rtl/TRIGGER_DELAY_TOP.sv

read_xdc constraints/trigger_delay_arty.xdc

# Synthesis
synth_design -top TRIGGER_DELAY_TOP -part xc7a35ticsg324-1L

write_checkpoint -force $outputDir/post_synth.dcp
report_timing_summary -file $outputDir/post_synth_timing_summary.rpt
report_utilization -file $outputDir/post_synth_util.rpt

# Implementation
opt_design
place_design
report_clock_utilization -file $outputDir/clock_util.rpt

if {[get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]] < 0} {
    puts "Found setup timing violations => running physical optimization"
    phys_opt_design
}

write_checkpoint -force $outputDir/post_place.dcp
report_utilization -file $outputDir/post_place_util.rpt
report_timing_summary -file $outputDir/post_place_timing_summary.rpt

# Route
route_design
write_checkpoint -force $outputDir/post_route.dcp
report_route_status -file $outputDir/post_route_status.rpt
report_timing_summary -file $outputDir/post_route_timing_summary.rpt
report_power -file $outputDir/post_route_power.rpt
report_drc -file $outputDir/post_imp_drc.rpt
write_verilog -force $outputDir/impl_netlist.v -mode timesim -sdf_anno true

# Generate bitstream
write_bitstream -force $outputDir/trigger_delay.bit