module ram_neuron_processor_tb #(
    parameter int NUM_TESTS = 1000,
    parameter int MIN_CYCLES_BETWEEN_TESTS = 1,
    parameter int MAX_CYCLES_BETWEEN_TESTS = 10,
    parameter int NEURONS_MAPPED_TO_ME = 2
);

  // Parameters
  localparam int MAX_NEURON_INPUTS = 16;
  localparam int PW = 8;
  localparam int THRESHOLD_WIDTH = $clog2(MAX_NEURON_INPUTS + 1);

  localparam int DATA_WIDTH = PW;
  localparam int W_ADDR_WIDTH = $clog2(NEURONS_MAPPED_TO_ME * (MAX_NEURON_INPUTS / PW));
  localparam int T_ADDR_WIDTH = $clog2(NEURONS_MAPPED_TO_ME);

  // -------------- Testbench signals -------------
  logic                       clk;
  logic                       rst;

  // Weight ram Port A (only expose port A; port B used internally)
  // wram = weight ram
  logic                       wram_en_a;  // read as wram's en on port A, for example
  logic                       wram_wr_en_a;
  logic [   W_ADDR_WIDTH-1:0] wram_addr_a;
  logic [     DATA_WIDTH-1:0] wram_wr_data_a;
  logic [     DATA_WIDTH-1:0] wram_rd_data_a;

  // Threshhold ram Port A (only expose port A; port B used internally)
  // tram = threshhold ram
  logic                       tram_en_a;
  logic                       tram_wr_en_a;
  logic [   T_ADDR_WIDTH-1:0] tram_addr_a;
  logic [THRESHOLD_WIDTH-1:0] tram_wr_data_a;
  logic [THRESHOLD_WIDTH-1:0] tram_rd_data_a;

  // TODO probably add a buffer or fifo or sm for input
  logic [             PW-1:0] inputs;

  logic                       valid_in;
  logic                       last;
  logic                       valid_out;
  logic                       y;
  logic [THRESHOLD_WIDTH-1:0] popcount;
  // -------------- END Testbench signals -------------

  // Instantiate DUT
  ram_neuron_processor #(
      .MAX_NEURON_INPUTS(MAX_NEURON_INPUTS),
      .PW(PW),
      .NEURONS_MAPPED_TO_ME(NEURONS_MAPPED_TO_ME)
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
    rand bit [PW-1:0] weights[NEURONS_MAPPED_TO_ME * MAX_NEURON_INPUTS/PW - 1:0];
    rand bit [PW-1:0] inputs[NEURONS_MAPPED_TO_ME * MAX_NEURON_INPUTS/PW - 1:0];
    rand bit [THRESHOLD_WIDTH-1:0] thresholds[NEURONS_MAPPED_TO_ME-1:0];
  endclass

  // dut expected output type
  // TODO in one place you'd like this to be list of results and in other
  // single result... maybe just make it a list of len1 idk could also make
  // a seperate struct idk (or unpack the packed one in model I actually like
  // that one best but idk)
  // This would require changes to scoreboard, whereever you call model, and
  // yeah
  typedef struct {
    int popcount[NEURONS_MAPPED_TO_ME-1:0];
    bit y[NEURONS_MAPPED_TO_ME-1:0];
  } neuron_result_t;


  // reference model
  function neuron_result_t model(neuron_processor_item test_item);
    automatic neuron_result_t result;

    for (int i = 0; i < NEURONS_MAPPED_TO_ME; i++) begin
      for (int j = 0; j < MAX_NEURON_INPUTS / PW; j++) begin
        result.popcount[i] += $countbits(
            test_item.weights[i*(MAX_NEURON_INPUTS/PW)+j] ~^ test_item.inputs[i*(MAX_NEURON_INPUTS/PW)+j],
            '1
        );
      end

      // set popcount and y
      result.y[i] = result.popcount[i] >= test_item.thresholds[i];
    end
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
    wram_en_a <= 1'b0;
    tram_en_a <= 1'b0;
    // other ram port stuff left as X (port is disabled so it doesn't matter
    // that they are X)
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
  int valid_out_counter;
  initial begin : done_monitor
    valid_out_counter = 0;
    forever begin
      @(posedge clk iff (valid_out == 1'b0));
      @(posedge clk iff (valid_out == 1'b1));
      valid_out_counter += 1;
      dut_output.popcount[0] = popcount;
      dut_output.y[0] = y;
      scoreboard_result_mailbox.put(dut_output);
    end
  end

  // driver TODO
  // load all rams and then input all inputs ig
  // could either run until valid_out is asserted NEURONS_MAPPED_TO_ME times 
  // or
  // just count all the inputs and iterate that many times idk
  initial begin : driver
    neuron_processor_item item;
    int addr;  // use int to make my life easier
    @(posedge clk iff !rst);
    forever begin
      driver_mailbox.get(item);

      // write weights to ram
      addr = 0;
      for (int i = 0; i < NEURONS_MAPPED_TO_ME * MAX_NEURON_INPUTS / PW; i++) begin
        wram_en_a <= 1'b1;
        wram_wr_en_a <= 1'b1;
        wram_addr_a <= addr;
        wram_wr_data_a <= item.weights[i];

        valid_in <= 1'b0;  // not needed but can't hurt
        addr <= addr + 1;
        @(posedge clk);
      end

      wram_en_a <= 1'b0;
      @(posedge clk);

      // write thresholds to ram
      addr = 0;
      for (int i = 0; i < NEURONS_MAPPED_TO_ME; i++) begin
        tram_en_a <= 1'b1;
        tram_wr_en_a <= 1'b1;
        tram_addr_a <= addr;
        tram_wr_data_a <= item.thresholds[i];

        valid_in <= 1'b0;  // not needed but can't hurt
        addr <= addr + 1;
        @(posedge clk);
      end

      tram_en_a <= 1'b0;
      valid_out_counter = 0;
      @(posedge clk);

      // atp all of the weights and thresholds are in ram :)
      // time to send inputs!

      // TODO send all the inputs!
      for (int i = 0; i < NEURONS_MAPPED_TO_ME; i++) begin
        for (int j = 0; j < MAX_NEURON_INPUTS / PW - 1; j++) begin
          inputs <= item.inputs[i*(MAX_NEURON_INPUTS/PW)+j];
          valid_in <= 1'b1;
          last <= 1'b0;
          @(posedge clk);
        end

        inputs <= item.inputs[i*(MAX_NEURON_INPUTS/PW)+MAX_NEURON_INPUTS/PW-1];
        valid_in <= 1'b1;
        last <= 1'b1;
        @(posedge clk);
      end

      // wait for NEURONS_MAPPED_TO_ME valid_outs
      valid_in <= 1'b0;
      last <= 1'b0;
      @(posedge clk iff valid_out_counter == NEURONS_MAPPED_TO_ME);

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
      // "packed" | all neurons that are mapped put into one
      // tldr: contains `NEURONS_MAPPED_TO_ME` popcounts
      scoreboard_data_mailbox.get(expected);

      for (int j = 0; j < NEURONS_MAPPED_TO_ME; j++) begin
        // single
        // tldr: contains 1 popcount
        scoreboard_result_mailbox.get(actual);

        if (actual.popcount[0] == expected.popcount[j] && actual.y[0] == expected.y[j]) begin
          $display("Test passed (time %0t)", $time);
          passed++;
        end else begin
          //$display("Test failed (time %0t): result_pop = %p instead of %p", $time, actual, expected);
          $display("Test failed (time %0t): result_pop = %p instead of %p", $time,
                   actual.popcount[0], expected.popcount[j]);
          $display("Test failed (time %0t): result_y = %p instead of %p", $time, actual.y[0],
                   expected.y[j]);
          failed++;
        end
      end
    end

    $display("Tests completed: %0d passed, %0d failed", passed, failed);
    disable generate_clock;
  end
endmodule

