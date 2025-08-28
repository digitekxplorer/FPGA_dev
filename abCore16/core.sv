`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: ab Systems
// Engineer: Al Baeza
// 
// Create Date: 06/18/2025
// Design Name: abCore16 
// Module Name: core
// Project Name: abCore16
// Target Devices: Xilinx FPGA
// Tool Versions: Vivado
// Description: 
// Top-level module for the microprocessor core. This version uses interfaces
// for its main instruction, data, and GPIO buses.
//
// Revision:
// Revision 1.3 - Multiple interrupts (Timer & UART) work
// Revision 1.2 - Refactored to use imem_bus_if, dmem_bus_if, and gpio_bus_if.
// Revision 1.1 - Corrected connections for the reverted DP-centric architecture.
//
//////////////////////////////////////////////////////////////////////////////////

`include "defines.svh"
`include "abcore_interfaces.sv"

module core (
    input  logic clk,
    input  logic rst_n,

    // Interface Ports
    imem_bus_if.master imem_bus,
    dmem_bus_if.master dmem_bus,
    gpio_bus_if.cpu    gpio_bus,
    pic_if.cpu         pic_bus,
    // Interrupt enable
    output logic       enable_int_o,
	// CPU dmem read including mmio registers
//	output logic      mmio_rden_o,          // memory read Rd = Mem[Rs_addr]
    // Debug
    output logic [20:0] dbg_bus_cu,      // 21 signals
    output logic [21:0] dbg_bus_dp,      // 22 signals 
    // CPU halt flag
    output logic       halted_o
);


    //================================================================
    // Internal Wires for CPU buses
    // These signals now connect the internal modules to the interfaces.
    //================================================================
    // --- Instruction Memory Interface ---
    logic [`ADDR_WIDTH-1:0] imem_addr_o;    // To datapath's PC output
    logic [7:0]             imem_rdata_i;   // To control unit's instruction input
    // --- Data Memory Interface ---
    logic                   dmem_we_o;      // From datapath
    logic [`ADDR_WIDTH-1:0] dmem_addr_o;    // From datapath
    logic [`DATA_WIDTH-1:0] dmem_wdata_o;   // From datapath
    logic [`DATA_WIDTH-1:0] dmem_rdata_i;   // To datapath
    // --- GPIO and MMIO Interface ---
    logic [`DATA_WIDTH-1:0] gpio_out_o;     // From datapath
    logic                   gpio_out_we_o;  // From control unit
    logic                   mmio_rden_o;    // memory read Rd = Mem[Rs_addr]
    logic                   dmem_byt_rden_o;  // data memory byte read
    logic                   dmem_byt_wrflg_o;  // data memory byte write
    // --- Interrupt Interface ---
    logic                   save_pc_o;       // interrupt save PC

    // --- Connect Interfaces to Internal Wires <<< NEW SECTION ---
    // This logic bridges the gap between the external interfaces and the
    // internal modules, which still use discrete wire connections.

    // Connect outputs from the core TO the interfaces
    assign imem_bus.addr      = imem_addr_o;
    assign dmem_bus.wren      = dmem_we_o;
    assign dmem_bus.addr      = dmem_addr_o;
    assign dmem_bus.wdata     = dmem_wdata_o;
    assign gpio_bus.data      = gpio_out_o;
    assign gpio_bus.wren      = gpio_out_we_o;
    assign gpio_bus.mmio_rden = mmio_rden_o;
    
    assign gpio_bus.dmem_byt_rden = dmem_byt_rden_o;
    assign gpio_bus.dmem_byt_wrflg = dmem_byt_wrflg_o;

    // Connect inputs TO the core FROM the interfaces
    assign imem_rdata_i = imem_bus.rdata;
    assign dmem_rdata_i = dmem_bus.rdata;
    //-------------------------------------------------------------

    //================================================================
    // Internal Wires connecting Control Unit (CU) and Datapath (DP)
    // (This section is unchanged)
    //================================================================
    logic zf_from_dp, sf_from_dp, cf_from_dp, of_from_dp;
    logic reg_is_zero_from_dp;
    logic reg_is_neg_from_dp;

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
    logic [1:0] dmem_addr_sel_to_dp;
    logic [1:0] dmem_data_sel_to_dp;
    logic sp_op_inc_to_dp;
    logic sp_op_dec_to_dp;
    
    // To reduce pin count for development board assign gpio_in_i here.
    logic [`DATA_WIDTH-1:0] gpio_in_i;
    assign gpio_in_i = gpio_out_o;
    
    
    //================================================================
    // Module Instantiations
    // (The connections here are to the internal wires, not directly to interfaces)
    //================================================================

    // Datapath (DP-centric architecture)
    datapath dp_unit (
        .clk(clk),
        .rst_n(rst_n),
        .grant_vec_i(pic_bus.grant_vec), // granted interrupt number
        .intrpt_i(pic_bus.intrpt),       // interrupt
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
        .save_pc_from_cu(save_pc_o),
        
        // Data memory interface
        .dmem_we_out(dmem_we_o),
        .dmem_addr_out(dmem_addr_o),
        .dmem_wdata_out(dmem_wdata_o),
        .dmem_rdata_in(dmem_rdata_i),
        
        // GPIO interface
        .gpio_in_data_bus(gpio_in_i),
        .gpio_out_data_bus(gpio_out_o),
        
        // Debug
        .dbg_bus_dp(dbg_bus_dp),
        
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
        .intrpt_in(pic_bus.intrpt),
        .pending_int_in(pic_bus.pending_int),

        // Outputs to DP
        .pc_write_en_out(pc_write_en_to_dp),
        .pc_src_sel_out(pc_src_sel_to_dp),
        .rf_write_en_out(rf_write_en_to_dp),
        .rf_dest_addr_out(rf_dest_addr_to_dp),
        .rf_src1_addr_out(rf_src1_addr_to_dp),
        .rf_src2_addr_out(rf_src2_addr_to_dp),
        .rf_write_data_sel_out(rf_write_data_sel_to_dp),
        .flags_write_en_out(flags_write_en_to_dp),
        .imm_val_to_dp_out(imm_val_to_dp),
        .alu_op_out(alu_op_to_dp),
        .alu_src_a_sel_out(alu_src_a_sel_to_dp),
        .alu_src_b_sel_out(alu_src_b_sel_to_dp),
        .dmem_write_en_out(dmem_write_en_to_dp),
        .mmio_rden_out(mmio_rden_o),
        .dmem_byt_rden_out(dmem_byt_rden_o),
        .dmem_byt_wrflg_out(dmem_byt_wrflg_o),
        .dmem_addr_sel_out(dmem_addr_sel_to_dp),
        .dmem_data_sel_out(dmem_data_sel_to_dp),
        .sp_op_inc_out(sp_op_inc_to_dp),
        .sp_op_dec_out(sp_op_dec_to_dp),
        .enable_int_out(enable_int_o),
        .save_pc_out(save_pc_o),
        // GPIO output
        .gpio_out_we_out(gpio_out_we_o),
        // Debug
        .dbg_bus_cu(dbg_bus_cu),
        // Halted flag
        .halted_o(halted_o)
    );
    
endmodule
