`timescale 1ns/1ps
// 1 KB direct-mapped cache, 16-byte blocks, 32-bit byte addresses.
module address_decoder (
    input  wire [31:0] address,
    output wire [21:0] tag,
    output wire [5:0]  index,
    output wire [1:0]  word_offset,
    output wire [1:0]  byte_offset,
    output wire [31:0] block_address
);
    assign tag           = address[31:10];
    assign index         = address[9:4];
    assign word_offset   = address[3:2];
    assign byte_offset   = address[1:0];
    assign block_address = {address[31:4], 4'b0000};
endmodule
