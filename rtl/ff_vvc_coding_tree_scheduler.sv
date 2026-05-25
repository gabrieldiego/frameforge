`timescale 1ns/1ps

module ff_vvc_coding_tree_scheduler #(
  parameter int CTU_SIZE = 64
) (
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,

  output logic [15:0] coded_width,
  output logic [15:0] coded_height,
  output logic [1:0]  body_kind
);
  localparam logic [1:0] BODY_GENERATED       = 2'd0;

  always_comb begin
    coded_width = coded_dimension(visible_width);
    coded_height = coded_dimension(visible_height);

    if ((visible_width <= 16'd32) && (visible_height <= 16'd32) &&
        ((visible_width > 16'd16) || (visible_height > 16'd16))) begin
      coded_width = 16'd32;
      coded_height = 16'd32;
    end else if ((visible_width <= 16'd16) && (visible_height <= 16'd16) &&
        ((visible_width > 16'd8) || (visible_height > 16'd8))) begin
      coded_width = 16'd16;
      coded_height = 16'd16;
    end

    body_kind = BODY_GENERATED;
  end

  function automatic logic [15:0] coded_dimension(input logic [15:0] value);
    begin
      if (value <= 16'd8) begin
        coded_dimension = 16'd8;
      end else if (value <= 16'd16) begin
        coded_dimension = 16'd16;
      end else if (value <= 16'd32) begin
        coded_dimension = 16'd32;
      end else begin
        coded_dimension = CTU_SIZE[15:0];
      end
    end
  endfunction

endmodule
