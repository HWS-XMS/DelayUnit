set outputDir ./build
file mkdir $outputDir

# Read design sources - Clock cycle delay only (5ns resolution @ 200MHz)
read_verilog -sv ../../rtl/TRIGGER_DELAY_DEFS.vh
read_verilog -sv ../../rtl/core/CDC_EDGE_DETECT.sv
read_verilog -sv ../../rtl/core/CONFIGURABLE_DELAY.sv
read_verilog -sv ../../rtl/uart/UART_RX.sv
read_verilog -sv ../../rtl/uart/UART_TX.sv
read_verilog -sv ../../rtl/TRIGGER_DELAY_TOP.sv

read_xdc constraints.xdc

# Synthesis for Nexys Video (XC7A200T)
synth_design -top TRIGGER_DELAY_TOP -part xc7a200tsbg484-1

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

# Set bitstream properties for SPI flash programming
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]

# Generate bitstream
write_bitstream -force $outputDir/trigger_delay.bit
