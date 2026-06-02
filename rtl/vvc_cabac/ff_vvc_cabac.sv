`timescale 1ns/1ps

module ff_vvc_cabac #(
  parameter int MAX_VISIBLE_WIDTH = 64,
  parameter int MAX_VISIBLE_HEIGHT = 64,
  parameter int VVC_CABAC_CTX_ID_BITS = 10
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        start,
  input  logic        enable,
  input  logic        mode_palette_444,
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,
  input  logic [15:0] coded_width,
  input  logic [15:0] coded_height,
  input  logic [4:0]  luma_rem,
  input  logic [4:0]  cb_rem,
  input  logic [4:0]  cr_rem,

  // Symbol stream boundary for future sequential CABAC. The current clean-room
  // body generators still use the parameter inputs above, but upstream blocks
  // should converge on this symbol-in/byte-out contract.
  input  logic        s_axis_valid,
  output logic        s_axis_ready,
  input  logic [7:0]  s_axis_kind,
  input  logic [31:0] s_axis_data,
  input  logic        s_axis_last,

  // CABAC byte stream.
  input  logic        m_axis_ready,
  output logic        m_axis_valid,
  output logic [7:0]  m_axis_data,
  output logic        m_axis_last,
  output logic [2:0]  stream_last_byte_bits
);
  logic streamed_m_axis_valid;
  logic [7:0] streamed_m_axis_data;
  logic streamed_m_axis_last;
  logic [2:0] streamed_stream_last_byte_bits;
  logic streamed_s_axis_ready;
  logic streamed_done;

  assign s_axis_ready = streamed_s_axis_ready;
  assign stream_last_byte_bits = streamed_stream_last_byte_bits;
  assign m_axis_valid = streamed_m_axis_valid;
  assign m_axis_data = streamed_m_axis_data;
  assign m_axis_last = streamed_m_axis_last;

  ff_vvc_cabac_pipeline #(
    .VVC_CABAC_CTX_ID_BITS(VVC_CABAC_CTX_ID_BITS)
  ) streamed_cabac (
    .clk(clk),
    .rst_n(rst_n),
    .start(start && enable),
    .clear(1'b0),
    .s_axis_valid(s_axis_valid),
    .s_axis_ready(streamed_s_axis_ready),
    .s_axis_kind(s_axis_kind),
    .s_axis_data(s_axis_data),
    .s_axis_last(s_axis_last),
    .m_axis_ready(m_axis_ready),
    .m_axis_valid(streamed_m_axis_valid),
    .m_axis_data(streamed_m_axis_data),
    .m_axis_last(streamed_m_axis_last),
    .stream_last_byte_bits(streamed_stream_last_byte_bits),
    .done(streamed_done)
  );

  logic unused_inputs;
  assign unused_inputs = mode_palette_444 || (|visible_width) || (|visible_height) ||
    (|coded_width) || (|coded_height) || (|luma_rem) || (|cb_rem) || (|cr_rem) || streamed_done;

endmodule
