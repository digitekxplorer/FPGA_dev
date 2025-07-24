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
// Memory-mapped functionality has been extracted into a separate core_regs module.
//
// Revision:
// Revision 1.3 - Extracted memory-mapped registers into separate core_regs module
// Revision 1.2 - Extracted timer functionality into separate module
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
//`define MEMORYMODELSIM    // use hex file
//`define SIMSPEEDUPCLK     // use Testbench 12MHz clock

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
//`define IMEM_HEX_FILE "test_timer.hex"  // blink LED using HW timer
`define IMEM_HEX_FILE "test_uart.hex"  // UART at 9600 baud


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

// Instruction Memory Interface
logic [`ADDR_WIDTH-1:0] imem_addr_o;    // Address to Instruction Memory (driven by DP's PC)
logic [7:0]             imem_rdata_i;   // Data from Instruction Memory (read by DP)
// Data Memory Interface
logic                   dmem_we_o;      // Data memory write enable
logic [`ADDR_WIDTH-1:0] dmem_addr_o;    // Data memory address bus
logic [`DATA_WIDTH-1:0] dmem_wdata_o;   // Data memory data bus
logic [`DATA_WIDTH-1:0] dmem_rdata_i;   // Data from memory (BRAM)

// Memory-mapped Registers
logic [15:0] mmio_rd_data;
logic        mmio_rd_valid;      // currently not used

logic        memorymap_range;
logic [15:0] dmem_rdata;

// Timer signals (interface to timer module)
logic        timer_enable;
logic        timer_reset;
logic        timer_mode;
logic        timer_prescale_en;
logic [15:0] timer_prescale;
logic [31:0] timer_reload_value;
logic        timer_timeout;
logic        timer_overflow;
logic        timer_running;
logic [31:0] timer_count;

// UART signals
logic [UART_DATA_BITS-1:0]  uart_tx_data;
logic        uart_tx_start;
logic        uart_reset_flags;
logic        uart_tx_busy;
logic [UART_DATA_BITS-1:0]  uart_rx_data;
logic        uart_rx_data_valid;
logic        uart_rx_frame_error;

logic        tx_start_btn;
logic        uart_tx_start_combo;

// LED control signal
logic [15:0] led_ctrl;

// To reduce pin count for development board assign gpio_in_i here.
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
// UART RX sync
//================================================================
logic [1:0] uart_rx_shft;
logic       uart_rx_sync;
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        uart_rx_shft <= 2'b00;
    end else begin
        uart_rx_shft <= { uart_rx_shft[0], uart_rx_i };
    end
end

assign uart_rx_sync = uart_rx_shft[1];

//================================================================
// Memory-mapped IO range check and data mux
//================================================================
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
    .dmem_rdata_i  (dmem_rdata),     // Data from BRAM or Memory-mapped IO
    // GPIO Interface
    .gpio_out_o    (gpio_out_o),
    .gpio_out_we_o (gpio_out_we_o),   
    // CPU halt flag
    .halted_o      (halted_o)
);

//================================================================
// Memory-mapped Registers Module Instantiation
//================================================================
core_regs core_regs01 (
    .clk                    (clk),
    .rst_n                  (rst_n),
    
    // CPU Interface
    .dmem_we_i              (dmem_we_o),
    .dmem_addr_i            (dmem_addr_o),
    .dmem_wdata_i           (dmem_wdata_o),
    .mmio_rd_data_o         (mmio_rd_data),
    .mmio_rd_valid_o        (mmio_rd_valid),
    
    // Timer Interface
    .timer_enable_o         (timer_enable),
    .timer_reset_o          (timer_reset),
    .timer_mode_o           (timer_mode),
    .timer_prescale_en_o    (timer_prescale_en),
    .timer_prescale_o       (timer_prescale),
    .timer_reload_value_o   (timer_reload_value),
    .timer_timeout_i        (timer_timeout),
    .timer_overflow_i       (timer_overflow),
    .timer_running_i        (timer_running),
    .timer_count_i          (timer_count),
    
    // UART Interface
    .uart_tx_data_o         (uart_tx_data),
    .uart_tx_start_o        (uart_tx_start),
    .uart_reset_flags_o     (uart_reset_flags),
    .uart_tx_busy_i         (uart_tx_busy),
    .uart_rx_data_i         (uart_rx_data),
    .uart_rx_data_valid_i   (uart_rx_data_valid),
    .uart_rx_frame_error_i  (uart_rx_frame_error),
    
    // LED Interface
    .led_ctrl_o             (led_ctrl)
);

//================================================================
// Timer Module Instantiation
//================================================================
timer timer01 (
    .clk               (clk),
    .rst_n             (rst_n),
    // Control inputs
    .ctrl_enable       (timer_enable),
    .ctrl_reset        (timer_reset),
    .ctrl_mode         (timer_mode),
    .ctrl_prescale_en  (timer_prescale_en),
    .prescale_value    (timer_prescale),
    .reload_value      (timer_reload_value),
    // Status outputs
    .timeout_o         (timer_timeout),
    .overflow_o        (timer_overflow),
    .running_o         (timer_running),
    .count_o           (timer_count)
);

//================================================================
// UART Module Instantiation
//================================================================
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
    .i_tx_data         (uart_tx_data),        // 8-bit TX data, memory-mapped register
    .i_tx_start        (uart_tx_start_combo), // memory-mapped or pushbutton
    .o_tx_busy         (uart_tx_busy),        // TX busy status
    .o_rx_data         (uart_rx_data),        // 8-bit RX data, memory-mapped register
    .o_rx_data_valid   (uart_rx_data_valid),  // RX data valid status
    .o_rx_frame_error  (uart_rx_frame_error), // RX error status
    .o_uart_tx         (uart_tx_o),           // serial TX, output
    .i_uart_rx         (uart_rx_sync)            // serial RX, input
);

// TX start combination
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        uart_tx_start_combo <= 1'b0;
    end else begin
        uart_tx_start_combo <= uart_tx_start | tx_start_btn;
    end
end

//================================================================
// UART Manual Trigger
//================================================================
// Sync and edge detector for the button press to create a single-cycle 
// start pulse
logic [2:0] tx_trig_shft;
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_trig_shft  <= 3'b000;
        tx_start_btn  <= 1'b0;
    end else begin
        tx_trig_shft  <= { tx_trig_shft[1:0], tx_trigger_btn_i };
        // Pulse tx_start for one clock cycle when the button is pressed.
        tx_start_btn <= tx_trig_shft[2:1] == 2'b01;
    end
end


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
    
//================================================================
// LED Control Logic
//================================================================
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
assign probe0[31:0] = { dmem_addr_o[8:0], uart_rx_data, uart_tx_data, uart_tx_o, uart_rx_sync, 
                        uart_tx_start, uart_tx_start_combo, uart_rx_data_valid,
                        dmem_we_o, led3_o };

ila_0 ab_ILA (
	.clk     (clk),   // input wire clk
	.probe0  (probe0) // input wire [31:0] probe0
);


endmodule
