`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: ab Systems
// Engineer: Al Baeza
// 
// Create Date: 06/18/2025
// Design Name: abCore16 Top Level
// Module Name: cpu_tl
// Project Name: abCore16
// Target Devices: Xilinx FPGA
// Tool Versions: Vivado
// Description: 
// Top-level module for the abCore16 CPU. This version is updated to correctly
// instantiate the original DP-centric datapath and a compatible control unit.
//
// Revision:
// Revision 1.1 - Corrected connections for the reverted DP-centric architecture.
// Additional Comments:
// The architecture is now DP-centric. The Datapath fetches and latches 
// instruction bytes into its IRs and provides them to the Control Unit.
//
// abCore16 Memory Map
// Memory = 0x2000 (8192)
// Code space = 0 - 0x1000 (0 - 4096)
// Memory for arrays = 0x1000 (4096) Grows up
// Memory-mapped IO base address = 0x1800 - 0x1900 (6,144 - 6,400)
// Stack base = 0x2000 - 2 = 0x1ffe (8190) Grows down to 0x190 (6,400)
//
//////////////////////////////////////////////////////////////////////////////////
import timer_uart_reg_pkg::*;

`include "defines.svh"

// For Synthesis, comment out both defines
`define MEMORYMODELSIM    // use hex file
`define SIMSPEEDUPCLK     // use Testbench 12MHz clock

// --- FOR SIMULATION: Use a fast, behavioral memory model ---
// Remember: Must add new coe and hex files to abCore16 project as Coefficient 
// and Memory Files!!
// .ab Programs
// `define IMEM_HEX_FILE "myProg_add.hex" // << CHANGE THIS TO YOUR TEST PROGRAM
//`define IMEM_HEX_FILE "myProg_generic.hex" // Comprehensive Test (.ab)
//`define IMEM_HEX_FILE "myProg_loadi.hex" // Comprehensive Test (.ab)
// SAL Programs
//`define IMEM_HEX_FILE "test_func.hex"  // Test STORFR, LOADFR
// SSL Programs: C-like with main()
//`define IMEM_HEX_FILE "test_program_short.hex"  // several C-Like features
//`define IMEM_HEX_FILE "test_arrays.hex"  // arrays
//`define IMEM_HEX_FILE "test_forLp.hex"  // for Loop
//`define IMEM_HEX_FILE "test_mmio.hex"  // memory-mapped I/O
//`define IMEM_HEX_FILE "test_pointers.hex"  // C-like pointers
//`define IMEM_HEX_FILE "test_postfix.hex"  // p++ and p--
//`define IMEM_HEX_FILE "test_new_features.hex"  // p++ and p--, else if, switch
//`define IMEM_HEX_FILE "test_blink.hex"  // blink LED using SW counters
`define IMEM_HEX_FILE "test_timer.hex"  // blink LED using HW timer


module cpu_tl (
    input  logic clk_12MHz,
    input  logic rst_in,

    // GPIO Interface
//    input  logic [`DATA_WIDTH-1:0] gpio_in_i,  // for now reduce pin count
    output logic [`DATA_WIDTH-1:0] gpio_out_o,
    output logic                   gpio_out_we_o,
    // UART
    output logic                   uart_tx_o,
    input  logic                   uart_rx_i,
    input  logic                   tx_trigger_btn_i, // From a push-button to send a test byte 
    // CPU halt flag
    output logic                   halted_o,
    output logic                   led2_o,
    output logic                   led3_o
);

//================================================================
// Internal parameters and signals
//================================================================
// UART parameters
localparam CLK50_FREQ = 50_000_000;
localparam UART_DATA_BITS = 8;
localparam BAUD_RATE = 9600;

// Memory = 0x2000 (8192)
// Code space = 0 - 0x1000 (0 - 4096)
// Memory for arrays = 0x1000 (4096) Grows up
// Memory-mapped IO base address = 0x1800 - 0x1900 (6,144 - 6,400)
// Stack base = 0x2000 - 2 = 0x1ffe (8190) Grows down to 0x190 (6,400)
  localparam ADDRESS_BASE            = 16'h1800;
  localparam ADDRESS_TIMER_CTRL      = 16'h1800;
  localparam ADDRESS_TIMER_PRESCALE  = 16'h1802;
  localparam ADDRESS_TIMER_RELOAD_L  = 16'h1804;
  localparam ADDRESS_TIMER_RELOAD_H  = 16'h1806;
  localparam ADDRESS_TIMER_COUNT_L   = 16'h1808;
  localparam ADDRESS_TIMER_COUNT_H   = 16'h180A;
  localparam ADDRESS_TIMER_STATUS    = 16'h180C;
  localparam ADDRESS_UART_CTRL       = 16'h1810;
  localparam ADDRESS_UART_STATUS     = 16'h1812;
  localparam ADDRESS_UART_TX_DATA    = 16'h1814;
  localparam ADDRESS_UART_RX_DATA    = 16'h1816;
  localparam ADDRESS_LED_CTRL        = 16'h1818;
  
//  localparam REGISTER_COUNT = 12;
//  localparam REGISTER_DWIDTH = 16;
//  localparam ADDRESS_WIDTH = 5;
  

// Instruction Memory Interface
logic [`ADDR_WIDTH-1:0] imem_addr_o;    // Address to Instruction Memory (driven by DP's PC)
logic [7:0]             imem_rdata_i;   // Data from Instruction Memory (read by DP)
// Data Memory Interface
logic                   dmem_we_o;      // Data memory write enable
logic [`ADDR_WIDTH-1:0] dmem_addr_o;    // Data memory address bus
logic [`DATA_WIDTH-1:0] dmem_wdata_o;   // Data memory data bus
logic [`DATA_WIDTH-1:0] dmem_rdata_i;   // Data from memory (BRAM)
// UART
//logic [UART_DATA_BITS-1:0] tx_data;
//logic                 tx_start;
//logic                 tx_busy;
//logic [UART_DATA_BITS-1:0] rx_data;
//logic                 rx_data_valid;
//logic                 rx_frame_error;

// Register map instance
register_map_t reg_map;
// Memory-mapped Registers
//logic [15:0] mmio_wr_data;
logic [15:0] mmio_rd_data;
logic [`ADDR_WIDTH-1:0]  mmio_addr;     // Register address (word aligned)
//logic        wr_en;         // Write enable
logic        mmio_rden;         // Read enable
logic        mmio_rd_valid;      // currently not used

logic memorymap_range;
logic [15:0] dmem_rdata;

// Timer internal signals
logic [15:0] prescale_counter;
logic        prescale_tick;
logic [31:0] counter_reg;
logic        timer_running;
logic        timeout_internal;
logic        overflow_internal;

// UART signals
logic [UART_DATA_BITS-1:0]  tx_data;
logic        tx_start;
logic        tx_busy;
logic [UART_DATA_BITS-1:0]  rx_data;
logic        rx_data_valid;
logic        rx_frame_error;

logic        tx_start_btn;
logic        tx_start_combo;

// Extract uart control signals from structured register
assign tx_data = reg_map.uart_tx_data.data;
assign tx_start = reg_map.uart_ctrl.tx_start;




// To rduce pin count for development board assign gpio_in_i here.
logic [`DATA_WIDTH-1:0] gpio_in_i;
assign gpio_in_i = gpio_out_o;
    
    
//================================================================
// Conditional Clock Module Instantiation
//================================================================
// To speedup simulation, use the 12MHz clock directly from the testbench
// instead of using the MMCM clock module that takes tens of uSeconds to
// lock.
logic rst_n;
logic locked;

`ifdef SIMSPEEDUPCLK
// --- FOR SIMULATION: Use the Testbench 12MHz clock ---
assign clk = clk_12MHz;
assign rst_n = !rst_in;
assign locked = 1'b1;

`else
// --- FOR SYNTHESIS: Use the real MMCM IP Core ---
clk_wiz_0 abCore16_clk (
    // Clock and pushbutton reset
    .clk_in1   (clk_12MHz ),  // input clk_in1
    .reset     (rst_in),      // input reset; pushbutton
    // outputs
    .clk_out1  (clk),         // 50 MHz
    .locked    (locked)       // clk locked
);

assign rst_n = locked;
`endif


//================================================================
// Module Instantiations
//================================================================
// abCore16 microprocessor core
core core01 (
    .clk           (clk),
    .rst_n         (rst_n),
    // Instruction Memory Interface
    .imem_addr_o   (imem_addr_o),    // Address to Instruction Memory (driven by DP's PC)
    .imem_rdata_i  (imem_rdata_i),   // Data from Instruction Memory (read by DP)
    // Data Memory Interface
    .dmem_we_o     (dmem_we_o),      // Data memory write enable
    .dmem_addr_o   (dmem_addr_o),    // Data memory address bus
    .dmem_wdata_o  (dmem_wdata_o),   // Data memory data bus
//    .dmem_rdata_i  (dmem_rdata_i),   // Data from memory (BRAM)
    .dmem_rdata_i  (dmem_rdata),   // Data from BRAM or Memory-mapped IO
    // GPIO Interface
    .gpio_out_o    (gpio_out_o),
    .gpio_out_we_o (gpio_out_we_o),   
    // CPU halt flag
    .halted_o      (halted_o)
);

// Memory-mapped IO between 0x1800 and 0x1900 (6144 and 6400)
assign memorymap_range = ( dmem_addr_o>=6144 && dmem_addr_o<6400 );
// Mux to select between BRAM data and Memory-mapped IO
always_comb begin
    if (memorymap_range) begin
        dmem_rdata = mmio_rd_data;
    end
    else begin
        dmem_rdata = dmem_rdata_i;
    end
end

// ************
// UART
// ************
// UART with programmable BAUD rate.
uart_mn #(
    // Parameters are passed to the instance here
    .CLK_FREQ(CLK50_FREQ),
    .DATA_BITS(UART_DATA_BITS),    // Explicitly pass DATA_BITS
    .BAUD_RATE(BAUD_RATE)          // Explicitly pass BAUD_RATE
) uart01 (
    // Ports are connected to signals here
    .i_clk             (clk),
    .i_rst_n           (rst_n),
    // The i_baud_divider input port is tied to a constant value
    // because it is unused by the baud rate generator logic.
    .i_baud_divider    (16'b0),
    .i_tx_data         (tx_data),         // 8-bit TX data, memory-mapped register
//    .i_tx_start        (tx_start),        // memory-mapped control
    .i_tx_start        (tx_start_combo),  // memory-mapped or pushbutton
    .o_tx_busy         (tx_busy),         // TX busy status
    .o_rx_data         (rx_data),         // 8-bit RX data, memory-mapped register
    .o_rx_data_valid   (rx_data_valid),   // RX data valid status
    .o_rx_frame_error  (rx_frame_error),  // RX error status
    .o_uart_tx         (uart_tx_o),       // serial TX, output
    .i_uart_rx         (uart_rx_i)        // serial RX, input
);

// TX start combination
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_start_combo <= 1'b0;
    end else begin
        tx_start_combo <= tx_start | tx_start_btn;
    end
end

//================================================================
// Timer
//================================================================
// Timer logic using structured registers
logic [31:0] reload_value;
assign reload_value = {reg_map.timer_reload_h, reg_map.timer_reload_l};

// Prescaler logic
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        prescale_counter <= 16'h0;
        prescale_tick <= 1'b0;
    end else begin
        prescale_tick <= 1'b0;
        if (reg_map.timer_ctrl.prescale_en && timer_running) begin
            if (prescale_counter >= reg_map.timer_prescale) begin  // 50,000 (0xc350) = 1 mSec
                prescale_counter <= 16'h0;
                prescale_tick <= 1'b1;
            end else begin
                prescale_counter <= prescale_counter + 1'b1;
            end
        end else if (timer_running) begin
            prescale_tick <= 1'b1;  // No prescaling, tick every clock
        end
    end
end

// Rising edge detector
//logic [1:0] timrun_sht;
//logic       timer_running_redge;
//always_ff @(posedge clk or negedge rst_n) begin
//    if (!rst_n) begin
//        timrun_sht          <= 2'b00;
//        timer_running_redge <= 1'b0;
//    end else begin
//        timrun_sht          <= { timrun_sht[0], timer_running };
//        timer_running_redge <= timrun_sht[0] & !timrun_sht[1];        
//    end
//end



// Main timer counter
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        counter_reg <= 32'h0;
        timeout_internal <= 1'b0;
        overflow_internal <= 1'b0;
        timer_running <= 1'b0;
    end else begin
        timeout_internal <= 1'b0;
        
 //       if (reg_map.timer_ctrl.reset | timer_running_redge) begin
        if (reg_map.timer_ctrl.reset) begin
            counter_reg <= reload_value;
            timeout_internal <= 1'b0;
            overflow_internal <= 1'b0;
            timer_running <= 1'b0;
        end else if (reg_map.timer_ctrl.enable) begin
            timer_running <= 1'b1;
            
            if (prescale_tick) begin
                if (counter_reg == 32'h0) begin
                    timeout_internal <= 1'b1;
                    
                    if (reg_map.timer_ctrl.mode) begin
                        // Continuous mode - reload counter
                        counter_reg <= reload_value;
                    end else begin
                        // One-shot mode - stop timer
                        timer_running <= 1'b0;
                    end
                end else begin
                    counter_reg <= counter_reg - 1'b1;
                end
                
                // Check for overflow
                if (counter_reg == 32'hFFFFFFFF) begin
                    overflow_internal <= 1'b1;
                end
            end
        end else begin
            timer_running <= 1'b0;
        end
    end
end

//================================================================
// Memory-mapped Registers
//================================================================

//assign mmio_wr_data = dmem_wdata_o;
//assign dmem_rdata_i = rd_data;
//assign wr_en = dmem_we_o;
assign mmio_rden = 1'b1;
assign mmio_addr = dmem_addr_o;   // TODO: increase addr length

// Register write logic using structured approach
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // Initialize all registers
        reg_map.timer_ctrl <= '0;
        reg_map.timer_prescale <= '0;
        reg_map.timer_reload_l <= '0;
        reg_map.timer_reload_h <= '0;
        reg_map.uart_ctrl <= '0;
        reg_map.uart_tx_data <= '0;
        reg_map.led_ctrl <= '0;
    end else begin
        // Auto-clear control bits
        if (reg_map.timer_ctrl.reset) begin
            reg_map.timer_ctrl.reset <= 1'b0;
        end
        if (reg_map.uart_ctrl.tx_start) begin
            reg_map.uart_ctrl.tx_start <= 1'b0;
        end
        if (reg_map.uart_ctrl.reset_flags) begin
            reg_map.uart_ctrl.reset_flags <= 1'b0;
        end
        
        // Handle register writes
        if (dmem_we_o && !is_read_only(mmio_addr)) begin
            case (mmio_addr)
                ADDRESS_TIMER_CTRL: begin
                    reg_map.timer_ctrl <= dmem_wdata_o;
                end
                ADDRESS_TIMER_PRESCALE: begin
                    reg_map.timer_prescale <= dmem_wdata_o;
                end
                ADDRESS_TIMER_RELOAD_L: begin
                    reg_map.timer_reload_l <= dmem_wdata_o;
                end
                ADDRESS_TIMER_RELOAD_H: begin
                    reg_map.timer_reload_h <= dmem_wdata_o;
                end
//                ADDRESS_TIMER_STATUS: begin
//                    // Clear-on-write for status flags
//                    if (dmem_wdata_o[0]) reg_map.timer_status.timeout <= 1'b0;
//                    if (dmem_wdata_o[1]) reg_map.timer_status.overflow <= 1'b0;
//                end
                ADDRESS_UART_CTRL: begin
                    reg_map.uart_ctrl <= dmem_wdata_o;
                end
                ADDRESS_UART_TX_DATA: begin
                    reg_map.uart_tx_data <= dmem_wdata_o;
                end
                ADDRESS_LED_CTRL: begin
                    reg_map.led_ctrl <= dmem_wdata_o;
                end                
                
                default: begin
                    // Invalid or read-only address
                end
            endcase
        end
    end
end

// Update read-only and status registers
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        reg_map.timer_count_l   <= '0;
        reg_map.timer_count_h   <= '0;
        reg_map.timer_status    <= '0;
        reg_map.uart_status     <= '0;
        reg_map.uart_rx_data    <= '0;
    end else begin
        // Update timer count registers
        reg_map.timer_count_l <= counter_reg[15:0];
        reg_map.timer_count_h <= counter_reg[31:16];
        
        // Update timer status
        if (timeout_internal) begin
            reg_map.timer_status.timeout <= 1'b1;
        end
        if (overflow_internal) begin
            reg_map.timer_status.overflow <= 1'b1;
        end
        reg_map.timer_status.running <= timer_running;
        
        // clear timeout
        if (dmem_we_o && is_read_only(mmio_addr)) begin
            case (mmio_addr)
                ADDRESS_TIMER_STATUS: begin
                    // Clear-on-write for status flags
                    if (dmem_wdata_o[0]) reg_map.timer_status.timeout <= 1'b0; 
                    if (dmem_wdata_o[1]) reg_map.timer_status.overflow <= 1'b0;
                end
                default: begin
                    // Invalid or read-only address
                end
            endcase
        end 
        
        
        // Update UART status
        reg_map.uart_status.tx_busy <= tx_busy;
        reg_map.uart_status.rx_valid <= rx_data_valid;
        reg_map.uart_status.rx_error <= rx_frame_error;
        
        // Capture RX data
        if (rx_data_valid) begin
            reg_map.uart_rx_data.data <= rx_data;
            reg_map.uart_rx_data.reserved <= 8'h00;
        end
        
        // Clear UART flags if requested
        if (reg_map.uart_ctrl.reset_flags) begin
            reg_map.uart_status.rx_valid <= 1'b0;
            reg_map.uart_status.rx_error <= 1'b0;
        end
    end
end

// Register read logic using structured approach
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mmio_rd_data <= 16'h0;
        mmio_rd_valid <= 1'b0;
    end 
    else begin
        mmio_rd_valid <= mmio_rden;
        
        if (mmio_rden) begin
            case (mmio_addr)
                ADDRESS_TIMER_CTRL:     mmio_rd_data <= reg_map.timer_ctrl;
                ADDRESS_TIMER_PRESCALE: mmio_rd_data <= reg_map.timer_prescale;
                ADDRESS_TIMER_RELOAD_L: mmio_rd_data <= reg_map.timer_reload_l;
                ADDRESS_TIMER_RELOAD_H: mmio_rd_data <= reg_map.timer_reload_h;
                ADDRESS_TIMER_COUNT_L:  mmio_rd_data <= reg_map.timer_count_l;
                ADDRESS_TIMER_COUNT_H:  mmio_rd_data <= reg_map.timer_count_h;
                ADDRESS_TIMER_STATUS:   mmio_rd_data <= reg_map.timer_status;
                ADDRESS_UART_CTRL:      mmio_rd_data <= reg_map.uart_ctrl;
                ADDRESS_UART_STATUS:    mmio_rd_data <= reg_map.uart_status;
                ADDRESS_UART_TX_DATA:   mmio_rd_data <= reg_map.uart_tx_data;
                ADDRESS_UART_RX_DATA:   mmio_rd_data <= reg_map.uart_rx_data;
                ADDRESS_LED_CTRL:       mmio_rd_data <= reg_map.led_ctrl;
                default:                mmio_rd_data <= 16'h0;
            endcase
        end
    end
end

// Output assignments
//assign timeout = timeout_internal;
//assign overflow = overflow_internal;


//================================================================
// UART Stimulus and LED Logic
//================================================================
// Simple test: Send the character 'X' (ASCII 0x58) when the button is pressed.
// The unsized literal will be correctly sized to DATA_BITS by the compiler.
//assign tx_data = 'h59;

// Edge detector for the button press to create a single-cycle start pulse
logic tx_trigger_d1, tx_trigger_d2;
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_trigger_d1 <= 1'b0;
        tx_trigger_d2 <= 1'b0;
    end else begin
        tx_trigger_d1 <= tx_trigger_btn_i;
        tx_trigger_d2 <= tx_trigger_d1;
    end
end
    
// Pulse tx_start for one clock cycle when the button is pressed.
assign tx_start_btn = (tx_trigger_d1 & ~tx_trigger_d2);

// Connect status signals directly to LEDs
//assign o_led_tx_busy  = tx_busy;
//assign o_led_rx_valid = rx_data_valid;
//assign o_led_rx_error = rx_frame_error;



//================================================================
// Conditional Memory Instantiation (`generate` block)
//================================================================
`ifdef MEMORYMODELSIM
    
    initial begin
        $display("INFO: Compiling with SIMULATION behavioral memory model.");
        $display("INFO: Loading instruction memory from '%s'.", `IMEM_HEX_FILE);
    end

    // Behavioral Instruction and Data Memory
    logic [7:0] instruction_memory [0:`INSTRUCTION_MEMORY_BYTES-1];
    logic [`DATA_WIDTH-1:0] data_memory [0: (`DATA_MEMORY_BYTES/2)-1]; // Corrected indexing for word array

    initial $readmemh(`IMEM_HEX_FILE, instruction_memory);

    // Read from Instruction and Data memory.
    // One clock latency to match BRAM behavior
    always_ff @(posedge clk) begin
        imem_rdata_i  <= instruction_memory[imem_addr_o];    // no addr to dout dly
        dmem_rdata_i = data_memory[dmem_addr_o >> 1];
    end
    
    // Write to Data memory
    always_ff @(posedge clk) begin
        if (dmem_we_o) begin
            data_memory[dmem_addr_o >> 1] <= dmem_wdata_o;
//            instruction_memory[dmem_addr_o >> 1] <= dmem_wdata_o;   // imem is a ROM, don't write to imem
        end
    end
    
`else
    // --- FOR SYNTHESIS: Use the real BRAM IP Core ---
    initial begin
        $display("INFO: Compiling with SYNTHESIS BRAM IP Core model.");
    end
    
    // Create a wire for the word-aligned data memory address
    logic [`ADDR_WIDTH-2:0] dmem_word_addr;
    
    // Convert the byte address from the CPU to a word address for the BRAM
    // by right-shifting by one (equivalent to dropping the LSB).
    assign dmem_word_addr = dmem_addr_o >> 1;

    // Program Memory IP Core
    // NOTE: instruction memory access is 8-bits while 
    //       data memory access is 16-bits
    abCore16_blk_mem cpu_mem (
        // Instruction Memory Interface
        .clka   ( clk ),
        .ena    ( 1'b1 ),
        .wea    ( 1'b0 ),       // ROM
        .addra  ( imem_addr_o[12:0] ),
        .dina   ( 9'b0 ),       // ROM
        .douta  ( imem_rdata_i ),   // 8-bits
        // Data Memory Interface
        .clkb   ( clk ),
        .enb    ( 1'b1 ),
        .web    ( dmem_we_o ),
        .addrb  ( {1'b0,dmem_word_addr} ), // THE FIX: Connect the corrected word address
        .dinb   ( {2'b00, dmem_wdata_o} ),
        .doutb  ( dmem_rdata_i )    // 16-bits
    );

`endif
    
// ***************************************************************
// 
// ***************************************************************
// Blink LED
// blink counter
// Using MMCM generated clock
logic [24:0] count = '0;

always_ff@(posedge clk) begin
   if(!rst_n) begin // Synthesis tools correctly infer an async reset here
       count <= '0; 
   end
   else begin 
       count <= count + 1; 
   end
end

assign led2_o = count[22];

// Use abCore16 software counters to toggle LED
// Memory-mapped I/O for LED control
logic led3;
always_ff@(posedge clk) begin
   if(!rst_n) begin 
       led3_o <= 1'b0; 
       led3   <= 1'b0;
   end
   else begin 
       // LED mapped-mapped IO address = 0x1800 (6144)
//       if ( (dmem_we_o == 1'b1) &&  (dmem_addr_o == 6144) ) begin  // 0x1800
       if ( (dmem_we_o == 1'b1) &&  (dmem_addr_o == 6168) ) begin  // 0x1818
         if ( dmem_wdata_o == 0 ) begin 
             led3_o <= 1'b0;              // turn off LED
             led3   <= 1'b0;
         end
         else begin 
             led3_o <= 1'b1;              // turn on LED
             led3   <= 1'b1;
         end
       end 
   end
end

//----------- ILA INSTANTIATION  ---
//logic [17:0] probe0;
//assign probe0[17:0] = { gpio_out_o, gpio_out_we_o, led3 };

logic [31:0] probe0;
assign probe0[31:0] = { dmem_addr_o,dmem_wdata_o, dmem_we_o, led3_o };

ila_0 ab_ILA (
	.clk     (clk),   // input wire clk
	.probe0  (probe0) // input wire [31:0] probe0
);


endmodule
