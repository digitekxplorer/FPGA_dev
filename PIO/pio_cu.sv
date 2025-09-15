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
// Description: PIO Controller.
// 
// Dependencies: pio_defs.svh
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


// August 31, 2025

// PIO Control/Datapath Architecture
// Control unit manages instruction sequencing and generates control signals
// Datapath handles register operations and data movement

`include "pio_defs.svh"

//================================================================
// PIO Control Unit Module  
//================================================================
module pio_cu #(
    parameter int ADDR_WIDTH = 5,
    parameter int REG_WIDTH = 32,
    parameter int GPIO_WIDTH = 32,
    parameter int INSTR_MEM_DEPTH = 32
) (
    input  logic clk,
    input  logic rst_n,
    
    // Instruction Memory Interface
    input  logic [15:0] instruction_data,
    input  logic        pio_go,
    
    // Status Inputs from Datapath
//    input  logic [ADDR_WIDTH-1:0] pc_current,
    input  logic [REG_WIDTH-1:0]  x_reg_value,
    input  logic [REG_WIDTH-1:0]  y_reg_value,
    input  logic [REG_WIDTH-1:0]  osr_value,
    input  logic [REG_WIDTH-1:0]  isr_value,
    input  logic [4:0]            osr_count,
    input  logic [4:0]            isr_count,
    input  logic                  x_is_zero,
    input  logic                  y_is_zero,
    input  logic                  x_not_equal_y,
    input  logic                  osr_below_threshold,
    input  logic                  isr_above_threshold,
    
    // External Status Inputs
    input  logic [GPIO_WIDTH-1:0] gpio_state,
    input  logic [7:0]            irq_flags,
    input  logic                  tx_fifo_empty,
    input  logic                  rx_fifo_full,
    
    // Configuration Inputs
    input  logic [4:0] execctrl_jmp_pin,
//    input  logic [4:0] shiftctrl_pull_thresh,
    input  logic [4:0] pinctrl_in_base,
    input  logic [1:0] state_machine_id, 
    
    // PULL instruction
    input logic         shiftctrl_autopull_en,
    input logic [4:0]   shiftctrl_autopull_thresh,					   
    // Control Outputs to Datapath
    output logic        pc_write_en,
    output logic [2:0]  pc_src_sel,
    output logic        pc_hold,
    output logic        x_reg_write_en,
    output logic        y_reg_write_en,
    output logic [1:0]  x_reg_src_sel,
    output logic [1:0]  y_reg_src_sel,
    output logic        x_reg_dec_en,
    output logic        y_reg_dec_en,
    
    // OSR Control
    output logic        osr_load_en,
    output logic        osr_shift_en,
    output logic [1:0]  osr_src_sel,
    output logic [4:0]  osr_shift_count,
    output logic        osr_counter_reset,
//    output logic        osr_shift_dir,
    
    // ISR Control
    output logic        isr_load_en,
    output logic        isr_shift_en,
    output logic [2:0]  isr_src_sel,
    output logic [4:0]  isr_shift_count,
    output logic        isr_shift_dir,
    output logic        isr_counter_reset,
    
    // IN
    input logic  [4:0]  shiftctrl_in_count,
    input logic         shiftctrl_in_shiftdir,
    input logic         shiftctrl_autopush_en,
    input logic  [4:0]  shiftctrl_autopush_thresh,
    
    // GPIO Control
    output logic        gpio_write_en,
    output logic        gpio_dir_write_en,
    output logic [1:0]  gpio_src_sel,
	
    // MOV Control
    output logic        mov_write_en,
    output logic [2:0]  mov_dest_sel,
    output logic [2:0]  mov_src_sel,
    output logic [1:0]  mov_op_sel,
    // SET Control
    output logic        set_write_en,
    output logic [2:0]  set_dest_sel,   // 3 bits for destination
//    output logic [4:0]  set_data_value,
    
    // IRQ Control
    output logic        irq_operation_en,
    output logic        irq_set_operation,
    output logic        irq_wait_for_clear,
    output logic [4:0]  irq_target_index,
//    output logic [7:0]  irq_set,        // Set IRQ flags
    
    // FIFO Control
    output logic        tx_fifo_read,
    output logic        rx_fifo_write,
    
    // IRQ Control
    output logic [7:0]  irq_clear,
    
    // Debug
//    output logic [ADDR_WIDTH-1:0] debug_pc,
    output logic         debug_waiting,
    output logic         debug_stalled
);

    //================================================================
    // FSM State Definition
    //================================================================
    typedef enum logic [2:0] {
        RESET,
        WAIT_GO,
        EXECUTE,
        WAIT_CONDITION,
        DLY_S
//        AUTOPULL,
//        AUTOPUSH,
//        STALLED
    } pio_state_t;
    
    pio_state_t current_state, next_state;
   
    
    // Instruction decode
    logic [3:0]  opcode;
    logic [2:0]  out_destin;
    logic [2:0]  jmp_cond;
    logic [4:0]  bit_count;
//    logic [4:0]  jmp_addr;  // not used in this module
    logic [4:0]  delay_value;
    logic        wait_polarity;
    logic [1:0]  wait_source;
    logic [4:0]  wait_index;
    // IN instruction fields
    logic [2:0]  in_source;
//    logic [4:0]  in_bit_count;
    
    // PUSH instruction fields
    logic iffull_flag;
    logic block_flag;
    // PULL instruction fields
    logic ifempty_flag;    // PULL instruction ifempty flag (bit 6)
    logic pull_flag;  // PUSH/PULL: 0=PUSH; 1=PULL]

    // MOV instruction fields
    logic [2:0]  mov_dest;     // Destination field
    logic [2:0]  mov_src;      // Source field
    logic [1:0]  mov_op;       // Operation field	
    
    // SET instruction fields
    logic [2:0]  set_dest;     // Destination field (3 bits)
    logic [4:0]  set_data;     // Data field (5 bits)
    // IRQ
    logic        irq_clear_flag;    // IRQ clear flag
    logic        irq_wait_flag;     // IRQ wait flag  
    logic [4:0]  irq_index_field;   // IRQ index field
    
    // IRQ control signals
    logic        irq_waiting;          // Currently waiting for IRQ clear
    
    // Debug: instructions
    logic jmp_instr;
    logic wait_instr;
    logic in_instr;
    logic out_instr;
    logic push_instr;
    logic pull_instr;
    logic mov_instr;
    logic set_instr;
    logic irq_instr;
    // Note: block_flag is shared between PUSH and PULL (bit 5)															   
    
    // Internal state
    logic [4:0]  delay_counter;
    logic        waiting;
    logic        jmp_condition_met;
    logic        wait_condition_met;
//    logic        autopull_needed;
//    logic        autopush_needed;
    logic [2:0]  computed_irq_index;
    
    logic        exec_state;
    
    assign pc_hold = current_state == DLY_S;
    
    // for debug
    assign exec_state = current_state == EXECUTE;
    
    //================================================================
    // Instruction Decode
    //================================================================
    always_comb begin
        opcode = {instruction_data[15:13], instruction_data[7]};
        
        // Common fields
        delay_value = instruction_data[12:8];
        
        // JMP instruction fields
        jmp_cond = instruction_data[7:5];
        // jump address not used in this module, used in datapath
//        jmp_addr = instruction_data[4:0]; // For JMP
        
        // WAIT instruction fields
        wait_polarity = instruction_data[7];
        wait_source = instruction_data[6:5];
        wait_index = instruction_data[4:0];
        
        // OUT instruction fields
        out_destin = instruction_data[7:5];
        bit_count = instruction_data[4:0];
        
        // IN instruction fields
        in_source = instruction_data[7:5];
        
        // PUSH instruction fields
        iffull_flag = instruction_data[6];
        block_flag = instruction_data[5];
        // PULL instruction fields  
        ifempty_flag = instruction_data[6];
        // Note: instruction_data[7] used to select PUSH (0) or PULL (1)
        pull_flag = instruction_data[7];
        
        // MOV instruction fields
        mov_dest = instruction_data[7:5];  // Destination (3 bits) [7:5]
        mov_op = instruction_data[4:3];    // Operation (2 bits) [4:3]  
        mov_src = instruction_data[2:0];   // Source (3 bits) [2:0]
    
        // IRQ instruction fields
        irq_clear_flag = instruction_data[6];     // Clear flag
        irq_wait_flag = instruction_data[5];      // Wait flag
        irq_index_field = instruction_data[4:0];   // IRQ index
    
        // SET instruction fields
        set_dest = instruction_data[7:5];    // Destination (3 bits) [7:5]
        set_data = instruction_data[4:0];    // Data value (5 bits) [4:0]									
    end
    
    // Debug
    // Note: casez handles the don't care but the comparisons below
    // have to be exact matches so use only the upper three bits for
    // all instructions except PUSH and PULL.
    assign jmp_instr  = (opcode[3:1] == 3'b000);  // debug
    assign wait_instr = (opcode[3:1] == 3'b001);  // debug
    assign in_instr   = (opcode[3:1] == 3'b010);  // debug
    assign out_instr  = (opcode[3:1] == 3'b011);  // debug
    assign push_instr = (opcode == `OP_PUSH);     // debug
    assign pull_instr = (opcode == `OP_PULL);     // debug
    assign mov_instr  = (opcode[3:1] == 3'b101);  // debug
    assign irq_instr  = (opcode == `OP_IRQ);      // debug
 //   assign irq_instr  = (opcode[3:1] == 3'b110);  // debug
    assign set_instr  = (opcode[3:1] == 3'b111);  // debug
    
    //================================================================
    // Condition Evaluation
    //================================================================
    logic [2:0] irq_index_eval;
    always_comb begin
        casez (opcode)
            `OP_JMP: begin
                case (jmp_cond)
                    3'b000: jmp_condition_met = 1'b1; // Always
                    3'b001: jmp_condition_met = x_is_zero; // !X
                    3'b010: jmp_condition_met = !x_is_zero; // X-- (before decrement)
                    3'b011: jmp_condition_met = y_is_zero; // !Y
                    3'b100: jmp_condition_met = !y_is_zero; // Y-- (before decrement)
                    3'b101: jmp_condition_met = x_not_equal_y; // X!=Y
                    3'b110: jmp_condition_met = gpio_state[execctrl_jmp_pin]; // branch on input PIN
                    3'b111: jmp_condition_met = !osr_below_threshold; // !OSRE
                    default: jmp_condition_met = 1'b0;
                endcase
            end
            
            `OP_WAIT: begin
                logic signal_value;
                case (wait_source)
                    2'b00: signal_value = gpio_state[wait_index]; // GPIO
                    2'b01: signal_value = gpio_state[(pinctrl_in_base + wait_index) % 32]; // PIN
                    2'b10: begin // IRQ
                        if (wait_index[4]) begin
                            // MSB is set, state machine ID (0…3) is added to the IRQ index
                            irq_index_eval = (wait_index[2:0] + state_machine_id) % 4;
                        end else begin
                            // 3 LSBs specify an IRQ index from 0-7
                            irq_index_eval = wait_index[2:0];
                        end
                        signal_value = irq_flags[irq_index_eval];
                    end
                    2'b11: signal_value = 1'b0; // Reserved
                    default: signal_value = 1'b0;
                endcase
                wait_condition_met = (signal_value == wait_polarity);
            end
            
            `OP_IRQ: begin
                // IRQ wait condition logic
                if (irq_index_field[4]) begin
                    // MSB is set, state machine ID (0…3) is added to the IRQ index
                    irq_index_eval = (irq_index_field[2:0] + state_machine_id) % 4;
                end else begin
                    // 3 LSBs specify an IRQ index from 0-7
                    irq_index_eval = irq_index_field[2:0];
                end
    
                if (irq_wait_flag) begin
                    if (irq_clear_flag) begin
                        // IRQ CLEAR with WAIT: wait until IRQ is cleared
                        wait_condition_met = !irq_flags[irq_index_eval];
                    end else begin
                        // IRQ SET with WAIT: wait until IRQ is cleared by system
                        wait_condition_met = !irq_flags[irq_index_eval];
                    end
                end else begin
                    // No wait required - condition always met
                    wait_condition_met = 1'b1;
                end
            end
            
            default: begin 
                    wait_condition_met = 1'b1; 
                    jmp_condition_met = 1'b1;
            end
            
        endcase
    end
    
    //================================================================
    // FSM State Logic
    //================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= RESET;
            delay_counter <= '0;
            waiting <= 1'b0;
        end else begin
            current_state <= next_state;
            
            // Delay counter management
            if (current_state == DLY_S) begin
                if (delay_counter > 0) begin
                    delay_counter <= delay_counter - 1'b1;
                end
            end else if (next_state == DLY_S) begin
                delay_counter <= delay_value;
            end
            
            // Wait state management
            if (current_state == WAIT_CONDITION) begin
                waiting <= !wait_condition_met;
            end else begin
                waiting <= 1'b0;
            end
        end
    end
    
    
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            RESET: next_state = WAIT_GO;
            
//            WAIT_GO: next_state = EXECUTE;
            // Wait from Go command from uProcessor
            WAIT_GO: begin 
                if (pio_go) begin
                    next_state = EXECUTE;
                end
            end
            
            EXECUTE: begin
                if (current_state == EXECUTE && pio_go) begin
                    casez (opcode)
                        `OP_WAIT: begin
                            if (!wait_condition_met) begin
                                next_state = WAIT_CONDITION;
                            end else begin
                                if (delay_value != '0) begin
                                    next_state = DLY_S;
                                end else begin
                                    next_state = EXECUTE;
                                end
                            end
                        end
            
                        `OP_IRQ: begin
                            if (irq_wait_flag && !wait_condition_met) begin
                                // IRQ with WAIT flag and condition not met
                                next_state = WAIT_CONDITION;
                            end else begin
                                // IRQ without WAIT or condition met
                                if (delay_value != '0) begin
                                    next_state = DLY_S;
                                end else begin
                                    next_state = EXECUTE;
                                end
                            end
                        end
            
                        // Handle other instruction cases...
                        `OP_PUSH: begin
                            if (push_instr && rx_fifo_full && block_flag) begin
                                next_state = EXECUTE; // Stay until FIFO has space
                            end else begin
                                if (delay_value != '0) begin
                                    next_state = DLY_S;
                                end else begin
                                    next_state = EXECUTE;
                                end
                            end
                        end
            
                        `OP_PULL: begin
                            if (pull_instr && tx_fifo_empty && block_flag) begin
                                next_state = EXECUTE; // Stay until FIFO has data
                            end else begin
                                if (delay_value != '0) begin
                                    next_state = DLY_S;
                                end else begin
                                    next_state = EXECUTE;
                                end
                            end
                        end
            
                        default: begin
                            // Normal instructions (JMP, IN, OUT, MOV, SET)
                            if (delay_value != '0) begin
                                next_state = DLY_S;
                            end else begin
                                next_state = EXECUTE;
                            end
                        end
                    endcase
                end else begin
                    next_state = WAIT_GO;
                end
            end 
                    
            // NOTE: We have to use exact three opcode bits because we aren't using
            // casez to select the instruction.
//            EXECUTE: begin
//                    if (wait_instr) begin
//                        next_state = WAIT_CONDITION;
//                    end else if (irq_instr) begin
//                        next_state = (irq_wait_flag) ? WAIT_CONDITION : EXECUTE;
//                    end else if (push_instr && !rx_fifo_full) begin
//                    // PUSH can complete
//                        if (delay_value != '0) begin
//                            next_state = DLY_S;
//                        end else begin
//                            next_state = EXECUTE;
//                        end
//                    end else if (push_instr && rx_fifo_full && !iffull_flag) begin
//                        // PUSH blocked - stay in EXECUTE until FIFO has space
//                        next_state = EXECUTE;
//                    end else if (pull_instr && !tx_fifo_empty) begin
//                        // PULL can complete - TX FIFO has data
//                        if (delay_value != '0) begin
//                            next_state = DLY_S;
//                        end else begin
//                            next_state = EXECUTE;
//                        end
//                    end else if (pull_instr && tx_fifo_empty && block_flag) begin
//                        // PULL blocked - stay in EXECUTE until FIFO has data
//                        next_state = EXECUTE;															   
                    
//                    end else begin
//                        // Normal instruction completion (JMP, IN, OUT, MOV, SET)
//                        if (delay_value != '0) begin
//                            next_state = DLY_S;
//                        end else begin
//                            next_state = EXECUTE;
//                        end
//                    end
//            end

            
            WAIT_CONDITION: begin
                if (wait_condition_met) begin
                    if (delay_value != '0) begin
                        next_state = DLY_S;
                    end else begin
                        next_state = EXECUTE;
                    end
                end
                // Stay in wait state if condition not met
            end
            
            DLY_S: begin
//                if (delay_counter == 0) begin
                if (delay_counter == 5'b00001) begin   // early done condition
                    next_state = EXECUTE;
                end
            end
            
            default: next_state = RESET;
        endcase
    end
    
    //================================================================
    // Control Signal Generation
    //================================================================
    // Bounds checking for IRQ index
    logic [1:0] raw_irq_index;
    logic irq_index_valid;
    
    always_comb begin
        logic [2:0] irq_index;
        // Default all control signals
        pc_write_en = 1'b0;
        pc_src_sel = `PC_SRC_PLUS_ONE;
        x_reg_write_en = 1'b0;
        y_reg_write_en = 1'b0;
        x_reg_src_sel = `REG_SRC_OSR;
        y_reg_src_sel = `REG_SRC_OSR;
        x_reg_dec_en = 1'b0;
        y_reg_dec_en = 1'b0;
        osr_load_en = 1'b0;
        osr_shift_en = 1'b0;
        osr_src_sel = `OSR_SRC_TX_FIFO;
        osr_shift_count = bit_count;
//        osr_shift_dir = 1'b1; // Default right shift
        isr_load_en = 1'b0;
        isr_shift_en = 1'b0;
        isr_src_sel = `ISR_SRC_GPIO;
        isr_shift_count = bit_count;
        isr_shift_dir = 1'b0; // Default left shift
        gpio_write_en = 1'b0;
        gpio_dir_write_en = 1'b0;
        gpio_src_sel = `GPIO_SRC_OSR;
        tx_fifo_read = 1'b0;
        rx_fifo_write = 1'b0;
        irq_clear = '0;
        isr_counter_reset = 1'b0;
        osr_counter_reset = 1'b0;
        computed_irq_index = '0;
        irq_waiting = 1'b0;
        irq_operation_en = 1'b0;
        irq_set_operation = 1'b0; 
        irq_wait_for_clear = 1'b0;
        irq_target_index = 5'b0;
        
	    // MOV defaults
        mov_write_en = 1'b0;
        mov_dest_sel = `MOV_DEST_X;
        mov_src_sel = `MOV_SRC_NULL;
        mov_op_sel = `MOV_OP_NONE;
        
        // SET control defaults
        set_write_en = 1'b0;
        set_dest_sel = `SET_DEST_PINS;

        
        // NOTE: We can use opcode definitions because we are using casez.
        case (current_state)
            RESET: begin
                pc_write_en = 1'b1;
                pc_src_sel = `PC_SRC_ZERO;   // start PC at address zero
            end
            
            WAIT_GO: begin
                if (pio_go) begin
//                    pc_write_en = 1'b1;      // TODO: instruction memory register
                end
                pc_src_sel = `PC_SRC_PLUS_ONE;
            end
            
            EXECUTE: begin
                casez (opcode)
                    `OP_JMP: begin
                        if (jmp_condition_met) begin
                            pc_write_en = 1'b1;
                            pc_src_sel = `PC_SRC_IMMEDIATE;
                        end else begin
                            pc_write_en = 1'b1;
                            pc_src_sel = `PC_SRC_PLUS_ONE;
                        end
                        
                        // Handle register decrements
                        if (jmp_cond == 3'b010) x_reg_dec_en = 1'b1; // X--
                        if (jmp_cond == 3'b100) y_reg_dec_en = 1'b1; // Y--
                    end
                    
                    `OP_OUT: begin
                        // Enable OSR shift
                        osr_shift_en = 1'b1;
                        
                        // Route output to destination
                        case (out_destin)
                            3'b000: begin // PINS
                                gpio_write_en = 1'b1;
                                gpio_src_sel = `GPIO_SRC_OSR;
                                pc_write_en = 1'b1;
                                pc_src_sel = `PC_SRC_PLUS_ONE;
                            end
                            3'b001: begin // X
                                x_reg_write_en = 1'b1;
                                x_reg_src_sel = `REG_SRC_OSR;
                                pc_write_en = 1'b1;
                                pc_src_sel = `PC_SRC_PLUS_ONE;
                            end
                            3'b010: begin // Y
                                y_reg_write_en = 1'b1;
                                y_reg_src_sel = `REG_SRC_OSR;
                                pc_write_en = 1'b1;
                                pc_src_sel = `PC_SRC_PLUS_ONE;
                            end
                            3'b100: begin // PINDIRS
                                gpio_dir_write_en = 1'b1;
                                gpio_src_sel = `GPIO_SRC_OSR;
                                pc_write_en = 1'b1;
                                pc_src_sel = `PC_SRC_PLUS_ONE;
                            end
                            3'b101: begin // PC
                                pc_write_en = 1'b1;
                                pc_src_sel = `PC_SRC_OSR;
                            end
                            3'b110: begin // ISR
                                isr_load_en = 1'b1;
                                isr_src_sel = `ISR_SRC_OSR;
                                pc_write_en = 1'b1;
                                pc_src_sel = `PC_SRC_OSR;
                            end
                            // Add other destinations
                            
                            default: begin
                                pc_write_en = 1'b1;          // Keep this for any other destinations
                                pc_src_sel = `PC_SRC_PLUS_ONE;
                            end
                        endcase 
                    end
                    

                    `OP_IN: begin
                        // Enable ISR shift operation
                        isr_shift_en = 1'b1;
                        // Enable load for all sources except when source is ISR itself (shift-only)???
                        isr_load_en =(in_source == 3'b110); // ISR = ISR; nop
                        
                        // Use bit count from instruction, or default from config
                        isr_shift_count = (bit_count == 5'b0) ? shiftctrl_in_count : bit_count;
                        isr_shift_dir = shiftctrl_in_shiftdir;
    
                        // Select data source for ISR
                        case (in_source)
                            3'b000: isr_src_sel = `ISR_SRC_GPIO;    // PINS
                            3'b001: isr_src_sel = `ISR_SRC_X_REG;   // X register
                            3'b010: isr_src_sel = `ISR_SRC_Y_REG;   // Y register  
                            3'b011: isr_src_sel = `ISR_SRC_ZERO;    // NULL (zeros)
                            3'b110: isr_src_sel = `ISR_SRC_ISR;     // ISR (shift only)
                            3'b111: isr_src_sel = `ISR_SRC_OSR;     // OSR
                            default: isr_src_sel = `ISR_SRC_GPIO;
                        endcase
    
                        // Always advance PC for IN instructions
                        pc_write_en = 1'b1;
                        pc_src_sel = `PC_SRC_PLUS_ONE;
                    end
                    

                    `OP_PUSH: begin
                        if (!rx_fifo_full || iffull_flag) begin
                            // Execute PUSH - move ISR to RX FIFO
                            rx_fifo_write = 1'b1;
                            isr_counter_reset = 1'b1;  // Reset ISR shift counter
        
                            // Advance PC after successful push
                            pc_write_en = 1'b1;
                            pc_src_sel = `PC_SRC_PLUS_ONE;
                        end else begin
                            // FIFO full and iffull=0: stall until FIFO has space
                            // Don't advance PC - stay on current instruction
                            // This creates a blocking behavior
                        end
                    end      

                    `OP_PULL: begin
                        if (!tx_fifo_empty || ifempty_flag) begin
                            // Execute PULL - load OSR from source
                            if (!tx_fifo_empty) begin
                                // Normal PULL operation - data available in TX FIFO
                                osr_load_en = 1'b1;
                                osr_src_sel = `OSR_SRC_TX_FIFO;
                                tx_fifo_read = 1'b1;  // Signal to read from TX FIFO
                            end else begin
                                // ifempty_flag = 1 and FIFO is empty
                                // Load OSR with X register when FIFO empty
                                osr_load_en = 1'b1;
                                osr_src_sel = `OSR_SRC_X_REG;
                            end
        
                            // Advance PC after successful pull
                            pc_write_en = 1'b1;
                            pc_src_sel = `PC_SRC_PLUS_ONE;
                        end else begin
                            // FIFO empty and ifempty=0: stall until FIFO has data
                            // Don't advance PC - stay on current instruction
                        end
                    end  
					
					// MOV instruction (FULL IMPLEMENTATION)
                    `OP_MOV: begin // MOV instruction (NEW - PLACEHOLDER)
                        // Check for special case: MOV to EXEC
                        if (mov_dest == `MOV_DEST_EXEC) begin
                            // MOV to EXEC: Execute the processed data as an instruction
                            // This is an advanced feature - for now, implement basic version
                            // TODO: Full EXEC implementation would require instruction injection
                
                            // For basic implementation, just treat as NOP and advance PC
                            mov_write_en = 1'b0;  // Don't write to normal destinations
//                            pc_write_en = 1'b1;
//                            pc_src_sel = `PC_SRC_PLUS_ONE;
                
                            // Note: Full EXEC would modify instruction flow
                        end else begin
                            // Normal MOV operation
                            mov_write_en = 1'b1;           // Enable MOV write
                            mov_dest_sel = mov_dest;       // Set destination
                            mov_src_sel = mov_src;         // Set source
                            mov_op_sel = mov_op;           // Set operation
                
                            // Always advance PC for normal MOV instructions
//                            pc_write_en = 1'b1;
//                            pc_src_sel = `PC_SRC_PLUS_ONE;
                        end
                        // Always advance PC
                        pc_write_en = 1'b1;
                        pc_src_sel = `PC_SRC_PLUS_ONE;
                    end 
                        
                    `OP_IRQ: begin
                        // Compute the target IRQ index (handle relative addressing)
                        if (irq_index_field[4]) begin
                            // Relative IRQ: add state machine ID to lower 3 bits
                            raw_irq_index = irq_index_field[1:0];
                            computed_irq_index = (raw_irq_index + state_machine_id) % 4;
                            irq_index_valid = 1'b1; // Always valid for relative addressing
                        end else begin
                            // Absolute IRQ: use lower 3 bits directly
                            computed_irq_index = irq_index_field[2:0];
                            irq_index_valid = (irq_index_field[2:0] <= `MAX_IRQ_INDEX);
                        end
   
                        // Only proceed if IRQ index is valid
                        if (irq_index_valid) begin 
                            // Enable IRQ operation in datapath
                            irq_operation_en = 1'b1;
                            irq_set_operation = !irq_clear_flag;  // 1=set, 0=clear
                            irq_wait_for_clear = irq_wait_flag;
                            irq_target_index = {2'b00, computed_irq_index};
    
                            // Handle program counter advancement
                            if (irq_wait_flag) begin
                                // IRQ with WAIT: check if we need to wait
                                if (irq_clear_flag) begin
                                    // IRQ CLEAR with WAIT: wait until IRQ is actually cleared
                                    irq_waiting = irq_flags[computed_irq_index];
                                end else begin
                                    // IRQ SET with WAIT: wait until IRQ is cleared by system after we set it
                                    irq_waiting = irq_flags[computed_irq_index];
                                end
        
                                if (!irq_waiting) begin
                                    // Condition met, advance PC
                                    pc_write_en = 1'b1;
                                    pc_src_sel = `PC_SRC_PLUS_ONE;
                                end
                                // If waiting, PC doesn't advance (handled by FSM)
                            end else begin
                                // IRQ without WAIT: immediate execution, advance PC
                                pc_write_en = 1'b1;
                                pc_src_sel = `PC_SRC_PLUS_ONE;
                                irq_waiting = 1'b0;  // Not waiting
                            end
                        
                        end else begin
                            // Invalid IRQ index - treat as NOP but advance PC
                            pc_write_en = 1'b1;
                            pc_src_sel = `PC_SRC_PLUS_ONE;
                            irq_waiting = 1'b0;
                        end
                    end  
                                      
                    `OP_SET: begin
                        // Enable SET operation
                        set_write_en = 1'b1;
                        set_dest_sel = set_dest;
//                        set_data_value = set_data;
    
                        // Handle different destinations
                        case (set_dest)
                            `SET_DEST_PINS: begin // 3'b000
                                // Set output pins - use GPIO write signals
                                gpio_write_en = 1'b1;
                                gpio_src_sel = `GPIO_SRC_IMMEDIATE;
                            end
        
                            `SET_DEST_X: begin // 3'b001
                                // Set X register
                                x_reg_write_en = 1'b1;
                                x_reg_src_sel = `REG_SRC_IMMEDIATE;
                            end
        
                            `SET_DEST_Y: begin // 3'b010
                                // Set Y register
                                y_reg_write_en = 1'b1;
                                y_reg_src_sel = `REG_SRC_IMMEDIATE;
                            end
        
                            `SET_DEST_PINDIRS: begin // 3'b100
                                // Set pin directions
                                gpio_dir_write_en = 1'b1;
                                gpio_src_sel = `GPIO_SRC_IMMEDIATE;
                            end
        
                            default: begin
                                // Invalid destination - treat as NOP
                                set_write_en = 1'b0;
                            end
                        endcase
    
                        // Always advance PC
                        pc_write_en = 1'b1;
                        pc_src_sel = `PC_SRC_PLUS_ONE;
                    end

                    // Add other instruction implementations
                endcase
            end
            
            WAIT_CONDITION: begin
                if (wait_condition_met) begin
                    // Handle IRQ clearing for WAIT IRQ with polarity=1
//                    if (opcode == `OP_WAIT && wait_source == 2'b10 && wait_polarity) begin
                    if (wait_instr && wait_source == 2'b10 && wait_polarity) begin
//                        logic [2:0] irq_index;  // moved to start of block
                        if (wait_index[4]) begin
                            irq_index = (wait_index[2:0] + state_machine_id) % 4;
                        end else begin
                            irq_index = wait_index[2:0];
                        end
                        irq_clear[irq_index] = 1'b1;
                    end
                    
                    // Advance PC
                    pc_write_en = 1'b1;
                    pc_src_sel = `PC_SRC_PLUS_ONE;
                end
            end
 
// ***************
// Verify this condition
// ***************            
            DLY_S: begin
//                if (opcode == `OP_PULL && delay_counter == 0) begin
                if (pull_instr && delay_counter == 5'b00000) begin
                    // Advance PC
                    pc_write_en = 1'b1;
                    pc_src_sel = `PC_SRC_PLUS_ONE;
                end
                // TODO: instruction memory register
//                else if (jmp_instr && delay_counter == 5'b00001) begin
//                    pc_write_en = 1'b1;
//                    pc_src_sel = `PC_SRC_IMMEDIATE;               
//                end
            end
            
        endcase  // end current state
    
        // Auto-push check - happens after any instruction that modifies ISR
        if (shiftctrl_autopush_en && isr_above_threshold && !rx_fifo_full) begin
            rx_fifo_write = 1'b1;
            isr_counter_reset = 1'b1;
        end
    
        // Auto-pull check - happens when OSR is below threshold
        if (shiftctrl_autopull_en && osr_below_threshold && !tx_fifo_empty) begin
            osr_load_en = 1'b1;
            osr_src_sel = `OSR_SRC_TX_FIFO;
            tx_fifo_read = 1'b1;
        end																
    end // end Control Signal Generation
    
    
    
    // Instruction address output
//    assign instruction_addr = pc_current;
    
    // Debug outputs
//    assign debug_pc = pc_current;
//    assign debug_pc = '0;
    assign debug_waiting = waiting;
    assign debug_stalled = (current_state == DLY_S) || (current_state == WAIT_CONDITION);
    
    // Debug signal for IRQ waiting state (ADD THIS)
    assign debug_irq_waiting = (current_state == WAIT_CONDITION && irq_instr);

endmodule

