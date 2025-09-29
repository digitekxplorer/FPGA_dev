`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: ab Systems
// Engineer: Al Baeza
// 
// Create Date: 08/25/2025
// Design Name: abCore16 CPU Subsystem
// Module Name: cpu_subsystem
// Project Name: abCore16
// Target Devices: Xilinx FPGA
// Tool Versions: Vivado
// Description: 
// Complete CPU subsystem for the abCore16 processor. This module combines
// the processor core, programmable interrupt controller (PIC), and memory
// subsystem into a single cohesive unit. This provides a cleaner interface
// to the top-level system and better encapsulation of CPU functionality.
//
// Revision:
// Revision 1.0 - Initial creation from cpu_tl.sv refactoring
//
//////////////////////////////////////////////////////////////////////////////////
import mmio_reg_pkg::*;

`include "defines.svh"
`include "abcore_interfaces.sv"

// For Synthesis, comment out both defines
`define MEMORYMODELSIM    // use hex file
`define SIMSPEEDUPCLK     // use Testbench 12MHz clock

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
//`define IMEM_HEX_FILE "test_char.hex"  // test char data type
//`define IMEM_HEX_FILE "test_loadb_storb.hex"  // Test byte instructions
//`define IMEM_HEX_FILE "test_loadbfr_storbfr.hex"  // Test byte instructions, frame relative
//`define IMEM_HEX_FILE "test_uart.hex"  // UART at 115,200 baud
//`define IMEM_HEX_FILE "test_interrupt.hex"   // Interrupt testing
`define IMEM_HEX_FILE "test_pio.hex"  // First PIO example; configure PIO


module cpu_system (
    input  logic clk,
    input  logic rst_n,
    // External interfaces to peripherals/system
    dmem_bus_if.mmio_writer dmem_mmio_bus,     // For MMIO access
    gpio_bus_if.gpio_writer gpio_wr_bus,     // GPIO interface
    // PIC interfaces
    pic_if.cpu         pic_cpu_bus,       // CPU-PIC interface
    // Direct connections
    input  logic [15:0] mmio_rd_data_i,
    output logic        enable_int_o,
    output logic        memorymap_range_o,
    // Debug outputs
    output logic [20:0] dbg_bus_cu,
    output logic [21:0] dbg_bus_dp,
    // Status outputs
    output logic        halted_o
);

//================================================================
// Internal Bus Interfaces
//================================================================
// Create internal interfaces for CPU-Memory communication
imem_bus_if imem_internal_bus ( .clk(clk), .rst_n(rst_n) );  // Instance of Interface
dmem_bus_if dmem_internal_bus ( .clk(clk), .rst_n(rst_n) );
// GPIO interface
gpio_bus_if gpio_internal_bus ( .clk(clk), .rst_n(rst_n) );

// --- CPU Bus Interfaces ---
//imem_bus_if imem_bus ( .clk(clk), .rst_n(rst_n) );

//================================================================
// Module Instantiations
//================================================================

// --- abCore16 Processor Core ---
core core01 (
    .clk          (clk),
    .rst_n        (rst_n),
    .imem_bus     (imem_internal_bus.master),
    .dmem_bus     (dmem_internal_bus.master), 
    .gpio_bus     (gpio_internal_bus.cpu),
    .pic_bus      (pic_cpu_bus),
    .enable_int_o (enable_int_o),
    .dbg_bus_cu   (dbg_bus_cu),
    .dbg_bus_dp   (dbg_bus_dp),
    .halted_o     (halted_o)
);

// --- Memory Subsystem ---
//memory_subsystem memory_inst (
//    .clk       (clk),
//    .rst_n     (rst_n),
//    .imem_bus  (imem_internal_bus.memory),
//    .dmem_bus  (dmem_internal_bus.memory),
//    .gpio_bus  (gpio_internal_bus.memory)
//);

//================================================================
// External Interface Connections
//================================================================

// Connect internal DMEM bus to external for MMIO access
// Only forward memory-mapped range accesses to external bus
assign dmem_mmio_bus.wren  = dmem_internal_bus.wren && memorymap_range_o;
assign dmem_mmio_bus.addr  = dmem_internal_bus.addr;
assign dmem_mmio_bus.wdata = dmem_internal_bus.wdata;

//assign dmem_external_bus.wren  = dmem_internal_bus.wren && memorymap_range_o;
//assign dmem_external_bus.addr  = dmem_internal_bus.addr;
//assign dmem_external_bus.wdata = dmem_internal_bus.wdata;
// Read data is handled by the mux above

// Connect GPIO interfaces
assign gpio_wr_bus.data           = gpio_internal_bus.data;
assign gpio_wr_bus.wren           = gpio_internal_bus.wren;
assign gpio_wr_bus.mmio_rden      = gpio_internal_bus.mmio_rden;
//assign gpio_wr_bus.dmem_byt_rden  = gpio_internal_bus.dmem_byt_rden;
//assign gpio_wr_bus.dmem_byt_wrflg = gpio_internal_bus.dmem_byt_wrflg;

//================================================================
// Conditional Memory Instantiation
//================================================================
logic                   dmem_wren_fsm;
logic [`ADDR_WIDTH-2:0] dmem_word_addr_fsm;
logic [15:0]            dmem_word_data_fsm;

logic [`DATA_WIDTH-1:0] dmem_bram_rdata_i; // Renamed to distinguish from interface rdata

// Use .hex file for fast simulation model without having to update
// BRAM IP.

logic [`ADDR_WIDTH-2:0] dmem_word_addr;
// Convert the byte address from the CPU to a word address for the BRAM
// by right-shifting by one (equivalent to dropping the LSB).
assign dmem_word_addr = dmem_internal_bus.addr >> 1;

`ifdef MEMORYMODELSIM
    
    initial begin
        $display("SIM_INFO: Compiling with SIMULATION behavioral memory model.");
        $display("SIM_INFO: Loading instruction memory from '%s'.", `IMEM_HEX_FILE);
    end

    // Behavioral Instruction Memory
    logic [7:0] instruction_memory [0:`INSTRUCTION_MEMORY_BYTES-1];
    // Data Memory
    logic [`DATA_WIDTH-1:0] data_memory [0: (`DATA_MEMORY_BYTES/2)-1];
    
    // Initialize data memory
    initial begin
        for (int i = 0; i > (`DATA_MEMORY_BYTES/2)-1; i++) begin
            data_memory[i] <= 16'h0; // clear data memory
        end
    end
    
     // Read the .hex file and place in Instruction Memory, much faster process
    // than updating the BRAM IP.
    initial $readmemh(`IMEM_HEX_FILE, instruction_memory);

    // ********************
    // Read from Instruction and Data memory
    // ********************
    // Use bus interfaces. One clock latency to match BRAM behavior.
    always_ff @(posedge clk) begin
        // The memory drives the read data signal of the instruction bus
        imem_internal_bus.rdata  <= instruction_memory[imem_internal_bus.addr];
        // The memory drives the dedicated BRAM read data
//        dmem_bram_rdata_i = data_memory[dmem_internal_bus.addr >> 1];
        dmem_bram_rdata_i = data_memory[dmem_word_addr_fsm];  // signal from FSM
    end
    
    // ********************
    // Write to Data memory
    // ********************
    // Use bus interfaces.
    // One clock latency to match BRAM behavior
    always_ff @(posedge clk) begin
        // Check the write enable from the data bus
        if (dmem_wren_fsm) begin
            // Use the address and write data from the data bus
            data_memory[dmem_word_addr_fsm] <= dmem_word_data_fsm; // signal from FSM
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
    

    // BRAM: Program Memory IP Core
    // NOTE: instruction memory access is 8-bits while data memory access is 
    // 16-bit so a true dual port BRAM was used to provide both 8-bit and
    // 16-bit access in a single memory.
    abCore16_blk_mem cpu_mem (
        // Instruction Memory Interface (connected to imem_internal_bus, 8-bit access)
        // Instruction memory is a ROM or read-only so wea is always 1'b0.
        .clka   ( clk ),
        .ena    ( 1'b1 ),    // dout always active
        .wea    ( 1'b0 ),
        .addra  ( imem_internal_bus.addr[12:0] ),
        .dina   ( 9'b0 ),
        .douta  ( imem_internal_bus.rdata ),   // BRAM drives the interface's read data
        // Data Memory Interface (connected to dmem_bus, 16-bit access)
        .clkb   ( clk ),
        .enb    ( 1'b1 ),    // dout always active
        .web    ( dmem_wren_fsm ),               // signal from FSM
        .addrb  ( {1'b0, dmem_word_addr_fsm} ),  // signal from FSM
        .dinb   ( {2'b00, dmem_word_data_fsm} ), // signal from FSM
        .doutb  ( dmem_bram_rdata_i )    // BRAM drives the dedicated bus
    );
`endif


//================================================================
// Byte Access Logic: Read-Modify-Write
//================================================================

// ****************
// Byte Write Logic
// ****************
logic    dmem_byt_wrflg_r;
logic    dmem_addr_lsb_r;
logic    dmem_addr_lsb_2r;
logic [`ADDR_WIDTH-2:0] dmem_word_addr_sav;
logic [15:0]            dmem_wdata_r;
logic [15:0]            dmem_wdata_low_sav;
logic [15:0]            dmem_wdata_hi_sav;


// Delay logic
always_ff@(posedge clk) begin
   if(!rst_n) begin
       dmem_addr_lsb_r      <= 1'b0;
       dmem_addr_lsb_2r     <= 1'b0;
       dmem_byt_wrflg_r     <= 1'b0;
       // data
       dmem_wdata_r         <= 16'h0;            
   end
   else begin 
       dmem_addr_lsb_r      <= dmem_internal_bus.addr[0];
       dmem_addr_lsb_2r     <= dmem_addr_lsb_r;
       dmem_byt_wrflg_r     <= gpio_internal_bus.dmem_byt_wrflg;
       // data
       dmem_wdata_r         <= dmem_internal_bus.wdata;
   end
end

// capture address for the complete READ-Modify-Write sequence
always_ff@(posedge clk) begin
   if(!rst_n) begin
       // address
       dmem_word_addr_sav        <= '0;
   end
   else begin 
       if (gpio_internal_bus.dmem_byt_wrflg) begin
           dmem_word_addr_sav        <= dmem_word_addr;
       end
   end
end

// capture data for the complete READ-Modify-Write sequence
always_ff@(posedge clk) begin
   if(!rst_n) begin
       // data
       dmem_wdata_low_sav        <= 16'h0;
       dmem_wdata_hi_sav         <= 16'h0;
   end
   else begin 
       if (dmem_byt_wrflg_r) begin
           dmem_wdata_low_sav        <= {dmem_bram_rdata_i[15:8], dmem_wdata_r[7:0]};
           dmem_wdata_hi_sav         <= {dmem_wdata_r[7:0], dmem_bram_rdata_i[7:0]};
       end
   end
end


// **********
// Write FSM
// **********
// We have to perform a Read-Modify-Write sequence to update one byte of a
// 16-bit word.
// State machine for byte Write
typedef enum logic [1:0] {
    IDLE,
    MEM_READ,
    MODIFY,
    MEM_WRITE
} wr_state_t;
    
wr_state_t wr_state;
    
always_ff @(posedge clk) begin
    if (!rst_n) begin
        wr_state <= IDLE;
    end else begin 
        case (wr_state)
            IDLE: begin
                if ( gpio_internal_bus.dmem_byt_wrflg ) begin
                    wr_state <= MEM_READ;
                end
            end
            // Read
            MEM_READ: begin
                wr_state <= MODIFY;
            end
            // Modify-Write
            MODIFY: begin
                wr_state <= MEM_WRITE;
            end
            // Write
            MEM_WRITE: begin
                wr_state <= IDLE;
            end
        endcase
    end
end

// Assign values to wren, addr, and data during each stage of the 
// Read-Modify-Write sequence
always_comb begin
    if(!rst_n) begin
        dmem_wren_fsm       <= 1'b0;
        dmem_word_addr_fsm  <= '0;
        dmem_word_data_fsm  <= '0;
    end
    else begin 
        // defaults
        dmem_wren_fsm <= 1'b0;
        if ( wr_state == IDLE ) begin 
	        dmem_wren_fsm       <= dmem_internal_bus.wren; 
		    dmem_word_addr_fsm  <= dmem_word_addr;
		    dmem_word_data_fsm  <= dmem_internal_bus.wdata;
	    end
		if ( wr_state == MEM_READ ) begin 
		    dmem_wren_fsm      <= 1'b0;           // do not write to memory yet
		    dmem_word_addr_fsm <= dmem_word_addr;
		    dmem_word_data_fsm <= dmem_wdata_r;
		end
		
		if ( wr_state == MODIFY ) begin 
		    dmem_wren_fsm         <= 1'b0;       // do not write to memory yet
		    dmem_word_addr_fsm    <= dmem_word_addr_sav;
		    dmem_word_data_fsm <= dmem_wdata_r;	
        end	 
        
 		if ( wr_state == MEM_WRITE ) begin  
		    dmem_wren_fsm         <= 1'b1;        // write to memory
		    dmem_word_addr_fsm    <= dmem_word_addr_sav;
		    // Select the correct byte to update
            if ( dmem_addr_lsb_2r ) begin
                // write new byte to upper byte
                dmem_word_data_fsm = dmem_wdata_hi_sav;
            end else begin
               // write new byte to lower byte
               dmem_word_data_fsm = dmem_wdata_low_sav;
            end	
		end
		
    end
end


//================================================================
// Memory-mapped IO range check and data mux
//================================================================
// Memory-mapped IO between 0x1800 and 0x1900 (6144 and 6400)
// --- Data Memory Read Mux ---
// This logic now determines what data gets driven INTO the dmem_internal_bus
assign memorymap_range_o = ( dmem_internal_bus.addr >= MMIO_ADDRESS_BASE && 
                           dmem_internal_bus.addr < (MMIO_ADDRESS_BASE + MMIO_ADDRESS_RANGE) );

// ================
// Byte Read Logic
// ================
// Reading byte from BRAM (LOADIB)
// Memory Data MUX select
logic [1:0] dmem_rd_data_sel;
always_comb begin
    dmem_rd_data_sel = 2'b00;         // default:  Read 16-bit word from BRAM
    // Byte Read
    if (gpio_internal_bus.dmem_byt_rden) begin // Byte Read is Active
        if (!memorymap_range_o) begin   // Read from BRAM
            // Select 2'b10 for lower byte, 2'b11 for upper byte
            dmem_rd_data_sel = {1'b1, dmem_internal_bus.addr[0]};
        end
    end
    // NOTE: Byte access to memory-mapped registers is undefined and falls to default
    else begin // Word Read  (16-bits)
        if (memorymap_range_o) begin     // Read 16-bit word from memory-mapped registers
            dmem_rd_data_sel = 2'b01;
        end 
        else begin                     // Read 16-bit word from BRAM
            dmem_rd_data_sel = 2'b00;
        end
    end
end

// Memory Data MUX
//     0   0    Read 16-bit word from BRAM
//     0   1    Read 16-bit word from memory-mapped registers
//     1   0    Read 16-bit word from BRAM and use lower byte
//     1   1    Read 16-bit word from BRAM and use upper byte
always_comb begin
    case( dmem_rd_data_sel )
        // Read 16-bit word from BRAM
        2'b00: dmem_internal_bus.rdata = dmem_bram_rdata_i;
        // Read 16-bit word from memory-mapped registers
        2'b01: dmem_internal_bus.rdata = mmio_rd_data_i;
        // Read 16-bit word from BRAM and use lower 8-bit byte
        2'b10: dmem_internal_bus.rdata = {8'h0,dmem_bram_rdata_i[7:0]};
        // Read 16-bit word from BRAM and use upper 8-bit byte
        2'b11: dmem_internal_bus.rdata = {8'h0,dmem_bram_rdata_i[15:8]};
        default: dmem_internal_bus.rdata = dmem_bram_rdata_i;
    endcase  
end



endmodule

