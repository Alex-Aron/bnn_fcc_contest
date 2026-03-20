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

  logic [31:0] weight_bytes_sent;  // todo size me
  logic [31:0] weights_in_shift_register;  // todo size me
  logic [8-1:0] weights[BUS_WIDTH/8-1:0];
  always_ff @(posedge clk or posedge rst) begin : PROCESS_WEIGHTSS
    if (rst) begin
      weight_bytes_sent <= '0;
      weights_in_shift_register <= '0;
      for (int i = 0; i < BUS_WIDTH / 8; i++) begin
        weights[i] <= '0;
      end
    end else begin
      if (state == PROCESS_WEIGHTS) begin
        // if out of weights, read more
        if (weights_in_shift_register == '0 && config_valid) begin
          weights_in_shift_register <= 8;
          for (int i = 0; i < BUS_WIDTH / 8; i++) begin
            weights[i] <= config_data_in[i*8+:8];
          end
        end

        // if we have weights, send them
        if (weights_in_shift_register != 0) begin
          weights_in_shift_register <= weights_in_shift_register - 1;
          weight_bytes_sent <= weight_bytes_sent + 1;
          for (int i = 0; i < (BUS_WIDTH / 8) - 1; i++) begin
            weights[i] <= weights[i+1];
          end
        end

        // if we are done, rst stuff plz :)
        if (weight_bytes_sent == header.payload_bytes) begin
          weight_bytes_sent <= '0;
          weights_in_shift_register <= '0;
        end
      end
    end
  end

  always_comb begin : assign_weight_outputs
    weight_wr_data = weights[0];
    weight_wr_en   = '0;

    if (state == PROCESS_WEIGHTS && weights_in_shift_register != 0) begin
      weight_wr_en[header.layer.id] = 1'b1;
    end
  end

  /////////////////////
  logic [31:0] thresh_bytes_sent;  // todo size me
  logic [31:0] thresh_in_shift_register;  // todo size me
  logic [31:0] threshholds[BUS_WIDTH/32-1:0];
  always_ff @(posedge clk or posedge rst) begin : PROCESS_THRESHOLDSS
    if (rst) begin
      thresh_bytes_sent <= '0;
      thresh_in_shift_register <= '0;
      for (int i = 0; i < BUS_WIDTH / 32; i++) begin
        threshholds[i] <= '0;
      end
    end else begin
      if (state == PROCESS_THRESHOLDS) begin
        // if out of threshholds, read more
        if (thresh_in_shift_register == '0 && config_valid) begin
          thresh_in_shift_register <= 2;
          for (int i = 0; i < BUS_WIDTH / 32; i++) begin
            threshholds[i] <= config_data_in[i*32+:32];
          end
        end

        // if we have threshholds, send them
        if (thresh_in_shift_register != 0) begin
          thresh_in_shift_register <= thresh_in_shift_register - 1;
          thresh_bytes_sent <= thresh_bytes_sent + 4;
          for (int i = 0; i < (BUS_WIDTH / 32) - 1; i++) begin
            threshholds[i] <= threshholds[i+1];
          end
        end

        // if we are done, rst stuff plz :)
        if (thresh_bytes_sent == header.payload_bytes) begin
          thresh_bytes_sent <= '0;
          thresh_in_shift_register <= '0;
        end
      end
    end
  end

  always_comb begin : assign_threshold_outputs
    threshold_wr_data = threshholds[0];
    threshold_wr_en   = '0;

    if (state == PROCESS_THRESHOLDS && thresh_in_shift_register != 0) begin
      threshold_wr_en[header.layer.id] = 1'b1;
    end
  end
  /////////////////////

  always_comb begin : assign_config_ready
    config_ready = 1'b1;

    if (state == PROCESS_WEIGHTS) begin
      if (weights_in_shift_register != '0) begin
        config_ready = 1'b0;
      end
    end

    if (state == PROCESS_THRESHOLDS) begin
      if (thresh_in_shift_register != '0) begin
        config_ready = 1'b0;
      end
    end
  end

  always_comb begin : next_state_logic
    next_state = state;
    case (state)
      HEADER_PARSE1: if (config_valid) next_state = HEADER_PARSE2;
      HEADER_PARSE2: begin
        if (config_valid) next_state = header.msg_type[0] ? PROCESS_THRESHOLDS : PROCESS_WEIGHTS;
      end
      PROCESS_WEIGHTS:
      next_state = weight_bytes_sent == header.payload_bytes ? HEADER_PARSE1 : PROCESS_WEIGHTS;
      PROCESS_THRESHOLDS:
      next_state = thresh_bytes_sent == header.payload_bytes ? HEADER_PARSE1 : PROCESS_WEIGHTS;
    endcase
  end
endmodule : config_manager
