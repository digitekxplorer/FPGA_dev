`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:      ab Systems
// Engineer:     Al Baeza
// 
// Create Date:  06/18/2025
// Design Name:  abCore16 Arithmetic Logic Unit
// Module Name:  alu
// Project Name: abCore16
// Target Devices: Xilinx FPGA
// Tool Versions: Vivado
// Description: 
// The 16-bit Arithmetic Logic Unit for the abCore16 processor. 
// It performs arithmetic and logical operations and sets status flags.
//
// Dependencies: `defines.svh`
// 
// Revision:
// Revision 1.0 - Synchronized control codes with the latest defines.svh.
//
//////////////////////////////////////////////////////////////////////////////////


`include "defines.svh"

module alu (
    input  logic [`DATA_WIDTH-1:0] A, B,
    input  logic [3:0]             ALUControl,
    output logic [`DATA_WIDTH-1:0] Result,
    output logic                   Zero,     // ZF
    output logic                   Sign,     // SF
    output logic                   Carry,    // CF (Unsigned carry/borrow)
    output logic                   Overflow  // OF (Signed overflow)
);

    // Internal wires for extended-precision results to correctly calculate flags
    logic [`DATA_WIDTH:0]     extended_result_addsub;
    logic [`DATA_WIDTH*2-1:0] extended_result_mul;

    always_comb begin
        // Default assignments
        Result   = `DATA_WIDTH'b0;
        Carry    = 1'b0;
        Overflow = 1'b0;
        extended_result_addsub = '0;
        extended_result_mul    = '0;

        case (ALUControl)
            `ALU_ADD: begin
                extended_result_addsub = {1'b0, A} + {1'b0, B};
                Result = extended_result_addsub[`DATA_WIDTH-1:0];
                Carry = extended_result_addsub[`DATA_WIDTH];
                Overflow = (A[`DATA_WIDTH-1] == B[`DATA_WIDTH-1]) && 
                           (Result[`DATA_WIDTH-1] != A[`DATA_WIDTH-1]);
            end
            `ALU_SUB: begin // Also used for CMP instruction
                extended_result_addsub = {1'b0, A} - {1'b0, B};
                Result = extended_result_addsub[`DATA_WIDTH-1:0];
                Carry = (A < B); // Unsigned Borrow is Carry Flag for subtract
                Overflow = (A[`DATA_WIDTH-1] != B[`DATA_WIDTH-1]) && 
                           (Result[`DATA_WIDTH-1] != A[`DATA_WIDTH-1]);
            end
            `ALU_INC: begin
                extended_result_addsub = {1'b0, A} + 1;
                Result = extended_result_addsub[`DATA_WIDTH-1:0];
                Carry = extended_result_addsub[`DATA_WIDTH];
                // Overflow on INC only occurs when 0x7FFF becomes 0x8000
                Overflow = (A == 16'h7FFF);
            end
            `ALU_DEC: begin
                extended_result_addsub = {1'b0, A} - 1;
                Result = extended_result_addsub[`DATA_WIDTH-1:0];
                Carry = (A < 1); // Borrow if A was 0
                // Overflow on DEC only occurs when 0x8000 becomes 0x7FFF
                Overflow = (A == 16'h8000);
            end
            `ALU_AND: begin 
                Result = A & B;
                Carry = 1'b0; Overflow = 1'b0; // Cleared for logical ops
            end
            `ALU_OR: begin 
                Result = A | B;
                Carry = 1'b0; Overflow = 1'b0;
            end
            `ALU_XOR: begin
                Result = A ^ B;
                Carry = 1'b0; Overflow = 1'b0;
            end
            `ALU_NOT: begin
                Result = ~A;
                Carry = 1'b0; Overflow = 1'b0;
            end
            
            `ALU_L_AND: begin 
                Result = A && B;
                Carry = 1'b0; Overflow = 1'b0; // Cleared for logical ops
            end
            `ALU_L_OR: begin 
                Result = A || B;
                Carry = 1'b0; Overflow = 1'b0; // Cleared for logical ops
            end 
            `ALU_L_NOT: begin 
                Result = !A;
                Carry = 1'b0; Overflow = 1'b0; // Cleared for logical ops
            end    
 
            
            `ALU_SHL: begin // Logical Shift Left (shift amount from B)
                automatic logic [4:0] shift_amount = B[4:0]; // Use lower 5 bits for shift amount (0-31)
                Result = A << shift_amount;
                // Carry is the last bit shifted out of the MSB
                Carry = (shift_amount > 0 && shift_amount <= `DATA_WIDTH) ? A[`DATA_WIDTH - shift_amount] : 1'b0;
                Overflow = 1'b0;
            end
            `ALU_SHR: begin // Logical Shift Right (shift amount from B)
                automatic logic [4:0] shift_amount = B[4:0];
                Result = A >> shift_amount;
                // Carry is the last bit shifted out of the LSB
                Carry = (shift_amount > 0 && shift_amount <= `DATA_WIDTH) ? A[shift_amount-1] : 1'b0;
                Overflow = 1'b0;
            end
            `ALU_MUL: begin
                extended_result_mul = A * B;
                Result = extended_result_mul[`DATA_WIDTH-1:0];
                // Set Carry/Overflow if the result requires more than 16 bits
                Carry = |extended_result_mul[(`DATA_WIDTH*2-1):`DATA_WIDTH];
                Overflow = Carry;
            end
            `ALU_PASS_A: begin
                Result = A;
                Carry = 1'b0; Overflow = 1'b0;
            end
            `ALU_PASS_B: begin
                Result = B;
                Carry = 1'b0; Overflow = 1'b0;
            end
            default: begin // Covers ALU_NOP and any invalid code
                Result   = `DATA_WIDTH'hXXXX; // Propagate 'X' for easier debugging
                Carry    = 1'bx;
                Overflow = 1'bx;
            end
        endcase

        // Zero and Sign flags are always based on the final result
        Zero = (Result == `DATA_WIDTH'b0);
        Sign = Result[`DATA_WIDTH-1];
    end
endmodule
