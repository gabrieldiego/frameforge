`timescale 1ns/1ps

module ff_vvc_cabac #(
  parameter int MAX_VISIBLE_WIDTH = 64,
  parameter int MAX_VISIBLE_HEIGHT = 64,
  parameter int MAX_PALETTE_SYMBOLS = 64
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        start,
  input  logic        enable,
  input  logic        mode_palette_444,
  input  logic [1:0]  body_kind,
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,
  input  logic [15:0] coded_width,
  input  logic [15:0] coded_height,
  input  logic [4:0]  luma_rem,
  input  logic [4:0]  chroma_rem,
  input  logic [7:0]  symbol_count,

  output logic        supported,

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
  output logic [12:0] stream_bit_count,
  output logic [12:0] stream_byte_count
);
  localparam logic [1:0] BODY_GENERATED = 2'd0;

  logic generated_supported;
  logic generated_m_axis_valid;
  logic [7:0] generated_m_axis_data;
  logic generated_m_axis_last;
  logic [12:0] generated_stream_bit_count;
  logic [12:0] generated_stream_byte_count;
  logic palette_m_axis_valid;
  logic [7:0] palette_m_axis_data;
  logic palette_m_axis_last;
  logic [12:0] palette_stream_bit_count;
  logic [12:0] palette_stream_byte_count;
  logic unused_generated_symbol_inputs;
  logic palette_s_axis_ready;

  assign s_axis_ready = mode_palette_444 ? palette_s_axis_ready : enable;
  assign stream_bit_count = mode_palette_444 ? palette_stream_bit_count : generated_stream_bit_count;
  assign stream_byte_count = mode_palette_444 ? palette_stream_byte_count : generated_stream_byte_count;
  assign m_axis_valid = mode_palette_444 ? palette_m_axis_valid : generated_m_axis_valid;
  assign m_axis_data = mode_palette_444 ? palette_m_axis_data : generated_m_axis_data;
  assign m_axis_last = mode_palette_444 ? palette_m_axis_last : generated_m_axis_last;

  ff_vvc_generated_cabac_body generated_body (
    .clk(clk),
    .rst_n(rst_n),
    .start(start && enable && !mode_palette_444),
    .body_kind(body_kind),
    .coded_width(coded_width),
    .coded_height(coded_height),
    .luma_rem(luma_rem),
    .chroma_rem(chroma_rem),
    .supported(generated_supported),
    .m_axis_ready(mode_palette_444 || m_axis_ready),
    .m_axis_valid(generated_m_axis_valid),
    .m_axis_data(generated_m_axis_data),
    .m_axis_last(generated_m_axis_last),
    .stream_bit_count(generated_stream_bit_count),
    .stream_byte_count(generated_stream_byte_count)
  );

  ff_vvc_palette_cabac #(
    .MAX_PALETTE_SYMBOLS(MAX_PALETTE_SYMBOLS)
  ) palette_444 (
    .clk(clk),
    .rst_n(rst_n),
    .start(start && enable && mode_palette_444),
    .clear(1'b0),
    .enable(enable && mode_palette_444),
    .coded_width(coded_width),
    .coded_height(coded_height),
    .symbol_count(symbol_count),
    .s_axis_valid(s_axis_valid && mode_palette_444),
    .s_axis_ready(palette_s_axis_ready),
    .s_axis_data(s_axis_data),
    .s_axis_last(s_axis_last),
    .m_axis_ready(!mode_palette_444 || m_axis_ready),
    .m_axis_valid(palette_m_axis_valid),
    .m_axis_data(palette_m_axis_data),
    .m_axis_last(palette_m_axis_last),
    .stream_bit_count(palette_stream_bit_count),
    .stream_byte_count(palette_stream_byte_count)
  );

  always @* begin
    if (!enable) begin
      supported = 1'b0;
    end else if (mode_palette_444) begin
      supported = 1'b1;
    end else begin
      supported = generated_supported;
    end
  end

  // Generated CABAC is still parameter-driven; keep the symbol-side inputs
  // electrically consumed until that path becomes a real symbol streamer.
  assign unused_generated_symbol_inputs =
    (!mode_palette_444) && s_axis_valid && s_axis_ready &&
    (|s_axis_kind || |s_axis_data || s_axis_last);

endmodule
