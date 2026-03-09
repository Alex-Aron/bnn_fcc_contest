module neuron_processor #(
    parameter int MAX_NEURON_INPUTS = 8,  // total inputs per neuron
    parameter int PW = 8,  // weights inputs that can be processed in one pass
    localparam int THRESHOLD_WIDTH = $clog2(MAX_NEURON_INPUTS + 1)
) (
    input  logic                       clk,
    input  logic                       rst,
    input  logic [             PW-1:0] weights,
    input  logic [             PW-1:0] inputs,
    input  logic [THRESHOLD_WIDTH-1:0] threshold,
    input  logic                       valid_in,   // assume input always valid for now
    input  logic                       last,
    output logic                       valid_out,
    output logic                       y,
    output logic [THRESHOLD_WIDTH-1:0] popcount
);
    logic [THRESHOLD_WIDTH-1:0] popcount_r, pop_out, next_pop;
    logic v_out;

    assign y = (pop_out >= threshold) ? 1 : 0;
    assign popcount = pop_out;
    assign valid_out = v_out;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            popcount_r <= '0;
            v_out <= '0;
            pop_out <= '0;
        end else begin
            if (last && valid_in) begin
                popcount_r <= '0;
                pop_out <= next_pop;
                v_out <= '1;
            end else begin
                popcount_r <= next_pop;
                v_out <= '0;
                pop_out <= '0;
            end
        end

    end

    always_comb begin
        next_pop = popcount_r;
        if (valid_in) next_pop = popcount_r + THRESHOLD_WIDTH'(unsigned'($countones(weights ~^ inputs)));
    end

endmodule : neuron_processor
