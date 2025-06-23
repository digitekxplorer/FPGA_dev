`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:      ab Systems
// Engineer:     Al Baeza
// 
// Create Date:  06/18/2025
// Design Name:  abCore16 Datapath (Original Architecture)
// Module Name:  datapath
// Project Name: abCore16
// Target Devices: Xilinx FPGA
// Tool Versions: Vivado
// Description: 
// The datapath for the abCore16 microprocessor. This version uses the original
// architecture where the datapath latches instruction bytes and provides them
// to the control unit for decoding.
//
// Dependencies: `defines.svh`, `alu.sv`
// 
// Revision:
// Revision 1.1 - Reverted to original architecture and synced with latest defines.
//
//////////////////////////////////////////////////////////////////////////////////


`include "defines.svh"

module datapath (
    input  logic clk,
    input  logic rst_n,

    // From Instruction Memory
    input  logic [7:0]             imem_rdata_i, // Fetches one byte at a time

    // To Instruction Memory
    output logic [`ADDR_WIDTH-1:0] pc_to_imem_addr,

    // Control Signals from Control Unit
    input  logic        pc_write_en_from_cu,
    input  logic [2:0]  pc_src_sel_from_cu,
    input  logic        ir_opcode_load_en_from_cu,
    input  logic        ir_operand1_load_en_from_cu,
    input  logic        ir_operand2_load_en_from_cu,
    input  logic        ir_operand3_load_en_from_cu, // For 4th byte of 4-byte instructions
    input  logic        reg_write_en_from_cu,
    input  logic [`REG_ADDR_WIDTH-1:0] reg_dest_addr_from_cu,
    input  logic [`REG_ADDR_WIDTH-1:0] reg_src1_addr_from_cu,
    input  logic [`REG_ADDR_WIDTH-1:0] reg_src2_addr_from_cu,
    input  logic [1:0]  reg_write_data_sel_from_cu,
    input  logic [`DATA_WIDTH-1:0] imm_val_from_cu, // Assembled immediate from CU
    input  logic [3:0]  alu_op_from_cu,
    input  logic [1:0]  alu_src_a_sel_from_cu,
    input  logic [1:0]  alu_src_b_sel_from_cu,
    input  logic        dmem_read_en_from_cu,
    input  logic        dmem_write_en_from_cu,
    input  logic [1:0]  dmem_addr_sel_from_cu,
    input  logic        sp_op_inc_from_cu,
    input  logic        sp_op_dec_from_cu,

    // Data Memory Interface
    output logic                   dmem_we_out,
    output logic [`ADDR_WIDTH-1:0] dmem_addr_out,
    output logic [`DATA_WIDTH-1:0] dmem_wdata_out,
    input  logic [`DATA_WIDTH-1:0] dmem_rdata_in,

    // GPIO Interface
    input  logic [`DATA_WIDTH-1:0] gpio_in_data_bus,
    output logic [`DATA_WIDTH-1:0] gpio_out_data_bus,

    // Outputs to Control Unit (from IR and Flags)
    output logic [7:0]             opcode_byte_to_cu,
    output logic [7:0]             operand1_byte_to_cu,
    output logic [7:0]             operand2_byte_to_cu,
    output logic [7:0]             operand3_byte_to_cu,
    output logic                   ZF_to_cu, SF_to_cu, CF_to_cu, OF_to_cu,
    output logic                   reg_is_zero_to_cu,
    output logic                   reg_is_neg_to_cu
);

    //================================================================
    // Program Counter (PC)
    //================================================================
    logic [`ADDR_WIDTH-1:0] pc_reg, pc_next_calculated;
    assign pc_to_imem_addr = pc_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) pc_reg <= `ADDR_WIDTH'h0000;
        else if (pc_write_en_from_cu) pc_reg <= pc_next_calculated;
    end
    
    // PC Next Logic
    always_comb begin
        case (pc_src_sel_from_cu)
            `PC_SRC_PC_PLUS_1:  pc_next_calculated = pc_reg + 1;
            `PC_SRC_IMM:        pc_next_calculated = imm_val_from_cu;
            `PC_SRC_MEM:        pc_next_calculated = dmem_rdata_in;
            `PC_SRC_PC_CURRENT: pc_next_calculated = pc_reg;
            `PC_SRC_ALU:        pc_next_calculated = alu_result_internal;
            default:            pc_next_calculated = pc_reg;
        endcase
    end
 
    
    //================================================================
    // Instruction Register (IR) components
    //================================================================
    logic [7:0] ir_opcode_reg;
    logic [7:0] ir_operand1_reg; // Holds byte 2 of instruction
    logic [7:0] ir_operand2_reg; // Holds byte 3 of instruction
    logic [7:0] ir_operand3_reg; // Holds byte 4 of instruction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ir_opcode_reg   <= `OP_NOP;
            ir_operand1_reg <= 8'h00;
            ir_operand2_reg <= 8'h00;
            ir_operand3_reg <= 8'h00;
        end else begin
            if (ir_opcode_load_en_from_cu)   ir_opcode_reg   <= imem_rdata_i;
            if (ir_operand1_load_en_from_cu) ir_operand1_reg <= imem_rdata_i;
            if (ir_operand2_load_en_from_cu) ir_operand2_reg <= imem_rdata_i;
            if (ir_operand3_load_en_from_cu) ir_operand3_reg <= imem_rdata_i;
        end
    end
    
    // Outputs from IR to Control Unit for decoding
    assign opcode_byte_to_cu   = ir_opcode_reg;
    assign operand1_byte_to_cu = ir_operand1_reg;
    assign operand2_byte_to_cu = ir_operand2_reg;
    assign operand3_byte_to_cu = ir_operand3_reg;

    //================================================================
    // Register File (R0-R7) and Stack Pointer (SP)
    //================================================================
    logic [`DATA_WIDTH-1:0] rf_rdata1, rf_rdata2;
    logic [`DATA_WIDTH-1:0] rf_wdata_final;
    logic [`NUM_GP_REGS-1:0] [`DATA_WIDTH-1:0] register_file;
    logic [`ADDR_WIDTH-1:0] sp_reg;

    // GPR Asynchronous Read
    assign rf_rdata1 = (reg_src1_addr_from_cu < `NUM_GP_REGS) ? register_file[reg_src1_addr_from_cu] : 16'b0;
    assign rf_rdata2 = (reg_src2_addr_from_cu < `NUM_GP_REGS) ? register_file[reg_src2_addr_from_cu] : 16'b0;

    // GPR Synchronous Write
    always_ff @(posedge clk) begin
        if (reg_write_en_from_cu && reg_dest_addr_from_cu < `NUM_GP_REGS) begin
            register_file[reg_dest_addr_from_cu] <= rf_wdata_final;
        end
    end

    // SP Logic
    localparam STACK_INIT_VAL_DP = `DATA_MEMORY_WORDS;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            sp_reg <= STACK_INIT_VAL_DP;
        else if (sp_op_inc_from_cu) 
            sp_reg <= sp_reg + 2; // Word-aligned stack
        else if (sp_op_dec_from_cu) 
            sp_reg <= sp_reg - 2; // Word-aligned stack
        else if (reg_write_en_from_cu && reg_dest_addr_from_cu == `SP_REG_ADDR) // For MOVTOSP
            sp_reg <= rf_wdata_final;
    end

    //================================================================
    // ALU
    //================================================================
    logic [`DATA_WIDTH-1:0] alu_in_a, alu_in_b;
    logic [`DATA_WIDTH-1:0] alu_result_internal;
    logic alu_zf, alu_sf, alu_cf, alu_of;

    // ALU Input Muxes
    always_comb begin
        case(alu_src_a_sel_from_cu)
            `ALU_A_SRC_PC:  alu_in_a = pc_reg;
            `ALU_A_SRC_REG: alu_in_a = rf_rdata1;
            default:        alu_in_a = rf_rdata1;
        endcase
        case(alu_src_b_sel_from_cu)
            `ALU_B_SRC_IMM: alu_in_b = imm_val_from_cu;
            `ALU_B_SRC_REG: alu_in_b = rf_rdata2;
            default:        alu_in_b = rf_rdata2;
        endcase
    end
    
    // ALU Instantiation
    alu alu_unit (
        .A(alu_in_a), 
        .B(alu_in_b), 
        .ALUControl(alu_op_from_cu),
        .Result(alu_result_internal), 
        .Zero(alu_zf), 
        .Sign(alu_sf),
        .Carry(alu_cf), 
        .Overflow(alu_of)
    );
    assign ZF_to_cu = alu_zf; assign SF_to_cu = alu_sf;
    assign CF_to_cu = alu_cf; assign OF_to_cu = alu_of;

    //================================================================
    // Write-back and Output Logic
    //================================================================
    // Write-back data selection for Register File
    always_comb begin
        case (reg_write_data_sel_from_cu)
            `WB_SRC_ALU:    rf_wdata_final = alu_result_internal;  // 00
            `WB_SRC_MEM:    rf_wdata_final = dmem_rdata_in;        // 01
            `WB_SRC_SP:     rf_wdata_final = sp_reg; // For MOVFRSP   10
            default:        rf_wdata_final = alu_result_internal;
        endcase
    end
    
    // Data Memory Connections
    assign dmem_we_out = dmem_write_en_from_cu;
    always_comb begin
        case (dmem_addr_sel_from_cu)
            `DMEM_ADDR_SRC_ALU: dmem_addr_out = alu_result_internal; // For LOADI/STORI
            `DMEM_ADDR_SRC_SP:  dmem_addr_out = sp_reg;
            `DMEM_ADDR_SRC_IMM: dmem_addr_out = imm_val_from_cu;
            default:            dmem_addr_out = 16'hDEAD;
        endcase
    end
    assign dmem_wdata_out = rf_rdata1;

    // GPIO Output
    assign gpio_out_data_bus = rf_rdata1;

    // Register-based jump condition flags to CU
    assign reg_is_zero_to_cu = (rf_rdata1 == 16'b0);
    assign reg_is_neg_to_cu  = rf_rdata1[15];

endmodule