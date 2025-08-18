/**
 * pic.sv
 * 16-Input Programmable Interrupt Controller (PIC) for the abCore16 Processor.
 *
 * This PIC manages up to 16 interrupt sources. It prioritizes the incoming
 * requests, masks unwanted interrupts, and signals the CPU when a valid
 * interrupt is pending. It is controlled by the CPU via memory-mapped registers.
 *
 * Features:
 * - 16 interrupt request inputs (irq_i).
 * - Fixed priority: IRQ 0 is the highest priority, IRQ 15 is the lowest.
 * - Registers:
 *   - IRR (Interrupt Request Register): Latches incoming interrupt requests.
 *   - IMR (Interrupt Mask Register): Allows software to enable/disable interrupts.
 *   - ISR (In-Service Register): Tracks interrupts currently being serviced.
 * - EOI (End-of-Interrupt) command support to clear interrupts from the ISR.
 * - Outputs a single interrupt signal (int_o) to the CPU.
 *
 * Address Map (assumes word-addressing, using the two least significant bits):
 * - 0x--00: IRR (Read-Only)
 * - 0x--01: IMR (Read/Write)
 * - 0x--02: ISR (Read-Only)
 * - 0x--03: EOI (Write-Only) - Writing the IRQ number (0-15) to this address
 *           signals EOI for that interrupt.
 */
 
//import mmio_reg_pkg::*;
`include "abcore_interfaces.sv"

module pic (
    pic_if.peripheral pic_bus,
//    input logic [15:0] irq_i,
    input logic        enable_int_i,
    input logic        eoi_update_i
);

    // --- Internal Registers ---
    logic [15:0] irr; // Interrupt Request Register
    logic [15:0] imr; // Interrupt Mask Register
    logic [15:0] isr; // In-Service Register

    // --- Combinational Logic for Priority Encoding and Bus ---
    logic [15:0] pending_and_unmasked;
    logic [15:0] requests_to_service;
    logic        grant_irq;
    logic [3:0]  grant_vec;
    
    logic [15:0] devices_irq;
//    assign devices_irq = pic_bus.irq;
    
    // Don't allow interrupts until interrupts are enabled
    always_comb begin
       if (enable_int_i) begin
           devices_irq = pic_bus.irq;
       end
       else begin
          devices_irq = '0;
       end
    end

    always_comb begin
        // 1. Determine which interrupts are active and allowed
        pending_and_unmasked = irr & ~imr;

        // 2. Filter out interrupts that are already being serviced
        requests_to_service = pending_and_unmasked & ~isr;

        // 3. Priority Encoder: Find the highest priority (lowest index) request
        grant_irq = 1'b0;
        grant_vec = 4'h0;
        // Find the first set bit from LSB (IRQ 0) to MSB (IRQ 15)
        for (int i = 0; i < 16; i++) begin
            if (enable_int_i) begin           // System level interrupts enabled
                if (requests_to_service[i]) begin
                    grant_irq = 1'b1;
                    grant_vec = i;
                    break; // Found the highest priority, stop searching
                end
            end
        end
    end

    // --- Sequential Logic for Register State ---
    always_ff @(posedge pic_bus.clk or negedge pic_bus.rst_n) begin
        if (!pic_bus.rst_n) begin
            // Reset state: no requests, all interrupts masked, no service active
            irr <= 16'h0000;
            imr <= 16'hFFFF; // Safe default: all interrupts are disabled
            isr <= 16'h0000;
        end else begin
            // Latch any new incoming requests from peripherals
            // A granted request is cleared from IRR in the next section
//            irr <= irr | pic_bus.irq;                                       // TODO: check this
            irr <= irr | devices_irq;
//            irr <= irr | irq_i;
            imr <= pic_bus.imr;
            
            // Clear Interrupt
            if (eoi_update_i) begin
                isr[pic_bus.irq_num] <= 1'b0;  // contains the IRQ number to clear
            end

            // Handle the grant of a new interrupt
            if (grant_irq) begin
                // Set the corresponding bit in the In-Service Register
                isr[grant_vec] <= 1'b1;
                // Clear the corresponding bit from the Request Register, as it's now being serviced
                irr[grant_vec] <= 1'b0;
            end
        end
    end

//================================================================
// Output assignments to the interface
//================================================================
assign pic_bus.irr       = irr;
assign pic_bus.isr       = isr;
assign pic_bus.intrpt    = grant_irq;      // granted irq
assign pic_bus.grant_vec = grant_vec - 1;  // granted irq num, start will zero


endmodule