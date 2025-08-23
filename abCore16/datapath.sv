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
// Revision 1.2 - Multiple interrupts (Timer & UART) work
// Revision 1.1 - Fixed problem with flags that caused interrupts to stop working
// Revision 1.1 - Reverted to original architecture and synced with latest defines.
//
//////////////////////////////////////////////////////////////////////////////////


`include "defines.svh"

module datapath (
    input  logic clk,
    input  logic rst_n,

    // Interrupts
    input  logic [3:0]             grant_vec_i,      // granted interrupt number
    input  logic                   intrpt_i,         // interrupt
    
    output logic [`ADDR_WIDTH-1:0] pc_to_imem_addr,

    // Control Signals from Control Unit
    input  logic        pc_write_en_from_cu,
    input  logic [2:0]  pc_src_sel_from_cu,
    input  logic        rf_write_en_from_cu,
    input  logic [`REG_ADDR_WIDTH-1:0] rf_dest_addr_from_cu,
    input  logic [`REG_ADDR_WIDTH-1:0] rf_src1_addr_from_cu,
    input  logic [`REG_ADDR_WIDTH-1:0] rf_src2_addr_from_cu,
    input  logic [1:0]  rf_write_data_sel_from_cu,
    input  logic        flags_write_en_from_cu,
    input  logic [`DATA_WIDTH-1:0] imm_val_from_cu, // Assembled immediate from CU
    input  logic [3:0]  alu_op_from_cu,
    input  logic        alu_src_a_sel_from_cu,
    input  logic        alu_src_b_sel_from_cu,
    input  logic        dmem_write_en_from_cu,
    input  logic [1:0]  dmem_addr_sel_from_cu,
    input  logic [1:0]  dmem_data_sel_from_cu,
    input  logic        sp_op_inc_from_cu,
    input  logic        sp_op_dec_from_cu,
    input  logic        save_pc_from_cu,

    // Data Memory Interface
    output logic                   dmem_we_out,
    output logic [`ADDR_WIDTH-1:0] dmem_addr_out,
    output logic [`DATA_WIDTH-1:0] dmem_wdata_out,
    input  logic [`DATA_WIDTH-1:0] dmem_rdata_in,

    // GPIO Interface
    input  logic [`DATA_WIDTH-1:0] gpio_in_data_bus,
    output logic [`DATA_WIDTH-1:0] gpio_out_data_bus,
    
    // Debug
        // Debug
    output logic [21:0] dbg_bus_dp,

    // Outputs to Control Unit (Flags)
    output logic                   ZF_to_cu, SF_to_cu, CF_to_cu, OF_to_cu,
    output logic                   reg_is_zero_to_cu,
    output logic                   reg_is_neg_to_cu
);

// ==============
// Local signals
// ==============
// ALU
logic [`DATA_WIDTH-1:0] alu_in_a, alu_in_b;
logic [`DATA_WIDTH-1:0] alu_result_internal;
logic alu_zf, alu_sf, alu_cf, alu_of;
// PC
logic [`ADDR_WIDTH-1:0] pc_reg, pc_next_calculated;
logic [`ADDR_WIDTH-1:0] pc_int_reti;
logic [ 5:0]            flags_sav;
// Register File
logic [`DATA_WIDTH-1:0] rf_rdata1, rf_rdata2;
logic [`DATA_WIDTH-1:0] rf_wdata_final;
logic [`NUM_GP_REGS-1:0] [`DATA_WIDTH-1:0] register_file;
logic [`ADDR_WIDTH-1:0] sp_reg;

logic                   restore_flags;
logic                   dmem_addr_rdy;


    // =================================
    // Interrupt FSM
    // =================================
    logic [`ADDR_WIDTH-1:0] dmem_addr_fsm;
    // State machine for TX FIFO control
    typedef enum logic [1:0] {
        IDLE,
        WT_CU_FSM,
        MEM_DLY,
        CLEANUP
    } dp_state_t;
    
    dp_state_t dp_state;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dp_state <= IDLE;
            dmem_addr_fsm <= '0;
        end else begin
            //
            case (dp_state)
                IDLE: begin
                    if (intrpt_i) begin
                        // setup dmem address using IVT_BASE + (irq_num << 1)
                        dmem_addr_fsm   <= `IVT_BASE_ADDR + (grant_vec_i << 1);  // IVT_BASE + (irq_num << 1)
                        dp_state <= WT_CU_FSM;
                    end
                end
                
                // Wait for control_unit FSM to select IVT address.
                // The CU FSM must wait to complete the instruction before the interrupt.
                WT_CU_FSM: begin
                    if (dmem_addr_rdy) begin
                       dp_state <= MEM_DLY;
                    end
                end
                
                // 1 clk delay for memory output
                MEM_DLY: begin
                    dp_state <= CLEANUP;
                end
                               
                CLEANUP: begin
                    dmem_addr_fsm   <= `IVT_BASE_ADDR;
                    dp_state        <= IDLE;          // wait for next interrupt
                end
            endcase
        end
    end
    
    assign dmem_addr_rdy = dmem_addr_sel_from_cu == `DMEM_ADDR_SRC_IVT; // 2'b11

    //================================================================
    // Program Counter (PC) and Flags
    //================================================================
    assign pc_to_imem_addr = pc_reg;

    // save_pc_from_cu
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            pc_reg <= `ADDR_WIDTH'h0000;
        else if (pc_write_en_from_cu) 
            pc_reg <= pc_next_calculated;
    end
    
    // save PC during Interrupt process
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_int_reti <= '0;
        end
        else if (save_pc_from_cu) begin
            pc_int_reti <= pc_reg;
        end
    end

    
    // PC Next Logic
    always_comb begin
        case (pc_src_sel_from_cu)
            `PC_SRC_PC_PLUS_1:  pc_next_calculated = pc_reg + 1;           //000
            `PC_SRC_IMM:        pc_next_calculated = imm_val_from_cu;      //001
            `PC_SRC_MEM:        pc_next_calculated = dmem_rdata_in;        //010, for RET and RETI
            `PC_SRC_PC_CURRENT: pc_next_calculated = pc_reg;               //011
            `PC_SRC_ALU:        pc_next_calculated = alu_result_internal;  //100
            // Entry address for Interrupt from IVT in instruction memory
// -------------- The BIG change -----------------------------
//            `PC_SRC_IVT:        pc_next_calculated = dmem_rdata_in;       //101 for dmem_data
            // RETI after interrupt; restore PC
            `PC_SRC_RESTORE:    pc_next_calculated = pc_int_reti;          //101
            default:            pc_next_calculated = pc_reg;
        endcase
    end

    // --- Flags Logic ---   
    // save flags at the start of an Interrupt during the
    // Fetch Opcode state
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            flags_sav  <= '0;
        end
        // save_pc_from_cu asserted when interrupt condition met
        else if (save_pc_from_cu) begin
            flags_sav  <= {reg_is_neg_to_cu, reg_is_zero_to_cu, ZF_to_cu, SF_to_cu, CF_to_cu, OF_to_cu};
        end
    end
    
 
    // signal used to restore flags after returning from interrupt (ISR)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            restore_flags <= 1'b0;
        end
        // pc_src_sel_from_cu == `PC_SRC_RESTORE during RETI instruction in CU
        else begin
            restore_flags <= pc_src_sel_from_cu == `PC_SRC_RESTORE;
        end
    end
    
    // Save Flags
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ZF_to_cu <= 1'b0;
            SF_to_cu <= 1'b0;
            CF_to_cu <= 1'b0;
            OF_to_cu <= 1'b0;
        end
        // save flags during an ALU operation and use them
        // for the next JXX instruction
        else if (flags_write_en_from_cu) begin 
            ZF_to_cu <= alu_zf;
            SF_to_cu <= alu_sf;
            CF_to_cu <= alu_cf;
            OF_to_cu <= alu_of;
        end
        // Restore flags saved during interrupt entry and use flags
        // with the next instruction after RETI.
        // Flags restored during RETI instruction
        else if (restore_flags) begin 
            ZF_to_cu <= flags_sav[3];
            SF_to_cu <= flags_sav[2];
            CF_to_cu <= flags_sav[1];
            OF_to_cu <= flags_sav[0];
       end
    end
    
    
    // Register-based jump condition flags to CU
    // These two flags are for the current instruction (OP_JMPZ or OP_JMPN)
    // so we don't have to save the flags for future use, possibly after an
    // interrupt.
    assign reg_is_zero_to_cu = (rf_rdata1 == 16'b0);
    assign reg_is_neg_to_cu  = rf_rdata1[15];
    
    // Register-based jump condition flags to CU
    // OP_JMPZ and OP_JMPN
//    always_ff @(posedge clk or negedge rst_n) begin
//        if (!rst_n) begin
//            reg_is_neg_to_cu  <= 1'b0;
//		    reg_is_zero_to_cu <= 1'b0;
//        end
//        // at the end of an interrupt, restore zero and neg flags
//        else if (restore_flags) begin
//            reg_is_neg_to_cu  <= flags_sav[5];
//		    reg_is_zero_to_cu <= flags_sav[4];        
//        end
//        else begin
//            reg_is_zero_to_cu <= (rf_rdata1 == 16'b0);
//            reg_is_neg_to_cu  <= rf_rdata1[15];        
//        end 
//    end
 

    //================================================================
    // Register File (R0-R7) and Stack Pointer (SP)
    //================================================================

    // GPR Asynchronous Read
    assign rf_rdata1 = (rf_src1_addr_from_cu < `NUM_GP_REGS) ? register_file[rf_src1_addr_from_cu] : 16'b0;
    assign rf_rdata2 = (rf_src2_addr_from_cu < `NUM_GP_REGS) ? register_file[rf_src2_addr_from_cu] : 16'b0;

    // GPR Synchronous Write
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < `NUM_GP_REGS; i++) begin
                register_file[i] <= '0; 
            end
        end
        else if (rf_write_en_from_cu && rf_dest_addr_from_cu < `NUM_GP_REGS) begin
            register_file[rf_dest_addr_from_cu] <= rf_wdata_final;
        end
    end

    // Stack Pointer Logic
//    localparam STACK_INIT_VAL_DP = `DATA_MEMORY_BYTES/2;    // 4096 x 16 = 8192 bytes
    localparam STACK_INIT_VAL_DP = `DATA_MEMORY_BYTES;    // 8192 bytes
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            sp_reg <= STACK_INIT_VAL_DP - 2;  // same as decrementing first before using the stack
        else if (sp_op_inc_from_cu) 
            sp_reg <= sp_reg + 2; // Word-aligned stack
        else if (sp_op_dec_from_cu) 
            sp_reg <= sp_reg - 2; // Word-aligned stack
        else if (rf_write_en_from_cu && rf_dest_addr_from_cu == `SP_REG_ADDR) // For MOVTOSP
            sp_reg <= rf_wdata_final;
    end

    //================================================================
    // ALU
    //================================================================

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

    //================================================================
    // Write-back and Output Logic
    //================================================================
    // Write-back data selection for Register File
    always_comb begin
        case (rf_write_data_sel_from_cu)
            `WB_SRC_ALU:    rf_wdata_final = alu_result_internal;  // 00
            `WB_SRC_MEM:    rf_wdata_final = dmem_rdata_in;        // 01
            `WB_SRC_SP:     rf_wdata_final = sp_reg; // For MOVFRSP   10
            `WB_SRC_GPIO:   rf_wdata_final = gpio_in_data_bus;
            default:        rf_wdata_final = alu_result_internal;
        endcase
    end
    
    // Data Memory Connections
    assign dmem_we_out = dmem_write_en_from_cu;
    always_comb begin
        case (dmem_addr_sel_from_cu)
            `DMEM_ADDR_SRC_IMM: dmem_addr_out = imm_val_from_cu;   // 00
            `DMEM_ADDR_SRC_SP:  dmem_addr_out = sp_reg;            // 01
            `DMEM_ADDR_SRC_ALU: dmem_addr_out = alu_result_internal; // For LOADI/STORI
            // IVT entry address
            `DMEM_ADDR_SRC_IVT: dmem_addr_out = dmem_addr_fsm;    // IVT base + irq_num << 1         
            default:            dmem_addr_out = 16'hDEAD;
        endcase
    end
    
    // During CALL instruction, we have to write the return address to the stack.
    always_comb begin
        case (dmem_data_sel_from_cu)
            `DMEM_DATA_SRC_RF1:  dmem_wdata_out = rf_rdata1;   // 00
            `DMEM_DATA_SRC_RF2:  dmem_wdata_out = rf_rdata2;   // 01
            `DMEM_DATA_SRC_PC:   dmem_wdata_out = pc_reg;      // 10 ; for CALL, rtn addr is PC, addr of next instr
            default:             dmem_wdata_out = rf_rdata1;
        endcase
    end

    // GPIO Output
    assign gpio_out_data_bus = rf_rdata1;
    
    //================================================================
    // Debug
    //================================================================
    
    // assign debug bus; 14 signals [13:0]
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dbg_bus_dp <= '0;
        end
        else begin 
            dbg_bus_dp <= { save_pc_from_cu, restore_flags, reg_is_neg_to_cu, reg_is_zero_to_cu, ZF_to_cu, SF_to_cu, CF_to_cu, OF_to_cu, pc_reg[13:0] };
       end
    end

endmodule
