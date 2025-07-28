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
//`define MEMORYMODELSIM    // use hex file
//`define SIMSPEEDUPCLK     // use Testbench 12MHz clock

// --- FOR SIMULATION: Use a fast, behavioral memory model ---
// Remember: Must add new coe and hex files to abCore16 project as Coefficient 
// and Memory Files!!
// .ab Programs
// `define IMEM_HEX_FILE "myProg_add.hex" // << CHANGE THIS TO YOUR TEST PROGRAM
//`define IMEM_HEX_FILE "myProg_generic.hex" // Comprehensive Test (.ab)
//`define IMEM_HEX_FILE "myProg_loadi.hex" // Comprehensive Test (.ab)
// SAL Programs
//`define IMEM_HEX_FILE "test_func.hex"  // Test STORFR, LOADFR
// SSL Programs: C-like with main()
//`define IMEM_HEX_FILE "test_program_short.hex"  // several C-Like features
//`define IMEM_HEX_FILE "test_arrays.hex"  // arrays
//`define IMEM_HEX_FILE "test_forLp.hex"  // for Loop
//`define IMEM_HEX_FILE "test_mmio.hex"  // memory-mapped I/O
//`define IMEM_HEX_FILE "test_pointers.hex"  // C-like pointers
//`define IMEM_HEX_FILE "test_postfix.hex"  // p++ and p--
//`define IMEM_HEX_FILE "test_new_features.hex"  // p++ and p--, else if, switch
//`define IMEM_HEX_FILE "test_blink.hex"  // blink LED using SW counters
//`define IMEM_HEX_FILE "test_timer.hex"  // blink LED using HW timer
`define IMEM_HEX_FILE "test_uart.hex"  // UART at 9600 baud

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
    input  logic                   tx_trigger_btn_i, // From a push-button to send a test byte 
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
logic [`DATA_WIDTH-1:0] dmem_bram_rdata_i; // Renamed to distinguish from interface rdata

logic [15:0] mmio_rd_data;
logic        mmio_rd_valid;
logic        uart_rx_access;
logic        memorymap_range;
logic        tx_start_btn;
//logic        mmio_rden;
// LED control signal
logic [15:0] led_ctrl;
// clock and reset
logic clk;
logic rst_n;
logic locked;

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
timer_if timer_bus ( .clk(clk), .rst_n(rst_n) );
uart_if  uart_bus  ( .clk(clk), .rst_n(rst_n) );
// --- CPU Bus Interfaces ---
imem_bus_if imem_bus ( .clk(clk), .rst_n(rst_n) );
dmem_bus_if dmem_bus ( .clk(clk), .rst_n(rst_n) );
gpio_bus_if gpio_bus ( .clk(clk), .rst_n(rst_n) );

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
// The top-level output ports are now driven by the gpio_bus interface
assign gpio_out_o    = gpio_bus.data;
assign gpio_out_we_o = gpio_bus.wren;


//================================================================
// Memory-mapped IO range check and data mux
//================================================================
// Memory-mapped IO between 0x1800 and 0x1900 (6144 and 6400)
// --- Data Memory Read Mux ---
// This logic now determines what data gets driven INTO the dmem_bus
//assign memorymap_range = ( dmem_bus.addr >= 6144 && dmem_bus.addr < 6400 );
assign memorymap_range = ( dmem_bus.addr >= MMIO_ADDRESS_BASE && 
                           dmem_bus.addr < (MMIO_ADDRESS_BASE + MMIO_ADDRESS_RANGE) );
always_comb begin
    if (memorymap_range) begin
        dmem_bus.rdata = mmio_rd_data;      // Read data comes from memory-mapped IO
    end else begin
        dmem_bus.rdata = dmem_bram_rdata_i; // Read data comes from BRAM
    end
end

//================================================================
// Module Instantiations
//================================================================
// --- abCore16 microprocessor core ---
// There are three microprocessor interfaces defined: 
// 1) instruction memory  (access instructions from memory)
// 2) data memory (access both data and memory-mapped IO)
// 3) GPIO bus (GPIO bus used for print instruction)
core core01 (
    .clk       (clk),
    .rst_n     (rst_n),
    .imem_bus  (imem_bus.master),  // instruction bus interface
    .dmem_bus  (dmem_bus.master),  // data bus interface
    .gpio_bus  (gpio_bus.cpu),     // gpio bus interface
//    .mmio_rden_o (mmio_rden),      // memory read Rd = Mem[Rs_addr]
    .halted_o  (halted_o)
);

// --- Memory-mapped IO Registers ---
// Use CPU data bus to access memory-mapped registers.
mmio_regs mmio_regs01 (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .dmem_bus               (dmem_bus.slave),        // cpu interface (data bus)
    .timer_bus              (timer_bus.controller),  // timer interface
    .uart_bus               (uart_bus.controller),   // uart interface
    .memorymap_range        (memorymap_range),
    .mmio_rd_data_o         (mmio_rd_data),
    .mmio_rd_valid_o        (mmio_rd_valid),
    .uart_rx_access_o       (uart_rx_access),
    .led_ctrl_o             (led_ctrl)
);

// --- Timer Module Instantiation ---
timer timer01 (
    // Connect the peripheral side of the interface
    .timer_bus(timer_bus.peripheral)    // timer interface
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
//    .i_mmio_rden       (mmio_rden),            // memory read Rd = Mem[Rs_addr]
    .gpio_bus          (gpio_bus.peripheral),    // gpio and mmio
    .o_uart_tx         (uart_tx_o),
    .i_uart_rx         (uart_rx_sync)
);

// --- UART Manual Trigger using pushbutton ---
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


//================================================================
// Conditional Memory Instantiation
//================================================================
// Use .hex file for fast simulation model without having to update
// BRAM IP.

`ifdef MEMORYMODELSIM
    
    initial begin
        $display("SIM_INFO: Compiling with SIMULATION behavioral memory model.");
        $display("SIM_INFO: Loading instruction memory from '%s'.", `IMEM_HEX_FILE);
    end

    // Behavioral Instruction and Data Memory
    logic [7:0] instruction_memory [0:`INSTRUCTION_MEMORY_BYTES-1];
    logic [`DATA_WIDTH-1:0] data_memory [0: (`DATA_MEMORY_BYTES/2)-1];
    // Read the .hex file and place in Instruction Memory, much faster process
    // than updating the BRAM IP.
    initial $readmemh(`IMEM_HEX_FILE, instruction_memory);

    // Read from Instruction and Data memory. Use bus interfaces.
    // One clock latency to match BRAM behavior
    always_ff @(posedge clk) begin
        // The memory drives the read data signal of the instruction bus
        imem_bus.rdata  <= instruction_memory[imem_bus.addr];
        // The memory drives the dedicated BRAM read data wire
        dmem_bram_rdata_i = data_memory[dmem_bus.addr >> 1];
    end
    
    // Write to Data memory
    // Use bus interfaces.
    // One clock latency to match BRAM behavior
    always_ff @(posedge clk) begin
        // Check the write enable from the data bus
        if (dmem_bus.wren) begin
            // Use the address and write data from the data bus
            data_memory[dmem_bus.addr >> 1] <= dmem_bus.wdata;
        end
    end
    
`else
    // --- FOR SYNTHESIS: Use the real BRAM IP Core ---
    // BRAM IP must be updated with the lastest .coe to initialize the
    // instruction memory with the last C-like program or assembly language
    // program.
    initial begin
        $display("INFO: Compiling with SYNTHESIS BRAM IP Core model.");
    end
    
    
    logic [`ADDR_WIDTH-2:0] dmem_word_addr;
    // Convert the byte address from the CPU to a word address for the BRAM
    // by right-shifting by one (equivalent to dropping the LSB).
    assign dmem_word_addr = dmem_bus.addr >> 1;

    // BRAM: Program Memory IP Core
    // NOTE: instruction memory access is 8-bits while data memory access is 
    // 16-bit so a true dual port BRAM was used to provide both 8-bit and
    // 16-bit access in a single memory.
    abCore16_blk_mem cpu_mem (
        // Instruction Memory Interface (connected to imem_bus, 8-bit access)
        // Instruction memory is a ROM or read-only so wea is always 1'b0.
        .clka   ( clk ),
        .ena    ( 1'b1 ),    // dout always active
        .wea    ( 1'b0 ),
        .addra  ( imem_bus.addr[12:0] ),
        .dina   ( 9'b0 ),
        .douta  ( imem_bus.rdata ),   // BRAM drives the interface's read data
        // Data Memory Interface (connected to dmem_bus, 16-bit access)
        .clkb   ( clk ),
        .enb    ( 1'b1 ),    // dout always active
        .web    ( dmem_bus.wren ),
        .addrb  ( {1'b0, dmem_word_addr} ),
        .dinb   ( {2'b00, dmem_bus.wdata} ),
        .doutb  ( dmem_bram_rdata_i )    // BRAM drives the dedicated bus
    );
`endif
    
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
// This block uses the dmem_bus interface signals
always_ff@(posedge clk) begin
   if(!rst_n) begin 
       led3_o <= 1'b0; 
       led3   <= 1'b0;
   end
   else begin 
       // LED memory-mapped IO address = 0x1818 (6168)
       // Check for a write to the correct address using the DATA MEMORY BUS
       // ADDRESS_LED_CTRL
       if ( (dmem_bus.wren == 1'b1) &&  (dmem_bus.addr == ADDRESS_LED_CTRL) ) begin
         if ( dmem_bus.wdata == 0 ) begin 
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
//--- ILA_0  ---
logic [31:0] probe0;
// The ILA probe uses the dmem_bus interface signals
assign probe0[31:0] = { dmem_bus.addr[8:0], uart_bus.rx_data, uart_bus.tx_data, uart_tx_o, uart_rx_sync, 
                        uart_bus.tx_start, 1'b0, uart_bus.rx_fifo_avail,
                        dmem_bus.wren, led3_o };

ila_0 ab_ILA (
	.clk     (clk),
	.probe0  (probe0)
);

endmodule
