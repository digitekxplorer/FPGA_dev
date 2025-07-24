`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: ab Systems
// Engineer: Al Baeza
// 
// Create Date: 07/22/2025
// Design Name: abCore16 Timer Module
// Module Name: timer
// Project Name: abCore16
// Target Devices: Xilinx FPGA
// Tool Versions: Vivado
// Description: 
// Timer module extracted from cpu_tl. Provides configurable timer functionality
// with prescaler, reload capability, and status reporting.
//
//////////////////////////////////////////////////////////////////////////////////

import timer_uart_reg_pkg::*;

module timer (
    input  logic        clk,
    input  logic        rst_n,
    
    // Timer control and configuration inputs
    input  logic        ctrl_enable,
    input  logic        ctrl_reset,
    input  logic        ctrl_mode,        // 0 = one-shot, 1 = continuous
    input  logic        ctrl_prescale_en,
    input  logic [15:0] prescale_value,
    input  logic [31:0] reload_value,
    
    // Timer status outputs
    output logic        timeout_o,
    output logic        overflow_o,
    output logic        running_o,
    output logic [31:0] count_o
);

//================================================================
// Internal signals
//================================================================
logic [15:0] prescale_counter;
logic        prescale_tick;
logic [31:0] counter_reg;
logic        timer_running;
logic        timeout_internal;
logic        overflow_internal;

//================================================================
// Timer Logic
//================================================================

// Prescaler logic
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        prescale_counter <= 16'h0;
        prescale_tick <= 1'b0;
    end else begin
        prescale_tick <= 1'b0;
        if (ctrl_prescale_en && timer_running) begin
            if (prescale_counter >= prescale_value) begin  // 50,000 (0xc350) = 1 mSec
                prescale_counter <= 16'h0;
                prescale_tick <= 1'b1;
            end else begin
                prescale_counter <= prescale_counter + 1'b1;
            end
        end else if (timer_running) begin
            prescale_tick <= 1'b1;  // No prescaling, tick every clock
        end
    end
end

// Main timer counter
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        counter_reg <= 32'h0;
        timeout_internal <= 1'b0;
        overflow_internal <= 1'b0;
        timer_running <= 1'b0;
    end else begin
        timeout_internal <= 1'b0;
        
        if (ctrl_reset) begin
            counter_reg <= reload_value;
            timeout_internal <= 1'b0;
            overflow_internal <= 1'b0;
            timer_running <= 1'b0;
        end else if (ctrl_enable) begin
            timer_running <= 1'b1;
            
            if (prescale_tick) begin
                if (counter_reg == 32'h0) begin
                    timeout_internal <= 1'b1;
                    
                    if (ctrl_mode) begin
                        // Continuous mode - reload counter
                        counter_reg <= reload_value;
                    end else begin
                        // One-shot mode - stop timer
                        timer_running <= 1'b0;
                    end
                end else begin
                    counter_reg <= counter_reg - 1'b1;
                end
                
                // Check for overflow
                if (counter_reg == 32'hFFFFFFFF) begin
                    overflow_internal <= 1'b1;
                end
            end
        end else begin
            timer_running <= 1'b0;
        end
    end
end

//================================================================
// Output assignments
//================================================================
assign timeout_o = timeout_internal;
assign overflow_o = overflow_internal;
assign running_o = timer_running;
assign count_o = counter_reg;

endmodule
