`timescale 1ns / 1ps
`include "trigger_delay_defs.vh"

module TRIGGER_DELAY_MODULE (
    input  logic        clk,
    input  logic        rst,
    input  logic        trigger_in,
    output logic        trigger_out,
    input  logic [31:0] delay_cycles,
    input  logic        delay_update,
    input  logic [1:0]  edge_type
);

    logic trigger_pulse;
    logic trigger_sync;
    
    // CDC and edge detection
    CDC_EDGE_DETECT #(
        .SYNC_STAGES(3)
    ) cdc_inst (
        .clk(clk),
        .rst(rst),
        .async_in(trigger_in),
        .edge_type(edge_type),
        .edge_pulse(trigger_pulse),
        .sync_out(trigger_sync)
    );
    
    // Configurable delay
    CONFIGURABLE_DELAY #(
        .MAX_DELAY_BITS(32)
    ) delay_inst (
        .clk(clk),
        .rst(rst),
        .trigger_in(trigger_pulse),
        .trigger_out(trigger_out),
        .delay_cycles(delay_cycles),
        .delay_update(delay_update)
    );

endmodule