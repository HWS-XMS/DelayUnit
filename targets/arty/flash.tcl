# Program Arty A7 SPI Flash with bitstream (persistent)

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target

# Get the FPGA device
current_hw_device [get_hw_devices xc7a35t_0]
refresh_hw_device -update_hw_probes false [lindex [get_hw_devices xc7a35t_0] 0]

# Create MCS file for flash programming
write_cfgmem -format mcs -size 16 -interface SPIx4 \
    -loadbit "up 0x0 build/trigger_delay.bit" \
    -force -file build/trigger_delay.mcs

# Program the flash
create_hw_cfgmem -hw_device [lindex [get_hw_devices xc7a35t_0] 0] \
    [lindex [get_cfgmem_parts {s25fl128sxxxxxx0-spi-x1_x2_x4}] 0]
set_property PROGRAM.BLANK_CHECK 0 [get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7a35t_0] 0]]
set_property PROGRAM.ERASE 1 [get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7a35t_0] 0]]
set_property PROGRAM.CFG_PROGRAM 1 [get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7a35t_0] 0]]
set_property PROGRAM.VERIFY 1 [get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7a35t_0] 0]]
set_property PROGRAM.CHECKSUM 0 [get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7a35t_0] 0]]
refresh_hw_device [lindex [get_hw_devices xc7a35t_0] 0]
set_property PROGRAM.ADDRESS_RANGE {use_file} [get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7a35t_0] 0]]
set_property PROGRAM.FILES [list "build/trigger_delay.mcs"] \
    [get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7a35t_0] 0]]
set_property PROGRAM.PRM_FILE {} [get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7a35t_0] 0]]
set_property PROGRAM.UNUSED_PIN_TERMINATION {pull-none} [get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7a35t_0] 0]]
set_property PROGRAM.BLANK_CHECK 0 [get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7a35t_0] 0]]
set_property PROGRAM.ERASE 1 [get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7a35t_0] 0]]
set_property PROGRAM.CFG_PROGRAM 1 [get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7a35t_0] 0]]
set_property PROGRAM.VERIFY 1 [get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7a35t_0] 0]]
set_property PROGRAM.CHECKSUM 0 [get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7a35t_0] 0]]
startgroup
create_hw_bitstream -hw_device [lindex [get_hw_devices xc7a35t_0] 0] \
    [get_property PROGRAM.HW_CFGMEM_BITFILE [lindex [get_hw_devices xc7a35t_0] 0]]
program_hw_cfgmem -hw_cfgmem [get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7a35t_0] 0]]
endgroup

close_hw_target
disconnect_hw_server
close_hw_manager
