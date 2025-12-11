`timescale 1ns / 1ps
`default_nettype none

// FINE_DELAY - Sub-cycle delay using MMCM phase shifting
// Provides two phase-shifted clock outputs for precise pulse edge control:
//   - clk_offset: controls pulse rising edge (delay offset)
//   - clk_width:  controls pulse falling edge (pulse width)
//
// Resolution: ~9ps per step (VCO=1000MHz, 56*10=560 steps per 5ns cycle)
// Range: 0 to 559 steps (~5ns) per phase shifter

module FINE_DELAY #(
    parameter PHASE_WIDTH = 32
)(
    input  wire                         clk_in,         // 100MHz reference
    input  wire                         rst,

    // Phase control - offset (pulse start)
    input  wire  [PHASE_WIDTH-1:0]      offset_target,  // Target phase for offset
    input  wire                         offset_configure,
    output logic                        offset_configured,

    // Phase control - width (pulse end)
    input  wire  [PHASE_WIDTH-1:0]      width_target,   // Target phase for width
    input  wire                         width_configure,
    output logic                        width_configured,

    // Clock outputs
    output wire                         clk_out,        // Main 200MHz clock (unshifted)
    output wire                         clk_offset,     // Phase-shifted clock for pulse start
    output wire                         clk_width,      // Phase-shifted clock for pulse end

    // Status
    output wire                         locked,
    output wire                         phase_shift_ready
);

    // =========================================================================
    // Main MMCM - Generates 200MHz and provides base for phase shifting
    // VCO = 100MHz * 10 = 1000MHz
    // CLKOUT0 = 1000MHz / 5 = 200MHz (main clock, unshifted)
    // =========================================================================

    logic clkfb_main, clkfb_main_buf;
    logic clk_200m_unbuf;
    logic mmcm_main_locked;

    MMCME2_ADV #(
        .BANDWIDTH            ("OPTIMIZED"),
        .CLKFBOUT_MULT_F      (10.0),           // VCO = 1000MHz
        .CLKFBOUT_PHASE       (0.0),
        .CLKFBOUT_USE_FINE_PS ("FALSE"),
        .CLKIN1_PERIOD        (10.0),           // 100MHz input
        .CLKOUT0_DIVIDE_F     (5.0),            // 200MHz output
        .CLKOUT0_DUTY_CYCLE   (0.5),
        .CLKOUT0_PHASE        (0.0),
        .CLKOUT0_USE_FINE_PS  ("FALSE"),
        .COMPENSATION         ("ZHOLD"),
        .DIVCLK_DIVIDE        (1),
        .REF_JITTER1          (0.01),
        .STARTUP_WAIT         ("FALSE")
    ) mmcm_main (
        .CLKOUT0              (clk_200m_unbuf),
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
        .CLKFBOUT             (clkfb_main),
        .CLKFBOUTB            (),
        .LOCKED               (mmcm_main_locked),
        .CLKINSTOPPED         (),
        .CLKFBSTOPPED         (),
        .CLKIN1               (clk_in),
        .CLKIN2               (1'b0),
        .CLKINSEL             (1'b1),
        .CLKFBIN              (clkfb_main_buf),
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

    BUFG bufg_clkfb_main (.I(clkfb_main), .O(clkfb_main_buf));
    BUFG bufg_clk_main   (.I(clk_200m_unbuf), .O(clk_out));

    // =========================================================================
    // Offset MMCM - Phase-shifted clock for pulse rising edge
    // =========================================================================

    logic clkfb_offset, clkfb_offset_buf;
    logic clk_offset_unbuf;
    logic mmcm_offset_locked;
    logic mmcm_offset_psen;
    logic mmcm_offset_psincdec;
    logic mmcm_offset_psdone;

    MMCME2_ADV #(
        .BANDWIDTH            ("OPTIMIZED"),
        .CLKFBOUT_MULT_F      (10.0),
        .CLKFBOUT_PHASE       (0.0),
        .CLKFBOUT_USE_FINE_PS ("FALSE"),
        .CLKIN1_PERIOD        (10.0),
        .CLKOUT0_DIVIDE_F     (5.0),
        .CLKOUT0_DUTY_CYCLE   (0.5),
        .CLKOUT0_PHASE        (0.0),
        .CLKOUT0_USE_FINE_PS  ("TRUE"),         // Enable fine phase shift
        .COMPENSATION         ("ZHOLD"),
        .DIVCLK_DIVIDE        (1),
        .REF_JITTER1          (0.01),
        .STARTUP_WAIT         ("FALSE")
    ) mmcm_offset (
        .CLKOUT0              (clk_offset_unbuf),
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
        .CLKFBOUT             (clkfb_offset),
        .CLKFBOUTB            (),
        .LOCKED               (mmcm_offset_locked),
        .CLKINSTOPPED         (),
        .CLKFBSTOPPED         (),
        .CLKIN1               (clk_in),
        .CLKIN2               (1'b0),
        .CLKINSEL             (1'b1),
        .CLKFBIN              (clkfb_offset_buf),
        .PSCLK                (clk_out),        // Phase shift clock = main clock
        .PSEN                 (mmcm_offset_psen),
        .PSINCDEC             (mmcm_offset_psincdec),
        .PSDONE               (mmcm_offset_psdone),
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

    BUFG bufg_clkfb_offset (.I(clkfb_offset), .O(clkfb_offset_buf));
    BUFG bufg_clk_offset   (.I(clk_offset_unbuf), .O(clk_offset));

    // =========================================================================
    // Width MMCM - Phase-shifted clock for pulse falling edge
    // =========================================================================

    logic clkfb_width, clkfb_width_buf;
    logic clk_width_unbuf;
    logic mmcm_width_locked;
    logic mmcm_width_psen;
    logic mmcm_width_psincdec;
    logic mmcm_width_psdone;

    MMCME2_ADV #(
        .BANDWIDTH            ("OPTIMIZED"),
        .CLKFBOUT_MULT_F      (10.0),
        .CLKFBOUT_PHASE       (0.0),
        .CLKFBOUT_USE_FINE_PS ("FALSE"),
        .CLKIN1_PERIOD        (10.0),
        .CLKOUT0_DIVIDE_F     (5.0),
        .CLKOUT0_DUTY_CYCLE   (0.5),
        .CLKOUT0_PHASE        (0.0),
        .CLKOUT0_USE_FINE_PS  ("TRUE"),         // Enable fine phase shift
        .COMPENSATION         ("ZHOLD"),
        .DIVCLK_DIVIDE        (1),
        .REF_JITTER1          (0.01),
        .STARTUP_WAIT         ("FALSE")
    ) mmcm_width (
        .CLKOUT0              (clk_width_unbuf),
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
        .CLKFBOUT             (clkfb_width),
        .CLKFBOUTB            (),
        .LOCKED               (mmcm_width_locked),
        .CLKINSTOPPED         (),
        .CLKFBSTOPPED         (),
        .CLKIN1               (clk_in),
        .CLKIN2               (1'b0),
        .CLKINSEL             (1'b1),
        .CLKFBIN              (clkfb_width_buf),
        .PSCLK                (clk_out),        // Phase shift clock = main clock
        .PSEN                 (mmcm_width_psen),
        .PSINCDEC             (mmcm_width_psincdec),
        .PSDONE               (mmcm_width_psdone),
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

    BUFG bufg_clkfb_width (.I(clkfb_width), .O(clkfb_width_buf));
    BUFG bufg_clk_width   (.I(clk_width_unbuf), .O(clk_width));

    // =========================================================================
    // Phase Shift Controllers (reusing MMCM_PHASESHIFT module pattern)
    // =========================================================================

    MMCM_PHASESHIFT #(
        .PHASE_WIDTH(PHASE_WIDTH)
    ) phaseshift_offset (
        .clk        (clk_out),
        .rst        (rst || !mmcm_offset_locked),
        .target     (offset_target),
        .configure  (offset_configure),
        .configured (offset_configured),
        .ps_done    (mmcm_offset_psdone),
        .ps_en      (mmcm_offset_psen),
        .ps_inc_dec (mmcm_offset_psincdec)
    );

    MMCM_PHASESHIFT #(
        .PHASE_WIDTH(PHASE_WIDTH)
    ) phaseshift_width (
        .clk        (clk_out),
        .rst        (rst || !mmcm_width_locked),
        .target     (width_target),
        .configure  (width_configure),
        .configured (width_configured),
        .ps_done    (mmcm_width_psdone),
        .ps_en      (mmcm_width_psen),
        .ps_inc_dec (mmcm_width_psincdec)
    );

    // =========================================================================
    // Status outputs
    // =========================================================================

    assign locked = mmcm_main_locked && mmcm_offset_locked && mmcm_width_locked;
    assign phase_shift_ready = offset_configured && width_configured;

endmodule

`default_nettype wire
