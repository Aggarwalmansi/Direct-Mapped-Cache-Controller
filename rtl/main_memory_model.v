`timescale 1ns/1ps

// =============================================================================
// Module: main_memory_model
// Project: Direct-Mapped Cache Controller (1 KB Capacity, 16-Byte Block)
// Member: Member 4 — Main-Memory Interface and Model
//
// Description:
//   Simulation-only behavioral model of main memory.
//   Provides a 32-bit word-read interface with configurable response latency
//   (including 0, 1, 5, 10, or arbitrary clock cycles) and deterministic
//   initial contents.
//
//   Supports dynamic overrides via simulation tasks (write_word, write_block,
//   set_latency) and returns a unique, predictable, address-dependent default
//   pattern for uninitialized locations.
// =============================================================================

module main_memory_model #(
    parameter DEFAULT_LATENCY = 1
)(
    input  wire        clk,
    input  wire        reset,
    input  wire        req,       // Active-high request for 32-bit read
    input  wire [31:0] addr,      // 32-bit byte address of the requested word (word-aligned)
    output wire        ready,     // Active-high 1-cycle data valid strobe
    output wire [31:0] data       // 32-bit read data
);

    // =========================================================================
    // Internal Storage & Override Table
    // =========================================================================
    // Associative table for testbench-directed block/word overrides
    reg [31:0] override_addr [0:255];
    reg [31:0] override_data [0:255];
    integer    override_count;

    // Runtime-configurable latency
    integer latency;

    // Internal timing registers for multi-cycle latency
    integer timer;
    reg     busy;
    reg [31:0] pending_addr;
    reg        reg_ready;
    reg [31:0] reg_data;

    // =========================================================================
    // Memory Lookup & Deterministic Default Function
    // =========================================================================
    // Generates a deterministic, unique, non-zero 32-bit word for any address
    function [31:0] get_default_word;
        input [31:0] byte_addr;
        reg [31:0] aligned;
        begin
            aligned = {byte_addr[31:2], 2'b00};
            // Upper 16 bits: XOR mask with address; Lower 16 bits: address inverted
            get_default_word = {aligned[31:16] ^ 16'h5a5a, aligned[15:2], 2'b00} ^ 32'ha5a5a5a5;
        end
    endfunction

    // Looks up word in override table; falls back to deterministic default
    function [31:0] read_word;
        input [31:0] byte_addr;
        integer k;
        reg [31:0] aligned;
        reg found;
        begin
            aligned = {byte_addr[31:2], 2'b00};
            found = 0;
            read_word = get_default_word(aligned);
            for (k = 0; k < override_count; k = k + 1) begin
                if (!found && (override_addr[k] == aligned)) begin
                    read_word = override_data[k];
                    found = 1;
                end
            end
        end
    endfunction

    // =========================================================================
    // Simulation Helper Tasks (for Testbench Control)
    // =========================================================================
    // Set a 32-bit word at a word-aligned byte address
    task write_word;
        input [31:0] byte_addr;
        input [31:0] word_val;
        integer k;
        reg found;
        reg [31:0] aligned;
        begin
            aligned = {byte_addr[31:2], 2'b00};
            found = 0;
            for (k = 0; k < override_count; k = k + 1) begin
                if (!found && (override_addr[k] == aligned)) begin
                    override_data[k] = word_val;
                    found = 1;
                end
            end
            if (!found && override_count < 256) begin
                override_addr[override_count] = aligned;
                override_data[override_count] = word_val;
                override_count = override_count + 1;
            end
        end
    endtask

    // Set a full 128-bit block at a 16-byte aligned address
    // Exact word ordering:
    //   word 0 at block_addr + 0  = block_val[31:0]
    //   word 1 at block_addr + 4  = block_val[63:32]
    //   word 2 at block_addr + 8  = block_val[95:64]
    //   word 3 at block_addr + 12 = block_val[127:96]
    task write_block;
        input [31:0]  block_addr;
        input [127:0] block_val;
        reg [31:0] base;
        begin
            base = {block_addr[31:4], 4'b0000};
            write_word(base + 32'd0,  block_val[31:0]);
            write_word(base + 32'd4,  block_val[63:32]);
            write_word(base + 32'd8,  block_val[95:64]);
            write_word(base + 32'd12, block_val[127:96]);
        end
    endtask

    // Configure read latency dynamically
    task set_latency;
        input integer new_latency;
        begin
            latency = new_latency;
        end
    endtask

    // Clear all overrides back to default pattern
    task clear_memory;
        begin
            override_count = 0;
        end
    endtask

    // =========================================================================
    // Initial Setup
    // =========================================================================
    initial begin
        override_count = 0;
        latency        = DEFAULT_LATENCY;
        timer          = 0;
        busy           = 0;
        pending_addr   = 32'd0;
        reg_ready      = 1'b0;
        reg_data       = 32'd0;
    end

    // =========================================================================
    // Response Timing Logic
    // =========================================================================
    // For zero-latency (latency == 0), response is delivered combinationally
    // in the same cycle as req. For latency > 0, response is delivered after
    // the configured number of clock cycles as a 1-cycle strobe.
    assign ready = (latency == 0) ? req : reg_ready;
    assign data  = (latency == 0) ? read_word(addr) : reg_data;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            reg_ready    <= 1'b0;
            reg_data     <= 32'd0;
            busy         <= 1'b0;
            timer        <= 0;
            pending_addr <= 32'd0;
        end else begin
            // Default 1-cycle pulse
            reg_ready <= 1'b0;

            if (req && !busy && (latency > 0)) begin
                if (latency == 1) begin
                    // 1 cycle delay: ready on the very next clock edge
                    reg_ready    <= 1'b1;
                    reg_data     <= read_word(addr);
                    busy         <= 1'b0;
                    timer        <= 0;
                    pending_addr <= addr;
                end else begin
                    // Multi-cycle delay: count down latency - 1
                    busy         <= 1'b1;
                    timer        <= latency - 1;
                    pending_addr <= addr;
                end
            end else if (busy) begin
                if (timer == 1) begin
                    reg_ready <= 1'b1;
                    reg_data  <= read_word(pending_addr);
                    busy      <= 1'b0;
                    timer     <= 0;
                end else begin
                    timer <= timer - 1;
                end
            end
        end
    end

endmodule
