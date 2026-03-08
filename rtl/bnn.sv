module bnn #(
    parameter int LAYERS = 3,
    parameter int NUM_INPUTS=16, //start with 8. lets try to get 16 - 8 - 8 - 4 or some other, smaller configuration working first
    parameter int NUM_NEURONS[LAYERS] = '{8, 8, 4},
    parameter int PARALLEL_INPUTS = 8,
    parameter int PARALLEL_NEURONS[LAYERS] = '{3{8}},
    parameter int MAX_PARALLEL_INPUTS = PARALLEL_INPUTS,  //idk if this is needed
    parameter int THRESHOLD_DATA_WIDTH = 32
) (
    input  logic                            clk,
    input  logic                            rst,
    input  logic                            en,
    input  logic                            ready,
    input  logic [     PARALLEL_INPUTS-1:0] weight_wr_data,
    input  logic [              LAYERS-1:0] weight_wr_en,
    input  logic [THRESHOLD_DATA_WIDTH-1:0] threshold_wr_data,
    input  logic [              LAYERS-1:0] threshold_wr_en,
    input  logic [     PARALLEL_INPUTS-1:0] data_in,
    input  logic                            data_in_valid,
    output logic                            data_out,
    output logic [THRESHOLD_DATA_WIDTH-1:0] count_out        [PARALLEL_NEURONS[0]],
    output logic                            data_out_valid
);

endmodule : bnn
