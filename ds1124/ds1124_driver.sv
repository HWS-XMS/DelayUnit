//-----------------------------------------------------------------------------
// DS1124 8-Bit Programmable Delay Line Driver
//-----------------------------------------------------------------------------
// This module provides a SystemVerilog interface to control the DS1124
// programmable delay IC via its 3-wire serial interface.
//
// IMPORTANT: The DS1124 operates at 5V logic levels. Level shifters are
// required when interfacing with 3.3V or 1.8V FPGA I/O banks. This includes:
// - Control signals (CLK, D, E, Q)
// - The actual signal path (IN/OUT pins for the signal being delayed)
//
// Features:
// - 8-bit delay control (0-255 steps, 0.25ns per step)
// - 3-wire serial interface (CLK, D, E)
// - Configurable clock divider for serial clock generation
// - Optional readback support for verifying programmed values
//
//-----------------------------------------------------------------------------

module ds1124_driver #(
    parameter int SYS_CLK_FREQ = 100_000_000,  // System clock frequency in Hz
    parameter int CLK_DIV      = 4,            // System clock divider for serial clock (minimum: 2)
    parameter bit READBACK_EN  = 1             // Enable readback functionality
)(
    // System interface
    input  logic        clk,            // System clock
    input  logic        rst,            // Active-high reset
    input  logic [7:0]  delay_value,    // Desired delay value (0-255)
    input  logic        en,             // Enable programming
    output logic        ready,          // Ready for new command
    
    // DS1124 hardware interface
    output logic        ds1124_clk,     // Serial clock to DS1124
    output logic        ds1124_d,       // Serial data to DS1124
    output logic        ds1124_e,       // Enable signal to DS1124
    input  logic        ds1124_q,       // Serial data from DS1124
    
    // Optional readback interface
    input  logic        read_delay,     // Request current delay reading
    output logic [7:0]  current_delay,  // Read delay value
    output logic        read_valid      // Read data valid
);

    //-------------------------------------------------------------------------
    // State Machine Definition
    //-------------------------------------------------------------------------
    typedef enum {
        IDLE,
        SHIFT,
        LATCH,
        SETTLE,
        READ
    } state_t;
    
    state_t state, next_state;
    
    //-------------------------------------------------------------------------
    // Parameter Validation
    //-------------------------------------------------------------------------
    initial begin
        assert(CLK_DIV >= 2) 
        else $fatal("CLK_DIV must be >= 2 for proper clock generation (current value: %0d)", CLK_DIV);
    end
    
    //-------------------------------------------------------------------------
    // Settling Time Calculation (must be before signal declarations)
    //-------------------------------------------------------------------------
    localparam int SETTLE_TIME_US = 50;  // 50 microseconds per datasheet
    localparam int SETTLE_TIME = SYS_CLK_FREQ / 1_000_000 * SETTLE_TIME_US;  // Avoid overflow
    
    //-------------------------------------------------------------------------
    // Internal Signals
    //-------------------------------------------------------------------------
    logic [7:0]  shift_reg;             // Shift register for serial data
    logic [7:0]  read_reg;               // Register for readback data
    logic [2:0]  bit_cnt;                // Bit counter (0-7)
    logic [$clog2(CLK_DIV)-1:0] clk_div_cnt;  // Clock divider counter
    logic        clk_en;                 // Clock enable for serial interface
    logic [$clog2(SETTLE_TIME+1)-1:0] settle_cnt;  // Settling time counter (sized to exact requirement)
    logic        shift_done;             // All bits shifted
    logic        settle_done;            // Settling time complete
    
    //-------------------------------------------------------------------------
    // Clock Divider for Serial Clock
    //-------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            clk_div_cnt <= '0;
            clk_en      <= 1'b0;
        end else begin
            if (clk_div_cnt == CLK_DIV - 1) begin
                clk_div_cnt <= '0;
                clk_en      <= 1'b1;
            end else begin
                clk_div_cnt <= clk_div_cnt + 1'b1;
                clk_en      <= 1'b0;
            end
        end
    end
    
    //-------------------------------------------------------------------------
    // State Machine
    //-------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    always_comb begin
        next_state = state;
        
        case (state)
            IDLE: begin
                if (en) begin
                    next_state = SHIFT;
                end else if (READBACK_EN && read_delay) begin
                    next_state = READ;
                end
            end
            
            SHIFT: begin
                if (shift_done) begin
                    next_state = LATCH;
                end
            end
            
            LATCH: begin
                next_state = SETTLE;  // Immediate transition after latching
            end
            
            SETTLE: begin
                if (settle_done) begin
                    next_state = IDLE;
                end
            end
            
            READ: begin
                if (shift_done) begin
                    next_state = LATCH;  // Go through LATCH->SETTLE like SHIFT does
                end
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    //-------------------------------------------------------------------------
    // Shift Register and Bit Counter
    //-------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            shift_reg   <= 8'h00;
            read_reg    <= 8'h00;
            bit_cnt     <= 3'd0;
            shift_done  <= 1'b0;
        end else begin
            shift_done <= 1'b0;
            
            case (state)
                IDLE: begin
                    bit_cnt <= 3'd0;
                    if (en) begin
                        shift_reg <= delay_value;  // Load new value
                    end
                end
                
                SHIFT: begin
                    if (clk_en && clk_phase == 2'd3) begin  // Shift after full clock cycle
                        if (bit_cnt == 3'd7) begin
                            bit_cnt    <= 3'd0;
                            shift_done <= 1'b1;
                        end else begin
                            bit_cnt   <= bit_cnt + 1'b1;
                            shift_reg <= {shift_reg[6:0], 1'b0};  // Shift left (MSB first)
                        end
                    end
                end
                
                READ: begin
                    if (clk_en) begin
                        if (clk_phase == 2'd1) begin  // Sample Q on clock high
                            read_reg <= {read_reg[6:0], ds1124_q};  // Shift in read data
                        end else if (clk_phase == 2'd3) begin  // Update bit count after full cycle
                            if (bit_cnt == 3'd7) begin
                                bit_cnt    <= 3'd0;
                                shift_done <= 1'b1;
                            end else begin
                                bit_cnt <= bit_cnt + 1'b1;
                            end
                        end
                    end
                end
                
                default: begin
                    bit_cnt <= 3'd0;
                end
            endcase
        end
    end
    
    //-------------------------------------------------------------------------
    // Settling Time Counter (50us per DS1124 datasheet tEDV spec)
    //-------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            settle_cnt  <= '0;
            settle_done <= 1'b0;
        end else begin
            settle_done <= 1'b0;
            
            if (state == SETTLE) begin
                if (settle_cnt == SETTLE_TIME - 1) begin
                    settle_cnt  <= '0;
                    settle_done <= 1'b1;
                end else begin
                    settle_cnt <= settle_cnt + 1'b1;
                end
            end else begin
                settle_cnt <= '0;
            end
        end
    end
    
    //-------------------------------------------------------------------------
    // Clock Phase Counter for proper timing
    //-------------------------------------------------------------------------
    logic [1:0] clk_phase;  // 0: setup data, 1: clock high, 2: clock low, 3: hold
    
    always_ff @(posedge clk) begin
        if (rst || state == IDLE) begin
            clk_phase <= 2'd0;
        end else if ((state == SHIFT || state == READ) && clk_en) begin
            clk_phase <= (clk_phase == 2'd3) ? 2'd0 : clk_phase + 1'b1;
        end
    end
    
    //-------------------------------------------------------------------------
    // DS1124 Interface Outputs
    //-------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            ds1124_clk <= 1'b0;
            ds1124_d   <= 1'b0;
            ds1124_e   <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    ds1124_clk <= 1'b0;
                    ds1124_d   <= 1'b0;
                    ds1124_e   <= 1'b0;
                end
                
                SHIFT: begin
                    ds1124_e <= 1'b1;  // Enable high during shift
                    
                    if (clk_en) begin
                        case (clk_phase)
                            2'd0: begin  // Setup data
                                ds1124_d <= shift_reg[7];
                                ds1124_clk <= 1'b0;
                            end
                            2'd1: begin  // Clock high
                                ds1124_clk <= 1'b1;
                            end
                            2'd2: begin  // Clock low
                                ds1124_clk <= 1'b0;
                            end
                            2'd3: begin  // Hold before next bit
                                ds1124_clk <= 1'b0;
                            end
                        endcase
                    end
                end
                
                READ: begin
                    ds1124_e <= 1'b1;
                    
                    if (clk_en) begin
                        case (clk_phase)
                            2'd0: begin  // Setup data - write back Q to preserve register
                                ds1124_d <= ds1124_q;  // Write Q back to D
                                ds1124_clk <= 1'b0;
                            end
                            2'd1: begin  // Clock high
                                ds1124_clk <= 1'b1;
                            end
                            2'd2: begin  // Clock low
                                ds1124_clk <= 1'b0;
                            end
                            2'd3: begin  // Hold
                                ds1124_clk <= 1'b0;
                            end
                        endcase
                    end
                end
                
                LATCH: begin
                    ds1124_e   <= 1'b0;  // Latch on falling edge of E
                    ds1124_clk <= 1'b0;
                    ds1124_d   <= 1'b0;
                end
                
                SETTLE: begin
                    ds1124_e   <= 1'b0;
                    ds1124_clk <= 1'b0;
                    ds1124_d   <= 1'b0;
                end
                
                default: begin
                    ds1124_clk <= 1'b0;
                    ds1124_d   <= 1'b0;
                    ds1124_e   <= 1'b0;
                end
            endcase
        end
    end
    
    //-------------------------------------------------------------------------
    // Ready Signal
    //-------------------------------------------------------------------------
    always_comb begin
        ready = (state == IDLE);
    end
    
    //-------------------------------------------------------------------------
    // Readback Interface
    //-------------------------------------------------------------------------
    generate
        if (READBACK_EN) begin : gen_readback
            always_ff @(posedge clk) begin
                if (rst) begin
                    current_delay <= 8'h00;
                    read_valid    <= 1'b0;
                end else begin
                    read_valid <= 1'b0;
                    
                    if (state == READ && shift_done) begin
                        current_delay <= read_reg;
                        read_valid    <= 1'b1;
                    end
                end
            end
        end else begin : gen_no_readback
            assign current_delay = 8'h00;
            assign read_valid    = 1'b0;
        end
    endgenerate
    
endmodule