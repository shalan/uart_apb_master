# UART-to-APB Master Bridge

A debug backdoor bridge that receives commands over a UART serial interface and issues single-word read/write transactions on an AMBA APB bus. Includes an APB bus splitter for up to 8 slave peripherals, a write-once lock register, and a Python host utility.

## Architecture

```
                     uart_apb_sys (system top)
    ┌─────────────────────────────────────────────────────────────┐
    │                                                             │
    │   uart_apb_master (bridge)          apb_splitter            │
    │  ┌──────────────────────┐      ┌─────────────────────┐      │
    │  │                      │      │                     │      │
  ──┼─>│ uart_rx -> cmd_parser├─APB─>│ addr decode  ──> S0 ├──>───┼── Slave 0
    │  │                      │      │              ──> S1 ├──>───┼── Slave 1
  <─┼──│ uart_tx <- resp_build│<─────│  mux PRDATA  ──> S2 ├──>───┼── Slave 2
    │  │             er       │      │              ──> S3 ├──>───┼── Slave 3
    │  │   baud_gen  lock_reg │      │              ──> S4 ├──>───┼── Slave 4
    │  └──────────────────────┘      │              ──> S5 ├──>───┼── Slave 5
    │                                │              ──> S6 ├──>───┼── Slave 6
    │                                │              ──> S7 ├──>───┼── Slave 7
    │                                └─────────────────────┘      │
    └─────────────────────────────────────────────────────────────┘
```

### Modules

| Module | Description |
|--------|-------------|
| `uart_apb_sys` | System top: bridge + splitter with 8 slave ports |
| `uart_apb_master` | Bridge top: UART ↔ APB with lock register and response mux |
| `apb_splitter` | Address decoder: routes 1 APB master to 8 slave ports |
| `baud_gen` | 16x oversampling baud tick generator |
| `uart_rx` | UART receiver with double-flop synchronizer (8N1) |
| `uart_tx` | UART transmitter (8N1) |
| `cmd_parser` | Byte-stream → command decoder with frame timeout |
| `resp_builder` | Response → byte-stream serializer |
| `apb_master` | APB master FSM: IDLE → SETUP → ACCESS → RESP |

## Address Map

The splitter divides a 64 KB window into 8 equal slots of 8 KB each. Address bits `[15:13]` select the slave, bits `[12:0]` are the offset within the slave.

| Slave | Base Address | End Address | Size |
|-------|-------------|-------------|------|
| 0 | `0x0000_0000` | `0x0000_1FFF` | 8 KB |
| 1 | `0x0000_2000` | `0x0000_3FFF` | 8 KB |
| 2 | `0x0000_4000` | `0x0000_5FFF` | 8 KB |
| 3 | `0x0000_6000` | `0x0000_7FFF` | 8 KB |
| 4 | `0x0000_8000` | `0x0000_9FFF` | 8 KB |
| 5 | `0x0000_A000` | `0x0000_BFFF` | 8 KB |
| 6 | `0x0000_C000` | `0x0000_DFFF` | 8 KB |
| 7 | `0x0000_E000` | `0x0000_FFFF` | 8 KB |

Accesses outside the 64 KB window (`0x0001_0000` and above) return `PSLVERR`.

## Command Protocol

All multi-byte fields are transmitted **MSB first**.

### Write Command

| Byte(s) | Value | Description |
|---------|-------|-------------|
| 0 | `0xDE` | Sync byte 0 |
| 1 | `0xAD` | Sync byte 1 |
| 2 | `0xA5` | Write command |
| 3-6 | address | 32-bit address (slave select + offset) |
| 7-10 | data | 32-bit write data |

**Response:** `0xAC` (ACK) or `0xEE` (error)

### Read Command

| Byte(s) | Value | Description |
|---------|-------|-------------|
| 0 | `0xDE` | Sync byte 0 |
| 1 | `0xAD` | Sync byte 1 |
| 2 | `0x5A` | Read command |
| 3-6 | address | 32-bit address (slave select + offset) |

**Response:** `0xAC` + 4 bytes read data (MSB first), or `0xEE` (error)

### Error Responses

| Status | Meaning |
|--------|---------|
| `0xAC` | Success (ACK) |
| `0xEE` | Error — PSLVERR, out-of-range address, or bridge is locked |

## Lock Register

Write `0xDEAD10CC` to address `0xFFFF_FFF0` to permanently disable the bridge:

- The lock command itself completes with ACK
- All subsequent commands receive `0xEE` error responses
- No further APB transactions are issued
- The `locked` output pin goes high
- Only a hardware reset (`rst_n`) can unlock

## Frame Timeout

If a command frame is not completed within `TIMEOUT_CYCLES` clock cycles, the parser resets to sync-search. This prevents lockup from dropped or corrupted bytes.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `DEFAULT_DIVISOR` | 87 | Baud rate divisor: `clk_freq / (baud_rate * 16)`. Default: 16 MHz / 115200. |
| `LOCK_ADDR` | `0xFFFFFFF0` | Address that triggers the lock |
| `LOCK_KEY` | `0xDEAD10CC` | Data value that triggers the lock |
| `TIMEOUT_CYCLES` | 5,000,000 | Frame timeout (~312 ms at 16 MHz) |
| `NUM_SLAVES` | 8 | Number of APB slave ports |
| `SLOT_BITS` | 13 | Address bits per slot (2^13 = 8 KB) |

## Port List

### `uart_apb_sys` (system top)

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `clk` | in | 1 | System clock |
| `rst_n` | in | 1 | Active-low async reset |
| `uart_rx` | in | 1 | UART receive line |
| `uart_tx` | out | 1 | UART transmit line |
| `locked` | out | 1 | High when bridge is locked |
| `Sn_PSEL` | out | 1 | Per-slave APB select (n = 0–7) |
| `Sn_PADDR` | out | 13 | Per-slave APB address (offset within slot) |
| `Sn_PENABLE` | out | 1 | Per-slave APB enable |
| `Sn_PWRITE` | out | 1 | Per-slave APB write |
| `Sn_PWDATA` | out | 32 | Per-slave APB write data |
| `Sn_PRDATA` | in | 32 | Per-slave APB read data |
| `Sn_PREADY` | in | 1 | Per-slave APB ready |
| `Sn_PSLVERR` | in | 1 | Per-slave APB error |

### `uart_apb_master` (bridge only)

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `clk` | in | 1 | System clock |
| `rst_n` | in | 1 | Active-low async reset |
| `uart_rx` | in | 1 | UART receive line |
| `uart_tx` | out | 1 | UART transmit line |
| `PADDR` | out | 32 | APB address |
| `PSEL` | out | 1 | APB select |
| `PENABLE` | out | 1 | APB enable |
| `PWRITE` | out | 1 | APB write |
| `PWDATA` | out | 32 | APB write data |
| `PRDATA` | in | 32 | APB read data |
| `PREADY` | in | 1 | APB ready |
| `PSLVERR` | in | 1 | APB slave error |
| `locked` | out | 1 | High when bridge is locked |

## File Structure

```
rtl/
  uart_apb_sys.v          System top (bridge + splitter + 8 slave ports)
  uart_apb_master.v       Bridge top (UART ↔ APB with lock register)
  apb_splitter.v          APB address decoder / bus splitter
  baud_gen.v              Baud rate tick generator
  uart_rx.v               UART receiver
  uart_tx.v               UART transmitter
  cmd_parser.v            Command frame decoder with timeout
  resp_builder.v          Response frame encoder
  apb_master.v            APB master FSM
tb/
  uart_apb_master_tb.v    Bridge-only testbench (10 tests)
  uart_apb_sys_tb.v       System testbench with 8 slaves (13 tests)
sw/
  uart_apb.py             Python host utility (requires pyserial)
Makefile                  Build targets
```

## Simulation

### Using Make

```bash
make sim            # system testbench (bridge + splitter, 13 tests)
make sim-bridge     # bridge-only testbench (10 tests)
make sim-all        # run both testbenches
make waves          # run system sim and open GTKWave
make lint           # Verilator lint
make clean          # remove build artifacts
```

### Expected Output (system testbench)

```
=== UART-APB System (Splitter) Tests ===

  [PASS] Test 1:  Write Slave 0 @ 0x0000
  [PASS] Test 2:  Read Slave 0 @ 0x0000
  [PASS] Test 3:  Write Slave 1 @ 0x2004
  [PASS] Test 4:  Read Slave 1 @ 0x2004
  [PASS] Test 5:  Write Slave 7 @ 0xE010
  [PASS] Test 6:  Read Slave 7 @ 0xE010
  [PASS] Test 7:  Slave 0 independent of Slave 7
  [PASS] Test 8:  Write to all 8 slaves completed
  [PASS] Test 9:  Read back all 8 slaves correct
  [PASS] Test 10: Out-of-range address returns error
  [PASS] Test 11: Out-of-range read returns error
  [PASS] Test 12: Lock activates
  [PASS] Test 13: Write after lock rejected

=== Results: 13 passed, 0 failed out of 13 ===

ALL TESTS PASSED
```

## Python Host Utility

### Requirements

```bash
pip install pyserial
```

### Usage

```bash
# Direct address (Slave 1, offset 0x04)
python sw/uart_apb.py write 0x2004 0xDEADBEEF
python sw/uart_apb.py read  0x2004

# Slave + offset notation
python sw/uart_apb.py write --slave 3 --offset 0x100 0xCAFEBABE
python sw/uart_apb.py read  --slave 3 --offset 0x100

# Lock the bridge
python sw/uart_apb.py lock

# Print address map
python sw/uart_apb.py map

# Custom port and baud rate
python sw/uart_apb.py read 0x0 --port /dev/tty.usbserial-0001 --baud 9600
```

### Address Map Command

```
$ python sw/uart_apb.py map
Slave      Base          End      Size
--------------------------------------------
  0      0x00000000   0x00001FFF   8192 B
  1      0x00002000   0x00003FFF   8192 B
  2      0x00004000   0x00005FFF   8192 B
  3      0x00006000   0x00007FFF   8192 B
  4      0x00008000   0x00009FFF   8192 B
  5      0x0000A000   0x0000BFFF   8192 B
  6      0x0000C000   0x0000DFFF   8192 B
  7      0x0000E000   0x0000FFFF   8192 B

Lock register: 0xFFFFFFF0 (write 0xDEAD10CC to lock)
```

## Integration Example

```verilog
uart_apb_sys #(
    .DEFAULT_DIVISOR (16'd27),         // 50 MHz / (115200 * 16)
    .TIMEOUT_CYCLES  (32'd10_000_000)  // 200 ms at 50 MHz
) u_debug_sys (
    .clk     (sys_clk),
    .rst_n   (sys_rst_n),
    .uart_rx (debug_rx),
    .uart_tx (debug_tx),
    .locked  (debug_locked),
    // Slave 0: GPIO
    .S0_PSEL(gpio_psel), .S0_PADDR(gpio_paddr), .S0_PENABLE(gpio_penable),
    .S0_PWRITE(gpio_pwrite), .S0_PWDATA(gpio_pwdata),
    .S0_PRDATA(gpio_prdata), .S0_PREADY(gpio_pready), .S0_PSLVERR(gpio_pslverr),
    // Slave 1: Timer
    .S1_PSEL(tmr_psel), .S1_PADDR(tmr_paddr), .S1_PENABLE(tmr_penable),
    .S1_PWRITE(tmr_pwrite), .S1_PWDATA(tmr_pwdata),
    .S1_PRDATA(tmr_prdata), .S1_PREADY(tmr_pready), .S1_PSLVERR(tmr_pslverr),
    // ... connect remaining slaves or tie off unused:
    // .Sn_PRDATA(32'd0), .Sn_PREADY(1'b1), .Sn_PSLVERR(1'b0)
);
```

## License

Apache 2.0
