`timescale 1ns/1ps

module ff_av2_encoder #(
  parameter int MAX_VISIBLE_WIDTH = 1024,
  parameter int MAX_VISIBLE_HEIGHT = 1024,
  // TODO(av2): revisit this shared integration name once AV2 block/superblock
  // terminology is finalized in the implementation.
  parameter int CTU_SIZE = 64,
  parameter int SAMPLE_BITS = 8,
  parameter int SOURCE_SAMPLE_BITS = SAMPLE_BITS
) (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       start,
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,
  // Shared chroma format IDs: 1=4:2:0, 2=4:2:2, 3=4:4:4.
  input  logic [1:0] chroma_format_idc,
  output logic       busy,

  input  logic       s_axis_valid,
  output logic       s_axis_ready,
  input  logic [SAMPLE_BITS - 1:0] s_axis_data,
  input  logic       s_axis_last,
  output logic       input_error,

  output logic       m_axis_valid,
  input  logic       m_axis_ready,
  output logic [7:0] m_axis_data,
  output logic       m_axis_last
);

  logic supported_black_geometry_w;
  logic start_invalid_w;

  assign supported_black_geometry_w =
    (visible_width >= 16'd8) &&
    (visible_width <= 16'd64) &&
    (visible_height >= 16'd8) &&
    (visible_height <= 16'd64) &&
    (visible_width[2:0] == 3'd0) &&
    (visible_height[2:0] == 3'd0);

  assign start_invalid_w =
    !supported_black_geometry_w ||
    (visible_width > MAX_VISIBLE_WIDTH) ||
    (visible_height > MAX_VISIBLE_HEIGHT) ||
    (chroma_format_idc != 2'd3);

  // TODO(av2): replace this shell with field-generated AV2 tile entropy
  // syntax. Hard-coded bitstream blobs and traced entropy operation tables are
  // intentionally not allowed here because they block real block/mode logic.
  assign busy = 1'b0;
  assign s_axis_ready = 1'b0;
  assign m_axis_valid = 1'b0;
  assign m_axis_data = 8'd0;
  assign m_axis_last = 1'b0;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      input_error <= 1'b0;
    end else if (start) begin
      input_error <= 1'b1;
    end else begin
      input_error <= 1'b0;
    end
  end

  wire _unused_inputs_w = &{
    1'b0,
    CTU_SIZE[0],
    SOURCE_SAMPLE_BITS[0],
    start_invalid_w,
    s_axis_valid,
    s_axis_data,
    s_axis_last,
    m_axis_ready
  };

endmodule
