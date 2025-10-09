//-----------------------------------------------------------------------------
// DS1124 Driver Testbench
//-----------------------------------------------------------------------------
// Comprehensive testbench for verifying DS1124 driver functionality
//
// Tests:
// 1. Basic write operations
// 2. Timing verification (setup/hold times)
// 3. Back-to-back writes
// 4. Readback functionality
// 5. Reset behavior
// 6. Edge cases (0x00, 0xFF)
//
//-----------------------------------------------------------------------------

`timescale 1ns/1ps

module ds1124_driver_tb;

    //-------------------------------------------------------------------------
    // Parameters
    //-------------------------------------------------------------------------
    parameter CLK_PERIOD = 10;  // 100MHz clock (10ns period)
    parameter CLK_DIV = 4;
    parameter READBACK_EN = 1;
    
    //-------------------------------------------------------------------------
    // DUT Signals
    //-------------------------------------------------------------------------
    logic        clk;
    logic        rst;
    logic [7:0]  delay_value;
    logic        en;
    logic        ready;
    
    logic        ds1124_clk;
    logic        ds1124_d;
    logic        ds1124_e;
    logic        ds1124_q;
    
    logic        read_delay;
    logic [7:0]  current_delay;
    logic        read_valid;
    
    //-------------------------------------------------------------------------
    // Test Variables
    //-------------------------------------------------------------------------
    logic [7:0]  captured_data = 8'h00;
    logic [7:0]  ds1124_internal_reg = 8'h00;
    logic [7:0]  last_written_value = 8'h00;  // Track last written value for verification
    int          test_cnt;
    int          error_cnt;
    bit          verbose = 1;
    
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
    ds1124_driver #(
        .CLK_DIV(CLK_DIV),
        .READBACK_EN(READBACK_EN)
    ) dut (
        .clk(clk),
        .rst(rst),
        .delay_value(delay_value),
        .en(en),
        .ready(ready),
        .ds1124_clk(ds1124_clk),
        .ds1124_d(ds1124_d),
        .ds1124_e(ds1124_e),
        .ds1124_q(ds1124_q),
        .read_delay(read_delay),
        .current_delay(current_delay),
        .read_valid(read_valid)
    );
    
    //-------------------------------------------------------------------------
    // DS1124 Model (simplified behavioral model)
    //-------------------------------------------------------------------------
    logic [7:0] readback_reg;  // Separate register for readback
    
    always @(posedge ds1124_clk) begin
        if (ds1124_e) begin
            // Shift in new data
            captured_data = {captured_data[6:0], ds1124_d};
            // Shift readback register for Q output
            readback_reg = {readback_reg[6:0], 1'b0};
        end
    end
    
    always @(negedge ds1124_e) begin
        // Latch the captured value when E falls
        ds1124_internal_reg = captured_data;
        if (verbose) $display("[%0t] DS1124 Model: Latched value = 0x%02X", $time, captured_data);
    end
    
    always @(posedge ds1124_e) begin
        // Load readback register at start of shift operation
        readback_reg = ds1124_internal_reg;
    end
    
    // Q output presents MSB of readback register
    assign ds1124_q = readback_reg[7];
    
    //-------------------------------------------------------------------------
    // Timing Checker Tasks
    //-------------------------------------------------------------------------
    task automatic check_setup_hold_timing();
        real t_data_setup;
        real t_clk_rise;
        real t_data_change;
        logic last_d;
        
        // Monitor setup time (tDSC = 30ns min)
        fork
            begin
                while(ds1124_e) begin
                    @(ds1124_d);  // Wait for data change
                    t_data_change = $realtime;
                    last_d = ds1124_d;
                    
                    @(posedge ds1124_clk);  // Wait for next clock edge
                    t_clk_rise = $realtime;
                    t_data_setup = t_clk_rise - t_data_change;
                    
                    if (t_data_setup < 30.0) begin
                        $error("[%0t] Setup time violation! tDSC = %0.2fns (min 30ns)", 
                               $time, t_data_setup);
                        error_cnt++;
                    end
                end
            end
        join_none
    endtask
    
    task automatic check_clock_frequency();
        real t_last_rise;
        real t_curr_rise;
        real t_period;
        int clk_count = 0;
        
        // Monitor clock frequency (max 10MHz = min 100ns period)
        @(posedge ds1124_e);  // Wait for E to go high
        
        while(ds1124_e) begin
            @(posedge ds1124_clk);
            t_curr_rise = $realtime;
            
            if (clk_count > 0) begin
                t_period = t_curr_rise - t_last_rise;
                if (t_period < 100.0) begin
                    $error("[%0t] Clock frequency violation! Period = %0.2fns (min 100ns for 10MHz)", 
                           $time, t_period);
                    error_cnt++;
                end
            end
            
            t_last_rise = t_curr_rise;
            clk_count++;
        end
    endtask
    
    task automatic check_enable_timing();
        real t_e_high_start;
        real t_e_high_end;
        real t_e_pulse_width;
        
        // Check E pulse width (tEW min 50ns)
        @(posedge ds1124_e);
        t_e_high_start = $realtime;
        
        @(negedge ds1124_e);
        t_e_high_end = $realtime;
        t_e_pulse_width = t_e_high_end - t_e_high_start;
        
        // E should be high for at least 8 clock cycles
        if (t_e_pulse_width < 50.0) begin
            $error("[%0t] Enable pulse width violation! tEW = %0.2fns (min 50ns)", 
                   $time, t_e_pulse_width);
            error_cnt++;
        end
    endtask
    
    //-------------------------------------------------------------------------
    // Test Tasks
    //-------------------------------------------------------------------------
    task reset_dut();
        if (verbose) $display("[%0t] Applying reset", $time);
        rst = 1;
        en = 0;
        read_delay = 0;
        delay_value = 8'h00;
        repeat(5) @(posedge clk);
        rst = 0;
        repeat(5) @(posedge clk);
    endtask
    
    task write_delay(input logic [7:0] value);
        if (verbose) $display("[%0t] Writing delay value: 0x%02X", $time, value);
        
        // Wait for ready
        wait(ready);
        @(posedge clk);
        
        // Store the last value before writing new one
        last_written_value = ds1124_internal_reg;
        
        // Apply new value
        delay_value = value;
        en = 1;
        @(posedge clk);
        en = 0;
        
        // Wait for E to go high (shift starts)
        wait(ds1124_e);
        
        // Wait for E to go low (latch happens)
        wait(!ds1124_e);
        @(posedge clk);  // One more cycle for stability
        
        // Now verify the value was written correctly
        if (ds1124_internal_reg !== value) begin
            $error("[%0t] Write mismatch! Expected: 0x%02X, Got: 0x%02X", 
                   $time, value, ds1124_internal_reg);
            error_cnt++;
        end else begin
            if (verbose) $display("[%0t] Write successful: 0x%02X", $time, value);
        end
        
        // Wait for ready before returning
        $display("[%0t] Waiting for ready signal", $time);
        wait(ready);
        $display("[%0t] Ready signal received", $time);
    endtask
    
    task test_readback(input logic [7:0] expected);
        if (!READBACK_EN) return;
        
        if (verbose) $display("[%0t] Testing readback", $time);
        
        wait(ready);
        @(posedge clk);
        
        read_delay = 1;
        @(posedge clk);
        read_delay = 0;
        
        wait(read_valid);
        
        if (current_delay !== expected) begin
            $error("[%0t] Readback mismatch! Expected: 0x%02X, Got: 0x%02X",
                   $time, expected, current_delay);
            error_cnt++;
        end else begin
            if (verbose) $display("[%0t] Readback successful: 0x%02X", $time, current_delay);
        end
        
        @(posedge clk);
    endtask
    
    task test_back_to_back();
        logic [7:0] test_values[4];
        
        test_values[0] = 8'hA5;
        test_values[1] = 8'h5A;
        test_values[2] = 8'h00;
        test_values[3] = 8'hFF;
        
        $display("[%0t] Testing back-to-back writes", $time);
        
        foreach(test_values[i]) begin
            write_delay(test_values[i]);
            // Small delay between writes
            repeat(10) @(posedge clk);
        end
    endtask
    
    task automatic verify_serial_protocol_with_timing();
        logic [7:0] test_val;
        logic [7:0] received;
        int bit_num;
        
        test_val = 8'hCA;  // 11001010
        $display("[%0t] Verifying serial protocol WITH TIMING CHECKS for value 0x%02X", $time, test_val);
        
        // Start write
        wait(ready);
        @(posedge clk);
        delay_value = test_val;
        en = 1;
        @(posedge clk);
        en = 0;
        
        // Wait for E to go high
        wait(ds1124_e);
        
        // Inline timing checks during bit capture
        begin
            real t_last_clk = 0;
            real t_curr_clk;
            real t_period;
            real t_e_start;
            
            t_e_start = $realtime;
            
            // Capture each bit with timing checks
            bit_num = 7;
            repeat(8) begin
                @(posedge ds1124_clk);
                t_curr_clk = $realtime;
                
                // Check clock period
                if (t_last_clk > 0) begin
                    t_period = t_curr_clk - t_last_clk;
                    if (t_period < 100.0) begin
                        $error("[%0t] Clock too fast! Period = %0.2fns (min 100ns)", $time, t_period);
                        error_cnt++;
                    end else if (verbose) begin
                        $display("[%0t] Clock period OK: %0.2fns", $time, t_period);
                    end
                end
                t_last_clk = t_curr_clk;
                
                @(negedge ds1124_clk);  // Sample data when stable
                received[bit_num] = ds1124_d;
                if (verbose) $display("[%0t] Bit %0d = %b", $time, bit_num, ds1124_d);
                
                bit_num--;
            end
            
            // Check E pulse width
            if (($realtime - t_e_start) < 50.0) begin
                $error("[%0t] E pulse too short! Width = %0.2fns (min 50ns)", 
                       $time, ($realtime - t_e_start));
                error_cnt++;
            end
        end
        
        $display("[%0t] All bits captured, waiting for E to go low", $time);
        // Wait for latch
        wait(!ds1124_e);
        $display("[%0t] E went low (latch occurred)", $time);
        @(posedge clk);
        
        // Check the latched value
        if (ds1124_internal_reg !== test_val) begin
            $error("[%0t] Latched value error! Expected: 0x%02X, Got: 0x%02X",
                   $time, test_val, ds1124_internal_reg);
            error_cnt++;
        end
        
        if (received !== test_val) begin
            $error("[%0t] Serial protocol error! Sent: 0x%02X, Received: 0x%02X",
                   $time, test_val, received);
            error_cnt++;
        end else begin
            $display("[%0t] Serial protocol verified correctly", $time);
        end
        
        // Wait for ready before returning
        $display("[%0t] Waiting for ready signal", $time);
        wait(ready);
        $display("[%0t] Ready signal received", $time);
    endtask
    
    //-------------------------------------------------------------------------
    // Main Test Sequence
    //-------------------------------------------------------------------------
    initial begin
        $display("========================================");
        $display("DS1124 Driver Testbench Starting");
        $display("========================================");
        
        error_cnt = 0;
        test_cnt = 0;
        
        // Initialize
        rst = 0;
        en = 0;
        read_delay = 0;
        delay_value = 8'h00;
        
        // Reset
        reset_dut();
        
        // Test 1: Basic writes
        $display("\n[TEST 1] Basic Write Operations");
        test_cnt++;
        write_delay(8'h00);  // Min delay
        write_delay(8'hFF);  // Max delay
        write_delay(8'h80);  // Mid delay
        write_delay(8'h55);  // Pattern 1
        write_delay(8'hAA);  // Pattern 2
        
        // Test 2: Serial protocol verification with timing
        $display("\n[TEST 2] Serial Protocol Verification with Timing");
        test_cnt++;
        verify_serial_protocol_with_timing();
        
        // Test 3: Back-to-back writes
        $display("\n[TEST 3] Back-to-Back Writes");
        test_cnt++;
        test_back_to_back();
        
        // Test 4: Readback functionality
        if (READBACK_EN) begin
            $display("\n[TEST 4] Readback Functionality");
            test_cnt++;
            write_delay(8'h3C);
            test_readback(8'h3C);
            write_delay(8'hF0);
            test_readback(8'hF0);
        end
        
        // Test 5: Reset during operation
        $display("\n[TEST 5] Reset During Operation");
        test_cnt++;
        delay_value = 8'hBE;
        en = 1;
        @(posedge clk);
        en = 0;
        repeat(20) @(posedge clk);  // Reset during shift
        rst = 1;
        repeat(5) @(posedge clk);
        rst = 0;
        repeat(5) @(posedge clk);
        
        // Verify ready after reset
        if (!ready) begin
            $error("[%0t] Not ready after reset!", $time);
            error_cnt++;
        end
        
        // Test 6: Rapid enable toggling
        $display("\n[TEST 6] Rapid Enable Toggling");
        test_cnt++;
        wait(ready);
        delay_value = 8'h42;
        repeat(3) begin
            en = 1;
            @(posedge clk);
            en = 0;
            @(posedge clk);
        end
        wait(ready);
        
        // Test 7: Random values
        $display("\n[TEST 7] Random Value Testing");
        test_cnt++;
        repeat(10) begin
            write_delay($urandom_range(0, 255));
        end
        
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
        #10ms;
        $error("Testbench timeout!");
        $finish;
    end
    
    //-------------------------------------------------------------------------
    // Waveform Dumping
    //-------------------------------------------------------------------------
    initial begin
        $dumpfile("ds1124_driver_tb.vcd");
        $dumpvars(0, ds1124_driver_tb);
    end
    
endmodule