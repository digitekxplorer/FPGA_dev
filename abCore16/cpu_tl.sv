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

// For Synthesis, comment out both defines
`define MEMORYMODELSIM    // use hex file
`define SIMSPEEDUPCLK     // use Testbench 12MHz clock

// --- FOR SIMULATION: Use a fast, behavioral memory model ---
// Remember: Must add new hex files to abCore16 project as a Memory File!!
// `define IMEM_HEX_FILE "myProg_add.hex" // << CHANGE THIS TO YOUR TEST PROGRAM
 `define IMEM_HEX_FILE "myProg_generic.hex" // Comprehensive Test (.ab)
//`define IMEM_HEX_FILE "test_program_short.hex"  // C-like with main() (.ssl)
// `define IMEM_HEX_FILE "test_func.hex"  // Test STORFR, LOADFR (.sal)

module cpu_tl (
    input  logic clk_12MHz,
    input  logic rst_in,

    // GPIO Interface
//    input  logic [`DATA_WIDTH-1:0] gpio_in_i,  // for now reduce pin count
    output logic [`DATA_WIDTH-1:0] gpio_out_o,
    output logic                   gpio_out_we_o,
    
    // CPU halt flag
    output logic                   halted_o
);

    //================================================================
    // Internal Wires connecting Control Unit (CU) and Datapath (DP)
    //================================================================

    // --- From Datapath TO Control Unit ---
    logic zf_from_dp, sf_from_dp, cf_from_dp, of_from_dp;
    logic reg_is_zero_from_dp;
    logic reg_is_neg_from_dp;

    // --- From Control Unit TO Datapath ---
    logic pc_write_en_to_dp;
    logic [2:0] pc_src_sel_to_dp;
    logic rf_write_en_to_dp;
    logic [`REG_ADDR_WIDTH-1:0] rf_dest_addr_to_dp;
    logic [`REG_ADDR_WIDTH-1:0] rf_src1_addr_to_dp;
    logic [`REG_ADDR_WIDTH-1:0] rf_src2_addr_to_dp;
    logic [1:0] rf_write_data_sel_to_dp;
    logic flags_write_en_to_dp;
    logic [`DATA_WIDTH-1:0] imm_val_to_dp;
    logic [3:0] alu_op_to_dp;
    logic       alu_src_a_sel_to_dp;
    logic       alu_src_b_sel_to_dp;
    logic dmem_write_en_to_dp;
    logic dmem_write_en;
    logic [1:0] dmem_addr_sel_to_dp;
    logic [1:0] dmem_data_sel_to_dp;
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
    
    // To rduce pin count for development board assign gpio_in_i here.
    logic [`DATA_WIDTH-1:0] gpio_in_i;
    assign gpio_in_i = gpio_out_o;
    
    
//================================================================
// Conditional Clock Module Instantiation
//================================================================
// To speedup simulation, use the 12MHz clock directly from the testbench
// instead of using the MMCM clock module that takes tens of uSeconds to
// lock.
logic rst_n;
logic locked;

`ifdef SIMSPEEDUPCLK
// --- FOR SIMULATION: Use the Testbench 12MHz clock ---
assign clk = clk_12MHz;
assign rst_n = !rst_in;
assign locked = 1'b1;

`else
// --- FOR SYNTHESIS: Use the real MMCM IP Core ---
clk_wiz_0 abCore16_clk (
    // Clock and pushbutton reset
    .clk_in1   (clk_12MHz ),  // input clk_in1
    .reset     (rst_in),      // input reset; pushbutton
    // outputs
    .clk_out1  (clk),         // 48 MHz
    .locked    (locked)       // clk locked
);

assign rst_n = locked;
`endif
    //================================================================
    // Module Instantiations
    //================================================================

    // Datapath (DP-centric architecture)
    datapath dp_unit (
        .clk(clk),
        .rst_n(rst_n),
        .pc_to_imem_addr(imem_addr_o),
        
        // Control signals from CU
        .pc_write_en_from_cu(pc_write_en_to_dp),
        .pc_src_sel_from_cu(pc_src_sel_to_dp),
        .rf_write_en_from_cu(rf_write_en_to_dp),
        .rf_dest_addr_from_cu(rf_dest_addr_to_dp),
        .rf_src1_addr_from_cu(rf_src1_addr_to_dp),
        .rf_src2_addr_from_cu(rf_src2_addr_to_dp),
        .rf_write_data_sel_from_cu(rf_write_data_sel_to_dp),
        .flags_write_en_from_cu(flags_write_en_to_dp),
        .imm_val_from_cu(imm_val_to_dp),
        .alu_op_from_cu(alu_op_to_dp),
        .alu_src_a_sel_from_cu(alu_src_a_sel_to_dp),
        .alu_src_b_sel_from_cu(alu_src_b_sel_to_dp),
        .dmem_write_en_from_cu(dmem_write_en_to_dp),
        .dmem_addr_sel_from_cu(dmem_addr_sel_to_dp),
        .dmem_data_sel_from_cu(dmem_data_sel_to_dp),
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
        .imem_rdata_i(imem_rdata_i), // DP must receive instruction data to load its IR
        
        // Inputs from DP (Flags)
        .ZF_in(zf_from_dp),
        .SF_in(sf_from_dp),
        .CF_in(cf_from_dp),
        .OF_in(of_from_dp),
        .reg_is_zero_in(reg_is_zero_from_dp),
        .reg_is_neg_in(reg_is_neg_from_dp),

        // Outputs to DP
        .pc_write_en_out(pc_write_en_to_dp),
        .pc_src_sel_out(pc_src_sel_to_dp),
        .rf_write_en_out(rf_write_en_to_dp),
        .rf_dest_addr_out(rf_dest_addr_to_dp),
        .rf_src1_addr_out(rf_src1_addr_to_dp),
        .rf_src2_addr_out(rf_src2_addr_to_dp),
        .rf_write_data_sel_out(rf_write_data_sel_to_dp),
        .flags_write_en_out(flags_write_en_to_dp),           // ab
        .imm_val_to_dp_out(imm_val_to_dp),
        .alu_op_out(alu_op_to_dp),
        .alu_src_a_sel_out(alu_src_a_sel_to_dp),
        .alu_src_b_sel_out(alu_src_b_sel_to_dp),
        .dmem_write_en_out(dmem_write_en_to_dp),
        .dmem_addr_sel_out(dmem_addr_sel_to_dp),
        .dmem_data_sel_out(dmem_data_sel_to_dp),
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
`ifdef MEMORYMODELSIM
    
    initial begin
        $display("INFO: Compiling with SIMULATION behavioral memory model.");
        $display("INFO: Loading instruction memory from '%s'.", `IMEM_HEX_FILE);
    end

    // Behavioral Instruction and Data Memory
    logic [7:0] instruction_memory [0:`DATA_MEMORY_BYTES-1];
    logic [`DATA_WIDTH-1:0] data_memory [0: (`DATA_MEMORY_BYTES/2)-1]; // Corrected indexing for word array

    initial $readmemh(`IMEM_HEX_FILE, instruction_memory);

    // Read from Instruction and Data memory.
    // One clock latency to match BRAM behavior
    always_ff @(posedge clk) begin
        imem_rdata_i  <= instruction_memory[imem_addr_o];    // no addr to dout dly
        dmem_rdata_i = data_memory[dmem_addr_o >> 1];
    end
    
    // Write to Data memory
    always_ff @(posedge clk) begin
        if (dmem_we_o) begin
            data_memory[dmem_addr_o >> 1] <= dmem_wdata_o;
//            instruction_memory[dmem_addr_o >> 1] <= dmem_wdata_o;   // imem is a ROM, don't write to imem
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
        .addra  ( imem_addr_o[12:0] ),
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
