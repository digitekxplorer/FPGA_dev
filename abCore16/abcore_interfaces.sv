// ---------------------------------------------------------------------------
// File: abcore_interfaces.sv
// Engineer: Al Baeza
// Create Date: 07/24/2025
// Description:
// Contains SystemVerilog interfaces for the abCore16 project to bundle
// signals and simplify module connections.
// ---------------------------------------------------------------------------

// Add an include guard to prevent multiple definitions
`ifndef ABCORE_INTERFACES_SV
`define ABCORE_INTERFACES_SV

`include "defines.svh"

// --- Instruction Memory Bus Interface ---
interface imem_bus_if (input logic clk, input logic rst_n);
    logic [`ADDR_WIDTH-1:0] addr;
    logic [7:0]             rdata;

    // View from the CPU (bus master)
    modport master (
        output addr,
        input  rdata
    );

    // View from the Memory (bus slave)
    modport slave (
        input addr,
        output rdata
    );
endinterface


// --- Data Memory Bus Interface ---
interface dmem_bus_if (input logic clk, input logic rst_n);
    logic                   wren;
    logic [`ADDR_WIDTH-1:0] addr;
    logic [`DATA_WIDTH-1:0] wdata;
    logic [`DATA_WIDTH-1:0] rdata;

    // View from the CPU (bus master)
    modport master (
        output wren,
        output addr,
        output wdata,
        input  rdata
    );

    // View from the Memory/Peripherals (bus slave)
    modport slave (
        input  wren,
        input  addr,
        input  wdata,
        output rdata
    );
endinterface


// --- GPIO Output Bus Interface ---
interface gpio_bus_if (input logic clk, input logic rst_n);
    logic [`DATA_WIDTH-1:0] data;
    logic                   wren;
    logic                   mmio_rden;

    // View from the CPU (controller)
    modport cpu (
        output data,
        output wren,
        output mmio_rden
    );
    
    // View from the device (MMIO peripheral, i.e. UART)
    modport peripheral (
        input data,
        input wren,
        input mmio_rden
    );
       
endinterface


// --- Timer Interface ---
interface timer_if (input logic clk, input logic rst_n);
    logic        enable, reset, mode, prescale_en;
    logic [15:0] prescale;
    logic [31:0] reload_value, count;
    logic        timeout, overflow, running;

    modport controller ( 
        input clk, rst_n, timeout, overflow, running, count, 
        output enable, reset, mode, prescale_en, prescale, reload_value 
    );
    
    modport peripheral ( 
        output timeout, overflow, running, count, 
        input clk, rst_n, enable, reset, mode, prescale_en, prescale, reload_value 
    );
endinterface


// --- UART Interface ---
interface uart_if (input logic clk, input logic rst_n);
    logic [7:0]  tx_data, rx_data;
    logic        tx_start, reset_flags, tx_fifo_avail, rx_fifo_avail, rx_frame_error, rx_fifo_prog_full;
    
    modport controller ( 
        input clk, rst_n, tx_fifo_avail, rx_data, rx_fifo_avail, rx_frame_error, rx_fifo_prog_full,
        output tx_data, tx_start, reset_flags 
    );
    
    modport peripheral ( 
        output tx_fifo_avail, rx_data, rx_fifo_avail, rx_frame_error, rx_fifo_prog_full,
        input clk, rst_n, tx_data, tx_start, reset_flags 
    );



//interface uart_if (input logic clk, input logic rst_n);
//    logic [7:0]  tx_data, rx_data;
//    logic        tx_start, reset_flags, tx_busy, rx_data_valid, rx_frame_error;

//    modport controller ( 
//        input clk, rst_n, tx_busy, rx_data, rx_data_valid, rx_frame_error, 
//        output tx_data, tx_start, reset_flags 
//    );
    
//    modport peripheral ( 
//        output tx_busy, rx_data, rx_data_valid, rx_frame_error, 
//        input clk, rst_n, tx_data, tx_start, reset_flags 
//    );
    
endinterface

`endif // ABCORE_INTERFACES_SV
