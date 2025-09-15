`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:      ab Systems
// Engineer:     Al Baeza
// 
// Create Date:  08/31/2025
// Design Name:  abCore16 PIO Definitions
// Module Name:  pio_defs
// Project Name: abCore16
// Target Devices: Xilinx FPGA
// Tool Versions: Vivado
// Description: 
// Centralized definitions for the abCore16 PIO project.
// Includes opcodes, register names, and control signal constants for the
// multi-cycle implementation.
//
// Dependencies: None
// 
// Revision:
// Revision 1.0 - Initial code.
//
//////////////////////////////////////////////////////////////////////////////////


`ifndef DEFINES_SVH
`define DEFINES_SVH

//================================================================
// System Level Parameters
//================================================================
//parameter int CLK_PERIOD = 10; // 100MHz clock
//parameter int INSTR_MEM_ADDR_WIDTH = 5;
//parameter int REG_WIDTH = 32;
//parameter int GPIO_WIDTH = 32;
//parameter int INSTR_MEM_DEPTH = 32;

// Main system clock
`define CLK_PERIOD 10
// Registers
`define REG_WIDTH  32
`define GPIO_WIDTH 32
// Instruction Memory
`define INSTR_MEM_ADDR_WIDTH  5
`define INSTR_MEM_DEPTH       32

//================================================================
// Instruction Opcodes
//================================================================
// Opcodes
`define OP_JMP    4'b000?
`define OP_WAIT   4'b001?
`define OP_IN     4'b010?
`define OP_OUT    4'b011?
`define OP_PUSH   4'b1000
`define OP_PULL   4'b1001
`define OP_MOV    4'b101?
//`define OP_IRQ    4'b110?
// Bit7 of IRQ is always 0
`define OP_IRQ    4'b1100
`define OP_SET    4'b111?

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
