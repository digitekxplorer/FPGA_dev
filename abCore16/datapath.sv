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

    // Instruction Memory
    input  logic [7:0]             imem_rdata_i,     // interrupt vector address
    input  logic                   grant_vec_i,      // granted interrupt number
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
//    input  logic        reti_flags_sel_from_cu,
    input  logic [`DATA_WIDTH-1:0] imm_val_from_cu, // Assembled immediate from CU
    input  logic [3:0]  alu_op_from_cu,
    input  logic        alu_src_a_sel_from_cu,
    input  logic        alu_src_b_sel_from_cu,
    input  logic        dmem_write_en_from_cu,
    input  logic [1:0]  dmem_addr_sel_from_cu,
    input  logic [1:0]  dmem_data_sel_from_cu,
    input  logic        imem_addr_sel_from_cu,
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
    output logic [19:0] dbg_bus_dp,

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
logic [ 3:0]            flags_sav;
// Register File
logic [`DATA_WIDTH-1:0] rf_rdata1, rf_rdata2;
logic [`DATA_WIDTH-1:0] rf_wdata_final;
logic [`NUM_GP_REGS-1:0] [`DATA_WIDTH-1:0] register_file;
logic [`ADDR_WIDTH-1:0] sp_reg;

logic [`ADDR_WIDTH-1:0] imem_addr_gen;
logic [15:0]            grant_int_addr;
logic [ 3:0]            irq_vec_sav;
logic                   imem_addr_sel_from_cu_r;
logic                   imem_addr_sel_fedge;
logic                   imem_addr_sel_redge;

    //================================================================
    // Program Counter (PC) and Flags
    //================================================================
    // Insruction memory address mux to read from IVT for interrupt entry
    always_comb begin
        if (imem_addr_sel_from_cu) begin
            pc_to_imem_addr = imem_addr_gen;  // IVT_BASE + (irq_num << 1) + 1
        end
        else begin
            pc_to_imem_addr = pc_reg;
        end
    end
    
    // imem_addr generator for interrupts
    // IVT_BASE + (irq_num << 1) + 1
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin; 
            imem_addr_gen   <= `IVT_BASE_ADDR;  // IVT_BASE
        end
        // get interrupt address
        else if (imem_addr_sel_redge) begin
            imem_addr_gen   <= `IVT_BASE_ADDR + irq_vec_sav;  // IVT_BASE + (irq_num << 1)
        end         
        else if (imem_addr_sel_from_cu) begin
            imem_addr_gen   <= imem_addr_gen + 1;   // IVT_BASE + (irq_num << 1) + 1
        end
        // set for next interrput
        else if (imem_addr_sel_fedge) begin
            imem_addr_gen   <= `IVT_BASE_ADDR;  // IVT_BASE + (irq_num << 1)
        end   
    end
    
    // Capture interrupt number in service
    // grant_vec_i from pic.sv
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin; 
            irq_vec_sav   <= 3'h0;  // interrupt number
        end
        // save the interrupt number when irq is granted
        else if (intrpt_i) begin
            irq_vec_sav   <=  grant_vec_i;  // IVT_BASE + (irq_num << 1)
        end
        // get ready for next interrupt
        else if (imem_addr_sel_fedge) begin
            irq_vec_sav   <=  '0;  
        end         
    end
    
    // one clock delay
    logic [2:0] imem_addr_sel_shft;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            imem_addr_sel_from_cu_r <= 1'b0;
            imem_addr_sel_shft      <= 3'b000;
            imem_addr_sel_fedge     <= 1'b0; 
        end
        else begin
            imem_addr_sel_from_cu_r <= imem_addr_sel_from_cu;
            imem_addr_sel_shft <= { imem_addr_sel_shft[1:0], imem_addr_sel_from_cu };
            if (imem_addr_sel_shft[1:0] == 2'b01 ) begin
               imem_addr_sel_fedge  <= 1'b1;
            end 
            else begin
               imem_addr_sel_fedge  <= 1'b0;
            end 
        end 
    end
    assign imem_addr_sel_redge = (imem_addr_sel_shft[1:0] == 2'b10);
    
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            grant_int_addr      <= 16'h0; 
        end
        else if (imem_addr_sel_from_cu_r) begin
            if (imem_addr_gen[0]) begin
                grant_int_addr[7:0]      <= imem_rdata_i; 
            end
            else begin
                grant_int_addr[15:8]     <= imem_rdata_i; 
            end 
        end 
    end
    
//    assign pc_to_imem_addr = pc_reg;

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
            `PC_SRC_MEM:        pc_next_calculated = dmem_rdata_in;        //010
            `PC_SRC_PC_CURRENT: pc_next_calculated = pc_reg;               //011
            `PC_SRC_ALU:        pc_next_calculated = alu_result_internal;  //100
            // Entry address for Interrupt from IVT in instruction memory
            `PC_SRC_IVT:        pc_next_calculated = grant_int_addr;       //101
            // RETI after interrupt; restore PC
            `PC_SRC_RESTORE:    pc_next_calculated = pc_int_reti;          //110
            default:            pc_next_calculated = pc_reg;
        endcase
    end

    // --- Flags Logic ---
    // save  flags during Interrupt process
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            flags_sav  <= 4'h0;
        end
        else if (save_pc_from_cu) begin
            flags_sav  <= {ZF_to_cu, SF_to_cu, CF_to_cu, OF_to_cu};
        end
    end
    
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ZF_to_cu <= 1'b0;
            SF_to_cu <= 1'b0;
            CF_to_cu <= 1'b0;
            OF_to_cu <= 1'b0;
        end
        else if (flags_write_en_from_cu) begin 
            // restore flags save during interrupt entry
//            if (reti_flags_sel_from_cu) begin
            if (pc_src_sel_from_cu == `PC_SRC_RESTORE) begin
                ZF_to_cu <= flags_sav[3];
                SF_to_cu <= flags_sav[2];
                CF_to_cu <= flags_sav[1];
                OF_to_cu <= flags_sav[0];
            end
            // normal flags saved
            else begin
                ZF_to_cu <= alu_zf;
                SF_to_cu <= alu_sf;
                CF_to_cu <= alu_cf;
                OF_to_cu <= alu_of;            
            end
        end
    end
 

//    always_ff @(posedge clk or negedge rst_n) begin
//        if (!rst_n) begin
//            ZF_to_cu <= 1'b0;
//            SF_to_cu <= 1'b0;
//            CF_to_cu <= 1'b0;
//            OF_to_cu <= 1'b0;
//        end
//        else if (flags_write_en_from_cu) begin 
//            ZF_to_cu <= alu_zf;
//            SF_to_cu <= alu_sf;
//            CF_to_cu <= alu_cf;
//            OF_to_cu <= alu_of;
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
            `DMEM_ADDR_SRC_IVT: dmem_addr_out = `IVT_BASE_ADDR;    // IVT base + irq_num << 1         
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
	
	// Gemini found the error below. A Mux is already used to assign dmem_wdata_out.
    // assign dmem_wdata_out = rf_rdata1;

    // GPIO Output
    assign gpio_out_data_bus = rf_rdata1;

    // Register-based jump condition flags to CU
    assign reg_is_zero_to_cu = (rf_rdata1 == 16'b0);
    assign reg_is_neg_to_cu  = rf_rdata1[15];
    
    //================================================================
    // Debug
    //================================================================
    
// ZF_to_cu, SF_to_cu, CF_to_cu, OF_to_cu,
// reg_is_zero_to_cu,
// reg_is_neg_to_cu
    
    // assign debug bus; 14 signals [13:0]
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dbg_bus_dp <= '0;
        end
        else begin 
            dbg_bus_dp <= { reg_is_neg_to_cu, reg_is_zero_to_cu, ZF_to_cu, SF_to_cu, CF_to_cu, OF_to_cu, pc_reg[13:0] };
       end
    end

endmodule
