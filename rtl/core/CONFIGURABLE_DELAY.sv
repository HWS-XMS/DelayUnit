`timescale 1ns / 1ps

module CONFIGURABLE_DELAY #(
    parameter MAX_DELAY_BITS = 32
)(
    input  logic clk,
    input  logic rst,
    input  logic trigger_in,  // Already a pulse from CDC edge detect
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
    logic output_active;

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

    always_ff @(posedge clk) begin
        if (rst) begin
            counter <= '0;
            width_counter <= '0;
            counting <= 1'b0;
            trigger_pending <= 1'b0;
            output_active <= 1'b0;
        end else begin
            // Handle output pulse width
            if (output_active) begin
                if (width_counter == '0) begin
                    output_active <= 1'b0;
                end else begin
                    width_counter <= width_counter - 1'b1;
                end
            end

            // trigger_in is already a single-cycle pulse from CDC
            if (trigger_in && !counting && !output_active) begin
                if (current_delay == '0) begin
                    output_active <= 1'b1;
                    width_counter <= current_width - 1'b1;
                end else begin
                    counting <= 1'b1;
                    counter <= current_delay - 1'b1;
                end
            end else if (trigger_in && counting) begin
                trigger_pending <= 1'b1;
            end

            if (counting) begin
                if (counter == '0) begin
                    output_active <= 1'b1;
                    width_counter <= current_width - 1'b1;

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

    assign trigger_out = output_active;

endmodule