# Live demonstration guide

Run from the repository root. With the locally downloaded tool suite:

```sh
source scripts/env.sh
iverilog -V
yosys -V
make verify
# Optional individual steps:
# make test
# make waveforms
# make analyze
make synth
make synth_ecp5
```

Allow a few minutes for synthesis and routing. No FPGA board is required for this simulation/device benchmark. Tools installed elsewhere can be used via PATH; `env.sh` is optional in that case. The suite is excluded from Git in `work/`.

1. Explain 64 cache lines, tag/index/offset, and the two FSMs using architecture.md.
2. Run `make test`: show all five PASS messages and reset-during-refill recovery.
3. Open reports/waveform.svg in a browser. It is drawn from the real VCD, not an illustrative timing sketch. Open build/tb_cache_top.vcd with GTKWave or another VCD viewer for the full run; inspect cpu_req, cpu_stall, cpu_ready, block request, word requests and FSM state. A hit returns without a block request; a miss produces four word reads. The initial sequence contains an intentionally aborted refill, reset, recovery miss and hit.
4. Show the twelve performance rows. Explain `AMAT = 2 + miss_ratio × (7 + 4L)` cycles, with L the configured word-memory latency. For sequential accesses and L=5: `2 + 0.25 × 27 = 8.75` cycles, or 87.5 ns at the simulated 10 ns period.
5. Compare the same 1 KB capacity with 2-way and fully associative LRU reference models in reports/performance.md. Explain that hit rate alone does not establish hardware speed-up.
6. Show synthesis logs and ECP5 post-route timing. Distinguish an unconstrained board-independent internal timing benchmark from a board-qualified implementation.

For physical demonstration, select an actual FPGA/board, provide its clock and reset circuits, assign real pins and I/O timing, connect a CPU stimulus source and backing-memory implementation, then rerun the board vendor's implementation flow. Do not program the unconstrained benchmark onto a board.
