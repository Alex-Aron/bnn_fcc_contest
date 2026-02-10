// TODO add registers to input and output for a total of 5 not 3
module neuron_proc #(
    parameter int MAX_NEURON_INPUTS = 8,
    parameter int PW = 8,

    parameter int THRESHHOLD_WIDTH = $clog2(MAX_NEURON_INPUTS + 1)
) (
    input logic [PW-1:0] inputs,
    input logic [PW-1:0] weights,
    input logic [THRESHHOLD_WIDTH-1:0] threshhold,
    input logic valid_in,
    input logic last,

    input logic clk,
    input logic rst,

    output logic valid_out,
    output logic y,
    output logic [THRESHHOLD_WIDTH-1:0] popcount
);
  /* delay and control signals + regs */
  // TODO just make a good shift register bro
  // also is you only ever use these signals in one place
  // then a delay would be better than a shift since you would/wouldn't need
  // to see/use the inbetween signals
  // TODO shorten these at the very least
  logic [2:0] valid_pipeline;
  logic [3:0] last_pipeline;
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      valid_pipeline <= 3'b0;
      last_pipeline  <= 4'b0;
    end else begin
      valid_pipeline <= {valid_pipeline[1:0], valid_in};
      last_pipeline  <= {last_pipeline[2:0], last};
    end
  end

  /* comb logic signals */
  logic [   $bits(inputs)-1:0] xnor_res;
  logic [THRESHHOLD_WIDTH-1:0] xnors_popcount;
  logic [ $bits(popcount)-1:0] next_accum;
  logic                        cmp_result;

  /* registers */
  logic [THRESHHOLD_WIDTH-1:0] accum_r;
  logic [              PW-1:0] xnor_res_r;
  logic [THRESHHOLD_WIDTH-1:0] popcount_res_r;

  always_comb begin
    xnor_res = inputs ~^ weights;
    xnors_popcount = $countones(xnor_res_r);
    next_accum = popcount_res_r;
    cmp_result = accum_r > threshhold;
    y = cmp_result;
    popcount = accum_r;
    valid_out = last_pipeline[2];
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      accum_r <= 0;
      xnor_res_r <= 0;
      popcount_res_r <= 0;
    end else begin
      xnor_res_r <= xnor_res;
      popcount_res_r <= xnors_popcount;

      if (valid_pipeline[1] == 1'b1) begin
        accum_r <= accum_r + next_accum;
      end

      if (last_pipeline[3] == 1'b1) begin
        accum_r <= 0;
      end
    end
  end
endmodule

