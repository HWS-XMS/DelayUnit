`timescale 1ns / 1ps

import trigger_delay_pkg::*;

module uart_command_handler (
    input  logic        clk,
    input  logic        rst,
    
    // UART interface
    input  logic [7:0]  rx_data,
    input  logic        rx_data_valid,
    output logic [7:0]  tx_data,
    output logic        tx_en,
    input  logic        tx_ready,
    
    // Delay control
    output logic [31:0] delay_cycles,
    output logic        delay_update,
    output edge_type_t  edge_type,
    output logic        edge_type_update,
    
    // Status
    input  logic [31:0] current_delay,
    input  logic [15:0] trigger_count,
    output logic        reset_counter
);

    typedef enum {
        STATE_IDLE,
        STATE_SET_DELAY,
        STATE_GET_DELAY,
        STATE_SET_EDGE,
        STATE_GET_EDGE,
        STATE_GET_STATUS,
        STATE_RESET_COUNT,
        STATE_SEND_ACK,
        STATE_SEND_RESPONSE
    } state_t;
    
    state_t current_state;
    
    logic [7:0] cmd_buffer;
    logic [31:0] rx_delay_value;
    logic [7:0] byte_counter;
    logic [31:0] tx_value;
    logic [7:0] response_bytes;
    
    always_ff @(posedge clk) begin
        if (rst) begin
            current_state <= STATE_IDLE;
            cmd_buffer <= 8'h00;
            rx_delay_value <= 32'h00000000;
            byte_counter <= 8'd0;
            delay_cycles <= 32'd0;
            delay_update <= 1'b0;
            edge_type <= EDGE_RISING;
            edge_type_update <= 1'b0;
            tx_data <= 8'h00;
            tx_en <= 1'b0;
            reset_counter <= 1'b0;
            tx_value <= 32'd0;
            response_bytes <= 8'd0;
            
        end else begin
            // Default assignments
            current_state <= current_state;
            cmd_buffer <= cmd_buffer;
            rx_delay_value <= rx_delay_value;
            byte_counter <= byte_counter;
            delay_cycles <= delay_cycles;
            delay_update <= 1'b0;
            edge_type <= edge_type;
            edge_type_update <= 1'b0;
            tx_data <= tx_data;
            tx_en <= 1'b0;
            reset_counter <= 1'b0;
            tx_value <= tx_value;
            response_bytes <= response_bytes;
            
            case (current_state)
                STATE_IDLE: begin
                    if (rx_data_valid) begin
                        if (rx_data == SYNC_BYTE) begin
                            byte_counter <= 8'd0;
                        end else begin
                            cmd_buffer <= rx_data;
                            byte_counter <= 8'd0;
                            case (rx_data)
                                8'h01: current_state <= STATE_SET_DELAY;  // CMD_SET_DELAY
                                8'h02: current_state <= STATE_GET_DELAY;  // CMD_GET_DELAY
                                8'h03: current_state <= STATE_SET_EDGE;   // CMD_SET_EDGE
                                8'h04: current_state <= STATE_GET_EDGE;   // CMD_GET_EDGE
                                8'h05: current_state <= STATE_GET_STATUS; // CMD_GET_STATUS
                                8'h06: current_state <= STATE_RESET_COUNT;// CMD_RESET_COUNT
                                default: current_state <= STATE_IDLE;
                            endcase
                        end
                    end
                end
                
                STATE_SET_DELAY: begin
                    if (byte_counter >= 4) begin
                        delay_cycles <= rx_delay_value;
                        delay_update <= 1'b1;
                        current_state <= STATE_SEND_ACK;
                        byte_counter <= 8'd0;
                    end else begin
                        if (rx_data_valid) begin
                            case (byte_counter)
                                0: rx_delay_value[7:0] <= rx_data;
                                1: rx_delay_value[15:8] <= rx_data;
                                2: rx_delay_value[23:16] <= rx_data;
                                3: rx_delay_value[31:24] <= rx_data;
                            endcase
                            byte_counter <= byte_counter + 1;
                        end
                    end
                end
                
                STATE_GET_DELAY: begin
                    tx_value <= current_delay;
                    response_bytes <= 8'd4;
                    byte_counter <= 8'd0;
                    current_state <= STATE_SEND_RESPONSE;
                end
                
                STATE_SET_EDGE: begin
                    if (rx_data_valid) begin
                        case (rx_data)
                            8'h00: edge_type <= EDGE_NONE;
                            8'h01: edge_type <= EDGE_RISING;
                            8'h02: edge_type <= EDGE_FALLING;
                            8'h03: edge_type <= EDGE_BOTH;
                            default: edge_type <= EDGE_RISING;
                        endcase
                        edge_type_update <= 1'b1;
                        current_state <= STATE_SEND_ACK;
                    end
                end
                
                STATE_GET_EDGE: begin
                    tx_value <= {30'd0, edge_type};
                    response_bytes <= 8'd1;
                    byte_counter <= 8'd0;
                    current_state <= STATE_SEND_RESPONSE;
                end
                
                STATE_GET_STATUS: begin
                    // Send back: [trigger_count(2 bytes)][current_delay(4 bytes)]
                    if (byte_counter >= 6) begin
                        current_state <= STATE_IDLE;
                    end else begin
                        if (tx_ready) begin
                            case (byte_counter)
                                0: tx_data <= trigger_count[7:0];
                                1: tx_data <= trigger_count[15:8];
                                2: tx_data <= current_delay[7:0];
                                3: tx_data <= current_delay[15:8];
                                4: tx_data <= current_delay[23:16];
                                5: tx_data <= current_delay[31:24];
                            endcase
                            tx_en <= 1'b1;
                            byte_counter <= byte_counter + 1;
                        end
                    end
                end
                
                STATE_RESET_COUNT: begin
                    reset_counter <= 1'b1;
                    current_state <= STATE_SEND_ACK;
                end
                
                STATE_SEND_ACK: begin
                    if (tx_ready) begin
                        tx_data <= 8'hAA;  // ACK
                        tx_en <= 1'b1;
                        current_state <= STATE_IDLE;
                    end
                end
                
                STATE_SEND_RESPONSE: begin
                    if (byte_counter >= response_bytes) begin
                        current_state <= STATE_IDLE;
                    end else begin
                        if (tx_ready) begin
                            case (byte_counter)
                                0: tx_data <= tx_value[7:0];
                                1: tx_data <= tx_value[15:8];
                                2: tx_data <= tx_value[23:16];
                                3: tx_data <= tx_value[31:24];
                            endcase
                            tx_en <= 1'b1;
                            byte_counter <= byte_counter + 1;
                        end
                    end
                end
                
                default: current_state <= STATE_IDLE;
            endcase
        end
    end

endmodule