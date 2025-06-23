`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:      ab Systems
// Engineer:     Al Baeza
// 
// Create Date:  [Current Date]
// Design Name:  abCore16 Control Unit (DP-Centric)
// Module Name:  control_unit
// Project Name: abCore16
// Target Devices: Xilinx FPGA
// Tool Versions: Vivado
// Description: 
// Control Unit for the abCore16. This version is designed for the
// DP-centric architecture where the datapath latches instruction bytes
// and provides them to the control unit for decoding.
//
// Dependencies: `defines.svh`
// 
// Revision:
// Revision 1.0 - Created to be compatible with the reverted DP-centric datapath.
//
//////////////////////////////////////////////////////////////////////////////////


`include "defines.svh"

module control_unit (
    input  logic clk,
    input  logic rst_n,

    // --- Inputs from Datapath's IR and Flags ---
    input  logic [7:0] opcode_from_dp,
    input  logic [7:0] operand1_from_dp,
    input  logic [7:0] operand2_from_dp,
    input  logic [7:0] operand3_from_dp,
    input  logic       ZF_in, SF_in, CF_in, OF_in,
    input  logic       reg_is_zero_in,
    input  logic       reg_is_neg_in,

    // --- Outputs to Datapath ---
    // PC Control
    output logic       pc_write_en_out,
    output logic [2:0] pc_src_sel_out,
    // IR Latching Control
    output logic       ir_opcode_load_en_out,
    output logic       ir_operand1_load_en_out,
    output logic       ir_operand2_load_en_out,
    output logic       ir_operand3_load_en_out,
    // Register File Control
    output logic       reg_write_en_out,
    output logic [`REG_ADDR_WIDTH-1:0] reg_dest_addr_out,
    output logic [`REG_ADDR_WIDTH-1:0] reg_src1_addr_out,
    output logic [`REG_ADDR_WIDTH-1:0] reg_src2_addr_out,
    output logic [1:0] reg_write_data_sel_out,
    // Immediate Value
    output logic [`DATA_WIDTH-1:0] imm_val_to_dp_out,
    // ALU Control
    output logic [3:0] alu_op_out,
    output logic [1:0] alu_src_a_sel_out,
    output logic [1:0] alu_src_b_sel_out,
    // Data Memory Control
    output logic       dmem_read_en_out,
    output logic       dmem_write_en_out,
    output logic [1:0] dmem_addr_sel_out,
    // Stack Pointer Control
    output logic       sp_op_inc_out,
    output logic       sp_op_dec_out,
    // GPIO Control
    output logic       gpio_out_we_out,
    
    // Halted flag
    output logic       halted_o
);
     // Local Signals
     logic ir_operand2_load_en;
     logic ir_operand2_load_en_r;
     logic ir_operand3_load_en;
     logic ir_operand3_load_en_r;

    //================================================================
    // FSM State Definition
    //================================================================
    typedef enum logic [3:0] { 
        S_RESET, S_FETCH_OPCODE, 
        S_DECODE,
        S_FETCH_OP1, S_FETCH_OP2, S_FETCH_OP3,
        S_EXECUTE, S_MEM_ACCESS, S_WRITEBACK, S_HALTED 
    } state_t;
    state_t current_state, next_state;

    logic [2:0] total_instr_bytes;
    logic branch_condition_met;

    //================================================================
    // Sequential Logic (State Register)
    //================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) current_state <= S_RESET;
        else        current_state <= next_state;
    end

    //================================================================
    // Combinational Logic Part 1: Instruction Length & Branch Condition
    //================================================================
    always_comb begin
        total_instr_bytes = 3'd1;
        case(opcode_from_dp)
            `OP_LOAD, `OP_STORE, `OP_LOADM, `OP_INM, `OP_OUTM, `OP_JMPZ, `OP_JMPN: total_instr_bytes = 3'd4;
            `OP_ADD, `OP_SUB, `OP_MUL, `OP_AND, `OP_OR, `OP_XOR, `OP_CMP, `OP_MOV, `OP_SHL, `OP_SHR,
            `OP_JMP, `OP_JE, `OP_JNE, `OP_JS, `OP_JNS, `OP_JC, `OP_JNC, `OP_JO, `OP_JNO, `OP_CALL,
            `OP_LOADI, `OP_STORI: total_instr_bytes = 3'd3;
            `OP_INC, `OP_DEC, `OP_NOT, `OP_INP, `OP_OUT, `OP_PUSH, `OP_POP, `OP_MOVFRSP, `OP_MOVTOSP: total_instr_bytes = 3'd2;
            `OP_RET, `OP_NOP, `OP_HALT: total_instr_bytes = 3'd1;
            default: total_instr_bytes = 3'd1;
        endcase
        
        branch_condition_met = 
            (opcode_from_dp == `OP_JE   && ZF_in)  || (opcode_from_dp == `OP_JNE  && !ZF_in) ||
            (opcode_from_dp == `OP_JS   && SF_in)  || (opcode_from_dp == `OP_JNS  && !SF_in) ||
            (opcode_from_dp == `OP_JC   && CF_in)  || (opcode_from_dp == `OP_JNC  && !CF_in) ||
            (opcode_from_dp == `OP_JO   && OF_in)  || (opcode_from_dp == `OP_JNO  && !OF_in) ||
            (opcode_from_dp == `OP_JMPZ && reg_is_zero_in) || (opcode_from_dp == `OP_JMPN && reg_is_neg_in);
    end

    //================================================================
    // Combinational Logic Part 2: FSM Next State Logic
    //================================================================
    always_comb begin
        next_state = current_state; 
        case(current_state)
            S_RESET:        next_state = S_FETCH_OPCODE;
            S_FETCH_OPCODE: next_state = S_DECODE;
            S_DECODE: begin
                if (opcode_from_dp == `OP_HALT)      next_state = S_HALTED;
                else if (total_instr_bytes == 1)    next_state = S_EXECUTE;
                else                                next_state = S_FETCH_OP1;
            end
            S_FETCH_OP1:    if (total_instr_bytes > 2) next_state = S_FETCH_OP2; else next_state = S_EXECUTE;
            S_FETCH_OP2:    if (total_instr_bytes > 3) next_state = S_FETCH_OP3; else next_state = S_EXECUTE;
            S_FETCH_OP3:    next_state = S_EXECUTE;
            S_EXECUTE:
                case (opcode_from_dp)
                    `OP_LOADM, `OP_LOADI, `OP_POP, `OP_INM: next_state = S_MEM_ACCESS;
                    `OP_STORE, `OP_STORI, `OP_PUSH, `OP_CALL, `OP_OUTM: next_state = S_MEM_ACCESS;
                    `OP_LOAD, `OP_ADD, `OP_SUB, `OP_MUL, `OP_INC, `OP_DEC, `OP_AND, `OP_OR, `OP_XOR, `OP_NOT,
                    `OP_SHL, `OP_SHR, `OP_MOV, `OP_INP, `OP_MOVFRSP: next_state = S_WRITEBACK;
                    default: next_state = S_FETCH_OPCODE; // Jumps, CMP, NOP, RET, OUT
                endcase
            S_MEM_ACCESS:
                case (opcode_from_dp)
                    `OP_LOADM, `OP_LOADI, `OP_POP, `OP_INM: next_state = S_WRITEBACK;
                    default: next_state = S_FETCH_OPCODE;
                endcase
            S_WRITEBACK:
                 if (opcode_from_dp == `OP_RET) next_state = S_EXECUTE; // RET needs to jump after pop
                 else next_state = S_FETCH_OPCODE;
            S_HALTED:       next_state = S_HALTED;
            default:        next_state = S_RESET;
        endcase
    end

    //================================================================
    // Combinational Logic Part 3: Control Signal Outputs
    //================================================================
    always_comb begin
        // --- Default all outputs to inactive state ---
        pc_write_en_out = 1'b0; pc_src_sel_out = `PC_SRC_PC_PLUS_1;
        ir_opcode_load_en_out = 1'b0; ir_operand1_load_en_out = 1'b0; ir_operand2_load_en = 1'b0; ir_operand3_load_en = 1'b0;
        reg_write_en_out = 1'b0; reg_dest_addr_out = '0; reg_src1_addr_out = '0; reg_src2_addr_out = '0; reg_write_data_sel_out = `WB_SRC_ALU;
        imm_val_to_dp_out = '0; alu_op_out = `ALU_NOP; alu_src_a_sel_out = `ALU_A_SRC_REG; alu_src_b_sel_out = `ALU_B_SRC_REG;
        dmem_read_en_out = 1'b0; dmem_write_en_out = 1'b0; dmem_addr_sel_out = `DMEM_ADDR_SRC_IMM;
        sp_op_inc_out = 1'b0; sp_op_dec_out = 1'b0; 
        //gpio_out_we_out = 1'b0;

        // --- Generate signals based on current FSM state ---
        case (current_state)
            S_FETCH_OPCODE: begin pc_write_en_out = 1'b1; ir_opcode_load_en_out = 1'b1; end
            S_FETCH_OP1:    begin pc_write_en_out = 1'b1; ir_operand1_load_en_out = 1'b1; end
            S_FETCH_OP2:    begin pc_write_en_out = 1'b1; ir_operand2_load_en = 1'b1; end
            S_FETCH_OP3:    begin pc_write_en_out = 1'b1; ir_operand3_load_en = 1'b1; end

            S_EXECUTE, S_MEM_ACCESS, S_WRITEBACK: begin
                // Decode operand fields first
                reg_dest_addr_out = operand1_from_dp[`REG_ADDR_WIDTH-1:0];
                reg_src1_addr_out = operand1_from_dp[`REG_ADDR_WIDTH-1:0];
                reg_src2_addr_out = operand2_from_dp[`REG_ADDR_WIDTH-1:0];
                
                // Assemble immediate value based on instruction type
                case(opcode_from_dp)
                    `OP_LOAD, `OP_LOADM, `OP_STORE, `OP_INM, `OP_OUTM, `OP_JMPZ, `OP_JMPN: imm_val_to_dp_out = {operand3_from_dp, operand2_from_dp};
                    `OP_JMP, `OP_CALL, `OP_JE, `OP_JNE, `OP_JS, `OP_JNS, `OP_JC, `OP_JNC, `OP_JO, `OP_JNO: imm_val_to_dp_out = {operand2_from_dp, operand1_from_dp};
                    `OP_SHL, `OP_SHR: imm_val_to_dp_out = {{8{operand2_from_dp[7]}}, operand2_from_dp}; // Sign-extend Imm8
                    default: imm_val_to_dp_out = '0;
                endcase
                
                // Set control signals based on state and opcode
                case(opcode_from_dp)
                    `OP_LOAD: if(current_state==S_WRITEBACK) begin reg_write_en_out=1; alu_src_b_sel_out=`ALU_B_SRC_IMM; alu_op_out=`ALU_PASS_B; end
                    `OP_ADD:  if(current_state==S_WRITEBACK) begin reg_write_en_out=1; alu_op_out=`ALU_ADD; end
                    //`OP_OUT:  if(current_state==S_EXECUTE)   begin gpio_out_we_out=1; end
                    `OP_HALT: if(current_state==S_HALTED)    begin pc_write_en_out=1; pc_src_sel_out=`PC_SRC_PC_CURRENT; end
                    `OP_JMP:  if(current_state==S_EXECUTE)   begin pc_write_en_out=1; pc_src_sel_out=`PC_SRC_IMM; end
                    `OP_JE,`OP_JNE,`OP_JS,`OP_JNS,`OP_JC,`OP_JNC,`OP_JO,`OP_JNO,`OP_JMPZ,`OP_JMPN: 
                              if(current_state==S_EXECUTE && branch_condition_met) begin pc_write_en_out=1; pc_src_sel_out=`PC_SRC_IMM; end
                    `OP_PUSH: if(current_state==S_EXECUTE)   begin sp_op_dec_out=1; end
                              else if(current_state==S_MEM_ACCESS) begin dmem_write_en_out=1; dmem_addr_sel_out=`DMEM_ADDR_SRC_SP; end
                    `OP_POP:  if(current_state==S_EXECUTE)   begin sp_op_inc_out=1; end
                              else if(current_state==S_MEM_ACCESS) begin dmem_read_en_out=1; dmem_addr_sel_out=`DMEM_ADDR_SRC_SP; end
                              else if(current_state==S_WRITEBACK) begin reg_write_en_out=1; reg_write_data_sel_out=`WB_SRC_MEM; end
                    `OP_RET:  if(current_state==S_WRITEBACK) begin sp_op_inc_out=1; dmem_read_en_out=1; dmem_addr_sel_out=`DMEM_ADDR_SRC_SP; pc_src_sel_out=`PC_SRC_MEM; end
                              else if(current_state==S_EXECUTE) begin pc_write_en_out=1; end
                    `OP_MOVFRSP: if(current_state==S_WRITEBACK) begin reg_write_en_out=1; reg_write_data_sel_out=`WB_SRC_SP; end
                    `OP_MOVTOSP: if(current_state==S_WRITEBACK) begin reg_write_en_out=1; reg_dest_addr_out=`SP_REG_ADDR; alu_op_out=`ALU_PASS_A; end
                    // Add all other instructions... this is a simplified example.
                endcase
            end
        endcase
    end
    
     //================================================================
    // Register Module outputs
    //================================================================

    // Operands 2 and 3
    logic [1:0]  shft_oper2_dly;
    logic [1:0]  shft_oper3_dly;
    // Variable delay
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shft_oper2_dly <= 2'b00;
            shft_oper3_dly <= 2'b00;
        end
        else begin
            shft_oper2_dly <= {shft_oper2_dly[0], ir_operand2_load_en};
            shft_oper3_dly <= {shft_oper3_dly[0], ir_operand3_load_en};
        end
    end
    assign ir_operand2_load_en_out  = shft_oper2_dly[0];     // 1 clk delay
    assign ir_operand3_load_en_out  = shft_oper3_dly[0];
//    assign ir_operand2_load_en_out  = shft_oper2_dly[1];   // 2 clk delay
//    assign ir_operand3_load_en_out  = shft_oper3_dly[1];


    //================================================================
    // Testbench Signals
    //================================================================
    // Halted flag
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) halted_o <= 1'b0;
        else        halted_o <= (current_state == S_HALTED);
    end

    // Signal used in testbench to check outputs
    // Rising edge detector
    logic      halted_o_r;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            halted_o_r       <= 1'b0;
            gpio_out_we_out  <= 1'b0;
        end
        else begin
            halted_o_r       <= halted_o;
            gpio_out_we_out  <= !halted_o_r & halted_o;
        end
    end

endmodule