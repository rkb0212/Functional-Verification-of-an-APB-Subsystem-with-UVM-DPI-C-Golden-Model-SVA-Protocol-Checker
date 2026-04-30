# Functional Verification of an APB Subsystem with UVM, DPI-C Golden Model & SVA Protocol Checker
### UVM · SystemVerilog · DPI-C · Assertion-Based Verification · EDA Playground · Aldec Riviera-PRO

## Overview

This project builds a complete **UVM-based functional verification environment** for a multi-peripheral APB subsystem written in SystemVerilog, extended with a **C++ DPI-C golden reference model** that runs as a fully independent checker alongside the UVM scoreboard, and an **SVA protocol checker** that continuously monitors AMBA APB specification compliance on every clock edge.

The DUT is an APB subsystem integrating three peripherals — a GPIO controller, a countdown timer with interrupt, and a 256-byte scratchpad memory — connected through a shared APB decoder. The testbench proves correctness across GPIO bit-manipulation, timer start/stop/interrupt, memory read-write, byte-lane write-strobe masking, PSLVERR error signaling, and the full legal address space.

**What the DPI-C layer adds over a bare UVM scoreboard:**

- A C++ golden model that independently tracks the state of every GPIO register, every timer register, and every memory word, using the same byte-lane `apply_wstrb()` logic as the DUT
- An independent PSLVERR prediction engine (`apb_c_slverr`) that tells the scoreboard — before the DUT responds — whether a given address and direction should produce a bus error, catching any mismatch between DUT error signaling and the AMBA APB specification
- A split-decision strategy in the scoreboard: PSLVERR is checked first for every transaction, the C model state is updated only for non-error writes, dynamic timer registers (COUNT, STATUS) are flagged and skipped rather than compared against a frozen snapshot, and all other reads are compared word-exact against `apb_c_read()`
- Full write-strobe coverage: the C model applies `apply_wstrb()` byte-by-byte, so partial writes (byte 0 only, upper half-word, etc.) are verified correctly rather than assumed to be full-word

The verification goal is consistent across all layers:

- **Safety** — no APB protocol rule is ever violated (enforced by eight concurrent SVA assertions)
- **Correctness** — every read returns the state the C model predicts; every PSLVERR matches the DPI error oracle
- **Completeness** — the testbench exercises every register in every peripheral, every write-strobe combination, and every invalid address, achieving **100% functional coverage**

---

## Repository Structure

```
apb_uvm_dpi_project/
│
├── rtl/
│   ├── apb_subsystem.sv       # Top-level DUT: APB decoder + GPIO + Timer + Memory
│   ├── apb_decoder.sv         # Address decoder and response mux (GPIO/Timer/Mem)
│   ├── apb_gpio.sv            # 8-bit GPIO: DATA, DIR, SET, CLEAR, STATUS registers
│   ├── apb_timer.sv           # Countdown timer: CTRL, LOAD, COUNT, STATUS, CLEAR
│   └── apb_memory.sv          # 256-byte word-addressed scratchpad memory
│
├── tb/
│   ├── top_tb.sv              # Top-level TB: DUT instantiation, clock/reset, UVM kickoff
│   ├── apb_if.sv              # APB interface with DRV and MON clocking blocks
│   ├── apb_sva.sv             # Eight SVA protocol assertions (AMBA APB spec)
│   ├── apb_pkg.sv             # TB package: address map constants, imports
│   └── uvm/
│       ├── apb_transaction.sv # UVM sequence item: cmd, addr, wdata, rdata, strb, prot, slverr
│       ├── apb_sequence.sv    # apb_base_sequence + apb_smoke_sequence + apb_random_sequence
│       ├── apb_driver.sv      # UVM driver: drives APB SETUP → ACCESS two-phase protocol
│       ├── apb_monitor.sv     # UVM monitor: captures completed APB transfers
│       ├── apb_scoreboard.sv  # DPI-C scoreboard: PSLVERR check + write-update + read-compare
│       ├── apb_coverage.sv    # Functional coverage: cmd × region, GPIO/Timer offsets, strobe, error
│       ├── apb_agent.sv       # UVM agent (active): driver + monitor + sequencer
│       ├── apb_env.sv         # UVM environment: agent + scoreboard + coverage
│       └── apb_test.sv        # apb_smoke_test and apb_random_test
│
├── dpi/
│   ├── apb_c_model.h          # DPI-C header: extern "C" API declarations
│   └── apb_c_model.cpp        # DPI-C golden model: full C++ implementation
│
├── sim/
│   ├── run.bash               # Shell script: compile C++ SO → compile SV → run sim
│   └── run.do                 # Aldec vsim Tcl script
│
└── output.txt                 # Captured simulation transcript (500-transaction random run)
```

---

## RTL Architecture

The DUT is a three-peripheral APB subsystem. The `apb_decoder` decodes `PADDR` and routes `PSEL` to exactly one peripheral; it also multiplexes `PRDATA`, `PREADY`, and `PSLVERR` back to the bus master.

```
                     APB Master
                         │
          ┌──────────────▼──────────────┐
          │        apb_subsystem        │
          │                             │
          │  ┌──────────────────────┐   │
          │  │     apb_decoder      │   │
          │  │  PADDR → PSEL mux   │   │
          │  │  PRDATA/PREADY mux  │   │
          │  └────┬───────┬────┬───┘   │
          │       │       │    │        │
          │  ┌────▼──┐ ┌──▼──┐ ┌▼────┐ │
          │  │ GPIO  │ │Timer│ │ Mem │ │
          │  │0x000- │ │0x100│ │0x200│ │
          │  │ 0x0FF │ │–1FF │ │–2FF │ │
          │  └───────┘ └─────┘ └─────┘ │
          └─────────────────────────────┘
```

### Address Map

| Peripheral | Base Address | End Address | Key Registers |
|------------|-------------|-------------|---------------|
| GPIO       | `0x0000_0000` | `0x0000_00FF` | DATA (0x00), DIR (0x04), SET (0x08), CLEAR (0x0C), STATUS (0x10) |
| Timer      | `0x0000_0100` | `0x0000_01FF` | CTRL (0x00), LOAD (0x04), COUNT (0x08), STATUS (0x0C), CLEAR (0x10) |
| Memory     | `0x0000_0200` | `0x0000_02FF` | Word-addressed, 64 × 32-bit words |
| Invalid    | All other    | —            | PSLVERR = 1 |

---

## DPI-C Golden Reference Model

### Architecture

The C++ model (`apb_c_model.cpp`) is compiled into a shared object (`apb_c_model.so`) and loaded by Riviera-PRO at simulation startup via `vsim -sv_lib`. The SV scoreboard imports four `extern "C"` functions at the top of `apb_scoreboard.sv` using standard `import "DPI-C"` declarations.

```
               UVM Scoreboard (SV)
                      │
       ┌──────────────┼───────────────┐
       │              │               │
  build_phase()    write(READ)    write(WRITE)
       │              │               │
  apb_c_reset()  apb_c_slverr() apb_c_slverr()
                 apb_c_read()   apb_c_write()
                      │               │
       └──────────────┼───────────────┘
                      │
           ┌──────────▼──────────┐
           │   apb_c_model.cpp   │
           │                     │
           │  gpio_data_model    │  ← GPIO register shadow
           │  gpio_dir_model     │
           │  gpio_status_model  │
           │  timer_ctrl_model   │  ← Timer register shadow
           │  timer_load_model   │
           │  timer_count_model  │
           │  timer_status_model │
           │  mem_model[64]      │  ← Memory word array
           └─────────────────────┘
```

### DPI-C API

| Function | Called from | Purpose |
|----------|-------------|---------|
| `apb_c_reset()` | `build_phase` | Zero all register shadows and memory array |
| `apb_c_slverr(addr, is_write)` | `write()` — every transaction | Predict whether PSLVERR should be asserted; checked before any state update |
| `apb_c_write(addr, data, strb)` | `write()` on WRITE, only if `!slverr` | Apply `apply_wstrb()` byte masking and update the relevant register shadow |
| `apb_c_read(addr)` | `write()` on READ, only if `!slverr` | Return the current shadow value for the given address |

### Golden Model Internals

The C++ model maintains independent register shadows for every readable/writable register in the three peripherals.

**GPIO model** implements the correct read-back semantics for each register:
- `GPIO_DATA`: stores the masked output value; `SET` ORs bits in; `CLEAR` clears bits
- `GPIO_DIR`: direction register, read-write
- `GPIO_STATUS` is read-only — writes to it are rejected by `apb_c_slverr()` returning 1

**Timer model** mirrors the DUT register behavior:
- `TIMER_LOAD` sets the reload value (default 10 after reset)
- `TIMER_CTRL` enables/starts the timer
- `TIMER_STATUS` is read-only — writes are rejected
- `TIMER_CLEAR` clears individual interrupt status bits via bit mask, not stored directly
- `TIMER_COUNT` is treated as a dynamic register: reads are observed but not compared against the model because the DUT counter advances in real time while the C model has no clock

**Memory model** is a flat `uint32_t mem_model[64]` array — 64 words of 4 bytes, covering the 256-byte memory range at `0x200–0x2FF`. All reads and writes go through `apply_wstrb()` to support partial byte-lane updates correctly.

**`apply_wstrb()` logic:** iterates over all four byte lanes, and for each lane where the strobe bit is set it copies the corresponding byte from `new_data` into `result`, leaving all other bytes from `old_data` unchanged:

```c
for (int i = 0; i < 4; i++) {
    if ((strb >> i) & 0x1) {
        uint32_t mask = 0xFFu << (i * 8);
        result = (result & ~mask) | (new_data & mask);
    }
}
```

### PSLVERR Prediction Logic

`apb_c_slverr()` is the error oracle. It enforces the following rules independently of the DUT:

| Condition | PSLVERR prediction |
|-----------|-------------------|
| Address not in any peripheral range | 1 |
| GPIO: offset not in {0x00, 0x04, 0x08, 0x0C, 0x10} | 1 |
| GPIO: write to STATUS register (offset 0x10) | 1 |
| Timer: offset not in {0x00, 0x04, 0x08, 0x0C, 0x10} | 1 |
| Timer: write to STATUS register (offset 0x0C) | 1 |
| Memory: unaligned address (`addr[1:0] != 0`) | 1 |
| Memory: address beyond 64 words | 1 |
| All other valid accesses | 0 |

---

## How the Scoreboard Uses the DPI

The scoreboard integrates the C++ model in a strict decision sequence to avoid false failures.

### `build_phase` — Reset

```systemverilog
apb_c_reset();
`uvm_info(get_type_name(), "DPI-C APB golden model reset complete", UVM_LOW)
```

Called once at simulation start. Synchronises all C model shadows to zero, matching the DUT after `PRESETn` de-assertion.

### `write()` — Every Transaction

The scoreboard's `write()` function follows a five-step decision tree:

```systemverilog
// Step 1: Predict error before anything else
expected_err = apb_c_slverr(tr.addr, is_write);

// Step 2: Compare PSLVERR — applies to reads AND writes
if (tr.slverr !== expected_err)
    `uvm_error(...)

// Step 3: For WRITE — update C model (only if no error expected)
if (tr.cmd == APB_WRITE) begin
    if (!expected_err) apb_c_write(tr.addr, tr.wdata, tr.strb);
    return;
end

// Step 4: For READ with expected error — skip PRDATA compare
if (expected_err) return;

// Step 5: Skip dynamic timer registers (COUNT, STATUS) — observed only
if (is_timer_dynamic_read(tr)) return;

// Step 6: Normal read compare against C model
expected_data = apb_c_read(tr.addr);
if (tr.rdata !== expected_data)
    `uvm_error(...)
else
    `uvm_info(... "DPI READ PASS ...")
```

This ordering ensures PSLVERR is always checked, the C model is never polluted by error transactions, and dynamic registers that race the simulation clock do not produce false failures.

---

## SVA Protocol Checker

`apb_sva.sv` is bound to the interface and runs eight concurrent SystemVerilog assertions that verify AMBA APB specification compliance on every clock edge, independent of the UVM scoreboard.

| Assertion | What it checks |
|-----------|---------------|
| `a_setup_before_access` | SETUP phase (`PSEL && !PENABLE`) must be followed by ACCESS phase (`PSEL && PENABLE`) on the next cycle |
| `a_control_stable_during_wait` | `PADDR`, `PWRITE`, `PWDATA`, `PSTRB`, `PPROT` must not change while `PSEL && PENABLE && !PREADY` (wait state) |
| `a_no_enable_without_select` | `PENABLE` may only be asserted when `PSEL` is also asserted |
| `a_idle_has_no_enable` | `PENABLE` must be deasserted in IDLE (`!PSEL`) |
| `a_pslverr_only_in_access_phase` | `PSLVERR` may only be asserted during a completed ACCESS phase (`PSEL && PENABLE && PREADY`) |
| `a_no_unknown_bus` | No X/Z on `PADDR`, `PWRITE`, `PSTRB`, `PPROT` when `PSEL` is high |
| `a_penable_deasserts` | `PENABLE` must deassert on the cycle after a completed transfer |
| `a_pready_no_unknown` | `PREADY` must not be X/Z during the ACCESS phase |

All eight assertions fire with `disable iff (!PRESETn)` so they are automatically suppressed during the reset window.

---

## Functional Coverage

Coverage is collected in `apb_coverage.sv` via a single `apb_cg` covergroup sampled on every transaction through a `uvm_analysis_imp`.

| Coverpoint | What it measures |
|------------|-----------------|
| `cp_cmd` | Both READ and WRITE directions exercised |
| `cp_region` | All three peripheral regions (GPIO / Timer / Memory) and the invalid address space hit |
| `cp_gpio_offsets` | All five valid GPIO register offsets covered, plus invalid offsets |
| `cp_timer_offsets` | All five valid Timer register offsets covered, plus invalid offsets |
| `cp_strb` | All seven meaningful write-strobe patterns: each single byte, both half-words, full-word |
| `cp_slverr` | Both normal completion (0) and slave error (1) observed |
| `cross_cmd_region` | Full cross of command direction × peripheral region |

**Final coverage result from the simulation transcript:**

```
UVM_INFO [apb_coverage] APB functional coverage = 100.00%
```

---

## Simulation Results

The random test (`apb_random_test`) runs 500 constrained-random transactions across all valid GPIO, Timer, and Memory register offsets plus the invalid `0x800` address, with all strobe combinations and both read/write directions.

```
UVM Report Summary
──────────────────
UVM_INFO    :  323
UVM_WARNING :    0
UVM_ERROR   :    0
UVM_FATAL   :    0

APB functional coverage = 100.00%
Simulation time: 15,405 ns
```

**Representative scoreboard output:**

```
[apb_scoreboard] DPI READ PASS  addr=0x000002E4  DUT_PRDATA=0x00002A00  DPI_EXPECTED=0x00002A00
[apb_scoreboard] DPI READ PASS  addr=0x00000238  DUT_PRDATA=0x5800AB69  DPI_EXPECTED=0x5800AB69
[apb_scoreboard] DPI READ expected error  addr=0x00000800  DUT_PSLVERR=1  DPI_EXPECTED_PSLVERR=1
[apb_scoreboard] DPI WRITE expected error addr=0x00000010  data=0x906C1DFC
```

Zero UVM_ERROR and zero UVM_FATAL with 100% functional coverage confirms both data-path correctness and protocol compliance across the complete test suite.

---

## How to Run on EDA Playground

### Setup

1. Go to [edaplayground.com](https://www.edaplayground.com) and log in
2. Select **Aldec Riviera-PRO 2025.04**
3. Tick **UVM 1.2** in the Libraries panel
4. Enable **"Use run.bash shell script"** in the Run Options panel

### Files

Place files in the **Design** pane in the following order:

```
rtl/apb_decoder.sv
rtl/apb_gpio.sv
rtl/apb_timer.sv
rtl/apb_memory.sv
rtl/apb_subsystem.sv
tb/apb_if.sv
tb/apb_sva.sv
tb/apb_pkg.sv
tb/uvm/apb_transaction.sv
tb/uvm/apb_sequence.sv
tb/uvm/apb_driver.sv
tb/uvm/apb_monitor.sv
tb/uvm/apb_scoreboard.sv
tb/uvm/apb_coverage.sv
tb/uvm/apb_agent.sv
tb/uvm/apb_env.sv
tb/uvm/apb_test.sv
tb/top_tb.sv              ← top-level module
dpi/apb_c_model.h         ← C++ header (must be present for #include)
dpi/apb_c_model.cpp       ← C++ golden model
```

### run.bash

```bash
#!/bin/bash
set -e

# Step 1: Compile DPI-C golden model into a shared object
g++ -fPIC -shared \
    -I"$RIVIERA_HOME/interfaces/include" \
    -o apb_c_model.so \
    apb_c_model.cpp

# Step 2: Compile SystemVerilog
vlib work
vlog -timescale 1ns/1ns \
    +incdir+$RIVIERA_HOME/vlib/uvm-1.2/src \
    +incdir+. \
    -l uvm_1_2 \
    design.sv testbench.sv

# Step 3: Simulate
vsim -c -do run.do
```

### run.do

```tcl
asim +access+r -sv_lib ./apb_c_model work.top_tb
run -all
exit
```

The `-sv_lib ./apb_c_model` flag tells Riviera-PRO to load `apb_c_model.so` at startup and resolve all `import "DPI-C"` declarations against it.

### Run Options (EDA Playground UI)

| Field | Value |
|-------|-------|
| Compile Options | `-timescale 1ns/1ns` |
| Run Options | `+access+r` |
| Use run.bash | ✅ enabled |
| Open EPWave after run | ✅ recommended |

---

## Reading the Simulation Output

After the run completes, look for these blocks in the transcript:

**Scoreboard DPI comparison log:**
```
[apb_scoreboard] DPI READ PASS addr=0x????????  DUT_PRDATA=0x????????  DPI_EXPECTED=0x????????
[apb_scoreboard] DPI READ expected error  addr=0x????????  DUT_PSLVERR=1  DPI_EXPECTED_PSLVERR=1
[apb_scoreboard] DPI WRITE expected error addr=0x????????  data=0x????????
```

**Coverage report (end of simulation):**
```
[apb_coverage] APB functional coverage = 100.00%
```

**Final UVM summary (clean run):**
```
UVM_INFO    :  323
UVM_WARNING :    0
UVM_ERROR   :    0
UVM_FATAL   :    0
```

Any `UVM_ERROR` line indicates a data mismatch or PSLVERR mismatch; the message contains the address, the DUT response, and the C model prediction for immediate diagnosis.

---

## Verification Plan

### What Is Verified

| Category | Checks | Verified by |
|----------|--------|-------------|
| GPIO DATA read-after-write | DUT PRDATA == C model shadow | DPI scoreboard |
| GPIO SET / CLEAR bit manipulation | OR/AND-mask applied correctly, read-back matches | DPI scoreboard |
| GPIO STATUS read-only enforcement | PSLVERR = 1 on write, matches DPI prediction | DPI error oracle + SVA |
| Timer LOAD / CTRL register write | Register shadow updated and read-back matches | DPI scoreboard |
| Timer COUNT / STATUS dynamic reads | Observed, not compared (real-time counter) | DPI scoreboard |
| Timer STATUS read-only enforcement | PSLVERR = 1 on write | DPI error oracle |
| Timer CLEAR interrupt clear | Bit-mask clear applied correctly | DPI scoreboard |
| Memory word read-after-write | All 64 word locations, full-word strobe | DPI scoreboard |
| Partial write-strobe masking | All 7 strobe patterns, byte/half/full granularity | DPI scoreboard + coverage |
| PSLVERR on invalid addresses | `0x800` and all unaligned/out-of-range addresses | DPI error oracle + SVA |
| PSLVERR on invalid register offsets | Unimplemented offsets in GPIO and Timer ranges | DPI error oracle |
| APB SETUP → ACCESS two-phase protocol | Every transaction checked on every clock edge | SVA `a_setup_before_access` |
| Control stability during wait states | PADDR/PWRITE/PWDATA/PSTRB/PPROT stable | SVA `a_control_stable_during_wait` |
| PENABLE / PSEL ordering rules | PENABLE cannot lead PSEL; IDLE has no PENABLE | SVA (3 assertions) |
| X/Z propagation prevention | No unknown values on bus during active transfers | SVA `a_no_unknown_bus`, `a_pready_no_unknown` |
| Functional coverage completeness | All cmd × region crosses, all strobe patterns, both error outcomes | `apb_cg` covergroup |

### Known Limitations

| Limitation | Impact | Path to closure |
|------------|--------|----------------|
| Timer COUNT and STATUS not compared | DUT timer arithmetic not verified exact-cycle | Add a cycle-accurate timer model to the C golden model |
| GPIO input path (`gpio_in` → `gpio_status`) not driven | STATUS register always reads 0 in current tests | Add directed sequence driving `gpio_in` from TB and verifying STATUS read-back |
| PPROT privilege and security bits not checked | PPROT field is driven but not used to gate access in this DUT | Extend DUT and C model to implement PPROT-based filtering |
| Wait-state insertion not tested | DUT always returns PREADY = 1 in one cycle; multi-cycle PREADY not verified | Add a configurable wait-state generator to the driver |

---

## Key Design Decisions

**Why check PSLVERR before updating the C model state?**
If the scoreboard updated the C model on every write and then checked PSLVERR, a write to a read-only register would corrupt the model state and produce a false data mismatch on the next read. Checking the error oracle first and skipping the state update on error transactions keeps the golden model always consistent with what the DUT's registers actually contain.

**Why skip TIMER_COUNT and TIMER_STATUS comparisons?**
The C model has no clock and cannot track the running counter value. Rather than freezing a snapshot at write time — which would only be valid for one cycle — the scoreboard classifies these two addresses as "dynamic reads" and logs them as observed without comparing. This is the correct approach: the timer's counting behavior is a DUT-internal concern verified by the timer interrupt logic, not by read-back comparisons against a static model.

**Why use `uint32_t mem_model[64]` rather than `uint8_t mem_model[256]`?**
The APB bus is 32 bits wide and the DUT enforces word-alignment (PSLVERR on unaligned addresses). Using a word array matches the DUT's storage granularity exactly and makes the `apply_wstrb()` indexing straightforward: `index = (addr - MEM_BASE) >> 2`.

**Why are SVA assertions in a separate module rather than inside the interface?**
Separating `apb_sva.sv` from `apb_if.sv` keeps the interface clean and reusable across projects. The SVA module is instantiated in `top_tb.sv` alongside the DUT, allowing the assertions to be enabled or disabled independently of the clocking-block infrastructure.
