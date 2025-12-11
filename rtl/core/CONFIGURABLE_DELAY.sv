`timescale 1ns / 1ps

module CONFIGURABLE_DELAY #(
    parameter MAX_DELAY_BITS = 32
)(
    input  logic clk,               // Main clock (200MHz)
    input  logic clk_offset,        // Phase-shifted clock for pulse start
    input  logic clk_width,         // Phase-shifted clock for pulse end
    input  logic rst,
    input  logic trigger_in,        // Already a pulse from CDC edge detect
    output logic trigger_out,
    input  logic [MAX_DELAY_BITS-1:0] delay_cycles,
    input  logic delay_update,
    input  logic [MAX_DELAY_BITS-1:0] output_width_cycles,
    input  logic width_update
);

    logic [MAX_DELAY_BITS-1:0] current_delay;
    logic [MAX_DELAY_BITS-1:0] current_width;
    logic [MAX_DELAY_BITS-1:0] counter;
    logic [MAX_DELAY_BITS-1:0] width_counter;
    logic counting;
    logic trigger_pending;

    // Coarse timing signals (main clock domain)
    logic coarse_delay_done;    // Coarse delay counter reached zero
    logic coarse_width_done;    // Coarse width counter reached zero

    // Fine timing signals (phase-shifted clock domains)
    logic output_set;           // Set by clk_offset after coarse_delay_done
    logic output_reset;         // Set by clk_width after coarse_width_done

    // Output flip-flop
    logic output_active;

    // =========================================================================
    // Configuration registers (main clock domain)
    // =========================================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            current_delay <= '0;
            current_width <= 32'd1;  // Default 1 cycle (5ns)
        end else begin
            if (delay_update) begin
                current_delay <= delay_cycles;
            end
            if (width_update) begin
                current_width <= output_width_cycles;
            end
        end
    end

    // =========================================================================
    // Coarse delay counter (main clock domain)
    // =========================================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            counter <= '0;
            counting <= 1'b0;
            trigger_pending <= 1'b0;
            coarse_delay_done <= 1'b0;
        end else begin
            coarse_delay_done <= 1'b0;

            // trigger_in is already a single-cycle pulse from CDC
            if (trigger_in && !counting && !output_active) begin
                if (current_delay == '0) begin
                    // Zero delay: immediately signal coarse done
                    coarse_delay_done <= 1'b1;
                end else begin
                    counting <= 1'b1;
                    counter <= current_delay - 1'b1;
                end
            end else if (trigger_in && counting) begin
                trigger_pending <= 1'b1;
            end

            if (counting) begin
                if (counter == '0) begin
                    coarse_delay_done <= 1'b1;

                    if (trigger_pending) begin
                        counter <= current_delay - 1'b1;
                        trigger_pending <= 1'b0;
                    end else begin
                        counting <= 1'b0;
                    end
                end else begin
                    counter <= counter - 1'b1;
                end
            end
        end
    end

    // =========================================================================
    // Coarse width counter (main clock domain)
    // =========================================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            width_counter <= '0;
            coarse_width_done <= 1'b0;
        end else begin
            coarse_width_done <= 1'b0;

            if (coarse_delay_done) begin
                // Start width counter when delay is done
                if (current_width == '0 || current_width == 32'd1) begin
                    // Zero or one cycle width: immediately signal done
                    coarse_width_done <= 1'b1;
                end else begin
                    width_counter <= current_width - 1'b1;
                end
            end else if (width_counter > 0) begin
                if (width_counter == 32'd1) begin
                    coarse_width_done <= 1'b1;
                    width_counter <= '0;
                end else begin
                    width_counter <= width_counter - 1'b1;
                end
            end
        end
    end

    // =========================================================================
    // Fine edge control - SET pulse (clk_offset domain)
    // Synchronize coarse_delay_done into clk_offset domain and generate SET
    // =========================================================================
    logic coarse_delay_done_sync1, coarse_delay_done_sync2;
    logic coarse_delay_done_edge;

    always_ff @(posedge clk_offset) begin
        if (rst) begin
            coarse_delay_done_sync1 <= 1'b0;
            coarse_delay_done_sync2 <= 1'b0;
        end else begin
            coarse_delay_done_sync1 <= coarse_delay_done;
            coarse_delay_done_sync2 <= coarse_delay_done_sync1;
        end
    end

    assign coarse_delay_done_edge = coarse_delay_done_sync1 && !coarse_delay_done_sync2;
    assign output_set = coarse_delay_done_edge;

    // =========================================================================
    // Fine edge control - RESET pulse (clk_width domain)
    // Synchronize coarse_width_done into clk_width domain and generate RESET
    // =========================================================================
    logic coarse_width_done_sync1, coarse_width_done_sync2;
    logic coarse_width_done_edge;

    always_ff @(posedge clk_width) begin
        if (rst) begin
            coarse_width_done_sync1 <= 1'b0;
            coarse_width_done_sync2 <= 1'b0;
        end else begin
            coarse_width_done_sync1 <= coarse_width_done;
            coarse_width_done_sync2 <= coarse_width_done_sync1;
        end
    end

    assign coarse_width_done_edge = coarse_width_done_sync1 && !coarse_width_done_sync2;
    assign output_reset = coarse_width_done_edge;

    // =========================================================================
    // Output SR flip-flop (main clock domain with async set/reset)
    // SET has priority over RESET for proper pulse generation
    // =========================================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            output_active <= 1'b0;
        end else begin
            if (output_set) begin
                output_active <= 1'b1;
            end else if (output_reset) begin
                output_active <= 1'b0;
            end
        end
    end

    assign trigger_out = output_active;

endmodule
