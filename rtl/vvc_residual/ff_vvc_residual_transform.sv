`timescale 1ns/1ps

module ff_vvc_residual_transform #(
  parameter int SAMPLE_BITS = 8,
  parameter int LUMA_TU_SIZE = 8,
  parameter int CU_ACTIVE_COUNT = 64
) (
  input  logic clk,
  input  logic rst_n,
  input  logic clear,
  input  logic enable,
  input  logic [CU_ACTIVE_COUNT - 1:0] cu_active_mask,
  input  logic [7:0] cu_index,
  output logic cu_active,
  input  logic s_axis_valid,
  output logic s_axis_ready,
  input  logic [SAMPLE_BITS - 1:0] s_axis_sample,
  input  logic s_axis_last,
  output logic m_axis_valid,
  input  logic m_axis_ready,
  output logic [7:0] m_axis_kind,
  output logic [31:0] m_axis_data,
  output logic m_axis_last,
  input  logic [(SAMPLE_BITS * LUMA_TU_SIZE * LUMA_TU_SIZE) - 1:0] luma_samples,
  output logic [4:0] quant_luma_rem,
  output logic [(8 * ((LUMA_TU_SIZE * LUMA_TU_SIZE) - 1)) - 1:0] quant_luma_ac_tokens,
  output logic [7:0] recon_luma_sample
);
  localparam int LUMA_SAMPLE_COUNT = LUMA_TU_SIZE * LUMA_TU_SIZE;
  localparam int SAMPLE_COUNT_BITS = $clog2(LUMA_SAMPLE_COUNT + 1);
  localparam int SUM_BITS = SAMPLE_BITS + $clog2(LUMA_SAMPLE_COUNT + 1) + 1;
  localparam logic [7:0] SYMBOL_BIN_EP  = 8'd0;
  localparam logic [7:0] SYMBOL_BIN_CTX = 8'd2;
  localparam logic [7:0] SYMBOL_BINS_EP = 8'd4;
  localparam logic [4:0] CTX_LAST_SIG_COEFF_X_PREFIX_3 = 5'd6;
  localparam logic [4:0] CTX_LAST_SIG_COEFF_Y_PREFIX_3 = 5'd7;
  localparam logic [4:0] CTX_ABS_LEVEL_GTX_0 = 5'd10;
  localparam logic [4:0] CTX_PAR_LEVEL_0 = 5'd11;
  localparam logic [4:0] CTX_ABS_LEVEL_GTX_32 = 5'd12;

  logic [7:0] direct_sample [0:LUMA_SAMPLE_COUNT - 1];
  logic [7:0] stream_sample [0:LUMA_SAMPLE_COUNT - 1];
  logic [SUM_BITS - 1:0] direct_sum;
  logic [SUM_BITS - 1:0] stream_sum;
  logic [SUM_BITS - 1:0] direct_dc_numerator;
  logic [SUM_BITS - 1:0] stream_dc_numerator;
  logic [7:0] dc_sample;
  logic [7:0] stream_dc_sample;
  logic signed [9:0] stream_recon_dc_coeff;
  logic [(SAMPLE_BITS * LUMA_SAMPLE_COUNT) - 1:0] stream_samples_q;
  logic [SAMPLE_COUNT_BITS - 1:0] stream_sample_count_q;
  logic stream_result_valid_q;
  logic [3:0] stream_packet_index_q;
  logic [4:0] stream_quant_luma_rem;
  logic [12:0] direct_scaled_distance;
  logic [12:0] stream_scaled_distance;
  logic [7:0] direct_recon_from_rem;
  logic [7:0] stream_recon_from_rem;
  logic stream_negative;
  logic [4:0] stream_abs_remainder_value;
  logic [4:0] stream_abs_remainder_code_value;
  logic [2:0] stream_abs_remainder_prefix_extra_len;
  logic [5:0] stream_abs_remainder_prefix_count;
  logic [31:0] stream_abs_remainder_prefix_pattern;
  logic [5:0] stream_abs_remainder_suffix_count;
  logic [31:0] stream_abs_remainder_suffix_pattern;
  logic [3:0] stream_last_packet_index;
  logic [40:0] residual_packet_next;
  integer sample_i;

  always_comb begin
    direct_sum = '0;
    stream_sum = '0;
    quant_luma_ac_tokens = '0;
    for (sample_i = 0; sample_i < LUMA_SAMPLE_COUNT; sample_i = sample_i + 1) begin
      if (SAMPLE_BITS <= 8) begin
        direct_sample[sample_i] = luma_samples[((LUMA_SAMPLE_COUNT - 1 - sample_i) * SAMPLE_BITS) +: SAMPLE_BITS];
        stream_sample[sample_i] = stream_samples_q[((LUMA_SAMPLE_COUNT - 1 - sample_i) * SAMPLE_BITS) +: SAMPLE_BITS];
      end else begin
        direct_sample[sample_i] = luma_samples[((LUMA_SAMPLE_COUNT - 1 - sample_i) * SAMPLE_BITS) +: SAMPLE_BITS] >> (SAMPLE_BITS - 8);
        stream_sample[sample_i] = stream_samples_q[((LUMA_SAMPLE_COUNT - 1 - sample_i) * SAMPLE_BITS) +: SAMPLE_BITS] >> (SAMPLE_BITS - 8);
      end
      direct_sum = direct_sum + direct_sample[sample_i];
      stream_sum = stream_sum + stream_sample[sample_i];
    end

    for (sample_i = 0; sample_i < LUMA_SAMPLE_COUNT - 1; sample_i = sample_i + 1) begin
      quant_luma_ac_tokens = (quant_luma_ac_tokens << 8) | 8'h40;
    end
  end

  assign direct_dc_numerator = direct_sum + (LUMA_SAMPLE_COUNT / 2);
  assign stream_dc_numerator = stream_sum + (LUMA_SAMPLE_COUNT / 2);
  assign dc_sample = direct_dc_numerator / LUMA_SAMPLE_COUNT;
  assign stream_dc_sample = stream_dc_numerator / LUMA_SAMPLE_COUNT;
  assign direct_scaled_distance = (((13'd114 - {5'd0, dc_sample}) * 13'd16) + 13'd57) / 13'd114;
  assign quant_luma_rem =
    (dc_sample >= 8'd114) ? 5'd0 :
    ((direct_scaled_distance > 13'd16) ? 5'd16 : direct_scaled_distance[4:0]);
  assign direct_recon_from_rem = (((9'd16 - quant_luma_rem) * 9'd114) + 9'd8) >> 4;
  assign recon_luma_sample = direct_recon_from_rem;

  assign s_axis_ready = enable && (!stream_result_valid_q || (m_axis_valid && m_axis_ready && m_axis_last));
  assign stream_scaled_distance =
    (((13'd114 - {5'd0, stream_dc_sample}) * 13'd16) + 13'd57) / 13'd114;
  assign stream_quant_luma_rem =
    (stream_dc_sample >= 8'd114) ? 5'd0 :
    ((stream_scaled_distance > 13'd16) ? 5'd16 : stream_scaled_distance[4:0]);
  assign stream_recon_from_rem = (((9'd16 - stream_quant_luma_rem) * 9'd114) + 9'd8) >> 4;
  assign stream_recon_dc_coeff = $signed({2'b00, stream_recon_from_rem}) - 10'sd114;
  assign stream_negative = (stream_quant_luma_rem != 5'd0) && (stream_recon_dc_coeff < 10'sd0);
  assign stream_abs_remainder_value =
    (stream_quant_luma_rem > 5'd3) ? ((stream_quant_luma_rem - 5'd4) >> 1) : 5'd0;
  assign stream_abs_remainder_code_value = stream_abs_remainder_value - 5'd5;
  assign stream_abs_remainder_prefix_extra_len =
    (stream_abs_remainder_code_value <= 5'd0) ? 3'd0 :
    ((stream_abs_remainder_code_value <= 5'd2) ? 3'd1 :
    ((stream_abs_remainder_code_value <= 5'd6) ? 3'd2 : 3'd3));
  assign stream_abs_remainder_prefix_count =
    (stream_abs_remainder_value < 5'd5) ? {1'b0, stream_abs_remainder_value + 5'd1} :
    {3'd0, stream_abs_remainder_prefix_extra_len} + 6'd5;
  assign stream_abs_remainder_prefix_pattern =
    (stream_abs_remainder_value < 5'd5) ?
    ((32'd1 << stream_abs_remainder_prefix_count) - 32'd2) :
    ((32'd1 << stream_abs_remainder_prefix_count) - 32'd1);
  assign stream_abs_remainder_suffix_count =
    (stream_abs_remainder_value < 5'd5) ? 6'd0 :
    {3'd0, stream_abs_remainder_prefix_extra_len} + 6'd1;
  assign stream_abs_remainder_suffix_pattern =
    (stream_abs_remainder_value < 5'd5) ? 32'd0 :
    (stream_abs_remainder_code_value - ((32'd1 << stream_abs_remainder_prefix_extra_len) - 32'd1));
  assign stream_last_packet_index =
    (stream_quant_luma_rem == 5'd0) ? 4'd1 :
    ((stream_quant_luma_rem <= 5'd1) ? 4'd3 :
    ((stream_quant_luma_rem <= 5'd3) ? 4'd5 : 4'd7));
  assign cu_active = cu_active_mask[CU_ACTIVE_COUNT - 1 - cu_index];

  always_comb begin
    case (stream_packet_index_q)
      4'd0: residual_packet_next = {
        SYMBOL_BIN_CTX, 18'd0, 1'b0, CTX_LAST_SIG_COEFF_X_PREFIX_3, 8'd0, 1'b0
      };
      4'd1: residual_packet_next = {
        SYMBOL_BIN_CTX, 18'd0, 1'b0, CTX_LAST_SIG_COEFF_Y_PREFIX_3, 8'd0, stream_last_packet_index == 4'd1
      };
      4'd2: residual_packet_next = {
        SYMBOL_BIN_CTX, 18'd0, 1'b0, CTX_ABS_LEVEL_GTX_0, 7'd0, stream_quant_luma_rem > 5'd1, 1'b0
      };
      4'd3: begin
        if (stream_last_packet_index == 4'd3) begin
          residual_packet_next = {SYMBOL_BIN_EP, 31'd0, stream_negative, 1'b1};
        end else begin
          residual_packet_next = {
            SYMBOL_BIN_CTX, 18'd0, 1'b0, CTX_PAR_LEVEL_0, 7'd0, stream_quant_luma_rem[0], 1'b0
          };
        end
      end
      4'd4: residual_packet_next = {
        SYMBOL_BIN_CTX, 18'd0, 1'b0, CTX_ABS_LEVEL_GTX_32, 7'd0, stream_quant_luma_rem > 5'd3,
        stream_last_packet_index == 4'd4
      };
      4'd5: begin
        if (stream_last_packet_index == 4'd5) begin
          residual_packet_next = {SYMBOL_BIN_EP, 31'd0, stream_negative, 1'b1};
        end else begin
          residual_packet_next = {
            SYMBOL_BINS_EP,
            (stream_abs_remainder_prefix_pattern << 6) |
              {26'd0, stream_abs_remainder_prefix_count},
            1'b0
          };
        end
      end
      4'd6: residual_packet_next = {
        SYMBOL_BINS_EP,
        (stream_abs_remainder_suffix_pattern << 6) |
          {26'd0, stream_abs_remainder_suffix_count},
        1'b0
      };
      default: residual_packet_next = {SYMBOL_BIN_EP, 31'd0, stream_negative, 1'b1};
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      stream_samples_q <= '0;
      stream_sample_count_q <= '0;
      stream_result_valid_q <= 1'b0;
      stream_packet_index_q <= 4'd0;
      m_axis_valid <= 1'b0;
      m_axis_kind <= 8'd0;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;
    end else if (clear || !enable) begin
      stream_samples_q <= '0;
      stream_sample_count_q <= '0;
      stream_result_valid_q <= 1'b0;
      stream_packet_index_q <= 4'd0;
      m_axis_valid <= 1'b0;
      m_axis_kind <= 8'd0;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;
    end else begin
      if (s_axis_valid && s_axis_ready) begin
        stream_samples_q[((LUMA_SAMPLE_COUNT - 1) - stream_sample_count_q) * SAMPLE_BITS +: SAMPLE_BITS] <=
          s_axis_sample;
        if (s_axis_last || stream_sample_count_q == LUMA_SAMPLE_COUNT - 1) begin
          stream_result_valid_q <= 1'b1;
          stream_packet_index_q <= 4'd0;
          stream_sample_count_q <= '0;
        end else begin
          stream_sample_count_q <= stream_sample_count_q + 1'b1;
        end
      end

      if (stream_result_valid_q && (!m_axis_valid || m_axis_ready)) begin
        m_axis_valid <= 1'b1;
        {m_axis_kind, m_axis_data, m_axis_last} <= residual_packet_next;
        if (stream_packet_index_q == stream_last_packet_index) begin
          stream_result_valid_q <= 1'b0;
          stream_packet_index_q <= 4'd0;
          stream_samples_q <= '0;
        end else begin
          stream_packet_index_q <= stream_packet_index_q + 4'd1;
        end
      end else if (m_axis_valid && m_axis_ready) begin
        m_axis_valid <= 1'b0;
        m_axis_kind <= 8'd0;
        m_axis_data <= 32'd0;
        m_axis_last <= 1'b0;
      end
    end
  end
endmodule
