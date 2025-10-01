`ifndef TRIGGER_DELAY_DEFS_VH
`define TRIGGER_DELAY_DEFS_VH

// Edge type definitions
`define EDGE_NONE    2'b00
`define EDGE_RISING  2'b01
`define EDGE_FALLING 2'b10
`define EDGE_BOTH    2'b11

// Command definitions
`define CMD_SET_COARSE   8'h01
`define CMD_GET_COARSE   8'h02
`define CMD_SET_EDGE     8'h03
`define CMD_GET_EDGE     8'h04
`define CMD_GET_STATUS   8'h05
`define CMD_RESET_COUNT  8'h06
`define CMD_SET_FINE     8'h07
`define CMD_GET_FINE     8'h08

// Response definitions
`define RESP_ACK         8'hAA
`define RESP_NACK        8'h55
`define RESP_DATA        8'hDD

// Other parameters
`define SYNC_BYTE        8'h7E
`define UART_TIMEOUT     1000000

`endif