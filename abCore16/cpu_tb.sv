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

module cpu_tb;

    // Testbench Parameters
    localparam CLK_PERIOD     = 10;  // 100 MHz clock
    localparam MAX_SIM_CYCLES = 1000;
    
    // Important Note: Must update test result for each test
    localparam TEST_RESULT    = 30;

    // DUT External Connections
    logic clk;
    logic rst_n;
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
        .clk(clk),
        .rst_n(rst_n),
        .gpio_in_i(gpio_in_tb_i),
        .gpio_out_o(gpio_out_tb_o),
        .gpio_out_we_o(gpio_out_we_tb_o),
        // Connect to the new halt signal from the DUT
        .halted_o(halted_from_dut) 
    );

    // Clock Generator
    initial begin
        clk = 0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // Main Test Sequence
    initial begin
        $display("SIM START: System-level Testbench with Integrated BRAM");
        $display("TB: Assuming DUT instruction memory is pre-loaded via COE file.");

        // 1. Reset the system
        rst_n = 1'b0;
        gpio_in_tb_i = `DATA_WIDTH'h0000;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        $display("TB: Reset de-asserted at time %0t.", $time);

        // 2. Fork off a process to monitor the GPIO output
        fork
            monitor_gpio_out();
        join_none

        // 3. Run simulation until HALT is detected or a timeout occurs
        while (cycle_count < MAX_SIM_CYCLES && !halted_from_dut) begin
            @(posedge clk);
            cycle_count++;
        end

        // 4. Check results and report pass/fail
        @(posedge clk); // Allow one final cycle for signals to settle

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
            wait (gpio_out_we_tb_o === 1'b1); // Wait for the first write enable
        
            // After the write enable is seen, wait for the next clock edge to ensure
            // the output data is stable before capturing it.
            @(posedge clk);
        
            captured_gpio_out = gpio_out_tb_o;
            $display("TB @ %0t [Cycle %0d]: GPIO write detected! Captured Value = %0d (0x%h)",
                 $time, cycle_count, captured_gpio_out, captured_gpio_out);
        
            wait (gpio_out_we_tb_o === 1'b0); // Wait for signal to deassert
            repeat (3) @(posedge clk);
        
        end // end for loop
    endtask

endmodule
