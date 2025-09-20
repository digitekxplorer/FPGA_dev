`timescale 1ns / 1ps
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
        output wren, addr, wdata,
        input  rdata
    );

    // View from Memory that drives rdata (like BRAM)
    modport slave (
        input  wren, addr, wdata,
        output rdata
    );
    
    // NEW: View from MMIO that only READS bus signals, never drives rdata
    modport mmio_reader (
        input  wren, addr, wdata
        // Note: NO rdata connection - MMIO provides data through separate output
    );
        
    // NEW: View from CPU that only Writes bus signals, never drives rdata
    modport mmio_writer (
        output  wren, addr, wdata
        // Note: NO rdata connection - MMIO provides data through separate output
    );
endinterface


// --- GPIO Output Bus Interface ---
interface gpio_bus_if (input logic clk, input logic rst_n);
    logic [`DATA_WIDTH-1:0] data;
    logic                   wren;
    logic                   mmio_rden;
    logic                   dmem_byt_rden;
    logic                   dmem_byt_wrflg;

    // View from the CPU (controller)
    modport cpu (
        output data,
        output wren,
        output mmio_rden,
        output dmem_byt_rden,
        output dmem_byt_wrflg
    );
    
    // View from the device (MMIO peripheral, i.e. UART)
    modport peripheral (
        input data,
        input wren,
        input mmio_rden,
        input dmem_byt_rden,
        input dmem_byt_wrflg
    );
    
    // View from the CPU (controller)
    modport gpio_writer (
        output data,
        output wren,
        output mmio_rden
//        output dmem_byt_rden,
//        output dmem_byt_wrflg
    );
       
endinterface

// --- Programmable Interrupt Controller (PIC) Bus Interface ---
// SIMPLIFIED PIC Interface - Only signals that cross module boundaries
interface pic_if (input logic clk, input logic rst_n);
    // Signals from PIC to CPU
    logic [ 3:0] grant_vec;    // Grant interrupt vector to CPU
    logic        intrpt;       // Master interrupt signal to CPU
    logic        pending_int;  // Pending interrupt status to CPU
    
    // CPU uses these signals (connected in core.sv)
    modport cpu (
        input  grant_vec, intrpt, pending_int
    );
    
    // PIC drives these signals
    modport pic (
        output grant_vec, intrpt, pending_int
    );
endinterface


// SEPARATE interface for MMIO register access to PIC
interface pic_mmio_if (input logic clk, input logic rst_n);
    // PIC status registers (from PIC to MMIO)
    logic [15:0] irr;          // Interrupt Request Register  
    logic [15:0] isr;          // In-Service Register
    
    // PIC control registers (from MMIO to PIC)
    logic [15:0] imr;          // Interrupt Mask Register
    logic [ 3:0] eoi_irq_num;  // EOI IRQ number
    logic        eoi_update;   // EOI update pulse
    
    // MMIO controller side (from mmio registers)
    modport mmio (
        input  irr, isr,                           // Read status from PIC
        output imr, eoi_irq_num, eoi_update       // Control signals to PIC
    );
    
    // PIC peripheral side  
    modport pic (
        output irr, isr,                          // Status to MMIO
        input  imr, eoi_irq_num, eoi_update      // Control from MMIO
    );
    
endinterface

// ******************************


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
        input clk, rst_n, enable, reset, mode, prescale_en, prescale, reload_value,
        output timeout, overflow, running, count 
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
        input clk, rst_n, tx_data, tx_start, reset_flags,
        output tx_fifo_avail, rx_data, rx_fifo_avail, rx_frame_error, rx_fifo_prog_full
    );
endinterface

// ***********************************
// ***********************************
// --- PIO Interface ---
interface pio_if (
    input logic clk,
    input logic rst_n
);
    // Configuration signals
    logic        pio_go;
    logic [1:0]  state_machine_id;
    logic        bootload_start;
    logic [3:0]  program_select;
    logic [4:0]  execctrl_jmp_pin;
    logic [4:0]  shiftctrl_pull_thresh;
    logic [4:0]  shiftctrl_push_thresh;
    logic        autopush_enable;
    logic        autopull_enable;
    logic [4:0]  pinctrl_in_base;
    logic [4:0]  pinctrl_out_base;
    logic [4:0]  pinctrl_out_count;
    logic [4:0]  shiftctrl_in_count;
    logic        shiftctrl_in_shiftdir;
    logic        shiftctrl_autopush_en;
    logic [4:0]  shiftctrl_autopush_thresh;
    logic        shiftctrl_autopull_en;
    logic [4:0]  shiftctrl_autopull_thresh;
    logic        shiftctrl_out_shiftdir;
    
    // Instruction programming
//    logic        imem_write_en;
//    logic [4:0]  imem_write_addr;
//    logic [15:0] imem_write_data;
    
    // FIFO interfaces
    logic [31:0] tx_fifo_wr_data;
    logic        tx_fifo_wren;
    logic        tx_fifo_full;
    logic        rx_fifo_rden;
    logic [31:0] rx_fifo_datout;
    logic        rx_fifo_mt;
    
    // IRQ interface
    logic [7:0]  irq_flags_in;
    logic [7:0]  irq_flags_clear;
    logic [7:0]  irq_flags_set;
    
    // Status/Debug
    logic        bootload_done;
    logic        bootload_error;
    logic        pio_out_pin;         // used as PIO output pins status
//    logic [4:0]  debug_pc;
    logic        debug_waiting;
    
    modport controller (
        output pio_go, state_machine_id, bootload_start, program_select,
               execctrl_jmp_pin, shiftctrl_pull_thresh,
               shiftctrl_push_thresh, autopush_enable, autopull_enable,
               pinctrl_in_base, pinctrl_out_base, pinctrl_out_count,
               shiftctrl_in_count, shiftctrl_in_shiftdir, shiftctrl_autopush_en,
               shiftctrl_autopush_thresh, shiftctrl_autopull_en, 
               shiftctrl_autopull_thresh, shiftctrl_out_shiftdir,
//               imem_write_en, imem_write_addr, imem_write_data,
               tx_fifo_wr_data, tx_fifo_wren, rx_fifo_rden, irq_flags_in,
        input  tx_fifo_full, rx_fifo_datout, rx_fifo_mt, irq_flags_clear,
//               irq_flags_set, debug_pc, debug_waiting
               irq_flags_set, bootload_done, bootload_error, pio_out_pin, debug_waiting
    );
    
    modport peripheral (
        input  pio_go, state_machine_id, bootload_start, program_select,
               execctrl_jmp_pin, shiftctrl_pull_thresh,
               shiftctrl_push_thresh, autopush_enable, autopull_enable,
               pinctrl_in_base, pinctrl_out_base, pinctrl_out_count,
               shiftctrl_in_count, shiftctrl_in_shiftdir, shiftctrl_autopush_en,
               shiftctrl_autopush_thresh, shiftctrl_autopull_en, 
               shiftctrl_autopull_thresh, shiftctrl_out_shiftdir,
//               imem_write_en, imem_write_addr, imem_write_data,
               tx_fifo_wr_data, tx_fifo_wren, rx_fifo_rden, irq_flags_in,
        output tx_fifo_full, rx_fifo_datout, rx_fifo_mt, irq_flags_clear,
 //              irq_flags_set, debug_pc, debug_waiting
               irq_flags_set, bootload_done, bootload_error, pio_out_pin, debug_waiting
    );
    
endinterface


`endif // ABCORE_INTERFACES_SV
