#!/bin/bash

# Create a single file with package contents inlined
cat > all_modules.sv << 'EOF'
`timescale 1ns / 1ps

// Package contents inlined
typedef enum logic [1:0] {
    EDGE_NONE   = 2'b00,
    EDGE_RISING = 2'b01,
    EDGE_FALLING = 2'b10,
    EDGE_BOTH   = 2'b11
} edge_type_t;

EOF

# Append modules without package import statements
for file in ../CDC_EDGE_DETECT.sv ../CONFIGURABLE_DELAY.sv ../TRIGGER_DELAY_MODULE.sv ../UART_RX.sv ../UART_TX.sv ../TRIGGER_DELAY_TOP.sv; do
    echo "// From $file" >> all_modules.sv
    grep -v "^import" "$file" | grep -v "^package" | grep -v "^endpackage" >> all_modules.sv
    echo "" >> all_modules.sv
done

echo "Preprocessed file created: all_modules.sv"