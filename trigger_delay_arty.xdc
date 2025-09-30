## Constraints file for Trigger Delay System on Arty A7-35
## Based on the master XDC file

## Clock signal - 100 MHz system clock
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { clk }]; #IO_L12P_T1_MRCC_35 Sch=gclk[100]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk }];

## Reset button - Use Button 0 for system reset
set_property -dict { PACKAGE_PIN D9    IOSTANDARD LVCMOS33 } [get_ports { rst }]; #IO_L6N_T0_VREF_16 Sch=btn[0]

## LEDs - Show trigger counter lower 4 bits
set_property -dict { PACKAGE_PIN H5    IOSTANDARD LVCMOS33 } [get_ports { leds[0] }]; #IO_L24N_T3_35 Sch=led[4]
set_property -dict { PACKAGE_PIN J5    IOSTANDARD LVCMOS33 } [get_ports { leds[1] }]; #IO_25_35 Sch=led[5]
set_property -dict { PACKAGE_PIN T9    IOSTANDARD LVCMOS33 } [get_ports { leds[2] }]; #IO_L24P_T3_A01_D17_14 Sch=led[6]
set_property -dict { PACKAGE_PIN T10   IOSTANDARD LVCMOS33 } [get_ports { leds[3] }]; #IO_L24N_T3_A00_D16_14 Sch=led[7]

## USB-UART Interface - For communication with host PC
set_property -dict { PACKAGE_PIN D10   IOSTANDARD LVCMOS33 } [get_ports { uart_tx }]; #IO_L19N_T3_VREF_16 Sch=uart_rxd_out (FPGA TX -> USB RX)
set_property -dict { PACKAGE_PIN A9    IOSTANDARD LVCMOS33 } [get_ports { uart_rx }]; #IO_L14N_T2_SRCC_16 Sch=uart_txd_in (USB TX -> FPGA RX)

## Trigger Input - Using Pmod JA Pin 1 for trigger input
## Can connect external trigger source here
set_property -dict { PACKAGE_PIN G13   IOSTANDARD LVCMOS33 } [get_ports { trigger_in }]; #IO_0_15 Sch=ja[1]

## Trigger Output - Using Pmod JA Pin 2 for delayed trigger output
## Can connect to oscilloscope or other equipment
set_property -dict { PACKAGE_PIN B11   IOSTANDARD LVCMOS33 } [get_ports { trigger_out }]; #IO_L4P_T0_15 Sch=ja[2]

## Optional: Additional trigger I/O on Pmod JB for differential signals
## Uncomment if using differential trigger signals
# set_property -dict { PACKAGE_PIN E15   IOSTANDARD LVCMOS33 } [get_ports { trigger_in_p }]; #IO_L11P_T1_SRCC_15 Sch=jb_p[1]
# set_property -dict { PACKAGE_PIN E16   IOSTANDARD LVCMOS33 } [get_ports { trigger_in_n }]; #IO_L11N_T1_SRCC_15 Sch=jb_n[1]
# set_property -dict { PACKAGE_PIN D15   IOSTANDARD LVCMOS33 } [get_ports { trigger_out_p }]; #IO_L12P_T1_MRCC_15 Sch=jb_p[2]
# set_property -dict { PACKAGE_PIN C15   IOSTANDARD LVCMOS33 } [get_ports { trigger_out_n }]; #IO_L12N_T1_MRCC_15 Sch=jb_n[2]

## Configuration options
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]

## Timing constraints for I/O
set_input_delay -clock [get_clocks sys_clk_pin] -min -add_delay 2.000 [get_ports trigger_in]
set_input_delay -clock [get_clocks sys_clk_pin] -max -add_delay 5.000 [get_ports trigger_in]
set_output_delay -clock [get_clocks sys_clk_pin] -min -add_delay -1.000 [get_ports trigger_out]
set_output_delay -clock [get_clocks sys_clk_pin] -max -add_delay 2.000 [get_ports trigger_out]

## UART timing constraints - for 115200 baud
set_input_delay -clock [get_clocks sys_clk_pin] -min -add_delay 2.000 [get_ports uart_rx]
set_input_delay -clock [get_clocks sys_clk_pin] -max -add_delay 5.000 [get_ports uart_rx]
set_output_delay -clock [get_clocks sys_clk_pin] -min -add_delay -1.000 [get_ports uart_tx]
set_output_delay -clock [get_clocks sys_clk_pin] -max -add_delay 2.000 [get_ports uart_tx]