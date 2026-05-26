`timescale 1ns/1ps

module ff_vvc_luma_partition (
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,

  output logic [15:0] coded_width,
  output logic [15:0] coded_height,
  output logic        root_quad_split,
  output logic [7:0]  luma_leaf_count
);
  import ff_vvc_geometry_pkg::*;

  always_comb begin
    coded_width = ff_vvc_coded_dimension(visible_width);
    coded_height = ff_vvc_coded_dimension(visible_height);

    root_quad_split = (coded_width > 16'd32) || (coded_height > 16'd32);
    luma_leaf_count = root_quad_split ? 8'd4 : 8'd1;
  end
endmodule
