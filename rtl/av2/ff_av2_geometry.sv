`timescale 1ns/1ps

// AV2 visible-size and tile geometry derivation for the MVP encoder. Keeping
// this arithmetic out of ff_av2_encoder leaves the top focused on module
// orchestration and state sequencing.
module ff_av2_geometry (
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,
  input  logic [15:0] coded_width,
  input  logic [15:0] coded_height,
  input  logic [15:0] tile_col,
  input  logic [15:0] tile_row,

  output logic [4:0]  width_bits,
  output logic [4:0]  height_bits,
  output logic [15:0] tile_cols,
  output logic [15:0] tile_rows,
  output logic [15:0] tile_count,
  output logic [15:0] tile_width,
  output logic [15:0] tile_height,
  output logic [3:0]  tile_width_blocks,
  output logic [3:0]  tile_height_blocks,
  output logic [7:0]  tile_block_count
);
  integer bit_i;

  always @* begin
    width_bits = 5'd3;
    height_bits = 5'd3;
    for (bit_i = 4; bit_i <= 16; bit_i = bit_i + 1) begin
      if (visible_width > (16'd1 << (bit_i - 1))) begin
        width_bits = bit_i[4:0];
      end
      if (visible_height > (16'd1 << (bit_i - 1))) begin
        height_bits = bit_i[4:0];
      end
    end
  end

  assign tile_cols = (visible_width + 16'd63) >> 6;
  assign tile_rows = (visible_height + 16'd63) >> 6;
  assign tile_width =
    (tile_col == (tile_cols - 16'd1)) ?
      (coded_width - (tile_col << 6)) : 16'd64;
  assign tile_height =
    (tile_row == (tile_rows - 16'd1)) ?
      (coded_height - (tile_row << 6)) : 16'd64;
  assign tile_width_blocks = tile_width[6:3];
  assign tile_height_blocks = tile_height[6:3];
  assign tile_block_count =
    (tile_height_blocks[0] ? {4'd0, tile_width_blocks} : 8'd0) +
    (tile_height_blocks[1] ? ({4'd0, tile_width_blocks} << 1) : 8'd0) +
    (tile_height_blocks[2] ? ({4'd0, tile_width_blocks} << 2) : 8'd0) +
    (tile_height_blocks[3] ? ({4'd0, tile_width_blocks} << 3) : 8'd0);
  assign tile_count =
    (tile_rows[0] ? tile_cols : 16'd0) +
    (tile_rows[1] ? (tile_cols << 1) : 16'd0) +
    (tile_rows[2] ? (tile_cols << 2) : 16'd0) +
    (tile_rows[3] ? (tile_cols << 3) : 16'd0) +
    (tile_rows[4] ? (tile_cols << 4) : 16'd0) +
    (tile_rows[5] ? (tile_cols << 5) : 16'd0) +
    (tile_rows[6] ? (tile_cols << 6) : 16'd0) +
    (tile_rows[7] ? (tile_cols << 7) : 16'd0) +
    (tile_rows[8] ? (tile_cols << 8) : 16'd0) +
    (tile_rows[9] ? (tile_cols << 9) : 16'd0);
endmodule
