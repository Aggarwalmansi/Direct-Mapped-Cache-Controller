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

## Verification & Testing

Tests are written in self-checking Verilog with `$fatal` assertions on failure.

### Test Targets

- **Run all tests:**
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

Verified on 16 November 2026 with Icarus Verilog 13.0 (`make test` passed cleanly).
