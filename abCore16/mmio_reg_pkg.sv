// July 17, 2025
// August 13, 2025 MODIFIED: Added PIC registers at the base address 
// and shifted all other peripherals.
// SystemVerilog Structures for abCore16 Memory-Mapped IO Registers
`ifndef MMIO_REG_PKG
`define MMIO_REG_PKG

package mmio_reg_pkg;

  // ************************
  // Register Data Structures
  // ************************
  
  // --- PIC Registers ---
  // PIC End-of-Interrupt Register (EOI) (Base + 0x06, Write-Only)
  // Used to signal the completion of an interrupt handler.
  typedef struct packed {
    logic [11:0] reserved; // Reserved bits [15:4]
    logic [3:0]  irq_num;  // IRQ number (0-15) to clear from ISR.
  } pic_eoi_t;
  
  // --- Timer Registers ---
  // Timer Control Register
  typedef struct packed {
    logic [11:0] reserved;      // Reserved bits [15:4]
    logic        prescale_en;   // Prescaler enable [3]
    logic        mode;          // 0=one-shot, 1=continuous [2]
    logic        reset;         // Timer reset (auto-clear) [1]
    logic        enable;        // Timer enable [0]
  } timer_ctrl_t;
  
  // Timer Status Register
  typedef struct packed {
    logic [12:0] reserved;      // Reserved bits [15:3]
    logic        running;       // Timer running status [2]
    logic        overflow;      // Timer overflow flag [1]
    logic        timeout;       // Timer timeout flag [0]
  } timer_status_t;
  
  // --- UART Registers ---
  // UART Control Register
  typedef struct packed {
    logic [13:0] reserved;      // Reserved bits [15:2]
    logic        reset_flags;   // Reset RX flags (auto-clear) [1]
    logic        tx_start;      // Start transmission (auto-clear) [0]
  } uart_ctrl_t;
  
  // UART Status Register
  typedef struct packed {
    logic [11:0] reserved;           // Reserved bits [15:4]
    logic        rx_fifo_prog_full;  // RX FIFO programed full [3]
    logic        rx_error;           // RX frame error [2]
    logic        rx_data_avail;      // RX Fifo data valid [1]
    logic        tx_fifo_avail;      // TX FIFO status [0]
  } uart_status_t;
  
  // UART Data Registers
  typedef struct packed {
    logic [7:0] reserved;       // Reserved bits [15:8]
    logic [7:0] data;           // UART data [7:0]
  } uart_data_t;
  
  // --- Board LED Register ---
  // Board LED Control Register
  typedef struct packed {
    logic [11:0] reserved;      // Reserved bits [15:4]
    logic        led3_o;     // LED#3: 0=off; 1=on
    logic        led2_o;     // LED#2: 0=off; 1=on
    logic        led1_o;     // LED#1: 0=off; 1=on
    logic        led0_o;     // LED#0: 0=off; 1=on
  } led_ctrl_t;
  
  // --- System Control (NEW) ---
  // 0x1822
  typedef struct packed {
    logic [14:0] reserved;      // Reserved bits [15:4]
    logic        sys_int_en;    // system level enabled: 0=off; 1=on
  } sys_ctrl_t;
  
  // --- PIO Control Registers ---
  // PIO Control Register (0x1830)
  typedef struct packed {
    logic [6:0]  reserved;          // Reserved [15:9]
    logic        bootload_start;    // Start bootloader [8] (auto-clear)
    logic [3:0]  program_select;    // Program selection [7:4]
    logic        pio_reset;         // PIO reset (self-clearing) [3]
    logic [1:0]  state_machine_id;  // State machine ID [2:1]
    logic        pio_go;            // PIO enable/start [0]
  } pio_ctrl_t;
  
  // PIO Pin Control Register (0x1832)  
  typedef struct packed {
    logic        reserved_15;       // Reserved [15]
    logic [4:0]  pinctrl_out_count; // Output pin count [14:10]
    logic [4:0]  pinctrl_out_base;  // Output pin base [9:5]
    logic [4:0]  pinctrl_in_base;   // Input pin base [4:0]
  } pio_pinctrl_t;

  // PIO Shift Control Register (0x1834)
  typedef struct packed {
    logic        shiftctrl_out_shiftdir; // Output shift direction [15]
    logic [4:0]  shiftctrl_autopull_thresh; // Auto-pull threshold [14:10]
    logic [4:0]  shiftctrl_push_thresh;  // Push threshold [9:5]
    logic [4:0]  shiftctrl_pull_thresh;  // Pull threshold [4:0]
  } pio_shiftctrl_t;

  // PIO Execution Control Register (0x1836)
  typedef struct packed {
    logic [3:0]  shiftctrl_autopush_thresh; // Auto-push threshold [15:12]
    logic        shiftctrl_autopush_en;     // Auto-push enable [11]
    logic        shiftctrl_in_shiftdir;     // Input shift direction [10]
    logic [4:0]  shiftctrl_in_count;       // Input count [9:5]
    logic [4:0]  execctrl_jmp_pin;         // Jump pin [4:0]
  } pio_execctrl_t;

  // PIO FIFO Data Registers (0x1838 => TX, 0x183A => RX)
  typedef struct packed {
    logic [15:0] data;              // FIFO data [15:0]
  } pio_fifo_data_t;

  // PIO Instruction Programming Register (0x183C)
  typedef struct packed {
    logic [15:0] instruction;       // 16-bit instruction [15:0]
  } pio_instr_t;

  // PIO Status Register (0x183E)                               // TODO: added status
  typedef struct packed {
    logic [12:0] reserved;          // Reserved [15:3]
//    logic [4:0]  debug_pc;          // Current PC [4:0]
    logic pio_out_pin;            // used as PIO output pins status
    logic bootload_error;         // PIO instruction transfer error
    logic bootload_done;          // PIO instruction transfer to PIO imem done
  } pio_status_t;
  
  // --- Complete Register Map Structure ---
  // Memory-mapped base address = 0x1800
  typedef struct packed {
    // PIC Registers (0x00 - 0x06)
    // PIC Interrupt Request Register (IRR) (Base + 0x00, Read-Only)
    // Latches requests from irq_i inputs.
    logic [15:0]    pic_irr;         // 0x00 (R)
    // PIC Interrupt Mask Register (IMR) (Base + 0x02, Read/Write)
    // Masks/disables interrupts.
    logic [15:0]    pic_imr;         // 0x02 (R/W)
    // PIC In-Service Register (ISR) (Base + 0x04, Read-Only)
    // Tracks interrupts currently being serviced.    
    logic [15:0]    pic_isr;         // 0x04 (R)
    // PIC End-of-Interrupt Register (EOI) (Base + 0x06, Write-Only)
    // Used to signal the completion of an interrupt handler.
    pic_eoi_t       pic_eoi;         // 0x06 (W)

    // Timer Registers (0x08 - 0x14)
    timer_ctrl_t    timer_ctrl;      // 0x08
    logic [15:0]    timer_prescale;  // 0x0A
    logic [15:0]    timer_reload_l;  // 0x0C
    logic [15:0]    timer_reload_h;  // 0x0E
    logic [15:0]    timer_count_l;   // 0x10 (R)
    logic [15:0]    timer_count_h;   // 0x12 (R)
    timer_status_t  timer_status;    // 0x14

    logic [15:0]    reserved_16;     // 0x16

    // UART and LED Registers (0x18 - 0x20)
    uart_ctrl_t     uart_ctrl;       // 0x18
    uart_status_t   uart_status;     // 0x1A
    uart_data_t     uart_tx_data;    // 0x1C
    uart_data_t     uart_rx_data;    // 0x1E
    led_ctrl_t      led_ctrl;        // 0x20
    sys_ctrl_t      sys_ctrl;        // 0x22
    
    // PIO Registers (0x30 - 0x3E)
    pio_ctrl_t      pio_ctrl;         // 0x30
    pio_pinctrl_t   pio_pinctrl;      // 0x32
    pio_shiftctrl_t pio_shiftctrl;    // 0x34
    pio_execctrl_t  pio_execctrl;     // 0x36
    pio_fifo_data_t pio_tx_fifo;      // 0x38
    pio_fifo_data_t pio_rx_fifo;      // 0x3A
    pio_instr_t     pio_instr;        // 0x3C
    pio_status_t    pio_status;       // 0x3E
    
  } register_map_t;
  
  
  // *********************
  // Register Address Map
  // *********************
  localparam MMIO_ADDRESS_BASE       = 16'h1800;
  localparam MMIO_ADDRESS_RANGE      = 16'h0100;

  // PIC Addresses
  localparam ADDRESS_PIC_IRR         = MMIO_ADDRESS_BASE + 16'h0000;
  localparam ADDRESS_PIC_IMR         = MMIO_ADDRESS_BASE + 16'h0002;
  localparam ADDRESS_PIC_ISR         = MMIO_ADDRESS_BASE + 16'h0004;
  localparam ADDRESS_PIC_EOI         = MMIO_ADDRESS_BASE + 16'h0006;

  // Timer Addresses
  localparam ADDRESS_TIMER_CTRL      = MMIO_ADDRESS_BASE + 16'h0008;
  localparam ADDRESS_TIMER_PRESCALE  = MMIO_ADDRESS_BASE + 16'h000A;
  localparam ADDRESS_TIMER_RELOAD_L  = MMIO_ADDRESS_BASE + 16'h000C;
  localparam ADDRESS_TIMER_RELOAD_H  = MMIO_ADDRESS_BASE + 16'h000E;
  localparam ADDRESS_TIMER_COUNT_L   = MMIO_ADDRESS_BASE + 16'h0010;
  localparam ADDRESS_TIMER_COUNT_H   = MMIO_ADDRESS_BASE + 16'h0012;
  localparam ADDRESS_TIMER_STATUS    = MMIO_ADDRESS_BASE + 16'h0014;

  // UART and LED Addresses
  localparam ADDRESS_UART_CTRL       = MMIO_ADDRESS_BASE + 16'h0018;
  localparam ADDRESS_UART_STATUS     = MMIO_ADDRESS_BASE + 16'h001A;
  localparam ADDRESS_UART_TX_DATA    = MMIO_ADDRESS_BASE + 16'h001C;
  localparam ADDRESS_UART_RX_DATA    = MMIO_ADDRESS_BASE + 16'h001E;
  localparam ADDRESS_LED_CTRL        = MMIO_ADDRESS_BASE + 16'h0020;
  localparam ADDRESS_SYSTEM_CTRL     = MMIO_ADDRESS_BASE + 16'h0022;
  
  // PIO Addresses
  localparam ADDRESS_PIO_CTRL        = MMIO_ADDRESS_BASE + 16'h0030;    // PIO Control Register
  localparam ADDRESS_PIO_PINCTRL     = MMIO_ADDRESS_BASE + 16'h0032;    // PIO Pin Control Register  
  localparam ADDRESS_PIO_SHIFTCTRL   = MMIO_ADDRESS_BASE + 16'h0034;    // PIO Shift Control Register
  localparam ADDRESS_PIO_EXECCTRL    = MMIO_ADDRESS_BASE + 16'h0036;    // PIO Execution Control Register
  localparam ADDRESS_PIO_TX_FIFO     = MMIO_ADDRESS_BASE + 16'h0038;    // PIO TX FIFO Data Register
  localparam ADDRESS_PIO_RX_FIFO     = MMIO_ADDRESS_BASE + 16'h003A;    // PIO RX FIFO Data Register
  localparam ADDRESS_PIO_INSTR       = MMIO_ADDRESS_BASE + 16'h003C;    // PIO Instruction Programming Register
  localparam ADDRESS_PIO_STATUS      = MMIO_ADDRESS_BASE + 16'h003E;    // PIO Status Register
  
  // *********************
  // Register Parameters
  // *********************
  // Note: REGISTER_COUNT may need adjustment based on how it's used.
  localparam REGISTER_COUNT = 17; 
  localparam REGISTER_DWIDTH = 16;
  localparam ADDRESS_WIDTH = 14;
  
  // Helper function for register access
  function automatic logic is_read_only(input logic [ADDRESS_WIDTH-1:0] addr);
    case (addr)
      // PIC Read-Only Registers
      ADDRESS_PIC_IRR,
      ADDRESS_PIC_ISR,
      // Note: ADDRESS_PIC_EOI is write-only.

      // Other Read-Only Registers
      ADDRESS_TIMER_COUNT_L,
      ADDRESS_TIMER_COUNT_H,
      ADDRESS_TIMER_STATUS,
      ADDRESS_UART_STATUS,
      ADDRESS_UART_RX_DATA: return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

endpackage : mmio_reg_pkg

`endif
