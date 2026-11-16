# Direct-Mapped Cache Controller
**Team ByteMe · Section D**
> [!Important]
> ##  Project Video
> **Watch the project demo video on Google Drive:**
> ### 👉 [**Open the Project Video (Google Drive)**](https://drive.google.com/file/d/1jduN_4kAap_2NAUFFYbR0nafiKiM6ZxO/view?usp=sharing)
A synthesizable Verilog implementation of a 1 KB Direct-Mapped Cache Controller with 16-byte cache blocks and 32-bit addressing.

## Cache Architecture and Parameters

- **Total Capacity:** 1,024 bytes (1 KB)
- **Block Size:** 16 bytes (128 bits, 4 words)
- **Number of Lines:** 64
- **Address Width:** 32 bits
- **Word Width:** 32 bits (4 words per block)
- **Address Breakdown:**
  - **Tag (`address[31:10]`):** 22 bits
  - **Index (`address[9:4]`):** 6 bits
  - **Word Offset (`address[3:2]`):** 2 bits
  - **Byte Offset (`address[1:0]`):** 2 bits

---

## Member Contributions & Modules

### Member 1 — Decoding and Tag Comparison
- **`rtl/address_decoder.v`**: Combinational decoding of 32-bit address into `tag` [21:0], `index` [5:0], `word_offset` [1:0], `byte_offset` [1:0], and 16-byte aligned `block_address` [31:0].
- **`rtl/tag_comparator.v`**: Valid-gated equality comparator producing `hit = valid && (requested_tag == stored_tag)`.

### Member 2 — Cache Storage
Implements the primary storage structures for data blocks, tags, and line validity. All storage modules use the common 6-bit `index` to select a cache line.

#### 1. Data RAM (`rtl/cache_data_ram.v`)
- **Storage:** 64 cache lines, each 128 bits wide.
- **Write:** Synchronous write on `posedge clk` when `write_enable` is asserted. Writes all 128 bits of `write_data`.
- **Read:** Combinational read selecting a 32-bit word using `word_offset`.
- **Word Ordering:**
  - `word_offset = 2'b00` → `read_data = line_data[31:0]`
  - `word_offset = 2'b01` → `read_data = line_data[63:32]`
  - `word_offset = 2'b10` → `read_data = line_data[95:64]`
  - `word_offset = 2'b11` → `read_data = line_data[127:96]`
- **Ports:**
  - `clk` (input, 1 bit): Clock signal
  - `index` (input, 6 bits): Cache line select (0–63)
  - `word_offset` (input, 2 bits): Selects 32-bit word within the line
  - `read_data` (output, 32 bits): Selected 32-bit word
  - `write_enable` (input, 1 bit): Active-high block write enable
  - `write_data` (input, 128 bits): Full 128-bit block from refill

#### 2. Tag RAM (`rtl/tag_ram.v`)
- **Storage:** 64 tag entries, each 22 bits wide.
- **Write:** Synchronous write on `posedge clk` when `write_enable` is asserted. Updates the 22-bit tag on refill completion.
- **Read:** Combinational read of `read_tag` corresponding to `index`.
- **Ports:**
  - `clk` (input, 1 bit): Clock signal
  - `index` (input, 6 bits): Cache line select (0–63)
  - `read_tag` (output, 22 bits): Stored tag for current index
  - `write_enable` (input, 1 bit): Active-high tag write enable
  - `write_tag` (input, 22 bits): New tag to store

#### 3. Valid Bit RAM (`rtl/valid_bit_ram.v`)
- **Storage:** 64 entries of 1-bit validity indicators.
- **Reset:** Active-high `reset` clears all 64 valid bits to 0.
- **Write:** Synchronous write on `posedge clk` when `write_enable` is asserted. Sets (`write_valid = 1`) or invalidates/clears (`write_valid = 0`) the selected line.
- **Read:** Combinational read of `valid_bit` corresponding to `index`.
- **Ports:**
  - `clk` (input, 1 bit): Clock signal
  - `reset` (input, 1 bit): Active-high reset clearing all valid bits
  - `index` (input, 6 bits): Cache line select (0–63)
  - `valid_bit` (output, 1 bit): Valid status for current index
  - `write_enable` (input, 1 bit): Active-high valid bit write enable
  - `write_valid` (input, 1 bit): Valid state to write (1 = valid, 0 = invalid)

---

### Member 3 — Controller FSM

- **Module:** `rtl/cache_controller.v`
- **Testbench:** `tb/tb_member3.v`
- **Functionality:** Manages the entire cache access lifecycle by integrating Member 1 (`address_decoder`, `tag_comparator`) and Member 2 (`cache_data_ram`, `tag_ram`, `valid_bit_ram`). Handles CPU request latching, cache lookup, single-cycle hit response, miss detection, 16-byte-aligned memory refill with variable latency, atomic line updates, and CPU stall management.

#### FSM States (7 States)
- **`S_IDLE` (`3'b000`):** Ready state. Latches incoming `cpu_addr` on `cpu_req` when not stalled; advances to `S_LOOKUP`.
- **`S_LOOKUP` (`3'b001`):** Decodes latched address, reads storage RAMs, and evaluates `cache_hit`. Branches to `S_HIT_RESPONSE` on hit or `S_MISS_REQUEST` on miss.
- **`S_HIT_RESPONSE` (`3'b010`):** Returns requested 32-bit word, asserts `cpu_ready = 1` for 1 cycle, and returns to `S_IDLE`. Zero memory requests generated.
- **`S_MISS_REQUEST` (`3'b011`):** Generates single-cycle `mem_req` strobe with 16-byte-aligned `mem_addr`. Transitions to `S_REFILL` if `mem_ready` is immediate, otherwise to `S_WAIT_MEMORY`.
- **`S_WAIT_MEMORY` (`3'b100`):** Deasserts `mem_req = 0` to prevent duplicate commands. Stalls CPU (`cpu_stall = 1`) and waits for `mem_ready`.
- **`S_REFILL` (`3'b101`):** Synchronously writes 128-bit block, tag, and valid bit into RAMs at the cache index. Extracts requested 32-bit word.
- **`S_MISS_RESPONSE` (`3'b110`):** Delivers refilled 32-bit word, asserts `cpu_ready = 1` for 1 cycle, and returns to `S_IDLE`.

#### Module Interface

| Signal | Direction | Width | Description |
|---|:---:|:---:|---|
| `clk` | Input | 1 bit | Master clock (posedge active) |
| `reset` | Input | 1 bit | Active-high asynchronous reset |
| `cpu_req` | Input | 1 bit | CPU memory read request |
| `cpu_addr` | Input | 32 bits | CPU byte address |
| `cpu_data` | Output | 32 bits | 32-bit data word returned to CPU |
| `cpu_ready` | Output | 1 bit | Active-high 1-cycle response strobe |
| `cpu_stall` | Output | 1 bit | Active-high stall signal (`state != S_IDLE`) |
| `mem_req` | Output | 1 bit | Active-high 1-cycle main memory request strobe |
| `mem_addr` | Output | 32 bits | 16-byte aligned block address (`{addr[31:4], 4'b0000}`) |
| `mem_ready` | Input | 1 bit | Main memory data valid indicator |
| `mem_data` | Input | 128 bits | 128-bit block returned from main memory |

---

### Member 4 — Main-Memory Interface and Model

- **Modules:**
  - `rtl/main_memory_interface.v` (Synthesizable 32-bit burst refill interface)
  - `rtl/main_memory_model.v` (Simulation-only behavioral backing memory model)
- **Testbench:** `tb/tb_member4.v`
- **Functionality:** Implements the main-memory subsystem responsible for servicing cache line refills. Accepts the cache controller's 1-cycle active-high `mem_req` strobe and 16-byte aligned `mem_addr`, fetches four consecutive 32-bit words sequentially over a 32-bit read interface from the memory model, and assembles the full 128-bit cache refill block. Delivers a clean, single-cycle `mem_ready` strobe with stable data to `cache_controller.v`.

#### Architecture & Handshake Protocol

```
+--------------------+                       +------------------------+                       +---------------------+
|                    |  mem_req (1-cycle)    |                        |  model_req (1-cycle)  |                     |
|                    | --------------------> |                        | --------------------> |                     |
|  cache_controller  |  mem_addr [31:0]      | main_memory_interface  |  model_addr [31:0]    |  main_memory_model  |
|                    | --------------------> |   (4-word assembler)   | --------------------> |  (behavioral store) |
|                    |  mem_ready (1-cycle)  |                        |  model_ready (1-cycle)|                     |
|                    | <-------------------- |                        | <-------------------- |                     |
|                    |  mem_data [127:0]     |                        |  model_data [31:0]    |                     |
|                    | <-------------------- |                        | <-------------------- |                     |
+--------------------+                       +------------------------+                       +---------------------+
```

#### Exact Word Ordering (Verified from RTL)
- `mem_data[31:0]`   = Word 0 at `block_addr + 0`  (`word_offset = 2'b00`)
- `mem_data[63:32]`  = Word 1 at `block_addr + 4`  (`word_offset = 2'b01`)
- `mem_data[95:64]`  = Word 2 at `block_addr + 8`  (`word_offset = 2'b10`)
- `mem_data[127:96]` = Word 3 at `block_addr + 12` (`word_offset = 2'b11`)
- Combined 128-bit literal: `mem_data = {Word 3, Word 2, Word 1, Word 0}`

#### Latency Semantics & Handshake Resolution
- **Memory Model Latency:** Parameterizable via `DEFAULT_LATENCY` and dynamically configurable via `set_latency(N)`.
  - `latency = 0`: Immediate combinational response (`ready = req`, zero wait states). Interface captures each word in 1 clock cycle (4 cycles total fetch + 1 cycle response = 5 cycles).
  - `latency = 1`: 1 wait-state per word (2 cycles per word, 9 cycles total).
  - `latency = 5`: 5 wait-states per word (6 cycles per word, 25 cycles total).
  - `latency = 10`: 10 wait-states per word (11 cycles per word, 45 cycles total).
- **Zero-Latency Handshake Compatibility:** The interface pulses `model_req` for 1 cycle per word and advances synchronously at each rising clock edge where `model_ready` is sampled high. `cache_controller.v` waits in `S_WAIT_MEMORY` with `cpu_stall = 1` until `main_memory_interface` completes the 4-word assembly and pulses `mem_ready = 1`, ensuring 100% glitch-free compatibility across all latencies.

#### Module Interface: `main_memory_interface`

| Signal | Direction | Width | Description |
|---|:---:|:---:|---|
| `clk` | Input | 1 bit | Master clock (posedge active) |
| `reset` | Input | 1 bit | Active-high asynchronous reset |
| `mem_req` | Input | 1 bit | Active-high 1-cycle request strobe from `cache_controller` |
| `mem_addr` | Input | 32 bits | 16-byte aligned block address from `cache_controller` |
| `mem_ready` | Output | 1 bit | Active-high 1-cycle data valid strobe to `cache_controller` |
| `mem_data` | Output | 128 bits | Assembled 128-bit cache refill block `{Word3, Word2, Word1, Word0}` |
| `model_req` | Output | 1 bit | Active-high 1-cycle read request strobe to memory model per word |
| `model_addr` | Output | 32 bits | 32-bit word-aligned address driven to memory model |
| `model_ready` | Input | 1 bit | Active-high data valid strobe from memory model |
| `model_data` | Input | 32 bits | 32-bit word returned from memory model |

---

### Member 5 — Top-Level Integration and Verification

- **RTL:** `rtl/cache_top.v` (synthesizable top level)
- **Testbench:** `tb/tb_cache_top.v`
- **Traces:** `traces/{sequential,random,repeated,conflict}.trace`, generated by `scripts/gen_traces.py`
- **Synthesis scripts:** `synth/synth_generic.ys` (technology-independent), `synth/synth_xc7.ys` (Xilinx 7-series)

#### Top-Level Structure

```
                 +-------------------------------- cache_top ---------------------------------+
  cpu_req   ---->|  +----------------------+   blk_req, blk_addr   +-----------------------+  |
  cpu_addr  ---->|  |   cache_controller   | --------------------> | main_memory_interface |  |
  cpu_data  <----|  | (M3; M1 decoder and  |                       |  (M4; 4-word refill   |  |
  cpu_ready <----|  |  comparator, M2 RAMs)| <-------------------- |   block assembler)    |  |
  cpu_stall <----|  +----------------------+  blk_ready, blk_data  +-----------------------+  |
                 |                                (128-bit)              |          ^         |
                 +-------------------------------------------------------|----------|---------+
                                                    mem_word_req, addr   v          |  mem_word_ready, data (32-bit)
                                                                   +-------------------------+
                                                                   |    main_memory_model    |
                                                                   | (M4; sim only, in TB)   |
                                                                   +-------------------------+
```

`cache_top` contains only synthesizable logic. The simulation-only `main_memory_model` is attached to the 32-bit `mem_word_*` port by the testbench, so any backing memory can be connected in hardware.

| Signal | Direction | Width | Description |
|---|:---:|:---:|---|
| `clk` | Input | 1 bit | Master clock (posedge active) |
| `reset` | Input | 1 bit | Active-high asynchronous reset (clears all valid bits) |
| `cpu_req` | Input | 1 bit | Read request; accepted on a rising edge with `cpu_stall = 0` |
| `cpu_addr` | Input | 32 bits | CPU byte address (latched on acceptance) |
| `cpu_data` | Output | 32 bits | Returned word, valid while `cpu_ready = 1` |
| `cpu_ready` | Output | 1 bit | 1-cycle response strobe, exactly one per accepted request |
| `cpu_stall` | Output | 1 bit | High from acceptance until the response |
| `mem_word_req` | Output | 1 bit | 1-cycle read strobe per word to backing memory |
| `mem_word_addr` | Output | 32 bits | Word-aligned byte address |
| `mem_word_ready` | Input | 1 bit | Word valid strobe from backing memory |
| `mem_word_data` | Input | 32 bits | Word returned by backing memory |

**CPU protocol:** the CPU holds `cpu_req` high until it is accepted, then drops it (a high `cpu_req` while the controller is idle counts as a new request). The controller works from its latched copy of the address, so `cpu_addr` may change once the request is accepted.

#### Traces

`scripts/gen_traces.py` writes one line per read: `<address> <expected data> <expected hit 1/0>`. Expected data comes from the documented memory-model pattern; expected hits come from an independent Python model of a 64-line, 16-byte-block direct-mapped cache that starts empty. Output is deterministic (fixed seed), and regenerating with `make traces` gives identical files.

| Trace | Requests | Content | Expected hit ratio |
|---|:---:|---|:---:|
| `sequential` | 512 | Word-by-word sweep over 2 KB (twice the cache size) | 75.00 % |
| `random` | 512 | Random byte addresses (including unaligned) in a 4 KB window | 21.88 % |
| `repeated` | 512 | Four passes over a 512-byte array that fits in the cache | 93.75 % |
| `conflict` | 144 | Same-index/different-tag thrashing at index 4; index 63 with tags `0x000000` vs `0x3FFFFF`; index 0 ping-pong | 22.22 % |

#### Verification Scenarios Covered (Member 5)
1. **D1 — Reset state:** no stall, response or memory traffic; all 64 valid bits cleared.
2. **D2 — Reset during a miss refill:** the aborted line does not become valid; the next access misses and returns correct data, then hits.
3. **Trace runs:** every trace runs from a cold cache at memory latencies of 0, 1 and 5 cycles per word (12 runs, 5,040 requests).
4. **Per-request checks:** returned data matches the trace and the memory model; hit/miss matches the reference cache; a hit causes no memory traffic and takes exactly 2 cycles; a miss issues exactly one 16-byte-aligned block request and exactly four word reads inside that block.
5. **Protocol monitor:** exactly one 1-cycle `cpu_ready` per accepted request, no response without an outstanding request, `cpu_stall` held for the whole transaction, and `cpu_addr` scrambled after acceptance to prove the address is latched.
6. **Counters:** accepted requests, responses, hits, misses, block refills, word reads and elapsed cycles. AMAT is reported as `hit time + miss ratio × miss penalty`, and the testbench checks that it matches the measured average latency.

The testbench was also run against deliberately broken RTL copies (swapped refill word order, hit ignoring the valid bit, tag never written, wrong index bits, unlatched address); every one was detected.

#### Simulation Results (Icarus Verilog 13.0, 100 MHz clock)

Latencies are in cycles from request acceptance to data. Hit time is 2 cycles. The miss penalty is `4 × (L + 1) + 3` cycles for a memory latency of `L` cycles per word.

| Trace | Mem latency | Hits | Misses | Hit % | Miss % | Miss penalty | AMAT (cycles) | AMAT (ns) | Elapsed cycles |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| sequential | 0 | 384 | 128 | 75.00 | 25.00 | 7 | 3.750 | 37.50 | 2433 |
| sequential | 1 | 384 | 128 | 75.00 | 25.00 | 11 | 4.750 | 47.50 | 2945 |
| sequential | 5 | 384 | 128 | 75.00 | 25.00 | 27 | 8.750 | 87.50 | 4993 |
| random | 0 | 112 | 400 | 21.88 | 78.12 | 7 | 7.469 | 74.69 | 4337 |
| random | 1 | 112 | 400 | 21.88 | 78.12 | 11 | 10.594 | 105.94 | 5937 |
| random | 5 | 112 | 400 | 21.88 | 78.12 | 27 | 23.094 | 230.94 | 12337 |
| repeated | 0 | 480 | 32 | 93.75 | 6.25 | 7 | 2.438 | 24.38 | 1761 |
| repeated | 1 | 480 | 32 | 93.75 | 6.25 | 11 | 2.688 | 26.88 | 1889 |
| repeated | 5 | 480 | 32 | 93.75 | 6.25 | 27 | 3.688 | 36.88 | 2401 |
| conflict | 0 | 32 | 112 | 22.22 | 77.78 | 7 | 7.444 | 74.44 | 1217 |
| conflict | 1 | 32 | 112 | 22.22 | 77.78 | 11 | 10.556 | 105.56 | 1665 |
| conflict | 5 | 32 | 112 | 22.22 | 77.78 | 27 | 23.000 | 230.00 | 3457 |

#### Synthesis Results (Yosys 0.71)

`main_memory_model.v` is simulation-only and is excluded. Reports are written to `build/synth/`.

| Resource | Generic gates (`synth_generic.ys`) | Xilinx 7-series (`synth_xc7.ys`) |
|---|:---:|:---:|
| Storage for data + tag RAMs | 9,600 enable FFs (64 × 128 + 64 × 22) | 150 × `RAM64X1S` distributed LUT-RAM (128 data + 22 tag) |
| Other flip-flops | 420 (valid bits, FSMs, latched address, refill buffers, output data) | 420 (419 `FDCE` + 1 `FDPE`) |
| Logic | 9,391 `MUX` + 1,430 other 2-input gates | 297 LUTs (142 LUT2, 12 LUT3, 16 LUT4, 5 LUT5, 122 LUT6) |
| I/O | — | 68 `IBUF`, 67 `OBUF`, 1 `BUFG` |

The data and tag RAMs have combinational reads, so they map to distributed LUT-RAM rather than block RAM. The valid bits need a global clear on reset, so they map to flip-flops; Yosys's "Replacing memory `\ram` with list of registers" warning for `valid_bit_ram.v` is expected.

**Timing:** no place-and-route tool is part of the flow, so post-route Fmax is not available. The available figure is logic depth: the longest register-to-register path in the generic netlist is **21 levels of 2-input gates**. It runs from the latched address (index) through the 64:1 valid-bit mux and the 22-bit tag comparator to `cache_hit` and the controller's `next_state` (`S_LOOKUP` → hit/miss decision).

---

### Project Status & Roadmap

| Member | Focus Area | Status | Deliverables |
|---|---|:---:|---|
| **Member 1** | Address Decoding & Tag Comparison | **Completed** | `rtl/address_decoder.v`, `rtl/tag_comparator.v`, `tb/tb_member1.v` |
| **Member 2** | Cache Storage (RAMs) | **Completed** | `rtl/cache_data_ram.v`, `rtl/tag_ram.v`, `rtl/valid_bit_ram.v`, `tb/tb_member2.v` |
| **Member 3** | Controller FSM & Datapath Integration | **Completed** | `rtl/cache_controller.v`, `tb/tb_member3.v` |
| **Member 4** | Main-Memory Interface and Model | **Completed** | `rtl/main_memory_interface.v`, `rtl/main_memory_model.v`, `tb/tb_member4.v` |
| **Member 5** | Top-Level Integration & Verification | **Completed** | `rtl/cache_top.v`, `tb/tb_cache_top.v`, `traces/*.trace`, `scripts/gen_traces.py`, `synth/*.ys` |

---

## Verification & Testing

Tests are written in self-checking Verilog with `$fatal` assertions on failure.

### Test Targets

- **Run all tests (Members 1–5):**
  ```bash
  make test
  ```
- **Run Member 1 tests only:**
  ```bash
  make test_member1
  ```
- **Run Member 2 tests only:**
  ```bash
  make test_member2
  ```
- **Run Member 3 tests only:**
  ```bash
  make test_member3
  ```
- **Run Member 4 tests only:**
  ```bash
  make test_member4
  ```
- **Run Member 5 system tests only** (add `SIMFLAGS=+VCD` to dump `build/tb_cache_top.vcd`)**:**
  ```bash
  make test_member5
  ```
- **Regenerate the trace files:**
  ```bash
  make traces
  ```
- **Run synthesis (generic + Xilinx 7-series; reports in `build/synth/`):**
  ```bash
  make synth
  ```
- **Clean build artifacts:**
  ```bash
  make clean
  ```

### Verification Scenarios Covered (Member 2)
1. **Reset Behavior:** Resetting valid-bit RAM clears all 64 lines to 0.
2. **128-bit Block Write & 32-bit Word Read:** Writes full 128-bit block into cache line 5 and verifies all four words at offsets `00`, `01`, `10`, `11` with proper endianness/ordering.
3. **Cache Line Replacement:** Overwrites line 5 with a new block and verifies old contents are replaced.
4. **Boundary Indices:** Tests index 0 and index 63 across all RAM modules to ensure correct addressing at limits.
5. **Full Addressability & Isolation:** Writes unique patterns to all 64 data lines and reads back 256 words; writes distinct tags to all 64 lines and reads back; verifies no cross-line interference.
6. **Valid Bit Manipulation:** Tests setting, explicitly clearing, and walking a valid bit across all lines.
7. **Combinational Read Verification:** Verifies read outputs change immediately when `index` or `word_offset` changes without waiting for clock edges.
8. **Write Enable Gating:** Verifies contents are preserved when `write_enable` is low.

### Verification Scenarios Covered (Member 3)
1. **Reset:** Verifies IDLE state, inactive control signals, and all 64 valid bits cleared.
2. **Cache Hit:** Pre-loaded line returns correct word in 2 cycles with zero memory requests.
3. **Cache Miss & Refill:** Invalid line asserts `cpu_stall`, generates single 16-byte aligned `mem_req`, and completes 128-bit refill.
4. **Post-Refill Hit:** Re-accessing same address produces instant cache hit without memory transaction.
5. **Word Offsets:** Verifies reading words at offsets `00`, `01`, `10`, and `11` from a 128-bit cached block.
6. **Delayed Memory:** Verifies correct waiting across 6 cycles of memory latency with exactly one memory request strobe.
7. **Conflict & Replacement:** Accessing differing tags at same index causes eviction, refill, and tag replacement.
8. **Consecutive Requests:** Stream of 6 back-to-back hit/miss requests generates exactly one response strobe per request.

### Verification Scenarios Covered (Member 4)
1. **Reset Behavior & Mid-Flight Abort:** Verifies IDLE state, inactive control outputs (`mem_ready = 0`, `model_req = 0`), and clean abort of active multi-cycle fetches upon reset.
2. **128-bit Block Assembly & Word Ordering:** Verifies four 32-bit words are sequentially fetched over 32-bit memory-read interface and assembled matching verified cache data ordering: `mem_data = {Word3, Word2, Word1, Word0}`.
3. **16-Byte Block Alignment:** Requests unaligned addresses (`+0x4`, `+0x8`, `+0xE`) and confirms hardware masks address to 16-byte aligned base (`{addr[31:4], 4'b0000}`).
4. **Configurable Latency Coverage:** Verifies correct operation across 0, 1, 5, and 10 clock cycles of memory delay, ensuring single-cycle `mem_ready` pulses and stable data delivery.
5. **Back-to-Back Block Streams:** Executes rapid consecutive requests across different block addresses without dropped requests, protocol stalls, or stale data.
6. **Deterministic Memory Default Pattern:** Verifies unwritten addresses return deterministic, address-dependent default words.
7. **Cache Controller Integration:** Connects `cache_controller.v` directly to `main_memory_interface.v` and `main_memory_model.v`, verifying cold miss detection, CPU stall enforcement, 4-word block refill, CPU data return, subsequent post-refill hits with zero memory transactions, and line eviction on tag conflict.

Verified with Icarus Verilog 13.0 (`make test` passed cleanly across Members 1–5) and synthesized with Yosys 0.71 (`make synth`).

## Integrated verification and final submission

The team integration was fetched through `ba8d39d`. The Makefile now points to
`tb/tb_member5.v`, the committed system testbench filename.

- [Final technical report and requirement checklist](reports/technical_report.md)
- [Architecture and FSM diagrams](docs/architecture.md)
- [Live demonstration commands](docs/demo.md)
- [Measured performance and equal-capacity baseline models](reports/performance.md)
- [Actual simulation waveform preview](reports/waveform.svg)
- [Full verification log](reports/simulation.log)

From the repository root, `source scripts/env.sh` activates the ignored local
OSS CAD Suite if present. Run `make test`, `make waveforms`, `make analyze`,
`make synth`, and `make synth_ecp5`. The ECP5 benchmark defaults to 80 MHz;
`PNR_FREQ=100` intentionally exercises a target that failed in this run.
The routed internal Fmax estimate was 94.84 MHz; this is not a board guarantee.
The simulation clock of 100 MHz must not be presented as timing closure.

## IEEE Project Report

[Download the final project report](project_report/ByteMe_IEEE_Project_Report.docx)
for Team ByteMe, Section D, including the architecture, verification results,
performance analysis, individual contributions, and references.
