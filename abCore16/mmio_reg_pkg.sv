// July 17, 2025
// SystemVerilog Structures for abCore16 Memory-Mapped IO Registers
`ifndef MMIO_REG_PKG
`define MMIO_REG_PKG

package mmio_reg_pkg;

  // ************************
  // Register Data Structures
  // ************************
  
  // Timer Control Register (0x00)
  typedef struct packed {
    logic [11:0] reserved;      // Reserved bits [15:4]
    logic        prescale_en;   // Prescaler enable [3]
    logic        mode;          // 0=one-shot, 1=continuous [2]
    logic        reset;         // Timer reset (auto-clear) [1]
    logic        enable;        // Timer enable [0]
  } timer_ctrl_t;
  
  // Timer Status Register (0x0C)
  typedef struct packed {
    logic [12:0] reserved;      // Reserved bits [15:3]
    logic        running;       // Timer running status [2]
    logic        overflow;      // Timer overflow flag [1]
    logic        timeout;       // Timer timeout flag [0]
  } timer_status_t;
  
  // UART Control Register (0x10)
  typedef struct packed {
    logic [13:0] reserved;      // Reserved bits [15:2]
    logic        reset_flags;   // Reset RX flags (auto-clear) [1]
    logic        tx_start;      // Start transmission (auto-clear) [0]
  } uart_ctrl_t;
  
  // UART Status Register (0x12)
  typedef struct packed {
    logic [12:0] reserved;      // Reserved bits [15:3]
    logic        rx_error;      // RX frame error [2]
    logic        rx_valid;      // RX data valid [1]
//    logic        tx_busy;       // TX busy status [0]
    logic        tx_fifo_avail; // TX FIFO status [0]
  } uart_status_t;
  
  // UART Data Registers (0x14, 0x16)
  typedef struct packed {
    logic [7:0] reserved;       // Reserved bits [15:8]
    logic [7:0] data;           // UART data [7:0]
  } uart_data_t;
  
  // Board LED Control Register (0x18)
  typedef struct packed {
    logic [11:0] reserved;      // Reserved bits [15:4]
    logic        led3_o;     // LED#1: 0=off; 1=on
    logic        led2_o;     // LED#0: 0=off; 1=on
    logic        led1_o;     // LED#1: 0=off; 1=on
    logic        led0_o;     // LED#0: 0=off; 1=on
  } led_ctrl_t;
  
  // Complete Register Map Structure
  // Memory-mapped base address = 0x1800
  typedef struct packed {
    timer_ctrl_t    timer_ctrl;      // 0x00
    logic [15:0]    timer_prescale;  // 0x02
    logic [15:0]    timer_reload_l;  // 0x04
    logic [15:0]    timer_reload_h;  // 0x06
    logic [15:0]    timer_count_l;   // 0x08 (read-only)
    logic [15:0]    timer_count_h;   // 0x0A (read-only)
    timer_status_t  timer_status;    // 0x0C
    logic [15:0]    reserved_0e;     // 0x0E
    uart_ctrl_t     uart_ctrl;       // 0x10
    uart_status_t   uart_status;     // 0x12
    uart_data_t     uart_tx_data;    // 0x14
    uart_data_t     uart_rx_data;    // 0x16
    led_ctrl_t      led_ctrl;        // 0x18
  } register_map_t;
  
  
  // *********************
  // Register Address Map
  // *********************
  localparam MMIO_ADDRESS_BASE       = 16'h1800;
  localparam MMIO_ADDRESS_RANGE      = 16'h0100;
  localparam ADDRESS_TIMER_CTRL      = MMIO_ADDRESS_BASE + 16'h0000;
  localparam ADDRESS_TIMER_PRESCALE  = MMIO_ADDRESS_BASE + 16'h0002;
  localparam ADDRESS_TIMER_RELOAD_L  = MMIO_ADDRESS_BASE + 16'h0004;
  localparam ADDRESS_TIMER_RELOAD_H  = MMIO_ADDRESS_BASE + 16'h0006;
  localparam ADDRESS_TIMER_COUNT_L   = MMIO_ADDRESS_BASE + 16'h0008;
  localparam ADDRESS_TIMER_COUNT_H   = MMIO_ADDRESS_BASE + 16'h000A;
  localparam ADDRESS_TIMER_STATUS    = MMIO_ADDRESS_BASE + 16'h000C;
  localparam ADDRESS_UART_CTRL       = MMIO_ADDRESS_BASE + 16'h0010;
  localparam ADDRESS_UART_STATUS     = MMIO_ADDRESS_BASE + 16'h0012;
  localparam ADDRESS_UART_TX_DATA    = MMIO_ADDRESS_BASE + 16'h0014;
  localparam ADDRESS_UART_RX_DATA    = MMIO_ADDRESS_BASE + 16'h0016;
  localparam ADDRESS_LED_CTRL        = MMIO_ADDRESS_BASE + 16'h0018;
  
  // *********************
  // Register Parameters
  // *********************
  localparam REGISTER_COUNT = 12;
  localparam REGISTER_DWIDTH = 16;
  localparam ADDRESS_WIDTH = 14;
  
  // Helper functions for register access
  // Currently not used.
//  function automatic logic [4:0] addr_to_index(input logic [4:0] addr);
//    return addr[4:1]; // Convert byte address to register index
//  endfunction
  
  function automatic logic is_read_only(input logic [ADDRESS_WIDTH-1:0] addr);
    case (addr)
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
