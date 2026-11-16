`timescale 1ns/1ps
// Storage for 64 tags (22 bits each).
// Synchronous write on refill completion, combinational read.
module tag_ram (
    input  wire        clk,
    input  wire [5:0]  index,
    output wire [21:0] read_tag,
    input  wire        write_enable,
    input  wire [21:0] write_tag
);
    // 64 tag entries, each 22 bits wide
    reg [21:0] ram [0:63];

    // Synchronous write of new tag
    always @(posedge clk) begin
        if (write_enable) begin
            ram[index] <= write_tag;
        end
    end

    // Combinational read of tag for current index
    assign read_tag = ram[index];
endmodule
