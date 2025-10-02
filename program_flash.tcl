# Vivado TCL script to program SPI flash on Arty A7
# This allows the FPGA to boot from flash on power-up

set mode "QSPI"
set bitfile "build/trigger_delay.bit"
set binfile "build/trigger_delay.bin"

# Arty A7 uses either:
# - MT25QL128-SPI-X1_X2_X4 (16MB, Rev C)
# - S25FL128SXXXXXX0-SPI-X1_X2_X4 (16MB, Rev E)
# We'll use mt25ql128 as it's most common

puts "Step 1: Creating BIN file from bitstream..."

# Create BIN file for SPI flash
write_cfgmem -format bin -size 16 \
    -interface SPIx4 \
    -loadbit "up 0x0 $bitfile" \
    -force \
    -file $binfile

puts "BIN file created: $binfile"

puts "\nStep 2: Opening hardware and connecting..."

# Open hardware
open_hw
if {[current_hw_server] == ""} {
    connect_hw_server
}

# Get and open target
open_hw_target [lindex [get_hw_targets] 0]

# Get device
set hw_device [lindex [get_hw_devices] 0]
puts "Connected to device: $hw_device"

if {$mode == "QSPI"} {

    puts "\nStep 3: Creating configuration memory device..."

    # Create configuration memory for Arty A7
    create_hw_cfgmem -hw_device $hw_device [lindex [get_cfgmem_parts {mt25ql128-spi-x1_x2_x4}] 0]

    set hw_cfgmem [get_property PROGRAM.HW_CFGMEM $hw_device]

    puts "\nStep 4: Setting programming properties..."

    # Initial properties
    set_property PROGRAM.BLANK_CHECK 0 $hw_cfgmem
    set_property PROGRAM.ERASE 1 $hw_cfgmem
    set_property PROGRAM.CFG_PROGRAM 1 $hw_cfgmem
    set_property PROGRAM.VERIFY 1 $hw_cfgmem
    set_property PROGRAM.CHECKSUM 0 $hw_cfgmem

    refresh_hw_device $hw_device

    # Set file properties
    set_property PROGRAM.ADDRESS_RANGE {use_file} $hw_cfgmem
    set_property PROGRAM.FILES $binfile $hw_cfgmem
    set_property PROGRAM.PRM_FILE {} $hw_cfgmem
    set_property PROGRAM.UNUSED_PIN_TERMINATION {pull-none} $hw_cfgmem
    set_property PROGRAM.BLANK_CHECK 0 $hw_cfgmem
    set_property PROGRAM.ERASE 1 $hw_cfgmem
    set_property PROGRAM.CFG_PROGRAM 1 $hw_cfgmem
    set_property PROGRAM.VERIFY 1 $hw_cfgmem
    set_property PROGRAM.CHECKSUM 0 $hw_cfgmem

    # Check if bitstream needs to be created
    set cfgmem_part [get_property CFGMEM_PART $hw_cfgmem]
    set mem_type [get_property MEM_TYPE $cfgmem_part]
    set hw_cfgmem_type [get_property PROGRAM.HW_CFGMEM_TYPE $hw_device]
    if {![string equal $hw_cfgmem_type $mem_type]} {
        puts "Creating configuration bitstream..."
        create_hw_bitstream -hw_device $hw_device [get_property PROGRAM.HW_CFGMEM_BITFILE $hw_device]
        program_hw_devices $hw_device
    }

    puts "\nStep 5: Programming SPI flash (this may take a few minutes)..."

    program_hw_cfgmem -hw_cfgmem $hw_cfgmem
}

puts "\nStep 6: Cleaning up..."

close_hw

puts "\n========================================"
puts "SPI Flash programming complete!"
puts "========================================"
puts ""
puts "The FPGA will now boot from flash on power-up."
puts "Cycle power on the board to verify."
puts ""
