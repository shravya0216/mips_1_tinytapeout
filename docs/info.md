<!--
This file gets automatically generated into your docs/index.html by the GitHub Action.
-->

## How it works

This is a classic 5-stage pipelined MIPS CPU (fetch, decode, execute, memory, writeback)
with data forwarding, load-use hazard stalling, and a simple PHT/BHT/BTB branch predictor.
Instead of a fixed program burned into the design, everything the CPU needs — the program,
initial register values, and initial data memory contents — is loaded from off-chip over I2C.

The chip is an I2C **slave** at address `0x42`. An external microcontroller (MCU) is the I2C
master and is write-only from the chip's point of view for programming, plus a read path for
verifying what was loaded.

### Memory map

| Address range     | Target                     |
|--------------------|-----------------------------|
| `0x0000`-`0x00FC`  | Instruction memory (64 x 32-bit words) |
| `0x1000`-`0x107C`  | Register file R0-R31        |
| `0x2000`-`0x20FC`  | Data memory (64 x 32-bit words) |
| `0x3000`           | CSR: bit0 = RUN (MCU-writable), bit1 = DONE (CPU-generated) |
| `0x3004`           | TARGET_PC (32-bit)          |
| `0x3008`           | Live PC (read-only)         |

Instruction, data and target-PC memory sizes were reduced from an earlier 256-word version to
64 words each (2048 bits) to fit the Tiny Tapeout sky130 area budget. Addresses are word-aligned;
writing to any other offset in a mapped region is ignored.

### Sequence of operation

1. **LOAD** (`CSR.RUN = 0`, the reset default): the CPU's PC and all of its pipeline registers
   are held. The MCU writes instructions into IMEM, initial register values into the register
   file, and any initial data into DMEM, plus a `TARGET_PC` — the address of the first
   instruction that must **not** execute.
2. The MCU writes `CSR.RUN = 1`. The CPU starts fetching from address 0 and runs normally —
   forwarding, stalling and branch prediction all work exactly as in the original CPU.
3. **DRAIN**: once the PC reaches `TARGET_PC`, fetch is blocked (a NOP is inserted instead) and
   the pipeline is allowed to drain the instructions already in flight.
4. **HALT**: once the pipeline is empty, `CSR.DONE` is set, the `led` output goes high, and
   every pipeline register freezes. No further instructions ever execute after this point.

### I2C protocol

**Write** (32-bit MMIO write, 63 SCL clocks total):

```
START  0x42+W  ACK  addr[15:8] ACK  addr[7:0] ACK
       data[31:24] ACK  data[23:16] ACK  data[15:8] ACK  data[7:0] ACK  STOP
```

**Read** (repeated START):

```
START  0x42+W  ACK  addr[15:8] ACK  addr[7:0] ACK
Sr     0x42+R  ACK  data[31:24] ACK data[23:16] ACK data[15:8] ACK data[7:0] NACK  STOP
```

All bytes are MSB-first. `mmio_wr` is asserted for exactly one system clock after the final
data byte of a write is received; the MMIO decoder that routes the write to IMEM/REGFILE/DMEM/
CSR/TARGET_PC is purely combinational, so it costs zero extra I2C clocks.

## How to test

Program a tiny 4-instruction routine and let it run:

```
0x0000  <- 0x08010005   ; addi $1, $0, 5
0x0004  <- 0x08020007   ; addi $2, $0, 7
0x0008  <- 0x00221800   ; add  $3, $1, $2
0x000C  <- 0x10030000   ; sw   $3, 0($0)
0x3004  <- 0x00000010   ; TARGET_PC = 0x10 (one past the last instruction)
0x3000  <- 0x00000001   ; CSR.RUN = 1
```

The `led` output should go high shortly after, and reading back MMIO address `0x2000`
(DMEM[0]) should return `12`. This exact sequence is exercised by the Verilog testbench in
`test/tb_top.v`.

## External hardware

An I2C master (any MCU) wired to `ui_in[0]` (SCL) and `uio[0]` (SDA, open-drain — needs an
external pull-up resistor to VDD, as with any I2C bus). `uo_out[0]` drives an LED (through a
current-limiting resistor) that lights up once the loaded program finishes.
