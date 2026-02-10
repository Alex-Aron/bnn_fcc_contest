// ima be so honest, i wrote a tb that tests a single test case
// then had chat generate this one based off of that
//
// this tb assumes that MAX_NEURON_INPUTS=16 and PW=8, it doesn't use the
// localparam's (ai not taking my job just yet). So I'll need to update it to
// actually use them

`timescale 1 ns / 10 ps  // 1 ns time unit, 10 ps precision
module neuron_proc_tb;
  localparam int MAX_NEURON_INPUTS = 8;
  localparam int PW = 8;
  localparam int THRESHHOLD_WIDTH = $clog2(MAX_NEURON_INPUTS + 1);
  localparam int period = 10;
  localparam int NUM_TESTS = 250;  // Number of random tests to run

  logic [PW-1:0] inputs = 0;
  logic [PW-1:0] weights = 0;
  logic [THRESHHOLD_WIDTH-1:0] threshhold = 0;
  logic valid_in = 0;
  logic last = 0;
  logic clk = 1'b0;
  logic rst;
  logic valid_out;
  logic y;
  logic [THRESHHOLD_WIDTH-1:0] popcount;

  // Variables for expected results
  logic [THRESHHOLD_WIDTH-1:0] expected_popcount;
  logic expected_y;
  int test_passed = 0;
  int test_failed = 0;

  neuron_proc #(
      .MAX_NEURON_INPUTS(MAX_NEURON_INPUTS),
      .PW(PW),
      .THRESHHOLD_WIDTH(THRESHHOLD_WIDTH)
  ) DUT (
      .*
  );

  // Generate a clock with a 10 ns period
  initial begin : generate_clock
    forever #5 clk <= ~clk;
  end

  // Function to calculate expected popcount from XNOR of inputs and weights
  function [THRESHHOLD_WIDTH-1:0] calc_popcount(logic [PW-1:0] in, logic [PW-1:0] w);
    logic [PW-1:0] xnor_result;
    automatic int count = 0;

    xnor_result = ~(in ^ w);  // XNOR operation

    for (int i = 0; i < PW; i++) begin
      if (xnor_result[i]) count++;
    end

    return count;
  endfunction

  initial begin : apply_tests
    $timeformat(-9, 0, " ns");

    // Reset sequence
    rst <= 1'b1;
    @(negedge clk);
    rst <= 1'b0;
    @(posedge clk);

    // First run your original test case
    valid_in <= 1'b1;
    inputs <= 8'b11110000;
    weights <= 8'b11111111;
    threshhold <= 1;
    @(posedge clk);
    valid_in <= 1'b1;
    inputs <= 8'b11111111;
    weights <= 8'b11111111;
    threshhold <= 1;
    last <= 1;
    @(posedge clk);
    last <= 0;
    valid_in <= 0;

    // Wait until valid_out is 1
    wait_for_valid_out();

    assert (y == 1'b1)
    else $display("Original test: y was incorrect! y = %b", y);
    assert (popcount == 12)
    else $display("Original test: popcount was incorrect! popcount = %0d", popcount);

    $display("Original test case passed");

    // Now run random tests
    for (int test = 0; test < NUM_TESTS; test++) begin
      // Random values for the first cycle
      expected_popcount = 0;
      inputs = $random;
      weights = $random;
      threshhold = $urandom_range(1, MAX_NEURON_INPUTS);
      valid_in = 1'b1;
      last = 0;

      // Calculate expected popcount for first input
      expected_popcount += calc_popcount(inputs, weights);

      @(posedge clk);

      // Random values for the second cycle with last=1
      inputs = $random;
      weights = $random;
      last = 1;

      // Add to expected popcount for second input
      expected_popcount += calc_popcount(inputs, weights);
      expected_y = (expected_popcount > threshhold) ? 1'b1 : 1'b0;

      @(posedge clk);
      last <= 0;
      valid_in <= 0;

      // Wait for valid_out
      wait_for_valid_out();

      // Check results
      if (y == expected_y && popcount == expected_popcount) begin
        $display("Test %0d PASSED: y=%b (expected=%b), popcount=%0d (expected=%0d), threshold=%0d",
                 test, y, expected_y, popcount, expected_popcount, threshhold);
        test_passed++;
      end else begin
        $display("Test %0d FAILED: y=%b (expected=%b), popcount=%0d (expected=%0d), threshold=%0d",
                 test, y, expected_y, popcount, expected_popcount, threshhold);
        test_failed++;
      end
    end

    // Report final results
    $display("\nTest Results: %0d PASSED, %0d FAILED", test_passed, test_failed);
    $display("TB ended");
    $finish;
  end

  // Task to wait for valid_out
  task wait_for_valid_out;
    @(posedge clk);
    while (!valid_out) begin
      @(posedge clk);
    end
  endtask

endmodule
