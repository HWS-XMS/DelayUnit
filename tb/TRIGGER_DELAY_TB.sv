`timescale 1ns / 1ps

module TRIGGER_DELAY_TB;

    // Clock and reset
    logic clk;
    logic rst;
    
    // DUT signals
    logic trigger_in;
    logic trigger_out;
    logic uart_rx_line;
    logic uart_tx_line;
    logic [3:0] leds;
    
    // Testbench UART signals
    logic [7:0] tb_tx_data;
    logic tb_tx_en;
    logic tb_tx_ready;
    logic [7:0] tb_rx_data;
    logic tb_rx_data_valid;
    
    // Test variables
    logic [31:0] test_delay;
    logic [7:0] rx_buffer[6];
    logic [15:0] counter_before;
    integer i;
    
    // Clock generation - 100 MHz
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 10ns period = 100 MHz
    end
    
    // DUT instance
    TRIGGER_DELAY_TOP dut (
        .clk(clk),
        .rst(rst),
        .trigger_in(trigger_in),
        .trigger_out(trigger_out),
        .uart_rx(uart_rx_line),
        .uart_tx(uart_tx_line),
        .leds(leds)
    );
    
    // Testbench UART TX (to send commands to DUT)
    UART_TX #(
        .SYSTEMCLOCK(100_000_000),
        .BAUDRATE(115200),
        .ELEMENT_WIDTH(8)
    ) tb_uart_tx (
        .clk(clk),
        .rst(rst),
        .tx_en(tb_tx_en),
        .tx_data(tb_tx_data),
        .tx_line(uart_rx_line),  // Connected to DUT's RX
        .tx_ready(tb_tx_ready)
    );
    
    // Testbench UART RX (to receive responses from DUT)
    UART_RX #(
        .ELEMENT_WIDTH(8),
        .BAUDRATE(115200),
        .SYSTEMCLOCK(100_000_000)
    ) tb_uart_rx (
        .clk(clk),
        .rst(rst),
        .rx_line(uart_tx_line),  // Connected to DUT's TX
        .rx_data(tb_rx_data),
        .rx_data_valid(tb_rx_data_valid)
    );
    
    // Task to send byte via UART
    task send_byte(input [7:0] data);
        begin
            @(posedge clk);
            wait(tb_tx_ready);
            tb_tx_data <= data;
            tb_tx_en <= 1'b1;
            @(posedge clk);
            tb_tx_en <= 1'b0;
            @(posedge clk);
            wait(tb_tx_ready);
        end
    endtask
    
    // Task to receive byte via UART
    task receive_byte(output [7:0] data);
        begin
            @(posedge tb_rx_data_valid);
            data = tb_rx_data;
            @(posedge clk);
        end
    endtask
    
    // Task to send trigger pulse
    task send_trigger_pulse();
        begin
            trigger_in = 1'b1;
            repeat(10) @(posedge clk);  // 10 clock cycles high
            trigger_in = 1'b0;
            repeat(10) @(posedge clk);  // 10 clock cycles low
        end
    endtask
    
    // Main test sequence
    initial begin
        $dumpfile("trigger_delay_tb.vcd");
        $dumpvars(0, trigger_delay_tb);
        
        // Initialize signals
        rst = 1'b1;
        trigger_in = 1'b0;
        tb_tx_data = 8'h00;
        tb_tx_en = 1'b0;
        
        // Reset sequence
        repeat(10) @(posedge clk);
        rst = 1'b0;
        repeat(10) @(posedge clk);
        
        $display("===========================================");
        $display("    Trigger Delay System Test Started     ");
        $display("===========================================\n");
        
        // Test 1: Set edge type to RISING
        $display("Test 1: Setting edge type to RISING (0x01)");
        send_byte(8'h03);  // CMD_SET_EDGE
        send_byte(8'h01);  // EDGE_RISING
        repeat(100) @(posedge clk);
        
        // Test 2: Set delay to 1000 clock cycles
        $display("Test 2: Setting delay to 1000 clock cycles");
        test_delay = 32'd1000;
        send_byte(8'h01);  // CMD_SET_DELAY
        send_byte(test_delay[7:0]);
        send_byte(test_delay[15:8]);
        send_byte(test_delay[23:16]);
        send_byte(test_delay[31:24]);
        repeat(100) @(posedge clk);
        
        // Test 3: Get current delay setting
        $display("Test 3: Reading back delay setting");
        send_byte(8'h02);  // CMD_GET_DELAY
        
        // Receive 4 bytes
        for (i = 0; i < 4; i++) begin
            receive_byte(rx_buffer[i]);
        end
        
        $display("  Received delay: 0x%08h (expected: 0x%08h)", 
                 {rx_buffer[3], rx_buffer[2], rx_buffer[1], rx_buffer[0]}, 
                 test_delay);
        
        // Test 4: Send triggers and verify delay
        $display("\nTest 4: Sending triggers and measuring delay");
        
        for (i = 0; i < 3; i++) begin
            $display("  Sending trigger %0d at time %0t", i+1, $time);
            send_trigger_pulse();
            repeat(2000) @(posedge clk);  // Wait for delayed output
        end
        
        // Test 5: Get status (counter and delay)
        $display("\nTest 5: Getting system status");
        send_byte(8'h05);  // CMD_GET_STATUS
        
        // Receive 6 bytes (2 for counter, 4 for delay)
        for (i = 0; i < 6; i++) begin
            receive_byte(rx_buffer[i]);
        end
        
        $display("  Trigger count: %0d", {rx_buffer[1], rx_buffer[0]});
        $display("  Current delay: %0d cycles", 
                 {rx_buffer[5], rx_buffer[4], rx_buffer[3], rx_buffer[2]});
        $display("  LED status: 4'b%04b", leds);
        
        // Test 6: Change edge type to FALLING
        $display("\nTest 6: Changing edge type to FALLING");
        send_byte(8'h03);  // CMD_SET_EDGE
        send_byte(8'h02);  // EDGE_FALLING
        repeat(100) @(posedge clk);
        
        // Send trigger with falling edge
        trigger_in = 1'b1;
        repeat(20) @(posedge clk);
        $display("  Trigger falling edge at time %0t", $time);
        trigger_in = 1'b0;  // This should trigger
        repeat(2000) @(posedge clk);
        
        // Test 7: Reset counter
        $display("\nTest 7: Resetting trigger counter");
        send_byte(8'h06);  // CMD_RESET_COUNT
        repeat(100) @(posedge clk);
        
        // Get status to verify reset
        send_byte(8'h05);  // CMD_GET_STATUS
        
        for (i = 0; i < 6; i++) begin
            receive_byte(rx_buffer[i]);
        end
        
        $display("  Counter after reset: %0d (should be 0)", 
                 {rx_buffer[1], rx_buffer[0]});
        
        // Test 8: Test BOTH edges mode
        $display("\nTest 8: Testing BOTH edges mode");
        send_byte(8'h03);  // CMD_SET_EDGE
        send_byte(8'h03);  // EDGE_BOTH
        repeat(100) @(posedge clk);
        
        // Send pulse (should trigger on both edges)
        trigger_in = 1'b0;
        repeat(10) @(posedge clk);
        trigger_in = 1'b1;  // Rising edge
        $display("  Rising edge at %0t", $time);
        repeat(20) @(posedge clk);
        trigger_in = 1'b0;  // Falling edge
        $display("  Falling edge at %0t", $time);
        repeat(2000) @(posedge clk);
        
        // Get final status
        send_byte(8'h05);  // CMD_GET_STATUS
        
        for (i = 0; i < 6; i++) begin
            receive_byte(rx_buffer[i]);
        end
        
        $display("  Final trigger count: %0d", {rx_buffer[1], rx_buffer[0]});
        
        // Test 9: Test zero delay
        $display("\nTest 9: Testing zero delay (immediate pass-through)");
        send_byte(8'h01);  // CMD_SET_DELAY
        send_byte(8'h00);  // 0 delay
        send_byte(8'h00);
        send_byte(8'h00);
        send_byte(8'h00);
        repeat(100) @(posedge clk);
        
        // Set edge type back to RISING for cleaner test
        send_byte(8'h03);  // CMD_SET_EDGE
        send_byte(8'h01);  // EDGE_RISING
        repeat(100) @(posedge clk);
        
        // Send trigger and check immediate response
        trigger_in = 1'b0;
        repeat(10) @(posedge clk);
        trigger_in = 1'b1;
        repeat(10) @(posedge clk);
        trigger_in = 1'b0;
        $display("  Zero delay: Trigger sent, output should be immediate");
        
        repeat(100) @(posedge clk);
        
        // Test 10: Test EDGE_NONE mode - should block all triggers
        $display("\nTest 10: Testing EDGE_NONE mode (no triggers should pass)");
        send_byte(8'h03);  // CMD_SET_EDGE
        send_byte(8'h00);  // EDGE_NONE
        repeat(100) @(posedge clk);
        
        // Send multiple edge types - none should trigger
        trigger_in = 1'b0;
        repeat(10) @(posedge clk);
        trigger_in = 1'b1;  // Rising edge - should NOT trigger
        $display("  Sent rising edge at %0t (should NOT trigger)", $time);
        repeat(20) @(posedge clk);
        trigger_in = 1'b0;  // Falling edge - should NOT trigger
        $display("  Sent falling edge at %0t (should NOT trigger)", $time);
        repeat(100) @(posedge clk);
        
        // Get status to verify no new triggers counted
        send_byte(8'h05);  // CMD_GET_STATUS
        for (i = 0; i < 6; i++) begin
            receive_byte(rx_buffer[i]);
        end
        $display("  Counter after EDGE_NONE test: %0d (should be unchanged)", 
                 {rx_buffer[1], rx_buffer[0]});
        
        // Test 11: Test GET_EDGE command
        $display("\nTest 11: Testing GET_EDGE command");
        
        // First set to RISING
        send_byte(8'h03);  // CMD_SET_EDGE
        send_byte(8'h01);  // EDGE_RISING
        repeat(100) @(posedge clk);
        
        // Get edge type
        send_byte(8'h04);  // CMD_GET_EDGE
        receive_byte(rx_buffer[0]);
        $display("  Read edge type: 0x%02h (expected 0x01 for RISING)", rx_buffer[0]);
        
        // Set to FALLING and verify
        send_byte(8'h03);  // CMD_SET_EDGE
        send_byte(8'h02);  // EDGE_FALLING
        repeat(100) @(posedge clk);
        
        send_byte(8'h04);  // CMD_GET_EDGE
        receive_byte(rx_buffer[0]);
        $display("  Read edge type: 0x%02h (expected 0x02 for FALLING)", rx_buffer[0]);
        
        // Set to BOTH and verify
        send_byte(8'h03);  // CMD_SET_EDGE
        send_byte(8'h03);  // EDGE_BOTH
        repeat(100) @(posedge clk);
        
        send_byte(8'h04);  // CMD_GET_EDGE
        receive_byte(rx_buffer[0]);
        $display("  Read edge type: 0x%02h (expected 0x03 for BOTH)", rx_buffer[0]);
        
        // Test 12: Test overlapping triggers (trigger while delay is counting)
        $display("\nTest 12: Testing overlapping triggers");
        
        // Set a moderate delay
        test_delay = 32'd500;
        send_byte(8'h01);  // CMD_SET_DELAY
        send_byte(test_delay[7:0]);
        send_byte(test_delay[15:8]);
        send_byte(test_delay[23:16]);
        send_byte(test_delay[31:24]);
        repeat(100) @(posedge clk);
        
        // Set to RISING edge
        send_byte(8'h03);  // CMD_SET_EDGE
        send_byte(8'h01);  // EDGE_RISING
        repeat(100) @(posedge clk);
        
        // Send first trigger
        $display("  Sending first trigger at %0t", $time);
        send_trigger_pulse();
        
        // Send second trigger while first is still being delayed (after 250 cycles)
        repeat(250) @(posedge clk);
        $display("  Sending second trigger at %0t (during first delay)", $time);
        send_trigger_pulse();
        
        // Wait for both triggers to complete
        repeat(1500) @(posedge clk);
        
        // Test 13: Test minimum non-zero delay (1 cycle)
        $display("\nTest 13: Testing minimum delay (1 cycle)");
        send_byte(8'h01);  // CMD_SET_DELAY
        send_byte(8'h01);  // 1 cycle delay
        send_byte(8'h00);
        send_byte(8'h00);
        send_byte(8'h00);
        repeat(100) @(posedge clk);
        
        $display("  Sending trigger with 1-cycle delay");
        send_trigger_pulse();
        repeat(100) @(posedge clk);
        
        // Test 14: Test invalid command (should be ignored)
        $display("\nTest 14: Testing invalid command handling");
        
        // Get current counter value
        send_byte(8'h05);  // CMD_GET_STATUS
        for (i = 0; i < 6; i++) begin
            receive_byte(rx_buffer[i]);
        end
        counter_before = {rx_buffer[1], rx_buffer[0]};
        $display("  Counter before invalid command: %0d", counter_before);
        
        // Send invalid command
        send_byte(8'hFF);  // Invalid command
        repeat(1000) @(posedge clk);
        
        // Verify system still works
        send_byte(8'h05);  // CMD_GET_STATUS
        for (i = 0; i < 6; i++) begin
            receive_byte(rx_buffer[i]);
        end
        $display("  Counter after invalid command: %0d (should be same)", 
                 {rx_buffer[1], rx_buffer[0]});
        
        // Test 15: Test changing delay while NOT counting
        $display("\nTest 15: Testing delay change while idle");
        
        // Set initial delay
        send_byte(8'h01);  // CMD_SET_DELAY
        send_byte(8'd100);  // 100 cycles
        send_byte(8'd0);
        send_byte(8'd0);
        send_byte(8'd0);
        repeat(100) @(posedge clk);
        
        // Immediately change to different delay
        send_byte(8'h01);  // CMD_SET_DELAY
        send_byte(8'd200);  // 200 cycles
        send_byte(8'd0);
        send_byte(8'd0);
        send_byte(8'd0);
        repeat(100) @(posedge clk);
        
        // Verify new delay is active
        send_byte(8'h02);  // CMD_GET_DELAY
        for (i = 0; i < 4; i++) begin
            receive_byte(rx_buffer[i]);
        end
        $display("  Delay after change: %0d (expected 200)", 
                 {rx_buffer[3], rx_buffer[2], rx_buffer[1], rx_buffer[0]});
        
        $display("\n===========================================");
        $display("    Trigger Delay System Test Complete    ");
        $display("    Total Tests Run: 15                   ");
        $display("===========================================");
        
        $finish;
    end
    
    // Monitor trigger output
    always @(posedge trigger_out) begin
        $display("  [MONITOR] Trigger output detected at time %0t", $time);
    end
    
    // Timeout watchdog
    initial begin
        #50_000_000;  // 50ms timeout
        $display("ERROR: Test timeout!");
        $finish;
    end

endmodule