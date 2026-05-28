`timescale 1ns/1ps

module ff_vvc_luma_partition (
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,

  output logic [15:0] coded_width,
  output logic [15:0] coded_height,
  output logic        root_quad_split,
  output logic [7:0]  luma_leaf_count
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

    root_quad_split = (coded_width > 16'd32) || (coded_height > 16'd32);
    luma_leaf_count = root_quad_split ? 8'd4 : 8'd1;
  end
endmodule
