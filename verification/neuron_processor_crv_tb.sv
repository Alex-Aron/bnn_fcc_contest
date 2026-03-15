// KNOWN BUG:
// fails if MAX_NEURON_INPUTS == PW (I feel like it's DUT's fault, not tb's
// fault)

module neuron_processor_crv_tb #(
    parameter int NUM_TESTS = 10000,
    parameter int MIN_CYCLES_BETWEEN_TESTS = 1,
    parameter int MAX_CYCLES_BETWEEN_TESTS = 10
);

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
  ) dut (
      .*
  );

  // scoreboard stuff
  int passed, failed;

  // mailboxes
  mailbox scoreboard_data_mailbox = new;
  mailbox scoreboard_result_mailbox = new;
  mailbox driver_mailbox = new;

  // inputs to the dut 
  class neuron_processor_item;
    rand bit [PW-1:0] weights[MAX_NEURON_INPUTS/PW - 1:0];
    rand bit [PW-1:0] inputs[MAX_NEURON_INPUTS/PW - 1:0];
    rand bit [THRESHOLD_WIDTH-1:0] threshold;
  endclass

  // dut expected output type
  typedef struct {
    int popcount;
    bit y;
  } neuron_result_t;


  // reference model
  function neuron_result_t model(neuron_processor_item test_item);
    automatic neuron_result_t result;
    result.popcount = 0;
    for (int i = 0; i < MAX_NEURON_INPUTS / PW; i++) begin
      result.popcount += $countbits(test_item.weights[i] ~^ test_item.inputs[i], '1);
    end

    result.y = result.popcount >= test_item.threshold;

    return result;
  endfunction

  // Clock generation
  initial begin : generate_clock
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Initialize the DUT.
  initial begin : initialization
    $timeformat(-9, 0, " ns");

    // Reset the design.
    rst <= 1'b1;
    valid_in <= 1'b0;
    last <= 1'b0;
    weights <= '0;
    inputs <= '0;
    threshold <= '0;
    repeat (5) @(posedge clk);
    @(negedge clk);
    rst <= 1'b0;
  end

  // Stimulus generation for random tests.
  initial begin : generator
    neuron_processor_item test;

    for (int i = 0; i < NUM_TESTS; i++) begin
      test = new();
      assert (test.randomize())
      else $fatal(1, "Failed to randomize.");

      driver_mailbox.put(test);
      scoreboard_data_mailbox.put(model(test));

    end
  end

  // Opted for no start monitor since i have all the test inputs in the
  // generator block anyways
  // Monitor to detect the start of execution.
  // TODO
  // initial begin : start_monitor
  // end

  // Monitor to detect the end of execution.
  neuron_result_t dut_output;
  initial begin : done_monitor
    forever begin
      @(posedge clk iff (valid_out == 1'b0));
      @(posedge clk iff (valid_out == 1'b1));
      dut_output.popcount = popcount;
      dut_output.y = y;
      scoreboard_result_mailbox.put(dut_output);
    end
  end

  // driver
  initial begin : driver
    neuron_processor_item item;
    @(posedge clk iff !rst);
    forever begin
      driver_mailbox.get(item);

      // send all the inputs with a valid_in and then the last one with
      // a valid_in and a last
      for (int i = 0; i < MAX_NEURON_INPUTS / PW - 1; i++) begin
        weights <= item.weights[i];
        inputs <= item.inputs[i];
        valid_in <= 1'b1;
        threshold <= item.threshold;
        last <= 1'b0;
        @(posedge clk);
      end

      weights <= item.weights[MAX_NEURON_INPUTS/PW-1];
      inputs <= item.inputs[MAX_NEURON_INPUTS/PW-1];
      valid_in <= 1'b1;
      threshold <= item.threshold;
      last <= 1'b1;
      @(posedge clk);

      @(posedge clk iff (valid_out == 1'b1));

      // Wait a random amount of time in between tests.
      repeat ($urandom_range(MIN_CYCLES_BETWEEN_TESTS - 1, MAX_CYCLES_BETWEEN_TESTS - 1));
      @(posedge clk);
    end
  end

  initial begin : scoreboard
    neuron_result_t expected, actual;

    passed = 0;
    failed = 0;

    for (int i = 0; i < NUM_TESTS; i++) begin
      scoreboard_data_mailbox.get(expected);
      scoreboard_result_mailbox.get(actual);

      if (actual == expected) begin
        $display("Test passed (time %0t)", $time);
        passed++;
      end else begin
        $display("Test failed (time %0t): result = %p instead of %p", $time, actual, expected);
        failed++;
      end
    end

    $display("Tests completed: %0d passed, %0d failed", passed, failed);
    disable generate_clock;
  end

endmodule


