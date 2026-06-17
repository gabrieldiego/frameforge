`timescale 1ns/1ps

module ff_av2_luma_palette_symbolizer (
  input  logic       enable,
  input  logic [2:0] phase,
  input  logic [4:0] step,
  input  logic [5:0] row,
  input  logic [5:0] col,
  input  logic [3:0] palette_size,
  input  logic [4:0] palette_cache_size,
  input  logic [7:0] palette_first_color,
  input  logic [1:0] palette_delta_bits_minus5,
  input  logic [55:0] palette_delta_minus1,
  input  logic [34:0] palette_delta_literal_bits,
  input  logic [2:0] current_index,
  input  logic [2:0] left_index,
  input  logic [2:0] top_index,
  input  logic [2:0] top_left_index,
  input  logic [1:0] identity_row_flag,
  input  logic [1:0] identity_row_ctx,
  output logic       op_valid,
  output logic       op_literal,
  output logic [31:0] op_literal_value,
  output logic [4:0]  op_literal_bits,
  output logic [31:0] op_fl,
  output logic [31:0] op_fh,
  output logic [4:0] op_fl_inc,
  output logic [4:0] op_fh_inc,
  output logic       header_last_step,
  output logic       map_token_required
);

  localparam logic [2:0] PHASE_PALETTE_HEADER = 3'd1;
  localparam logic [2:0] PHASE_PALETTE_MAP = 3'd2;

  logic [4:0] delta_bits_for_step_w;
  logic [7:0] delta_minus1_for_step_w;
  logic [2:0] delta_index_w;
  logic [4:0] color_first_step_w;
  logic [4:0] delta_bits_step_w;
  logic [4:0] delta_step_start_w;
  logic [31:0] identity_row_cdf0_w;
  logic [31:0] identity_row_cdf1_w;
  logic [2:0] color_ctx_w;
  logic [2:0] color_token_w;
  logic [2:0] color_priority0_w;
  logic [2:0] color_priority1_w;
  logic [2:0] color_priority2_w;
  logic [1:0] color_priority_count_w;
  logic color_priority0_valid_w;
  logic color_priority1_valid_w;
  logic color_priority2_valid_w;
  logic color_priority0_match_w;
  logic color_priority1_match_w;
  logic color_priority2_match_w;
  logic [7:0] color_priority_hit_w;
  logic [7:0] color_non_priority_before_mask_w;
  logic [1:0] color_non_priority_sum01_w;
  logic [1:0] color_non_priority_sum23_w;
  logic [1:0] color_non_priority_sum45_w;
  logic [1:0] color_non_priority_sum67_w;
  logic [2:0] color_non_priority_sum0123_w;
  logic [2:0] color_non_priority_sum4567_w;
  logic [2:0] color_non_priority_before_w;
  logic [2:0] cdf_symbol_w;
  logic [31:0] cdf_w [0:7];
  logic [4:0] prob_inc_w [0:7];

  always @* begin
    color_first_step_w = palette_cache_size + 5'd2;
    delta_bits_step_w = palette_cache_size + 5'd3;
    delta_step_start_w = palette_cache_size + 5'd4;
    delta_index_w = (step >= delta_step_start_w) ? (step - delta_step_start_w) : 3'd0;

    case (delta_index_w)
      3'd0: begin
        delta_minus1_for_step_w = palette_delta_minus1[7:0];
        delta_bits_for_step_w = palette_delta_literal_bits[4:0];
      end
      3'd1: begin
        delta_minus1_for_step_w = palette_delta_minus1[15:8];
        delta_bits_for_step_w = palette_delta_literal_bits[9:5];
      end
      3'd2: begin
        delta_minus1_for_step_w = palette_delta_minus1[23:16];
        delta_bits_for_step_w = palette_delta_literal_bits[14:10];
      end
      3'd3: begin
        delta_minus1_for_step_w = palette_delta_minus1[31:24];
        delta_bits_for_step_w = palette_delta_literal_bits[19:15];
      end
      3'd4: begin
        delta_minus1_for_step_w = palette_delta_minus1[39:32];
        delta_bits_for_step_w = palette_delta_literal_bits[24:20];
      end
      3'd5: begin
        delta_minus1_for_step_w = palette_delta_minus1[47:40];
        delta_bits_for_step_w = palette_delta_literal_bits[29:25];
      end
      default: begin
        delta_minus1_for_step_w = palette_delta_minus1[55:48];
        delta_bits_for_step_w = palette_delta_literal_bits[34:30];
      end
    endcase
  end

  always @* begin
    color_ctx_w = 3'd0;
    color_priority0_w = 3'd0;
    color_priority1_w = 3'd0;
    color_priority2_w = 3'd0;
    color_priority_count_w = 2'd0;
    color_priority0_valid_w = 1'b0;
    color_priority1_valid_w = 1'b0;
    color_priority2_valid_w = 1'b0;

    if (row > 6'd0 && col > 6'd0) begin
      if (left_index == top_left_index && left_index == top_index) begin
        color_ctx_w = 3'd4;
        color_priority0_w = left_index;
        color_priority_count_w = 2'd1;
        color_priority0_valid_w = 1'b1;
      end else if (left_index == top_index) begin
        color_ctx_w = 3'd3;
        color_priority0_w = left_index;
        color_priority1_w = top_left_index;
        color_priority_count_w = 2'd2;
        color_priority0_valid_w = 1'b1;
        color_priority1_valid_w = 1'b1;
      end else if (left_index == top_left_index) begin
        color_ctx_w = 3'd2;
        color_priority0_w = left_index;
        color_priority1_w = top_index;
        color_priority_count_w = 2'd2;
        color_priority0_valid_w = 1'b1;
        color_priority1_valid_w = 1'b1;
      end else if (top_left_index == top_index) begin
        color_ctx_w = 3'd2;
        color_priority0_w = top_index;
        color_priority1_w = left_index;
        color_priority_count_w = 2'd2;
        color_priority0_valid_w = 1'b1;
        color_priority1_valid_w = 1'b1;
      end else begin
        color_ctx_w = 3'd1;
        color_priority0_w = left_index;
        color_priority1_w = top_index;
        color_priority2_w = top_left_index;
        color_priority_count_w = 2'd3;
        color_priority0_valid_w = 1'b1;
        color_priority1_valid_w = 1'b1;
        color_priority2_valid_w = 1'b1;
      end
    end else if (row > 6'd0 || col > 6'd0) begin
      color_ctx_w = 3'd0;
      if (col == 6'd0) begin
        color_priority0_w = top_index;
      end else begin
        color_priority0_w = left_index;
      end
      color_priority_count_w = 2'd1;
      color_priority0_valid_w = 1'b1;
    end

    color_priority0_match_w = color_priority0_valid_w && (current_index == color_priority0_w);
    color_priority1_match_w = color_priority1_valid_w && (current_index == color_priority1_w);
    color_priority2_match_w = color_priority2_valid_w && (current_index == color_priority2_w);

    color_priority_hit_w[0] =
      (color_priority0_valid_w && color_priority0_w == 3'd0) ||
      (color_priority1_valid_w && color_priority1_w == 3'd0) ||
      (color_priority2_valid_w && color_priority2_w == 3'd0);
    color_priority_hit_w[1] =
      (color_priority0_valid_w && color_priority0_w == 3'd1) ||
      (color_priority1_valid_w && color_priority1_w == 3'd1) ||
      (color_priority2_valid_w && color_priority2_w == 3'd1);
    color_priority_hit_w[2] =
      (color_priority0_valid_w && color_priority0_w == 3'd2) ||
      (color_priority1_valid_w && color_priority1_w == 3'd2) ||
      (color_priority2_valid_w && color_priority2_w == 3'd2);
    color_priority_hit_w[3] =
      (color_priority0_valid_w && color_priority0_w == 3'd3) ||
      (color_priority1_valid_w && color_priority1_w == 3'd3) ||
      (color_priority2_valid_w && color_priority2_w == 3'd3);
    color_priority_hit_w[4] =
      (color_priority0_valid_w && color_priority0_w == 3'd4) ||
      (color_priority1_valid_w && color_priority1_w == 3'd4) ||
      (color_priority2_valid_w && color_priority2_w == 3'd4);
    color_priority_hit_w[5] =
      (color_priority0_valid_w && color_priority0_w == 3'd5) ||
      (color_priority1_valid_w && color_priority1_w == 3'd5) ||
      (color_priority2_valid_w && color_priority2_w == 3'd5);
    color_priority_hit_w[6] =
      (color_priority0_valid_w && color_priority0_w == 3'd6) ||
      (color_priority1_valid_w && color_priority1_w == 3'd6) ||
      (color_priority2_valid_w && color_priority2_w == 3'd6);
    color_priority_hit_w[7] =
      (color_priority0_valid_w && color_priority0_w == 3'd7) ||
      (color_priority1_valid_w && color_priority1_w == 3'd7) ||
      (color_priority2_valid_w && color_priority2_w == 3'd7);

    color_non_priority_before_mask_w[0] =
      (3'd0 < current_index) && (4'd0 < palette_size) && !color_priority_hit_w[0];
    color_non_priority_before_mask_w[1] =
      (3'd1 < current_index) && (4'd1 < palette_size) && !color_priority_hit_w[1];
    color_non_priority_before_mask_w[2] =
      (3'd2 < current_index) && (4'd2 < palette_size) && !color_priority_hit_w[2];
    color_non_priority_before_mask_w[3] =
      (3'd3 < current_index) && (4'd3 < palette_size) && !color_priority_hit_w[3];
    color_non_priority_before_mask_w[4] =
      (3'd4 < current_index) && (4'd4 < palette_size) && !color_priority_hit_w[4];
    color_non_priority_before_mask_w[5] =
      (3'd5 < current_index) && (4'd5 < palette_size) && !color_priority_hit_w[5];
    color_non_priority_before_mask_w[6] =
      (3'd6 < current_index) && (4'd6 < palette_size) && !color_priority_hit_w[6];
    color_non_priority_before_mask_w[7] =
      (3'd7 < current_index) && (4'd7 < palette_size) && !color_priority_hit_w[7];

    color_non_priority_sum01_w =
      {1'b0, color_non_priority_before_mask_w[0]} +
      {1'b0, color_non_priority_before_mask_w[1]};
    color_non_priority_sum23_w =
      {1'b0, color_non_priority_before_mask_w[2]} +
      {1'b0, color_non_priority_before_mask_w[3]};
    color_non_priority_sum45_w =
      {1'b0, color_non_priority_before_mask_w[4]} +
      {1'b0, color_non_priority_before_mask_w[5]};
    color_non_priority_sum67_w =
      {1'b0, color_non_priority_before_mask_w[6]} +
      {1'b0, color_non_priority_before_mask_w[7]};
    color_non_priority_sum0123_w =
      {1'b0, color_non_priority_sum01_w} +
      {1'b0, color_non_priority_sum23_w};
    color_non_priority_sum4567_w =
      {1'b0, color_non_priority_sum45_w} +
      {1'b0, color_non_priority_sum67_w};
    color_non_priority_before_w =
      color_non_priority_sum0123_w + color_non_priority_sum4567_w;

    if (color_priority0_match_w) begin
      color_token_w = 3'd0;
    end else if (color_priority1_match_w) begin
      color_token_w = 3'd1;
    end else if (color_priority2_match_w) begin
      color_token_w = 3'd2;
    end else begin
      color_token_w = {1'b0, color_priority_count_w} + color_non_priority_before_w;
    end
  end

  always @* begin
    cdf_w[0] = 32'd32768;
    cdf_w[1] = 32'd0;
    cdf_w[2] = 32'd0;
    cdf_w[3] = 32'd0;
    cdf_w[4] = 32'd0;
    cdf_w[5] = 32'd0;
    cdf_w[6] = 32'd0;
    cdf_w[7] = 32'd0;
    prob_inc_w[0] = 0;
    prob_inc_w[1] = 0;
    prob_inc_w[2] = 0;
    prob_inc_w[3] = 0;
    prob_inc_w[4] = 0;
    prob_inc_w[5] = 0;
    prob_inc_w[6] = 0;
    prob_inc_w[7] = 0;

    if (palette_size == 4'd2) begin
      prob_inc_w[0] = 8;
      prob_inc_w[1] = 0;
      case (color_ctx_w)
        3'd0: cdf_w[0] = 32'd4628;
        3'd1: cdf_w[0] = 32'd16384;
        3'd2: cdf_w[0] = 32'd24186;
        3'd3: cdf_w[0] = 32'd5355;
        default: cdf_w[0] = 32'd2339;
      endcase
    end else if (palette_size == 4'd4) begin
      prob_inc_w[0] = 12;
      prob_inc_w[1] = 8;
      prob_inc_w[2] = 4;
      prob_inc_w[3] = 0;
      case (color_ctx_w)
        3'd0: begin cdf_w[0] = 32'd9062; cdf_w[1] = 32'd5806; cdf_w[2] = 32'd3708; end
        3'd1: begin cdf_w[0] = 32'd22792; cdf_w[1] = 32'd10252; cdf_w[2] = 32'd5386; end
        3'd2: begin cdf_w[0] = 32'd26077; cdf_w[1] = 32'd7308; cdf_w[2] = 32'd3534; end
        3'd3: begin cdf_w[0] = 32'd13859; cdf_w[1] = 32'd8843; cdf_w[2] = 32'd4365; end
        default: begin cdf_w[0] = 32'd2460; cdf_w[1] = 32'd1692; cdf_w[2] = 32'd950; end
      endcase
    end else begin
      // AV2 v1.0.0 Section 8.3 CDF updates: nsymbs=8 selects the 8-symbol
      // increment row used by the software entropy writer.
      prob_inc_w[0] = 14;
      prob_inc_w[1] = 12;
      prob_inc_w[2] = 10;
      prob_inc_w[3] = 8;
      prob_inc_w[4] = 6;
      prob_inc_w[5] = 4;
      prob_inc_w[6] = 2;
      prob_inc_w[7] = 0;
      case (color_ctx_w)
        3'd0: begin cdf_w[0] = 32'd10297; cdf_w[1] = 32'd7685; cdf_w[2] = 32'd6784; cdf_w[3] = 32'd5875; cdf_w[4] = 32'd5114; cdf_w[5] = 32'd4018; cdf_w[6] = 32'd2865; end
        3'd1: begin cdf_w[0] = 32'd25226; cdf_w[1] = 32'd15711; cdf_w[2] = 32'd13617; cdf_w[3] = 32'd9218; cdf_w[4] = 32'd7309; cdf_w[5] = 32'd5702; cdf_w[6] = 32'd3964; end
        3'd2: begin cdf_w[0] = 32'd25186; cdf_w[1] = 32'd12331; cdf_w[2] = 32'd10040; cdf_w[3] = 32'd8146; cdf_w[4] = 32'd6253; cdf_w[5] = 32'd4189; cdf_w[6] = 32'd2136; end
        3'd3: begin cdf_w[0] = 32'd10666; cdf_w[1] = 32'd8624; cdf_w[2] = 32'd5852; cdf_w[3] = 32'd4617; cdf_w[4] = 32'd3922; cdf_w[5] = 32'd3556; cdf_w[6] = 32'd2615; end
        default: begin cdf_w[0] = 32'd2244; cdf_w[1] = 32'd1881; cdf_w[2] = 32'd1612; cdf_w[3] = 32'd1375; cdf_w[4] = 32'd1142; cdf_w[5] = 32'd857; cdf_w[6] = 32'd487; end
      endcase
    end
  end

  always @* begin
    // AV2 v1.0.0 Section 5.20.8.4 palette_tokens(): identity_row_flag uses
    // ctx=3 on row 0 and the previous row's identity flag on later rows.
    case (identity_row_ctx)
      2'd0: begin
        identity_row_cdf0_w = 32'd10253;
        identity_row_cdf1_w = 32'd7017;
      end
      2'd1: begin
        identity_row_cdf0_w = 32'd28754;
        identity_row_cdf1_w = 32'd27535;
      end
      2'd2: begin
        identity_row_cdf0_w = 32'd29220;
        identity_row_cdf1_w = 32'd28605;
      end
      default: begin
        identity_row_cdf0_w = 32'd19769;
        identity_row_cdf1_w = 32'd12;
      end
    endcase
  end

  always @* begin
    op_valid = 1'b0;
    op_literal = 1'b0;
    op_literal_value = 32'd0;
    op_literal_bits = 5'd0;
    op_fl = 32'd32768;
    op_fh = 32'd0;
    op_fl_inc = 0;
    op_fh_inc = 0;
    header_last_step = (step == ({1'b0, palette_size} + palette_cache_size + 5'd2));
    map_token_required =
      (row == 6'd0 && col == 6'd0) ||
      (identity_row_flag != 2'd2 && (identity_row_flag != 2'd1 || col == 6'd0));

    if (enable && phase == PHASE_PALETTE_HEADER) begin
      op_valid = 1'b1;
      if (step == 5'd0) begin
        // AV2 v1.0.0 Section 5.20.8.1 palette_mode_info(): has_palette_y.
        op_fl = 32'd2723;
        op_fh = 32'd0;
        op_fl_inc = 8;
      end else if (step == 5'd1) begin
        // palette_y_size_minus_2, with PALETTE_MIN_SIZE=2 and PALETTE_MAX_SIZE=8.
        if (palette_size == 4'd2) begin
          op_fh = 32'd23989;
          op_fh_inc = 13;
        end else if (palette_size == 4'd4) begin
          op_fl = 32'd17673;
          op_fh = 32'd11991;
          op_fl_inc = 11;
          op_fh_inc = 9;
        end else begin
          op_fl = 32'd2365;
          op_fh = 32'd0;
          op_fl_inc = 2;
          op_fh_inc = 0;
        end
      end else if (step < color_first_step_w) begin
        // AV2 v1.0.0 Section 5.20.8.1 palette_mode_info(): above/left cache
        // entries are each accepted or declined. The MVP declines all cache
        // colors so block-local palettes stay self-contained.
        op_literal = 1'b1;
        op_literal_value = 32'd0;
        op_literal_bits = 5'd1;
      end else if (step == color_first_step_w) begin
        op_literal = 1'b1;
        op_literal_value = {24'd0, palette_first_color};
        op_literal_bits = 5'd8;
      end else if (step == delta_bits_step_w) begin
        op_literal = 1'b1;
        op_literal_value = {30'd0, palette_delta_bits_minus5};
        op_literal_bits = 5'd2;
      end else if (step <= ({1'b0, palette_size} + palette_cache_size + 5'd2)) begin
        op_literal = 1'b1;
        op_literal_value = {24'd0, delta_minus1_for_step_w};
        op_literal_bits = delta_bits_for_step_w;
      end else begin
        op_valid = 1'b0;
      end
    end else if (enable && phase == PHASE_PALETTE_MAP) begin
      if (step == 5'd0) begin
        // AV2 v1.0.0 Section 5.20.8.4 palette_tokens(): palette blocks
        // smaller than 64x64 signal color-map scan direction. The first MVP
        // palette path uses horizontal scan order.
        op_valid = 1'b1;
        op_literal = 1'b1;
        op_literal_value = 32'd0;
        op_literal_bits = 5'd1;
      end else if (step == 5'd1) begin
        op_valid = 1'b1;
        case (identity_row_flag)
          2'd0: begin
            op_fh = identity_row_cdf0_w;
            op_fh_inc = 10;
          end
          2'd1: begin
            op_fl = identity_row_cdf0_w;
            op_fh = identity_row_cdf1_w;
            op_fl_inc = 10;
            op_fh_inc = 5;
          end
          default: begin
            op_fl = identity_row_cdf1_w;
            op_fh = 32'd0;
            op_fl_inc = 5;
          end
        endcase
      end else if (step == 5'd2 && map_token_required) begin
        op_valid = 1'b1;
        if (row == 6'd0 && col == 6'd0) begin
          op_literal = 1'b1;
          op_literal_value = {29'd0, current_index};
          if (palette_size == 4'd2) begin
            op_literal_bits = 5'd1;
          end else if (palette_size == 4'd4) begin
            op_literal_bits = 5'd2;
          end else begin
            op_literal_bits = 5'd3;
          end
        end else begin
          cdf_symbol_w = color_token_w;
          if (cdf_symbol_w == 0) begin
            op_fl = 32'd32768;
            op_fl_inc = 0;
          end else begin
            op_fl = cdf_w[cdf_symbol_w - 1];
            op_fl_inc = prob_inc_w[cdf_symbol_w - 1];
          end
          op_fh = cdf_w[cdf_symbol_w];
          op_fh_inc = prob_inc_w[cdf_symbol_w];
        end
      end
    end
  end

endmodule
