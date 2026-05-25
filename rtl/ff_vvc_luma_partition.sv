`timescale 1ns/1ps

module ff_vvc_luma_partition (
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,

  output logic [15:0] coded_width,
  output logic [15:0] coded_height,
  output logic        root_quad_split,
  output logic [7:0]  luma_leaf_count
);
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

    root_quad_split = (coded_width > 16'd32) || (coded_height > 16'd32);
    luma_leaf_count = root_quad_split ? 8'd4 : 8'd1;
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
        coded_dimension = 16'd64;
      end
    end
  endfunction
endmodule
