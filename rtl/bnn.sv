module bnn #(
    parameter int LAYERS = 3,
    parameter int NUM_INPUTS = 8,  // MAX_NEURON_INPUTS of first hidden layer
    parameter int NUM_NEURONS[LAYERS] = '{8, 8, 8},  // the number of neurons in each layer
    parameter int PARALLEL_INPUTS = 8, // Number of inputs consumed simultaneously in the first hidden layer
    parameter int PARALLEL_NEURONS[LAYERS] = '{8, 8, 8},  // PN for each layer
    parameter int MAX_PARALLEL_INPUTS = PARALLEL_INPUTS,  //idk if this is needed
    parameter int THRESHOLD_DATA_WIDTH = 32,

    // fan in of each layer
    localparam int NEURON_INPUTS[LAYERS] = '{PARALLEL_INPUTS, NUM_NEURONS[0], NUM_NEURONS[1]}
) (
    input logic clk,
    input logic rst,

    input  logic en,
    output logic ready,

    input logic [     MAX_PARALLEL_INPUTS-1:0] weight_wr_data,  // me when i hard code something for no reason :P
    input logic [LAYERS-1:0] weight_wr_en,

    input logic [THRESHOLD_DATA_WIDTH-1:0] threshold_wr_data,
    input logic [              LAYERS-1:0] threshold_wr_en,

    input logic [PARALLEL_INPUTS-1:0] data_in,
    input logic                       data_in_valid,


    output logic [PARALLEL_NEURONS[LAYERS-1]-1:0] ys_out,

    output logic [THRESHOLD_DATA_WIDTH-1:0] popcounts_out [PARALLEL_NEURONS[LAYERS-1]-1:0],
    output logic                            data_out_valid
);

  /*START LAYER SIGNALS*/
  logic [PARALLEL_INPUTS-1:0] layer_inputs[LAYERS-1:0];
  logic input_valid[LAYERS-1:0];

  logic layer_ready[LAYERS-1:0];

  logic [8-1:0] ys[LAYERS-1:0];  // TODO change to be a param
  logic [THRESHOLD_DATA_WIDTH-1:0] popcounts[LAYERS-1:0][8-1:0];
  logic layer_valid_out[LAYERS-1:0];
  /* END LAYER SIGNALS*/

  always_comb begin : assign_ready
    // it's just all the ready signals or'd together
    // THIS IS THE WORST WAY EVER TO OR A BUNCH OF BITS
    ready = $countones(layer_ready) != 0;
  end

  always_comb begin : assign_layer_inputs
    layer_inputs[0] = data_in;
    for (int i = 1; i < LAYERS; i++) begin
      layer_inputs[i] = ys[i-1];
    end
  end

  always_comb begin : assign_layer_input_valid
    input_valid[0] = data_in_valid;
    for (int i = 1; i < LAYERS; i++) begin
      input_valid[i] = layer_valid_out[i-1];
    end
  end

  always_comb begin : assign_module_outputs
    data_out_valid = layer_valid_out[LAYERS-1];
    ys_out = ys[LAYERS-1];
    popcounts_out = popcounts[LAYERS-1];
  end

  for (genvar i = 0; i < LAYERS; i++) begin : l_generate_layers
    layer #(
        .MAX_NEURON_INPUTS(NEURON_INPUTS[i]),
        .PW(8),
        .PN(PARALLEL_NEURONS[i]),
        .NEURONS_IN_THIS_LAYER(NUM_NEURONS[i]),
        .FIFO_SAFTEY_FACTOR(10)
    ) u_layer (
        .clk(clk),
        .rst(rst),
        .layer_en(en),
        .layer_ready(layer_ready[i]),
        .layer_inputs(layer_inputs[i]),
        .input_valid(input_valid[i]),
        .weight(weight_wr_data),
        .weight_valid(weight_wr_en[i]),
        .threshold(threshold_wr_data),
        .threshold_valid(threshold_wr_en[i]),
        .ys(ys[i]),
        .popcounts(popcounts[i]),
        .layer_valid_out(layer_valid_out[i])
    );
  end

endmodule : bnn
