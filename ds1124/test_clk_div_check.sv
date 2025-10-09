// Test that CLK_DIV parameter validation works
module test_clk_div_check;
    logic clk = 0;
    logic rst = 0;
    logic [7:0] delay_value = 0;
    logic en = 0;
    logic ready;
    logic ds1124_clk, ds1124_d, ds1124_e;
    logic ds1124_q = 0;
    logic read_delay = 0;
    logic [7:0] current_delay;
    logic read_valid;
    
    // Test with valid CLK_DIV = 4
    ds1124_driver #(.CLK_DIV(4)) good_driver (.*);
    
    // Test with invalid CLK_DIV = 1 (should trigger assertion)
    // Uncomment to test:
    ds1124_driver #(.CLK_DIV(1)) bad_driver (.*);
    
    initial begin
        $display("Testing CLK_DIV validation...");
        #10;
        $display("CLK_DIV=4 instantiation successful!");
        $display("Uncomment the CLK_DIV=1 line to test assertion failure");
        $finish;
    end
endmodule