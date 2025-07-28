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
// General Design Notes:
// Instructions that require a 16-bit immediate value from instruction memory
// need an extra one clock delay to assemble the both bytes from BRAM to create
// the 16-bit value (imm_val_to_dp_out from imem_rdata_i).

`include "defines.svh"

module control_unit (
    input  logic clk,
    input  logic rst_n,
    // From Instruction Memory
    input  logic [7:0]             imem_rdata_i, // Fetches one byte at a time
    
    // --- Inputs from Datapath's Flags ---
    input  logic       ZF_in, SF_in, CF_in, OF_in,
    input  logic       reg_is_zero_in,
    input  logic       reg_is_neg_in,

    // --- Outputs to Datapath ---
    // PC Control
    output logic       pc_write_en_out,
    output logic [2:0] pc_src_sel_out,

    // Register File Control
    output logic       rf_write_en_out,
    output logic [`REG_ADDR_WIDTH-1:0] rf_dest_addr_out,
    output logic [`REG_ADDR_WIDTH-1:0] rf_src1_addr_out,
    output logic [`REG_ADDR_WIDTH-1:0] rf_src2_addr_out,
    output logic [1:0] rf_write_data_sel_out,
    // Flags Register Control
    output logic       flags_write_en_out,
    // Immediate Value
    output logic [`DATA_WIDTH-1:0] imm_val_to_dp_out,
    // ALU Control
    output logic [3:0] alu_op_out,
    output logic       alu_src_a_sel_out,
    output logic       alu_src_b_sel_out,
    // Data Memory Control
    output logic       dmem_write_en_out,
    output logic       mmio_rden_out,        // Rd = Mem[Rs_addr]
    output logic [1:0] dmem_addr_sel_out,
    output logic [1:0] dmem_data_sel_out,
    // Stack Pointer Control
    output logic       sp_op_inc_out,
    output logic       sp_op_dec_out,
    // GPIO Control
    output logic       gpio_out_we_out,
    
    // Halted flag
    output logic       halted_o
);

    // Local Signals  
    logic       ir_opcode_load_en;
    logic       ir_operand1_load_en;
    logic       ir_operand2_load_en;
    logic       ir_operand3_load_en;
    logic       ir_operand4_load_en;
    logic       ir_operand2_load_en_dly;
    logic       ir_operand3_load_en_dly;
    logic       ir_operand4_load_en_dly;
     
    logic [7:0] ir_opcode_reg;
    logic [7:0] ir_operand1_reg; // Holds byte 2 of instruction
    logic [7:0] ir_operand2_reg; // Holds byte 3 of instruction
    logic [7:0] ir_operand3_reg; // Holds byte 4 of instruction
    logic [7:0] ir_operand4_reg; // Holds byte 4 of instruction
    
    logic       gpio_out_we;
    
    logic       mmio_rden;

    //================================================================
    // FSM State Definition
    //================================================================
    typedef enum logic [3:0] { 
        S_RESET, S_FETCH_OPCODE, 
        S_DECODE,
        S_FETCH_OP1, S_FETCH_OP2, S_FETCH_OP3, S_FETCH_OP4,
        S_BRAM_DLY, S_BRANCH_DLY, // ab: one clk delays
        S_RTN_ADDR,
        S_EXECUTE, S_MEM_ACCESS, S_PCWREN, S_WRITEBACK, S_HALTED
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
        case(ir_opcode_reg)
            // 5-byte instructions
            `OP_LOADFR, `OP_STORFR: total_instr_bytes = 3'd5;
            // 4-byte instructions
            `OP_LOAD, `OP_STORE, `OP_LOADM, `OP_INM, `OP_OUTM, `OP_JMPZ, `OP_JMPN, `OP_L_AND, `OP_L_OR: total_instr_bytes = 3'd4;
            // 3-byte instructions
            `OP_ADD, `OP_SUB, `OP_MUL, `OP_AND, `OP_OR, `OP_XOR, `OP_CMP, `OP_MOV, `OP_SHL, `OP_SHR,
            `OP_JMP, `OP_JE, `OP_JNE, `OP_JS, `OP_JNS, `OP_JC, `OP_JNC, `OP_JO, `OP_JNO, `OP_CALL,
            `OP_LOADI, `OP_STORI, `OP_L_NOT: total_instr_bytes = 3'd3;
            // 2-byte instructions
            `OP_INC, `OP_DEC, `OP_NOT, `OP_INP, `OP_OUT, `OP_PUSH, `OP_POP, `OP_MOVFRSP, `OP_MOVTOSP: total_instr_bytes = 3'd2;
            // 1-byte instructions
            `OP_RET, `OP_NOP, `OP_HALT: total_instr_bytes = 3'd1;
            default: total_instr_bytes = 3'd1;
        endcase
        
        branch_condition_met = 
            (ir_opcode_reg == `OP_JE   && ZF_in)  || (ir_opcode_reg == `OP_JNE  && !ZF_in) ||
            (ir_opcode_reg == `OP_JS   && SF_in)  || (ir_opcode_reg == `OP_JNS  && !SF_in) ||
            (ir_opcode_reg == `OP_JC   && CF_in)  || (ir_opcode_reg == `OP_JNC  && !CF_in) ||
            (ir_opcode_reg == `OP_JO   && OF_in)  || (ir_opcode_reg == `OP_JNO  && !OF_in) ||
            (ir_opcode_reg == `OP_JMPZ && reg_is_zero_in) || (ir_opcode_reg == `OP_JMPN && reg_is_neg_in);
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
                if (ir_opcode_reg == `OP_HALT)      next_state = S_HALTED;
                else if (total_instr_bytes == 1)    next_state = S_EXECUTE;
                else                                next_state = S_FETCH_OP1;
            end
            
            S_FETCH_OP1: if (total_instr_bytes > 2) begin 
                             next_state = S_FETCH_OP2;
                         end
                         else begin 
                             next_state = S_EXECUTE; 
                         end
            
            S_FETCH_OP2: if (total_instr_bytes > 3) begin 
                             next_state = S_FETCH_OP3;
                         end
                         else begin 
                             // ab: add one clk delay to wait for data for operand read from BRAM
                             case (ir_opcode_reg)
                                 `OP_JE,`OP_JNE,`OP_JS,`OP_JNS,`OP_JC,`OP_JNC,`OP_JO,`OP_JNO, `OP_JMP,`OP_SHL, `OP_CALL: next_state = S_BRAM_DLY;   // add one clk delay for BRAM access
                                 default: next_state = S_EXECUTE;
                             endcase
                         end
            
            S_FETCH_OP3: if (total_instr_bytes > 4) begin 
                             next_state = S_FETCH_OP4;
                         end
                         else begin 
                             case (ir_opcode_reg)
                                 `OP_JMPZ,`OP_JMPN: next_state = S_BRAM_DLY;
                                 default: next_state = S_EXECUTE;
                             endcase
                         end
                 
            // there are only two instructions that need 4 operands: OP_LOADFR and OP_STORFR     
            S_FETCH_OP4:    next_state = S_EXECUTE;
            
            // For Jumps, we need one clk delay to setup destination address (imm_val_to_dp_out)
            S_BRAM_DLY: 
                case (ir_opcode_reg)
//                    `OP_CALL: begin next_state = S_PC_REG_DLY; end
                    default: next_state = S_EXECUTE;
                endcase
            
            S_EXECUTE:
                case (ir_opcode_reg)
                    `OP_LOADM, `OP_POP, `OP_INM: next_state = S_MEM_ACCESS;
                    `OP_STORE, `OP_STORI, `OP_PUSH, `OP_CALL, `OP_OUTM: next_state = S_MEM_ACCESS;
                    `OP_RET, `OP_STORFR: next_state = S_MEM_ACCESS;
                    `OP_LOADI: next_state = S_MEM_ACCESS;           // July 11, 2025; fix for pointers
//                    `OP_LOADI: next_state = S_WRITEBACK;
//                    `OP_LOADFR, `OP_LOADI: next_state = S_WRITEBACK;
//                    `OP_LOADFR: next_state = S_WRITEBACK;
                    `OP_LOADFR: next_state = S_MEM_ACCESS;                        // TODO: check
                    `OP_L_AND, `OP_L_OR, `OP_L_NOT: next_state = S_WRITEBACK;
                    `OP_LOAD, `OP_ADD, `OP_SUB, `OP_CMP, `OP_MUL, `OP_INC, `OP_DEC, `OP_AND, `OP_OR, `OP_XOR, `OP_NOT,
                    `OP_SHL, `OP_SHR, `OP_MOV, `OP_INP, `OP_MOVFRSP: next_state = S_WRITEBACK;
                    `OP_JE,`OP_JNE,`OP_JS,`OP_JNS,`OP_JC,`OP_JNC,`OP_JO,`OP_JNO,`OP_JMPZ,`OP_JMPN: 
                        if (branch_condition_met) begin
                            next_state = S_BRANCH_DLY;
                        end
                        else begin
                            next_state = S_FETCH_OPCODE;
                        end
                    `OP_JMP: next_state = S_BRANCH_DLY; 
                    default: next_state = S_FETCH_OPCODE; // Jumps, CMP, NOP, RET, OUT
                endcase
                
            // For Jumps, we need one clk delay to get new opcode loaded into ir_opcode_reg
            S_BRANCH_DLY:
                case (ir_opcode_reg)
                    `OP_RET: next_state = S_MEM_ACCESS;
                    default: next_state = S_FETCH_OPCODE;
                endcase
                
            S_MEM_ACCESS:
                case (ir_opcode_reg)
                    `OP_LOADM, `OP_LOADI, `OP_POP, `OP_INM: next_state = S_WRITEBACK;
                    `OP_LOADFR: next_state = S_WRITEBACK;                                    // TODO: check
                    `OP_RET: next_state = S_PCWREN;
                    default: next_state = S_FETCH_OPCODE;
                endcase

            S_PCWREN: begin 
                next_state = S_RTN_ADDR; 
            end

            // Need extra delay for the PC register
            S_RTN_ADDR: begin 
                next_state = S_FETCH_OPCODE; 
            end
                
            S_WRITEBACK:
                case (ir_opcode_reg)
                    //
                    default: next_state = S_FETCH_OPCODE;
                endcase
//                 if (ir_opcode_reg == `OP_RET) next_state = S_EXECUTE; // RET needs to jump after pop
//                 else next_state = S_FETCH_OPCODE;
                 
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
        ir_opcode_load_en = 1'b0; ir_operand1_load_en = 1'b0; 
        ir_operand2_load_en = 1'b0; ir_operand3_load_en = 1'b0; 
        ir_operand4_load_en = 1'b0;
        rf_write_en_out = 1'b0; rf_dest_addr_out = '0; 
        rf_src1_addr_out = '0; rf_src2_addr_out = '0; rf_write_data_sel_out = `WB_SRC_ALU;
        imm_val_to_dp_out = '0; alu_op_out = `ALU_NOP; alu_src_a_sel_out = `ALU_A_SRC_REG; 
        alu_src_b_sel_out = `ALU_B_SRC_REG; dmem_write_en_out = 1'b0; 
        mmio_rden = 1'b0;
        dmem_addr_sel_out = `DMEM_ADDR_SRC_IMM; dmem_data_sel_out = `DMEM_DATA_SRC_RF1;
        sp_op_inc_out = 1'b0; sp_op_dec_out = 1'b0; flags_write_en_out = 1'b0;
        gpio_out_we = 1'b0;

        // --- Generate signals based on current FSM state ---
        case (current_state)
            S_FETCH_OPCODE: begin pc_write_en_out = 1'b1; ir_opcode_load_en = 1'b1; end
            S_FETCH_OP1:    begin pc_write_en_out = 1'b1; ir_operand1_load_en = 1'b1; end
            S_FETCH_OP2:    begin pc_write_en_out = 1'b1; ir_operand2_load_en = 1'b1; end
            S_FETCH_OP3:    begin pc_write_en_out = 1'b1; ir_operand3_load_en = 1'b1; end
            S_FETCH_OP4:    begin pc_write_en_out = 1'b1; ir_operand4_load_en = 1'b1; end
            
            S_BRAM_DLY: begin 
                    // 
            end   
            
            S_BRANCH_DLY: begin 
                //
            end

            // Add states to this list that access the datatpath control signals
            S_EXECUTE, S_MEM_ACCESS, S_WRITEBACK, S_RTN_ADDR, S_PCWREN: begin
                // Decode operand fields first
                // The first operand is always the destination
                rf_dest_addr_out = ir_operand1_reg[`REG_ADDR_WIDTH-1:0];
                
                
//                case(ir_opcode_reg)
//                    `OP_MOV: begin
//                        rf_src1_addr_out = ir_operand2_reg[`REG_ADDR_WIDTH-1:0];
//                        rf_src2_addr_out = ir_operand2_reg[`REG_ADDR_WIDTH-1:0]; // Not used, but ok
//                    end 
//                    `OP_L_AND, `OP_L_OR: begin
//                        rf_src1_addr_out = ir_operand2_reg[`REG_ADDR_WIDTH-1:0];
//                        rf_src2_addr_out = ir_operand3_reg[`REG_ADDR_WIDTH-1:0];
//                    end
//                    `OP_L_NOT: begin
//                         rf_src1_addr_out = ir_operand2_reg[`REG_ADDR_WIDTH-1:0];
//                         rf_src2_addr_out = ir_operand2_reg[`REG_ADDR_WIDTH-1:0]; // Not used
//                    end

//                    // FIX: Specific routing for LOADFR
//                    `OP_LOADFR: begin // Rd, R_base, #off16
//                        // Read R_base (Op2) for ALU 'A' input
//                        rf_src1_addr_out = ir_operand2_reg[`REG_ADDR_WIDTH-1:0];
//                        rf_src2_addr_out = '0; // Not used
//                    end

//                    // FIX: Specific routing for STORFR
//                    `OP_STORFR: begin // Rt, R_base, #off16
//                        // Read R_base (Op2) for ALU 'A' input
//                        rf_src1_addr_out = ir_operand2_reg[`REG_ADDR_WIDTH-1:0];
//                        // Read Rt (Op1) for data memory write data
//                        rf_src2_addr_out = ir_operand1_reg[`REG_ADDR_WIDTH-1:0];
//                    end

//                    // FIX: Specific routing for LOADI
//                    `OP_LOADI: begin // Rd, Rs_addr
//                        // Read Rs_addr (Op2) for ALU 'A' input (to pass to dmem addr)
//                        rf_src1_addr_out = ir_operand2_reg[`REG_ADDR_WIDTH-1:0];
//                        rf_src2_addr_out = '0; // Not used
//                    end

//                    // FIX: Specific routing for STORI
//                    `OP_STORI: begin // Rt_val, Rs_addr
//                        // Read Rs_addr (Op2) for ALU 'A' input (to pass to dmem addr)
//                        rf_src1_addr_out = ir_operand2_reg[`REG_ADDR_WIDTH-1:0];
//                        // Read Rt_val (Op1) for data memory write data
//                        rf_src2_addr_out = ir_operand1_reg[`REG_ADDR_WIDTH-1:0];
//                    end

//                    default: begin // Default for ADD, SUB, etc.
//                        rf_src1_addr_out = ir_operand1_reg[`REG_ADDR_WIDTH-1:0];
//                        rf_src2_addr_out = ir_operand2_reg[`REG_ADDR_WIDTH-1:0];
//                    end
//                endcase
                
                case(ir_opcode_reg)
                    `OP_MOV: begin
                        rf_src1_addr_out = ir_operand2_reg[`REG_ADDR_WIDTH-1:0];     // write to different reg
                        rf_src2_addr_out = ir_operand2_reg[`REG_ADDR_WIDTH-1:0];
                    end 
                    `OP_L_AND, `OP_L_OR, `OP_L_NOT: begin  // 3 operands: Rx = (Ry!=0 && Rz!=0); for L_NOT 3 operand not used
                        rf_src1_addr_out = ir_operand2_reg[`REG_ADDR_WIDTH-1:0];     // write to different reg
                        rf_src2_addr_out = ir_operand3_reg[`REG_ADDR_WIDTH-1:0];
                    end
                    `OP_STORFR, `OP_LOADFR, `OP_STORI, `OP_LOADI: begin
                        rf_src1_addr_out = ir_operand2_reg[`REG_ADDR_WIDTH-1:0];
                        rf_src2_addr_out = ir_operand1_reg[`REG_ADDR_WIDTH-1:0];
                    end 
                    default: begin
                        rf_src1_addr_out = ir_operand1_reg[`REG_ADDR_WIDTH-1:0];     // write back to same reg
                        rf_src2_addr_out = ir_operand2_reg[`REG_ADDR_WIDTH-1:0];
                    end
                endcase
                
                
                // Assemble immediate value based on instruction type
                case(ir_opcode_reg)
                    `OP_LOAD, `OP_LOADM, `OP_STORE, `OP_INM, `OP_OUTM, `OP_JMPZ, `OP_JMPN: 
                        imm_val_to_dp_out = {ir_operand3_reg, ir_operand2_reg};
                    `OP_JMP, `OP_JE, `OP_JNE, `OP_JS, `OP_JNS, `OP_JC, `OP_JNC, `OP_JO, `OP_JNO, `OP_CALL: 
                        imm_val_to_dp_out = {ir_operand2_reg, ir_operand1_reg};
                    `OP_SHL, `OP_SHR: 
                        imm_val_to_dp_out = {{8{ir_operand2_reg[7]}}, ir_operand2_reg}; // Sign-extend Imm8
                    `OP_STORFR, `OP_LOADFR: 
                        imm_val_to_dp_out = {ir_operand4_reg, ir_operand3_reg};
                    default: 
                        imm_val_to_dp_out = '0;
                endcase
                
                // Set control signals based on state and opcode
                case(ir_opcode_reg)
                    // Note: these signals are asserted during S_WRITEBACK state
                    `OP_LOAD: if(current_state==S_WRITEBACK) begin rf_write_en_out=1; alu_src_b_sel_out=`ALU_B_SRC_IMM; alu_op_out=`ALU_PASS_B; end
                    `OP_ADD:  if(current_state==S_WRITEBACK) begin flags_write_en_out=1; rf_write_en_out=1; alu_op_out=`ALU_ADD; end
                    `OP_SUB:  if(current_state==S_WRITEBACK) begin flags_write_en_out=1; rf_write_en_out=1; alu_op_out=`ALU_SUB; end
                    `OP_CMP:  if(current_state==S_WRITEBACK) begin flags_write_en_out=1; alu_op_out=`ALU_SUB; end  // don't update reg
                    `OP_MUL:  if(current_state==S_WRITEBACK) begin flags_write_en_out=1; rf_write_en_out=1; alu_op_out=`ALU_MUL; end
                    `OP_INC:  if(current_state==S_WRITEBACK) begin flags_write_en_out=1; rf_write_en_out=1; alu_op_out=`ALU_INC; end
                    `OP_DEC:  if(current_state==S_WRITEBACK) begin flags_write_en_out=1; rf_write_en_out=1; alu_op_out=`ALU_DEC; end
                    `OP_AND:  if(current_state==S_WRITEBACK) begin flags_write_en_out=1; rf_write_en_out=1; alu_op_out=`ALU_AND; end
                    `OP_OR:   if(current_state==S_WRITEBACK) begin flags_write_en_out=1; rf_write_en_out=1; alu_op_out=`ALU_OR; end
                    `OP_XOR:  if(current_state==S_WRITEBACK) begin flags_write_en_out=1; rf_write_en_out=1; alu_op_out=`ALU_XOR; end
                    `OP_NOT:  if(current_state==S_WRITEBACK) begin flags_write_en_out=1; rf_write_en_out=1; alu_op_out=`ALU_NOT; end
                    `OP_L_AND:  if(current_state==S_WRITEBACK) begin flags_write_en_out=1; rf_write_en_out=1; alu_op_out=`ALU_L_AND; end
                    `OP_L_OR:   if(current_state==S_WRITEBACK) begin flags_write_en_out=1; rf_write_en_out=1; alu_op_out=`ALU_L_OR; end
                    `OP_L_NOT:  if(current_state==S_WRITEBACK) begin flags_write_en_out=1; rf_write_en_out=1; alu_op_out=`ALU_L_NOT; end
                    
                    `OP_MOV: if(current_state==S_WRITEBACK) begin 
                        rf_write_en_out=1;
                        alu_src_a_sel_out = `ALU_A_SRC_REG;
                        rf_write_data_sel_out=`WB_SRC_ALU; 
                        alu_op_out=`ALU_PASS_A; 
                    end
                    
                    `OP_MOVFRSP: if(current_state==S_WRITEBACK) begin 
                        rf_write_en_out=1; 
                        rf_write_data_sel_out=`WB_SRC_SP;
                    end
                    
                    `OP_MOVTOSP: if(current_state==S_EXECUTE) begin
                        rf_write_en_out=1; 
                        rf_dest_addr_out=`SP_REG_ADDR; 
                        alu_op_out=`ALU_PASS_A; 
                    end
                    
                    // Note: these signals are asserted during S_HALTED state
                    `OP_HALT: if(current_state==S_HALTED)    begin pc_write_en_out=1; pc_src_sel_out=`PC_SRC_PC_CURRENT; end
                    
                    // Note: these signals are asserted during S_EXECUTE state
                    `OP_OUT:  if(current_state==S_EXECUTE)   begin gpio_out_we=1; end
                    `OP_JMP:  if(current_state==S_EXECUTE)   begin pc_write_en_out=1; pc_src_sel_out=`PC_SRC_IMM; end
                    
                    // Note: these signals are asserted during mix of states
                    `OP_SHL: if(current_state==S_EXECUTE) begin
                                 alu_src_b_sel_out=`ALU_B_SRC_IMM;        // select operand from BRAM
                             end
                             else if(current_state==S_WRITEBACK) begin 
                                 flags_write_en_out=1'b1;                  // capture flags
                                 rf_write_en_out=1'b1;                    // write result back to register file
                                 alu_src_b_sel_out=`ALU_B_SRC_IMM;         // select operand from BRAM
                                 alu_op_out=`ALU_SHL;                      // select shift left function in ALU
                              end
                    `OP_SHR: if(current_state==S_EXECUTE) begin
                                 alu_src_b_sel_out=`ALU_B_SRC_IMM;         // select operand from BRAM
                             end
                             else if(current_state==S_WRITEBACK) begin 
                                 flags_write_en_out=1'b1;                  // capture flags
                                 rf_write_en_out=1'b1;                    // write result back to register file
                                 alu_src_b_sel_out=`ALU_B_SRC_IMM;         // select operand from BRAM
                                 alu_op_out=`ALU_SHR;                      // select shift right function in ALU
                              end

                    `OP_JE,`OP_JNE,`OP_JS,`OP_JNS,`OP_JC,`OP_JNC,`OP_JO,`OP_JNO,`OP_JMPZ,`OP_JMPN: 
                        if(current_state==S_EXECUTE && branch_condition_met) begin 
                            pc_write_en_out=1'b1; 
                            pc_src_sel_out=`PC_SRC_IMM; 
                        end
                    
                    `OP_STORE: if(current_state==S_EXECUTE)   begin
                                   // nothing to do
                               end
                               else if(current_state==S_MEM_ACCESS) begin 
                                   dmem_write_en_out=1'b1; 
                                   dmem_addr_sel_out=`DMEM_ADDR_SRC_IMM; 
                               end 

                    // During CALL instruction, we have to write the return address to the stack.
                    `OP_CALL: if(current_state==S_EXECUTE)   begin
                                   pc_write_en_out=1'b1; 
                                   pc_src_sel_out=`PC_SRC_IMM; 
                                   // rtn addr
                                   dmem_data_sel_out = `DMEM_DATA_SRC_PC;   // for rtn addr
                                   dmem_write_en_out=1'b1; 
                                   dmem_addr_sel_out=`DMEM_ADDR_SRC_SP;
                               end
                               else if(current_state==S_MEM_ACCESS) begin  
                                   pc_src_sel_out=`PC_SRC_PC_CURRENT;       // don't increment PC
                                   pc_write_en_out=1'b1;
                                   ir_opcode_load_en = 1'b1;                // load new opcode
                                   sp_op_dec_out=1'b1;
                               end               
                    
                    `OP_LOADM: if(current_state==S_EXECUTE)   begin
                                   // nothing to do
                               end
                               else if(current_state==S_MEM_ACCESS) begin  
                                   dmem_addr_sel_out=`DMEM_ADDR_SRC_IMM; 
                               end
                               else if(current_state==S_WRITEBACK) begin 
                                   rf_write_en_out=1'b1; 
                                   rf_write_data_sel_out=`WB_SRC_MEM; 
                               end

                    `OP_PUSH: if(current_state==S_EXECUTE)   begin 
                                  dmem_addr_sel_out=`DMEM_ADDR_SRC_SP;  
                              end
                              else if(current_state==S_MEM_ACCESS) begin 
                                  sp_op_dec_out=1'b1;
                                  dmem_write_en_out=1'b1; 
                                  dmem_addr_sel_out=`DMEM_ADDR_SRC_SP;
                              end
                              
                    `OP_POP:  if(current_state==S_EXECUTE)   begin 
                                  sp_op_inc_out=1'b1; 
                              end
                              else if(current_state==S_MEM_ACCESS) begin 
                                  dmem_addr_sel_out=`DMEM_ADDR_SRC_SP; 
                              end
                              else if(current_state==S_WRITEBACK) begin 
                                  rf_write_en_out=1'b1; 
                                  rf_write_data_sel_out=`WB_SRC_MEM; 
                              end
                    
                    `OP_RET:  if(current_state==S_EXECUTE) begin 
                                  sp_op_inc_out=1'b1; 
                                  dmem_addr_sel_out=`DMEM_ADDR_SRC_SP; 
                                  pc_src_sel_out=`PC_SRC_MEM; 
                              end
                              else if(current_state==S_MEM_ACCESS) begin 
                                  dmem_addr_sel_out=`DMEM_ADDR_SRC_SP;
                                  pc_src_sel_out=`PC_SRC_MEM; 
                              end
                              else if(current_state==S_PCWREN) begin 
                                  dmem_addr_sel_out=`DMEM_ADDR_SRC_SP;
                                  pc_src_sel_out=`PC_SRC_MEM;
                                  pc_write_en_out=1'b1; 
                              end
                              else if(current_state==S_RTN_ADDR) begin
                                  dmem_addr_sel_out=`DMEM_ADDR_SRC_SP;
                                  pc_src_sel_out=`PC_SRC_MEM;  
                              end                 

                    // 4 operand instructions (or 5 total bytes)
                    
//                    `OP_LOADFR: begin
//                        // These signals are needed across multiple states to calculate address
//                        // These signals are needed across S_EXECUTE and S_MEM_ACCESS
//                        dmem_addr_sel_out = `DMEM_ADDR_SRC_ALU;
//                        alu_op_out = `ALU_ADD;
//                        alu_src_a_sel_out = `ALU_A_SRC_REG;
//                        alu_src_b_sel_out = `ALU_B_SRC_IMM;
//                        rf_write_data_sel_out = `WB_SRC_MEM;
                    
//                        // This signal is asserted ONLY in the final state
//                        if (current_state == S_WRITEBACK) begin
//                            // write to Register File
//                            rf_write_en_out = 1'b1;
//                        end
//                    end
                    
                    
                    
                    `OP_LOADFR: 
                        if(current_state==S_EXECUTE) begin 
                            dmem_addr_sel_out=`DMEM_ADDR_SRC_ALU;
                            alu_op_out=`ALU_ADD;                   // [R_base + IMM]
                            alu_src_a_sel_out=`ALU_A_SRC_REG;      // src R_base
                            alu_src_b_sel_out=`ALU_B_SRC_IMM;      // IMM
                            rf_write_data_sel_out=`WB_SRC_MEM;     // sel dmem_rdata_in
                        end
                        else if(current_state==S_MEM_ACCESS) begin 
                            dmem_addr_sel_out=`DMEM_ADDR_SRC_ALU;
                            alu_op_out=`ALU_ADD;                   // [R_base + IMM]
                            alu_src_a_sel_out=`ALU_A_SRC_REG;      // src R_base
                            alu_src_b_sel_out=`ALU_B_SRC_IMM;      // IMM
                            rf_write_data_sel_out=`WB_SRC_MEM;     // sel dmem_rdata_in
                        end
                        else if(current_state==S_WRITEBACK) begin 
                            dmem_addr_sel_out=`DMEM_ADDR_SRC_ALU;
                            alu_op_out=`ALU_ADD;                   // [R_base + IMM]
                            alu_src_a_sel_out=`ALU_A_SRC_REG;      // src R_base
                            alu_src_b_sel_out=`ALU_B_SRC_IMM;      // IMM
                            rf_write_data_sel_out=`WB_SRC_MEM;     // sel dmem_rdata_in
                            // write to Register File
                            rf_write_en_out=1;                     // write to Rd
                        end
                        
//                    `OP_LOADFR: 
//                        if(current_state==S_EXECUTE) begin 
//                            dmem_addr_sel_out=`DMEM_ADDR_SRC_ALU;
//                            alu_op_out=`ALU_ADD;                   // [R_base + IMM]
//                            alu_src_a_sel_out=`ALU_A_SRC_REG;      // src R_base
//                            alu_src_b_sel_out=`ALU_B_SRC_IMM;      // IMM
//                            rf_write_data_sel_out=`WB_SRC_MEM;     // sel dmem_rdata_in
//                        end
//                        else if(current_state==S_WRITEBACK) begin 
//                            dmem_addr_sel_out=`DMEM_ADDR_SRC_ALU;
//                            alu_op_out=`ALU_ADD;                   // [R_base + IMM]
//                            alu_src_a_sel_out=`ALU_A_SRC_REG;      // src R_base
//                            alu_src_b_sel_out=`ALU_B_SRC_IMM;      // IMM
//                            rf_write_data_sel_out=`WB_SRC_MEM;     // sel dmem_rdata_in
//                            // write to Register File
//                            rf_write_en_out=1;                     // write to Rd
//                        end


// Gemini update
//                        `OP_STORFR: begin
//                            // These signals are needed across S_EXECUTE and S_MEM_ACCESS
//                            dmem_addr_sel_out = `DMEM_ADDR_SRC_ALU;
//                            alu_op_out = `ALU_ADD;
//                            alu_src_a_sel_out = `ALU_A_SRC_REG;
//                            alu_src_b_sel_out = `ALU_B_SRC_IMM;
//                            dmem_data_sel_out = `DMEM_DATA_SRC_RF2;
                        
//                            // This signal is asserted ONLY in the memory access state
//                            if (current_state == S_MEM_ACCESS) begin
//                                dmem_write_en_out = 1'b1;
//                            end
//                        end
                        
                    `OP_STORFR: 
                        if(current_state==S_EXECUTE) begin 
                            dmem_addr_sel_out=`DMEM_ADDR_SRC_ALU;
                            alu_op_out=`ALU_ADD;                   // [R_base + IMM]
                            alu_src_a_sel_out=`ALU_A_SRC_REG;      // src R_base
                            alu_src_b_sel_out=`ALU_B_SRC_IMM;      // IMM
                            // data out to DMEM
                            dmem_data_sel_out=`DMEM_DATA_SRC_RF2;  // data from Rt
                        end
                        else if(current_state==S_MEM_ACCESS) begin 
                            dmem_addr_sel_out=`DMEM_ADDR_SRC_ALU;
                            alu_op_out=`ALU_ADD;                   // [R_base + IMM]
                            alu_src_a_sel_out=`ALU_A_SRC_REG;      // src R_base
                            alu_src_b_sel_out=`ALU_B_SRC_IMM;      // IMM
                            // data out to DMEM
                            dmem_data_sel_out=`DMEM_DATA_SRC_RF2;  // data from Rt
                            // write to DMEM
                            dmem_write_en_out=1'b1;                // write to dmem
                        end
                        
                    // Rd = Mem[Rs_addr]
                    `OP_LOADI: 
                        if(current_state==S_EXECUTE) begin 
                            dmem_addr_sel_out=`DMEM_ADDR_SRC_ALU;
                            alu_op_out=`ALU_PASS_A;                // [Rs_addr]
                            alu_src_a_sel_out=`ALU_A_SRC_REG;      // src Rs
                            rf_write_data_sel_out=`WB_SRC_MEM;     // sel dmem_rdata_in
                            // <<< NEW
                            mmio_rden = 1'b1;               // read from dmem including mmio registers
                        end
                        // July 11, 2025; fix for pointers
                        else if(current_state==S_MEM_ACCESS) begin  
                            dmem_addr_sel_out=`DMEM_ADDR_SRC_ALU;
                            alu_op_out=`ALU_PASS_A;                // [Rs_addr]
                            alu_src_a_sel_out=`ALU_A_SRC_REG;      // src Rs
                            rf_write_data_sel_out=`WB_SRC_MEM;     // sel dmem_rdata_in
                        end
                        else if(current_state==S_WRITEBACK) begin 
                            dmem_addr_sel_out=`DMEM_ADDR_SRC_ALU;
                            alu_op_out=`ALU_PASS_A;                // [Rs_addr]
                            alu_src_a_sel_out=`ALU_A_SRC_REG;      // src Rs
                            rf_write_data_sel_out=`WB_SRC_MEM;     // sel dmem_rdata_in
                            // write to Register File
                            rf_write_en_out=1;                     // write to Rd
                        end
                        
                    // Mem[Rs_addr] = Rt_val
                    `OP_STORI: 
                        if(current_state==S_EXECUTE) begin 
                            dmem_addr_sel_out=`DMEM_ADDR_SRC_ALU;  // alu_result_internal
                            alu_op_out=`ALU_PASS_A;                // [Rs_addr]
                            alu_src_a_sel_out=`ALU_A_SRC_REG;      // src Rs_addr
                //            alu_src_b_sel_out=`ALU_B_SRC_IMM;      // IMM
                            // data out to DMEM
                            dmem_data_sel_out=`DMEM_DATA_SRC_RF2;  // data from Rt_val
                        end
                        else if(current_state==S_MEM_ACCESS) begin 
                            dmem_addr_sel_out=`DMEM_ADDR_SRC_ALU;  // alu_result_internal
                            alu_op_out=`ALU_PASS_A;                // [Rs_addr]
                            alu_src_a_sel_out=`ALU_A_SRC_REG;      // src Rs_addr
//                            alu_src_b_sel_out=`ALU_B_SRC_IMM;      // IMM
                            // data out to DMEM
                            dmem_data_sel_out=`DMEM_DATA_SRC_RF2;  // data from Rt_val
                            // write to DMEM
                            dmem_write_en_out=1'b1;                // write to dmem
                        end
                                              
                    // Add all other instructions... this is a simplified example.
                endcase
            end
        endcase
    end
    
    // Register the mmio_rden_out output and align to data
    // Function: Rd = Mem[Rs_addr]
    logic  mmio_rden_r;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mmio_rden_out   <= 1'b0;
            mmio_rden_r     <= 1'b0;
        end else begin
            mmio_rden_r     <= mmio_rden;
            mmio_rden_out   <= mmio_rden_r;
        end
    end
    

//1. Data Transfer & Memory Operations
//These instructions move data between registers, memory, and immediate values.
//Mnemonic	Operands            Opcode	Description
//LOAD	    Rd, #imm16          0x01	Load Immediate: Loads a 16-bit immediate value into destination register Rd.
//LOADM	    Rd, addr16          0x03	Load from Memory: Loads a 16-bit value from the specified memory address into Rd.
//STORE	    Rs, addr16          0x02	Store to Memory: Stores the 16-bit value from source register Rs to the specified memory address.
//LOADFR	Rd, R_base, #off16	0x04	Load Frame-Relative: Loads a value from memory at address [R_base + signed_offset] into Rd. Used for accessing stack variables.
//STORFR	Rt, R_base, #off16	0x05	Store Frame-Relative: Stores the value from Rt to memory at address [R_base + signed_offset]. Used for accessing stack variables.
//LOADI	    Rd, Rs_addr	        0x06	Load Indirect: Loads a value from the memory address specified in Rs_addr and places it into Rd. Rd = Mem[Rs_addr].
//STORI	    Rt_val, Rs_addr     0x07	Store Indirect: Stores the value from Rt_val into memory at the address specified in Rs_addr. Mem[Rs_addr] = Rt_val.

    
    //================================================================
    // Instruction Register (IR) components
    //================================================================
    // Important: Do not modify the these IR registers.  The timing delay
    // for ir_operand2_reg and ir_operand3_reg must be maintain to capture
    // the correct 16-bit values for 4-byte instructions.  The concat value 
    // imm_val_to_dp_out becomes valid after the second load_en_dly.
    // total_instr_bytes == 3'd5
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ir_opcode_reg   <= `OP_NOP;
            ir_operand1_reg <= 8'h00;
            ir_operand2_reg <= 8'h00;
            ir_operand3_reg <= 8'h00;
            ir_operand4_reg <= 8'h00;
        end else begin
            if (ir_opcode_load_en) begin  ir_opcode_reg   <= imem_rdata_i; end
            if (ir_operand1_load_en) begin ir_operand1_reg <= imem_rdata_i; end
//            if ( total_instr_bytes == 3'd4 ) begin 
//            end
            // currently, there are two 5-byte instructions: OP_LOADFR and OP_STORFR
            if ( total_instr_bytes == 3'd5 ) begin
                if (ir_operand2_load_en_dly) begin ir_operand2_reg <= imem_rdata_i; end  // dly needed for BRAM latency
                if (ir_operand3_load_en_dly) begin ir_operand3_reg <= imem_rdata_i; end  // dly needed for BRAM latency
                if (ir_operand4_load_en_dly) begin ir_operand4_reg <= imem_rdata_i; end   // dly needed for BRAM latency
            end
            else begin
                if (ir_operand2_load_en_dly) begin ir_operand2_reg <= imem_rdata_i; end  // dly needed for BRAM latency
                if (ir_operand3_load_en_dly) begin ir_operand3_reg <= imem_rdata_i; end  // dly needed for BRAM latency
            end
            //
        end
    end
    
    //================================================================
    // Register Module outputs
    //================================================================

    // Operands 2, 3, and 4
    logic [1:0]  shft_oper2_dly;
    logic [1:0]  shft_oper3_dly;
    logic [1:0]  shft_oper4_dly;
    // Variable delay
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shft_oper2_dly <= 2'b00;
            shft_oper3_dly <= 2'b00;
            shft_oper4_dly <= 2'b00;
        end
        else begin
            shft_oper2_dly <= {shft_oper2_dly[0], ir_operand2_load_en};
            shft_oper3_dly <= {shft_oper3_dly[0], ir_operand3_load_en};
            shft_oper4_dly <= {shft_oper4_dly[0], ir_operand4_load_en};
        end
    end
    assign ir_operand2_load_en_dly  = shft_oper2_dly[0];     // 1 clk delay
    assign ir_operand3_load_en_dly  = shft_oper3_dly[0];
    assign ir_operand4_load_en_dly  = shft_oper4_dly[0];
//    assign ir_operand2_load_en  = shft_oper2_dly[1];   // 2 clk delay
//    assign ir_operand3_load_en  = shft_oper3_dly[1];

    //================================================================
    // Register Output Signals
    //================================================================
//    always_ff @(posedge clk or negedge rst_n) begin
//        if (!rst_n) begin 
//            gpio_out_we_out <= 1'b0;
//        end
//        else begin
//            gpio_out_we_out <= gpio_out_we;
//        end    
//    end
    
    assign gpio_out_we_out = gpio_out_we;

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
//    logic      halted_o_r;
//    always_ff @(posedge clk or negedge rst_n) begin
//        if (!rst_n) begin
//            halted_o_r       <= 1'b0;
//        end
//        else begin
//            halted_o_r       <= halted_o;
//        end
//    end

endmodule
