`timescale 1ns/1ps

// =============================================================================
// Module: main_memory_interface
// Project: Direct-Mapped Cache Controller (1 KB Capacity, 16-Byte Block)
// Member: Member 4 — Main-Memory Interface and Model
//
// Description:
//   Synthesizable four-word memory refill interface.
//   Accepts the cache controller's 1-cycle active-high request strobe (mem_req)
//   and 16-byte aligned block address (mem_addr), fetches four consecutive
//   32-bit words sequentially over a 32-bit memory-read interface, and
//   assembles the full 128-bit cache line refill block.
//
//   Guarantees verified word ordering:
//     mem_data[31:0]   = Word 0 at block address + 0
//     mem_data[63:32]  = Word 1 at block address + 4
//     mem_data[95:64]  = Word 2 at block address + 8
//     mem_data[127:96] = Word 3 at block address + 12
//     mem_data         = {Word 3, Word 2, Word 1, Word 0}
//
//   Asserts a clean 1-cycle mem_ready response strobe with stable data to
//   the cache controller and deasserts on the subsequent clock cycle.
// =============================================================================

module main_memory_interface (
    // Clock and Active-High Reset
    input  wire         clk,
    input  wire         reset,

    // Cache Controller Interface (128-bit block read)
    input  wire         mem_req,     // 1-cycle active-high request strobe from cache controller
    input  wire [31:0]  mem_addr,    // 16-byte aligned block address
    output reg          mem_ready,   // 1-cycle active-high data valid strobe to cache controller
    output wire [127:0] mem_data,    // 128-bit assembled refill block

    // Backing Memory Model Interface (32-bit word read)
    output reg          model_req,   // 1-cycle active-high read strobe per word
    output reg  [31:0]  model_addr,  // 32-bit word address (4-byte aligned)
    input  wire         model_ready, // Active-high data valid strobe from memory model
    input  wire [31:0]  model_data   // 32-bit word returned from memory model
);

    // =========================================================================
    // FSM State Encoding
    // =========================================================================
    localparam [2:0]
        S_IDLE  = 3'b000,   // Await mem_req from cache controller
        S_WORD0 = 3'b001,   // Fetch Word 0 (block_addr + 0)
        S_WORD1 = 3'b010,   // Fetch Word 1 (block_addr + 4)
        S_WORD2 = 3'b011,   // Fetch Word 2 (block_addr + 8)
        S_WORD3 = 3'b100,   // Fetch Word 3 (block_addr + 12)
        S_RESP  = 3'b101;   // Assert single-cycle mem_ready with stable 128-bit block

    reg [2:0]   state;
    reg [31:0]  base_addr;      // Latched 16-byte aligned block base address
    reg [127:0] refill_buffer;  // Holds four assembled 32-bit words
    reg         req_sent;       // Ensures model_req is pulsed for exactly 1 cycle per word

    // =========================================================================
    // Sequential State Transition & Data Latching
    // =========================================================================
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state         <= S_IDLE;
            base_addr     <= 32'd0;
            refill_buffer <= 128'd0;
            req_sent      <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    req_sent <= 1'b0;
                    if (mem_req) begin
                        // Enforce 16-byte block alignment on captured address
                        base_addr <= {mem_addr[31:4], 4'b0000};
                        state     <= S_WORD0;
                    end
                end

                S_WORD0: begin
                    if (model_ready) begin
                        refill_buffer[31:0] <= model_data;
                        state               <= S_WORD1;
                        req_sent            <= 1'b0;
                    end else begin
                        req_sent            <= 1'b1;
                    end
                end

                S_WORD1: begin
                    if (model_ready) begin
                        refill_buffer[63:32] <= model_data;
                        state                <= S_WORD2;
                        req_sent             <= 1'b0;
                    end else begin
                        req_sent             <= 1'b1;
                    end
                end

                S_WORD2: begin
                    if (model_ready) begin
                        refill_buffer[95:64] <= model_data;
                        state                <= S_WORD3;
                        req_sent             <= 1'b0;
                    end else begin
                        req_sent             <= 1'b1;
                    end
                end

                S_WORD3: begin
                    if (model_ready) begin
                        refill_buffer[127:96] <= model_data;
                        state                 <= S_RESP;
                        req_sent              <= 1'b0;
                    end else begin
                        req_sent              <= 1'b1;
                    end
                end

                S_RESP: begin
                    // Single-cycle response complete; return to IDLE
                    state    <= S_IDLE;
                    req_sent <= 1'b0;
                end

                default: begin
                    state    <= S_IDLE;
                    req_sent <= 1'b0;
                end
            endcase
        end
    end

    // =========================================================================
    // Combinational Output Logic
    // =========================================================================
    always @(*) begin
        // Default outputs
        model_req  = 1'b0;
        model_addr = 32'd0;
        mem_ready  = 1'b0;

        case (state)
            S_IDLE: begin
                // Inactive in IDLE
            end

            S_WORD0: begin
                model_req  = ~req_sent;
                model_addr = base_addr;
            end

            S_WORD1: begin
                model_req  = ~req_sent;
                model_addr = base_addr + 32'd4;
            end

            S_WORD2: begin
                model_req  = ~req_sent;
                model_addr = base_addr + 32'd8;
            end

            S_WORD3: begin
                model_req  = ~req_sent;
                model_addr = base_addr + 32'd12;
            end

            S_RESP: begin
                mem_ready = 1'b1;
            end

            default: begin
                // Inactive
            end
        endcase
    end

    // Assembled 128-bit block driven to cache controller
    assign mem_data = refill_buffer;

endmodule
