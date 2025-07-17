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
//////////////////////////////////////////////////////////////////////////////////

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
`define IMEM_HEX_FILE "test_blink.hex"  // blink LED using SW counters


module cpu_tl (
    input  logic clk_12MHz,
    input  logic rst_in,

    // GPIO Interface
//    input  logic [`DATA_WIDTH-1:0] gpio_in_i,  // for now reduce pin count
    output logic [`DATA_WIDTH-1:0] gpio_out_o,
    output logic                   gpio_out_we_o,   
    // CPU halt flag
    output logic                   halted_o,
    output logic                   led2_o,
    output logic                   led3_o
);

//================================================================
// Internal Wires connecting microprocessor core
//================================================================
// Instruction Memory Interface
logic [`ADDR_WIDTH-1:0] imem_addr_o;    // Address to Instruction Memory (driven by DP's PC)
logic [7:0]             imem_rdata_i;   // Data from Instruction Memory (read by DP)
// Data Memory Interface
logic                   dmem_we_o;      // Data memory write enable
logic [`ADDR_WIDTH-1:0] dmem_addr_o;    // Data memory address bus
logic [`DATA_WIDTH-1:0] dmem_wdata_o;   // Data memory data bus
logic [`DATA_WIDTH-1:0] dmem_rdata_i;   // Data from memory (BRAM)
    
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
    .dmem_rdata_i  (dmem_rdata_i),   // Data from memory (BRAM)
    // GPIO Interface
    .gpio_out_o    (gpio_out_o),
    .gpio_out_we_o (gpio_out_we_o),   
    // CPU halt flag
    .halted_o      (halted_o)
);
    

//================================================================
// Conditional Memory Instantiation (`generate` block)
//================================================================
`ifdef MEMORYMODELSIM
    
    initial begin
        $display("INFO: Compiling with SIMULATION behavioral memory model.");
        $display("INFO: Loading instruction memory from '%s'.", `IMEM_HEX_FILE);
    end

    // Behavioral Instruction and Data Memory
    logic [7:0] instruction_memory [0:`DATA_MEMORY_BYTES-1];
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
       if ( (dmem_we_o == 1'b1) &&  (dmem_addr_o == 6144) ) begin  
         if ( dmem_wdata_o == 0 ) begin   // address 0x1800
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
