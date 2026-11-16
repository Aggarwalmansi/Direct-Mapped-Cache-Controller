`timescale 1ns/1ps
// Storage for 64 valid bits.
// Clears all valid bits on reset, synchronous update/invalidation, combinational read.
module valid_bit_ram (
    input  wire       clk,
    input  wire       reset,
    input  wire [5:0] index,
    output wire       valid_bit,
    input  wire       write_enable,
    input  wire       write_valid
);
    // 64 one-bit valid entries
    reg ram [0:63];
    integer i;

    // Reset clears all 64 valid bits to 0.
    // Synchronous write sets or clears selected entry.
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 64; i = i + 1) begin
                ram[i] <= 1'b0;
            end
        end else if (write_enable) begin
            ram[index] <= write_valid;
        end
    end

    // Combinational read of valid bit for current index
    assign valid_bit = ram[index];
endmodule
