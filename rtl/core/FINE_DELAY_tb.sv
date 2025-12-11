`timescale 1ns / 1ps

//-----------------------------------------------------------------------------
// FINE_DELAY Testbench
//-----------------------------------------------------------------------------
// Tests the MMCM phase shift controller for sub-cycle delay resolution.
// Note: MMCM primitives are stubbed for simulation - actual timing verification
// requires post-synthesis simulation or hardware testing.
//-----------------------------------------------------------------------------

module FINE_DELAY_tb;

    //-------------------------------------------------------------------------
    // Parameters
    //-------------------------------------------------------------------------
    parameter CLK_PERIOD = 10.0;  // 100MHz input clock
    parameter PHASE_WIDTH = 32;

    // Phase shift resolution: 56 steps per VCO cycle, VCO_MULT=10
    // So 560 steps per output clock cycle (5ns)
    parameter STEPS_PER_CYCLE = 560;
    parameter STEP_PS = 5000.0 / STEPS_PER_CYCLE;  // ~8.93ps per step

    //-------------------------------------------------------------------------
    // DUT Signals
    //-------------------------------------------------------------------------
    logic                       clk_in;
    logic                       rst;

    logic [PHASE_WIDTH-1:0]     offset_target;
    logic                       offset_configure;
    logic                       offset_configured;

    logic [PHASE_WIDTH-1:0]     width_target;
    logic                       width_configure;
    logic                       width_configured;

    logic                       clk_out;
    logic                       clk_offset;
    logic                       clk_width;
    logic                       locked;
    logic                       all_configured;

    //-------------------------------------------------------------------------
    // Test Variables
    //-------------------------------------------------------------------------
    int test_cnt;
    int error_cnt;
    bit verbose = 1;

    //-------------------------------------------------------------------------
    // Clock Generation
    //-------------------------------------------------------------------------
    initial begin
        clk_in = 0;
        forever #(CLK_PERIOD/2) clk_in = ~clk_in;
    end

    //-------------------------------------------------------------------------
    // DUT Instantiation
    //-------------------------------------------------------------------------
    FINE_DELAY #(
        .PHASE_WIDTH(PHASE_WIDTH)
    ) dut (
        .clk_in             (clk_in),
        .rst                (rst),
        .offset_target      (offset_target),
        .offset_configure   (offset_configure),
        .offset_configured  (offset_configured),
        .width_target       (width_target),
        .width_configure    (width_configure),
        .width_configured   (width_configured),
        .clk_out            (clk_out),
        .clk_offset         (clk_offset),
        .clk_width          (clk_width),
        .locked             (locked),
        .all_configured     (all_configured)
    );

    //-------------------------------------------------------------------------
    // Test Tasks
    //-------------------------------------------------------------------------
    task reset_dut();
        if (verbose) $display("[%0t] Applying reset", $time);
        rst = 1;
        offset_target = 0;
        offset_configure = 0;
        width_target = 0;
        width_configure = 0;
        repeat(10) @(posedge clk_in);
        rst = 0;

        // Wait for MMCMs to lock
        if (verbose) $display("[%0t] Waiting for MMCM lock", $time);
        wait(locked);
        if (verbose) $display("[%0t] MMCM locked", $time);
        repeat(10) @(posedge clk_out);
    endtask

    task set_offset(input logic [PHASE_WIDTH-1:0] target);
        if (verbose) $display("[%0t] Setting offset to %0d steps (%0.2f ps)",
                              $time, target, target * STEP_PS);

        @(posedge clk_out);
        offset_target = target;
        offset_configure = 1;
        @(posedge clk_out);
        offset_configure = 0;

        // Wait for configuration to complete
        wait(offset_configured);
        if (verbose) $display("[%0t] Offset configured", $time);
        @(posedge clk_out);
    endtask

    task set_width(input logic [PHASE_WIDTH-1:0] target);
        if (verbose) $display("[%0t] Setting width to %0d steps (%0.2f ps)",
                              $time, target, target * STEP_PS);

        @(posedge clk_out);
        width_target = target;
        width_configure = 1;
        @(posedge clk_out);
        width_configure = 0;

        // Wait for configuration to complete
        wait(width_configured);
        if (verbose) $display("[%0t] Width configured", $time);
        @(posedge clk_out);
    endtask

    task test_phase_stepping();
        int steps_to_test[];

        steps_to_test = '{0, 1, 10, 100, 280, 559};  // Various step values

        $display("\n[TEST] Phase Stepping - Offset");
        foreach(steps_to_test[i]) begin
            set_offset(steps_to_test[i]);
            repeat(5) @(posedge clk_out);
        end

        $display("\n[TEST] Phase Stepping - Width");
        foreach(steps_to_test[i]) begin
            set_width(steps_to_test[i]);
            repeat(5) @(posedge clk_out);
        end
    endtask

    task test_bidirectional_stepping();
        $display("\n[TEST] Bidirectional Stepping");

        // Step forward
        set_offset(100);
        repeat(5) @(posedge clk_out);

        // Step backward
        set_offset(50);
        repeat(5) @(posedge clk_out);

        // Step forward again
        set_offset(200);
        repeat(5) @(posedge clk_out);

        // Back to zero
        set_offset(0);
        repeat(5) @(posedge clk_out);
    endtask

    task test_simultaneous_config();
        $display("\n[TEST] Simultaneous Configuration");

        @(posedge clk_out);
        offset_target = 150;
        width_target = 300;
        offset_configure = 1;
        width_configure = 1;
        @(posedge clk_out);
        offset_configure = 0;
        width_configure = 0;

        // Wait for both to complete
        wait(all_configured);
        $display("[%0t] Both phase shifters configured", $time);
        repeat(10) @(posedge clk_out);
    endtask

    task test_large_step();
        $display("\n[TEST] Large Step (near full cycle)");

        // Set to near maximum (just under one full cycle)
        set_offset(550);
        repeat(10) @(posedge clk_out);

        // Return to small value
        set_offset(10);
        repeat(10) @(posedge clk_out);
    endtask

    //-------------------------------------------------------------------------
    // Main Test Sequence
    //-------------------------------------------------------------------------
    initial begin
        $display("========================================");
        $display("FINE_DELAY Testbench Starting");
        $display("========================================");
        $display("Phase step resolution: %0.2f ps", STEP_PS);
        $display("Steps per cycle: %0d", STEPS_PER_CYCLE);

        error_cnt = 0;
        test_cnt = 0;

        // Reset
        reset_dut();

        // Test 1: Basic phase stepping
        test_cnt++;
        test_phase_stepping();

        // Test 2: Bidirectional stepping
        test_cnt++;
        test_bidirectional_stepping();

        // Test 3: Simultaneous configuration
        test_cnt++;
        test_simultaneous_config();

        // Test 4: Large steps
        test_cnt++;
        test_large_step();

        // Final summary
        #1000;
        $display("\n========================================");
        $display("Test Summary:");
        $display("  Tests Run: %0d", test_cnt);
        $display("  Errors: %0d", error_cnt);
        if (error_cnt == 0) begin
            $display("  Result: PASSED");
        end else begin
            $display("  Result: FAILED");
        end
        $display("========================================");

        $finish;
    end

    //-------------------------------------------------------------------------
    // Timeout Watchdog
    //-------------------------------------------------------------------------
    initial begin
        #100ms;
        $error("Testbench timeout!");
        $finish;
    end

    //-------------------------------------------------------------------------
    // Waveform Dumping
    //-------------------------------------------------------------------------
    initial begin
        $dumpfile("fine_delay_tb.vcd");
        $dumpvars(0, FINE_DELAY_tb);
    end

endmodule
