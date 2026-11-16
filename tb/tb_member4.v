`timescale 1ns/1ps

// =============================================================================
// Testbench: tb_member4
// Project: Direct-Mapped Cache Controller (1 KB Capacity, 16-Byte Block)
// Member: Member 4 — Main-Memory Interface and Model
//
// Scenarios Tested:
//   Test 1: Reset behavior and idle inactivity (including abort during active fetch)
//   Test 2: Word retrieval, verified ordering, and 128-bit block assembly
//   Test 3: 16-byte block alignment enforcement
//   Test 4: Configurable latency coverage (0, 1, 5, 10 clock cycles)
//   Test 5: Back-to-back block requests to different addresses
//   Test 6: Deterministic uninitialized memory pattern verification
//   Test 7: End-to-end integration with existing cache_controller.v:
//           - Cold cache miss and 4-word refill
//           - Valid CPU word delivery
//           - Subsequent post-refill cache hits with zero memory requests
//           - Cache line eviction and tag replacement on conflict miss
// =============================================================================

module tb_member4;

    // Master clock and reset
    reg clk;
    reg reset;

    // Mode select: 0 = Direct Interface Test, 1 = Cache Controller Integration Test
    reg ctrl_mode;

    // Direct interface test signals
    reg         tb_mem_req;
    reg  [31:0] tb_mem_addr;
    wire        if_mem_ready;
    wire [127:0] if_mem_data;

    // Interface to Memory Model signals
    wire        model_req;
    wire [31:0] model_addr;
    wire        model_ready;
    wire [31:0] model_data;

    // Cache Controller CPU Interface signals
    reg         cpu_req;
    reg  [31:0] cpu_addr;
    wire [31:0] cpu_data;
    wire        cpu_ready;
    wire        cpu_stall;

    // Cache Controller Memory Interface signals
    wire        cc_mem_req;
    wire [31:0] cc_mem_addr;

    // Multiplexed interface inputs
    wire        active_mem_req  = (ctrl_mode) ? cc_mem_req  : tb_mem_req;
    wire [31:0] active_mem_addr = (ctrl_mode) ? cc_mem_addr : tb_mem_addr;

    // Test tracking variables
    integer cycle_count;
    integer mem_req_counter;
    integer i;
    reg [31:0] captured_cpu_data;

    // =========================================================================
    // Module Instantiations
    // =========================================================================

    // 1. Member 4: Main Memory Interface (Unit Under Test)
    main_memory_interface u_interface (
        .clk        (clk),
        .reset      (reset),
        .mem_req    (active_mem_req),
        .mem_addr   (active_mem_addr),
        .mem_ready  (if_mem_ready),
        .mem_data   (if_mem_data),
        .model_req  (model_req),
        .model_addr (model_addr),
        .model_ready(model_ready),
        .model_data (model_data)
    );

    // 2. Member 4: Main Memory Model (Behavioral Backing Store)
    main_memory_model #(
        .DEFAULT_LATENCY(1)
    ) u_model (
        .clk  (clk),
        .reset(reset),
        .req  (model_req),
        .addr (model_addr),
        .ready(model_ready),
        .data (model_data)
    );

    // 3. Member 3: Cache Controller (for End-to-End Integration Test)
    cache_controller u_controller (
        .clk      (clk),
        .reset    (reset),
        .cpu_req  (cpu_req),
        .cpu_addr (cpu_addr),
        .cpu_data (cpu_data),
        .cpu_ready(cpu_ready),
        .cpu_stall(cpu_stall),
        .mem_req  (cc_mem_req),
        .mem_addr (cc_mem_addr),
        .mem_ready(if_mem_ready),
        .mem_data (if_mem_data)
    );

    // =========================================================================
    // Clock Generation (100 MHz, 10 ns period)
    // =========================================================================
    always #5 clk = ~clk;

    // Memory request monitor
    always @(posedge clk) begin
        if (active_mem_req) begin
            mem_req_counter <= mem_req_counter + 1;
        end
    end

    // =========================================================================
    // Helper Tasks for Verification
    // =========================================================================

    // Task to submit a 128-bit block read to main_memory_interface directly
    task send_mem_block_request;
        input  [31:0]  addr;
        output [127:0] block;
        output integer latency_cycles;
        integer timeout;
        begin
            @(posedge clk);
            tb_mem_addr = addr;
            tb_mem_req  = 1'b1;
            @(posedge clk);
            tb_mem_req  = 1'b0;

            timeout = 0;
            while (!if_mem_ready && timeout < 200) begin
                @(posedge clk);
                timeout = timeout + 1;
            end

            if (timeout >= 200) begin
                $fatal(1, "FAIL: Memory interface timed out awaiting mem_ready for addr 0x%08h", addr);
            end

            // Capture data on ready strobe
            block = if_mem_data;
            latency_cycles = timeout;

            // Verify single-pulse response on next clock cycle
            @(posedge clk);
            if (if_mem_ready) begin
                $fatal(1, "FAIL: mem_ready remained asserted for more than 1 clock cycle!");
            end
        end
    endtask

    // Task to submit a CPU read request to cache_controller
    task send_cpu_read_request;
        input  [31:0] addr;
        output [31:0] data;
        integer timeout;
        begin
            while (cpu_stall) @(posedge clk);

            @(posedge clk);
            cpu_addr = addr;
            cpu_req  = 1'b1;
            @(posedge clk);
            cpu_req  = 1'b0;

            timeout = 0;
            while (!cpu_ready && timeout < 250) begin
                @(posedge clk);
                timeout = timeout + 1;
            end

            if (timeout >= 250) begin
                $fatal(1, "FAIL: CPU request timed out for address 0x%08h", addr);
            end

            data = cpu_data;

            @(posedge clk);
            if (cpu_ready) begin
                $fatal(1, "FAIL: cpu_ready remained asserted for more than 1 clock cycle!");
            end
        end
    endtask

    // =========================================================================
    // Test Sequences
    // =========================================================================
    reg [127:0] captured_block;
    integer     elapsed;
    integer     prev_mem_reqs;

    initial begin
        // Signal Initialization
        clk             = 0;
        reset           = 0;
        ctrl_mode       = 0;
        tb_mem_req      = 0;
        tb_mem_addr     = 32'd0;
        cpu_req         = 0;
        cpu_addr        = 32'd0;
        mem_req_counter = 0;

        #10;

        $display("==================================================");
        $display("Starting Member 4 Testbench: Memory Interface & Model");
        $display("==================================================");

        // ---------------------------------------------------------------------
        // Test 1: Reset Behavior and Control Signal Inactivity
        // ---------------------------------------------------------------------
        $display("[Test 1] Apply reset and verify inactive controls in IDLE");
        @(posedge clk);
        reset = 1'b1;
        @(posedge clk);
        @(posedge clk);
        #1;
        reset = 1'b0;
        #1;

        if (if_mem_ready !== 1'b0) $fatal(1, "FAIL: Test 1 - mem_ready active after reset");
        if (model_req !== 1'b0)    $fatal(1, "FAIL: Test 1 - model_req active after reset");
        if (u_interface.state !== 3'b000)
            $fatal(1, "FAIL: Test 1 - Interface not in S_IDLE after reset (state = %b)", u_interface.state);

        // Test reset during active fetch: start request with latency=5 and reset mid-flight
        u_model.set_latency(5);
        @(posedge clk);
        tb_mem_addr = 32'h00001000;
        tb_mem_req  = 1'b1;
        @(posedge clk);
        tb_mem_req  = 1'b0;
        @(posedge clk);
        @(posedge clk); // Now fetching word 0
        reset = 1'b1;
        @(posedge clk);
        reset = 1'b0;
        #1;

        if (u_interface.state !== 3'b000)
            $fatal(1, "FAIL: Test 1 - Interface failed to abort to S_IDLE on mid-transfer reset");
        if (if_mem_ready !== 1'b0)
            $fatal(1, "FAIL: Test 1 - Spurious mem_ready observed after reset abort");
        $display("         Reset behavior verified cleanly (idle and mid-flight abort)");
        u_model.set_latency(1);

        // ---------------------------------------------------------------------
        // Test 2: Word Retrieval, Verified Ordering & 128-bit Block Assembly
        // ---------------------------------------------------------------------
        $display("[Test 2] Four-word retrieval, verified word ordering & 128-bit assembly");
        // Program distinct, known word patterns at 32'h00001000:
        //   Word 0 (+0x0): 32'h11223344
        //   Word 1 (+0x4): 32'h55667788
        //   Word 2 (+0x8): 32'h99AABBCC
        //   Word 3 (+0xC): 32'hDDEEFF00
        u_model.write_word(32'h00001000, 32'h11223344);
        u_model.write_word(32'h00001004, 32'h55667788);
        u_model.write_word(32'h00001008, 32'h99aabbcc);
        u_model.write_word(32'h0000100c, 32'hddeeff00);

        send_mem_block_request(32'h00001000, captured_block, elapsed);

        // Verify verified word ordering from existing RTL:
        //   mem_data[31:0]   = word0
        //   mem_data[63:32]  = word1
        //   mem_data[95:64]  = word2
        //   mem_data[127:96] = word3
        if (captured_block[31:0] !== 32'h11223344)
            $fatal(1, "FAIL: Test 2 - Word 0 mismatch: expected 0x11223344, got 0x%08h", captured_block[31:0]);
        if (captured_block[63:32] !== 32'h55667788)
            $fatal(1, "FAIL: Test 2 - Word 1 mismatch: expected 0x55667788, got 0x%08h", captured_block[63:32]);
        if (captured_block[95:64] !== 32'h99aabbcc)
            $fatal(1, "FAIL: Test 2 - Word 2 mismatch: expected 0x99aabbcc, got 0x%08h", captured_block[95:64]);
        if (captured_block[127:96] !== 32'hddeeff00)
            $fatal(1, "FAIL: Test 2 - Word 3 mismatch: expected 0xddeeff00, got 0x%08h", captured_block[127:96]);

        if (captured_block !== 128'hddeeff00_99aabbcc_55667788_11223344)
            $fatal(1, "FAIL: Test 2 - Full 128-bit block mismatch: got 0x%032h", captured_block);

        $display("         Verified word ordering confirmed: mem_data = {Word3, Word2, Word1, Word0}");

        // ---------------------------------------------------------------------
        // Test 3: 16-Byte Block Alignment Enforcement
        // ---------------------------------------------------------------------
        $display("[Test 3] 16-byte block alignment enforcement");
        // Request unaligned addresses: +0x4, +0x8, +0xE within the same 16-byte block
        send_mem_block_request(32'h00001004, captured_block, elapsed);
        if (captured_block !== 128'hddeeff00_99aabbcc_55667788_11223344)
            $fatal(1, "FAIL: Test 3 - Address 0x00001004 did not align to 16-byte block");

        send_mem_block_request(32'h00001008, captured_block, elapsed);
        if (captured_block !== 128'hddeeff00_99aabbcc_55667788_11223344)
            $fatal(1, "FAIL: Test 3 - Address 0x00001008 did not align to 16-byte block");

        send_mem_block_request(32'h0000100e, captured_block, elapsed);
        if (captured_block !== 128'hddeeff00_99aabbcc_55667788_11223344)
            $fatal(1, "FAIL: Test 3 - Address 0x0000100E did not align to 16-byte block");

        $display("         Alignment verified: unaligned addresses cleanly masked to 16-byte boundary");

        // ---------------------------------------------------------------------
        // Test 4: Configurable Latency Coverage (0, 1, 5, 10 cycles)
        // ---------------------------------------------------------------------
        $display("[Test 4] Configurable latency coverage (0, 1, 5, and 10 clock cycles)");

        // 4a: Latency = 0 (Immediate combinational response per word)
        u_model.set_latency(0);
        u_model.write_block(32'h00002000, 128'h03030303_02020202_01010101_00000000);
        send_mem_block_request(32'h00002000, captured_block, elapsed);
        if (captured_block !== 128'h03030303_02020202_01010101_00000000)
            $fatal(1, "FAIL: Test 4 - Latency 0 block data mismatch");
        $display("         Latency = 0 cycles verified (elapsed wait = %0d cycles)", elapsed);

        // 4b: Latency = 1 (1 clock cycle per word)
        u_model.set_latency(1);
        u_model.write_block(32'h00002010, 128'h13131313_12121212_11111111_10101010);
        send_mem_block_request(32'h00002010, captured_block, elapsed);
        if (captured_block !== 128'h13131313_12121212_11111111_10101010)
            $fatal(1, "FAIL: Test 4 - Latency 1 block data mismatch");
        $display("         Latency = 1 cycle verified (elapsed wait = %0d cycles)", elapsed);

        // 4c: Latency = 5 (5 clock cycles per word)
        u_model.set_latency(5);
        u_model.write_block(32'h00002020, 128'h53535353_52525252_51515151_50505050);
        send_mem_block_request(32'h00002020, captured_block, elapsed);
        if (captured_block !== 128'h53535353_52525252_51515151_50505050)
            $fatal(1, "FAIL: Test 4 - Latency 5 block data mismatch");
        $display("         Latency = 5 cycles verified (elapsed wait = %0d cycles)", elapsed);

        // 4d: Latency = 10 (10 clock cycles per word)
        u_model.set_latency(10);
        u_model.write_block(32'h00002030, 128'ha3a3a3a3_a2a2a2a2_a1a1a1a1_a0a0a0a0);
        send_mem_block_request(32'h00002030, captured_block, elapsed);
        if (captured_block !== 128'ha3a3a3a3_a2a2a2a2_a1a1a1a1_a0a0a0a0)
            $fatal(1, "FAIL: Test 4 - Latency 10 block data mismatch");
        $display("         Latency = 10 cycles verified (elapsed wait = %0d cycles)", elapsed);

        u_model.set_latency(1); // Restore standard latency

        // ---------------------------------------------------------------------
        // Test 5: Back-to-Back Requests to Different Blocks
        // ---------------------------------------------------------------------
        $display("[Test 5] Back-to-back consecutive requests to different blocks");
        u_model.write_block(32'h00003000, 128'h33333333_22222222_11111111_00000000);
        u_model.write_block(32'h00003010, 128'h77777777_66666666_55555555_44444444);
        u_model.write_block(32'h00003020, 128'hbbbbbbbb_aaaaaaaa_99999999_88888888);
        u_model.write_block(32'h00003030, 128'hffffffff_eeeeeeee_dddddddd_cccccccc);

        send_mem_block_request(32'h00003000, captured_block, elapsed);
        if (captured_block !== 128'h33333333_22222222_11111111_00000000)
            $fatal(1, "FAIL: Test 5 - Stream request 1 failed");

        send_mem_block_request(32'h00003010, captured_block, elapsed);
        if (captured_block !== 128'h77777777_66666666_55555555_44444444)
            $fatal(1, "FAIL: Test 5 - Stream request 2 failed");

        send_mem_block_request(32'h00003020, captured_block, elapsed);
        if (captured_block !== 128'hbbbbbbbb_aaaaaaaa_99999999_88888888)
            $fatal(1, "FAIL: Test 5 - Stream request 3 failed");

        send_mem_block_request(32'h00003030, captured_block, elapsed);
        if (captured_block !== 128'hffffffff_eeeeeeee_dddddddd_cccccccc)
            $fatal(1, "FAIL: Test 5 - Stream request 4 failed");

        $display("         Consecutive back-to-back block streams verified cleanly (4/4 passed)");

        // ---------------------------------------------------------------------
        // Test 6: Deterministic Initial Memory Contents
        // ---------------------------------------------------------------------
        $display("[Test 6] Deterministic default memory patterns for unwritten locations");
        send_mem_block_request(32'h00007800, captured_block, elapsed);
        // Verify non-zero and stable across multiple reads
        if (captured_block === 128'd0)
            $fatal(1, "FAIL: Test 6 - Unwritten memory returned all zeros");

        send_mem_block_request(32'h00007800, captured_block, elapsed);
        // Second read must match exactly
        if (captured_block[31:0] !== u_model.read_word(32'h00007800) ||
            captured_block[63:32] !== u_model.read_word(32'h00007804) ||
            captured_block[95:64] !== u_model.read_word(32'h00007808) ||
            captured_block[127:96] !== u_model.read_word(32'h0000780c))
            $fatal(1, "FAIL: Test 6 - Deterministic pattern mismatch against read_word()");

        $display("         Deterministic memory model pattern verified");

        // ---------------------------------------------------------------------
        // Test 7: End-to-End Integration with cache_controller.v
        // ---------------------------------------------------------------------
        $display("[Test 7] End-to-End Cache Controller Integration");
        ctrl_mode = 1; // Hand over interface control to cache_controller

        // Reset the entire integrated subsystem
        @(posedge clk);
        reset = 1'b1;
        @(posedge clk);
        @(posedge clk);
        reset = 1'b0;
        #1;

        if (u_controller.state !== 3'b000)
            $fatal(1, "FAIL: Test 7 - Cache controller not IDLE after reset");

        // Set memory block at 32'h00008040:
        // Tag = 22'h000020, Index = 6'd4 (6'b000100), Offset = 00 -> 32'h00008040
        u_model.write_block(32'h00008040, 128'hcafe0003_cafe0002_cafe0001_cafe0000);

        // 7a: Cold Cache Miss on CPU Read at 32'h00008044 (Word 1, offset 01)
        $display("         Step 7a: Cold Miss at 0x00008044 (triggers 4-word refill)");
        prev_mem_reqs = mem_req_counter;
        send_cpu_read_request(32'h00008044, captured_cpu_data);

        if (captured_cpu_data !== 32'hcafe0001)
            $fatal(1, "FAIL: Test 7a - Expected 0xcafe0001, got 0x%08h", captured_cpu_data);
        if (mem_req_counter !== prev_mem_reqs + 1)
            $fatal(1, "FAIL: Test 7a - Expected 1 memory request from cache controller");
        $display("         Refill complete: CPU received 0x%08h", captured_cpu_data);

        // 7b: Post-Refill Cache Hit on Word 2 (32'h00008048, offset 10)
        $display("         Step 7b: Post-Refill Hit at 0x00008048 (offset 10)");
        prev_mem_reqs = mem_req_counter;
        send_cpu_read_request(32'h00008048, captured_cpu_data);

        if (captured_cpu_data !== 32'hcafe0002)
            $fatal(1, "FAIL: Test 7b - Expected 0xcafe0002, got 0x%08h", captured_cpu_data);
        if (mem_req_counter !== prev_mem_reqs)
            $fatal(1, "FAIL: Test 7b - Memory request was generated on post-refill hit!");
        $display("         Cache hit passed: returned 0x%08h with zero memory transactions", captured_cpu_data);

        // 7c: Post-Refill Cache Hit on Word 0 (32'h00008040, offset 00)
        $display("         Step 7c: Post-Refill Hit at 0x00008040 (offset 00)");
        prev_mem_reqs = mem_req_counter;
        send_cpu_read_request(32'h00008040, captured_cpu_data);

        if (captured_cpu_data !== 32'hcafe0000)
            $fatal(1, "FAIL: Test 7c - Expected 0xcafe0000, got 0x%08h", captured_cpu_data);
        if (mem_req_counter !== prev_mem_reqs)
            $fatal(1, "FAIL: Test 7c - Memory request generated on hit!");

        // 7d: Post-Refill Cache Hit on Word 3 (32'h0000804C, offset 11)
        $display("         Step 7d: Post-Refill Hit at 0x0000804C (offset 11)");
        prev_mem_reqs = mem_req_counter;
        send_cpu_read_request(32'h0000804c, captured_cpu_data);

        if (captured_cpu_data !== 32'hcafe0003)
            $fatal(1, "FAIL: Test 7d - Expected 0xcafe0003, got 0x%08h", captured_cpu_data);
        if (mem_req_counter !== prev_mem_reqs)
            $fatal(1, "FAIL: Test 7d - Memory request generated on hit!");

        // 7e: Conflict Miss & Line Replacement at Index 4 (Tag 22'h000030)
        // Address: {22'h000030, 6'd4, 2'b00, 2'b00} = 32'h0000C040
        $display("         Step 7e: Conflict Miss & Replacement at Index 4");
        u_model.write_block(32'h0000c040, 128'hbabe0003_babe0002_babe0001_babe0000);

        prev_mem_reqs = mem_req_counter;
        send_cpu_read_request(32'h0000c040, captured_cpu_data);

        if (captured_cpu_data !== 32'hbabe0000)
            $fatal(1, "FAIL: Test 7e - Expected replaced word 0xbabe0000, got 0x%08h", captured_cpu_data);
        if (mem_req_counter !== prev_mem_reqs + 1)
            $fatal(1, "FAIL: Test 7e - Expected 1 memory request for replacement");

        // Verify Address B is now cached as a Hit
        prev_mem_reqs = mem_req_counter;
        send_cpu_read_request(32'h0000c040, captured_cpu_data);
        if (captured_cpu_data !== 32'hbabe0000)
            $fatal(1, "FAIL: Test 7e - Expected cache hit on 0x0000C040");
        if (mem_req_counter !== prev_mem_reqs)
            $fatal(1, "FAIL: Test 7e - Memory transaction occurred on hit!");

        $display("         Cache line replacement and re-fetch verified successfully");

        // ---------------------------------------------------------------------
        // Summary
        // ---------------------------------------------------------------------
        $display("==================================================");
        $display("PASS: Member 4 Memory Interface & Model all PASSED!");
        $display("==================================================");
        $finish;
    end

endmodule
