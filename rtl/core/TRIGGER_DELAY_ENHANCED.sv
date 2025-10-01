`timescale 1ns / 1ps
`include "../TRIGGER_DELAY_DEFS.vh"

module TRIGGER_DELAY_ENHANCED (
    input  logic        clk,
    input  logic        rst,
    input  logic        trigger_in,
    output logic        trigger_out,
    input  logic [31:0] coarse_delay,    // Delay in clock cycles
    input  logic        coarse_update,
    input  logic [15:0] fine_delay_ps,   // Fine delay in picoseconds (0-9999)
    input  logic        fine_update,
    input  logic [1:0]  edge_type,
    output logic        mmcm_locked
);

    logic trigger_pulse;
    logic trigger_coarse;
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
    
    // Coarse delay (clock cycles)
    CONFIGURABLE_DELAY #(
        .MAX_DELAY_BITS(32)
    ) coarse_delay_inst (
        .clk(clk),
        .rst(rst),
        .trigger_in(trigger_pulse),
        .trigger_out(trigger_coarse),
        .delay_cycles(coarse_delay),
        .delay_update(coarse_update)
    );
    
    // Fine delay (picoseconds)
    MMCM_FINE_DELAY fine_delay_inst (
        .clk(clk),
        .rst(rst),
        .trigger_in(trigger_coarse),
        .trigger_out(trigger_out),
        .fine_delay_ps(fine_delay_ps),
        .fine_update(fine_update),
        .mmcm_locked(mmcm_locked)
    );

endmodule