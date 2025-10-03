`timescale 1ns / 1ps

`include "TRIGGER_DELAY_DEFS.vh"

module TRIGGER_DELAY_TOP (
    input  logic        clk,
    input  logic        rst,
    input  logic        trigger_in,
    output logic        trigger_out,
    output logic        soft_trigger_out,  // Soft trigger output on JA-3
    input  logic        uart_rx,
    output logic        uart_tx,
    output logic [3:0]  leds
);

    localparam CLK_FREQ = 200_000_000;  // 200MHz for 5ns resolution
    localparam BAUD_RATE = 1_000_000;

    // =========================================================================
    // MMCM - Generate 200MHz from 100MHz input
    // =========================================================================
    logic clk_sys;
    logic mmcm_locked;
    logic clkfb, clkfb_buf;

    MMCME2_ADV #(
        .BANDWIDTH            ("OPTIMIZED"),
        .CLKFBOUT_MULT_F      (10.0),       // 100MHz × 10 = 1000MHz VCO
        .CLKFBOUT_PHASE       (0.0),
        .CLKFBOUT_USE_FINE_PS ("FALSE"),
        .CLKIN1_PERIOD        (10.0),       // 100MHz input
        .CLKIN2_PERIOD        (0.0),
        .CLKOUT0_DIVIDE_F     (5.0),        // 1000MHz / 5 = 200MHz
        .CLKOUT0_DUTY_CYCLE   (0.5),
        .CLKOUT0_PHASE        (0.0),
        .CLKOUT0_USE_FINE_PS  ("FALSE"),
        .COMPENSATION         ("ZHOLD"),
        .DIVCLK_DIVIDE        (1),
        .REF_JITTER1          (0.01),
        .STARTUP_WAIT         ("FALSE")
    ) mmcm_sys (
        .CLKOUT0              (clk_sys),
        .CLKOUT0B             (),
        .CLKOUT1              (),
        .CLKOUT1B             (),
        .CLKOUT2              (),
        .CLKOUT2B             (),
        .CLKOUT3              (),
        .CLKOUT3B             (),
        .CLKOUT4              (),
        .CLKOUT5              (),
        .CLKOUT6              (),
        .CLKFBOUT             (clkfb),
        .CLKFBOUTB            (),
        .LOCKED               (mmcm_locked),
        .CLKINSTOPPED         (),
        .CLKFBSTOPPED         (),
        .CLKIN1               (clk),
        .CLKIN2               (1'b0),
        .CLKINSEL             (1'b1),
        .CLKFBIN              (clkfb_buf),
        .PSCLK                (1'b0),
        .PSEN                 (1'b0),
        .PSINCDEC             (1'b0),
        .PSDONE               (),
        .DADDR                (7'h0),
        .DCLK                 (1'b0),
        .DEN                  (1'b0),
        .DI                   (16'h0),
        .DWE                  (1'b0),
        .DO                   (),
        .DRDY                 (),
        .PWRDWN               (1'b0),
        .RST                  (rst)
    );

    BUFG clkfb_bufg (.I(clkfb), .O(clkfb_buf));

    logic clk_sys_buf;
    BUFG sys_bufg (.I(clk_sys), .O(clk_sys_buf));

    // Reset synchronization
    logic rst_sync;
    always_ff @(posedge clk_sys_buf) begin
        rst_sync <= rst || !mmcm_locked;
    end

    // =========================================================================
    // UART
    // =========================================================================
    logic [7:0] uart_rx_data;
    logic uart_rx_data_valid;
    logic uart_tx_en;
    logic [7:0] uart_tx_data;
    logic uart_tx_ready;

    UART_RX #(
        .ELEMENT_WIDTH(8),
        .BAUDRATE(BAUD_RATE),
        .SYSTEMCLOCK(CLK_FREQ)
    ) uart_rx_inst (
        .clk(clk_sys_buf),
        .rst(rst_sync),
        .rx_line(uart_rx),
        .rx_data(uart_rx_data),
        .rx_data_valid(uart_rx_data_valid)
    );

    UART_TX #(
        .SYSTEMCLOCK(CLK_FREQ),
        .BAUDRATE(BAUD_RATE),
        .ELEMENT_WIDTH(8)
    ) uart_tx_inst (
        .clk(clk_sys_buf),
        .rst(rst_sync),
        .tx_en(uart_tx_en),
        .tx_data(uart_tx_data),
        .tx_line(uart_tx),
        .tx_ready(uart_tx_ready)
    );

    // =========================================================================
    // Delay Logic - 5ns resolution (200MHz) - Clock Cycle Delay Only
    // =========================================================================
    logic [31:0] delay_cycles;
    logic delay_update;
    logic [31:0] output_width_cycles;
    logic width_update;
    logic [1:0] edge_type;
    logic [31:0] current_delay;
    logic [31:0] current_width;
    logic [15:0] trigger_counter;
    logic trigger_pulse;
    logic trigger_delayed;
    logic soft_trigger;
    logic [7:0] soft_trigger_width;

    // Soft trigger output - multi-cycle pulse on JA-3 (make it wider for reliable CDC detection)
    always_ff @(posedge clk_sys_buf) begin
        if (rst_sync) begin
            soft_trigger_width <= 8'd0;
        end else begin
            if (soft_trigger) begin
                soft_trigger_width <= 8'd10;  // 50ns pulse (10 cycles @ 200MHz)
            end else if (soft_trigger_width > 0) begin
                soft_trigger_width <= soft_trigger_width - 1;
            end
        end
    end

    assign soft_trigger_out = (soft_trigger_width > 0);

    CDC_EDGE_DETECT #(
        .SYNC_STAGES(3)
    ) cdc_inst (
        .clk(clk_sys_buf),
        .rst(rst_sync),
        .async_in(trigger_in),
        .edge_type(edge_type),
        .edge_pulse(trigger_pulse),
        .sync_out()
    );

    CONFIGURABLE_DELAY #(
        .MAX_DELAY_BITS(32)
    ) delay_inst (
        .clk(clk_sys_buf),
        .rst(rst_sync),
        .trigger_in(trigger_pulse),
        .trigger_out(trigger_delayed),
        .delay_cycles(delay_cycles),
        .delay_update(delay_update),
        .output_width_cycles(output_width_cycles),
        .width_update(width_update)
    );

    assign trigger_out = trigger_delayed;

    // LED assignment
    assign leds = {mmcm_locked, trigger_counter[2:0]};

    // =========================================================================
    // State Machine - Commands for coarse delay only
    // =========================================================================
    typedef enum {
        STATE_IDLE,
        STATE_SET_DELAY,
        STATE_GET_DELAY,
        STATE_SET_EDGE,
        STATE_GET_EDGE,
        STATE_GET_STATUS,
        STATE_RESET_COUNT,
        STATE_SOFT_TRIGGER,
        STATE_SET_WIDTH,
        STATE_GET_WIDTH
    } state_t;
    state_t current_state;

    logic [31:0] uart_transmission_counter;
    logic [31:0] rx_delay_value;

    always_ff @(posedge clk_sys_buf) begin
        if (rst_sync) begin
            current_state <= STATE_IDLE;
            uart_tx_en <= 1'b0;
            uart_tx_data <= 8'b0;
            uart_transmission_counter <= 32'd0;
            delay_cycles <= 32'd0;
            delay_update <= 1'b0;
            output_width_cycles <= 32'd1;  // Default 1 cycle (5ns)
            width_update <= 1'b0;
            edge_type <= `EDGE_RISING;
            current_delay <= 32'd0;
            current_width <= 32'd1;
            trigger_counter <= 16'd0;
            rx_delay_value <= 32'd0;
            soft_trigger <= 1'b0;
        end else begin
            soft_trigger <= 1'b0;  // Default: no soft trigger
            width_update <= 1'b0;  // Default: no width update
            current_state <= current_state;
            uart_tx_en <= 1'b0;
            uart_tx_data <= uart_tx_data;
            uart_transmission_counter <= uart_transmission_counter;
            delay_cycles <= delay_cycles;
            delay_update <= 1'b0;
            edge_type <= edge_type;
            current_delay <= current_delay;
            trigger_counter <= trigger_counter;
            rx_delay_value <= rx_delay_value;

            if (delay_update) begin
                current_delay <= delay_cycles;
            end

            if (width_update) begin
                current_width <= output_width_cycles;
            end

            if (trigger_pulse) begin
                trigger_counter <= trigger_counter + 16'd1;
            end

            case (current_state)
                STATE_IDLE: begin
                    if (uart_rx_data_valid) begin
                        uart_transmission_counter <= 32'd0;
                        case (uart_rx_data)
                            `CMD_SET_COARSE:    current_state <= STATE_SET_DELAY;
                            `CMD_GET_COARSE:    current_state <= STATE_GET_DELAY;
                            `CMD_SET_EDGE:      current_state <= STATE_SET_EDGE;
                            `CMD_GET_EDGE:      current_state <= STATE_GET_EDGE;
                            `CMD_GET_STATUS:    current_state <= STATE_GET_STATUS;
                            `CMD_RESET_COUNT:   current_state <= STATE_RESET_COUNT;
                            `CMD_SOFT_TRIGGER:  current_state <= STATE_SOFT_TRIGGER;
                            `CMD_SET_WIDTH:     current_state <= STATE_SET_WIDTH;
                            `CMD_GET_WIDTH:     current_state <= STATE_GET_WIDTH;
                            default:            current_state <= STATE_IDLE;
                        endcase
                    end
                end

                STATE_SET_DELAY: begin
                    if (uart_transmission_counter >= 4) begin
                        delay_cycles <= rx_delay_value;
                        delay_update <= 1'b1;
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

                STATE_GET_DELAY: begin
                    if (uart_transmission_counter >= 4) begin
                        current_state <= STATE_IDLE;
                    end else begin
                        if (uart_tx_ready) begin
                            case (uart_transmission_counter)
                                0: uart_tx_data <= current_delay[7:0];
                                1: uart_tx_data <= current_delay[15:8];
                                2: uart_tx_data <= current_delay[23:16];
                                3: uart_tx_data <= current_delay[31:24];
                            endcase
                            uart_tx_en <= 1'b1;
                            uart_transmission_counter <= uart_transmission_counter + 1;
                        end
                    end
                end

                STATE_SET_EDGE: begin
                    if (uart_rx_data_valid) begin
                        edge_type <= uart_rx_data[1:0];
                        current_state <= STATE_IDLE;
                    end
                end

                STATE_GET_EDGE: begin
                    if (uart_transmission_counter >= 1) begin
                        current_state <= STATE_IDLE;
                    end else begin
                        if (uart_tx_ready) begin
                            uart_tx_data <= {6'b0, edge_type};
                            uart_tx_en <= 1'b1;
                            uart_transmission_counter <= uart_transmission_counter + 1;
                        end
                    end
                end

                STATE_GET_STATUS: begin
                    if (uart_transmission_counter >= 6) begin
                        current_state <= STATE_IDLE;
                    end else begin
                        if (uart_tx_ready) begin
                            case (uart_transmission_counter)
                                0: uart_tx_data <= trigger_counter[7:0];
                                1: uart_tx_data <= trigger_counter[15:8];
                                2: uart_tx_data <= current_delay[7:0];
                                3: uart_tx_data <= current_delay[15:8];
                                4: uart_tx_data <= current_delay[23:16];
                                5: uart_tx_data <= current_delay[31:24];
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

                STATE_SOFT_TRIGGER: begin
                    soft_trigger <= 1'b1;
                    current_state <= STATE_IDLE;
                end

                STATE_SET_WIDTH: begin
                    if (uart_transmission_counter >= 4) begin
                        output_width_cycles <= rx_delay_value;
                        width_update <= 1'b1;
                        current_state <= STATE_IDLE;
                    end else begin
                        if (uart_rx_data_valid) begin
                            rx_delay_value[uart_transmission_counter*8 +: 8] <= uart_rx_data;
                            uart_transmission_counter <= uart_transmission_counter + 1;
                        end
                    end
                end

                STATE_GET_WIDTH: begin
                    if (uart_transmission_counter >= 4) begin
                        current_state <= STATE_IDLE;
                    end else begin
                        if (uart_tx_ready) begin
                            case (uart_transmission_counter)
                                0: uart_tx_data <= current_width[7:0];
                                1: uart_tx_data <= current_width[15:8];
                                2: uart_tx_data <= current_width[23:16];
                                3: uart_tx_data <= current_width[31:24];
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
