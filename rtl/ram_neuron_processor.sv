// this design assumes that what we want is stored sequentially in ram
// first threshold at address 0, then 1, then 2
// it also assumes that:
// 1. weights are "used" on the same cycle as valid_in is asserted
// 2. threshholds are "used" on the same cycle as valid_out is asserted
// A weight or threshhold is replaced (RAM address changes) the cycle after it's used 
module ram_neuron_processor #(
    /* parameters for neuron neuron_processor */
    parameter int MAX_NEURON_INPUTS = 8,  // total inputs per neuron
    parameter int PW = 8,  // weights inputs that can be processed in one pass
    localparam int THRESHOLD_WIDTH = $clog2(MAX_NEURON_INPUTS + 1),

    /* parameters for ram*/
    localparam int DATA_WIDTH = PW,
    // i feel like MAX_NEURON_INPUTS weights would be stored in here but i have no idea TODO
    localparam int W_ADDR_WIDTH = $clog2(MAX_NEURON_INPUTS),
    localparam int T_ADDR_WIDTH = $clog2(
        MAX_NEURON_INPUTS / PW
    ),  // this assumes MAX_NEURON_INPUTS % PW = 0
    parameter bit REG_RD_DATA = 1'b1,
    parameter string STYLE = ""  // idk what this does
) (
    input logic clk,
    input logic rst,

    // Weight ram Port A (only expose port A, port B used internally)
    // wram = weight ram
    input  logic                    wram_en_a,       // read as wram's en on port A, for example
    input  logic                    wram_wr_en_a,
    input  logic [W_ADDR_WIDTH-1:0] wram_addr_a,
    input  logic [  DATA_WIDTH-1:0] wram_wr_data_a,
    output logic [  DATA_WIDTH-1:0] wram_rd_data_a,

    // Threshhold ram Port A (only expose port A, port B used internally)
    // tram = threshhold ram
    input  logic                       tram_en_a,
    input  logic                       tram_wr_en_a,
    input  logic [   T_ADDR_WIDTH-1:0] tram_addr_a,
    input  logic [THRESHOLD_WIDTH-1:0] tram_wr_data_a,
    output logic [THRESHOLD_WIDTH-1:0] tram_rd_data_a,

    // TODO probably add a buffer or fifo or sm for input
    input logic [PW-1:0] inputs,

    input  logic                       valid_in,
    input  logic                       last,
    output logic                       valid_out,
    output logic                       y,
    output logic [THRESHOLD_WIDTH-1:0] popcount
);
  logic [T_ADDR_WIDTH-1:0] tram_addr_r, next_tram_addr;
  logic [W_ADDR_WIDTH-1:0] wram_addr_r, next_wram_addr;
  logic last_was_set_r; // for resetting threshold_ram, we reset when valid_out = 1 AFTER last was set
  logic next_last_was_set;

  /* counters and control */
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      tram_addr_r <= '0;
      wram_addr_r <= '0;
      last_was_set_r <= '0;
    end else begin
      tram_addr_r <= next_tram_addr;
      wram_addr_r <= next_wram_addr;
      last_was_set_r <= next_last_was_set;
    end
  end

  always_comb begin
    next_tram_addr = tram_addr_r;
    next_wram_addr = wram_addr_r;
    next_last_was_set = last_was_set_r;

    // valid_out = 1 implies we used the current threshold, so move to next
    if (valid_out) next_tram_addr = tram_addr_r + 1'b1;

    // valid_in = 1 implies we used the current weights, so move to next
    if (valid_in) next_wram_addr = wram_addr_r + 1'b1;

    if (last) next_wram_addr = '0;

    // if last = 1, we need to reset adress registers (in reality we have to schedule that
    // reset)
    if (last & valid_in) next_last_was_set = 1'b1;

    if (last_was_set_r & valid_out) begin
      next_last_was_set = 1'b0;
      next_tram_addr = '0;
    end
  end

  /* STRUCTURAL STUFF */

  logic [THRESHOLD_WIDTH-1:0] tram_rd_data;
  logic [DATA_WIDTH-1:0] wram_rd_data;

  // instantiate neuron_processor
  neuron_processor #(
      .MAX_NEURON_INPUTS(MAX_NEURON_INPUTS),
      .PW(PW)
  ) single_neuron (
      .clk(clk),
      .rst(rst),
      .weights(wram_rd_data),  // somehow connect to ram
      .inputs(inputs),
      .threshold(tram_rd_data),  // somehow connect to ram
      .valid_in(valid_in),
      .last(last),
      .valid_out(valid_out),
      .y(y),
      .popcount(popcount)
  );

  ram_tdp #(
      .DATA_WIDTH(DATA_WIDTH),
      .ADDR_WIDTH(W_ADDR_WIDTH),
      .REG_RD_DATA(REG_RD_DATA),
      .STYLE(STYLE)
  ) wram (
      .clk(clk),

      // Port A - to be used by configuration manager
      .en_a(wram_en_a),
      .wr_en_a(wram_wr_en_a),
      .addr_a(wram_addr_a),
      .wr_data_a(wram_wr_data_a),
      .rd_data_a(wram_rd_data_a),

      // Port B TODO connect this to the neuron_processor somehow
      .en_b(1'b1),  // always on?? TODO
      .wr_en_b(1'b0),
      .addr_b(next_wram_addr),
      .wr_data_b(),  // not used
      .rd_data_b(wram_rd_data)
  );

  ram_tdp #(
      .DATA_WIDTH(THRESHOLD_WIDTH),  // lol it's not data width sorry-bout-that
      .ADDR_WIDTH(T_ADDR_WIDTH),
      .REG_RD_DATA(REG_RD_DATA),
      .STYLE(STYLE)
  ) tram (
      .clk(clk),

      // Port A - to be used by configuration manager
      .en_a(tram_en_a),
      .wr_en_a(tram_wr_en_a),
      .addr_a(tram_addr_a),
      .wr_data_a(tram_wr_data_a),
      .rd_data_a(tram_rd_data_a),

      // Port B TODO connect this to the neuron_processor somehow
      .en_b(1'b1),  // always on?? TODO
      .wr_en_b(1'b0),
      .addr_b(next_tram_addr),
      .wr_data_b(),  // not used
      .rd_data_b(tram_rd_data)
  );

endmodule : ram_neuron_processor

