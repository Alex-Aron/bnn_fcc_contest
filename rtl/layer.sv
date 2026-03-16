module layer #(
    /* parameters for neuron neuron_processor */
    parameter int MAX_NEURON_INPUTS = 16,  // total inputs per neuron
    parameter int PW = 8,  // weights inputs that can be processed in one pass
    parameter int PN = 5,
    parameter int NEURONS_IN_THIS_LAYER = 10,
    localparam int THRESHOLD_WIDTH = $clog2(MAX_NEURON_INPUTS + 1),

    /* parameters for ram */
    localparam int W_ADDR_WIDTH = $clog2(NEURONS_MAPPED_TO_ME * (MAX_NEURON_INPUTS / PW)),
    localparam int T_ADDR_WIDTH = $clog2(NEURONS_MAPPED_TO_ME),
    localparam int NEURONS_MAPPED_TO_ME = NEURONS_IN_THIS_LAYER / PN  // ASSUME this works 
) (
    input logic clk,
    input logic rst,

    input logic [8-1:0] weight,
    input logic weight_valid,

    input logic [32-1:0] threshold,
    input logic threshold_valid
);
  /* --------------- ALL RAM NP SIGNALS      ---------------------*/
  // packed list of all the wram write ports
  logic                       wram_en_a     [PN-1:0];
  logic                       wram_wr_en_a  [PN-1:0];
  logic [   W_ADDR_WIDTH-1:0] wram_addr_a   [PN-1:0];
  logic [     DATA_WIDTH-1:0] wram_wr_data_a[PN-1:0];
  logic [     DATA_WIDTH-1:0] wram_rd_data_a[PN-1:0];

  // packed list of all the tram write ports
  logic                       tram_en_a     [PN-1:0];
  logic                       tram_wr_en_a  [PN-1:0];
  logic [   T_ADDR_WIDTH-1:0] tram_addr_a   [PN-1:0];
  logic [THRESHOLD_WIDTH-1:0] tram_wr_data_a[PN-1:0];
  logic [THRESHOLD_WIDTH-1:0] tram_rd_data_a[PN-1:0];

  // packed list of all the np signals
  logic [             PW-1:0] inputs        [PN-1:0];
  logic                       valid_in      [PN-1:0];
  logic                       last          [PN-1:0];
  logic                       valid_out     [PN-1:0];
  logic                       y             [PN-1:0];
  logic [THRESHOLD_WIDTH-1:0] popcount      [PN-1:0];
  /* --------------- END ALL RAM NP SIGNALS      ---------------------*/

  // create PN ram_neuron_processors
  for (genvar i = 0; i < PN; i++) begin : l_ram_neuron_processors
    ram_neuron_processor #(
        .NEURONS_MAPPED_TO_ME(NEURONS_MAPPED_TO_ME),
        .MAX_NEURON_INPUTS(MAX_NEURON_INPUTS),
        .PW(PW)
    ) u_ram_np (
        .clk(clk),
        .rst(rst),
        .wram_en_a(wram_en_a[i]),
        .wram_wr_en_a(wram_wr_en_a[i]),
        .wram_addr_a(wram_addr_a[i]),
        .wram_wr_data_a(wram_wr_data_a[i]),
        .wram_rd_data_a(wram_rd_data_a[i]),
        .tram_en_a(tram_en_a[i]),
        .tram_wr_en_a(tram_wr_en_a[i]),
        .tram_addr_a(tram_addr_a[i]),
        .tram_wr_data_a(tram_wr_data_a[i]),
        .tram_rd_data_a(tram_rd_data_a[i]),
        .inputs(inputs[i]),
        .valid_in(valid_in[i]),
        .last(last[i]),
        .valid_out(valid_out[i]),
        .y(y[i]),
        .popcount(popcount[i])
    );
  end

  // take the config stream and write to tram's
  // TODO add something to ignore first thresholds if not first layer
  // TODO add something to ignore trailing thresholds if not in last layer
  logic [  $clog2(NP)-1:0] t_current_np;  // max value is NP-1
  logic [T_ADDR_WIDTH-1:0] current_tram_addr_a;
  always_ff @(posedge clk or posedge rst) begin : program_tram
    // the default is that all the tram ports are disabled
    for (int i = 0; i < PN; i++) begin
      tram_en_a[i] <= 1'b0;
    end

    if (rst) begin
      t_current_np <= '0;
      current_tram_addr_a <= '0;
    end else begin
      if (threshold_valid) begin
        // write the threshold
        tram_en_a[t_current_np] <= 1'b1;
        tram_wr_en_a[t_current_np] <= 1'b1;  // TODO just hard code this to be 1
        tram_addr_a[t_current_np] <= current_tram_addr_a;
        tram_wr_data_a[t_current_np] <= threshold[THRESHOLD_WIDTH-1:0];

        // increment values as needed
        current_tram_addr_a <= current_tram_addr_a + 1;
        if (current_tram_addr_a == NEURONS_MAPPED_TO_ME - 1) begin
          t_current_np <= t_current_np + 1;
          current_tram_addr_a <= '0;
        end
      end
    end
  end

  // take the config stream and write to wrams
  // TODO add something to ignore first weights if not first layer
  // TODO add something to ignore trailing weights if not in last layer
  logic [  $clog2(NP)-1:0] t_current_np;  // max value is NP-1
  logic [W_ADDR_WIDTH-1:0] current_wram_addr_a;
  always_ff @(posedge clk or posedge rst) begin : program_wram
    // the default is that all the tram ports are disabled
    for (int i = 0; i < PN; i++) begin
      wram_en_a[i] <= 1'b0;
    end

    if (rst) begin
      t_current_np <= '0;
      current_wram_addr_a <= '0;
    end else begin
      if (weight_valid) begin
        // write the threshold
        wram_en_a[t_current_np] <= 1'b1;
        wram_wr_en_a[t_current_np] <= 1'b1;  // TODO just hard code this to be 1
        wram_addr_a[t_current_np] <= current_wram_addr_a;
        wram_wr_data_a[t_current_np] <= weight; // todo add some way to handle different sized weights

        // increment values as needed
        current_wram_addr_a <= current_wram_addr_a + 1;
        if (current_wram_addr_a == MAX_NEURON_INPUTS / PW * NEURONS_MAPPED_TO_ME - 1) begin
          t_current_np <= t_current_np + 1;
          current_wram_addr_a <= '0;
        end
      end
    end
  end

endmodule : layer

