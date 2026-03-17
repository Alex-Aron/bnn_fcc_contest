module layer_tb #(
    parameter int NUM_TESTS = 1000,
    parameter int MIN_CYCLES_BETWEEN_TESTS = 1,
    parameter int MAX_CYCLES_BETWEEN_TESTS = 10
);

  // Parameters
  localparam int MAX_NEURON_INPUTS = 16;
  localparam int PW = 8;
  localparam int PN = 5;
  localparam int NEURONS_IN_THIS_LAYER = 10;
  localparam int SETS_OF_INPUTS = 2;

  localparam int NEURONS_MAPPED_TO_ME = NEURONS_IN_THIS_LAYER / PN;

  localparam int THRESHOLD_WIDTH = $clog2(MAX_NEURON_INPUTS + 1);
  localparam int DATA_WIDTH = PW;
  localparam int W_ADDR_WIDTH = $clog2(NEURONS_MAPPED_TO_ME * (MAX_NEURON_INPUTS / PW));
  localparam int T_ADDR_WIDTH = $clog2(NEURONS_MAPPED_TO_ME);

  // give me a bit that's 50/50 0 or 1 (assuming p=0.5)
  function automatic bit chance(real p);
    if (p > 1.0 || p < 0.0) $fatal(1, "Invalid probability in chance()");
    return ($urandom < (p * (2.0 ** 32)));
  endfunction

  // -------------- Testbench signals -------------
  logic clk;
  logic rst;

  logic [PW-1:0] layer_inputs;
  logic input_valid;

  logic [8-1:0] weight;
  logic weight_valid;

  logic [32-1:0] threshold;
  logic threshold_valid;

  logic [PN-1:0] ys;
  logic [THRESHOLD_WIDTH-1:0] popcounts[PN-1:0];
  logic layer_valid_out;
  // -------------- END Testbench signals -------------

  // Instantiate DUT
  layer #(
      .MAX_NEURON_INPUTS(MAX_NEURON_INPUTS),
      .PW(PW),
      .PN(PN)
      //.NEURONS_MAPPED_TO_ME(NEURONS_MAPPED_TO_ME)
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
    rand bit [PW-1:0] weights[NEURONS_IN_THIS_LAYER * MAX_NEURON_INPUTS/PW - 1:0];
    rand bit [PW-1:0] layer_inputs[SETS_OF_INPUTS*MAX_NEURON_INPUTS/PW-1:0];
    rand bit [THRESHOLD_WIDTH-1:0] thresholds[NEURONS_IN_THIS_LAYER-1:0];
  endclass

  typedef struct {
    int popcount[SETS_OF_INPUTS*NEURONS_IN_THIS_LAYER-1:0];
    bit y[SETS_OF_INPUTS*NEURONS_IN_THIS_LAYER-1:0];
  } neuron_result_t;


  // reference model
  // returns results for each neruon in the layer
  function neuron_result_t model(neuron_processor_item test_item, int id);
    automatic neuron_result_t result;
    //if (id == 0) begin
    //$display("---------------");
    //end
    for (int i = 0; i < NEURONS_IN_THIS_LAYER; i++) begin
      result.popcount[i] = 0;
      result.y[i] = 1'b0;
    end

    for (int k = 0; k < SETS_OF_INPUTS; k++) begin
      for (int i = 0; i < NEURONS_IN_THIS_LAYER; i++) begin
        for (int j = 0; j < MAX_NEURON_INPUTS / PW; j++) begin
          result.popcount[NEURONS_IN_THIS_LAYER*k+i] += $countones(
              test_item.weights[i*(MAX_NEURON_INPUTS/PW)+j] ~^ test_item.layer_inputs[NEURONS_IN_THIS_LAYER*k+j]
          );
          //if (id == 0) begin
          //$display("result.pop = %h; weight = %h; input = %h;", result.popcount[i],
          //test_item.weights[i*(MAX_NEURON_INPUTS/PW)+j], test_item.layer_inputs[j]);
          //end
        end

        // set popcount and y
        result.y[NEURONS_IN_THIS_LAYER*k+i] = result.popcount[NEURONS_IN_THIS_LAYER*k+i] >= test_item.thresholds[NEURONS_IN_THIS_LAYER*k+i];
      end
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
    weight_valid <= 1'b0;
    threshold_valid <= 1'b0;
    input_valid <= 1'b0;
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
      scoreboard_data_mailbox.put(model(test, i));
    end
  end

  // Monitor to detect the end of execution.
  neuron_result_t dut_output;
  int valid_out_counter;
  initial begin : done_monitor
    valid_out_counter = 0;
    forever begin
      @(posedge clk iff (layer_valid_out == 1'b0));
      @(posedge clk iff (layer_valid_out == 1'b1));
      valid_out_counter += 1;
      for (int i = 0; i < PN; i++) begin
        dut_output.popcount[i] = popcounts[i];
        dut_output.y[i] = ys[i];
      end
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
    int thresholds_sent, weights_sent;
    @(posedge clk iff !rst);
    thresholds_sent = 0;
    weights_sent = 0;
    forever begin
      driver_mailbox.get(item);

      // program weights and thresholds
      while (thresholds_sent < NEURONS_IN_THIS_LAYER || weights_sent < NEURONS_IN_THIS_LAYER * MAX_NEURON_INPUTS/PW) begin
        // le default values
        threshold_valid <= 1'b0;
        weight_valid <= 1'b0;

        // send a weight?
        if (chance(0.5) && thresholds_sent < NEURONS_IN_THIS_LAYER) begin
          threshold_valid <= 1'b1;
          threshold <= item.thresholds[thresholds_sent];
          thresholds_sent <= thresholds_sent + 1;
        end
        // send a threshold?
        if (chance(0.5) && weights_sent < NEURONS_IN_THIS_LAYER * MAX_NEURON_INPUTS / PW) begin
          weight_valid <= 1'b1;
          weight <= item.weights[weights_sent];
          weights_sent <= weights_sent + 1;
        end
        @(posedge clk);
      end
      thresholds_sent = 0;
      weights_sent = 0;

      threshold_valid <= 1'b0;
      weight_valid <= 1'b0;
      @(posedge clk);

      // send the entire input list once
      for (int i = 0; i < SETS_OF_INPUTS * MAX_NEURON_INPUTS / PW; i++) begin
        input_valid  <= 1'b1;
        layer_inputs <= item.layer_inputs[i];
        @(posedge clk);
      end

      input_valid <= 1'b0;

      // wait for NEURONS_IN_THIS_LAYER/PN valid_outs (RE DO ME)
      //last <= 1'b0;
      @(posedge clk iff valid_out_counter == SETS_OF_INPUTS * NEURONS_IN_THIS_LAYER / PN);
      valid_out_counter <= '0;

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
      // this has popcounts and ys from all neruons in the layer for each set
      // of inputs
      scoreboard_data_mailbox.get(expected);

      for (int j = 0; j < SETS_OF_INPUTS * NEURONS_IN_THIS_LAYER / PN; j++) begin
        // this has popcounts and ys from PN neruons in the layer
        scoreboard_result_mailbox.get(actual);

        for (int k = 0; k < PN; k++) begin
          if (actual.popcount[k] == expected.popcount[(j*PN)+k] && actual.y[k] == expected.y[(j*PN)+k]) begin
            $display("Test passed (time %0t)", $time);
            passed++;
          end else begin
            //$display("Test failed (time %0t): result_pop = %p instead of %p", $time, actual, expected);
            $display("Test failed (time %0t): result_pop = %p instead of %p", $time,
                     actual.popcount[k], expected.popcount[(j*PN)+k]);
            $display("Test failed (time %0t): result_y = %p instead of %p", $time,
                     actual.y[(j*PN)+k], expected.y[(j*PN)+k]);
            failed++;
          end
        end
      end
    end

    $display("Tests completed: %0d passed, %0d failed", passed, failed);
    disable generate_clock;
  end

  // assert property (@(posedge clk) disable iff (rst) last |-> input_valid);
endmodule

