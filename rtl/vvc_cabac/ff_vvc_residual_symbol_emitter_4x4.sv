`timescale 1ns/1ps

module ff_vvc_residual_symbol_emitter_4x4 (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        clear,
  input  logic        start,
  input  logic        chroma_mode,
  input  logic [15:0] tb_width,
  input  logic [15:0] tb_height,
  input  logic [7:0]  luma_dc_abs,
  input  logic        luma_dc_negative,
  input  logic [(4 * 15) - 1:0] luma_ac_levels,
  input  logic signed [8:0] chroma_dc_level,
  input  logic [(4 * 3) - 1:0] chroma_ac_levels,

  output logic        m_axis_valid,
  input  logic        m_axis_ready,
  output logic [7:0]  m_axis_kind,
  output logic [31:0] m_axis_data,
  output logic        done,
  output logic        busy
);
  localparam logic [7:0] SYMBOL_BIN_CTX = 8'd2;
  localparam logic [7:0] SYMBOL_BINS_EP = 8'd4;

  `include "ff_vvc_cabac_context_ids.svh"

  localparam logic [2:0] ST_IDLE = 3'd0;
  localparam logic [2:0] ST_LAST_X = 3'd1;
  localparam logic [2:0] ST_LAST_Y = 3'd2;
  localparam logic [2:0] ST_SCAN = 3'd3;
  localparam logic [2:0] ST_SECOND = 3'd4;
  localparam logic [2:0] ST_SIGN = 3'd5;

  localparam logic [2:0] SUB_SIG = 3'd0;
  localparam logic [2:0] SUB_GT1 = 3'd1;
  localparam logic [2:0] SUB_PAR = 3'd2;
  localparam logic [2:0] SUB_GT3 = 3'd3;
  localparam logic [2:0] SUB_REM_PREFIX = 3'd4;
  localparam logic [2:0] SUB_REM_SUFFIX = 3'd5;
  localparam logic [2:0] SUB_SIGN_ACCUM = 3'd6;
  localparam logic [2:0] SUB_REM_PREP = 3'd7;

  logic [2:0] state_q;
  logic mode_q;
  logic [15:0] tb_width_q;
  logic [15:0] tb_height_q;
  logic [(9 * 16) - 1:0] coeff_abs_q;
  logic [(9 * 16) - 1:0] coeff_template_abs_q;
  logic [15:0] coeff_negative_q;
  logic [1:0] bin_idx_q;
  logic [4:0] scan_pos_q;
  logic [2:0] subphase_q;
  logic [31:0] sign_bits_q;
  logic [5:0] sign_count_q;
  logic [5:0] num_nonzero_q;
  logic [9:0] regular_bins_left_q;
  logic scan_regular_active_q;
  logic signed [5:0] min_pos_2nd_pass_q;
  logic [5:0] rem_prefix_count_q;
  logic [31:0] rem_prefix_pattern_q;
  logic [5:0] rem_suffix_count_q;
  logic [31:0] rem_suffix_pattern_q;
  logic rem_emit_needed_q;

  logic [(9 * 16) - 1:0] load_coeff_abs;
  logic [(9 * 16) - 1:0] load_coeff_template_abs;
  logic [15:0] load_coeff_negative;
  logic load_has_coeff;
  integer load_i;
  logic signed [8:0] load_level_tmp;
  logic [8:0] load_abs_tmp;

  integer last_i;
  logic [3:0] last_scan_x_tmp;
  logic [3:0] last_scan_y_tmp;
  logic [4:0] last_scan_raster_tmp;
  logic [4:0] last_scan_pos_w;
  logic [1:0] last_x_w;
  logic [1:0] last_y_w;

  logic [3:0] scan_x_w;
  logic [3:0] scan_y_w;
  logic [4:0] scan_raster_w;
  logic [8:0] coeff_abs_w;
  logic coeff_negative_w;
  logic [8:0] loc_sum_abs_w;
  logic [7:0] loc_num_sig_w;
  logic [8:0] rice_sum_abs_w;
  logic [8:0] sum_abs_for_rice_w;
  logic [8:0] coeff_abs_lane_w [0:15];
  logic [8:0] coeff_template_sig_lane_w [0:15];
  logic [15:0] coeff_sig_w;
  genvar coeff_lane_i;

  logic [2:0] last_x_cmax_w;
  logic [2:0] last_y_cmax_w;
  logic [1:0] last_x_emit_max_w;
  logic [1:0] last_y_emit_max_w;
  logic scan_regular_active_w;
  logic second_active_w;
  logic sig_needed_w;
  logic rem_needed_w;
  logic [9:0] sig_ctx_w;
  logic [9:0] level_ctx_inc_w;
  logic [9:0] gt1_ctx_w;
  logic [9:0] par_ctx_w;
  logic [9:0] gt3_ctx_w;
  logic [7:0] ctx_offset_w;
  logic [7:0] sum_bucket_w;
  logic [7:0] d_sum_w;
  logic [2:0] rice_param_w;
  logic [8:0] bypass_zero_pos_w;
  logic [8:0] bypass_value_w;
  logic [8:0] rem_threshold_w;
  logic [8:0] rem_abs_value_w;
  logic [8:0] rem_code_value_w;
  logic [8:0] rem_prefix_value_w;
  logic [2:0] rem_prefix_extra_len_w;
  logic [5:0] rem_prefix_count_w;
  logic [31:0] rem_prefix_pattern_w;
  logic [5:0] rem_suffix_count_w;
  logic [31:0] rem_suffix_pattern_w;
  integer prefix_len_i;

  assign busy = (state_q != ST_IDLE);
  assign d_sum_w = {4'd0, scan_x_w} + {4'd0, scan_y_w};

  generate
    for (coeff_lane_i = 0; coeff_lane_i < 16; coeff_lane_i = coeff_lane_i + 1) begin : gen_coeff_lanes
      assign coeff_abs_lane_w[coeff_lane_i] =
        coeff_abs_q[(coeff_lane_i * 9) +: 9];
      assign coeff_sig_w[coeff_lane_i] =
        (coeff_abs_lane_w[coeff_lane_i] != 9'd0);
      assign coeff_template_sig_lane_w[coeff_lane_i] =
        coeff_sig_w[coeff_lane_i] ?
        coeff_template_abs_q[(coeff_lane_i * 9) +: 9] : 9'd0;
    end
  endgenerate

  always @* begin
    load_coeff_abs = {(9 * 16){1'b0}};
    load_coeff_template_abs = {(9 * 16){1'b0}};
    load_coeff_negative = 16'd0;
    load_has_coeff = 1'b0;
    load_level_tmp = 9'sd0;
    load_abs_tmp = 9'd0;
    for (load_i = 0; load_i < 16; load_i = load_i + 1) begin
      if (chroma_mode) begin
        if (load_i == 0) begin
          load_level_tmp = chroma_dc_level;
        end else if (load_i == 1) begin
          load_level_tmp =
            $signed({{5{chroma_ac_levels[(0 * 4) + 3]}},
                     chroma_ac_levels[(0 * 4) +: 4]});
        end else if (load_i == 4) begin
          load_level_tmp =
            $signed({{5{chroma_ac_levels[(1 * 4) + 3]}},
                     chroma_ac_levels[(1 * 4) +: 4]});
        end else if (load_i == 5) begin
          load_level_tmp =
            $signed({{5{chroma_ac_levels[(2 * 4) + 3]}},
                     chroma_ac_levels[(2 * 4) +: 4]});
        end else begin
          load_level_tmp = 9'sd0;
        end
      end else begin
        if (load_i == 0) begin
          load_level_tmp = (luma_dc_negative && (luma_dc_abs != 8'd0)) ?
            -$signed({1'b0, luma_dc_abs}) : $signed({1'b0, luma_dc_abs});
        end else begin
          load_level_tmp =
            $signed({{5{luma_ac_levels[((15 - load_i) * 4) + 3]}},
                     luma_ac_levels[((15 - load_i) * 4) +: 4]});
        end
      end
      load_abs_tmp = load_level_tmp[8] ? -load_level_tmp : load_level_tmp;
      load_coeff_abs[(load_i * 9) +: 9] = load_abs_tmp;
      load_coeff_negative[load_i] = load_level_tmp[8];
      load_coeff_template_abs[(load_i * 9) +: 9] =
        (load_abs_tmp < (9'd4 + {8'd0, load_abs_tmp[0]})) ?
        load_abs_tmp : (9'd4 + {8'd0, load_abs_tmp[0]});
      if (load_abs_tmp != 9'd0) begin
        load_has_coeff = 1'b1;
      end
    end
  end

  always @* begin
    last_scan_pos_w = 5'd0;
    last_x_w = 2'd0;
    last_y_w = 2'd0;
    last_scan_x_tmp = 4'd0;
    last_scan_y_tmp = 4'd0;
    last_scan_raster_tmp = 5'd0;
    for (last_i = 0; last_i < 16; last_i = last_i + 1) begin
      case (last_i)
        0: begin last_scan_x_tmp = 4'd0; last_scan_y_tmp = 4'd0; last_scan_raster_tmp = 5'd0; end
        1: begin last_scan_x_tmp = 4'd0; last_scan_y_tmp = 4'd1; last_scan_raster_tmp = 5'd4; end
        2: begin last_scan_x_tmp = 4'd1; last_scan_y_tmp = 4'd0; last_scan_raster_tmp = 5'd1; end
        3: begin last_scan_x_tmp = 4'd0; last_scan_y_tmp = 4'd2; last_scan_raster_tmp = 5'd8; end
        4: begin last_scan_x_tmp = 4'd1; last_scan_y_tmp = 4'd1; last_scan_raster_tmp = 5'd5; end
        5: begin last_scan_x_tmp = 4'd2; last_scan_y_tmp = 4'd0; last_scan_raster_tmp = 5'd2; end
        6: begin last_scan_x_tmp = 4'd0; last_scan_y_tmp = 4'd3; last_scan_raster_tmp = 5'd12; end
        7: begin last_scan_x_tmp = 4'd1; last_scan_y_tmp = 4'd2; last_scan_raster_tmp = 5'd9; end
        8: begin last_scan_x_tmp = 4'd2; last_scan_y_tmp = 4'd1; last_scan_raster_tmp = 5'd6; end
        9: begin last_scan_x_tmp = 4'd3; last_scan_y_tmp = 4'd0; last_scan_raster_tmp = 5'd3; end
        10: begin last_scan_x_tmp = 4'd1; last_scan_y_tmp = 4'd3; last_scan_raster_tmp = 5'd13; end
        11: begin last_scan_x_tmp = 4'd2; last_scan_y_tmp = 4'd2; last_scan_raster_tmp = 5'd10; end
        12: begin last_scan_x_tmp = 4'd3; last_scan_y_tmp = 4'd1; last_scan_raster_tmp = 5'd7; end
        13: begin last_scan_x_tmp = 4'd2; last_scan_y_tmp = 4'd3; last_scan_raster_tmp = 5'd14; end
        14: begin last_scan_x_tmp = 4'd3; last_scan_y_tmp = 4'd2; last_scan_raster_tmp = 5'd11; end
        default: begin last_scan_x_tmp = 4'd3; last_scan_y_tmp = 4'd3; last_scan_raster_tmp = 5'd15; end
      endcase
      if (coeff_abs_q[(last_scan_raster_tmp * 9) +: 9] != 9'd0) begin
        last_scan_pos_w = last_i[4:0];
        last_x_w = last_scan_x_tmp[1:0];
        last_y_w = last_scan_y_tmp[1:0];
      end
    end
  end

  always @* begin
    case (scan_pos_q)
      5'd0: begin
        scan_x_w = 4'd0; scan_y_w = 4'd0; scan_raster_w = 5'd0;
        coeff_abs_w = coeff_abs_lane_w[0]; coeff_negative_w = coeff_negative_q[0];
      end
      5'd1: begin
        scan_x_w = 4'd0; scan_y_w = 4'd1; scan_raster_w = 5'd4;
        coeff_abs_w = coeff_abs_lane_w[4]; coeff_negative_w = coeff_negative_q[4];
      end
      5'd2: begin
        scan_x_w = 4'd1; scan_y_w = 4'd0; scan_raster_w = 5'd1;
        coeff_abs_w = coeff_abs_lane_w[1]; coeff_negative_w = coeff_negative_q[1];
      end
      5'd3: begin
        scan_x_w = 4'd0; scan_y_w = 4'd2; scan_raster_w = 5'd8;
        coeff_abs_w = coeff_abs_lane_w[8]; coeff_negative_w = coeff_negative_q[8];
      end
      5'd4: begin
        scan_x_w = 4'd1; scan_y_w = 4'd1; scan_raster_w = 5'd5;
        coeff_abs_w = coeff_abs_lane_w[5]; coeff_negative_w = coeff_negative_q[5];
      end
      5'd5: begin
        scan_x_w = 4'd2; scan_y_w = 4'd0; scan_raster_w = 5'd2;
        coeff_abs_w = coeff_abs_lane_w[2]; coeff_negative_w = coeff_negative_q[2];
      end
      5'd6: begin
        scan_x_w = 4'd0; scan_y_w = 4'd3; scan_raster_w = 5'd12;
        coeff_abs_w = coeff_abs_lane_w[12]; coeff_negative_w = coeff_negative_q[12];
      end
      5'd7: begin
        scan_x_w = 4'd1; scan_y_w = 4'd2; scan_raster_w = 5'd9;
        coeff_abs_w = coeff_abs_lane_w[9]; coeff_negative_w = coeff_negative_q[9];
      end
      5'd8: begin
        scan_x_w = 4'd2; scan_y_w = 4'd1; scan_raster_w = 5'd6;
        coeff_abs_w = coeff_abs_lane_w[6]; coeff_negative_w = coeff_negative_q[6];
      end
      5'd9: begin
        scan_x_w = 4'd3; scan_y_w = 4'd0; scan_raster_w = 5'd3;
        coeff_abs_w = coeff_abs_lane_w[3]; coeff_negative_w = coeff_negative_q[3];
      end
      5'd10: begin
        scan_x_w = 4'd1; scan_y_w = 4'd3; scan_raster_w = 5'd13;
        coeff_abs_w = coeff_abs_lane_w[13]; coeff_negative_w = coeff_negative_q[13];
      end
      5'd11: begin
        scan_x_w = 4'd2; scan_y_w = 4'd2; scan_raster_w = 5'd10;
        coeff_abs_w = coeff_abs_lane_w[10]; coeff_negative_w = coeff_negative_q[10];
      end
      5'd12: begin
        scan_x_w = 4'd3; scan_y_w = 4'd1; scan_raster_w = 5'd7;
        coeff_abs_w = coeff_abs_lane_w[7]; coeff_negative_w = coeff_negative_q[7];
      end
      5'd13: begin
        scan_x_w = 4'd2; scan_y_w = 4'd3; scan_raster_w = 5'd14;
        coeff_abs_w = coeff_abs_lane_w[14]; coeff_negative_w = coeff_negative_q[14];
      end
      5'd14: begin
        scan_x_w = 4'd3; scan_y_w = 4'd2; scan_raster_w = 5'd11;
        coeff_abs_w = coeff_abs_lane_w[11]; coeff_negative_w = coeff_negative_q[11];
      end
      default: begin
        scan_x_w = 4'd3; scan_y_w = 4'd3; scan_raster_w = 5'd15;
        coeff_abs_w = coeff_abs_lane_w[15]; coeff_negative_w = coeff_negative_q[15];
      end
    endcase
  end

  always @* begin
    loc_sum_abs_w = 9'd0;
    loc_num_sig_w = 8'd0;
    rice_sum_abs_w = 9'd0;
    case (scan_pos_q)
      5'd0: begin
        rice_sum_abs_w = coeff_abs_lane_w[1] + coeff_abs_lane_w[2] +
          coeff_abs_lane_w[5] + coeff_abs_lane_w[4] + coeff_abs_lane_w[8];
        loc_num_sig_w = {7'd0, coeff_sig_w[1]} + {7'd0, coeff_sig_w[2]} +
          {7'd0, coeff_sig_w[5]} + {7'd0, coeff_sig_w[4]} + {7'd0, coeff_sig_w[8]};
        loc_sum_abs_w = coeff_template_sig_lane_w[1] + coeff_template_sig_lane_w[2] +
          coeff_template_sig_lane_w[5] + coeff_template_sig_lane_w[4] +
          coeff_template_sig_lane_w[8];
      end
      5'd1: begin
        rice_sum_abs_w = coeff_abs_lane_w[5] + coeff_abs_lane_w[6] +
          coeff_abs_lane_w[9] + coeff_abs_lane_w[8] + coeff_abs_lane_w[12];
        loc_num_sig_w = {7'd0, coeff_sig_w[5]} + {7'd0, coeff_sig_w[6]} +
          {7'd0, coeff_sig_w[9]} + {7'd0, coeff_sig_w[8]} + {7'd0, coeff_sig_w[12]};
        loc_sum_abs_w = coeff_template_sig_lane_w[5] + coeff_template_sig_lane_w[6] +
          coeff_template_sig_lane_w[9] + coeff_template_sig_lane_w[8] +
          coeff_template_sig_lane_w[12];
      end
      5'd2: begin
        rice_sum_abs_w = coeff_abs_lane_w[2] + coeff_abs_lane_w[3] +
          coeff_abs_lane_w[6] + coeff_abs_lane_w[5] + coeff_abs_lane_w[9];
        loc_num_sig_w = {7'd0, coeff_sig_w[2]} + {7'd0, coeff_sig_w[3]} +
          {7'd0, coeff_sig_w[6]} + {7'd0, coeff_sig_w[5]} + {7'd0, coeff_sig_w[9]};
        loc_sum_abs_w = coeff_template_sig_lane_w[2] + coeff_template_sig_lane_w[3] +
          coeff_template_sig_lane_w[6] + coeff_template_sig_lane_w[5] +
          coeff_template_sig_lane_w[9];
      end
      5'd3: begin
        rice_sum_abs_w = coeff_abs_lane_w[9] + coeff_abs_lane_w[10] +
          coeff_abs_lane_w[13] + coeff_abs_lane_w[12];
        loc_num_sig_w = {7'd0, coeff_sig_w[9]} + {7'd0, coeff_sig_w[10]} +
          {7'd0, coeff_sig_w[13]} + {7'd0, coeff_sig_w[12]};
        loc_sum_abs_w = coeff_template_sig_lane_w[9] + coeff_template_sig_lane_w[10] +
          coeff_template_sig_lane_w[13] + coeff_template_sig_lane_w[12];
      end
      5'd4: begin
        rice_sum_abs_w = coeff_abs_lane_w[6] + coeff_abs_lane_w[7] +
          coeff_abs_lane_w[10] + coeff_abs_lane_w[9] + coeff_abs_lane_w[13];
        loc_num_sig_w = {7'd0, coeff_sig_w[6]} + {7'd0, coeff_sig_w[7]} +
          {7'd0, coeff_sig_w[10]} + {7'd0, coeff_sig_w[9]} + {7'd0, coeff_sig_w[13]};
        loc_sum_abs_w = coeff_template_sig_lane_w[6] + coeff_template_sig_lane_w[7] +
          coeff_template_sig_lane_w[10] + coeff_template_sig_lane_w[9] +
          coeff_template_sig_lane_w[13];
      end
      5'd5: begin
        rice_sum_abs_w = coeff_abs_lane_w[3] + coeff_abs_lane_w[7] +
          coeff_abs_lane_w[6] + coeff_abs_lane_w[10];
        loc_num_sig_w = {7'd0, coeff_sig_w[3]} + {7'd0, coeff_sig_w[7]} +
          {7'd0, coeff_sig_w[6]} + {7'd0, coeff_sig_w[10]};
        loc_sum_abs_w = coeff_template_sig_lane_w[3] + coeff_template_sig_lane_w[7] +
          coeff_template_sig_lane_w[6] + coeff_template_sig_lane_w[10];
      end
      5'd6: begin
        rice_sum_abs_w = coeff_abs_lane_w[13] + coeff_abs_lane_w[14];
        loc_num_sig_w = {7'd0, coeff_sig_w[13]} + {7'd0, coeff_sig_w[14]};
        loc_sum_abs_w = coeff_template_sig_lane_w[13] + coeff_template_sig_lane_w[14];
      end
      5'd7: begin
        rice_sum_abs_w = coeff_abs_lane_w[10] + coeff_abs_lane_w[11] +
          coeff_abs_lane_w[14] + coeff_abs_lane_w[13];
        loc_num_sig_w = {7'd0, coeff_sig_w[10]} + {7'd0, coeff_sig_w[11]} +
          {7'd0, coeff_sig_w[14]} + {7'd0, coeff_sig_w[13]};
        loc_sum_abs_w = coeff_template_sig_lane_w[10] + coeff_template_sig_lane_w[11] +
          coeff_template_sig_lane_w[14] + coeff_template_sig_lane_w[13];
      end
      5'd8: begin
        rice_sum_abs_w = coeff_abs_lane_w[7] + coeff_abs_lane_w[11] +
          coeff_abs_lane_w[10] + coeff_abs_lane_w[14];
        loc_num_sig_w = {7'd0, coeff_sig_w[7]} + {7'd0, coeff_sig_w[11]} +
          {7'd0, coeff_sig_w[10]} + {7'd0, coeff_sig_w[14]};
        loc_sum_abs_w = coeff_template_sig_lane_w[7] + coeff_template_sig_lane_w[11] +
          coeff_template_sig_lane_w[10] + coeff_template_sig_lane_w[14];
      end
      5'd9: begin
        rice_sum_abs_w = coeff_abs_lane_w[7] + coeff_abs_lane_w[11];
        loc_num_sig_w = {7'd0, coeff_sig_w[7]} + {7'd0, coeff_sig_w[11]};
        loc_sum_abs_w = coeff_template_sig_lane_w[7] + coeff_template_sig_lane_w[11];
      end
      5'd10: begin
        rice_sum_abs_w = coeff_abs_lane_w[14] + coeff_abs_lane_w[15];
        loc_num_sig_w = {7'd0, coeff_sig_w[14]} + {7'd0, coeff_sig_w[15]};
        loc_sum_abs_w = coeff_template_sig_lane_w[14] + coeff_template_sig_lane_w[15];
      end
      5'd11: begin
        rice_sum_abs_w = coeff_abs_lane_w[11] + coeff_abs_lane_w[15] +
          coeff_abs_lane_w[14];
        loc_num_sig_w = {7'd0, coeff_sig_w[11]} + {7'd0, coeff_sig_w[15]} +
          {7'd0, coeff_sig_w[14]};
        loc_sum_abs_w = coeff_template_sig_lane_w[11] + coeff_template_sig_lane_w[15] +
          coeff_template_sig_lane_w[14];
      end
      5'd12: begin
        rice_sum_abs_w = coeff_abs_lane_w[11] + coeff_abs_lane_w[15];
        loc_num_sig_w = {7'd0, coeff_sig_w[11]} + {7'd0, coeff_sig_w[15]};
        loc_sum_abs_w = coeff_template_sig_lane_w[11] + coeff_template_sig_lane_w[15];
      end
      5'd13: begin
        rice_sum_abs_w = coeff_abs_lane_w[15];
        loc_num_sig_w = {7'd0, coeff_sig_w[15]};
        loc_sum_abs_w = coeff_template_sig_lane_w[15];
      end
      5'd14: begin
        rice_sum_abs_w = coeff_abs_lane_w[15];
        loc_num_sig_w = {7'd0, coeff_sig_w[15]};
        loc_sum_abs_w = coeff_template_sig_lane_w[15];
      end
      default: begin
        loc_sum_abs_w = 9'd0;
        loc_num_sig_w = 8'd0;
        rice_sum_abs_w = 9'd0;
      end
    endcase
  end

  assign last_x_cmax_w = (tb_width_q <= 16'd4) ? 3'd3 :
    ((tb_width_q <= 16'd8) ? 3'd5 : 3'd7);
  assign last_y_cmax_w = (tb_height_q <= 16'd4) ? 3'd3 :
    ((tb_height_q <= 16'd8) ? 3'd5 : 3'd7);
  assign last_x_emit_max_w =
    (mode_q && ({1'b0, last_x_w} >= last_x_cmax_w)) ? (last_x_w - 2'd1) : last_x_w;
  assign last_y_emit_max_w =
    (mode_q && ({1'b0, last_y_w} >= last_y_cmax_w)) ? (last_y_w - 2'd1) : last_y_w;
  assign scan_regular_active_w =
    (scan_pos_q <= last_scan_pos_w) && (!mode_q || (regular_bins_left_q >= 10'd4));
  assign second_active_w = mode_q && ($signed({1'b0, scan_pos_q}) <= min_pos_2nd_pass_q);
  assign sig_needed_w =
    scan_regular_active_q && ((num_nonzero_q != 6'd0) || (scan_pos_q != last_scan_pos_w));
  assign rem_needed_w = mode_q ? (coeff_abs_w > 9'd3) :
    ((scan_raster_w == 5'd0) && (coeff_abs_w > 9'd3));

  always @* begin
    sum_bucket_w = (loc_sum_abs_w[7:0] + 8'd1) >> 1;
    if (sum_bucket_w > 8'd3) begin
      sum_bucket_w = 8'd3;
    end
    if (mode_q) begin
      sig_ctx_w = CTX_SIG_COEFF_FLAG_36 + {2'd0,
        ((8'd36 + sum_bucket_w + ((d_sum_w < 8'd2) ? 8'd4 : 8'd0)) - 8'd36)
      };
    end else begin
      if (d_sum_w < 8'd2) begin
        sig_ctx_w = 10'd8 + {2'd0, sum_bucket_w};
      end else if (d_sum_w < 8'd5) begin
        sig_ctx_w = 10'd4 + {2'd0, sum_bucket_w};
      end else begin
        sig_ctx_w = {2'd0, sum_bucket_w};
      end
      case (sig_ctx_w[7:0])
        8'd0: sig_ctx_w = 10'd118;
        8'd1: sig_ctx_w = CTX_SIG_COEFF_FLAG_1;
        8'd2: sig_ctx_w = 10'd119;
        8'd3: sig_ctx_w = 10'd120;
        8'd4: sig_ctx_w = CTX_SIG_COEFF_FLAG_4;
        8'd5: sig_ctx_w = CTX_SIG_COEFF_FLAG_5;
        8'd6: sig_ctx_w = CTX_SIG_COEFF_FLAG_6;
        8'd7: sig_ctx_w = 10'd121;
        8'd8: sig_ctx_w = 10'd122;
        8'd9: sig_ctx_w = CTX_SIG_COEFF_FLAG_9;
        8'd10: sig_ctx_w = 10'd123;
        8'd11: sig_ctx_w = 10'd124;
        default: sig_ctx_w = 10'd1023;
      endcase
    end
  end

  always @* begin
    ctx_offset_w = loc_sum_abs_w[7:0] - loc_num_sig_w;
    if (ctx_offset_w > 8'd4) begin
      ctx_offset_w = 8'd4;
    end
    if (mode_q) begin
      if ((scan_x_w[1:0] == last_x_w) && (scan_y_w[1:0] == last_y_w)) begin
        level_ctx_inc_w = 10'd21;
      end else begin
        level_ctx_inc_w = 10'd22 + {2'd0, ctx_offset_w} +
          ((d_sum_w == 8'd0) ? 10'd5 : 10'd0);
      end
      if (level_ctx_inc_w[7:0] >= 8'd53) begin
        gt1_ctx_w = CTX_ABS_LEVEL_GTX_FLAG_53 + {2'd0, (level_ctx_inc_w[7:0] - 8'd53)};
      end else begin
        gt1_ctx_w = CTX_ABS_LEVEL_GTX_FLAG_21 + {2'd0, (level_ctx_inc_w[7:0] - 8'd21)};
      end
      par_ctx_w = CTX_PAR_LEVEL_FLAG_21 + {2'd0, (level_ctx_inc_w[7:0] - 8'd21)};
      if ((level_ctx_inc_w[7:0] + 8'd32) >= 8'd53) begin
        gt3_ctx_w = CTX_ABS_LEVEL_GTX_FLAG_53 +
          {2'd0, ((level_ctx_inc_w[7:0] + 8'd32) - 8'd53)};
      end else begin
        gt3_ctx_w = CTX_ABS_LEVEL_GTX_FLAG_21 +
          {2'd0, ((level_ctx_inc_w[7:0] + 8'd32) - 8'd21)};
      end
    end else begin
      if ((scan_x_w[1:0] == last_x_w) && (scan_y_w[1:0] == last_y_w)) begin
        level_ctx_inc_w = 10'd0;
      end else begin
        level_ctx_inc_w = 10'd1 + {2'd0, ctx_offset_w} +
          ((d_sum_w == 8'd0) ? 10'd15 : ((d_sum_w < 8'd3) ? 10'd10 : 10'd5));
      end
      case (level_ctx_inc_w[7:0])
        8'd0: gt1_ctx_w = CTX_ABS_LEVEL_GTX_FLAG_0;
        8'd6: gt1_ctx_w = 10'd137;
        8'd7: gt1_ctx_w = CTX_ABS_LEVEL_GTX_FLAG_7;
        8'd8: gt1_ctx_w = 10'd138;
        8'd9: gt1_ctx_w = 10'd139;
        8'd10: gt1_ctx_w = 10'd140;
        8'd11: gt1_ctx_w = CTX_ABS_LEVEL_GTX_FLAG_11;
        8'd12: gt1_ctx_w = 10'd141;
        8'd13: gt1_ctx_w = CTX_ABS_LEVEL_GTX_FLAG_13;
        8'd14: gt1_ctx_w = 10'd142;
        8'd15: gt1_ctx_w = 10'd143;
        8'd16: gt1_ctx_w = 10'd144;
        8'd17: gt1_ctx_w = 10'd145;
        8'd18: gt1_ctx_w = 10'd146;
        8'd19: gt1_ctx_w = 10'd147;
        8'd20: gt1_ctx_w = 10'd148;
        default: gt1_ctx_w = 10'd1023;
      endcase
      case (level_ctx_inc_w[7:0])
        8'd0: par_ctx_w = CTX_PAR_LEVEL_FLAG_0;
        8'd6: par_ctx_w = 10'd125;
        8'd7: par_ctx_w = CTX_PAR_LEVEL_FLAG_7;
        8'd8: par_ctx_w = 10'd126;
        8'd9: par_ctx_w = 10'd127;
        8'd10: par_ctx_w = 10'd128;
        8'd11: par_ctx_w = CTX_PAR_LEVEL_FLAG_11;
        8'd12: par_ctx_w = 10'd129;
        8'd13: par_ctx_w = CTX_PAR_LEVEL_FLAG_13;
        8'd14: par_ctx_w = 10'd130;
        8'd15: par_ctx_w = 10'd131;
        8'd16: par_ctx_w = 10'd132;
        8'd17: par_ctx_w = 10'd133;
        8'd18: par_ctx_w = 10'd134;
        8'd19: par_ctx_w = 10'd135;
        8'd20: par_ctx_w = 10'd136;
        default: par_ctx_w = 10'd1023;
      endcase
      if ((scan_x_w[1:0] == last_x_w) && (scan_y_w[1:0] == last_y_w)) begin
        level_ctx_inc_w = 10'd32;
      end else begin
        level_ctx_inc_w = 10'd33 + {2'd0, ctx_offset_w} +
          ((d_sum_w == 8'd0) ? 10'd15 : ((d_sum_w < 8'd3) ? 10'd10 : 10'd5));
      end
      case (level_ctx_inc_w[7:0])
        8'd32: gt3_ctx_w = CTX_ABS_LEVEL_GTX_FLAG_32;
        8'd38: gt3_ctx_w = 10'd149;
        8'd39: gt3_ctx_w = CTX_ABS_LEVEL_GTX_FLAG_39;
        8'd40: gt3_ctx_w = 10'd150;
        8'd41: gt3_ctx_w = 10'd151;
        8'd42: gt3_ctx_w = 10'd152;
        8'd43: gt3_ctx_w = CTX_ABS_LEVEL_GTX_FLAG_43;
        8'd44: gt3_ctx_w = 10'd153;
        8'd45: gt3_ctx_w = CTX_ABS_LEVEL_GTX_FLAG_45;
        8'd46: gt3_ctx_w = 10'd154;
        8'd47: gt3_ctx_w = 10'd155;
        8'd48: gt3_ctx_w = 10'd156;
        8'd49: gt3_ctx_w = 10'd157;
        8'd50: gt3_ctx_w = 10'd158;
        8'd51: gt3_ctx_w = 10'd159;
        8'd52: gt3_ctx_w = 10'd160;
        default: gt3_ctx_w = 10'd1023;
      endcase
    end
  end

  always @* begin
    sum_abs_for_rice_w = 9'd0;
    rice_param_w = 3'd0;
    bypass_zero_pos_w = 9'd0;
    bypass_value_w = 9'd0;
    rem_threshold_w = 9'd0;
    rem_abs_value_w = 9'd0;
    rem_code_value_w = 9'd0;
    rem_prefix_value_w = 9'd0;
    rem_prefix_extra_len_w = 3'd0;
    rem_prefix_count_w = 6'd0;
    rem_prefix_pattern_w = 32'd0;
    rem_suffix_count_w = 6'd0;
    rem_suffix_pattern_w = 32'd0;
    prefix_len_i = 0;
    if (mode_q && (state_q == ST_SECOND)) begin
      sum_abs_for_rice_w = rice_sum_abs_w;
      if (sum_abs_for_rice_w <= 9'd6) begin
        rice_param_w = 3'd0;
      end else if (sum_abs_for_rice_w <= 9'd13) begin
        rice_param_w = 3'd1;
      end else if (sum_abs_for_rice_w <= 9'd27) begin
        rice_param_w = 3'd2;
      end else begin
        rice_param_w = 3'd3;
      end
      bypass_zero_pos_w = 9'd1 << rice_param_w;
      if (coeff_abs_w == 9'd0) begin
        bypass_value_w = bypass_zero_pos_w;
      end else if (coeff_abs_w <= bypass_zero_pos_w) begin
        bypass_value_w = coeff_abs_w - 9'd1;
      end else begin
        bypass_value_w = coeff_abs_w;
      end
      rem_threshold_w = 9'd5 << rice_param_w;
      if (bypass_value_w < rem_threshold_w) begin
        rem_prefix_value_w = bypass_value_w >> rice_param_w;
        rem_prefix_extra_len_w = 3'd0;
        rem_prefix_count_w = {1'b0, rem_prefix_value_w[4:0]} + 6'd1;
        rem_prefix_pattern_w = (32'd1 << rem_prefix_count_w) - 32'd2;
        rem_suffix_count_w = {3'd0, rice_param_w};
        rem_suffix_pattern_w = bypass_value_w & ((32'd1 << rice_param_w) - 32'd1);
      end else begin
        rem_code_value_w = (bypass_value_w >> rice_param_w) - 9'd5;
        rem_prefix_extra_len_w = 3'd0;
        for (prefix_len_i = 0; prefix_len_i < 7; prefix_len_i = prefix_len_i + 1) begin
          if (rem_code_value_w > ((9'd2 << prefix_len_i) - 9'd2)) begin
            rem_prefix_extra_len_w = prefix_len_i[2:0] + 3'd1;
          end
        end
        rem_prefix_value_w = 9'd0;
        rem_prefix_count_w = {3'd0, rem_prefix_extra_len_w} + 6'd5;
        rem_prefix_pattern_w = (32'd1 << rem_prefix_count_w) - 32'd1;
        rem_suffix_count_w =
          {3'd0, rem_prefix_extra_len_w} + {3'd0, rice_param_w} + 6'd1;
        rem_suffix_pattern_w =
          ((rem_code_value_w - ((32'd1 << rem_prefix_extra_len_w) - 32'd1)) << rice_param_w) |
          (bypass_value_w & ((32'd1 << rice_param_w) - 32'd1));
      end
      rem_abs_value_w = 9'd0;
    end else begin
      rem_abs_value_w = (coeff_abs_w - 9'd4) >> 1;
      rem_code_value_w = rem_abs_value_w - 9'd5;
      rem_prefix_extra_len_w = 3'd0;
      if (mode_q) begin
        for (prefix_len_i = 0; prefix_len_i < 7; prefix_len_i = prefix_len_i + 1) begin
          if (rem_code_value_w > ((9'd2 << prefix_len_i) - 9'd2)) begin
            rem_prefix_extra_len_w = prefix_len_i[2:0] + 3'd1;
          end
        end
      end else begin
        rem_prefix_extra_len_w =
          (rem_code_value_w <= 9'd0) ? 3'd0 :
          ((rem_code_value_w <= 9'd2) ? 3'd1 :
          ((rem_code_value_w <= 9'd6) ? 3'd2 : 3'd3));
      end
      rem_prefix_count_w =
        (rem_abs_value_w < 9'd5) ? {1'b0, rem_abs_value_w[4:0] + 5'd1} :
        {3'd0, rem_prefix_extra_len_w} + 6'd5;
      rem_prefix_pattern_w =
        (rem_abs_value_w < 9'd5) ?
        ((32'd1 << rem_prefix_count_w) - 32'd2) :
        ((32'd1 << rem_prefix_count_w) - 32'd1);
      rem_suffix_count_w =
        (rem_abs_value_w < 9'd5) ? 6'd0 : {3'd0, rem_prefix_extra_len_w} + 6'd1;
      rem_suffix_pattern_w =
        (rem_abs_value_w < 9'd5) ? 32'd0 :
        (rem_code_value_w - ((32'd1 << rem_prefix_extra_len_w) - 32'd1));
    end
  end

  always @* begin
    m_axis_valid = 1'b0;
    m_axis_kind = 8'd0;
    m_axis_data = 32'd0;
    case (state_q)
      ST_LAST_X: begin
        m_axis_valid = 1'b1;
        m_axis_kind = SYMBOL_BIN_CTX;
        if (mode_q) begin
          m_axis_data = {
            14'd0,
            (CTX_LAST_SIG_X_PREFIX_20 + {7'd0,
              ((tb_width_q <= 16'd4) ? bin_idx_q :
              ((tb_width_q <= 16'd8) ? {1'b0, bin_idx_q[1]} : 2'd0)), 1'b0}),
            7'd0,
            (bin_idx_q < last_x_w)
          };
        end else begin
          m_axis_data = {
            14'd0,
            ((bin_idx_q < 2'd2) ? CTX_LAST_SIG_X_PREFIX_3 : CTX_LAST_SIG_X_PREFIX_4),
            7'd0,
            (bin_idx_q < last_x_w)
          };
        end
      end
      ST_LAST_Y: begin
        m_axis_valid = 1'b1;
        m_axis_kind = SYMBOL_BIN_CTX;
        if (mode_q) begin
          m_axis_data = {
            14'd0,
            (CTX_LAST_SIG_Y_PREFIX_20 + {7'd0,
              ((tb_height_q <= 16'd4) ? bin_idx_q :
              ((tb_height_q <= 16'd8) ? {1'b0, bin_idx_q[1]} : 2'd0)), 1'b0}),
            7'd0,
            (bin_idx_q < last_y_w)
          };
        end else begin
          m_axis_data = {
            14'd0,
            ((bin_idx_q < 2'd2) ? CTX_LAST_SIG_Y_PREFIX_3 : CTX_LAST_SIG_Y_PREFIX_4),
            7'd0,
            (bin_idx_q < last_y_w)
          };
        end
      end
      ST_SCAN: begin
        case (subphase_q)
          SUB_SIG: begin
            if (sig_needed_w) begin
              m_axis_valid = 1'b1;
              m_axis_kind = SYMBOL_BIN_CTX;
              m_axis_data = {14'd0, sig_ctx_w, 7'd0, (coeff_abs_w != 9'd0)};
            end
          end
          SUB_GT1: begin
            if (scan_regular_active_q && (coeff_abs_w != 9'd0)) begin
              m_axis_valid = 1'b1;
              m_axis_kind = SYMBOL_BIN_CTX;
              m_axis_data = {14'd0, gt1_ctx_w, 7'd0, (coeff_abs_w > 9'd1)};
            end
          end
          SUB_PAR: begin
            if (scan_regular_active_q && (coeff_abs_w > 9'd1)) begin
              m_axis_valid = 1'b1;
              m_axis_kind = SYMBOL_BIN_CTX;
              m_axis_data = {14'd0, par_ctx_w, 7'd0, coeff_abs_w[0]};
            end
          end
          SUB_GT3: begin
            if (scan_regular_active_q && (coeff_abs_w > 9'd1)) begin
              m_axis_valid = 1'b1;
              m_axis_kind = SYMBOL_BIN_CTX;
              m_axis_data = {14'd0, gt3_ctx_w, 7'd0, (coeff_abs_w > 9'd3)};
            end
          end
          SUB_REM_PREFIX: begin
            if (scan_regular_active_q && rem_emit_needed_q) begin
              m_axis_valid = 1'b1;
              m_axis_kind = SYMBOL_BINS_EP;
              m_axis_data = (rem_prefix_pattern_q << 6) | {26'd0, rem_prefix_count_q};
            end
          end
          SUB_REM_SUFFIX: begin
            if (scan_regular_active_q && rem_emit_needed_q) begin
              m_axis_valid = 1'b1;
              m_axis_kind = SYMBOL_BINS_EP;
              m_axis_data = (rem_suffix_pattern_q << 6) | {26'd0, rem_suffix_count_q};
            end
          end
          default: begin
            m_axis_valid = 1'b0;
          end
        endcase
      end
      ST_SECOND: begin
        if (second_active_w) begin
          if (subphase_q == SUB_REM_PREFIX) begin
            m_axis_valid = 1'b1;
            m_axis_kind = SYMBOL_BINS_EP;
            m_axis_data = (rem_prefix_pattern_q << 6) | {26'd0, rem_prefix_count_q};
          end else if (subphase_q == SUB_REM_SUFFIX) begin
            m_axis_valid = 1'b1;
            m_axis_kind = SYMBOL_BINS_EP;
            m_axis_data = (rem_suffix_pattern_q << 6) | {26'd0, rem_suffix_count_q};
          end
        end
      end
      ST_SIGN: begin
        if (sign_count_q != 6'd0) begin
          m_axis_valid = 1'b1;
          m_axis_kind = SYMBOL_BINS_EP;
          m_axis_data = (sign_bits_q << 6) | {26'd0, sign_count_q};
        end
      end
      default: begin
        m_axis_valid = 1'b0;
      end
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_IDLE;
      mode_q <= 1'b0;
      tb_width_q <= 16'd0;
      tb_height_q <= 16'd0;
      coeff_abs_q <= {(9 * 16){1'b0}};
      coeff_template_abs_q <= {(9 * 16){1'b0}};
      coeff_negative_q <= 16'd0;
      bin_idx_q <= 2'd0;
      scan_pos_q <= 5'd0;
      subphase_q <= SUB_SIG;
      sign_bits_q <= 32'd0;
      sign_count_q <= 6'd0;
      num_nonzero_q <= 6'd0;
      regular_bins_left_q <= 10'd0;
      scan_regular_active_q <= 1'b0;
      min_pos_2nd_pass_q <= -6'sd1;
      rem_prefix_count_q <= 6'd0;
      rem_prefix_pattern_q <= 32'd0;
      rem_suffix_count_q <= 6'd0;
      rem_suffix_pattern_q <= 32'd0;
      rem_emit_needed_q <= 1'b0;
      done <= 1'b0;
    end else if (clear) begin
      state_q <= ST_IDLE;
      bin_idx_q <= 2'd0;
      scan_pos_q <= 5'd0;
      subphase_q <= SUB_SIG;
      sign_bits_q <= 32'd0;
      sign_count_q <= 6'd0;
      num_nonzero_q <= 6'd0;
      regular_bins_left_q <= 10'd0;
      scan_regular_active_q <= 1'b0;
      min_pos_2nd_pass_q <= -6'sd1;
      rem_prefix_count_q <= 6'd0;
      rem_prefix_pattern_q <= 32'd0;
      rem_suffix_count_q <= 6'd0;
      rem_suffix_pattern_q <= 32'd0;
      rem_emit_needed_q <= 1'b0;
      done <= 1'b0;
    end else begin
      if (state_q == ST_IDLE) begin
        if (start) begin
          done <= 1'b0;
          mode_q <= chroma_mode;
          tb_width_q <= tb_width;
          tb_height_q <= tb_height;
          coeff_abs_q <= load_coeff_abs;
          coeff_template_abs_q <= load_coeff_template_abs;
          coeff_negative_q <= load_coeff_negative;
          bin_idx_q <= 2'd0;
          scan_pos_q <= 5'd15;
          subphase_q <= SUB_SIG;
          sign_bits_q <= 32'd0;
          sign_count_q <= 6'd0;
          num_nonzero_q <= 6'd0;
          regular_bins_left_q <= chroma_mode ?
            (({16'd0, tb_width} * {16'd0, tb_height} * 32'd28) >> 4) :
            10'd112;
          scan_regular_active_q <= 1'b0;
          min_pos_2nd_pass_q <= -6'sd1;
          rem_prefix_count_q <= 6'd0;
          rem_prefix_pattern_q <= 32'd0;
          rem_suffix_count_q <= 6'd0;
          rem_suffix_pattern_q <= 32'd0;
          rem_emit_needed_q <= 1'b0;
          if (load_has_coeff) begin
            state_q <= ST_LAST_X;
          end else begin
            done <= 1'b1;
          end
        end
      end else if (!m_axis_valid || m_axis_ready) begin
        case (state_q)
          ST_LAST_X: begin
            if (bin_idx_q >= last_x_emit_max_w) begin
              bin_idx_q <= 2'd0;
              state_q <= ST_LAST_Y;
            end else begin
              bin_idx_q <= bin_idx_q + 2'd1;
            end
          end

          ST_LAST_Y: begin
            if (bin_idx_q >= last_y_emit_max_w) begin
              bin_idx_q <= 2'd0;
              scan_pos_q <= 5'd15;
              subphase_q <= SUB_SIG;
              scan_regular_active_q <=
                (5'd15 <= last_scan_pos_w) && (!mode_q || (regular_bins_left_q >= 10'd4));
              state_q <= ST_SCAN;
            end else begin
              bin_idx_q <= bin_idx_q + 2'd1;
            end
          end

          ST_SCAN: begin
            if (!scan_regular_active_q) begin
              if (scan_pos_q == 5'd0) begin
                scan_pos_q <= 5'd15;
                subphase_q <= SUB_REM_PREP;
                scan_regular_active_q <= 1'b0;
                state_q <= (mode_q && (min_pos_2nd_pass_q >= 0)) ? ST_SECOND : ST_SIGN;
              end else if (mode_q && (regular_bins_left_q < 10'd4) &&
                           (scan_pos_q <= last_scan_pos_w)) begin
                scan_pos_q <= 5'd15;
                subphase_q <= SUB_REM_PREP;
                scan_regular_active_q <= 1'b0;
                state_q <= (min_pos_2nd_pass_q >= 0) ? ST_SECOND : ST_SIGN;
              end else begin
                scan_pos_q <= scan_pos_q - 5'd1;
                subphase_q <= SUB_SIG;
                scan_regular_active_q <=
                  ((scan_pos_q - 5'd1) <= last_scan_pos_w) &&
                  (!mode_q || (regular_bins_left_q >= 10'd4));
              end
            end else begin
              case (subphase_q)
                SUB_SIG: begin
                  if (mode_q) begin
                    min_pos_2nd_pass_q <= $signed({1'b0, scan_pos_q}) - 6'sd1;
                  end
                  if (sig_needed_w && (regular_bins_left_q != 10'd0)) begin
                    regular_bins_left_q <= regular_bins_left_q - 10'd1;
                  end
                  subphase_q <= SUB_GT1;
                end
                SUB_GT1: begin
                  if ((coeff_abs_w != 9'd0) && (regular_bins_left_q != 10'd0)) begin
                    regular_bins_left_q <= regular_bins_left_q - 10'd1;
                  end
                  subphase_q <= SUB_PAR;
                end
                SUB_PAR: begin
                  if ((coeff_abs_w > 9'd1) && (regular_bins_left_q != 10'd0)) begin
                    regular_bins_left_q <= regular_bins_left_q - 10'd1;
                  end
                  subphase_q <= SUB_GT3;
                end
                SUB_GT3: begin
                  if ((coeff_abs_w > 9'd1) && (regular_bins_left_q != 10'd0)) begin
                    regular_bins_left_q <= regular_bins_left_q - 10'd1;
                  end
                  rem_emit_needed_q <= rem_needed_w;
                  rem_prefix_count_q <= rem_prefix_count_w;
                  rem_prefix_pattern_q <= rem_prefix_pattern_w;
                  rem_suffix_count_q <= rem_suffix_count_w;
                  rem_suffix_pattern_q <= rem_suffix_pattern_w;
                  subphase_q <= rem_needed_w ? SUB_REM_PREFIX : SUB_SIGN_ACCUM;
                end
                SUB_REM_PREFIX: begin
                  subphase_q <= SUB_REM_SUFFIX;
                end
                SUB_REM_SUFFIX: begin
                  subphase_q <= SUB_SIGN_ACCUM;
                end
                default: begin
                  if (coeff_abs_w != 9'd0) begin
                    if (sign_count_q != 6'd0) begin
                      sign_bits_q <= (sign_bits_q << 1) | {31'd0, coeff_negative_w};
                    end else begin
                      sign_bits_q <= {31'd0, coeff_negative_w};
                    end
                    sign_count_q <= sign_count_q + 6'd1;
                    num_nonzero_q <= num_nonzero_q + 6'd1;
                  end
                  if (scan_pos_q == 5'd0) begin
                    scan_pos_q <= 5'd15;
                    subphase_q <= SUB_REM_PREP;
                    scan_regular_active_q <= 1'b0;
                    state_q <= (mode_q && (min_pos_2nd_pass_q >= 0)) ? ST_SECOND : ST_SIGN;
                  end else begin
                    scan_pos_q <= scan_pos_q - 5'd1;
                    subphase_q <= SUB_SIG;
                    scan_regular_active_q <=
                      ((scan_pos_q - 5'd1) <= last_scan_pos_w) &&
                      (!mode_q || (regular_bins_left_q >= 10'd4));
                  end
                end
              endcase
            end
          end

          ST_SECOND: begin
            if (!second_active_w) begin
              if (scan_pos_q == 5'd0) begin
                state_q <= ST_SIGN;
              end else begin
                scan_pos_q <= scan_pos_q - 5'd1;
                subphase_q <= SUB_REM_PREP;
              end
            end else if (subphase_q == SUB_REM_PREP) begin
              rem_emit_needed_q <= 1'b1;
              rem_prefix_count_q <= rem_prefix_count_w;
              rem_prefix_pattern_q <= rem_prefix_pattern_w;
              rem_suffix_count_q <= rem_suffix_count_w;
              rem_suffix_pattern_q <= rem_suffix_pattern_w;
              subphase_q <= SUB_REM_PREFIX;
            end else if (subphase_q == SUB_REM_PREFIX) begin
              subphase_q <= SUB_REM_SUFFIX;
            end else if (subphase_q == SUB_REM_SUFFIX) begin
              subphase_q <= SUB_SIGN_ACCUM;
            end else begin
              if (coeff_abs_w != 9'd0) begin
                if (sign_count_q != 6'd0) begin
                  sign_bits_q <= (sign_bits_q << 1) | {31'd0, coeff_negative_w};
                end else begin
                  sign_bits_q <= {31'd0, coeff_negative_w};
                end
                sign_count_q <= sign_count_q + 6'd1;
              end
              if (scan_pos_q == 5'd0) begin
                state_q <= ST_SIGN;
              end else begin
                scan_pos_q <= scan_pos_q - 5'd1;
                subphase_q <= SUB_REM_PREP;
              end
            end
          end

          ST_SIGN: begin
            state_q <= ST_IDLE;
            done <= 1'b1;
          end

          default: begin
            state_q <= ST_IDLE;
          end
        endcase
      end
    end
  end
endmodule
