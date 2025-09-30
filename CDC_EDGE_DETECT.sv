`timescale 1ns / 1ps
`include "trigger_delay_defs.vh"

module CDC_EDGE_DETECT #(
    parameter SYNC_STAGES = 3
)(
    input  logic clk,
    input  logic rst,
    input  logic async_in,
    input  logic [1:0] edge_type,
    output logic edge_pulse,
    output logic sync_out
);

    logic [SYNC_STAGES-1:0] sync_ff;
    logic sync_delayed;
    
    always_ff @(posedge clk) begin
        if (rst) begin
            sync_ff <= '0;
        end else begin
            sync_ff <= {sync_ff[SYNC_STAGES-2:0], async_in};
        end
    end
    
    assign sync_out = sync_ff[SYNC_STAGES-1];
    
    always_ff @(posedge clk) begin
        if (rst) begin
            sync_delayed <= 1'b0;
        end else begin
            sync_delayed <= sync_out;
        end
    end
    
    logic rising_edge;
    logic falling_edge;
    
    assign rising_edge = sync_out & ~sync_delayed;
    assign falling_edge = ~sync_out & sync_delayed;
    
    always_comb begin
        case (edge_type)
            `EDGE_NONE:    edge_pulse = 1'b0;
            `EDGE_RISING:  edge_pulse = rising_edge;
            `EDGE_FALLING: edge_pulse = falling_edge;
            `EDGE_BOTH:    edge_pulse = rising_edge | falling_edge;
            default:       edge_pulse = 1'b0;
        endcase
    end

endmodule