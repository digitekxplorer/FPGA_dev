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
// Description: PIO Datapath.
// 
// Dependencies: pio_defs.svh
// 
// Revision:
// Revision 1.1 - Instruction set complete
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
// PIO Datapath Module
//================================================================
module pio_dp #(
    parameter int ADDR_WIDTH = 5,
    parameter int REG_WIDTH = 32,
    parameter int GPIO_WIDTH = 32
) (
    input  logic clk,
    input  logic rst_n,
    
    // Control Signals from Control Unit
    input  logic        pc_write_en,
    input  logic [2:0]  pc_src_sel,
    input  logic        x_reg_write_en,
    input  logic        y_reg_write_en,
    input  logic [1:0]  x_reg_src_sel,
    input  logic [1:0]  y_reg_src_sel,
    input  logic        x_reg_dec_en,
    input  logic        y_reg_dec_en,
    
    // OSR Control
    input  logic        osr_load_en,
    input  logic        osr_shift_en,
    input  logic [1:0]  osr_src_sel,
    input  logic [4:0]  osr_shift_count,
    input  logic        osr_shift_dir,
	input  logic [4:0]  shiftctrl_pull_thresh,
    
    // ISR Control  
    input  logic        isr_load_en,
    input  logic        isr_shift_en,
    input  logic [2:0]  isr_src_sel,
    input  logic [4:0]  isr_shift_count,
    input  logic        isr_shift_dir,
    input  logic        isr_counter_reset,
    
    // GPIO Control
    input  logic        gpio_write_en,
    input  logic        gpio_dir_write_en,
    input  logic [1:0]  gpio_src_sel,
	
    // MOV Control (NEW - ADD TO EXISTING INPUTS)
    input  logic        mov_write_en,
    input  logic [2:0]  mov_dest_sel,
    input  logic [2:0]  mov_src_sel,
    input  logic [1:0]  mov_op_sel,
    // SET control signals
    input  logic        set_write_en,
    input  logic [2:0]  set_dest_sel,    // 3 bits for destination
    input  logic [4:0]  set_data_value,
    // FIFO status inputs for STATUS register (ADD IF MISSING)
    input  logic        tx_fifo_empty,
    input  logic        rx_fifo_full,
    
    // Data Inputs
    input  logic [ADDR_WIDTH-1:0] pc_immediate,
    input  logic [REG_WIDTH-1:0]  data_immediate,
    input  logic [REG_WIDTH-1:0]  tx_fifo_data,
    input  logic [GPIO_WIDTH-1:0] gpio_in,
    input  logic [GPIO_WIDTH-1:0] mapped_pins,
    
    // Configuration
    input  logic [4:0] pinctrl_out_base,
    input  logic [4:0] pinctrl_out_count,
    
    // Status Outputs to Control Unit
    output logic [ADDR_WIDTH-1:0] pc_current,
    output logic [REG_WIDTH-1:0]  x_reg_value,
    output logic [REG_WIDTH-1:0]  y_reg_value,
    output logic [REG_WIDTH-1:0]  osr_value,
    output logic [REG_WIDTH-1:0]  isr_value,
    output logic [4:0]            osr_count,
    output logic [4:0]            isr_count,
    output logic                  x_is_zero,
    output logic                  y_is_zero,
    output logic                  x_not_equal_y,
    output logic                  osr_below_threshold,
    output logic                  isr_above_threshold,
    
    // External Outputs
    output logic [GPIO_WIDTH-1:0] gpio_out,
    output logic [GPIO_WIDTH-1:0] gpio_dir,
    output logic [REG_WIDTH-1:0]  rx_fifo_data,
    output logic                  rx_fifo_write
);

    // Internal Registers
    logic [ADDR_WIDTH-1:0] pc_reg;
    logic [REG_WIDTH-1:0]  x_register;
    logic [REG_WIDTH-1:0]  y_register;
    logic [REG_WIDTH-1:0]  osr_register;
    logic [REG_WIDTH-1:0]  isr_register;
    logic [4:0]            osr_shift_counter;
    logic [4:0]            isr_shift_counter;
    logic [GPIO_WIDTH-1:0] gpio_output_reg;
    logic [GPIO_WIDTH-1:0] gpio_direction_reg;
    logic [REG_WIDTH-1:0]  set_extended_data;  // SET data extended to 32 bits
    
    // Internal Signals
    logic [REG_WIDTH-1:0] x_reg_next;
    logic [REG_WIDTH-1:0] y_reg_next;
    logic [REG_WIDTH-1:0] osr_shifted_data;
    logic [REG_WIDTH-1:0] isr_shifted_data;
    logic [REG_WIDTH-1:0] gpio_write_data;
    
    // MOV processing signals (NEW - ADD TO EXISTING SIGNALS)
    logic [REG_WIDTH-1:0] mov_src_data;        // Selected source data
    logic [REG_WIDTH-1:0] mov_processed_data;  // Data after operation
    logic [REG_WIDTH-1:0] status_register;     // STATUS register value
    logic [REG_WIDTH-1:0] mov_write_data;      // Final data for destination
    
    
    // Zero-extend the 5-bit SET data to 32 bits
    assign set_extended_data = {27'b0, set_data_value};
    
    
    //================================================================
    // Program Counter
    //================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_reg <= '0;
        end else if (pc_write_en) begin
            case (pc_src_sel)
                `PC_SRC_PLUS_ONE:  pc_reg <= pc_reg + 1'b1;
                `PC_SRC_IMMEDIATE: pc_reg <= pc_immediate;
                `PC_SRC_OSR:       pc_reg <= osr_register[ADDR_WIDTH-1:0];
                `PC_SRC_CURRENT:   pc_reg <= pc_reg; // Hold current
                default:           pc_reg <= pc_reg + 1'b1;
            endcase
        end
    end
    
    assign pc_current = pc_reg;
    
    //================================================================
    // X and Y Scratch Registers
    //================================================================
    
    // X Register data source selection
    always_comb begin
        case (x_reg_src_sel)
            `REG_SRC_OSR:       x_reg_next = osr_shifted_data;
            `REG_SRC_ISR:       x_reg_next = isr_register;
            `REG_SRC_IMMEDIATE: x_reg_next = data_immediate;
            `REG_SRC_GPIO:      x_reg_next = {24'b0, gpio_in[7:0]};
            default:            x_reg_next = x_register;
        endcase
    end
    
    // Y Register data source selection  
    always_comb begin
        case (y_reg_src_sel)
            `REG_SRC_OSR:       y_reg_next = osr_shifted_data;
            `REG_SRC_ISR:       y_reg_next = isr_register;
            `REG_SRC_IMMEDIATE: y_reg_next = data_immediate;
            `REG_SRC_GPIO:      y_reg_next = {24'b0, gpio_in[7:0]};
            default:            y_reg_next = y_register;
        endcase
    end

//================================================================
// X Register (Modified to include MOV writes)
//================================================================
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        x_register <= '0;
    end else begin
        // MOV to X (highest priority)
        if (mov_write_en && mov_dest_sel == `MOV_DEST_X) begin // 3'b001
//            $display("DEBUG RESET: rst_n=%b at time %0t", rst_n, $time);
            x_register <= mov_write_data;
//            $display("MOV to X: %08X", mov_write_data);
//            $display("MOV to X Actual Value: %08X", x_register);
        end
        // Normal X register writes
        else if (x_reg_write_en) begin
            case (x_reg_src_sel)
                `REG_SRC_OSR: x_register <= osr_value;
                `REG_SRC_ISR: x_register <= isr_value;
//                `REG_SRC_IMMEDIATE: x_register <= data_immediate;
                `REG_SRC_IMMEDIATE: begin
                    // Check if this is a SET instruction writing to X
                    if (set_write_en && set_dest_sel == `SET_DEST_X) begin
                        x_register <= set_extended_data;
                    end else begin
                        x_register <= data_immediate;
                    end               
                end
                `REG_SRC_GPIO: x_register <= gpio_in;
                default: x_register <= data_immediate;
            endcase
        end
        // X register decrement
        else if (x_reg_dec_en) begin
            x_register <= x_register - 1'b1;
        end
    end
end

//================================================================
// Y Register (Modified to include MOV writes)
//================================================================
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        y_register <= '0;
    end else begin
        // MOV to Y (highest priority)
        if (mov_write_en && mov_dest_sel == `MOV_DEST_Y) begin // 3'b010
            y_register <= mov_write_data;
        end
        // Normal Y register writes
        else if (y_reg_write_en) begin
            case (y_reg_src_sel)
                `REG_SRC_OSR: y_register <= osr_value;
                `REG_SRC_ISR: y_register <= isr_value;
//                `REG_SRC_IMMEDIATE: y_register <= data_immediate;
                `REG_SRC_IMMEDIATE: begin
                    // Check if this is a SET instruction writing to Y
                    if (set_write_en && set_dest_sel == `SET_DEST_Y) begin
                        y_register <= set_extended_data;
                    end else begin
                        y_register <= data_immediate;
                    end
                end
                `REG_SRC_GPIO: y_register <= gpio_in;
                default: y_register <= data_immediate;
            endcase
        end
        // Y register decrement
        else if (y_reg_dec_en) begin
            y_register <= y_register - 1'b1;
        end
    end
end
    
//================================================================
// Output Shift Register (OSR) - Fixed for synthesis
//================================================================
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        osr_register <= '0;
        osr_shift_counter <= '0;
    end else begin
        // MOV to OSR (NEW)
        if (mov_write_en && mov_dest_sel == `MOV_DEST_OSR) begin // 3'b111
            osr_register <= mov_write_data;
            osr_shift_counter <= '0; // Reset counter on load
        end
        // Existing OSR load logic
        else if (osr_load_en) begin
            case (osr_src_sel)
                `OSR_SRC_TX_FIFO: osr_register <= tx_fifo_data;
                `OSR_SRC_X_REG: osr_register <= x_register;
                `OSR_SRC_Y_REG: osr_register <= y_register;
                `OSR_SRC_IMMEDIATE: osr_register <= data_immediate;
                default: osr_register <= tx_fifo_data;
            endcase
            osr_shift_counter <= '0;
        end
        // Existing OSR shift logic
        else if (osr_shift_en) begin
            if (osr_shift_count > 0) begin
                case (osr_shift_dir)
                    1'b0: osr_register <= osr_register >> osr_shift_count; // Right shift
                    1'b1: osr_register <= osr_register << osr_shift_count;  // Left shift
                endcase
                osr_shift_counter <= osr_shift_counter + osr_shift_count;
            end
        end
    end
end
    
    // Extract shifted data for output using masks instead of variable bit selects
    always_comb begin
        logic [REG_WIDTH-1:0] extract_mask;
        
        // Create mask for the number of bits to extract
        if (osr_shift_count == 5'd0) begin
            extract_mask = 32'h0000_0000;
        end else if (osr_shift_count >= 5'd32) begin
            extract_mask = 32'hFFFF_FFFF;
        end else begin
            extract_mask = (32'h0000_0001 << osr_shift_count) - 1;
        end
        
        case (osr_shift_dir)
            1'b0: begin // Right shift - output LSBs before they're shifted out
                osr_shifted_data = osr_register & extract_mask;
            end
            1'b1: begin // Left shift - output MSBs before they're shifted out
                if (osr_shift_count < 5'd32) begin
                    osr_shifted_data = (osr_register >> (32 - osr_shift_count)) & extract_mask;
                end else begin
                    osr_shifted_data = osr_register;
                end
            end
        endcase
    end
    
    //================================================================
    // Input Shift Register (ISR) - Fixed for source selection
    //================================================================ 
    // Source data selection for ISR shifting - THIS IS THE KEY FIX
    logic [REG_WIDTH-1:0] isr_shift_in_data;
    
    always_comb begin
        case (isr_src_sel)
            `ISR_SRC_GPIO:  isr_shift_in_data = gpio_in;
            `ISR_SRC_X_REG: isr_shift_in_data = x_register;
            `ISR_SRC_Y_REG: isr_shift_in_data = y_register;
            `ISR_SRC_ZERO:  isr_shift_in_data = 32'h0;
            `ISR_SRC_OSR:   isr_shift_in_data = osr_register;
            default:        isr_shift_in_data = gpio_in;
        endcase
    end
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            isr_register <= '0;
            isr_shift_counter <= '0;
        end else begin
            if (isr_counter_reset) begin
                isr_shift_counter <= '0;
            end 
            
            // MOV to ISR (NEW)
            if (mov_write_en && mov_dest_sel == `MOV_DEST_ISR) begin // 3'b110
                isr_register <= mov_write_data;
                isr_shift_counter <= '0; // Reset counter on load
            end
            else if (isr_load_en) begin
                case (isr_src_sel)
                    `ISR_SRC_GPIO:  isr_register <= {24'b0, gpio_in[7:0]};
                    `ISR_SRC_X_REG: isr_register <= x_register;
                    `ISR_SRC_Y_REG: isr_register <= y_register;
                    `ISR_SRC_ZERO:  isr_register <= '0;
                    `ISR_SRC_ISR:   isr_register <= isr_register;
                    `ISR_SRC_OSR:   isr_register <= osr_register;
                    default: isr_register <= {24'b0, gpio_in[7:0]};
                endcase
                isr_shift_counter <= '0;
            end else if (isr_shift_en) begin
                if (isr_shift_count > 0) begin
                    case (isr_shift_dir)
                        1'b0: begin // Right shift - shift in selected data from left
                            // Use shift operators instead of variable bit selects
                            logic [REG_WIDTH-1:0] data_shifted;
                            logic [REG_WIDTH-1:0] isr_shifted;
                            
                            // FIXED: Use selected source data instead of hardcoded gpio_in
                            data_shifted = (REG_WIDTH'(isr_shift_in_data) << (REG_WIDTH - isr_shift_count));
                            
                            // Shift existing ISR data right
                            isr_shifted = isr_register >> isr_shift_count;
                            
                            // Combine them
                            isr_register <= data_shifted | isr_shifted;
                        end
                        1'b1: begin // Left shift - shift in selected data from right
                            // Use shift operators instead of variable bit selects
                            logic [REG_WIDTH-1:0] data_masked;
                            logic [REG_WIDTH-1:0] isr_shifted;
                            logic [REG_WIDTH-1:0] data_mask;
                            
                            // Create mask for source data
                            if (isr_shift_count >= 5'd32) begin
                                data_mask = 32'hFFFF_FFFF;
                            end else begin
                                data_mask = (32'h0000_0001 << isr_shift_count) - 1;
                            end
                            
                            // Mask selected data
                            data_masked = REG_WIDTH'(isr_shift_in_data) & data_mask;
                            
                            // Shift existing ISR data left
                            isr_shifted = isr_register << isr_shift_count;
                            
                            // Combine them
                            isr_register <= isr_shifted | data_masked;
                        end
                    endcase
                    isr_shift_counter <= isr_shift_counter + isr_shift_count;
                end
            end
        end
    end
    
    //================================================================
    // GPIO Output Registers
    //================================================================
    always_comb begin
        case (gpio_src_sel)
            `GPIO_SRC_OSR:       gpio_write_data = osr_shifted_data;
            `GPIO_SRC_X_REG:     gpio_write_data = x_register;
            `GPIO_SRC_Y_REG:     gpio_write_data = y_register;
//            `GPIO_SRC_IMMEDIATE: gpio_write_data = data_immediate;
            `GPIO_SRC_IMMEDIATE: begin
                // Check if this is a SET instruction
                if (set_write_en && (set_dest_sel == `SET_DEST_PINS || set_dest_sel == `SET_DEST_PINDIRS)) begin
                    gpio_write_data = set_extended_data;
                end else begin
                    gpio_write_data = data_immediate;
                end
            end
            default:             gpio_write_data = data_immediate;
        endcase
    end
    
//================================================================
// GPIO Output Registers (Modified to include MOV writes)
//================================================================
logic [GPIO_WIDTH-1:0] pin_mask;
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        gpio_output_reg <= '0;
        gpio_direction_reg <= '0;
    end else begin
        // Existing OUT instruction logic
        if (gpio_write_en) begin
//            logic [GPIO_WIDTH-1:0] pin_mask;
            pin_mask = ((32'h0000_0001 << pinctrl_out_count) - 1) << pinctrl_out_base;
            gpio_output_reg <= (gpio_output_reg & ~pin_mask) | 
                              ((gpio_write_data << pinctrl_out_base) & pin_mask);
        end
        
        if (gpio_dir_write_en) begin
//            logic [GPIO_WIDTH-1:0] pin_mask;
            pin_mask = ((32'h0000_0001 << pinctrl_out_count) - 1) << pinctrl_out_base;
            gpio_direction_reg <= (gpio_direction_reg & ~pin_mask) | 
                                 ((gpio_write_data << pinctrl_out_base) & pin_mask);
        end
        
        // MOV to PINS - CORRECTED destination check
        if (mov_write_en && mov_dest_sel == `MOV_DEST_PINS) begin // 3'b000
            logic [GPIO_WIDTH-1:0] pin_mask;
            pin_mask = ((32'h0000_0001 << pinctrl_out_count) - 1) << pinctrl_out_base;
            gpio_output_reg <= (gpio_output_reg & ~pin_mask) | 
                              ((mov_write_data << pinctrl_out_base) & pin_mask);
        end
    end
end

    //================================================================
    // STATUS Register Construction
    //================================================================
    always_comb begin
        // Build STATUS register according to RP2040 specification
        // Note: This is a simplified version - full RP2040 has more status bits
        status_register = {
            19'b0,                     // Reserved bits [31:13]
            tx_fifo_empty,             // TX FIFO empty flag [12]
            rx_fifo_full,              // RX FIFO full flag [11] 
            1'b0,                      // Reserved [10]
            1'b0,                      // Reserved [9]
            1'b0,                      // Reserved [8]
            osr_shift_counter[2:0],    // OSR shift counter [7:5] (3 bits)
            isr_shift_counter[4:0]     // ISR shift counter [4:0] (5 bits)
        };
    end

    
    //================================================================
    // MOV Operation Processing
    //================================================================
    always_comb begin
        case (mov_op_sel)
            `MOV_OP_NONE: begin
                // Direct copy - no operation
                mov_processed_data = mov_src_data;
            end
        
            `MOV_OP_INVERT: begin
                // Bitwise invert
                mov_processed_data = ~mov_src_data;
            end
        
            `MOV_OP_REVERSE: begin
                // Bit-reverse the 32-bit data
                // Reverse bit order: bit[0] becomes bit[31], etc.
                for (int i = 0; i < REG_WIDTH; i++) begin
                    mov_processed_data[i] = mov_src_data[REG_WIDTH-1-i];
                end
            end
        
            default: begin
                // Reserved operation - default to direct copy
                mov_processed_data = mov_src_data;
            end
        endcase
    end
    
    assign mov_write_data = mov_processed_data;
    
    //================================================================
    // MOV Write Data Selection
    //================================================================
    always_comb begin
        case (mov_src_sel)
            `MOV_SRC_PINS:   mov_src_data = gpio_in;           // 3'b000
            `MOV_SRC_X:      mov_src_data = x_register;        // 3'b001
            `MOV_SRC_Y:      mov_src_data = y_register;        // 3'b010
            `MOV_SRC_NULL:   mov_src_data = 32'h0000_0000;     // 3'b011
            // Note: 3'b100 is reserved in RP2040
            `MOV_SRC_STATUS: mov_src_data = status_register;   // 3'b101
            `MOV_SRC_ISR:    mov_src_data = isr_register;      // 3'b110
            `MOV_SRC_OSR:    mov_src_data = osr_register;      // 3'b111
            default:         mov_src_data = 32'h0000_0000;
        endcase
    end
    
    //================================================================
    // Status Flag Generation
    //================================================================
    assign x_is_zero = (x_register == '0);
    assign y_is_zero = (y_register == '0);
    assign x_not_equal_y = (x_register != y_register);
    assign osr_below_threshold = (osr_shift_counter >= shiftctrl_pull_thresh);
    assign isr_above_threshold = (isr_shift_counter >= 5'd24);         // Example threshold
    
    //================================================================
    // Output Assignments
    //================================================================
    assign pc_current  = pc_reg;
    assign x_reg_value = x_register;
    assign y_reg_value = y_register;
    assign osr_value   = osr_register;
    assign isr_value   = isr_register;
    assign osr_count   = osr_shift_counter;
    assign isr_count   = isr_shift_counter;
    assign gpio_out    = gpio_output_reg;
    assign gpio_dir    = gpio_direction_reg;
    
    // RX FIFO interface (for PUSH operations)
    assign rx_fifo_data = isr_register;
    assign rx_fifo_write = 1'b0; // Controlled by control unit

endmodule

