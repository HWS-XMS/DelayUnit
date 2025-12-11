`timescale 1ns / 1ps

//-----------------------------------------------------------------------------
// MMCM_PHASESHIFT Testbench
//-----------------------------------------------------------------------------
// Tests the phase shift stepping controller logic.
// Focus: aliasing boundary (±280 steps), direction verification, reset behavior
//-----------------------------------------------------------------------------

module MMCM_PHASESHIFT_tb;

    //-------------------------------------------------------------------------
    // Parameters
    //-------------------------------------------------------------------------
    parameter CLK_PERIOD = 5.0;  // 200MHz clock
    parameter PHASE_WIDTH = 32;
    parameter MAX_PHASE = 280;   // 50% of cycle (aliasing boundary)

    //-------------------------------------------------------------------------
    // DUT Signals
    //-------------------------------------------------------------------------
    logic                       clk;
    logic                       rst;
    logic [PHASE_WIDTH-1:0]     target;
    logic                       configure;
    logic                       configured;
    logic                       ps_done;
    logic                       ps_en;
    logic                       ps_inc_dec;

    //-------------------------------------------------------------------------
    // Test Variables
    //-------------------------------------------------------------------------
    int error_cnt;
    logic signed [PHASE_WIDTH-1:0] simulated_phase;
    int psdone_delay_cycles = 12;

    //-------------------------------------------------------------------------
    // Clock Generation
    //-------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //-------------------------------------------------------------------------
    // DUT Instantiation
    //-------------------------------------------------------------------------
    MMCM_PHASESHIFT #(
        .PHASE_WIDTH(PHASE_WIDTH)
    ) dut (
        .clk        (clk),
        .rst        (rst),
        .target     (target),
        .configure  (configure),
        .configured (configured),
        .ps_done    (ps_done),
        .ps_en      (ps_en),
        .ps_inc_dec (ps_inc_dec)
    );

    //-------------------------------------------------------------------------
    // MMCM Phase Shift Simulation
    // Models MMCM behavior: reset clears phase, ps_done after delay
    //-------------------------------------------------------------------------
    int psdone_countdown;
    logic ps_en_active;

    always_ff @(posedge clk) begin
        if (rst) begin
            ps_done <= 0;
            simulated_phase <= 0;
            psdone_countdown <= 0;
            ps_en_active <= 0;
        end else begin
            ps_done <= 0;

            if (ps_en && !ps_en_active) begin
                // Start countdown on ps_en rising
                psdone_countdown <= psdone_delay_cycles;
                ps_en_active <= 1;
            end else if (ps_en_active) begin
                if (psdone_countdown > 0) begin
                    psdone_countdown <= psdone_countdown - 1;
                end else begin
                    // Countdown done - assert ps_done and update phase
                    ps_done <= 1;
                    if (ps_inc_dec)
                        simulated_phase <= simulated_phase + 1;
                    else
                        simulated_phase <= simulated_phase - 1;
                    ps_en_active <= 0;
                end
            end
        end
    end

    //-------------------------------------------------------------------------
    // Test Tasks
    //-------------------------------------------------------------------------
    task reset_dut();
        rst = 1;
        target = 0;
        configure = 0;
        simulated_phase = 0;
        repeat(5) @(posedge clk);
        rst = 0;
        repeat(5) @(posedge clk);
    endtask

    task set_phase(input logic signed [PHASE_WIDTH-1:0] new_target);
        @(posedge clk);
        target = new_target;
        configure = 1;
        @(posedge clk);
        configure = 0;
        wait(configured);
        if (simulated_phase !== new_target) begin
            $error("Phase mismatch! Expected: %0d, Got: %0d", new_target, simulated_phase);
            error_cnt++;
        end
        @(posedge clk);
    endtask

    task test_direction_verification();
        logic expected_dir;
        logic signed [PHASE_WIDTH-1:0] start_phase;

        $display("[TEST] Direction Verification");

        // Test increment direction
        start_phase = simulated_phase;
        @(posedge clk);
        target = start_phase + 5;
        configure = 1;
        @(posedge clk);
        configure = 0;

        // Wait for first ps_en and check direction
        wait(ps_en);
        if (ps_inc_dec !== 1'b1) begin
            $error("Direction wrong for increment! Expected: 1, Got: %0b", ps_inc_dec);
            error_cnt++;
        end
        wait(configured);
        @(posedge clk);

        // Test decrement direction
        start_phase = simulated_phase;
        @(posedge clk);
        target = start_phase - 3;
        configure = 1;
        @(posedge clk);
        configure = 0;

        wait(ps_en);
        if (ps_inc_dec !== 1'b0) begin
            $error("Direction wrong for decrement! Expected: 0, Got: %0b", ps_inc_dec);
            error_cnt++;
        end
        wait(configured);
        @(posedge clk);
    endtask

    task test_reset_during_stepping();
        $display("[TEST] Reset During Stepping");

        // Start a long stepping operation
        @(posedge clk);
        target = 50;
        configure = 1;
        @(posedge clk);
        configure = 0;

        // Wait for stepping to start
        wait(ps_en);
        repeat(3) @(posedge clk);

        // Assert reset mid-operation
        rst = 1;
        repeat(5) @(posedge clk);
        rst = 0;
        repeat(5) @(posedge clk);

        // Verify DUT is back in IDLE (can accept new configure)
        simulated_phase = 0;  // Reset simulation model too
        set_phase(10);  // Should work cleanly

        if (simulated_phase !== 10) begin
            $error("DUT not functional after reset during stepping");
            error_cnt++;
        end
    endtask

    //-------------------------------------------------------------------------
    // Main Test Sequence
    //-------------------------------------------------------------------------
    initial begin
        $display("========================================");
        $display("MMCM_PHASESHIFT Testbench");
        $display("========================================");

        error_cnt = 0;
        reset_dut();

        // Test 1: Forward stepping
        $display("[TEST] Forward Stepping (0 -> 100)");
        set_phase(100);

        // Test 2: Backward stepping
        $display("[TEST] Backward Stepping (100 -> 50)");
        set_phase(50);

        // Test 3: Boundary test (max positive)
        $display("[TEST] Boundary (50 -> 280)");
        set_phase(MAX_PHASE);

        // Test 4: Negative phase
        $display("[TEST] Negative Phase (280 -> -100)");
        set_phase(-100);

        // Test 5: Max negative boundary
        $display("[TEST] Max Negative (-100 -> -280)");
        set_phase(-MAX_PHASE);

        // Test 6: Cross zero
        $display("[TEST] Cross Zero (-280 -> 50)");
        set_phase(50);

        // Test 7: Same target (no-op)
        $display("[TEST] Same Target (no-op)");
        set_phase(50);

        // Test 8: Direction verification
        test_direction_verification();

        // Test 9: Reset during stepping
        test_reset_during_stepping();

        // Summary
        $display("\n========================================");
        $display("Errors: %0d", error_cnt);
        $display("Result: %s", error_cnt == 0 ? "PASSED" : "FAILED");
        $display("========================================");

        $finish;
    end

    //-------------------------------------------------------------------------
    // Timeout Watchdog
    //-------------------------------------------------------------------------
    initial begin
        #10ms;
        $error("Testbench timeout!");
        $finish;
    end

endmodule
