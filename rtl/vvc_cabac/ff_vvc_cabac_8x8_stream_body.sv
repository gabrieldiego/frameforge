`timescale 1ns/1ps

module ff_vvc_cabac_8x8_stream_body (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       start,
  input  logic       clear,
  input  logic [4:0] luma_rem,
  input  logic [4:0] cb_rem,

  input  logic       m_axis_ready,
  output logic       m_axis_valid,
  output logic [7:0] m_axis_data,
  output logic       m_axis_last,
  output logic [2:0] stream_last_byte_bits,
  output logic       done
);
  logic       symbol_valid;
  logic       symbol_ready;
  logic [2:0] symbol_kind;
  logic       symbol_bin;
  logic [8:0] symbol_lps;
  logic       symbol_mps;
  logic       symbol_last;
  logic       symbol_done;
  logic       writer_done;

  assign done = writer_done;

  ff_vvc_cabac_8x8_symbolizer symbolizer (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .clear(clear),
    .luma_rem(luma_rem),
    .cb_rem(cb_rem),
    .m_axis_valid(symbol_valid),
    .m_axis_ready(symbol_ready),
    .m_axis_kind(symbol_kind),
    .m_axis_bin(symbol_bin),
    .m_axis_lps(symbol_lps),
    .m_axis_mps(symbol_mps),
    .m_axis_last(symbol_last),
    .done(symbol_done)
  );

  ff_vvc_cabac_stream_writer stream_writer (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .clear(clear),
    .s_axis_valid(symbol_valid),
    .s_axis_ready(symbol_ready),
    .s_axis_kind(symbol_kind),
    .s_axis_bin(symbol_bin),
    .s_axis_lps(symbol_lps),
    .s_axis_mps(symbol_mps),
    .s_axis_last(symbol_last),
    .m_axis_ready(m_axis_ready),
    .m_axis_valid(m_axis_valid),
    .m_axis_data(m_axis_data),
    .m_axis_last(m_axis_last),
    .stream_last_byte_bits(stream_last_byte_bits),
    .done(writer_done)
  );
endmodule
