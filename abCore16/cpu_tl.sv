`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: ab Systems
// Engineer: Al Baeza
// 
// Create Date: 06/18/2025
// Design Name: abCore16 Top Level
// Module Name: cpu_tl
// Project Name: abCore16
// Target Devices: Xilinx FPGA
// Tool Versions: Vivado
// Description: 
// Top-level module for the abCore16 CPU. This version is updated to correctly
// instantiate the original DP-centric datapath and a compatible control unit.
//
// Revision:
// Revision 1.1 - Corrected connections for the reverted DP-centric architecture.
// Additional Comments:
// The architecture is now DP-centric. The Datapath fetches and latches 
// instruction bytes into its IRs and provides them to the Control Unit.
//
//////////////////////////////////////////////////////////////////////////////////

`include "defines.svh"

//`define SIMULATION

module cpu_tl (
    input  logic clk,
    input  logic rst_n,

    // GPIO Interface
    input  logic [`DATA_WIDTH-1:0] gpio_in_i,
    output logic [`DATA_WIDTH-1:0] gpio_out_o,
    output logic                   gpio_out_we_o,
    
    // CPU halt flag
    output logic                   halted_o
);

    //================================================================
    // Internal Wires connecting Control Unit (CU) and Datapath (DP)
    //================================================================

    // --- From Datapath TO Control Unit ---
    logic [7:0] opcode_byte_from_dp;
    logic [7:0] operand1_byte_from_dp;
    logic [7:0] operand2_byte_from_dp;
    logic [7:0] operand3_byte_from_dp;
    logic zf_from_dp, sf_from_dp, cf_from_dp, of_from_dp;
    logic reg_is_zero_from_dp;
    logic reg_is_neg_from_dp;

    // --- From Control Unit TO Datapath ---
    logic pc_write_en_to_dp;
    logic [2:0] pc_src_sel_to_dp;
    logic ir_opcode_load_en_to_dp;
    logic ir_operand1_load_en_to_dp;
    logic ir_operand2_load_en_to_dp;
    logic ir_operand3_load_en_to_dp; // For 4th byte
    logic reg_write_en_to_dp;
    logic [`REG_ADDR_WIDTH-1:0] reg_dest_addr_to_dp;
    logic [`REG_ADDR_WIDTH-1:0] reg_src1_addr_to_dp;
    logic [`REG_ADDR_WIDTH-1:0] reg_src2_addr_to_dp;
    logic [1:0] reg_write_data_sel_to_dp;
    logic [`DATA_WIDTH-1:0] imm_val_to_dp;
    logic [3:0] alu_op_to_dp;
    logic [1:0] alu_src_a_sel_to_dp;
    logic [1:0] alu_src_b_sel_to_dp;
    logic dmem_read_en_to_dp;
    logic dmem_write_en_to_dp;
    logic [1:0] dmem_addr_sel_to_dp;
    logic sp_op_inc_to_dp;
    logic sp_op_dec_to_dp;
    
    // Instruction Memory Interface
    logic [`ADDR_WIDTH-1:0] imem_addr_o;    // Address to Instruction Memory (driven by DP's PC)
    logic [7:0]             imem_rdata_i;   // Data from Instruction Memory (read by DP)
    // Data Memory Interface
    logic                   dmem_we_o;
    logic [`ADDR_WIDTH-1:0] dmem_addr_o;
    logic [`DATA_WIDTH-1:0] dmem_wdata_o;
    logic [`DATA_WIDTH-1:0] dmem_rdata_i;


    //================================================================
    // Module Instantiations
    //================================================================

    // Datapath (DP-centric architecture)
    datapath dp_unit (
        .clk(clk),
        .rst_n(rst_n),
        .imem_rdata_i(imem_rdata_i), // DP must receive instruction data to load its IR
        .pc_to_imem_addr(imem_addr_o),
        
        // Control signals from CU
        .pc_write_en_from_cu(pc_write_en_to_dp),
        .pc_src_sel_from_cu(pc_src_sel_to_dp),
        .ir_opcode_load_en_from_cu(ir_opcode_load_en_to_dp),
        .ir_operand1_load_en_from_cu(ir_operand1_load_en_to_dp),
        .ir_operand2_load_en_from_cu(ir_operand2_load_en_to_dp),
        .ir_operand3_load_en_from_cu(ir_operand3_load_en_to_dp),
        .reg_write_en_from_cu(reg_write_en_to_dp),
        .reg_dest_addr_from_cu(reg_dest_addr_to_dp),
        .reg_src1_addr_from_cu(reg_src1_addr_to_dp),
        .reg_src2_addr_from_cu(reg_src2_addr_to_dp),
        .reg_write_data_sel_from_cu(reg_write_data_sel_to_dp),
        .imm_val_from_cu(imm_val_to_dp),
        .alu_op_from_cu(alu_op_to_dp),
        .alu_src_a_sel_from_cu(alu_src_a_sel_to_dp),
        .alu_src_b_sel_from_cu(alu_src_b_sel_to_dp),
        .dmem_read_en_from_cu(dmem_read_en_to_dp),
        .dmem_write_en_from_cu(dmem_write_en_to_dp),
        .dmem_addr_sel_from_cu(dmem_addr_sel_to_dp),
        .sp_op_inc_from_cu(sp_op_inc_to_dp),
        .sp_op_dec_from_cu(sp_op_dec_to_dp),
        
        // Data memory interface
        .dmem_we_out(dmem_we_o),
        .dmem_addr_out(dmem_addr_o),
        .dmem_wdata_out(dmem_wdata_o),
        .dmem_rdata_in(dmem_rdata_i),
        
        // GPIO interface
        .gpio_in_data_bus(gpio_in_i),
        .gpio_out_data_bus(gpio_out_o),
        
        // Outputs to CU
        .opcode_byte_to_cu(opcode_byte_from_dp),
        .operand1_byte_to_cu(operand1_byte_from_dp),
        .operand2_byte_to_cu(operand2_byte_from_dp),
        .operand3_byte_to_cu(operand3_byte_from_dp),
        .ZF_to_cu(zf_from_dp),
        .SF_to_cu(sf_from_dp),
        .CF_to_cu(cf_from_dp),
        .OF_to_cu(of_from_dp),
        .reg_is_zero_to_cu(reg_is_zero_from_dp),
        .reg_is_neg_to_cu(reg_is_neg_from_dp)
    );

    // Control Unit (must be compatible with DP-centric architecture)
    control_unit cu_unit (
        .clk(clk),
        .rst_n(rst_n),
        
        // Inputs from DP (Instruction Bytes and Flags)
        .opcode_from_dp(opcode_byte_from_dp),
        .operand1_from_dp(operand1_byte_from_dp),
        .operand2_from_dp(operand2_byte_from_dp),
        .operand3_from_dp(operand3_byte_from_dp),
        .ZF_in(zf_from_dp),
        .SF_in(sf_from_dp),
        .CF_in(cf_from_dp),
        .OF_in(of_from_dp),
        .reg_is_zero_in(reg_is_zero_from_dp),
        .reg_is_neg_in(reg_is_neg_from_dp),

        // Outputs to DP
        .pc_write_en_out(pc_write_en_to_dp),
        .pc_src_sel_out(pc_src_sel_to_dp),
        .ir_opcode_load_en_out(ir_opcode_load_en_to_dp),
        .ir_operand1_load_en_out(ir_operand1_load_en_to_dp),
        .ir_operand2_load_en_out(ir_operand2_load_en_to_dp),
        .ir_operand3_load_en_out(ir_operand3_load_en_to_dp),
        .reg_write_en_out(reg_write_en_to_dp),
        .reg_dest_addr_out(reg_dest_addr_to_dp),
        .reg_src1_addr_out(reg_src1_addr_to_dp),
        .reg_src2_addr_out(reg_src2_addr_to_dp),
        .reg_write_data_sel_out(reg_write_data_sel_to_dp),
        .imm_val_to_dp_out(imm_val_to_dp),
        .alu_op_out(alu_op_to_dp),
        .alu_src_a_sel_out(alu_src_a_sel_to_dp),
        .alu_src_b_sel_out(alu_src_b_sel_to_dp),
        .dmem_read_en_out(dmem_read_en_to_dp),
        .dmem_write_en_out(dmem_write_en_to_dp),
        .dmem_addr_sel_out(dmem_addr_sel_to_dp),
        .sp_op_inc_out(sp_op_inc_to_dp),
        .sp_op_dec_out(sp_op_dec_to_dp),
        
        // GPIO output
        .gpio_out_we_out(gpio_out_we_o),
        
        // Halted flag
        .halted_o(halted_o)
    );
    

//================================================================
// Conditional Memory Instantiation (`generate` block)
//================================================================
`ifdef SIMULATION
    // --- FOR SIMULATION: Use a fast, behavioral memory model ---
    `define IMEM_HEX_FILE "myProg_add.hex" // << CHANGE THIS TO YOUR TEST PROGRAM
    
    initial begin
        $display("INFO: Compiling with SIMULATION behavioral memory model.");
        $display("INFO: Loading instruction memory from '%s'.", `IMEM_HEX_FILE);
    end

    // Behavioral Instruction and Data Memory
    logic [7:0] instruction_memory [0:8191];
    logic [`DATA_WIDTH-1:0] data_memory [0: (`DATA_MEMORY_WORDS/2)-1]; // Corrected indexing for word array

    initial $readmemh(`IMEM_HEX_FILE, instruction_memory);

    // One clock latency to match BRAM behavior
    always_ff @(posedge clk) begin
        imem_rdata_i  <= instruction_memory[imem_addr_o];    // no addr to dout dly
    end
    
    assign dmem_rdata_i = data_memory[dmem_addr_o >> 1];

    always_ff @(posedge clk) begin
        if (dmem_we_o) begin
            data_memory[dmem_addr_o >> 1] <= dmem_wdata_o;
        end
    end

`else
    // --- FOR SYNTHESIS: Use the real BRAM IP Core ---
    initial begin
        $display("INFO: Compiling with SYNTHESIS BRAM IP Core model.");
    end
    
    // Create a wire for the word-aligned data memory address
    logic [`ADDR_WIDTH-2:0] dmem_word_addr;
    
    // Convert the byte address from the CPU to a word address for the BRAM
    // by right-shifting by one (equivalent to dropping the LSB).
    assign dmem_word_addr = dmem_addr_o >> 1;

    // Program Memory IP Core
    // NOTE: instruction memory access is 8-bits while 
    //       data memory access is 16-bits
    abCore16_blk_mem cpu_mem (
        // Instruction Memory Interface
        .clka   ( clk ),
        .ena    ( 1'b1 ),
        .wea    ( 1'b0 ),       // ROM
        .addra  ( imem_addr_o ),
        .dina   ( 9'b0 ),       // ROM
        .douta  ( imem_rdata_i ),   // 8-bits
        // Data Memory Interface
        .clkb   ( clk ),
        .enb    ( 1'b1 ),
        .web    ( dmem_we_o ),
        .addrb  ( dmem_word_addr ), // THE FIX: Connect the corrected word address
        .dinb   ( {2'b00, dmem_wdata_o} ),
        .doutb  ( dmem_rdata_i )    // 16-bits
    );

`endif
    

endmodule
