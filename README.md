# Picosecond-Precision Trigger Delay System

A configurable digital delay system for Xilinx FPGAs with 17.0068ps resolution using MMCM technology.

## Features

- **Resolution**: 17.0068ps per step (1050MHz VCO with 56 phase steps)
- **Range**: Unlimited delay (coarse + fine combination)
- **Control**: UART interface with Python API
- **Edge Detection**: Configurable rising/falling/both edge triggering
- **Platform**: Xilinx Artix-7 (Arty A7-35T)

## Architecture

### Delay System
- **Coarse Delay**: Clock cycle increments (10ns @ 100MHz)
- **Fine Delay**: MMCM phase shifting (17.0068ps steps)
- **Total Delay** = (coarse_cycles × 10ns) + (fine_steps × 17.0068ps)

### Key Modules
- `TRIGGER_DELAY_TOP`: Top module with UART control and MMCM integration
- `MMCM_FINE_DELAY`: Fine delay using MMCME2_ADV primitive
- `TRIGGER_DELAY_ENHANCED`: Combined coarse and fine delay system
- `CONFIGURABLE_DELAY`: Coarse delay in clock cycles
- `CDC_EDGE_DETECT`: Clock domain crossing with edge detection
- `UART_RX/TX`: UART communication modules (1Mbaud)

## Directory Structure

```
delay_unit/
├── rtl/                    # RTL source files
│   ├── core/              # Core delay logic
│   ├── mmcm/              # MMCM fine delay
│   ├── uart/              # UART interface
│   ├── TRIGGER_DELAY_TOP.sv
│   └── TRIGGER_DELAY_DEFS.vh
├── tb/                    # Testbench
│   └── MMCM_FINE_DELAY_TB.sv
├── constraints/           # Pin constraints
│   └── trigger_delay_arty.xdc
├── python/                # Control software
│   └── delay_control.py
├── synth.tcl             # Vivado synthesis script
└── Makefile              # Build automation
```

## Quick Start

### 1. Synthesis

```bash
# Using Makefile
make synth

# Or directly with Vivado
vivado -mode batch -source synth.tcl
```

### 2. Programming FPGA

#### Volatile Programming (JTAG - lost on power cycle)
```bash
# Using Makefile
make program

# Or manually in Vivado GUI
# Open Hardware Manager, connect to board, program with build/trigger_delay.bit
```

#### Persistent Programming (SPI Flash - survives power cycle)
```bash
# Using Makefile
make program-flash

# Or manually with Vivado
vivado -mode batch -source program_flash.tcl
```

The SPI flash programming will:
1. Generate BIN file from bitstream
2. Erase flash memory
3. Program and verify flash
4. FPGA will auto-boot from flash on power-up

### 3. Control via Python

```bash
cd python

# Set delay to 25.5ns (25500ps)
python delay_control.py set 25500

# Get current delay
python delay_control.py get

# Get system status
python delay_control.py status

# Set edge detection
python delay_control.py edge rising

# Sweep delay range (0-10ns in 100ps steps)
python delay_control.py sweep 0 10000 100
```

## Python API

The control API uses properties for clean, Pythonic access (all delays in picoseconds):

```python
from delay_unit import DelayUnit, EdgeType

with DelayUnit() as unit:
    # Set delay in picoseconds (25.5ns)
    unit.delay_ps = 25500
    print(f"Configured: {unit.delay_ps}ps ({unit.delay_ps/1000}ns)")

    # Set fine delay directly (0-9999ps)
    unit.fine = 5000  # 5ns fine delay

    # Configure edge detection
    unit.edge = EdgeType.RISING

    # Get system status
    status = unit.status
    print(f"Trigger count: {status['trigger_count']}")
    print(f"Actual delay: {status['actual_delay_ps']}ps")

    # Reset counter
    unit.reset_counter()
```

## UART Protocol

### Commands
| Command | Code | Data | Description |
|---------|------|------|-------------|
| SET_COARSE | 0x01 | 4 bytes | Set coarse delay (cycles) |
| GET_COARSE | 0x02 | - | Get coarse delay |
| SET_EDGE | 0x03 | 1 byte | Set edge type (0=none, 1=rising, 2=falling, 3=both) |
| GET_EDGE | 0x04 | - | Get edge type |
| GET_STATUS | 0x05 | - | Get trigger count and delays |
| RESET_COUNT | 0x06 | - | Reset trigger counter |
| SET_FINE | 0x07 | 2 bytes | Set fine delay (ps) |
| GET_FINE | 0x08 | - | Get fine delay |

### Communication Settings
- Baud rate: 1000000
- Data bits: 8
- Stop bits: 1
- Parity: None

## Technical Details

### MMCM Configuration
- Input: 100MHz system clock
- VCO Frequency: 1050MHz (21/2 = 10.5× multiplier)
- Phase Steps: 56 per VCO period
- Resolution: 952.38ps / 56 = 17.0068ps per step
- Maximum Fine Delay: 588 steps × 17.0068ps ≈ 10ns
- Note: CLKOUT0 = 50MHz (used only for trigger delay, system runs at 100MHz)

### Delay Calculation
```
Requested ps → Steps = ps × 59 / 1003
Actual ps = Steps × 17.0068
```

This integer math avoids floating point and prevents overflow.

## Pin Assignments (Arty A7)

| Signal | Pin | Description |
|--------|-----|-------------|
| clk | E3 | 100MHz system clock |
| rst | D9 | Reset (BTN0) |
| trigger_in | D10 | Trigger input (BTN1) |
| trigger_out | H5 | Delayed trigger (LED0) |
| uart_rx | D10 | UART receive |
| uart_tx | A9 | UART transmit |
| leds[3:0] | H5,J5,T9,T10 | Status LEDs |

LED[3] indicates MMCM lock status.

## Simulation

```bash
# Run testbench
make sim

# Or manually
cd tb
iverilog -g2012 -I../rtl ../rtl/mmcm/MMCM_FINE_DELAY.sv MMCM_FINE_DELAY_TB.sv -o mmcm_tb.vvp
vvp mmcm_tb.vvp
```

## Performance

- Clock Frequency: 100MHz
- Minimum Delay: ~30ns (system latency)
- Resolution: 17.0068ps
- Jitter: < 50ps RMS (MMCM specification)
- Maximum Trigger Rate: 50MHz

## Requirements

- Xilinx Vivado (for synthesis)
- Python 3.x with pyserial
- Arty A7-35T board (or compatible Xilinx 7-series FPGA)

## License

MIT

## Author

TU Berlin - SASS Group