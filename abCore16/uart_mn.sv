`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: ab Systems
// Engineer: Al Baeza
// 
// Create Date: 07/17/2025 08:09:50 AM
// Design Name: UART
// Module Name: uart_mn
// Project Name: Uart
// Target Devices: xc7s25csga225-1
// Tool Versions: Vivado 2024.2
// Description: Top-level module with a robust, drift-free baud rate generator.
// This is the final version that SYNCHRONIZES the TX accumulator to the 
// start of a transmission, ensuring correct bit widths. 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module uart_mn #(
    // --- PARAMETER LIST ---
    parameter CLK_FREQ      = 50_000_000,  // 50 MHz system clock
    parameter DATA_BITS     = 8,
    parameter BAUD_RATE     = 9600,
    parameter ACC_WIDTH     = 20           // Accumulator width for precision
) (
    // --- PORT LIST ---
    input  logic                  i_clk,
    input  logic                  i_rst_n,
    input  logic [15:0]           i_baud_divider, // Unused by this logic

    // TX Interface
    input  logic [DATA_BITS-1:0]  i_tx_data,
    input  logic                  i_tx_start,
    output logic                  o_tx_busy,

    // RX Interface
    output logic [DATA_BITS-1:0]  o_rx_data,
    output logic                  o_rx_data_valid,
    output logic                  o_rx_frame_error,

    // Physical Pins
    output logic                  o_uart_tx,
    input  logic                  i_uart_rx
);

    // -- Baud Rate Generation --

    localparam longint PHASE_INC_1X = (longint'(BAUD_RATE) * (longint'(1) << ACC_WIDTH)) / CLK_FREQ;
    localparam longint PHASE_INC_16X = (longint'(BAUD_RATE * 16) * (longint'(1) << ACC_WIDTH)) / CLK_FREQ;

    // --- DEFINITIVE FIX FOR "LONG START BIT" ---
    logic [ACC_WIDTH-1:0] acc_1x_reg;
    logic [ACC_WIDTH-1:0] acc_16x_reg;

    logic [ACC_WIDTH:0] sum_1x;
    logic [ACC_WIDTH:0] sum_16x;
    
    // We only need to synchronize the TX accumulator. The RX accumulator must
    // remain free-running to catch the asynchronous start bit.
    logic tx_busy_d1;
    logic tx_start_edge;

    // Detect the rising edge of o_tx_busy, which marks the start of a TX
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) tx_busy_d1 <= 1'b0;
        else          tx_busy_d1 <= o_tx_busy;
    end
    assign tx_start_edge = o_tx_busy & ~tx_busy_d1;

    // TX Accumulator: Resets on system reset OR at the start of a new transmission
    assign sum_1x = acc_1x_reg + PHASE_INC_1X;
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n || tx_start_edge) begin
            acc_1x_reg <= '0;
        end else begin
            acc_1x_reg <= sum_1x[ACC_WIDTH-1:0];
        end
    end

    // RX Accumulator: Must be free-running
    assign sum_16x = acc_16x_reg + PHASE_INC_16X;
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            acc_16x_reg <= '0;
        end else begin
            acc_16x_reg <= sum_16x[ACC_WIDTH-1:0];
        end
    end

    assign baud_tick_1x  = sum_1x[ACC_WIDTH];
    assign baud_tick_16x = sum_16x[ACC_WIDTH];
    // --- END OF FIX ---


    // -- Instantiations --

    uart_tx #(
        .DATA_BITS(DATA_BITS)
    ) tx_inst (
        .i_clk          (i_clk),
        .i_rst_n        (i_rst_n),
        .i_tx_data      (i_tx_data),
        .i_tx_start     (i_tx_start),
        .o_tx_busy      (o_tx_busy),
        .o_uart_tx      (o_uart_tx),
        .i_baud_tick    (baud_tick_1x)
    );

    uart_rx #(
        .DATA_BITS(DATA_BITS)
    ) rx_inst (
        .i_clk            (i_clk),
        .i_rst_n          (i_rst_n),
        .i_uart_rx        (i_uart_rx),
        .o_rx_data        (o_rx_data),
        .o_rx_data_valid  (o_rx_data_valid),
        .o_rx_frame_error (o_rx_frame_error),
        .i_baud_tick      (baud_tick_16x)
    );

endmodule

