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
// Revision 1.3 - Fixed multiple driver issues by using continuous assignments
//                for read-only registers that directly reflect hardware state.
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
    dmem_bus_if.mmio_reader dmem_bus,  // CPU data bus used to access memory-mapped IO
    // Peripheral Interfaces
    timer_if.controller timer_bus,
    uart_if.controller  uart_bus,
    pic_mmio_if.mmio    pic_mmio_bus,  // PIC MMIO interface
    //
    input logic memorymap_range,    // memory-map access flag
    // MMIO Read Data (This is an output *to* the dmem_bus mux in the top level)
    output logic [`DATA_WIDTH-1:0] mmio_rd_data_o,
    output logic                   mmio_rd_valid_o, 
    output logic                   uart_rx_access_o,
    // LED Interface
    output logic [15:0] led_ctrl_o
);

//================================================================
// Register Memory-Map and Local Signals
//================================================================
register_map_t reg_map;
logic mmio_rden;

//================================================================
// Continuous Assignments for Read-Only Fields
//================================================================
// These assignments eliminate multiple driver issues by making read-only
// register fields directly reflect the current hardware state without
// creating additional storage elements.

// Timer read-only registers - directly connected to timer interface
assign reg_map.timer_count_l = timer_bus.count[15:0];
assign reg_map.timer_count_h = timer_bus.count[31:16];
assign reg_map.timer_status.running = timer_bus.running;

// PIC read-only registers - directly connected to PIC MMIO interface
assign reg_map.pic_irr = pic_mmio_bus.irr;
assign reg_map.pic_isr = pic_mmio_bus.isr;

// UART read-only status bits - directly connected to UART interface
assign reg_map.uart_status.tx_fifo_avail = uart_bus.tx_fifo_avail;
assign reg_map.uart_status.rx_fifo_prog_full = uart_bus.rx_fifo_prog_full;

// Reserved field (always zero)
assign reg_map.reserved_16 = 16'h0000;

//================================================================
// Output Assignments to Interfaces
//================================================================
// Timer
assign timer_bus.enable       = reg_map.timer_ctrl.enable;
assign timer_bus.reset        = reg_map.timer_ctrl.reset;
assign timer_bus.mode         = reg_map.timer_ctrl.mode;
assign timer_bus.prescale_en  = reg_map.timer_ctrl.prescale_en;
assign timer_bus.prescale     = reg_map.timer_prescale;
assign timer_bus.reload_value = {reg_map.timer_reload_h, reg_map.timer_reload_l};

// UART
assign uart_bus.tx_data      = reg_map.uart_tx_data.data;
assign uart_bus.tx_start     = reg_map.uart_ctrl.tx_start;
assign uart_bus.reset_flags  = reg_map.uart_ctrl.reset_flags;

// PIC MMIO interface
assign pic_mmio_bus.imr        = reg_map.pic_imr;
assign pic_mmio_bus.eoi_irq_num = reg_map.pic_eoi.irq_num;
assign pic_mmio_bus.eoi_update = (dmem_bus.wren && memorymap_range && 
                                  dmem_bus.addr == ADDRESS_PIC_EOI);

// GPIO 
assign led_ctrl_o            = reg_map.led_ctrl;

//================================================================
// Memory-mapped Register Logic
//================================================================
assign mmio_rden = 1'b1;

//================================================================
// Clocked Logic for Read/Write Registers
//================================================================
// This block handles only read/write registers and write-only registers.
// Read-only registers are handled by continuous assignments above.
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // Initialize read/write and write-only registers
        reg_map.timer_ctrl     <= '0;
        reg_map.timer_prescale <= '0;
        reg_map.timer_reload_l <= '0;
        reg_map.timer_reload_h <= '0;
        reg_map.uart_ctrl      <= '0;
        reg_map.uart_tx_data   <= '0;
        reg_map.pic_imr        <= 16'hFFFE; // Safe default: allow interrupts 0 and 1
        reg_map.pic_eoi        <= '0;
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
                ADDRESS_PIC_IMR:        reg_map.pic_imr        <= dmem_bus.wdata;
                ADDRESS_PIC_EOI:        reg_map.pic_eoi        <= dmem_bus.wdata; 
                ADDRESS_LED_CTRL:       reg_map.led_ctrl       <= dmem_bus.wdata;                
                default:                ;
            endcase
        end
    end
end

//================================================================
// Clocked Logic for Latched Status Registers
//================================================================
// This block handles status flags that need latching, clearing, or other
// stateful behavior that cannot be handled by simple continuous assignments.
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // Initialize latched status flags
        reg_map.timer_status.timeout  <= 1'b0;
        reg_map.timer_status.overflow <= 1'b0;
        reg_map.timer_status.reserved <= 13'b0;
        reg_map.uart_status.rx_data_avail <= 1'b0;
        reg_map.uart_status.rx_error <= 1'b0;
        reg_map.uart_status.reserved <= 12'b0;
        reg_map.uart_rx_data <= '0;
    end else begin
        // Latch timeout and overflow flags when they occur
        if (timer_bus.timeout)  reg_map.timer_status.timeout  <= 1'b1;
        if (timer_bus.overflow) reg_map.timer_status.overflow <= 1'b1;
        
        // Handle clear-on-write for timer status flags
        if (dmem_bus.wren && memorymap_range && dmem_bus.addr == ADDRESS_TIMER_STATUS) begin
            if (dmem_bus.wdata[0]) reg_map.timer_status.timeout  <= 1'b0; 
            if (dmem_bus.wdata[1]) reg_map.timer_status.overflow <= 1'b0;
        end
        
        // Handle UART RX data and status
        if (uart_bus.rx_fifo_avail) begin
            reg_map.uart_rx_data.data <= uart_bus.rx_data;
            reg_map.uart_rx_data.reserved <= 8'h00;
            reg_map.uart_status.rx_data_avail <= 1'b1;
        end
        
        // Latch UART RX error
        if (uart_bus.rx_frame_error) begin
            reg_map.uart_status.rx_error <= 1'b1;
        end
        
        // Handle UART flag clearing
        if (reg_map.uart_ctrl.reset_flags) begin
            reg_map.uart_status.rx_data_avail <= 1'b0;
            reg_map.uart_status.rx_error <= 1'b0;
        end
    end
end

//================================================================
// Register Read Logic
//================================================================
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mmio_rd_data_o      <= 16'h0;
        mmio_rd_valid_o     <= 1'b0;
        uart_rx_access_o    <= 1'b0;
    end 
    else begin
        mmio_rd_valid_o  <= mmio_rden;
        uart_rx_access_o <= 1'b0;
        
        // The read case statement uses the address from the dmem_bus interface
        if (memorymap_range) begin
            case (dmem_bus.addr)
                // Timer registers
                ADDRESS_TIMER_CTRL:     mmio_rd_data_o <= reg_map.timer_ctrl;
                ADDRESS_TIMER_PRESCALE: mmio_rd_data_o <= reg_map.timer_prescale;
                ADDRESS_TIMER_RELOAD_L: mmio_rd_data_o <= reg_map.timer_reload_l;
                ADDRESS_TIMER_RELOAD_H: mmio_rd_data_o <= reg_map.timer_reload_h;
                ADDRESS_TIMER_COUNT_L:  mmio_rd_data_o <= reg_map.timer_count_l;  // Wire assignment
                ADDRESS_TIMER_COUNT_H:  mmio_rd_data_o <= reg_map.timer_count_h;  // Wire assignment
                ADDRESS_TIMER_STATUS:   mmio_rd_data_o <= reg_map.timer_status;
                
                // UART registers
                ADDRESS_UART_CTRL:      mmio_rd_data_o <= reg_map.uart_ctrl;
                ADDRESS_UART_STATUS:    mmio_rd_data_o <= reg_map.uart_status;
                ADDRESS_UART_TX_DATA:   mmio_rd_data_o <= reg_map.uart_tx_data;
                ADDRESS_UART_RX_DATA:   begin 
                                           mmio_rd_data_o <= reg_map.uart_rx_data; 
                                           uart_rx_access_o <= 1'b1;
                                        end
                
                // PIC registers
                ADDRESS_PIC_IRR:        mmio_rd_data_o <= reg_map.pic_irr;  // Wire assignment
                ADDRESS_PIC_IMR:        mmio_rd_data_o <= reg_map.pic_imr;
                ADDRESS_PIC_ISR:        mmio_rd_data_o <= reg_map.pic_isr;  // Wire assignment
                // Note: PIC_EOI is write-only, no read case needed
                
                // LED and System Control
                ADDRESS_LED_CTRL:       mmio_rd_data_o <= reg_map.led_ctrl;
                
                default:                mmio_rd_data_o <= 16'h0;
            endcase
        end else begin
            mmio_rd_data_o <= 16'h0;
        end
    end
end

endmodule
