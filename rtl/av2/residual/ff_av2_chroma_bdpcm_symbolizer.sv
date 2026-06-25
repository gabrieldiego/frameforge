`timescale 1ns/1ps

module ff_av2_chroma_bdpcm_symbolizer #(
  parameter int LUMA_PALETTE_RESIDUAL = 0,
  parameter int DC_DELTA_ONLY = 0
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        enable,
  input  logic        advance,
  input  logic        plane_v,
  input  logic        bdpcm_horz,
  input  logic [3:0]  skip_ctx,
  input  logic [1:0]  dc_sign_ctx,
  input  logic [127:0] txb_samples,
  input  logic [31:0] predictor_samples,
  input  logic [127:0] predictor_txb_samples,
  input  logic signed [9:0] dc_delta,
  input  logic [7:0]  dc_recon_sample,
  input  logic        known_zero_txb,
  output logic        op_valid,
  output logic        op_literal,
  output logic [31:0] op_literal_value,
  output logic [4:0]  op_literal_bits,
  output logic [31:0] op_fl,
  output logic [31:0] op_fh,
  output logic [4:0]  op_fl_inc,
  output logic [4:0]  op_fh_inc,
  output logic        txb_done,
  output logic        txb_nonzero,
  output logic [7:0]  entropy_context,
  output logic [7:0]  latched_dc_recon_sample
);

  localparam logic [3:0] TABLE_NONE = 4'd0;
  localparam logic [3:0] TABLE_SKIP = 4'd1;
  localparam logic [3:0] TABLE_EOB = 4'd2;
  localparam logic [3:0] TABLE_EOB_EXTRA = 4'd3;
  localparam logic [3:0] TABLE_BASE_EOB = 4'd4;
  localparam logic [3:0] TABLE_BASE_LF_EOB = 4'd5;
  localparam logic [3:0] TABLE_BASE = 4'd6;
  localparam logic [3:0] TABLE_BASE_LF = 4'd7;
  localparam logic [3:0] TABLE_BR = 4'd8;
  localparam logic [3:0] TABLE_BR_LF = 4'd9;
  localparam logic [3:0] TABLE_DC_SIGN = 4'd10;

  localparam logic [4:0] EMIT_SKIP = 5'd0;
  localparam logic [4:0] EMIT_EOB = 5'd1;
  localparam logic [4:0] EMIT_EOB_EXTRA_BIT = 5'd2;
  localparam logic [4:0] EMIT_EOB_EXTRA_LITERAL = 5'd3;
  localparam logic [4:0] EMIT_BASE_SCAN = 5'd4;
  localparam logic [4:0] EMIT_BR = 5'd5;
  localparam logic [4:0] EMIT_DC_BASE = 5'd6;
  localparam logic [4:0] EMIT_SIGN_SCAN = 5'd7;
  localparam logic [4:0] EMIT_HR_CMAX_ZEROS = 5'd8;
  localparam logic [4:0] EMIT_HR_EXP_PREFIX = 5'd9;
  localparam logic [4:0] EMIT_HR_EXP_VALUE = 5'd10;
  localparam logic [4:0] EMIT_HR_Q_ZEROS = 5'd11;
  localparam logic [4:0] EMIT_HR_ONE = 5'd12;
  localparam logic [4:0] EMIT_HR_LOW_BITS = 5'd13;
  localparam logic [4:0] EMIT_HR_PACK = 5'd14;

  localparam logic [63:0] TX4X4_SCAN_PACK = {
    4'd15, 4'd11, 4'd14, 4'd7, 4'd10, 4'd13, 4'd3, 4'd6,
    4'd9, 4'd12, 4'd2, 4'd5, 4'd8, 4'd1, 4'd4, 4'd0
  };

  logic active_q;
  logic prepare_context_q;
  logic [4:0] emit_state_q;
  logic [3:0] scan_q;
  logic [4:0] eob_q;
  logic [3:0] eob_pt_q;
  logic [3:0] eob_extra_q;
  logic [2:0] eob_offset_bits_q;
  logic [2:0] eob_shift_q;
  logic [7:0] entropy_context_q;
  logic txb_nonzero_q;
  logic plane_v_q;
  logic bdpcm_horz_q;
  logic [3:0] skip_ctx_q;
  logic [1:0] dc_sign_ctx_q;
  logic [7:0] dc_recon_sample_q;
  logic [15:0] level_q [0:15];
  logic coeff_negative_q [0:15];
  logic [4:0] coeff_ctx_q [0:15];
  logic [4:0] br_ctx_q [0:15];
  logic [15:0] hr_avg_q;

  logic signed [15:0] residual_w [0:15];
  logic signed [15:0] pass0_w [0:15];
  logic signed [15:0] coeff_w [0:15];
  logic [15:0] level_pre_w [0:15];
  logic coeff_negative_pre_w [0:15];
  logic [15:0] abs_coeff_w;
  logic [3:0] cul_context_level_w;
  logic [15:0] tx4x4_nonzero_scan_w;
  logic [3:0] cul_level_sat_w [0:15];
  logic [4:0] cul_pair_sum_w [0:7];
  logic [3:0] cul_pair_sat_w [0:7];
  logic [4:0] cul_quad_sum_w [0:3];
  logic [3:0] cul_quad_sat_w [0:3];
  logic [4:0] cul_oct_sum_w [0:1];
  logic [3:0] cul_oct_sat_w [0:1];
  logic [4:0] cul_final_sum_w;
  logic signed [15:0] dc_value_w;
  logic signed [15:0] dc_delta_ext_w;
  logic [15:0] dc_delta_abs_w;
  logic [4:0] eob_pre_w;
  logic [3:0] eob_pt_pre_w;
  logic [3:0] eob_extra_pre_w;
  logic [2:0] eob_offset_bits_pre_w;
  logic [2:0] eob_shift_pre_w;
  logic [7:0] entropy_context_pre_w;
  logic bdpcm_horz_current_w;
  logic [4:0] coeff_ctx_pre_w [0:15];
  logic [4:0] br_ctx_pre_w [0:15];

  logic [3:0] coeff_pos_w;
  logic [15:0] current_level_w;
  logic current_negative_w;
  logic current_base_lf_w;
  logic current_high_range_w;
  logic [15:0] current_high_value_w;
  logic current_plane_v_w;
  logic [2:0] hr_m_w;
  logic [2:0] hr_k_w;
  logic [3:0] hr_cmax_w;
  logic [15:0] hr_q_w;
  logic [15:0] hr_exp_value_w;
  logic [15:0] hr_x_w;
  logic [4:0] hr_length_w;
  logic [4:0] hr_prefix_bits_w;
  logic [31:0] hr_low_mask_w;
  logic [5:0] hr_pack_bits_w;
  logic [31:0] hr_pack_value_w;
  logic hr_pack_valid_w;
  logic sign_hr_pack_current_w;
  logic [5:0] sign_hr_pack_bits_w;
  logic [31:0] sign_hr_pack_value_w;
  logic has_lower_nonzero_w;
  logic [3:0] next_lower_nonzero_scan_w;
  logic [4:0] sign_pack_count_w;
  logic [31:0] sign_pack_value_w;
  logic sign_pack_done_w;
  logic [3:0] sign_pack_next_scan_w;
  logic sign_pack_current_literal_w;

  logic [3:0] table_w;
  logic [4:0] table_ctx_w;
  logic [3:0] symbol_w;
  logic [4:0] nsymbs_w;
  logic op_done_w;
  logic progress_w;
  logic start_op_w;
  logic zero_fast_q;
  logic [31:0] cdf0_w;
  logic [31:0] cdf1_w;
  logic [31:0] cdf2_w;
  logic [31:0] cdf3_w;
  logic [31:0] cdf4_w;
  logic [31:0] cdf_prev_w;
  logic [31:0] cdf_curr_w;
  integer sample_index_w;
  integer scan_index_w;
  integer row_w;
  integer col_w;
  integer mag_w;
  logic signed [15:0] a1_w;
  logic signed [15:0] b1_w;
  logic signed [15:0] c1_w;
  logic signed [15:0] d1_w;
  logic signed [15:0] e1_w;

  assign dc_delta_ext_w = {{6{dc_delta[9]}}, dc_delta};
  assign dc_delta_abs_w = (dc_delta_ext_w < 0) ? -dc_delta_ext_w : dc_delta_ext_w;
  assign current_plane_v_w = plane_v_q;
  assign bdpcm_horz_current_w = (!active_q && !prepare_context_q) ? bdpcm_horz : bdpcm_horz_q;

  always @* begin
    for (sample_index_w = 0; sample_index_w < 16; sample_index_w = sample_index_w + 1) begin
      if (LUMA_PALETTE_RESIDUAL != 0) begin
        // AV2 v1.0.0 Sections 5.20.8.4 and 5.20.7.27: palette provides the
        // luma predictor; coeffs() then carries original_y - predictor_y.
        residual_w[sample_index_w] =
          $signed({1'b0, txb_samples[sample_index_w * 8 +: 8]}) -
          $signed({1'b0, predictor_txb_samples[sample_index_w * 8 +: 8]});
      end else if (sample_index_w[1:0] == 2'd0) begin
        if (bdpcm_horz_current_w) begin
          residual_w[sample_index_w] =
            $signed({1'b0, txb_samples[sample_index_w * 8 +: 8]}) -
            $signed({1'b0, predictor_samples[sample_index_w[3:2] * 8 +: 8]});
        end else if (sample_index_w[3:2] == 2'd0) begin
          // AV2 v1.0.0 Section 5.20.5.6 read_intra_uv_mode() selects the
          // DPCM axis. Vertical DPCM predicts the first row from the edge
          // above the TXB and later rows from the reconstructed row above.
          residual_w[sample_index_w] =
            $signed({1'b0, txb_samples[sample_index_w * 8 +: 8]}) -
            $signed({1'b0, predictor_samples[sample_index_w[1:0] * 8 +: 8]});
        end else begin
          residual_w[sample_index_w] =
            $signed({1'b0, txb_samples[sample_index_w * 8 +: 8]}) -
            $signed({1'b0, txb_samples[(sample_index_w - 4) * 8 +: 8]});
        end
      end else begin
        if (bdpcm_horz_current_w) begin
          residual_w[sample_index_w] =
            $signed({1'b0, txb_samples[sample_index_w * 8 +: 8]}) -
            $signed({1'b0, txb_samples[(sample_index_w - 1) * 8 +: 8]});
        end else if (sample_index_w[3:2] == 2'd0) begin
          residual_w[sample_index_w] =
            $signed({1'b0, txb_samples[sample_index_w * 8 +: 8]}) -
            $signed({1'b0, predictor_samples[sample_index_w[1:0] * 8 +: 8]});
        end else begin
          residual_w[sample_index_w] =
            $signed({1'b0, txb_samples[sample_index_w * 8 +: 8]}) -
            $signed({1'b0, txb_samples[(sample_index_w - 4) * 8 +: 8]});
        end
      end
    end

    for (sample_index_w = 0; sample_index_w < 4; sample_index_w = sample_index_w + 1) begin
      a1_w = residual_w[sample_index_w];
      b1_w = residual_w[4 + sample_index_w];
      c1_w = residual_w[8 + sample_index_w];
      d1_w = residual_w[12 + sample_index_w];

      a1_w = a1_w + b1_w;
      d1_w = d1_w - c1_w;
      e1_w = (a1_w - d1_w) >>> 1;
      b1_w = e1_w - b1_w;
      c1_w = e1_w - c1_w;
      a1_w = a1_w - c1_w;
      d1_w = d1_w + b1_w;

      pass0_w[sample_index_w] = a1_w;
      pass0_w[4 + sample_index_w] = c1_w;
      pass0_w[8 + sample_index_w] = d1_w;
      pass0_w[12 + sample_index_w] = b1_w;
    end

    for (sample_index_w = 0; sample_index_w < 4; sample_index_w = sample_index_w + 1) begin
      a1_w = pass0_w[sample_index_w * 4];
      b1_w = pass0_w[sample_index_w * 4 + 1];
      c1_w = pass0_w[sample_index_w * 4 + 2];
      d1_w = pass0_w[sample_index_w * 4 + 3];

      a1_w = a1_w + b1_w;
      d1_w = d1_w - c1_w;
      e1_w = (a1_w - d1_w) >>> 1;
      b1_w = e1_w - b1_w;
      c1_w = e1_w - c1_w;
      a1_w = a1_w - c1_w;
      d1_w = d1_w + b1_w;

      coeff_w[sample_index_w * 4] = a1_w <<< 3;
      coeff_w[sample_index_w * 4 + 1] = c1_w <<< 3;
      coeff_w[sample_index_w * 4 + 2] = d1_w <<< 3;
      coeff_w[sample_index_w * 4 + 3] = b1_w <<< 3;
    end

    eob_pre_w = 5'd0;
    tx4x4_nonzero_scan_w = 16'd0;
    cul_context_level_w = 4'd0;
    dc_value_w = 16'sd0;
    for (sample_index_w = 0; sample_index_w < 16; sample_index_w = sample_index_w + 1) begin
      if (DC_DELTA_ONLY != 0) begin
        // AV2 v1.0.0 Section 5.20.7.27 coeffs(): the staged 4:2:0 lossy
        // path emits one DC coefficient whose level is abs(delta) * 4,
        // matching the Rust model's write_*_dc_delta_txb helpers.
        if (sample_index_w == 0) begin
          level_pre_w[sample_index_w] = dc_delta_abs_w << 2;
          coeff_negative_pre_w[sample_index_w] = (dc_delta_ext_w < 0);
        end else begin
          level_pre_w[sample_index_w] = 16'd0;
          coeff_negative_pre_w[sample_index_w] = 1'b0;
        end
      end else begin
        if (coeff_w[sample_index_w] < 0) begin
          abs_coeff_w = -coeff_w[sample_index_w];
          coeff_negative_pre_w[sample_index_w] = 1'b1;
        end else begin
          abs_coeff_w = coeff_w[sample_index_w];
          coeff_negative_pre_w[sample_index_w] = 1'b0;
        end
        level_pre_w[sample_index_w] = abs_coeff_w >> 3;
      end
    end

    for (scan_index_w = 0; scan_index_w < 16; scan_index_w = scan_index_w + 1) begin
      tx4x4_nonzero_scan_w[scan_index_w] =
        (level_q[TX4X4_SCAN_PACK[(scan_index_w * 4) +: 4]] != 16'd0);
    end

    // AV2 v1.0.0 Section 5.20.7.27 coeffs(): a TX_4X4 end-of-block value can
    // be 16. AVM's tokenization treats EOB as a value in 1..TX4X4_SAMPLES, so
    // the RTL must keep one more bit than scan_q.
    casez (tx4x4_nonzero_scan_w)
      16'b1???_????_????_????: eob_pre_w = 5'd16;
      16'b01??_????_????_????: eob_pre_w = 5'd15;
      16'b001?_????_????_????: eob_pre_w = 5'd14;
      16'b0001_????_????_????: eob_pre_w = 5'd13;
      16'b0000_1???_????_????: eob_pre_w = 5'd12;
      16'b0000_01??_????_????: eob_pre_w = 5'd11;
      16'b0000_001?_????_????: eob_pre_w = 5'd10;
      16'b0000_0001_????_????: eob_pre_w = 5'd9;
      16'b0000_0000_1???_????: eob_pre_w = 5'd8;
      16'b0000_0000_01??_????: eob_pre_w = 5'd7;
      16'b0000_0000_001?_????: eob_pre_w = 5'd6;
      16'b0000_0000_0001_????: eob_pre_w = 5'd5;
      16'b0000_0000_0000_1???: eob_pre_w = 5'd4;
      16'b0000_0000_0000_01??: eob_pre_w = 5'd3;
      16'b0000_0000_0000_001?: eob_pre_w = 5'd2;
      16'b0000_0000_0000_0001: eob_pre_w = 5'd1;
      default: eob_pre_w = 5'd0;
    endcase

    // AV2 v1.0.0 Section 5.20.7.27 coeffs(): the above/left entropy context
    // uses min(culLevel, 7). EOB is the last nonzero scan position, so summing
    // all 16 coefficient levels is equivalent to summing scan positions before
    // EOB while avoiding an EOB-dependent adder chain.
    for (sample_index_w = 0; sample_index_w < 16; sample_index_w = sample_index_w + 1) begin
      cul_level_sat_w[sample_index_w] =
        (level_q[sample_index_w] > 16'd7) ? 4'd8 : {1'b0, level_q[sample_index_w][2:0]};
    end
    for (sample_index_w = 0; sample_index_w < 8; sample_index_w = sample_index_w + 1) begin
      cul_pair_sum_w[sample_index_w] =
        {1'b0, cul_level_sat_w[sample_index_w * 2]} +
        {1'b0, cul_level_sat_w[(sample_index_w * 2) + 1]};
      cul_pair_sat_w[sample_index_w] =
        (cul_pair_sum_w[sample_index_w] > 5'd7) ? 4'd8 : cul_pair_sum_w[sample_index_w][3:0];
    end
    for (sample_index_w = 0; sample_index_w < 4; sample_index_w = sample_index_w + 1) begin
      cul_quad_sum_w[sample_index_w] =
        {1'b0, cul_pair_sat_w[sample_index_w * 2]} +
        {1'b0, cul_pair_sat_w[(sample_index_w * 2) + 1]};
      cul_quad_sat_w[sample_index_w] =
        (cul_quad_sum_w[sample_index_w] > 5'd7) ? 4'd8 : cul_quad_sum_w[sample_index_w][3:0];
    end
    for (sample_index_w = 0; sample_index_w < 2; sample_index_w = sample_index_w + 1) begin
      cul_oct_sum_w[sample_index_w] =
        {1'b0, cul_quad_sat_w[sample_index_w * 2]} +
        {1'b0, cul_quad_sat_w[(sample_index_w * 2) + 1]};
      cul_oct_sat_w[sample_index_w] =
        (cul_oct_sum_w[sample_index_w] > 5'd7) ? 4'd8 : cul_oct_sum_w[sample_index_w][3:0];
    end
    cul_final_sum_w = {1'b0, cul_oct_sat_w[0]} + {1'b0, cul_oct_sat_w[1]};
    cul_context_level_w = (cul_final_sum_w > 5'd7) ? 4'd7 : cul_final_sum_w[3:0];

    if (coeff_negative_q[0]) begin
      dc_value_w = -$signed(level_q[0]);
    end else begin
      dc_value_w = $signed(level_q[0]);
    end

    entropy_context_pre_w = {4'd0, cul_context_level_w};
    if (dc_value_w < 0) begin
      entropy_context_pre_w = {4'd0, cul_context_level_w} | 8'd8;
    end else if (dc_value_w > 0) begin
      entropy_context_pre_w = {4'd0, cul_context_level_w} + 8'd16;
    end

    if (eob_pre_w <= 5'd2) eob_pt_pre_w = eob_pre_w[3:0];
    else if (eob_pre_w <= 5'd4) eob_pt_pre_w = 4'd3;
    else if (eob_pre_w <= 5'd8) eob_pt_pre_w = 4'd4;
    else eob_pt_pre_w = 4'd5;

    if (eob_pt_pre_w == 4'd3) begin
      eob_extra_pre_w = eob_pre_w - 5'd3;
      eob_offset_bits_pre_w = 3'd1;
    end else if (eob_pt_pre_w == 4'd4) begin
      eob_extra_pre_w = eob_pre_w - 5'd5;
      eob_offset_bits_pre_w = 3'd2;
    end else if (eob_pt_pre_w == 4'd5) begin
      eob_extra_pre_w = eob_pre_w - 5'd9;
      eob_offset_bits_pre_w = 3'd3;
    end else begin
      eob_extra_pre_w = 4'd0;
      eob_offset_bits_pre_w = 3'd0;
    end
    eob_shift_pre_w = (eob_offset_bits_pre_w == 3'd0) ? 3'd0 : (eob_offset_bits_pre_w - 3'd1);

    for (sample_index_w = 0; sample_index_w < 16; sample_index_w = sample_index_w + 1) begin
      row_w = sample_index_w >> 2;
      col_w = sample_index_w & 3;
      mag_w = 0;
      if (LUMA_PALETTE_RESIDUAL != 0 && (row_w + col_w) < 4) begin
        // AV2 v1.0.0 Section 5.20.7.27, LF lower-level luma context:
        // AVM get_nz_mag_lf() uses five forward neighbors for luma.
        if (row_w + 1 < 4) begin
          mag_w = mag_w + ((level_q[sample_index_w + 4] > 16'd5) ? 5 : level_q[sample_index_w + 4]);
        end
        if (col_w + 1 < 4) begin
          mag_w = mag_w + ((level_q[sample_index_w + 1] > 16'd5) ? 5 : level_q[sample_index_w + 1]);
        end
        if (row_w + 1 < 4 && col_w + 1 < 4) begin
          mag_w = mag_w + ((level_q[sample_index_w + 5] > 16'd5) ? 5 : level_q[sample_index_w + 5]);
        end
        if (col_w + 2 < 4) begin
          mag_w = mag_w + ((level_q[sample_index_w + 2] > 16'd5) ? 5 : level_q[sample_index_w + 2]);
        end
        if (row_w + 2 < 4) begin
          mag_w = mag_w + ((level_q[sample_index_w + 8] > 16'd5) ? 5 : level_q[sample_index_w + 8]);
        end
        if (sample_index_w == 0) begin
          coeff_ctx_pre_w[sample_index_w] = (((mag_w + 1) >> 1) > 8) ? 4'd8 : ((mag_w + 1) >> 1);
        end else if ((row_w + col_w) < 2) begin
          coeff_ctx_pre_w[sample_index_w] =
            ((((mag_w + 1) >> 1) > 6) ? 4'd6 : ((mag_w + 1) >> 1)) + 4'd9;
        end else begin
          coeff_ctx_pre_w[sample_index_w] =
            ((((mag_w + 1) >> 1) > 4) ? 5'd4 : ((mag_w + 1) >> 1)) + 5'd16;
        end
      end else if (LUMA_PALETTE_RESIDUAL != 0) begin
        // AV2 v1.0.0 Section 5.20.7.27, regular luma lower-level context.
        if (sample_index_w == 0) begin
          coeff_ctx_pre_w[sample_index_w] = 4'd0;
        end else begin
          if (row_w + 1 < 4) begin
            mag_w = mag_w + ((level_q[sample_index_w + 4] > 16'd3) ? 3 : level_q[sample_index_w + 4]);
          end
          if (col_w + 1 < 4) begin
            mag_w = mag_w + ((level_q[sample_index_w + 1] > 16'd3) ? 3 : level_q[sample_index_w + 1]);
          end
          if (row_w + 1 < 4 && col_w + 1 < 4) begin
            mag_w = mag_w + ((level_q[sample_index_w + 5] > 16'd3) ? 3 : level_q[sample_index_w + 5]);
          end
          if (col_w + 2 < 4) begin
            mag_w = mag_w + ((level_q[sample_index_w + 2] > 16'd3) ? 3 : level_q[sample_index_w + 2]);
          end
          if (row_w + 2 < 4) begin
            mag_w = mag_w + ((level_q[sample_index_w + 8] > 16'd3) ? 3 : level_q[sample_index_w + 8]);
          end
          coeff_ctx_pre_w[sample_index_w] = (((mag_w + 1) >> 1) > 4) ? 4'd4 : ((mag_w + 1) >> 1);
          if ((row_w + col_w) >= 6) begin
            coeff_ctx_pre_w[sample_index_w] = coeff_ctx_pre_w[sample_index_w] + 4'd5;
          end
        end
      end else if (sample_index_w == 0) begin
        // AV2 v1.0.0 Section 5.20.7.27, LF lower-level chroma context.
        if (row_w + 1 < 4) begin
          mag_w = mag_w + ((level_q[sample_index_w + 4] > 16'd5) ? 5 : level_q[sample_index_w + 4]);
        end
        if (col_w + 1 < 4) begin
          mag_w = mag_w + ((level_q[sample_index_w + 1] > 16'd5) ? 5 : level_q[sample_index_w + 1]);
        end
        if (row_w + 1 < 4 && col_w + 1 < 4) begin
          mag_w = mag_w + ((level_q[sample_index_w + 5] > 16'd5) ? 5 : level_q[sample_index_w + 5]);
        end
      end else begin
        // AV2 v1.0.0 Section 5.20.7.27, regular chroma lower-level context.
        if (row_w + 1 < 4) begin
          mag_w = mag_w + ((level_q[sample_index_w + 4] > 16'd3) ? 3 : level_q[sample_index_w + 4]);
        end
        if (col_w + 1 < 4) begin
          mag_w = mag_w + ((level_q[sample_index_w + 1] > 16'd3) ? 3 : level_q[sample_index_w + 1]);
        end
        if (row_w + 1 < 4 && col_w + 1 < 4) begin
          mag_w = mag_w + ((level_q[sample_index_w + 5] > 16'd3) ? 3 : level_q[sample_index_w + 5]);
        end
      end
      if (LUMA_PALETTE_RESIDUAL == 0) begin
        coeff_ctx_pre_w[sample_index_w] = ((mag_w + 1) >> 1) > 3 ? 4'd3 : ((mag_w + 1) >> 1);
        if (plane_v_q) begin
          coeff_ctx_pre_w[sample_index_w] = coeff_ctx_pre_w[sample_index_w] + 4'd4;
        end
      end

      mag_w = 0;
      if (row_w + 1 < 4) begin
        mag_w = mag_w + ((LUMA_PALETTE_RESIDUAL != 0 && level_q[sample_index_w + 4] > 16'd5) ? 5 : level_q[sample_index_w + 4]);
      end
      if (col_w + 1 < 4) begin
        mag_w = mag_w + ((LUMA_PALETTE_RESIDUAL != 0 && level_q[sample_index_w + 1] > 16'd5) ? 5 : level_q[sample_index_w + 1]);
      end
      if (row_w + 1 < 4 && col_w + 1 < 4) begin
        mag_w = mag_w + ((LUMA_PALETTE_RESIDUAL != 0 && level_q[sample_index_w + 5] > 16'd5) ? 5 : level_q[sample_index_w + 5]);
      end
      if (LUMA_PALETTE_RESIDUAL != 0) begin
        br_ctx_pre_w[sample_index_w] = ((mag_w + 1) >> 1) > 6 ? 4'd6 : ((mag_w + 1) >> 1);
        if ((row_w + col_w) < 4 && sample_index_w != 0) begin
          br_ctx_pre_w[sample_index_w] = br_ctx_pre_w[sample_index_w] + 4'd7;
        end
      end else begin
        br_ctx_pre_w[sample_index_w] = ((mag_w + 1) >> 1) > 3 ? 4'd3 : ((mag_w + 1) >> 1);
      end
    end
  end

  always @* begin
    coeff_pos_w = TX4X4_SCAN_PACK[(scan_q * 4) +: 4];
    current_level_w = level_q[coeff_pos_w];
    current_negative_w = coeff_negative_q[coeff_pos_w];
    current_base_lf_w =
      (LUMA_PALETTE_RESIDUAL != 0) ?
        (((coeff_pos_w >> 2) + (coeff_pos_w & 4'd3)) < 4) :
        (coeff_pos_w == 4'd0);
    if (LUMA_PALETTE_RESIDUAL != 0 && current_base_lf_w) begin
      current_high_range_w = (current_level_w > 16'd7);
      current_high_value_w = current_level_w - 16'd8;
    end else if (LUMA_PALETTE_RESIDUAL != 0) begin
      current_high_range_w = (current_level_w > 16'd5);
      current_high_value_w = current_level_w - 16'd6;
    end else begin
      current_high_range_w =
        (coeff_pos_w == 4'd0) ? (current_level_w > 16'd4) : (current_level_w > 16'd5);
      current_high_value_w =
        (coeff_pos_w == 4'd0) ? (current_level_w - 16'd5) : (current_level_w - 16'd6);
    end

    if (hr_avg_q < 16'd4) hr_m_w = 3'd1;
    else if (hr_avg_q < 16'd8) hr_m_w = 3'd2;
    else if (hr_avg_q < 16'd16) hr_m_w = 3'd3;
    else if (hr_avg_q < 16'd32) hr_m_w = 3'd4;
    else if (hr_avg_q < 16'd64) hr_m_w = 3'd5;
    else hr_m_w = 3'd6;
    hr_k_w = hr_m_w + 3'd1;
    hr_cmax_w = ({1'b0, hr_m_w} + 4'd4 > 4'd6) ? 4'd6 : ({1'b0, hr_m_w} + 4'd4);
    hr_q_w = current_high_value_w >> hr_m_w;
    hr_exp_value_w = current_high_value_w - ({12'd0, hr_cmax_w} << hr_m_w);
    hr_x_w = hr_exp_value_w + (16'd1 << hr_k_w);
    casez (hr_x_w)
      16'b1???_????_????_????: hr_length_w = 5'd16;
      16'b01??_????_????_????: hr_length_w = 5'd15;
      16'b001?_????_????_????: hr_length_w = 5'd14;
      16'b0001_????_????_????: hr_length_w = 5'd13;
      16'b0000_1???_????_????: hr_length_w = 5'd12;
      16'b0000_01??_????_????: hr_length_w = 5'd11;
      16'b0000_001?_????_????: hr_length_w = 5'd10;
      16'b0000_0001_????_????: hr_length_w = 5'd9;
      16'b0000_0000_1???_????: hr_length_w = 5'd8;
      16'b0000_0000_01??_????: hr_length_w = 5'd7;
      16'b0000_0000_001?_????: hr_length_w = 5'd6;
      16'b0000_0000_0001_????: hr_length_w = 5'd5;
      16'b0000_0000_0000_1???: hr_length_w = 5'd4;
      16'b0000_0000_0000_01??: hr_length_w = 5'd3;
      16'b0000_0000_0000_001?: hr_length_w = 5'd2;
      default: hr_length_w = 5'd1;
    endcase
    hr_prefix_bits_w = hr_length_w - 5'd1 - {2'd0, hr_k_w};
    hr_low_mask_w = (32'd1 << hr_m_w) - 32'd1;
    if (hr_q_w >= {12'd0, hr_cmax_w}) begin
      // AV2 v1.0.0 Section 5.20.7.27 highRange coding emits consecutive
      // bypass literals: cmax zero bits, an optional exponential prefix, then
      // the exponential value. The range coder can consume the same literal
      // sequence in one operation when it fits the 5-bit literal-width port.
      hr_pack_bits_w =
        {2'd0, hr_cmax_w} + {1'd0, hr_prefix_bits_w} + {1'd0, hr_length_w};
      hr_pack_value_w = {16'd0, hr_x_w};
    end else begin
      // For q < cmax, the syntax is q zero bits, a stop one, and m low bits.
      // Leading zero bits do not change the packed literal value.
      hr_pack_bits_w = {1'd0, hr_q_w[4:0]} + 6'd1 + {3'd0, hr_m_w};
      hr_pack_value_w =
        (32'd1 << hr_m_w) | ({16'd0, current_high_value_w} & hr_low_mask_w);
    end
    hr_pack_valid_w = (hr_pack_bits_w != 6'd0) && (hr_pack_bits_w <= 6'd31);
    // AV2 v1.0.0 Section 5.20.7.27 orders a literal coefficient sign before
    // highRange bypass literals. When the sign is not the context-coded luma DC
    // sign, combine both literal runs into one range-coder operation.
    sign_hr_pack_current_w =
      current_high_range_w &&
      !((LUMA_PALETTE_RESIDUAL != 0) && (scan_q == 4'd0)) &&
      hr_pack_valid_w &&
      (hr_pack_bits_w <= 6'd30);
    sign_hr_pack_bits_w = hr_pack_bits_w + 6'd1;
    sign_hr_pack_value_w =
      ({31'd0, current_negative_w} << hr_pack_bits_w[4:0]) |
      hr_pack_value_w;
    has_lower_nonzero_w = 1'b0;
    next_lower_nonzero_scan_w = 4'd0;
    for (scan_index_w = 0; scan_index_w < 16; scan_index_w = scan_index_w + 1) begin
      if (scan_index_w < scan_q && scan_index_w < eob_q &&
          level_q[TX4X4_SCAN_PACK[(scan_index_w * 4) +: 4]] != 16'd0) begin
        has_lower_nonzero_w = 1'b1;
        next_lower_nonzero_scan_w = scan_index_w[3:0];
      end
    end

    // AV2 v1.0.0 Section 5.20.7.27 emits one literal sign per nonzero chroma
    // coefficient, immediately followed by high-range bits when present.
    // AV2 v1.0.0 Section 5.20.7.27 emits one literal sign per nonzero chroma
    // coefficient. Keep the RTL in that one-sign form for now: a wider
    // lookahead packer improved utilization slightly, but became the residual
    // critical path and needed another lower-nonzero search to stay correct.
    sign_pack_current_literal_w = !current_high_range_w && (LUMA_PALETTE_RESIDUAL == 0);
    sign_pack_count_w = 5'd1;
    sign_pack_value_w = {31'd0, current_negative_w};
    sign_pack_done_w = !has_lower_nonzero_w;
    sign_pack_next_scan_w = next_lower_nonzero_scan_w;
  end

  always @* begin
    op_valid = 1'b0;
    op_literal = 1'b0;
    op_literal_value = 32'd0;
    op_literal_bits = 5'd0;
    table_w = TABLE_NONE;
    table_ctx_w = 5'd0;
    symbol_w = 4'd0;
    nsymbs_w = 5'd0;
    op_done_w = 1'b0;

    if (active_q) begin
      case (emit_state_q)
        EMIT_SKIP: begin
          op_valid = 1'b1;
          table_w = TABLE_SKIP;
          table_ctx_w = skip_ctx_q;
          symbol_w = txb_nonzero_q ? 4'd0 : 4'd1;
          nsymbs_w = 5'd2;
          op_done_w = !txb_nonzero_q;
        end
        EMIT_EOB: begin
          op_valid = 1'b1;
          table_w = TABLE_EOB;
          symbol_w = eob_pt_q - 4'd1;
          nsymbs_w = 5'd5;
        end
        EMIT_EOB_EXTRA_BIT: begin
          op_valid = 1'b1;
          table_w = TABLE_EOB_EXTRA;
          symbol_w = {3'd0, eob_extra_q[eob_shift_q]};
          nsymbs_w = 5'd2;
        end
        EMIT_EOB_EXTRA_LITERAL: begin
          op_valid = 1'b1;
          op_literal = 1'b1;
          op_literal_value = {28'd0, eob_extra_q & ((4'd1 << eob_shift_q) - 4'd1)};
          op_literal_bits = {2'd0, eob_shift_q};
        end
        EMIT_BASE_SCAN: begin
          if (scan_q != 4'd0 && scan_q < eob_q) begin
            op_valid = 1'b1;
            if (({1'b0, scan_q} + 5'd1) == eob_q) begin
              if (current_base_lf_w) begin
                table_w = TABLE_BASE_LF_EOB;
                symbol_w = (current_level_w > 16'd5) ? 4'd4 : (current_level_w[3:0] - 4'd1);
                nsymbs_w = 5'd5;
              end else begin
                table_w = TABLE_BASE_EOB;
                symbol_w = (current_level_w > 16'd3) ? 4'd2 : (current_level_w[3:0] - 4'd1);
                nsymbs_w = 5'd3;
              end
              table_ctx_w =
                (scan_q <= 4'd2) ? 4'd1 :
                (scan_q <= 4'd4) ? 4'd2 : 4'd3;
            end else if (current_base_lf_w) begin
              table_w = TABLE_BASE_LF;
              table_ctx_w = coeff_ctx_q[coeff_pos_w];
              symbol_w = (current_level_w > 16'd5) ? 4'd5 : current_level_w[3:0];
              nsymbs_w = 5'd6;
            end else begin
              table_w = TABLE_BASE;
              table_ctx_w = coeff_ctx_q[coeff_pos_w];
              symbol_w = (current_level_w > 16'd3) ? 4'd3 : current_level_w[3:0];
              nsymbs_w = 5'd4;
            end
          end
        end
        EMIT_BR: begin
          op_valid = 1'b1;
          table_w = (LUMA_PALETTE_RESIDUAL != 0 && current_base_lf_w) ? TABLE_BR_LF : TABLE_BR;
          table_ctx_w = br_ctx_q[coeff_pos_w];
          if (LUMA_PALETTE_RESIDUAL != 0 && current_base_lf_w) begin
            symbol_w = ((current_level_w - 16'd5) > 16'd3) ? 4'd3 : (current_level_w[3:0] - 4'd5);
          end else begin
            symbol_w = ((current_level_w - 16'd3) > 16'd3) ? 4'd3 : (current_level_w[3:0] - 4'd3);
          end
          nsymbs_w = 5'd4;
        end
        EMIT_DC_BASE: begin
          op_valid = 1'b1;
          if (eob_q == 5'd1) begin
            table_w = TABLE_BASE_LF_EOB;
            table_ctx_w = 4'd0;
            symbol_w = (level_q[0] > 16'd5) ? 4'd4 : (level_q[0][3:0] - 4'd1);
            nsymbs_w = 5'd5;
          end else begin
            table_w = TABLE_BASE_LF;
            table_ctx_w = coeff_ctx_q[0];
            symbol_w = (level_q[0] > 16'd5) ? 4'd5 : level_q[0][3:0];
            nsymbs_w = 5'd6;
          end
        end
        EMIT_SIGN_SCAN: begin
          if (scan_q < eob_q && current_level_w != 16'd0) begin
            op_valid = 1'b1;
            if (LUMA_PALETTE_RESIDUAL != 0 && scan_q == 4'd0) begin
              // AV2 v1.0.0 Section 5.20.7.27 uses dc_sign context for luma DC.
              table_w = TABLE_DC_SIGN;
              table_ctx_w = {2'd0, dc_sign_ctx_q};
              symbol_w = {3'd0, current_negative_w};
              nsymbs_w = 5'd2;
            end else if (sign_hr_pack_current_w) begin
              op_literal = 1'b1;
              op_literal_value = sign_hr_pack_value_w;
              op_literal_bits = sign_hr_pack_bits_w[4:0];
            end else if (sign_pack_current_literal_w) begin
              op_literal = 1'b1;
              op_literal_value = sign_pack_value_w;
              op_literal_bits = sign_pack_count_w;
            end else begin
              op_literal = 1'b1;
              op_literal_value = {31'd0, current_negative_w};
              op_literal_bits = 5'd1;
            end
            op_done_w =
              sign_hr_pack_current_w ? !has_lower_nonzero_w :
              (sign_pack_current_literal_w ?
                sign_pack_done_w : (!has_lower_nonzero_w && !current_high_range_w));
          end
        end
        EMIT_HR_CMAX_ZEROS: begin
          op_valid = 1'b1;
          op_literal = 1'b1;
          op_literal_value = 32'd0;
          op_literal_bits = {1'd0, hr_cmax_w};
        end
        EMIT_HR_EXP_PREFIX: begin
          op_valid = 1'b1;
          op_literal = 1'b1;
          op_literal_value = 32'd0;
          op_literal_bits = hr_prefix_bits_w;
        end
        EMIT_HR_EXP_VALUE: begin
          op_valid = 1'b1;
          op_literal = 1'b1;
          op_literal_value = {16'd0, hr_x_w};
          op_literal_bits = hr_length_w;
          op_done_w = !has_lower_nonzero_w;
        end
        EMIT_HR_Q_ZEROS: begin
          op_valid = 1'b1;
          op_literal = 1'b1;
          op_literal_value = 32'd0;
          op_literal_bits = hr_q_w[4:0];
        end
        EMIT_HR_ONE: begin
          op_valid = 1'b1;
          op_literal = 1'b1;
          op_literal_value = 32'd1;
          op_literal_bits = 5'd1;
          op_done_w = !has_lower_nonzero_w && (hr_m_w == 3'd0);
        end
        EMIT_HR_LOW_BITS: begin
          op_valid = 1'b1;
          op_literal = 1'b1;
          op_literal_value = {16'd0, current_high_value_w} & hr_low_mask_w;
          op_literal_bits = {2'd0, hr_m_w};
          op_done_w = !has_lower_nonzero_w;
        end
        EMIT_HR_PACK: begin
          op_valid = 1'b1;
          op_literal = 1'b1;
          op_literal_value = hr_pack_value_w;
          op_literal_bits = hr_pack_bits_w[4:0];
          op_done_w = !has_lower_nonzero_w;
        end
        default: begin
        end
      endcase
    end
  end

  always @* begin
    cdf0_w = 32'd0;
    cdf1_w = 32'd0;
    cdf2_w = 32'd0;
    cdf3_w = 32'd0;
    cdf4_w = 32'd0;
    case (table_w)
      TABLE_SKIP: begin
        if (LUMA_PALETTE_RESIDUAL != 0) begin
          case (table_ctx_w)
            4'd1: cdf0_w = 32'd31669;
            4'd2: cdf0_w = 32'd30006;
            4'd3: cdf0_w = 32'd24824;
            4'd4: cdf0_w = 32'd16538;
            4'd5: cdf0_w = 32'd3692;
            default: cdf0_w = 32'd16384;
          endcase
        end else begin
          case (table_ctx_w)
            // AV2 v1.0.0 Section 5.20.7.23 read_tx_block(): 4:2:0 V
            // chroma blocks are one TX_4X4, so get_txb_ctx() can select
            // V-plane skip contexts 0..2 before the retained U EOB offset.
            4'd0: cdf0_w = current_plane_v_w ? 32'd31329 : 32'd16384;
            4'd1: cdf0_w = current_plane_v_w ? 32'd26577 : 32'd16384;
            4'd2: cdf0_w = current_plane_v_w ? 32'd18158 : 32'd16384;
            4'd3: cdf0_w = 32'd32588;
            4'd4: cdf0_w = 32'd16384;
            4'd5: cdf0_w = 32'd16384;
            // AV2 v1.0.0 Section 5.20.7.27 coeffs(): V-plane TXB skip
            // contexts include the retained U-plane nonzero flag, but still
            // use V-plane CDF rows. The 4:2:0 path reaches ctx6..8 here.
            4'd6: cdf0_w = current_plane_v_w ? 32'd25120 : 32'd23870;
            4'd7: cdf0_w = current_plane_v_w ? 32'd16620 : 32'd19113;
            4'd8: cdf0_w = current_plane_v_w ? 32'd8203 : 32'd10420;
            4'd9: cdf0_w = 32'd16384;
            4'd10: cdf0_w = 32'd16384;
            4'd11: cdf0_w = 32'd16384;
            default: cdf0_w = 32'd16384;
          endcase
        end
      end
      TABLE_EOB: begin
        if (LUMA_PALETTE_RESIDUAL != 0) begin
          cdf0_w = 32'd30822;
          cdf1_w = 32'd29709;
          cdf2_w = 32'd25934;
          cdf3_w = 32'd17645;
        end else begin
          cdf0_w = 32'd24768;
          cdf1_w = 32'd22402;
          cdf2_w = 32'd18302;
          cdf3_w = 32'd13199;
        end
      end
      TABLE_EOB_EXTRA: begin
        cdf0_w = 32'd16377;
      end
      TABLE_BASE_EOB: begin
        if (LUMA_PALETTE_RESIDUAL != 0) begin
          case (table_ctx_w)
            4'd0,
            4'd1,
            4'd2: begin cdf0_w = 32'd21845; cdf1_w = 32'd10923; end
            default: begin cdf0_w = 32'd7293; cdf1_w = 32'd2979; end
          endcase
        end else begin
          case (table_ctx_w)
            4'd0: begin cdf0_w = 32'd21845; cdf1_w = 32'd10923; end
            4'd1: begin cdf0_w = 32'd1554; cdf1_w = 32'd331; end
            4'd2: begin cdf0_w = 32'd880; cdf1_w = 32'd321; end
            default: begin cdf0_w = 32'd2156; cdf1_w = 32'd695; end
          endcase
        end
      end
      TABLE_BASE_LF_EOB: begin
        if (LUMA_PALETTE_RESIDUAL != 0) begin
          case (table_ctx_w)
            4'd0: begin cdf0_w = 32'd5282; cdf1_w = 32'd1628; cdf2_w = 32'd989; cdf3_w = 32'd704; end
            4'd1: begin cdf0_w = 32'd4505; cdf1_w = 32'd1626; cdf2_w = 32'd955; cdf3_w = 32'd711; end
            4'd2: begin cdf0_w = 32'd5190; cdf1_w = 32'd2363; cdf2_w = 32'd1566; cdf3_w = 32'd1320; end
            default: begin cdf0_w = 32'd2968; cdf1_w = 32'd623; cdf2_w = 32'd179; cdf3_w = 32'd103; end
          endcase
        end else begin
          case (table_ctx_w)
            4'd0: begin cdf0_w = 32'd3818; cdf1_w = 32'd1325; cdf2_w = 32'd759; cdf3_w = 32'd511; end
            4'd1: begin cdf0_w = 32'd2852; cdf1_w = 32'd849; cdf2_w = 32'd544; cdf3_w = 32'd327; end
            4'd2: begin cdf0_w = 32'd3866; cdf1_w = 32'd1963; cdf2_w = 32'd1189; cdf3_w = 32'd952; end
            default: begin cdf0_w = 32'd26214; cdf1_w = 32'd19661; cdf2_w = 32'd13107; cdf3_w = 32'd6554; end
          endcase
        end
      end
      TABLE_BASE: begin
        if (LUMA_PALETTE_RESIDUAL != 0) begin
          case (table_ctx_w)
            4'd0: begin cdf0_w = 32'd20408; cdf1_w = 32'd6376; cdf2_w = 32'd2825; end
            4'd1: begin cdf0_w = 32'd25522; cdf1_w = 32'd13272; cdf2_w = 32'd6238; end
            4'd2: begin cdf0_w = 32'd28760; cdf1_w = 32'd20163; cdf2_w = 32'd13840; end
            4'd3: begin cdf0_w = 32'd29620; cdf1_w = 32'd23375; cdf2_w = 32'd17868; end
            4'd4: begin cdf0_w = 32'd30225; cdf1_w = 32'd25242; cdf2_w = 32'd20747; end
            4'd5,
            4'd6,
            4'd7,
            4'd8,
            4'd9,
            4'd10,
            4'd11,
            4'd12,
            4'd13,
            4'd14: begin cdf0_w = 32'd24576; cdf1_w = 32'd16384; cdf2_w = 32'd8192; end
            4'd15: begin cdf0_w = 32'd4754; cdf1_w = 32'd1234; cdf2_w = 32'd708; end
            5'd16: begin cdf0_w = 32'd19633; cdf1_w = 32'd9281; cdf2_w = 32'd4169; end
            5'd17: begin cdf0_w = 32'd25719; cdf1_w = 32'd17400; cdf2_w = 32'd12000; end
            5'd18: begin cdf0_w = 32'd29659; cdf1_w = 32'd24714; cdf2_w = 32'd20385; end
            default: begin cdf0_w = 32'd24576; cdf1_w = 32'd16384; cdf2_w = 32'd8192; end
          endcase
        end else begin
          case (table_ctx_w)
            4'd0: begin cdf0_w = 32'd5864; cdf1_w = 32'd666; cdf2_w = 32'd170; end
            4'd1: begin cdf0_w = 32'd17019; cdf1_w = 32'd3870; cdf2_w = 32'd1158; end
            4'd2: begin cdf0_w = 32'd23662; cdf1_w = 32'd11439; cdf2_w = 32'd5806; end
            4'd3: begin cdf0_w = 32'd27940; cdf1_w = 32'd19845; cdf2_w = 32'd13785; end
            4'd4: begin cdf0_w = 32'd4989; cdf1_w = 32'd362; cdf2_w = 32'd79; end
            4'd5: begin cdf0_w = 32'd15354; cdf1_w = 32'd2691; cdf2_w = 32'd743; end
            4'd6: begin cdf0_w = 32'd23540; cdf1_w = 32'd10472; cdf2_w = 32'd5001; end
            4'd7: begin cdf0_w = 32'd28204; cdf1_w = 32'd20034; cdf2_w = 32'd13624; end
            4'd8: begin cdf0_w = 32'd3530; cdf1_w = 32'd279; cdf2_w = 32'd75; end
            4'd9: begin cdf0_w = 32'd12949; cdf1_w = 32'd1915; cdf2_w = 32'd546; end
            4'd10: begin cdf0_w = 32'd23454; cdf1_w = 32'd13450; cdf2_w = 32'd7422; end
            default: begin cdf0_w = 32'd29708; cdf1_w = 32'd22503; cdf2_w = 32'd16680; end
          endcase
        end
      end
      TABLE_BASE_LF: begin
        if (LUMA_PALETTE_RESIDUAL != 0) begin
          case (table_ctx_w)
            4'd0: begin cdf0_w = 32'd27307; cdf1_w = 32'd21845; cdf2_w = 32'd16384; cdf3_w = 32'd10923; cdf4_w = 32'd5461; end
            4'd1: begin cdf0_w = 32'd30940; cdf1_w = 32'd15917; cdf2_w = 32'd8756; cdf3_w = 32'd4119; cdf4_w = 32'd2346; end
            4'd2: begin cdf0_w = 32'd25845; cdf1_w = 32'd16752; cdf2_w = 32'd11062; cdf3_w = 32'd5619; cdf4_w = 32'd3332; end
            4'd3: begin cdf0_w = 32'd27278; cdf1_w = 32'd23948; cdf2_w = 32'd16954; cdf3_w = 32'd12524; cdf4_w = 32'd8747; end
            4'd4: begin cdf0_w = 32'd29736; cdf1_w = 32'd24738; cdf2_w = 32'd19681; cdf3_w = 32'd15306; cdf4_w = 32'd11027; end
            4'd5: begin cdf0_w = 32'd30507; cdf1_w = 32'd26350; cdf2_w = 32'd23609; cdf3_w = 32'd20795; cdf4_w = 32'd17177; end
            4'd6: begin cdf0_w = 32'd30468; cdf1_w = 32'd27481; cdf2_w = 32'd24221; cdf3_w = 32'd20625; cdf4_w = 32'd16931; end
            4'd7: begin cdf0_w = 32'd31070; cdf1_w = 32'd27571; cdf2_w = 32'd24493; cdf3_w = 32'd21319; cdf4_w = 32'd20556; end
            4'd8: begin cdf0_w = 32'd32180; cdf1_w = 32'd29862; cdf2_w = 32'd28576; cdf3_w = 32'd26770; cdf4_w = 32'd25678; end
            4'd9: begin cdf0_w = 32'd20014; cdf1_w = 32'd3758; cdf2_w = 32'd1229; cdf3_w = 32'd632; cdf4_w = 32'd245; end
            4'd10: begin cdf0_w = 32'd24794; cdf1_w = 32'd9456; cdf2_w = 32'd4025; cdf3_w = 32'd1581; cdf4_w = 32'd639; end
            4'd11: begin cdf0_w = 32'd26764; cdf1_w = 32'd15015; cdf2_w = 32'd7279; cdf3_w = 32'd3862; cdf4_w = 32'd2076; end
            4'd12: begin cdf0_w = 32'd27450; cdf1_w = 32'd19862; cdf2_w = 32'd11937; cdf3_w = 32'd6920; cdf4_w = 32'd3857; end
            4'd13: begin cdf0_w = 32'd29431; cdf1_w = 32'd22607; cdf2_w = 32'd16355; cdf3_w = 32'd11865; cdf4_w = 32'd8039; end
            4'd14: begin cdf0_w = 32'd30136; cdf1_w = 32'd24512; cdf2_w = 32'd19379; cdf3_w = 32'd14419; cdf4_w = 32'd10711; end
            4'd15: begin cdf0_w = 32'd31121; cdf1_w = 32'd27787; cdf2_w = 32'd24750; cdf3_w = 32'd22055; cdf4_w = 32'd19838; end
            5'd16: begin cdf0_w = 32'd15310; cdf1_w = 32'd2897; cdf2_w = 32'd768; cdf3_w = 32'd222; cdf4_w = 32'd66; end
            5'd17: begin cdf0_w = 32'd22256; cdf1_w = 32'd8265; cdf2_w = 32'd3122; cdf3_w = 32'd1239; cdf4_w = 32'd550; end
            5'd18: begin cdf0_w = 32'd26259; cdf1_w = 32'd15332; cdf2_w = 32'd8706; cdf3_w = 32'd4470; cdf4_w = 32'd2329; end
            5'd19: begin cdf0_w = 32'd28434; cdf1_w = 32'd19925; cdf2_w = 32'd13129; cdf3_w = 32'd7961; cdf4_w = 32'd4959; end
            default: begin cdf0_w = 32'd30005; cdf1_w = 32'd24826; cdf2_w = 32'd20217; cdf3_w = 32'd15895; cdf4_w = 32'd12193; end
          endcase
        end else begin
          case (table_ctx_w)
            4'd0: begin cdf0_w = 32'd18692; cdf1_w = 32'd6304; cdf2_w = 32'd2830; cdf3_w = 32'd1460; cdf4_w = 32'd940; end
            4'd1: begin cdf0_w = 32'd25248; cdf1_w = 32'd11541; cdf2_w = 32'd5002; cdf3_w = 32'd2456; cdf4_w = 32'd1291; end
            4'd2: begin cdf0_w = 32'd28391; cdf1_w = 32'd19478; cdf2_w = 32'd12957; cdf3_w = 32'd8548; cdf4_w = 32'd5704; end
            4'd3: begin cdf0_w = 32'd31086; cdf1_w = 32'd27629; cdf2_w = 32'd24167; cdf3_w = 32'd20795; cdf4_w = 32'd17722; end
            4'd4: begin cdf0_w = 32'd17533; cdf1_w = 32'd4163; cdf2_w = 32'd1401; cdf3_w = 32'd617; cdf4_w = 32'd317; end
            4'd5: begin cdf0_w = 32'd22512; cdf1_w = 32'd8182; cdf2_w = 32'd2993; cdf3_w = 32'd1303; cdf4_w = 32'd631; end
            4'd6: begin cdf0_w = 32'd26850; cdf1_w = 32'd17139; cdf2_w = 32'd10451; cdf3_w = 32'd6166; cdf4_w = 32'd3667; end
            4'd7: begin cdf0_w = 32'd30753; cdf1_w = 32'd27064; cdf2_w = 32'd22933; cdf3_w = 32'd19063; cdf4_w = 32'd15469; end
            4'd8: begin cdf0_w = 32'd6348; cdf1_w = 32'd813; cdf2_w = 32'd456; cdf3_w = 32'd338; cdf4_w = 32'd242; end
            4'd9: begin cdf0_w = 32'd16394; cdf1_w = 32'd3208; cdf2_w = 32'd1237; cdf3_w = 32'd745; cdf4_w = 32'd477; end
            4'd10: begin cdf0_w = 32'd25571; cdf1_w = 32'd16814; cdf2_w = 32'd11782; cdf3_w = 32'd7834; cdf4_w = 32'd5031; end
            default: begin cdf0_w = 32'd27948; cdf1_w = 32'd23280; cdf2_w = 32'd21067; cdf3_w = 32'd18703; cdf4_w = 32'd16520; end
          endcase
        end
      end
      TABLE_BR: begin
        if (LUMA_PALETTE_RESIDUAL != 0) begin
          case (table_ctx_w)
            4'd0: begin cdf0_w = 32'd10463; cdf1_w = 32'd4025; cdf2_w = 32'd2423; end
            4'd1: begin cdf0_w = 32'd10105; cdf1_w = 32'd2820; cdf2_w = 32'd1448; end
            4'd2: begin cdf0_w = 32'd12992; cdf1_w = 32'd4110; cdf2_w = 32'd2333; end
            4'd3: begin cdf0_w = 32'd17332; cdf1_w = 32'd7455; cdf2_w = 32'd4587; end
            4'd4: begin cdf0_w = 32'd21554; cdf1_w = 32'd12097; cdf2_w = 32'd7914; end
            4'd5: begin cdf0_w = 32'd24220; cdf1_w = 32'd15786; cdf2_w = 32'd11002; end
            default: begin cdf0_w = 32'd27039; cdf1_w = 32'd20775; cdf2_w = 32'd15592; end
          endcase
        end else begin
          case (table_ctx_w)
            4'd0: begin cdf0_w = 32'd12754; cdf1_w = 32'd6227; cdf2_w = 32'd3216; end
            4'd1: begin cdf0_w = 32'd12094; cdf1_w = 32'd5088; cdf2_w = 32'd2439; end
            4'd2: begin cdf0_w = 32'd16540; cdf1_w = 32'd8475; cdf2_w = 32'd4454; end
            default: begin cdf0_w = 32'd23188; cdf1_w = 32'd16485; cdf2_w = 32'd11809; end
          endcase
        end
      end
      TABLE_BR_LF: begin
        case (table_ctx_w)
          4'd0: begin cdf0_w = 32'd24825; cdf1_w = 32'd18575; cdf2_w = 32'd11993; end
          4'd1: begin cdf0_w = 32'd18471; cdf1_w = 32'd10368; cdf2_w = 32'd6530; end
          4'd2: begin cdf0_w = 32'd22211; cdf1_w = 32'd14085; cdf2_w = 32'd10218; end
          4'd3: begin cdf0_w = 32'd24479; cdf1_w = 32'd16700; cdf2_w = 32'd14314; end
          4'd4: begin cdf0_w = 32'd27510; cdf1_w = 32'd22038; cdf2_w = 32'd19059; end
          4'd5: begin cdf0_w = 32'd28835; cdf1_w = 32'd24602; cdf2_w = 32'd22088; end
          4'd6: begin cdf0_w = 32'd30303; cdf1_w = 32'd27443; cdf2_w = 32'd26143; end
          4'd7: begin cdf0_w = 32'd21903; cdf1_w = 32'd16338; cdf2_w = 32'd13077; end
          4'd8: begin cdf0_w = 32'd18197; cdf1_w = 32'd10035; cdf2_w = 32'd6662; end
          4'd9: begin cdf0_w = 32'd18696; cdf1_w = 32'd9747; cdf2_w = 32'd6797; end
          4'd10: begin cdf0_w = 32'd21210; cdf1_w = 32'd12515; cdf2_w = 32'd9533; end
          4'd11: begin cdf0_w = 32'd24165; cdf1_w = 32'd16568; cdf2_w = 32'd13302; end
          4'd12: begin cdf0_w = 32'd26127; cdf1_w = 32'd19682; cdf2_w = 32'd16156; end
          default: begin cdf0_w = 32'd28528; cdf1_w = 32'd23725; cdf2_w = 32'd20822; end
        endcase
      end
      TABLE_DC_SIGN: begin
        case (table_ctx_w)
          4'd0: cdf0_w = 32'd16937;
          4'd1: cdf0_w = 32'd19136;
          default: cdf0_w = 32'd13727;
        endcase
      end
      default: begin
      end
    endcase
  end

  always @* begin
    case (symbol_w)
      4'd0: begin cdf_prev_w = 32'd32768; cdf_curr_w = cdf0_w; end
      4'd1: begin cdf_prev_w = cdf0_w; cdf_curr_w = cdf1_w; end
      4'd2: begin cdf_prev_w = cdf1_w; cdf_curr_w = cdf2_w; end
      4'd3: begin cdf_prev_w = cdf2_w; cdf_curr_w = cdf3_w; end
      4'd4: begin cdf_prev_w = cdf3_w; cdf_curr_w = cdf4_w; end
      default: begin cdf_prev_w = cdf4_w; cdf_curr_w = 32'd0; end
    endcase
  end

  always @* begin
    op_fl = 32'd32768;
    op_fh = 32'd0;
    op_fl_inc = 0;
    op_fh_inc = 0;
    if (op_valid && !op_literal && table_w != TABLE_NONE) begin
      op_fl = cdf_prev_w;
      op_fh = cdf_curr_w;
      case (nsymbs_w)
        5'd2: begin
          if (symbol_w == 4'd0) begin op_fl_inc = 0; op_fh_inc = 8; end
          else begin op_fl_inc = 8; op_fh_inc = 0; end
        end
        5'd3: begin
          case (symbol_w)
            4'd0: begin op_fl_inc = 0; op_fh_inc = 10; end
            4'd1: begin op_fl_inc = 10; op_fh_inc = 5; end
            default: begin op_fl_inc = 5; op_fh_inc = 0; end
          endcase
        end
        5'd4: begin
          case (symbol_w)
            4'd0: begin op_fl_inc = 0; op_fh_inc = 12; end
            4'd1: begin op_fl_inc = 12; op_fh_inc = 8; end
            4'd2: begin op_fl_inc = 8; op_fh_inc = 4; end
            default: begin op_fl_inc = 4; op_fh_inc = 0; end
          endcase
        end
        5'd5: begin
          case (symbol_w)
            4'd0: begin op_fl_inc = 0; op_fh_inc = 12; end
            4'd1: begin op_fl_inc = 12; op_fh_inc = 9; end
            4'd2: begin op_fl_inc = 9; op_fh_inc = 6; end
            4'd3: begin op_fl_inc = 6; op_fh_inc = 3; end
            default: begin op_fl_inc = 3; op_fh_inc = 0; end
          endcase
        end
        5'd6: begin
          case (symbol_w)
            4'd0: begin op_fl_inc = 0; op_fh_inc = 13; end
            4'd1: begin op_fl_inc = 13; op_fh_inc = 10; end
            4'd2: begin op_fl_inc = 10; op_fh_inc = 8; end
            4'd3: begin op_fl_inc = 8; op_fh_inc = 5; end
            4'd4: begin op_fl_inc = 5; op_fh_inc = 2; end
            default: begin op_fl_inc = 2; op_fh_inc = 0; end
          endcase
        end
        default: begin
        end
      endcase
    end
  end

  assign start_op_w = zero_fast_q;
  assign progress_w = active_q && (advance || !op_valid);
  assign txb_done = active_q && op_valid && op_done_w;
  assign txb_nonzero = txb_nonzero_q;
  assign entropy_context = entropy_context_q;
  assign latched_dc_recon_sample = dc_recon_sample_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      active_q <= 1'b0;
      prepare_context_q <= 1'b0;
      emit_state_q <= EMIT_SKIP;
      scan_q <= 4'd15;
      eob_q <= 5'd0;
      eob_pt_q <= 4'd0;
      eob_extra_q <= 4'd0;
      eob_offset_bits_q <= 3'd0;
      eob_shift_q <= 3'd0;
      entropy_context_q <= 8'd0;
      txb_nonzero_q <= 1'b0;
      plane_v_q <= 1'b0;
      bdpcm_horz_q <= 1'b1;
      skip_ctx_q <= 4'd0;
      dc_sign_ctx_q <= 2'd0;
      dc_recon_sample_q <= 8'd0;
      zero_fast_q <= 1'b0;
      hr_avg_q <= 16'd0;
      for (sample_index_w = 0; sample_index_w < 16; sample_index_w = sample_index_w + 1) begin
        level_q[sample_index_w] <= 16'd0;
        coeff_negative_q[sample_index_w] <= 1'b0;
        coeff_ctx_q[sample_index_w] <= 5'd0;
        br_ctx_q[sample_index_w] <= 5'd0;
      end
    end else if (!enable) begin
      active_q <= 1'b0;
      prepare_context_q <= 1'b0;
      emit_state_q <= EMIT_SKIP;
      scan_q <= 4'd15;
      zero_fast_q <= 1'b0;
      hr_avg_q <= 16'd0;
    end else if (!active_q && !prepare_context_q && known_zero_txb) begin
      active_q <= !advance;
      prepare_context_q <= 1'b0;
      emit_state_q <= EMIT_SKIP;
      scan_q <= 4'd15;
      eob_q <= 5'd0;
      eob_pt_q <= 4'd0;
      eob_extra_q <= 4'd0;
      eob_offset_bits_q <= 3'd0;
      eob_shift_q <= 3'd0;
      entropy_context_q <= 8'd0;
      txb_nonzero_q <= 1'b0;
      plane_v_q <= plane_v;
      bdpcm_horz_q <= bdpcm_horz;
      skip_ctx_q <= skip_ctx;
      dc_sign_ctx_q <= dc_sign_ctx;
      dc_recon_sample_q <= dc_recon_sample;
      zero_fast_q <= 1'b1;
      hr_avg_q <= 16'd0;
      for (sample_index_w = 0; sample_index_w < 16; sample_index_w = sample_index_w + 1) begin
        level_q[sample_index_w] <= 16'd0;
        coeff_negative_q[sample_index_w] <= 1'b0;
        coeff_ctx_q[sample_index_w] <= 5'd0;
        br_ctx_q[sample_index_w] <= 5'd0;
      end
    end else if (!active_q && !prepare_context_q) begin
      // Pipeline the launch of nonzero TXBs: the first cycle registers
      // transformed levels from samples; the next cycle derives AV2 v1.0.0
      // Section 5.20.7.27 EOB, context, and BR tables from those levels.
      active_q <= 1'b0;
      prepare_context_q <= 1'b1;
      emit_state_q <= EMIT_SKIP;
      scan_q <= 4'd15;
      plane_v_q <= plane_v;
      bdpcm_horz_q <= bdpcm_horz;
      skip_ctx_q <= skip_ctx;
      dc_sign_ctx_q <= dc_sign_ctx;
      dc_recon_sample_q <= dc_recon_sample;
      zero_fast_q <= 1'b0;
      hr_avg_q <= 16'd0;
      for (sample_index_w = 0; sample_index_w < 16; sample_index_w = sample_index_w + 1) begin
        level_q[sample_index_w] <= level_pre_w[sample_index_w];
        coeff_negative_q[sample_index_w] <= coeff_negative_pre_w[sample_index_w];
      end
    end else if (!active_q) begin
      prepare_context_q <= 1'b0;
      active_q <= 1'b1;
      emit_state_q <= EMIT_SKIP;
      scan_q <= 4'd15;
      zero_fast_q <= 1'b0;
      eob_q <= eob_pre_w;
      eob_pt_q <= eob_pt_pre_w;
      eob_extra_q <= eob_extra_pre_w;
      eob_offset_bits_q <= eob_offset_bits_pre_w;
      eob_shift_q <= eob_shift_pre_w;
      entropy_context_q <= entropy_context_pre_w;
      txb_nonzero_q <= (eob_pre_w != 5'd0);
      hr_avg_q <= 16'd0;
      for (sample_index_w = 0; sample_index_w < 16; sample_index_w = sample_index_w + 1) begin
        coeff_ctx_q[sample_index_w] <= coeff_ctx_pre_w[sample_index_w];
        br_ctx_q[sample_index_w] <= br_ctx_pre_w[sample_index_w];
      end
    end else if (progress_w) begin
      zero_fast_q <= 1'b0;
      case (emit_state_q)
        EMIT_SKIP: begin
          if (!txb_nonzero_q) begin
            active_q <= 1'b0;
          end else begin
            emit_state_q <= EMIT_EOB;
          end
        end
        EMIT_EOB: begin
          if (eob_offset_bits_q != 3'd0) begin
            emit_state_q <= EMIT_EOB_EXTRA_BIT;
          end else begin
            emit_state_q <= (eob_q == 5'd1) ? EMIT_DC_BASE : EMIT_BASE_SCAN;
            scan_q <= eob_q[3:0] - 4'd1;
          end
        end
        EMIT_EOB_EXTRA_BIT: begin
          if (eob_shift_q != 3'd0) begin
            emit_state_q <= EMIT_EOB_EXTRA_LITERAL;
          end else begin
            emit_state_q <= (eob_q == 5'd1) ? EMIT_DC_BASE : EMIT_BASE_SCAN;
            scan_q <= eob_q[3:0] - 4'd1;
          end
        end
        EMIT_EOB_EXTRA_LITERAL: begin
          emit_state_q <= (eob_q == 5'd1) ? EMIT_DC_BASE : EMIT_BASE_SCAN;
          scan_q <= eob_q[3:0] - 4'd1;
        end
        EMIT_BASE_SCAN: begin
          if (scan_q == 4'd0) begin
            emit_state_q <= EMIT_DC_BASE;
          end else if (scan_q >= eob_q) begin
            scan_q <= scan_q - 4'd1;
          end else if (
            op_valid && advance &&
            ((LUMA_PALETTE_RESIDUAL != 0 && current_base_lf_w && current_level_w > 16'd4) ||
             (LUMA_PALETTE_RESIDUAL != 0 && !current_base_lf_w && current_level_w > 16'd2) ||
             (LUMA_PALETTE_RESIDUAL == 0 && coeff_pos_w != 4'd0 && current_level_w > 16'd2))
          ) begin
            emit_state_q <= EMIT_BR;
          end else if (op_valid && advance) begin
            if (scan_q == 4'd1) begin
              emit_state_q <= EMIT_DC_BASE;
            end
            scan_q <= scan_q - 4'd1;
          end
        end
        EMIT_BR: begin
          if (scan_q == 4'd0) begin
            emit_state_q <= EMIT_SIGN_SCAN;
            scan_q <= eob_q[3:0] - 4'd1;
            hr_avg_q <= 16'd0;
          end else begin
            emit_state_q <= EMIT_BASE_SCAN;
            if (scan_q == 4'd1) begin
              emit_state_q <= EMIT_DC_BASE;
            end
            scan_q <= scan_q - 4'd1;
          end
        end
        EMIT_DC_BASE: begin
          if (LUMA_PALETTE_RESIDUAL != 0 && level_q[0] > 16'd4) begin
            emit_state_q <= EMIT_BR;
            scan_q <= 4'd0;
          end else begin
            emit_state_q <= EMIT_SIGN_SCAN;
            scan_q <= eob_q[3:0] - 4'd1;
            hr_avg_q <= 16'd0;
          end
        end
        EMIT_SIGN_SCAN: begin
          if (scan_q >= eob_q || current_level_w == 16'd0) begin
            if (has_lower_nonzero_w) begin
              scan_q <= next_lower_nonzero_scan_w;
            end else begin
              active_q <= 1'b0;
            end
          end else if (op_valid && advance) begin
            if (sign_hr_pack_current_w) begin
              hr_avg_q <= (hr_avg_q + current_high_value_w) >> 1;
              if (!has_lower_nonzero_w) begin
                active_q <= 1'b0;
              end else begin
                scan_q <= next_lower_nonzero_scan_w;
              end
            end else if (sign_pack_current_literal_w) begin
              if (sign_pack_done_w) begin
                active_q <= 1'b0;
              end else begin
                scan_q <= sign_pack_next_scan_w;
              end
            end else if (current_high_range_w) begin
              if (hr_pack_valid_w) begin
                emit_state_q <= EMIT_HR_PACK;
              end else if (hr_q_w >= {12'd0, hr_cmax_w}) begin
                emit_state_q <= EMIT_HR_CMAX_ZEROS;
              end else if (hr_q_w != 16'd0) begin
                emit_state_q <= EMIT_HR_Q_ZEROS;
              end else begin
                emit_state_q <= EMIT_HR_ONE;
              end
            end else if (!has_lower_nonzero_w) begin
              active_q <= 1'b0;
            end else begin
              scan_q <= next_lower_nonzero_scan_w;
            end
          end
        end
        EMIT_HR_CMAX_ZEROS: begin
          if (hr_prefix_bits_w != 5'd0) begin
            emit_state_q <= EMIT_HR_EXP_PREFIX;
          end else begin
            emit_state_q <= EMIT_HR_EXP_VALUE;
          end
        end
        EMIT_HR_EXP_PREFIX: begin
          emit_state_q <= EMIT_HR_EXP_VALUE;
        end
        EMIT_HR_EXP_VALUE: begin
          hr_avg_q <= (hr_avg_q + current_high_value_w) >> 1;
          if (!has_lower_nonzero_w) begin
            active_q <= 1'b0;
          end else begin
            scan_q <= next_lower_nonzero_scan_w;
            emit_state_q <= EMIT_SIGN_SCAN;
          end
        end
        EMIT_HR_Q_ZEROS: begin
          emit_state_q <= EMIT_HR_ONE;
        end
        EMIT_HR_ONE: begin
          if (hr_m_w != 3'd0) begin
            emit_state_q <= EMIT_HR_LOW_BITS;
          end else begin
            hr_avg_q <= (hr_avg_q + current_high_value_w) >> 1;
            if (!has_lower_nonzero_w) begin
              active_q <= 1'b0;
            end else begin
              scan_q <= next_lower_nonzero_scan_w;
              emit_state_q <= EMIT_SIGN_SCAN;
            end
          end
        end
        EMIT_HR_LOW_BITS: begin
          hr_avg_q <= (hr_avg_q + current_high_value_w) >> 1;
          if (!has_lower_nonzero_w) begin
            active_q <= 1'b0;
          end else begin
            scan_q <= next_lower_nonzero_scan_w;
            emit_state_q <= EMIT_SIGN_SCAN;
          end
        end
        EMIT_HR_PACK: begin
          hr_avg_q <= (hr_avg_q + current_high_value_w) >> 1;
          if (!has_lower_nonzero_w) begin
            active_q <= 1'b0;
          end else begin
            scan_q <= next_lower_nonzero_scan_w;
            emit_state_q <= EMIT_SIGN_SCAN;
          end
        end
        default: begin
          active_q <= 1'b0;
        end
      endcase
    end else begin
      zero_fast_q <= 1'b0;
    end
  end

  wire _unused_inputs_w = &{1'b0, plane_v_q};

endmodule
