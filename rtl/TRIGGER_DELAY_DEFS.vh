`ifndef TRIGGER_DELAY_DEFS_VH
`define TRIGGER_DELAY_DEFS_VH

// Edge type definitions
`define EDGE_NONE    2'b00
`define EDGE_RISING  2'b01
`define EDGE_FALLING 2'b10
`define EDGE_BOTH    2'b11

// Trigger mode definitions
`define TRIGGER_MODE_EXTERNAL 1'b0
`define TRIGGER_MODE_INTERNAL 1'b1

// Command definitions - Clock cycle delay only (5ns resolution @ 200MHz)
`define CMD_SET_COARSE                 8'h01
`define CMD_GET_COARSE                 8'h02
`define CMD_SET_EDGE                   8'h03
`define CMD_GET_EDGE                   8'h04
`define CMD_GET_STATUS                 8'h05
`define CMD_RESET_COUNT                8'h06
`define CMD_SOFT_TRIGGER               8'h07
`define CMD_SET_OUTPUT_TRIGGER_WIDTH   8'h08
`define CMD_GET_OUTPUT_TRIGGER_WIDTH   8'h09
`define CMD_SET_TRIGGER_MODE           8'h0A
`define CMD_GET_TRIGGER_MODE           8'h0B
`define CMD_SET_SOFT_TRIGGER_WIDTH     8'h0C
`define CMD_GET_SOFT_TRIGGER_WIDTH     8'h0D

// Response definitions
`define RESP_ACK         8'hAA
`define RESP_NACK        8'h55
`define RESP_DATA        8'hDD

// Other parameters
`define SYNC_BYTE        8'h7E
`define UART_TIMEOUT     1000000

`endif