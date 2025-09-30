# Makefile for IceStick synthesis using Yosys + NextPNR
PROJ = trigger_delay
PIN_DEF = icestick.pcf
DEVICE = hx1k
PACKAGE = tq144

# Source files
VERILOG_FILES = ../TRIGGER_DELAY_PKG.sv \
                ../CDC_EDGE_DETECT.sv \
                ../CONFIGURABLE_DELAY.sv \
                ../TRIGGER_DELAY_MODULE.sv \
                ../UART_RX.sv \
                ../UART_TX.sv \
                ../TRIGGER_DELAY_TOP.sv

all: $(PROJ).bin

synth: $(PROJ).json

$(PROJ).json: $(VERILOG_FILES)
	yosys synth.ys

$(PROJ).asc: $(PROJ).json $(PIN_DEF)
	nextpnr-ice40 --$(DEVICE) --package $(PACKAGE) --json $< --pcf $(PIN_DEF) --asc $@

$(PROJ).bin: $(PROJ).asc
	icepack $< $@

timing: $(PROJ).json $(PIN_DEF)
	nextpnr-ice40 --$(DEVICE) --package $(PACKAGE) --json $(PROJ).json --pcf $(PIN_DEF) --asc $(PROJ)_timing.asc --report timing.rpt

prog: $(PROJ).bin
	iceprog $<

clean:
	rm -f *.json *.asc *.bin *.rpt *.v

.PHONY: all synth timing prog clean