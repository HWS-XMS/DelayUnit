`timescale 1ns / 1ps

package TRIGGER_DELAY_PKG;

    typedef enum {
        EDGE_NONE,
        EDGE_RISING,
        EDGE_FALLING,
        EDGE_BOTH
    } edge_type_t;
    
    typedef enum {
        CMD_SET_DELAY,
        CMD_GET_DELAY,
        CMD_SET_EDGE,
        CMD_GET_STATUS,
        CMD_RESET_COUNT
    } cmd_type_t;
    
    typedef enum {
        RESP_ACK,
        RESP_NACK,
        RESP_DATA
    } resp_type_t;
    
    localparam logic [7:0] SYNC_BYTE = 8'h7E;
    localparam int UART_TIMEOUT = 1000000;

endpackage