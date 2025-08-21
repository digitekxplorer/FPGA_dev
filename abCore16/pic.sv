`timescale 1ns / 1ps
/**
 * pic.sv - Simplified interface version
 * 16-Input Programmable Interrupt Controller (PIC) for the abCore16 Processor.
 */

module pic (
    input logic        clk,
    input logic        rst_n,
    // Simplified interfaces
    pic_if.pic         pic_cpu_bus,      // Signals to CPU
    pic_mmio_if.pic    pic_mmio_bus,     // Signals to/from MMIO registers
    // Direct inputs
    input logic        enable_int_i,
    input logic [15:0] irq_i,
    // Debug
    output logic [60:0] dbg_bus_pic   
);

    // --- Internal Registers ---
    logic [15:0] irr; // Interrupt Request Register
    logic [15:0] isr; // In-Service Register

    // --- Combinational Logic ---
    logic [15:0] pending_and_unmasked;
    logic [15:0] requests_to_service;
    logic [3:0]  grant_vec;
    
    logic [15:0] devices_irq;
    logic [15:0] devices_irq_r;
    logic [15:0] devices_irq_2r;
    logic [15:0] devices_irq_sav;
    logic        enable_int_sav;
    logic        new_irq;
    
    // --- FSM signals ---
    logic        grant_irq_fsm;
    logic        pending_irqs_done_fsm;
    logic        pending_int_fsm;

    // =================================
    // FSM (unchanged logic)
    // =================================
    typedef enum logic [2:0] {
        IDLE, SEND_PENDING, WT_EOI, CHK_ISR, NXT_INT
    } pic_state_t;
    
    pic_state_t pic_state;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pic_state              <= IDLE;
            grant_irq_fsm          <= 1'b0;
            pending_irqs_done_fsm  <= 1'b0;
            pending_int_fsm        <= 1'b0;
        end else begin
            grant_irq_fsm          <= 1'b0;
            pending_irqs_done_fsm  <= 1'b0;
            
            case (pic_state)
                IDLE: begin
                    if (enable_int_sav && new_irq) begin
                        grant_irq_fsm  <= 1'b1;
                        pic_state      <= SEND_PENDING;
                    end
                end
                
                SEND_PENDING: begin
                    pending_int_fsm <= 1'b1;
                    pic_state       <= WT_EOI;
                end
                
                WT_EOI: begin
                    if (pic_mmio_bus.eoi_update) begin
                        pic_state <= CHK_ISR;
                    end
                end
                               
                CHK_ISR: begin
                    if (pending_and_unmasked == 16'h0) begin
                        pending_irqs_done_fsm <= 1'b1;
                        pending_int_fsm       <= 1'b0;
                        pic_state             <= IDLE;
                    end else begin
                        pic_state <= NXT_INT;
                    end
                end
            
                NXT_INT: begin
                    grant_irq_fsm <= 1'b1;
                    pic_state     <= SEND_PENDING;
                end
            endcase
        end
    end
    
    // --- IRQ Detection Logic ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            devices_irq_r   <= '0;
            devices_irq_2r  <= '0;
            devices_irq_sav <= '0;
        end else begin
            devices_irq_r  <= irq_i;
            devices_irq_2r <= devices_irq_r;
            if (new_irq) begin
                devices_irq_sav <= devices_irq_2r | devices_irq_sav;
            end else if (pending_irqs_done_fsm) begin
                devices_irq_sav <= '0;
            end
       end
    end
    
    assign new_irq = (devices_irq_r != devices_irq_2r);
    
    always_comb begin
       devices_irq = enable_int_sav ? irq_i : '0;
    end

    // --- Priority Encoding ---
    always_comb begin
        // Use IMR from MMIO interface
        pending_and_unmasked = irr & ~pic_mmio_bus.imr;
        requests_to_service = pending_and_unmasked & ~isr;

        grant_vec = 4'h0;
        if (grant_irq_fsm) begin
            for (int i = 0; i < 16; i++) begin
                if (requests_to_service[i]) begin
                    grant_vec = i;
                    break;
                end
            end
        end       
    end

    // --- Interrupt Enable Logic ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enable_int_sav <= 1'b0;
        end else if (enable_int_i) begin
            enable_int_sav <= 1'b1;
        end else if (pending_irqs_done_fsm) begin
            enable_int_sav <= 1'b0;
        end
    end

    // --- PIC Register Logic ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            irr <= 16'h0000;
            isr <= 16'h0000;
        end else begin
            irr <= irr | devices_irq;

            if (grant_irq_fsm) begin
                isr[grant_vec] <= 1'b1;
                irr[grant_vec] <= 1'b0;
            end else if ((pic_state == WT_EOI) && pic_mmio_bus.eoi_update) begin
                isr[pic_mmio_bus.eoi_irq_num] <= 1'b0;
            end else if (pending_irqs_done_fsm) begin
                isr <= 16'h0000;
                irr <= 16'h0000;
            end
        end
    end
 
    //================================================================
    // Interface Output Assignments
    //================================================================
    // CPU interface
    assign pic_cpu_bus.grant_vec   = grant_vec;
    assign pic_cpu_bus.intrpt      = grant_irq_fsm;
    assign pic_cpu_bus.pending_int = pending_int_fsm;
    
    // MMIO interface  
    assign pic_mmio_bus.irr = irr;
    assign pic_mmio_bus.isr = isr;

    //================================================================
    // Debug
    //================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dbg_bus_pic <= '0;
        end else begin 
            dbg_bus_pic <= { enable_int_i, enable_int_sav, grant_irq_fsm, 
                            pending_int_fsm, pending_irqs_done_fsm, new_irq, 
                            pic_state[2:0], grant_vec[3:0], irr, isr, 
                            pending_and_unmasked };
        end
    end

endmodule
