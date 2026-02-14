module tb_neuron_processor;

    // Parameters
    localparam int MAX_NEURON_INPUTS = 16;
    localparam int PW = 8;
    localparam int THRESHOLD_WIDTH = $clog2(MAX_NEURON_INPUTS + 1);

    // Testbench signals
    logic                       clk;
    logic                       rst;
    logic [             PW-1:0] weights;
    logic [             PW-1:0] inputs;
    logic [THRESHOLD_WIDTH-1:0] threshold;
    logic                       valid_in;
    logic                       last;
    logic                       valid_out;
    logic                       y;
    logic [THRESHOLD_WIDTH-1:0] popcount;

    // Instantiate DUT
    neuron_processor #(
        .MAX_NEURON_INPUTS(MAX_NEURON_INPUTS),
        .PW(PW)
    ) dut (.*);

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Test stimulus
    initial begin
        // Initialize signals
        rst = 1;
        weights = '0;
        inputs = '0;
        threshold = '0;
        valid_in = 0;
        last = 0;

        // Wait for a few cycles
        repeat(3) @(posedge clk);
        rst = 0;
        @(posedge clk);

        $display("\n========================================");
        $display("   BASIC DIRECTED TESTS (Original)");
        $display("========================================");

        $display("\n=== Test Case 1: Full Match (Popcount should be 16) ===");
        threshold = 5'd10; // Out of 16 total inputs
        drive_pass(8'hFF, 8'hFF, 0); // First 8
        drive_pass(8'hAA, 8'hAA, 1); // Last 8, assert last
        
        @(posedge clk);
        if (valid_out && popcount == 5'd16) begin
            $display("TC1 PASS: Popcount 16, Y=%b", y);
        end else begin
            $display("TC1 FAIL: Popcount %d (expected 16), valid_out=%b", popcount, valid_out);
        end

        @(posedge clk);

        $display("\n=== Test Case 2: Partial Match ===");
        threshold = 5'd10;
        // Iteration 1: 4 matches
        drive_pass(8'b1111_0000, 8'b1111_1111, 0); 
        // Iteration 2: 2 matches
        drive_pass(8'b0000_0011, 8'b1111_1111, 1); 

        @(posedge clk);
        if (valid_out && popcount == 5'd6) begin
            $display("TC2 PASS: Popcount 6, Y=%b (expected 0 since 6 < 10)", y);
        end else begin
            $display("TC2 FAIL: Popcount %d (expected 6), Y=%b", popcount, y);
        end

        @(posedge clk);

        $display("\n========================================");
        $display("   EXTENDED COMPREHENSIVE TESTS");
        $display("========================================");

        $display("\n=== Test 1: Single chunk input (all matches) ===");
        test_single_chunk(8'b11110000, 8'b11110000, 5'd8);

        $display("\n=== Test 2: Single chunk input (partial matches) ===");
        test_single_chunk(8'b11001100, 8'b10101010, 5'd4);

        $display("\n=== Test 3: Multi-chunk input (2 chunks) ===");
        test_multi_chunk_2();

        $display("\n=== Test 4: Multi-chunk input (3 chunks) ===");
        test_multi_chunk_3();

        $display("\n=== Test 5: Back-to-back neuron processing ===");
        test_back_to_back();

        $display("\n=== Test 6: Zero threshold ===");
        test_single_chunk(8'b10101010, 8'b01010101, 5'd0);

        $display("\n=== Test 7: Valid toggling ===");
        test_valid_toggling();

        $display("\n=== Test 8: Large multi-chunk input (10 chunks) ===");
        test_large_chunks(10);

        $display("\n=== Test 9: Large multi-chunk input (16 chunks) ===");
        test_large_chunks(16);

        $display("\n=== Test 10: Very large multi-chunk input (32 chunks) ===");
        test_large_chunks(32);

        $display("\n=== Test 11: Random verification (50 iterations) ===");
        test_random_verification(50);

        $display("\n=== Test 12: Random with varying chunk counts ===");
        test_random_varying_chunks(30);

        $display("\n=== Test 13: Stress test with random valid toggling ===");
        test_random_valid_toggling(20);

        $display("\n=== Test 14: Edge cases ===");
        test_edge_cases();

        // End simulation
        repeat(10) @(posedge clk);
        $display("\n========================================");
        $display("   ALL TESTS COMPLETED");
        $display("========================================\n");
        $finish;
    end

    // Helper Task (from original testbench)
    task drive_pass(input [PW-1:0] w, input [PW-1:0] i, input l);
        weights = w;
        inputs = i;
        valid_in = 1;
        last = l;
        @(posedge clk);
        valid_in = 0;
        last = 0;
    endtask

    // Task: Test single chunk (last asserted on first input)
    task test_single_chunk(
        input logic [PW-1:0] w,
        input logic [PW-1:0] i,
        input logic [THRESHOLD_WIDTH-1:0] thresh
    );
        logic [THRESHOLD_WIDTH-1:0] expected_popcount;
        logic expected_y;
        expected_popcount = THRESHOLD_WIDTH'($countones(w ~^ i));
        expected_y = (expected_popcount >= thresh) ? 1 : 0;
        weights = w;
        inputs = i;
        threshold = thresh;
        valid_in = 1;
        last = 1;
        
        @(posedge clk);
        valid_in = 0;
        last = 0;
                @(posedge clk);

        // Check outputs
        if (valid_out !== 1'b1) begin
            $display("ERROR: valid_out = %b, expected 1", valid_out);
        end
        if (popcount !== expected_popcount) begin
            $display("ERROR: popcount = %0d, expected %0d", popcount, expected_popcount);
        end else begin
            $display("PASS: popcount = %0d", popcount);
        end
        if (y !== expected_y) begin
            $display("ERROR: y = %b, expected %b (threshold = %0d)", y, expected_y, thresh);
        end else begin
            $display("PASS: y = %b (threshold = %0d)", y, thresh);
        end
        
        // Check that accumulator is cleared (next cycle should start fresh)
        @(posedge clk);
        if (valid_out !== 1'b0) begin
            $display("ERROR: valid_out should be 0 after output");
        end
    endtask

    // Task: Test with 2 chunks
    task test_multi_chunk_2();
        logic [THRESHOLD_WIDTH-1:0] chunk1_matches, chunk2_matches, total_matches;
        logic [PW-1:0] w1, w2, i1, i2;
        logic [THRESHOLD_WIDTH-1:0] thresh;
        
        w1 = 8'b11110000;
        i1 = 8'b11110000;
        w2 = 8'b10101010;
        i2 = 8'b10101010;
        thresh = 5'd12;
        
        chunk1_matches = THRESHOLD_WIDTH'($countones(w1 ~^ i1));
        chunk2_matches = THRESHOLD_WIDTH'($countones(w2 ~^ i2));
        total_matches = chunk1_matches + chunk2_matches;
        
        $display("Chunk 1 matches: %0d, Chunk 2 matches: %0d, Total: %0d", 
                 chunk1_matches, chunk2_matches, total_matches);
        
        // Chunk 1
        @(posedge clk);
        weights = w1;
        inputs = i1;
        threshold = thresh;
        valid_in = 1;
        last = 0;
        
        @(posedge clk);
        if (valid_out !== 1'b0) begin
            $display("ERROR: valid_out should be 0 during accumulation");
        end
        
        // Chunk 2 (last)
        weights = w2;
        inputs = i2;
        last = 1;
        
        @(posedge clk);
        valid_in = 0;
        last = 0;
        
        // Check outputs
        if (valid_out !== 1'b1) begin
            $display("ERROR: valid_out = %b, expected 1", valid_out);
        end
        if (popcount !== total_matches) begin
            $display("ERROR: popcount = %0d, expected %0d", popcount, total_matches);
        end else begin
            $display("PASS: popcount = %0d", popcount);
        end
        if (y !== (total_matches >= thresh)) begin
            $display("ERROR: y = %b, expected %b", y, (total_matches >= thresh));
        end else begin
            $display("PASS: y = %b", y);
        end
    endtask

    // Task: Test with 3 chunks
    task test_multi_chunk_3();
        logic [THRESHOLD_WIDTH-1:0] total_matches;
        logic [THRESHOLD_WIDTH-1:0] thresh;
        
        thresh = 5'd15;
        total_matches = '0;
        
        // Chunk 1
        @(posedge clk);
        weights = 8'b11111111;
        inputs = 8'b11111111;
        threshold = thresh;
        valid_in = 1;
        last = 0;
        total_matches = total_matches + THRESHOLD_WIDTH'($countones(weights ~^ inputs));
        
        // Chunk 2
        @(posedge clk);
        weights = 8'b00000000;
        inputs = 8'b00000000;
        last = 0;
        total_matches = total_matches + THRESHOLD_WIDTH'($countones(weights ~^ inputs));
        
        // Chunk 3 (last)
        @(posedge clk);
        weights = 8'b10101010;
        inputs = 8'b01010101;
        last = 1;
        total_matches = total_matches + THRESHOLD_WIDTH'($countones(weights ~^ inputs));
        
        @(posedge clk);
        valid_in = 0;
        last = 0;
        
        $display("Total matches across 3 chunks: %0d", total_matches);
        
        // Check outputs
        if (popcount !== total_matches) begin
            $display("ERROR: popcount = %0d, expected %0d", popcount, total_matches);
        end else begin
            $display("PASS: popcount = %0d", popcount);
        end
    endtask

    // Task: Test back-to-back neuron processing
    task test_back_to_back();
        $display("Processing neuron 1...");
        
        // Neuron 1
        @(posedge clk);
        weights = 8'b11110000;
        inputs = 8'b11110000;
        threshold = 5'd5;
        valid_in = 1;
        last = 1;
        
        @(posedge clk);
        if (valid_out !== 1'b1 || popcount !== 5'd8) begin
            $display("ERROR: Neuron 1 output incorrect");
        end else begin
            $display("PASS: Neuron 1 - popcount = %0d, y = %b", popcount, y);
        end
        
        $display("Processing neuron 2...");
        
        // Neuron 2 (immediately after)
        weights = 8'b10101010;
        inputs = 8'b01010101;
        threshold = 5'd1;
        last = 1;
        
        @(posedge clk);
        valid_in = 0;
        
        if (valid_out !== 1'b1 || popcount !== 5'd0) begin
            $display("ERROR: Neuron 2 output incorrect, popcount = %0d", popcount);
        end else begin
            $display("PASS: Neuron 2 - popcount = %0d, y = %b (accumulator properly cleared)", popcount, y);
        end
    endtask

    // Task: Test valid signal toggling
    task test_valid_toggling();
        @(posedge clk);
        weights = 8'b11110000;
        inputs = 8'b11110000;
        threshold = 5'd10;
        valid_in = 1;
        last = 0;
        
        // Toggle valid
        @(posedge clk);
        valid_in = 0;
        
        @(posedge clk);
        @(posedge clk);
        
        // Resume
        valid_in = 1;
        weights = 8'b00001111;
        inputs = 8'b00001111;
        last = 1;
        
        @(posedge clk);
        valid_in = 0;
        last = 0;
        
        if (popcount !== 5'd16) begin
            $display("ERROR: popcount = %0d, expected 16", popcount);
        end else begin
            $display("PASS: Accumulation works correctly with valid toggling");
        end
    endtask

    // Task: Test with large number of chunks
    task test_large_chunks(input int num_chunks);
        logic [THRESHOLD_WIDTH-1:0] total_matches;
        logic [PW-1:0] w_array[];
        logic [PW-1:0] i_array[];
        logic [THRESHOLD_WIDTH-1:0] thresh;
        int i;
        
        w_array = new[num_chunks];
        i_array = new[num_chunks];
        total_matches = '0;
        
        // Generate random data
        for (i = 0; i < num_chunks; i++) begin
            w_array[i] = $random;
            i_array[i] = $random;
            total_matches = total_matches + THRESHOLD_WIDTH'($countones(w_array[i] ~^ i_array[i]));
        end
        
        thresh = THRESHOLD_WIDTH'($urandom_range(0, num_chunks * PW));
        
        $display("Testing %0d chunks, expected total matches: %0d, threshold: %0d", 
                 num_chunks, total_matches, thresh);
        
        // Process all chunks
        for (i = 0; i < num_chunks; i++) begin
            @(posedge clk);
            weights = w_array[i];
            inputs = i_array[i];
            threshold = thresh;
            valid_in = 1;
            last = (i == num_chunks - 1);
            
            // During accumulation, valid_out should be 0
            if (i < num_chunks - 1) begin
                @(posedge clk);
                if (valid_out !== 1'b0) begin
                    $display("ERROR: valid_out should be 0 during accumulation at chunk %0d", i);
                end
            end
        end
        
        // Check output after last chunk
        @(posedge clk);
        valid_in = 0;
        last = 0;
        
        if (valid_out !== 1'b1) begin
            $display("ERROR: valid_out = %b, expected 1", valid_out);
        end
        
        if (popcount !== total_matches) begin
            $display("ERROR: popcount = %0d, expected %0d", popcount, total_matches);
        end else begin
            $display("PASS: popcount = %0d matches expected", popcount);
        end
        
        if (y !== (total_matches >= thresh)) begin
            $display("ERROR: y = %b, expected %b", y, (total_matches >= thresh));
        end else begin
            $display("PASS: y = %b (correct threshold comparison)", y);
        end
        
        // Verify accumulator cleared
        @(posedge clk);
        if (valid_out !== 1'b0) begin
            $display("ERROR: valid_out should be 0 after output");
        end
    endtask

    // Task: Random verification with fixed chunk count
    task test_random_verification(input int num_tests);
        int test_num;
        int num_chunks;
        logic [THRESHOLD_WIDTH-1:0] total_matches;
        logic [PW-1:0] w_val, i_val;
        logic [THRESHOLD_WIDTH-1:0] thresh;
        int i;
        int errors;
        
        errors = 0;
        num_chunks = 5; // Fixed at 5 chunks per test
        
        $display("Running %0d random tests with %0d chunks each...", num_tests, num_chunks);
        
        for (test_num = 0; test_num < num_tests; test_num++) begin
            total_matches = '0;
            thresh = THRESHOLD_WIDTH'($urandom_range(0, num_chunks * PW));
            
            // Process chunks
            for (i = 0; i < num_chunks; i++) begin
                w_val = $random;
                i_val = $random;
                total_matches = total_matches + THRESHOLD_WIDTH'($countones(w_val ~^ i_val));
                
                @(posedge clk);
                weights = w_val;
                inputs = i_val;
                threshold = thresh;
                valid_in = 1;
                last = (i == num_chunks - 1);
            end
            
            // Check output
            @(posedge clk);
            valid_in = 0;
            last = 0;
            
            if (valid_out !== 1'b1) begin
                $display("Test %0d ERROR: valid_out = %b, expected 1", test_num, valid_out);
                errors++;
            end
            
            if (popcount !== total_matches) begin
                $display("Test %0d ERROR: popcount = %0d, expected %0d", test_num, popcount, total_matches);
                errors++;
            end
            
            if (y !== (total_matches >= thresh)) begin
                $display("Test %0d ERROR: y = %b, expected %b (popcount=%0d, thresh=%0d)", 
                         test_num, y, (total_matches >= thresh), total_matches, thresh);
                errors++;
            end
            
            @(posedge clk);
        end
        
        if (errors == 0) begin
            $display("PASS: All %0d random tests passed!", num_tests);
        end else begin
            $display("FAIL: %0d errors in %0d tests", errors, num_tests);
        end
    endtask

    // Task: Random verification with varying chunk counts
    task test_random_varying_chunks(input int num_tests);
        int test_num;
        int num_chunks;
        logic [THRESHOLD_WIDTH-1:0] total_matches;
        logic [PW-1:0] w_val, i_val;
        logic [THRESHOLD_WIDTH-1:0] thresh;
        int i;
        int errors;
        
        errors = 0;
        
        $display("Running %0d random tests with varying chunk counts...", num_tests);
        
        for (test_num = 0; test_num < num_tests; test_num++) begin
            num_chunks = $urandom_range(1, 20); // Random 1-20 chunks
            total_matches = '0;
            thresh = THRESHOLD_WIDTH'($urandom_range(0, num_chunks * PW));
            
            // Process chunks
            for (i = 0; i < num_chunks; i++) begin
                w_val = $random;
                i_val = $random;
                total_matches = total_matches + THRESHOLD_WIDTH'($countones(w_val ~^ i_val));
                
                @(posedge clk);
                weights = w_val;
                inputs = i_val;
                threshold = thresh;
                valid_in = 1;
                last = (i == num_chunks - 1);
            end
            
            // Check output
            @(posedge clk);
            valid_in = 0;
            last = 0;
            
            if (valid_out !== 1'b1 || popcount !== total_matches || y !== (total_matches >= thresh)) begin
                $display("Test %0d ERROR: chunks=%0d, popcount=%0d (exp %0d), y=%b (exp %b), thresh=%0d", 
                         test_num, num_chunks, popcount, total_matches, y, (total_matches >= thresh), thresh);
                errors++;
            end else if (test_num % 10 == 0) begin
                $display("Test %0d: chunks=%0d, popcount=%0d, y=%b, thresh=%0d - PASS", 
                         test_num, num_chunks, popcount, y, thresh);
            end
            
            @(posedge clk);
        end
        
        if (errors == 0) begin
            $display("PASS: All %0d random varying-chunk tests passed!", num_tests);
        end else begin
            $display("FAIL: %0d errors in %0d tests", errors, num_tests);
        end
    endtask

    // Task: Random valid toggling stress test
    task test_random_valid_toggling(input int num_tests);
        int test_num;
        int num_chunks;
        logic [THRESHOLD_WIDTH-1:0] total_matches;
        logic [PW-1:0] w_val, i_val;
        logic [THRESHOLD_WIDTH-1:0] thresh;
        int i;
        int errors;
        int pause_cycles;
        
        errors = 0;
        
        $display("Running %0d random tests with valid toggling...", num_tests);
        
        for (test_num = 0; test_num < num_tests; test_num++) begin
            num_chunks = $urandom_range(3, 10);
            total_matches = '0;
            thresh = THRESHOLD_WIDTH'($urandom_range(0, num_chunks * PW));
            
            // Process chunks with random pauses
            for (i = 0; i < num_chunks; i++) begin
                w_val = $random;
                i_val = $random;
                total_matches = total_matches + THRESHOLD_WIDTH'($countones(w_val ~^ i_val));
                
                @(posedge clk);
                weights = w_val;
                inputs = i_val;
                threshold = thresh;
                valid_in = 1;
                last = (i == num_chunks - 1);
                
                // Randomly insert pauses
                if ($urandom_range(0, 2) == 0 && i < num_chunks - 1) begin
                    @(posedge clk);
                    valid_in = 0;
                    pause_cycles = $urandom_range(1, 3);
                    repeat(pause_cycles) @(posedge clk);
                end
            end
            
            // Check output
            @(posedge clk);
            valid_in = 0;
            last = 0;
            
            if (valid_out !== 1'b1 || popcount !== total_matches || y !== (total_matches >= thresh)) begin
                $display("Test %0d ERROR: popcount=%0d (exp %0d), y=%b (exp %b)", 
                         test_num, popcount, total_matches, y, (total_matches >= thresh));
                errors++;
            end else if (test_num % 5 == 0) begin
                $display("Test %0d: popcount=%0d, y=%b - PASS", test_num, popcount, y);
            end
            
            @(posedge clk);
        end
        
        if (errors == 0) begin
            $display("PASS: All %0d random valid-toggling tests passed!", num_tests);
        end else begin
            $display("FAIL: %0d errors in %0d tests", errors, num_tests);
        end
    endtask

    // Task: Edge case testing
    task test_edge_cases();
        $display("Testing edge case: All zeros");
        test_single_chunk(8'b00000000, 8'b00000000, 5'd8);
        
        $display("Testing edge case: All ones");
        test_single_chunk(8'b11111111, 8'b11111111, 5'd8);
        
        $display("Testing edge case: Complete mismatch");
        test_single_chunk(8'b11111111, 8'b00000000, 5'd1);
        
        $display("Testing edge case: Maximum threshold");
        test_single_chunk(8'b10101010, 8'b10101010, 5'd15);
        
        $display("Testing edge case: Single bit match");
        test_single_chunk(8'b10000000, 8'b10000000, 5'd1);
    endtask

    // Disable monitor for cleaner output during random tests
    initial begin
        // $monitor("Time=%0t rst=%b valid_in=%b last=%b weights=%b inputs=%b threshold=%0d | valid_out=%b y=%b popcount=%0d",
        //          $time, rst, valid_in, last, weights, inputs, threshold, valid_out, y, popcount);
    end

    // Timeout watchdog
    initial begin
        #100000;
        $display("ERROR: Simulation timeout");
        $finish;
    end

endmodule