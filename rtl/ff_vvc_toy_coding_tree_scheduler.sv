`timescale 1ns/1ps

module ff_vvc_toy_coding_tree_scheduler (
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,

  output logic [15:0] coded_width,
  output logic [15:0] coded_height,
  output logic [1:0]  body_kind,
  output logic        uses_capacity_tu_grid,
  output logic [12:0] luma_tu_count,
  output logic [12:0] capacity_tu_grid_bit_len
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

    uses_capacity_tu_grid = uses_generated_tu_grid(coded_width, coded_height);
    luma_tu_count = ((visible_width + 16'd3) >> 2) * ((visible_height + 16'd3) >> 2);
    capacity_tu_grid_bit_len = 13'd16 + (luma_tu_count * 13'd13);
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

  function automatic logic supports_generated_body(
    input logic [15:0] width,
    input logic [15:0] height
  );
    begin
      supports_generated_body =
        ((width == 16'd8) && (height == 16'd8)) ||
        ((width == 16'd16) && (height == 16'd16)) ||
        ((width == 16'd32) && (height == 16'd32)) ||
        ((width == 16'd64) && (height == 16'd64));
    end
  endfunction

  function automatic logic uses_generated_tu_grid(
    input logic [15:0] width,
    input logic [15:0] height
  );
    begin
      uses_generated_tu_grid = (width == 16'd64) && (height == 16'd64);
    end
  endfunction
endmodule
