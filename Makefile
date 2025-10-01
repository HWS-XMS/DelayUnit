# Picosecond Delay Unit - Makefile

.PHONY: all synth sim clean help program

help:
	@echo "Picosecond Delay Unit - Build Targets"
	@echo ""
	@echo "Synthesis:"
	@echo "  make synth     - Synthesize design for Artix-7"
	@echo ""
	@echo "Simulation:"
	@echo "  make sim       - Run MMCM testbench"
	@echo ""
	@echo "Other:"
	@echo "  make clean     - Clean all build artifacts"
	@echo "  make program   - Program FPGA with bitstream"
	@echo "  make help      - Show this help"

# Default target
all: synth

# Vivado synthesis
synth:
	@echo "Synthesizing design with 20ps resolution MMCM..."
	vivado -mode batch -source synth.tcl

# Simulation
sim:
	@echo "Running MMCM testbench..."
	cd tb && \
	iverilog -g2012 -I../rtl \
		../rtl/mmcm/MMCM_FINE_DELAY.sv \
		MMCM_FINE_DELAY_TB.sv \
		-o mmcm_tb.vvp && \
	vvp mmcm_tb.vvp

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

# Program FPGA
program: synth
	@echo "Programming FPGA with bitstream..."
	echo "open_hw_manager" > program.tcl && \
	echo "connect_hw_server" >> program.tcl && \
	echo "open_hw_target" >> program.tcl && \
	echo "set_property PROGRAM.FILE {build/trigger_delay.bit} [current_hw_device]" >> program.tcl && \
	echo "program_hw_devices [current_hw_device]" >> program.tcl && \
	echo "close_hw_manager" >> program.tcl && \
	vivado -mode batch -source program.tcl && \
	rm program.tcl