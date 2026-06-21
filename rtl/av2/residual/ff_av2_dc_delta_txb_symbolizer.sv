`timescale 1ns/1ps

module ff_av2_dc_delta_txb_symbolizer #(
  parameter int LUMA_PLANE = 0
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        enable,
  input  logic        advance,
  input  logic        plane_v,
  input  logic [3:0]  skip_ctx,
  input  logic [1:0]  dc_sign_ctx,
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

  localparam logic [3:0] EMIT_SKIP = 4'd0;
  localparam logic [3:0] EMIT_EOB = 4'd1;
  localparam logic [3:0] EMIT_DC_BASE = 4'd2;
  localparam logic [3:0] EMIT_BR = 4'd3;
  localparam logic [3:0] EMIT_SIGN = 4'd4;
  localparam logic [3:0] EMIT_HR_CMAX_ZEROS = 4'd5;
  localparam logic [3:0] EMIT_HR_EXP_PREFIX = 4'd6;
  localparam logic [3:0] EMIT_HR_EXP_VALUE = 4'd7;
  localparam logic [3:0] EMIT_HR_Q_ZEROS = 4'd8;
  localparam logic [3:0] EMIT_HR_ONE = 4'd9;
  localparam logic [3:0] EMIT_HR_LOW_BITS = 4'd10;

  logic active_q;
  logic [3:0] emit_state_q;
  logic [15:0] level_q;
  logic coeff_negative_q;
  logic plane_v_q;
  logic [3:0] skip_ctx_q;
  logic [1:0] dc_sign_ctx_q;
  logic [7:0] entropy_context_q;
  logic [7:0] dc_recon_sample_q;

  logic signed [15:0] dc_delta_ext_w;
  logic [15:0] level_pre_w;
  logic coeff_negative_pre_w;
  logic [2:0] cul_context_level_w;
  logic [7:0] entropy_context_pre_w;
  logic progress_w;
  logic current_plane_v_w;
  logic [3:0] current_skip_ctx_w;
  logic [1:0] current_dc_sign_ctx_w;
  logic [31:0] skip_cdf0_w;
  logic [31:0] eob_cdf0_w;
  logic [31:0] base_cdf0_w;
  logic [31:0] base_cdf1_w;
  logic [31:0] base_cdf2_w;
  logic [31:0] base_cdf3_w;
  logic [31:0] br_cdf0_w;
  logic [31:0] br_cdf1_w;
  logic [31:0] br_cdf2_w;
  logic [31:0] sign_cdf0_w;
  logic [3:0] base_symbol_w;
  logic [1:0] br_symbol_w;
  logic high_range_w;
  logic [15:0] high_value_w;
  logic [15:0] hr_q_w;
  logic [15:0] hr_exp_value_w;
  logic [15:0] hr_x_w;
  logic [4:0] hr_length_w;
  logic [4:0] hr_prefix_bits_w;
  logic op_done_w;

  // AV2 coeffs() coding for the lossy 4:2:0 residual path currently emits a
  // single 4x4-transform DC coefficient. Keeping that DC-only path out of the
  // general 16-coefficient BDPCM symbolizer shortens the residual-to-entropy
  // timing path reported by Vivado.
  assign dc_delta_ext_w = {{6{dc_delta[9]}}, dc_delta};
  assign level_pre_w = (dc_delta_ext_w < 0) ? ((-dc_delta_ext_w) << 2) : (dc_delta_ext_w << 2);
  assign coeff_negative_pre_w = (dc_delta_ext_w < 0);
  assign cul_context_level_w = (level_pre_w > 16'd7) ? 3'd7 : level_pre_w[2:0];
  assign progress_w = active_q && (advance || !op_valid);
  assign current_plane_v_w = plane_v_q;
  assign current_skip_ctx_w = skip_ctx_q;
  assign current_dc_sign_ctx_w = dc_sign_ctx_q;
  assign base_symbol_w = (level_q > 16'd5) ? 4'd4 : (level_q[3:0] - 4'd1);
  assign br_symbol_w = ((level_q - 16'd5) > 16'd3) ? 2'd3 : (level_q[1:0] - 2'd1);
  assign high_range_w = (LUMA_PLANE != 0) ? (level_q > 16'd7) : (level_q > 16'd4);
  assign high_value_w = (LUMA_PLANE != 0) ? (level_q - 16'd8) : (level_q - 16'd5);
  // AV2 high-range coefficient coding follows the reference write_adaptive_hr()
  // flow. A DC-only TXB starts with an average of zero, which selects m=1.
  assign hr_q_w = high_value_w >> 1;
  assign hr_exp_value_w = high_value_w - 16'd10;
  assign hr_x_w = hr_exp_value_w + 16'd4;
  assign hr_prefix_bits_w = hr_length_w - 5'd3;
  assign txb_nonzero = active_q && (level_q != 16'd0);
  assign entropy_context = entropy_context_q;
  assign latched_dc_recon_sample = dc_recon_sample_q;
  assign txb_done = active_q && op_valid && op_done_w;

  always @* begin
    entropy_context_pre_w = {5'd0, cul_context_level_w};
    if (coeff_negative_pre_w) begin
      entropy_context_pre_w = {5'd0, cul_context_level_w} | 8'd8;
    end else if (level_pre_w != 16'd0) begin
      entropy_context_pre_w = {5'd0, cul_context_level_w} + 8'd16;
    end
  end

  always @* begin
    skip_cdf0_w = 32'd16384;
    if (LUMA_PLANE != 0) begin
      case (current_skip_ctx_w)
        4'd1: skip_cdf0_w = 32'd31669;
        4'd2: skip_cdf0_w = 32'd30006;
        4'd3: skip_cdf0_w = 32'd24824;
        4'd4: skip_cdf0_w = 32'd16538;
        4'd5: skip_cdf0_w = 32'd3692;
        default: skip_cdf0_w = 32'd16384;
      endcase
    end else begin
      case (current_skip_ctx_w)
        4'd0: skip_cdf0_w = current_plane_v_w ? 32'd31329 : 32'd16384;
        4'd1: skip_cdf0_w = current_plane_v_w ? 32'd26577 : 32'd16384;
        4'd2: skip_cdf0_w = current_plane_v_w ? 32'd18158 : 32'd16384;
        4'd3: skip_cdf0_w = 32'd32588;
        4'd6: skip_cdf0_w = current_plane_v_w ? 32'd25120 : 32'd23870;
        4'd7: skip_cdf0_w = current_plane_v_w ? 32'd16620 : 32'd19113;
        4'd8: skip_cdf0_w = current_plane_v_w ? 32'd8203 : 32'd10420;
        default: skip_cdf0_w = 32'd16384;
      endcase
    end
  end

  always @* begin
    eob_cdf0_w = (LUMA_PLANE != 0) ? 32'd30822 : 32'd24768;
    if (LUMA_PLANE != 0) begin
      base_cdf0_w = 32'd5282;
      base_cdf1_w = 32'd1628;
      base_cdf2_w = 32'd989;
      base_cdf3_w = 32'd704;
    end else begin
      base_cdf0_w = 32'd3818;
      base_cdf1_w = 32'd1325;
      base_cdf2_w = 32'd759;
      base_cdf3_w = 32'd511;
    end
    br_cdf0_w = 32'd24825;
    br_cdf1_w = 32'd18575;
    br_cdf2_w = 32'd11993;
    case (current_dc_sign_ctx_w)
      2'd0: sign_cdf0_w = 32'd16937;
      2'd1: sign_cdf0_w = 32'd19136;
      default: sign_cdf0_w = 32'd13727;
    endcase
  end

  always @* begin
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
  end

  always @* begin
    op_valid = 1'b0;
    op_literal = 1'b0;
    op_literal_value = 32'd0;
    op_literal_bits = 5'd0;
    op_fl = 32'd32768;
    op_fh = 32'd0;
    op_fl_inc = 5'd0;
    op_fh_inc = 5'd0;
    op_done_w = 1'b0;

    if (active_q) begin
      op_valid = 1'b1;
      case (emit_state_q)
        EMIT_SKIP: begin
          if (level_q == 16'd0) begin
            op_fl = skip_cdf0_w;
            op_fl_inc = 5'd8;
            op_done_w = 1'b1;
          end else begin
            op_fh = skip_cdf0_w;
            op_fh_inc = 5'd8;
          end
        end
        EMIT_EOB: begin
          op_fh = eob_cdf0_w;
          op_fh_inc = 5'd12;
        end
        EMIT_DC_BASE: begin
          case (base_symbol_w)
            4'd0: begin op_fh = base_cdf0_w; op_fh_inc = 5'd12; end
            4'd1: begin op_fl = base_cdf0_w; op_fh = base_cdf1_w; op_fl_inc = 5'd12; op_fh_inc = 5'd9; end
            4'd2: begin op_fl = base_cdf1_w; op_fh = base_cdf2_w; op_fl_inc = 5'd9; op_fh_inc = 5'd6; end
            4'd3: begin op_fl = base_cdf2_w; op_fh = base_cdf3_w; op_fl_inc = 5'd6; op_fh_inc = 5'd3; end
            default: begin op_fl = base_cdf3_w; op_fl_inc = 5'd3; end
          endcase
        end
        EMIT_BR: begin
          case (br_symbol_w)
            2'd0: begin op_fh = br_cdf0_w; op_fh_inc = 5'd12; end
            2'd1: begin op_fl = br_cdf0_w; op_fh = br_cdf1_w; op_fl_inc = 5'd12; op_fh_inc = 5'd8; end
            2'd2: begin op_fl = br_cdf1_w; op_fh = br_cdf2_w; op_fl_inc = 5'd8; op_fh_inc = 5'd4; end
            default: begin op_fl = br_cdf2_w; op_fl_inc = 5'd4; end
          endcase
        end
        EMIT_SIGN: begin
          if (LUMA_PLANE != 0) begin
            if (coeff_negative_q) begin
              op_fl = sign_cdf0_w;
              op_fl_inc = 5'd8;
            end else begin
              op_fh = sign_cdf0_w;
              op_fh_inc = 5'd8;
            end
          end else begin
            op_literal = 1'b1;
            op_literal_value = {31'd0, coeff_negative_q};
            op_literal_bits = 5'd1;
          end
          op_done_w = !high_range_w;
        end
        EMIT_HR_CMAX_ZEROS: begin
          op_literal = 1'b1;
          op_literal_value = 32'd0;
          op_literal_bits = 5'd5;
        end
        EMIT_HR_EXP_PREFIX: begin
          op_literal = 1'b1;
          op_literal_value = 32'd0;
          op_literal_bits = hr_prefix_bits_w;
        end
        EMIT_HR_EXP_VALUE: begin
          op_literal = 1'b1;
          op_literal_value = {16'd0, hr_x_w};
          op_literal_bits = hr_length_w;
          op_done_w = 1'b1;
        end
        EMIT_HR_Q_ZEROS: begin
          op_literal = 1'b1;
          op_literal_value = 32'd0;
          op_literal_bits = hr_q_w[4:0];
        end
        EMIT_HR_ONE: begin
          op_literal = 1'b1;
          op_literal_value = 32'd1;
          op_literal_bits = 5'd1;
        end
        EMIT_HR_LOW_BITS: begin
          op_literal = 1'b1;
          op_literal_value = {31'd0, high_value_w[0]};
          op_literal_bits = 5'd1;
          op_done_w = 1'b1;
        end
        default: begin
          op_valid = 1'b0;
        end
      endcase
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      active_q <= 1'b0;
      emit_state_q <= EMIT_SKIP;
      level_q <= 16'd0;
      coeff_negative_q <= 1'b0;
      plane_v_q <= 1'b0;
      skip_ctx_q <= 4'd0;
      dc_sign_ctx_q <= 2'd0;
      entropy_context_q <= 8'd0;
      dc_recon_sample_q <= 8'd0;
    end else if (!enable) begin
      active_q <= 1'b0;
      emit_state_q <= EMIT_SKIP;
    end else if (!active_q && known_zero_txb) begin
      // Register the zero-TXB decision before emitting the skip symbol. This
      // avoids a long same-cycle path from the DC estimator into the range
      // coder while preserving the emitted AV2 coeffs() syntax.
      active_q <= 1'b1;
      emit_state_q <= EMIT_SKIP;
      level_q <= 16'd0;
      coeff_negative_q <= 1'b0;
      plane_v_q <= plane_v;
      skip_ctx_q <= skip_ctx;
      dc_sign_ctx_q <= dc_sign_ctx;
      entropy_context_q <= 8'd0;
      dc_recon_sample_q <= dc_recon_sample;
    end else if (!active_q) begin
      active_q <= 1'b1;
      emit_state_q <= EMIT_SKIP;
      level_q <= level_pre_w;
      coeff_negative_q <= coeff_negative_pre_w;
      plane_v_q <= plane_v;
      skip_ctx_q <= skip_ctx;
      dc_sign_ctx_q <= dc_sign_ctx;
      entropy_context_q <= entropy_context_pre_w;
      dc_recon_sample_q <= dc_recon_sample;
    end else if (progress_w) begin
      case (emit_state_q)
        EMIT_SKIP: begin
          if (level_q == 16'd0) begin
            active_q <= 1'b0;
          end else begin
            emit_state_q <= EMIT_EOB;
          end
        end
        EMIT_EOB: begin
          emit_state_q <= EMIT_DC_BASE;
        end
        EMIT_DC_BASE: begin
          if (LUMA_PLANE != 0 && level_q > 16'd4) begin
            emit_state_q <= EMIT_BR;
          end else begin
            emit_state_q <= EMIT_SIGN;
          end
        end
        EMIT_BR: begin
          emit_state_q <= EMIT_SIGN;
        end
        EMIT_SIGN: begin
          if (!high_range_w) begin
            active_q <= 1'b0;
          end else if (hr_q_w >= 16'd5) begin
            emit_state_q <= EMIT_HR_CMAX_ZEROS;
          end else if (hr_q_w != 16'd0) begin
            emit_state_q <= EMIT_HR_Q_ZEROS;
          end else begin
            emit_state_q <= EMIT_HR_ONE;
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
          active_q <= 1'b0;
        end
        EMIT_HR_Q_ZEROS: begin
          emit_state_q <= EMIT_HR_ONE;
        end
        EMIT_HR_ONE: begin
          emit_state_q <= EMIT_HR_LOW_BITS;
        end
        EMIT_HR_LOW_BITS: begin
          active_q <= 1'b0;
        end
        default: begin
          active_q <= 1'b0;
        end
      endcase
    end
  end

endmodule
