// SPDX-License-Identifier: Apache-2.0
// SystemVerilog blinky design using a package and an interface.
package counter_pkg;
  typedef struct packed {
    logic [7:0] val;
  } counter_val_t;
endpackage

interface counter_if(input logic clk);
  logic [7:0] count;
  logic reset;
  logic out;
  modport counter_port(input clk, input reset, output count, output out);
endinterface

module up_counter_sv (
  input  wire clk,
  input  wire reset,
  output wire out
);
  import counter_pkg::*;

  counter_if cif(clk);
  assign cif.reset = reset;
  assign out = cif.out;

  always_ff @(posedge clk) begin
    if (cif.reset) begin
      cif.count <= 8'b0;
    end else begin
      cif.count <= cif.count + 8'b1;
    end
  end

  assign cif.out = cif.count[7];
endmodule
