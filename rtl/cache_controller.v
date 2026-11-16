`timescale 1ns/1ps

// =============================================================================
// Module: cache_controller
// Project: Direct-Mapped Cache Controller (1 KB Capacity, 16-Byte Block)
// Member: Member 3 — Controller FSM & Datapath Integration
//
// Description:
//   Finite State Machine and controller logic managing the direct-mapped cache.
//   Integrates Member 1 modules (address_decoder, tag_comparator) and Member 2
//   modules (cache_data_ram, tag_ram, valid_bit_ram).
//
//   Handles CPU request acceptance, cache lookup, hit response, miss detection,
//   main memory refill with variable latency, cache line replacement, and CPU
//   response generation with single-pulse handshake and stall enforcement.
// =============================================================================

module cache_controller (
    // Clock and Active-High Reset
    input  wire         clk,
    input  wire         reset,

    // CPU Interface
    input  wire         cpu_req,    // Active-high CPU memory read request
    input  wire [31:0]  cpu_addr,   // 32-bit CPU target address
    output wire [31:0]  cpu_data,   // 32-bit data word returned to CPU
    output reg          cpu_ready,  // Active-high 1-cycle strobe indicating valid cpu_data
    output wire         cpu_stall,  // Active-high stall signal (controller busy)

    // Main Memory Interface
    output reg          mem_req,    // Active-high 1-cycle memory request strobe
    output wire [31:0]  mem_addr,   // 32-bit 16-byte aligned block address
    input  wire         mem_ready,  // Active-high indicator that mem_data is valid
    input  wire [127:0] mem_data    // 128-bit cache block from main memory
);

    // =========================================================================
    // FSM State Definitions (7 States)
    // =========================================================================
    localparam [2:0]
        S_IDLE          = 3'b000,   // Wait for CPU request
        S_LOOKUP        = 3'b001,   // Decode address and evaluate hit/miss
        S_HIT_RESPONSE  = 3'b010,   // Return hit data to CPU
        S_MISS_REQUEST  = 3'b011,   // Generate main memory block request
        S_WAIT_MEMORY   = 3'b100,   // Wait for main memory response
        S_REFILL        = 3'b101,   // Write refill block, tag, and valid bit into RAMs
        S_MISS_RESPONSE = 3'b110;   // Return requested word to CPU after refill

    reg [2:0] state, next_state;

    // =========================================================================
    // Internal Registers
    // =========================================================================
    reg [31:0]  latched_address;    // Latched CPU address preserved through transaction
    reg [127:0] refill_buffer;      // Latched 128-bit block returned by memory
    reg [31:0]  latched_cpu_data;   // Registered 32-bit word returned to CPU

    // =========================================================================
    // Member 1: Address Decoder
    // =========================================================================
    wire [21:0] dec_tag;
    wire [5:0]  dec_index;
    wire [1:0]  dec_word_offset;
    wire [1:0]  dec_byte_offset;
    wire [31:0] dec_block_addr;

    address_decoder u_decoder (
        .address      (latched_address),
        .tag          (dec_tag),
        .index        (dec_index),
        .word_offset  (dec_word_offset),
        .byte_offset  (dec_byte_offset),
        .block_address(dec_block_addr)
    );

    // Memory request address is the 16-byte aligned block address
    assign mem_addr = dec_block_addr;

    // =========================================================================
    // Member 2: Cache Storage RAMs
    // =========================================================================
    // 1. Tag RAM
    wire [21:0] stored_tag;
    reg         tag_we;

    tag_ram u_tag_ram (
        .clk         (clk),
        .index       (dec_index),
        .read_tag    (stored_tag),
        .write_enable(tag_we),
        .write_tag   (dec_tag)
    );

    // 2. Valid Bit RAM
    wire stored_valid;
    reg  valid_we;
    reg  valid_write_val;

    valid_bit_ram u_valid_ram (
        .clk         (clk),
        .reset       (reset),
        .index       (dec_index),
        .valid_bit   (stored_valid),
        .write_enable(valid_we),
        .write_valid (valid_write_val)
    );

    // =========================================================================
    // Member 1: Tag Comparator
    // =========================================================================
    wire cache_hit;

    tag_comparator u_comparator (
        .requested_tag(dec_tag),
        .stored_tag   (stored_tag),
        .valid        (stored_valid),
        .hit          (cache_hit)
    );

    // =========================================================================
    // Member 2: Cache Data RAM
    // =========================================================================
    wire [31:0] cache_read_word;
    reg         data_we;

    cache_data_ram u_data_ram (
        .clk         (clk),
        .index       (dec_index),
        .word_offset (dec_word_offset),
        .read_data   (cache_read_word),
        .write_enable(data_we),
        .write_data  (refill_buffer)
    );

    // Word selection from 128-bit refill block matching cache_data_ram ordering:
    //   word_offset 00 -> refill_buffer[31:0]
    //   word_offset 01 -> refill_buffer[63:32]
    //   word_offset 10 -> refill_buffer[95:64]
    //   word_offset 11 -> refill_buffer[127:96]
    wire [31:0] refill_word = (dec_word_offset == 2'b00) ? refill_buffer[31:0]  :
                              (dec_word_offset == 2'b01) ? refill_buffer[63:32] :
                              (dec_word_offset == 2'b10) ? refill_buffer[95:64] :
                                                           refill_buffer[127:96];

    // CPU outputs
    assign cpu_data  = latched_cpu_data;
    assign cpu_stall = (state != S_IDLE);

    // =========================================================================
    // Combinational Next-State and Output Logic
    // =========================================================================
    always @(*) begin
        // Default assignments to prevent inferred latches
        next_state       = state;
        mem_req          = 1'b0;
        cpu_ready        = 1'b0;
        tag_we           = 1'b0;
        valid_we         = 1'b0;
        valid_write_val  = 1'b0;
        data_we          = 1'b0;

        case (state)
            S_IDLE: begin
                if (cpu_req) begin
                    next_state = S_LOOKUP;
                end
            end

            S_LOOKUP: begin
                if (cache_hit) begin
                    next_state = S_HIT_RESPONSE;
                end else begin
                    next_state = S_MISS_REQUEST;
                end
            end

            S_HIT_RESPONSE: begin
                cpu_ready  = 1'b1;
                next_state = S_IDLE;
            end

            S_MISS_REQUEST: begin
                mem_req = 1'b1;
                if (mem_ready) begin
                    next_state = S_REFILL;
                end else begin
                    next_state = S_WAIT_MEMORY;
                end
            end

            S_WAIT_MEMORY: begin
                if (mem_ready) begin
                    next_state = S_REFILL;
                end
            end

            S_REFILL: begin
                data_we         = 1'b1;
                tag_we          = 1'b1;
                valid_we        = 1'b1;
                valid_write_val = 1'b1;
                next_state      = S_MISS_RESPONSE;
            end

            S_MISS_RESPONSE: begin
                cpu_ready  = 1'b1;
                next_state = S_IDLE;
            end

            default: begin
                next_state = S_IDLE;
            end
        endcase
    end

    // =========================================================================
    // Sequential State and Register Logic
    // =========================================================================
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state            <= S_IDLE;
            latched_address  <= 32'd0;
            refill_buffer    <= 128'd0;
            latched_cpu_data <= 32'd0;
        end else begin
            state <= next_state;

            // Latch CPU address only on request acceptance in IDLE
            if (state == S_IDLE && cpu_req) begin
                latched_address <= cpu_addr;
            end

            // Capture memory block data when memory asserts ready
            if (((state == S_MISS_REQUEST) || (state == S_WAIT_MEMORY)) && mem_ready) begin
                refill_buffer <= mem_data;
            end

            // Capture response data for CPU
            if (state == S_LOOKUP && cache_hit) begin
                latched_cpu_data <= cache_read_word;
            end else if (state == S_REFILL) begin
                latched_cpu_data <= refill_word;
            end
        end
    end

endmodule

