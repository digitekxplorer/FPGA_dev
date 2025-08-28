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
// Revision 1.3 - Added FIFO integration for TX and RX paths
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
    // i_clk and i_rst_n are accessed via the uart_bus interface.
    uart_if.peripheral       uart_bus,
    
    input  logic             i_tx_start_manual,
    input  logic             i_uart_rx_access,     // Uart RX addr selected for access, from mmio_regs.sv
//    input  logic             i_mmio_rden,
    gpio_bus_if.peripheral   gpio_bus,             // gpio and mmio interface, from control_unit.sv
    output logic             o_uart_tx,
    input  logic             i_uart_rx
);

    // -- Local Signals --
    logic baud_tick_1x;
    logic baud_tick_16x;
    logic tx_start_combined;

    // -- FIFO Signals --
    // TX FIFO signals
    logic [7:0] tx_fifo_dout;
    logic       tx_fifo_empty;
    logic       tx_fifo_full;
    logic       tx_fifo_rd_en;
    logic       tx_fifo_wr_en;
    
    // RX FIFO signals
    logic       rx_fifo_empty;
    logic       rx_fifo_full;
    logic       rx_fifo_wr_en;
    
    // TX Control signals
    logic       tx_busy_internal;
    logic       tx_start_internal;
    logic       tx_data_available;
    
    // RX Control signals
    logic       rx_data_valid_internal;
    logic [7:0] rx_data_internal;
    logic       rx_frame_error_internal;

    // -- Baud Rate Generation --
    localparam longint PHASE_INC_1X = (longint'(BAUD_RATE) * (longint'(1) << ACC_WIDTH)) / CLK_FREQ;
    localparam longint PHASE_INC_16X = (longint'(BAUD_RATE * 16) * (longint'(1) << ACC_WIDTH)) / CLK_FREQ;
    logic [ACC_WIDTH-1:0] acc_1x_reg;
    logic [ACC_WIDTH-1:0] acc_16x_reg;
    logic [ACC_WIDTH:0] sum_1x;
    logic [ACC_WIDTH:0] sum_16x;
    
    // We only need to synchronize the TX accumulator. The RX accumulator must
    // remain free-running to catch the asynchronous start bit.    
    logic tx_busy_d1;
    logic tx_start_edge;
    
    // FSM signals
    logic tx_fifo_rden_fsm;
    
    logic rx_fifo_prog_full;
    

    // Detect the rising edge of o_tx_busy, which marks the start of a TX
    always_ff @(posedge uart_bus.clk or negedge uart_bus.rst_n) begin
        if (!uart_bus.rst_n) tx_busy_d1 <= 1'b0;
        else                 tx_busy_d1 <= tx_busy_internal;
    end
    
    assign tx_start_edge = tx_busy_internal & ~tx_busy_d1;
    
    // TX Accumulator: Resets on system reset OR at the start of a new transmission
    assign sum_1x = acc_1x_reg + PHASE_INC_1X;
    always_ff @(posedge uart_bus.clk or negedge uart_bus.rst_n) begin
        if (!uart_bus.rst_n || tx_start_edge) acc_1x_reg <= '0;
        else acc_1x_reg <= sum_1x[ACC_WIDTH-1:0];
    end
    
    // RX Accumulator: Must be free-running
    assign sum_16x = acc_16x_reg + PHASE_INC_16X;
    always_ff @(posedge uart_bus.clk or negedge uart_bus.rst_n) begin
        if (!uart_bus.rst_n) acc_16x_reg <= '0;
        else acc_16x_reg <= sum_16x[ACC_WIDTH-1:0];
    end
    
    assign baud_tick_1x  = sum_1x[ACC_WIDTH];
    assign baud_tick_16x = sum_16x[ACC_WIDTH];

    // -- TX FIFO Control Logic --
    // Write to TX FIFO when interface signals a write
    assign tx_fifo_wr_en = uart_bus.tx_start;
    
    // Check if data is available in TX FIFO
    assign tx_data_available = ~tx_fifo_empty;
    
    // FIFO read enable: assert during READ_FIFO state
    assign tx_fifo_rd_en = tx_fifo_rden_fsm & tx_data_available;
    
    // Connect interface outputs for TX status - indicate FIFO availability
    assign uart_bus.tx_fifo_avail = ~tx_fifo_full;  // High when FIFO can accept data

    // -- RX FIFO Control Logic --
    // Write to RX FIFO when valid data is received and FIFO is not full
    assign rx_fifo_wr_en = rx_data_valid_internal & ~rx_fifo_full;
    
    // Connect interface outputs for RX
    // assign uart_bus.rx_data = rx_fifo_empty ? 8'h00 : uart_bus.rx_data;  // You may want to connect FIFO output here
    assign uart_bus.rx_fifo_avail = ~rx_fifo_empty;  // Data valid when FIFO not empty
    assign uart_bus.rx_frame_error = rx_frame_error_internal;
    
    assign uart_bus.rx_fifo_prog_full = rx_fifo_prog_full;     // <<< NEW

    // =================================
    // TX UART
    // =================================
    
    // State machine for TX FIFO control
    typedef enum logic [1:0] {
        TX_IDLE,
        TX_READ_FIFO,
        TX_START_WAIT,
        TX_TRANSMIT
    } tx_state_t;
    
    tx_state_t tx_state;
    
    always_ff @(posedge uart_bus.clk or negedge uart_bus.rst_n) begin
        if (!uart_bus.rst_n) begin
            tx_state <= TX_IDLE;
            tx_fifo_rden_fsm <= 1'b0;
        end else begin
            tx_fifo_rden_fsm <= 1'b0;  // Default
            
            case (tx_state)
                TX_IDLE: begin
                    if ((tx_data_available || i_tx_start_manual) && !tx_busy_internal) begin
                        tx_state <= TX_READ_FIFO;
                    end
                end
                
                TX_READ_FIFO: begin
                    // Read data from FIFO, then start transmission on next cycle
                    tx_fifo_rden_fsm <= 1'b1;
                    tx_state <= TX_START_WAIT;
                end
                
                // Wait for the start of TX transmission
                TX_START_WAIT: begin
                    if (tx_busy_internal) begin
                        tx_state <= TX_TRANSMIT;
                    end
                end
                               
                TX_TRANSMIT: begin
                    if (!tx_busy_internal) begin
                        // Transmission complete, check for more data
                        if (tx_data_available) begin
                            tx_state <= TX_READ_FIFO;  // More data available
                        end else begin
                            tx_state <= TX_IDLE;       // No more data
                        end
                    end
                end
            endcase
        end
    end
    
    // TX start: use registered signal or manual start
    assign tx_start_internal = tx_fifo_rden_fsm | (i_tx_start_manual & (tx_state == TX_IDLE));
    
    logic tx_fifo_prog_full;
    uart_fifo uart_tx_fifo (
        .clk       (uart_bus.clk),        // input wire clk
        .srst      (!uart_bus.rst_n),     // input wire srst
        .din       (uart_bus.tx_data),    // input wire [7 : 0] din
        .wr_en     (tx_fifo_wr_en),       // input wire wr_en
        .rd_en     (tx_fifo_rd_en),       // input wire rd_en
        .dout      (tx_fifo_dout),        // output wire [7 : 0] dout
        .full      (tx_fifo_full),        // output wire full
        .empty     (tx_fifo_empty),       // output wire empty
        .prog_full (tx_fifo_prog_full)    // output wire prog_full
    );
    
    // UART instantiation
    uart_tx #(
        .DATA_BITS(DATA_BITS)
    ) tx_inst (
        .i_clk          (uart_bus.clk),
        .i_rst_n        (uart_bus.rst_n),
        .i_tx_data      (tx_fifo_dout),         // Connect to FIFO output
        .i_tx_start     (tx_start_internal),    // Use internal start signal
        .o_tx_busy      (tx_busy_internal),     // Connect to internal signal
        .o_uart_tx      (o_uart_tx),
        .i_baud_tick    (baud_tick_1x)
    );


    // =================================
    // RX UART
    // =================================
    logic rx_fifo_rden_fsm;
    logic rx_data_valid_fsm;
    logic [7:0] rx_fifo_dout;
    
    // State machine for RX FIFO control
    typedef enum logic [1:0] {
        RX_IDLE,
        RX_READ_FIFO,
        RX_DATA_VALID
    } rx_state_t;
    
    rx_state_t rx_state;
    
    always_ff @(posedge uart_bus.clk or negedge uart_bus.rst_n) begin
        if (!uart_bus.rst_n) begin
            rx_state <= RX_IDLE;
            rx_fifo_rden_fsm <= 1'b0;
            rx_data_valid_fsm <= 1'b0;     // currently not used
        end else begin
            rx_fifo_rden_fsm <= 1'b0;  // Default
            rx_data_valid_fsm <= 1'b0;  // Default
            
            case (rx_state)
                RX_IDLE: begin
//                    if (~rx_fifo_empty) begin
                    // Is cpu accessing RX Uart Fifo with a read enable?
                    // This means cpu read from the RX Uart Fifo
                    // Use gpio_bus interface to access mmio_rden; memory read Rd = Mem[Rs_addr]
                    if (i_uart_rx_access && gpio_bus.mmio_rden) begin
//                    if (i_uart_rx_access && i_mmio_rden) begin
                        rx_state <= RX_READ_FIFO;
                    end
                end
                
                RX_READ_FIFO: begin
                    // Read data from FIFO
                    rx_fifo_rden_fsm <= 1'b1;
                    rx_state <= RX_DATA_VALID;
                end
                
                RX_DATA_VALID: begin
                    // Data is now valid on the interface
                    rx_data_valid_fsm <= 1'b1;
                    rx_state <= RX_IDLE;  // Return to idle for next read
                end
            endcase
        end
    end
    
    // UART RX Fifo
//    uart_fifo uart_rx_fifo (
//        .clk    (uart_bus.clk),         // input wire clk
//        .srst   (!uart_bus.rst_n),      // input wire srst
//        //.din    (rx_fifo_din),          // input wire [7 : 0] din
//        .din    (rx_data_internal),     // input wire [7 : 0] din
//        .wr_en  (rx_fifo_wr_en),        // input wire wr_en
//        //.rd_en  (rx_fifo_rd_en),        // input wire rd_en
//        .rd_en  (rx_fifo_rden_fsm),        // input wire rd_en
//        //.dout   (uart_bus.rx_data),     // output wire [7 : 0] dout - connected to interface
//        .dout   (rx_fifo_dout),     // output wire [7 : 0] dout - connected to interface
//        .full   (rx_fifo_full),         // output wire full
//        .empty  (rx_fifo_empty)         // output wire empty
//    );
    
    // logic rx_fifo_prog_full;
    uart_fifo uart_rx_fifo (
        .clk       (uart_bus.clk),       // input wire clk
        .srst      (!uart_bus.rst_n),    // input wire srst
        .din       (rx_data_internal),   // input wire [7 : 0] din
        .wr_en     (rx_fifo_wr_en),      // input wire wr_en
        .rd_en     (rx_fifo_rden_fsm),   // input wire rd_en
        .dout      (rx_fifo_dout),       // output wire [7 : 0] dout
        .full      (rx_fifo_full),       // output wire full
        .empty     (rx_fifo_empty),      // output wire empty
        .prog_full (rx_fifo_prog_full)   // output wire prog_full
    );
    
    assign uart_bus.rx_data = rx_fifo_dout;
    
    // UART instantiation
    uart_rx #(
        .DATA_BITS(DATA_BITS)
    ) rx_inst (
        .i_clk            (uart_bus.clk),
        .i_rst_n          (uart_bus.rst_n),
        .i_uart_rx        (i_uart_rx),
        .o_rx_data        (rx_data_internal),        // Connect to internal signal
        .o_rx_data_valid  (rx_data_valid_internal),  // Connect to internal signal
        .o_rx_frame_error (rx_frame_error_internal), // Connect to internal signal
        .i_baud_tick      (baud_tick_16x)
    );
    
endmodule
