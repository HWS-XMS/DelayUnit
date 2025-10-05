# Precision Trigger Delay System

Configurable digital delay system for Xilinx FPGAs with 5ns resolution.

## Features

- **Resolution**: 5ns (200MHz clock)
- **Delay Range**: 0 to 21.5 seconds
- **Configurable Output Width**: 5ns to any duration
- **Control**: UART @ 1Mbaud with Python API
- **Supported Platforms**:
  - Digilent Arty A7-35T (XC7A35T)
  - Digilent Nexys Video (XC7A200T)

## Quick Start

### Build & Program

Navigate to your target board directory and use the local Makefile:

**For Arty A7:**
```bash
cd targets/arty
make synth         # Synthesize design
make program       # Program FPGA (volatile)
make flash         # Program SPI flash (persistent)
```

**For Nexys Video:**
```bash
cd targets/nexys
make synth         # Synthesize design
make program       # Program FPGA (volatile)
make flash         # Program SPI flash (persistent)
```

### Python Control

```python
from delay_unit import DelayUnit, EdgeType

with DelayUnit() as unit:
    unit.delay_ns = 100
    unit.width_ns = 50
    unit.soft_trigger()
    print(unit.status)
```

### Testing

```bash
cd python
python test_comprehensive.py  # 1000 test combinations
```

## Hardware Setup

### Arty A7-35T

**Soft Trigger Testing:**
- Jumper: JA Pin 3 → JA Pin 1
- Scope Ch1: JA Pin 3 (trigger)
- Scope Ch2: JA Pin 2 (delayed output)

**Pmod JA Pinout:**
- Pin 1 (G13): External trigger input
- Pin 2 (B11): Delayed trigger output
- Pin 3 (A11): Soft trigger output

### Nexys Video (XC7A200T)

**Soft Trigger Testing:**
- Jumper: JA Pin 3 → JA Pin 1
- Scope Ch1: JA Pin 3 (trigger)
- Scope Ch2: JA Pin 2 (delayed output)

**Pmod JA Pinout:**
- Pin 1 (AB22): External trigger input
- Pin 2 (AB21): Delayed trigger output
- Pin 3 (AB20): Soft trigger output

## Architecture

- **CDC_EDGE_DETECT**: Clock domain crossing with edge detection
- **CONFIGURABLE_DELAY**: Programmable delay with configurable output width
- **UART_RX/TX**: UART communication @ 1Mbaud
- **Clock**: 100MHz input → 200MHz system clock via MMCM

## UART Commands

| Command | Code | Data | Description |
|---------|------|------|-------------|
| SET_COARSE | 0x01 | 4 bytes | Set delay (cycles) |
| GET_COARSE | 0x02 | - | Get delay |
| SET_WIDTH | 0x08 | 4 bytes | Set output width (cycles) |
| GET_WIDTH | 0x09 | - | Get output width |
| SOFT_TRIGGER | 0x07 | - | Generate trigger |
| GET_STATUS | 0x05 | - | Get trigger count + delay |
| RESET_COUNT | 0x06 | - | Reset counter |

## License

MIT
