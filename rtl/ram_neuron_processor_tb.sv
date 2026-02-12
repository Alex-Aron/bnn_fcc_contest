`timescale 1 ns / 100 ps

module neuron_processor_tb;

  // Params
  parameter int MAX_NEURON_INPUTS = 8;
  parameter int PW = 8;
  parameter bit REG_RD_DATA = 1'b1;
  parameter string STYLE = "";
  // we also need some local params from inside the DUT, copied here
  localparam int THRESHOLD_WIDTH = $clog2(MAX_NEURON_INPUTS + 1);
  localparam int DATA_WIDTH = PW;
  localparam int ADDR_WIDTH = $clog2(MAX_NEURON_INPUTS + 1);

  // Signals
  logic                       clk;
  logic                       rst;

  // DUT signals
  logic                       wram_en_a;
  logic                       wram_wr_en_a;
  logic [     ADDR_WIDTH-1:0] wram_addr_a;
  logic [     DATA_WIDTH-1:0] wram_wr_data_a;
  logic [     DATA_WIDTH-1:0] wram_rd_data_a;
  logic                       tram_en_a;
  logic                       tram_wr_en_a;
  logic [     ADDR_WIDTH-1:0] tram_addr_a;
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
  initial begin : the_rabbits_clk
    forever #5 clk <= ~clk;
  end

  initial begin : apply_tests
    $timeformat(-9, 0, " ns");

    // rst and drive valid_in false
    rst <= 1'b1;
    valid_in <= 1'b0;
    #5
    // un-reset
    rst <= 1'b0;

    // TODO load the rams, provided the inputs, verify the inputs, put it all
    // in a loop :(

    $display("Tests completed.");
    disable generate_clock;
  end
endmodule
