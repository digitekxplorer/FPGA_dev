`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: ab Systems
// Engineer: Al Baeza
// 
// Create Date: 07/22/2025
// Design Name: abCore16 Memory-Mapped IO Registers
// Module Name: mmio_regs
// Project Name: abCore16
// Target Devices: Xilinx FPGA
// Tool Versions: Vivado
// Description: 
// Memory-mapped registers module for the abCore16 CPU. This module handles
// all memory-mapped I/O functionality including timer, UART, and LED control
// registers using SystemVerilog interfaces.
//
// Revision:
// Revision 1.2 - Refactored to use dmem_bus_if interface for CPU connection.
// Revision 1.1 - Refactored to use timer_if and uart_if interfaces.
//
//////////////////////////////////////////////////////////////////////////////////

import mmio_reg_pkg::*;
`include "defines.svh"
`include "abcore_interfaces.sv"

module mmio_regs (
    input  logic clk,
    input  logic rst_n,
    // CPU Interface (a single interface port)
    dmem_bus_if.slave dmem_bus,  // CPU data bus used to access memory-mapped IO
    // Peripheral Interfaces
    timer_if.controller timer_bus,
    uart_if.controller  uart_bus,
    //
    input logic memorymap_range,    // memory-map access flag
    // MMIO Read Data (This is an output *to* the dmem_bus mux in the top level)
    output logic [`DATA_WIDTH-1:0] mmio_rd_data_o,
    output logic                   mmio_rd_valid_o, 
    // LED Interface
    output logic [15:0] led_ctrl_o
);

//================================================================
// Register Memory-Map and Local Signals
//================================================================
register_map_t reg_map;
logic mmio_rden;

//================================================================
// Address Range Check
//================================================================
//logic memorymap_range;
// The check now uses the address signal from the dmem_bus interface
//assign memorymap_range = (dmem_bus.addr >= 6144 && dmem_bus.addr < 6400);


//================================================================
// Output Assignments to Interfaces
//================================================================
assign timer_bus.enable       = reg_map.timer_ctrl.enable;
assign timer_bus.reset        = reg_map.timer_ctrl.reset;
assign timer_bus.mode         = reg_map.timer_ctrl.mode;
assign timer_bus.prescale_en  = reg_map.timer_ctrl.prescale_en;
assign timer_bus.prescale     = reg_map.timer_prescale;
assign timer_bus.reload_value = {reg_map.timer_reload_h, reg_map.timer_reload_l};

assign uart_bus.tx_data      = reg_map.uart_tx_data.data;
assign uart_bus.tx_start     = reg_map.uart_ctrl.tx_start;
assign uart_bus.reset_flags  = reg_map.uart_ctrl.reset_flags;

assign led_ctrl_o            = reg_map.led_ctrl;

//================================================================
// Memory-mapped Register Logic
//================================================================
assign mmio_rden = 1'b1;

// Register write logic
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // Initialize all registers
        reg_map.timer_ctrl     <= '0;
        reg_map.timer_prescale <= '0;
        reg_map.timer_reload_l <= '0;
        reg_map.timer_reload_h <= '0;
        reg_map.uart_ctrl      <= '0;
        reg_map.uart_tx_data   <= '0;
        reg_map.led_ctrl       <= '0;
    end else begin
        // Auto-clear control bits
        if (reg_map.timer_ctrl.reset)    reg_map.timer_ctrl.reset    <= 1'b0;
        if (reg_map.uart_ctrl.tx_start)  reg_map.uart_ctrl.tx_start  <= 1'b0;
        if (reg_map.uart_ctrl.reset_flags) reg_map.uart_ctrl.reset_flags <= 1'b0;
        
        // Handle register writes using the dmem_bus interface
        if (dmem_bus.wren && memorymap_range && !is_read_only(dmem_bus.addr)) begin
            case (dmem_bus.addr)
                ADDRESS_TIMER_CTRL:     reg_map.timer_ctrl     <= dmem_bus.wdata;
                ADDRESS_TIMER_PRESCALE: reg_map.timer_prescale <= dmem_bus.wdata;
                ADDRESS_TIMER_RELOAD_L: reg_map.timer_reload_l <= dmem_bus.wdata;
                ADDRESS_TIMER_RELOAD_H: reg_map.timer_reload_h <= dmem_bus.wdata;
                ADDRESS_UART_CTRL:      reg_map.uart_ctrl      <= dmem_bus.wdata;
                ADDRESS_UART_TX_DATA:   reg_map.uart_tx_data   <= dmem_bus.wdata;
                ADDRESS_LED_CTRL:       reg_map.led_ctrl       <= dmem_bus.wdata;                
                default:                ;
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
        // Update timer count & status from timer interface
        reg_map.timer_count_l <= timer_bus.count[15:0];
        reg_map.timer_count_h <= timer_bus.count[31:16];
        if (timer_bus.timeout)  reg_map.timer_status.timeout  <= 1'b1;
        if (timer_bus.overflow) reg_map.timer_status.overflow <= 1'b1;
        reg_map.timer_status.running <= timer_bus.running;
        
        // Handle clear-on-write for status flags using the dmem_bus interface
        if (dmem_bus.wren && memorymap_range && is_read_only(dmem_bus.addr)) begin
            case (dmem_bus.addr)
                ADDRESS_TIMER_STATUS: begin
                    if (dmem_bus.wdata[0]) reg_map.timer_status.timeout  <= 1'b0; 
                    if (dmem_bus.wdata[1]) reg_map.timer_status.overflow <= 1'b0;
                end
                default: ;
            endcase
        end 
        
        // Update UART status from UART interface
        reg_map.uart_status.tx_busy   <= uart_bus.tx_busy;
        reg_map.uart_status.rx_error  <= uart_bus.rx_frame_error;
        if (uart_bus.rx_data_valid) begin
            reg_map.uart_rx_data.data     <= uart_bus.rx_data;
            reg_map.uart_status.rx_valid  <= 1'b1;
            reg_map.uart_rx_data.reserved <= 8'h00;
        end
        if (reg_map.uart_ctrl.reset_flags) begin
            reg_map.uart_status.rx_valid <= 1'b0;
            reg_map.uart_status.rx_error <= 1'b0;
        end
    end
end

// Register read logic
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mmio_rd_data_o  <= 16'h0;
        mmio_rd_valid_o <= 1'b0;
    end 
    else begin
        mmio_rd_valid_o <= mmio_rden;
        
        // The read case statement now uses the address from the dmem_bus interface
        if (mmio_rden && memorymap_range) begin
            case (dmem_bus.addr)
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
