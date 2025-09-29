`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/17/2025 01:23:55 PM
// Design Name: 
// Module Name: pio_bootloader
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


module pio_bootloader (
    input  logic clk,
    input  logic rst_n,
    
    // Control interface
    input  logic        bootload_start,
    input  logic [3:0]  program_select,
    output logic        bootload_done,
    output logic        bootload_error,
    output logic        pio_header_sav,
    
    // BRAM interface
    output logic        bram_read_en,
    output logic [7:0]  bram_addr,
    input  logic [15:0] bram_instruction,
    input  logic [4:0]  program_length,
    input  logic [7:0]  program_start_addr,
    
    // PIO instruction memory interface
    output logic        imem_write_en,
    output logic [4:0]  imem_write_addr,
    output logic [15:0] imem_write_data
);

    typedef enum logic [2:0] {
        BL_IDLE,
        BL_READ_HEADER,
//        BL_READ_WAIT,
        BL_VALIDATE,
        BL_LOAD_PROGRAM,
        BL_DONE,
        BL_ERROR
    } bootloader_state_t;
    
    bootloader_state_t bl_state;
    logic [4:0] instruction_count;
//    logic [7:0] current_bram_addr;
    logic [4:0] current_imem_addr;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bl_state <= BL_IDLE;
            instruction_count <= 5'b0;
//            current_bram_addr <= 8'b0;
            bram_addr <=  8'b0;
            current_imem_addr <= 5'b0;
            bram_read_en <= 1'b0;
            imem_write_en <= 1'b0;
            imem_write_addr <= '0;
            imem_write_data <= '0;
            bootload_done <= 1'b0;
            bootload_error <= 1'b0;
            pio_header_sav <= 1'b0;
        end else begin
            case (bl_state)
                BL_IDLE: begin
                    bootload_done <= 1'b0;
                    bootload_error <= 1'b0;
                    imem_write_en <= 1'b0;
//                    bram_read_en <= 1'b0;
                    bram_read_en <= 1'b1;
                    
                    if (bootload_start) begin
                        bl_state <= BL_READ_HEADER;
                        bram_addr <= {4'b0000, program_select}; // Header address
                        pio_header_sav <= 1'b1;          // capture header
//                        bram_read_en <= 1'b1;
                    end
                end
                
                BL_READ_HEADER: begin
                    // Wait one cycle for BRAM read
                    bl_state <= BL_VALIDATE;
                    bram_addr <= program_start_addr;
                    pio_header_sav <= 1'b0;
//                    bram_read_en <= 1'b0;
                end               
                
                BL_VALIDATE: begin
                    // Check if program is valid
                    if (program_length == 5'b0 || program_length > 5'd31) begin
                        bl_state <= BL_ERROR;
                    end else begin
                        bl_state <= BL_LOAD_PROGRAM;
//                        bl_state <= BL_READ_WAIT;
                        instruction_count <= program_length;
//                        current_bram_addr <= program_start_addr;
                        current_imem_addr <= 5'b0;
//                        bram_addr <= program_start_addr;
                        bram_addr <= bram_addr + 1'b1;
//                        bram_read_en <= 1'b1;
                    end
                end
                
                
                BL_LOAD_PROGRAM: begin
                    if (instruction_count > 0) begin
                        // Write current instruction to PIO instruction memory
                        imem_write_en <= 1'b1;
                        imem_write_addr <= current_imem_addr;
                        imem_write_data <= bram_instruction;
                        
                        // Update counters and addresses
                        instruction_count <= instruction_count - 1'b1;
                        current_imem_addr <= current_imem_addr + 1'b1;
//                        current_bram_addr <= current_bram_addr + 1'b1;
                        
                        if (instruction_count > 1) begin
                            // Setup next BRAM read
                            bram_addr <= bram_addr + 1'b1;
//                            bram_read_en <= 1'b1;
                        end else begin
//                            bram_read_en <= 1'b0;
                        end
                    end else begin
                        imem_write_en <= 1'b0;
                        bl_state <= BL_DONE;
                    end
                end
                
                BL_DONE: begin
                    bootload_done <= 1'b1;
                    // Stay in DONE state until next bootload_start
                    if (bootload_start) begin
                        bl_state <= BL_READ_HEADER;
                        bootload_done <= 1'b0;
                    end
                end
                
                BL_ERROR: begin
                    bootload_error <= 1'b1;
                    // Stay in ERROR state until reset or new bootload
                    if (bootload_start) begin
                        bl_state <= BL_READ_HEADER;
                        bootload_error <= 1'b0;
                    end
                end
            endcase
        end
    end
    
    // BRAM address assignment
//    assign bram_addr = (bl_state == BL_READ_HEADER) ? {4'b0000, program_select} : current_bram_addr;

endmodule

