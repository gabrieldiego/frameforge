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
  output logic [7:0] quant_luma_rem,
  output logic       quant_luma_negative,
  output logic [(8 * 15) - 1:0] quant_luma_ac_levels,
  output logic [7:0] recon_luma_sample
);
  localparam int LUMA_SAMPLE_COUNT = LUMA_TU_SIZE * LUMA_TU_SIZE;
  localparam int SAMPLE_COUNT_BITS = $clog2(LUMA_SAMPLE_COUNT + 1);
  localparam int SUM_BITS = SAMPLE_BITS + $clog2(LUMA_SAMPLE_COUNT + 1) + 1;
  localparam logic [7:0] SYMBOL_BIN_EP  = 8'd0;
  localparam logic [7:0] SYMBOL_BIN_CTX = 8'd2;
  localparam logic [7:0] SYMBOL_BINS_EP = 8'd4;
  `include "ff_vvc_cabac_context_ids.svh"
  localparam int LUMA_AC_QUANT_SHIFT = 19;

  logic [SUM_BITS - 1:0] stream_sum_q;
  logic [SUM_BITS - 1:0] stream_sum_next;
  logic [SUM_BITS - 1:0] result_dc_numerator;
  logic [7:0] result_dc_sample;
  logic [SAMPLE_COUNT_BITS - 1:0] stream_sample_count_q;
  logic stream_result_valid_q;
  logic [3:0] stream_packet_index_q;
  logic [7:0] stream_quant_luma_rem;
  logic signed [9:0] result_residual_avg;
  logic [9:0] result_abs_residual;
  logic [12:0] result_level_scaled;
  logic [7:0] stream_recon_residual_abs;
  logic stream_negative;
  logic [7:0] stream_abs_remainder_value;
  logic [7:0] stream_abs_remainder_code_value;
  logic [2:0] stream_abs_remainder_prefix_extra_len;
  logic [5:0] stream_abs_remainder_prefix_count;
  logic [31:0] stream_abs_remainder_prefix_pattern;
  logic [5:0] stream_abs_remainder_suffix_count;
  logic [31:0] stream_abs_remainder_suffix_pattern;
  logic [3:0] stream_last_packet_index;
  logic [40:0] residual_packet_next;
  logic [7:0] sample_8bit_w;
  logic signed [9:0] residual_sample_w;
  logic [2:0] sample_x_w;
  logic [2:0] sample_y_w;
  logic signed [63:0] ac_acc_q [0:14];
  logic signed [63:0] ac_acc_next [0:14];
  logic signed [63:0] ac_abs_acc;
  logic [63:0] ac_rounded_abs;
  logic signed [7:0] ac_level_next;
  logic [(8 * 15) - 1:0] quant_luma_ac_levels_next;
  logic [7:0] quant_luma_rem_next;
  logic quant_luma_negative_next;
  logic [7:0] recon_luma_sample_next;
  logic [7:0] result_recon_residual_abs;
  logic signed [8:0] basis_x;
  logic signed [8:0] basis_y;
  integer ac_i;
  integer ac_x_i;
  integer ac_y_i;
  always @* begin
    stream_sum_next = stream_sum_q + { {(SUM_BITS - 8){1'b0}}, sample_8bit_w };
    quant_luma_ac_levels_next = '0;
    for (ac_i = 0; ac_i < 15; ac_i = ac_i + 1) begin
      ac_x_i = (ac_i + 1) % 4;
      ac_y_i = (ac_i + 1) / 4;
      case ((ac_y_i * 8) + sample_y_w)
        0, 1, 2, 3, 4, 5, 6, 7: basis_y = 9'sd64;
        8: basis_y = 9'sd89;
        9: basis_y = 9'sd75;
        10: basis_y = 9'sd50;
        11: basis_y = 9'sd18;
        12: basis_y = -9'sd18;
        13: basis_y = -9'sd50;
        14: basis_y = -9'sd75;
        15: basis_y = -9'sd89;
        16: basis_y = 9'sd83;
        17: basis_y = 9'sd36;
        18: basis_y = -9'sd36;
        19: basis_y = -9'sd83;
        20: basis_y = -9'sd83;
        21: basis_y = -9'sd36;
        22: basis_y = 9'sd36;
        23: basis_y = 9'sd83;
        24: basis_y = 9'sd75;
        25: basis_y = -9'sd18;
        26: basis_y = -9'sd89;
        27: basis_y = -9'sd50;
        28: basis_y = 9'sd50;
        29: basis_y = 9'sd89;
        30: basis_y = 9'sd18;
        default: basis_y = -9'sd75;
      endcase
      case ((ac_x_i * 8) + sample_x_w)
        0, 1, 2, 3, 4, 5, 6, 7: basis_x = 9'sd64;
        8: basis_x = 9'sd89;
        9: basis_x = 9'sd75;
        10: basis_x = 9'sd50;
        11: basis_x = 9'sd18;
        12: basis_x = -9'sd18;
        13: basis_x = -9'sd50;
        14: basis_x = -9'sd75;
        15: basis_x = -9'sd89;
        16: basis_x = 9'sd83;
        17: basis_x = 9'sd36;
        18: basis_x = -9'sd36;
        19: basis_x = -9'sd83;
        20: basis_x = -9'sd83;
        21: basis_x = -9'sd36;
        22: basis_x = 9'sd36;
        23: basis_x = 9'sd83;
        24: basis_x = 9'sd75;
        25: basis_x = -9'sd18;
        26: basis_x = -9'sd89;
        27: basis_x = -9'sd50;
        28: basis_x = 9'sd50;
        29: basis_x = 9'sd89;
        30: basis_x = 9'sd18;
        default: basis_x = -9'sd75;
      endcase
      ac_acc_next[ac_i] = ac_acc_q[ac_i] + (residual_sample_w * basis_x * basis_y);
      ac_abs_acc = ac_acc_next[ac_i][63] ? -ac_acc_next[ac_i] : ac_acc_next[ac_i];
      ac_rounded_abs = (ac_abs_acc + (64'd1 << (LUMA_AC_QUANT_SHIFT - 1))) >> LUMA_AC_QUANT_SHIFT;
      if (ac_rounded_abs > 64'd2) begin
        ac_rounded_abs = 64'd2;
      end
      ac_level_next = ac_acc_next[ac_i][63] ?
        -$signed({5'd0, ac_rounded_abs[2:0]}) : $signed({5'd0, ac_rounded_abs[2:0]});
      quant_luma_ac_levels_next[((14 - ac_i) * 8) +: 8] = ac_level_next;
    end
  end

  assign sample_8bit_w =
    (SAMPLE_BITS <= 8) ? s_axis_sample[7:0] : (s_axis_sample >> (SAMPLE_BITS - 8));
  assign residual_sample_w = $signed({2'b00, sample_8bit_w}) - 10'sd128;
  assign sample_x_w = stream_sample_count_q[2:0];
  assign sample_y_w = stream_sample_count_q[5:3];
  assign result_dc_numerator = stream_sum_next + (LUMA_SAMPLE_COUNT / 2);
  assign result_dc_sample = result_dc_numerator / LUMA_SAMPLE_COUNT;
  assign result_residual_avg = $signed({2'b00, result_dc_sample}) - 10'sd128;
  assign result_abs_residual = result_residual_avg < 10'sd0 ?
    -result_residual_avg : result_residual_avg;
  assign result_level_scaled = ({3'd0, result_abs_residual} * 13'd5) + 13'd8;
  assign quant_luma_rem_next =
    (result_level_scaled[12:4] > 9'd255) ? 8'hff : result_level_scaled[11:4];
  assign quant_luma_negative_next = (quant_luma_rem_next != 8'd0) && (result_residual_avg < 10'sd0);
  assign result_recon_residual_abs = (({5'd0, quant_luma_rem_next} * 13'd16) + 13'd2) / 13'd5;
  assign recon_luma_sample_next = quant_luma_negative_next ?
    ((result_recon_residual_abs >= 8'd128) ? 8'd0 : (8'd128 - result_recon_residual_abs)) :
    (((9'd128 + {1'b0, result_recon_residual_abs}) > 9'd255) ?
      8'd255 : (8'd128 + result_recon_residual_abs));

  assign s_axis_ready = enable && (!stream_result_valid_q || (m_axis_valid && m_axis_ready && m_axis_last));
  assign stream_quant_luma_rem = quant_luma_rem;
  assign stream_recon_residual_abs = (({5'd0, stream_quant_luma_rem} * 13'd16) + 13'd2) / 13'd5;
  assign stream_negative = quant_luma_negative;
  assign stream_abs_remainder_value =
    (stream_quant_luma_rem > 8'd3) ? ((stream_quant_luma_rem - 8'd4) >> 1) : 8'd0;
  assign stream_abs_remainder_code_value = stream_abs_remainder_value - 8'd5;
  assign stream_abs_remainder_prefix_extra_len =
    (stream_abs_remainder_code_value <= 8'd0) ? 3'd0 :
    ((stream_abs_remainder_code_value <= 8'd2) ? 3'd1 :
    ((stream_abs_remainder_code_value <= 8'd6) ? 3'd2 : 3'd3));
  assign stream_abs_remainder_prefix_count =
    (stream_abs_remainder_value < 8'd5) ? {1'b0, stream_abs_remainder_value[4:0] + 5'd1} :
    {3'd0, stream_abs_remainder_prefix_extra_len} + 6'd5;
  assign stream_abs_remainder_prefix_pattern =
    (stream_abs_remainder_value < 8'd5) ?
    ((32'd1 << stream_abs_remainder_prefix_count) - 32'd2) :
    ((32'd1 << stream_abs_remainder_prefix_count) - 32'd1);
  assign stream_abs_remainder_suffix_count =
    (stream_abs_remainder_value < 8'd5) ? 6'd0 :
    {3'd0, stream_abs_remainder_prefix_extra_len} + 6'd1;
  assign stream_abs_remainder_suffix_pattern =
    (stream_abs_remainder_value < 8'd5) ? 32'd0 :
    (stream_abs_remainder_code_value - ((32'd1 << stream_abs_remainder_prefix_extra_len) - 32'd1));
  assign stream_last_packet_index =
    (stream_quant_luma_rem == 8'd0) ? 4'd1 :
    ((stream_quant_luma_rem <= 8'd1) ? 4'd3 :
    ((stream_quant_luma_rem <= 8'd3) ? 4'd5 : 4'd7));
  assign cu_active = cu_active_mask[CU_ACTIVE_COUNT - 1 - cu_index];

  always @* begin
    case (stream_packet_index_q)
      4'd0: residual_packet_next = {
        SYMBOL_BIN_CTX, 13'd0, 1'b0, CTX_LAST_SIG_X_PREFIX_3, 8'd0, 1'b0
      };
      4'd1: residual_packet_next = {
        SYMBOL_BIN_CTX, 13'd0, 1'b0, CTX_LAST_SIG_Y_PREFIX_3, 8'd0, stream_last_packet_index == 4'd1
      };
      4'd2: residual_packet_next = {
        SYMBOL_BIN_CTX, 13'd0, 1'b0, CTX_ABS_LEVEL_GTX_FLAG_0, 7'd0,
        stream_quant_luma_rem > 8'd1, 1'b0
      };
      4'd3: begin
        if (stream_last_packet_index == 4'd3) begin
          residual_packet_next = {SYMBOL_BINS_EP, 25'd0, stream_negative, 6'd1, 1'b1};
        end else begin
          residual_packet_next = {
            SYMBOL_BIN_CTX, 13'd0, 1'b0, CTX_PAR_LEVEL_FLAG_0, 7'd0,
            stream_quant_luma_rem[0], 1'b0
          };
        end
      end
      4'd4: residual_packet_next = {
        SYMBOL_BIN_CTX, 13'd0, 1'b0, CTX_ABS_LEVEL_GTX_FLAG_32, 7'd0, stream_quant_luma_rem > 8'd3,
        stream_last_packet_index == 4'd4
      };
      4'd5: begin
        if (stream_last_packet_index == 4'd5) begin
          residual_packet_next = {SYMBOL_BINS_EP, 25'd0, stream_negative, 6'd1, 1'b1};
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
      default: residual_packet_next = {SYMBOL_BINS_EP, 25'd0, stream_negative, 6'd1, 1'b1};
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      stream_sum_q <= '0;
      stream_sample_count_q <= '0;
      stream_result_valid_q <= 1'b0;
      stream_packet_index_q <= 4'd0;
      quant_luma_rem <= 8'd0;
      quant_luma_negative <= 1'b0;
      quant_luma_ac_levels <= '0;
      recon_luma_sample <= 8'd128;
      m_axis_valid <= 1'b0;
      m_axis_kind <= 8'd0;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;
      for (ac_i = 0; ac_i < 15; ac_i = ac_i + 1) begin
        ac_acc_q[ac_i] <= 64'sd0;
      end
    end else if (clear || !enable) begin
      stream_sum_q <= '0;
      stream_sample_count_q <= '0;
      stream_result_valid_q <= 1'b0;
      stream_packet_index_q <= 4'd0;
      quant_luma_rem <= 8'd0;
      quant_luma_negative <= 1'b0;
      quant_luma_ac_levels <= '0;
      recon_luma_sample <= 8'd128;
      m_axis_valid <= 1'b0;
      m_axis_kind <= 8'd0;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;
      for (ac_i = 0; ac_i < 15; ac_i = ac_i + 1) begin
        ac_acc_q[ac_i] <= 64'sd0;
      end
    end else begin
      if (s_axis_valid && s_axis_ready) begin
        if (s_axis_last || stream_sample_count_q == LUMA_SAMPLE_COUNT - 1) begin
          stream_result_valid_q <= 1'b1;
          stream_packet_index_q <= 4'd0;
          stream_sample_count_q <= '0;
          stream_sum_q <= '0;
          quant_luma_rem <= quant_luma_rem_next;
          quant_luma_negative <= quant_luma_negative_next;
          quant_luma_ac_levels <= quant_luma_ac_levels_next;
          recon_luma_sample <= recon_luma_sample_next;
          for (ac_i = 0; ac_i < 15; ac_i = ac_i + 1) begin
            ac_acc_q[ac_i] <= 64'sd0;
          end
        end else begin
          stream_sum_q <= stream_sum_next;
          stream_sample_count_q <= stream_sample_count_q + 1'b1;
          for (ac_i = 0; ac_i < 15; ac_i = ac_i + 1) begin
            ac_acc_q[ac_i] <= ac_acc_next[ac_i];
          end
        end
      end

      if (stream_result_valid_q && (!m_axis_valid || m_axis_ready)) begin
        m_axis_valid <= 1'b1;
        {m_axis_kind, m_axis_data, m_axis_last} <= residual_packet_next;
        if (stream_packet_index_q == stream_last_packet_index) begin
          stream_result_valid_q <= 1'b0;
          stream_packet_index_q <= 4'd0;
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
