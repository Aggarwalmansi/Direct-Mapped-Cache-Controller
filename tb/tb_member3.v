`timescale 1ns/1ps

// =============================================================================
// Testbench: tb_member3
// Project: Direct-Mapped Cache Controller (1 KB Capacity, 16-Byte Block)
// Member: Member 3 — Controller FSM & Datapath Integration
//
// Scenarios Tested:
//   Test 1: Reset Behavior and Control Signal Inactivity
//   Test 2: Cache Hit on Pre-loaded Line (No Memory Access)
//   Test 3: Cache Miss Detection and CPU Stall Enforcement
//   Test 4: Main Memory Refill and Cache Line Storage Update
//   Test 5: Post-Refill Hit on Same Address (No Memory Access)
//   Test 6: Word Selection across all 4 Word Offsets (00, 01, 10, 11)
//   Test 7: Variable / Multi-Cycle Memory Latency Handling
//   Test 8: Conflicting Addresses (Same Index, Different Tags — Line Replacement)
//   Test 9: Consecutive Back-to-Back Requests with Single-Pulse Handshakes
// =============================================================================

module tb_member3;

    // Clock and Reset signals
    reg         clk;
    reg         reset;

    // CPU Interface signals
    reg         cpu_req;
    reg  [31:0] cpu_addr;
    wire [31:0] cpu_data;
    wire        cpu_ready;
    wire        cpu_stall;

    // Main Memory Interface signals
    wire        mem_req;
    wire [31:0] mem_addr;
    reg         mem_ready;
    reg  [127:0] mem_data;

    // Testbench tracking variables
    integer i;
    integer mem_req_count;
    integer mem_latency;
    integer mem_timer;
    reg     mem_busy;
    reg [127:0] pending_block;
    reg [31:0]  captured_data;

    // =========================================================================
    // Mock Main Memory Associative Storage Table
    // =========================================================================
    reg [31:0]  mem_table_addr  [0:63];
    reg [127:0] mem_table_block [0:63];
    integer     mem_table_count;

    task set_mem_block;
        input [31:0]  addr;
        input [127:0] block;
        integer k;
        reg found;
        begin
            found = 0;
            for (k = 0; k < mem_table_count; k = k + 1) begin
                if (mem_table_addr[k] == (addr & 32'hfffffff0)) begin
                    mem_table_block[k] = block;
                    found = 1;
                end
            end
            if (!found && mem_table_count < 64) begin
                mem_table_addr[mem_table_count]  = (addr & 32'hfffffff0);
                mem_table_block[mem_table_count] = block;
                mem_table_count = mem_table_count + 1;
            end
        end
    endtask

    function [127:0] lookup_mem;
        input [31:0] addr;
        integer k;
        begin
            lookup_mem = {addr, addr, addr, addr}; // default pattern
            for (k = 0; k < mem_table_count; k = k + 1) begin
                if (mem_table_addr[k] == (addr & 32'hfffffff0)) begin
                    lookup_mem = mem_table_block[k];
                end
            end
        end
    endfunction

    // Instantiate Unit Under Test (UUT)
    cache_controller uut (
        .clk      (clk),
        .reset    (reset),
        .cpu_req  (cpu_req),
        .cpu_addr (cpu_addr),
        .cpu_data (cpu_data),
        .cpu_ready(cpu_ready),
        .cpu_stall(cpu_stall),
        .mem_req  (mem_req),
        .mem_addr (mem_addr),
        .mem_ready(mem_ready),
        .mem_data (mem_data)
    );

    // 100 MHz clock generation (10 ns period)
    always #5 clk = ~clk;

    // =========================================================================
    // Mock Main Memory Handler with Configurable Latency
    // =========================================================================
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            mem_ready     <= 1'b0;
            mem_data      <= 128'd0;
            mem_req_count <= 0;
            mem_busy      <= 1'b0;
            mem_timer     <= 0;
            pending_block <= 128'd0;
        end else begin
            // Default 1-cycle ready strobe
            mem_ready <= 1'b0;

            if (mem_req) begin
                mem_req_count <= mem_req_count + 1;
                if (mem_latency == 0) begin
                    // Zero wait-state response
                    mem_ready <= 1'b1;
                    mem_data  <= lookup_mem(mem_addr);
                end else begin
                    mem_busy      <= 1'b1;
                    mem_timer     <= mem_latency;
                    pending_block <= lookup_mem(mem_addr);
                end
            end else if (mem_busy) begin
                if (mem_timer == 1) begin
                    mem_ready <= 1'b1;
                    mem_data  <= pending_block;
                    mem_busy  <= 1'b0;
                    mem_timer <= 0;
                end else begin
                    mem_timer <= mem_timer - 1;
                end
            end
        end
    end

    // =========================================================================
    // Helper Task: Submit CPU Request and Await Response
    // =========================================================================
    task cpu_read_request;
        input  [31:0] addr;
        output [31:0] data;
        integer timeout;
        begin
            // Wait if controller is busy
            while (cpu_stall) @(posedge clk);

            // Assert CPU request for 1 clock cycle
            @(posedge clk);
            cpu_addr = addr;
            cpu_req  = 1'b1;

            @(posedge clk);
            cpu_req  = 1'b0;

            // Wait for cpu_ready strobe with timeout protection
            timeout = 0;
            while (!cpu_ready && timeout < 100) begin
                @(posedge clk);
                timeout = timeout + 1;
            end

            if (timeout >= 100) begin
                $fatal(1, "FAIL: CPU request timed out for address 0x%08h", addr);
            end

            // Capture valid data
            data = cpu_data;

            // Verify single-pulse response on the next clock cycle
            @(posedge clk);
            if (cpu_ready) begin
                $fatal(1, "FAIL: Duplicate cpu_ready response detected for address 0x%08h", addr);
            end
        end
    endtask

    // =========================================================================
    // Test Sequences
    // =========================================================================
    integer prev_reqs;

    initial begin
        // Initialize inputs
        clk             = 0;
        reset           = 0;
        cpu_req         = 0;
        cpu_addr        = 32'd0;
        mem_latency     = 1;
        mem_req_count   = 0;
        mem_table_count = 0;

        #10;

        $display("==================================================");
        $display("Starting Member 3 Testbench: Cache Controller FSM");
        $display("==================================================");

        // ---------------------------------------------------------------------
        // Test 1: Reset Behavior and Control Signal Inactivity
        // ---------------------------------------------------------------------
        $display("[Test 1] Apply reset and verify IDLE state, inactive signals, cleared valid bits");
        @(posedge clk);
        reset = 1'b1;
        @(posedge clk);
        @(posedge clk);
        #1;
        reset = 1'b0;
        #1;

        if (uut.state !== 3'b000)
            $fatal(1, "FAIL: Test 1 - FSM state not IDLE after reset (state = %b)", uut.state);
        if (cpu_stall !== 1'b0)
            $fatal(1, "FAIL: Test 1 - cpu_stall active after reset");
        if (cpu_ready !== 1'b0)
            $fatal(1, "FAIL: Test 1 - cpu_ready active after reset");
        if (mem_req !== 1'b0)
            $fatal(1, "FAIL: Test 1 - mem_req active after reset");

        for (i = 0; i < 64; i = i + 1) begin
            if (uut.u_valid_ram.ram[i] !== 1'b0)
                $fatal(1, "FAIL: Test 1 - Valid bit for line %0d not cleared on reset", i);
        end
        $display("         Reset verified: all 64 valid bits cleared, controller in IDLE");

        // ---------------------------------------------------------------------
        // Test 2: Cache Hit on Pre-loaded Line (No Memory Access)
        // ---------------------------------------------------------------------
        $display("[Test 2] Cache Hit on pre-loaded cache line (verify correct word, no mem_req)");
        // Pre-load line 5:
        // tag = 22'h1ABCDE, index = 6'd5, valid = 1'b1
        // data block = {128'hdeadbeef_cafebabe_baadf00d_12345678}
        // Address: {22'h1ABCDE, 6'd5, 2'b00, 2'b00} = 32'h6AF37850
        uut.u_data_ram.ram[5]  = 128'hdeadbeef_cafebabe_baadf00d_12345678;
        uut.u_tag_ram.ram[5]   = 22'h1abcde;
        uut.u_valid_ram.ram[5] = 1'b1;

        prev_reqs = mem_req_count;
        cpu_read_request(32'h6af37850, captured_data);

        if (captured_data !== 32'h12345678)
            $fatal(1, "FAIL: Test 2 - Expected word 0x12345678, got 0x%08h", captured_data);
        if (mem_req_count !== prev_reqs)
            $fatal(1, "FAIL: Test 2 - Memory request generated on cache hit!");
        $display("         Cache hit passed: returned 0x%08h, zero memory requests", captured_data);

        // ---------------------------------------------------------------------
        // Test 3 & 4: Cache Miss and Memory Refill
        // ---------------------------------------------------------------------
        $display("[Test 3 & 4] Cache Miss detection, CPU stall, Memory Request and Refill");
        // Target: line 12 (valid = 0 initially)
        // Tag = 22'h055555, index = 6'd12 (6'b001100), word_offset = 2'b01, byte_offset = 2'b00
        // Address: {22'h055555, 6'b001100, 2'b01, 2'b00} = 32'h155554C4
        // Block address: 32'h155554C0
        set_mem_block(32'h155554c0, 128'h11111111_22222222_33333333_44444444);

        prev_reqs = mem_req_count;
        cpu_read_request(32'h155554c4, captured_data);

        // Verify correct word returned (word_offset 01 -> word 1 = 32'h33333333)
        if (captured_data !== 32'h33333333)
            $fatal(1, "FAIL: Test 4 - Expected refill word 0x33333333, got 0x%08h", captured_data);

        // Verify exactly one memory request was generated
        if (mem_req_count !== prev_reqs + 1)
            $fatal(1, "FAIL: Test 4 - Expected 1 memory request, got %0d", mem_req_count - prev_reqs);

        // Verify cache storage was updated
        if (uut.u_data_ram.ram[12] !== 128'h11111111_22222222_33333333_44444444)
            $fatal(1, "FAIL: Test 4 - Cache data RAM line 12 not updated correctly");
        if (uut.u_tag_ram.ram[12] !== 22'h055555)
            $fatal(1, "FAIL: Test 4 - Tag RAM line 12 not updated with 0x055555");
        if (uut.u_valid_ram.ram[12] !== 1'b1)
            $fatal(1, "FAIL: Test 4 - Valid bit for line 12 not set to 1");

        $display("         Refill verified: block written, tag=0x055555, valid=1, returned 0x%08h", captured_data);

        // ---------------------------------------------------------------------
        // Test 5: Post-Refill Hit
        // ---------------------------------------------------------------------
        $display("[Test 5] Post-Refill Hit: submit same address again, verify hit with no mem_req");
        prev_reqs = mem_req_count;
        cpu_read_request(32'h155554c4, captured_data);

        if (captured_data !== 32'h33333333)
            $fatal(1, "FAIL: Test 5 - Post-refill read mismatch: expected 0x33333333, got 0x%08h", captured_data);
        if (mem_req_count !== prev_reqs)
            $fatal(1, "FAIL: Test 5 - Memory request generated on post-refill hit!");
        $display("         Post-refill hit passed: returned 0x%08h without memory transaction", captured_data);

        // ---------------------------------------------------------------------
        // Test 6: Different Word Offsets (00, 01, 10, 11)
        // ---------------------------------------------------------------------
        $display("[Test 6] Read all 4 word offsets from cached line 12");
        // Offset 00: 32'h155554C0 -> word 0: 32'h44444444
        prev_reqs = mem_req_count;
        cpu_read_request(32'h155554c0, captured_data);
        if (captured_data !== 32'h44444444)
            $fatal(1, "FAIL: Test 6 - Offset 00 expected 0x44444444, got 0x%08h", captured_data);

        // Offset 01: 32'h155554C4 -> word 1: 32'h33333333
        cpu_read_request(32'h155554c4, captured_data);
        if (captured_data !== 32'h33333333)
            $fatal(1, "FAIL: Test 6 - Offset 01 expected 0x33333333, got 0x%08h", captured_data);

        // Offset 10: 32'h155554C8 -> word 2: 32'h22222222
        cpu_read_request(32'h155554c8, captured_data);
        if (captured_data !== 32'h22222222)
            $fatal(1, "FAIL: Test 6 - Offset 10 expected 0x22222222, got 0x%08h", captured_data);

        // Offset 11: 32'h155554CC -> word 3: 32'h11111111
        cpu_read_request(32'h155554cc, captured_data);
        if (captured_data !== 32'h11111111)
            $fatal(1, "FAIL: Test 6 - Offset 11 expected 0x11111111, got 0x%08h", captured_data);

        if (mem_req_count !== prev_reqs)
            $fatal(1, "FAIL: Test 6 - Memory requests generated during word offset hit tests!");
        $display("         All 4 word offsets (00, 01, 10, 11) verified correctly on cache hits");

        // ---------------------------------------------------------------------
        // Test 7: Delayed Memory Response (Multi-Cycle Memory Latency)
        // ---------------------------------------------------------------------
        $display("[Test 7] Delayed memory response (latency = 6 clock cycles)");
        mem_latency = 6;
        // Address: line 20, tag = 22'h0AAAAA, word_offset = 2'b10
        // Address: {22'h0AAAAA, 6'd20, 2'b10, 2'b00} = 32'h2AAAA948
        set_mem_block(32'h2aaaa940, 128'ha1a2a3a4_b1b2b3b4_c1c2c3c4_d1d2d3d4);

        prev_reqs = mem_req_count;

        // Initiate request manually to inspect cycle-by-cycle stall and wait behavior
        @(posedge clk);
        cpu_addr = 32'h2aaaa948;
        cpu_req  = 1'b1;
        @(posedge clk);
        cpu_req  = 1'b0;

        // Cycle 1: LOOKUP
        #1;
        if (cpu_stall !== 1'b1) $fatal(1, "FAIL: Test 7 - CPU not stalled during LOOKUP");

        // Cycle 2: MISS_REQUEST (mem_req asserted)
        @(posedge clk);
        #1;
        if (mem_req !== 1'b1) $fatal(1, "FAIL: Test 7 - mem_req not asserted in MISS_REQUEST");
        if (mem_addr !== 32'h2aaaa940)
            $fatal(1, "FAIL: Test 7 - mem_addr incorrect: expected 0x2aaaa940, got 0x%08h", mem_addr);

        // Cycle 3: Enters WAIT_MEMORY (mem_req must deassert, CPU must remain stalled)
        @(posedge clk);
        #1;
        if (mem_req !== 1'b0) $fatal(1, "FAIL: Test 7 - mem_req not deasserted in WAIT_MEMORY");
        if (cpu_stall !== 1'b1) $fatal(1, "FAIL: Test 7 - CPU stall released prematurely");

        // Monitor while memory is busy: ensure no duplicate mem_req and no premature cpu_ready
        while (!cpu_ready) begin
            if (mem_req !== 1'b0)
                $fatal(1, "FAIL: Test 7 - Duplicate mem_req asserted during WAIT_MEMORY");
            if (cpu_stall !== 1'b1)
                $fatal(1, "FAIL: Test 7 - cpu_stall dropped prematurely");
            @(posedge clk);
            #1;
        end

        // On cpu_ready: capture and check data (word_offset 10 -> word 2 = 32'hb1b2b3b4)
        if (cpu_data !== 32'hb1b2b3b4)
            $fatal(1, "FAIL: Test 7 - Data mismatch after delayed refill: expected 0xb1b2b3b4, got 0x%08h", cpu_data);

        // Next cycle: cpu_ready must drop
        @(posedge clk);
        #1;
        if (cpu_ready !== 1'b0)
            $fatal(1, "FAIL: Test 7 - Duplicate cpu_ready response pulse detected");
        if (cpu_stall !== 1'b0)
            $fatal(1, "FAIL: Test 7 - cpu_stall not deasserted upon returning to IDLE");

        if (mem_req_count !== prev_reqs + 1)
            $fatal(1, "FAIL: Test 7 - Expected exactly 1 memory request, got %0d", mem_req_count - prev_reqs);

        $display("         Delayed memory response passed: waited 6 cycles, single pulse response");
        mem_latency = 1; // Restore default latency

        // ---------------------------------------------------------------------
        // Test 8: Conflicting Addresses (Same Index, Different Tags — Replacement)
        // ---------------------------------------------------------------------
        $display("[Test 8] Conflicting Addresses: line replacement at index 15");
        // Address A: Tag = 22'h111111, index = 6'd15, offset = 00 -> 32'h444444F0
        // Address B: Tag = 22'h222222, index = 6'd15, offset = 00 -> 32'h888888F0
        set_mem_block(32'h444444f0, 128'haaaa0003_aaaa0002_aaaa0001_aaaa0000);
        set_mem_block(32'h888888f0, 128'hbbbb0003_bbbb0002_bbbb0001_bbbb0000);

        // Step 8a: Request Address A (Miss & Refill)
        prev_reqs = mem_req_count;
        cpu_read_request(32'h444444f0, captured_data);
        if (captured_data !== 32'haaaa0000)
            $fatal(1, "FAIL: Test 8 - Address A read mismatch: expected 0xaaaa0000, got 0x%08h", captured_data);
        if (uut.u_tag_ram.ram[15] !== 22'h111111)
            $fatal(1, "FAIL: Test 8 - Tag RAM line 15 not updated with Address A tag");
        $display("         Address A cached at line 15 (Tag = 0x111111)");

        // Step 8b: Request Address B (Conflict Miss & Replace Line 15)
        prev_reqs = mem_req_count;
        cpu_read_request(32'h888888f0, captured_data);
        if (captured_data !== 32'hbbbb0000)
            $fatal(1, "FAIL: Test 8 - Address B read mismatch: expected 0xbbbb0000, got 0x%08h", captured_data);
        if (mem_req_count !== prev_reqs + 1)
            $fatal(1, "FAIL: Test 8 - Expected memory request for conflicting Address B");
        if (uut.u_tag_ram.ram[15] !== 22'h222222)
            $fatal(1, "FAIL: Test 8 - Tag RAM line 15 not replaced with Address B tag 0x222222");
        if (uut.u_data_ram.ram[15] !== 128'hbbbb0003_bbbb0002_bbbb0001_bbbb0000)
            $fatal(1, "FAIL: Test 8 - Data RAM line 15 not replaced with Address B block");
        $display("         Address B successfully replaced Address A at line 15 (Tag = 0x222222)");

        // Step 8c: Request Address B again (Now a Hit!)
        prev_reqs = mem_req_count;
        cpu_read_request(32'h888888f0, captured_data);
        if (captured_data !== 32'hbbbb0000)
            $fatal(1, "FAIL: Test 8 - Address B hit mismatch: expected 0xbbbb0000, got 0x%08h", captured_data);
        if (mem_req_count !== prev_reqs)
            $fatal(1, "FAIL: Test 8 - Memory request occurred on hit for Address B!");
        $display("         Address B verified as cache hit after replacement");

        // Step 8d: Request Address A again (Now a Miss, replaces B!)
        prev_reqs = mem_req_count;
        cpu_read_request(32'h444444f0, captured_data);
        if (captured_data !== 32'haaaa0000)
            $fatal(1, "FAIL: Test 8 - Address A re-fetch mismatch");
        if (mem_req_count !== prev_reqs + 1)
            $fatal(1, "FAIL: Test 8 - Memory request missing on re-fetch of Address A");
        if (uut.u_tag_ram.ram[15] !== 22'h111111)
            $fatal(1, "FAIL: Test 8 - Tag RAM line 15 not restored to Address A tag");
        $display("         Address A re-fetched and replaced Address B correctly");

        // ---------------------------------------------------------------------
        // Test 9: Consecutive Requests (Back-to-Back Transactions)
        // ---------------------------------------------------------------------
        $display("[Test 9] Consecutive back-to-back requests (hits and misses)");
        set_mem_block(32'h333333e0, 128'h03030303_02020202_01010101_00000000);
        set_mem_block(32'h555555d0, 128'hffff0003_ffff0002_ffff0001_ffff0000);

        // Req 1: Hit on line 15 (Tag 0x111111, offset 00)
        cpu_read_request(32'h444444f0, captured_data);
        if (captured_data !== 32'haaaa0000) $fatal(1, "FAIL: Test 9 - Req 1 data mismatch");

        // Req 2: Miss on line 30 -> Tag = 22'h0CCCCC, index = 6'd30, offset 01 -> 32'h333333E4
        cpu_read_request(32'h333333e4, captured_data);
        if (captured_data !== 32'h01010101) $fatal(1, "FAIL: Test 9 - Req 2 data mismatch");

        // Req 3: Hit on line 30 (offset 10 -> word 2: 32'h02020202)
        cpu_read_request(32'h333333e8, captured_data);
        if (captured_data !== 32'h02020202) $fatal(1, "FAIL: Test 9 - Req 3 data mismatch");

        // Req 4: Miss on line 45 -> Tag = 22'h155555, index = 6'd45, offset 00 -> 32'h555555D0
        cpu_read_request(32'h555555d0, captured_data);
        if (captured_data !== 32'hffff0000) $fatal(1, "FAIL: Test 9 - Req 4 data mismatch");

        // Req 5: Hit on line 5 (from Test 2, offset 11 -> word 3: 32'hdeadbeef)
        cpu_read_request(32'h6af3785c, captured_data);
        if (captured_data !== 32'hdeadbeef) $fatal(1, "FAIL: Test 9 - Req 5 data mismatch");

        // Req 6: Hit on line 45 (offset 11 -> word 3: 32'hffff0003)
        cpu_read_request(32'h555555dc, captured_data);
        if (captured_data !== 32'hffff0003) $fatal(1, "FAIL: Test 9 - Req 6 data mismatch");

        $display("         Consecutive requests verified: 6/6 requests completed cleanly");

        // ---------------------------------------------------------------------
        // Summary
        // ---------------------------------------------------------------------
        $display("==================================================");
        $display("PASS: Member 3 Cache Controller all tests PASSED!");
        $display("==================================================");
        $finish;
    end

endmodule
