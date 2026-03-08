module config_manager #(
    parameter int BUS_WIDTH = 32,
    parameter int LAYERS = 3,
    parameter int PARALLEL_INPUTS = 8,
    parameter int PARALLEL_NEURONS[LAYERS] = '{default: 8}
) (
    input logic                       clk,
    input logic                       rst,
    input logic [      BUS_WIDTH-1:0] config_data_in,
    input logic                       config_valid,
    input logic [    BUS_WIDTH/8-1:0] config_keep,
    input logic                       config_last,
    output logic                       config_ready,
    input logic [PARALLEL_INPUTS-1:0] weight_wr_data,
    input logic [         LAYERS-1:0] weight_wr_en,
    input logic [               31:0] threshold_wr_data,
    input logic [         LAYERS-1:0] threshold_wr_en
);

/*
Define in and out ports in relation to the top level in the example bnn_fcc
*: Write enable has a seperate enable for each layer. Maybe instead of that we have a single logic bit,
and we just control which layer we write to through the fsm?
Just ideas, I am going to work on this I just want to push after making the two modules
*/

endmodule : config_manager
