`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/17/2025 02:53:22 PM
// Design Name: 
// Module Name: pio_program_mem
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

// For Synthesis, comment out
//`define PIO_MEMORYMODELSIM    // use hex file

//`define IMEM_COE_FILE "pio_program.coe"  // PIO program
`define PIO_HEX_FILE "pio_program.hex"  // PIO program

module pio_program_mem (
    input  logic clk,
    input  logic rst_n,
    
    // Bootloader interface
    input  logic        bl_read_en,
    input  logic [7:0]  bl_addr,        // 256 instruction capacity
    output logic [15:0] bl_instruction,
    
    // Program header interface  
    input  logic [3:0]  program_select,
    input  logic        pio_header_sav,
    output logic [4:0]  program_length,
    output logic [7:0]  program_start_addr
);

    // BRAM instance for program storage
    // This will be initialized with COE file during synthesis
    logic [15:0] pio_prog_memory [0:255];
    logic [15:0] bram_dout;
    
    // Program header table (first 16 locations)
    // Each header contains: [15:11] length, [10:3] start_addr, [2:0] reserved
    // Headers for programs 0-15 at addresses 0x00-0x0F
    
`ifdef PIO_MEMORYMODELSIM

    initial begin
        $display("SIM_INFO: Compiling with SIMULATION behavioral PIO memory model.");
        $display("SIM_INFO: Loading instruction memory from '%s'.", `PIO_HEX_FILE);
    end

    // BRAM read logic
    always_ff @(posedge clk) begin
         if (!rst_n) begin
            bram_dout <= 16'h0;
        end else if (bl_read_en) begin
//        if (bl_read_en) begin
            bram_dout <= pio_prog_memory[bl_addr];
        end
    end
    
    assign bl_instruction = bram_dout;
    
    // Program header decode
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            program_length <= 5'b0;
            program_start_addr <= 8'b0;
//        end else if (pio_header_sav) begin
        end else begin
            // Read header for selected program
//            program_length <= pio_prog_memory[program_select][15:11];
//            program_start_addr <= pio_prog_memory[program_select][10:3];
            
            program_length <= pio_prog_memory[program_select][12:8];
            program_start_addr <= pio_prog_memory[program_select][7:0];
        end
    end
    
    // Initialize BRAM with COE file (synthesis time)
    initial begin
        $readmemh(`PIO_HEX_FILE, pio_prog_memory);
    end
    
`else
    // --- FOR SYNTHESIS: Use the real BRAM IP Core ---
    // BRAM IP must be updated with the lastest .coe to initialize the
    // PIO instruction memory.
    
    initial begin
        $display("INFO: Compiling with SYNTHESIS BRAM IP Core model.");
    end
    
    // Program header decode
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            program_length <= 5'b0;
            program_start_addr <= 8'b0;
        end else if (pio_header_sav) begin
            // Read header for selected program
            program_length <= bl_instruction[12:8];
            program_start_addr <= bl_instruction[7:0];
        end
    end
    
    // Instantiate BRAM
    logic [15:0] bl_instruction_bram;
    logic [7:0]  bram_addr_combo;
    assign bram_addr_combo = {program_start_addr[7:4], bl_addr[3:0]};
    pio_program_bram pio_prog_bram01 (
      .clka(clk),             // input wire clka
 //     .ena(bl_read_en),       // input wire ena
      .ena(1'b1),       // input wire ena
//      .addra(bl_addr),        // input wire [7 : 0] addra
      .addra(bram_addr_combo),        // input wire [7 : 0] addra
      .douta(bl_instruction)  // output wire [15 : 0] douta
//      .douta(bl_instruction_bram)  // output wire [15 : 0] douta
    );
    
    
`endif

endmodule

