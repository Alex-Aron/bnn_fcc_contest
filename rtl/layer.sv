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

    input logic [PW-1:0] layer_inputs,
    input logic input_valid,

    input logic [8-1:0] weight,
    input logic weight_valid,

    input logic [32-1:0] threshold,
    input logic threshold_valid,

    output logic [PN-1:0] ys,
    output logic [THRESHOLD_WIDTH-1:0] popcounts[PN-1:0],
    output logic layer_valid_out
);
  assign ys = y;
  assign popcounts = popcount;
  assign layer_valid_out = valid_out[0];  // all neurons in a layer output at the same time

  /* --------------- ALL RAM NP SIGNALS      ---------------------*/
  // packed list of all the wram write ports
  logic                       wram_en_a     [PN-1:0];
  logic                       wram_wr_en_a  [PN-1:0];
  logic [   W_ADDR_WIDTH-1:0] wram_addr_a   [PN-1:0];
  logic [             PW-1:0] wram_wr_data_a[PN-1:0];
  logic [             PW-1:0] wram_rd_data_a[PN-1:0];

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

  // input buffer that holds MAX_NEURON_INPUTS/PW sets of inputs until they
  // are used by every neuron
  // TODO the tb assumes this doesn't exist
  logic [$clog2(MAX_NEURON_INPUTS/PW)-1:0] valid_in_count;
  logic [$clog2(NEURONS_IN_THIS_LAYER/PN)-1:0] valid_out_count;
  logic [PW-1:0] input_buffer[MAX_NEURON_INPUTS/PW-1:0];
  logic input_buffer_full;
  always_ff @(posedge clk or posedge rst) begin
    // the default is that all the neurons are disabled
    for (int i = 0; i < PN; i++) begin
      valid_in[i] <= 1'b0;
    end

    if (rst) begin
      input_buffer_full <= 1'b0;
      valid_in_count <= '0;
      valid_out_count <= '0;
      for (int i = 0; i < MAX_NEURON_INPUTS / PW; i++) begin
        input_buffer[i] <= '0;
      end
    end else begin
      // if the input buffer isn't full, this is a new input
      if (!input_buffer_full && input_valid) begin
        // 0. increment valid_in_count
        valid_in_count <= valid_in_count + 1;

        // 1. store to input buffer
        for (int i = 0; i < MAX_NEURON_INPUTS / PW - 1; i++) begin
          input_buffer[i] <= input_buffer[i+1];
        end
        input_buffer[MAX_NEURON_INPUTS/PW-1] <= layer_inputs;

        // 2. send to neurons in the layer
        for (int i = 0; i < PN; i++) begin
          inputs[i]   <= layer_inputs;
          valid_in[i] <= 1'b1;
        end

        // 3. check if input buffer full
        // (more like check if the buffer will be full after this input)
        // (more like check if the buffer is one away from being full)
        if (valid_in_count == MAX_NEURON_INPUTS / PW - 1) begin
          if (NEURONS_MAPPED_TO_ME != 1) begin
            input_buffer_full <= 1'b1;
          end
          valid_in_count <= '0;  // we can safely reset this here
          for (int i = 0; i < PN; i++) begin
            last[i] <= 1'b1;
            valid_out_count <= valid_out_count + 1;
          end
        end
      end

      // if the input buffer is full...
      // we have all the inputs already! spam them each cycle until they are
      // completely consumed by every neuron in this layer
      if (input_buffer_full) begin
        // we have already sent the input in MAX_NEURON_INPUTS/PW times, 
        // we have to send it in a total of MAX_NEURON_INPUTS/PW * NEURONS_MAPPED_TO_ME times
        // in other words, we are busy consuming this input for another
        // MAX_NEURON_INPUTS/PW * NEURONS_MAPPED_TO_ME - MAX_NEURON_INPUTS/PW
        // or
        // MAX_NEURON_INPUTS/PW * (NEURONS_MAPPED_TO_ME - 1) <------ assume NEURONS_MAPPED_TO_ME is > 1
        // cycles

        valid_in_count <= valid_in_count + 1;
        for (int i = 0; i < PN; i++) begin
          inputs[i]   <= input_buffer[valid_in_count];
          valid_in[i] <= 1'b1;
        end

        if (valid_in_count == MAX_NEURON_INPUTS / PW - 1) begin
          for (int i = 0; i < PN; i++) begin
            last[i] <= 1'b1;
          end

          valid_out_count <= valid_out_count + 1;
          valid_in_count  <= '0;

          if (valid_out_count + 1 == NEURONS_MAPPED_TO_ME) begin
            valid_out_count   <= '0;
            input_buffer_full <= '0;
          end
        end
      end
    end
  end

  // take the config stream and write to tram's
  // TODO add something to ignore first thresholds if not first layer
  // TODO add something to ignore trailing thresholds if not in last layer
  logic [  $clog2(PN)-1:0] t_current_np;  // max value is PN-1
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
  logic [  $clog2(PN)-1:0] w_current_np;  // max value is NP-1
  logic [W_ADDR_WIDTH-1:0] current_wram_addr_a;
  always_ff @(posedge clk or posedge rst) begin : program_wram
    // the default is that all the tram ports are disabled
    for (int i = 0; i < PN; i++) begin
      wram_en_a[i] <= 1'b0;
    end

    if (rst) begin
      w_current_np <= '0;
      current_wram_addr_a <= '0;
    end else begin
      if (weight_valid) begin
        // write the threshold
        wram_en_a[w_current_np] <= 1'b1;
        wram_wr_en_a[w_current_np] <= 1'b1;  // TODO just hard code this to be 1
        wram_addr_a[w_current_np] <= current_wram_addr_a;
        wram_wr_data_a[w_current_np] <= weight; // todo add some way to handle different sized weights

        // increment values as needed
        current_wram_addr_a <= current_wram_addr_a + 1;
        if (current_wram_addr_a == MAX_NEURON_INPUTS / PW * NEURONS_MAPPED_TO_ME - 1) begin
          w_current_np <= w_current_np + 1;
          current_wram_addr_a <= '0;
        end
      end
    end
  end

endmodule : layer

