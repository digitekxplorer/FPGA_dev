//////////////////////////////////////////////////////////////////////////////////
// Company: ab Systems
// Engineer: Al Baeza
// 
// Create Date: 08/31/2025 11:28:47 AM
// Design Name: Programmable Input Output (PIO)
// Module Name: pio_tl
// Project Name: abCore16 PIO
// Target Devices: Xilinx FPGA
// Tool Versions: Vivado 2024.2
// Description: PIO Testbench. Tests JMP, WAIT, IN, OUT, PUSH, PULL, and MOV
// 
// Dependencies:
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
//================================================================
// PIO State Machine Comprehensive Testbench
// Tests JMP, WAIT, OUT, PUSH, IN, PULL and MOV instructions
//================================================================

`timescale 1ns / 1ps

module pio_tb;

    // Parameters
    parameter int CLK_PERIOD = 10; // 100MHz clock
    parameter int ADDR_WIDTH = 5;
    parameter int REG_WIDTH = 32;
    parameter int GPIO_WIDTH = 32;
    parameter int INSTR_MEM_DEPTH = 32;
    
    // Clock and Reset
    logic clk;
    logic rst_n;
    
    // DUT Signals
    logic [GPIO_WIDTH-1:0] gpio_in;
    logic [GPIO_WIDTH-1:0] gpio_out;
    logic [GPIO_WIDTH-1:0] gpio_dir;
    
    // Configuration
    logic [4:0] execctrl_jmp_pin;
    logic [4:0] shiftctrl_pull_thresh;
    logic [4:0] pinctrl_in_base;
    logic [4:0] pinctrl_out_base;
    logic [4:0] pinctrl_out_count;
    logic [1:0] state_machine_id;
    
    // Instruction Memory Programming
    logic                  imem_write_en;
    logic [ADDR_WIDTH-1:0] imem_write_addr;
    logic [15:0]           imem_write_data;
    
    // FIFO interfaces
    logic [REG_WIDTH-1:0] tx_fifo_data;
    logic                 tx_fifo_empty;
    logic                 tx_fifo_read;
    logic [REG_WIDTH-1:0] rx_fifo_data;
    logic                 rx_fifo_write;
    logic                 rx_fifo_full;
	
    logic                  fifo_write_req;
    logic [REG_WIDTH-1:0]  fifo_write_data;
    
    // IRQ interface
    logic [7:0] irq_flags_in;
    logic [7:0] irq_flags_clear;
    
    // IN configuration
    logic [4:0] shiftctrl_in_count;
    logic       shiftctrl_in_shiftdir;
    logic       shiftctrl_autopush_en;
    logic [4:0] shiftctrl_autopush_thresh;
    
    // PULL configuration (NEW)
    logic       shiftctrl_autopull_en;
    logic [4:0] shiftctrl_autopull_thresh;							   
    // Debug outputs
    logic [ADDR_WIDTH-1:0] debug_pc;
    logic [REG_WIDTH-1:0]  debug_x_reg;
    logic [REG_WIDTH-1:0]  debug_y_reg;
    logic [REG_WIDTH-1:0]  debug_osr;
    logic [4:0]            debug_osr_count;
    logic                  debug_waiting;
    logic [REG_WIDTH-1:0]  debug_isr;
    logic [4:0]            debug_isr_count;
    
    // TX FIFO simulation
    logic [REG_WIDTH-1:0] fifo_data_queue [$];
    
    logic [REG_WIDTH-1:0] prev_osr;
    int autopull_count = 0;
    int start_time;
    int end_time;
    int cycles_taken;
    
    logic [31:0] expected_inverted;
    logic [31:0] expected_reversed;
    logic [31:0] test_text;
    						   
    //================================================================
    // DUT Instantiation
    //================================================================
    pio_tl #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .REG_WIDTH(REG_WIDTH),
        .GPIO_WIDTH(GPIO_WIDTH),
        .INSTR_MEM_DEPTH(INSTR_MEM_DEPTH)
    ) u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .gpio_in(gpio_in),
        .gpio_out(gpio_out),
        .gpio_dir(gpio_dir),
        .execctrl_jmp_pin(execctrl_jmp_pin),
        .shiftctrl_pull_thresh(shiftctrl_pull_thresh),
        .pinctrl_in_base(pinctrl_in_base),
        .pinctrl_out_base(pinctrl_out_base),
        .pinctrl_out_count(pinctrl_out_count),
        .state_machine_id(state_machine_id),
        .imem_write_en(imem_write_en),
        .imem_write_addr(imem_write_addr),
        .imem_write_data(imem_write_data),
        .tx_fifo_data(tx_fifo_data),
        .tx_fifo_empty(tx_fifo_empty),
        .tx_fifo_read(tx_fifo_read),
        .rx_fifo_data(rx_fifo_data),
        .rx_fifo_write(rx_fifo_write),
        .rx_fifo_full(rx_fifo_full),
        .irq_flags_in(irq_flags_in),
        .irq_flags_clear(irq_flags_clear),
        
        .shiftctrl_in_count(shiftctrl_in_count),
        .shiftctrl_in_shiftdir(shiftctrl_in_shiftdir),
        .shiftctrl_autopush_en(shiftctrl_autopush_en),
        .shiftctrl_autopush_thresh(shiftctrl_autopush_thresh),
        .shiftctrl_autopull_en(shiftctrl_autopull_en),
        .shiftctrl_autopull_thresh(shiftctrl_autopull_thresh),													  
        .debug_pc(debug_pc),
        .debug_x_reg(debug_x_reg),
        .debug_y_reg(debug_y_reg),
        .debug_osr(debug_osr),
        .debug_osr_count(debug_osr_count),
        .debug_isr(debug_isr), 
        .debug_isr_count(debug_isr_count),
        .debug_waiting(debug_waiting)
    );
    
    //================================================================
    // Clock Generation
    //================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    //================================================================
    // Enhanced TX FIFO Simulation
    //================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_data_queue = {};
            tx_fifo_empty <= 1'b1;
            tx_fifo_data <= '0;
            fifo_write_req <= 1'b0; // Auto-clear write request															   
        end else begin
            // Handle FIFO write request
            if (fifo_write_req) begin
                fifo_data_queue.push_back(fifo_write_data);
                fifo_write_req <= 1'b0; // Auto-clear
            end
            // Handle FIFO read
            if (tx_fifo_read && !tx_fifo_empty) begin
                if (fifo_data_queue.size() > 0) begin
                    void'(fifo_data_queue.pop_front());
                end
            end
            
            // Update FIFO status
            if (fifo_data_queue.size() > 0) begin
                tx_fifo_data <= fifo_data_queue[0];
                tx_fifo_empty <= 1'b0;
            end else begin
                tx_fifo_data <= '0;
                tx_fifo_empty <= 1'b1;
            end
        end
    end
    
    //================================================================
    // Helper Tasks
    //================================================================
    
    // Task to load a single instruction
    task load_instruction(input logic [ADDR_WIDTH-1:0] addr, input logic [15:0] instr);
        @(posedge clk);
        imem_write_en = 1'b1;
        imem_write_addr = addr;
        imem_write_data = instr;
        @(posedge clk);
        imem_write_en = 1'b0;
        $display("Loaded instruction 0x%04X at address %0d", instr, addr);
    endtask
    
    
    // Task to load program arrays (workaround for unpacked array parameter issue)
    task load_program_out();
        $display("=== Loading OUT Test Program ===");
        load_instruction(0, 16'b011_00000_000_00000);  // OUT PINS, 8 bits, no delay
        load_instruction(1, 16'b011_00001_001_00001);  // OUT X, default count, delay 1
        load_instruction(2, 16'b011_00000_010_00000);  // OUT Y, default count, no delay
        load_instruction(3, 16'b000_00000_000_00001);  // JMP 0, delay 1 (loop)
        $display("=== Program Loading Complete ===");
    endtask
    
    task load_program_jmp();
        $display("=== Loading JMP Test Program ===");
        load_instruction(0, 16'b011_00000_001_00000);  // OUT X, default count
        load_instruction(1, 16'b000_00010_001_00000);  // JMP 2 if !X
        load_instruction(2, 16'b000_00100_010_00000);  // JMP 4 if X--
        load_instruction(3, 16'b011_00000_001_00000);  // OUT X (should be skipped)
        load_instruction(4, 16'b000_00110_001_00000);  // JMP 6 if !X
        load_instruction(5, 16'b011_00000_001_00000);  // OUT X (should be skipped)
        load_instruction(6, 16'b000_00000_000_00000);  // JMP 0 (loop)
        $display("=== Program Loading Complete ===");
    endtask
    
    task load_program_wait();
        $display("=== Loading WAIT Test Program ===");
        load_instruction(0, 16'b001_00000_1_00_00001); // WAIT 1 GPIO[1], delay 0
        load_instruction(1, 16'b011_00010_000_00000);  // OUT PINS, 8 bits
        load_instruction(2, 16'b001_00010_1_10_00010); // WAIT 1 IRQ[2], delay 2
        load_instruction(3, 16'b011_00100_000_00000);  // OUT PINS, 8 bits
        load_instruction(4, 16'b000_00000_000_00000);  // JMP 0 (loop)
        $display("=== Program Loading Complete ===");
    endtask
    
    task load_program_complex();
        $display("=== Loading Complex Test Program ===");
        load_instruction(0, 16'b011_00000_001_00000);  // OUT X
        load_instruction(1, 16'b000_00010_001_00000);  // JMP 2 if !X
        load_instruction(2, 16'b001_00000_1_00_01010); // WAIT 1 GPIO[10], delay 0
        load_instruction(3, 16'b011_00010_000_00000);  // OUT PINS, 8 bits
        load_instruction(4, 16'b000_00000_010_00001);  // JMP 0 if X--, delay 1
        load_instruction(5, 16'b011_11111_000_00000);  // OUT PINS, 31 bits (end marker)
        $display("=== Program Loading Complete ===");
    endtask
    
    task load_program_push();
        // Load some data into ISR first (manually with force)
        // Then test PUSH instruction
        $display("=== Loading PUSH Test Program ===");
        load_instruction(0, 16'b100_00000_0_0_0_00000); // PUSH, no flags, no delay
        load_instruction(1, 16'b100_00000_0_0_1_00000); // PUSH, block=1, no delay  
        load_instruction(2, 16'b100_00000_0_1_0_00000); // PUSH, iffull=1, no delay
        load_instruction(3, 16'b000_00000_000_00000); // JMP 0 (loop)
    endtask
    
    task load_program_in();
        $display("=== Loading IN Test Program ===");
        load_instruction(0, 16'h4000); // IN PINS, default count, no delay
        load_instruction(1, 16'h4020); // IN X, default count, no delay
        load_instruction(2, 16'h4040); // IN Y, default count, no delay
        load_instruction(3, 16'h4060); // IN NULL, default count, no delay
        load_instruction(4, 16'h0000); // JMP 0 (loop)
        $display("=== Program Loading Complete ===");
    endtask
    
    // PULL instruction test programs
    task load_program_pull();
        $display("=== Loading PULL Test Program ===");
        load_instruction(0, 16'b100_00000_1_0_0_00000); // PULL, no flags, no delay
        load_instruction(1, 16'b100_00000_1_0_1_00000); // PULL, block=1, no delay  
        load_instruction(2, 16'b100_00000_1_1_0_00000); // PULL, ifempty=1, no delay
        load_instruction(3, 16'b100_00010_1_0_0_00000); // PULL, delay=2, no flags
        load_instruction(4, 16'b000_00000_000_00000);   // JMP 0 (loop back)
        $display("=== PULL Program Loading Complete ===");
    endtask

    task load_program_autopull();
        $display("=== Loading Autopull Test Program ===");
        load_instruction(0, 16'b011_00000_000_01000); // OUT PINS, 8 bits - will trigger autopull
        load_instruction(1, 16'b011_00000_000_01000); // OUT PINS, 8 bits - will trigger autopull again  
        load_instruction(2, 16'b011_00000_000_01000); // OUT PINS, 8 bits - will trigger autopull again
        load_instruction(3, 16'b000_00000_000_00000); // JMP 0 (loop)
        $display("=== Autopull Program Loading Complete ===");
    endtask

    task load_program_pull_blocking();
        $display("=== Loading PULL Blocking Test Program ===");
        load_instruction(0, 16'b100_00000_1_0_0_00000); // PULL, ifempty=0 (blocking)
        load_instruction(1, 16'b011_00000_000_01000);   // OUT PINS, 8 bits
        load_instruction(2, 16'b100_00000_1_1_0_00000); // PULL, ifempty=1 (non-blocking) 
        load_instruction(3, 16'b011_00000_000_01000);   // OUT PINS, 8 bits
        load_instruction(4, 16'b000_00000_000_00000);   // JMP 0 (loop)
        $display("=== PULL Blocking Program Loading Complete ===");
    endtask
    
    // I corrected instruction definitions
    task load_program_mov_basic();
        $display("=== Loading Basic MOV Test Program ===");
        // [15:13]=101 [12:8]=00000 [7:5]=001 [4:3]=00 [2:0]=010
        load_instruction(0, 16'b101_00000_001_00_010);  // MOV X, Y: Copy Y register to X register
        load_instruction(1, 16'b101_00000_010_00_011);  // MOV Y, NULL: Load zeros into Y register
        load_instruction(2, 16'b000_00000_0_00_00000);   // JMP 0: Loop back
        $display("=== Basic MOV Program Loading Complete ===");
    endtask
    
    // I corrected instruction definitions
    task load_program_mov_comprehensive();
        $display("=== Loading Comprehensive MOV Test Program ===");
        // [15:13]=101 [12:8]=00000 [7:5]=001 [4:3]=00 [2:0]=010
        load_instruction(0, 16'b101_00000_001_00_010);   // Test 1: MOV X, Y (copy Y to X)
        load_instruction(1, 16'b101_00000_010_00_111);   // Test 2: MOV Y, OSR (copy OSR to Y)
        load_instruction(2, 16'b101_00000_000_01_001);   // Test 3: MOV PINS, ~X (invert X to PINS)
        load_instruction(3, 16'b101_00000_001_00_101);   // Test 4: MOV X, STATUS (copy STATUS to X)
        load_instruction(4, 16'b101_00000_010_10_110);   // Test 5: MOV Y, REVERSE(ISR) (bit-reverse ISR to Y)
        load_instruction(5, 16'b101_00000_001_00_011);   // Test 6: MOV X, NULL (clear X register)
        load_instruction(6, 16'b000_00000_0_00_00000);   // JMP 0: Loop back to start
         $display("=== Comprehensive MOV Program Loading Complete ===");
    endtask
    
task load_program_mov_corrected();
    $display("=== Loading CORRECTED MOV Test Program ===");
    // MOV X, Y: [15:13]=101 [12:8]=00000 [7:5]=001 [4:3]=00 [2:0]=010
    // Destination=X(001), Operation=NONE(00), Source=Y(010)
    load_instruction(0, 16'b101_00000_001_00_010);         // MOV X, Y
    // MOV Y, OSR: [15:13]=101 [12:8]=00000 [7:5]=010 [4:3]=00 [2:0]=111  
    // Destination=Y(010), Operation=NONE(00), Source=OSR(111)
    load_instruction(1, 16'b101_00000_010_00_111);         // MOV Y, OSR
    // MOV PINS, ~X: [15:13]=101 [12:8]=00000 [7:5]=000 [4:3]=01 [2:0]=001
    // Destination=PINS(000), Operation=INVERT(01), Source=X(001)
    load_instruction(2, 16'b101_00000_000_01_001);         // MOV PINS, ~X
    // JMP 0: Loop back
    load_instruction(3, 16'b000_00000_0_00_00000);
    $display("=== CORRECTED MOV Program Loading Complete ===");
endtask
    
    // Task to add data to TX FIFO
    task fifo_write(input logic [REG_WIDTH-1:0] data);
        fifo_write_req = 1'b1;
        fifo_write_data = data;
        @(posedge clk); // Wait for the always_ff block to process
        // fifo_write_req will be auto-cleared by always_ff block
        $display("Added 0x%08X to TX FIFO", data);
    endtask
    
    // Task to wait for N clock cycles
    task wait_cycles(input int cycles);
        repeat(cycles) @(posedge clk);
    endtask
    
    // Task to wait until PC reaches specific address
    task wait_for_pc(input logic [ADDR_WIDTH-1:0] target_pc, input int timeout_cycles = 100);
        int cycle_count = 0;
        while (debug_pc != target_pc && cycle_count < timeout_cycles) begin
            @(posedge clk);
            cycle_count++;
        end
        if (cycle_count >= timeout_cycles) begin
            $display("TIMEOUT: PC never reached %0d", target_pc);
        end else begin
            $display("PC reached %0d after %0d cycles", target_pc, cycle_count);
        end
    endtask
    

    // PULL test helper functions
    task verify_pull_result(
        input logic [REG_WIDTH-1:0] expected_osr,
        input string test_name
    );
        if (debug_osr == expected_osr) begin
            $display("✓ %s: OSR correctly loaded with 0x%08X", test_name, debug_osr);
        end else begin
            $display("✗ %s: Expected OSR=0x%08X, got 0x%08X", test_name, expected_osr, debug_osr);
        end
    endtask

    task verify_pull_blocked(input string test_name);
        logic [ADDR_WIDTH-1:0] initial_pc = debug_pc;
        wait_cycles(5);
        if (debug_pc == initial_pc) begin
            $display("✓ %s: PULL correctly blocked (PC=%0d)", test_name, debug_pc);
        end else begin
            $display("✗ %s: PULL should be blocked, but PC advanced from %0d to %0d", 
                     test_name, initial_pc, debug_pc);
        end
    endtask

    task wait_for_fifo_read(input int timeout_cycles = 20);
        int cycle_count = 0;
        while (!tx_fifo_read && cycle_count < timeout_cycles) begin
            @(posedge clk);
            cycle_count++;
        end
        if (tx_fifo_read) begin
            $display("✓ TX FIFO read detected after %0d cycles", cycle_count);
        end else begin
            $display("✗ TX FIFO read timeout after %0d cycles", timeout_cycles);
        end
    endtask							  
    
    //================================================================
    // Main Test Sequence
    //================================================================
    initial begin
        // Initialize all signals
        rst_n = 1'b0;
        gpio_in = '0;
        execctrl_jmp_pin = 5'd10;
        shiftctrl_pull_thresh = 5'd8;
        pinctrl_in_base = 5'd0;
        pinctrl_out_base = 5'd0;
        pinctrl_out_count = 5'd8;
        state_machine_id = 2'b00;
	    // OUT configuration
//        shiftctrl_out_count = 5'd8;
//        shiftctrl_out_shiftdir = 1'b1; // Right shift
//        shiftctrl_autopull_en = 1'b1;
//        shiftctrl_autopull_thresh = 5'd24;
        
        // IN configuration (Add these)
        shiftctrl_in_count = 5'd8;      // Default 8 bits for IN
        shiftctrl_in_shiftdir = 1'b0;   // Left shift (typical for input)
        shiftctrl_autopush_en = 1'b0;   // Disable auto-push for testing
        shiftctrl_autopush_thresh = 5'd24;						
        
        // PULL configuration
        shiftctrl_autopull_en = 1'b0;      // Disable auto-pull for initial testing  
        shiftctrl_autopull_thresh = 5'd24; // Threshold for autopull trigger		
        imem_write_en = 1'b0;
        imem_write_addr = '0;
        imem_write_data = '0;
        irq_flags_in = '0;
        rx_fifo_full = 1'b0;
        
        // Initial reset and stabilization
        $display("=== PIO Testbench Starting ===");
        wait_cycles(5);
        
        // Test 1: Basic OUT instruction
        $display("\n=== TEST 1: OUT Instruction ===");
        // Keep reset active while loading program
        rst_n = 1'b0;
        load_program_out();
        wait_cycles(2); // Let signals settle
        
        // Release reset to start execution
        rst_n = 1'b1;
        
        // Preload OSR with test data (after reset release)
        wait_cycles(1);
        force u_dut.u_datapath.osr_register = 32'hAA55_F0F0;
        force u_dut.u_datapath.osr_shift_counter = 5'd32;
        
        // Add FIFO data for auto-pull testing
        fifo_write(32'h1234_5678);
        fifo_write(32'hDEAD_BEEF);
        
        $display("Starting OUT instruction test...");
        wait_cycles(20);
        
        // Verify results
        if (gpio_out[7:0] == 8'hF0) begin
            $display("✓ OUT PINS: Correctly output 0x%02X", gpio_out[7:0]);
        end else begin
            $display("✗ OUT PINS: Expected 0xF0, got 0x%02X", gpio_out[7:0]);
        end
        
        release u_dut.u_datapath.osr_register;
        release u_dut.u_datapath.osr_shift_counter;
        
        // Test 2: JMP instruction conditions
        $display("\n=== TEST 2: JMP Instructions ===");
        // Reset and load new program
        rst_n = 1'b0;
        wait_cycles(2);
        load_program_jmp();
        wait_cycles(2);
        
        // Release reset
        rst_n = 1'b1;
        wait_cycles(1);
        
        // Preload OSR and X register for testing
        force u_dut.u_datapath.osr_register = 32'h0000_0003;
        force u_dut.u_datapath.osr_shift_counter = 5'd32;
        force u_dut.u_datapath.x_register = 32'h0000_0000; // Start with X=0
        
        $display("Testing JMP conditions...");
        
        // Let it run and observe PC movement
        wait_cycles(5);
        if (debug_pc == 5'd1) begin
            $display("✓ JMP !X: Correctly did NOT jump (X was 0)");
        end else begin
            $display("✗ JMP !X: Unexpected PC = %0d", debug_pc);
        end
        
        // Force X to non-zero for X-- test
        force u_dut.u_datapath.x_register = 32'h0000_0002;
        wait_cycles(3);
        
        if (debug_pc == 5'd4) begin
            $display("✓ JMP X--: Correctly jumped (X was non-zero)");
        end else begin
            $display("✗ JMP X--: Expected PC=4, got %0d", debug_pc);
        end
        
        release u_dut.u_datapath.osr_register;
        release u_dut.u_datapath.osr_shift_counter;
        release u_dut.u_datapath.x_register;
        
        // Test 3: WAIT instruction
        $display("\n=== TEST 3: WAIT Instructions ===");
        // Reset and load new program
        rst_n = 1'b0;
        wait_cycles(2);
        load_program_wait();
        wait_cycles(2);
        
        // Release reset
        rst_n = 1'b1;
        wait_cycles(1);
        
        // Preload OSR for OUT instructions
        force u_dut.u_datapath.osr_register = 32'hA5A5_A5A5;
        force u_dut.u_datapath.osr_shift_counter = 5'd32;
        
        $display("Testing WAIT GPIO...");
        gpio_in[1] = 1'b0; // Initially low
        wait_cycles(5);
        
        if (debug_waiting) begin
            $display("✓ WAIT GPIO: Correctly waiting for GPIO[1] = 1");
        end else begin
            $display("✗ WAIT GPIO: Should be waiting but debug_waiting = %b", debug_waiting);
        end
        
        // Release wait condition
        gpio_in[1] = 1'b1;
        wait_cycles(3);
        
        if (!debug_waiting && debug_pc == 5'd1) begin
            $display("✓ WAIT GPIO: Correctly released and advanced PC");
        end else begin
            $display("✗ WAIT GPIO: Wait release failed, PC=%0d, waiting=%b", debug_pc, debug_waiting);
        end
        
        // Test WAIT IRQ
        $display("Testing WAIT IRQ...");
        wait_for_pc(5'd2, 10);
        
        irq_flags_in[2] = 1'b0; // Initially clear
        wait_cycles(3);
        
        if (debug_waiting) begin
            $display("✓ WAIT IRQ: Correctly waiting for IRQ[2] = 1");
        end else begin
            $display("✗ WAIT IRQ: Should be waiting");
        end
        
        // Set IRQ flag
        irq_flags_in[2] = 1'b1;
        wait_cycles(3);
        
        if (irq_flags_clear[2]) begin
            $display("✓ WAIT IRQ: Correctly cleared IRQ flag");
        end else begin
            $display("✗ WAIT IRQ: Failed to clear IRQ flag");
        end
        
        release u_dut.u_datapath.osr_register;
        release u_dut.u_datapath.osr_shift_counter;
        
        // Test 4: Complex integration test
        $display("\n=== TEST 4: Complex Integration ===");
        // Reset and load new program
        rst_n = 1'b0;
        wait_cycles(2);
        load_program_complex();
        wait_cycles(2);
        
        // Release reset
        rst_n = 1'b1;
        wait_cycles(1);
        
        // Setup for complex test
        force u_dut.u_datapath.osr_register = 32'h0000_0005; // X will get value 5
        force u_dut.u_datapath.osr_shift_counter = 5'd32;
        gpio_in[10] = 1'b0; // WAIT will wait for this
        
        $display("Running complex test...");
        wait_cycles(10);
        
        // Should be waiting at instruction 2
        if (debug_waiting && debug_pc == 5'd2) begin
            $display("✓ Complex: Reached WAIT instruction correctly");
        end else begin
            $display("✗ Complex: Expected waiting at PC=2, got PC=%0d, waiting=%b", debug_pc, debug_waiting);
        end
        
        // Release wait and observe loop behavior
        gpio_in[10] = 1'b1;
        wait_cycles(5);
        
        $display("Final state: PC=%0d, X=%0d, Y=%0d, OSR=0x%08X", 
                debug_pc, debug_x_reg, debug_y_reg, debug_osr);
        
        release u_dut.u_datapath.osr_register;
        release u_dut.u_datapath.osr_shift_counter;
        
        
        // Test 5: PUSH instruction
        $display("\n=== TEST 5: PUSH Instructions ===");
        // Reset and load new program
        rst_n = 1'b0;
        wait_cycles(2);
        load_program_push();
        wait_cycles(2);
        
        // Release reset
        rst_n = 1'b1;
        wait_cycles(1);
        
        // Manually load ISR with test data
        force u_dut.u_datapath.isr_register = 32'hDEAD_BEEF;
        force u_dut.u_datapath.isr_shift_counter = 5'd16;
        
        // Execute PUSH and verify RX FIFO gets the data
        wait_cycles(5);
        
        // Check results
        if (rx_fifo_data == 32'hDEAD_BEEF && rx_fifo_write) begin
            $display("✓ PUSH: Successfully wrote ISR to RX FIFO");
        end 

        // Release wait and observe loop behavior
        gpio_in[10] = 1'b1;
        wait_cycles(5);
        
        $display("Final PUSH content: PC=%0d, X=%0d, Y=%0d, OSR=0x%08X", 
                debug_pc, debug_x_reg, debug_y_reg, debug_osr);
        
        release u_dut.u_datapath.isr_register;
        release u_dut.u_datapath.isr_shift_counter;
        
        // Test 6: IN Instructions
        $display("\n=== TEST 6: IN Instructions ===");
        rst_n = 1'b0;
        load_program_in();
        rst_n = 1'b1;
        wait_cycles(1);

        // Set up GPIO input data for testing
        gpio_in = 32'hABCD_1234;

        // Set up X and Y registers with test data
        force u_dut.u_datapath.x_register = 32'hDEAD_BEEF;
        force u_dut.u_datapath.y_register = 32'hCAFE_BABE;

        $display("Testing IN instructions...");
        wait_cycles(20);

        // Verify ISR contains expected data after IN operations
        $display("Final ISR content: 0x%08X, count: %0d", debug_isr, debug_isr_count);

        release u_dut.u_datapath.x_register;
        release u_dut.u_datapath.y_register;
        
        // Test 7: PULL Instructions - Basic Functionality
        $display("\n=== TEST 7: PULL Instructions - Basic Functionality ===");
        rst_n = 1'b0;
        load_program_pull();
        rst_n = 1'b1;
        wait_cycles(1);

        // Pre-load TX FIFO with test data
        fifo_write(32'h1234_5678);
        fifo_write(32'hABCD_EF00);
        fifo_write(32'hDEAD_BEEF);

        // Set up X register for ifempty test
        force u_dut.u_datapath.x_register = 32'hFEED_FACE;

		$display("Testing basic PULL operations...");
		
        // Test normal PULL (instruction 0)
        wait_for_pc(5'd1, 20);
        verify_pull_result(32'h1234_5678, "Basic PULL");																			  
        // Continue execution to test other PULL variants
        wait_for_pc(5'd0, 30); // Wait for loop to complete							
        $display("Final OSR after PULL tests: 0x%08X, OSR count: %0d", debug_osr, debug_osr_count);
        release u_dut.u_datapath.x_register;					   
        
        // Test 8: PULL Instructions - Blocking Behavior  
        $display("\n=== TEST 8: PULL Instructions - Blocking Behavior ===");
        rst_n = 1'b0;
        load_program_pull_blocking();
        rst_n = 1'b1;
        wait_cycles(1);										  

        // Start with empty TX FIFO to test blocking
//        fifo_data_queue = {};

        // Set up X register for ifempty test
        force u_dut.u_datapath.x_register = 32'hBAD_C0DE;

        $display("Testing PULL blocking behavior with empty FIFO...");

        // Should block on first PULL instruction (ifempty=0)
        verify_pull_blocked("PULL with ifempty=0");

        // Add data to FIFO and verify PULL completes
        $display("Adding data to TX FIFO to unblock PULL...");
        fifo_write(32'h1111_2222);
        wait_cycles(10);

        if (debug_pc >= 5'd1 && debug_osr == 32'h1111_2222) begin
            $display("✓ PULL Unblocking: Successfully resumed and loaded OSR");
        end else begin
            $display("✗ PULL Unblocking: Expected PC>=1 and OSR=0x1111_2222, got PC=%0d, OSR=0x%08X", 														  
                     debug_pc, debug_osr);
        end

        // Test ifempty=1 behavior - wait for PC to reach instruction 2
        wait_cycles(20);

        if (debug_osr == 32'hBAD_C0DE) begin
            $display("✓ PULL ifempty=1: Successfully loaded X register when FIFO empty");
        end else begin
            $display("✗ PULL ifempty=1: Expected OSR=0xBAD_C0DE (X reg), got 0x%08X", debug_osr);
        end

        release u_dut.u_datapath.x_register;
		
		// Test 9: Autopull Functionality
				
        // Test MOV Infrastructure (Phase 1 Verification)
        $display("\n=== TEST: MOV Infrastructure Verification ===");
        rst_n = 1'b0;
        load_program_mov_basic();
        rst_n = 1'b1;
        wait_cycles(1);

        // Setup test data
//        force u_dut.u_datapath.x_register = 32'h0000_0000;
        force u_dut.u_datapath.y_register = 32'h5555_BAE2;

        $display("Testing MOV instruction decode and control signals...");

        // Let it run for a few cycles to verify no crashes
        wait_cycles(10);

        if (debug_pc <= 5'd2) begin
            $display("✓ MOV Infrastructure: PC advancing correctly");
            $display("  PC = %0d", debug_pc);
            $display("  X = 0x%08X", debug_x_reg);
            $display("  Y = 0x%08X", debug_y_reg);
        end else begin
            $display("✗ MOV Infrastructure: Unexpected PC behavior");
        end

        release u_dut.u_datapath.x_register;
        release u_dut.u_datapath.y_register;

// ****************************************************
// ****************************************************
// Test MOV Core Functionality (Phase 2 Verification)
$display("\n=== TEST: MOV Core Functionality ===");
rst_n = 1'b0;
load_program_mov_comprehensive();
rst_n = 1'b1;
wait_cycles(1);

// Setup initial test data
force u_dut.u_datapath.x_register = 32'h1111_1111;
force u_dut.u_datapath.y_register = 32'hAAAA_5555;
force u_dut.u_datapath.osr_register = 32'hDEAD_BEEF;
force u_dut.u_datapath.isr_register = 32'hCAFE_BABE;
force u_dut.u_datapath.isr_shift_counter = 5'd12;
force u_dut.u_datapath.osr_shift_counter = 5'd8;

$display("Initial values:");
$display("  X = 0x%08X", debug_x_reg);
$display("  Y = 0x%08X", debug_y_reg);
$display("  OSR = 0x%08X", debug_osr);
$display("  ISR = 0x%08X", debug_isr);

// Test 1: MOV X, Y
wait_for_pc(5'd1, 10);
if (debug_x_reg == 32'hAAAA_5555) begin
    $display("✓ MOV X, Y: Successfully copied Y to X (0x%08X)", debug_x_reg);
end else begin
    $display("✗ MOV X, Y: Expected 0xAAAA_5555, got 0x%08X", debug_x_reg);
end

// Test 2: MOV Y, OSR
wait_for_pc(5'd2, 10);
if (debug_y_reg == 32'hDEAD_BEEF) begin
    $display("✓ MOV Y, OSR: Successfully copied OSR to Y (0x%08X)", debug_y_reg);
end else begin
    $display("✗ MOV Y, OSR: Expected 0xDEAD_BEEF, got 0x%08X", debug_y_reg);
end

// Test 3: MOV PINS, ~X (invert X to PINS)
wait_for_pc(5'd3, 10);
expected_inverted = ~debug_x_reg;
if (gpio_out[7:0] == expected_inverted[7:0]) begin
    $display("✓ MOV PINS, ~X: Successfully inverted X to PINS (0x%02X)", gpio_out[7:0]);
end else begin
    $display("✗ MOV PINS, ~X: Expected 0x%02X, got 0x%02X", 
             expected_inverted[7:0], gpio_out[7:0]);
end

// Test 4: MOV X, STATUS
wait_for_pc(5'd4, 10);
// Check if X now contains STATUS register value
$display("  MOV X, STATUS: X = 0x%08X (STATUS register)", debug_x_reg);
if (debug_x_reg[4:0] == 5'd12) begin  // ISR shift counter should be in bits [4:0]
    $display("✓ MOV X, STATUS: STATUS register correctly loaded");
end else begin
    $display("✗ MOV X, STATUS: STATUS register format may be incorrect");
end

// Test 5: MOV Y, REVERSE(ISR) - Check bit reversal
wait_for_pc(5'd5, 10);
test_text = 32'hCAFE_BABE;
for (int i = 0; i < 32; i++) begin
//    expected_reversed[i] = 32'hCAFE_BABE[31-i];
    expected_reversed[i] = test_text[31-i];
end
if (debug_y_reg == expected_reversed) begin
    $display("✓ MOV Y, REVERSE(ISR): Bit reversal successful");
end else begin
    $display("  MOV Y, REVERSE(ISR): Y = 0x%08X", debug_y_reg);
    $display("  Expected reversed = 0x%08X", expected_reversed);
end

// Test 6: MOV X, NULL
wait_for_pc(5'd6, 10);
if (debug_x_reg == 32'h0000_0000) begin
    $display("✓ MOV X, NULL: Successfully cleared X register");
end else begin
    $display("✗ MOV X, NULL: Expected 0x00000000, got 0x%08X", debug_x_reg);
end

$display("MOV Phase 2 testing complete.");

release u_dut.u_datapath.x_register;
release u_dut.u_datapath.y_register;
release u_dut.u_datapath.osr_register;
release u_dut.u_datapath.isr_register;
release u_dut.u_datapath.isr_shift_counter;
release u_dut.u_datapath.osr_shift_counter;
        
// ****************************************************
// ****************************************************

        
        // Test complete
        $display("\n=== All Tests Complete ===");
        $finish;
    end
    
    //================================================================
    // Monitoring and Debugging
    //================================================================
    
    // Monitor main signals
initial begin
    $monitor("Datapath Debug: time=%0t mov_en=%b src_data=%08X proc_data=%08X write_data=%08X X=%08X Y=%08X", 
             $time, 
             u_dut.u_datapath.mov_write_en,
             u_dut.u_datapath.mov_src_data,
             u_dut.u_datapath.mov_processed_data, 
             u_dut.u_datapath.mov_write_data,
             u_dut.u_datapath.x_register,
             u_dut.u_datapath.y_register);
end
    
    
//    initial begin
//        $monitor("MOV Debug: time=%0t PC=%0d mov_en=%b dest=%d(3b) src=%d(3b) op=%d(2b) X=%08X Y=%08X", 
//             $time, debug_pc, u_dut.cu_mov_write_en, 
//             u_dut.cu_mov_dest_sel, u_dut.cu_mov_src_sel, u_dut.cu_mov_op_sel,
//             debug_x_reg, debug_y_reg);
//    end
    
    
//    initial begin
//        $monitor("Time=%0t PC=%0d X=%0d Y=%0d OSR=0x%08X[%0d] ISR=0x%08X[%0d] GPIO_OUT=0x%02X WAIT=%b", 
//                 $time, debug_pc, debug_x_reg, debug_y_reg, debug_osr, debug_osr_count, debug_isr, debug_isr_count,
//                 gpio_out[7:0], debug_waiting);
//    end
    
//    initial begin
//        $monitor("Time=%0t PC=%0d X=%0d Y=%0d OSR=0x%08X[%0d] GPIO_OUT=0x%02X WAIT=%b", 
//                 $time, debug_pc, debug_x_reg, debug_y_reg, debug_osr, debug_osr_count, 
//                 gpio_out[7:0], debug_waiting);
//    end
    
    // Instruction execution tracker
    always @(posedge clk) begin
        if (rst_n && !debug_waiting && u_dut.cu_pc_write_en) begin
            // Only report when PC is actually advancing
            case (u_dut.u_control_unit.opcode) // Use the decoded opcode from control unit
                3'b000: $display("@%0t: Executing JMP at PC=%0d", $time, debug_pc);
                3'b001: $display("@%0t: Executing WAIT at PC=%0d", $time, debug_pc);
                3'b010: $display("@%0t: Executing IN at PC=%0d", $time, debug_pc);
                3'b111: $display("@%0t: Executing OUT at PC=%0d", $time, debug_pc);
                default: $display("@%0t: Executing instruction 0x%04X at PC=%0d", 
                                $time, u_dut.instruction_data, debug_pc);
            endcase
        end
    end
    
    // Auto-pull monitor
    always @(posedge clk) begin
        if (tx_fifo_read) begin
            $display("@%0t: AUTO-PULL: Reading 0x%08X from TX FIFO", $time, tx_fifo_data);
        end
    end
    
    // GPIO change monitor
    always @(gpio_out) begin
        $display("@%0t: GPIO_OUT changed to 0x%08X", $time, gpio_out);
    end
    
    // IRQ clear monitor
    always @(posedge clk) begin
        if (|irq_flags_clear) begin
            $display("@%0t: IRQ flags cleared: 0x%02X", $time, irq_flags_clear);
        end
    end
    
    //================================================================
    // Assertions for Verification
    //================================================================
    
    // PC should never exceed instruction memory bounds
    property pc_bounds_check;
        @(posedge clk) disable iff (!rst_n)
        debug_pc < INSTR_MEM_DEPTH;
    endproperty
    assert property (pc_bounds_check) else $error("PC out of bounds: %0d", debug_pc);
    
    // When waiting, PC should not advance
    property wait_pc_stable;
        @(posedge clk) disable iff (!rst_n)
        debug_waiting |-> ##1 (debug_pc == $past(debug_pc));
    endproperty
    assert property (wait_pc_stable) else $error("PC advanced while waiting");
    
    // OSR count should never exceed 32
    property osr_count_bounds;
        @(posedge clk) disable iff (!rst_n)
        debug_osr_count <= 5'd32;
    endproperty
    assert property (osr_count_bounds) else $error("OSR count out of bounds: %0d", debug_osr_count);
    
    //================================================================
    // Waveform Dumping
    //================================================================
    initial begin
        $dumpfile("pio_tb.vcd");
        $dumpvars(0, pio_tb);
    end

endmodule