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
//    output logic [ADDR_WIDTH-1:0] instruction_addr,
    
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
    input  logic [4:0] shiftctrl_pull_thresh,
    input  logic [4:0] pinctrl_in_base,
    input  logic [1:0] state_machine_id,
    
    // PULL instruction
    input logic         shiftctrl_autopull_en,
    input logic [4:0]   shiftctrl_autopull_thresh,					   
    // Control Outputs to Datapath
    output logic        pc_write_en,
    output logic [2:0]  pc_src_sel,
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
    output logic        osr_shift_dir,
    
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
    typedef enum logic [3:0] {
        S_RESET,
//        S_FETCH,
        S_FET_DEC,
        S_EXECUTE,
        S_WAIT_CONDITION,
        S_DELAY,
        S_AUTOPULL,
        S_AUTOPUSH,
        S_STALLED
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
    
    // Debug: instructions
    logic jmp_instr;
    logic wait_instr;
    logic in_instr;
    logic out_instr;
    logic push_instr;
    logic pull_instr;
    logic mov_instr;
    // Note: block_flag is shared between PUSH and PULL (bit 5)															   
    
    // Internal state
    logic [4:0]  delay_counter;
    logic        waiting;
//    logic        condition_met;
    logic        jmp_condition_met;
    logic        wait_condition_met;
    logic        autopull_needed;
    logic        autopush_needed;
    
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
//        jmp_addr = instruction_data[12:8]; // For JMP
        
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
    // irq_clear = instruction_data[6];     // Clear flag
    // irq_wait = instruction_data[5];      // Wait flag
    // irq_index = instruction_data[4:0];   // IRQ index
    
    // SET instruction fields
    // set_dest = instruction_data[6:5];    // Destination
    // set_data = instruction_data[4:0];    // Data (5 bits)									
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
    assign mov_instr  = (opcode[3:1] == 3'b101); // debug
    
    //================================================================
    // Condition Evaluation
    //================================================================
    always_comb begin
        logic [2:0] irq_index;
        casez (opcode)
            `OP_JMP: begin
                case (jmp_cond)
                    3'b000: jmp_condition_met = 1'b1; // Always
                    3'b001: jmp_condition_met = x_is_zero; // !X
                    3'b010: jmp_condition_met = !x_is_zero; // X-- (before decrement)
                    3'b011: jmp_condition_met = y_is_zero; // !Y
                    3'b100: jmp_condition_met = !y_is_zero; // Y-- (before decrement)
                    3'b101: jmp_condition_met = x_not_equal_y; // X!=Y
                    3'b110: jmp_condition_met = gpio_state[execctrl_jmp_pin]; // PIN
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
                            irq_index = (wait_index[2:0] + state_machine_id) % 4;
                        end else begin
                            irq_index = wait_index[2:0];
                        end
                        signal_value = irq_flags[irq_index];
                    end
                    2'b11: signal_value = 1'b0; // Reserved
                    default: signal_value = 1'b0;
                endcase
                wait_condition_met = (signal_value == wait_polarity);
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
            current_state <= S_RESET;
            delay_counter <= '0;
            waiting <= 1'b0;
        end else begin
            current_state <= next_state;
            
            // Delay counter management
            if (current_state == S_DELAY) begin
                if (delay_counter > 0) begin
                    delay_counter <= delay_counter - 1'b1;
                end
            end else if (next_state == S_DELAY) begin
                delay_counter <= delay_value;
            end
            
            // Wait state management
            if (current_state == S_WAIT_CONDITION) begin
                waiting <= !wait_condition_met;
            end else begin
                waiting <= 1'b0;
            end
        end
    end
    
    // Next state logic
    always_comb begin
        next_state = current_state;
        
        case (current_state)
//            S_RESET: next_state = S_FETCH;
            S_RESET: next_state = S_FET_DEC;
            
//            S_FETCH: next_state = S_DECODE;
            
            S_FET_DEC: begin
                casez (opcode)
                    `OP_JMP:  next_state = S_EXECUTE;
                    `OP_WAIT: next_state = S_WAIT_CONDITION;
                    `OP_OUT:  next_state = S_EXECUTE;
                    `OP_IN:   next_state = S_EXECUTE;
                    `OP_PUSH: next_state = S_EXECUTE;
                    `OP_PULL: next_state = S_EXECUTE;
                    `OP_MOV:  next_state = S_EXECUTE;        // MOV
//                    4'b110?: next_state = S_EXECUTE;        // IRQ
//                    4'b111?: next_state = S_EXECUTE;        // SET																	
                    // Add other instructions
//                    default: next_state = S_FETCH; // NOP
                    default: next_state = S_RESET; // NOP
                endcase
            end
            
            S_EXECUTE: begin
                    if (opcode == `OP_PUSH && !rx_fifo_full) begin
                    // PUSH can complete
                        if (delay_value != '0) begin
                            next_state = S_DELAY;
                        end else begin
//                            next_state = S_FETCH;
                            next_state = S_FET_DEC;
                        end
                    end else if (opcode == `OP_PUSH && rx_fifo_full && !iffull_flag) begin
                        // PUSH blocked - stay in S_EXECUTE until FIFO has space
                        next_state = S_EXECUTE;

// TODO: Verify this change                        
                    end else if (opcode == `OP_PULL && !tx_fifo_empty) begin
//                    end else if (opcode == `OP_PULL && tx_fifo_empty) begin
                        // PULL can complete - TX FIFO has data
                        // delay_counter
                        if (delay_value != '0) begin
                            next_state = S_DELAY;
                        end else begin
//                            next_state = S_FETCH;
                            next_state = S_FET_DEC;
                        end
                    end else if (opcode == `OP_PULL && tx_fifo_empty && !ifempty_flag) begin
                        // PULL blocked - stay in S_EXECUTE until FIFO has data
                        next_state = S_EXECUTE;															   
                    
                    end else begin
                        // Normal instruction completion
                        if (delay_value != '0) begin
                            next_state = S_DELAY;
                        end else begin
//                            next_state = S_FETCH;
                            next_state = S_FET_DEC;
                        end
                    end
            end

            
            S_WAIT_CONDITION: begin
                if (wait_condition_met) begin
                    if (delay_value != '0) begin
                        next_state = S_DELAY;
                    end else begin
//                        next_state = S_FETCH;
                        next_state = S_FET_DEC;
                    end
                end
                // Stay in wait state if condition not met
            end
            
            S_DELAY: begin
                if (delay_counter == 0) begin
//                    next_state = S_FETCH;
                    next_state = S_FET_DEC;
                end
            end
            
            default: next_state = S_RESET;
        endcase
    end
    
    //================================================================
    // Control Signal Generation
    //================================================================
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
        osr_shift_dir = 1'b1; // Default right shift
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
	    // MOV defaults (NEW - ADD THESE LINES)
        mov_write_en = 1'b0;
        mov_dest_sel = `MOV_DEST_X;
        mov_src_sel = `MOV_SRC_NULL;
        mov_op_sel = `MOV_OP_NONE;

        
        case (current_state)
//            S_FETCH: begin end
            
            S_EXECUTE: begin
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
//                        isr_load_en = 1'b1;        // TODO: ab check this
                        // Enable load for all sources except when source is ISR itself (shift-only)
                        isr_load_en =(in_source != 3'b110); // Not ISR_SRC_ISR
                        
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
                            pc_write_en = 1'b1;
                            pc_src_sel = `PC_SRC_PLUS_ONE;
                
                            // Note: Full EXEC would modify instruction flow
                        end else begin
                            // Normal MOV operation
                            mov_write_en = 1'b1;           // Enable MOV write
                            mov_dest_sel = mov_dest;       // Set destination
                            mov_src_sel = mov_src;         // Set source
                            mov_op_sel = mov_op;           // Set operation
                
                            // Always advance PC for normal MOV instructions
                            pc_write_en = 1'b1;
                            pc_src_sel = `PC_SRC_PLUS_ONE;
                        end
                    end                   

					
                    // Add other instruction implementations
                endcase
            end
            
            S_WAIT_CONDITION: begin
                if (wait_condition_met) begin
                    // Handle IRQ clearing for WAIT IRQ with polarity=1
                    if (opcode == `OP_WAIT && wait_source == 2'b10 && wait_polarity) begin
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
            S_DELAY: begin
                if (opcode == `OP_PULL && delay_counter == 0) begin
                    // Advance PC
                    pc_write_en = 1'b1;
                    pc_src_sel = `PC_SRC_PLUS_ONE;
                end
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
    assign debug_stalled = (current_state == S_DELAY) || (current_state == S_WAIT_CONDITION);

endmodule

