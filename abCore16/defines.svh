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
// Revision 1.3 - Multiple interrupts (Timer & UART) work
// Revision 1.2 - Added all byte-access instruction opcodes: LOADB, STORB, LOADIB, STORIB, LOADBFR, STORBFR
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
// NEW: Byte access instructions
`define OP_LOADB    8'h08 // LOADB Rd, Addr16 (4 bytes) - Load byte from memory
`define OP_STORB    8'h09 // STORB Rs, Addr16 (4 bytes) - Store byte to memory
`define OP_LOADIB   8'h0A // LOADIB Rd, Rs_addr (3 bytes) - Load byte indirect
`define OP_STORIB   8'h0B // STORIB Rt_val, Rs_addr (3 bytes) - Store byte indirect
`define OP_LOADBFR  8'h0C // LOADBFR Rd, Rbase, #off16 (5 bytes) - Load byte frame-relative
`define OP_STORBFR  8'h0D // STORBFR Rt, Rbase, #off16 (5 bytes) - Store byte frame-relative
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

`define OP_EI       8'h72 // Enable Interrupts (1 byte)
`define OP_DI       8'h73 // Disable Interrupts (1 byte)
`define OP_RETI     8'h74 // Return from Interrupt (1 byte)

`define OP_MOV      8'h80 // MOV Rd, Rs (3 bytes)
`define OP_MOVFRSP  8'h81 // MOVFRSP Rd (2 bytes)
`define OP_MOVTOSP  8'h82 // MOVTOSP Rs (2 bytes)
`define OP_HALT     8'hFF // HALT (1 byte)

//================================================================
// Core Architecture Parameters
//================================================================
`define DATA_WIDTH 16
`define ADDR_WIDTH 14
`define DATA_MEMORY_BYTES 8192 // Max capacity for 16-bit addressing. Defines SP initial value.
`define INSTRUCTION_MEMORY_BYTES 4096 // Instruction memory for 8-bit addressing. Use only half the total memory.

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
`define PC_SRC_MEM          3'b010 // Value from data memory bus (for RET and RETI)
`define PC_SRC_PC_CURRENT   3'b011 // PC = PC (for HALT)
`define PC_SRC_ALU          3'b100 // Value from ALU result (for calculated jumps - future)
//`define PC_SRC_IVT          3'b101 // Interrupt vector address
`define PC_SRC_RESTORE      3'b101 // Saved PC when entering Interrupt - restore value

// ALU Operand A Source Selection (for alu_src_a_sel_out)
`define ALU_A_SRC_REG       1'b0
`define ALU_A_SRC_PC        1'b1

// ALU Operand B Source Selection (for alu_src_b_sel_out)
`define ALU_B_SRC_REG       1'b0
`define ALU_B_SRC_IMM       1'b1

// Register File Writeback Data Source (for reg_write_data_sel_out)
`define WB_SRC_ALU          2'b00 // From ALU result
`define WB_SRC_MEM          2'b01 // From Data Memory (LOAD, POP)
`define WB_SRC_SP           2'b10 // From Stack Pointer (MOVFRSP)
`define WB_SRC_GPIO         2'b11 // From GPIO Input Bus (INP)

// Data Memory Address Source (for dmem_addr_sel_out)
`define DMEM_ADDR_SRC_IMM   2'b00 // Direct address from instruction
`define DMEM_ADDR_SRC_SP    2'b01 // From Stack Pointer
`define DMEM_ADDR_SRC_ALU   2'b10 // From ALU result (LOADI, STORI)
`define DMEM_ADDR_SRC_IVT   2'b11 // Interrupt, vector table address

// Data Memory Data Source (for dmem_rtn_addr_sel)
`define DMEM_DATA_SRC_RF1   2'b00 // From Register File, rf_src1
`define DMEM_DATA_SRC_RF2   2'b01 // From Register File, rf_src2
`define DMEM_DATA_SRC_PC    2'b10 // From PC

// Instruction Memory Address Source (for imem_addr_sel_out)
//`define IMEM_ADDR_SRC_PC    1'b0  // Direct address from PC
//`define IMEM_ADDR_SRC_IVT   1'b1  // IVT_Base + irq_num<<1

//================================================================
// Interrut Vector 
//================================================================
`define IVT_BASE_ADDR       16'h0002


//================================================================
// PIO Definitions
//================================================================
// Registers
`define REG_WIDTH  32
`define GPIO_WIDTH 32
// Instruction Memory
`define INSTR_MEM_ADDR_WIDTH  5
`define INSTR_MEM_DEPTH       32

//================================================================
// Instruction Opcodes
//================================================================
// Note: Some of the PIO opcode name were already in use for the 
//       abCore16 opcodes so OP_ was changed to OC_ to distinguish opcodes.
// Opcodes
`define OC_JMP    4'b000?
`define OC_WAIT   4'b001?
`define OC_IN     4'b010?
`define OC_OUT    4'b011?
`define OC_PUSH   4'b1000
`define OC_PULL   4'b1001
`define OC_MOV    4'b101?
//`define OC_IRQ    4'b110?
// Bit7 of IRQ is always 0
`define OC_IRQ    4'b1100
`define OC_SET    4'b111?

// PC Source Select (pc_src_sel)
`define PC_SRC_PLUS_ONE   3'b000
`define PC_SRC_IMMEDIATE  3'b001
`define PC_SRC_OSR        3'b010
`define PC_SRC_CURRENT    3'b011
`define PC_SRC_ZERO       3'b100

// Register Source Select
`define REG_SRC_OSR       2'b00
`define REG_SRC_ISR       2'b01
`define REG_SRC_IMMEDIATE 2'b10
`define REG_SRC_GPIO      2'b11

// OSR Source Select
`define OSR_SRC_TX_FIFO   2'b00
`define OSR_SRC_X_REG     2'b01
`define OSR_SRC_Y_REG     2'b10
`define OSR_SRC_IMMEDIATE 2'b11

// ISR Source Select
`define ISR_SRC_GPIO      3'b000
`define ISR_SRC_X_REG     3'b001
`define ISR_SRC_Y_REG     3'b010
`define ISR_SRC_ZERO      3'b011
// Reserved               3b'100
// Reserved               3b'101
`define ISR_SRC_ISR       3'b110
`define ISR_SRC_OSR       3'b111

// GPIO Source Select
`define GPIO_SRC_OSR      2'b00
`define GPIO_SRC_X_REG    2'b01
`define GPIO_SRC_Y_REG    2'b10
`define GPIO_SRC_IMMEDIATE 2'b11

// MOV Destination Select (3 bits [7:5])
// Output to GPIO pins
`define MOV_DEST_PINS   3'b000
// Write to X register
`define MOV_DEST_X      3'b001
// Write to Y register
`define MOV_DEST_Y      3'b010
// Reserved             3'b011
// EXEC (Execute data as instruction)
`define MOV_DEST_EXEC 3'b100
// PC
`define MOV_DEST_PC    3'b101
// Input Shift Register
`define MOV_DEST_ISR    3'b110
// Output Shift Register
`define MOV_DEST_OSR    3'b111


// MOV Source Select (3 bits [2:0])
// Read from GPIO pins
`define MOV_SRC_PINS   3'b000
// Read from X register
`define MOV_SRC_X      3'b001
// Read from Y register
`define MOV_SRC_Y      3'b010
// All zeros
`define MOV_SRC_NULL   3'b011
// STATUS register
`define MOV_SRC_STATUS 3'b101
// Input Shift Register
`define MOV_SRC_ISR    3'b110
// Output Shift Register
`define MOV_SRC_OSR    3'b111


// MOV Operation Select (2 bits [4:3])
// Direct copy (no operation)
`define MOV_OP_NONE    2'b00
// Bitwise invert (~)
`define MOV_OP_INVERT  2'b01
// Bit-reverse
`define MOV_OP_REVERSE 2'b10
// 2'b11 reserved

// SET Destination Select (3 bits [7:5])
// Set output pins
`define SET_DEST_PINS    3'b000
// Set X register
`define SET_DEST_X       3'b001
// Set Y register
`define SET_DEST_Y       3'b010
// 3'b011 reserved
// Set pin directions
`define SET_DEST_PINDIRS 3'b100
// 3'b101, 3'b110, 3'b111 reserved

// IRQ Operations
// Set IRQ, don't wait
`define IRQ_OP_SET_NOWAIT   2'b00
// Set IRQ, wait for clear
`define IRQ_OP_SET_WAIT     2'b01
// Clear IRQ, don't wait
`define IRQ_OP_CLEAR_NOWAIT 2'b10
// Clear IRQ, wait for clear (unusual)
`define IRQ_OP_CLEAR_WAIT   2'b11

// IRQ Instruction Field Positions
// IRQ clear flag bit position
`define IRQ_CLEAR_BIT     6
// IRQ wait flag bit position  
`define IRQ_WAIT_BIT      5
// IRQ relative addressing bit
`define IRQ_REL_BIT       4
// Mask for IRQ index bits [2:0]
`define IRQ_INDEX_MASK    3'b111

// IRQ Limits
// Maximum IRQ index (0-7)
`define MAX_IRQ_INDEX     7
// Maximum state machines for relative addressing
`define MAX_STATE_MACHINES 4


`endif // DEFINES_SVH
