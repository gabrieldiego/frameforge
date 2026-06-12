`timescale 1ns/1ps

module ff_vvc_ctu_symbolizer #(
  parameter int CTU_SIZE = 64,
  parameter int LUMA_TUS_PER_CTU = (CTU_SIZE / 8) * (CTU_SIZE / 8),
  parameter int CHROMA_TUS_PER_CTU = LUMA_TUS_PER_CTU
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        clear,
  input  logic        start,
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,
  input  logic [1:0]  chroma_format_idc,
  input  logic [(8 * LUMA_TUS_PER_CTU) - 1:0] luma_abs_levels,
  input  logic [LUMA_TUS_PER_CTU - 1:0] luma_negative,
  input  logic [(4 * 15 * LUMA_TUS_PER_CTU) - 1:0] luma_ac_levels,
  input  logic [(9 * CHROMA_TUS_PER_CTU) - 1:0] cb_dc_levels,
  input  logic [(9 * CHROMA_TUS_PER_CTU) - 1:0] cr_dc_levels,
  input  logic [(4 * 3 * CHROMA_TUS_PER_CTU) - 1:0] cb_ac_levels,
  input  logic [(4 * 3 * CHROMA_TUS_PER_CTU) - 1:0] cr_ac_levels,
  input  logic [2:0]  luma_log2_tb_width,
  input  logic [2:0]  luma_log2_tb_height,
  input  logic        sps_mrl_enabled_flag,
  input  logic        sps_cclm_enabled_flag,
  input  logic        palette_partition_mode,

  output logic        m_axis_valid,
  input  logic        m_axis_ready,
  output logic [7:0]  m_axis_kind,
  output logic [31:0] m_axis_data,
  output logic        m_axis_last,
  output logic        busy
);
  localparam logic [7:0] SYMBOL_BIN_EP  = 8'd0;
  localparam logic [7:0] SYMBOL_BIN_TRM = 8'd1;
  localparam logic [7:0] SYMBOL_BIN_CTX = 8'd2;
  localparam logic [7:0] SYMBOL_BINS_EP = 8'd4;
  localparam logic [7:0] SYMBOL_PALETTE_LEAF = 8'hfe;

  localparam logic [15:0] CTU_SIZE_L = CTU_SIZE;
  localparam logic [15:0] MIN_CODING_BLOCK_SIZE = 16'd4;
  localparam logic [15:0] MAX_TB_SIZEY = 16'd64;
  localparam logic [15:0] MIN_DUALTREE_CHROMA_WIDTH = 16'd4;
  localparam logic [15:0] MIN_DUALTREE_CHROMA_AREA = 16'd16;
  localparam logic [15:0] LUMA_MAX_LEAF_SIZE = 16'd8;
  localparam logic [15:0] LUMA_BOUNDARY_BT_SIZE = LUMA_MAX_LEAF_SIZE << 2;
  // Current residual subset: H.266 7.3.11.10 transform_unit() is only reached
  // for 8x8 luma-coordinate leaves. In 4:2:0 that is a fixed 4x4 chroma TB.
  // Larger legal VVC chroma TBs are intentionally not synthesized yet.
  localparam logic [15:0] CHROMA_MAX_LEAF_SIZE = 16'd4;
  localparam logic [15:0] CHROMA_MAX_BT_SIZE_LUMA = 16'd64;
  localparam logic [15:0] CHROMA_MAX_TT_SIZE_LUMA = 16'd32;
  localparam logic [15:0] CHROMA_BOUNDARY_LEAF_SIZE = CHROMA_MAX_BT_SIZE_LUMA >> 1;
  localparam logic [15:0] CHROMA_ROOT_SIZE = CTU_SIZE_L >> 1;
  localparam logic [15:0] DUAL_TREE_CHROMA_LUMA_CU_SIZE = 16'd32;
  localparam logic [15:0] DUAL_TREE_CHROMA_CU_SIZE = DUAL_TREE_CHROMA_LUMA_CU_SIZE >> 1;
  localparam logic [15:0] LUMA_MIN_QT_SIZE = 16'd8;
  localparam logic [15:0] CHROMA_MIN_QT_SIZE = 16'd4;
  // Fixed 64->8 luma and 32->4 chroma traversal reaches at most ten pending
  // siblings under depth-first QT splitting. Keep a small margin without
  // synthesizing a wider stack mux than this subset can use.
  localparam int STACK_DEPTH = 16;
  localparam int LUMA_NEIGHBOUR_GRID = CTU_SIZE / 8;
  localparam int LUMA_NEIGHBOUR_CELLS = LUMA_NEIGHBOUR_GRID * LUMA_NEIGHBOUR_GRID;
  localparam int CHROMA_NEIGHBOUR_GRID = CTU_SIZE / 8;
  localparam int CHROMA_NEIGHBOUR_CELLS = CHROMA_NEIGHBOUR_GRID * CHROMA_NEIGHBOUR_GRID;

  `include "ff_vvc_cabac_context_ids.svh"

  // H.266 7.3.11.11 residual_coding() can emit significance, parity/greater-than,
  // bypass suffix, and sign bins for each non-zero coefficient in a coefficient
  // group. The current fixed first-4x4 group path is bounded below 96 symbols;
  // keep the queue at that synthesis-visible limit instead of a generic TU size.
  localparam int LUMA_RESIDUAL_SYMBOL_MAX = 96;
  localparam int CHROMA_RESIDUAL_SYMBOL_MAX = 96;

  localparam logic [4:0] ST_IDLE = 5'd0;
  localparam logic [4:0] ST_POP = 5'd1;
  localparam logic [4:0] ST_DISPATCH = 5'd2;
  localparam logic [4:0] ST_SPLIT_FLAG = 5'd3;
  localparam logic [4:0] ST_SPLIT_QT = 5'd4;
  localparam logic [4:0] ST_SPLIT_MTT = 5'd5;
  localparam logic [4:0] ST_SPLIT_BIN = 5'd6;
  localparam logic [4:0] ST_SPLIT_PUSH = 5'd7;
  localparam logic [4:0] ST_LUMA_SPLIT = 5'd8;
  localparam logic [4:0] ST_LUMA_MRL = 5'd9;
  localparam logic [4:0] ST_LUMA_MPM = 5'd10;
  localparam logic [4:0] ST_LUMA_MODE = 5'd11;
  localparam logic [4:0] ST_LUMA_CBF = 5'd12;
  localparam logic [4:0] ST_LUMA_RESIDUAL = 5'd13;
  localparam logic [4:0] ST_CHROMA_SPLIT = 5'd14;
  localparam logic [4:0] ST_CHROMA_CCLM = 5'd15;
  localparam logic [4:0] ST_CHROMA_MODE = 5'd16;
  localparam logic [4:0] ST_CHROMA_CBF_CB = 5'd17;
  localparam logic [4:0] ST_CHROMA_CBF_CR = 5'd18;
  localparam logic [4:0] ST_CHROMA_RESIDUAL = 5'd19;
  localparam logic [4:0] ST_DONE = 5'd20;
  localparam logic [4:0] ST_PALETTE_LEAF = 5'd21;
  localparam logic [4:0] ST_LUMA_MPM_IDX = 5'd22;
  localparam logic [4:0] ST_CLEAR_NEIGHBOURS = 5'd23;

  logic [4:0] state_q;
  logic [5:0] stack_count_q;
  // H.266 7.3.11.4 coding_tree() traversal is still stack based. In this
  // fixed 8x8 luma / 4x4 chroma subset, positions are multiples of 4 samples
  // and CU sizes are powers of two from 4..64. Store that normalized form so
  // synthesis does not build wide generic muxes for 16-bit stack fields.
  logic [STACK_DEPTH - 1:0][3:0] stack_x4;
  logic [STACK_DEPTH - 1:0][3:0] stack_y4;
  logic [STACK_DEPTH - 1:0][2:0] stack_w_log2;
  logic [STACK_DEPTH - 1:0][2:0] stack_h_log2;
  logic [STACK_DEPTH - 1:0][2:0] stack_cqt;
  logic [STACK_DEPTH - 1:0][2:0] stack_mtt;
  logic [STACK_DEPTH - 1:0][2:0] stack_implicit_mtt;
  logic [STACK_DEPTH - 1:0] stack_chroma;

  // H.266 9.3.4.2.2 split contexts use coded left/above CU state. With fixed
  // 8x8 luma and 4x4 chroma leaves, coded neighbour dimensions are constants,
  // so each map entry only stores qtDepth+1; zero means invalid/unavailable.
  localparam logic [2:0] LUMA_NEIGHBOUR_SIZE_LOG2 = 3'd3;
  localparam logic [2:0] CHROMA_NEIGHBOUR_SIZE_LOG2 = 3'd2;
  logic [2:0] luma_neighbour_depth_p1 [0:LUMA_NEIGHBOUR_CELLS - 1];
  logic [2:0] chroma_neighbour_depth_p1 [0:CHROMA_NEIGHBOUR_CELLS - 1];
  logic [5:0] neighbour_clear_index_q;
  logic [5:0] cur_grid_x;
  logic [5:0] cur_grid_y;
  logic [5:0] cur_grid_index;
  logic [5:0] cur_left_grid_index;
  logic [5:0] cur_above_grid_index;
  logic cur_luma_left_valid;
  logic cur_luma_above_valid;
  logic [2:0] cur_luma_left_depth_p1;
  logic [2:0] cur_luma_left_qt_depth;
  logic [2:0] cur_luma_above_depth_p1;
  logic [2:0] cur_luma_above_qt_depth;
  logic [5:0] cur_chroma_grid_x;
  logic [5:0] cur_chroma_grid_y;
  logic [5:0] cur_chroma_grid_index;
  logic [5:0] cur_chroma_left_grid_index;
  logic [5:0] cur_chroma_above_grid_index;
  logic cur_chroma_left_valid;
  logic cur_chroma_above_valid;
  logic [2:0] cur_chroma_left_depth_p1;
  logic [2:0] cur_chroma_left_qt_depth;
  logic [2:0] cur_chroma_above_depth_p1;
  logic [2:0] cur_chroma_above_qt_depth;

  logic [15:0] cur_x_q;
  logic [15:0] cur_y_q;
  logic [15:0] cur_w_q;
  logic [15:0] cur_h_q;
  logic [2:0] cur_w_log2_q;
  logic [2:0] cur_h_log2_q;
  logic [2:0] cur_cqt_q;
  logic [2:0] cur_mtt_q;
  logic [2:0] cur_implicit_mtt_q;
  logic cur_chroma_q;
  logic chroma_started_q;
  logic [5:0] chroma_tu_index_q;

  logic split_is_qt_q;
  logic split_vertical_q;
  logic split_chroma_q;
  logic split_implicit_q;
  logic [15:0] split_x_q;
  logic [15:0] split_y_q;
  logic [15:0] split_w_q;
  logic [15:0] split_h_q;
  logic [2:0] split_cqt_q;
  logic [2:0] split_mtt_q;
  logic [9:0] split_ctx_q;
  logic split_write_split_q;
  logic [9:0] split_qt_ctx_q;
  logic split_qt_bin_q;
  logic split_write_qt_q;
  logic split_write_mtt_q;
  logic [9:0] split_mtt_ctx_q;
  logic split_write_binary_q;
  logic [9:0] split_binary_ctx_q;
  logic [1:0] split_push_phase_q;
  logic [3:0] stack_pop_index;
  logic [2:0] stack_pop_w_log2;
  logic [2:0] stack_pop_h_log2;
  logic [15:0] stack_pop_w;
  logic [15:0] stack_pop_h;
  logic [2:0] split_w_log2_w;
  logic [2:0] split_h_log2_w;
  logic [3:0] split_x4_w;
  logic [3:0] split_y4_w;
  logic [3:0] split_half_w4_w;
  logic [3:0] split_half_h4_w;

  logic leaf_cbf_q;
  logic chroma_cbf_cb_q;
  logic chroma_cbf_cr_q;
  logic chroma_res_cr_q;
  logic residual_emitter_start_q;
  logic residual_axis_valid;
  logic residual_axis_ready;
  logic [7:0] residual_axis_kind;
  logic [31:0] residual_axis_data;
  logic residual_emitter_done;
  logic residual_emitter_busy;
  logic [7:0] residual_step_q;
  logic [5:0] cur_luma_tu_index;
  logic [7:0] selected_luma_abs_level_w;
  logic       selected_luma_negative_w;
  logic [(4 * 15) - 1:0] selected_luma_ac_levels_w;
  logic [7:0] cur_luma_abs_level;
  logic       cur_luma_negative;
  logic [(4 * 15) - 1:0] cur_luma_ac_levels;
  logic [7:0] rem_abs_value;
  logic [7:0] rem_code_value;
  logic [2:0] rem_prefix_extra_len;
  logic [5:0] rem_prefix_count;
  logic [31:0] rem_prefix_pattern;
  logic [5:0] rem_suffix_count;
  logic [31:0] rem_suffix_pattern;
  logic [9:0] cur_leaf_split_ctx;
  logic cur_leaf_writes_split;
  logic [15:0] cur_visible_width;
  logic [15:0] cur_visible_height;
  logic [15:0] cur_leaf_max;
  logic [15:0] cur_boundary_leaf_max;
  logic [15:0] cur_min_qt_size;
  logic cur_leaf_allowed;
  logic cur_chroma_cclm_allowed;
  logic cur_qt_flag_can_be_signaled;
  logic cur_qt_left_deeper;
  logic cur_qt_above_deeper;
  logic [2:0] cur_qt_ctx_inc;
  logic [9:0] cur_split_qt_ctx;
  logic [16:0] cur_right;
  logic [16:0] cur_bottom;
  logic cur_intersects;
  logic cur_fits;
  logic cur_bottom_left_in_pic;
  logic cur_top_right_in_pic;
  logic cur_implicit_bt_allowed;
  logic fits_split_vertical;
  logic [1:0] cur_mtt_horizontal_alternatives;
  logic [1:0] cur_mtt_vertical_alternatives;
  logic [3:0] cur_mtt_dep_above;
  logic [3:0] cur_mtt_dep_left;
  logic [3:0] cur_mtt_dep_above_log2_delta;
  logic [3:0] cur_mtt_dep_left_log2_delta;
  logic [9:0] cur_mtt_vertical_ctx;
  logic cur_mtt_write_vertical;
  logic cur_mtt_write_binary;
  logic [9:0] cur_mtt_binary_ctx;
  logic cur_chroma_fits_split_vertical;
  logic [1:0] cur_chroma_mtt_horizontal_alternatives;
  logic [1:0] cur_chroma_mtt_vertical_alternatives;
  logic [3:0] cur_chroma_mtt_dep_above;
  logic [3:0] cur_chroma_mtt_dep_left;
  logic [3:0] cur_chroma_mtt_dep_above_log2_delta;
  logic [3:0] cur_chroma_mtt_dep_left_log2_delta;
  logic [9:0] cur_chroma_mtt_vertical_ctx;
  logic cur_chroma_mtt_write_vertical;
  logic cur_chroma_mtt_write_binary;
  logic [9:0] cur_chroma_mtt_binary_ctx;
  logic cur_luma_can_qt;
  logic cur_luma_can_btt;
  logic [3:0] cur_luma_max_btt_depth;
  logic cur_luma_exceeds_bt_size;
  logic cur_luma_can_bh;
  logic cur_luma_can_bv;
  logic cur_luma_can_th;
  logic cur_luma_can_tv;
  logic [3:0] cur_luma_split_alternatives;
  logic [1:0] cur_luma_split_neighbour_ctx;
  logic [3:0] cur_luma_split_ctx_inc;
  logic [9:0] cur_luma_split_ctx;
  logic cur_luma_writes_split;
  logic [15:0] cur_chroma_luma_width;
  logic [15:0] cur_chroma_luma_height;
  logic cur_chroma_area_gt_min;
  logic cur_chroma_area_gt_min2;
  logic dual_tree_chroma_enabled;
  logic cur_chroma_can_qt;
  logic cur_chroma_can_btt;
  logic [3:0] cur_chroma_max_btt_depth;
  logic cur_chroma_exceeds_bt_size;
  logic cur_chroma_can_bh;
  logic cur_chroma_can_bv;
  logic cur_chroma_can_th;
  logic cur_chroma_can_tv;
  logic [3:0] cur_chroma_split_alternatives;
  logic [1:0] cur_chroma_split_neighbour_ctx;
  logic [3:0] cur_chroma_split_ctx_inc;
  logic [9:0] cur_chroma_split_ctx;
  logic cur_chroma_writes_split;
  logic signed [8:0] dispatch_cb_dc_level_w;
  logic signed [8:0] dispatch_cr_dc_level_w;
  logic [(4 * 3) - 1:0] dispatch_cb_ac_levels_w;
  logic [(4 * 3) - 1:0] dispatch_cr_ac_levels_w;
  logic signed [8:0] cur_cb_dc_level_q;
  logic signed [8:0] cur_cr_dc_level_q;
  logic [(4 * 3) - 1:0] cur_cb_ac_levels_q;
  logic [(4 * 3) - 1:0] cur_cr_ac_levels_q;
  logic cb_has_coeff;
  logic cr_has_coeff;
  logic cur_chroma_cbf_cb;
  logic cur_chroma_cbf_cr;
  logic signed [7:0] luma_coeff_level [0:15];
  logic [7:0] luma_coeff_abs [0:15];
  logic       luma_coeff_negative [0:15];
  logic [7:0] luma_coeff_template_abs [0:15];
  logic       luma_has_coeff;
  logic [4:0] luma_last_scan_pos;
  logic [1:0] luma_last_x;
  logic [1:0] luma_last_y;
  logic [7:0] luma_res_symbol_count;
  logic [7:0] luma_res_kind;
  logic [31:0] luma_res_data;
  logic signed [8:0] chroma_coeff_level [0:15];
  logic [8:0] chroma_coeff_abs [0:15];
  logic       chroma_coeff_negative [0:15];
  logic [8:0] chroma_coeff_template_abs [0:15];
  logic       chroma_has_coeff;
  logic [4:0] chroma_last_scan_pos;
  logic [1:0] chroma_last_x;
  logic [1:0] chroma_last_y;
  logic [7:0] chroma_res_symbol_count;
  logic [7:0] chroma_res_kind;
  logic [31:0] chroma_res_data;
  integer coeff_i;
  integer scan_i;
  integer bin_i;
  integer res_i;
  integer local_i;
  integer local_x_i;
  integer local_y_i;
  integer mark_coeff_i;
  logic [3:0] scan_x_tmp;
  logic [3:0] scan_y_tmp;
  logic [4:0] scan_raster_tmp;
  logic [4:0] last_scan_pos_tmp;
  logic [1:0] last_x_tmp;
  logic [1:0] last_y_tmp;
  logic [7:0] coeff_abs_tmp;
  logic coeff_negative_tmp;
  logic [9:0] residual_ctx_tmp;
  logic [7:0] loc_num_sig_tmp;
  logic [7:0] loc_sum_abs_tmp;
  logic [7:0] sum_bucket_tmp;
  logic [7:0] ctx_offset_tmp;
  logic [7:0] d_sum_tmp;
  logic [31:0] sign_bits_tmp;
  logic [5:0] sign_count_tmp;
  logic [7:0] regular_bins_left_tmp;
  integer chroma_coeff_i;
  integer chroma_scan_i;
  integer chroma_bin_i;
  integer chroma_res_i;
  integer chroma_local_i;
  integer chroma_local_x_i;
  integer chroma_local_y_i;
  integer chroma_mark_coeff_i;
  integer chroma_prefix_len_i;
  logic [3:0] chroma_scan_x_tmp;
  logic [3:0] chroma_scan_y_tmp;
  logic [4:0] chroma_scan_raster_tmp;
  logic [4:0] chroma_last_scan_pos_tmp;
  logic [1:0] chroma_last_x_tmp;
  logic [1:0] chroma_last_y_tmp;
  logic [8:0] chroma_coeff_abs_tmp;
  logic [9:0] chroma_residual_ctx_tmp;
  logic [7:0] chroma_loc_num_sig_tmp;
  logic [8:0] chroma_loc_sum_abs_tmp;
  logic [7:0] chroma_sum_bucket_tmp;
  logic [7:0] chroma_ctx_offset_tmp;
  logic [9:0] chroma_level_ctx_inc_tmp;
  logic [7:0] chroma_d_sum_tmp;
  logic [31:0] chroma_sign_bits_tmp;
  logic [5:0] chroma_sign_count_tmp;
  integer chroma_regular_bins_left_tmp;
  integer chroma_min_pos_2nd_pass_tmp;
  integer chroma_num_nonzero_tmp;
  logic [2:0] chroma_last_x_cmax_tmp;
  logic [2:0] chroma_last_y_cmax_tmp;
  logic [8:0] chroma_rice_sum_abs_tmp;
  logic [2:0] chroma_rice_param_tmp;
  logic [1:0] chroma_last_ctx_offset_tmp;
  logic [8:0] chroma_bypass_zero_pos_tmp;
  logic [8:0] chroma_bypass_value_tmp;
  logic [8:0] chroma_rem_threshold_tmp;
  logic [8:0] chroma_rem_abs_value_tmp;
  logic [8:0] chroma_rem_code_value_tmp;
  logic [8:0] chroma_rem_prefix_value_tmp;
  logic [2:0] chroma_rem_prefix_extra_len_tmp;
  logic [5:0] chroma_rem_prefix_count_tmp;
  logic [31:0] chroma_rem_prefix_pattern_tmp;
  logic [5:0] chroma_rem_suffix_count_tmp;
  logic [31:0] chroma_rem_suffix_pattern_tmp;

  assign busy = (state_q != ST_IDLE) || m_axis_valid;
  assign stack_pop_index = stack_count_q[3:0] - 4'd1;
  assign stack_pop_w_log2 = stack_w_log2[stack_pop_index];
  assign stack_pop_h_log2 = stack_h_log2[stack_pop_index];
  assign split_x4_w = split_x_q[5:2];
  assign split_y4_w = split_y_q[5:2];
  assign split_half_w4_w = split_w_q[6:3];
  assign split_half_h4_w = split_h_q[6:3];
  always @* begin
    case (stack_pop_w_log2)
      3'd2: stack_pop_w = 16'd4;
      3'd3: stack_pop_w = 16'd8;
      3'd4: stack_pop_w = 16'd16;
      3'd5: stack_pop_w = 16'd32;
      default: stack_pop_w = 16'd64;
    endcase
  end
  always @* begin
    case (stack_pop_h_log2)
      3'd2: stack_pop_h = 16'd4;
      3'd3: stack_pop_h = 16'd8;
      3'd4: stack_pop_h = 16'd16;
      3'd5: stack_pop_h = 16'd32;
      default: stack_pop_h = 16'd64;
    endcase
  end
  always @* begin
    case (split_w_q)
      16'd4: split_w_log2_w = 3'd2;
      16'd8: split_w_log2_w = 3'd3;
      16'd16: split_w_log2_w = 3'd4;
      16'd32: split_w_log2_w = 3'd5;
      default: split_w_log2_w = 3'd6;
    endcase
  end
  always @* begin
    case (split_h_q)
      16'd4: split_h_log2_w = 3'd2;
      16'd8: split_h_log2_w = 3'd3;
      16'd16: split_h_log2_w = 3'd4;
      16'd32: split_h_log2_w = 3'd5;
      default: split_h_log2_w = 3'd6;
    endcase
  end
  assign dual_tree_chroma_enabled = (chroma_format_idc != 2'd0) && (chroma_format_idc != 2'd3);
  assign cur_grid_x = cur_x_q >> 3;
  assign cur_grid_y = cur_y_q >> 3;
  assign cur_grid_index = {cur_grid_y[2:0], cur_grid_x[2:0]};
  assign cur_left_grid_index = cur_grid_index - 6'd1;
  assign cur_above_grid_index = cur_grid_index - 6'd8;
  assign cur_luma_left_depth_p1 = luma_neighbour_depth_p1[cur_left_grid_index];
  assign cur_luma_above_depth_p1 = luma_neighbour_depth_p1[cur_above_grid_index];
  assign cur_luma_left_valid = !cur_chroma_q && (cur_x_q != 16'd0) &&
    (cur_luma_left_depth_p1 != 3'd0);
  assign cur_luma_above_valid = !cur_chroma_q && (cur_y_q != 16'd0) &&
    (cur_luma_above_depth_p1 != 3'd0);
  assign cur_luma_left_qt_depth =
    cur_luma_left_valid ? (cur_luma_left_depth_p1 - 3'd1) : 3'd0;
  assign cur_luma_above_qt_depth =
    cur_luma_above_valid ? (cur_luma_above_depth_p1 - 3'd1) : 3'd0;
  assign cur_chroma_grid_x = cur_x_q >> 2;
  assign cur_chroma_grid_y = cur_y_q >> 2;
  assign cur_chroma_grid_index = {cur_chroma_grid_y[2:0], cur_chroma_grid_x[2:0]};
  assign cur_chroma_left_grid_index = cur_chroma_grid_index - 6'd1;
  assign cur_chroma_above_grid_index = cur_chroma_grid_index - 6'd8;
  assign cur_chroma_left_depth_p1 = chroma_neighbour_depth_p1[cur_chroma_left_grid_index];
  assign cur_chroma_above_depth_p1 = chroma_neighbour_depth_p1[cur_chroma_above_grid_index];
  assign cur_chroma_left_valid = cur_chroma_q && (cur_x_q != 16'd0) &&
    (cur_chroma_left_depth_p1 != 3'd0);
  assign cur_chroma_above_valid = cur_chroma_q && (cur_y_q != 16'd0) &&
    (cur_chroma_above_depth_p1 != 3'd0);
  assign cur_chroma_left_qt_depth =
    cur_chroma_left_valid ? (cur_chroma_left_depth_p1 - 3'd1) : 3'd0;
  assign cur_chroma_above_qt_depth =
    cur_chroma_above_valid ? (cur_chroma_above_depth_p1 - 3'd1) : 3'd0;

  assign cur_visible_width = cur_chroma_q ? (visible_width >> 1) : visible_width;
  assign cur_visible_height = cur_chroma_q ? (visible_height >> 1) : visible_height;
  assign cur_leaf_max = cur_chroma_q ? CHROMA_MAX_LEAF_SIZE : LUMA_MAX_LEAF_SIZE;
  assign cur_boundary_leaf_max = cur_chroma_q ? CHROMA_BOUNDARY_LEAF_SIZE : LUMA_BOUNDARY_BT_SIZE;
  assign cur_min_qt_size = cur_chroma_q ? CHROMA_MIN_QT_SIZE : LUMA_MIN_QT_SIZE;
  assign cur_qt_flag_can_be_signaled = (cur_mtt_q == 3'd0) &&
    (cur_w_q > cur_min_qt_size) && (cur_h_q > cur_min_qt_size);
  // ITU-T H.266 clause 9.3.4.2.2, Table 133 derives split_qt_flag ctxInc from
  // the actual neighbouring CU QT depths in the current channel. Luma and
  // chroma have separate fixed-TB grids: 8x8 luma leaves and 4x4 chroma leaves.
  assign cur_qt_left_deeper = cur_chroma_q ?
    (cur_chroma_left_valid && (cur_chroma_left_qt_depth > cur_cqt_q)) :
    (cur_luma_left_valid && (cur_luma_left_qt_depth > cur_cqt_q));
  assign cur_qt_above_deeper = cur_chroma_q ?
    (cur_chroma_above_valid && (cur_chroma_above_qt_depth > cur_cqt_q)) :
    (cur_luma_above_valid && (cur_luma_above_qt_depth > cur_cqt_q));
  assign cur_qt_ctx_inc = ((cur_cqt_q >= 3'd2) ? 3'd3 : 3'd0) +
    {2'd0, cur_qt_left_deeper} + {2'd0, cur_qt_above_deeper};
  assign cur_leaf_allowed = cur_chroma_q ?
    ((cur_w_q <= CHROMA_MAX_LEAF_SIZE) && (cur_h_q <= CHROMA_MAX_LEAF_SIZE)) :
    ((cur_w_q <= LUMA_MAX_LEAF_SIZE) && (cur_h_q <= LUMA_MAX_LEAF_SIZE));
  // VTM CodingUnit::checkCCLMAllowed implements the VVC dual-tree CCLM
  // restrictions. For the current fixed-TB 4:2:0 residual path, every coded
  // chroma transform leaf below a QT split reaches the CCLM-enabled subset and
  // emits cclm_mode_flag = 0 when the SPS enables CCLM.
  assign cur_chroma_cclm_allowed =
    (((cur_cqt_q != 3'd0) &&
      (cur_w_q <= DUAL_TREE_CHROMA_CU_SIZE) &&
      (cur_h_q <= DUAL_TREE_CHROMA_CU_SIZE)) ||
     ((cur_cqt_q == 3'd0) && (cur_mtt_q == 3'd0) &&
      (cur_w_q == (DUAL_TREE_CHROMA_CU_SIZE << 1)) &&
      (cur_h_q == (DUAL_TREE_CHROMA_CU_SIZE << 1))) ||
     ((cur_cqt_q == 3'd0) && (cur_mtt_q == 3'd1) &&
      (cur_w_q == (DUAL_TREE_CHROMA_CU_SIZE << 1)) &&
      (cur_h_q == DUAL_TREE_CHROMA_CU_SIZE)));
  assign cur_right = {1'b0, cur_x_q} + {1'b0, cur_w_q} - 17'd1;
  assign cur_bottom = {1'b0, cur_y_q} + {1'b0, cur_h_q} - 17'd1;
  assign cur_intersects = (cur_x_q < cur_visible_width) && (cur_y_q < cur_visible_height);
  assign cur_fits = (cur_right < {1'b0, cur_visible_width}) && (cur_bottom < {1'b0, cur_visible_height});
  assign cur_bottom_left_in_pic = (cur_x_q < cur_visible_width) && (cur_bottom < {1'b0, cur_visible_height});
  assign cur_top_right_in_pic = (cur_right < {1'b0, cur_visible_width}) && (cur_y_q < cur_visible_height);
  assign cur_implicit_bt_allowed = (cur_w_q <= cur_boundary_leaf_max) && (cur_h_q <= cur_boundary_leaf_max);
  assign fits_split_vertical = (cur_w_q > cur_leaf_max) && ((cur_h_q <= cur_leaf_max) || (cur_w_q >= cur_h_q));
  assign cur_mtt_horizontal_alternatives = {1'b0, cur_luma_can_bh} + {1'b0, cur_luma_can_th};
  assign cur_mtt_vertical_alternatives = {1'b0, cur_luma_can_bv} + {1'b0, cur_luma_can_tv};
  // H.266 9.3.4.2.2/Table 133 compares currWidth/aboveWidth against
  // currHeight/leftHeight for mtt_split_cu_vertical_flag. The fixed 8x8/4x4
  // subset only creates power-of-two CU sizes, so use a bounded ratio ladder
  // instead of synthesizing a general divider.
  assign cur_mtt_dep_above_log2_delta =
    {1'b0, cur_w_log2_q} - {1'b0, LUMA_NEIGHBOUR_SIZE_LOG2};
  assign cur_mtt_dep_left_log2_delta =
    {1'b0, cur_h_log2_q} - {1'b0, LUMA_NEIGHBOUR_SIZE_LOG2};
  assign cur_mtt_dep_above =
    (!cur_luma_above_valid || (cur_w_log2_q < LUMA_NEIGHBOUR_SIZE_LOG2)) ? 4'd0 :
    (cur_mtt_dep_above_log2_delta == 4'd0) ? 4'd1 :
    (cur_mtt_dep_above_log2_delta == 4'd1) ? 4'd2 :
    (cur_mtt_dep_above_log2_delta == 4'd2) ? 4'd4 :
    (cur_mtt_dep_above_log2_delta == 4'd3) ? 4'd8 : 4'd15;
  assign cur_mtt_dep_left =
    (!cur_luma_left_valid || (cur_h_log2_q < LUMA_NEIGHBOUR_SIZE_LOG2)) ? 4'd0 :
    (cur_mtt_dep_left_log2_delta == 4'd0) ? 4'd1 :
    (cur_mtt_dep_left_log2_delta == 4'd1) ? 4'd2 :
    (cur_mtt_dep_left_log2_delta == 4'd2) ? 4'd4 :
    (cur_mtt_dep_left_log2_delta == 4'd3) ? 4'd8 : 4'd15;
  // ITU-T H.266 clause 9.3.4.2.2, Table 133 derives
  // mtt_split_cu_vertical_flag ctxInc from the number of horizontal and
  // vertical BT/TT alternatives; when tied, actual coded-neighbour CU sizes
  // select ctxInc 1 or 2. Keeping this on the neighbour map prevents thin
  // boundary partitions from reusing the default ctxInc 0.
  assign cur_mtt_vertical_ctx =
    (cur_mtt_vertical_alternatives < cur_mtt_horizontal_alternatives) ? CTX_MTT_SPLIT_CU_VERTICAL_3 :
    ((cur_mtt_vertical_alternatives > cur_mtt_horizontal_alternatives) ? CTX_MTT_SPLIT_CU_VERTICAL_4 :
    (!(cur_luma_left_valid && cur_luma_above_valid) ? CTX_MTT_SPLIT_CU_VERTICAL_0 :
    ((cur_mtt_dep_above < cur_mtt_dep_left) ? CTX_MTT_SPLIT_CU_VERTICAL_1 :
    ((cur_mtt_dep_above > cur_mtt_dep_left) ? CTX_MTT_SPLIT_CU_VERTICAL_2 :
    CTX_MTT_SPLIT_CU_VERTICAL_0))));
  assign cur_mtt_write_vertical =
    ((cur_mtt_horizontal_alternatives != 2'd0) && (cur_mtt_vertical_alternatives != 2'd0));
  assign cur_mtt_write_binary = fits_split_vertical ?
    (cur_luma_can_bv && cur_luma_can_tv) : (cur_luma_can_bh && cur_luma_can_th);
  // ITU-T H.266 (V4) clause 9.3.4.2.1, Table 132:
  // ctxInc = (2 * mtt_split_cu_vertical_flag) + (mttDepth <= 1 ? 1 : 0).
  assign cur_mtt_binary_ctx = fits_split_vertical ?
    ((cur_mtt_q <= 3'd1) ? CTX_MTT_SPLIT_CU_BINARY_3 : CTX_MTT_SPLIT_CU_BINARY_2) :
    ((cur_mtt_q <= 3'd1) ? CTX_MTT_SPLIT_CU_BINARY_1 : CTX_MTT_SPLIT_CU_BINARY_0);
  assign cur_chroma_fits_split_vertical =
    (cur_w_q > CHROMA_MAX_LEAF_SIZE) &&
    ((cur_h_q <= CHROMA_MAX_LEAF_SIZE) || (cur_w_q >= cur_h_q));

  assign cur_luma_can_qt = (cur_mtt_q == 3'd0) &&
    (cur_w_q > LUMA_MIN_QT_SIZE) && (cur_h_q > LUMA_MIN_QT_SIZE);
  assign cur_luma_max_btt_depth = 4'd3 + {1'b0, cur_implicit_mtt_q};
  assign cur_luma_can_btt = ({1'b0, cur_mtt_q} < cur_luma_max_btt_depth) &&
    !((cur_w_q <= MIN_CODING_BLOCK_SIZE) && (cur_h_q <= MIN_CODING_BLOCK_SIZE)) &&
    !(((cur_w_q > LUMA_BOUNDARY_BT_SIZE) || (cur_h_q > LUMA_BOUNDARY_BT_SIZE)) &&
      ((cur_w_q > LUMA_BOUNDARY_BT_SIZE) || (cur_h_q > LUMA_BOUNDARY_BT_SIZE)));
  assign cur_luma_exceeds_bt_size =
    (cur_w_q > LUMA_BOUNDARY_BT_SIZE) || (cur_h_q > LUMA_BOUNDARY_BT_SIZE);
  assign cur_luma_can_bh = cur_luma_can_btt && !cur_luma_exceeds_bt_size &&
    (cur_h_q > MIN_CODING_BLOCK_SIZE) &&
    !((cur_w_q > MAX_TB_SIZEY) && (cur_h_q <= MAX_TB_SIZEY));
  assign cur_luma_can_bv = cur_luma_can_btt && !cur_luma_exceeds_bt_size &&
    (cur_w_q > MIN_CODING_BLOCK_SIZE) &&
    !((cur_w_q <= MAX_TB_SIZEY) && (cur_h_q > MAX_TB_SIZEY));
  assign cur_luma_can_th = cur_luma_can_btt &&
    (cur_h_q > (MIN_CODING_BLOCK_SIZE << 1)) &&
    (cur_h_q <= LUMA_BOUNDARY_BT_SIZE) &&
    (cur_w_q <= LUMA_BOUNDARY_BT_SIZE) &&
    (cur_w_q <= MAX_TB_SIZEY) && (cur_h_q <= MAX_TB_SIZEY);
  assign cur_luma_can_tv = cur_luma_can_btt &&
    (cur_w_q > (MIN_CODING_BLOCK_SIZE << 1)) &&
    (cur_w_q <= LUMA_BOUNDARY_BT_SIZE) &&
    (cur_h_q <= LUMA_BOUNDARY_BT_SIZE) &&
    (cur_w_q <= MAX_TB_SIZEY) && (cur_h_q <= MAX_TB_SIZEY);
  assign cur_luma_split_alternatives =
    {3'd0, cur_luma_can_bv} + {3'd0, cur_luma_can_bh} +
    {3'd0, cur_luma_can_tv} + {3'd0, cur_luma_can_th} +
    {2'd0, cur_luma_can_qt, 1'b0};
  // ITU-T H.266 clause 9.3.4.2.2, Table 133 derives
  // split_cu_flag ctxInc from legal split alternatives plus left/above coded
  // CUs that are smaller in the current channel. Use the same coded-neighbour
  // map as split_qt_flag so the RTL path follows the Rust/spec model instead
  // of geometry-only heuristics.
  assign cur_luma_split_neighbour_ctx =
    {1'b0, (cur_luma_left_valid && (LUMA_NEIGHBOUR_SIZE_LOG2 < cur_h_log2_q))} +
    {1'b0, (cur_luma_above_valid && (LUMA_NEIGHBOUR_SIZE_LOG2 < cur_w_log2_q))};
  assign cur_luma_split_ctx_inc =
    ((cur_luma_split_alternatives >= 4'd5) ? 4'd6 :
    ((cur_luma_split_alternatives >= 4'd3) ? 4'd3 : 4'd0)) +
    {2'd0, cur_luma_split_neighbour_ctx};
  always @* begin
    case (cur_luma_split_ctx_inc)
      4'd0: cur_luma_split_ctx = CTX_SPLIT_FLAG_0;
      4'd1: cur_luma_split_ctx = CTX_SPLIT_FLAG_1;
      4'd2: cur_luma_split_ctx = CTX_SPLIT_FLAG_2;
      4'd3: cur_luma_split_ctx = CTX_SPLIT_FLAG_3;
      4'd4: cur_luma_split_ctx = CTX_SPLIT_FLAG_4;
      4'd5: cur_luma_split_ctx = CTX_SPLIT_FLAG_5;
      4'd6: cur_luma_split_ctx = CTX_SPLIT_FLAG_6;
      4'd7: cur_luma_split_ctx = CTX_SPLIT_FLAG_7;
      default: cur_luma_split_ctx = CTX_SPLIT_FLAG_8;
    endcase
  end
  assign cur_luma_writes_split = cur_luma_split_alternatives != 4'd0;

  assign cur_chroma_luma_width = cur_w_q << 1;
  assign cur_chroma_luma_height = cur_h_q << 1;
  // For the fixed 4:2:0 chroma tree, CU dimensions are powers of two. These
  // predicates replace area multipliers used by VVC split availability checks.
  assign cur_chroma_area_gt_min = (cur_w_q > 16'd4) || (cur_h_q > 16'd4);
  assign cur_chroma_area_gt_min2 =
    ((cur_w_q > 16'd4) && (cur_h_q > 16'd4)) ||
    (cur_w_q > 16'd8) || (cur_h_q > 16'd8);
  assign cur_chroma_can_qt = (cur_mtt_q == 3'd0) &&
    (cur_chroma_luma_width > LUMA_MIN_QT_SIZE) &&
    (cur_w_q > MIN_DUALTREE_CHROMA_WIDTH);
  assign cur_chroma_max_btt_depth = 4'd3 + {1'b0, cur_implicit_mtt_q};
  assign cur_chroma_can_btt = ({1'b0, cur_mtt_q} < cur_chroma_max_btt_depth) &&
    !((cur_chroma_luma_width <= MIN_CODING_BLOCK_SIZE) &&
      (cur_chroma_luma_height <= MIN_CODING_BLOCK_SIZE)) &&
    !(((cur_chroma_luma_width > CHROMA_MAX_BT_SIZE_LUMA) ||
       (cur_chroma_luma_height > CHROMA_MAX_BT_SIZE_LUMA)) &&
      ((cur_chroma_luma_width > CHROMA_MAX_TT_SIZE_LUMA) ||
       (cur_chroma_luma_height > CHROMA_MAX_TT_SIZE_LUMA)));
  assign cur_chroma_exceeds_bt_size =
    (cur_chroma_luma_width > CHROMA_MAX_BT_SIZE_LUMA) ||
    (cur_chroma_luma_height > CHROMA_MAX_BT_SIZE_LUMA);
  assign cur_chroma_can_bh = cur_chroma_can_btt && !cur_chroma_exceeds_bt_size &&
    (cur_chroma_luma_height > MIN_CODING_BLOCK_SIZE) &&
    !((cur_chroma_luma_width > MAX_TB_SIZEY) && (cur_chroma_luma_height <= MAX_TB_SIZEY)) &&
    cur_chroma_area_gt_min;
  assign cur_chroma_can_bv = cur_chroma_can_btt && !cur_chroma_exceeds_bt_size &&
    (cur_chroma_luma_width > MIN_CODING_BLOCK_SIZE) &&
    !((cur_chroma_luma_width <= MAX_TB_SIZEY) && (cur_chroma_luma_height > MAX_TB_SIZEY)) &&
    cur_chroma_area_gt_min &&
    (cur_w_q != MIN_DUALTREE_CHROMA_WIDTH);
  assign cur_chroma_can_th = cur_chroma_can_btt &&
    (cur_chroma_luma_height > (MIN_CODING_BLOCK_SIZE << 1)) &&
    (cur_chroma_luma_height <= CHROMA_MAX_TT_SIZE_LUMA) &&
    (cur_chroma_luma_width <= CHROMA_MAX_TT_SIZE_LUMA) &&
    (cur_chroma_luma_width <= MAX_TB_SIZEY) &&
    (cur_chroma_luma_height <= MAX_TB_SIZEY) &&
    cur_chroma_area_gt_min2;
  assign cur_chroma_can_tv = cur_chroma_can_btt &&
    (cur_chroma_luma_width > (MIN_CODING_BLOCK_SIZE << 1)) &&
    (cur_chroma_luma_width <= CHROMA_MAX_TT_SIZE_LUMA) &&
    (cur_chroma_luma_height <= CHROMA_MAX_TT_SIZE_LUMA) &&
    (cur_chroma_luma_width <= MAX_TB_SIZEY) &&
    (cur_chroma_luma_height <= MAX_TB_SIZEY) &&
    cur_chroma_area_gt_min2 &&
    (cur_w_q != (MIN_DUALTREE_CHROMA_WIDTH << 1));
  assign cur_chroma_split_alternatives =
    {3'd0, cur_chroma_can_bh} + {3'd0, cur_chroma_can_bv} +
    {3'd0, cur_chroma_can_th} + {3'd0, cur_chroma_can_tv} +
    {2'd0, cur_chroma_can_qt, 1'b0};
  assign cur_chroma_mtt_horizontal_alternatives =
    {1'b0, cur_chroma_can_bh} + {1'b0, cur_chroma_can_th};
  assign cur_chroma_mtt_vertical_alternatives =
    {1'b0, cur_chroma_can_bv} + {1'b0, cur_chroma_can_tv};
  assign cur_chroma_mtt_dep_above_log2_delta =
    {1'b0, cur_w_log2_q} - {1'b0, CHROMA_NEIGHBOUR_SIZE_LOG2};
  assign cur_chroma_mtt_dep_left_log2_delta =
    {1'b0, cur_h_log2_q} - {1'b0, CHROMA_NEIGHBOUR_SIZE_LOG2};
  assign cur_chroma_mtt_dep_above =
    (!cur_chroma_above_valid || (cur_w_log2_q < CHROMA_NEIGHBOUR_SIZE_LOG2)) ? 4'd0 :
    (cur_chroma_mtt_dep_above_log2_delta == 4'd0) ? 4'd1 :
    (cur_chroma_mtt_dep_above_log2_delta == 4'd1) ? 4'd2 :
    (cur_chroma_mtt_dep_above_log2_delta == 4'd2) ? 4'd4 :
    (cur_chroma_mtt_dep_above_log2_delta == 4'd3) ? 4'd8 : 4'd15;
  assign cur_chroma_mtt_dep_left =
    (!cur_chroma_left_valid || (cur_h_log2_q < CHROMA_NEIGHBOUR_SIZE_LOG2)) ? 4'd0 :
    (cur_chroma_mtt_dep_left_log2_delta == 4'd0) ? 4'd1 :
    (cur_chroma_mtt_dep_left_log2_delta == 4'd1) ? 4'd2 :
    (cur_chroma_mtt_dep_left_log2_delta == 4'd2) ? 4'd4 :
    (cur_chroma_mtt_dep_left_log2_delta == 4'd3) ? 4'd8 : 4'd15;
  assign cur_chroma_mtt_vertical_ctx =
    (cur_chroma_mtt_vertical_alternatives < cur_chroma_mtt_horizontal_alternatives) ?
      CTX_MTT_SPLIT_CU_VERTICAL_3 :
    ((cur_chroma_mtt_vertical_alternatives > cur_chroma_mtt_horizontal_alternatives) ?
      CTX_MTT_SPLIT_CU_VERTICAL_4 :
    (!(cur_chroma_left_valid && cur_chroma_above_valid) ? CTX_MTT_SPLIT_CU_VERTICAL_0 :
    ((cur_chroma_mtt_dep_above < cur_chroma_mtt_dep_left) ? CTX_MTT_SPLIT_CU_VERTICAL_1 :
    ((cur_chroma_mtt_dep_above > cur_chroma_mtt_dep_left) ? CTX_MTT_SPLIT_CU_VERTICAL_2 :
    CTX_MTT_SPLIT_CU_VERTICAL_0))));
  assign cur_chroma_mtt_write_vertical =
    ((cur_chroma_mtt_horizontal_alternatives != 2'd0) &&
     (cur_chroma_mtt_vertical_alternatives != 2'd0));
  assign cur_chroma_mtt_write_binary = cur_chroma_fits_split_vertical ?
    (cur_chroma_can_bv && cur_chroma_can_tv) :
    (cur_chroma_can_bh && cur_chroma_can_th);
  assign cur_chroma_mtt_binary_ctx = cur_chroma_fits_split_vertical ?
    ((cur_mtt_q <= 3'd1) ? CTX_MTT_SPLIT_CU_BINARY_3 : CTX_MTT_SPLIT_CU_BINARY_2) :
    ((cur_mtt_q <= 3'd1) ? CTX_MTT_SPLIT_CU_BINARY_1 : CTX_MTT_SPLIT_CU_BINARY_0);
  // ITU-T H.266 clause 9.3.4.2.2, Table 133 derives
  // split_cu_flag ctxInc from legal split alternatives plus left/above coded
  // CUs that are smaller in the current channel. The chroma table is a 4x4
  // sample grid matching the fixed 4:2:0 TB policy.
  assign cur_chroma_split_neighbour_ctx =
    {1'b0, (cur_chroma_left_valid && (CHROMA_NEIGHBOUR_SIZE_LOG2 < cur_h_log2_q))} +
    {1'b0, (cur_chroma_above_valid && (CHROMA_NEIGHBOUR_SIZE_LOG2 < cur_w_log2_q))};
  assign cur_chroma_split_ctx_inc =
    ((cur_chroma_split_alternatives >= 4'd5) ? 4'd6 :
    ((cur_chroma_split_alternatives >= 4'd3) ? 4'd3 : 4'd0)) +
    {2'd0, cur_chroma_split_neighbour_ctx};
  always @* begin
    case (cur_chroma_split_ctx_inc)
      4'd0: cur_chroma_split_ctx = CTX_SPLIT_FLAG_0;
      4'd1: cur_chroma_split_ctx = CTX_SPLIT_FLAG_1;
      4'd2: cur_chroma_split_ctx = CTX_SPLIT_FLAG_2;
      4'd3: cur_chroma_split_ctx = CTX_SPLIT_FLAG_3;
      4'd4: cur_chroma_split_ctx = CTX_SPLIT_FLAG_4;
      4'd5: cur_chroma_split_ctx = CTX_SPLIT_FLAG_5;
      4'd6: cur_chroma_split_ctx = CTX_SPLIT_FLAG_6;
      4'd7: cur_chroma_split_ctx = CTX_SPLIT_FLAG_7;
      default: cur_chroma_split_ctx = CTX_SPLIT_FLAG_8;
    endcase
  end
  assign cur_chroma_writes_split = (cur_chroma_split_alternatives != 4'd0);
  always @* begin
    case (cur_qt_ctx_inc)
      3'd0: cur_split_qt_ctx = CTX_SPLIT_QT_FLAG_0;
      3'd1: cur_split_qt_ctx = CTX_SPLIT_QT_FLAG_1;
      3'd2: cur_split_qt_ctx = CTX_SPLIT_QT_FLAG_2;
      3'd3: cur_split_qt_ctx = CTX_SPLIT_QT_FLAG_3;
      3'd4: cur_split_qt_ctx = CTX_SPLIT_QT_FLAG_4;
      default: cur_split_qt_ctx = CTX_SPLIT_QT_FLAG_5;
    endcase
  end

  always @* begin
    cur_leaf_writes_split = 1'b1;
    cur_leaf_split_ctx = CTX_SPLIT_FLAG_3;
    if (cur_chroma_q) begin
      // VVC 9.3.4.2.2 derives split_cu_flag ctxInc from the set of
      // legal split alternatives. The cur_chroma_* availability signals
      // mirror VTM QTBTPartitioner::canSplit for the current 4:2:0
      // dual-tree SPS constraints.
      cur_leaf_writes_split = cur_chroma_writes_split;
      cur_leaf_split_ctx = cur_chroma_split_ctx;
    end else begin
      cur_leaf_writes_split = cur_luma_writes_split;
      cur_leaf_split_ctx = cur_luma_split_ctx;
    end
  end

  assign cur_luma_tu_index = cur_grid_index;
  assign selected_luma_abs_level_w =
    luma_abs_levels[{cur_luma_tu_index, 3'b000} +: 8];
  assign selected_luma_negative_w = luma_negative[cur_luma_tu_index];
  assign selected_luma_ac_levels_w =
    luma_ac_levels[(cur_luma_tu_index * (4 * 15)) +: (4 * 15)];
  assign dispatch_cb_dc_level_w =
    $signed(cb_dc_levels[(chroma_tu_index_q * 9) +: 9]);
  assign dispatch_cr_dc_level_w =
    $signed(cr_dc_levels[(chroma_tu_index_q * 9) +: 9]);
  assign dispatch_cb_ac_levels_w =
    cb_ac_levels[(chroma_tu_index_q * (4 * 3)) +: (4 * 3)];
  assign dispatch_cr_ac_levels_w =
    cr_ac_levels[(chroma_tu_index_q * (4 * 3)) +: (4 * 3)];

  assign cb_has_coeff = (dispatch_cb_dc_level_w != 9'sd0) || (|dispatch_cb_ac_levels_w);
  assign cr_has_coeff = (dispatch_cr_dc_level_w != 9'sd0) || (|dispatch_cr_ac_levels_w);
  // H.266 7.3.11.10 transform_unit() carries tu_cbf_cb/tu_cbf_cr for the
  // current chroma transform leaf. Clipped 4:2:0 pictures such as 24x8 have
  // more than one visible chroma leaf, so CBFs follow traversal order rather
  // than a CTU-origin-only coefficient bundle.
  assign cur_chroma_cbf_cb = cb_has_coeff;
  assign cur_chroma_cbf_cr = cr_has_coeff;
  assign luma_has_coeff = (selected_luma_abs_level_w != 8'd0) || (|selected_luma_ac_levels_w);
  assign residual_axis_ready =
    ((state_q == ST_LUMA_RESIDUAL) || (state_q == ST_CHROMA_RESIDUAL)) &&
    (!m_axis_valid || m_axis_ready);

`ifdef FF_VVC_USE_COMBINATIONAL_RESIDUAL_EMITTER
  always @* begin
    luma_res_kind = 8'd0;
    luma_res_data = 32'd0;

    for (coeff_i = 0; coeff_i < 16; coeff_i = coeff_i + 1) begin
      luma_coeff_level[coeff_i] = 8'sd0;
      luma_coeff_abs[coeff_i] = 8'd0;
      luma_coeff_negative[coeff_i] = 1'b0;
      luma_coeff_template_abs[coeff_i] = 8'd0;
    end

    luma_coeff_level[0] = (cur_luma_negative && (cur_luma_abs_level != 8'd0)) ?
      -$signed({1'b0, cur_luma_abs_level}) : $signed({1'b0, cur_luma_abs_level});
    for (coeff_i = 1; coeff_i < 16; coeff_i = coeff_i + 1) begin
      luma_coeff_level[coeff_i] =
        $signed({{4{cur_luma_ac_levels[((15 - coeff_i) * 4) + 3]}},
                 cur_luma_ac_levels[((15 - coeff_i) * 4) +: 4]});
    end

    luma_has_coeff = 1'b0;
    for (coeff_i = 0; coeff_i < 16; coeff_i = coeff_i + 1) begin
      coeff_abs_tmp = luma_coeff_level[coeff_i][7] ?
        -$signed(luma_coeff_level[coeff_i]) : luma_coeff_level[coeff_i];
      luma_coeff_abs[coeff_i] = coeff_abs_tmp;
      luma_coeff_negative[coeff_i] = luma_coeff_level[coeff_i][7];
      luma_coeff_template_abs[coeff_i] =
        (coeff_abs_tmp < (8'd4 + {7'd0, coeff_abs_tmp[0]})) ?
        coeff_abs_tmp : (8'd4 + {7'd0, coeff_abs_tmp[0]});
      if (coeff_abs_tmp != 8'd0) begin
        luma_has_coeff = 1'b1;
      end
    end

    last_scan_pos_tmp = 5'd0;
    last_x_tmp = 2'd0;
    last_y_tmp = 2'd0;
    for (scan_i = 0; scan_i < 16; scan_i = scan_i + 1) begin
      case (scan_i)
        0: begin scan_x_tmp = 4'd0; scan_y_tmp = 4'd0; scan_raster_tmp = 5'd0; end
        1: begin scan_x_tmp = 4'd0; scan_y_tmp = 4'd1; scan_raster_tmp = 5'd4; end
        2: begin scan_x_tmp = 4'd1; scan_y_tmp = 4'd0; scan_raster_tmp = 5'd1; end
        3: begin scan_x_tmp = 4'd0; scan_y_tmp = 4'd2; scan_raster_tmp = 5'd8; end
        4: begin scan_x_tmp = 4'd1; scan_y_tmp = 4'd1; scan_raster_tmp = 5'd5; end
        5: begin scan_x_tmp = 4'd2; scan_y_tmp = 4'd0; scan_raster_tmp = 5'd2; end
        6: begin scan_x_tmp = 4'd0; scan_y_tmp = 4'd3; scan_raster_tmp = 5'd12; end
        7: begin scan_x_tmp = 4'd1; scan_y_tmp = 4'd2; scan_raster_tmp = 5'd9; end
        8: begin scan_x_tmp = 4'd2; scan_y_tmp = 4'd1; scan_raster_tmp = 5'd6; end
        9: begin scan_x_tmp = 4'd3; scan_y_tmp = 4'd0; scan_raster_tmp = 5'd3; end
        10: begin scan_x_tmp = 4'd1; scan_y_tmp = 4'd3; scan_raster_tmp = 5'd13; end
        11: begin scan_x_tmp = 4'd2; scan_y_tmp = 4'd2; scan_raster_tmp = 5'd10; end
        12: begin scan_x_tmp = 4'd3; scan_y_tmp = 4'd1; scan_raster_tmp = 5'd7; end
        13: begin scan_x_tmp = 4'd2; scan_y_tmp = 4'd3; scan_raster_tmp = 5'd14; end
        14: begin scan_x_tmp = 4'd3; scan_y_tmp = 4'd2; scan_raster_tmp = 5'd11; end
        default: begin scan_x_tmp = 4'd3; scan_y_tmp = 4'd3; scan_raster_tmp = 5'd15; end
      endcase
      if (luma_coeff_abs[scan_raster_tmp] != 8'd0) begin
        last_scan_pos_tmp = scan_i[4:0];
        last_x_tmp = scan_x_tmp[1:0];
        last_y_tmp = scan_y_tmp[1:0];
      end
    end
    luma_last_scan_pos = last_scan_pos_tmp;
    luma_last_x = last_x_tmp;
    luma_last_y = last_y_tmp;

    luma_res_symbol_count = 8'd0;
    sign_bits_tmp = 32'd0;
    sign_count_tmp = 6'd0;
    regular_bins_left_tmp = 8'd112;

    if (luma_has_coeff) begin
      for (bin_i = 0; bin_i < 4; bin_i = bin_i + 1) begin
        if (bin_i <= {30'd0, luma_last_x}) begin
          residual_ctx_tmp = (bin_i < 2) ? CTX_LAST_SIG_X_PREFIX_3 : CTX_LAST_SIG_X_PREFIX_4;
          if (luma_res_symbol_count == residual_step_q) begin
            luma_res_kind = SYMBOL_BIN_CTX;
            luma_res_data = {
              14'd0, residual_ctx_tmp, 7'd0, (bin_i < {30'd0, luma_last_x})
            };
          end
          luma_res_symbol_count = luma_res_symbol_count + 8'd1;
        end
      end
      for (bin_i = 0; bin_i < 4; bin_i = bin_i + 1) begin
        if (bin_i <= {30'd0, luma_last_y}) begin
          residual_ctx_tmp = (bin_i < 2) ? CTX_LAST_SIG_Y_PREFIX_3 : CTX_LAST_SIG_Y_PREFIX_4;
          if (luma_res_symbol_count == residual_step_q) begin
            luma_res_kind = SYMBOL_BIN_CTX;
            luma_res_data = {
              14'd0, residual_ctx_tmp, 7'd0, (bin_i < {30'd0, luma_last_y})
            };
          end
          luma_res_symbol_count = luma_res_symbol_count + 8'd1;
        end
      end

      for (scan_i = 15; scan_i >= 0; scan_i = scan_i - 1) begin
        case (scan_i)
          0: begin scan_x_tmp = 4'd0; scan_y_tmp = 4'd0; scan_raster_tmp = 5'd0; end
          1: begin scan_x_tmp = 4'd0; scan_y_tmp = 4'd1; scan_raster_tmp = 5'd4; end
          2: begin scan_x_tmp = 4'd1; scan_y_tmp = 4'd0; scan_raster_tmp = 5'd1; end
          3: begin scan_x_tmp = 4'd0; scan_y_tmp = 4'd2; scan_raster_tmp = 5'd8; end
          4: begin scan_x_tmp = 4'd1; scan_y_tmp = 4'd1; scan_raster_tmp = 5'd5; end
          5: begin scan_x_tmp = 4'd2; scan_y_tmp = 4'd0; scan_raster_tmp = 5'd2; end
          6: begin scan_x_tmp = 4'd0; scan_y_tmp = 4'd3; scan_raster_tmp = 5'd12; end
          7: begin scan_x_tmp = 4'd1; scan_y_tmp = 4'd2; scan_raster_tmp = 5'd9; end
          8: begin scan_x_tmp = 4'd2; scan_y_tmp = 4'd1; scan_raster_tmp = 5'd6; end
          9: begin scan_x_tmp = 4'd3; scan_y_tmp = 4'd0; scan_raster_tmp = 5'd3; end
          10: begin scan_x_tmp = 4'd1; scan_y_tmp = 4'd3; scan_raster_tmp = 5'd13; end
          11: begin scan_x_tmp = 4'd2; scan_y_tmp = 4'd2; scan_raster_tmp = 5'd10; end
          12: begin scan_x_tmp = 4'd3; scan_y_tmp = 4'd1; scan_raster_tmp = 5'd7; end
          13: begin scan_x_tmp = 4'd2; scan_y_tmp = 4'd3; scan_raster_tmp = 5'd14; end
          14: begin scan_x_tmp = 4'd3; scan_y_tmp = 4'd2; scan_raster_tmp = 5'd11; end
          default: begin scan_x_tmp = 4'd3; scan_y_tmp = 4'd3; scan_raster_tmp = 5'd15; end
        endcase

        if (scan_i <= {27'd0, luma_last_scan_pos}) begin
          loc_num_sig_tmp = 8'd0;
          loc_sum_abs_tmp = 8'd0;
          for (local_i = 0; local_i < 5; local_i = local_i + 1) begin
            case (local_i)
              0: begin local_x_i = scan_x_tmp + 1; local_y_i = scan_y_tmp; end
              1: begin local_x_i = scan_x_tmp + 2; local_y_i = scan_y_tmp; end
              2: begin local_x_i = scan_x_tmp + 1; local_y_i = scan_y_tmp + 1; end
              3: begin local_x_i = scan_x_tmp; local_y_i = scan_y_tmp + 1; end
              default: begin local_x_i = scan_x_tmp; local_y_i = scan_y_tmp + 2; end
            endcase
            mark_coeff_i = (local_y_i * 4) + local_x_i;
            if ((local_x_i < 4) && (local_y_i < 4) && (luma_coeff_abs[mark_coeff_i] != 8'd0)) begin
              loc_num_sig_tmp = loc_num_sig_tmp + 8'd1;
              loc_sum_abs_tmp = loc_sum_abs_tmp + luma_coeff_template_abs[mark_coeff_i];
            end
          end

          if ((sign_count_tmp != 6'd0) || (scan_i != {27'd0, luma_last_scan_pos})) begin
            sum_bucket_tmp = (loc_sum_abs_tmp + 8'd1) >> 1;
            if (sum_bucket_tmp > 8'd3) begin
              sum_bucket_tmp = 8'd3;
            end
            d_sum_tmp = {4'd0, scan_x_tmp} + {4'd0, scan_y_tmp};
            if (d_sum_tmp < 8'd2) begin
              residual_ctx_tmp = 6'd8 + sum_bucket_tmp[5:0];
            end else if (d_sum_tmp < 8'd5) begin
              residual_ctx_tmp = 6'd4 + sum_bucket_tmp[5:0];
            end else begin
              residual_ctx_tmp = sum_bucket_tmp[5:0];
            end
            // H.266 Table 132 and 9.3.4.2.8 define sig_coeff_flag ctxInc
            // 0..62. The current luma first-4x4 path reaches 0..11.
            case (residual_ctx_tmp[7:0])
              8'd0: residual_ctx_tmp = 10'd118;
              8'd1: residual_ctx_tmp = CTX_SIG_COEFF_FLAG_1;
              8'd2: residual_ctx_tmp = 10'd119;
              8'd3: residual_ctx_tmp = 10'd120;
              8'd4: residual_ctx_tmp = CTX_SIG_COEFF_FLAG_4;
              8'd5: residual_ctx_tmp = CTX_SIG_COEFF_FLAG_5;
              8'd6: residual_ctx_tmp = CTX_SIG_COEFF_FLAG_6;
              8'd7: residual_ctx_tmp = 10'd121;
              8'd8: residual_ctx_tmp = 10'd122;
              8'd9: residual_ctx_tmp = CTX_SIG_COEFF_FLAG_9;
              8'd10: residual_ctx_tmp = 10'd123;
              8'd11: residual_ctx_tmp = 10'd124;
              default: residual_ctx_tmp = 10'd1023;
            endcase
            if (luma_res_symbol_count == residual_step_q) begin
              luma_res_kind = SYMBOL_BIN_CTX;
              luma_res_data = {
                14'd0, residual_ctx_tmp, 7'd0, luma_coeff_abs[scan_raster_tmp] != 8'd0
              };
            end
            luma_res_symbol_count = luma_res_symbol_count + 8'd1;
            regular_bins_left_tmp = regular_bins_left_tmp - 8'd1;
          end

          if (luma_coeff_abs[scan_raster_tmp] != 8'd0) begin
            if ((scan_x_tmp[1:0] == luma_last_x) && (scan_y_tmp[1:0] == luma_last_y)) begin
              ctx_offset_tmp = 8'd0;
              residual_ctx_tmp = 10'd0;
            end else begin
              ctx_offset_tmp = loc_sum_abs_tmp - loc_num_sig_tmp;
              if (ctx_offset_tmp > 8'd4) begin
                ctx_offset_tmp = 8'd4;
              end
              d_sum_tmp = {4'd0, scan_x_tmp} + {4'd0, scan_y_tmp};
              residual_ctx_tmp = 6'd1 + ctx_offset_tmp[5:0] +
                ((d_sum_tmp == 8'd0) ? 6'd15 :
                ((d_sum_tmp < 8'd3) ? 6'd10 : 6'd5));
            end

            // H.266 Table 132 and 9.3.4.2.9 define abs_level_gtx_flag
            // ctxInc 0..71. The first greater-than flag here reaches 0..20.
            case (residual_ctx_tmp[7:0])
              8'd0: residual_ctx_tmp = CTX_ABS_LEVEL_GTX_FLAG_0;
              8'd6: residual_ctx_tmp = 10'd137;
              8'd7: residual_ctx_tmp = CTX_ABS_LEVEL_GTX_FLAG_7;
              8'd8: residual_ctx_tmp = 10'd138;
              8'd9: residual_ctx_tmp = 10'd139;
              8'd10: residual_ctx_tmp = 10'd140;
              8'd11: residual_ctx_tmp = CTX_ABS_LEVEL_GTX_FLAG_11;
              8'd12: residual_ctx_tmp = 10'd141;
              8'd13: residual_ctx_tmp = CTX_ABS_LEVEL_GTX_FLAG_13;
              8'd14: residual_ctx_tmp = 10'd142;
              8'd15: residual_ctx_tmp = 10'd143;
              8'd16: residual_ctx_tmp = 10'd144;
              8'd17: residual_ctx_tmp = 10'd145;
              8'd18: residual_ctx_tmp = 10'd146;
              8'd19: residual_ctx_tmp = 10'd147;
              8'd20: residual_ctx_tmp = 10'd148;
              default: residual_ctx_tmp = 10'd1023;
            endcase
            if (luma_res_symbol_count == residual_step_q) begin
              luma_res_kind = SYMBOL_BIN_CTX;
              luma_res_data = {
                14'd0, residual_ctx_tmp, 7'd0, luma_coeff_abs[scan_raster_tmp] > 8'd1
              };
            end
            luma_res_symbol_count = luma_res_symbol_count + 8'd1;
            regular_bins_left_tmp = regular_bins_left_tmp - 8'd1;

            if (luma_coeff_abs[scan_raster_tmp] > 8'd1) begin
              if ((scan_x_tmp[1:0] == luma_last_x) && (scan_y_tmp[1:0] == luma_last_y)) begin
                residual_ctx_tmp = 10'd0;
              end else begin
                ctx_offset_tmp = loc_sum_abs_tmp - loc_num_sig_tmp;
                if (ctx_offset_tmp > 8'd4) begin
                  ctx_offset_tmp = 8'd4;
                end
                d_sum_tmp = {4'd0, scan_x_tmp} + {4'd0, scan_y_tmp};
                residual_ctx_tmp = 6'd1 + ctx_offset_tmp[5:0] +
                  ((d_sum_tmp == 8'd0) ? 6'd15 :
                  ((d_sum_tmp < 8'd3) ? 6'd10 : 6'd5));
              end
              // H.266 Table 132 and 9.3.4.2.9 define par_level_flag ctxInc
              // 0..32. The current luma first-4x4 path reaches 0 and 6..20.
              case (residual_ctx_tmp[7:0])
                8'd0: residual_ctx_tmp = CTX_PAR_LEVEL_FLAG_0;
                8'd6: residual_ctx_tmp = 10'd125;
                8'd7: residual_ctx_tmp = CTX_PAR_LEVEL_FLAG_7;
                8'd8: residual_ctx_tmp = 10'd126;
                8'd9: residual_ctx_tmp = 10'd127;
                8'd10: residual_ctx_tmp = 10'd128;
                8'd11: residual_ctx_tmp = CTX_PAR_LEVEL_FLAG_11;
                8'd12: residual_ctx_tmp = 10'd129;
                8'd13: residual_ctx_tmp = CTX_PAR_LEVEL_FLAG_13;
                8'd14: residual_ctx_tmp = 10'd130;
                8'd15: residual_ctx_tmp = 10'd131;
                8'd16: residual_ctx_tmp = 10'd132;
                8'd17: residual_ctx_tmp = 10'd133;
                8'd18: residual_ctx_tmp = 10'd134;
                8'd19: residual_ctx_tmp = 10'd135;
                8'd20: residual_ctx_tmp = 10'd136;
                default: residual_ctx_tmp = 10'd1023;
              endcase
              if (luma_res_symbol_count == residual_step_q) begin
                luma_res_kind = SYMBOL_BIN_CTX;
                luma_res_data = {
                  14'd0, residual_ctx_tmp, 7'd0, luma_coeff_abs[scan_raster_tmp][0]
                };
              end
              luma_res_symbol_count = luma_res_symbol_count + 8'd1;

              if ((scan_x_tmp[1:0] == luma_last_x) && (scan_y_tmp[1:0] == luma_last_y)) begin
                residual_ctx_tmp = 10'd32;
              end else begin
                ctx_offset_tmp = loc_sum_abs_tmp - loc_num_sig_tmp;
                if (ctx_offset_tmp > 8'd4) begin
                  ctx_offset_tmp = 8'd4;
                end
                d_sum_tmp = {4'd0, scan_x_tmp} + {4'd0, scan_y_tmp};
                residual_ctx_tmp = 6'd33 + ctx_offset_tmp[5:0] +
                  ((d_sum_tmp == 8'd0) ? 6'd15 :
                  ((d_sum_tmp < 8'd3) ? 6'd10 : 6'd5));
              end
              // H.266 Table 132 and 9.3.4.2.9 add 32 to the ctxInc for the
              // second abs_level_gtx_flag. This path reaches 32 and 38..52.
              case (residual_ctx_tmp[7:0])
                8'd32: residual_ctx_tmp = CTX_ABS_LEVEL_GTX_FLAG_32;
                8'd38: residual_ctx_tmp = 10'd149;
                8'd39: residual_ctx_tmp = CTX_ABS_LEVEL_GTX_FLAG_39;
                8'd40: residual_ctx_tmp = 10'd150;
                8'd41: residual_ctx_tmp = 10'd151;
                8'd42: residual_ctx_tmp = 10'd152;
                8'd43: residual_ctx_tmp = CTX_ABS_LEVEL_GTX_FLAG_43;
                8'd44: residual_ctx_tmp = 10'd153;
                8'd45: residual_ctx_tmp = CTX_ABS_LEVEL_GTX_FLAG_45;
                8'd46: residual_ctx_tmp = 10'd154;
                8'd47: residual_ctx_tmp = 10'd155;
                8'd48: residual_ctx_tmp = 10'd156;
                8'd49: residual_ctx_tmp = 10'd157;
                8'd50: residual_ctx_tmp = 10'd158;
                8'd51: residual_ctx_tmp = 10'd159;
                8'd52: residual_ctx_tmp = 10'd160;
                default: residual_ctx_tmp = 10'd1023;
              endcase
              if (luma_res_symbol_count == residual_step_q) begin
                luma_res_kind = SYMBOL_BIN_CTX;
                luma_res_data = {
                  14'd0, residual_ctx_tmp, 7'd0, luma_coeff_abs[scan_raster_tmp] > 8'd3
                };
              end
              luma_res_symbol_count = luma_res_symbol_count + 8'd1;
            end

            if ((scan_raster_tmp == 5'd0) && (luma_coeff_abs[scan_raster_tmp] > 8'd3)) begin
              if (luma_res_symbol_count == residual_step_q) begin
                luma_res_kind = SYMBOL_BINS_EP;
                luma_res_data = (rem_prefix_pattern << 6) | {26'd0, rem_prefix_count};
              end
              luma_res_symbol_count = luma_res_symbol_count + 8'd1;
              if (luma_res_symbol_count == residual_step_q) begin
                luma_res_kind = SYMBOL_BINS_EP;
                luma_res_data = (rem_suffix_pattern << 6) | {26'd0, rem_suffix_count};
              end
              luma_res_symbol_count = luma_res_symbol_count + 8'd1;
            end

            if (sign_count_tmp != 6'd0) begin
              sign_bits_tmp = sign_bits_tmp << 1;
            end
            sign_bits_tmp = sign_bits_tmp | {31'd0, luma_coeff_negative[scan_raster_tmp]};
            sign_count_tmp = sign_count_tmp + 6'd1;
          end
        end
      end

      if (sign_count_tmp != 6'd0) begin
        if (luma_res_symbol_count == residual_step_q) begin
          luma_res_kind = SYMBOL_BINS_EP;
          luma_res_data = (sign_bits_tmp << 6) | {26'd0, sign_count_tmp};
        end
        luma_res_symbol_count = luma_res_symbol_count + 8'd1;
      end
    end
  end

  always @* begin
    chroma_res_kind = 8'd0;
    chroma_res_data = 32'd0;

    for (chroma_coeff_i = 0; chroma_coeff_i < 16; chroma_coeff_i = chroma_coeff_i + 1) begin
      chroma_coeff_level[chroma_coeff_i] = 9'sd0;
      chroma_coeff_abs[chroma_coeff_i] = 9'd0;
      chroma_coeff_negative[chroma_coeff_i] = 1'b0;
      chroma_coeff_template_abs[chroma_coeff_i] = 9'd0;
    end

    chroma_coeff_level[0] =
      chroma_res_cr_q ? cur_cr_dc_level_q : cur_cb_dc_level_q;
    for (chroma_coeff_i = 1; chroma_coeff_i < 16; chroma_coeff_i = chroma_coeff_i + 1) begin
      chroma_coeff_level[chroma_coeff_i] = chroma_res_cr_q ?
        $signed({{5{cur_cr_ac_levels_q[((15 - chroma_coeff_i) * 4) + 3]}},
                 cur_cr_ac_levels_q[((15 - chroma_coeff_i) * 4) +: 4]}) :
        $signed({{5{cur_cb_ac_levels_q[((15 - chroma_coeff_i) * 4) + 3]}},
                 cur_cb_ac_levels_q[((15 - chroma_coeff_i) * 4) +: 4]});
    end

    chroma_has_coeff = 1'b0;
    for (chroma_coeff_i = 0; chroma_coeff_i < 16; chroma_coeff_i = chroma_coeff_i + 1) begin
      chroma_coeff_abs_tmp = chroma_coeff_level[chroma_coeff_i][8] ?
        -$signed(chroma_coeff_level[chroma_coeff_i]) : chroma_coeff_level[chroma_coeff_i];
      chroma_coeff_abs[chroma_coeff_i] = chroma_coeff_abs_tmp;
      chroma_coeff_negative[chroma_coeff_i] = chroma_coeff_level[chroma_coeff_i][8];
      // H.266 9.3.4.2.7/9.3.4.2.8 local-template contexts use
      // min(4 + (absLevel & 1), absLevel), matching VTM sigCtxIdAbs.
      chroma_coeff_template_abs[chroma_coeff_i] =
        (chroma_coeff_abs_tmp < (9'd4 + {8'd0, chroma_coeff_abs_tmp[0]})) ?
        chroma_coeff_abs_tmp : (9'd4 + {8'd0, chroma_coeff_abs_tmp[0]});
      if (chroma_coeff_abs_tmp != 9'd0) begin
        chroma_has_coeff = 1'b1;
      end
    end

    chroma_last_scan_pos_tmp = 5'd0;
    chroma_last_x_tmp = 2'd0;
    chroma_last_y_tmp = 2'd0;
    for (chroma_scan_i = 0; chroma_scan_i < 16; chroma_scan_i = chroma_scan_i + 1) begin
      case (chroma_scan_i)
        0: begin chroma_scan_x_tmp = 4'd0; chroma_scan_y_tmp = 4'd0; chroma_scan_raster_tmp = 5'd0; end
        1: begin chroma_scan_x_tmp = 4'd0; chroma_scan_y_tmp = 4'd1; chroma_scan_raster_tmp = 5'd4; end
        2: begin chroma_scan_x_tmp = 4'd1; chroma_scan_y_tmp = 4'd0; chroma_scan_raster_tmp = 5'd1; end
        3: begin chroma_scan_x_tmp = 4'd0; chroma_scan_y_tmp = 4'd2; chroma_scan_raster_tmp = 5'd8; end
        4: begin chroma_scan_x_tmp = 4'd1; chroma_scan_y_tmp = 4'd1; chroma_scan_raster_tmp = 5'd5; end
        5: begin chroma_scan_x_tmp = 4'd2; chroma_scan_y_tmp = 4'd0; chroma_scan_raster_tmp = 5'd2; end
        6: begin chroma_scan_x_tmp = 4'd0; chroma_scan_y_tmp = 4'd3; chroma_scan_raster_tmp = 5'd12; end
        7: begin chroma_scan_x_tmp = 4'd1; chroma_scan_y_tmp = 4'd2; chroma_scan_raster_tmp = 5'd9; end
        8: begin chroma_scan_x_tmp = 4'd2; chroma_scan_y_tmp = 4'd1; chroma_scan_raster_tmp = 5'd6; end
        9: begin chroma_scan_x_tmp = 4'd3; chroma_scan_y_tmp = 4'd0; chroma_scan_raster_tmp = 5'd3; end
        10: begin chroma_scan_x_tmp = 4'd1; chroma_scan_y_tmp = 4'd3; chroma_scan_raster_tmp = 5'd13; end
        11: begin chroma_scan_x_tmp = 4'd2; chroma_scan_y_tmp = 4'd2; chroma_scan_raster_tmp = 5'd10; end
        12: begin chroma_scan_x_tmp = 4'd3; chroma_scan_y_tmp = 4'd1; chroma_scan_raster_tmp = 5'd7; end
        13: begin chroma_scan_x_tmp = 4'd2; chroma_scan_y_tmp = 4'd3; chroma_scan_raster_tmp = 5'd14; end
        14: begin chroma_scan_x_tmp = 4'd3; chroma_scan_y_tmp = 4'd2; chroma_scan_raster_tmp = 5'd11; end
        default: begin chroma_scan_x_tmp = 4'd3; chroma_scan_y_tmp = 4'd3; chroma_scan_raster_tmp = 5'd15; end
      endcase
      if (chroma_coeff_abs[chroma_scan_raster_tmp] != 9'd0) begin
        chroma_last_scan_pos_tmp = chroma_scan_i[4:0];
        chroma_last_x_tmp = chroma_scan_x_tmp[1:0];
        chroma_last_y_tmp = chroma_scan_y_tmp[1:0];
      end
    end
    chroma_last_scan_pos = chroma_last_scan_pos_tmp;
    chroma_last_x = chroma_last_x_tmp;
    chroma_last_y = chroma_last_y_tmp;

    chroma_res_symbol_count = 8'd0;
    chroma_sign_bits_tmp = 32'd0;
    chroma_sign_count_tmp = 6'd0;
    // H.266 7.3.11.11 residual_coding() derives remBinsPass1 from the
    // coefficient-zeroed TU area. A 4x4 chroma TU gets 28 bins, while wider
    // 4:2:0 chroma TUs keep the regular pass active longer.
    chroma_regular_bins_left_tmp =
      (({16'd0, cur_w_q} * {16'd0, cur_h_q} * 32'd28) >> 4);
    chroma_min_pos_2nd_pass_tmp = -1;
    chroma_num_nonzero_tmp = 0;
    chroma_last_x_cmax_tmp =
      (cur_w_q <= 16'd4) ? 3'd3 : ((cur_w_q <= 16'd8) ? 3'd5 : 3'd7);
    chroma_last_y_cmax_tmp =
      (cur_h_q <= 16'd4) ? 3'd3 : ((cur_h_q <= 16'd8) ? 3'd5 : 3'd7);

    if (chroma_has_coeff) begin
      for (chroma_bin_i = 0; chroma_bin_i < 4; chroma_bin_i = chroma_bin_i + 1) begin
        if ((chroma_bin_i < {30'd0, chroma_last_x}) ||
            ((chroma_bin_i == {30'd0, chroma_last_x}) &&
             ({1'b0, chroma_last_x} < chroma_last_x_cmax_tmp))) begin
          // H.266 9.3.4.2.4 derives chroma ctxShift as
          // Clip3(0, 2, (1 << log2TbSize) >> 3).
          chroma_last_ctx_offset_tmp =
            (cur_w_q <= 16'd4) ? chroma_bin_i[1:0] :
            ((cur_w_q <= 16'd8) ? {1'b0, chroma_bin_i[1]} : 2'd0);
          chroma_residual_ctx_tmp =
            CTX_LAST_SIG_X_PREFIX_20 + {7'd0, chroma_last_ctx_offset_tmp, 1'b0};
          if (chroma_res_symbol_count == residual_step_q) begin
            chroma_res_kind = SYMBOL_BIN_CTX;
            chroma_res_data = {
              14'd0, chroma_residual_ctx_tmp, 7'd0, (chroma_bin_i < {30'd0, chroma_last_x})
            };
          end
          chroma_res_symbol_count = chroma_res_symbol_count + 8'd1;
        end
      end
      for (chroma_bin_i = 0; chroma_bin_i < 4; chroma_bin_i = chroma_bin_i + 1) begin
        if ((chroma_bin_i < {30'd0, chroma_last_y}) ||
            ((chroma_bin_i == {30'd0, chroma_last_y}) &&
             ({1'b0, chroma_last_y} < chroma_last_y_cmax_tmp))) begin
          chroma_last_ctx_offset_tmp =
            (cur_h_q <= 16'd4) ? chroma_bin_i[1:0] :
            ((cur_h_q <= 16'd8) ? {1'b0, chroma_bin_i[1]} : 2'd0);
          chroma_residual_ctx_tmp =
            CTX_LAST_SIG_Y_PREFIX_20 + {7'd0, chroma_last_ctx_offset_tmp, 1'b0};
          if (chroma_res_symbol_count == residual_step_q) begin
            chroma_res_kind = SYMBOL_BIN_CTX;
            chroma_res_data = {
              14'd0, chroma_residual_ctx_tmp, 7'd0, (chroma_bin_i < {30'd0, chroma_last_y})
            };
          end
          chroma_res_symbol_count = chroma_res_symbol_count + 8'd1;
        end
      end

      for (chroma_scan_i = 15; chroma_scan_i >= 0; chroma_scan_i = chroma_scan_i - 1) begin
        case (chroma_scan_i)
          0: begin chroma_scan_x_tmp = 4'd0; chroma_scan_y_tmp = 4'd0; chroma_scan_raster_tmp = 5'd0; end
          1: begin chroma_scan_x_tmp = 4'd0; chroma_scan_y_tmp = 4'd1; chroma_scan_raster_tmp = 5'd4; end
          2: begin chroma_scan_x_tmp = 4'd1; chroma_scan_y_tmp = 4'd0; chroma_scan_raster_tmp = 5'd1; end
          3: begin chroma_scan_x_tmp = 4'd0; chroma_scan_y_tmp = 4'd2; chroma_scan_raster_tmp = 5'd8; end
          4: begin chroma_scan_x_tmp = 4'd1; chroma_scan_y_tmp = 4'd1; chroma_scan_raster_tmp = 5'd5; end
          5: begin chroma_scan_x_tmp = 4'd2; chroma_scan_y_tmp = 4'd0; chroma_scan_raster_tmp = 5'd2; end
          6: begin chroma_scan_x_tmp = 4'd0; chroma_scan_y_tmp = 4'd3; chroma_scan_raster_tmp = 5'd12; end
          7: begin chroma_scan_x_tmp = 4'd1; chroma_scan_y_tmp = 4'd2; chroma_scan_raster_tmp = 5'd9; end
          8: begin chroma_scan_x_tmp = 4'd2; chroma_scan_y_tmp = 4'd1; chroma_scan_raster_tmp = 5'd6; end
          9: begin chroma_scan_x_tmp = 4'd3; chroma_scan_y_tmp = 4'd0; chroma_scan_raster_tmp = 5'd3; end
          10: begin chroma_scan_x_tmp = 4'd1; chroma_scan_y_tmp = 4'd3; chroma_scan_raster_tmp = 5'd13; end
          11: begin chroma_scan_x_tmp = 4'd2; chroma_scan_y_tmp = 4'd2; chroma_scan_raster_tmp = 5'd10; end
          12: begin chroma_scan_x_tmp = 4'd3; chroma_scan_y_tmp = 4'd1; chroma_scan_raster_tmp = 5'd7; end
          13: begin chroma_scan_x_tmp = 4'd2; chroma_scan_y_tmp = 4'd3; chroma_scan_raster_tmp = 5'd14; end
          14: begin chroma_scan_x_tmp = 4'd3; chroma_scan_y_tmp = 4'd2; chroma_scan_raster_tmp = 5'd11; end
          default: begin chroma_scan_x_tmp = 4'd3; chroma_scan_y_tmp = 4'd3; chroma_scan_raster_tmp = 5'd15; end
        endcase

        if ((chroma_scan_i <= {27'd0, chroma_last_scan_pos}) &&
            (chroma_regular_bins_left_tmp >= 4)) begin
          chroma_min_pos_2nd_pass_tmp = chroma_scan_i - 1;
          chroma_loc_num_sig_tmp = 8'd0;
          chroma_loc_sum_abs_tmp = 9'd0;
          for (chroma_local_i = 0; chroma_local_i < 5; chroma_local_i = chroma_local_i + 1) begin
            case (chroma_local_i)
              0: begin chroma_local_x_i = chroma_scan_x_tmp + 1; chroma_local_y_i = chroma_scan_y_tmp; end
              1: begin chroma_local_x_i = chroma_scan_x_tmp + 2; chroma_local_y_i = chroma_scan_y_tmp; end
              2: begin chroma_local_x_i = chroma_scan_x_tmp + 1; chroma_local_y_i = chroma_scan_y_tmp + 1; end
              3: begin chroma_local_x_i = chroma_scan_x_tmp; chroma_local_y_i = chroma_scan_y_tmp + 1; end
              default: begin chroma_local_x_i = chroma_scan_x_tmp; chroma_local_y_i = chroma_scan_y_tmp + 2; end
            endcase
            chroma_mark_coeff_i = (chroma_local_y_i * 4) + chroma_local_x_i;
            if ((chroma_local_x_i < 4) && (chroma_local_y_i < 4) &&
                (chroma_coeff_abs[chroma_mark_coeff_i] != 9'd0)) begin
              chroma_loc_num_sig_tmp = chroma_loc_num_sig_tmp + 8'd1;
              chroma_loc_sum_abs_tmp =
                chroma_loc_sum_abs_tmp + chroma_coeff_template_abs[chroma_mark_coeff_i];
            end
          end

          if ((chroma_num_nonzero_tmp != 0) ||
              (chroma_scan_i != {27'd0, chroma_last_scan_pos})) begin
            chroma_sum_bucket_tmp = (chroma_loc_sum_abs_tmp[7:0] + 8'd1) >> 1;
            if (chroma_sum_bucket_tmp > 8'd3) begin
              chroma_sum_bucket_tmp = 8'd3;
            end
            chroma_d_sum_tmp = {4'd0, chroma_scan_x_tmp} + {4'd0, chroma_scan_y_tmp};
            chroma_residual_ctx_tmp =
              CTX_SIG_COEFF_FLAG_36 + {2'd0,
                ((8'd36 + chroma_sum_bucket_tmp +
                  ((chroma_d_sum_tmp < 8'd2) ? 8'd4 : 8'd0)) - 8'd36)
              };
            if (chroma_res_symbol_count == residual_step_q) begin
              chroma_res_kind = SYMBOL_BIN_CTX;
              chroma_res_data = {
                14'd0, chroma_residual_ctx_tmp, 7'd0,
                chroma_coeff_abs[chroma_scan_raster_tmp] != 9'd0
              };
            end
            chroma_res_symbol_count = chroma_res_symbol_count + 8'd1;
            chroma_regular_bins_left_tmp = chroma_regular_bins_left_tmp - 1;
          end

          if (chroma_coeff_abs[chroma_scan_raster_tmp] != 9'd0) begin
            chroma_num_nonzero_tmp = chroma_num_nonzero_tmp + 1;
            if ((chroma_scan_x_tmp[1:0] == chroma_last_x) &&
                (chroma_scan_y_tmp[1:0] == chroma_last_y)) begin
              chroma_ctx_offset_tmp = 8'd0;
              chroma_residual_ctx_tmp = 10'd21;
            end else begin
              chroma_ctx_offset_tmp = chroma_loc_sum_abs_tmp[7:0] - chroma_loc_num_sig_tmp;
              if (chroma_ctx_offset_tmp > 8'd4) begin
                chroma_ctx_offset_tmp = 8'd4;
              end
              chroma_d_sum_tmp = {4'd0, chroma_scan_x_tmp} + {4'd0, chroma_scan_y_tmp};
              chroma_residual_ctx_tmp =
                10'd22 + {2'd0, chroma_ctx_offset_tmp} +
                ((chroma_d_sum_tmp == 8'd0) ? 10'd5 : 10'd0);
            end

            chroma_level_ctx_inc_tmp = chroma_residual_ctx_tmp;
            if (chroma_level_ctx_inc_tmp[7:0] >= 8'd53) begin
              chroma_residual_ctx_tmp =
                CTX_ABS_LEVEL_GTX_FLAG_53 + {2'd0, (chroma_level_ctx_inc_tmp[7:0] - 8'd53)};
            end else begin
              chroma_residual_ctx_tmp =
                CTX_ABS_LEVEL_GTX_FLAG_21 + {2'd0, (chroma_level_ctx_inc_tmp[7:0] - 8'd21)};
            end
            if (chroma_res_symbol_count == residual_step_q) begin
              chroma_res_kind = SYMBOL_BIN_CTX;
              chroma_res_data = {
                14'd0, chroma_residual_ctx_tmp, 7'd0,
                chroma_coeff_abs[chroma_scan_raster_tmp] > 9'd1
              };
            end
            chroma_res_symbol_count = chroma_res_symbol_count + 8'd1;
            chroma_regular_bins_left_tmp = chroma_regular_bins_left_tmp - 1;

            if (chroma_coeff_abs[chroma_scan_raster_tmp] > 9'd1) begin
              chroma_residual_ctx_tmp =
                CTX_PAR_LEVEL_FLAG_21 + {2'd0, (chroma_level_ctx_inc_tmp[7:0] - 8'd21)};
              if (chroma_res_symbol_count == residual_step_q) begin
                chroma_res_kind = SYMBOL_BIN_CTX;
                chroma_res_data = {
                  14'd0, chroma_residual_ctx_tmp, 7'd0,
                  chroma_coeff_abs[chroma_scan_raster_tmp][0]
                };
              end
              chroma_res_symbol_count = chroma_res_symbol_count + 8'd1;
              chroma_regular_bins_left_tmp = chroma_regular_bins_left_tmp - 1;

              if ((chroma_level_ctx_inc_tmp[7:0] + 8'd32) >= 8'd53) begin
                chroma_residual_ctx_tmp =
                  CTX_ABS_LEVEL_GTX_FLAG_53 +
                  {2'd0, ((chroma_level_ctx_inc_tmp[7:0] + 8'd32) - 8'd53)};
              end else begin
                chroma_residual_ctx_tmp =
                  CTX_ABS_LEVEL_GTX_FLAG_21 +
                  {2'd0, ((chroma_level_ctx_inc_tmp[7:0] + 8'd32) - 8'd21)};
              end
              if (chroma_res_symbol_count == residual_step_q) begin
                chroma_res_kind = SYMBOL_BIN_CTX;
                chroma_res_data = {
                  14'd0, chroma_residual_ctx_tmp, 7'd0,
                  chroma_coeff_abs[chroma_scan_raster_tmp] > 9'd3
                };
              end
              chroma_res_symbol_count = chroma_res_symbol_count + 8'd1;
              chroma_regular_bins_left_tmp = chroma_regular_bins_left_tmp - 1;
            end

            if (chroma_coeff_abs[chroma_scan_raster_tmp] > 9'd3) begin
              chroma_rem_abs_value_tmp = (chroma_coeff_abs[chroma_scan_raster_tmp] - 9'd4) >> 1;
              chroma_rem_code_value_tmp = chroma_rem_abs_value_tmp - 9'd5;
              chroma_rem_prefix_extra_len_tmp = 3'd0;
              for (chroma_prefix_len_i = 0;
                   chroma_prefix_len_i < 7;
                   chroma_prefix_len_i = chroma_prefix_len_i + 1) begin
                if (chroma_rem_code_value_tmp >
                    ((9'd2 << chroma_prefix_len_i) - 9'd2)) begin
                  chroma_rem_prefix_extra_len_tmp = chroma_prefix_len_i[2:0] + 3'd1;
                end
              end
              chroma_rem_prefix_count_tmp =
                (chroma_rem_abs_value_tmp < 9'd5) ?
                {1'b0, chroma_rem_abs_value_tmp[4:0] + 5'd1} :
                {3'd0, chroma_rem_prefix_extra_len_tmp} + 6'd5;
              chroma_rem_prefix_pattern_tmp =
                (chroma_rem_abs_value_tmp < 9'd5) ?
                ((32'd1 << chroma_rem_prefix_count_tmp) - 32'd2) :
                ((32'd1 << chroma_rem_prefix_count_tmp) - 32'd1);
              chroma_rem_suffix_count_tmp =
                (chroma_rem_abs_value_tmp < 9'd5) ?
                6'd0 : {3'd0, chroma_rem_prefix_extra_len_tmp} + 6'd1;
              chroma_rem_suffix_pattern_tmp =
                (chroma_rem_abs_value_tmp < 9'd5) ? 32'd0 :
                (chroma_rem_code_value_tmp - ((32'd1 << chroma_rem_prefix_extra_len_tmp) - 32'd1));
              if (chroma_res_symbol_count == residual_step_q) begin
                chroma_res_kind = SYMBOL_BINS_EP;
                chroma_res_data =
                  (chroma_rem_prefix_pattern_tmp << 6) | {26'd0, chroma_rem_prefix_count_tmp};
              end
              chroma_res_symbol_count = chroma_res_symbol_count + 8'd1;
              if (chroma_res_symbol_count == residual_step_q) begin
                chroma_res_kind = SYMBOL_BINS_EP;
                chroma_res_data =
                  (chroma_rem_suffix_pattern_tmp << 6) | {26'd0, chroma_rem_suffix_count_tmp};
              end
              chroma_res_symbol_count = chroma_res_symbol_count + 8'd1;
            end

            if (chroma_sign_count_tmp != 6'd0) begin
              chroma_sign_bits_tmp = chroma_sign_bits_tmp << 1;
            end
            chroma_sign_bits_tmp =
              chroma_sign_bits_tmp | {31'd0, chroma_coeff_negative[chroma_scan_raster_tmp]};
            chroma_sign_count_tmp = chroma_sign_count_tmp + 6'd1;
          end
        end
      end

      for (chroma_scan_i = 15;
           chroma_scan_i >= 0;
           chroma_scan_i = chroma_scan_i - 1) begin
        if (chroma_scan_i <= chroma_min_pos_2nd_pass_tmp) begin
        case (chroma_scan_i)
          0: begin chroma_scan_x_tmp = 4'd0; chroma_scan_y_tmp = 4'd0; chroma_scan_raster_tmp = 5'd0; end
          1: begin chroma_scan_x_tmp = 4'd0; chroma_scan_y_tmp = 4'd1; chroma_scan_raster_tmp = 5'd4; end
          2: begin chroma_scan_x_tmp = 4'd1; chroma_scan_y_tmp = 4'd0; chroma_scan_raster_tmp = 5'd1; end
          3: begin chroma_scan_x_tmp = 4'd0; chroma_scan_y_tmp = 4'd2; chroma_scan_raster_tmp = 5'd8; end
          4: begin chroma_scan_x_tmp = 4'd1; chroma_scan_y_tmp = 4'd1; chroma_scan_raster_tmp = 5'd5; end
          5: begin chroma_scan_x_tmp = 4'd2; chroma_scan_y_tmp = 4'd0; chroma_scan_raster_tmp = 5'd2; end
          6: begin chroma_scan_x_tmp = 4'd0; chroma_scan_y_tmp = 4'd3; chroma_scan_raster_tmp = 5'd12; end
          7: begin chroma_scan_x_tmp = 4'd1; chroma_scan_y_tmp = 4'd2; chroma_scan_raster_tmp = 5'd9; end
          8: begin chroma_scan_x_tmp = 4'd2; chroma_scan_y_tmp = 4'd1; chroma_scan_raster_tmp = 5'd6; end
          9: begin chroma_scan_x_tmp = 4'd3; chroma_scan_y_tmp = 4'd0; chroma_scan_raster_tmp = 5'd3; end
          10: begin chroma_scan_x_tmp = 4'd1; chroma_scan_y_tmp = 4'd3; chroma_scan_raster_tmp = 5'd13; end
          11: begin chroma_scan_x_tmp = 4'd2; chroma_scan_y_tmp = 4'd2; chroma_scan_raster_tmp = 5'd10; end
          12: begin chroma_scan_x_tmp = 4'd3; chroma_scan_y_tmp = 4'd1; chroma_scan_raster_tmp = 5'd7; end
          13: begin chroma_scan_x_tmp = 4'd2; chroma_scan_y_tmp = 4'd3; chroma_scan_raster_tmp = 5'd14; end
          14: begin chroma_scan_x_tmp = 4'd3; chroma_scan_y_tmp = 4'd2; chroma_scan_raster_tmp = 5'd11; end
          default: begin chroma_scan_x_tmp = 4'd3; chroma_scan_y_tmp = 4'd3; chroma_scan_raster_tmp = 5'd15; end
        endcase

        chroma_rice_sum_abs_tmp = 9'd0;
        for (chroma_local_i = 0; chroma_local_i < 5; chroma_local_i = chroma_local_i + 1) begin
          case (chroma_local_i)
            0: begin chroma_local_x_i = chroma_scan_x_tmp + 1; chroma_local_y_i = chroma_scan_y_tmp; end
            1: begin chroma_local_x_i = chroma_scan_x_tmp + 2; chroma_local_y_i = chroma_scan_y_tmp; end
            2: begin chroma_local_x_i = chroma_scan_x_tmp + 1; chroma_local_y_i = chroma_scan_y_tmp + 1; end
            3: begin chroma_local_x_i = chroma_scan_x_tmp; chroma_local_y_i = chroma_scan_y_tmp + 1; end
            default: begin chroma_local_x_i = chroma_scan_x_tmp; chroma_local_y_i = chroma_scan_y_tmp + 2; end
          endcase
          chroma_mark_coeff_i = (chroma_local_y_i * 4) + chroma_local_x_i;
          if ((chroma_local_x_i < 4) && (chroma_local_y_i < 4)) begin
            chroma_rice_sum_abs_tmp =
              chroma_rice_sum_abs_tmp + chroma_coeff_abs[chroma_mark_coeff_i];
          end
        end

        if (chroma_rice_sum_abs_tmp <= 9'd6) begin
          chroma_rice_param_tmp = 3'd0;
        end else if (chroma_rice_sum_abs_tmp <= 9'd13) begin
          chroma_rice_param_tmp = 3'd1;
        end else if (chroma_rice_sum_abs_tmp <= 9'd27) begin
          chroma_rice_param_tmp = 3'd2;
        end else begin
          chroma_rice_param_tmp = 3'd3;
        end
        chroma_bypass_zero_pos_tmp = 9'd1 << chroma_rice_param_tmp;
        if (chroma_coeff_abs[chroma_scan_raster_tmp] == 9'd0) begin
          chroma_bypass_value_tmp = chroma_bypass_zero_pos_tmp;
        end else if (chroma_coeff_abs[chroma_scan_raster_tmp] <= chroma_bypass_zero_pos_tmp) begin
          chroma_bypass_value_tmp = chroma_coeff_abs[chroma_scan_raster_tmp] - 9'd1;
        end else begin
          chroma_bypass_value_tmp = chroma_coeff_abs[chroma_scan_raster_tmp];
        end

        chroma_rem_threshold_tmp = 9'd5 << chroma_rice_param_tmp;
        if (chroma_bypass_value_tmp < chroma_rem_threshold_tmp) begin
          chroma_rem_prefix_value_tmp = chroma_bypass_value_tmp >> chroma_rice_param_tmp;
          chroma_rem_prefix_count_tmp =
            {1'b0, chroma_rem_prefix_value_tmp[4:0]} + 6'd1;
          chroma_rem_prefix_pattern_tmp =
            (32'd1 << chroma_rem_prefix_count_tmp) - 32'd2;
          chroma_rem_suffix_count_tmp = {3'd0, chroma_rice_param_tmp};
          chroma_rem_suffix_pattern_tmp =
            chroma_bypass_value_tmp & ((32'd1 << chroma_rice_param_tmp) - 32'd1);
        end else begin
          chroma_rem_code_value_tmp =
            (chroma_bypass_value_tmp >> chroma_rice_param_tmp) - 9'd5;
          chroma_rem_prefix_extra_len_tmp = 3'd0;
          for (chroma_prefix_len_i = 0;
               chroma_prefix_len_i < 7;
               chroma_prefix_len_i = chroma_prefix_len_i + 1) begin
            if (chroma_rem_code_value_tmp >
                ((9'd2 << chroma_prefix_len_i) - 9'd2)) begin
              chroma_rem_prefix_extra_len_tmp = chroma_prefix_len_i[2:0] + 3'd1;
            end
          end
          chroma_rem_prefix_count_tmp =
            {3'd0, chroma_rem_prefix_extra_len_tmp} + 6'd5;
          chroma_rem_prefix_pattern_tmp =
            (32'd1 << chroma_rem_prefix_count_tmp) - 32'd1;
          chroma_rem_suffix_count_tmp =
            {3'd0, chroma_rem_prefix_extra_len_tmp} + {3'd0, chroma_rice_param_tmp} + 6'd1;
          chroma_rem_suffix_pattern_tmp =
            ((chroma_rem_code_value_tmp -
              ((32'd1 << chroma_rem_prefix_extra_len_tmp) - 32'd1)) << chroma_rice_param_tmp) |
            (chroma_bypass_value_tmp & ((32'd1 << chroma_rice_param_tmp) - 32'd1));
        end
        if (chroma_res_symbol_count == residual_step_q) begin
          chroma_res_kind = SYMBOL_BINS_EP;
          chroma_res_data =
            (chroma_rem_prefix_pattern_tmp << 6) | {26'd0, chroma_rem_prefix_count_tmp};
        end
        chroma_res_symbol_count = chroma_res_symbol_count + 8'd1;
        if (chroma_res_symbol_count == residual_step_q) begin
          chroma_res_kind = SYMBOL_BINS_EP;
          chroma_res_data =
            (chroma_rem_suffix_pattern_tmp << 6) | {26'd0, chroma_rem_suffix_count_tmp};
        end
        chroma_res_symbol_count = chroma_res_symbol_count + 8'd1;

        if (chroma_coeff_abs[chroma_scan_raster_tmp] != 9'd0) begin
          if (chroma_sign_count_tmp != 6'd0) begin
            chroma_sign_bits_tmp = chroma_sign_bits_tmp << 1;
          end
          chroma_sign_bits_tmp =
            chroma_sign_bits_tmp | {31'd0, chroma_coeff_negative[chroma_scan_raster_tmp]};
          chroma_sign_count_tmp = chroma_sign_count_tmp + 6'd1;
        end
        end
      end

      if (chroma_sign_count_tmp != 6'd0) begin
        if (chroma_res_symbol_count == residual_step_q) begin
          chroma_res_kind = SYMBOL_BINS_EP;
          chroma_res_data =
            (chroma_sign_bits_tmp << 6) | {26'd0, chroma_sign_count_tmp};
        end
        chroma_res_symbol_count = chroma_res_symbol_count + 8'd1;
      end
    end
  end
`endif

  ff_vvc_residual_symbol_emitter_4x4 residual_symbol_emitter_i (
    .clk(clk),
    .rst_n(rst_n),
    .clear(clear),
    .start(residual_emitter_start_q),
    .chroma_mode(cur_chroma_q),
    .tb_width(cur_w_q),
    .tb_height(cur_h_q),
    .luma_dc_abs(cur_luma_abs_level),
    .luma_dc_negative(cur_luma_negative),
    .luma_ac_levels(cur_luma_ac_levels),
    .chroma_dc_level(chroma_res_cr_q ? cur_cr_dc_level_q : cur_cb_dc_level_q),
    .chroma_ac_levels(chroma_res_cr_q ? cur_cr_ac_levels_q : cur_cb_ac_levels_q),
    .raw_coeff_levels({(9 * 16){1'b0}}),
    .m_axis_valid(residual_axis_valid),
    .m_axis_ready(residual_axis_ready),
    .m_axis_kind(residual_axis_kind),
    .m_axis_data(residual_axis_data),
    .done(residual_emitter_done),
    .busy(residual_emitter_busy)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_IDLE;
      stack_count_q <= 6'd0;
      chroma_started_q <= 1'b0;
      neighbour_clear_index_q <= 6'd0;
      m_axis_valid <= 1'b0;
      m_axis_kind <= 8'd0;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;
      cur_x_q <= 16'd0;
      cur_y_q <= 16'd0;
      cur_w_q <= 16'd0;
      cur_h_q <= 16'd0;
      cur_w_log2_q <= 3'd0;
      cur_h_log2_q <= 3'd0;
      cur_cqt_q <= 3'd0;
      cur_mtt_q <= 3'd0;
      cur_implicit_mtt_q <= 3'd0;
      cur_chroma_q <= 1'b0;
      chroma_tu_index_q <= 6'd0;
      cur_luma_abs_level <= 8'd0;
      cur_luma_negative <= 1'b0;
      cur_luma_ac_levels <= '0;
      cur_cb_dc_level_q <= 9'sd0;
      cur_cr_dc_level_q <= 9'sd0;
      cur_cb_ac_levels_q <= '0;
      cur_cr_ac_levels_q <= '0;
      split_is_qt_q <= 1'b0;
      split_vertical_q <= 1'b0;
      split_chroma_q <= 1'b0;
      split_implicit_q <= 1'b0;
      split_x_q <= 16'd0;
      split_y_q <= 16'd0;
      split_w_q <= 16'd0;
      split_h_q <= 16'd0;
      split_cqt_q <= 3'd0;
      split_mtt_q <= 3'd0;
      split_ctx_q <= 6'd0;
      split_write_split_q <= 1'b0;
      split_qt_ctx_q <= 6'd0;
      split_qt_bin_q <= 1'b0;
      split_write_qt_q <= 1'b0;
      split_write_mtt_q <= 1'b0;
      split_mtt_ctx_q <= 6'd0;
      split_write_binary_q <= 1'b0;
      split_binary_ctx_q <= 6'd0;
      split_push_phase_q <= 2'd0;
      leaf_cbf_q <= 1'b0;
      chroma_cbf_cb_q <= 1'b0;
      chroma_cbf_cr_q <= 1'b0;
      chroma_res_cr_q <= 1'b0;
      residual_emitter_start_q <= 1'b0;
      residual_step_q <= 8'd0;
    end else if (clear) begin
      state_q <= ST_IDLE;
      stack_count_q <= 6'd0;
      chroma_started_q <= 1'b0;
      neighbour_clear_index_q <= 6'd0;
      m_axis_valid <= 1'b0;
      m_axis_kind <= 8'd0;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;
      chroma_cbf_cb_q <= 1'b0;
      chroma_cbf_cr_q <= 1'b0;
      chroma_res_cr_q <= 1'b0;
      residual_emitter_start_q <= 1'b0;
      chroma_tu_index_q <= 6'd0;
      cur_luma_abs_level <= 8'd0;
      cur_luma_negative <= 1'b0;
      cur_luma_ac_levels <= '0;
      cur_cb_dc_level_q <= 9'sd0;
      cur_cr_dc_level_q <= 9'sd0;
      cur_cb_ac_levels_q <= '0;
      cur_cr_ac_levels_q <= '0;
      split_push_phase_q <= 2'd0;
      residual_step_q <= 8'd0;
    end else if (m_axis_valid && !m_axis_ready) begin
      state_q <= state_q;
    end else begin
      m_axis_valid <= 1'b0;
      m_axis_kind <= 8'd0;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;
      residual_emitter_start_q <= 1'b0;

      case (state_q)
        ST_IDLE: begin
          if (start) begin
            stack_count_q <= 6'd0;
            chroma_started_q <= 1'b0;
            chroma_tu_index_q <= 6'd0;
            neighbour_clear_index_q <= 6'd0;
            state_q <= ST_CLEAR_NEIGHBOURS;
          end
        end

        ST_CLEAR_NEIGHBOURS: begin
          luma_neighbour_depth_p1[neighbour_clear_index_q] <= 3'd0;
          chroma_neighbour_depth_p1[neighbour_clear_index_q] <= 3'd0;
          if (neighbour_clear_index_q == 6'd63) begin
            stack_x4[0] <= 4'd0;
            stack_y4[0] <= 4'd0;
            stack_w_log2[0] <= 3'd6;
            stack_h_log2[0] <= 3'd6;
            stack_cqt[0] <= 3'd0;
            stack_mtt[0] <= 3'd0;
            stack_implicit_mtt[0] <= 3'd0;
            stack_chroma[0] <= 1'b0;
            stack_count_q <= 6'd1;
            neighbour_clear_index_q <= 6'd0;
            state_q <= ST_POP;
          end else begin
            neighbour_clear_index_q <= neighbour_clear_index_q + 6'd1;
          end
        end

        ST_POP: begin
          if (stack_count_q == 6'd0) begin
            if (!chroma_started_q && dual_tree_chroma_enabled) begin
              stack_x4[0] <= 4'd0;
              stack_y4[0] <= 4'd0;
              stack_w_log2[0] <= 3'd5;
              stack_h_log2[0] <= 3'd5;
              stack_cqt[0] <= 3'd0;
              stack_mtt[0] <= 3'd0;
              stack_implicit_mtt[0] <= 3'd0;
              stack_chroma[0] <= 1'b1;
              stack_count_q <= 6'd1;
              chroma_started_q <= 1'b1;
              chroma_tu_index_q <= 6'd0;
              state_q <= ST_POP;
            end else begin
              state_q <= ST_DONE;
            end
          end else begin
            cur_x_q <= {10'd0, stack_x4[stack_pop_index], 2'd0};
            cur_y_q <= {10'd0, stack_y4[stack_pop_index], 2'd0};
            cur_w_q <= stack_pop_w;
            cur_h_q <= stack_pop_h;
            cur_w_log2_q <= stack_pop_w_log2;
            cur_h_log2_q <= stack_pop_h_log2;
            cur_cqt_q <= stack_cqt[stack_pop_index];
            cur_mtt_q <= stack_mtt[stack_pop_index];
            cur_implicit_mtt_q <= stack_implicit_mtt[stack_pop_index];
            cur_chroma_q <= stack_chroma[stack_pop_index];
            stack_count_q <= stack_count_q - 6'd1;
            state_q <= ST_DISPATCH;
          end
        end

        ST_DISPATCH: begin
          if (!cur_intersects) begin
            state_q <= ST_POP;
          end else if (cur_fits && cur_leaf_allowed) begin
            residual_step_q <= 8'd0;
            if (cur_chroma_q) begin
              chroma_cbf_cb_q <= cur_chroma_cbf_cb;
              chroma_cbf_cr_q <= cur_chroma_cbf_cr;
              chroma_res_cr_q <= 1'b0;
              cur_cb_dc_level_q <= dispatch_cb_dc_level_w;
              cur_cr_dc_level_q <= dispatch_cr_dc_level_w;
              cur_cb_ac_levels_q <= dispatch_cb_ac_levels_w;
              cur_cr_ac_levels_q <= dispatch_cr_ac_levels_w;
              chroma_tu_index_q <= chroma_tu_index_q + 6'd1;
              state_q <= ST_CHROMA_SPLIT;
            end else begin
              // H.266 7.3.11.10 emits tu_y_coded_flag for each luma
              // transform_unit(). The CTU-local quantizer supplies one bundle
              // per 8x8 leaf, so CBF must follow the current leaf rather than
              // the CTU origin.
              cur_luma_abs_level <= selected_luma_abs_level_w;
              cur_luma_negative <= selected_luma_negative_w;
              cur_luma_ac_levels <= selected_luma_ac_levels_w;
              leaf_cbf_q <= luma_has_coeff;
              state_q <= ST_LUMA_SPLIT;
            end
          end else if (!cur_fits) begin
            if (cur_chroma_q && cur_chroma_can_qt) begin
              // H.266 7.4.12.4 infers split_cu_flag at picture boundaries.
              // When QT and BTT are both legal, 7.3.11.4 still signals
              // split_qt_flag; the fixed 4x4 chroma subset mirrors the Rust
              // boundary preference and chooses QT before boundary BT.
              split_is_qt_q <= 1'b1;
              split_chroma_q <= 1'b1;
              split_implicit_q <= 1'b0;
              split_x_q <= cur_x_q;
              split_y_q <= cur_y_q;
              split_w_q <= cur_w_q;
              split_h_q <= cur_h_q;
              split_cqt_q <= cur_cqt_q;
              split_mtt_q <= cur_mtt_q;
              split_ctx_q <= cur_chroma_split_ctx;
              split_write_split_q <= 1'b0;
              split_qt_ctx_q <= cur_split_qt_ctx;
              split_qt_bin_q <= 1'b1;
              split_write_qt_q <=
                ((!cur_bottom_left_in_pic && cur_top_right_in_pic && cur_chroma_can_bh) ||
                 (cur_bottom_left_in_pic && !cur_top_right_in_pic && cur_chroma_can_bv));
              split_write_mtt_q <= 1'b0;
              split_mtt_ctx_q <= 6'd0;
              split_write_binary_q <= 1'b0;
              split_binary_ctx_q <= 6'd0;
              state_q <= ST_SPLIT_FLAG;
            end else if ((!cur_bottom_left_in_pic && !cur_top_right_in_pic) || !cur_implicit_bt_allowed) begin
              split_is_qt_q <= 1'b1;
              split_chroma_q <= cur_chroma_q;
              split_implicit_q <= 1'b0;
              split_x_q <= cur_x_q;
              split_y_q <= cur_y_q;
              split_w_q <= cur_w_q;
              split_h_q <= cur_h_q;
              split_cqt_q <= cur_cqt_q;
              split_mtt_q <= cur_mtt_q;
              state_q <= ST_SPLIT_PUSH;
            end else if (!cur_chroma_q && !cur_bottom_left_in_pic && cur_top_right_in_pic &&
                         cur_qt_flag_can_be_signaled &&
                         (cur_w_q > LUMA_MAX_LEAF_SIZE) &&
                         (cur_h_q > LUMA_MAX_LEAF_SIZE)) begin
              // H.266 coding_tree boundary handling, mirrored from the Rust
              // VvcCtuCabacOp::boundary_qt_preferred path: when only the
              // bottom edge is clipped and the luma CU is still larger than
              // the supported leaf/TU size, prefer QT and signal
              // split_qt_flag instead of forcing a horizontal BT.
              split_is_qt_q <= 1'b1;
              split_chroma_q <= 1'b0;
              split_implicit_q <= 1'b0;
              split_x_q <= cur_x_q;
              split_y_q <= cur_y_q;
              split_w_q <= cur_w_q;
              split_h_q <= cur_h_q;
              split_cqt_q <= cur_cqt_q;
              split_mtt_q <= cur_mtt_q;
              split_ctx_q <= cur_luma_split_ctx;
              split_write_split_q <= 1'b0;
              split_qt_ctx_q <= cur_split_qt_ctx;
              split_qt_bin_q <= 1'b1;
              split_write_qt_q <= cur_luma_can_qt &&
                (cur_luma_can_bh || cur_luma_can_bv || cur_luma_can_th || cur_luma_can_tv);
              split_write_mtt_q <= 1'b0;
              split_mtt_ctx_q <= 6'd0;
              split_write_binary_q <= 1'b0;
              split_binary_ctx_q <= 6'd0;
              state_q <= ST_SPLIT_FLAG;
            end else begin
              split_is_qt_q <= 1'b0;
              split_vertical_q <= !cur_top_right_in_pic;
              split_chroma_q <= cur_chroma_q;
              split_implicit_q <= 1'b1;
              split_x_q <= cur_x_q;
              split_y_q <= cur_y_q;
              split_w_q <= cur_w_q;
              split_h_q <= cur_h_q;
              split_cqt_q <= cur_cqt_q;
              split_mtt_q <= cur_mtt_q;
              split_ctx_q <= CTX_SPLIT_FLAG_3;
              split_write_split_q <= 1'b0;
              split_qt_ctx_q <= cur_split_qt_ctx;
              split_qt_bin_q <= 1'b0;
              split_write_qt_q <= cur_chroma_q ?
                (cur_chroma_can_qt &&
                 (cur_chroma_can_bh || cur_chroma_can_bv || cur_chroma_can_th || cur_chroma_can_tv)) :
                cur_qt_flag_can_be_signaled;
              split_write_mtt_q <= 1'b0;
              split_mtt_ctx_q <= cur_chroma_q ? cur_chroma_mtt_vertical_ctx : CTX_MTT_SPLIT_CU_VERTICAL_3;
              split_write_binary_q <= 1'b0;
              split_binary_ctx_q <= cur_chroma_q ? cur_chroma_mtt_binary_ctx :
                (!cur_top_right_in_pic ? CTX_MTT_SPLIT_CU_BINARY_3 : CTX_MTT_SPLIT_CU_BINARY_1);
              state_q <= ST_SPLIT_FLAG;
            end
          end else if (cur_chroma_q && (cur_w_q != cur_h_q)) begin
            split_is_qt_q <= 1'b0;
            split_vertical_q <= cur_chroma_fits_split_vertical;
            split_chroma_q <= 1'b1;
            split_implicit_q <= 1'b0;
            split_x_q <= cur_x_q;
            split_y_q <= cur_y_q;
            split_w_q <= cur_w_q;
            split_h_q <= cur_h_q;
            split_cqt_q <= cur_cqt_q;
            split_mtt_q <= cur_mtt_q;
            split_ctx_q <= cur_leaf_split_ctx;
            split_write_split_q <= cur_chroma_writes_split;
            split_qt_ctx_q <= cur_split_qt_ctx;
            split_qt_bin_q <= 1'b0;
            split_write_qt_q <= cur_chroma_can_qt;
            split_write_mtt_q <= cur_chroma_mtt_write_vertical;
            split_mtt_ctx_q <= cur_chroma_mtt_vertical_ctx;
            split_write_binary_q <= cur_chroma_mtt_write_binary;
            split_binary_ctx_q <= cur_chroma_mtt_binary_ctx;
            state_q <= ST_SPLIT_FLAG;
          end else if (!cur_chroma_q && cur_mtt_q != 3'd0) begin
            split_is_qt_q <= 1'b0;
            split_vertical_q <= fits_split_vertical;
            split_chroma_q <= 1'b0;
            split_implicit_q <= 1'b0;
            split_x_q <= cur_x_q;
            split_y_q <= cur_y_q;
            split_w_q <= cur_w_q;
            split_h_q <= cur_h_q;
            split_cqt_q <= cur_cqt_q;
            split_mtt_q <= cur_mtt_q;
            split_ctx_q <= cur_luma_split_ctx;
            split_write_split_q <= cur_luma_writes_split;
            split_qt_ctx_q <= cur_split_qt_ctx;
            split_qt_bin_q <= 1'b0;
            split_write_qt_q <= cur_qt_flag_can_be_signaled;
            split_write_mtt_q <= cur_mtt_write_vertical;
            split_mtt_ctx_q <= cur_mtt_vertical_ctx;
            split_write_binary_q <= cur_mtt_write_binary;
            split_binary_ctx_q <= cur_mtt_binary_ctx;
            state_q <= ST_SPLIT_FLAG;
          end else begin
            split_is_qt_q <= 1'b1;
            split_chroma_q <= cur_chroma_q;
            split_implicit_q <= 1'b0;
            split_x_q <= cur_x_q;
            split_y_q <= cur_y_q;
            split_w_q <= cur_w_q;
            split_h_q <= cur_h_q;
            split_cqt_q <= cur_cqt_q;
            split_mtt_q <= cur_mtt_q;
            split_ctx_q <= cur_chroma_q ? cur_chroma_split_ctx : cur_luma_split_ctx;
            split_write_split_q <= cur_chroma_q ? cur_chroma_writes_split : cur_luma_writes_split;
            split_qt_ctx_q <= cur_split_qt_ctx;
            split_qt_bin_q <= 1'b1;
            split_write_qt_q <= cur_chroma_q ?
              (cur_chroma_can_bh || cur_chroma_can_bv || cur_chroma_can_th || cur_chroma_can_tv) :
              ((cur_cqt_q != 3'd0) || (cur_mtt_q != 3'd0));
            split_write_mtt_q <= 1'b0;
            split_mtt_ctx_q <= 6'd0;
            split_write_binary_q <= 1'b0;
            split_binary_ctx_q <= 6'd0;
            state_q <= ST_SPLIT_FLAG;
          end
        end

        ST_SPLIT_FLAG: begin
          if (split_write_split_q) begin
            m_axis_valid <= 1'b1;
            m_axis_kind <= SYMBOL_BIN_CTX;
            m_axis_data <= {14'd0, split_ctx_q, 7'd0, 1'b1};
          end
          state_q <= ST_SPLIT_QT;
        end

        ST_SPLIT_QT: begin
          if (split_write_qt_q) begin
            m_axis_valid <= 1'b1;
            m_axis_kind <= SYMBOL_BIN_CTX;
            m_axis_data <= {14'd0, split_qt_ctx_q, 7'd0, split_qt_bin_q};
            state_q <= ST_SPLIT_MTT;
          end else begin
            state_q <= ST_SPLIT_MTT;
          end
        end

        ST_SPLIT_MTT: begin
          if (split_write_mtt_q) begin
            m_axis_valid <= 1'b1;
            m_axis_kind <= SYMBOL_BIN_CTX;
            m_axis_data <= {14'd0, split_mtt_ctx_q, 7'd0, split_vertical_q};
            state_q <= ST_SPLIT_BIN;
          end else begin
            state_q <= ST_SPLIT_BIN;
          end
        end

        ST_SPLIT_BIN: begin
          if (split_write_binary_q) begin
            m_axis_valid <= 1'b1;
            m_axis_kind <= SYMBOL_BIN_CTX;
            m_axis_data <= {14'd0, split_binary_ctx_q, 7'd0, 1'b1};
            state_q <= ST_SPLIT_PUSH;
          end else begin
            state_q <= ST_SPLIT_PUSH;
          end
          split_push_phase_q <= 2'd0;
        end

        ST_SPLIT_PUSH: begin
          if (split_is_qt_q) begin
            stack_w_log2[stack_count_q] <= split_w_log2_w - 3'd1;
            stack_h_log2[stack_count_q] <= split_h_log2_w - 3'd1;
            stack_cqt[stack_count_q] <= split_cqt_q + 3'd1;
            stack_mtt[stack_count_q] <= 3'd0;
            stack_implicit_mtt[stack_count_q] <= 3'd0;
            stack_chroma[stack_count_q] <= split_chroma_q;
            case (split_push_phase_q)
              2'd0: begin
                stack_x4[stack_count_q] <= split_x4_w + split_half_w4_w;
                stack_y4[stack_count_q] <= split_y4_w + split_half_h4_w;
              end
              2'd1: begin
                stack_x4[stack_count_q] <= split_x4_w;
                stack_y4[stack_count_q] <= split_y4_w + split_half_h4_w;
              end
              2'd2: begin
                stack_x4[stack_count_q] <= split_x4_w + split_half_w4_w;
                stack_y4[stack_count_q] <= split_y4_w;
              end
              default: begin
                stack_x4[stack_count_q] <= split_x4_w;
                stack_y4[stack_count_q] <= split_y4_w;
              end
            endcase
            stack_count_q <= stack_count_q + 6'd1;
            if (split_push_phase_q == 2'd3) begin
              split_push_phase_q <= 2'd0;
              state_q <= ST_POP;
            end else begin
              split_push_phase_q <= split_push_phase_q + 2'd1;
            end
          end else if (split_vertical_q) begin
            stack_x4[stack_count_q] <=
              (split_push_phase_q == 2'd0) ? (split_x4_w + split_half_w4_w) : split_x4_w;
            stack_y4[stack_count_q] <= split_y4_w;
            stack_w_log2[stack_count_q] <= split_w_log2_w - 3'd1;
            stack_h_log2[stack_count_q] <= split_h_log2_w;
            stack_cqt[stack_count_q] <= split_cqt_q;
            stack_mtt[stack_count_q] <= split_mtt_q + 3'd1;
            stack_implicit_mtt[stack_count_q] <= cur_implicit_mtt_q + {2'd0, split_implicit_q};
            stack_chroma[stack_count_q] <= split_chroma_q;
            stack_count_q <= stack_count_q + 6'd1;
            if (split_push_phase_q == 2'd1) begin
              split_push_phase_q <= 2'd0;
              state_q <= ST_POP;
            end else begin
              split_push_phase_q <= 2'd1;
            end
          end else begin
            stack_x4[stack_count_q] <= split_x4_w;
            stack_y4[stack_count_q] <=
              (split_push_phase_q == 2'd0) ? (split_y4_w + split_half_h4_w) : split_y4_w;
            stack_w_log2[stack_count_q] <= split_w_log2_w;
            stack_h_log2[stack_count_q] <= split_h_log2_w - 3'd1;
            stack_cqt[stack_count_q] <= split_cqt_q;
            stack_mtt[stack_count_q] <= split_mtt_q + 3'd1;
            stack_implicit_mtt[stack_count_q] <= cur_implicit_mtt_q + {2'd0, split_implicit_q};
            stack_chroma[stack_count_q] <= split_chroma_q;
            stack_count_q <= stack_count_q + 6'd1;
            if (split_push_phase_q == 2'd1) begin
              split_push_phase_q <= 2'd0;
              state_q <= ST_POP;
            end else begin
              split_push_phase_q <= 2'd1;
            end
          end
        end

        ST_LUMA_SPLIT: begin
          if (cur_leaf_writes_split) begin
            m_axis_valid <= 1'b1;
            m_axis_kind <= SYMBOL_BIN_CTX;
            m_axis_data <= {14'd0, cur_leaf_split_ctx, 7'd0, 1'b0};
          end
          state_q <= palette_partition_mode ? ST_PALETTE_LEAF : ST_LUMA_MRL;
        end

        ST_PALETTE_LEAF: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_PALETTE_LEAF;
          m_axis_data <= {cur_x_q, cur_y_q};
          m_axis_last <= (stack_count_q == 6'd0);
          luma_neighbour_depth_p1[cur_grid_index] <= cur_cqt_q + 3'd1;
          state_q <= ST_POP;
        end

        ST_LUMA_MRL: begin
          if (sps_mrl_enabled_flag && (cur_y_q != 16'd0)) begin
            m_axis_valid <= 1'b1;
            m_axis_kind <= SYMBOL_BIN_CTX;
            m_axis_data <= {14'd0, CTX_MULTI_REF_LINE_IDX_0, 7'd0, 1'b0};
          end
          state_q <= ST_LUMA_MPM;
        end

        ST_LUMA_MPM: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= {14'd0, CTX_INTRA_LUMA_MPM_FLAG, 7'd0, 1'b1};
          state_q <= ST_LUMA_MODE;
        end

        ST_LUMA_MODE: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= {14'd0, CTX_INTRA_LUMA_PLANAR_FLAG_1, 7'd0, 1'b1};
          state_q <= ST_LUMA_MPM_IDX;
        end

        ST_LUMA_MPM_IDX: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_EP;
          m_axis_data <= 32'd0;
          state_q <= ST_LUMA_CBF;
        end

        ST_LUMA_CBF: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= {14'd0, CTX_QT_CBF_Y_0, 7'd0, leaf_cbf_q};
          luma_neighbour_depth_p1[cur_grid_index] <= cur_cqt_q + 3'd1;
          residual_step_q <= 8'd0;
          if (leaf_cbf_q) begin
            residual_emitter_start_q <= 1'b1;
            state_q <= ST_LUMA_RESIDUAL;
          end else begin
            state_q <= ST_POP;
          end
        end

        ST_LUMA_RESIDUAL: begin
          if (residual_axis_valid) begin
            m_axis_valid <= 1'b1;
            m_axis_kind <= residual_axis_kind;
            m_axis_data <= residual_axis_data;
          end
          if (residual_emitter_done && !residual_axis_valid && !residual_emitter_start_q) begin
            state_q <= ST_POP;
          end
        end

        ST_CHROMA_SPLIT: begin
          if (cur_leaf_writes_split) begin
            m_axis_valid <= 1'b1;
            m_axis_kind <= SYMBOL_BIN_CTX;
            m_axis_data <= {14'd0, cur_leaf_split_ctx, 7'd0, 1'b0};
          end
          state_q <= (sps_cclm_enabled_flag && cur_chroma_cclm_allowed) ? ST_CHROMA_CCLM : ST_CHROMA_MODE;
        end

        ST_CHROMA_CCLM: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= {14'd0, CTX_CCLM_MODE_FLAG, 7'd0, 1'b0};
          state_q <= ST_CHROMA_MODE;
        end

        ST_CHROMA_MODE: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= {14'd0, CTX_INTRA_CHROMA_PRED_MODE_0, 7'd0, 1'b0};
          residual_step_q <= 8'd0;
          state_q <= ST_CHROMA_CBF_CB;
        end

        ST_CHROMA_CBF_CB: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= {14'd0, CTX_QT_CBF_CB_0, 7'd0, chroma_cbf_cb_q};
          state_q <= ST_CHROMA_CBF_CR;
        end

        ST_CHROMA_CBF_CR: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= {
            14'd0,
            (chroma_cbf_cb_q ? CTX_QT_CBF_CR_1 : CTX_QT_CBF_CR_0),
            7'd0,
            chroma_cbf_cr_q
          };
          // H.266 9.3.4.2.2 split contexts use coded neighbouring chroma CU
          // sizes. Mark the fixed 4x4 chroma leaf once its transform_unit()
          // CBF syntax has been emitted; later siblings see the same state as
          // the Rust/VTM traversal.
          chroma_neighbour_depth_p1[cur_chroma_grid_index] <= cur_cqt_q + 3'd1;
          residual_step_q <= 8'd0;
          if (chroma_cbf_cb_q) begin
            chroma_res_cr_q <= 1'b0;
            residual_emitter_start_q <= 1'b1;
            state_q <= ST_CHROMA_RESIDUAL;
          end else if (chroma_cbf_cr_q) begin
            chroma_res_cr_q <= 1'b1;
            residual_emitter_start_q <= 1'b1;
            state_q <= ST_CHROMA_RESIDUAL;
          end else begin
            state_q <= ST_POP;
          end
        end

        ST_CHROMA_RESIDUAL: begin
          if (residual_axis_valid) begin
            m_axis_valid <= 1'b1;
            m_axis_kind <= residual_axis_kind;
            m_axis_data <= residual_axis_data;
          end
          if (residual_emitter_done && !residual_axis_valid && !residual_emitter_start_q) begin
            if (!chroma_res_cr_q && chroma_cbf_cr_q) begin
              chroma_res_cr_q <= 1'b1;
              residual_emitter_start_q <= 1'b1;
              state_q <= ST_CHROMA_RESIDUAL;
            end else begin
              state_q <= ST_POP;
            end
          end
        end

        ST_DONE: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_TRM;
          m_axis_data <= {31'd0, 1'b1};
          m_axis_last <= 1'b1;
          state_q <= ST_IDLE;
        end

        default: begin
          state_q <= ST_IDLE;
        end
      endcase
    end
  end
endmodule
