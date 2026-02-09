// TODO: add more tests, just had gemini make this after finishing my neuron processor to see if it passed the most basic tests

module neuron_processor_tb;

    // Params
    localparam int MAX_NEURON_INPUTS = 16;
    localparam int PW = 8;
    localparam int THRESHOLD_WIDTH = $clog2(MAX_NEURON_INPUTS + 1);

    // Signals
    logic clk;
    logic rst;
    logic [PW-1:0] weights;
    logic [PW-1:0] inputs;
    logic [THRESHOLD_WIDTH-1:0] threshold;
    logic valid_in;
    logic last;
    logic valid_out;
    logic y;
    logic [THRESHOLD_WIDTH-1:0] popcount;

    // DUT Instantiation
    neuron_processor #(
        .MAX_NEURON_INPUTS(MAX_NEURON_INPUTS),
        .PW(PW)
    ) dut (.*);

    // Clock Gen
    initial clk = 0;
    always #5 clk = ~clk;

    // Test Procedure
    initial begin
        // Initialize
        rst = 1;
        weights = '0;
        inputs = '0;
        threshold = 10; // Out of 16 total inputs
        valid_in = 0;
        last = 0;

        repeat(2) @(posedge clk);
        rst = 0;
        @(posedge clk);

        // --- Test Case 1: Full Match (Popcount should be 16) ---
        drive_pass(8'hFF, 8'hFF, 0); // First 8
        drive_pass(8'hAA, 8'hAA, 1); // Last 8, assert last
        
        @(posedge clk);
        if (valid_out && popcount == 16) $display("TC1 Pass: Popcount 16");
        else $display("TC1 Fail: Popcount %d", popcount);

        // --- Test Case 2: Partial Match ---
        // Iteration 1: 4 matches
        drive_pass(8'b1111_0000, 8'b1111_1111, 0); 
        // Iteration 2: 2 matches
        drive_pass(8'b0000_0011, 8'b1111_1111, 1); 

        @(posedge clk);
        if (valid_out && popcount == 6) $display("TC2 Pass: Popcount 6, Y=%b", y);
        else $display("TC2 Fail: Popcount %d", popcount);

        #20;
        $finish;
    end

    // Helper Task
    task drive_pass(input [PW-1:0] w, input [PW-1:0] i, input l);
        weights = w;
        inputs = i;
        valid_in = 1;
        last = l;
        @(posedge clk);
        valid_in = 0;
        last = 0;
    endtask

endmodule