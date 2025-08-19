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
//    logic [3:0]  grant_vec_sav;
    logic        pending_int;  // OR all irr bits
    
    logic [15:0] devices_irq;
    logic [15:0] devices_irq_r;
    logic [15:0] devices_irq_2r;
    logic [15:0] devices_irq_sav;
    logic        enable_int_sav;
    logic        enable_int_sav_clr;
    logic        new_irq;
    
    logic [15:0] isr_sav;
    logic        grant_irq_gen;


    // --- Sequential Logic for Register State ---
    always_ff @(posedge pic_bus.clk or negedge pic_bus.rst_n) begin
        if (!pic_bus.rst_n) begin
            devices_irq_r   <= '0;
            devices_irq_2r  <= '0;
            devices_irq_sav <= '0;
//            grant_vec_sav   <= '0;
        end 
        else begin
            devices_irq_r  <= pic_bus.irq;
            devices_irq_2r <= devices_irq_r;
            if (new_irq) begin
                devices_irq_sav <= devices_irq_2r;
            end
            
            //
            if (grant_irq) begin
//                grant_vec_sav <= grant_vec;
            end 
       end
    end
    
    assign new_irq = (devices_irq_r != devices_irq_2r);
    
    
    // Don't allow interrupts until interrupts are enabled
    always_comb begin
//       if (enable_int_i) begin
       if (enable_int_sav) begin
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
//        for (int i = 0; i < 16; i++) begin
//            if (enable_int_i) begin           // System level interrupts enabled
//                if (requests_to_service[i]) begin
//                    grant_irq = 1'b1;
//                    grant_vec = i;
//                    break; // Found the highest priority, stop searching
//                end
//            end
//        end
        
//    if (enable_int_sav) begin
    // grant_irq_gen
    if (grant_irq_gen) begin
        // Check from highest priority (0) to lowest priority (15)
        if (requests_to_service[0]) begin
            grant_irq = 1'b1;
            grant_vec = 0;
        end else if (requests_to_service[1]) begin
            grant_irq = 1'b1;
            grant_vec = 1;
        end else if (requests_to_service[2]) begin
            grant_irq = 1'b1;
            grant_vec = 2;
        end else if (requests_to_service[3]) begin
            grant_irq = 1'b1;
            grant_vec = 3;
        end else if (requests_to_service[4]) begin
            grant_irq = 1'b1;
            grant_vec = 4;
        end else if (requests_to_service[5]) begin
            grant_irq = 1'b1;
            grant_vec = 5;
        end else if (requests_to_service[6]) begin
            grant_irq = 1'b1;
            grant_vec = 6;
        end else if (requests_to_service[7]) begin
            grant_irq = 1'b1;
            grant_vec = 7;
        end else if (requests_to_service[8]) begin
            grant_irq = 1'b1;
            grant_vec = 8;
        end else if (requests_to_service[9]) begin
            grant_irq = 1'b1;
            grant_vec = 9;
        end else if (requests_to_service[10]) begin
            grant_irq = 1'b1;
            grant_vec = 10;
        end else if (requests_to_service[11]) begin
            grant_irq = 1'b1;
            grant_vec = 11;
        end else if (requests_to_service[12]) begin
            grant_irq = 1'b1;
            grant_vec = 12;
        end else if (requests_to_service[13]) begin
            grant_irq = 1'b1;
            grant_vec = 13;
        end else if (requests_to_service[14]) begin
            grant_irq = 1'b1;
            grant_vec = 14;
        end else if (requests_to_service[15]) begin
            grant_irq = 1'b1;
            grant_vec = 15;
        end
    end

        
        
    end  // always_comb end
    
    // --- Sequential Logic for Register State ---
    always_ff @(posedge pic_bus.clk or negedge pic_bus.rst_n) begin
        if (!pic_bus.rst_n) begin
            enable_int_sav <= 1'b0;
        end 
        else if (enable_int_i) begin
            enable_int_sav <= 1'b1;
       end
//       else if (eoi_update_i  && !pending_int) begin
       // enable_int_sav_clr
       else if (enable_int_sav_clr) begin
            enable_int_sav <= 1'b0;
      end
    end

    // --- Sequential Logic for Register State ---
    always_ff @(posedge pic_bus.clk or negedge pic_bus.rst_n) begin
        if (!pic_bus.rst_n) begin
            // Reset state: no requests, all interrupts masked, no service active
            irr <= 16'h0000;
            imr <= 16'hFFFF; // Safe default: all interrupts are disabled
            isr <= 16'h0000;
//            pending_int <= 1'b0;  // OR all irr bits
        end else begin
            // Latch any new incoming requests from peripherals
            // A granted request is cleared from IRR in the next section
            irr <= irr | devices_irq;
            imr <= pic_bus.imr;
            // Pending interrupt
//            pending_int <= |pending_and_unmasked;  // Perform the reduction OR operation
//            pending_int <= |isr;  // Perform the reduction OR operation
            // Clear Interrupt
//            if (eoi_update_i) begin
//                isr[pic_bus.irq_num] <= 1'b0;  // contains the IRQ number to clear
//            end

            // Handle the grant of a new interrupt
            if (grant_irq) begin
                // Set the corresponding bit in the In-Service Register
                isr[grant_vec] <= 1'b1;
                // Clear the corresponding bit from the Request Register, as it's now being serviced
                irr[grant_vec] <= 1'b0;
            end
            
            // clr isr when done with all interrupts
            if (enable_int_sav_clr) begin
                isr <= 16'h0000;          // clr
            end
        end
    end
 
	
	// =================================
    // FSM
    // =================================
    // State machine
    typedef enum logic [2:0] {
        IDLE,
        SAVE_REGS,
        WT_EOI,
        CHK_ISR,
		NXT_INT
    } pic_state_t;
    
    pic_state_t pic_state;
    
    always_ff @(posedge uart_bus.clk or negedge uart_bus.rst_n) begin
        if (!uart_bus.rst_n) begin
            pic_state <= IDLE;
            isr_sav <= '0;
			grant_irq_gen <= 1'b0;
			enable_int_sav_clr <= 1'b0;
			pending_int <= 1'b0;
        end else begin
            isr_sav <= '0;  // Default
			grant_irq_gen <= 1'b0;
			enable_int_sav_clr <= 1'b0;
//			pending_int <= 1'b0;
            
            case (pic_state)
                IDLE: begin
                    if (enable_int_sav && (new_irq)) begin
                        grant_irq_gen <= 1'b1;
						pic_state <= SAVE_REGS;
                    end
                end
                
                SAVE_REGS: begin
                    // 
//                    isr_sav       <= isr;
//					grant_vec_sav <= grant_vec;
					pending_int <= 1'b1;
                    pic_state     <= WT_EOI;
                end
                
                // Wait update from control_unit, means end of ISR
                WT_EOI: begin
                    isr_sav       <= isr;
                    if (eoi_update_i) begin
					    isr[pic_bus.irq_num] <= 1'b0;  // contains the IRQ number to clear
                        pic_state <= CHK_ISR;
                    end
                end
                               
                CHK_ISR: begin
                    if (pending_and_unmasked == 16'h0) begin
                        enable_int_sav_clr <= 1'b1;
                        pending_int <= 1'b0;
                        pic_state <= IDLE;    // done with interrupt, wait for next
                    end
					else begin
					    pic_state <= NXT_INT;
					end
                end
			
                NXT_INT: begin
				    isr_sav       <= isr;
					grant_irq_gen <= 1'b1;
                    pic_state <= SAVE_REGS;
                end
				
            endcase
        end
    end
    

//================================================================
// Output assignments to the interface
//================================================================
assign pic_bus.irr         = irr;
assign pic_bus.isr         = isr;
assign pic_bus.intrpt      = grant_irq;      // granted irq
assign pic_bus.grant_vec   = grant_vec - 1;  // granted irq num, start will zero
assign pic_bus.pending_int = pending_int;


endmodule
