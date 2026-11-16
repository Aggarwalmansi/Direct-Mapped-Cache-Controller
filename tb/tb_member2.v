`timescale 1ns/1ps
// Testbench for Member 2 — Cache Storage
// Tests cache_data_ram, tag_ram, and valid_bit_ram independently and integration compatibility.
module tb_member2;
    reg clk;
    reg reset;

    // cache_data_ram signals
    reg [5:0]   data_index;
    reg [1:0]   data_word_offset;
    wire [31:0] data_read;
    reg         data_we;
    reg [127:0] data_write;

    // tag_ram signals
    reg [5:0]   tag_index;
    wire [21:0] tag_read;
    reg         tag_we;
    reg [21:0]  tag_write;

    // valid_bit_ram signals
    reg [5:0]   valid_index;
    wire        valid_out;
    reg         valid_we;
    reg         valid_write;

    integer i;

    // Instantiate Member 2 modules
    cache_data_ram u_data_ram (
        .clk(clk),
        .index(data_index),
        .word_offset(data_word_offset),
        .read_data(data_read),
        .write_enable(data_we),
        .write_data(data_write)
    );

    tag_ram u_tag_ram (
        .clk(clk),
        .index(tag_index),
        .read_tag(tag_read),
        .write_enable(tag_we),
        .write_tag(tag_write)
    );

    valid_bit_ram u_valid_ram (
        .clk(clk),
        .reset(reset),
        .index(valid_index),
        .valid_bit(valid_out),
        .write_enable(valid_we),
        .write_valid(valid_write)
    );

    // 100 MHz clock (10 ns period)
    always #5 clk = ~clk;

    // Helper task to write a 128-bit block into data RAM
    task write_data_block;
        input [5:0]   idx;
        input [127:0] block;
        begin
            @(posedge clk);
            data_index = idx;
            data_write = block;
            data_we    = 1'b1;
            @(posedge clk);
            data_we    = 1'b0;
            #1;
        end
    endtask

    // Helper task to check a 32-bit word in data RAM
    task check_data_word;
        input [5:0]  idx;
        input [1:0]  offset;
        input [31:0] expected;
        begin
            data_index       = idx;
            data_word_offset = offset;
            #1;
            if (data_read !== expected) begin
                $fatal(1, "FAIL: Data mismatch at line %0d, offset %b: expected 0x%08h, got 0x%08h",
                       idx, offset, expected, data_read);
            end
        end
    endtask

    // Helper task to write a tag into tag RAM
    task write_tag;
        input [5:0]  idx;
        input [21:0] tag_val;
        begin
            @(posedge clk);
            tag_index = idx;
            tag_write = tag_val;
            tag_we    = 1'b1;
            @(posedge clk);
            tag_we    = 1'b0;
            #1;
        end
    endtask

    // Helper task to check a tag in tag RAM
    task check_tag;
        input [5:0]  idx;
        input [21:0] expected;
        begin
            tag_index = idx;
            #1;
            if (tag_read !== expected) begin
                $fatal(1, "FAIL: Tag mismatch at line %0d: expected 0x%06h, got 0x%06h",
                       idx, expected, tag_read);
            end
        end
    endtask

    // Helper task to write a valid bit
    task write_valid_bit;
        input [5:0] idx;
        input       val;
        begin
            @(posedge clk);
            valid_index = idx;
            valid_write = val;
            valid_we    = 1'b1;
            @(posedge clk);
            valid_we    = 1'b0;
            #1;
        end
    endtask

    // Helper task to check a valid bit
    task check_valid_bit;
        input [5:0] idx;
        input       expected;
        begin
            valid_index = idx;
            #1;
            if (valid_out !== expected) begin
                $fatal(1, "FAIL: Valid bit mismatch at line %0d: expected %b, got %b",
                       idx, expected, valid_out);
            end
        end
    endtask

    initial begin
        // Initialize inputs
        clk              = 0;
        reset            = 0;
        data_index       = 0;
        data_word_offset = 0;
        data_we          = 0;
        data_write       = 128'd0;
        tag_index        = 0;
        tag_we           = 0;
        tag_write        = 22'd0;
        valid_index      = 0;
        valid_we         = 0;
        valid_write      = 0;

        #10;

        $display("==================================================");
        $display("Starting Member 2 Testbench: Cache Storage Modules");
        $display("==================================================");

        // ----------------------------------------------------
        // Scenario 6: Reset valid-bit RAM and verify all 64 entries are 0
        // ----------------------------------------------------
        $display("[Test 1] Reset valid_bit_ram and verify all 64 lines are 0");
        @(posedge clk);
        reset = 1'b1;
        @(posedge clk);
        reset = 1'b0;
        #1;
        for (i = 0; i < 64; i = i + 1) begin
            check_valid_bit(i[5:0], 1'b0);
        end

        // ----------------------------------------------------
        // Scenario 1, 2, 3: Write 128-bit block into line 5, read 4 words
        // ----------------------------------------------------
        $display("[Test 2] Write 128-bit block into line 5 and verify 4 words");
        write_data_block(6'd5, 128'hdeadbeef_cafebabe_baadf00d_12345678);
        check_data_word(6'd5, 2'b00, 32'h12345678);
        check_data_word(6'd5, 2'b01, 32'hbaadf00d);
        check_data_word(6'd5, 2'b10, 32'hcafebabe);
        check_data_word(6'd5, 2'b11, 32'hdeadbeef);

        // ----------------------------------------------------
        // Scenario 11: Overwrite line 5 with new block and verify replacement
        // ----------------------------------------------------
        $display("[Test 3] Overwrite line 5 with a new block and verify replacement");
        write_data_block(6'd5, 128'h01234567_89abcdef_11223344_55667788);
        check_data_word(6'd5, 2'b00, 32'h55667788);
        check_data_word(6'd5, 2'b01, 32'h11223344);
        check_data_word(6'd5, 2'b10, 32'h89abcdef);
        check_data_word(6'd5, 2'b11, 32'h01234567);

        // ----------------------------------------------------
        // Scenario 10: Test boundary indices (index 0 and index 63)
        // ----------------------------------------------------
        $display("[Test 4] Boundary indices test: index 0 and index 63 for data RAM");
        write_data_block(6'd0,  128'h00000003_00000002_00000001_00000000);
        write_data_block(6'd63, 128'hffffffff_fffffffe_fffffffd_fffffffc);

        check_data_word(6'd0, 2'b00, 32'h00000000);
        check_data_word(6'd0, 2'b01, 32'h00000001);
        check_data_word(6'd0, 2'b10, 32'h00000002);
        check_data_word(6'd0, 2'b11, 32'h00000003);

        check_data_word(6'd63, 2'b00, 32'hfffffffc);
        check_data_word(6'd63, 2'b01, 32'hfffffffd);
        check_data_word(6'd63, 2'b10, 32'hfffffffe);
        check_data_word(6'd63, 2'b11, 32'hffffffff);

        // Line 5 must be unaffected by writes to lines 0 and 63
        check_data_word(6'd5, 2'b00, 32'h55667788);
        check_data_word(6'd5, 2'b01, 32'h11223344);
        check_data_word(6'd5, 2'b10, 32'h89abcdef);
        check_data_word(6'd5, 2'b11, 32'h01234567);

        // ----------------------------------------------------
        // Verify all 64 data lines are independently addressable
        // ----------------------------------------------------
        $display("[Test 5] Verify all 64 data RAM lines independently addressable");
        for (i = 0; i < 64; i = i + 1) begin
            write_data_block(i[5:0], {26'b0, i[5:0], 26'b0, i[5:0], 26'b0, i[5:0], 26'b0, i[5:0]} ^ 128'h5a5a5a5a_3c3c3c3c_a5a5a5a5_c3c3c3c3);
        end
        for (i = 0; i < 64; i = i + 1) begin
            check_data_word(i[5:0], 2'b00, {26'b0, i[5:0]} ^ 32'hc3c3c3c3);
            check_data_word(i[5:0], 2'b01, {26'b0, i[5:0]} ^ 32'ha5a5a5a5);
            check_data_word(i[5:0], 2'b10, {26'b0, i[5:0]} ^ 32'h3c3c3c3c);
            check_data_word(i[5:0], 2'b11, {26'b0, i[5:0]} ^ 32'h5a5a5a5a);
        end

        // ----------------------------------------------------
        // Scenario 4 & 5: Write and retrieve tags, verify lines don't collide
        // ----------------------------------------------------
        $display("[Test 6] Write and retrieve tags from multiple indices");
        write_tag(6'd0,  22'h155555);
        write_tag(6'd5,  22'h2aaaaa);
        write_tag(6'd31, 22'h3fffff);
        write_tag(6'd63, 22'h000001);

        check_tag(6'd0,  22'h155555);
        check_tag(6'd5,  22'h2aaaaa);
        check_tag(6'd31, 22'h3fffff);
        check_tag(6'd63, 22'h000001);

        // Update tag 5 and verify other lines are unchanged
        $display("[Test 7] Verify updating one tag does not modify another line");
        write_tag(6'd5, 22'h123456);
        check_tag(6'd5,  22'h123456);
        check_tag(6'd0,  22'h155555);
        check_tag(6'd31, 22'h3fffff);
        check_tag(6'd63, 22'h000001);

        // Write all 64 tags with distinct patterns and read back
        $display("[Test 8] Write distinct tags to all 64 lines and read back");
        for (i = 0; i < 64; i = i + 1) begin
            write_tag(i[5:0], (22'h200000 | (i[5:0] << 10) | i[5:0]));
        end
        for (i = 0; i < 64; i = i + 1) begin
            check_tag(i[5:0], (22'h200000 | (i[5:0] << 10) | i[5:0]));
        end

        // ----------------------------------------------------
        // Scenario 7, 8, 9: Valid bit set, clear, and independence
        // ----------------------------------------------------
        $display("[Test 9] Valid bit operations: set, clear, isolation");
        // Re-reset valid RAM
        @(posedge clk);
        reset = 1'b1;
        @(posedge clk);
        reset = 1'b0;
        #1;
        for (i = 0; i < 64; i = i + 1) begin
            check_valid_bit(i[5:0], 1'b0);
        end

        // Set line 5 to 1
        write_valid_bit(6'd5, 1'b1);
        check_valid_bit(6'd5, 1'b1);

        // Set line 10 and 63 to 1
        write_valid_bit(6'd10, 1'b1);
        write_valid_bit(6'd63, 1'b1);
        check_valid_bit(6'd10, 1'b1);
        check_valid_bit(6'd63, 1'b1);

        // Clear line 5 to 0
        write_valid_bit(6'd5, 1'b0);
        check_valid_bit(6'd5, 1'b0);

        // Verify line 10 and 63 remain 1, other lines remain 0
        check_valid_bit(6'd10, 1'b1);
        check_valid_bit(6'd63, 1'b1);
        check_valid_bit(6'd0,  1'b0);
        check_valid_bit(6'd31, 1'b0);

        // Walking 1 test across all 64 valid bits
        $display("[Test 10] Walking single valid bit across all 64 lines");
        // Reset all
        @(posedge clk);
        reset = 1'b1;
        @(posedge clk);
        reset = 1'b0;
        #1;

        for (i = 0; i < 64; i = i + 1) begin
            write_valid_bit(i[5:0], 1'b1);
            check_valid_bit(i[5:0], 1'b1);
            if (i > 0) check_valid_bit((i-1), 1'b0);
            write_valid_bit(i[5:0], 1'b0);
            check_valid_bit(i[5:0], 1'b0);
        end

        // ----------------------------------------------------
        // Combinational read checks without clock edge
        // ----------------------------------------------------
        $display("[Test 11] Verify combinational read behavior (no clock required)");
        // Set line 7 data and tag and valid
        write_data_block(6'd7, 128'haaaaaaaa_bbbbbbbb_cccccccc_dddddddd);
        write_tag(6'd7, 22'h1a2b3c);
        write_valid_bit(6'd7, 1'b1);

        // Read without clock pulses, just changing address/offset
        data_index       = 6'd7;
        data_word_offset = 2'b00;
        tag_index        = 6'd7;
        valid_index      = 6'd7;
        #1;
        if (data_read !== 32'hdddddddd || tag_read !== 22'h1a2b3c || valid_out !== 1'b1)
            $fatal(1, "FAIL: Combinational read 1 failed");

        data_word_offset = 2'b01; #1;
        if (data_read !== 32'hcccccccc) $fatal(1, "FAIL: Combinational read word 1 failed");

        data_word_offset = 2'b10; #1;
        if (data_read !== 32'hbbbbbbbb) $fatal(1, "FAIL: Combinational read word 2 failed");

        data_word_offset = 2'b11; #1;
        if (data_read !== 32'haaaaaaaa) $fatal(1, "FAIL: Combinational read word 3 failed");

        // ----------------------------------------------------
        // Write enable gating check
        // ----------------------------------------------------
        $display("[Test 12] Verify write_enable gating (no write when we = 0)");
        @(posedge clk);
        data_index  = 6'd7;
        data_write  = 128'hffffffff_ffffffff_ffffffff_ffffffff;
        data_we     = 1'b0; // disabled!
        tag_index   = 6'd7;
        tag_write   = 22'h000000;
        tag_we      = 1'b0; // disabled!
        valid_index = 6'd7;
        valid_write = 1'b0;
        valid_we    = 1'b0; // disabled!
        @(posedge clk);
        #1;
        // Verify data, tag, valid were NOT modified
        check_data_word(6'd7, 2'b00, 32'hdddddddd);
        check_tag(6'd7, 22'h1a2b3c);
        check_valid_bit(6'd7, 1'b1);

        $display("==================================================");
        $display("PASS: Member 2 cache storage all checks succeeded");
        $display("==================================================");
        $finish;
    end
endmodule
