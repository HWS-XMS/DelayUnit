# Board Targets

This directory contains board-specific build configurations for the Precision Trigger Delay System.

## Available Targets

### arty/
Digilent Arty A7-35T (XC7A35TICSG324-1L)
- 100MHz system clock → 200MHz via MMCM
- Pmod JA connections for trigger I/O
- USB-UART for control interface

### nexys/
Digilent Nexys Video (XC7A200TSBG484-1)
- 100MHz system clock → 200MHz via MMCM
- Pmod JA connections for trigger I/O
- USB-UART for control interface

## Target Structure

Each target directory contains:

```
targetname/
├── Makefile          # Board-specific build rules
├── synth.tcl         # Vivado synthesis script
├── program.tcl       # FPGA programming (volatile)
├── flash.tcl         # Flash programming (persistent)
├── constraints.xdc   # Pin assignments & timing
└── build/           # Generated during synthesis
    ├── trigger_delay.bit
    ├── trigger_delay.mcs (for flash)
    └── *.rpt (reports)
```

## Building

### From project root:
```bash
make arty-synth      # Synthesize Arty target
make arty-program    # Program Arty FPGA
make arty-flash      # Program Arty flash

make nexys-synth     # Synthesize Nexys target
make nexys-program   # Program Nexys FPGA
make nexys-flash     # Program Nexys flash
```

### From target directory:
```bash
cd arty              # or nexys
make synth           # Synthesize
make program         # Program FPGA
make flash           # Program flash
make clean           # Clean build
```

## Pin Mappings

### Arty A7-35T Pmod JA
- **Pin 1 (G13)**: External trigger input
- **Pin 2 (B11)**: Delayed trigger output
- **Pin 3 (A11)**: Soft trigger output

### Nexys Video Pmod JA
- **Pin 1 (AB22)**: External trigger input
- **Pin 2 (AB21)**: Delayed trigger output
- **Pin 3 (AB20)**: Soft trigger output

## Common Operations

**Clean all targets:**
```bash
cd ../..
make clean
```

**View build reports:**
```bash
cd arty/build
ls *.rpt
```

**Test bitstream:**
```bash
make synth
make program
cd ../../python
python test_comprehensive.py
```

## Adding New Targets

1. Copy an existing target directory
2. Rename and update these files:
   - `constraints.xdc` - Pin assignments
   - `synth.tcl` - FPGA part number
   - `program.tcl` - Device ID
   - `flash.tcl` - Flash part number
3. Add rules to top-level Makefile
4. Document in this README

## Notes

- All targets share the same RTL in `../../rtl/`
- Build outputs are isolated per target
- FPGA programming requires Vivado installed
- Flash programming requires JTAG connection
