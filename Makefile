# Picosecond Delay Unit - Makefile

.PHONY: all synth sim clean help program program-flash

help:
	@echo "Picosecond Delay Unit - Build Targets"
	@echo ""
	@echo "Synthesis:"
	@echo "  make synth         - Synthesize design for Artix-7"
	@echo ""
	@echo "Programming:"
	@echo "  make program       - Program FPGA (volatile, lost on power cycle)"
	@echo "  make program-flash - Program SPI flash (persistent, boots on power-up)"
	@echo ""
	@echo "Simulation:"
	@echo "  make sim           - Run MMCM testbench"
	@echo ""
	@echo "Other:"
	@echo "  make clean         - Clean all build artifacts"
	@echo "  make help          - Show this help"

# Default target
all: synth

# Vivado synthesis
synth:
	@echo "Synthesizing design with 5ns clock cycle delay (200MHz)..."
	vivado -mode batch -source synth.tcl -nojournal -nolog

# Simulation
sim:
	@echo "No simulation targets available (removed MMCM testbenches)"

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	rm -rf build
	rm -rf *.jou *.log .Xil
	rm -f tb/*.vvp tb/*.vcd
	find . -name "*.pyc" -delete
	find . -name "__pycache__" -type d -delete

# Install Python dependencies
install-python:
	pip install pyserial

# Program FPGA (volatile - lost on power cycle)
program:
	@echo "Programming FPGA with bitstream..."
	@if [ ! -f build/trigger_delay.bit ]; then \
		echo "Error: Bitstream not found. Run 'make synth' first."; \
		exit 1; \
	fi
	vivado -mode batch -source program.tcl -nojournal -nolog

# Program SPI Flash (persistent - survives power cycle)
program-flash:
	@echo "Programming SPI flash with bitstream..."
	@if [ ! -f build/trigger_delay.bit ]; then \
		echo "Error: Bitstream not found. Run 'make synth' first."; \
		exit 1; \
	fi
	vivado -mode batch -source program_flash.tcl -nojournal -nolog