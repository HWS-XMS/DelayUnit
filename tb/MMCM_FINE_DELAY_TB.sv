`timescale 1ps / 1ps

module MMCM_FINE_DELAY_TB;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic trigger_in = 1'b0;
    logic trigger_out;
    logic [15:0] fine_delay_ps = 16'd0;
    logic fine_update = 1'b0;
    logic mmcm_locked;
    
    // Clock generation - 100MHz
    always #5000 clk = ~clk;  // 10ns period in ps
    
    // DUT instance
    MMCM_FINE_DELAY dut (
        .clk(clk),
        .rst(rst),
        .trigger_in(trigger_in),
        .trigger_out(trigger_out),
        .fine_delay_ps(fine_delay_ps),
        .fine_update(fine_update),
        .mmcm_locked(mmcm_locked)
    );
    
    // Measure delay
    time trigger_in_time;
    time trigger_out_time;
    real measured_delay_ps;
    
    always @(posedge trigger_in) begin
        trigger_in_time = $time;
    end
    
    always @(posedge trigger_out) begin
        trigger_out_time = $time;
        measured_delay_ps = trigger_out_time - trigger_in_time;
        $display("[%0t] Trigger delay: %.1f ps", $time, measured_delay_ps);
    end
    
    // Test sequence
    initial begin
        $display("Starting MMCM Fine Delay Test");
        
        // Reset
        #100000 rst = 1'b0;
        
        // Wait for MMCM lock
        wait(mmcm_locked);
        $display("[%0t] MMCM locked", $time);
        #100000;
        
        // Test 1: No delay
        $display("\nTest 1: Zero delay");
        fine_delay_ps = 16'd0;
        fine_update = 1'b1;
        #10000 fine_update = 1'b0;
        #500000;
        
        trigger_in = 1'b1;
        #100000 trigger_in = 1'b0;
        #1000000;
        
        // Test 2: 100ps delay
        $display("\nTest 2: 100ps delay");
        fine_delay_ps = 16'd100;
        fine_update = 1'b1;
        #10000 fine_update = 1'b0;
        #2000000;  // Wait for phase shift completion
        
        trigger_in = 1'b1;
        #100000 trigger_in = 1'b0;
        #1000000;
        
        // Test 3: 500ps delay
        $display("\nTest 3: 500ps delay");
        fine_delay_ps = 16'd500;
        fine_update = 1'b1;
        #10000 fine_update = 1'b0;
        #3000000;  // Wait for phase shift completion
        
        trigger_in = 1'b1;
        #100000 trigger_in = 1'b0;
        #1000000;
        
        // Test 4: Maximum delay (999ps)
        $display("\nTest 4: 999ps delay");
        fine_delay_ps = 16'd999;
        fine_update = 1'b1;
        #10000 fine_update = 1'b0;
        #5000000;  // Wait for phase shift completion
        
        trigger_in = 1'b1;
        #100000 trigger_in = 1'b0;
        #1000000;
        
        // Test 5: Sweep fine delays
        $display("\nTest 5: Delay sweep 0-900ps in 100ps steps");
        for (int i = 0; i <= 900; i += 100) begin
            fine_delay_ps = i;
            fine_update = 1'b1;
            #10000 fine_update = 1'b0;
            #3000000;  // Wait for phase shift
            
            $display("  Setting delay: %d ps", i);
            trigger_in = 1'b1;
            #100000 trigger_in = 1'b0;
            #1000000;
        end
        
        $display("\nTest complete");
        $finish;
    end
    
    // Timeout
    initial begin
        #100_000_000;  // 100ms timeout
        $display("ERROR: Test timeout");
        $finish;
    end

endmodule