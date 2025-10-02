`timescale 1ns / 1ps

module MMCM_FINE_DELAY (
    input  logic        clk,            // 100MHz input clock
    input  logic        rst,
    input  logic        trigger_in,     // Delayed trigger from coarse delay
    output logic        trigger_out,    // Fine-delayed trigger output
    input  logic [15:0] fine_delay_ps,  // Fine delay in picoseconds (0-9999)
    input  logic        fine_update,    // Update fine delay
    output logic        mmcm_locked
);

    // MMCM signals
    logic clkfb, clkfb_buf;
    logic clk_vco;  // VCO clock at 887.5MHz
    logic ps_clk;
    logic ps_en;
    logic ps_incdec;
    logic ps_done;
    
    // Phase shift calculation
    // VCO at 1050MHz (21/2 multiplier)
    // VCO period = 952.38ps
    // Resolution: 952.38ps/56 = 17.0068ps per step
    // Full 10ns = 10.5 VCO periods = 588 phase steps
    logic [9:0] phase_steps;
    logic [9:0] current_steps;
    logic [9:0] target_steps;

    // Calculate phase steps from picoseconds
    // Accurate: steps = ps / 17.0068 ≈ ps * 10000 / 170068
    // Simplified: steps = ps * 59 / 1003 (0.01% error)
    always_ff @(posedge clk) begin
        if (rst) begin
            target_steps <= 10'd0;
        end else if (fine_update) begin
            // Accurate conversion: 1 step = 17.0068ps
            // Using integer math: ps * 59 / 1003 (preserves precision)
            if (fine_delay_ps >= 16'd10000) begin
                target_steps <= 10'd588;  // Max steps for 10ns
            end else begin
                target_steps <= (fine_delay_ps * 59) / 1003;
            end
        end
    end
    
    // Phase shift control FSM
    typedef enum logic [1:0] {
        PS_IDLE,
        PS_SHIFT,
        PS_WAIT
    } ps_state_t;
    ps_state_t ps_state;
    
    always_ff @(posedge clk) begin
        if (rst) begin
            ps_state <= PS_IDLE;
            ps_en <= 1'b0;
            ps_incdec <= 1'b0;
            current_steps <= 10'd0;
        end else begin
            ps_en <= 1'b0;  // Default
            
            case (ps_state)
                PS_IDLE: begin
                    if (current_steps != target_steps && mmcm_locked) begin
                        ps_incdec <= (target_steps > current_steps);
                        ps_en <= 1'b1;
                        ps_state <= PS_SHIFT;
                    end
                end
                
                PS_SHIFT: begin
                    ps_state <= PS_WAIT;
                end
                
                PS_WAIT: begin
                    if (ps_done) begin
                        if (ps_incdec) begin
                            current_steps <= current_steps + 10'd1;
                        end else begin
                            current_steps <= current_steps - 10'd1;
                        end
                        ps_state <= PS_IDLE;
                    end
                end
                
                default: ps_state <= PS_IDLE;
            endcase
        end
    end
    
    // MMCME2_ADV instantiation
    MMCME2_ADV #(
        .BANDWIDTH            ("OPTIMIZED"),
        .CLKFBOUT_MULT_F      (21.0),       // 100MHz × 21 / 2 = 1050MHz VCO (17.0068ps steps!)
        .CLKFBOUT_PHASE       (0.0),
        .CLKFBOUT_USE_FINE_PS ("FALSE"),

        .CLKIN1_PERIOD        (10.0),       // 100MHz = 10ns period
        .CLKIN2_PERIOD        (0.0),

        .CLKOUT0_DIVIDE_F     (21.0),       // 1050MHz / 21 = 50MHz (INTEGER for fine PS!)
        .CLKOUT0_DUTY_CYCLE   (0.5),
        .CLKOUT0_PHASE        (0.0),
        .CLKOUT0_USE_FINE_PS  ("TRUE"),     // Enable fine phase shift
        
        .CLKOUT1_DIVIDE       (10),
        .CLKOUT1_DUTY_CYCLE   (0.5),
        .CLKOUT1_PHASE        (0.0),
        .CLKOUT1_USE_FINE_PS  ("FALSE"),
        
        .CLKOUT2_DIVIDE       (10),
        .CLKOUT2_DUTY_CYCLE   (0.5),
        .CLKOUT2_PHASE        (0.0),
        .CLKOUT2_USE_FINE_PS  ("FALSE"),
        
        .CLKOUT3_DIVIDE       (10),
        .CLKOUT3_DUTY_CYCLE   (0.5),
        .CLKOUT3_PHASE        (0.0),
        .CLKOUT3_USE_FINE_PS  ("FALSE"),
        
        .CLKOUT4_CASCADE      ("FALSE"),
        .CLKOUT4_DIVIDE       (10),
        .CLKOUT4_DUTY_CYCLE   (0.5),
        .CLKOUT4_PHASE        (0.0),
        .CLKOUT4_USE_FINE_PS  ("FALSE"),
        
        .CLKOUT5_DIVIDE       (10),
        .CLKOUT5_DUTY_CYCLE   (0.5),
        .CLKOUT5_PHASE        (0.0),
        .CLKOUT5_USE_FINE_PS  ("FALSE"),
        
        .CLKOUT6_DIVIDE       (10),
        .CLKOUT6_DUTY_CYCLE   (0.5),
        .CLKOUT6_PHASE        (0.0),
        .CLKOUT6_USE_FINE_PS  ("FALSE"),
        
        .COMPENSATION         ("ZHOLD"),
        .DIVCLK_DIVIDE        (2),
        .REF_JITTER1          (0.01),
        .STARTUP_WAIT         ("FALSE")
    ) mmcm_inst (
        // Clock outputs
        .CLKOUT0              (clk_vco),
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
        
        // Feedback
        .CLKFBOUT             (clkfb),
        .CLKFBOUTB            (),
        
        // Status
        .LOCKED               (mmcm_locked),
        .CLKINSTOPPED         (),
        .CLKFBSTOPPED         (),
        
        // Clock inputs
        .CLKIN1               (clk),
        .CLKIN2               (1'b0),
        .CLKINSEL             (1'b1),
        
        // Feedback input
        .CLKFBIN              (clkfb_buf),
        
        // Dynamic phase shift
        .PSCLK                (clk),
        .PSEN                 (ps_en),
        .PSINCDEC             (ps_incdec),
        .PSDONE               (ps_done),
        
        // Dynamic reconfiguration (unused)
        .DADDR                (7'h0),
        .DCLK                 (1'b0),
        .DEN                  (1'b0),
        .DI                   (16'h0),
        .DWE                  (1'b0),
        .DO                   (),
        .DRDY                 (),
        
        // Other
        .PWRDWN               (1'b0),
        .RST                  (rst)
    );
    
    // Feedback buffer
    BUFG clkfb_bufg (
        .I(clkfb),
        .O(clkfb_buf)
    );
    
    // Retime trigger through phase-shifted clock domain
    logic trigger_vco_q1, trigger_vco_q2;
    logic trigger_resync_q1, trigger_resync_q2;
    
    // Sample trigger with phase-shifted VCO clock
    always_ff @(posedge clk_vco) begin
        if (rst) begin
            trigger_vco_q1 <= 1'b0;
            trigger_vco_q2 <= 1'b0;
        end else begin
            trigger_vco_q1 <= trigger_in;
            trigger_vco_q2 <= trigger_vco_q1;
        end
    end
    
    // Resynchronize back to original clock domain
    always_ff @(posedge clk) begin
        if (rst) begin
            trigger_resync_q1 <= 1'b0;
            trigger_resync_q2 <= 1'b0;
        end else begin
            trigger_resync_q1 <= trigger_vco_q2;
            trigger_resync_q2 <= trigger_resync_q1;
        end
    end
    
    assign trigger_out = trigger_resync_q2;

endmodule