`timescale 1ns / 1ps

`include "TRIGGER_DELAY_DEFS.vh"

//-----------------------------------------------------------------------------
// TRIGGER_DELAY_TOP Integration Testbench
//-----------------------------------------------------------------------------
// Architecture:
//   - UART_TX (stimulus) -> DUT uart_rx
//   - DUT uart_tx -> UART_RX (monitor)
//   - Same clock/baud parameters as DUT internal UART
//-----------------------------------------------------------------------------

module TRIGGER_DELAY_TOP_tb;

    //-------------------------------------------------------------------------
    // Parameters - Match DUT internal configuration
    //-------------------------------------------------------------------------
    localparam CLK_PERIOD_100M = 10.0;   // 100MHz input clock (10ns)
    localparam CLK_FREQ_200M   = 200_000_000;
    localparam BAUD_RATE       = 1_000_000;

    //-------------------------------------------------------------------------
    // DUT Signals
    //-------------------------------------------------------------------------
    logic        clk_100m;
    logic        rst;
    logic        trigger_in;
    logic        trigger_delayed_out;
    logic        soft_trigger_out;
    logic        uart_rx_line;   // DUT's RX input (driven by test UART_TX)
    logic        uart_tx_line;   // DUT's TX output (monitored by test UART_RX)
    logic [3:0]  leds;

    //-------------------------------------------------------------------------
    // Test UART Signals (stimulus/monitor)
    //-------------------------------------------------------------------------
    // Stimulus UART_TX - sends commands to DUT
    logic        stim_tx_en;
    logic [7:0]  stim_tx_data;
    logic        stim_tx_ready;

    // Monitor UART_RX - receives responses from DUT
    logic [7:0]  mon_rx_data;
    logic        mon_rx_valid;

    // Internal 200MHz clock for test UARTs (directly from DUT's MMCM)
    logic        clk_200m;
    assign clk_200m = dut.clk_sys_buf;

    // Reset synchronized to 200MHz domain
    logic        rst_200m;

    //-------------------------------------------------------------------------
    // Test Variables
    //-------------------------------------------------------------------------
    int error_cnt;
    logic [31:0] received_value;
    int byte_cnt;

    //-------------------------------------------------------------------------
    // Clock Generation - 100MHz input
    //-------------------------------------------------------------------------
    initial begin
        clk_100m = 0;
        forever #(CLK_PERIOD_100M/2) clk_100m = ~clk_100m;
    end

    //-------------------------------------------------------------------------
    // DUT Instantiation
    //-------------------------------------------------------------------------
    TRIGGER_DELAY_TOP dut (
        .clk                (clk_100m),
        .rst                (rst),
        .trigger_in         (trigger_in),
        .trigger_delayed_out(trigger_delayed_out),
        .soft_trigger_out   (soft_trigger_out),
        .uart_rx            (uart_rx_line),
        .uart_tx            (uart_tx_line),
        .leds               (leds)
    );

    //-------------------------------------------------------------------------
    // Stimulus UART_TX - Sends commands to DUT
    // Runs on 200MHz clock, same as DUT internal UART
    //-------------------------------------------------------------------------
    UART_TX #(
        .SYSTEMCLOCK  (CLK_FREQ_200M),
        .BAUDRATE     (BAUD_RATE),
        .ELEMENT_WIDTH(8)
    ) stim_uart_tx (
        .clk     (clk_200m),
        .rst     (rst_200m),
        .tx_en   (stim_tx_en),
        .tx_data (stim_tx_data),
        .tx_line (uart_rx_line),  // Connected to DUT's RX
        .tx_ready(stim_tx_ready)
    );

    //-------------------------------------------------------------------------
    // Monitor UART_RX - Receives responses from DUT
    //-------------------------------------------------------------------------
    UART_RX #(
        .ELEMENT_WIDTH(8),
        .BAUDRATE     (BAUD_RATE),
        .SYSTEMCLOCK  (CLK_FREQ_200M)
    ) mon_uart_rx (
        .clk          (clk_200m),
        .rst          (rst_200m),
        .rx_line      (uart_tx_line),  // Connected to DUT's TX
        .rx_data      (mon_rx_data),
        .rx_data_valid(mon_rx_valid)
    );

    //-------------------------------------------------------------------------
    // Reset synchronization to 200MHz domain
    //-------------------------------------------------------------------------
    always_ff @(posedge clk_200m or posedge rst) begin
        if (rst)
            rst_200m <= 1'b1;
        else
            rst_200m <= 1'b0;
    end

    //-------------------------------------------------------------------------
    // MMCM Lock Monitoring
    //-------------------------------------------------------------------------
    logic mmcm_locked;
    assign mmcm_locked = dut.mmcm_locked;

    //-------------------------------------------------------------------------
    // Test Tasks
    //-------------------------------------------------------------------------

    // Wait for MMCM to lock with timeout
    task automatic wait_for_mmcm_lock(input int timeout_us);
        int cycles;
        cycles = 0;
        while (!mmcm_locked && cycles < timeout_us * 100) begin
            @(posedge clk_100m);
            cycles++;
        end
        if (!mmcm_locked) begin
            $error("MMCM failed to lock within %0d us", timeout_us);
            error_cnt++;
        end else begin
            $display("[%0t] MMCM locked after %0d cycles", $time, cycles);
        end
    endtask

    // Send a single byte via stimulus UART
    task automatic send_byte(input logic [7:0] data);
        wait(stim_tx_ready);
        @(posedge clk_200m);
        stim_tx_data = data;
        stim_tx_en = 1'b1;
        @(posedge clk_200m);
        stim_tx_en = 1'b0;
        wait(stim_tx_ready);  // Wait for transmission complete
    endtask

    // Send command with no payload
    task automatic send_cmd(input logic [7:0] cmd);
        $display("[%0t] Sending command: 0x%02X", $time, cmd);
        send_byte(cmd);
    endtask

    // Send command with 1-byte payload
    task automatic send_cmd_1byte(input logic [7:0] cmd, input logic [7:0] payload);
        $display("[%0t] Sending command: 0x%02X, payload: 0x%02X", $time, cmd, payload);
        send_byte(cmd);
        send_byte(payload);
    endtask

    // Send command with 4-byte payload (little-endian)
    task automatic send_cmd_4byte(input logic [7:0] cmd, input logic [31:0] payload);
        $display("[%0t] Sending command: 0x%02X, payload: 0x%08X", $time, cmd, payload);
        send_byte(cmd);
        send_byte(payload[7:0]);
        send_byte(payload[15:8]);
        send_byte(payload[23:16]);
        send_byte(payload[31:24]);
    endtask

    // Receive 1 byte with timeout
    task automatic receive_byte(output logic [7:0] data, output logic success);
        int timeout;
        timeout = 0;
        success = 1'b0;
        while (!mon_rx_valid && timeout < 50000) begin
            @(posedge clk_200m);
            timeout++;
        end
        if (mon_rx_valid) begin
            data = mon_rx_data;
            success = 1'b1;
            @(posedge clk_200m);  // Allow valid to clear
        end else begin
            $error("[%0t] Receive timeout!", $time);
            error_cnt++;
        end
    endtask

    // Receive 4 bytes (little-endian) with timeout
    task automatic receive_4bytes(output logic [31:0] data, output logic success);
        logic [7:0] byte_val;
        logic byte_ok;
        data = 32'd0;
        success = 1'b1;
        for (int i = 0; i < 4; i++) begin
            receive_byte(byte_val, byte_ok);
            if (!byte_ok) begin
                success = 1'b0;
                return;
            end
            data[i*8 +: 8] = byte_val;
        end
    endtask

    //-------------------------------------------------------------------------
    // Test Cases
    //-------------------------------------------------------------------------

    task automatic test_get_coarse();
        logic [31:0] value;
        logic ok;
        $display("\n[TEST] GET_COARSE (default value should be 0)");
        send_cmd(`CMD_GET_COARSE);
        receive_4bytes(value, ok);
        if (ok) begin
            if (value !== 32'd0) begin
                $error("GET_COARSE: Expected 0, got %0d", value);
                error_cnt++;
            end else begin
                $display("[PASS] GET_COARSE = %0d", value);
            end
        end
    endtask

    task automatic test_set_get_coarse(input logic [31:0] delay_val);
        logic [31:0] value;
        logic ok;
        $display("\n[TEST] SET_COARSE(%0d) then GET_COARSE", delay_val);
        send_cmd_4byte(`CMD_SET_COARSE, delay_val);
        // Small delay for processing
        repeat(100) @(posedge clk_200m);
        send_cmd(`CMD_GET_COARSE);
        receive_4bytes(value, ok);
        if (ok) begin
            if (value !== delay_val) begin
                $error("SET/GET_COARSE: Expected %0d, got %0d", delay_val, value);
                error_cnt++;
            end else begin
                $display("[PASS] SET/GET_COARSE = %0d", value);
            end
        end
    endtask

    task automatic test_set_get_edge(input logic [1:0] edge_val);
        logic [7:0] value;
        logic ok;
        $display("\n[TEST] SET_EDGE(%0d) then GET_EDGE", edge_val);
        send_cmd_1byte(`CMD_SET_EDGE, {6'b0, edge_val});
        repeat(100) @(posedge clk_200m);
        send_cmd(`CMD_GET_EDGE);
        receive_byte(value, ok);
        if (ok) begin
            if (value[1:0] !== edge_val) begin
                $error("SET/GET_EDGE: Expected %0d, got %0d", edge_val, value[1:0]);
                error_cnt++;
            end else begin
                $display("[PASS] SET/GET_EDGE = %0d", value[1:0]);
            end
        end
    endtask

    task automatic test_arm_disarm();
        logic [7:0] value;
        logic ok;

        $display("\n[TEST] ARM/DISARM sequence");

        // Check initial state (should be disarmed)
        send_cmd(`CMD_GET_ARMED);
        receive_byte(value, ok);
        if (ok && value[0] !== 1'b0) begin
            $error("Initial armed state should be 0, got %0d", value[0]);
            error_cnt++;
        end

        // ARM
        send_cmd(`CMD_ARM);
        repeat(100) @(posedge clk_200m);

        // Verify armed
        send_cmd(`CMD_GET_ARMED);
        receive_byte(value, ok);
        if (ok) begin
            if (value[0] !== 1'b1) begin
                $error("After ARM, armed should be 1, got %0d", value[0]);
                error_cnt++;
            end else begin
                $display("[PASS] ARM successful");
            end
        end

        // DISARM
        send_cmd(`CMD_DISARM);
        repeat(100) @(posedge clk_200m);

        // Verify disarmed
        send_cmd(`CMD_GET_ARMED);
        receive_byte(value, ok);
        if (ok) begin
            if (value[0] !== 1'b0) begin
                $error("After DISARM, armed should be 0, got %0d", value[0]);
                error_cnt++;
            end else begin
                $display("[PASS] DISARM successful");
            end
        end
    endtask

    task automatic test_trigger_mode();
        logic [7:0] value;
        logic ok;

        $display("\n[TEST] TRIGGER_MODE set/get");

        // Set to INTERNAL mode
        send_cmd_1byte(`CMD_SET_TRIGGER_MODE, 8'h01);
        repeat(100) @(posedge clk_200m);

        send_cmd(`CMD_GET_TRIGGER_MODE);
        receive_byte(value, ok);
        if (ok) begin
            if (value[0] !== 1'b1) begin
                $error("TRIGGER_MODE: Expected INTERNAL(1), got %0d", value[0]);
                error_cnt++;
            end else begin
                $display("[PASS] TRIGGER_MODE = INTERNAL");
            end
        end

        // Set back to EXTERNAL mode
        send_cmd_1byte(`CMD_SET_TRIGGER_MODE, 8'h00);
        repeat(100) @(posedge clk_200m);

        send_cmd(`CMD_GET_TRIGGER_MODE);
        receive_byte(value, ok);
        if (ok) begin
            if (value[0] !== 1'b0) begin
                $error("TRIGGER_MODE: Expected EXTERNAL(0), got %0d", value[0]);
                error_cnt++;
            end else begin
                $display("[PASS] TRIGGER_MODE = EXTERNAL");
            end
        end
    endtask

    task automatic test_get_status();
        logic [7:0] byte_val;
        logic ok;
        logic [15:0] trigger_count;
        logic [31:0] coarse_delay, fine_offset, coarse_width, fine_width;
        logic armed, trigger_mode, armed_mode, counter_mode, mmcm_locked, phase_shift_ready;
        logic [1:0] edge_type;

        $display("\n[TEST] GET_STATUS (26 bytes)");
        send_cmd(`CMD_GET_STATUS);

        // Receive 26 bytes
        receive_byte(byte_val, ok); if (!ok) return; trigger_count[7:0] = byte_val;
        receive_byte(byte_val, ok); if (!ok) return; trigger_count[15:8] = byte_val;
        receive_byte(byte_val, ok); if (!ok) return; coarse_delay[7:0] = byte_val;
        receive_byte(byte_val, ok); if (!ok) return; coarse_delay[15:8] = byte_val;
        receive_byte(byte_val, ok); if (!ok) return; coarse_delay[23:16] = byte_val;
        receive_byte(byte_val, ok); if (!ok) return; coarse_delay[31:24] = byte_val;
        receive_byte(byte_val, ok); if (!ok) return; fine_offset[7:0] = byte_val;
        receive_byte(byte_val, ok); if (!ok) return; fine_offset[15:8] = byte_val;
        receive_byte(byte_val, ok); if (!ok) return; fine_offset[23:16] = byte_val;
        receive_byte(byte_val, ok); if (!ok) return; fine_offset[31:24] = byte_val;
        receive_byte(byte_val, ok); if (!ok) return; coarse_width[7:0] = byte_val;
        receive_byte(byte_val, ok); if (!ok) return; coarse_width[15:8] = byte_val;
        receive_byte(byte_val, ok); if (!ok) return; coarse_width[23:16] = byte_val;
        receive_byte(byte_val, ok); if (!ok) return; coarse_width[31:24] = byte_val;
        receive_byte(byte_val, ok); if (!ok) return; fine_width[7:0] = byte_val;
        receive_byte(byte_val, ok); if (!ok) return; fine_width[15:8] = byte_val;
        receive_byte(byte_val, ok); if (!ok) return; fine_width[23:16] = byte_val;
        receive_byte(byte_val, ok); if (!ok) return; fine_width[31:24] = byte_val;
        receive_byte(byte_val, ok); if (!ok) return; armed = byte_val[0];
        receive_byte(byte_val, ok); if (!ok) return; trigger_mode = byte_val[0];
        receive_byte(byte_val, ok); if (!ok) return; armed_mode = byte_val[0];
        receive_byte(byte_val, ok); if (!ok) return; counter_mode = byte_val[0];
        receive_byte(byte_val, ok); if (!ok) return; mmcm_locked = byte_val[0];
        receive_byte(byte_val, ok); if (!ok) return; phase_shift_ready = byte_val[0];
        receive_byte(byte_val, ok); if (!ok) return; edge_type = byte_val[1:0];
        receive_byte(byte_val, ok); if (!ok) return; // reserved

        $display("[PASS] GET_STATUS: trig_cnt=%0d, delay=%0d, fine_off=%0d, width=%0d, fine_w=%0d",
                 trigger_count, coarse_delay, $signed(fine_offset), coarse_width, $signed(fine_width));
        $display("       armed=%0d, trig_mode=%0d, arm_mode=%0d, cnt_mode=%0d, locked=%0d, ps_ready=%0d, edge=%0d",
                 armed, trigger_mode, armed_mode, counter_mode, mmcm_locked, phase_shift_ready, edge_type);
    endtask

    task automatic test_output_width();
        logic [31:0] value;
        logic ok;

        $display("\n[TEST] OUTPUT_TRIGGER_WIDTH set/get");

        // Set width to 20 cycles (100ns @ 200MHz)
        send_cmd_4byte(`CMD_SET_OUTPUT_TRIGGER_WIDTH, 32'd20);
        repeat(100) @(posedge clk_200m);

        send_cmd(`CMD_GET_OUTPUT_TRIGGER_WIDTH);
        receive_4bytes(value, ok);
        if (ok) begin
            if (value !== 32'd20) begin
                $error("OUTPUT_WIDTH: Expected 20, got %0d", value);
                error_cnt++;
            end else begin
                $display("[PASS] OUTPUT_WIDTH = %0d", value);
            end
        end
    endtask

    task automatic test_fine_offset();
        logic [31:0] value;
        logic ok;

        $display("\n[TEST] FINE_OFFSET set/get");

        // Set fine offset to 100 steps
        send_cmd_4byte(`CMD_SET_FINE_OFFSET, 32'd100);

        // Wait for phase shifting to complete (may take many cycles)
        repeat(20000) @(posedge clk_200m);

        send_cmd(`CMD_GET_FINE_OFFSET);
        receive_4bytes(value, ok);
        if (ok) begin
            if (value !== 32'd100) begin
                $error("FINE_OFFSET: Expected 100, got %0d", value);
                error_cnt++;
            end else begin
                $display("[PASS] FINE_OFFSET = %0d", value);
            end
        end
    endtask

    //-------------------------------------------------------------------------
    // Main Test Sequence
    //-------------------------------------------------------------------------
    initial begin
        $display("========================================");
        $display("TRIGGER_DELAY_TOP Integration Testbench");
        $display("========================================");
        $display("Using UART_TX/RX for communication");
        $display("Clock: 100MHz input -> 200MHz internal");
        $display("Baud: %0d", BAUD_RATE);

        error_cnt = 0;

        // Initialize signals
        rst = 1;
        trigger_in = 0;
        stim_tx_en = 0;
        stim_tx_data = 8'h00;

        // Hold reset
        repeat(100) @(posedge clk_100m);
        rst = 0;

        // Wait for MMCM lock
        wait_for_mmcm_lock(1000);  // 1ms timeout

        // Additional settling time after MMCM lock
        repeat(1000) @(posedge clk_200m);

        // Run tests
        test_get_coarse();
        test_set_get_coarse(32'd100);
        test_set_get_coarse(32'd12345);
        test_set_get_edge(`EDGE_RISING);
        test_set_get_edge(`EDGE_FALLING);
        test_set_get_edge(`EDGE_BOTH);
        test_arm_disarm();
        test_trigger_mode();
        test_get_status();
        test_output_width();
        test_fine_offset();

        // Summary
        repeat(1000) @(posedge clk_200m);
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
        #50ms;
        $error("Testbench timeout!");
        $finish;
    end

endmodule
