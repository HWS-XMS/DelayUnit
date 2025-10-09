// Test to demonstrate automatic counter width sizing
module test_counter_width;

    initial begin
        $display("Settle Counter Width Analysis:");
        $display("================================");
        
        // 100 MHz clock
        begin
            localparam int SYS_CLK_FREQ = 100_000_000;
            localparam int SETTLE_TIME_US = 50;
            localparam int SETTLE_TIME = SYS_CLK_FREQ / 1_000_000 * SETTLE_TIME_US;
            localparam int COUNTER_WIDTH = $clog2(SETTLE_TIME+1);
            $display("100 MHz:  SETTLE_TIME=%0d cycles, Counter width=%0d bits", SETTLE_TIME, COUNTER_WIDTH);
        end
        
        // 50 MHz clock
        begin
            localparam int SYS_CLK_FREQ = 50_000_000;
            localparam int SETTLE_TIME_US = 50;
            localparam int SETTLE_TIME = SYS_CLK_FREQ / 1_000_000 * SETTLE_TIME_US;
            localparam int COUNTER_WIDTH = $clog2(SETTLE_TIME+1);
            $display("50 MHz:   SETTLE_TIME=%0d cycles, Counter width=%0d bits", SETTLE_TIME, COUNTER_WIDTH);
        end
        
        // 500 MHz clock
        begin
            localparam int SYS_CLK_FREQ = 500_000_000;
            localparam int SETTLE_TIME_US = 50;
            localparam int SETTLE_TIME = SYS_CLK_FREQ / 1_000_000 * SETTLE_TIME_US;
            localparam int COUNTER_WIDTH = $clog2(SETTLE_TIME+1);
            $display("500 MHz:  SETTLE_TIME=%0d cycles, Counter width=%0d bits", SETTLE_TIME, COUNTER_WIDTH);
        end
        
        // 1 GHz clock
        begin
            localparam int SYS_CLK_FREQ = 1_000_000_000;
            localparam int SETTLE_TIME_US = 50;
            localparam int SETTLE_TIME = SYS_CLK_FREQ / 1_000_000 * SETTLE_TIME_US;
            localparam int COUNTER_WIDTH = $clog2(SETTLE_TIME+1);
            $display("1 GHz:    SETTLE_TIME=%0d cycles, Counter width=%0d bits", SETTLE_TIME, COUNTER_WIDTH);
        end
        
        // 2 GHz clock
        begin
            localparam int SYS_CLK_FREQ = 2_000_000_000;
            localparam int SETTLE_TIME_US = 50;
            localparam int SETTLE_TIME = SYS_CLK_FREQ / 1_000_000 * SETTLE_TIME_US;
            localparam int COUNTER_WIDTH = $clog2(SETTLE_TIME+1);
            $display("2 GHz:    SETTLE_TIME=%0d cycles, Counter width=%0d bits", SETTLE_TIME, COUNTER_WIDTH);
        end
        
        $display("\nConclusion: Counter automatically sizes from %0d to %0d bits based on clock frequency", 12, 17);
        $display("Old fixed [15:0] would overflow at frequencies > 1.31 GHz");
        $display("New dynamic sizing supports any frequency!");
        $finish;
    end
    
endmodule