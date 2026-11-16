# Direct-Mapped Cache Controller — Member 1

Local contribution: combinational address decoding and valid-gated tag comparison.

## Configuration and interfaces

The cache has 1,024 data bytes, 64 lines, and 16-byte blocks. Addresses are 32-bit byte addresses; words are 32 bits.

| Decoder output | Width | Address bits |
| --- | --- | --- |
| tag | 22 | 31:10 |
| index | 6 | 9:4 |
| word_offset | 2 | 3:2 |
| byte_offset | 2 | 1:0 |
| block_address | 32 | Address rounded down to a multiple of 16 |

Connect the index to Member 2's storage, and connect its stored tag and valid bit to `tag_comparator`. Feed the requested tag from the decoder. The comparator produces `hit = valid && (requested_tag == stored_tag)`. Member 3 must sample this result only when the storage lookup is ready. These modules have no clock, reset, or internal state. Valid-bit reset belongs to Member 2. The decoder exposes byte offsets but does not implement unaligned loads.

## Verification

Install Icarus Verilog, then run `make test`. The self-checking testbench checks field boundaries, all low 4,096 addresses, 1,000 pseudorandom addresses, block alignment, and all four combinations of validity and tag equality. It exits with a fatal error on failure.

Verified on 16 November 2026 with Icarus Verilog 13.0: `make test` passed. Checks also cover every tag bit, same-index conflicting addresses, and invalid entries with unknown stored tags. Other members' storage, controller, memory interface, and integration are not implemented here.
