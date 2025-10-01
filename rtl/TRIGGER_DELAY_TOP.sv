`timescale 1ns / 1ps

`include "TRIGGER_DELAY_DEFS.vh"

module TRIGGER_DELAY_TOP (
    input  logic        clk,
    input  logic        rst,
    input  logic        trigger_in,
    output logic        trigger_out,
    input  logic        uart_rx,
    output logic        uart_tx,
    output logic [3:0]  leds
);

    localparam CLK_FREQ = 100_000_000;
    localparam BAUD_RATE = 1_000_000;
    
    // UART signals
    logic [7:0] uart_rx_data;
    logic uart_rx_data_valid;
    logic uart_tx_en;
    logic [7:0] uart_tx_data;
    logic uart_tx_ready;
    
    // UART RX instance
    UART_RX #(
        .ELEMENT_WIDTH(8),
        .BAUDRATE(BAUD_RATE),
        .SYSTEMCLOCK(CLK_FREQ)
    ) uart_rx_inst (
        .clk(clk),
        .rst(rst),
        .rx_line(uart_rx),
        .rx_data(uart_rx_data),
        .rx_data_valid(uart_rx_data_valid)
    );
    
    // UART TX instance
    UART_TX #(
        .SYSTEMCLOCK(CLK_FREQ),
        .BAUDRATE(BAUD_RATE),
        .ELEMENT_WIDTH(8)
    ) uart_tx_inst (
        .clk(clk),
        .rst(rst),
        .tx_en(uart_tx_en),
        .tx_data(uart_tx_data),
        .tx_line(uart_tx),
        .tx_ready(uart_tx_ready)
    );
    
    // Control signals for trigger delay
    logic [31:0] coarse_delay;
    logic coarse_update;
    logic [15:0] fine_delay_ps;
    logic fine_update;
    logic [1:0] edge_type;
    logic [31:0] current_coarse;
    logic [15:0] current_fine;
    logic [15:0] trigger_counter;
    logic trigger_pulse_for_counter;
    logic mmcm_locked;
    
    // Enhanced trigger delay with MMCM fine control
    TRIGGER_DELAY_ENHANCED trigger_delay_inst (
        .clk(clk),
        .rst(rst),
        .trigger_in(trigger_in),
        .trigger_out(trigger_out),
        .coarse_delay(coarse_delay),
        .coarse_update(coarse_update),
        .fine_delay_ps(fine_delay_ps),
        .fine_update(fine_update),
        .edge_type(edge_type),
        .mmcm_locked(mmcm_locked)
    );
    
    // Edge detector for counter
    CDC_EDGE_DETECT #(
        .SYNC_STAGES(3)
    ) counter_edge_detect (
        .clk(clk),
        .rst(rst),
        .async_in(trigger_in),
        .edge_type(edge_type),
        .edge_pulse(trigger_pulse_for_counter),
        .sync_out()
    );
    
    // Commands are defined in header file
    
    // State machine
    typedef enum {
        STATE_IDLE,
        STATE_SET_COARSE,
        STATE_GET_COARSE,
        STATE_SET_EDGE,
        STATE_GET_EDGE,
        STATE_GET_STATUS,
        STATE_RESET_COUNT,
        STATE_SET_FINE,
        STATE_GET_FINE
    } state_t;
    state_t current_state;
    
    logic [31:0] uart_transmission_counter;
    logic [31:0] rx_delay_value;
    logic [15:0] rx_fine_value;
    
    // LED assignment (bit 3 shows MMCM lock status)
    assign leds = {mmcm_locked, trigger_counter[2:0]};
    
    // State machine
    always_ff @(posedge clk) begin
        if (rst) begin
            current_state <= STATE_IDLE;
            uart_tx_en <= 1'b0;
            uart_tx_data <= 8'b0;
            uart_transmission_counter <= 32'd0;
            coarse_delay <= 32'd0;
            coarse_update <= 1'b0;
            fine_delay_ps <= 16'd0;
            fine_update <= 1'b0;
            edge_type <= `EDGE_RISING;
            current_coarse <= 32'd0;
            current_fine <= 16'd0;
            trigger_counter <= 16'd0;
            rx_delay_value <= 32'd0;
            rx_fine_value <= 16'd0;
            
        end else begin
            // Default assignments
            current_state <= current_state;
            uart_tx_en <= 1'b0;
            uart_tx_data <= uart_tx_data;
            uart_transmission_counter <= uart_transmission_counter;
            coarse_delay <= coarse_delay;
            coarse_update <= 1'b0;
            fine_delay_ps <= fine_delay_ps;
            fine_update <= 1'b0;
            edge_type <= edge_type;
            current_coarse <= current_coarse;
            current_fine <= current_fine;
            trigger_counter <= trigger_counter;
            rx_delay_value <= rx_delay_value;
            rx_fine_value <= rx_fine_value;
            
            // Update current delays
            if (coarse_update) begin
                current_coarse <= coarse_delay;
            end
            if (fine_update) begin
                current_fine <= fine_delay_ps;
            end
            
            // Increment trigger counter
            if (trigger_pulse_for_counter) begin
                trigger_counter <= trigger_counter + 16'd1;
            end
            
            case (current_state)
                STATE_IDLE: begin
                    if (uart_rx_data_valid) begin
                        uart_transmission_counter <= 32'd0;
                        case (uart_rx_data)
                            `CMD_SET_COARSE:  current_state <= STATE_SET_COARSE;
                            `CMD_GET_COARSE:  current_state <= STATE_GET_COARSE;
                            `CMD_SET_EDGE:    current_state <= STATE_SET_EDGE;
                            `CMD_GET_EDGE:    current_state <= STATE_GET_EDGE;
                            `CMD_GET_STATUS:  current_state <= STATE_GET_STATUS;
                            `CMD_RESET_COUNT: current_state <= STATE_RESET_COUNT;
                            `CMD_SET_FINE:    current_state <= STATE_SET_FINE;
                            `CMD_GET_FINE:    current_state <= STATE_GET_FINE;
                            default:          current_state <= STATE_IDLE;
                        endcase
                    end
                end
                
                STATE_SET_COARSE: begin
                    if (uart_transmission_counter >= 4) begin
                        coarse_delay <= rx_delay_value;
                        coarse_update <= 1'b1;
                        current_state <= STATE_IDLE;
                    end else begin
                        if (uart_rx_data_valid) begin
                            case (uart_transmission_counter)
                                0: rx_delay_value[7:0] <= uart_rx_data;
                                1: rx_delay_value[15:8] <= uart_rx_data;
                                2: rx_delay_value[23:16] <= uart_rx_data;
                                3: rx_delay_value[31:24] <= uart_rx_data;
                            endcase
                            uart_transmission_counter <= uart_transmission_counter + 1;
                        end
                    end
                end
                
                STATE_GET_COARSE: begin
                    if (uart_transmission_counter >= 4) begin
                        current_state <= STATE_IDLE;
                    end else begin
                        if (uart_tx_ready) begin
                            case (uart_transmission_counter)
                                0: uart_tx_data <= current_coarse[7:0];
                                1: uart_tx_data <= current_coarse[15:8];
                                2: uart_tx_data <= current_coarse[23:16];
                                3: uart_tx_data <= current_coarse[31:24];
                            endcase
                            uart_tx_en <= 1'b1;
                            uart_transmission_counter <= uart_transmission_counter + 1;
                        end
                    end
                end
                
                STATE_SET_EDGE: begin
                    if (uart_rx_data_valid) begin
                        case (uart_rx_data)
                            8'h00: edge_type <= `EDGE_NONE;
                            8'h01: edge_type <= `EDGE_RISING;
                            8'h02: edge_type <= `EDGE_FALLING;
                            8'h03: edge_type <= `EDGE_BOTH;
                            default: edge_type <= `EDGE_RISING;
                        endcase
                        current_state <= STATE_IDLE;
                    end
                end
                
                STATE_GET_EDGE: begin
                    if (uart_transmission_counter >= 1) begin
                        current_state <= STATE_IDLE;
                    end else begin
                        if (uart_tx_ready) begin
                            uart_tx_data <= {6'd0, edge_type};
                            uart_tx_en <= 1'b1;
                            uart_transmission_counter <= uart_transmission_counter + 1;
                        end
                    end
                end
                
                STATE_GET_STATUS: begin
                    if (uart_transmission_counter >= 8) begin
                        current_state <= STATE_IDLE;
                    end else begin
                        if (uart_tx_ready) begin
                            case (uart_transmission_counter)
                                0: uart_tx_data <= trigger_counter[7:0];
                                1: uart_tx_data <= trigger_counter[15:8];
                                2: uart_tx_data <= current_coarse[7:0];
                                3: uart_tx_data <= current_coarse[15:8];
                                4: uart_tx_data <= current_coarse[23:16];
                                5: uart_tx_data <= current_coarse[31:24];
                                6: uart_tx_data <= current_fine[7:0];
                                7: uart_tx_data <= current_fine[15:8];
                            endcase
                            uart_tx_en <= 1'b1;
                            uart_transmission_counter <= uart_transmission_counter + 1;
                        end
                    end
                end
                
                STATE_RESET_COUNT: begin
                    trigger_counter <= 16'd0;
                    current_state <= STATE_IDLE;
                end
                
                STATE_SET_FINE: begin
                    if (uart_transmission_counter >= 2) begin
                        fine_delay_ps <= rx_fine_value;
                        fine_update <= 1'b1;
                        current_state <= STATE_IDLE;
                    end else begin
                        if (uart_rx_data_valid) begin
                            case (uart_transmission_counter)
                                0: rx_fine_value[7:0] <= uart_rx_data;
                                1: rx_fine_value[15:8] <= uart_rx_data;
                            endcase
                            uart_transmission_counter <= uart_transmission_counter + 1;
                        end
                    end
                end
                
                STATE_GET_FINE: begin
                    if (uart_transmission_counter >= 2) begin
                        current_state <= STATE_IDLE;
                    end else begin
                        if (uart_tx_ready) begin
                            case (uart_transmission_counter)
                                0: uart_tx_data <= current_fine[7:0];
                                1: uart_tx_data <= current_fine[15:8];
                            endcase
                            uart_tx_en <= 1'b1;
                            uart_transmission_counter <= uart_transmission_counter + 1;
                        end
                    end
                end
                
                default: current_state <= STATE_IDLE;
            endcase
        end
    end

endmodule