`timescale 1ns/1ps

// =============================================================================
// Module: cache_top
// Project: Direct-Mapped Cache Controller (1 KB Capacity, 16-Byte Block)
// Member: Member 5 — Top-Level Integration and Verification
//
// Description:
//   Synthesizable top level for the cache subsystem. Connects:
//     - cache_controller      (Member 3, which itself instantiates the Member 1
//                              decoder/comparator and Member 2 storage RAMs)
//     - main_memory_interface (Member 4, four-word refill assembler)
//
//   The simulation-only main_memory_model (Member 4) is NOT part of this
//   module. It is attached outside, through the 32-bit word-read port
//   (mem_word_*), by the testbench (tb/tb_cache_top.v). This keeps cache_top
//   fully synthesizable while letting any backing memory be connected.
//
//   Data flow:
//
//     CPU <-> cache_controller <-(128-bit block)-> main_memory_interface
//                                                    <-(32-bit words)-> memory
//
// CPU protocol (blocking, in-order, read-only):
//   - The CPU drives cpu_addr and holds cpu_req high.
//   - A request is accepted on the rising edge where cpu_req = 1 and
//     cpu_stall = 0. The CPU should drop cpu_req after acceptance (or present
//     its next request), because a high cpu_req in IDLE is a new request.
//   - Exactly one cpu_ready pulse (1 cycle) is produced for every accepted
//     request; cpu_data is valid while cpu_ready = 1 and holds afterwards.
//   - cpu_stall stays high from acceptance until the response has been given.
// =============================================================================

module cache_top (
    // Clock and active-high asynchronous reset
    input  wire        clk,
    input  wire        reset,

    // CPU interface
    input  wire        cpu_req,
    input  wire [31:0] cpu_addr,
    output wire [31:0] cpu_data,
    output wire        cpu_ready,
    output wire        cpu_stall,

    // Backing-memory 32-bit word-read interface
    output wire        mem_word_req,    // 1-cycle read strobe per word
    output wire [31:0] mem_word_addr,   // word-aligned byte address
    input  wire        mem_word_ready,  // data valid strobe from memory
    input  wire [31:0] mem_word_data    // 32-bit word from memory
);

    // -------------------------------------------------------------------------
    // Controller <-> refill interface (128-bit block channel)
    // -------------------------------------------------------------------------
    wire         blk_req;
    wire [31:0]  blk_addr;
    wire         blk_ready;
    wire [127:0] blk_data;

    // -------------------------------------------------------------------------
    // Member 3: Cache controller FSM + datapath (includes Members 1 and 2)
    // -------------------------------------------------------------------------
    cache_controller u_cache_controller (
        .clk      (clk),
        .reset    (reset),
        .cpu_req  (cpu_req),
        .cpu_addr (cpu_addr),
        .cpu_data (cpu_data),
        .cpu_ready(cpu_ready),
        .cpu_stall(cpu_stall),
        .mem_req  (blk_req),
        .mem_addr (blk_addr),
        .mem_ready(blk_ready),
        .mem_data (blk_data)
    );

    // -------------------------------------------------------------------------
    // Member 4: Four-word main-memory refill interface
    // -------------------------------------------------------------------------
    main_memory_interface u_main_memory_interface (
        .clk        (clk),
        .reset      (reset),
        .mem_req    (blk_req),
        .mem_addr   (blk_addr),
        .mem_ready  (blk_ready),
        .mem_data   (blk_data),
        .model_req  (mem_word_req),
        .model_addr (mem_word_addr),
        .model_ready(mem_word_ready),
        .model_data (mem_word_data)
    );

endmodule
