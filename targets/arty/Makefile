# Makefile for Arty A7-35T Target

.PHONY: all synth program flash clean help

BITSTREAM = build/trigger_delay.bit
MCS_FILE = build/trigger_delay.mcs

help:
	@echo "Arty A7-35T Build Targets"
	@echo ""
	@echo "  make synth   - Synthesize design"
	@echo "  make program - Program FPGA (volatile)"
	@echo "  make flash   - Program SPI flash (persistent)"
	@echo "  make clean   - Clean build artifacts"
	@echo "  make help    - Show this help"

all: synth

synth:
	@echo "Synthesizing for Arty A7-35T (XC7A35T)..."
	vivado -mode batch -source synth.tcl -nojournal -nolog

program:
	@echo "Programming Arty A7 FPGA..."
	@if [ ! -f $(BITSTREAM) ]; then \
		echo "Error: Bitstream not found. Run 'make synth' first."; \
		exit 1; \
	fi
	vivado -mode batch -source program.tcl -nojournal -nolog

flash:
	@echo "Programming Arty A7 SPI Flash..."
	@if [ ! -f $(BITSTREAM) ]; then \
		echo "Error: Bitstream not found. Run 'make synth' first."; \
		exit 1; \
	fi
	vivado -mode batch -source flash.tcl -nojournal -nolog

clean:
	@echo "Cleaning Arty build artifacts..."
	rm -rf build
	rm -f *.jou *.log
	rm -rf .Xil
