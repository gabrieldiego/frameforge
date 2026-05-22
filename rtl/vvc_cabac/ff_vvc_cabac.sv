`timescale 1ns/1ps

module ff_vvc_cabac #(
  parameter int MAX_VISIBLE_WIDTH = 64,
  parameter int MAX_VISIBLE_HEIGHT = 64,
  parameter int MAX_PALETTE_SYMBOLS = 64,
  parameter int MAX_SLICE_PAYLOAD_BITS = 4096
) (
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
  input  logic [(24 * MAX_PALETTE_SYMBOLS) - 1:0] symbol_payload,

  output logic        supported,
  output logic [12:0] payload_bit_len,

  // Streaming view of the completed CABAC payload. The selected sub-blocks are
  // still combinational models; this interface is the stable boundary for
  // replacing them with sequential symbol consumers.
  input  logic        m_axis_ready,
  output logic        m_axis_valid,
  output logic [7:0]  m_axis_data,
  output logic        m_axis_last,
  input  logic [12:0] stream_byte_index,
  output logic [12:0] stream_byte_count,

  // Temporary bridge for the surrounding combinational slice payload packer.
  // The byte stream above is the CABAC block boundary that should remain when
  // this module becomes a sequential symbol-in/byte-out engine.
  output logic [MAX_SLICE_PAYLOAD_BITS - 1:0] compat_payload_bits
);
  localparam logic [1:0] BODY_GENERATED = 2'd0;

  logic generated_supported;
  logic [12:0] generated_bit_len;
  logic [MAX_SLICE_PAYLOAD_BITS - 1:0] generated_bits;
  logic [12:0] palette_bit_len;
  logic [MAX_SLICE_PAYLOAD_BITS - 1:0] palette_bits;
  logic [MAX_SLICE_PAYLOAD_BITS - 1:0] selected_bits;
  logic [12:0] selected_pad_bits;

  ff_vvc_generated_cabac_body #(
    .MAX_SLICE_PAYLOAD_BITS(MAX_SLICE_PAYLOAD_BITS)
  ) generated_body (
    .body_kind(body_kind),
    .coded_width(coded_width),
    .coded_height(coded_height),
    .luma_rem(luma_rem),
    .chroma_rem(chroma_rem),
    .supported(generated_supported),
    .payload_bit_len(generated_bit_len),
    .payload_bits(generated_bits)
  );

  ff_vvc_palette_cabac #(
    .MAX_PALETTE_SYMBOLS(MAX_PALETTE_SYMBOLS),
    .MAX_SLICE_PAYLOAD_BITS(MAX_SLICE_PAYLOAD_BITS)
  ) palette_444 (
    .enable(enable && mode_palette_444),
    .coded_width(coded_width),
    .coded_height(coded_height),
    .symbol_count(symbol_count),
    .symbol_payload(symbol_payload),
    .payload_bit_len(palette_bit_len),
    .payload_bits(palette_bits)
  );

  always @* begin
    if (!enable) begin
      supported = 1'b0;
      payload_bit_len = 13'd0;
      compat_payload_bits = '0;
    end else if (mode_palette_444) begin
      supported = 1'b1;
      payload_bit_len = palette_bit_len;
      compat_payload_bits = palette_bits;
    end else begin
      supported = generated_supported;
      payload_bit_len = generated_bit_len;
      compat_payload_bits = generated_bits;
    end
  end

  always @* begin
    stream_byte_count = (payload_bit_len + 13'd7) >> 3;
    selected_pad_bits = (stream_byte_count << 3) - payload_bit_len;
    selected_bits = compat_payload_bits << selected_pad_bits;
    m_axis_valid = enable && supported && (stream_byte_index < stream_byte_count);
    m_axis_last = m_axis_valid && (stream_byte_index == stream_byte_count - 13'd1);
    if (m_axis_valid && m_axis_ready) begin
      m_axis_data = selected_bits >> (((stream_byte_count - 13'd1) - stream_byte_index) * 8);
    end else begin
      m_axis_data = 8'h00;
    end
  end

endmodule
