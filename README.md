# Picosecond-Precision Trigger Delay System

A configurable digital delay system for FPGAs with 20.12ps resolution using Xilinx MMCM technology.

## Features

- **Resolution**: 20.12ps per step (887.5MHz VCO with 56 phase steps)
- **Range**: Unlimited delay (coarse + fine combination)
- **Control**: UART interface with Python API
- **Edge Detection**: Configurable rising/falling/both edge triggering
- **Platform Support**: Xilinx Artix-7 (Vivado) and Lattice iCE40 (Yosys)

## Architecture

### Delay System
- **Coarse Delay**: Clock cycle increments (10ns @ 100MHz)
- **Fine Delay**: MMCM phase shifting (20.12ps steps)
- **Total Delay** = (coarse_cycles × 10ns) + (fine_steps × 20.12ps)

### Key Modules
- `TRIGGER_DELAY_TOP_MMCM`: Top module with UART control and MMCM
- `MMCM_FINE_DELAY`: Fine delay using MMCME2_ADV primitive
- `CONFIGURABLE_DELAY`: Coarse delay in clock cycles
- `CDC_EDGE_DETECT`: Clock domain crossing with edge detection
- `UART_RX/TX`: UART communication modules (115200 baud)

## Directory Structure

```
delay_unit/
├── rtl/                    # RTL source files
│   ├── core/              # Core delay logic
│   │   ├── CDC_EDGE_DETECT.sv
│   │   ├── CONFIGURABLE_DELAY.sv
│   │   ├── TRIGGER_DELAY_MODULE.sv
│   │   └── TRIGGER_DELAY_ENHANCED.sv
│   ├── mmcm/              # MMCM fine delay
│   │   └── MMCM_FINE_DELAY.sv
│   ├── uart/              # UART interface
│   │   ├── UART_RX.sv
│   │   └── UART_TX.sv
│   ├── TRIGGER_DELAY_TOP.sv       # Basic top module
│   ├── TRIGGER_DELAY_TOP_MMCM.sv  # MMCM-enhanced top
│   └── trigger_delay_defs.vh      # Definitions header
├── tb/                    # Testbenches
│   ├── TRIGGER_DELAY_TB.sv
│   └── MMCM_FINE_DELAY_TB.sv
├── constraints/           # Pin constraints
│   └── trigger_delay_arty.xdc
├── scripts/               # Build and control scripts
│   ├── vivado/           # Vivado synthesis
│   │   ├── synth_trigger_delay.tcl
│   │   └── synth_mmcm.tcl
│   └── python/           # Control software
│       └── delay_control.py
├── IceStick/             # IceStick synthesis
│   ├── synth.ys
│   ├── icestick.pcf
│   └── Makefile
└── docs/                 # Documentation
```

## Quick Start

### 1. Synthesis (Vivado)

For MMCM version with picosecond precision:
```bash
cd scripts/vivado
vivado -mode batch -source synth_mmcm.tcl
```

For basic version (clock-cycle resolution only):
```bash
cd scripts/vivado
vivado -mode batch -source synth_trigger_delay.tcl
```

### 2. Synthesis (IceStick/Yosys)

```bash
cd IceStick
make
```

### 3. Programming FPGA

```bash
# For Arty board
vivado -mode batch -source program.tcl

# For IceStick
iceprog trigger_delay.bin
```

### 4. Control via Python

```bash
cd scripts/python

# Set delay to 25.5ns (25500ps)
python delay_control.py set 25500

# Get current delay
python delay_control.py get

# Get system status
python delay_control.py status

# Sweep delay range
python delay_control.py sweep 0 10000 100

# Set edge detection
python delay_control.py edge rising
```

## Python API

The control script works entirely in picoseconds:

```python
from delay_control import DelayController

controller = DelayController('/dev/ttyUSB1')

# Set delay in picoseconds
result = controller.set_delay(5000)  # 5ns
print(f"Requested: {result['requested_ps']}ps")
print(f"Actual: {result['actual_ps']}ps")

# Read back actual delay
actual_ps = controller.get_delay()
print(f"Current delay: {actual_ps}ps")
```

## UART Protocol

### Commands
| Command | Code | Data | Description |
|---------|------|------|-------------|
| SET_DELAY | 0x01 | 4 bytes | Set coarse delay (cycles) |
| GET_DELAY | 0x02 | - | Get coarse delay |
| SET_EDGE | 0x03 | 1 byte | Set edge type (0=none, 1=rising, 2=falling, 3=both) |
| GET_EDGE | 0x04 | - | Get edge type |
| GET_STATUS | 0x05 | - | Get trigger count and delays |
| RESET_COUNT | 0x06 | - | Reset trigger counter |
| SET_FINE | 0x07 | 2 bytes | Set fine delay (ps) |
| GET_FINE | 0x08 | - | Get fine delay |

### Communication Settings
- Baud rate: 115200
- Data bits: 8
- Stop bits: 1
- Parity: None

## Technical Details

### MMCM Configuration
- Input: 100MHz system clock
- VCO Frequency: 887.5MHz (8.875× multiplier)
- Phase Steps: 56 per VCO period
- Resolution: 1126.76ps / 56 = 20.12ps per step
- Maximum Fine Delay: 497 steps × 20.12ps ≈ 10ns

### Delay Calculation
```
Requested ps → Steps = ps × 50 / 1006
Actual ps = Steps × 20.12
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

## Testing

### Simulation
```bash
cd tb
vsim TRIGGER_DELAY_TB
vsim MMCM_FINE_DELAY_TB
```

### Hardware Testing
1. Connect trigger source to BTN1
2. Monitor delayed output on LED0
3. Use oscilloscope to measure actual delay
4. Control via Python script

## Performance

- Clock Frequency: 100MHz
- Minimum Delay: ~30ns (system latency)
- Resolution: 20.12ps
- Jitter: < 50ps RMS (MMCM specification)
- Maximum Frequency: 50MHz trigger rate

## License

MIT

## Author

TU Berlin - SASS Group