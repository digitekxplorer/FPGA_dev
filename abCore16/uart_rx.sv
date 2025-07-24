`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: ab Systems
// Engineer: Al Baeza 
// 
// Create Date: 07/17/2025 08:17:56 AM
// Design Name: UART
// Module Name: uart_rx
// Project Name: Uart
// Target Devices: xc7s25csga225-1
// Tool Versions: Vivado 2024.2
// Description: // Listens for serial data, oversamples it, and 
// converts it to parallel. 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module uart_rx #(
    parameter DATA_BITS = 8
) (
    input  logic                  i_clk,
    input  logic                  i_rst_n,

    // Physical Interface
    input  logic                  i_uart_rx,

    // Control/Data Interface
    output logic [DATA_BITS-1:0]  o_rx_data,
    output logic                  o_rx_data_valid,
    output logic                  o_rx_frame_error,

    // Timing
    input  logic                  i_baud_tick // A 16x oversampling tick
);

    // State machine states
    typedef enum logic [2:0] {
        IDLE,
        CHECK_START,
        RECEIVE_DATA,
        CHECK_STOP,
        DONE
    } rx_state_e;

    rx_state_e state_reg, state_next;
    logic [3:0] sample_count_reg, sample_count_next; // Counts 16 samples per bit
    logic [$clog2(DATA_BITS):0] bit_count_reg, bit_count_next;
    logic [DATA_BITS-1:0] rx_data_reg, rx_data_next;
    logic rx_data_valid_reg, rx_data_valid_next;
    logic frame_error_reg, frame_error_next;

    // Synchronize the asynchronous input to prevent metastability
    logic rx_sync_0, rx_sync_1, rx_sync_2;
    always_ff @(posedge i_clk) begin
        rx_sync_0 <= i_uart_rx;
        rx_sync_1 <= rx_sync_0;
        rx_sync_2 <= rx_sync_1;
    end
    
    // A falling edge indicates a potential start bit
    logic start_edge_detected;
//    assign start_edge_detected = rx_sync_1 & ~rx_sync_2;  // incorrect rising edge
    assign start_edge_detected = ~rx_sync_1 & rx_sync_2;    // correct falling edge

    // Registers
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state_reg         <= IDLE;
            sample_count_reg  <= '0;
            bit_count_reg     <= '0;
            rx_data_reg       <= '0;
            rx_data_valid_reg <= 1'b0;
            frame_error_reg   <= 1'b0;
        end else begin
            state_reg         <= state_next;
            sample_count_reg  <= sample_count_next;
            bit_count_reg     <= bit_count_next;
            rx_data_reg       <= rx_data_next;
            rx_data_valid_reg <= rx_data_valid_next;
            frame_error_reg   <= frame_error_next;
        end
    end

    // Next state logic and outputs
    always_comb begin
        state_next         = state_reg;
        sample_count_next  = sample_count_reg;
        bit_count_next     = bit_count_reg;
        rx_data_next       = rx_data_reg;
        rx_data_valid_next = 1'b0; // Default to not valid
        frame_error_next   = 1'b0; // Default to no error

        case (state_reg)
            IDLE: begin
                if (start_edge_detected) begin
                    state_next        = CHECK_START;
                    sample_count_next = '0;
                end
            end

            CHECK_START: begin
                if (i_baud_tick) begin
                    // Sample at the middle of the bit (tick 7 of 15)
                    if (sample_count_reg == 7) begin
                        if (rx_sync_2 == 1'b0) begin // It's a valid start bit
//                        if (rx_sync_2 == 1'b1) begin // start bit should be high
                            state_next        = RECEIVE_DATA;
                            sample_count_next = '0;
                            bit_count_next    = '0;
                        end else begin // False start, glitch
                            state_next = IDLE;
                        end
                    end else begin
                        sample_count_next = sample_count_reg + 1;
                    end
                end
            end

            RECEIVE_DATA: begin
                if (i_baud_tick) begin
                    if (sample_count_reg == 15) begin // End of a bit period
                        sample_count_next = '0;
                        // Sample in the middle of the bit
                        rx_data_next[bit_count_reg] = rx_sync_2;
                        
                        if (bit_count_reg == DATA_BITS - 1) begin
                            state_next = CHECK_STOP;
                        end else begin
                            bit_count_next = bit_count_reg + 1;
                        end
                    end else begin
                        sample_count_next = sample_count_reg + 1;
                    end
                end
            end

            CHECK_STOP: begin
                if (i_baud_tick) begin
                    if (sample_count_reg == 15) begin
                        if (rx_sync_2 == 1'b1) begin // Stop bit is high, frame is good
                            rx_data_valid_next = 1'b1;
                        end else begin // Stop bit is low, framing error
                            frame_error_next = 1'b1;
                        end
                        state_next = DONE;
                    end else begin
                        sample_count_next = sample_count_reg + 1;
                    end
                end
            end

            DONE: begin
                // This state ensures valid/error flags are pulsed for one clock cycle
                state_next = IDLE;
            end

            default: state_next = IDLE;
        endcase
    end

    assign o_rx_data         = rx_data_reg;
    assign o_rx_data_valid   = rx_data_valid_reg;
    assign o_rx_frame_error  = frame_error_reg;

endmodule

