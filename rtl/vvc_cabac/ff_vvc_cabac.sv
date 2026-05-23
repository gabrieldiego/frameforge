`timescale 1ns/1ps

module ff_vvc_cabac #(
  parameter int MAX_VISIBLE_WIDTH = 64,
  parameter int MAX_VISIBLE_HEIGHT = 64,
  parameter int MAX_PALETTE_SYMBOLS = 64,
  parameter int MAX_SLICE_PAYLOAD_BITS = 4096
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
  output logic [12:0] compat_payload_bit_len,

  // Symbol stream boundary for future sequential CABAC. The current clean-room
  // body generators still use the parameter inputs above, but upstream blocks
  // should converge on this symbol-in/byte-out contract.
  input  logic        s_axis_valid,
  output logic        s_axis_ready,
  input  logic [7:0]  s_axis_kind,
  input  logic [31:0] s_axis_data,
  input  logic        s_axis_last,

  // Registered byte stream for the completed CABAC payload.
  input  logic        m_axis_ready,
  output logic        m_axis_valid,
  output logic [7:0]  m_axis_data,
  output logic        m_axis_last,
  output logic [12:0] stream_bit_count,
  output logic [12:0] stream_byte_count,

  // Temporary bridge for the surrounding combinational slice payload packer.
  // The byte stream above is the CABAC block boundary that should remain when
  // this module becomes a sequential symbol-in/byte-out engine.
  output logic [MAX_SLICE_PAYLOAD_BITS - 1:0] compat_payload_bits
);
  localparam logic [1:0] BODY_GENERATED = 2'd0;

  logic generated_supported;
  logic generated_m_axis_valid;
  logic [7:0] generated_m_axis_data;
  logic generated_m_axis_last;
  logic [12:0] generated_stream_bit_count;
  logic [12:0] generated_stream_byte_count;
  logic [12:0] palette_bit_len;
  logic [MAX_SLICE_PAYLOAD_BITS - 1:0] palette_bits;
  logic [MAX_SLICE_PAYLOAD_BITS - 1:0] selected_bits;
  logic [12:0] selected_pad_bits;
  logic [MAX_SLICE_PAYLOAD_BITS - 1:0] stream_bits_q;
  logic [12:0] stream_byte_count_q;
  logic [12:0] stream_byte_index_q;
  logic stream_active_q;
  logic palette_m_axis_valid;
  logic [7:0] palette_m_axis_data;
  logic palette_m_axis_last;
  logic [7:0] symbol_kind_q;
  logic [31:0] symbol_data_q;
  logic symbol_last_q;
  logic palette_s_axis_ready;

  assign s_axis_ready = mode_palette_444 ? palette_s_axis_ready : enable;
  assign stream_bit_count = mode_palette_444 ? palette_bit_len : generated_stream_bit_count;
  assign stream_byte_count = mode_palette_444
    ? (stream_active_q ? stream_byte_count_q : ((palette_bit_len + 13'd7) >> 3))
    : generated_stream_byte_count;
  assign m_axis_valid = mode_palette_444 ? palette_m_axis_valid : generated_m_axis_valid;
  assign m_axis_data = mode_palette_444 ? palette_m_axis_data : generated_m_axis_data;
  assign m_axis_last = mode_palette_444 ? palette_m_axis_last : generated_m_axis_last;

  ff_vvc_generated_cabac_body #(
    .MAX_SLICE_PAYLOAD_BITS(MAX_SLICE_PAYLOAD_BITS)
  ) generated_body (
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
    .MAX_PALETTE_SYMBOLS(MAX_PALETTE_SYMBOLS),
    .MAX_SLICE_PAYLOAD_BITS(MAX_SLICE_PAYLOAD_BITS)
  ) palette_444 (
    .clk(clk),
    .rst_n(rst_n),
    .clear(1'b0),
    .enable(enable && mode_palette_444),
    .coded_width(coded_width),
    .coded_height(coded_height),
    .symbol_count(symbol_count),
    .s_axis_valid(s_axis_valid && mode_palette_444),
    .s_axis_ready(palette_s_axis_ready),
    .s_axis_data(s_axis_data),
    .s_axis_last(s_axis_last),
    .compat_payload_bit_len(palette_bit_len),
    .compat_payload_bits(palette_bits)
  );

  always @* begin
    if (!enable) begin
      supported = 1'b0;
      compat_payload_bit_len = 13'd0;
      compat_payload_bits = '0;
    end else if (mode_palette_444) begin
      supported = 1'b1;
      compat_payload_bit_len = palette_bit_len;
      compat_payload_bits = palette_bits;
    end else begin
      supported = generated_supported;
      compat_payload_bit_len = 13'd0;
      compat_payload_bits = '0;
    end
  end

  always @* begin
    selected_pad_bits = ((((compat_payload_bit_len + 13'd7) >> 3) << 3) - compat_payload_bit_len);
    selected_bits = compat_payload_bits << selected_pad_bits;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      stream_bits_q <= '0;
      stream_byte_count_q <= 13'd0;
      stream_byte_index_q <= 13'd0;
      stream_active_q <= 1'b0;
      palette_m_axis_valid <= 1'b0;
      palette_m_axis_data <= 8'd0;
      palette_m_axis_last <= 1'b0;
    end else begin
      if (start && enable && supported && mode_palette_444) begin
        stream_bits_q <= selected_bits;
        stream_byte_count_q <= (compat_payload_bit_len + 13'd7) >> 3;
        stream_byte_index_q <= 13'd0;
        stream_active_q <= ((compat_payload_bit_len + 13'd7) >> 3) != 13'd0;
        palette_m_axis_valid <= ((compat_payload_bit_len + 13'd7) >> 3) != 13'd0;
        palette_m_axis_data <= stream_byte(selected_bits, (compat_payload_bit_len + 13'd7) >> 3, 13'd0);
        palette_m_axis_last <= ((compat_payload_bit_len + 13'd7) >> 3) == 13'd1;
      end else if (palette_m_axis_valid && m_axis_ready) begin
        if (palette_m_axis_last) begin
          stream_active_q <= 1'b0;
          palette_m_axis_valid <= 1'b0;
          palette_m_axis_data <= 8'd0;
          palette_m_axis_last <= 1'b0;
        end else begin
          stream_byte_index_q <= stream_byte_index_q + 13'd1;
          palette_m_axis_data <= stream_byte(stream_bits_q, stream_byte_count_q, stream_byte_index_q + 13'd1);
          palette_m_axis_last <= (stream_byte_index_q + 13'd1) == (stream_byte_count_q - 13'd1);
        end
      end else if (!stream_active_q) begin
        palette_m_axis_valid <= 1'b0;
        palette_m_axis_last <= 1'b0;
        palette_m_axis_data <= 8'd0;
      end
    end
  end

  function automatic logic [7:0] stream_byte(
    input logic [MAX_SLICE_PAYLOAD_BITS - 1:0] bits,
    input logic [12:0] byte_count,
    input logic [12:0] byte_index
  );
    begin
      if (byte_index < byte_count) begin
        stream_byte = bits >> (((byte_count - 13'd1) - byte_index) * 8);
      end else begin
        stream_byte = 8'd0;
      end
    end
  endfunction

  // Keep the symbol stream visible to lint/simulation until the current
  // parameter-driven generators are replaced by real symbol consumers.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      symbol_kind_q <= 8'd0;
      symbol_data_q <= 32'd0;
      symbol_last_q <= 1'b0;
    end else if (s_axis_valid && s_axis_ready) begin
      symbol_kind_q <= s_axis_kind;
      symbol_data_q <= s_axis_data;
      symbol_last_q <= s_axis_last;
    end
  end

endmodule
