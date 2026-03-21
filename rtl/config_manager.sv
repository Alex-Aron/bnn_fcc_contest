module config_manager #(
    parameter int BUS_WIDTH = 64,
    parameter int LAYERS = 3,
    parameter int PARALLEL_INPUTS = 8,
    parameter int PARALLEL_NEURONS[LAYERS] = '{default: 8}
) (
    input  logic                       clk,
    input  logic                       rst,
    input  logic [      BUS_WIDTH-1:0] config_data_in,
    input  logic                       config_valid,
    input  logic [    BUS_WIDTH/8-1:0] config_keep,
    input  logic                       config_last,
    output logic                       config_ready,
    output logic [PARALLEL_INPUTS-1:0] weight_wr_data,
    output logic [         LAYERS-1:0] weight_wr_en,
    output logic [               31:0] threshold_wr_data,
    output logic [         LAYERS-1:0] threshold_wr_en
);

  /*
Define in and out ports in relation to the top level in the example bnn_fcc
*: Write enable has a seperate enable for each layer. Maybe instead of that we have a single logic bit,
and we just control which layer we write to through the fsm?
Just ideas, I am going to work on this I just want to push after making the two modules
*/
  // hardcode bus width being 64 for now?
  // number of states can just change as needed
  localparam int TOTAL_MESSAGES = 2 * LAYERS;

  initial
    if (BUS_WIDTH != 64) $fatal(1, "currently hardcoded for bus width 64 (final width anyways)");

  // This is mad overkill but I want to see how certain things work in this lang
  typedef struct packed {
    logic [7:0]  id;
    logic [15:0] num_inputs;
    logic [15:0] num_neurons;
  } layer_t;

  // wait!!!! header_t is a great idea (its over)
  typedef struct packed {
    logic [7:0] msg_type;
    layer_t layer;
    logic [15:0] bytes_per_neuron;
    logic [31:0] payload_bytes;
  } header_t;

  header_t header;

  typedef enum logic [3:0] {
    HEADER_PARSE1,
    HEADER_PARSE2,
    PROCESS_WEIGHTS,
    PROCESS_THRESHOLDS,  // enter a diff state based on the message type
    // thought of adding an error 
    FINISH_LAYER  // some state to just process anything remaining in layer (or reset stuff) 
  } state_t;

  state_t state, next_state;

  always_ff @(posedge clk or posedge rst)
    if (rst) state <= HEADER_PARSE1;
    else state <= next_state;


  always_ff @(posedge clk or posedge rst) begin : state_out
    if (rst) begin
      header <= '0;
    end else begin
      case (state)
        HEADER_PARSE1: begin
          if (config_valid) begin
            header.msg_type <= config_data_in[7:0];
            header.layer.id <= config_data_in[15:8];
            header.layer.num_inputs <= config_data_in[31:16];
            header.layer.num_neurons <= config_data_in[47:32];
            header.bytes_per_neuron <= config_data_in[63:48];
          end
        end
        HEADER_PARSE2: begin
          if (config_valid) begin
            header.payload_bytes <= config_data_in[31:0];
          end
        end
      endcase
    end
  end

  logic [31:0] bytes_read;
  logic [BUS_WIDTH/8-1:0] weights_last;
  logic [BUS_WIDTH/32-1:0] thresholds_last;

  always_comb begin : next_state_logic
    next_state = state;
    case (state)
      HEADER_PARSE1: if (config_valid) next_state = HEADER_PARSE2;
      HEADER_PARSE2: begin
        if (config_valid) next_state = header.msg_type[0] ? PROCESS_THRESHOLDS : PROCESS_WEIGHTS;
      end
      PROCESS_WEIGHTS:
      next_state = ( (header.payload_bytes == bytes_read) && (weights_last[0] == 1'b1) ) ? HEADER_PARSE1 : PROCESS_WEIGHTS;
      PROCESS_THRESHOLDS:
      next_state = ( (header.payload_bytes == bytes_read) && (thresholds_last[0] == 1'b1) ) ? HEADER_PARSE1 : PROCESS_THRESHOLDS;
    endcase
  end

  always_ff @(posedge clk or posedge rst) begin : track_bytes_read
    if (rst) begin
      bytes_read <= '0;
    end else begin
      if (state == HEADER_PARSE2) begin
        bytes_read <= '0;
      end else if (config_valid && config_ready) begin
        bytes_read <= bytes_read + BUS_WIDTH / 8;
      end
    end
  end

  logic [8-1:0] weights[BUS_WIDTH/8-1:0];
  assign weight_wr_data = weights[0];
  always_ff @(posedge clk or posedge rst) begin : PROCESS_WEIGHTS_PAYLOAD
    if (rst) begin
      weights_last <= '0;
      for (int i = 0; i < BUS_WIDTH / 8; i++) begin
        weights[i] <= '0;
      end

    end else if (state == PROCESS_WEIGHTS) begin
      // do we need to read more into shift reg?
      if (config_ready && config_valid) begin
        for (int i = 0; i < BUS_WIDTH / 8; i++) begin
          weights[i] <= config_data_in[i*8+:8];
        end
        weights_last[BUS_WIDTH/8-1] <= 1'b1;
        weights_last[0] <= 1'b0;
      end else if ($countones(weights_last) != '0) begin
        // shfit the registers
        for (int i = 0; i < BUS_WIDTH / 8 - 1; i++) begin
          weights[i] <= weights[i+1];
          weights_last[i] <= weights_last[i+1];
        end

        // shift in a 0 for the weights_last
        weights_last[BUS_WIDTH/8-1] <= 1'b0;
      end

    end
  end

  always_comb begin : set_weight_wr_en
    weight_wr_en = '0;
    if ($countones(weights_last) != '0) begin
      weight_wr_en[header.layer.id] = 1'b1;
    end
  end
  ///////////////////////// TODO add thresh
  logic [32-1:0] thresholds[BUS_WIDTH/32-1:0];
  assign threshold_wr_data = thresholds[0];
  always_ff @(posedge clk or posedge rst) begin : PROCESS_THRESHOLDS_PAYLOAD
    if (rst) begin
      thresholds_last <= '0;
      for (int i = 0; i < BUS_WIDTH / 32; i++) begin
        thresholds[i] <= '0;
      end

    end else if (state == PROCESS_THRESHOLDS) begin
      // do we need to read more into shift reg?
      if (config_ready && config_valid) begin
        for (int i = 0; i < BUS_WIDTH / 32; i++) begin
          thresholds[i] <= config_data_in[i*32+:32];
        end
        thresholds_last[BUS_WIDTH/32-1] <= 1'b1;
        thresholds_last[0] <= 1'b0;
      end else if ($countones(thresholds_last) != '0) begin
        // shfit the registers
        for (int i = 0; i < BUS_WIDTH / 32 - 1; i++) begin
          thresholds[i] <= thresholds[i+1];
          thresholds_last[i] <= thresholds_last[i+1];
        end

        // shift in a 0 for the weights_last
        thresholds_last[BUS_WIDTH/32-1] <= 1'b0;
      end

    end
  end

  always_comb begin : set_threshold_wr_en
    threshold_wr_en = '0;
    if ($countones(thresholds_last) != '0) begin
      threshold_wr_en[header.layer.id] = 1'b1;
    end
  end
  //////////////////////

  always_comb begin : set_config_ready
    config_ready = 1'b1;

    if (state == PROCESS_WEIGHTS) begin
      config_ready = 1'b0;

      if (bytes_read == '0) begin
        config_ready = 1'b1;
      end

      if (weights_last[0] == 1'b1 && header.payload_bytes != bytes_read) begin
        config_ready = 1'b1;
      end

      if ($countones(weights_last) == '0 && header.payload_bytes != bytes_read) begin
        config_ready = 1'b1;
      end
    end

    ///////////////////
    if (state == PROCESS_THRESHOLDS) begin
      config_ready = 1'b0;

      if (bytes_read == '0) begin
        config_ready = 1'b1;
      end

      if (thresholds_last[0] == 1'b1 && header.payload_bytes != bytes_read) begin
        config_ready = 1'b1;
      end

      if ($countones(thresholds_last) == '0 && header.payload_bytes != bytes_read) begin
        config_ready = 1'b1;
      end
    end
  end

endmodule : config_manager
