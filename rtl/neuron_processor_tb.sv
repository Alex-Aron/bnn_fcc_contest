// TODO: add more tests, just had gemini make this after finishing my neuron processor to see if it passed the most basic tests

module neuron_processor_tb;

    // Params
    localparam int MAX_NEURON_INPUTS = 32;
    localparam int PW = 8;
    localparam int THRESHOLD_WIDTH = $clog2(MAX_NEURON_INPUTS + 1);

    // Signals
    logic clk;
    logic rst;
    logic [PW-1:0] weights;
    logic [MAX_NEURON_INPUTS-1:0] total_weights;
    logic [MAX_NEURON_INPUTS-1:0] total_inputs;
    logic [PW-1:0] inputs;
    logic [THRESHOLD_WIDTH-1:0] threshold;

    logic valid_in;
    logic last;
    logic valid_out;
    logic y;
    logic y_correct;
    logic [THRESHOLD_WIDTH-1:0] popcount;
    logic [THRESHOLD_WIDTH-1:0] popcount_correct;


    // DUT Instantiation
    neuron_processor #(
        .MAX_NEURON_INPUTS(MAX_NEURON_INPUTS),
        .PW               (PW)
    ) dut (
        .clk,
        .rst,
        .weights,
        .inputs,
        .threshold,
        .valid_in,
        .last,
        .valid_out,
        .y,
        .popcount
    );

    initial begin : generate_clock
        clk <= 1'b0;
        forever #5 clk <= ~clk;
    end

    // Test Procedure
    initial begin : drive_inputs
        $timeformat(-9, 0, " ns");
        $dumpfile("neuron_tb.vcd");
        $dumpvars(0, neuron_processor_tb);
        // Initialize
        rst <= 1;
        valid_in <= 1;  // TODO: test valid in turning on and off randomly

        repeat (2) @(posedge clk);
        rst <= 0;
        @(posedge clk);

        for (int i = 0; i < 10000; i++) begin
            total_weights <= $urandom;
            total_inputs <= $urandom;
            threshold <= $urandom;
            @(posedge clk);
            popcount_correct <= $countones(total_weights ~^ total_inputs);
            y_correct <= $countones(total_weights ~^ total_inputs) >= int'(threshold) ? 1 : 0;
            for (int j = 0; j <= MAX_NEURON_INPUTS / PW; j++) begin
                if (j == MAX_NEURON_INPUTS / PW - 1) last <= 1;
                else last <= '0;
                weights  <= total_weights[j*PW+:PW];
                inputs   <= total_inputs[j*PW+:PW];
                valid_in <= 1'b1;
                @(posedge clk);
            end
            if (popcount_correct != popcount)
                $error("Popcount should be %d but is %d", popcount_correct, popcount);
            if (y_correct != y) $error("Y should be %d but is %d", y_correct, y);


        end

        $finish;
    end


    assert property (@(posedge clk) disable iff (rst) last |=> valid_out);


endmodule
