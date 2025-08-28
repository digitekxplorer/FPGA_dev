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
// Testbench for the complete abCore16 CPU subsystem (cpu_tl).
//
// Revision:
// Revision 1.1 - Updated to use uart_if for the testbench's own UART instance.
//
//////////////////////////////////////////////////////////////////////////////////

`include "defines.svh" 
`include "abcore_interfaces.sv" 

module cpu_tb;

    // Testbench Parameters
    localparam CLK12_PERIOD     = 83.3;  // 12 MHz clock
    localparam MAX_SIM_CYCLES = 122000;
    localparam TEST_RESULT    = 30;
    
    localparam LOOP_CNT = 7;
    localparam TX_DATA  = 'h59;

    // DUT External Connections
    logic clk_12MHz;
    logic rst_in;
    logic [`DATA_WIDTH-1:0] gpio_out_tb_o;
    logic                   gpio_out_we_tb_o;
    logic                   halted_from_dut;
    logic                   led2_o;
    logic                   led3_o;
    
    // Physical UART Wires
    // These wires physically connect the DUT to the testbench's UART.
    logic                   dut_tx_wire; // Connects to DUT's uart_tx_o
    logic                   dut_rx_wire; // Connects to DUT's uart_rx_i
    
    logic                   tx_trigger_btn_o;
    logic                   dut_uart_rx_access;
//    logic                   dut_mmio_rden;

    // Testbench UART signals
    logic tb_uart_rst;

    // Testbench Internal State
    int   cycle_count = 0;
    logic test_passed = 1'b0;
    logic [`DATA_WIDTH-1:0] captured_gpio_out = 'x;
    
 //   logic tb_mmio_rden;
   

    //================================================================
    // DUT Instantiation
    //================================================================
    cpu_tl dut (
        .clk_12MHz      (clk_12MHz),
        .rst_in         (rst_in),
        .gpio_out_o     (gpio_out_tb_o),
        .gpio_out_we_o  (gpio_out_we_tb_o),
        // Connect the DUT's physical pins to the testbench signals
        .uart_tx_o      (dut_tx_wire),
        .uart_rx_i      (dut_rx_wire),
        .tx_trigger_btn_i (tx_trigger_btn_o),
        .halted_o       (halted_from_dut),
        .led2_o         (led2_o),
        .led3_o         (led3_o)
    );

    // Clock Generator
    initial begin
        clk_12MHz = 0;
        forever #(CLK12_PERIOD / 2) clk_12MHz = ~clk_12MHz;
    end
    
    // SIMSPEEDUP logic remains the same...
`ifdef SIMSPEEDUP
    initial begin
        repeat(3) @(posedge clk_12MHz);
        @(posedge dut.abCore16_clk.clk_out1);
        #100;
        @(posedge clk_12MHz);
        force dut.abCore16_clk.locked = 1'b1;
    end
`endif

    //================================================================
    // Interface Instantiation for the Testbench's UART and gpio
    //================================================================
    // This interface belongs to the testbench and will be connected to uart02.
    // It is driven by the testbench's clock and reset.
    uart_if tb_uart_bus ( .clk(clk_12MHz), .rst_n(!tb_uart_rst) );
    
    gpio_bus_if tb_gpio_bus ( .clk(clk_12MHz), .rst_n(!tb_uart_rst) );

    //================================================================
    // Testbench UART Driver Logic
    //================================================================
    initial begin
        $display("SIM UART START: Testbench UART to drive abCore16 serial interface.");
        // 1. Reset the testbench UART
        tb_uart_rst = 1'b1;
        // Drive signals inside the interface
        tb_uart_bus.tx_data  <= 'h59;
        tb_uart_bus.tx_start <= 1'b0;
        dut_uart_rx_access <= 1'b0;     // currently not used
        tb_gpio_bus.mmio_rden <= 1'b0;     // currently not used
//        tb_mmio_rden <= 1'b0;     // currently not used
        tx_trigger_btn_o      = 1'b0;
        repeat(5) @(posedge clk_12MHz);
        tb_uart_rst = 1'b0;
        
    // ****************************
    // Test Pushbutton UART TX
//    repeat(15) @(posedge clk_12MHz);
//    tx_trigger_btn_o = 1'b1;            // test with pushbutton
//    repeat(1) @(posedge clk_12MHz);
//    tx_trigger_btn_o = 1'b0;
    // *****************************
        
        repeat(100) @(posedge clk_12MHz);   // wait for abCore16 setup  
        
        for (integer i=0; i<LOOP_CNT; i++) begin
            // TX_DATA
            tx_data_send(TX_DATA + i);
            repeat(2) @(posedge clk_12MHz);
        end 
        
//        tx_data_send('h59);
//        repeat(2) @(posedge clk_12MHz);
//        tx_data_send('h60);
//        repeat(2) @(posedge clk_12MHz);
//        tx_data_send('h61);
//        repeat(2) @(posedge clk_12MHz);
//        tx_data_send('h62);
//        repeat(2) @(posedge clk_12MHz);
//        tx_data_send('h63);
//        repeat(2) @(posedge clk_12MHz);
//        tx_data_send('h64);
        
        // Start the transmission by asserting the start signal inside the interface
//        tb_uart_bus.tx_start <= 1'b1;      // send one single pulse
//        @(posedge clk_12MHz);
//        tb_uart_bus.tx_start <= 1'b0;
    end 

    //================================================================
    // Testbench UART Instantiation
    //================================================================
    localparam CLK50_FREQ = 50_000_000;
    localparam UART_DATA_BITS = 8;
    //localparam BAUD_RATE = 9600;
    localparam BAUD_RATE = 115200;
    uart_mn #(
          .CLK_FREQ(CLK50_FREQ),
          .DATA_BITS(UART_DATA_BITS),
          .BAUD_RATE(BAUD_RATE)
        ) uart02 (
        // No separate clk/rst, they come from the interface now
        .uart_bus          (tb_uart_bus.peripheral), // Connect the TB interface
        .i_tx_start_manual ('0), // Manual button not used by this instance
        .i_uart_rx_access  (dut_uart_rx_access),
//        .i_mmio_rden       (tb_mmio_rden),
        .gpio_bus          (tb_gpio_bus.peripheral),    // gpio and mmio
        // Connect the physical pins to the wires going to the DUT
        .o_uart_tx         (dut_rx_wire),  // TB UART TX -> DUT RX
        .i_uart_rx         (dut_tx_wire)   // TB UART RX <- DUT TX
    );
    


    // Main Test Sequence (remains the same)
    initial begin
        $display("SIM START: System-level Testbench with Integrated BRAM");
        // 1. Reset the system
        rst_in = 1'b1;
        #1000;
        repeat(2) @(posedge clk_12MHz);
        rst_in = 1'b0;
        $display("TB: Reset de-asserted at time %0t.", $time);

        // 2. Fork off a process to monitor the GPIO output
        fork
            monitor_gpio_out();
        join_none

        // 3. Run simulation
        while (cycle_count < MAX_SIM_CYCLES && !halted_from_dut) begin
            @(posedge dut.clk);
            cycle_count++;
        end

        // 4. Check results
        @(posedge dut.clk);

        if (halted_from_dut) begin
            $display("TB: DUT asserted HALT signal after %0d cycles.", cycle_count);
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

    //================================================================
    // Testbench Tasks
    //================================================================
    // Display to console data on GPIO bus
    task monitor_gpio_out;
        while ( !halted_from_dut ) begin
            @(posedge dut.clk iff gpio_out_we_tb_o);
            captured_gpio_out = gpio_out_tb_o;
            $display("TB @ %0t [Cycle %0d]: GPIO write detected! Captured Value = %0d (0x%h)",
                 $time, cycle_count, captured_gpio_out, captured_gpio_out);
            wait (gpio_out_we_tb_o === 1'b0);
            repeat (3) @(posedge dut.clk);
        end
    endtask
    
    //
    task tx_data_send(input [7:0] tx_data);
        // Drive signals inside the interface
        tb_uart_bus.tx_data <= tx_data;
        
        // Start the transmission by asserting the start signal inside the interface
        tb_uart_bus.tx_start <= 1'b1;      // send one single pulse
//        repeat(2) @(posedge clk_12MHz);
        @(posedge clk_12MHz);
        tb_uart_bus.tx_start <= 1'b0;

    endtask

endmodule
