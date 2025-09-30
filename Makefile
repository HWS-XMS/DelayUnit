# Picosecond Delay Unit - Main Makefile

.PHONY: all vivado mmcm icestick sim clean help

help:
	@echo "Picosecond Delay Unit - Build Targets"
	@echo ""
	@echo "Synthesis:"
	@echo "  make vivado    - Build basic version for Artix-7"
	@echo "  make mmcm      - Build MMCM version with 20ps resolution"
	@echo "  make icestick  - Build for IceStick (basic version)"
	@echo ""
	@echo "Simulation:"
	@echo "  make sim       - Run all testbenches"
	@echo "  make sim-mmcm  - Run MMCM testbench only"
	@echo ""
	@echo "Other:"
	@echo "  make clean     - Clean all build artifacts"
	@echo "  make help      - Show this help"

# Default target
all: mmcm

# Vivado synthesis - basic version
vivado:
	@echo "Building basic version with Vivado..."
	cd scripts/vivado && vivado -mode batch -source synth_trigger_delay.tcl

# Vivado synthesis - MMCM version
mmcm:
	@echo "Building MMCM version with 20ps resolution..."
	cd scripts/vivado && vivado -mode batch -source synth_mmcm.tcl

# IceStick synthesis
icestick:
	@echo "Building for IceStick..."
	$(MAKE) -C IceStick

# Simulation
sim:
	@echo "Running simulations..."
	cd tb && \
	iverilog -g2012 -I../rtl \
		../rtl/trigger_delay_defs.vh \
		../rtl/core/*.sv \
		../rtl/uart/*.sv \
		../rtl/TRIGGER_DELAY_TOP.sv \
		TRIGGER_DELAY_TB.sv \
		-o trigger_delay_tb.vvp && \
	vvp trigger_delay_tb.vvp

sim-mmcm:
	@echo "Running MMCM simulation..."
	cd tb && \
	iverilog -g2012 -I../rtl \
		../rtl/mmcm/MMCM_FINE_DELAY.sv \
		MMCM_FINE_DELAY_TB.sv \
		-o mmcm_tb.vvp && \
	vvp mmcm_tb.vvp

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	rm -rf scripts/vivado/build
	rm -rf scripts/vivado/*.jou
	rm -rf scripts/vivado/*.log
	rm -rf scripts/vivado/.Xil
	$(MAKE) -C IceStick clean
	rm -f tb/*.vvp tb/*.vcd
	find . -name "*.pyc" -delete
	find . -name "__pycache__" -type d -delete

# Install Python dependencies
install-python:
	pip install pyserial

# Program FPGA (requires configuration)
program: mmcm
	@echo "Programming FPGA with MMCM bitstream..."
	cd scripts/vivado && \
	echo "open_hw_manager" > program.tcl && \
	echo "connect_hw_server" >> program.tcl && \
	echo "open_hw_target" >> program.tcl && \
	echo "set_property PROGRAM.FILE {build/trigger_delay_mmcm.bit} [current_hw_device]" >> program.tcl && \
	echo "program_hw_devices [current_hw_device]" >> program.tcl && \
	echo "close_hw_manager" >> program.tcl && \
	vivado -mode batch -source program.tcl