`timescale 1ns/1ps
// The valid bit gates tag equality; invalid lines never produce a hit.
module tag_comparator (
    input  wire [21:0] requested_tag,
    input  wire [21:0] stored_tag,
    input  wire        valid,
    output wire        hit
);
    assign hit = valid && (requested_tag == stored_tag);
endmodule
