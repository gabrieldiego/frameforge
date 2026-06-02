`timescale 1ns/1ps

module ff_vvc_coding_tree_scheduler #(
  parameter int CTU_SIZE = 64
) (
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,

  output logic [15:0] coded_width,
  output logic [15:0] coded_height
);
  localparam int CODED_DIMENSION_GRANULARITY = 8;

  always_comb begin
    if (visible_width <= CODED_DIMENSION_GRANULARITY[15:0]) begin
      coded_width = CODED_DIMENSION_GRANULARITY[15:0];
    end else begin
      coded_width =
        ((visible_width + CODED_DIMENSION_GRANULARITY[15:0] - 16'd1) /
         CODED_DIMENSION_GRANULARITY[15:0]) *
        CODED_DIMENSION_GRANULARITY[15:0];
    end

    if (visible_height <= CODED_DIMENSION_GRANULARITY[15:0]) begin
      coded_height = CODED_DIMENSION_GRANULARITY[15:0];
    end else begin
      coded_height =
        ((visible_height + CODED_DIMENSION_GRANULARITY[15:0] - 16'd1) /
         CODED_DIMENSION_GRANULARITY[15:0]) *
        CODED_DIMENSION_GRANULARITY[15:0];
    end
  end

endmodule
