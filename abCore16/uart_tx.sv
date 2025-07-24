`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: ab Systems
// Engineer: Al Baeza 
// 
// Create Date: 07/17/2025 08:17:23 AM
// Design Name: UART
// Module Name: uart_tx
// Project Name: Uart
// Target Devices: xc7s25csga225-1
// Tool Versions: Vivado 2024.2
// Description: Takes a parallel byte and serializes it out.
// This is the definitive final version with corrected state machine
// output logic to ensure all bits are held for the full period.
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module uart_tx #(
    parameter DATA_BITS = 8,
    parameter STOP_BITS = 1
) (
    input  logic                  i_clk,
    input  logic                  i_rst_n,

    // Control/Data Interface
    input  logic [DATA_BITS-1:0]  i_tx_data,
    input  logic                  i_tx_start,
    output logic                  o_tx_busy,

    // Physical Interface
    output logic                  o_uart_tx,

    // Timing
    input  logic                  i_baud_tick // One pulse per bit period
);

    // State machine states
    typedef enum logic [1:0] {
        IDLE,
        START_BIT,
        DATA_BITS_STATE,
        STOP_BITS_STATE
    } tx_state_e;

    tx_state_e state_reg, state_next;
    logic [DATA_BITS-1:0] tx_data_reg;
    logic [$clog2(DATA_BITS):0] bits_sent_reg, bits_sent_next;
    logic tx_reg; // Output register

    // Sequential Logic (Registers)
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state_reg     <= IDLE;
            bits_sent_reg <= '0;
            tx_data_reg   <= '0;
            tx_reg        <= 1'b1; // UART idle is high
        end else begin
            state_reg     <= state_next;
            bits_sent_reg <= bits_sent_next;
            
            // Latch new data only when starting a new transmission from IDLE
            if (state_reg == IDLE && i_tx_start) begin
                tx_data_reg <= i_tx_data;
            end

            // The output register is determined purely by the state
            // (This could be done in combo logic too, but this is clear)
            case (state_next)
                IDLE:            tx_reg <= 1'b1;
                START_BIT:       tx_reg <= 1'b0;
                DATA_BITS_STATE: tx_reg <= tx_data_reg[bits_sent_reg];
                STOP_BITS_STATE: tx_reg <= 1'b1;
                default:         tx_reg <= 1'b1;
            endcase
        end
    end

    // Combinational Logic (Next State and Counter Logic)
    always_comb begin
        // Default assignments: stay in current state
        state_next     = state_reg;
        bits_sent_next = bits_sent_reg;

        case (state_reg)
            IDLE: begin
                if (i_tx_start) begin
                    state_next = START_BIT;
                end
            end

            START_BIT: begin
                if (i_baud_tick) begin
                    state_next     = DATA_BITS_STATE;
                    bits_sent_next = '0;
                end
            end

            DATA_BITS_STATE: begin
                if (i_baud_tick) begin
                    if (bits_sent_reg == DATA_BITS - 1) begin
                        state_next     = STOP_BITS_STATE;
                        bits_sent_next = '0;
                    end else begin
                        bits_sent_next = bits_sent_reg + 1;
                    end
                end
            end

            STOP_BITS_STATE: begin
                if (i_baud_tick) begin
                    // Note: For simplicity, only 1 stop bit is handled.
                    state_next = IDLE;
                end
            end

            default: begin
                state_next = IDLE;
            end
        endcase
    end

    // Final output assignments
    assign o_tx_busy = (state_reg != IDLE);
    assign o_uart_tx = tx_reg;

endmodule

