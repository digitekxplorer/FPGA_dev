# abCore16

A custom 16-bit microprocessor written in SystemVerilog, with a complete Python-based toolchain — write programs in a simple high-level language, compile them to assembly, assemble to machine code, and run them in simulation or on a Xilinx FPGA.

**abCore16 is a learning platform**: a full vertical slice of 16-bit computing, from language design down to flip-flops, small enough to read end-to-end and real enough to blink LEDs, service interrupts, and drive a UART on actual hardware.

## Features

### Hardware (SystemVerilog RTL)

- **16-bit multi-cycle CPU core** — Harvard-style byte-wide instruction fetch, 8 general-purpose registers (R0–R7), dedicated stack pointer, ALU with Zero/Sign/Carry/Overflow flags
- **~50-instruction ISA** — loads/stores (direct, indirect, frame-relative, byte-wide), arithmetic and logic ops, logical (boolean) ops, full set of conditional jumps, CALL/RET, PUSH/POP, EI/DI/RETI
- **Programmable Interrupt Controller (PIC)** — 16 IRQ lines, priority encoding, IRR/ISR/IMR registers, EOI protocol, with interrupt vector table in data memory
- **Peripherals**
  - 32-bit timer with prescaler, one-shot and continuous modes
  - UART (default 115,200 baud) with TX/RX FIFOs and frame-error detection
  - GPIO output bus and board LED control
- **PIO subsystem** — an RP2040-inspired programmable I/O block: a dedicated state machine executing a compact 9-instruction set (JMP, WAIT, IN, OUT, PUSH, PULL, MOV, SET, IRQ) with input/output shift registers, scratch registers, TX/RX FIFOs, and a bootloader that loads PIO programs from BRAM
- **Memory-mapped I/O** — all peripherals controlled through a register block at `0x1800`
- **Debug support** — internal debug buses wired to a Vivado ILA for on-chip logic analysis

### Software (Python toolchain)

- **SSL compiler** — a simple, direct Simple Source Language translated to assembly
- **C-like SSL compiler** — a more expressive C-like language (functions, arrays, pointers, `char` type, `for`/`while`, `else if`, `switch`, postfix `++`/`--`) built on PLY
- **SAL assembler** — Simple Assembly Language to 16-bit binary machine code
- **Disassembler** — for verifying generated binaries
- **Instruction-level simulator** — execute machine code with full architectural state visibility, no FPGA required

## Memory Map

| Region | Address range | Notes |
|---|---|---|
| Code | `0x0000 – 0x0FFF` | 4 KB instruction memory (byte-addressed) |
| Interrupt vector table | `0x0002 +` | one 16-bit entry per IRQ |
| Data / heap | `0x1000 – 0x17FF` | grows up |
| Memory-mapped I/O | `0x1800 – 0x18FF` | PIC, timer, UART, LEDs, PIO |
| Stack | `0x1FFE` ↓ | grows down toward `0x1900` |

## Repository Layout

```
rtl/
  defines.svh           Opcodes, architecture parameters, control encodings
  abcore_interfaces.sv  SystemVerilog interfaces (imem/dmem/gpio/pic/timer/uart/pio)
  cpu_tl.sv             FPGA top level: clocks, peripherals, ILA
  cpu_system.sv         CPU subsystem: core + memory + byte-access logic
  core.sv               Processor core (control unit + datapath)
  control_unit.sv       Multi-cycle FSM, instruction decode
  datapath.sv           PC, register file, SP, flags, ALU muxing
  alu.sv                16-bit ALU with flag generation
  pic.sv                Programmable interrupt controller
  timer.sv              32-bit timer peripheral
  uart_mn.sv            UART top (FIFOs + control FSMs)
  uart_tx.sv, uart_rx.sv
  mmio_reg_pkg.sv       Register map package (addresses, register structs)
  mmio_regs.sv          Memory-mapped register block
  pio_tl.sv             PIO top level
  pio_cu.sv, pio_dp.sv  PIO control unit and datapath
  pio_bootloader.sv     Loads PIO programs from BRAM into PIO imem
  pio_program_mem.sv    PIO program storage
```

*(Adjust paths to match your actual layout — the Python toolchain typically lives in a sibling `tools/` or `toolchain/` directory.)*

## Getting Started

### Prerequisites

- **Simulation / synthesis:** AMD Xilinx Vivado (developed with 2024.2)
- **Toolchain:** Python 3.x, [PLY](https://www.dabeaz.com/ply/) for the C-like compiler
- **Hardware (optional):** a Xilinx 7-series board (developed on Spartan-7, `xc7s25csga225-1`) with a 12 MHz input clock

### Build a program and run it in simulation

1. Write a program in SSL or C-like SSL:

   ```c
   // blink.ssl — toggle the board LED using the hardware timer
   int main() {
       // configure timer, enable interrupts, loop...
   }
   ```

2. Compile → assemble to a `.hex` image:

   ```
   python compiler.py blink.ssl -o blink.sal
   python assembler.py blink.sal -o blink.hex
   ```

3. Run in the Python simulator for fast iteration:

   ```
   python simulator.py blink.hex
   ```

4. Run in RTL simulation: set the image in `cpu_system.sv`

   ```systemverilog
   `define IMEM_HEX_FILE "blink.hex"
   ```

   with `MEMORYMODELSIM` and `SIMSPEEDUPCLK` defined, then simulate `cpu_tl` from your Vivado testbench.

### Build for FPGA

1. Comment out `MEMORYMODELSIM` and `SIMSPEEDUPCLK` in `cpu_system.sv` / `cpu_tl.sv`
2. Regenerate the block-memory IP (`abCore16_blk_mem`) with the program's `.coe` file
3. Synthesize and implement `cpu_tl` in Vivado; the MMCM generates the 50 MHz system clock from the 12 MHz board clock

## Architecture Overview

```
             ┌─────────────────────────── cpu_tl ───────────────────────────┐
             │  ┌──────── cpu_system ────────┐                              │
 12 MHz ──►  │  │  ┌── core ──┐              │   ┌───────────┐   ┌───────┐  │
 (MMCM 50M)  │  │  │ control  │  imem (BRAM) │   │ mmio_regs │◄─►│ timer │  │
             │  │  │  unit    │  dmem (BRAM) │◄─►│  0x1800   │   ├───────┤  │
             │  │  │ datapath │  byte R-M-W  │   │           │◄─►│ uart  │──► TX/RX
             │  │  └──────────┘              │   │           │   ├───────┤  │
             │  └────────────▲───────────────┘   │           │◄─►│  pio  │──► GPIO
             │               │ IRQ grant         └─────▲─────┘   └───┬───┘  │
             │           ┌───┴───┐  IRR/ISR/IMR/EOI    │             │      │
             │           │  pic  │◄────────────────────┘    IRQs ────┘      │
             │           └───────┘                                          │
             └──────────────────────────────────────────────────────────────┘
```

The core is **DP-centric multi-cycle**: the control unit fetches instruction bytes one at a time through the byte-wide instruction port, assembles operands in its instruction registers, and sequences the datapath through fetch → decode → execute → memory → writeback states. Interrupt entry saves PC and flags in hardware; `RETI` restores both.

## Status

Working in simulation and on hardware: full ISA, multiple simultaneous interrupts (timer + UART RX), byte-access instructions, C-like language features (pointers, arrays, `char`), UART at 115,200 baud, hardware-timer LED blink. PIO subsystem is functional and under active integration with the MMIO register block.

## License

MIT — see [LICENSE](LICENSE).

## Author

Al Baeza — ab Systems
