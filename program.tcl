# Program FPGA directly (volatile - lost on power cycle)

open_hw_manager
connect_hw_server
open_hw_target localhost:3121/xilinx_tcf/Digilent/210319788922A

set hw_device [lindex [get_hw_devices] 0]
set_property PROGRAM.FILE "build/trigger_delay.bit" $hw_device

program_hw_devices $hw_device
refresh_hw_device $hw_device

close_hw_manager

puts "FPGA programmed successfully (volatile)"
