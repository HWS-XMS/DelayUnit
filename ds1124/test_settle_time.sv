// Test that settle time is calculated correctly for different clock frequencies
module test_settle_time;

    // Test different clock frequencies
    initial begin
        $display("Testing SETTLE_TIME calculation:");
        
        // 100 MHz clock
        begin
            localparam int SYS_CLK_FREQ = 100_000_000;
            localparam int SETTLE_TIME_US = 50;
            localparam int SETTLE_TIME = SYS_CLK_FREQ / 1_000_000 * SETTLE_TIME_US;
            $display("  100 MHz: SETTLE_TIME = %0d cycles (expected 5000)", SETTLE_TIME);
            assert(SETTLE_TIME == 5000) else $error("100MHz calculation failed!");
        end
        
        // 50 MHz clock
        begin
            localparam int SYS_CLK_FREQ = 50_000_000;
            localparam int SETTLE_TIME_US = 50;
            localparam int SETTLE_TIME = SYS_CLK_FREQ / 1_000_000 * SETTLE_TIME_US;
            $display("  50 MHz:  SETTLE_TIME = %0d cycles (expected 2500)", SETTLE_TIME);
            assert(SETTLE_TIME == 2500) else $error("50MHz calculation failed!");
        end
        
        // 125 MHz clock
        begin
            localparam int SYS_CLK_FREQ = 125_000_000;
            localparam int SETTLE_TIME_US = 50;
            localparam int SETTLE_TIME = SYS_CLK_FREQ / 1_000_000 * SETTLE_TIME_US;
            $display("  125 MHz: SETTLE_TIME = %0d cycles (expected 6250)", SETTLE_TIME);
            assert(SETTLE_TIME == 6250) else $error("125MHz calculation failed!");
        end
        
        // 200 MHz clock
        begin
            localparam int SYS_CLK_FREQ = 200_000_000;
            localparam int SETTLE_TIME_US = 50;
            localparam int SETTLE_TIME = SYS_CLK_FREQ / 1_000_000 * SETTLE_TIME_US;
            $display("  200 MHz: SETTLE_TIME = %0d cycles (expected 10000)", SETTLE_TIME);
            assert(SETTLE_TIME == 10000) else $error("200MHz calculation failed!");
        end
        
        $display("All settle time calculations passed!");
        $finish;
    end
    
endmodule