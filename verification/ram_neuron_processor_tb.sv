`timescale 1 ns / 100 ps

module ram_neuron_processor_tb;

  // Params
  parameter int MAX_NEURON_INPUTS = 4;
  parameter int PW = 2;
  parameter bit REG_RD_DATA = 1'b1;
  parameter string STYLE = "";
  // we also need some local params from inside the DUT, copied here
  localparam int THRESHOLD_WIDTH = $clog2(MAX_NEURON_INPUTS + 1);
  localparam int W_ADDR_WIDTH = $clog2(MAX_NEURON_INPUTS / PW);
  localparam int T_ADDR_WIDTH = 1;  // TODO

  // Signals
  logic                       clk;
  logic                       rst;

  // DUT signals
  logic                       wram_en_a;
  logic                       wram_wr_en_a;
  logic [   W_ADDR_WIDTH-1:0] wram_addr_a;
  logic [             PW-1:0] wram_wr_data_a;
  logic [             PW-1:0] wram_rd_data_a;
  logic                       tram_en_a;
  logic                       tram_wr_en_a;
  logic [   T_ADDR_WIDTH-1:0] tram_addr_a;
  logic [THRESHOLD_WIDTH-1:0] tram_wr_data_a;
  logic [THRESHOLD_WIDTH-1:0] tram_rd_data_a;
  logic [             PW-1:0] inputs;
  logic                       valid_in;
  logic                       last;
  logic                       valid_out;
  logic                       y;
  logic [THRESHOLD_WIDTH-1:0] popcount;


  // DUT Instantiation
  ram_neuron_processor #(
      .MAX_NEURON_INPUTS(MAX_NEURON_INPUTS),
      .PW(PW),
      .REG_RD_DATA(REG_RD_DATA),
      .STYLE(STYLE)
  ) dut (
      .*
  );

  // start the clock
  initial begin : generate_clock
    clk <= '0;
    #5 forever #5 clk <= ~clk;
  end

  // generate random weights
  logic rams_ready;
  logic [PW-1:0] rand_weights[(1<<W_ADDR_WIDTH)-1:0];
  logic [THRESHOLD_WIDTH-1:0] rand_threshholds[T_ADDR_WIDTH-1:0];  // TODO kill me
  logic [PW-1:0] rand_inputs[(1<<W_ADDR_WIDTH)-1:0];
  int counter;
  initial begin : generate_input
    rams_ready <= 1'b0;

    // populate `weights` and `threshholds` vectors with random weights and threshholds
    // we need them as intermediates since they will also be used to compute
    // expected outputs
    for (int i = 0; i < (1 << W_ADDR_WIDTH); i++) begin
      rand_weights[i] <= $urandom;
      rand_inputs[i]  <= $urandom;
    end
    for (int i = 0; i < (1 << T_ADDR_WIDTH); i++) begin
      rand_threshholds[i] <= $urandom;
    end

    // actually write ts to rams :P
    wram_en_a <= 1'b1;
    wram_addr_a <= '0;
    wram_wr_en_a <= 1'b0;

    tram_en_a <= 1'b1;
    tram_addr_a <= '0;
    tram_wr_en_a <= 1'b0;

    @(posedge clk);

    for (int i = 0; i < (1 << W_ADDR_WIDTH) - 1; i++) begin
      wram_en_a <= 1'b1;
      wram_addr_a <= i;
      wram_wr_en_a <= 1'b1;
      wram_wr_data_a <= rand_weights[i];

      @(posedge clk);
    end
    wram_en_a <= 1'b0;

    for (int i = 0; i < (1 << T_ADDR_WIDTH) - 1; i++) begin
      tram_en_a <= 1'b1;
      tram_addr_a <= i;
      tram_wr_en_a <= 1'b1;
      tram_wr_data_a <= rand_weights[i];

      @(posedge clk);
    end
    tram_en_a  <= 1'b0;

    rams_ready <= 1'b1;
  end

  // signals for storing actual outputs
  initial begin : apply_tests
    $timeformat(-9, 0, " ns");

    // rst and drive valid_in false
    rst <= 1'b1;
    valid_in <= 1'b0;
    last <= 1'b0;
    @(negedge clk iff rams_ready == 1'b1);  // wait until rams are ready to start
    // un-reset
    rst <= 1'b0;
    @(posedge clk);  // in class dr stitt said he does this 
                     // i dont remember why tho


    // uses `int counter;` defined above this initial block
    // input all the inputs :P
    // assert last as needed
    counter = 0;
    for (int i = 0; i < (1 << W_ADDR_WIDTH); i++) begin
      counter++;
      inputs <= rand_inputs[i];
      valid_in <= '1;
      last <= counter == (MAX_NEURON_INPUTS / PW) ? 1'b1 : 1'b0;
      counter <= counter == (MAX_NEURON_INPUTS / PW) ? 0 : counter;
      @(posedge clk);
    end

    @(negedge clk iff valid_out == 1'b1);

    $display("Tests completed.");
    disable generate_clock;
  end
endmodule
