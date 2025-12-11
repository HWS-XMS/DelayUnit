`timescale 1ns / 1ps
`default_nettype none

// MMCM_PHASESHIFT - Steps MMCM phase from current position to target
// Each step is ~1/56th of VCO period (~9ps at 1000MHz VCO)
// Based on existing module, renamed 'delta' to 'target' for clarity

module MMCM_PHASESHIFT #(
    parameter PHASE_WIDTH = 32
)(
    input  wire                         clk,
    input  wire                         rst,
    input  wire  [PHASE_WIDTH-1:0]      target,     // Absolute target phase position
    input  wire                         configure,  // Pulse to start phase adjustment
    output logic                        configured, // Pulse when target reached

    input  wire                         ps_done,    // From MMCM PSDONE
    output logic                        ps_en,      // To MMCM PSEN
    output logic                        ps_inc_dec  // To MMCM PSINCDEC (1=inc, 0=dec)
);

    typedef enum {
        STATE_IDLE,
        STATE_UPDATE_PHASE,
        STATE_WAIT
    } state_t;
    state_t current_state;

    logic signed [PHASE_WIDTH-1:0] counter;

    always_ff @(posedge clk) begin
        if (rst) begin
            current_state <= STATE_IDLE;
            configured    <= 1'b0;
            ps_en         <= 1'b0;
            ps_inc_dec    <= 1'b0;
            counter       <= '0;

        end else begin
            current_state <= current_state;
            ps_en         <= 1'b0;
            ps_inc_dec    <= ps_inc_dec;
            counter       <= counter;

            case (current_state)
                STATE_IDLE: begin
                    configured <= 1'b1;  // Idle = configured
                    if (configure) begin
                        configured    <= 1'b0;
                        current_state <= STATE_UPDATE_PHASE;
                    end
                end

                STATE_UPDATE_PHASE: begin
                    configured <= 1'b0;  // Busy
                    if ($signed(target) != counter) begin
                        ps_inc_dec    <= ($signed(target) > counter);
                        ps_en         <= 1'b1;
                        counter       <= counter + (($signed(target) > counter) ? $signed(1) : $signed(-1));
                        current_state <= STATE_WAIT;
                    end else begin
                        configured    <= 1'b1;
                        current_state <= STATE_IDLE;
                    end
                end

                STATE_WAIT: begin
                    configured <= 1'b0;  // Busy
                    if (ps_done) begin
                        current_state <= STATE_UPDATE_PHASE;
                    end
                end

            endcase
        end
    end

endmodule

`default_nettype wire
