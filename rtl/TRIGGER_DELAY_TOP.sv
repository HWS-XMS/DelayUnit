`timescale 1ns / 1ps

`include "TRIGGER_DELAY_DEFS.vh"

module TRIGGER_DELAY_TOP (
    input  logic        clk,
    input  logic        rst,
    input  logic        trigger_in,             // PIN1: External trigger input (from DuT, or from PIN3 via test jumper)
    output logic        trigger_delayed_out,    // PIN2: Delayed trigger output
    output logic        soft_trigger_out,       // PIN3: Soft trigger pulse output (for monitoring or test jumper)
    input  logic        uart_rx,
    output logic        uart_tx,
    output logic [3:0]  leds
);

    localparam CLK_FREQ = 200_000_000;  // 200MHz for 5ns resolution
    localparam BAUD_RATE = 1_000_000;

    // =========================================================================
    // FINE_DELAY - Generate 200MHz clocks with phase shifting capability
    // Provides: clk_sys (main), clk_offset (pulse start), clk_width (pulse end)
    // =========================================================================
    logic clk_sys_buf;
    logic clk_offset;
    logic clk_width;
    logic mmcm_locked;

    // Fine delay control signals
    logic [31:0] fine_offset_target;
    logic fine_offset_configure;
    logic fine_offset_configured;
    logic [31:0] fine_width_target;
    logic fine_width_configure;
    logic fine_width_configured;
    logic phase_shift_ready;

    // Current fine delay values (tracked locally)
    logic [31:0] current_fine_offset;
    logic [31:0] current_fine_width;

    FINE_DELAY #(
        .PHASE_WIDTH(32)
    ) fine_delay_inst (
        .clk_in             (clk),
        .rst                (rst),
        .offset_target      (fine_offset_target),
        .offset_configure   (fine_offset_configure),
        .offset_configured  (fine_offset_configured),
        .width_target       (fine_width_target),
        .width_configure    (fine_width_configure),
        .width_configured   (fine_width_configured),
        .clk_out            (clk_sys_buf),
        .clk_offset         (clk_offset),
        .clk_width          (clk_width),
        .locked             (mmcm_locked),
        .phase_shift_ready  (phase_shift_ready)
    );

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
    logic [31:0] current_soft_trigger_width_cycles;
    logic [15:0] trigger_counter;
    logic trigger_pulse;
    logic trigger_pulse_external;
    logic trigger_delayed;
    logic soft_trigger;
    logic [31:0] soft_trigger_width_counter;
    logic soft_trigger_width_update;
    logic [31:0] soft_trigger_width_cycles;

    // Trigger mode: EXTERNAL (0) or INTERNAL (1)
    // This setting determines the expected hardware setup:
    // - EXTERNAL: PIN1 receives trigger from DuT, no jumper needed
    // - INTERNAL: Jumper PIN3 to PIN1, soft_trigger loops back through delay
    logic trigger_mode;

    // Counter trigger mode - only trigger after N edges
    logic counter_mode;
    logic [31:0] edge_count_target;
    logic [31:0] edge_count_current;
    logic counter_trigger_pulse;

    // Armed state - gate trigger output
    logic armed;
    logic armed_mode;  // SINGLE (0) = disarm after trigger, REPEAT (1) = stay armed

    // Soft trigger output - multi-cycle pulse on JA-3 (for debugging/monitoring)
    always_ff @(posedge clk_sys_buf) begin
        if (rst_sync) begin
            soft_trigger_width_counter <= 32'd0;
        end else begin
            if (soft_trigger) begin
                soft_trigger_width_counter <= current_soft_trigger_width_cycles;
            end else if (soft_trigger_width_counter > 0) begin
                soft_trigger_width_counter <= soft_trigger_width_counter - 1;
            end
        end
    end

    assign soft_trigger_out = (soft_trigger_width_counter > 0);

    // CDC for external trigger input
    CDC_EDGE_DETECT #(
        .SYNC_STAGES(3)
    ) cdc_inst (
        .clk(clk_sys_buf),
        .rst(rst_sync),
        .async_in(trigger_in),
        .edge_type(edge_type),
        .edge_pulse(trigger_pulse_external),
        .sync_out()
    );

    // Counter trigger logic - count edges and trigger on Nth edge
    // Only count when armed to prevent accumulated counts during setup
    logic edge_count_reset;
    always_ff @(posedge clk_sys_buf) begin
        if (rst_sync || edge_count_reset) begin
            edge_count_current <= 32'd0;
            counter_trigger_pulse <= 1'b0;
        end else begin
            counter_trigger_pulse <= 1'b0;
            edge_count_current <= edge_count_current;
            if (trigger_pulse_external && armed) begin
                if (counter_mode == `COUNTER_MODE_ENABLED) begin
                    if (edge_count_current + 1 >= edge_count_target) begin
                        counter_trigger_pulse <= 1'b1;
                        edge_count_current <= 32'd0;  // Auto-reset after trigger
                    end else begin
                        edge_count_current <= edge_count_current + 1;
                    end
                end
            end
        end
    end

    // Trigger source MUX based on trigger mode and counter mode:
    // EXTERNAL mode (0) + counter disabled: Use edge-detected trigger from PIN1
    // EXTERNAL mode (0) + counter enabled: Use counter_trigger_pulse (Nth edge)
    // INTERNAL mode (1): Use soft_trigger command directly (bypasses PIN1)
    logic external_trigger_selected;
    logic trigger_pulse_ungated;
    assign external_trigger_selected = (counter_mode == `COUNTER_MODE_ENABLED) ? counter_trigger_pulse : trigger_pulse_external;
    assign trigger_pulse_ungated = (trigger_mode == `TRIGGER_MODE_EXTERNAL) ? external_trigger_selected : soft_trigger;

    // Gate trigger with armed state
    assign trigger_pulse = trigger_pulse_ungated && armed;

    // Auto-disarm logic for SINGLE mode
    logic arm_cmd;      // Set by state machine
    logic disarm_cmd;   // Set by state machine
    always_ff @(posedge clk_sys_buf) begin
        if (rst_sync) begin
            armed <= 1'b0;
        end else begin
            if (disarm_cmd) begin
                armed <= 1'b0;
            end else if (arm_cmd) begin
                armed <= 1'b1;
            end else if (trigger_pulse_ungated && armed && armed_mode == `ARMED_MODE_SINGLE) begin
                // Auto-disarm after trigger in SINGLE mode
                armed <= 1'b0;
            end else begin
                armed <= armed;
            end
        end
    end

    CONFIGURABLE_DELAY #(
        .MAX_DELAY_BITS(32)
    ) delay_inst (
        .clk(clk_sys_buf),
        .clk_offset(clk_offset),
        .clk_width(clk_width),
        .rst(rst_sync),
        .trigger_in(trigger_pulse),
        .trigger_out(trigger_delayed),
        .delay_cycles(delay_cycles),
        .delay_update(delay_update),
        .output_width_cycles(output_width_cycles),
        .width_update(width_update)
    );

    assign trigger_delayed_out = trigger_delayed;

    // LED assignment
    assign leds = {mmcm_locked, trigger_counter[2:0]};

    // =========================================================================
    // State Machine - Commands for coarse delay only
    // =========================================================================
    typedef enum {
        STATE_IDLE,
        STATE_SET_COARSE,
        STATE_GET_COARSE,
        STATE_SET_EDGE,
        STATE_GET_EDGE,
        STATE_GET_STATUS,
        STATE_RESET_COUNT,
        STATE_SOFT_TRIGGER,
        STATE_SET_OUTPUT_TRIGGER_WIDTH,
        STATE_GET_OUTPUT_TRIGGER_WIDTH,
        STATE_SET_TRIGGER_MODE,
        STATE_GET_TRIGGER_MODE,
        STATE_SET_SOFT_TRIGGER_WIDTH,
        STATE_GET_SOFT_TRIGGER_WIDTH,
        STATE_SET_COUNTER_MODE,
        STATE_GET_COUNTER_MODE,
        STATE_SET_EDGE_COUNT_TARGET,
        STATE_GET_EDGE_COUNT_TARGET,
        STATE_RESET_EDGE_COUNT,
        STATE_ARM,
        STATE_DISARM,
        STATE_SET_ARMED_MODE,
        STATE_GET_ARMED_MODE,
        STATE_GET_ARMED,
        STATE_SET_FINE_OFFSET,
        STATE_GET_FINE_OFFSET,
        STATE_SET_FINE_WIDTH,
        STATE_GET_FINE_WIDTH,
        STATE_WAIT_FINE_OFFSET,
        STATE_WAIT_FINE_WIDTH
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
            trigger_mode <= `TRIGGER_MODE_EXTERNAL;  // Default to external mode
            soft_trigger_width_cycles <= 32'd10;     // Default 50ns pulse (10 cycles @ 200MHz)
            current_soft_trigger_width_cycles <= 32'd10;
            soft_trigger_width_update <= 1'b0;
            counter_mode <= `COUNTER_MODE_DISABLED;
            edge_count_target <= 32'd1;              // Default: trigger on 1st edge
            edge_count_reset <= 1'b0;
            armed_mode <= `ARMED_MODE_SINGLE;        // Default: disarm after trigger
            arm_cmd <= 1'b0;
            disarm_cmd <= 1'b0;
            // Fine delay registers
            fine_offset_target <= 32'd0;
            fine_offset_configure <= 1'b0;
            fine_width_target <= 32'd0;
            fine_width_configure <= 1'b0;
            current_fine_offset <= 32'd0;
            current_fine_width <= 32'd0;
        end else begin
            soft_trigger <= 1'b0;  // Default: no soft trigger
            width_update <= 1'b0;  // Default: no width update
            soft_trigger_width_update <= 1'b0;  // Default: no soft trigger width update
            edge_count_reset <= 1'b0;  // Default: no edge count reset
            arm_cmd <= 1'b0;  // Default: no arm command
            disarm_cmd <= 1'b0;  // Default: no disarm command
            fine_offset_configure <= 1'b0;  // Default: no fine offset configure
            fine_width_configure <= 1'b0;   // Default: no fine width configure
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
            trigger_mode <= trigger_mode;
            counter_mode <= counter_mode;
            edge_count_target <= edge_count_target;
            armed_mode <= armed_mode;
            output_width_cycles <= output_width_cycles;
            current_width <= current_width;
            soft_trigger_width_cycles <= soft_trigger_width_cycles;
            current_soft_trigger_width_cycles <= current_soft_trigger_width_cycles;

            if (delay_update) begin
                current_delay <= delay_cycles;
            end

            if (width_update) begin
                current_width <= output_width_cycles;
            end

            if (soft_trigger_width_update) begin
                current_soft_trigger_width_cycles <= soft_trigger_width_cycles;
            end

            if (trigger_pulse) begin
                trigger_counter <= trigger_counter + 16'd1;
            end

            case (current_state)
                STATE_IDLE: begin
                    if (uart_rx_data_valid) begin
                        uart_transmission_counter <= 32'd0;
                        case (uart_rx_data)
                            `CMD_SET_COARSE:                 current_state <= STATE_SET_COARSE;
                            `CMD_GET_COARSE:                 current_state <= STATE_GET_COARSE;
                            `CMD_SET_EDGE:                   current_state <= STATE_SET_EDGE;
                            `CMD_GET_EDGE:                   current_state <= STATE_GET_EDGE;
                            `CMD_GET_STATUS:                 current_state <= STATE_GET_STATUS;
                            `CMD_RESET_COUNT:                current_state <= STATE_RESET_COUNT;
                            `CMD_SOFT_TRIGGER:               current_state <= STATE_SOFT_TRIGGER;
                            `CMD_SET_OUTPUT_TRIGGER_WIDTH:   current_state <= STATE_SET_OUTPUT_TRIGGER_WIDTH;
                            `CMD_GET_OUTPUT_TRIGGER_WIDTH:   current_state <= STATE_GET_OUTPUT_TRIGGER_WIDTH;
                            `CMD_SET_TRIGGER_MODE:           current_state <= STATE_SET_TRIGGER_MODE;
                            `CMD_GET_TRIGGER_MODE:           current_state <= STATE_GET_TRIGGER_MODE;
                            `CMD_SET_SOFT_TRIGGER_WIDTH:     current_state <= STATE_SET_SOFT_TRIGGER_WIDTH;
                            `CMD_GET_SOFT_TRIGGER_WIDTH:     current_state <= STATE_GET_SOFT_TRIGGER_WIDTH;
                            `CMD_SET_COUNTER_MODE:           current_state <= STATE_SET_COUNTER_MODE;
                            `CMD_GET_COUNTER_MODE:           current_state <= STATE_GET_COUNTER_MODE;
                            `CMD_SET_EDGE_COUNT_TARGET:      current_state <= STATE_SET_EDGE_COUNT_TARGET;
                            `CMD_GET_EDGE_COUNT_TARGET:      current_state <= STATE_GET_EDGE_COUNT_TARGET;
                            `CMD_RESET_EDGE_COUNT:           current_state <= STATE_RESET_EDGE_COUNT;
                            `CMD_ARM:                        current_state <= STATE_ARM;
                            `CMD_DISARM:                     current_state <= STATE_DISARM;
                            `CMD_SET_ARMED_MODE:             current_state <= STATE_SET_ARMED_MODE;
                            `CMD_GET_ARMED_MODE:             current_state <= STATE_GET_ARMED_MODE;
                            `CMD_GET_ARMED:                  current_state <= STATE_GET_ARMED;
                            `CMD_SET_FINE_OFFSET:            current_state <= STATE_SET_FINE_OFFSET;
                            `CMD_GET_FINE_OFFSET:            current_state <= STATE_GET_FINE_OFFSET;
                            `CMD_SET_FINE_WIDTH:             current_state <= STATE_SET_FINE_WIDTH;
                            `CMD_GET_FINE_WIDTH:             current_state <= STATE_GET_FINE_WIDTH;
                            default:                         current_state <= STATE_IDLE;
                        endcase
                    end
                end

                STATE_SET_COARSE: begin
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

                STATE_GET_COARSE: begin
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
                    // Extended status: 26 bytes total
                    // [0:1]   trigger_counter (2 bytes)
                    // [2:5]   current_delay (4 bytes)
                    // [6:9]   current_fine_offset (4 bytes, signed)
                    // [10:13] current_width (4 bytes)
                    // [14:17] current_fine_width (4 bytes, signed)
                    // [18]    armed (1 byte)
                    // [19]    trigger_mode (1 byte)
                    // [20]    armed_mode (1 byte)
                    // [21]    counter_mode (1 byte)
                    // [22]    mmcm_locked (1 byte)
                    // [23]    phase_shift_ready (1 byte)
                    // [24]    edge_type (1 byte)
                    // [25]    reserved (1 byte)
                    if (uart_transmission_counter >= 26) begin
                        current_state <= STATE_IDLE;
                    end else begin
                        if (uart_tx_ready) begin
                            case (uart_transmission_counter)
                                0:  uart_tx_data <= trigger_counter[7:0];
                                1:  uart_tx_data <= trigger_counter[15:8];
                                2:  uart_tx_data <= current_delay[7:0];
                                3:  uart_tx_data <= current_delay[15:8];
                                4:  uart_tx_data <= current_delay[23:16];
                                5:  uart_tx_data <= current_delay[31:24];
                                6:  uart_tx_data <= current_fine_offset[7:0];
                                7:  uart_tx_data <= current_fine_offset[15:8];
                                8:  uart_tx_data <= current_fine_offset[23:16];
                                9:  uart_tx_data <= current_fine_offset[31:24];
                                10: uart_tx_data <= current_width[7:0];
                                11: uart_tx_data <= current_width[15:8];
                                12: uart_tx_data <= current_width[23:16];
                                13: uart_tx_data <= current_width[31:24];
                                14: uart_tx_data <= current_fine_width[7:0];
                                15: uart_tx_data <= current_fine_width[15:8];
                                16: uart_tx_data <= current_fine_width[23:16];
                                17: uart_tx_data <= current_fine_width[31:24];
                                18: uart_tx_data <= {7'd0, armed};
                                19: uart_tx_data <= {7'd0, trigger_mode};
                                20: uart_tx_data <= {7'd0, armed_mode};
                                21: uart_tx_data <= {7'd0, counter_mode};
                                22: uart_tx_data <= {7'd0, mmcm_locked};
                                23: uart_tx_data <= {7'd0, phase_shift_ready};
                                24: uart_tx_data <= {6'd0, edge_type};
                                25: uart_tx_data <= 8'd0;  // Reserved
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

                STATE_SET_OUTPUT_TRIGGER_WIDTH: begin
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

                STATE_GET_OUTPUT_TRIGGER_WIDTH: begin
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

                STATE_SET_TRIGGER_MODE: begin
                    if (uart_rx_data_valid) begin
                        trigger_mode <= uart_rx_data[0];
                        current_state <= STATE_IDLE;
                    end
                end

                STATE_GET_TRIGGER_MODE: begin
                    if (uart_transmission_counter >= 1) begin
                        current_state <= STATE_IDLE;
                    end else begin
                        if (uart_tx_ready) begin
                            uart_tx_data <= {7'b0, trigger_mode};
                            uart_tx_en <= 1'b1;
                            uart_transmission_counter <= uart_transmission_counter + 1;
                        end
                    end
                end

                STATE_SET_SOFT_TRIGGER_WIDTH: begin
                    if (uart_transmission_counter >= 4) begin
                        soft_trigger_width_cycles <= rx_delay_value;
                        soft_trigger_width_update <= 1'b1;
                        current_state <= STATE_IDLE;
                    end else begin
                        if (uart_rx_data_valid) begin
                            rx_delay_value[uart_transmission_counter*8 +: 8] <= uart_rx_data;
                            uart_transmission_counter <= uart_transmission_counter + 1;
                        end
                    end
                end

                STATE_GET_SOFT_TRIGGER_WIDTH: begin
                    if (uart_transmission_counter >= 4) begin
                        current_state <= STATE_IDLE;
                    end else begin
                        if (uart_tx_ready) begin
                            case (uart_transmission_counter)
                                0: uart_tx_data <= current_soft_trigger_width_cycles[7:0];
                                1: uart_tx_data <= current_soft_trigger_width_cycles[15:8];
                                2: uart_tx_data <= current_soft_trigger_width_cycles[23:16];
                                3: uart_tx_data <= current_soft_trigger_width_cycles[31:24];
                            endcase
                            uart_tx_en <= 1'b1;
                            uart_transmission_counter <= uart_transmission_counter + 1;
                        end
                    end
                end

                STATE_SET_COUNTER_MODE: begin
                    if (uart_rx_data_valid) begin
                        counter_mode <= uart_rx_data[0];
                        current_state <= STATE_IDLE;
                    end
                end

                STATE_GET_COUNTER_MODE: begin
                    if (uart_transmission_counter >= 1) begin
                        current_state <= STATE_IDLE;
                    end else begin
                        if (uart_tx_ready) begin
                            uart_tx_data <= {7'b0, counter_mode};
                            uart_tx_en <= 1'b1;
                            uart_transmission_counter <= uart_transmission_counter + 1;
                        end
                    end
                end

                STATE_SET_EDGE_COUNT_TARGET: begin
                    if (uart_transmission_counter >= 4) begin
                        edge_count_target <= rx_delay_value;
                        current_state <= STATE_IDLE;
                    end else begin
                        if (uart_rx_data_valid) begin
                            rx_delay_value[uart_transmission_counter*8 +: 8] <= uart_rx_data;
                            uart_transmission_counter <= uart_transmission_counter + 1;
                        end
                    end
                end

                STATE_GET_EDGE_COUNT_TARGET: begin
                    if (uart_transmission_counter >= 4) begin
                        current_state <= STATE_IDLE;
                    end else begin
                        if (uart_tx_ready) begin
                            case (uart_transmission_counter)
                                0: uart_tx_data <= edge_count_target[7:0];
                                1: uart_tx_data <= edge_count_target[15:8];
                                2: uart_tx_data <= edge_count_target[23:16];
                                3: uart_tx_data <= edge_count_target[31:24];
                            endcase
                            uart_tx_en <= 1'b1;
                            uart_transmission_counter <= uart_transmission_counter + 1;
                        end
                    end
                end

                STATE_RESET_EDGE_COUNT: begin
                    edge_count_reset <= 1'b1;
                    current_state <= STATE_IDLE;
                end

                STATE_ARM: begin
                    arm_cmd <= 1'b1;
                    current_state <= STATE_IDLE;
                end

                STATE_DISARM: begin
                    disarm_cmd <= 1'b1;
                    current_state <= STATE_IDLE;
                end

                STATE_SET_ARMED_MODE: begin
                    if (uart_rx_data_valid) begin
                        armed_mode <= uart_rx_data[0];
                        current_state <= STATE_IDLE;
                    end
                end

                STATE_GET_ARMED_MODE: begin
                    if (uart_transmission_counter >= 1) begin
                        current_state <= STATE_IDLE;
                    end else begin
                        if (uart_tx_ready) begin
                            uart_tx_data <= {7'b0, armed_mode};
                            uart_tx_en <= 1'b1;
                            uart_transmission_counter <= uart_transmission_counter + 1;
                        end
                    end
                end

                STATE_GET_ARMED: begin
                    if (uart_transmission_counter >= 1) begin
                        current_state <= STATE_IDLE;
                    end else begin
                        if (uart_tx_ready) begin
                            uart_tx_data <= {7'b0, armed};
                            uart_tx_en <= 1'b1;
                            uart_transmission_counter <= uart_transmission_counter + 1;
                        end
                    end
                end

                // =========================================================
                // Fine delay offset commands
                // =========================================================
                STATE_SET_FINE_OFFSET: begin
                    if (uart_transmission_counter >= 4) begin
                        fine_offset_target <= rx_delay_value;
                        fine_offset_configure <= 1'b1;
                        current_state <= STATE_WAIT_FINE_OFFSET;
                    end else begin
                        if (uart_rx_data_valid) begin
                            rx_delay_value[uart_transmission_counter*8 +: 8] <= uart_rx_data;
                            uart_transmission_counter <= uart_transmission_counter + 1;
                        end
                    end
                end

                STATE_WAIT_FINE_OFFSET: begin
                    if (fine_offset_configured) begin
                        current_fine_offset <= fine_offset_target;
                        current_state <= STATE_IDLE;
                    end
                end

                STATE_GET_FINE_OFFSET: begin
                    if (uart_transmission_counter >= 4) begin
                        current_state <= STATE_IDLE;
                    end else begin
                        if (uart_tx_ready) begin
                            case (uart_transmission_counter)
                                0: uart_tx_data <= current_fine_offset[7:0];
                                1: uart_tx_data <= current_fine_offset[15:8];
                                2: uart_tx_data <= current_fine_offset[23:16];
                                3: uart_tx_data <= current_fine_offset[31:24];
                            endcase
                            uart_tx_en <= 1'b1;
                            uart_transmission_counter <= uart_transmission_counter + 1;
                        end
                    end
                end

                // =========================================================
                // Fine delay width commands
                // =========================================================
                STATE_SET_FINE_WIDTH: begin
                    if (uart_transmission_counter >= 4) begin
                        fine_width_target <= rx_delay_value;
                        fine_width_configure <= 1'b1;
                        current_state <= STATE_WAIT_FINE_WIDTH;
                    end else begin
                        if (uart_rx_data_valid) begin
                            rx_delay_value[uart_transmission_counter*8 +: 8] <= uart_rx_data;
                            uart_transmission_counter <= uart_transmission_counter + 1;
                        end
                    end
                end

                STATE_WAIT_FINE_WIDTH: begin
                    if (fine_width_configured) begin
                        current_fine_width <= fine_width_target;
                        current_state <= STATE_IDLE;
                    end
                end

                STATE_GET_FINE_WIDTH: begin
                    if (uart_transmission_counter >= 4) begin
                        current_state <= STATE_IDLE;
                    end else begin
                        if (uart_tx_ready) begin
                            case (uart_transmission_counter)
                                0: uart_tx_data <= current_fine_width[7:0];
                                1: uart_tx_data <= current_fine_width[15:8];
                                2: uart_tx_data <= current_fine_width[23:16];
                                3: uart_tx_data <= current_fine_width[31:24];
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
