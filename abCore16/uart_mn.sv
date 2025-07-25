`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: ab Systems
// Engineer: Al Baeza
// 
// Create Date: 07/17/2025
// Design Name: UART
// Module Name: uart_mn
// Project Name: Uart
//
// Revision:
// Revision 1.2 - Modified to get clk/rst from the interface for consistency.
// Revision 1.1 - Refactored to use uart_if interface.
//
//////////////////////////////////////////////////////////////////////////////////

`include "abcore_interfaces.sv"

module uart_mn #(
    parameter CLK_FREQ      = 50_000_000,
    parameter DATA_BITS     = 8,
    parameter BAUD_RATE     = 9600,
    parameter ACC_WIDTH     = 20
) (
    // <<< FIX: No separate i_clk and i_rst_n ports here.
    // They are accessed via the uart_bus interface.
    uart_if.peripheral       uart_bus,
    
    input  logic [15:0]      i_baud_divider, 
    input  logic             i_tx_start_manual,
    output logic             o_uart_tx,
    input  logic             i_uart_rx
);

    // -- Local Signals --
    logic baud_tick_1x;
    logic baud_tick_16x;
    logic tx_start_combined;

    // -- Baud Rate Generation --
    localparam longint PHASE_INC_1X = (longint'(BAUD_RATE) * (longint'(1) << ACC_WIDTH)) / CLK_FREQ;
    localparam longint PHASE_INC_16X = (longint'(BAUD_RATE * 16) * (longint'(1) << ACC_WIDTH)) / CLK_FREQ;
    logic [ACC_WIDTH-1:0] acc_1x_reg;
    logic [ACC_WIDTH-1:0] acc_16x_reg;
    logic [ACC_WIDTH:0] sum_1x;
    logic [ACC_WIDTH:0] sum_16x;
    logic tx_busy_d1;
    logic tx_start_edge;

    // <<< FIX: Use clock and reset from the interface consistently
    always_ff @(posedge uart_bus.clk or negedge uart_bus.rst_n) begin
        if (!uart_bus.rst_n) tx_busy_d1 <= 1'b0;
        else                 tx_busy_d1 <= uart_bus.tx_busy;
    end
    assign tx_start_edge = uart_bus.tx_busy & ~tx_busy_d1;
    assign sum_1x = acc_1x_reg + PHASE_INC_1X;
    always_ff @(posedge uart_bus.clk or negedge uart_bus.rst_n) begin
        if (!uart_bus.rst_n || tx_start_edge) acc_1x_reg <= '0;
        else acc_1x_reg <= sum_1x[ACC_WIDTH-1:0];
    end
    assign sum_16x = acc_16x_reg + PHASE_INC_16X;
    always_ff @(posedge uart_bus.clk or negedge uart_bus.rst_n) begin
        if (!uart_bus.rst_n) acc_16x_reg <= '0;
        else acc_16x_reg <= sum_16x[ACC_WIDTH-1:0];
    end
    assign baud_tick_1x  = sum_1x[ACC_WIDTH];
    assign baud_tick_16x = sum_16x[ACC_WIDTH];

    assign tx_start_combined = uart_bus.tx_start | i_tx_start_manual;

    // -- Instantiations --
    uart_tx #(
        .DATA_BITS(DATA_BITS)
    ) tx_inst (
        .i_clk          (uart_bus.clk),
        .i_rst_n        (uart_bus.rst_n),
        .i_tx_data      (uart_bus.tx_data),
        .i_tx_start     (tx_start_combined),
        .o_tx_busy      (uart_bus.tx_busy),
        .o_uart_tx      (o_uart_tx),
        .i_baud_tick    (baud_tick_1x)
    );

    uart_rx #(
        .DATA_BITS(DATA_BITS)
    ) rx_inst (
        .i_clk            (uart_bus.clk),
        .i_rst_n          (uart_bus.rst_n),
        .i_uart_rx        (i_uart_rx),
        .o_rx_data        (uart_bus.rx_data),
        .o_rx_data_valid  (uart_bus.rx_data_valid),
        .o_rx_frame_error (uart_bus.rx_frame_error),
        .i_baud_tick      (baud_tick_16x)
    );
endmodule
