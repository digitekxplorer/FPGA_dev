`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:      ab Systems
// Engineer:     Al Baeza
// 
// Create Date:  [Current Date]
// Design Name:  abCore16 System Testbench
// Module Name:  cpu_tb
// Project Name: abCore16
// Target Devices: Simulation
// Tool Versions: Vivado
// Description: 
// Testbench for the complete abCore16 CPU subsystem (cpu_tl) which includes
// integrated BRAMs for instruction and data memory. This testbench interacts
// with the DUT as a black box, stimulating external inputs and verifying
// external outputs.
//
// ** IMPORTANT **
// 1. Program loading is NOT handled here. It is assumed the BRAM IP core
//    inside the DUT is initialized using a .coe file at simulation start.
// 2. A .hex file for fast Verilog simulation loading (program only).
// 3. This testbench requires the DUT to have a 'halted_o' output port.
//
//////////////////////////////////////////////////////////////////////////////////


`include "defines.svh" 

//`define SIMSPEEDUP

module cpu_tb;

    // Testbench Parameters
    localparam CLK_PERIOD     = 83.3;  // 12 MHz clock
    localparam MAX_SIM_CYCLES = 2500;
    
    // Important Note: Must update test result for each test
    localparam TEST_RESULT    = 30;

    // DUT External Connections
    logic clk_12MHz;
//    logic clk;
    logic rst_in;
    logic [`DATA_WIDTH-1:0] gpio_in_tb_i;
    logic [`DATA_WIDTH-1:0] gpio_out_tb_o;
    logic                   gpio_out_we_tb_o;
    logic                   halted_from_dut; // Recommended new output from DUT

    // Testbench Internal State
    int   cycle_count = 0;
    logic test_passed = 1'b0;
    logic [`DATA_WIDTH-1:0] captured_gpio_out = 'x; // Use 'x' to detect if it was ever written

    // Instantiate the complete CPU subsystem (Device Under Test)
    cpu_tl dut (
        .clk_12MHz(clk_12MHz),
        .rst_in(rst_in),
//        .gpio_in_i(gpio_in_tb_i),   // TODO: add later if needed, for now reduce pic count
        .gpio_out_o(gpio_out_tb_o),
        .gpio_out_we_o(gpio_out_we_tb_o),
        // Connect to the new halt signal from the DUT
        .halted_o(halted_from_dut) 
    );

    // Clock Generator
    initial begin
        clk_12MHz = 0;
        forever #(CLK_PERIOD / 2) clk_12MHz = ~clk_12MHz;
    end
    
    // For simulation only, force the MCM pin high to speedup sim.
`ifdef SIMSPEEDUP
    initial begin
        // wait for clock glitches at start of sim
        repeat(3) @(posedge clk_12MHz);  // skip glitches at start
        // wait for an output from the MCM
        @(posedge dut.abCore16_clk.clk_out1);

        // Force the locked signal high after a small delay.
        // NOTE: This is a hack for simulation only!
        #100; // Wait a bit
        @(posedge clk_12MHz);
        force dut.abCore16_clk.locked = 1'b1;
    end
`endif

    // Main Test Sequence
    initial begin
        $display("SIM START: System-level Testbench with Integrated BRAM");
        $display("TB: Assuming DUT instruction memory is pre-loaded via COE file.");

        // 1. Reset the system
        rst_in = 1'b1;
        gpio_in_tb_i = `DATA_WIDTH'h0000;
        #1000; // simulate pushbutton
        
//        repeat(5) @(posedge dut.clk);
        repeat(2) @(posedge clk_12MHz);
        rst_in = 1'b0;
        $display("TB: Reset de-asserted at time %0t.", $time);

        // 2. Fork off a process to monitor the GPIO output
        fork
            monitor_gpio_out();
        join_none

        // 3. Run simulation until HALT is detected or a timeout occurs
        while (cycle_count < MAX_SIM_CYCLES && !halted_from_dut) begin
            @(posedge dut.clk);
            cycle_count++;
        end

        // 4. Check results and report pass/fail
        @(posedge dut.clk); // Allow one final cycle for signals to settle

        if (halted_from_dut) begin
            $display("TB: DUT asserted HALT signal after %0d cycles.", cycle_count);
            
            // Check if the captured GPIO value is correct for the test program
            // 
            // The test program loaded via COE
            // NOTE: update TEST_RESULT for each test program
            if (captured_gpio_out == TEST_RESULT) begin
                $display("TB TEST PASSED: GPIO output matches expected value %0d.", TEST_RESULT);
                test_passed = 1'b1;
            end else if (captured_gpio_out === 'x) begin
                $display("TB TEST FAILED: The OUT instruction never executed. No value was written to GPIO.");
                test_passed = 1'b0;
            end else begin
                $display("TB TEST FAILED: GPIO output was 0x%h, expected %0d.", captured_gpio_out, TEST_RESULT);
                test_passed = 1'b0;
            end
        end else begin
            $display("TB TEST FAILED: Max sim cycles (%0d) reached without DUT asserting HALT.", MAX_SIM_CYCLES);
            test_passed = 1'b0;
        end

        $display("SIM END");
        $finish;
    end

    // --- Testbench Tasks ---

    // This task monitors the GPIO port and captures the first value written.
    task monitor_gpio_out;
//        for ( int i= 0; i < 3; i++ ) begin
        while ( !halted_from_dut ) begin
        
            // This is a robust, non-blocking way to wait for the event.
            // It triggers exactly on the clock edge where the write enable is high.
            @(posedge dut.clk iff gpio_out_we_tb_o);
        
            //wait (gpio_out_we_tb_o === 1'b1); // Wait for the first write enable
        
            // After the write enable is seen, wait for the next clock edge to ensure
            // the output data is stable before capturing it.
            //@(posedge dut.clk);
        
            captured_gpio_out = gpio_out_tb_o;
            $display("TB @ %0t [Cycle %0d]: GPIO write detected! Captured Value = %0d (0x%h)",
                 $time, cycle_count, captured_gpio_out, captured_gpio_out);
        
            wait (gpio_out_we_tb_o === 1'b0); // Wait for signal to deassert
            repeat (3) @(posedge dut.clk);
        
        end // end for loop
    endtask

endmodule
