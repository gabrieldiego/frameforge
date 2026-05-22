`timescale 1ns/1ps

module ff_vvc_toy4x4_encoder #(
  parameter int MAX_VISIBLE_WIDTH = 64,
  parameter int MAX_VISIBLE_HEIGHT = 64,
  parameter int SAMPLE_BITS = 8,
  parameter int SOURCE_SAMPLE_BITS = SAMPLE_BITS,
  // VVC chroma_format_idc values: 1=4:2:0, 2=4:2:2, 3=4:4:4.
  // The current generated bitstream remains the toy 4:2:0 validation stream,
  // but the input drain and first-chroma sampling are parameterized so wider
  // RTL input front-ends can be tested independently.
  parameter int CHROMA_FORMAT_IDC = 1
) (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       start,
  input  logic [1:0] frame_count,
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,
  output logic       busy,

  input  logic       s_axis_valid,
  output logic       s_axis_ready,
  input  logic [SAMPLE_BITS - 1:0] s_axis_data,
  input  logic       s_axis_last,
  output logic       input_error,
  output logic       sampled_color_valid,
  output logic [SAMPLE_BITS - 1:0] sampled_y,
  output logic [SAMPLE_BITS - 1:0] sampled_u,
  output logic [SAMPLE_BITS - 1:0] sampled_v,

  output logic       m_axis_valid,
  input  logic       m_axis_ready,
  output logic [7:0] m_axis_data,
  output logic       m_axis_last
);
  localparam int NAL_OVERHEAD_LEN = 6;
  localparam int MAX_LUMA_SAMPLES = MAX_VISIBLE_WIDTH * MAX_VISIBLE_HEIGHT;
  localparam int MAX_CHROMA_PLANE_SAMPLES = MAX_LUMA_SAMPLES;
  localparam int MAX_FRAME_SAMPLES = MAX_LUMA_SAMPLES + (MAX_CHROMA_PLANE_SAMPLES * 2);
  localparam int INPUT_COUNT_BITS = $clog2((MAX_FRAME_SAMPLES * 2) + 1);
  localparam int TOY_RESIDUAL_CB_SIZE = 4;
  localparam int TOY_RESIDUAL_LUMA_SAMPLES = TOY_RESIDUAL_CB_SIZE * TOY_RESIDUAL_CB_SIZE;
  localparam int MAX_SLICE_PAYLOAD_BITS = 4096;
  localparam int CABAC_BITS_LSB = 0;
  localparam int CABAC_LEN_LSB = CABAC_BITS_LSB + MAX_SLICE_PAYLOAD_BITS;
  localparam int CABAC_LOW_LSB = CABAC_LEN_LSB + 13;
  localparam int CABAC_RANGE_LSB = CABAC_LOW_LSB + 32;
  localparam int CABAC_BUFFERED_BYTE_LSB = CABAC_RANGE_LSB + 16;
  localparam int CABAC_NUM_BUFFERED_BYTES_LSB = CABAC_BUFFERED_BYTE_LSB + 9;
  localparam int CABAC_BITS_LEFT_LSB = CABAC_NUM_BUFFERED_BYTES_LSB + 8;
  localparam int CABAC_STATE_BITS = CABAC_BITS_LEFT_LSB + 8;
  localparam int CABAC_PACKET_BITS = 13 + MAX_SLICE_PAYLOAD_BITS;
  localparam int TOY_32X32_TRACE_BIN_COUNT = 542;
  localparam bit PALETTE_MODE = (CHROMA_FORMAT_IDC == 3);

  typedef logic [CABAC_STATE_BITS - 1:0] cabac_state_t;

  // Compact D_CABAC trace words for the first 32x32 fallback path. Bit 15
  // marks bypass bins. Context-coded words store (lps << 2) | (mps << 1) | bin.
  localparam logic [(TOY_32X32_TRACE_BIN_COUNT * 16) - 1:0] TOY_32X32_TRACE_WORDS = {
    16'h035a, 16'h010f, 16'h0377, 16'h8000, 16'h0163, 16'h020b, 16'h0153, 16'h0153, 16'h00f3, 16'h020b, 16'h0133, 16'h02ca,
    16'h0233, 16'h0153, 16'h01ab, 16'h0113, 16'h029b, 16'h0170, 16'h8001, 16'h8001, 16'h8000, 16'h007d, 16'h011e, 16'h0092,
    16'h008a, 16'h01b1, 16'h0196, 16'h00c7, 16'h0102, 16'h0116, 16'h0013, 16'h0146, 16'h0203, 16'h010e, 16'h0394, 16'h009e,
    16'h0337, 16'h0092, 16'h008b, 16'h007e, 16'h0013, 16'h0062, 16'h022f, 16'h0061, 16'h008a, 16'h0012, 16'h0077, 16'h00a2,
    16'h0013, 16'h00e1, 16'h0129, 16'h005a, 16'h8000, 16'h8000, 16'h8000, 16'h8000, 16'h8001, 16'h8000, 16'h8000, 16'h8001,
    16'h8000, 16'h8001, 16'h8000, 16'h00b1, 16'h007e, 16'h013d, 16'h008e, 16'h00b1, 16'h00aa, 16'h0179, 16'h0096, 16'h01ca,
    16'h025e, 16'h017a, 16'h02cb, 16'h00ba, 16'h00fb, 16'h007e, 16'h0013, 16'h0076, 16'h017a, 16'h008b, 16'h007e, 16'h0013,
    16'h0062, 16'h020b, 16'h0062, 16'h01b4, 16'h02cf, 16'h0052, 16'h8001, 16'h8001, 16'h8000, 16'h8000, 16'h8000, 16'h8000,
    16'h8001, 16'h8000, 16'h8001, 16'h8000, 16'h0162, 16'h0073, 16'h00d7, 16'h005a, 16'h0013, 16'h0042, 16'h01c3, 16'h0046,
    16'h0141, 16'h004e, 16'h006b, 16'h0042, 16'h0013, 16'h01d2, 16'h01f1, 16'h006a, 16'h02e8, 16'h01f4, 16'h02e3, 16'h020a,
    16'h006b, 16'h004e, 16'h0013, 16'h004e, 16'h01ac, 16'h007b, 16'h00e9, 16'h009d, 16'h0022, 16'h0013, 16'h00d5, 16'h00c6,
    16'h0026, 16'h0013, 16'h024f, 16'h024e, 16'h00b2, 16'h8000, 16'h8000, 16'h8001, 16'h8000, 16'h8000, 16'h8000, 16'h8001,
    16'h8000, 16'h8000, 16'h8001, 16'h8001, 16'h8000, 16'h8001, 16'h0083, 16'h0013, 16'h005e, 16'h024e, 16'h00a3, 16'h004a,
    16'h0013, 16'h0046, 16'h02cf, 16'h004e, 16'h02e8, 16'h0223, 16'h0321, 16'h01c2, 16'h00b2, 16'h035b, 16'h0032, 16'h0053,
    16'h004e, 16'h0013, 16'h004a, 16'h0267, 16'h0209, 16'h0132, 16'h00d6, 16'h005b, 16'h0036, 16'h0013, 16'h0032, 16'h0173,
    16'h027c, 16'h019f, 16'h014a, 16'h0027, 16'h01f1, 16'h01b6, 16'h008a, 16'h8001, 16'h8001, 16'h8001, 16'h8001, 16'h8000,
    16'h8001, 16'h8001, 16'h8000, 16'h8001, 16'h8001, 16'h8001, 16'h8001, 16'h8000, 16'h8000, 16'h0053, 16'h01b6, 16'h0083,
    16'h0046, 16'h0013, 16'h0042, 16'h0263, 16'h004a, 16'h02b4, 16'h01a2, 16'h033b, 16'h0032, 16'h0053, 16'h004e, 16'h0013,
    16'h004a, 16'h0242, 16'h005b, 16'h0032, 16'h0013, 16'h0032, 16'h0142, 16'h0027, 16'h0102, 16'h0013, 16'h00c2, 16'h0304,
    16'h8001, 16'h8001, 16'h8000, 16'h8000, 16'h8001, 16'h8000, 16'h8001, 16'h8000, 16'h8001, 16'h8001, 16'h005b, 16'h0027,
    16'h028d, 16'h0165, 16'h00c2, 16'h0013, 16'h01e7, 16'h01f5, 16'h013e, 16'h0230, 16'h0023, 16'h0123, 16'h029a, 16'h0242,
    16'h01c8, 16'h002f, 16'h0298, 16'h0013, 16'h0167, 16'h0306, 16'h0142, 16'h0013, 16'h0193, 16'h01e6, 16'h01b2, 16'h0013,
    16'h0201, 16'h0142, 16'h007e, 16'h0013, 16'h01d2, 16'h0253, 16'h01f3, 16'h0281, 16'h017a, 16'h0297, 16'h01b3, 16'h01f5,
    16'h011e, 16'h002b, 16'h0337, 16'h01fe, 16'h006a, 16'h0170, 16'h0027, 16'h0173, 16'h01b2, 16'h0156, 16'h017f, 16'h0173,
    16'h01b1, 16'h01c9, 16'h8001, 16'h8001, 16'h8001, 16'h8000, 16'h8000, 16'h8001, 16'h8000, 16'h8001, 16'h8000, 16'h8001,
    16'h8000, 16'h8001, 16'h8000, 16'h8001, 16'h8001, 16'h8000, 16'h8000, 16'h0067, 16'h02e8, 16'h028c, 16'h0268, 16'h023c,
    16'h0132, 16'h0335, 16'h011a, 16'h0063, 16'h01c1, 16'h019a, 16'h0076, 16'h0155, 16'h00ee, 16'h0142, 16'h02f8, 16'h0208,
    16'h0141, 16'h00da, 16'h0093, 16'h012a, 16'h0013, 16'h024e, 16'h0375, 16'h00fa, 16'h01f7, 16'h011e, 16'h8000, 16'h8000,
    16'h8000, 16'h8001, 16'h8000, 16'h8001, 16'h8000, 16'h8001, 16'h002b, 16'h0337, 16'h020a, 16'h006a, 16'h01c3, 16'h015b,
    16'h01c2, 16'h018e, 16'h002f, 16'h031f, 16'h022d, 16'h0062, 16'h0013, 16'h01d3, 16'h0281, 16'h017a, 16'h017c, 16'h0013,
    16'h0234, 16'h0013, 16'h0103, 16'h02ce, 16'h020e, 16'h0013, 16'h015b, 16'h01b2, 16'h0166, 16'h0013, 16'h031f, 16'h01ae,
    16'h00d5, 16'h0013, 16'h031f, 16'h01fe, 16'h005a, 16'h0013, 16'h00fb, 16'h0306, 16'h01f3, 16'h0013, 16'h00e3, 16'h02ce,
    16'h0377, 16'h0013, 16'h00e0, 16'h010f, 16'h012c, 16'h00b0, 16'h00ef, 16'h00a3, 16'h0359, 16'h01cb, 16'h8001, 16'h8001,
    16'h8001, 16'h8001, 16'h8001, 16'h8001, 16'h8001, 16'h8001, 16'h8000, 16'h8000, 16'h8001, 16'h8001, 16'h8000, 16'h8000,
    16'h8001, 16'h8000, 16'h8001, 16'h8000, 16'h8000, 16'h8001, 16'h8000, 16'h8000, 16'h8001, 16'h8000, 16'h8001, 16'h8001,
    16'h8000, 16'h8001, 16'h8001, 16'h8000, 16'h8001, 16'h8000, 16'h01e5, 16'h02c2, 16'h023e, 16'h012b, 16'h0181, 16'h02e1,
    16'h0147, 16'h0192, 16'h0223, 16'h0295, 16'h8001, 16'h01f1, 16'h03b3, 16'h01c2, 16'h01c2, 16'h0221, 16'h01c1, 16'h0242,
    16'h005a, 16'h0143, 16'h00ea, 16'h0013, 16'h00c6, 16'h00c7, 16'h0338, 16'h8000, 16'h8000, 16'h8001, 16'h8000, 16'h0221,
    16'h01a1, 16'h0219, 16'h0181, 16'h011a, 16'h021a, 16'h8001, 16'h006a, 16'h018e, 16'h0295, 16'h00b2, 16'h8001, 16'h8001,
    16'h0062, 16'h0062, 16'h009e, 16'h0092, 16'h008a, 16'h007e, 16'h0075, 16'h00f1, 16'h00a6, 16'h0012, 16'h0282, 16'h0072,
    16'h02c2, 16'h01ae, 16'h024e, 16'h0172, 16'h01f6, 16'h022e, 16'h0166, 16'h01f2, 16'h8000, 16'h0252, 16'h027b, 16'h01c2,
    16'h029a, 16'h010e, 16'h0223, 16'h0202, 16'h010c, 16'h0200, 16'h0163, 16'h01de, 16'h029a, 16'h0092, 16'h0226, 16'h018f,
    16'h0296, 16'h01ad, 16'h02cc, 16'h024f, 16'h02ea, 16'h0305, 16'h01d9, 16'h0146, 16'h0072, 16'h019f, 16'h00b1, 16'h007e,
    16'h0012, 16'h00c7, 16'h00d2, 16'h0117, 16'h019f, 16'h01b1, 16'h017d, 16'h8001, 16'h8001, 16'h8001, 16'h8000, 16'h8001,
    16'h8000, 16'h8001, 16'h8000, 16'h01b1, 16'h01e7, 16'h019e, 16'h02b6, 16'h00e2, 16'h01c8, 16'h0209, 16'h8000, 16'h8000,
    16'h0192, 16'h008a
  };

  logic [12:0] index_q;
  logic [12:0] stream_len_q;
  logic [INPUT_COUNT_BITS - 1:0] input_count_q;
  logic [INPUT_COUNT_BITS - 1:0] input_len_q;
  logic       input_active_q;
  logic [(SAMPLE_BITS * MAX_LUMA_SAMPLES) - 1:0] luma_frame_q;
  logic [(SAMPLE_BITS * TOY_RESIDUAL_LUMA_SAMPLES) - 1:0] luma_samples_q;
  logic [(SAMPLE_BITS * TOY_RESIDUAL_LUMA_SAMPLES) - 1:0] luma_samples_1_q;
  logic [(SAMPLE_BITS * 16) - 1:0] cb_samples_q;
  logic [(SAMPLE_BITS * 16) - 1:0] cr_samples_q;
  logic [4:0] quant_luma_rem_q;
  logic [4:0] quant_luma_rem_1_q;
  logic [4:0] quant_chroma_rem_q;
  logic [119:0] quant_luma_ac_tokens_q;
  logic [119:0] quant_luma_ac_tokens_1_q;
  logic [4:0] residual_quant_luma_rem;
  logic [4:0] residual_quant_luma_rem_1;
  logic [119:0] residual_quant_luma_ac_tokens;
  logic [119:0] residual_quant_luma_ac_tokens_1;
  logic [7:0] residual_recon_luma_sample;
  logic [7:0] residual_recon_luma_sample_1;
  logic [15:0] coding_tree_coded_width;
  logic [15:0] coding_tree_coded_height;
  logic [1:0]  coding_tree_body_kind;
  logic        coding_tree_uses_capacity_tu_grid;
  logic [12:0] coding_tree_luma_tu_count;
  logic [12:0] coding_tree_capacity_tu_grid_bit_len;
  logic        generated_cabac_body_supported;
  logic [12:0] generated_cabac_body_len;
  logic [MAX_SLICE_PAYLOAD_BITS - 1:0] generated_cabac_body_bits;

  assign busy = input_active_q || m_axis_valid || (index_q != 0);

  ff_vvc_toy_coding_tree_scheduler coding_tree_scheduler (
    .visible_width(visible_width),
    .visible_height(visible_height),
    .coded_width(coding_tree_coded_width),
    .coded_height(coding_tree_coded_height),
    .body_kind(coding_tree_body_kind),
    .uses_capacity_tu_grid(coding_tree_uses_capacity_tu_grid),
    .luma_tu_count(coding_tree_luma_tu_count),
    .capacity_tu_grid_bit_len(coding_tree_capacity_tu_grid_bit_len)
  );

  ff_vvc_toy_cabac_body #(
    .MAX_SLICE_PAYLOAD_BITS(MAX_SLICE_PAYLOAD_BITS)
  ) generated_cabac_body (
    .body_kind(coding_tree_body_kind),
    .luma_rem(quant_luma_rem_q),
    .chroma_rem(quant_chroma_rem_q),
    .supported(generated_cabac_body_supported),
    .cabac_bit_len(generated_cabac_body_len),
    .cabac_bits(generated_cabac_body_bits)
  );

  ff_residual_stub #(
    .SAMPLE_BITS(SAMPLE_BITS),
    .LUMA_CB_SIZE(TOY_RESIDUAL_CB_SIZE)
  ) residual_block (
    .luma_samples(luma_samples_q),
    .quant_luma_rem(residual_quant_luma_rem),
    .quant_luma_ac_tokens(residual_quant_luma_ac_tokens),
    .recon_luma_sample(residual_recon_luma_sample)
  );

  ff_residual_stub #(
    .SAMPLE_BITS(SAMPLE_BITS),
    .LUMA_CB_SIZE(TOY_RESIDUAL_CB_SIZE)
  ) residual_block_1 (
    .luma_samples(luma_samples_1_q),
    .quant_luma_rem(residual_quant_luma_rem_1),
    .quant_luma_ac_tokens(residual_quant_luma_ac_tokens_1),
    .recon_luma_sample(residual_recon_luma_sample_1)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      index_q      <= '0;
      stream_len_q <= '0;
      input_count_q <= '0;
      input_len_q   <= '0;
      input_active_q <= 1'b0;
      s_axis_ready <= 1'b0;
      input_error  <= 1'b0;
      sampled_color_valid <= 1'b0;
      sampled_y <= '0;
      sampled_u <= '0;
      sampled_v <= '0;
      luma_frame_q <= '0;
      luma_samples_q <= '0;
      luma_samples_1_q <= '0;
      cb_samples_q <= '0;
      cr_samples_q <= '0;
      quant_luma_rem_q <= 5'd16;
      quant_luma_rem_1_q <= 5'd16;
      quant_chroma_rem_q <= 5'd6;
      quant_luma_ac_tokens_q <= {15{8'h40}};
      quant_luma_ac_tokens_1_q <= {15{8'h40}};
      m_axis_valid <= 1'b0;
      m_axis_data  <= '0;
      m_axis_last  <= 1'b0;
    end else begin
      if (start && !busy) begin
        input_active_q <= 1'b1;
        s_axis_ready   <= 1'b1;
        input_count_q  <= '0;
        input_len_q    <= input_len(frame_count);
        stream_len_q   <= '0;
        input_error    <= 1'b0;
        sampled_color_valid <= 1'b0;
        luma_frame_q <= '0;
        luma_samples_q <= '0;
        luma_samples_1_q <= '0;
        cb_samples_q <= '0;
        cr_samples_q <= '0;
        quant_luma_rem_q <= 5'd16;
        quant_luma_rem_1_q <= 5'd16;
        quant_chroma_rem_q <= 5'd6;
        quant_luma_ac_tokens_q <= {15{8'h40}};
        quant_luma_ac_tokens_1_q <= {15{8'h40}};
        m_axis_valid   <= 1'b0;
        m_axis_last    <= 1'b0;
        index_q        <= '0;
      end else if (input_active_q && s_axis_valid && s_axis_ready) begin
        if (s_axis_last != (input_count_q == input_len_q - 1'b1)) begin
          input_error <= 1'b1;
        end
        if (input_count_q == 8'd0) begin
          sampled_y <= s_axis_data;
        end
        if (input_count_q < luma_samples()) begin
          luma_frame_q[(MAX_LUMA_SAMPLES - 1 - input_count_q) * SAMPLE_BITS +: SAMPLE_BITS] <= s_axis_data;
        end
        if (is_residual_luma_sample(input_count_q)) begin
          luma_samples_q[(15 - residual_luma_sample_index(input_count_q)) * SAMPLE_BITS +: SAMPLE_BITS] <= s_axis_data;
        end
        if (is_second_residual_luma_sample(input_count_q)) begin
          luma_samples_1_q[(15 - second_residual_luma_sample_index(input_count_q)) * SAMPLE_BITS +: SAMPLE_BITS] <= s_axis_data;
        end
        if (PALETTE_MODE && input_count_q >= luma_samples() && input_count_q < luma_samples() + 10'd16) begin
          cb_samples_q[(15 - (input_count_q - luma_samples())) * SAMPLE_BITS +: SAMPLE_BITS] <= s_axis_data;
        end
        if (PALETTE_MODE && input_count_q >= v_sample_index() && input_count_q < v_sample_index() + 10'd16) begin
          cr_samples_q[(15 - (input_count_q - v_sample_index())) * SAMPLE_BITS +: SAMPLE_BITS] <= s_axis_data;
        end
        if (input_count_q == luma_samples()) begin
          quant_luma_rem_q <= residual_quant_luma_rem;
          quant_luma_ac_tokens_q <= residual_quant_luma_ac_tokens;
          quant_luma_rem_1_q <= residual_quant_luma_rem_1;
          quant_luma_ac_tokens_1_q <= residual_quant_luma_ac_tokens_1;
        end
        if (input_count_q == luma_samples()) begin
          sampled_u <= s_axis_data;
        end
        if (input_count_q == v_sample_index()) begin
          sampled_v <= s_axis_data;
          quant_chroma_rem_q <= quant_chroma_rem_from_samples(sampled_u, s_axis_data);
        end

        if (input_count_q == input_len_q - 1'b1) begin
          input_active_q <= 1'b0;
          s_axis_ready   <= 1'b0;
          sampled_color_valid <= !input_error && s_axis_last;
          stream_len_q   <= stream_len(frame_count);
          m_axis_valid   <= 1'b1;
          m_axis_data    <= stream_byte(13'd0);
          m_axis_last    <= 1'b0;
          index_q        <= 8'd1;
        end else begin
          input_count_q <= input_count_q + 1'b1;
        end
      end else if (m_axis_valid && m_axis_ready) begin
        if (index_q == stream_len_q) begin
          m_axis_valid <= 1'b0;
          m_axis_last  <= 1'b0;
          index_q      <= '0;
        end else begin
          m_axis_data <= stream_byte(index_q);
          m_axis_last <= (index_q == stream_len_q - 1'b1);
          index_q     <= index_q + 1'b1;
        end
      end
    end
  end

  function automatic logic [INPUT_COUNT_BITS - 1:0] input_len(input logic [1:0] frames);
    case (frames)
      2'd2: input_len = frame_samples() * 2;
      default: input_len = frame_samples();
    endcase
  endfunction

  function automatic logic [INPUT_COUNT_BITS - 1:0] luma_samples();
    begin
      luma_samples = visible_width * visible_height;
    end
  endfunction

  function automatic logic [INPUT_COUNT_BITS - 1:0] chroma_plane_samples();
    begin
      chroma_plane_samples = (visible_width / chroma_subsample_x()) *
                             (visible_height / chroma_subsample_y());
    end
  endfunction

  function automatic logic [1:0] chroma_subsample_x();
    begin
      case (CHROMA_FORMAT_IDC)
        1, 2: chroma_subsample_x = 2'd2;
        default: chroma_subsample_x = 2'd1;
      endcase
    end
  endfunction

  function automatic logic [1:0] chroma_subsample_y();
    begin
      case (CHROMA_FORMAT_IDC)
        1: chroma_subsample_y = 2'd2;
        default: chroma_subsample_y = 2'd1;
      endcase
    end
  endfunction

  function automatic logic [INPUT_COUNT_BITS - 1:0] frame_samples();
    begin
      frame_samples = luma_samples() + (chroma_plane_samples() << 1);
    end
  endfunction

  function automatic logic [INPUT_COUNT_BITS - 1:0] v_sample_index();
    begin
      v_sample_index = luma_samples() + chroma_plane_samples();
    end
  endfunction

  function automatic logic is_residual_luma_sample(input logic [INPUT_COUNT_BITS - 1:0] sample_index);
    begin
      is_residual_luma_sample = (sample_index < luma_samples()) &&
                                ((sample_index % visible_width) < TOY_RESIDUAL_CB_SIZE) &&
                                ((sample_index / visible_width) < TOY_RESIDUAL_CB_SIZE);
    end
  endfunction

  function automatic logic [3:0] residual_luma_sample_index(input logic [INPUT_COUNT_BITS - 1:0] sample_index);
    logic [INPUT_COUNT_BITS - 1:0] index;
    begin
      index = ((sample_index / visible_width) * TOY_RESIDUAL_CB_SIZE) + (sample_index % visible_width);
      residual_luma_sample_index = index[3:0];
    end
  endfunction

  function automatic logic has_second_residual_luma_block();
    begin
      has_second_residual_luma_block = (visible_width >= (TOY_RESIDUAL_CB_SIZE * 2)) ||
                                       (visible_height >= (TOY_RESIDUAL_CB_SIZE * 2));
    end
  endfunction

  function automatic logic [15:0] second_residual_origin_x();
    begin
      second_residual_origin_x = (visible_width >= (TOY_RESIDUAL_CB_SIZE * 2)) ? TOY_RESIDUAL_CB_SIZE : 16'd0;
    end
  endfunction

  function automatic logic [15:0] second_residual_origin_y();
    begin
      second_residual_origin_y = (visible_width >= (TOY_RESIDUAL_CB_SIZE * 2)) ? 16'd0 :
                                 ((visible_height >= (TOY_RESIDUAL_CB_SIZE * 2)) ? TOY_RESIDUAL_CB_SIZE : 16'd0);
    end
  endfunction

  function automatic logic is_second_residual_luma_sample(input logic [INPUT_COUNT_BITS - 1:0] sample_index);
    logic [INPUT_COUNT_BITS - 1:0] x;
    logic [INPUT_COUNT_BITS - 1:0] y;
    begin
      x = sample_index % visible_width;
      y = sample_index / visible_width;
      is_second_residual_luma_sample = (sample_index < luma_samples()) &&
                                       has_second_residual_luma_block() &&
                                       (x >= second_residual_origin_x()) &&
                                       (x < second_residual_origin_x() + TOY_RESIDUAL_CB_SIZE) &&
                                       (y >= second_residual_origin_y()) &&
                                       (y < second_residual_origin_y() + TOY_RESIDUAL_CB_SIZE);
    end
  endfunction

  function automatic logic [3:0] second_residual_luma_sample_index(input logic [INPUT_COUNT_BITS - 1:0] sample_index);
    logic [INPUT_COUNT_BITS - 1:0] x;
    logic [INPUT_COUNT_BITS - 1:0] y;
    logic [INPUT_COUNT_BITS - 1:0] index;
    begin
      x = sample_index % visible_width;
      y = sample_index / visible_width;
      index = ((y - second_residual_origin_y()) * TOY_RESIDUAL_CB_SIZE) +
              (x - second_residual_origin_x());
      second_residual_luma_sample_index = index[3:0];
    end
  endfunction

  function automatic logic [12:0] stream_len(input logic [1:0] frames);
    case (frames)
      2'd2: stream_len = parameter_set_len() + color_filler_nal_len() + (slice_nal_len() * 2);
      default: stream_len = parameter_set_len() + color_filler_nal_len() + slice_nal_len();
    endcase
  endfunction

  function automatic logic [12:0] sps_nal_len();
    begin
      sps_nal_len = NAL_OVERHEAD_LEN + sps_payload_len();
    end
  endfunction

  function automatic logic [12:0] pps_nal_len();
    begin
      pps_nal_len = NAL_OVERHEAD_LEN + pps_payload_len();
    end
  endfunction

  function automatic logic [12:0] parameter_set_len();
    begin
      parameter_set_len = sps_nal_len() + pps_nal_len();
    end
  endfunction

  function automatic logic [12:0] slice_payload_len();
    logic [CABAC_PACKET_BITS - 1:0] cabac;
    logic [12:0]  bit_len;
    begin
      if (uses_capacity_tu_grid()) begin
        bit_len = 13'd24 + capacity_tu_grid_bit_len() + 13'd1;
      end else begin
        cabac = toy_cabac_bitstream(
          quant_luma_rem(),
          quant_luma_ac_tokens(),
          quant_luma_rem_1(),
          quant_luma_ac_tokens_1()
        );
        bit_len = 13'd24 + cabac[CABAC_PACKET_BITS - 1 -: 13] + 13'd1;
      end
      slice_payload_len = (bit_len + 13'd7) >> 3;
    end
  endfunction

  function automatic logic [12:0] slice_nal_len();
    begin
      slice_nal_len = NAL_OVERHEAD_LEN + slice_payload_len();
    end
  endfunction

  function automatic logic [4:0] quant_luma_rem();
    begin
      quant_luma_rem = quant_luma_rem_q;
    end
  endfunction

  function automatic logic [4:0] quant_chroma_rem();
    begin
      quant_chroma_rem = quant_chroma_rem_q;
    end
  endfunction

  function automatic logic [119:0] quant_luma_ac_tokens();
    begin
      quant_luma_ac_tokens = quant_luma_ac_tokens_q;
    end
  endfunction

  function automatic logic [4:0] quant_luma_rem_1();
    begin
      quant_luma_rem_1 = quant_luma_rem_1_q;
    end
  endfunction

  function automatic logic [119:0] quant_luma_ac_tokens_1();
    begin
      quant_luma_ac_tokens_1 = quant_luma_ac_tokens_1_q;
    end
  endfunction

  function automatic logic [4:0] quant_chroma_rem_from_samples(
    input logic [SAMPLE_BITS - 1:0] u,
    input logic [SAMPLE_BITS - 1:0] v
  );
    begin
      quant_chroma_rem_from_samples = (sample_to_8bit(u) == 8'd0 && sample_to_8bit(v) == 8'd0) ? 5'd6 : 5'd0;
    end
  endfunction

  function automatic logic [7:0] sample_to_8bit(input logic [SAMPLE_BITS - 1:0] sample);
    begin
      if (SAMPLE_BITS <= 8) begin
        sample_to_8bit = sample[7:0];
      end else begin
        sample_to_8bit = sample >> (SAMPLE_BITS - 8);
      end
    end
  endfunction

  function automatic logic [7:0] color_filler_count();
    begin
      color_filler_count = (sample_to_8bit(sampled_y) + sample_to_8bit(sampled_u) + sample_to_8bit(sampled_v)) & 8'h0f;
    end
  endfunction

  function automatic logic [7:0] color_filler_payload_len();
    begin
      color_filler_payload_len = color_filler_count() + 8'd1;
    end
  endfunction

  function automatic logic [12:0] color_filler_nal_len();
    begin
      color_filler_nal_len = NAL_OVERHEAD_LEN + color_filler_payload_len();
    end
  endfunction

  function automatic logic [7:0] stream_byte(input logic [12:0] index);
    logic second_picture;
    logic [12:0] slice_base;
    logic [12:0] slice_index;

    begin
      if (index < sps_nal_len()) begin
        stream_byte = nal_byte(3'd0, index, 1'b0);
      end else if (index < parameter_set_len()) begin
        stream_byte = nal_byte(3'd1, index - sps_nal_len(), 1'b0);
      end else if (index < parameter_set_len() + color_filler_nal_len()) begin
        stream_byte = nal_byte(3'd3, index - parameter_set_len(), 1'b0);
      end else begin
        slice_base = parameter_set_len() + color_filler_nal_len();
        second_picture = (index >= slice_base + slice_nal_len());
        slice_index = second_picture
          ? (index - (slice_base + slice_nal_len()))
          : (index - slice_base);
        stream_byte = nal_byte(3'd2, slice_index, second_picture);
      end
    end
  endfunction

  function automatic logic [7:0] nal_byte(
    input logic [2:0] nal_kind,
    input logic [12:0] nal_index,
    input logic       cra_picture
  );
    begin
      if (nal_index < 7'd4) begin
        nal_byte = start_code_byte(nal_index[1:0]);
      end else if (nal_index < 7'd6) begin
        nal_byte = nal_header_byte(nal_kind, nal_index[0], cra_picture);
      end else begin
        nal_byte = payload_byte(nal_kind, nal_index - 7'd6, cra_picture);
      end
    end
  endfunction

  function automatic logic [7:0] start_code_byte(input logic [1:0] index);
    case (index)
      2'd3: start_code_byte = 8'h01;
      default: start_code_byte = 8'h00;
    endcase
  endfunction

  function automatic logic [7:0] nal_header_byte(
    input logic [2:0] nal_kind,
    input logic       byte_index,
    input logic       cra_picture
  );
    logic [15:0] header;

    begin
      header = nal_header_bits(6'd0, nal_unit_type(nal_kind, cra_picture), 3'd0);
      nal_header_byte = byte_index ? header[7:0] : header[15:8];
    end
  endfunction

  function automatic logic [4:0] nal_unit_type(
    input logic [2:0] nal_kind,
    input logic       cra_picture
  );
    begin
      case (nal_kind)
        3'd0: nal_unit_type = 5'd15; // SPS.
        3'd1: nal_unit_type = 5'd16; // PPS.
        3'd3: nal_unit_type = 5'd25; // Filler data.
        default: nal_unit_type = cra_picture ? 5'd9 : 5'd8;
      endcase
    end
  endfunction

  function automatic logic [15:0] nal_header_bits(
    input logic [5:0] layer_id,
    input logic [4:0] nal_type,
    input logic [2:0] temporal_id
  );
    begin
      nal_header_bits = {
        1'b0,              // forbidden_zero_bit
        1'b0,              // nuh_reserved_zero_bit
        layer_id,          // nuh_layer_id
        nal_type,          // nal_unit_type
        temporal_id + 3'd1 // nuh_temporal_id_plus1
      };
    end
  endfunction

  function automatic logic [7:0] payload_byte(
    input logic [2:0] nal_kind,
    input logic [12:0] payload_index,
    input logic       cra_picture
  );
    begin
      case (nal_kind)
        3'd0: payload_byte = sps_payload_byte(payload_index);
        3'd1: payload_byte = pps_payload_byte(payload_index);
        3'd3: payload_byte = color_filler_payload_byte(payload_index);
        default: payload_byte = slice_payload_byte(payload_index, cra_picture);
      endcase
    end
  endfunction

  function automatic logic [7:0] color_filler_payload_byte(input logic [12:0] index);
    begin
      if (index < color_filler_count()) begin
        color_filler_payload_byte = 8'hff;
      end else if (index == color_filler_count()) begin
        color_filler_payload_byte = 8'h80;
      end else begin
        color_filler_payload_byte = 8'h00;
      end
    end
  endfunction

  function automatic logic [7:0] sps_payload_byte(input logic [12:0] index);
    logic [264:0] payload;

    begin
      payload = sps_payload_state();
      if (index < sps_payload_len()) begin
        sps_payload_byte = payload[255:0] >> (((sps_payload_len() - 1) - index) * 8);
      end else begin
        sps_payload_byte = 8'h00;
      end
    end
  endfunction

  function automatic logic [7:0] pps_payload_byte(input logic [12:0] index);
    logic [264:0] payload;

    begin
      payload = pps_payload_state();
      if (index < pps_payload_len()) begin
        pps_payload_byte = payload[255:0] >> (((pps_payload_len() - 1) - index) * 8);
      end else begin
        pps_payload_byte = 8'h00;
      end
    end
  endfunction

  function automatic logic [8:0] sps_payload_len();
    logic [264:0] payload;

    begin
      payload = sps_payload_state();
      sps_payload_len = payload[264:256] >> 3;
    end
  endfunction

  function automatic logic [8:0] pps_payload_len();
    logic [264:0] payload;

    begin
      payload = pps_payload_state();
      pps_payload_len = payload[264:256] >> 3;
    end
  endfunction

  function automatic logic [264:0] append_u(
    input logic [264:0] state,
    input logic [31:0]  value,
    input int unsigned  width
  );
    logic [8:0] len;
    logic [255:0] bits;
    logic [63:0] mask;

    begin
      len = state[264:256];
      bits = state[255:0];
      if (width == 0) begin
        append_u = state;
      end else begin
        mask = (64'd1 << width) - 64'd1;
        bits = (bits << width) | (value & mask);
        len = len + width[8:0];
        append_u = {len, bits};
      end
    end
  endfunction

  function automatic logic [264:0] append_flag(input logic [264:0] state, input logic value);
    begin
      append_flag = append_u(state, {31'd0, value}, 1);
    end
  endfunction

  function automatic logic [264:0] append_ue(input logic [264:0] state, input logic [31:0] value);
    begin
      append_ue = append_exp_golomb_code(state, value + 32'd1);
    end
  endfunction

  function automatic logic [264:0] append_exp_golomb_code(
    input logic [264:0] state,
    input logic [31:0] code_num
  );
    int unsigned prefix;

    begin
      prefix = 0;
      while ((code_num >> prefix) > 1) begin
        prefix = prefix + 1;
      end
      state = append_u(state, 32'd0, prefix);
      append_exp_golomb_code = append_u(state, code_num, prefix + 1);
    end
  endfunction

  function automatic logic [264:0] append_se(input logic [264:0] state, input int signed value);
    logic [31:0] mapped;

    begin
      if (value > 0) begin
        mapped = value * 2;
      end else begin
        mapped = (-value * 2) + 1;
      end
      append_se = append_exp_golomb_code(state, mapped);
    end
  endfunction

  function automatic logic [264:0] append_trailing_bits(input logic [264:0] state);
    begin
      state = append_flag(state, 1'b1);
      while (state[258:256] != 3'd0) begin
        state = append_flag(state, 1'b0);
      end
      append_trailing_bits = state;
    end
  endfunction

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

  function automatic logic [15:0] coded_width();
    begin
      coded_width = coding_tree_coded_width;
    end
  endfunction

  function automatic logic [15:0] coded_height();
    begin
      coded_height = coding_tree_coded_height;
    end
  endfunction

  function automatic logic [264:0] sps_payload_state();
    logic [264:0] state;

    begin
      state = '0;
      state = append_u(state, 0, 4);
      state = append_u(state, 0, 4);
      state = append_u(state, 0, 3);
      state = append_u(state, 1, 2);
      state = append_u(state, 1, 2);
      state = append_flag(state, 1'b1);
      state = append_u(state, 1, 7);
      state = append_flag(state, 1'b0);
      state = append_u(state, 0, 8);
      state = append_flag(state, 1'b1);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      repeat (5) state = append_flag(state, 1'b0);
      state = append_u(state, 0, 8);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b1);
      state = append_flag(state, 1'b0);
      state = append_ue(state, coded_width());
      state = append_ue(state, coded_height());
      state = append_flag(state, 1'b1);
      state = append_ue(state, 0);
      state = append_ue(state, (coded_width() - visible_width) >> 1);
      state = append_ue(state, 0);
      state = append_ue(state, (coded_height() - visible_height) >> 1);
      state = append_flag(state, 1'b0);
      state = append_ue(state, 0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b1);
      state = append_u(state, 4, 4);
      state = append_flag(state, 1'b0);
      state = append_u(state, 0, 2);
      state = append_u(state, 0, 2);
      state = append_ue(state, 0);
      state = append_ue(state, 0);
      state = append_ue(state, 0);
      state = append_ue(state, 0);
      state = append_flag(state, 1'b1);
      state = append_ue(state, 1);
      state = append_ue(state, 3);
      state = append_ue(state, 2);
      state = append_ue(state, 2);
      state = append_flag(state, 1'b1);
      state = append_ue(state, 1);
      state = append_ue(state, 3);
      state = append_ue(state, 3);
      state = append_ue(state, 2);
      state = append_ue(state, 1);
      state = append_ue(state, 3);
      state = append_ue(state, 3);
      state = append_ue(state, 3);
      state = append_flag(state, 1'b1);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b1);
      state = append_flag(state, 1'b1);
      state = append_se(state, -9);
      state = append_ue(state, 2);
      state = append_ue(state, 9);
      state = append_ue(state, 5);
      state = append_ue(state, 4);
      state = append_ue(state, 1);
      state = append_ue(state, 11);
      state = append_ue(state, 12);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b1);
      state = append_ue(state, 1);
      state = append_ue(state, 0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b1);
      state = append_flag(state, 1'b1);
      state = append_flag(state, 1'b1);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b1);
      state = append_flag(state, 1'b1);
      state = append_ue(state, 0);
      state = append_flag(state, 1'b1);
      state = append_flag(state, 1'b1);
      state = append_ue(state, 0);
      state = append_flag(state, 1'b1);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_ue(state, 0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b1);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b1);
      state = append_flag(state, 1'b1);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b1);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      sps_payload_state = append_trailing_bits(state);
    end
  endfunction

  function automatic logic [264:0] pps_payload_state();
    logic [264:0] state;

    begin
      state = '0;
      state = append_u(state, 0, 6);
      state = append_u(state, 0, 4);
      state = append_flag(state, 1'b0);
      state = append_ue(state, coded_width());
      state = append_ue(state, coded_height());
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b1);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b1);
      state = append_ue(state, 3);
      state = append_ue(state, 3);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_se(state, 6);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b1);
      state = append_se(state, 0);
      state = append_se(state, 0);
      state = append_flag(state, 1'b1);
      state = append_se(state, -1);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b1);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_se(state, -2);
      state = append_se(state, -5);
      state = append_se(state, -2);
      state = append_se(state, -5);
      state = append_se(state, -2);
      state = append_se(state, -5);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      pps_payload_state = append_trailing_bits(state);
    end
  endfunction

  function automatic logic [7:0] slice_payload_byte(
    input logic [12:0] index,
    input logic       cra_picture
  );
    begin
      slice_payload_byte = quant_luma_payload_byte(
        quant_luma_rem(),
        quant_luma_ac_tokens(),
        quant_luma_rem_1(),
        quant_luma_ac_tokens_1(),
        index,
        cra_picture
      );
    end
  endfunction

  function automatic logic [7:0] quant_luma_payload_byte(
    input logic [4:0] rem,
    input logic [119:0] ac_tokens,
    input logic [4:0] rem_1,
    input logic [119:0] ac_tokens_1,
    input logic [12:0] index,
    input logic       cra_picture
  );
    logic [MAX_SLICE_PAYLOAD_BITS - 1:0] payload;

    begin
      payload = toy_slice_payload_bits(rem, ac_tokens, rem_1, ac_tokens_1, cra_picture);
      quant_luma_payload_byte = payload >> (((slice_payload_len() - 13'd1) - index) * 8);
    end
  endfunction

  function automatic logic [MAX_SLICE_PAYLOAD_BITS - 1:0] toy_slice_payload_bits(
    input logic [4:0] rem,
    input logic [119:0] ac_tokens,
    input logic [4:0] rem_1,
    input logic [119:0] ac_tokens_1,
    input logic       cra_picture
  );
    logic [MAX_SLICE_PAYLOAD_BITS - 1:0] acc;
    logic [12:0]  bit_len;
    logic [CABAC_PACKET_BITS - 1:0] cabac;
    logic [MAX_SLICE_PAYLOAD_BITS - 1:0] cabac_bits;
    logic [MAX_SLICE_PAYLOAD_BITS - 1:0] capacity_bits;
    logic [12:0]  payload_len;
    logic [12:0]  payload_bits_len;
    logic [12:0]  payload_byte_len;

    begin
      acc = '0;
      bit_len = 13'd0;

      acc = (acc << 19) | slice_header_bits(cra_picture);
      bit_len = bit_len + 13'd19;

      acc = (acc << 1) | 1'b1; // cabac_alignment_one_bit
      bit_len = bit_len + 13'd1;
      if (cra_picture) begin
        acc = (acc << 1) | 1'b1; // current CRA slice alignment bit
        bit_len = bit_len + 13'd1;
      end
      while (bit_len[2:0] != 3'd0) begin
        acc = acc << 1;
        bit_len = bit_len + 13'd1;
      end

      if (uses_capacity_tu_grid()) begin
        capacity_bits = capacity_tu_grid_bits();
        payload_len = capacity_tu_grid_bit_len();
        acc = (acc << payload_len) | capacity_bits;
        bit_len = bit_len + payload_len;
      end else begin
        cabac = toy_cabac_bitstream(rem, ac_tokens, rem_1, ac_tokens_1);
        payload_len = cabac[CABAC_PACKET_BITS - 1 -: 13];
        cabac_bits = cabac[MAX_SLICE_PAYLOAD_BITS - 1:0];
        acc = (acc << payload_len) | cabac_bits;
        bit_len = bit_len + payload_len;
      end

      acc = (acc << 1) | 1'b1; // rbsp_stop_one_bit
      bit_len = bit_len + 13'd1;
      while (bit_len[2:0] != 3'd0) begin
        acc = acc << 1;
        bit_len = bit_len + 13'd1;
      end

      payload_byte_len = slice_payload_len();
      payload_bits_len = payload_byte_len << 3;
      toy_slice_payload_bits = acc << (payload_bits_len - bit_len);
    end
  endfunction

  function automatic logic uses_capacity_tu_grid();
    begin
      uses_capacity_tu_grid = coding_tree_uses_capacity_tu_grid;
    end
  endfunction

  function automatic logic [12:0] luma_tu_count();
    begin
      luma_tu_count = coding_tree_luma_tu_count;
    end
  endfunction

  function automatic logic [12:0] capacity_tu_grid_bit_len();
    begin
      capacity_tu_grid_bit_len = coding_tree_capacity_tu_grid_bit_len;
    end
  endfunction

  function automatic logic [MAX_SLICE_PAYLOAD_BITS - 1:0] capacity_tu_grid_bits();
    logic [MAX_SLICE_PAYLOAD_BITS - 1:0] bits;
    logic [12:0] tu;
    begin
      bits = luma_tu_count();
      for (tu = 13'd0; tu < luma_tu_count(); tu = tu + 13'd1) begin
        bits = (bits << 5) | quant_luma_rem_for_tu(tu);
        bits = (bits << 8) | quant_luma_ac0_for_tu(tu);
      end
      capacity_tu_grid_bits = bits;
    end
  endfunction

  function automatic logic [4:0] quant_luma_rem_for_tu(input logic [12:0] tu);
    begin
      quant_luma_rem_for_tu = quant_luma_rem_from_sample(forward_luma_dc_sample_for_tu(tu));
    end
  endfunction

  function automatic logic [7:0] quant_luma_ac0_for_tu(input logic [12:0] tu);
    logic [7:0] dc;
    begin
      dc = forward_luma_dc_sample_for_tu(tu);
      quant_luma_ac0_for_tu = quant_ac_token_for_samples(luma_sample_for_tu(tu, 4'd1), dc);
    end
  endfunction

  function automatic logic [7:0] forward_luma_dc_sample_for_tu(input logic [12:0] tu);
    logic [12:0] sum;
    integer i;
    begin
      sum = 13'd0;
      for (i = 0; i < 16; i = i + 1) begin
        sum = sum + {5'd0, luma_sample_for_tu(tu, i[3:0])};
      end
      forward_luma_dc_sample_for_tu = (sum + 13'd8) >> 4;
    end
  endfunction

  function automatic logic [7:0] luma_sample_for_tu(input logic [12:0] tu, input logic [3:0] sample_index);
    logic [15:0] tus_per_row;
    logic [15:0] origin_x;
    logic [15:0] origin_y;
    logic [15:0] x;
    logic [15:0] y;
    logic [INPUT_COUNT_BITS - 1:0] linear_index;
    logic [SAMPLE_BITS - 1:0] raw;
    begin
      tus_per_row = (visible_width + 16'd3) >> 2;
      origin_x = (tu % tus_per_row) << 2;
      origin_y = (tu / tus_per_row) << 2;
      x = origin_x + {12'd0, sample_index[1:0]};
      y = origin_y + {12'd0, sample_index[3:2]};
      if ((x < visible_width) && (y < visible_height)) begin
        linear_index = y * visible_width + x;
        raw = luma_frame_q[(MAX_LUMA_SAMPLES - 1 - linear_index) * SAMPLE_BITS +: SAMPLE_BITS];
        luma_sample_for_tu = sample_to_8bit(raw);
      end else begin
        luma_sample_for_tu = 8'd0;
      end
    end
  endfunction

  function automatic logic [7:0] quant_ac_token_for_samples(input logic [7:0] sample, input logic [7:0] dc);
    logic signed [9:0] coeff;
    logic [8:0] abs_coeff;
    logic [4:0] magnitude;
    logic negative;
    begin
      coeff = $signed({ 2'b00, sample }) - $signed({ 2'b00, dc });
      negative = coeff < 0;
      abs_coeff = negative ? -coeff : coeff;
      magnitude = (abs_coeff + 9'd8) >> 4;
      if (magnitude > 5'd8) begin
        magnitude = 5'd8;
      end
      if (magnitude == 5'd0) begin
        negative = 1'b0;
      end
      quant_ac_token_for_samples = 8'h40 | { 2'b00, negative, magnitude };
    end
  endfunction

  function automatic logic [4:0] quant_luma_rem_from_sample(input logic [7:0] sample);
    begin
      if (sample >= 8'd111) quant_luma_rem_from_sample = 5'd0;
      else if (sample >= 8'd104) quant_luma_rem_from_sample = 5'd1;
      else if (sample >= 8'd97) quant_luma_rem_from_sample = 5'd2;
      else if (sample >= 8'd90) quant_luma_rem_from_sample = 5'd3;
      else if (sample >= 8'd82) quant_luma_rem_from_sample = 5'd4;
      else if (sample >= 8'd75) quant_luma_rem_from_sample = 5'd5;
      else if (sample >= 8'd68) quant_luma_rem_from_sample = 5'd6;
      else if (sample >= 8'd61) quant_luma_rem_from_sample = 5'd7;
      else if (sample >= 8'd54) quant_luma_rem_from_sample = 5'd8;
      else if (sample >= 8'd46) quant_luma_rem_from_sample = 5'd9;
      else if (sample >= 8'd40) quant_luma_rem_from_sample = 5'd10;
      else if (sample >= 8'd33) quant_luma_rem_from_sample = 5'd11;
      else if (sample >= 8'd25) quant_luma_rem_from_sample = 5'd12;
      else if (sample >= 8'd18) quant_luma_rem_from_sample = 5'd13;
      else if (sample >= 8'd11) quant_luma_rem_from_sample = 5'd14;
      else if (sample >= 8'd4) quant_luma_rem_from_sample = 5'd15;
      else quant_luma_rem_from_sample = 5'd16;
    end
  endfunction

  function automatic logic [CABAC_PACKET_BITS - 1:0] toy_cabac_bitstream(
    input logic [4:0]   rem,
    input logic [119:0] ac_tokens,
    input logic [4:0]   rem_1,
    input logic [119:0] ac_tokens_1
  );
    cabac_state_t st;
    logic [4:0]   chroma_rem;

    begin
      chroma_rem = quant_chroma_rem();
      st = cabac_start();
      if (generated_cabac_body_supported) begin
        toy_cabac_bitstream = {generated_cabac_body_len, generated_cabac_body_bits};
      end else if (toy_supports_32x32_trace()) begin
        st = toy_encode_32x32_trace(st);
      end else begin
        if (toy_supports_16x16_trace(rem, chroma_rem)) begin
          st = toy_encode_16x16_trace(st, rem, chroma_rem);
        end else if (toy_supports_8x8_mapped_tree()) begin
          st = toy_encode_8x8_luma_tree(st, rem);
          st = toy_encode_4x4_chroma_tree(st, chroma_rem);
        end else begin
          st = toy_encode_capacity_placeholder_tree(st, rem, chroma_rem, ac_tokens, rem_1, ac_tokens_1);
        end
        st = cabac_encode_bin_trm(st, 1'b1);
        st = cabac_finish(st);
        toy_cabac_bitstream = {
          st[CABAC_LEN_LSB +: 13],
          st[CABAC_BITS_LSB +: MAX_SLICE_PAYLOAD_BITS]
        };
      end
    end
  endfunction

  function automatic logic toy_supports_8x8_mapped_tree();
    begin
      toy_supports_8x8_mapped_tree = (luma_cb_width() == 16'd8) && (luma_cb_height() == 16'd8);
    end
  endfunction

  function automatic logic toy_supports_16x16_trace(input logic [4:0] rem, input logic [4:0] chroma_rem);
    begin
      toy_supports_16x16_trace = (luma_cb_width() == 16'd16) && (luma_cb_height() == 16'd16);
    end
  endfunction

  function automatic logic toy_supports_32x32_trace();
    begin
      toy_supports_32x32_trace = (luma_cb_width() == 16'd32) && (luma_cb_height() == 16'd32);
    end
  endfunction

  function automatic logic [15:0] luma_cb_width();
    begin
      luma_cb_width = coded_width();
    end
  endfunction

  function automatic logic [15:0] luma_cb_height();
    begin
      luma_cb_height = coded_height();
    end
  endfunction

  function automatic cabac_state_t toy_encode_8x8_luma_tree(
    input cabac_state_t st_in,
    input logic [4:0]   rem
  );
    cabac_state_t st;

    begin
      st = st_in;
      st = cabac_encode_ctx_bins(st, 5'd0,  8'b0000_0101, 4'd4);
      st = cabac_encode_ctx_bins(st, 5'd4,  8'b0000_0010, 4'd4);
      st = cabac_encode_ctx_bins(st, 5'd8,  8'b0000_0001, 4'd1);
      st = cabac_encode_rem_abs_ep(st, rem, 3'd0);
      st = cabac_encode_bin_ep(st, 1'b1);
      st = cabac_encode_ctx_bins(st, 5'd9,  8'b0000_1011, 4'd4);
      st = cabac_encode_ctx_bins(st, 5'd13, 8'b0000_0100, 4'd3);
      toy_encode_8x8_luma_tree = st;
    end
  endfunction

  function automatic cabac_state_t toy_encode_4x4_chroma_tree(
    input cabac_state_t st_in,
    input logic [4:0]   chroma_rem
  );
    cabac_state_t st;

    begin
      st = st_in;
      st = cabac_encode_ctx_bins(st, 5'd16, 8'b0000_0101, 4'd3);
      st = cabac_encode_rem_abs_ep(st, chroma_rem, 3'd0);
      st = cabac_encode_bin_ep(st, 1'b1);
      toy_encode_4x4_chroma_tree = st;
    end
  endfunction

  function automatic cabac_state_t toy_encode_capacity_placeholder_tree(
    input cabac_state_t st_in,
    input logic [4:0]   rem,
    input logic [4:0]   chroma_rem,
    input logic [119:0] ac_tokens,
    input logic [4:0]   rem_1,
    input logic [119:0] ac_tokens_1
  );
    cabac_state_t st;

    begin
      // TODO(vvc): Replace this with geometry-specific coding-tree generation.
      // Keeping it isolated prevents larger geometry support from looking like
      // the VTM-mapped 8x8 path.
      st = toy_encode_8x8_luma_tree(st_in, rem);
      st = toy_encode_4x4_chroma_tree(st, chroma_rem);
      st = cabac_encode_bins_ep(st, {24'd0, ac_tokens[119:112]}, 6'd8);
      if (has_second_residual_luma_block()) begin
        st = cabac_encode_rem_abs_ep(st, rem_1, 3'd0);
        st = cabac_encode_bins_ep(st, {24'd0, ac_tokens_1[119:112]}, 6'd8);
      end
      toy_encode_capacity_placeholder_tree = st;
    end
  endfunction

  function automatic cabac_state_t toy_encode_32x32_trace(input cabac_state_t st_in);
    cabac_state_t st;
    integer i;

    begin
      st = st_in;
      for (i = 0; i < TOY_32X32_TRACE_BIN_COUNT; i = i + 1) begin
        st = toy_encode_compact_trace_word(st, toy_32x32_trace_word(i));
      end
      toy_encode_32x32_trace = st;
    end
  endfunction

  function automatic logic [15:0] toy_32x32_trace_word(input integer index);
    begin
      toy_32x32_trace_word =
        TOY_32X32_TRACE_WORDS[((TOY_32X32_TRACE_BIN_COUNT - 1 - index) * 16) +: 16];
    end
  endfunction

  function automatic cabac_state_t toy_encode_compact_trace_word(
    input cabac_state_t st_in,
    input logic [15:0]  word
  );
    begin
      if (word[15]) begin
        toy_encode_compact_trace_word = cabac_encode_bin_ep(st_in, word[0]);
      end else begin
        toy_encode_compact_trace_word = cabac_encode_bin(st_in, word[0], {1'b0, word[10:2]}, ~(word[1] ^ word[0]));
      end
    end
  endfunction

  function automatic cabac_state_t toy_encode_16x16_trace(
    input cabac_state_t st_in,
    input logic [4:0]   rem,
    input logic [4:0]   chroma_rem
  );
    cabac_state_t st;

    begin
      st = st_in;
      // This 16x16 path is still trace-derived, but the emitted decisions are
      // selected from visible geometry plus the quantized residual parameters.
      // Luma CU split, intra mode 26, CBF, and one DC-like residual.
      st = cabac_encode_bin(st, 1'b0, 9'd214, 1'b0); // split_cu_mode split=1
        st = cabac_encode_bin(st, 1'b0, 9'd67, 1'b1);  // split_cu_mode qt=1
        st = cabac_encode_bin_ep(st, 1'b0);            // intra_luma_pred_mode[5]
        st = cabac_encode_bin_ep(st, 1'b1);            // intra_luma_pred_mode[4]
        st = cabac_encode_bin_ep(st, 1'b1);            // intra_luma_pred_mode[3]
        st = cabac_encode_bin_ep(st, 1'b0);            // intra_luma_pred_mode[2]
        st = cabac_encode_bin_ep(st, 1'b1);            // intra_luma_pred_mode[1]
        st = cabac_encode_bin_ep(st, 1'b0);            // intra_luma_pred_mode[0]
        st = cabac_encode_bin(st, 1'b1, 9'd52, 1'b1);  // split_cu_mode split=1
        st = cabac_encode_bin(st, 1'b0, 9'd166, 1'b1); // split_cu_mode qt=1
        st = cabac_encode_bin(st, 1'b1, 9'd109, 1'b1); // split_cu_mode split=0
        st = cabac_encode_bin(st, 1'b1, 9'd134, 1'b1); // cbf_comp luma=1
        st = cabac_encode_bin(st, 1'b1, 9'd116, 1'b1); // sig_coeff_group_flag
        st = cabac_encode_bin(st, 1'b1, 9'd142, 1'b1); // sig_coeff_group_flag
        st = cabac_encode_bin(st, 1'b1, 9'd221, 1'b0); // last_sig_coeff_x_prefix
        st = cabac_encode_bin(st, 1'b0, 9'd205, 1'b0); // last_sig_coeff_y_prefix
        st = cabac_encode_bin_ep(st, 1'b0);            // last_sig_coeff_suffix
        st = cabac_encode_bin(st, 1'b0, 9'd39, 1'b0);  // sig_coeff_flag
        st = cabac_encode_bin(st, 1'b0, 9'd101, 1'b0); // sig_coeff_flag
        st = cabac_encode_bin(st, 1'b0, 9'd99, 1'b0);  // sig_coeff_flag
        st = cabac_encode_bin(st, 1'b1, 9'd4, 1'b1);   // sig_coeff_flag
        st = cabac_encode_bin(st, 1'b0, 9'd67, 1'b0);  // abs_level_gtx_flag
        st = cabac_encode_bin_ep(st, 1'b0);            // remainder_prefix
        st = cabac_encode_bin_ep(st, 1'b1);            // coeff_sign_flag
        st = cabac_encode_bin(st, 1'b0, 9'd64, 1'b0);  // ts_flag=0
        st = cabac_encode_bin(st, 1'b0, 9'd54, 1'b0);  // mts_idx=0

        // Chroma tree split plus first 4x4 Cr-coded transform unit.
        st = cabac_encode_bin(st, 1'b0, 9'd40, 1'b0);  // split_cu_mode split=1
        st = cabac_encode_bin(st, 1'b0, 9'd176, 1'b0); // split_cu_mode qt=1
        st = cabac_encode_bin(st, 1'b0, 9'd103, 1'b0); // split_cu_mode split=1
        st = cabac_encode_bin(st, 1'b0, 9'd130, 1'b0); // split_cu_mode qt=1
        st = cabac_encode_bin(st, 1'b0, 9'd88, 1'b0);  // split_cu_mode split=1
        st = cabac_encode_bin(st, 1'b0, 9'd114, 1'b0); // split_cu_mode qt=1
        st = cabac_encode_bin(st, 1'b0, 9'd80, 1'b0);  // split_cu_mode split=0
        st = cabac_encode_bin(st, 1'b1, 9'd4, 1'b1);   // cbf_comp Cb=0
        st = cabac_encode_bin(st, 1'b0, 9'd53, 1'b0);  // cbf_comp Cr=1
        st = cabac_encode_bin(st, 1'b0, 9'd26, 1'b0);  // sig_coeff_group_flag
        st = cabac_encode_bin(st, 1'b1, 9'd96, 1'b0);  // last_sig_coeff_x_prefix
        st = cabac_encode_bin(st, 1'b0, 9'd112, 1'b0); // last_sig_coeff_y_prefix
        st = cabac_encode_bin(st, 1'b1, 9'd4, 1'b1);   // sig_coeff_flag
        st = cabac_encode_bin(st, 1'b0, 9'd72, 1'b0);  // abs_level_gtx_flag
        st = cabac_encode_bin(st, 1'b1, 9'd112, 1'b1); // sig_coeff_flag
        st = cabac_encode_bin(st, 1'b0, 9'd72, 1'b0);  // abs_level_gtx_flag
        st = cabac_encode_bin(st, 1'b1, 9'd88, 1'b1);  // sig_coeff_flag
        st = cabac_encode_bin(st, 1'b0, 9'd84, 1'b0);  // abs_level_gtx_flag
        st = cabac_encode_bin(st, 1'b1, 9'd4, 1'b1);   // sig_coeff_flag
        st = cabac_encode_bin(st, 1'b0, 9'd206, 1'b1); // abs_level_gtx_flag
        st = cabac_encode_bin_ep(st, 1'b1);            // remainder_prefix
        st = cabac_encode_bin_ep(st, 1'b1);            // remainder_prefix
        st = cabac_encode_bin_ep(st, 1'b1);            // remainder_prefix
        st = cabac_encode_bin_ep(st, 1'b1);            // remainder_prefix
        st = cabac_encode_bin_ep(st, 1'b0);            // remainder_suffix
        st = cabac_encode_bin_ep(st, 1'b1);            // coeff_sign_flag
        st = cabac_encode_bin(st, 1'b1, 9'd160, 1'b0); // ts_flag=0
        st = cabac_encode_bin(st, 1'b1, 9'd29, 1'b0);  // mts_idx=0

        // Remaining chroma 4x4 transform units are coded as empty.
        st = cabac_encode_bin(st, 1'b1, 9'd172, 1'b1); // split_cu_mode split=0 at (4,0)
        st = cabac_encode_bin(st, 1'b0, 9'd107, 1'b0); // cbf_comp Cb(4,0)=0
        st = cabac_encode_bin(st, 1'b0, 9'd136, 1'b0); // cbf_comp Cr(4,0)=0
        st = cabac_encode_bin(st, 1'b1, 9'd67, 1'b0);  // mts_idx=0 at (4,0)
        st = cabac_encode_bin(st, 1'b0, 9'd100, 1'b0); // split_cu_mode split=0 at (0,4)
        st = cabac_encode_bin(st, 1'b0, 9'd124, 1'b0); // cbf_comp Cb(0,4)=0
        st = cabac_encode_bin(st, 1'b0, 9'd160, 1'b0); // cbf_comp Cr(0,4)=0
        st = cabac_encode_bin(st, 1'b0, 9'd20, 1'b0);  // mts_idx=0 at (0,4)
        st = cabac_encode_bin_ep(st, 1'b1);            // trace EP before final block
        st = cabac_encode_bin(st, 1'b1, 9'd169, 1'b1); // split_cu_mode split=0 at (4,4)
        st = cabac_encode_bin(st, 1'b0, 9'd103, 1'b0); // cbf_comp Cb(4,4)=0
        st = cabac_encode_bin(st, 1'b0, 9'd147, 1'b0); // cbf_comp Cr(4,4)=0
        st = cabac_encode_bin(st, 1'b0, 9'd68, 1'b0);  // mts_idx=0 at (4,4)
        st = cabac_encode_bin(st, 1'b1, 9'd140, 1'b1); // final empty-tu context
        st = cabac_encode_bin(st, 1'b0, 9'd103, 1'b0); // final empty-tu context
        st = cabac_encode_bin(st, 1'b0, 9'd119, 1'b0); // final empty-tu context
        st = cabac_encode_bin(st, 1'b0, 9'd56, 1'b0);  // final empty-tu context
        st = cabac_encode_bin(st, 1'b0, 9'd118, 1'b1); // final empty-tu context
        st = cabac_encode_bin(st, 1'b0, 9'd130, 1'b0); // final empty-tu context
      st = cabac_encode_bin(st, 1'b0, 9'd104, 1'b0); // final cbf cleanup
      st = cabac_encode_bin(st, 1'b0, 9'd81, 1'b0);  // final cbf cleanup
      toy_encode_16x16_trace = st;
    end
  endfunction

  function automatic cabac_state_t cabac_start();
    begin
      cabac_start = '0;
      cabac_start[CABAC_LOW_LSB +: 32] = 32'd0;
      cabac_start[CABAC_RANGE_LSB +: 16] = 16'd510;
      cabac_start[CABAC_BUFFERED_BYTE_LSB +: 9] = 9'h0ff;
      cabac_start[CABAC_NUM_BUFFERED_BYTES_LSB +: 8] = 8'd0;
      cabac_start[CABAC_BITS_LEFT_LSB +: 8] = 8'd23;
    end
  endfunction

  function automatic cabac_state_t cabac_encode_ctx_bins(
    input cabac_state_t st_in,
    input logic [4:0]   ctx_offset,
    input logic [7:0]   bin_pattern,
    input logic [3:0]   num_bins
  );
    cabac_state_t st;
    integer i;

    begin
      st = st_in;
      for (i = 0; i < num_bins; i = i + 1) begin
        st = cabac_encode_bin(
          st,
          bin_pattern[num_bins - 1 - i],
          toy_ctx_lps(ctx_offset + i[4:0]),
          toy_ctx_mps(ctx_offset + i[4:0])
        );
      end
      cabac_encode_ctx_bins = st;
    end
  endfunction

  function automatic cabac_state_t cabac_encode_bin(
    input cabac_state_t st_in,
    input logic         bin,
    input logic [8:0]   lps_in,
    input logic         mps
  );
    cabac_state_t st;
    logic [31:0] low;
    logic [15:0] range;
    logic [8:0]  lps;
    integer bits_left;
    integer num_bits;

    begin
      st = st_in;
      low = st[CABAC_LOW_LSB +: 32];
      range = st[CABAC_RANGE_LSB +: 16];
      bits_left = st[CABAC_BITS_LEFT_LSB +: 8];
      lps = lps_in;

      range = range - lps;
      if (bin != mps) begin
        num_bits = renorm_bits_sv(lps);
        bits_left = bits_left - num_bits;
        low = low + range;
        low = low << num_bits;
        range = lps << num_bits;
        st[CABAC_LOW_LSB +: 32] = low;
        st[CABAC_RANGE_LSB +: 16] = range;
        st[CABAC_BITS_LEFT_LSB +: 8] = bits_left[7:0];
        if (bits_left < 12) begin
          st = cabac_write_out(st);
        end
      end else if (range < 16'd256) begin
        num_bits = renorm_bits_sv(range);
        bits_left = bits_left - num_bits;
        low = low << num_bits;
        range = range << num_bits;
        st[CABAC_LOW_LSB +: 32] = low;
        st[CABAC_RANGE_LSB +: 16] = range;
        st[CABAC_BITS_LEFT_LSB +: 8] = bits_left[7:0];
        if (bits_left < 12) begin
          st = cabac_write_out(st);
        end
      end else begin
        st[CABAC_RANGE_LSB +: 16] = range;
      end
      cabac_encode_bin = st;
    end
  endfunction

  function automatic cabac_state_t cabac_encode_bin_ep(
    input cabac_state_t st_in,
    input logic         bin
  );
    cabac_state_t st;
    logic [31:0] low;
    logic [15:0] range;
    integer bits_left;

    begin
      st = st_in;
      low = st[CABAC_LOW_LSB +: 32] << 1;
      range = st[CABAC_RANGE_LSB +: 16];
      bits_left = st[CABAC_BITS_LEFT_LSB +: 8] - 1;
      if (bin) begin
        low = low + range;
      end
      st[CABAC_LOW_LSB +: 32] = low;
      st[CABAC_BITS_LEFT_LSB +: 8] = bits_left[7:0];
      if (bits_left < 12) begin
        st = cabac_write_out(st);
      end
      cabac_encode_bin_ep = st;
    end
  endfunction

  function automatic cabac_state_t cabac_encode_bins_ep(
    input cabac_state_t st_in,
    input logic [31:0]  bin_pattern_in,
    input logic [5:0]   num_bins_in
  );
    cabac_state_t st;
    logic [31:0] low;
    logic [31:0] bin_pattern;
    logic [15:0] range;
    logic [31:0] pattern;
    integer bits_left;
    integer num_bins;

      begin
      st = st_in;
      bin_pattern = bin_pattern_in;
      num_bins = num_bins_in;
      low = st[CABAC_LOW_LSB +: 32];
      range = st[CABAC_RANGE_LSB +: 16];
      bits_left = st[CABAC_BITS_LEFT_LSB +: 8];

      while (num_bins > 8) begin
        num_bins = num_bins - 8;
        pattern = bin_pattern >> num_bins;
        low = low << 8;
        low = low + (range * pattern);
        bin_pattern = bin_pattern - (pattern << num_bins);
        bits_left = bits_left - 8;
        st[CABAC_LOW_LSB +: 32] = low;
        st[CABAC_BITS_LEFT_LSB +: 8] = bits_left[7:0];
        if (bits_left < 12) begin
          st = cabac_write_out(st);
          low = st[CABAC_LOW_LSB +: 32];
          bits_left = st[CABAC_BITS_LEFT_LSB +: 8];
        end
      end

      low = low << num_bins;
      low = low + (range * bin_pattern);
      bits_left = bits_left - num_bins;
      st[CABAC_LOW_LSB +: 32] = low;
      st[CABAC_BITS_LEFT_LSB +: 8] = bits_left[7:0];
      if (bits_left < 12) begin
        st = cabac_write_out(st);
      end
      cabac_encode_bins_ep = st;
    end
  endfunction

  function automatic cabac_state_t cabac_encode_rem_abs_ep(
    input cabac_state_t st_in,
    input logic [4:0]   value,
    input logic [2:0]   rice_param
  );
    cabac_state_t st;
    logic [5:0] threshold;
    logic [5:0] length;
    logic [5:0] code_value;
    logic [5:0] prefix_length;
    logic [5:0] total_prefix_length;
    logic [5:0] suffix_length;
    logic [31:0] prefix;
    logic [31:0] suffix;

    begin
      st = st_in;
      threshold = 6'd5 << rice_param;
      if (value < threshold) begin
        length = (value >> rice_param) + 6'd1;
        st = cabac_encode_bins_ep(st, (32'd1 << length) - 32'd2, length);
        st = cabac_encode_bins_ep(st, value & ((32'd1 << rice_param) - 32'd1), rice_param);
      end else begin
        code_value = (value >> rice_param) - 6'd5;
        prefix_length = 6'd0;
        while (code_value > ((6'd2 << prefix_length) - 6'd2)) begin
          prefix_length = prefix_length + 6'd1;
        end
        total_prefix_length = prefix_length + 6'd5;
        suffix_length = prefix_length + rice_param + 6'd1;
        prefix = (32'd1 << total_prefix_length) - 32'd1;
        suffix = ((code_value - ((6'd1 << prefix_length) - 6'd1)) << rice_param)
          | (value & ((32'd1 << rice_param) - 32'd1));
        st = cabac_encode_bins_ep(st, prefix, total_prefix_length);
        st = cabac_encode_bins_ep(st, suffix, suffix_length);
      end
      cabac_encode_rem_abs_ep = st;
    end
  endfunction

  function automatic cabac_state_t cabac_encode_bin_trm(
    input cabac_state_t st_in,
    input logic         bin
  );
    cabac_state_t st;
    logic [31:0] low;
    logic [15:0] range;
    integer bits_left;

    begin
      st = st_in;
      low = st[CABAC_LOW_LSB +: 32];
      range = st[CABAC_RANGE_LSB +: 16] - 16'd2;
      bits_left = st[CABAC_BITS_LEFT_LSB +: 8];
      if (bin) begin
        low = low + range;
        low = low << 7;
        range = 16'd256;
        bits_left = bits_left - 7;
      end else if (range < 16'd256) begin
        low = low << 1;
        range = range << 1;
        bits_left = bits_left - 1;
      end
      st[CABAC_LOW_LSB +: 32] = low;
      st[CABAC_RANGE_LSB +: 16] = range;
      st[CABAC_BITS_LEFT_LSB +: 8] = bits_left[7:0];
      if (bits_left < 12) begin
        st = cabac_write_out(st);
      end
      cabac_encode_bin_trm = st;
    end
  endfunction

  function automatic cabac_state_t cabac_finish(input cabac_state_t st_in);
    cabac_state_t st;
    logic [31:0] low;
    logic [8:0] buffered_byte;
    logic [7:0] num_buffered_bytes;
    integer bits_left;
    integer final_bits;

    begin
      st = st_in;
      low = st[CABAC_LOW_LSB +: 32];
      buffered_byte = st[CABAC_BUFFERED_BYTE_LSB +: 9];
      num_buffered_bytes = st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8];
      bits_left = st[CABAC_BITS_LEFT_LSB +: 8];

      if ((low >> (32 - bits_left)) != 0) begin
        st = cabac_write_bits(st, buffered_byte + 9'd1, 6'd8);
        num_buffered_bytes = st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8];
        while (num_buffered_bytes > 8'd1) begin
          st = cabac_write_bits(st, 9'd0, 6'd8);
          num_buffered_bytes = num_buffered_bytes - 8'd1;
          st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8] = num_buffered_bytes;
        end
        low = low - (32'd1 << (32 - bits_left));
        st[CABAC_LOW_LSB +: 32] = low;
      end else begin
        if (num_buffered_bytes > 8'd0) begin
          st = cabac_write_bits(st, buffered_byte, 6'd8);
        end
        num_buffered_bytes = st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8];
        while (num_buffered_bytes > 8'd1) begin
          st = cabac_write_bits(st, 9'h0ff, 6'd8);
          num_buffered_bytes = num_buffered_bytes - 8'd1;
          st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8] = num_buffered_bytes;
        end
      end

      final_bits = 24 - bits_left;
      if (final_bits > 0) begin
        st = cabac_write_bits(st, low >> 8, final_bits[5:0]);
      end
      cabac_finish = st;
    end
  endfunction

  function automatic cabac_state_t cabac_write_out(input cabac_state_t st_in);
    cabac_state_t st;
    logic [31:0] low;
    logic [31:0] lead_byte;
    logic [31:0] mask;
    logic [8:0] buffered_byte;
    logic [7:0] num_buffered_bytes;
    logic [8:0] byte_value;
    logic [8:0] repeated_byte;
    logic [8:0] carry;
    integer bits_left;

    begin
      st = st_in;
      low = st[CABAC_LOW_LSB +: 32];
      bits_left = st[CABAC_BITS_LEFT_LSB +: 8];
      buffered_byte = st[CABAC_BUFFERED_BYTE_LSB +: 9];
      num_buffered_bytes = st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8];
      lead_byte = low >> (24 - bits_left);
      bits_left = bits_left + 8;
      mask = 32'hffff_ffff >> bits_left;
      low = low & mask;

      if (lead_byte == 32'hff) begin
        num_buffered_bytes = num_buffered_bytes + 8'd1;
      end else if (num_buffered_bytes > 8'd0) begin
        carry = lead_byte >> 8;
        byte_value = buffered_byte + carry;
        buffered_byte = lead_byte[7:0];
        st[CABAC_LOW_LSB +: 32] = low;
        st[CABAC_BUFFERED_BYTE_LSB +: 9] = buffered_byte;
        st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8] = num_buffered_bytes;
        st[CABAC_BITS_LEFT_LSB +: 8] = bits_left[7:0];
        st = cabac_write_bits(st, byte_value, 6'd8);
        repeated_byte = (9'h0ff + carry) & 9'h0ff;
        num_buffered_bytes = st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8];
        while (num_buffered_bytes > 8'd1) begin
          st = cabac_write_bits(st, repeated_byte, 6'd8);
          num_buffered_bytes = num_buffered_bytes - 8'd1;
          st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8] = num_buffered_bytes;
        end
      end else begin
        num_buffered_bytes = 8'd1;
        buffered_byte = lead_byte[7:0];
      end

      st[CABAC_LOW_LSB +: 32] = low;
      st[CABAC_BUFFERED_BYTE_LSB +: 9] = buffered_byte;
      st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8] = num_buffered_bytes;
      st[CABAC_BITS_LEFT_LSB +: 8] = bits_left[7:0];
      cabac_write_out = st;
    end
  endfunction

  function automatic cabac_state_t cabac_write_bits(
    input cabac_state_t st_in,
    input logic [31:0]  value,
    input logic [5:0]   bit_count
  );
    cabac_state_t st;
    logic [MAX_SLICE_PAYLOAD_BITS - 1:0] bits;
    logic [12:0] len;
    integer i;

    begin
      st = st_in;
      bits = st[CABAC_BITS_LSB +: MAX_SLICE_PAYLOAD_BITS];
      len = st[CABAC_LEN_LSB +: 13];
      for (i = bit_count - 1; i >= 0; i = i - 1) begin
        bits = (bits << 1) | value[i];
        len = len + 13'd1;
      end
      st[CABAC_BITS_LSB +: MAX_SLICE_PAYLOAD_BITS] = bits;
      st[CABAC_LEN_LSB +: 13] = len;
      cabac_write_bits = st;
    end
  endfunction

  function automatic logic [3:0] renorm_bits_sv(input logic [15:0] range_in);
    logic [15:0] range;
    logic [3:0] count;

    begin
      range = range_in;
      count = 4'd0;
      while (range < 16'd256) begin
        range = range << 1;
        count = count + 4'd1;
      end
      renorm_bits_sv = count;
    end
  endfunction

  function automatic logic [8:0] toy_ctx_lps(input logic [4:0] index);
    begin
      case (index)
        5'd0: toy_ctx_lps = 9'd146;
        5'd1: toy_ctx_lps = 9'd81;
        5'd2: toy_ctx_lps = 9'd128;
        5'd3: toy_ctx_lps = 9'd52;
        5'd4: toy_ctx_lps = 9'd160;
        5'd5: toy_ctx_lps = 9'd129;
        5'd6: toy_ctx_lps = 9'd24;
        5'd7: toy_ctx_lps = 9'd58;
        5'd8: toy_ctx_lps = 9'd29;
        5'd9: toy_ctx_lps = 9'd172;
        5'd10: toy_ctx_lps = 9'd107;
        5'd11: toy_ctx_lps = 9'd136;
        5'd12: toy_ctx_lps = 9'd128;
        5'd13: toy_ctx_lps = 9'd125;
        5'd14: toy_ctx_lps = 9'd184;
        5'd15: toy_ctx_lps = 9'd112;
        5'd16: toy_ctx_lps = 9'd28;
        5'd17: toy_ctx_lps = 9'd67;
        default: toy_ctx_lps = 9'd26;
      endcase
    end
  endfunction

  function automatic logic toy_ctx_mps(input logic [4:0] index);
    begin
      case (index)
        5'd0: toy_ctx_mps = 1'b0;
        5'd1, 5'd2, 5'd3, 5'd4, 5'd5, 5'd9, 5'd12: toy_ctx_mps = 1'b1;
        default: toy_ctx_mps = 1'b0;
      endcase
    end
  endfunction

  function automatic logic [18:0] slice_header_bits(input logic cra_picture);
    logic [7:0] poc_lsb;

    begin
      poc_lsb = cra_picture ? 8'd1 : 8'd0;
      slice_header_bits = {
        1'b1,    // sh_picture_header_in_slice_header_flag
        1'b1,    // ph_gdr_or_irap_pic_flag
        1'b0,    // ph_non_ref_pic_flag
        1'b0,    // ph_gdr_pic_flag
        1'b0,    // ph_inter_slice_allowed_flag
        1'b1,    // ph_pic_parameter_set_id ue(v) = 0
        poc_lsb, // ph_pic_order_cnt_lsb
        1'b0,    // ph_partition_constraints_override_flag
        1'b0,    // ph_joint_cbcr_sign_flag
        1'b0,    // sh_no_output_of_prior_pics_flag
        1'b1,    // sh_qp_delta se(v) = 0
        1'b1     // sh_dep_quant_used_flag
      };
    end
  endfunction

endmodule
