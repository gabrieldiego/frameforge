`timescale 1ns/1ps

module ff_vvc_cabac_pipeline (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        start,
  input  logic        clear,

  input  logic        s_axis_valid,
  output logic        s_axis_ready,
  input  logic [7:0]  s_axis_kind,
  input  logic [31:0] s_axis_data,
  input  logic        s_axis_last,

  input  logic        m_axis_ready,
  output logic        m_axis_valid,
  output logic [7:0]  m_axis_data,
  output logic        m_axis_last,
  output logic [2:0]  stream_last_byte_bits,
  output logic        done
);
  logic        bin_valid;
  logic        bin_ready;
  logic [2:0]  bin_kind;
  logic        bin_value;
  logic [31:0] bin_pattern;
  logic [5:0]  bin_count;
  logic        bin_ctx_valid;
  logic [4:0]  bin_ctx_id;
  logic [8:0]  bin_lps;
  logic        bin_mps;
  logic        bin_last;
  logic        syntax_valid;
  logic        syntax_ready;
  logic [7:0]  syntax_kind;
  logic [31:0] syntax_data;
  logic        syntax_last;

  ff_vvc_cabac_syntax_frontend syntax_frontend (
    .clk(clk),
    .rst_n(rst_n),
    .clear(clear || start),
    .raw_symbol_valid(s_axis_valid),
    .raw_symbol_ready(s_axis_ready),
    .raw_symbol_kind(s_axis_kind),
    .raw_symbol_data(s_axis_data),
    .raw_symbol_last(s_axis_last),
    .ctu_valid(1'b0),
    .ctu_ready(),
    .ctu_x(16'd0),
    .ctu_y(16'd0),
    .ctu_visible_width(16'd0),
    .ctu_visible_height(16'd0),
    .ctu_last(1'b0),
    .m_axis_valid(syntax_valid),
    .m_axis_ready(syntax_ready),
    .m_axis_kind(syntax_kind),
    .m_axis_data(syntax_data),
    .m_axis_last(syntax_last)
  );

  ff_vvc_cabac_symbol_binarizer symbol_binarizer (
    .clk(clk),
    .rst_n(rst_n),
    .clear(clear || start),
    .s_axis_valid(syntax_valid),
    .s_axis_ready(syntax_ready),
    .s_axis_kind(syntax_kind),
    .s_axis_data(syntax_data),
    .s_axis_last(syntax_last),
    .m_axis_valid(bin_valid),
    .m_axis_ready(bin_ready),
    .m_axis_kind(bin_kind),
    .m_axis_bin(bin_value),
    .m_axis_bins_pattern(bin_pattern),
    .m_axis_bins_count(bin_count),
    .m_axis_ctx_valid(bin_ctx_valid),
    .m_axis_ctx_id(bin_ctx_id),
    .m_axis_lps(bin_lps),
    .m_axis_mps(bin_mps),
    .m_axis_last(bin_last)
  );

  ff_vvc_cabac_stream_writer stream_writer (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .clear(clear),
    .s_axis_valid(bin_valid),
    .s_axis_ready(bin_ready),
    .s_axis_kind(bin_kind),
    .s_axis_bin(bin_value),
    .s_axis_bins_pattern(bin_pattern),
    .s_axis_bins_count(bin_count),
    .s_axis_ctx_valid(bin_ctx_valid),
    .s_axis_ctx_id(bin_ctx_id),
    .s_axis_lps(bin_lps),
    .s_axis_mps(bin_mps),
    .s_axis_last(bin_last),
    .m_axis_ready(m_axis_ready),
    .m_axis_valid(m_axis_valid),
    .m_axis_data(m_axis_data),
    .m_axis_last(m_axis_last),
    .stream_last_byte_bits(stream_last_byte_bits),
    .done(done)
  );
endmodule
