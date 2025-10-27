## Constraints file for Trigger Delay System on Nexys Video (XC7A200T-1SBG484C)

## Clock signal - 100 MHz system clock
set_property -dict { PACKAGE_PIN R4    IOSTANDARD LVCMOS33 } [get_ports { clk }]; #IO_L13P_T2_MRCC_34 Sch=sysclk
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk }];

## Reset - Use SW0 (active high when switch is up)
set_property -dict { PACKAGE_PIN E22  IOSTANDARD LVCMOS12 } [get_ports { rst }]; #IO_L22P_T3_16 Sch=sw[0]

## LEDs - Show trigger counter and status
set_property -dict { PACKAGE_PIN T14   IOSTANDARD LVCMOS25 } [get_ports { leds[0] }]; #IO_L15P_T2_DQS_13 Sch=led[0]
set_property -dict { PACKAGE_PIN T15   IOSTANDARD LVCMOS25 } [get_ports { leds[1] }]; #IO_L15N_T2_DQS_13 Sch=led[1]
set_property -dict { PACKAGE_PIN T16   IOSTANDARD LVCMOS25 } [get_ports { leds[2] }]; #IO_L17P_T2_13 Sch=led[2]
set_property -dict { PACKAGE_PIN U16   IOSTANDARD LVCMOS25 } [get_ports { leds[3] }]; #IO_L17N_T2_13 Sch=led[3]

## USB-UART Interface - For communication with host PC
set_property -dict { PACKAGE_PIN AA19  IOSTANDARD LVCMOS33 } [get_ports { uart_tx }]; #IO_L15P_T2_DQS_RDWR_B_14 Sch=uart_rx_out (FPGA TX -> USB RX)
set_property -dict { PACKAGE_PIN V18   IOSTANDARD LVCMOS33 } [get_ports { uart_rx }]; #IO_L14P_T2_SRCC_14 Sch=uart_tx_in (USB TX -> FPGA RX)

## Trigger Input/Output - Using Pmod JA Pin 1 (bidirectional)
## EXTERNAL mode: INPUT - receives trigger from DuT
## INTERNAL mode: OUTPUT - sends trigger to DuT
set_property -dict { PACKAGE_PIN AB22  IOSTANDARD LVCMOS33 } [get_ports { trigger_in }]; #IO_L10N_T1_D15_14 Sch=ja[0]

## Trigger Output - Using Pmod JA Pin 2 for delayed trigger output
## Can connect to oscilloscope or other equipment
set_property -dict { PACKAGE_PIN AB21  IOSTANDARD LVCMOS33 } [get_ports { trigger_delayed_out }]; #IO_L10P_T1_D14_14 Sch=ja[1]

## Soft Trigger Output - Using Pmod JA Pin 3 for soft trigger pulse (for debugging/monitoring)
set_property -dict { PACKAGE_PIN AB20  IOSTANDARD LVCMOS33 } [get_ports { soft_trigger_out }]; #IO_L15N_T2_DQS_DOUT_CSO_B_14 Sch=ja[2]

## Configuration options
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]

## Timing constraints for I/O
set_input_delay -clock [get_clocks sys_clk_pin] -min -add_delay 2.000 [get_ports trigger_in]
set_input_delay -clock [get_clocks sys_clk_pin] -max -add_delay 5.000 [get_ports trigger_in]
set_output_delay -clock [get_clocks sys_clk_pin] -min -add_delay -1.000 [get_ports trigger_delayed_out]
set_output_delay -clock [get_clocks sys_clk_pin] -max -add_delay 2.000 [get_ports trigger_delayed_out]
set_output_delay -clock [get_clocks sys_clk_pin] -min -add_delay -1.000 [get_ports soft_trigger_out]
set_output_delay -clock [get_clocks sys_clk_pin] -max -add_delay 2.000 [get_ports soft_trigger_out]

## UART timing constraints - for 1Mbaud
set_input_delay -clock [get_clocks sys_clk_pin] -min -add_delay 2.000 [get_ports uart_rx]
set_input_delay -clock [get_clocks sys_clk_pin] -max -add_delay 5.000 [get_ports uart_rx]
set_output_delay -clock [get_clocks sys_clk_pin] -min -add_delay -1.000 [get_ports uart_tx]
set_output_delay -clock [get_clocks sys_clk_pin] -max -add_delay 2.000 [get_ports uart_tx]
