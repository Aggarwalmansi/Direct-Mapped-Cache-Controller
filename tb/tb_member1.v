`timescale 1ns/1ps
module tb_member1;
    reg [31:0] address;
    wire [21:0] tag;
    wire [5:0] index;
    wire [1:0] word_offset, byte_offset;
    wire [31:0] block_address;
    reg [21:0] stored_tag;
    reg valid;
    wire hit;
    integer i;
    address_decoder decoder(address, tag, index, word_offset,
                            byte_offset, block_address);
    tag_comparator comparator(tag, stored_tag, valid, hit);

    task check_address;
        input [31:0] value;
        begin
            address = value;
            #1;
            if (tag !== (value >> 10) ||
                index !== ((value >> 4) & 32'h3f) ||
                word_offset !== ((value >> 2) & 32'h3) ||
                byte_offset !== (value & 32'h3))
                $fatal(1, "Decoded fields incorrect: %h", value);
            if ({tag, index, word_offset, byte_offset} !== value)
                $fatal(1, "Address reconstruction failed: %h", value);
            if (block_address !== ((value / 16) * 16))
                $fatal(1, "Block alignment failed: %h", value);
        end
    endtask

    initial begin
        address = 0; stored_tag = 0; valid = 0;
        check_address(32'h00000000);
        check_address(32'h000003ff);
        if (tag !== 0 || index !== 63 || word_offset !== 3 || byte_offset !== 3)
            $fatal(1, "Field boundary failed");
        check_address(32'h00000400);
        if (tag !== 1 || index !== 0 || word_offset !== 0 || byte_offset !== 0)
            $fatal(1, "Tag boundary failed");
        check_address(32'hffffffff);
        for (i = 0; i < 4096; i = i + 1)
            check_address(i);
        for (i = 0; i < 1000; i = i + 1)
            check_address($random);

        address = 32'h12345678; #1;
        stored_tag = tag; valid = 0; #1;
        if (hit !== 0) $fatal(1, "Invalid matching line hit");
        valid = 1; #1;
        if (hit !== 1) $fatal(1, "Valid matching line missed");
        stored_tag = tag ^ 22'b1; #1;
        if (hit !== 0) $fatal(1, "Conflicting tag hit");
        valid = 0; #1;
        if (hit !== 0) $fatal(1, "Invalid conflicting line hit");
        // Every tag bit must participate in the comparison.
        for (i = 0; i < 22; i = i + 1) begin
            stored_tag = tag ^ (22'b1 << i); valid = 1; #1;
            if (hit !== 0) $fatal(1, "Tag bit %0d ignored", i);
        end
        // Addresses 1 KB apart conflict at the same cache index.
        address = 32'h00000040; #1;
        stored_tag = tag; valid = 1; #1;
        if (hit !== 1 || index !== 4) $fatal(1, "Initial line failed");
        address = 32'h00000440; #1;
        if (hit !== 0 || index !== 4) $fatal(1, "Conflict missed");
        // Invalid entries must mask even unknown uninitialized tags.
        stored_tag = 22'bx; valid = 0; #1;
        if (hit !== 0) $fatal(1, "Invalid unknown tag was not masked");
        $display("PASS: Member 1 decoder and comparator checks");
        $finish;
    end
endmodule
