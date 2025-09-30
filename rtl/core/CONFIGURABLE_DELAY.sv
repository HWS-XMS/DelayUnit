`timescale 1ns / 1ps

module CONFIGURABLE_DELAY #(
    parameter MAX_DELAY_BITS = 32
)(
    input  logic clk,
    input  logic rst,
    input  logic trigger_in,
    output logic trigger_out,
    input  logic [MAX_DELAY_BITS-1:0] delay_cycles,
    input  logic delay_update
);

    logic [MAX_DELAY_BITS-1:0] current_delay;
    logic [MAX_DELAY_BITS-1:0] counter;
    logic counting;
    logic trigger_pending;
    logic trigger_in_d;
    
    always_ff @(posedge clk) begin
        if (rst) begin
            current_delay <= '0;
        end else if (delay_update) begin
            current_delay <= delay_cycles;
        end
    end
    
    always_ff @(posedge clk) begin
        if (rst) begin
            trigger_in_d <= 1'b0;
        end else begin
            trigger_in_d <= trigger_in;
        end
    end
    
    logic trigger_edge;
    assign trigger_edge = trigger_in & ~trigger_in_d;
    
    always_ff @(posedge clk) begin
        if (rst) begin
            counter <= '0;
            counting <= 1'b0;
            trigger_pending <= 1'b0;
            trigger_out <= 1'b0;
        end else begin
            trigger_out <= 1'b0;
            
            if (trigger_edge && !counting) begin
                if (current_delay == '0) begin
                    trigger_out <= 1'b1;
                end else begin
                    counting <= 1'b1;
                    counter <= current_delay - 1'b1;
                end
            end else if (trigger_edge && counting) begin
                trigger_pending <= 1'b1;
            end
            
            if (counting) begin
                if (counter == '0) begin
                    trigger_out <= 1'b1;
                    
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

endmodule