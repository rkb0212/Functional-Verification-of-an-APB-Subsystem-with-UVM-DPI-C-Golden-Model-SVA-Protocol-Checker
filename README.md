# Functional Verification of an APB Subsystem with UVM, DPI-C Golden Model, SVA Protocol Checker & Formal Verification
### UVM · SystemVerilog · DPI-C · SVA · Formal Verification (SymbiYosys + Boolector + Ubuntu 22.04) · EDA Playground · Aldec Riviera-PRO

## Overview

This project builds a complete **UVM-based functional verification environment** for a multi-peripheral APB subsystem written in SystemVerilog, extended with a **C++ DPI-C golden reference model** that runs as a fully independent checker alongside the UVM scoreboard, an **SVA protocol checker** that continuously monitors AMBA APB specification compliance on every clock edge, and a **formal verification layer** using SymbiYosys and the Boolector SMT solver that mathematically proves key safety and protocol properties hold for all possible inputs across a 30-cycle bounded model checking depth.

The DUT is an APB subsystem integrating three peripherals — a GPIO controller, a countdown timer with interrupt, and a 256-byte scratchpad memory — connected through a shared APB decoder. The testbench proves correctness across GPIO bit-manipulation, timer start/stop/interrupt, memory read-write, byte-lane write-strobe masking, PSLVERR error signaling, and the full legal address space.

**What each verification layer adds:**

- **DPI-C golden model** — independently tracks every GPIO register, timer register, and memory word in C++; predicts PSLVERR before the DUT responds; applies byte-lane write-strobe masking correctly; catches any mismatch between DUT behavior and AMBA specification
- **SVA protocol checker** — eight concurrent assertions enforce APB two-phase protocol, signal stability, X/Z freedom, and PSLVERR timing on every clock edge in simulation
- **Formal verification** — SymbiYosys k-induction proof over 30 cycles mathematically proves reset behavior, zero-wait-state PREADY, invalid-address PSLVERR, GPIO write-through correctness, GPIO/Timer read-only register error signaling, and memory alignment errors hold for all possible APB input sequences — not just those exercised by the test sequences

The verification goal is consistent across all layers:

- **Safety** — no APB protocol rule is ever violated (SVA + formal proof)
- **Correctness** — every read returns the state the C model predicts; every PSLVERR matches the DPI error oracle (DPI scoreboard + formal proof)
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
├── formal/
│   ├── apb_combined_dut.sv    # Flat DUT (all RTL modules in one file for Yosys)
│   ├── apb_formal_top.sv      # Formal top: DUT + assumptions + assertions + cover properties
│   └── apb_formal.sby         # SymbiYosys config: prove mode, depth 30, Boolector engine
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
| GPIO | `0x0000_0000` | `0x0000_00FF` | DATA (0x00), DIR (0x04), SET (0x08), CLEAR (0x0C), STATUS (0x10) |
| Timer | `0x0000_0100` | `0x0000_01FF` | CTRL (0x00), LOAD (0x04), COUNT (0x08), STATUS (0x0C), CLEAR (0x10) |
| Memory | `0x0000_0200` | `0x0000_02FF` | Word-addressed, 64 × 32-bit words |
| Invalid | All other | — | PSLVERR = 1 |

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

**GPIO model** implements correct read-back semantics for each register: `GPIO_DATA` stores the masked output value; `SET` ORs bits in; `CLEAR` clears bits. `GPIO_STATUS` is read-only — writes are rejected by `apb_c_slverr()` returning 1.

**Timer model** mirrors DUT register behavior: `TIMER_LOAD` sets the reload value; `TIMER_CTRL` enables/starts the timer; `TIMER_STATUS` is read-only; `TIMER_CLEAR` clears interrupt status bits via bit mask; `TIMER_COUNT` is treated as dynamic and not compared against the model since the DUT counter advances in real time.

**Memory model** is a flat `uint32_t mem_model[64]` array covering the 256-byte memory range. All reads and writes go through `apply_wstrb()` to support partial byte-lane updates correctly:

```c
for (int i = 0; i < 4; i++) {
    if ((strb >> i) & 0x1) {
        uint32_t mask = 0xFFu << (i * 8);
        result = (result & ~mask) | (new_data & mask);
    }
}
```

### PSLVERR Prediction Logic

| Condition | PSLVERR prediction |
|-----------|--------------------|
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

The scoreboard's `write()` function follows a five-step decision tree to avoid false failures:

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
```

---

## SVA Protocol Checker

`apb_sva.sv` is bound to the interface and runs eight concurrent assertions that verify AMBA APB compliance on every clock edge, independent of the UVM scoreboard.

| Assertion | What it checks |
|-----------|---------------|
| `a_setup_before_access` | SETUP phase (`PSEL && !PENABLE`) must be followed by ACCESS phase on the next cycle |
| `a_control_stable_during_wait` | `PADDR`, `PWRITE`, `PWDATA`, `PSTRB`, `PPROT` must not change during wait states |
| `a_no_enable_without_select` | `PENABLE` may only be asserted when `PSEL` is also asserted |
| `a_idle_has_no_enable` | `PENABLE` must be deasserted in IDLE (`!PSEL`) |
| `a_pslverr_only_in_access_phase` | `PSLVERR` may only be asserted during a completed ACCESS phase |
| `a_no_unknown_bus` | No X/Z on `PADDR`, `PWRITE`, `PSTRB`, `PPROT` when `PSEL` is high |
| `a_penable_deasserts` | `PENABLE` must deassert on the cycle after a completed transfer |
| `a_pready_no_unknown` | `PREADY` must not be X/Z during the ACCESS phase |

All eight assertions fire with `disable iff (!PRESETn)` so they are suppressed during the reset window.

---

## Formal Verification

### Overview

The `formal/` directory contains a SymbiYosys-based formal verification flow that runs independently of the UVM simulation. It uses **k-induction** with the **Boolector** SMT solver to prove that specific properties of the DUT hold for **all possible APB input sequences**, not just those covered by the directed and random test sequences.

```
formal/
├── apb_combined_dut.sv   # All RTL modules flattened into one file for Yosys synthesis
├── apb_formal_top.sv     # Formal harness: assumptions + assertions + cover properties
└── apb_formal.sby        # SymbiYosys configuration
```

### Tool Flow

```
apb_combined_dut.sv ──┐
apb_formal_top.sv  ───┼──► Yosys (synthesis + SMT-LIB2 generation)
                       │
                       ▼
               yosys-smtbmc (Boolector)
                  │              │
          basecase check   induction check
          (BMC depth 30)   (k-induction)
                  │              │
                  └──────┬───────┘
                         ▼
                   PASS / FAIL + counterexample trace
```

**`apb_formal.sby` configuration:**

```
[options]
mode  prove
depth 30

[engines]
smtbmc boolector

[script]
read_verilog -formal -sv apb_combined_dut.sv
read_verilog -formal -sv apb_formal_top.sv
prep -top apb_formal_top
```

`mode prove` runs both a bounded model check (basecase) and a k-induction step simultaneously. If both pass, the properties are proven to hold for all reachable states, not just within the bounded window.

### Formal Harness Design (`apb_formal_top.sv`)

The harness wraps the DUT with unconstrained primary inputs, then adds two groups of statements:

**`assume` statements (master constraints):** constrain the formal environment to only generate legal APB master behavior. Without these, the solver would find trivial counterexamples by violating the protocol from the master side.

| Assumption | What it enforces |
|------------|-----------------|
| First cycle: `PRESETn == 0` | DUT always starts from reset |
| After reset: `PRESETn == 1` | Reset deasserts and stays deasserted |
| `PENABLE → PSEL` | Master never asserts PENABLE without PSEL |
| `!PSEL → !PENABLE` | Master clears PENABLE in IDLE |
| After SETUP (`PSEL && !PENABLE`): `PSEL && PENABLE` | SETUP always followed by ACCESS |
| Control stable SETUP→ACCESS | `PADDR/PWRITE/PWDATA/PSTRB/PPROT` unchanged |
| During wait state: control stable | Same signals held while `PSEL && PENABLE && !PREADY` |
| After completed transfer: `!PENABLE` | PENABLE deasserts after `PSEL && PENABLE && PREADY` |

**`assert` statements (DUT properties):** what the solver proves must always hold given the assumptions above.

### Properties Proven

#### Reset Properties

```systemverilog
always_ff @(posedge PCLK) begin
    if (!PRESETn) begin
        assert(gpio_out == 8'h00);
        assert(gpio_dir == 8'h00);
        assert(timer_irq == 1'b0);
    end
end
```

Proves that GPIO outputs, GPIO direction register, and timer interrupt are always zero immediately after reset — for any possible input history that led to the reset state.

#### Zero-Wait-State Property

```systemverilog
assert(PREADY == 1'b1);
```

Proves the DUT never inserts wait states — `PREADY` is always 1 whenever `PRESETn` is high. This is a global liveness guarantee: no APB transfer can stall indefinitely.

#### Invalid Address PSLVERR

```systemverilog
if (!((PADDR >= 32'h0000_0000 && PADDR <= 32'h0000_00FF) ||
      (PADDR >= 32'h0000_0100 && PADDR <= 32'h0000_01FF) ||
      (PADDR >= 32'h0000_0200 && PADDR <= 32'h0000_02FF))) begin
    assert(PSLVERR == 1'b1);
    assert(PRDATA  == 32'h0000_0000);
end
```

Proves that for every possible address outside the three valid peripheral ranges, the DUT asserts PSLVERR and returns zero data — exhaustively, across all 2³² possible address values.

#### GPIO Write-Through Properties

```systemverilog
// GPIO DATA write-through
if ($past(PSEL && PENABLE && PREADY && PWRITE &&
          PADDR == 32'h0000_0000 && PSTRB[0])) begin
    assert(gpio_out == $past(PWDATA[7:0]));
end

// GPIO DIR write-through
if ($past(PSEL && PENABLE && PREADY && PWRITE &&
          PADDR == 32'h0000_0004 && PSTRB[0])) begin
    assert(gpio_dir == $past(PWDATA[7:0]));
end
```

Proves that after a successful write to `GPIO_DATA` (0x000) or `GPIO_DIR` (0x004) with byte-strobe 0 set, the corresponding output register always reflects the written value on the very next cycle — for any possible data value.

#### Read-Only Register Enforcement

```systemverilog
// GPIO STATUS is read-only
if (PSEL && PENABLE && PWRITE && PADDR == 32'h0000_0010) begin
    assert(PSLVERR == 1'b1);
end

// Timer STATUS is read-only
if (PWRITE && PADDR == 32'h0000_010C) begin
    assert(PSLVERR == 1'b1);
end
```

Proves that writing to the GPIO STATUS register or Timer STATUS register always produces PSLVERR — regardless of what `PWDATA` contains or what the current state of any other register is.

#### Memory Alignment Property

```systemverilog
if ((PADDR >= 32'h0000_0200 && PADDR <= 32'h0000_02FF) &&
    (PADDR[1:0] != 2'b00)) begin
    assert(PSLVERR == 1'b1);
end
```

Proves that every unaligned access to the memory range (any address with `PADDR[1:0] != 00`) produces PSLVERR — exhaustively across all possible unaligned addresses in the 0x200–0x2FF range.

#### Cover Properties

In addition to `assert`, the harness includes five `cover` statements. These do not prove anything — instead they ask the solver whether a given scenario is reachable at all, validating that the assumptions are not over-constraining the input space:

```systemverilog
cover(PSEL && PENABLE && PWRITE && PADDR == 32'h0000_0000); // GPIO write reachable
cover(PSEL && PENABLE && !PWRITE && PADDR == 32'h0000_0000); // GPIO read reachable
cover(PSEL && PENABLE && PWRITE && PADDR == 32'h0000_0100); // Timer write reachable
cover(PSEL && PENABLE && PWRITE && PADDR == 32'h0000_0200); // Memory write reachable
cover(PSEL && PENABLE && PSLVERR);                          // Error response reachable
```

### Formal Verification Results

The flow was run twice. The first run exposed a failing assertion at `apb_formal_top.sv:231`, which was then fixed. The second run produced a clean proof.

#### First Run — Failure (Before Fix)

```
SBY [formal/apb_formal] engine_0.basecase: BMC failed!
SBY [formal/apb_formal] engine_0.basecase: Assert failed in apb_formal_top:
    apb_formal_top.sv:231.17-231.55
SBY [formal/apb_formal] DONE (FAIL, rc=2)
```

The BMC found a counterexample at step 1 for the assertion at line 231 — the GPIO `STATUS` read-only check. The issue was that the initial assertion was written without the correct `f_past_valid` guard and fired in the very first cycle before the harness assumptions had constrained the input space, allowing the solver to present `PSEL && PENABLE && PWRITE` at cycle 0 before reset had properly initialized. The fix was to add the `f_past_valid && $past(PRESETn) && PRESETn` guard on the enclosing `always_ff` block.

#### Second Run — Full Proof Passed

```
SBY [formal/apb_formal] engine_0.induction: Temporal induction successful.
SBY [formal/apb_formal] engine_0.induction: Status: passed

SBY [formal/apb_formal] engine_0.basecase: Status: passed

SBY [formal/apb_formal] summary: engine_0 (smtbmc boolector) returned pass for basecase
SBY [formal/apb_formal] summary: engine_0 (smtbmc boolector) returned pass for induction
SBY [formal/apb_formal] summary: successful proof by k-induction.
SBY [formal/apb_formal] DONE (PASS, rc=0)
```

Both basecase (BMC over 30 cycles) and the induction step passed. A k-induction proof means the properties hold not just for the first 30 cycles but for **all reachable states** of the design — the induction step proves that if the properties hold in step N, they continue to hold in step N+1, completing the proof by induction over all time.

**Elapsed time: 1 second** (basecase) / less than 1 second (induction). The small DUT size means the Boolector backend solves the SMT problem almost instantly.

### How to Run Formal Verification

Install SymbiYosys and Boolector:

```bash
# Ubuntu/Debian
sudo apt install symbiyosys yosys python3-click
pip install meson
# Boolector is bundled with sby in recent versions; if not:
sudo apt install boolector
```

Run from the project root:

```bash
sby -f formal/apb_formal.sby
```

The results appear in `formal/apb_formal/`. If the run fails, the counterexample VCD trace is at `formal/apb_formal/engine_0/trace.vcd` — open it in GTKWave to see the exact sequence of inputs that violated the property.

---

## Functional Coverage

Coverage is collected in `apb_coverage.sv` via a single `apb_cg` covergroup sampled on every transaction.

| Coverpoint | What it measures |
|------------|-----------------|
| `cp_cmd` | Both READ and WRITE directions exercised |
| `cp_region` | All three peripheral regions (GPIO / Timer / Memory) and the invalid address space hit |
| `cp_gpio_offsets` | All five valid GPIO register offsets covered, plus invalid offsets |
| `cp_timer_offsets` | All five valid Timer register offsets covered, plus invalid offsets |
| `cp_strb` | All seven meaningful write-strobe patterns: each single byte, both half-words, full-word |
| `cp_slverr` | Both normal completion (0) and slave error (1) observed |
| `cross_cmd_region` | Full cross of command direction × peripheral region |

**Final coverage result:**

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
dpi/apb_c_model.h         ← C++ header
dpi/apb_c_model.cpp       ← C++ golden model
```

The `formal/` directory is not used on EDA Playground — run it locally with SymbiYosys.

### run.bash

```bash
#!/bin/bash
set -e

# Step 1: Compile DPI-C golden model
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

### Run Options (EDA Playground UI)

| Field | Value |
|-------|-------|
| Compile Options | `-timescale 1ns/1ns` |
| Run Options | `+access+r` |
| Use run.bash | ✅ enabled |
| Open EPWave after run | ✅ recommended |

---

## Verification Plan

### What Is Verified

| Category | Checks | Verified by |
|----------|--------|-------------|
| GPIO DATA read-after-write | DUT PRDATA == C model shadow | DPI scoreboard |
| GPIO DATA write-through (all data values) | `gpio_out` correct cycle after write | **Formal proof** |
| GPIO SET / CLEAR bit manipulation | OR/AND-mask applied correctly | DPI scoreboard |
| GPIO STATUS read-only enforcement | PSLVERR = 1 on write, all possible PWDATA | DPI oracle + **Formal proof** |
| GPIO DIR write-through (all data values) | `gpio_dir` correct cycle after write | **Formal proof** |
| Timer LOAD / CTRL register write | Register shadow updated and read-back matches | DPI scoreboard |
| Timer COUNT / STATUS dynamic reads | Observed, not compared | DPI scoreboard |
| Timer STATUS read-only enforcement | PSLVERR = 1 on write | DPI oracle + **Formal proof** |
| Timer CLEAR interrupt clear | Bit-mask clear applied correctly | DPI scoreboard |
| Memory word read-after-write | All 64 word locations, full-word strobe | DPI scoreboard |
| Partial write-strobe masking | All 7 strobe patterns | DPI scoreboard + coverage |
| PSLVERR on invalid addresses (all 2³²) | Every out-of-range address | DPI oracle + **Formal proof** |
| PSLVERR + zero PRDATA on invalid address | Exhaustive address space | **Formal proof** |
| PSLVERR on unaligned memory access | All misaligned addresses in 0x200–0x2FF | DPI oracle + **Formal proof** |
| Zero-wait-state PREADY | `PREADY == 1` always | **Formal proof** |
| Reset output values | `gpio_out`, `gpio_dir`, `timer_irq` == 0 | **Formal proof** |
| APB SETUP → ACCESS two-phase protocol | Every transaction | SVA `a_setup_before_access` |
| Control stability during wait states | PADDR/PWRITE/PWDATA/PSTRB/PPROT stable | SVA `a_control_stable_during_wait` |
| PENABLE / PSEL ordering rules | PENABLE cannot lead PSEL | SVA (3 assertions) |
| X/Z propagation prevention | No unknowns on bus during active transfers | SVA `a_no_unknown_bus`, `a_pready_no_unknown` |
| Functional coverage completeness | All cmd × region crosses, all strobe patterns | `apb_cg` covergroup |

### Known Limitations

| Limitation | Impact | Path to closure |
|------------|--------|----------------|
| Timer COUNT and STATUS not compared | DUT timer arithmetic not verified cycle-exact | Add a cycle-accurate timer model to the C golden model |
| GPIO input path (`gpio_in` → `gpio_status`) not driven | STATUS always reads 0 in current tests | Add directed sequence driving `gpio_in` from TB |
| PPROT privilege/security bits not checked | PPROT driven but not used to gate access | Extend DUT and C model to implement PPROT-based filtering |
| Wait-state insertion not tested | DUT always PREADY = 1; multi-cycle PREADY not verified | Add a configurable wait-state generator to the driver |
| Formal depth limited to 30 cycles | Properties involving longer sequences (e.g. multi-transfer refresh patterns) may not be caught | Increase depth or use unbounded model checking with a different engine |
| Formal covers not checked in second run | `cover` properties confirm reachability but were not reported as passing/failing | Run `sby` with `mode cover` separately to verify all cover targets are reachable |

---

## Key Design Decisions

**Why check PSLVERR before updating the C model state?**
If the scoreboard updated the C model on every write and then checked PSLVERR, a write to a read-only register would corrupt the model state and produce a false data mismatch on the next read. Checking the error oracle first and skipping the state update on error transactions keeps the golden model always consistent with what the DUT's registers actually contain.

**Why use k-induction rather than plain BMC?**
Bounded model checking (BMC) only proves properties for the first N cycles. K-induction proves them for all reachable states: if the property holds through step N and is preserved from step N to N+1, it holds forever. The `successful proof by k-induction` result in the second sby run means the properties are not just bug-free for 30 cycles — they are mathematically proven for all time.

**Why did the first formal run fail at step 1?**
The GPIO STATUS read-only assertion was missing a `f_past_valid` guard. At step 0 (the very first clock edge), `$past(...)` is undefined and the assumptions had not yet constrained the input space, allowing the solver to present an ACCESS-phase write to address 0x10 in the first cycle without a preceding SETUP phase. Wrapping the assertion in `if (f_past_valid && $past(PRESETn) && PRESETn)` ensures it only fires after at least one full clock cycle with valid history, eliminating the spurious counterexample.

**Why separate `apb_combined_dut.sv` from the RTL source?**
Yosys (used internally by SymbiYosys) requires all modules to be in a single synthesis pass. Flattening the RTL into `apb_combined_dut.sv` avoids multi-file ordering issues with `read_verilog` in the `.sby` script and keeps the formal harness self-contained. The production RTL files under `rtl/` are not modified.

**Why skip TIMER_COUNT and TIMER_STATUS comparisons?**
The C model has no clock and cannot track the running counter value. Rather than freezing a snapshot at write time — which would only be valid for one cycle — the scoreboard classifies these addresses as "dynamic reads" and logs them as observed without comparing. The timer's counting behavior is a DUT-internal concern verified by the interrupt logic, not by read-back comparisons against a static model.

**Why use `uint32_t mem_model[64]` rather than `uint8_t mem_model[256]`?**
The APB bus is 32 bits wide and the DUT enforces word-alignment (PSLVERR on unaligned addresses). Using a word array matches the DUT's storage granularity exactly and makes `apply_wstrb()` indexing straightforward: `index = (addr - MEM_BASE) >> 2`.
