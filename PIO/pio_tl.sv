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
// Revision 1.0 - Implemented instructions: JMP, WAIT, IN, OUT, PUSH, PULL, MOV
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


//================================================================
// Top-Level PIO State Machine
//================================================================
module pio_tl #(
    parameter int ADDR_WIDTH = 5,
    parameter int REG_WIDTH = 32,
    parameter int GPIO_WIDTH = 32,
    parameter int INSTR_MEM_DEPTH = 32
) (
    input  logic clk,
    input  logic rst_n,
    
    // External GPIO interface
    input  logic [GPIO_WIDTH-1:0] gpio_in,
    output logic [GPIO_WIDTH-1:0] gpio_out,
    output logic [GPIO_WIDTH-1:0] gpio_dir,
    
    // Configuration registers
    input  logic [4:0] execctrl_jmp_pin,
    input  logic [4:0] shiftctrl_pull_thresh,
    input  logic [4:0] pinctrl_in_base,
    input  logic [4:0] pinctrl_out_base,
    input  logic [4:0] pinctrl_out_count,
    input  logic [1:0] state_machine_id,
    
    // Instruction Memory Programming Interface
    input  logic                  imem_write_en,
    input  logic [ADDR_WIDTH-1:0] imem_write_addr,
    input  logic [15:0]           imem_write_data,
    
    // FIFO interfaces
    input  logic [REG_WIDTH-1:0]  tx_fifo_data,
    input  logic                  tx_fifo_empty,
    output logic                  tx_fifo_read,
    output logic [REG_WIDTH-1:0]  rx_fifo_data,
    output logic                  rx_fifo_write,
    input  logic                  rx_fifo_full,
    
    // IRQ interface
    input  logic [7:0]            irq_flags_in,
    output logic [7:0]            irq_flags_clear,
    
    // IN
    input logic [4:0] shiftctrl_in_count,
    input logic       shiftctrl_in_shiftdir,
    input logic       shiftctrl_autopush_en,
    input logic [4:0] shiftctrl_autopush_thresh,    
    input logic       shiftctrl_autopull_en,
    input logic [4:0] shiftctrl_autopull_thresh,											
    
    // Debug outputs
    output logic [ADDR_WIDTH-1:0] debug_pc,
    output logic [REG_WIDTH-1:0]  debug_x_reg,
    output logic [REG_WIDTH-1:0]  debug_y_reg,
    output logic [REG_WIDTH-1:0]  debug_osr,
    output logic [4:0]            debug_osr_count,
    output logic [REG_WIDTH-1:0]  debug_isr,
    output logic [4:0]            debug_isr_count,
    output logic                  debug_waiting
);

    // Internal interconnect signals between control unit and datapath
    logic [ADDR_WIDTH-1:0] pc_current;
    logic [REG_WIDTH-1:0]  x_reg_value;
    logic [REG_WIDTH-1:0]  y_reg_value;
    logic [REG_WIDTH-1:0]  osr_value;
    logic [REG_WIDTH-1:0]  isr_value;
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
    
    // Instruction memory interface
    logic [15:0] instruction_data;
    
    // Simple instruction memory implementation with write capability
    logic [15:0] instruction_memory [0:INSTR_MEM_DEPTH-1];
    
    // Instruction memory write (for programming)
    always_ff @(posedge clk) begin
        if (imem_write_en && imem_write_addr < INSTR_MEM_DEPTH) begin
            instruction_memory[imem_write_addr] <= imem_write_data;
        end
    end
    
    // Instruction memory read - PC drives the address directly
    always_comb begin
        instruction_data = (pc_current < INSTR_MEM_DEPTH) ? 
                          instruction_memory[pc_current] : 16'b0;
    end
    
    //================================================================
    // Control Unit Instantiation
    //================================================================
    pio_cu #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .REG_WIDTH(REG_WIDTH),
        .GPIO_WIDTH(GPIO_WIDTH),
        .INSTR_MEM_DEPTH(INSTR_MEM_DEPTH)
    ) u_control_unit (
        .clk(clk),
        .rst_n(rst_n),
        
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
        .tx_fifo_empty(tx_fifo_empty),
        .rx_fifo_full(rx_fifo_full),
        
        // Configuration inputs
        .execctrl_jmp_pin(execctrl_jmp_pin),
        .shiftctrl_pull_thresh(shiftctrl_pull_thresh),
        .pinctrl_in_base(pinctrl_in_base),
        .state_machine_id(state_machine_id),
        
        // Control signal outputs to datapath
        .pc_write_en(cu_pc_write_en),
        .pc_src_sel(cu_pc_src_sel),
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
        .osr_shift_dir(cu_osr_shift_dir),
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
		
        .tx_fifo_read(tx_fifo_read),
        .rx_fifo_write(rx_fifo_write),
        .irq_clear(irq_flags_clear),
        
        // Debug outputs
 //       .debug_pc(debug_pc),
        .debug_waiting(debug_waiting),
        .debug_stalled()
    );
    assign debug_pc = pc_current;
    //================================================================
    // Datapath Instantiation
    //================================================================
    pio_dp #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .REG_WIDTH(REG_WIDTH),
        .GPIO_WIDTH(GPIO_WIDTH)
    ) u_datapath (
        .clk(clk),
        .rst_n(rst_n),
        
        // Control signals from control unit
        .pc_write_en(cu_pc_write_en),
        .pc_src_sel(cu_pc_src_sel),
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
        .osr_shift_dir(cu_osr_shift_dir),
        .shiftctrl_pull_thresh(shiftctrl_pull_thresh),													  
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
        .tx_fifo_empty(tx_fifo_empty),
        .rx_fifo_full(rx_fifo_full),
        
        // Data inputs
        .pc_immediate(instruction_data[12:8]), // Address field for JMP
        .data_immediate({27'b0, instruction_data[4:0]}), // Simple immediate data
        .tx_fifo_data(tx_fifo_data),
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
        
        // External outputs
        .gpio_out(gpio_out),
        .gpio_dir(gpio_dir),
        .rx_fifo_data(rx_fifo_data),
        .rx_fifo_write(rx_fifo_write)
    );
    
    // Final debug output assignments
    assign debug_x_reg = x_reg_value;
    assign debug_y_reg = y_reg_value;
    assign debug_osr = osr_value;
    assign debug_osr_count = osr_count;
    
    assign debug_isr = isr_value;
    assign debug_isr_count = isr_count;

endmodule

