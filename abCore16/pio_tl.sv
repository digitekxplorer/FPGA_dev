`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: ab Systems
// Engineer: Al Baeza
// 
// Create Date: 08/31/2025 11:28:47 AM
// Design Name: Programmable Input Output (PIO)
// Module Name: pio_tl
// Project Name: abCore16 PIO
// Target Devices: Xilinx FPGA
// Tool Versions: Vivado 2024.2
// Description: PIO gives you the power to create custom digital interfaces 
// using 9 instructions that run on dedicated state machine.
// 
// Dependencies: pio_defs.svh
// 
// Revision:
// Revision 1.4 - Fixed and enhanced IRQ instruction 
// Revision 1.3 - Single-cycle instruction execution 
// Revision 1.2 - Instruction set complete: JMP, WAIT, IN, OUT, PUSH, PULL, MOV, SET, IRQ
// Revision 1.1 - Implemented instructions: JMP, WAIT, IN, OUT, PUSH, PULL, MOV, SET
// Revision 1.0 - Implemented instructions: JMP, WAIT, IN, OUT, PUSH, PULL, MOV
// Revision 0.01 - File Created
// Additional Comments:
// 
// TODO:
// 1) Add BRAM for program memory
// 2) Add delay/side effects to SET instruction
// 3) AutoPush and AutoPull with thresholds
// 4) Single cycle instructions
// 5) Clock divider
// 6) Integrate PIO into abCore16 Project
// 7) Build and test in FPGA
//////////////////////////////////////////////////////////////////////////////////

//`include "pio_defs.svh"
`include "defines.svh"

//================================================================
// Top-Level PIO State Machine
//================================================================
//module pio_tl #(
//    parameter int INSTR_MEM_ADDR_WIDTH = 5,
//    parameter int REG_WIDTH = 32,
//    parameter int GPIO_WIDTH = 32,
//    parameter int INSTR_MEM_DEPTH = 32
//) (
module pio_tl (
    input  logic clk,
    input  logic rst_n,
    input  logic pio_go,
    
    // External GPIO interface
    input  logic [`GPIO_WIDTH-1:0] gpio_in,
    output logic [`GPIO_WIDTH-1:0] gpio_out,
    output logic [`GPIO_WIDTH-1:0] gpio_dir,
    
    // Configuration registers
    input  logic [4:0] execctrl_jmp_pin,
    input  logic [4:0] shiftctrl_pull_thresh,
    input  logic [4:0] shiftctrl_push_thresh,
    input  logic       autopush_enable,
    input  logic       autopull_enable,
    input  logic [4:0] pinctrl_in_base,
    input  logic [4:0] pinctrl_out_base,
    input  logic [4:0] pinctrl_out_count,
    input  logic [1:0] state_machine_id,
    // PIO program bootloader
    input  logic        bootload_start,
    input  logic [3:0]  program_select,
    output logic        bootload_done,
    output logic        bootload_error,
    
    // Instruction Memory Programming Interface
//    input  logic                  imem_write_en,
//    input  logic [`INSTR_MEM_ADDR_WIDTH-1:0] imem_write_addr,
//    input  logic [15:0]           imem_write_data,
    
    // FIFO interfaces
    // TX Fifo  
    input  logic [`REG_WIDTH-1:0] tx_fifo_wr_data,
    input  logic                  tx_fifo_wren,
    output logic                  tx_fifo_full,
    // RX Fifo  
    input  logic                  rx_fifo_rden,
    output logic [`REG_WIDTH-1:0] rx_fifo_datout,
    output logic                  rx_fifo_mt,
    
    // IRQ interface
    input  logic [7:0]            irq_flags_in,
    output logic [7:0]            irq_flags_clear,
    output logic [7:0]            irq_clear_cu,
    output logic [7:0]            irq_flags_set,    // IRQ set requests
    
    // IN
    input logic [4:0] shiftctrl_in_count,
    input logic       shiftctrl_in_shiftdir,
    input logic       shiftctrl_autopush_en,
    input logic [4:0] shiftctrl_autopush_thresh,    
    input logic       shiftctrl_autopull_en,
    input logic [4:0] shiftctrl_autopull_thresh,
    // OUT
    // SHIFTCTRL_OUT_SHIFTDIR
    input logic       shiftctrl_out_shiftdir,										
    
    // Debug outputs
//    output logic [`INSTR_MEM_ADDR_WIDTH-1:0] debug_pc,
//    output logic [`REG_WIDTH-1:0]  debug_x_reg,
//    output logic [`REG_WIDTH-1:0]  debug_y_reg,
//    output logic [`REG_WIDTH-1:0]  debug_osr,
//    output logic [4:0]             debug_osr_count,
//    output logic [`REG_WIDTH-1:0]  debug_isr,
//    output logic [4:0]             debug_isr_count,
    output logic [35:0]            dbg_bus_pio,
    output logic                   debug_waiting
);

    // Internal interconnect signals between control unit and datapath
    logic [`INSTR_MEM_ADDR_WIDTH-1:0] pc_current;
    logic [`REG_WIDTH-1:0]  x_reg_value;
    logic [`REG_WIDTH-1:0]  y_reg_value;
    logic [`REG_WIDTH-1:0]  osr_value;
    logic [`REG_WIDTH-1:0]  isr_value;
    logic [4:0]            osr_count;
    logic [4:0]            isr_count;
    logic                  x_is_zero;
    logic                  y_is_zero;
    logic                  x_not_equal_y;
    logic                  osr_below_threshold;
    logic                  isr_above_threshold;
    
    // Control signals from control unit to datapath
    logic        cu_pc_write_en;
    logic [2:0]  cu_pc_src_sel;
    logic        cu_pc_hold;
    logic        cu_x_reg_write_en;
    logic        cu_y_reg_write_en;
    logic [1:0]  cu_x_reg_src_sel;
    logic [1:0]  cu_y_reg_src_sel;
    logic        cu_x_reg_dec_en;
    logic        cu_y_reg_dec_en;
    logic        cu_osr_load_en;
    logic        cu_osr_shift_en;
    logic [1:0]  cu_osr_src_sel;
    logic [4:0]  cu_osr_shift_count;
    logic        cu_osr_shift_dir;
    logic        cu_osr_counter_reset;
    logic        cu_isr_load_en;
    logic        cu_isr_shift_en;
    logic [2:0]  cu_isr_src_sel;
    logic [4:0]  cu_isr_shift_count;
    logic        cu_isr_shift_dir;
    logic        cu_isr_counter_reset;
    logic        cu_gpio_write_en;
    logic        cu_gpio_dir_write_en;
    logic [1:0]  cu_gpio_src_sel;
	
    // MOV control signals from control unit to datapath (NEW)
    logic        cu_mov_write_en;
    logic [2:0]  cu_mov_dest_sel;
    logic [2:0]  cu_mov_src_sel;
    logic [1:0]  cu_mov_op_sel;
    // SET control signals from control unit to datapath
    logic        cu_set_write_en;
    logic [2:0]  cu_set_dest_sel;    // 3 bits for destination
    // IRQ control signals from control unit
    logic        cu_irq_operation_en;
    logic        cu_irq_set_operation;
    logic        cu_irq_wait_for_clear;
    logic [4:0]  cu_irq_target_index;
//    logic [7:0]  cu_irq_set;          // IRQ set outputs

    // TX Fifo
//    logic tx_fifo_full;
    logic tx_fifo_mt;
    logic [31:0] tx_fifo_datout;
    // RX Fifo
    logic [`REG_WIDTH-1:0]  rx_fifo_data;
    logic                  rx_fifo_write;
    logic                  rx_fifo_full;
    
    // Instruction memory interface
    logic [15:0] instruction_data;
    
    // Simple instruction memory implementation with write capability
    logic [15:0] instruction_memory [0:`INSTR_MEM_DEPTH-1];
    
    // Internal signals
    logic        imem_write_en_bootloader;
    logic [4:0]  imem_write_addr_bootloader;
    logic [15:0] imem_write_data_bootloader;
    
//    logic        imem_write_en_manual;     // For manual programming (legacy)
//    logic [4:0]  imem_write_addr_manual;
//    logic [15:0] imem_write_data_manual;
//    logic        imem_write_en_final;
//    logic [4:0]  imem_write_addr_final;
//    logic [15:0] imem_write_data_final;
//    logic        bootloader_active;
    
    // Bootloader BRAM interface
    logic        bram_read_en;
    logic [7:0]  bram_addr;
    logic [15:0] bram_instruction;
    logic [4:0]  program_length;
    logic [7:0]  program_start_addr;
    
    logic        pio_header_sav;
    
    logic [11:0]  dbg_pio_cu;
    logic [ 4:0]  dbg_pio_dp;
	
//	logic [4:0]  set_data;     // Data field (5 bits)
//	assign set_data = instruction_data[4:0];    // Data value (5 bits) [4:0]
    
    
    //================================================================
    // Control Unit Instantiation
    //================================================================
    pio_cu #(
        .ADDR_WIDTH(`INSTR_MEM_ADDR_WIDTH),
        .REG_WIDTH(`REG_WIDTH),
        .GPIO_WIDTH(`GPIO_WIDTH),
        .INSTR_MEM_DEPTH(`INSTR_MEM_DEPTH)
    ) u_control_unit (
        .clk(clk),
        .rst_n(rst_n),
        .pio_go(pio_go),
        
        // Instruction interface - only data input, no address output needed
        .instruction_data(instruction_data),
        
        // Status inputs from datapath
//        .pc_current(pc_current),
        .x_reg_value(x_reg_value),
        .y_reg_value(y_reg_value),
        .osr_value(osr_value),
        .isr_value(isr_value),
        .osr_count(osr_count),
        .isr_count(isr_count),
        .x_is_zero(x_is_zero),
        .y_is_zero(y_is_zero),
        .x_not_equal_y(x_not_equal_y),
        .osr_below_threshold(osr_below_threshold),
        .isr_above_threshold(isr_above_threshold),
        
        // External status inputs
        .gpio_state(gpio_in),
        .irq_flags(irq_flags_in),
//        .tx_fifo_empty(tx_fifo_empty),                 // ab: from testbench
        .tx_fifo_empty(tx_fifo_mt),                      // ab: from TX Fifo
        .rx_fifo_full(rx_fifo_full),
        
        // Configuration inputs
        .execctrl_jmp_pin(execctrl_jmp_pin),
//        .shiftctrl_pull_thresh(shiftctrl_pull_thresh),
        .pinctrl_in_base(pinctrl_in_base),
        .state_machine_id(state_machine_id),
        
        // Control signal outputs to datapath
        .pc_write_en(cu_pc_write_en),
        .pc_src_sel(cu_pc_src_sel),
        .pc_hold(cu_pc_hold),
        .x_reg_write_en(cu_x_reg_write_en),
        .y_reg_write_en(cu_y_reg_write_en),
        .x_reg_src_sel(cu_x_reg_src_sel),
        .y_reg_src_sel(cu_y_reg_src_sel),
        .x_reg_dec_en(cu_x_reg_dec_en),
        .y_reg_dec_en(cu_y_reg_dec_en),
        .osr_load_en(cu_osr_load_en),
        .osr_shift_en(cu_osr_shift_en),
        .osr_src_sel(cu_osr_src_sel),
        .osr_shift_count(cu_osr_shift_count),
        .osr_counter_reset(cu_osr_counter_reset),
//        .osr_shift_dir(cu_osr_shift_dir),
        .isr_load_en(cu_isr_load_en),
        .isr_shift_en(cu_isr_shift_en),
        .isr_src_sel(cu_isr_src_sel),
        .isr_shift_count(cu_isr_shift_count),
        .isr_shift_dir(cu_isr_shift_dir),
        .isr_counter_reset(cu_isr_counter_reset),
        .shiftctrl_in_count(shiftctrl_in_count),
        .shiftctrl_in_shiftdir(shiftctrl_in_shiftdir),
        .shiftctrl_autopush_en(shiftctrl_autopush_en),
        .shiftctrl_autopush_thresh(shiftctrl_autopush_thresh),
        .shiftctrl_autopull_en(shiftctrl_autopull_en),
        .shiftctrl_autopull_thresh(shiftctrl_autopull_thresh),													  
        .gpio_write_en(cu_gpio_write_en),
        .gpio_dir_write_en(cu_gpio_dir_write_en),
        .gpio_src_sel(cu_gpio_src_sel),
        // MOV Control (NEW - ADD THESE LINES)
        .mov_write_en(cu_mov_write_en),
        .mov_dest_sel(cu_mov_dest_sel),
        .mov_src_sel(cu_mov_src_sel),
        .mov_op_sel(cu_mov_op_sel),
		// SET control outputs (ADD THESE)
        .set_write_en(cu_set_write_en),
        .set_dest_sel(cu_set_dest_sel),
		
        // IRQ control outputs (ADD THESE)
        .irq_operation_en(cu_irq_operation_en),
        .irq_set_operation(cu_irq_set_operation),
        .irq_wait_for_clear(cu_irq_wait_for_clear),
        .irq_target_index(cu_irq_target_index),
//        .irq_set(irq_flags_set),                     // set in pio_dp
        
        .tx_fifo_read(tx_fifo_read),
        .rx_fifo_write(rx_fifo_write),
        .irq_clear(irq_clear_cu),
        
        // Debug outputs
 //       .debug_pc(debug_pc),
        .dbg_pio_cu(dbg_pio_cu),
        .debug_waiting(debug_waiting),
        .debug_stalled()
    );
//    assign debug_pc = pc_current;
    
    // output logic [11:0]  dbg_pio_cu,
    //================================================================
    // Datapath Instantiation
    //================================================================
    pio_dp #(
        .ADDR_WIDTH(`INSTR_MEM_ADDR_WIDTH),
        .REG_WIDTH(`REG_WIDTH),
        .GPIO_WIDTH(`GPIO_WIDTH)
    ) u_datapath (
        .clk(clk),
        .rst_n(rst_n),
        
        // Instruction interface - only data input, no address output needed
        .instruction_data(instruction_data),
        // Control signals from control unit
        .pc_write_en(cu_pc_write_en),
        .pc_src_sel(cu_pc_src_sel),
        .pc_hold(cu_pc_hold),
        .x_reg_write_en(cu_x_reg_write_en),
        .y_reg_write_en(cu_y_reg_write_en),
        .x_reg_src_sel(cu_x_reg_src_sel),
        .y_reg_src_sel(cu_y_reg_src_sel),
        .x_reg_dec_en(cu_x_reg_dec_en),
        .y_reg_dec_en(cu_y_reg_dec_en),
        .osr_load_en(cu_osr_load_en),
        .osr_shift_en(cu_osr_shift_en),
        .osr_src_sel(cu_osr_src_sel),
        .osr_shift_count(cu_osr_shift_count),
        .osr_shift_dir(shiftctrl_out_shiftdir),
        .osr_counter_reset(cu_osr_counter_reset),
        .shiftctrl_pull_thresh(shiftctrl_pull_thresh),
        .shiftctrl_push_thresh(shiftctrl_push_thresh),	
        .autopush_enable(autopush_enable),
        .autopull_enable(autopull_enable),												  
        .isr_load_en(cu_isr_load_en),
        .isr_shift_en(cu_isr_shift_en),
        .isr_src_sel(cu_isr_src_sel),
        .isr_shift_count(cu_isr_shift_count),
        .isr_shift_dir(cu_isr_shift_dir),
        .isr_counter_reset(cu_isr_counter_reset),
        .gpio_write_en(cu_gpio_write_en),
        .gpio_dir_write_en(cu_gpio_dir_write_en),
        .gpio_src_sel(cu_gpio_src_sel),
        // MOV Control (NEW - ADD THESE LINES)
        .mov_write_en(cu_mov_write_en),
        .mov_dest_sel(cu_mov_dest_sel),
        .mov_src_sel(cu_mov_src_sel),
        .mov_op_sel(cu_mov_op_sel),
        // SET control outputs (ADD THESE)
        .set_write_en(cu_set_write_en),
        .set_dest_sel(cu_set_dest_sel),
        
//        .tx_fifo_empty(tx_fifo_empty),                 // ab: from testbench
        .tx_fifo_empty(tx_fifo_mt),                      // ab: from TX Fifo
        .rx_fifo_full(rx_fifo_full),
        
        // Data inputs
//        .pc_immediate(instruction_data[4:0]), // Address field for JMP
		// set_data
//        .data_immediate({27'b0, instruction_data[4:0]}), // Simple immediate data
		
		
//        .tx_fifo_data(tx_fifo_data),                   // ab: from testbench
        .tx_fifo_data(tx_fifo_datout),                   // ab: from TX Fifo
        .gpio_in(gpio_in),
        .mapped_pins(gpio_in), // TODO: Apply proper pin mapping logic
        
        // Configuration
        .pinctrl_out_base(pinctrl_out_base),
        .pinctrl_out_count(pinctrl_out_count),
        
        // Status outputs to control unit
        .pc_current(pc_current),
        .x_reg_value(x_reg_value),
        .y_reg_value(y_reg_value),
        .osr_value(osr_value),
        .isr_value(isr_value),
        .osr_count(osr_count),
        .isr_count(isr_count),
        .x_is_zero(x_is_zero),
        .y_is_zero(y_is_zero),
        .x_not_equal_y(x_not_equal_y),
        .osr_below_threshold(osr_below_threshold),
        .isr_above_threshold(isr_above_threshold),
        
        // IRQ
        .irq_operation_en(cu_irq_operation_en),
        .irq_set_operation(cu_irq_set_operation), 
        .irq_wait_for_clear(cu_irq_wait_for_clear),
        .irq_target_index(cu_irq_target_index),
        .irq_set_request(irq_flags_set),
        .irq_clear_request(irq_flags_clear),
        
        .dbg_pio_dp(dbg_pio_dp),
        
        // External outputs
        .gpio_out(gpio_out),
        .gpio_dir(gpio_dir),
        .rx_fifo_data(rx_fifo_data)
//        .rx_fifo_write(rx_fifo_write)
    );
    

    // FIFO interfaces
    // TX FIFO -> OSR (PULL)
    // following code in datapath
    // if(osr_load_en && osr_src_sel==`OSR_SRC_TX_FIFO) osr_register <= tx_fifo_data;
    // TX FIFO
    fifo_TxRx TX_Fifo (
    .clk    (clk),              // input clk
    .srst   (!rst_n),           // input reset
    .din    (tx_fifo_wr_data),  // input [31:0] din
    .wr_en  (tx_fifo_wren),     // input wren
    .rd_en  (tx_fifo_read),     // input rden
    .dout   (tx_fifo_datout),   // output [31:0] dout
    .full   (tx_fifo_full),     // output full
    .empty  (tx_fifo_mt)        // output empty
    );
    
    // RX FIFO
    // ISR -> RX FIFO (PUSH)
    // assign rx_fifo_data = isr_register;   // code in datapath
    // assign rx_fifo_write = 1'b0;          // code in control unit
    fifo_TxRx RX_Fifo (
    .clk    (clk),              // input clk
    .srst   (!rst_n),           // input reset
    .din    (rx_fifo_data),     // input [31:0] din
    .wr_en  (rx_fifo_write),    // input wren
    .rd_en  (rx_fifo_rden),     // input rden
    .dout   (rx_fifo_datout),   // output [31:0] dout
    .full   (rx_fifo_full),     // output full
    .empty  (rx_fifo_mt)        // output empty
    );
    
    //================================================================
    // Program Storage BRAM
    //================================================================
    pio_program_mem pio_prog_mem01 (
        .clk(clk),
        .rst_n(rst_n),
        .bl_read_en(bram_read_en),
        .bl_addr(bram_addr),
        .bl_instruction(bram_instruction),
        .program_select(program_select),
        .pio_header_sav(pio_header_sav),
        .program_length(program_length),
        .program_start_addr(program_start_addr)
    );
    
    //================================================================
    // Bootloader FSM
    //================================================================
    
    logic                  imem_write_en;
    logic [`INSTR_MEM_ADDR_WIDTH-1:0] imem_write_addr;
    logic [15:0]           imem_write_data;
    
    pio_bootloader bootloader01 (
        .clk(clk),
        .rst_n(rst_n),
        .bootload_start(bootload_start),
        .program_select(program_select),
        .bootload_done(bootload_done),
        .bootload_error(bootload_error),
        .pio_header_sav(pio_header_sav),
        .bram_read_en(bram_read_en),
        .bram_addr(bram_addr),
        .bram_instruction(bram_instruction),
        .program_length(program_length),
        .program_start_addr(program_start_addr),
        .imem_write_en(imem_write_en),
        .imem_write_addr(imem_write_addr),
        .imem_write_data(imem_write_data)
        
//        .imem_write_en(imem_write_en_bootloader),
//        .imem_write_addr(imem_write_addr_bootloader),
//        .imem_write_data(imem_write_data_bootloader)
    );
    
    //================================================================
    // PIO Instruction Memory
    //================================================================
    // Instruction memory write (for programming)
    always_ff @(posedge clk) begin
        if (imem_write_en && (imem_write_addr < `INSTR_MEM_DEPTH)) begin
            instruction_memory[imem_write_addr] <= imem_write_data;
        end
    end
    
    // Instruction memory read - PC drives the address directly
    // NO delays between pc_current and instruction data
    always_comb begin
        if (pc_current < `INSTR_MEM_DEPTH) begin
            instruction_data = instruction_memory[pc_current];
        end else begin
            instruction_data = 16'h0;
        end
    end
    
    
    //================================================================
    // Debug
    //================================================================
    // assign debug bus; 21 signals [20:0]
    // logic [11:0]  dbg_pio_cu              12
    //               instruction_data        16
    // logic [ 4:0]  dbg_pio_dp               5
    //               others                   3
    //                                       36
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dbg_bus_pio <= '0;
        end
        else begin 
//            dbg_bus_cu <= { 3'b000, enable_int_out, mmio_rden_out, int_cond_met, intrpt_in, pending_int_in , current_state[4:0] ,ir_opcode_reg[7:0]};
            dbg_bus_pio <= { bootload_start, bootload_done, pio_go, instruction_data, 
            dbg_pio_dp, dbg_pio_cu};
       end
    end
    

    
    //================================================================
    // Instruction Memory Arbitration
    //================================================================
//    assign bootloader_active = (bootload_start || !bootload_done) && !bootload_error;
    // Select between bootloader and manual programming
//    assign imem_write_en_final = bootloader_active ? imem_write_en_bootloader : imem_write_en_manual;
//    assign imem_write_addr_final = bootloader_active ? imem_write_addr_bootloader : imem_write_addr_manual;
//    assign imem_write_data_final = bootloader_active ? imem_write_data_bootloader : imem_write_data_manual;
    
    
    // Final debug output assignments
//    assign debug_x_reg = x_reg_value;
//    assign debug_y_reg = y_reg_value;
//    assign debug_osr = osr_value;
//    assign debug_osr_count = osr_count;
//    assign debug_isr = isr_value;
//    assign debug_isr_count = isr_count;

endmodule

