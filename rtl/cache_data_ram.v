`timescale 1ns/1ps
// Storage for 64 cache lines (128 bits each) with 32-bit word selection.
// Synchronous write of full 128-bit block, combinational read of 32-bit word.
module cache_data_ram (
    input  wire         clk,
    input  wire [5:0]   index,
    input  wire [1:0]   word_offset,
    output wire [31:0]  read_data,
    input  wire         write_enable,
    input  wire [127:0] write_data
);
    // 64 cache lines, each 128 bits wide
    reg [127:0] ram [0:63];

    // Synchronous write: refill updates entire 128-bit block
    always @(posedge clk) begin
        if (write_enable) begin
            ram[index] <= write_data;
        end
    end

    // Combinational read: select one 32-bit word based on word_offset
    // Word ordering:
    //   word_offset 00 -> line_data[31:0]
    //   word_offset 01 -> line_data[63:32]
    //   word_offset 10 -> line_data[95:64]
    //   word_offset 11 -> line_data[127:96]
    wire [127:0] line_data = ram[index];

    assign read_data = (word_offset == 2'b00) ? line_data[31:0]  :
                       (word_offset == 2'b01) ? line_data[63:32] :
                       (word_offset == 2'b10) ? line_data[95:64] :
                                                line_data[127:96];
endmodule
