`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: ab Systems
// Engineer: Al Baeza
// 
// Create Date: 07/22/2025
// Design Name: abCore16 Timer Module
// Module Name: timer
// Project Name: abCore16
//
// Revision:
// Revision 1.1 - Refactored to use timer_if interface.
//
//////////////////////////////////////////////////////////////////////////////////

//import mmio_reg_pkg::*;
`include "abcore_interfaces.sv"

module timer (
    // This port list is correct.
    timer_if.peripheral timer_bus
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
// Timer Logic - This logic now works because the modport allows access
//================================================================

// Prescaler logic
always_ff @(posedge timer_bus.clk or negedge timer_bus.rst_n) begin
    if (!timer_bus.rst_n) begin
        prescale_counter <= 16'h0;
        prescale_tick <= 1'b0;
    end else begin
        prescale_tick <= 1'b0;
        if (timer_bus.prescale_en && timer_running) begin
            if (prescale_counter >= timer_bus.prescale) begin
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
always_ff @(posedge timer_bus.clk or negedge timer_bus.rst_n) begin
    if (!timer_bus.rst_n) begin
        counter_reg <= 32'h0;
        timeout_internal <= 1'b0;
        overflow_internal <= 1'b0;
        timer_running <= 1'b0;
    end else begin
        timeout_internal <= 1'b0;
        
        if (timer_bus.reset) begin
            counter_reg <= timer_bus.reload_value;
            timeout_internal <= 1'b0;
            overflow_internal <= 1'b0;
            timer_running <= 1'b0;
        end else if (timer_bus.enable) begin
            timer_running <= 1'b1;
            
            if (prescale_tick) begin
                if (counter_reg == 32'h0) begin
                    timeout_internal <= 1'b1;
                    
                    if (timer_bus.mode) begin // Continuous mode
                        counter_reg <= timer_bus.reload_value;
                    end else begin // One-shot mode
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
// Output assignments to the interface
//================================================================
assign timer_bus.timeout  = timeout_internal;
assign timer_bus.overflow = overflow_internal;
assign timer_bus.running  = timer_running;
assign timer_bus.count    = counter_reg;

endmodule
