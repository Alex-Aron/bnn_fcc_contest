module ram_neuron_processor #(
    /* parameters for neuron neuron_processor */
    parameter int MAX_NEURON_INPUTS = 8,  // total inputs per neuron
    parameter int PW = 8,  // weights inputs that can be processed in one pass
    localparam int THRESHOLD_WIDTH = $clog2(MAX_NEURON_INPUTS + 1),

    /* parameters for ram*/
    localparam int DATA_WIDTH = PW,
    // i feel like MAX_NEURON_INPUTS weights would be stored in here but i have no idea TODO
    localparam int ADDR_WIDTH = $clog2(MAX_NEURON_INPUTS + 1),
    parameter bit REG_RD_DATA = 1'b1,
    parameter string STYLE = ""
) (
    input logic clk,
    input logic rst,

    // Weight ram Port A (only expose port A, port B used internally)
    // wram = weight ram
    input  logic                  wram_en_a,       // read as wram's en on port A, for example
    input  logic                  wram_wr_en_a,
    input  logic [ADDR_WIDTH-1:0] wram_addr_a,
    input  logic [DATA_WIDTH-1:0] wram_wr_data_a,
    output logic [DATA_WIDTH-1:0] wram_rd_data_a,

    // Threshhold ram Port A (only expose port A, port B used internally)
    // tram = threshhold ram
    input  logic                  tram_en_a,
    input  logic                  tram_wr_en_a,
    input  logic [ADDR_WIDTH-1:0] tram_addr_a,
    input  logic [DATA_WIDTH-1:0] tram_wr_data_a,
    output logic [DATA_WIDTH-1:0] tram_rd_data_a,

    // TODO probably add a buffer or sm
    input logic [PW-1:0] inputs,

    input  logic                       valid_in,   // assume input always valid for now
    input  logic                       last,
    output logic                       valid_out,
    output logic                       y,
    output logic [THRESHOLD_WIDTH-1:0] popcount
);

  // instantiate neuron_processor
  neuron_processor #(
      .MAX_NEURON_INPUTS(MAX_NEURON_INPUTS),
      .PW(PW)
  ) single_neuron (
      .clk(clk),
      .rst(rst),
      .weights(),  // somehow connect to ram
      .inputs(inputs),
      .threshold(),  // somehow connect to ram
      .valid_in(valid_in),
      .last(last),
      .valid_out(valid_out),
      .y(y),
      .popcount(popcount)
  );

  ram_tdp #(
      .DATA_WIDTH(DATA_WIDTH),
      .ADDR_WIDTH(ADDR_WIDTH),
      .REG_RD_DATA(REG_RD_DATA),
      .STYLE(STYLE)
  ) wram (
      .clk(clk),

      // Port A
      .en_a(wram_en_a),
      .wr_en_a(wram_wr_en_a),
      .addr_a(wram_addr_a),
      .wr_data_a(wram_wr_data_a),
      .rd_data_a(wram_rd_data_a),

      // Port B TODO connect this to the neuron_processor somehow
      .en_b(),
      .wr_en_b(),
      .addr_b(),
      .wr_data_b(),
      .rd_data_b()
  );

  ram_tdp #(
      .DATA_WIDTH(THRESHOLD_WIDTH),  // lol it's not data width sorry-bout-that
      .ADDR_WIDTH(ADDR_WIDTH),
      .REG_RD_DATA(REG_RD_DATA),
      .STYLE(STYLE)
  ) tram (
      .clk(clk),

      // Port A
      .en_a(tram_en_a),
      .wr_en_a(tram_wr_en_a),
      .addr_a(tram_addr_a),
      .wr_data_a(tram_wr_data_a),
      .rd_data_a(tram_rd_data_a),

      // Port B TODO connect this to the neuron_processor somehow
      .en_b(),
      .wr_en_b(),
      .addr_b(),
      .wr_data_b(),
      .rd_data_b()
  );

endmodule : neuron_processor

