`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: ab Systems
// Engineer: Al Baeza
// 
// Create Date: 07/22/2025
// Design Name: abCore16 Memory-Mapped Registers
// Module Name: core_regs
// Project Name: abCore16
// Target Devices: Xilinx FPGA
// Tool Versions: Vivado
// Description: 
// Memory-mapped registers module for the abCore16 CPU. This module handles
// all memory-mapped I/O functionality including timer, UART, and LED control
// registers.
//
// Memory-mapped IO base address = 0x1800 - 0x1900 (6,144 - 6,400)
//
//////////////////////////////////////////////////////////////////////////////////

import timer_uart_reg_pkg::*;
`include "defines.svh"

module core_regs (
    input  logic clk,
    input  logic rst_n,
    
    // CPU Interface
    input  logic                   dmem_we_i,      // Data memory write enable
    input  logic [`ADDR_WIDTH-1:0] dmem_addr_i,    // Data memory address bus
    input  logic [`DATA_WIDTH-1:0] dmem_wdata_i,   // Data memory write data
    output logic [`DATA_WIDTH-1:0] mmio_rd_data_o, // Memory-mapped read data
    output logic                   mmio_rd_valid_o, // Read valid (currently not used)
    
    // Timer Interface
    output logic        timer_enable_o,
    output logic        timer_reset_o,
    output logic        timer_mode_o,
    output logic        timer_prescale_en_o,
    output logic [15:0] timer_prescale_o,
    output logic [31:0] timer_reload_value_o,
    input  logic        timer_timeout_i,
    input  logic        timer_overflow_i,
    input  logic        timer_running_i,
    input  logic [31:0] timer_count_i,
    
    // UART Interface
    output logic [7:0]  uart_tx_data_o,
    output logic        uart_tx_start_o,
    output logic        uart_reset_flags_o,
    input  logic        uart_tx_busy_i,
    input  logic [7:0]  uart_rx_data_i,
    input  logic        uart_rx_data_valid_i,
    input  logic        uart_rx_frame_error_i,
    
    // LED Interface
    output logic [15:0] led_ctrl_o
);

//================================================================
// Parameters and Local Signals
//================================================================
localparam ADDRESS_BASE            = 16'h1800;
localparam ADDRESS_TIMER_CTRL      = 16'h1800;
localparam ADDRESS_TIMER_PRESCALE  = 16'h1802;
localparam ADDRESS_TIMER_RELOAD_L  = 16'h1804;
localparam ADDRESS_TIMER_RELOAD_H  = 16'h1806;
localparam ADDRESS_TIMER_COUNT_L   = 16'h1808;
localparam ADDRESS_TIMER_COUNT_H   = 16'h180A;
localparam ADDRESS_TIMER_STATUS    = 16'h180C;
localparam ADDRESS_UART_CTRL       = 16'h1810;
localparam ADDRESS_UART_STATUS     = 16'h1812;
localparam ADDRESS_UART_TX_DATA    = 16'h1814;
localparam ADDRESS_UART_RX_DATA    = 16'h1816;
localparam ADDRESS_LED_CTRL        = 16'h1818;

// Register map instance
register_map_t reg_map;

// Memory-mapped register enable
logic mmio_rden;

//================================================================
// Address Range Check
//================================================================
logic memorymap_range;
assign memorymap_range = (dmem_addr_i >= 6144 && dmem_addr_i < 6400);

//================================================================
// Output Assignments
//================================================================
// Timer outputs
assign timer_enable_o      = reg_map.timer_ctrl.enable;
assign timer_reset_o       = reg_map.timer_ctrl.reset;
assign timer_mode_o        = reg_map.timer_ctrl.mode;
assign timer_prescale_en_o = reg_map.timer_ctrl.prescale_en;
assign timer_prescale_o    = reg_map.timer_prescale;
assign timer_reload_value_o = {reg_map.timer_reload_h, reg_map.timer_reload_l};

// UART outputs
assign uart_tx_data_o      = reg_map.uart_tx_data.data;
assign uart_tx_start_o     = reg_map.uart_ctrl.tx_start;
assign uart_reset_flags_o  = reg_map.uart_ctrl.reset_flags;

// LED outputs
assign led_ctrl_o          = reg_map.led_ctrl;

//================================================================
// Memory-mapped Register Logic
//================================================================
assign mmio_rden = 1'b1;

// Register write logic using structured approach
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // Initialize all registers
        reg_map.timer_ctrl <= '0;
        reg_map.timer_prescale <= '0;
        reg_map.timer_reload_l <= '0;
        reg_map.timer_reload_h <= '0;
        reg_map.uart_ctrl <= '0;
        reg_map.uart_tx_data <= '0;
        reg_map.led_ctrl <= '0;
    end else begin
        // Auto-clear control bits
        if (reg_map.timer_ctrl.reset) begin
            reg_map.timer_ctrl.reset <= 1'b0;
        end
        if (reg_map.uart_ctrl.tx_start) begin
            reg_map.uart_ctrl.tx_start <= 1'b0;
        end
        if (reg_map.uart_ctrl.reset_flags) begin
            reg_map.uart_ctrl.reset_flags <= 1'b0;
        end
        
        // Handle register writes (only when in memory-mapped range)
        if (dmem_we_i && memorymap_range && !is_read_only(dmem_addr_i)) begin
            case (dmem_addr_i)
                ADDRESS_TIMER_CTRL: begin
                    reg_map.timer_ctrl <= dmem_wdata_i;
                end
                ADDRESS_TIMER_PRESCALE: begin
                    reg_map.timer_prescale <= dmem_wdata_i;
                end
                ADDRESS_TIMER_RELOAD_L: begin
                    reg_map.timer_reload_l <= dmem_wdata_i;
                end
                ADDRESS_TIMER_RELOAD_H: begin
                    reg_map.timer_reload_h <= dmem_wdata_i;
                end
                ADDRESS_UART_CTRL: begin
                    reg_map.uart_ctrl <= dmem_wdata_i;
                end
                ADDRESS_UART_TX_DATA: begin
                    reg_map.uart_tx_data <= dmem_wdata_i;
                end
                ADDRESS_LED_CTRL: begin
                    reg_map.led_ctrl <= dmem_wdata_i;
                end                
                default: begin
                    // Invalid or read-only address
                end
            endcase
        end
    end
end

// Update read-only and status registers
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        reg_map.timer_count_l   <= '0;
        reg_map.timer_count_h   <= '0;
        reg_map.timer_status    <= '0;
        reg_map.uart_status     <= '0;
        reg_map.uart_rx_data    <= '0;
    end else begin
        // Update timer count registers from timer module
        reg_map.timer_count_l <= timer_count_i[15:0];
        reg_map.timer_count_h <= timer_count_i[31:16];
        
        // Update timer status from timer module
        if (timer_timeout_i) begin
            reg_map.timer_status.timeout <= 1'b1;
        end
        if (timer_overflow_i) begin
            reg_map.timer_status.overflow <= 1'b1;
        end
        reg_map.timer_status.running <= timer_running_i;
        
        // Clear timeout (handle writes to read-only registers for status clearing)
        if (dmem_we_i && memorymap_range && is_read_only(dmem_addr_i)) begin
            case (dmem_addr_i)
                ADDRESS_TIMER_STATUS: begin
                    // Clear-on-write for status flags
                    if (dmem_wdata_i[0]) reg_map.timer_status.timeout <= 1'b0; 
                    if (dmem_wdata_i[1]) reg_map.timer_status.overflow <= 1'b0;
                end
                default: begin
                    // Invalid or read-only address
                end
            endcase
        end 
        
        // Update UART status
        reg_map.uart_status.tx_busy <= uart_tx_busy_i;
        reg_map.uart_status.rx_error <= uart_rx_frame_error_i;
        
        // Capture RX data
        if (uart_rx_data_valid_i) begin
            reg_map.uart_rx_data.data     <= uart_rx_data_i;
            reg_map.uart_status.rx_valid  <= 1'b1;       // capture valid flag
            reg_map.uart_rx_data.reserved <= 8'h00;
        end
        
        // Clear UART flags if requested
        if (reg_map.uart_ctrl.reset_flags) begin
            reg_map.uart_status.rx_valid <= 1'b0;      // clear valid flag
            reg_map.uart_status.rx_error <= 1'b0;
        end
    end
end

// Register read logic using structured approach
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mmio_rd_data_o <= 16'h0;
        mmio_rd_valid_o <= 1'b0;
    end 
    else begin
        mmio_rd_valid_o <= mmio_rden;
        
        if (mmio_rden && memorymap_range) begin
            case (dmem_addr_i)
                ADDRESS_TIMER_CTRL:     mmio_rd_data_o <= reg_map.timer_ctrl;
                ADDRESS_TIMER_PRESCALE: mmio_rd_data_o <= reg_map.timer_prescale;
                ADDRESS_TIMER_RELOAD_L: mmio_rd_data_o <= reg_map.timer_reload_l;
                ADDRESS_TIMER_RELOAD_H: mmio_rd_data_o <= reg_map.timer_reload_h;
                ADDRESS_TIMER_COUNT_L:  mmio_rd_data_o <= reg_map.timer_count_l;
                ADDRESS_TIMER_COUNT_H:  mmio_rd_data_o <= reg_map.timer_count_h;
                ADDRESS_TIMER_STATUS:   mmio_rd_data_o <= reg_map.timer_status;
                ADDRESS_UART_CTRL:      mmio_rd_data_o <= reg_map.uart_ctrl;
                ADDRESS_UART_STATUS:    mmio_rd_data_o <= reg_map.uart_status;
                ADDRESS_UART_TX_DATA:   mmio_rd_data_o <= reg_map.uart_tx_data;
                ADDRESS_UART_RX_DATA:   mmio_rd_data_o <= reg_map.uart_rx_data;
                ADDRESS_LED_CTRL:       mmio_rd_data_o <= reg_map.led_ctrl;
                default:                mmio_rd_data_o <= 16'h0;
            endcase
        end else begin
            mmio_rd_data_o <= 16'h0;
        end
    end
end

endmodule
