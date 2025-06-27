`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:      ab Systems
// Engineer:     Al Baeza
// 
// Create Date:  [Current Date]
// Design Name:  abCore16 Definitions
// Module Name:  defines
// Project Name: abCore16
// Target Devices: Xilinx FPGA
// Tool Versions: Vivado
// Description: 
// Centralized definitions for the abCore16 microprocessor project.
// Includes opcodes, register names, and control signal constants for the
// multi-cycle implementation.
//
// Dependencies: None
// 
// Revision:
// Revision 1.1 - Added back missing DATA_MEMORY_WORDS macro definition.
// Revision 1.0 - Synced with Python toolchain and added control constants.
//
//////////////////////////////////////////////////////////////////////////////////


`ifndef DEFINES_SVH
`define DEFINES_SVH

//================================================================
// Instruction Opcodes
//================================================================
`define OP_NOP      8'h00 // NOP (1 byte)
`define OP_LOAD     8'h01 // LOAD Rd, #Imm16 (4 bytes)
`define OP_STORE    8'h02 // STORE Rs, Addr16 (4 bytes)
`define OP_LOADM    8'h03 // LOADM Rd, Addr16 (4 bytes)
`define OP_LOADFR   8'h04 // LOADFR Rd, Rbase, #off16 (5 bytes)
`define OP_STORFR   8'h05 // STORFR Rt, Rbase, #off16 (5 bytes)
`define OP_LOADI    8'h06 // LOADI Rd, Rs_addr (3 bytes)
`define OP_STORI    8'h07 // STORI Rt_val, Rs_addr (3 bytes)

`define OP_ADD      8'h10 // ADD Rd, Rs (3 bytes)
`define OP_SUB      8'h11 // SUB Rd, Rs (3 bytes)
`define OP_MUL      8'h12 // MUL Rd, Rs (3 bytes)
`define OP_INC      8'h13 // INC Rd (2 bytes)
`define OP_DEC      8'h14 // DEC Rd (2 bytes)

`define OP_AND      8'h20 // AND Rd, Rs (3 bytes)
`define OP_OR       8'h21 // OR Rd, Rs (3 bytes)
`define OP_XOR      8'h22 // XOR Rd, Rs (3 bytes)
`define OP_NOT      8'h23 // NOT Rd (2 bytes)
`define OP_SHL      8'h24 // SHL Rd, #Imm8 (3 bytes)
`define OP_SHR      8'h25 // SHR Rd, #Imm8 (3 bytes)

`define OP_L_AND    8'h26 // LAND Rd, Rs1, Rs2 (4 bytes)
`define OP_L_OR     8'h27 // LOR Rd, Rs1, Rs2 (4 bytes)
`define OP_L_NOT    8'h28 // LNOT Rd, Rs (3 bytes)

`define OP_INP      8'h30 // INP Rd (2 bytes)
`define OP_OUT      8'h31 // OUT Rs (2 bytes)
`define OP_INM      8'h32 // INM Rd, Addr16 (4 bytes)
`define OP_OUTM     8'h33 // OUTM Rs, Addr16 (4 bytes)

`define OP_CMP      8'h40 // CMP R1, R2 (3 bytes)

`define OP_JMP      8'h50 // JMP Addr16 (3 bytes)
`define OP_JMPZ     8'h51 // JMPZ Rs, Addr16 (4 bytes)
`define OP_JMPN     8'h52 // JMPN Rs, Addr16 (4 bytes)
`define OP_JE       8'h53 // JE Addr16 (3 bytes)
`define OP_JNE      8'h54 // JNE Addr16 (3 bytes)
`define OP_JS       8'h55 // JS Addr16 (3 bytes)
`define OP_JNS      8'h56 // JNS Addr16 (3 bytes)
`define OP_JC       8'h57 // JC Addr16 (3 bytes)
`define OP_JNC      8'h58 // JNC Addr16 (3 bytes)
`define OP_JO       8'h59 // JO Addr16 (3 bytes)
`define OP_JNO      8'h5A // JNO Addr16 (3 bytes)

`define OP_PUSH     8'h60 // PUSH Rs (2 bytes)
`define OP_POP      8'h61 // POP Rd (2 bytes)

`define OP_CALL     8'h70 // CALL Addr16 (3 bytes)
`define OP_RET      8'h71 // RET (1 byte)

`define OP_MOV      8'h80 // MOV Rd, Rs (3 bytes)
`define OP_MOVFRSP  8'h81 // MOVFRSP Rd (2 bytes)
`define OP_MOVTOSP  8'h82 // MOVTOSP Rs (2 bytes)

`define OP_HALT     8'hFF // HALT (1 byte)

//================================================================
// Core Architecture Parameters
//================================================================
`define DATA_WIDTH 16
`define ADDR_WIDTH 14
`define DATA_MEMORY_WORDS 8192 // Max capacity for 16-bit addressing. Defines SP initial value.

//================================================================
// Register Definitions
//================================================================
`define REG_ADDR_WIDTH 5    // Using 5 bits allows for 32 special registers (GPRs, SP, FP, status, etc.)
`define NUM_GP_REGS    8

`define REG_R0         5'd0
`define REG_R1         5'd1
`define REG_R2         5'd2
`define REG_R3         5'd3
`define REG_R4         5'd4
`define REG_R5         5'd5
`define REG_R6         5'd6
`define REG_R7         5'd7
`define SP_REG_ADDR    5'd29  // Special, non-GPR address for writing to SP

//================================================================
// ALU Control Signals (4-bit)
//================================================================
`define ALU_ADD     4'h0
`define ALU_SUB     4'h1
`define ALU_AND     4'h2
`define ALU_OR      4'h3
`define ALU_XOR     4'h4
`define ALU_NOT     4'h5
`define ALU_SHL     4'h6
`define ALU_SHR     4'h7
`define ALU_MUL     4'h8
`define ALU_INC     4'h9
`define ALU_DEC     4'hA

`define ALU_L_AND   4'hB
`define ALU_L_OR    4'hC
`define ALU_L_NOT   4'hD

`define ALU_PASS_A  4'hE // Pass input A through
`define ALU_PASS_B  4'hF // Pass input B through
`define ALU_NOP     4'hC // No operation

//================================================================
// Control Signal Constants for Multi-Cycle Datapath
//================================================================
// PC Source Selection (for pc_src_sel_out)
`define PC_SRC_PC_PLUS_1    3'b000 // PC + 1 (for byte-wise fetch)
`define PC_SRC_IMM          3'b001 // Immediate value from instruction (for JMP, CALL)
`define PC_SRC_MEM          3'b010 // Value from data memory bus (for RET)
`define PC_SRC_PC_CURRENT   3'b011 // PC = PC (for HALT)
`define PC_SRC_ALU          3'b100 // Value from ALU result (for calculated jumps - future)

// ALU Operand A Source Selection (for alu_src_a_sel_out)
`define ALU_A_SRC_REG       2'b00
`define ALU_A_SRC_PC        2'b01

// ALU Operand B Source Selection (for alu_src_b_sel_out)
`define ALU_B_SRC_REG       2'b00
`define ALU_B_SRC_IMM       2'b01

// Register File Writeback Data Source (for reg_write_data_sel_out)
`define WB_SRC_ALU          2'b00 // From ALU result
`define WB_SRC_MEM          2'b01 // From Data Memory (LOAD, POP)
`define WB_SRC_SP           2'b10 // From Stack Pointer (MOVFRSP)
`define WB_SRC_GPIO         2'b11 // From GPIO Input Bus (INP)

// Data Memory Address Source (for dmem_addr_sel_out)
`define DMEM_ADDR_SRC_IMM   2'b00 // Direct address from instruction
`define DMEM_ADDR_SRC_SP    2'b01 // From Stack Pointer
`define DMEM_ADDR_SRC_ALU   2'b10 // From ALU result (LOADI, STORI)

`endif // DEFINES_SVH
