module bnn #(
    parameter int LAYERS = 3,
    parameter int NUM_INPUTS=16, //start with 8. lets try to get 16 - 8 - 8 - 4 or some other, smaller configuration working first
    parameter int NUM_NEURONS[LAYERS] = '{8, 8, 4},
    parameter int PARALLEL_INPUTS = 8,
    // parameter int PARALLEL_NEURONS[LAYERS] = '{3{8}},
    parameter int MAX_PARALLEL_INPUTS = PARALLEL_INPUTS,  //idk if this is needed
    parameter int THRESHOLD_DATA_WIDTH = 32,

    parameter int PN = 4,

    localparam int NEURON_INPUTS[LAYERS] = '{NUM_INPUTS, NUM_NEURONS[0], NUM_NEURONS[1]}
) (
    input logic clk,
    input logic rst,

    input logic [     8-1:0] weight_wr_data,  // me when i hard code something for no reason :P
    input logic [LAYERS-1:0] weight_wr_en,

    input logic [THRESHOLD_DATA_WIDTH-1:0] threshold_wr_data,
    input logic [              LAYERS-1:0] threshold_wr_en,

    input logic [PARALLEL_INPUTS-1:0] data_in,
    input logic                       data_in_valid,


    output logic [                          PN-1:0] ys_out,
    output logic [$clog2(NEURON_INPUTS[2] + 1)-1:0] popcounts_out [PN-1:0],
    output logic                                    data_out_valid
);

  /*START LAYER SIGNALS*/
  logic [PARALLEL_INPUTS-1:0] layer_inputs[LAYERS-1:0];
  logic input_valid[LAYERS-1:0];

  logic [PN-1:0] ys[LAYERS-1:0];
  logic [$clog2(NEURON_INPUTS[2] + 1)-1:0] popcounts[LAYERS*PN-1:0];
  logic layer_valid_out[LAYERS-1:0];
  /* END LAYER SIGNALS*/

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
    popcounts_out = popcounts[(LAYERS-1)*PN+:PN];
  end

  for (genvar i = 0; i < LAYERS; i++) begin : l_generate_layers
    layer #(
        .MAX_NEURON_INPUTS(NEURON_INPUTS[i]),
        .PW(8),
        .PN(PN),
        .NEURONS_IN_THIS_LAYER(NUM_NEURONS[i]),
        .FIFO_SAFTEY_FACTOR(10)
    ) u_layer (
        .clk(clk),
        .rst(rst),
        .layer_inputs(layer_inputs[i]),
        .input_valid(input_valid[i]),
        .weight(weight_wr_data),
        .weight_valid(weight_wr_en[i]),
        .threshold(threshold_wr_data),
        .threshold_valid(threshold_wr_en[i]),
        .ys(ys[i]),
        .popcounts(popcounts[i*PN+:PN]),
        .layer_valid_out(layer_valid_out[i])
    );
  end

endmodule : bnn
