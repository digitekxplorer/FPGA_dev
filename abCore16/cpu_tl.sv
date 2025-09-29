`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: ab Systems
// Engineer: Al Baeza
// 
// Create Date: 06/18/2025
// Design Name: abCore16 Top Level
// Module Name: cpu_tl
// Project Name: abCore16
// Target Devices: Xilinx FPGA
// Tool Versions: Vivado
// Description: 
// Top-level module for the abCore16 CPU. This version is updated to correctly
// instantiate the original DP-centric datapath and a compatible control unit.
// Memory-mapped functionality has been extracted into a separate core_regs module.
//
// Revision:
// Revision 1.7 - PIO added to abCore16
// Revision 1.7 - Moved CPU memory and core to cpu_system.sv
// Revision 1.6 - Multiple interrupts (Timer & UART) work
// Revision 1.5 - Fixed multiple driver issues by using continuous assignments
//                for read-only registers that directly reflect hardware state.
// Revision 1.4 - Refactored to use timer_if and uart_if interfaces.
// Revision 1.3 - Extracted memory-mapped registers into separate core_regs module
// Revision 1.2 - Extracted timer functionality into separate module
// Revision 1.1 - Corrected connections for the reverted DP-centric architecture.
// Additional Comments:
// The architecture is now DP-centric. The Datapath fetches and latches 
// instruction bytes into its IRs and provides them to the Control Unit.
//
// abCore16 Memory Map
// Memory = 0x2000 (8192)
// Code space = 0 - 0x1000 (0 - 4096)
// Memory for arrays = 0x1000 (4096) Grows up
// Memory-mapped IO base address = 0x1800 - 0x1900 (6,144 - 6,400)
// Stack base = 0x2000 - 2 = 0x1ffe (8190) Grows down to 0x190 (6,400)
//
//////////////////////////////////////////////////////////////////////////////////
import mmio_reg_pkg::*;

`include "defines.svh"
`include "abcore_interfaces.sv" // INCLUDE INTERFACES FILE

// For Synthesis, comment out both defines
`define MEMORYMODELSIM    // use hex file
`define SIMSPEEDUPCLK     // use Testbench 12MHz clock

module cpu_tl (
    input  logic clk_12MHz,
    input  logic rst_in,

    // GPIO Interface
//    input  logic [`DATA_WIDTH-1:0] gpio_in_i,  // for now reduce pin count
    output logic [`DATA_WIDTH-1:0] gpio_out_o,
    output logic                   gpio_out_we_o,
    // UART
    output logic                   uart_tx_o,
    input  logic                   uart_rx_i,
    input  logic                   tx_trigger_btn_i, // From a push-button
    // PIO GPIO Interface (NEW - ADD THESE PORTS)
//    input  logic [31:0]            pio_gpio_in_i,
//    output logic [31:0]            pio_gpio_out_o,

    // CPU halt flag
    output logic                   halted_o,
    output logic                   led2_o,
    output logic                   led3_o
);

//================================================================
// Internal parameters and signals
//================================================================
// UART parameters
localparam CLK50_FREQ = 50_000_000;
localparam UART_DATA_BITS = 8;
//localparam BAUD_RATE = 9600;
localparam BAUD_RATE = 115200;

// -- Internal signals --

logic [15:0] mmio_rd_data;
logic        mmio_rd_valid;
logic        uart_rx_access;
logic        tx_start_btn;
logic        eoi_update;
logic        enable_int;
// LED control signal
logic [15:0] led_ctrl;
// clock and reset
logic clk;
logic rst_n;
logic locked;
logic memorymap_range;

// Debug
logic [60:0] dbg_bus_pic;     // 61 signals
logic [20:0] dbg_bus_cu;      // 21 signals
logic [21:0] dbg_bus_dp;      // 22 signals 
                              // 104
// --- Programmable Interrupt Controller (PIC) Module Instantiation ---
logic [15:0] device_irqs;       // Interrupt request lines from peripherals
logic int0_timeout;
logic int1_timeout;
logic int2_timeout;
logic int1_uartrx;

// PIO
logic [31:0]  pio_gpio_in_i;
logic [31:0]  pio_gpio_out_o;
logic         pio_irq_o;
logic [31:0]  pio_gpio_dir_o;

//logic         pio_bootload_done;
//logic         pio_bootload_error; 
//logic [7:0]   irq_clear_cu;
logic [35:0]  dbg_bus_pio;

// To reduce pin count for development board assign gpio_in_i here.
logic [`DATA_WIDTH-1:0] gpio_in_i;
assign gpio_in_i = gpio_out_o;
    
//================================================================
// Conditional Clock Module Instantiation
//================================================================
// To speedup simulation, use the 12MHz clock directly from the testbench
// instead of using the MMCM clock module that takes tens of uSeconds to
// lock.

`ifdef SIMSPEEDUPCLK
// --- FOR SIMULATION: Use the Testbench 12MHz clock ---
assign clk = clk_12MHz;
assign rst_n = !rst_in;
assign locked = 1'b1;

`else
// --- FOR SYNTHESIS: Use the real MMCM IP Core ---
clk_wiz_0 abCore16_clk (
    // Clock and pushbutton reset
    .clk_in1   (clk_12MHz ),  // input clk_in1
    .reset     (rst_in),      // input reset; pushbutton
    // outputs
    .clk_out1  (clk),         // 50 MHz
    .locked    (locked)       // clk locked
);

assign rst_n = locked;
`endif

//================================================================
// Interface Instantiations
//================================================================
// Instantiate the interfaces that will bundle signals between modules.
// Pass the system clock and reset to them.
// Instantiate the interfaces that will bundle signals between modules.
// Pass the system clock and reset to them.
timer_if timer_bus ( .clk(clk), .rst_n(rst_n) );         // Instance of Interface
uart_if  uart_bus  ( .clk(clk), .rst_n(rst_n) );
// --- PIC interfaces ---
pic_if      pic_cpu_bus  ( .clk(clk), .rst_n(rst_n) );   // PIC to CPU signals
pic_mmio_if pic_mmio_bus ( .clk(clk), .rst_n(rst_n) );   // PIC to MMIO signals
// --- CPU Bus Interfaces ---
dmem_bus_if dmem_mmio_bus ( .clk(clk), .rst_n(rst_n) );
gpio_bus_if gpio_wr_bus ( .clk(clk), .rst_n(rst_n) );
// --- PIO Interface (NEW - ADD THIS LINE) ---
pio_if pio_bus ( .clk(clk), .rst_n(rst_n) );

//================================================================
// Top-Level Port Connections and Logic
//================================================================
// --- UART RX sync ---
logic [1:0] uart_rx_shft;
logic       uart_rx_sync;
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        uart_rx_shft <= 2'b00;
    end else begin
        uart_rx_shft <= { uart_rx_shft[0], uart_rx_i };
    end
end
assign uart_rx_sync = uart_rx_shft[1];

// --- GPIO Output Assignment ---
// The top-level output ports are now driven by the gpio_wr_bus interface
assign gpio_out_o    = gpio_wr_bus.data;
assign gpio_out_we_o = gpio_wr_bus.wren;


//================================================================
// Module Instantiations
//================================================================
// --- abCore16 microprocessor core plus memory ---
// There are three microprocessor interfaces defined: 
// 1) instruction memory  (access instructions from memory)
// 2) data memory (access both data and memory-mapped IO)
// 3) GPIO bus (GPIO bus used for print instruction)
cpu_system cpu_system01 (
    .clk               (clk),
    .rst_n             (rst_n),
    // Interfaces to peripherals/system
    .dmem_mmio_bus     (dmem_mmio_bus.mmio_writer),    // For MMIO access
    .gpio_wr_bus       (gpio_wr_bus.gpio_writer),      // GPIO interface
    .pic_cpu_bus       (pic_cpu_bus.cpu),              // CPU-PIC interface  
    // Direct connections
    .mmio_rd_data_i    (mmio_rd_data),
    .enable_int_o      (enable_int),
    .memorymap_range_o (memorymap_range),
    // Debug outputs
    .dbg_bus_cu        (dbg_bus_cu),                   // [20:0] 
    .dbg_bus_dp        (dbg_bus_dp),                   // [21:0] 
    // Status outputs
    .halted_o          (halted_o)
);

// --- Memory-mapped IO Registers ---
// Use CPU data bus to access memory-mapped registers.
mmio_regs mmio_regs01 (
    .clk               (clk),
    .rst_n             (rst_n),
    .dmem_bus          (dmem_mmio_bus.mmio_reader),      // CHANGED: New modport
    .timer_bus         (timer_bus.controller),     // timer interface
    .uart_bus          (uart_bus.controller),      // uart interface
    .pic_mmio_bus      (pic_mmio_bus.mmio),         // CHANGED: New PIC interface
    .pio_bus           (pio_bus.controller),        // NEW - ADD THIS LINE
    .memorymap_range   (memorymap_range),
    .mmio_rd_data_o    (mmio_rd_data),
    .mmio_rd_valid_o   (mmio_rd_valid),
    .uart_rx_access_o  (uart_rx_access),
    // REMOVED: .eoi_update_o (eoi_update),               // Now part of pic_mmio_bus
    .led_ctrl_o        (led_ctrl)
);

// --- Timer Module Instantiation ---
timer timer01 (
    // Connect the peripheral side of the interface
    .timer_bus         (timer_bus.peripheral)    // timer interface
);


// --- UART Module Instantiation ---
// UART with programmable BAUD rate.
uart_mn #(
    .CLK_FREQ(CLK50_FREQ),
    .DATA_BITS(UART_DATA_BITS),
    .BAUD_RATE(BAUD_RATE)
) uart01 (
    .uart_bus          (uart_bus.peripheral),   // uart interface
    .i_tx_start_manual (tx_start_btn),
    .i_uart_rx_access  (uart_rx_access),
    .gpio_bus          (gpio_wr_bus.peripheral),    // gpio and mmio
    .o_uart_tx         (uart_tx_o),
    .i_uart_rx         (uart_rx_sync)
);

// UART Manual Trigger using pushbutton
// Sync and edge detector for the button press to create a single-cycle 
// start pulse. Used to test UART.
logic [2:0] tx_trig_shft;
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_trig_shft  <= 3'b000;
        tx_start_btn  <= 1'b0;
    end else begin
        tx_trig_shft  <= { tx_trig_shft[1:0], tx_trigger_btn_i };
        // Pulse tx_start for one clock cycle when the button is pressed.
        tx_start_btn <= tx_trig_shft[2:1] == 2'b01;
    end
end


// --- UART Module Instantiation ---
pic pic01 (
    .clk             (clk),
    .rst_n           (rst_n),
    .pic_cpu_bus     (pic_cpu_bus.pic),      // CPU interface
    .pic_mmio_bus    (pic_mmio_bus.pic),     // MMIO interface  
    .enable_int_i    (enable_int),           
    .irq_i           (device_irqs),          // Direct connection
    .dbg_bus_pic     (dbg_bus_pic)     
);

// Assign interrupts to PIC
assign int0_timeout = timer_bus.timeout;
//assign int1_uartrx = uart_bus.rx_fifo_avail;
// UART RX int signal rising edge
logic [1:0] int01_shft;
always_ff@(posedge clk) begin
   if(!rst_n) begin
       int01_shft  <= '0;
       int1_uartrx <= 1'b0;         
   end
   else begin 
       int01_shft  <= { int01_shft[0], uart_bus.rx_fifo_avail };
       int1_uartrx <= int01_shft == 2'b01;
   end
end

//assign device_irqs = {14'h0, int1_uartrx, int0_timeout};
// Device IRQs
assign device_irqs[0] = int0_timeout;
assign device_irqs[1] = int1_uartrx;
assign device_irqs[2] = pio_irq_o;              // NEW - ADD PIO IRQ
assign device_irqs[15:3] = '0;                  // Unused IRQs

// Int 1 Shifter
logic [15:0] int00_shft;
always_ff@(posedge clk) begin
   if(!rst_n) begin
       int00_shft  <= 16'h0;          
   end
   else begin 
       int00_shft  <= { int00_shft[14:0], int0_timeout };
   end
end
// create a delayed versions of int0_timeout
assign int1_timeout = int00_shft[15];  // Int#1
assign int2_timeout = int00_shft[5];  // Int#2

//================================================================
// Programmable Input/Output (PIO) Instance
//================================================================  
assign pio_gpio_in_i = 32'ha10b_ae2a;                 // TODO: assign to real pins

pio_tl pio01 (
    .clk(clk),
    .rst_n(rst_n),
    .pio_bus(pio_bus.peripheral),         // PIO interface
    // GPIO interface
    .gpio_in(pio_gpio_in_i),
    .gpio_out( pio_gpio_out_o),
    .gpio_dir(pio_gpio_dir_o),
     // IRQ interface
//    .irq_flags_clear(pio_bus.irq_flags_clear),      // TODO: clear irq??
//    .irq_clear_cu(irq_clear_cu),                    // TODO: clear irq??
    // Debug outputs
    .dbg_bus_pio(dbg_bus_pio)
);
  
// IRQ generation
assign pio_irq_o = |pio_bus.irq_flags_set;   // irq 0-7 ORed
    
//================================================================
// LED Control Logic
//================================================================
// Blink LED
// blink counter
logic [24:0] count = '0;

always_ff@(posedge clk) begin
   if(!rst_n) begin // Synthesis tools correctly infer an async reset here
       count <= '0; 
   end
   else begin 
       count <= count + 1; 
   end
end

assign led2_o = count[22];

// Use abCore16 software counters to toggle LED
// Memory-mapped I/O for LED control
logic led3;
// This block uses the dmem_mmio_bus interface signals
always_ff@(posedge clk) begin
   if(!rst_n) begin 
       led3_o <= 1'b0; 
       led3   <= 1'b0;
   end
   else begin 
       // LED memory-mapped IO address = 0x1818 (6168)
       // Check for a write to the correct address using the DATA MEMORY BUS
       // ADDRESS_LED_CTRL
       if ( (dmem_mmio_bus.wren == 1'b1) &&  (dmem_mmio_bus.addr == ADDRESS_LED_CTRL) ) begin
         if ( dmem_mmio_bus.wdata == 0 ) begin 
             led3_o <= 1'b0;
             led3   <= 1'b0;
         end
         else begin 
             led3_o <= 1'b1;
             led3   <= 1'b1;
         end
       end 
   end
end
    
//================================================================
// ILA INSTANTIATION
//================================================================
// Debug
//logic [60:0] dbg_bus_pic;     // 61 signals
//logic [20:0] dbg_bus_cu;      // 21 signals
//logic [21:0] dbg_bus_dp;      // 22 signals 
//                                 104 signals
// logic [35:0]  dbg_bus_pio;   // 36
// 21 + 22 + 36 = 79
// Total: 79 + 3 = 82
//--- ILA_0  ---
//logic [107:0] probe0;
logic [81:0] probe0;
// The ILA probe uses the dmem_mmio_bus interface signals
//assign probe0[31:0] = { dmem_mmio_bus.addr[8:0], uart_bus.rx_data, uart_bus.tx_data, uart_tx_o, uart_rx_sync, 
//                        uart_bus.tx_start, 1'b0, uart_bus.rx_fifo_avail,
//                        dmem_mmio_bus.wren, led3_o };

//assign probe0 = { led3_o, uart_bus.tx_start, uart_bus.rx_fifo_avail, dmem_mmio_bus.wren,
//                  dbg_bus_pic, dbg_bus_cu, dbg_bus_dp };
                  
//assign probe0 = { 46'h0, dbg_bus_pio};
                  
assign probe0 = { led3_o, uart_bus.tx_start, uart_bus.rx_fifo_avail, dmem_mmio_bus.wren,
                  dbg_bus_pio, dbg_bus_cu, dbg_bus_dp };

// Debug logic analyzer
ila_0 ab_ILA (
	.clk     (clk),
	.probe0  (probe0)
);

endmodule
