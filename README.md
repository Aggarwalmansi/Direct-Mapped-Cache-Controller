# Direct-Mapped Cache Controller

**Team ByteMe · Section D**
> [!Important]
> ##  Project Video
> **Watch the project demo video on Google Drive:**
> ### 👉 [**Open the Project Video (Google Drive)**](https://drive.google.com/drive/u/0/folders/1IOG2N3P3jU9f9sL_8U6O8kBgdy0eofwT?q=sharedwith:public%20parent:1IOG2N3P3jU9f9sL_8U6O8kBgdy0eofwT)
A modular, synthesizable Verilog implementation of a 1 KB direct-mapped cache with a four-word refill interface. The project studies temporal locality, spatial locality, placement conflicts, hit/miss ratios, and average memory access time (AMAT).

[Download the IEEE project report](project_report/ByteMe_IEEE_Project_Report.docx) · [Architecture and FSM diagrams](docs/architecture.md) · [Live demonstration guide](docs/demo.md)

## Team and individual contributions

Member numbers match the project report and each member's dedicated testbench. Each contribution below describes implementation ownership, integration responsibilities, and verification work.

| Member | Name | Enrollment number | Responsibility |
|---|---|---|---|
| 1 | Adamya Tiwari | 2401010025 | Address decoding and tag comparison |
| 2 | Nachiket Amlekar | 2401020039 | Cache data, tag, and valid-bit storage |
| 3 | Aditi Singh | 2401020006 | Cache controller FSM and datapath integration |
| 4 | Mansi Agarwal | 2401010264 | Main-memory interface and simulation model |
| 5 | Tanisha | 2401010475 | Top-level integration, traces, and system verification |

### Member 1 — Adamya Tiwari

- **Implementation:** Developed [`address_decoder.v`](rtl/address_decoder.v) and [`tag_comparator.v`](rtl/tag_comparator.v) to extract address fields, align block addresses, and generate hits only when the selected valid tag matches.
- **Integration:** Defined the tag, index, word-offset, and byte-offset outputs used by storage and control logic; provided the lookup comparison that directs hit and miss processing.
- **Verification:** Developed [`tb_member1.v`](tb/tb_member1.v), checking field boundaries, 5,100 addresses, block alignment, every tag bit, same-index conflicts, and invalid entries containing unknown tags.

### Member 2 — Nachiket Amlekar

- **Implementation:** Developed [`cache_data_ram.v`](rtl/cache_data_ram.v), [`tag_ram.v`](rtl/tag_ram.v), and [`valid_bit_ram.v`](rtl/valid_bit_ram.v) for the 64-line cache, including full-block writes and word selection.
- **Integration:** Provided combinational lookup reads, synchronous data/tag updates, and resettable valid bits so the controller can refill or replace a selected line consistently.
- **Verification:** Developed [`tb_member2.v`](tb/tb_member2.v), checking all-line addressing, word ordering, storage isolation, replacement, write-enable gating, and valid-bit reset, set, and clear operations.

### Member 3 — Aditi Singh

- **Implementation:** Developed [`cache_controller.v`](rtl/cache_controller.v) with a seven-state FSM for request acceptance, lookup, hit response, miss request, memory wait, refill, and miss response.
- **Integration:** Connected the decoder, comparator, and storage modules; latched accepted CPU addresses and controlled stalls, memory requests, cache updates, and one-cycle CPU responses.
- **Verification:** Developed [`tb_member3.v`](tb/tb_member3.v), checking reset, hits, misses, delayed refills, word selection, tag conflicts, replacement, and consecutive request/response sequencing.

### Member 4 — Mansi Agarwal

- **Implementation:** Developed [`main_memory_interface.v`](rtl/main_memory_interface.v) and [`main_memory_model.v`](rtl/main_memory_model.v) to fetch four words, assemble refill blocks, and model configurable backing-memory latency.
- **Integration:** Connected the controller's 128-bit block channel to a 32-bit word channel, preserving alignment, word ordering, request pulses, and completion signaling; kept the behavioral model outside the synthesized hierarchy.
- **Verification:** Developed [`tb_member4.v`](tb/tb_member4.v), checking immediate and delayed responses, block assembly, reset during a transfer, consecutive blocks, deterministic data, and controller-to-memory integration.

### Member 5 — Tanisha

- **Implementation:** Developed [`cache_top.v`](rtl/cache_top.v), [`gen_traces.py`](scripts/gen_traces.py), and the initial generic/Xilinx synthesis scripts to connect the subsystem and generate repeatable workloads.
- **Integration:** Connected the cache controller and refill interface, attached backing memory in simulation, and collected request, response, hit, miss, refill, and elapsed-cycle statistics for architectural analysis.
- **Verification:** Developed [`tb_member5.v`](tb/tb_member5.v), checking returned data, reference hit/miss outcomes, reset recovery, stall/response accounting, memory traffic, measured latency, and AMAT across twelve trace runs.

The final integration package also includes shared project evidence: waveform previews, associative reference comparisons, ECP5 routed timing results, architecture documentation, and the IEEE report. These artifacts support the combined implementation of all five members.

## Architecture and scope

| Parameter | Configuration |
|---|---|
| Data capacity | 1,024 bytes |
| Block size | 16 bytes / four 32-bit words |
| Cache lines | 64 |
| Address width | 32 bits, byte-addressed |
| Tag | `address[31:10]`, 22 bits |
| Index | `address[9:4]`, 6 bits |
| Word offset | `address[3:2]`, 2 bits |
| Byte offset | `address[1:0]`, 2 bits |
| Total array storage | 9,664 bits including tags and valid bits |

```text
cache_top
├── cache_controller
│   ├── address_decoder
│   ├── tag_comparator
│   ├── cache_data_ram
│   ├── tag_ram
│   └── valid_bit_ram
└── main_memory_interface
    └── external 32-bit word-read channel

Simulation only: main_memory_model attaches to the external channel.
```

The cache is blocking, in-order, and read-only, with one outstanding CPU request. Supported CPU loads are aligned 32-bit words. The decoder exposes byte offsets; byte extraction, stores, coherence, and cross-word unaligned loads are not implemented. Some traces include byte-unaligned addresses to exercise decoding; returned data is the containing word, not a cross-word unaligned load.

A request is accepted on a rising edge with `cpu_req && !cpu_stall`. The controller latches the address, asserts stall while processing, and pulses `cpu_ready` for one cycle with valid `cpu_data`. Keeping `cpu_req` high when the controller returns to idle accepts another request. Hit response latency is **two cycles**.

On a miss, the controller requests a 16-byte-aligned block. The refill interface reads addresses base + 0, +4, +8, and +12, then returns `{word3, word2, word1, word0}`. Cache arrays have combinational reads and synchronous writes. Reset clears all valid bits and aborts an outstanding transaction; the backing-memory interface must cancel its pending transaction on reset too.

See [architecture.md](docs/architecture.md) for the controller and refill state diagrams and protocol explanation.

## Build and verification

Requirements: GNU Make, Python 3, and Icarus Verilog (`iverilog` and `vvp`). Synthesis additionally needs Yosys; ECP5 routing needs nextpnr-ecp5 and its device database. The local OSS CAD Suite is ignored under `work/tools/`; fresh clones must install the tools or supply them on `PATH`.

From the repository root:

```sh
# Optional: activate the locally downloaded OSS CAD Suite if present.
source scripts/env.sh

# Run all five testbenches, refresh the simulation log, and check analysis.
make verify
```

| Command | Purpose |
|---|---|
| `make test` | Run all five self-checking Verilog testbenches |
| `make test_member1` through `make test_member5` | Run an individual member's testbench |
| `make waveforms` | Run system tests with VCD output and render the waveform preview |
| `make traces` | Regenerate deterministic trace files |
| `make analyze` | Compare measured results with reference models and write performance reports |
| `make synth` | Run generic and Xilinx 7-series mapped synthesis |
| `make synth_ecp5` | Run ECP5 synthesis and routing at the default 80 MHz target |
| `make clean` | Remove generated `build/` artifacts |

Tests use self-checking assertions and fail on mismatches. All five passed in the retained run using the bundled Icarus Verilog 14.0 development build. System testing covers **5,040 trace accesses** across four traces and three memory latencies, plus directed reset/recovery tests. Including directed tests, 5,043 requests were accepted, 5,042 responses returned, and one request was deliberately aborted by reset.

The system monitor checks data, reference hit/miss outcomes, one response per accepted request, stall behavior, block alignment, four word reads per completed miss, and no memory traffic on hits. Unit test coverage for each module is listed with its owner above.

- [Full simulation evidence](reports/simulation.log)
- [Actual waveform preview](reports/waveform.svg)
- Full generated waveform: `build/tb_cache_top.vcd`, viewable with GTKWave or another VCD viewer.

## Performance and baseline comparison

Each trace starts with an empty cache and runs at word-memory latencies `L = 0, 1, 5`. Hit latency is 2 cycles; the measured additional miss penalty is `7 + 4L` cycles:

```text
hit ratio  = hits / requests
miss ratio = misses / requests
AMAT       = 2 + miss ratio × (7 + 4L) cycles
```

| Trace | Requests per run | Hits | Misses | Hit rate | AMAT at L = 5 (cycles) |
|---|---:|---:|---:|---:|---:|
| Sequential | 512 | 384 | 128 | 75.00% | 8.7500 |
| Random | 512 | 112 | 400 | 21.88% | 23.0938 |
| Repeated | 512 | 480 | 32 | 93.75% | 3.6875 |
| Conflict | 144 | 32 | 112 | 22.22% | 23.0000 |

Sequential accesses exploit spatial locality; repeated accesses exploit temporal reuse. Random and conflicting accesses demonstrate the limits of direct mapping. Equal-capacity two-way and fully associative LRU reference models improve the conflict trace hit rate to 63.89% and 95.14%. These alternatives are Python models, not synthesized alternative RTL, so their hardware area and speed-up are not claimed.

The testbench uses a 10 ns period for simulated nanosecond values. This does **not** establish a 100 MHz hardware clock. At 80 MHz, multiply AMAT cycles by 12.5 ns. Elapsed trace time also includes request-issue intervals.

See [all twelve performance rows and comparison assumptions](reports/performance.md) or [the CSV results](reports/performance.csv). Traces are generated by [gen_traces.py](scripts/gen_traces.py), and [analyze_results.py](scripts/analyze_results.py) independently checks hit counts and measured AMAT.

## Synthesis and timing

The behavioral memory model is excluded from all synthesis flows. Generic, Xilinx, and ECP5 synthesis pass structural checks with Yosys 0.71+39. Distributed memory is used because cache reads are asynchronous; the resettable valid-bit array maps to flip-flops.

| Flow | Measured result |
|---|---|
| Generic synthesis | 20,841 cells; longest combinational topological path: 21 cells |
| Xilinx 7-series mapped synthesis | 420 flip-flops, 297 LUT2–LUT6 cells, 150 RAM64X1S primitives |
| ECP5 post-pack utilisation | 1,924/24,288 logic elements, 420 flip-flops, 152 RAMW resources, no block RAM |
| ECP5 routed timing | Estimated internal Fmax **94.84 MHz**; **80 MHz passes**, **100 MHz fails** |

ECP5 benchmark configuration: LFE5U-25F, CABGA256, speed grade 6, routing seed 1, nextpnr-ecp5 0.11.1-92. I/O placement is unconstrained and external timing budgets are absent. This is an internal device timing estimate, not a board-qualified guarantee. Xilinx results are synthesis-only and do not include routed Fmax.

[Raw synthesis and timing reports](reports/synthesis/) retain both the failed 100 MHz and successful 80 MHz experiments. The final Makefile fails on an unmet timing target.

## Report and demonstration

- [IEEE project report — Team ByteMe, Section D](project_report/ByteMe_IEEE_Project_Report.docx): abstract, literature review, proposed solution, verification, results, individual contributions, conclusion, and references.
- [Technical results and requirement checklist](reports/technical_report.md): measured results, tool versions, assumptions, and limitations.
- [Live demonstration guide](docs/demo.md): commands and explanations for presenting the integrated system.

The RTL, simulation, waveform, performance, and synthesis/device-timing evidence are available locally. A live presentation remains a team activity. Physical FPGA verification requires an actual board, clock/reset setup, pin and I/O timing constraints, a stimulus source, and backing-memory integration.
