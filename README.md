# Direct-Mapped Cache Controller

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

- **Module Name & File Path:** `cache_controller` (`rtl/cache_controller.v`)
- **Purpose:** Manages the entire cache access lifecycle, including CPU request latching, cache line lookup, hit determination, single-pulse CPU response delivery, cache miss detection, 16-byte-aligned main memory refill requests with variable wait-state handling, synchronous line updates, and CPU stall management.

#### 1. FSM Architecture and State Descriptions
The controller is implemented as a clean, synthesizable 7-state Moore/Mealy hybrid FSM with registered outputs and separate combinational next-state/output logic:

| State | Encoding | Description |
|---|---|---|
| `S_IDLE` | `3'b000` | Controller is ready. Accepts new CPU request (`cpu_req`) when not stalled; latches `cpu_addr` into `latched_address`. |
| `S_LOOKUP` | `3'b001` | Drives decoded index to cache RAMs and tag comparator. Evaluates hit/miss combinational condition. Next state is `S_HIT_RESPONSE` if hit, or `S_MISS_REQUEST` if miss. |
| `S_HIT_RESPONSE` | `3'b010` | Latches word from Data RAM into `latched_cpu_data`. Asserts `cpu_ready = 1` for exactly 1 cycle. Returns to `S_IDLE`. |
| `S_MISS_REQUEST` | `3'b011` | Asserts `mem_req = 1` with 16-byte aligned `mem_addr`. If `mem_ready` is asserted immediately (zero wait-state), transitions to `S_REFILL`; otherwise transitions to `S_WAIT_MEMORY`. |
| `S_WAIT_MEMORY` | `3'b100` | Deasserts `mem_req = 0` to prevent duplicate memory commands. Waits for `mem_ready` with variable latency. Upon `mem_ready`, latches 128-bit `mem_data` and advances to `S_REFILL`. |
| `S_REFILL` | `3'b101` | Asserts synchronous write enables for Data RAM, Tag RAM, and Valid Bit RAM at the latched cache index. Simultaneously extracts requested 32-bit word into `latched_cpu_data`. Advances to `S_MISS_RESPONSE`. |
| `S_MISS_RESPONSE` | `3'b110` | Asserts `cpu_ready = 1` with valid `cpu_data` for exactly 1 cycle. Storage RAMs now hold the newly written block. Returns to `S_IDLE`. |

#### 2. CPU Handshake & Request Acceptance
- **Request Acceptance:** When in `S_IDLE` and `cpu_stall == 0`, assertion of `cpu_req` causes the controller to latch `cpu_addr` on `posedge clk` and enter `S_LOOKUP`.
- **Address Preservation:** `latched_address` is held invariant throughout the entire transaction, ensuring that subsequent memory access, refill, and word extraction remain tied to the original CPU request.
- **Single Response Guarantee:** Exactly one `cpu_ready` pulse (duration = 1 clock cycle) is generated per accepted request in `S_HIT_RESPONSE` or `S_MISS_RESPONSE`.
- **CPU Master Protocol:** Masters may either pulse `cpu_req` high for 1 cycle or hold `cpu_req` high until observing `cpu_ready`, deasserting `cpu_req` on the following cycle.

#### 3. Cache Hit Handling
- During `S_LOOKUP`, the combinational `cache_hit` signal is evaluated:
  $$\text{hit} = \text{valid\_bit} \land (\text{requested\_tag} == \text{stored\_tag})$$
- On hit, Data RAM combinationally selects the 32-bit word using `word_offset`.
- The controller registers this word into `latched_cpu_data` and enters `S_HIT_RESPONSE`.
- `cpu_ready` is asserted for 1 cycle with `cpu_data = latched_cpu_data`.
- No memory request is triggered (`mem_req = 0`).

#### 4. Cache Miss Handling & CPU Stall Behavior
- On miss (`cache_hit == 0`), the CPU is stalled via `cpu_stall = (state != S_IDLE)`.
- The controller ignores any new requests while busy.
- `latched_address` is retained to compute `mem_addr = {latched_address[31:4], 4'b0000}`.

#### 5. Main-Memory Request & Refill Procedure
- **Request Strobe:** `mem_req` is pulsed high for exactly 1 clock cycle during `S_MISS_REQUEST` alongside the 16-byte-aligned `mem_addr`.
- **Variable Latency:** In `S_WAIT_MEMORY`, `mem_req` is low while the controller waits for `mem_ready`. Any number of wait states (0, 1, 5, 10+ cycles) are handled correctly without duplicate transactions.
- **Refill Buffer:** When `mem_ready` is asserted, the full 128-bit block is captured into `refill_buffer`.
- **Consistent Storage Write:** In `S_REFILL`, write enables for `cache_data_ram`, `tag_ram`, and `valid_bit_ram` are asserted simultaneously for index `dec_index`.
- **Valid Bit Setting:** The valid bit is asserted to 1 only upon successful refill completion.
- **Line Replacement:** If the line was previously occupied by an older block with a different tag, the tag, data, and valid bit are overwritten atomically.

#### 6. Interaction with Member 1 & Member 2 Modules
`cache_controller` directly instantiates and orchestrates all Member 1 and Member 2 modules:
- **`address_decoder` (Member 1):** Takes `latched_address` and continuously decodes `dec_tag` [21:0], `dec_index` [5:0], `dec_word_offset` [1:0], `dec_byte_offset` [1:0], and `dec_block_addr` [31:0].
- **`tag_ram` (Member 2):** Takes `dec_index`, outputs `stored_tag`, and updates tag with `dec_tag` during `S_REFILL`.
- **`valid_bit_ram` (Member 2):** Takes `dec_index` and `reset`, outputs `stored_valid`, and writes `write_valid = 1` during `S_REFILL`. Clears all lines on system reset.
- **`tag_comparator` (Member 1):** Compares `dec_tag` with `stored_tag` gated by `stored_valid` to produce `cache_hit`.
- **`cache_data_ram` (Member 2):** Takes `dec_index` and `dec_word_offset`, outputs `cache_read_word`, and writes 128-bit `refill_buffer` during `S_REFILL`.

#### 7. Input and Output Signals

| Signal | Direction | Width | Description |
|---|:---:|:---:|---|
| `clk` | Input | 1 bit | Master clock (rising-edge active) |
| `reset` | Input | 1 bit | Active-high asynchronous reset |
| `cpu_req` | Input | 1 bit | Active-high memory read request from CPU |
| `cpu_addr` | Input | 32 bits | 32-bit target byte address from CPU |
| `cpu_data` | Output | 32 bits | 32-bit data word returned to CPU |
| `cpu_ready` | Output | 1 bit | Active-high single-cycle strobe indicating transaction complete and valid data |
| `cpu_stall` | Output | 1 bit | Active-high stall indicator asserted whenever controller is busy (`state != S_IDLE`) |
| `mem_req` | Output | 1 bit | Active-high single-cycle request strobe initiating 128-bit block read from main memory |
| `mem_addr` | Output | 32 bits | 16-byte aligned 32-bit block address (`{latched_address[31:4], 4'b0000}`) |
| `mem_ready` | Input | 1 bit | Active-high indicator from main memory when `mem_data` is valid |
| `mem_data` | Input | 128 bits | 128-bit cache block returned from main memory |

---

### Project Status & Roadmap

| Member | Focus Area | Status | Deliverables |
|---|---|:---:|---|
| **Member 1** | Address Decoding & Tag Comparison | **Completed** | `rtl/address_decoder.v`, `rtl/tag_comparator.v`, `tb/tb_member1.v` |
| **Member 2** | Cache Storage (RAMs) | **Completed** | `rtl/cache_data_ram.v`, `rtl/tag_ram.v`, `rtl/valid_bit_ram.v`, `tb/tb_member2.v` |
| **Member 3** | Controller FSM & Datapath Integration | **Completed** | `rtl/cache_controller.v`, `tb/tb_cache_controller.v` |
| **Member 4** | Write Policy / Write Buffer / Cache Statistics | *Pending* | Write-through / write-back logic, hit/miss counters (future assignment) |
| **Member 5** | Top-Level Integration & System Testbench | *Pending* | `cache_top` SoC wrapper, CPU bus interface, system-level verification |

---

## Verification & Testing

Tests are written in self-checking Verilog with `$fatal` assertions on failure.

### Test Targets

- **Run all tests (Members 1, 2, and 3):**
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

### Verification Scenarios Covered (Member 3 — Controller FSM)
1. **Test 1: Reset Behavior & Control Inactivity:** Applies reset and asserts that the controller enters `S_IDLE`, `cpu_stall = 0`, `cpu_ready = 0`, `mem_req = 0`, and all 64 valid bits are cleared to 0.
2. **Test 2: Cache Hit on Pre-loaded Line:** Submits matching address to a pre-populated valid line; verifies correct 32-bit word returned in 2 cycles, `cpu_ready` single pulse, and zero main memory requests.
3. **Test 3 & 4: Cache Miss Detection, Stall, and Memory Refill:** Submits address to an invalid line; verifies `cpu_stall` asserted, `mem_req` generated for 16-byte aligned address, 128-bit block refilled from mock memory into cache line, tag and valid bit updated, and requested word returned.
4. **Test 5: Post-Refill Hit:** Re-submits the exact same address; verifies cache hit with correct word returned and zero memory transactions.
5. **Test 6: Word Offsets (00, 01, 10, 11):** Verifies reading each of the four 32-bit words within a single 128-bit cached block with correct alignment and endianness.
6. **Test 7: Variable Memory Latency:** Introduces 6 clock cycles of memory delay; verifies controller waits in `S_WAIT_MEMORY`, keeps `cpu_stall = 1`, generates exactly one `mem_req` pulse (no duplicate memory requests), and asserts exactly one `cpu_ready` strobe upon refill.
7. **Test 8: Conflicting Addresses & Line Replacement:** Submits two addresses mapping to the same index (15) with different tags; verifies conflict miss on second address, proper eviction and replacement of data and tag, subsequent hit on second address, and clean re-fetching upon accessing the first address again.
8. **Test 9: Consecutive Requests:** Executes a back-to-back stream of 6 interleaved hit and miss requests; verifies each accepted request generates exactly one response with zero dropped requests or protocol stalls.

Verified with Icarus Verilog 13.0 (`make test` passed cleanly).
