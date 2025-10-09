# DS1124 8-Bit Programmable Delay Line Driver

SystemVerilog implementation of a driver for the DS1124 programmable delay IC.

## ⚠️ Important Hardware Requirements

**The DS1124 operates at 5V logic levels.** Most modern FPGAs use 3.3V or 1.8V I/O standards, therefore:

### Control Interface Level Shifting
- **Level shifters are REQUIRED** between FPGA and DS1124
- Use bidirectional level shifters for the Q signal (if readback is used)
- Use unidirectional level shifters for CLK, D, and E signals (FPGA → DS1124)
- Ensure level shifters can handle the serial clock frequency (up to 10 MHz)

### Signal Path Level Shifting
- **The actual signal to be delayed ALSO requires level shifting:**
  - INPUT: FPGA output (3.3V/1.8V) → Level Shifter → DS1124 IN (5V)
  - OUTPUT: DS1124 OUT (5V) → Level Shifter → FPGA input (3.3V/1.8V)
- These signal path level shifters must support the full bandwidth of your delayed signal
- Use high-speed level shifters for critical timing paths

Example level shifters:
- TXB0104 (4-channel bidirectional, auto-direction, up to 100 Mbps)
- SN74LVC1T45 (single channel bidirectional, up to 420 Mbps)
- SN74LVC2T45 (dual channel bidirectional)
- SN74LVC1G125 (single channel unidirectional, high-speed)

## Files

- `ds1124_driver.sv` - Main driver module
- `ds1124_driver_tb.sv` - Comprehensive testbench
- `test_*.sv` - Auxiliary test files for specific features

## Features

- 8-bit delay control (0-255 steps, 0.25ns per step)  
- 3-wire serial interface (CLK, D, E)
- Configurable system clock frequency
- Optional non-destructive readback
- Automatic settling time calculation

## Usage

```systemverilog
ds1124_driver #(
    .SYS_CLK_FREQ(100_000_000),  // 100 MHz
    .CLK_DIV(4),                  // Divide by 4
    .READBACK_EN(1)               // Enable readback
) u_ds1124 (
    .clk(clk),
    .rst(rst),
    .delay_value(delay_value),
    .en(en),
    .ready(ready),
    .ds1124_clk(ds1124_clk),
    .ds1124_d(ds1124_d),
    .ds1124_e(ds1124_e),
    .ds1124_q(ds1124_q),
    .read_delay(read_delay),
    .current_delay(current_delay),
    .read_valid(read_valid)
);
```

## Testing

Run the comprehensive testbench:
```bash
iverilog -g2012 -o ds1124_tb ds1124_driver.sv ds1124_driver_tb.sv
vvp ds1124_tb
```