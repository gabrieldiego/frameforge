`timescale 1ns/1ps

module ff_av2_input_classifier_444 #(
  parameter int SAMPLE_BITS = 8,
  parameter int SUPPORT_PALETTE_444 = 1
) (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       start,
  input  logic       sample_fire,
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,
  input  logic [SAMPLE_BITS - 1:0] sample,
  input  logic       sample_last,
  output logic       done,
  output logic       unsupported,
  output logic       black_mode,
  output logic       luma_palette_bars_mode
);

  logic [31:0] area_q;
  logic [31:0] half_area_q;
  logic [31:0] frame_samples_q;
  logic [31:0] sample_index_q;
  logic black_ok_q;
  logic palette_bars_ok_q;
  logic black_sample_ok_w;
  logic palette_sample_ok_w;
  logic black_next_w;
  logic palette_next_w;
  logic final_sample_w;

  assign final_sample_w = sample_fire && (sample_index_q == (frame_samples_q - 32'd1));
  assign black_sample_ok_w = (sample == {SAMPLE_BITS{1'b0}});
  assign palette_sample_ok_w =
    (SUPPORT_PALETTE_444 != 0) &&
    (SAMPLE_BITS == 8) &&
    (visible_width == 16'd64) &&
    (visible_height == 16'd64) &&
    (
      ((sample_index_q < half_area_q) && (sample == 8'd32)) ||
      ((sample_index_q >= half_area_q) && (sample_index_q < area_q) && (sample == 8'd176)) ||
      ((sample_index_q >= area_q) && (sample == 8'd0))
    );
  assign black_next_w = black_ok_q && black_sample_ok_w;
  assign palette_next_w = palette_bars_ok_q && palette_sample_ok_w;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      area_q <= 32'd0;
      half_area_q <= 32'd0;
      frame_samples_q <= 32'd0;
      sample_index_q <= 32'd0;
      black_ok_q <= 1'b0;
      palette_bars_ok_q <= 1'b0;
      done <= 1'b0;
      unsupported <= 1'b0;
      black_mode <= 1'b0;
      luma_palette_bars_mode <= 1'b0;
    end else if (start) begin
      area_q <= {16'd0, visible_width} * {16'd0, visible_height};
      half_area_q <= ({16'd0, visible_width} * {16'd0, visible_height}) >> 1;
      frame_samples_q <= ({16'd0, visible_width} * {16'd0, visible_height}) * 32'd3;
      sample_index_q <= 32'd0;
      black_ok_q <= 1'b1;
      palette_bars_ok_q <=
        (SUPPORT_PALETTE_444 != 0) &&
        (SAMPLE_BITS == 8) &&
        (visible_width == 16'd64) &&
        (visible_height == 16'd64);
      done <= 1'b0;
      unsupported <= 1'b0;
      black_mode <= 1'b0;
      luma_palette_bars_mode <= 1'b0;
    end else if (sample_fire && !done) begin
      black_ok_q <= black_next_w;
      palette_bars_ok_q <= palette_next_w;
      sample_index_q <= sample_index_q + 32'd1;
      if (final_sample_w) begin
        done <= 1'b1;
        black_mode <= black_next_w;
        luma_palette_bars_mode <= !black_next_w && palette_next_w;
        unsupported <= !(black_next_w || palette_next_w) || !sample_last;
      end else if (sample_last) begin
        done <= 1'b1;
        black_mode <= 1'b0;
        luma_palette_bars_mode <= 1'b0;
        unsupported <= 1'b1;
      end
    end
  end

endmodule
