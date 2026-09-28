// SPDX-License-Identifier: Apache-2.0
// From filmil/bazel_rules_vivado, build/tests/vivado/blinky.sv, unchanged
// but for this header, so that both rule sets build the same design.
module up_counter (
    output reg out
    , input  wire      clk
    , input  wire      reset
    );

    reg [7:0] count;

    always_ff @(posedge clk) begin
        if (reset) begin
            count <= 8'b0;
        end else begin
            count++;
        end
    end

    always_comb begin
        out <= count[7];
    end

    endmodule
