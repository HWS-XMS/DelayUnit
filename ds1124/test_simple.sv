`timescale 1ns/1ps
module test_simple;
    logic clk = 0;
    logic rst;
    logic [7:0] delay_value;
    logic en;
    logic ready;
    logic ds1124_clk, ds1124_d, ds1124_e, ds1124_q = 0;
    logic read_delay;
    logic [7:0] current_delay;
    logic read_valid;
    
    always #5 clk = ~clk;
    
    ds1124_driver #(.CLK_DIV(4)) dut (.*);
    
    initial begin
        $dumpfile("simple.vcd");
        $dumpvars(0);
        rst = 1;
        en = 0;
        delay_value = 0;
        read_delay = 0;
        #100;
        rst = 0;
        #100;
        
        // Write 0x55
        wait(ready);
        delay_value = 8'h55;
        en = 1;
        @(posedge clk);
        en = 0;
        
        // Count clocks
        begin
            int clk_count = 0;
            wait(ds1124_e);
            $display("E went high at %0t", $time);
            
            while(ds1124_e) begin
                @(posedge ds1124_clk);
                clk_count++;
                $display("CLK %0d rise at %0t, D=%b", clk_count, $time, ds1124_d);
            end
            
            $display("E went low at %0t after %0d clocks", $time, clk_count);
        end
        
        wait(ready);
        $display("Ready at %0t", $time);
        #100;
        $finish;
    end
endmodule