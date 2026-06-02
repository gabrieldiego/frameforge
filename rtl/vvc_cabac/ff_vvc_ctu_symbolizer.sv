`timescale 1ns/1ps

module ff_vvc_ctu_symbolizer #(
  parameter int CTU_SIZE = 64
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        clear,
  input  logic        start,
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,
  input  logic [1:0]  chroma_format_idc,
  input  logic [4:0]  luma_abs_level,
  input  logic        luma_negative,
  input  logic [4:0]  cb_abs_level,
  input  logic        cb_negative,
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
  // With sps_max_luma_transform_size_64_flag enabled, the current 4:2:0
  // chroma transform block limit is MaxTbSizeY/SubWidthC by
  // MaxTbSizeY/SubHeightC, i.e. 32x32 chroma samples. Keep this as the chroma
  // leaf stopper; smaller 4x4-era leaves are an implementation detail of older
  // test paths and would force non-spec partition syntax.
  localparam logic [15:0] CHROMA_MAX_LEAF_SIZE = 16'd32;
  localparam logic [15:0] CHROMA_MAX_BT_SIZE_LUMA = 16'd64;
  localparam logic [15:0] CHROMA_MAX_TT_SIZE_LUMA = 16'd32;
  localparam logic [15:0] CHROMA_BOUNDARY_LEAF_SIZE = CHROMA_MAX_BT_SIZE_LUMA >> 1;
  localparam logic [15:0] CHROMA_ROOT_SIZE = CTU_SIZE_L >> 1;
  localparam logic [15:0] DUAL_TREE_CHROMA_LUMA_CU_SIZE = 16'd32;
  localparam logic [15:0] DUAL_TREE_CHROMA_CU_SIZE = DUAL_TREE_CHROMA_LUMA_CU_SIZE >> 1;
  localparam logic [15:0] LUMA_MIN_QT_SIZE = 16'd8;
  localparam logic [15:0] CHROMA_MIN_QT_SIZE = 16'd4;
  localparam int STACK_DEPTH = 32;
  localparam int LUMA_NEIGHBOUR_GRID = CTU_SIZE / 8;
  localparam int LUMA_NEIGHBOUR_CELLS = LUMA_NEIGHBOUR_GRID * LUMA_NEIGHBOUR_GRID;

  localparam logic [5:0] CTX_SPLIT_FLAG_0 = 6'd0;
  localparam logic [5:0] CTX_SPLIT_FLAG_6 = 6'd1;
  localparam logic [5:0] CTX_SPLIT_QT_FLAG_3 = 6'd2;
  localparam logic [5:0] CTX_SPLIT_FLAG_3 = 6'd3;
  localparam logic [5:0] CTX_INTRA_LUMA_MPM_FLAG = 6'd4;
  localparam logic [5:0] CTX_QT_CBF_Y_0 = 6'd5;
  localparam logic [5:0] CTX_LAST_SIG_X_PREFIX_3 = 6'd6;
  localparam logic [5:0] CTX_LAST_SIG_Y_PREFIX_3 = 6'd7;
  localparam logic [5:0] CTX_LAST_SIG_X_PREFIX_6 = 6'd8;
  localparam logic [5:0] CTX_LAST_SIG_Y_PREFIX_6 = 6'd9;
  localparam logic [5:0] CTX_ABS_LEVEL_GTX_FLAG_0 = 6'd10;
  localparam logic [5:0] CTX_PAR_LEVEL_FLAG_0 = 6'd11;
  localparam logic [5:0] CTX_ABS_LEVEL_GTX_FLAG_32 = 6'd12;
  localparam logic [5:0] CTX_CCLM_MODE_FLAG = 6'd13;
  localparam logic [5:0] CTX_INTRA_CHROMA_PRED_MODE_0 = 6'd14;
  localparam logic [5:0] CTX_QT_CBF_CB_0 = 6'd15;
  localparam logic [5:0] CTX_QT_CBF_CR_0 = 6'd16;
  localparam logic [5:0] CTX_LAST_SIG_X_PREFIX_10 = 6'd17;
  localparam logic [5:0] CTX_LAST_SIG_Y_PREFIX_10 = 6'd18;
  localparam logic [5:0] CTX_SPLIT_FLAG_7 = 6'd19;
  localparam logic [5:0] CTX_SPLIT_QT_FLAG_0 = 6'd20;
  localparam logic [5:0] CTX_MULTI_REF_LINE_IDX_0 = 6'd21;
  localparam logic [5:0] CTX_LAST_SIG_X_PREFIX_15 = 6'd22;
  localparam logic [5:0] CTX_LAST_SIG_Y_PREFIX_15 = 6'd23;
  localparam logic [5:0] CTX_MTT_SPLIT_CU_VERTICAL_3 = 6'd24;
  localparam logic [5:0] CTX_MTT_SPLIT_CU_BINARY_1 = 6'd25;
  localparam logic [5:0] CTX_MTT_SPLIT_CU_BINARY_3 = 6'd26;
  localparam logic [5:0] CTX_SPLIT_FLAG_1 = 6'd27;
  localparam logic [5:0] CTX_SPLIT_FLAG_2 = 6'd28;
  localparam logic [5:0] CTX_MTT_SPLIT_CU_VERTICAL_0 = 6'd29;
  localparam logic [5:0] CTX_MTT_SPLIT_CU_VERTICAL_4 = 6'd30;
  localparam logic [5:0] CTX_MTT_SPLIT_CU_BINARY_0 = 6'd31;
  localparam logic [5:0] CTX_MTT_SPLIT_CU_BINARY_2 = 6'd32;
  localparam logic [5:0] CTX_SPLIT_FLAG_4 = 6'd33;
  localparam logic [5:0] CTX_SPLIT_QT_FLAG_1 = 6'd34;
  localparam logic [5:0] CTX_SPLIT_QT_FLAG_2 = 6'd35;
  localparam logic [5:0] CTX_SPLIT_QT_FLAG_4 = 6'd36;
  localparam logic [5:0] CTX_SPLIT_QT_FLAG_5 = 6'd37;
  localparam logic [5:0] CTX_SPLIT_FLAG_5 = 6'd38;
  localparam logic [5:0] CTX_SPLIT_FLAG_8 = 6'd39;
  localparam logic [5:0] CTX_MTT_SPLIT_CU_VERTICAL_1 = 6'd40;
  localparam logic [5:0] CTX_MTT_SPLIT_CU_VERTICAL_2 = 6'd41;

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

  logic [4:0] state_q;
  logic [5:0] stack_count_q;
  logic [15:0] stack_x [0:STACK_DEPTH - 1];
  logic [15:0] stack_y [0:STACK_DEPTH - 1];
  logic [15:0] stack_w [0:STACK_DEPTH - 1];
  logic [15:0] stack_h [0:STACK_DEPTH - 1];
  logic [2:0] stack_cqt [0:STACK_DEPTH - 1];
  logic [2:0] stack_mtt [0:STACK_DEPTH - 1];
  logic [2:0] stack_implicit_mtt [0:STACK_DEPTH - 1];
  logic stack_chroma [0:STACK_DEPTH - 1];

  logic luma_neighbour_valid [0:LUMA_NEIGHBOUR_CELLS - 1];
  logic [15:0] luma_neighbour_width [0:LUMA_NEIGHBOUR_CELLS - 1];
  logic [15:0] luma_neighbour_height [0:LUMA_NEIGHBOUR_CELLS - 1];
  logic [2:0] luma_neighbour_qt_depth [0:LUMA_NEIGHBOUR_CELLS - 1];

  integer neighbour_i;
  integer mark_x_i;
  integer mark_y_i;

  logic [5:0] cur_grid_x;
  logic [5:0] cur_grid_y;
  logic [5:0] cur_left_grid_index;
  logic [5:0] cur_above_grid_index;
  logic cur_luma_left_valid;
  logic cur_luma_above_valid;
  logic [15:0] cur_luma_left_width;
  logic [15:0] cur_luma_left_height;
  logic [2:0] cur_luma_left_qt_depth;
  logic [15:0] cur_luma_above_width;
  logic [15:0] cur_luma_above_height;
  logic [2:0] cur_luma_above_qt_depth;

  logic [15:0] cur_x_q;
  logic [15:0] cur_y_q;
  logic [15:0] cur_w_q;
  logic [15:0] cur_h_q;
  logic [2:0] cur_cqt_q;
  logic [2:0] cur_mtt_q;
  logic [2:0] cur_implicit_mtt_q;
  logic cur_chroma_q;
  logic chroma_started_q;

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
  logic [5:0] split_ctx_q;
  logic split_write_split_q;
  logic [5:0] split_qt_ctx_q;
  logic split_qt_bin_q;
  logic split_write_qt_q;
  logic split_write_mtt_q;
  logic [5:0] split_mtt_ctx_q;
  logic split_write_binary_q;
  logic [5:0] split_binary_ctx_q;

  logic leaf_cbf_q;
  logic chroma_cbf_cb_q;
  logic [3:0] residual_step_q;
  logic [4:0] rem_abs_value;
  logic [4:0] rem_code_value;
  logic [2:0] rem_prefix_extra_len;
  logic [5:0] rem_prefix_count;
  logic [31:0] rem_prefix_pattern;
  logic [5:0] rem_suffix_count;
  logic [31:0] rem_suffix_pattern;
  logic [4:0] cb_rem_code_value;
  logic [2:0] cb_rem_prefix_extra_len;
  logic [5:0] cb_rem_prefix_count;
  logic [31:0] cb_rem_prefix_pattern;
  logic [5:0] cb_rem_suffix_count;
  logic [31:0] cb_rem_suffix_pattern;
  logic [5:0] cur_last_sig_x_ctx;
  logic [5:0] cur_last_sig_y_ctx;
  logic [5:0] cur_leaf_split_ctx;
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
  logic [5:0] cur_split_qt_ctx;
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
  logic [15:0] cur_mtt_dep_above;
  logic [15:0] cur_mtt_dep_left;
  logic [5:0] cur_mtt_vertical_ctx;
  logic cur_mtt_write_vertical;
  logic cur_mtt_write_binary;
  logic [5:0] cur_mtt_binary_ctx;
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
  logic [5:0] cur_luma_split_ctx;
  logic cur_luma_writes_split;
  logic [15:0] cur_chroma_luma_width;
  logic [15:0] cur_chroma_luma_height;
  logic [31:0] cur_chroma_area;
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
  logic [5:0] cur_chroma_split_ctx;
  logic cur_chroma_writes_split;
  logic [2:0] unused_luma_log2;

  assign busy = (state_q != ST_IDLE) || m_axis_valid;
  assign dual_tree_chroma_enabled = (chroma_format_idc != 2'd0) && (chroma_format_idc != 2'd3);
  assign cur_grid_x = cur_x_q >> 3;
  assign cur_grid_y = cur_y_q >> 3;
  assign cur_left_grid_index = (cur_grid_y * LUMA_NEIGHBOUR_GRID) + cur_grid_x - 6'd1;
  assign cur_above_grid_index = ((cur_grid_y - 6'd1) * LUMA_NEIGHBOUR_GRID) + cur_grid_x;
  assign cur_luma_left_valid = !cur_chroma_q && (cur_x_q != 16'd0) &&
    luma_neighbour_valid[cur_left_grid_index];
  assign cur_luma_above_valid = !cur_chroma_q && (cur_y_q != 16'd0) &&
    luma_neighbour_valid[cur_above_grid_index];
  assign cur_luma_left_width = cur_luma_left_valid ? luma_neighbour_width[cur_left_grid_index] : 16'd0;
  assign cur_luma_left_height = cur_luma_left_valid ? luma_neighbour_height[cur_left_grid_index] : 16'd0;
  assign cur_luma_left_qt_depth = cur_luma_left_valid ? luma_neighbour_qt_depth[cur_left_grid_index] : 3'd0;
  assign cur_luma_above_width = cur_luma_above_valid ? luma_neighbour_width[cur_above_grid_index] : 16'd0;
  assign cur_luma_above_height = cur_luma_above_valid ? luma_neighbour_height[cur_above_grid_index] : 16'd0;
  assign cur_luma_above_qt_depth = cur_luma_above_valid ? luma_neighbour_qt_depth[cur_above_grid_index] : 3'd0;

  assign cur_visible_width = cur_chroma_q ? (visible_width >> 1) : visible_width;
  assign cur_visible_height = cur_chroma_q ? (visible_height >> 1) : visible_height;
  assign cur_leaf_max = cur_chroma_q ? CHROMA_MAX_LEAF_SIZE : LUMA_MAX_LEAF_SIZE;
  assign cur_boundary_leaf_max = cur_chroma_q ? CHROMA_BOUNDARY_LEAF_SIZE : LUMA_BOUNDARY_BT_SIZE;
  assign cur_min_qt_size = cur_chroma_q ? CHROMA_MIN_QT_SIZE : LUMA_MIN_QT_SIZE;
  assign cur_qt_flag_can_be_signaled = (cur_mtt_q == 3'd0) &&
    (cur_w_q > cur_min_qt_size) && (cur_h_q > cur_min_qt_size);
  // ITU-T H.266 clause 9.3.4.2.2, Table 133 derives split_qt_flag ctxInc from
  // the actual neighbouring CU QT depths in the current channel. Track coded
  // luma leaves on an 8x8 CTU grid so boundary and thin-picture cases do not
  // confuse a geometrically smaller neighbour with a deeper QT neighbour.
  assign cur_qt_left_deeper = cur_luma_left_valid &&
    (cur_luma_left_qt_depth > cur_cqt_q);
  assign cur_qt_above_deeper = cur_luma_above_valid &&
    (cur_luma_above_qt_depth > cur_cqt_q);
  assign cur_qt_ctx_inc = ((cur_cqt_q >= 3'd2) ? 3'd3 : 3'd0) +
    {2'd0, cur_qt_left_deeper} + {2'd0, cur_qt_above_deeper};
  assign cur_leaf_allowed = cur_chroma_q ?
    (((cur_w_q <= CHROMA_MAX_LEAF_SIZE) && (cur_h_q <= CHROMA_MAX_LEAF_SIZE)) ||
     ((cur_mtt_q != 3'd0) &&
      (((cur_w_q <= CHROMA_BOUNDARY_LEAF_SIZE) && (cur_h_q <= CHROMA_MAX_LEAF_SIZE)) ||
       ((cur_h_q <= CHROMA_BOUNDARY_LEAF_SIZE) && (cur_w_q <= CHROMA_MAX_LEAF_SIZE)) ||
       ((cur_w_q <= (CHROMA_BOUNDARY_LEAF_SIZE >> 1)) && (cur_h_q <= (CHROMA_BOUNDARY_LEAF_SIZE >> 1)))))) :
    ((cur_w_q <= LUMA_MAX_LEAF_SIZE) && (cur_h_q <= LUMA_MAX_LEAF_SIZE));
  // VTM CodingUnit::checkCCLMAllowed implements the VVC dual-tree CCLM
  // restrictions. For the current 4:2:0 residual path, chroma CUs are derived
  // from 32x32 luma regions after a root QT split, so CCLM is legal when the
  // resulting chroma node is no larger than 16x16. Keep the other root-path
  // cases labeled for future mixed split support.
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
  assign cur_mtt_dep_above = (cur_luma_above_valid && (cur_luma_above_width != 16'd0)) ?
    (cur_w_q / cur_luma_above_width) : 16'd0;
  assign cur_mtt_dep_left = (cur_luma_left_valid && (cur_luma_left_height != 16'd0)) ?
    (cur_h_q / cur_luma_left_height) : 16'd0;
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
    {1'b0, (cur_luma_left_valid && (cur_luma_left_height < cur_h_q))} +
    {1'b0, (cur_luma_above_valid && (cur_luma_above_width < cur_w_q))};
  assign cur_luma_split_ctx_inc =
    ((cur_luma_split_alternatives >= 4'd5) ? 4'd6 :
    ((cur_luma_split_alternatives >= 4'd3) ? 4'd3 : 4'd0)) +
    {2'd0, cur_luma_split_neighbour_ctx};
  always_comb begin
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
  assign cur_chroma_area = {16'd0, cur_w_q} * {16'd0, cur_h_q};
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
    (cur_chroma_area > MIN_DUALTREE_CHROMA_AREA);
  assign cur_chroma_can_bv = cur_chroma_can_btt && !cur_chroma_exceeds_bt_size &&
    (cur_chroma_luma_width > MIN_CODING_BLOCK_SIZE) &&
    !((cur_chroma_luma_width <= MAX_TB_SIZEY) && (cur_chroma_luma_height > MAX_TB_SIZEY)) &&
    (cur_chroma_area > MIN_DUALTREE_CHROMA_AREA) &&
    (cur_w_q != MIN_DUALTREE_CHROMA_WIDTH);
  assign cur_chroma_can_th = cur_chroma_can_btt &&
    (cur_chroma_luma_height > (MIN_CODING_BLOCK_SIZE << 1)) &&
    (cur_chroma_luma_height <= CHROMA_MAX_TT_SIZE_LUMA) &&
    (cur_chroma_luma_width <= CHROMA_MAX_TT_SIZE_LUMA) &&
    (cur_chroma_luma_width <= MAX_TB_SIZEY) &&
    (cur_chroma_luma_height <= MAX_TB_SIZEY) &&
    (cur_chroma_area > (MIN_DUALTREE_CHROMA_AREA << 1));
  assign cur_chroma_can_tv = cur_chroma_can_btt &&
    (cur_chroma_luma_width > (MIN_CODING_BLOCK_SIZE << 1)) &&
    (cur_chroma_luma_width <= CHROMA_MAX_TT_SIZE_LUMA) &&
    (cur_chroma_luma_height <= CHROMA_MAX_TT_SIZE_LUMA) &&
    (cur_chroma_luma_width <= MAX_TB_SIZEY) &&
    (cur_chroma_luma_height <= MAX_TB_SIZEY) &&
    (cur_chroma_area > (MIN_DUALTREE_CHROMA_AREA << 1)) &&
    (cur_w_q != (MIN_DUALTREE_CHROMA_WIDTH << 1));
  assign cur_chroma_split_alternatives =
    {3'd0, cur_chroma_can_bh} + {3'd0, cur_chroma_can_bv} +
    {3'd0, cur_chroma_can_th} + {3'd0, cur_chroma_can_tv} +
    {2'd0, cur_chroma_can_qt, 1'b0};
  // ITU-T H.266 clause 9.3.4.2.2, Table 133 derives
  // split_cu_flag ctxInc from legal split alternatives plus left/above coded
  // CUs that are smaller in the current channel. Our current chroma traversal
  // reaches larger boundary children after adjacent 4x4 leaves, so these
  // simple neighbour flags model CbHeight/CbWidth comparisons until a full
  // coded-CU neighbour table is wired.
  assign cur_chroma_split_neighbour_ctx =
    {1'b0, ((cur_x_q != 16'd0) && (cur_h_q > CHROMA_MAX_LEAF_SIZE))} +
    {1'b0, ((cur_y_q != 16'd0) && (cur_w_q > CHROMA_MAX_LEAF_SIZE))};
  assign cur_chroma_split_ctx_inc =
    ((cur_chroma_split_alternatives >= 4'd5) ? 4'd6 :
    ((cur_chroma_split_alternatives >= 4'd3) ? 4'd3 : 4'd0)) +
    {2'd0, cur_chroma_split_neighbour_ctx};
  always_comb begin
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
  assign unused_luma_log2 = luma_log2_tb_width ^ luma_log2_tb_height;


  always_comb begin
    case (cur_qt_ctx_inc)
      3'd0: cur_split_qt_ctx = CTX_SPLIT_QT_FLAG_0;
      3'd1: cur_split_qt_ctx = CTX_SPLIT_QT_FLAG_1;
      3'd2: cur_split_qt_ctx = CTX_SPLIT_QT_FLAG_2;
      3'd3: cur_split_qt_ctx = CTX_SPLIT_QT_FLAG_3;
      3'd4: cur_split_qt_ctx = CTX_SPLIT_QT_FLAG_4;
      default: cur_split_qt_ctx = CTX_SPLIT_QT_FLAG_5;
    endcase
  end

  always_comb begin
    if (cur_w_q >= 16'd64) begin
      cur_last_sig_x_ctx = CTX_LAST_SIG_X_PREFIX_15;
    end else if (cur_w_q >= 16'd32) begin
      cur_last_sig_x_ctx = CTX_LAST_SIG_X_PREFIX_10;
    end else if (cur_w_q >= 16'd16) begin
      cur_last_sig_x_ctx = CTX_LAST_SIG_X_PREFIX_6;
    end else begin
      cur_last_sig_x_ctx = CTX_LAST_SIG_X_PREFIX_3;
    end

    if (cur_h_q >= 16'd64) begin
      cur_last_sig_y_ctx = CTX_LAST_SIG_Y_PREFIX_15;
    end else if (cur_h_q >= 16'd32) begin
      cur_last_sig_y_ctx = CTX_LAST_SIG_Y_PREFIX_10;
    end else if (cur_h_q >= 16'd16) begin
      cur_last_sig_y_ctx = CTX_LAST_SIG_Y_PREFIX_6;
    end else begin
      cur_last_sig_y_ctx = CTX_LAST_SIG_Y_PREFIX_3;
    end
  end

  always_comb begin
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


  assign rem_abs_value = (luma_abs_level - 5'd4) >> 1;
  assign rem_code_value = rem_abs_value - 5'd5;
  assign rem_prefix_extra_len =
    (rem_code_value <= 5'd0) ? 3'd0 :
    ((rem_code_value <= 5'd2) ? 3'd1 :
    ((rem_code_value <= 5'd6) ? 3'd2 : 3'd3));
  assign rem_prefix_count =
    (rem_abs_value < 5'd5) ? {1'b0, rem_abs_value + 5'd1} : {3'd0, rem_prefix_extra_len} + 6'd5;
  assign rem_prefix_pattern =
    (rem_abs_value < 5'd5) ?
    ((32'd1 << rem_prefix_count) - 32'd2) :
    ((32'd1 << rem_prefix_count) - 32'd1);
  assign rem_suffix_count = (rem_abs_value < 5'd5) ? 6'd0 : {3'd0, rem_prefix_extra_len} + 6'd1;
  assign rem_suffix_pattern =
    (rem_abs_value < 5'd5) ? 32'd0 :
    (rem_code_value - ((32'd1 << rem_prefix_extra_len) - 32'd1));

  assign cb_rem_code_value = cb_abs_level - 5'd5;
  assign cb_rem_prefix_extra_len =
    (cb_rem_code_value <= 5'd0) ? 3'd0 :
    ((cb_rem_code_value <= 5'd2) ? 3'd1 :
    ((cb_rem_code_value <= 5'd6) ? 3'd2 : 3'd3));
  assign cb_rem_prefix_count =
    (cb_abs_level < 5'd5) ? {1'b0, cb_abs_level + 5'd1} : {3'd0, cb_rem_prefix_extra_len} + 6'd5;
  assign cb_rem_prefix_pattern =
    (cb_abs_level < 5'd5) ?
    ((32'd1 << cb_rem_prefix_count) - 32'd2) :
    ((32'd1 << cb_rem_prefix_count) - 32'd1);
  assign cb_rem_suffix_count =
    (cb_abs_level < 5'd5) ? 6'd0 : {3'd0, cb_rem_prefix_extra_len} + 6'd1;
  assign cb_rem_suffix_pattern =
    (cb_abs_level < 5'd5) ? 32'd0 :
    (cb_rem_code_value - ((32'd1 << cb_rem_prefix_extra_len) - 32'd1));

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_IDLE;
      stack_count_q <= 6'd0;
      chroma_started_q <= 1'b0;
      m_axis_valid <= 1'b0;
      m_axis_kind <= 8'd0;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;
      cur_x_q <= 16'd0;
      cur_y_q <= 16'd0;
      cur_w_q <= 16'd0;
      cur_h_q <= 16'd0;
      cur_cqt_q <= 3'd0;
      cur_mtt_q <= 3'd0;
      cur_implicit_mtt_q <= 3'd0;
      cur_chroma_q <= 1'b0;
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
      leaf_cbf_q <= 1'b0;
      chroma_cbf_cb_q <= 1'b0;
      residual_step_q <= 4'd0;
      for (neighbour_i = 0; neighbour_i < LUMA_NEIGHBOUR_CELLS; neighbour_i = neighbour_i + 1) begin
        luma_neighbour_valid[neighbour_i] <= 1'b0;
        luma_neighbour_width[neighbour_i] <= 16'd0;
        luma_neighbour_height[neighbour_i] <= 16'd0;
        luma_neighbour_qt_depth[neighbour_i] <= 3'd0;
      end
    end else if (clear) begin
      state_q <= ST_IDLE;
      stack_count_q <= 6'd0;
      chroma_started_q <= 1'b0;
      m_axis_valid <= 1'b0;
      m_axis_kind <= 8'd0;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;
      for (neighbour_i = 0; neighbour_i < LUMA_NEIGHBOUR_CELLS; neighbour_i = neighbour_i + 1) begin
        luma_neighbour_valid[neighbour_i] <= 1'b0;
        luma_neighbour_width[neighbour_i] <= 16'd0;
        luma_neighbour_height[neighbour_i] <= 16'd0;
        luma_neighbour_qt_depth[neighbour_i] <= 3'd0;
      end
    end else if (m_axis_valid && !m_axis_ready) begin
      state_q <= state_q;
    end else begin
      m_axis_valid <= 1'b0;
      m_axis_kind <= 8'd0;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;

      case (state_q)
        ST_IDLE: begin
          if (start) begin
            for (neighbour_i = 0; neighbour_i < LUMA_NEIGHBOUR_CELLS; neighbour_i = neighbour_i + 1) begin
              luma_neighbour_valid[neighbour_i] <= 1'b0;
              luma_neighbour_width[neighbour_i] <= 16'd0;
              luma_neighbour_height[neighbour_i] <= 16'd0;
              luma_neighbour_qt_depth[neighbour_i] <= 3'd0;
            end
            stack_x[0] <= 16'd0;
            stack_y[0] <= 16'd0;
            stack_w[0] <= CTU_SIZE_L;
            stack_h[0] <= CTU_SIZE_L;
            stack_cqt[0] <= 3'd0;
            stack_mtt[0] <= 3'd0;
            stack_implicit_mtt[0] <= 3'd0;
            stack_chroma[0] <= 1'b0;
            stack_count_q <= 6'd1;
            chroma_started_q <= 1'b0;
            state_q <= ST_POP;
          end
        end

        ST_POP: begin
          if (stack_count_q == 6'd0) begin
            if (!chroma_started_q && dual_tree_chroma_enabled) begin
              stack_x[0] <= 16'd0;
              stack_y[0] <= 16'd0;
              stack_w[0] <= CHROMA_ROOT_SIZE;
              stack_h[0] <= CHROMA_ROOT_SIZE;
              stack_cqt[0] <= 3'd0;
              stack_mtt[0] <= 3'd0;
              stack_implicit_mtt[0] <= 3'd0;
              stack_chroma[0] <= 1'b1;
              stack_count_q <= 6'd1;
              chroma_started_q <= 1'b1;
              state_q <= ST_POP;
            end else begin
              state_q <= ST_DONE;
            end
          end else begin
            cur_x_q <= stack_x[stack_count_q - 6'd1];
            cur_y_q <= stack_y[stack_count_q - 6'd1];
            cur_w_q <= stack_w[stack_count_q - 6'd1];
            cur_h_q <= stack_h[stack_count_q - 6'd1];
            cur_cqt_q <= stack_cqt[stack_count_q - 6'd1];
            cur_mtt_q <= stack_mtt[stack_count_q - 6'd1];
            cur_implicit_mtt_q <= stack_implicit_mtt[stack_count_q - 6'd1];
            cur_chroma_q <= stack_chroma[stack_count_q - 6'd1];
            stack_count_q <= stack_count_q - 6'd1;
            state_q <= ST_DISPATCH;
          end
        end

        ST_DISPATCH: begin
          if (!cur_intersects) begin
            state_q <= ST_POP;
          end else if (cur_fits && cur_leaf_allowed) begin
            residual_step_q <= 4'd0;
            if (cur_chroma_q) begin
              chroma_cbf_cb_q <= 1'b0;
              state_q <= ST_CHROMA_SPLIT;
            end else begin
              leaf_cbf_q <= (cur_x_q == 16'd0) && (cur_y_q == 16'd0) && (luma_abs_level != 5'd0);
              state_q <= ST_LUMA_SPLIT;
            end
          end else if (!cur_fits) begin
            if ((!cur_bottom_left_in_pic && !cur_top_right_in_pic) || !cur_implicit_bt_allowed) begin
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
              split_write_qt_q <= cur_qt_flag_can_be_signaled;
              split_write_mtt_q <= 1'b0;
              split_mtt_ctx_q <= CTX_MTT_SPLIT_CU_VERTICAL_3;
              split_write_binary_q <= 1'b0;
              split_binary_ctx_q <= !cur_top_right_in_pic ? CTX_MTT_SPLIT_CU_BINARY_3 : CTX_MTT_SPLIT_CU_BINARY_1;
              state_q <= ST_SPLIT_FLAG;
            end
          end else if (cur_chroma_q && (cur_w_q != cur_h_q)) begin
            split_is_qt_q <= 1'b0;
            split_vertical_q <= (cur_w_q > cur_h_q);
            split_chroma_q <= 1'b1;
            split_implicit_q <= 1'b0;
            split_x_q <= cur_x_q;
            split_y_q <= cur_y_q;
            split_w_q <= cur_w_q;
            split_h_q <= cur_h_q;
            split_cqt_q <= cur_cqt_q;
            split_mtt_q <= cur_mtt_q;
            split_ctx_q <= cur_leaf_split_ctx;
            split_write_split_q <= 1'b1;
            split_qt_ctx_q <= cur_split_qt_ctx;
            split_qt_bin_q <= 1'b0;
            split_write_qt_q <= 1'b0;
            split_write_mtt_q <= 1'b1;
            split_mtt_ctx_q <= CTX_MTT_SPLIT_CU_VERTICAL_0;
            split_write_binary_q <= 1'b0;
            split_binary_ctx_q <= (cur_w_q > cur_h_q) ? CTX_MTT_SPLIT_CU_BINARY_3 : CTX_MTT_SPLIT_CU_BINARY_1;
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
            split_write_qt_q <= cur_chroma_q || (cur_cqt_q != 3'd0) || (cur_mtt_q != 3'd0);
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
            m_axis_data <= {18'd0, split_ctx_q, 7'd0, 1'b1};
          end
          state_q <= ST_SPLIT_QT;
        end

        ST_SPLIT_QT: begin
          if (split_write_qt_q) begin
            m_axis_valid <= 1'b1;
            m_axis_kind <= SYMBOL_BIN_CTX;
            m_axis_data <= {18'd0, split_qt_ctx_q, 7'd0, split_qt_bin_q};
            state_q <= ST_SPLIT_MTT;
          end else begin
            state_q <= ST_SPLIT_MTT;
          end
        end

        ST_SPLIT_MTT: begin
          if (split_write_mtt_q) begin
            m_axis_valid <= 1'b1;
            m_axis_kind <= SYMBOL_BIN_CTX;
            m_axis_data <= {18'd0, split_mtt_ctx_q, 7'd0, split_vertical_q};
            state_q <= ST_SPLIT_BIN;
          end else begin
            state_q <= ST_SPLIT_BIN;
          end
        end

        ST_SPLIT_BIN: begin
          if (split_write_binary_q) begin
            m_axis_valid <= 1'b1;
            m_axis_kind <= SYMBOL_BIN_CTX;
            m_axis_data <= {18'd0, split_binary_ctx_q, 7'd0, 1'b1};
            state_q <= ST_SPLIT_PUSH;
          end else begin
            state_q <= ST_SPLIT_PUSH;
          end
        end

        ST_SPLIT_PUSH: begin
          if (split_is_qt_q) begin
            stack_x[stack_count_q] <= split_x_q + (split_w_q >> 1);
            stack_y[stack_count_q] <= split_y_q + (split_h_q >> 1);
            stack_w[stack_count_q] <= split_w_q >> 1;
            stack_h[stack_count_q] <= split_h_q >> 1;
            stack_cqt[stack_count_q] <= split_cqt_q + 3'd1;
            stack_mtt[stack_count_q] <= 3'd0;
            stack_implicit_mtt[stack_count_q] <= 3'd0;
            stack_chroma[stack_count_q] <= split_chroma_q;
            stack_x[stack_count_q + 6'd1] <= split_x_q;
            stack_y[stack_count_q + 6'd1] <= split_y_q + (split_h_q >> 1);
            stack_w[stack_count_q + 6'd1] <= split_w_q >> 1;
            stack_h[stack_count_q + 6'd1] <= split_h_q >> 1;
            stack_cqt[stack_count_q + 6'd1] <= split_cqt_q + 3'd1;
            stack_mtt[stack_count_q + 6'd1] <= 3'd0;
            stack_implicit_mtt[stack_count_q + 6'd1] <= 3'd0;
            stack_chroma[stack_count_q + 6'd1] <= split_chroma_q;
            stack_x[stack_count_q + 6'd2] <= split_x_q + (split_w_q >> 1);
            stack_y[stack_count_q + 6'd2] <= split_y_q;
            stack_w[stack_count_q + 6'd2] <= split_w_q >> 1;
            stack_h[stack_count_q + 6'd2] <= split_h_q >> 1;
            stack_cqt[stack_count_q + 6'd2] <= split_cqt_q + 3'd1;
            stack_mtt[stack_count_q + 6'd2] <= 3'd0;
            stack_implicit_mtt[stack_count_q + 6'd2] <= 3'd0;
            stack_chroma[stack_count_q + 6'd2] <= split_chroma_q;
            stack_x[stack_count_q + 6'd3] <= split_x_q;
            stack_y[stack_count_q + 6'd3] <= split_y_q;
            stack_w[stack_count_q + 6'd3] <= split_w_q >> 1;
            stack_h[stack_count_q + 6'd3] <= split_h_q >> 1;
            stack_cqt[stack_count_q + 6'd3] <= split_cqt_q + 3'd1;
            stack_mtt[stack_count_q + 6'd3] <= 3'd0;
            stack_implicit_mtt[stack_count_q + 6'd3] <= 3'd0;
            stack_chroma[stack_count_q + 6'd3] <= split_chroma_q;
            stack_count_q <= stack_count_q + 6'd4;
          end else if (split_vertical_q) begin
            stack_x[stack_count_q] <= split_x_q + (split_w_q >> 1);
            stack_y[stack_count_q] <= split_y_q;
            stack_w[stack_count_q] <= split_w_q >> 1;
            stack_h[stack_count_q] <= split_h_q;
            stack_cqt[stack_count_q] <= split_cqt_q;
            stack_mtt[stack_count_q] <= split_mtt_q + 3'd1;
            stack_implicit_mtt[stack_count_q] <= cur_implicit_mtt_q + {2'd0, split_implicit_q};
            stack_chroma[stack_count_q] <= split_chroma_q;
            stack_x[stack_count_q + 6'd1] <= split_x_q;
            stack_y[stack_count_q + 6'd1] <= split_y_q;
            stack_w[stack_count_q + 6'd1] <= split_w_q >> 1;
            stack_h[stack_count_q + 6'd1] <= split_h_q;
            stack_cqt[stack_count_q + 6'd1] <= split_cqt_q;
            stack_mtt[stack_count_q + 6'd1] <= split_mtt_q + 3'd1;
            stack_implicit_mtt[stack_count_q + 6'd1] <= cur_implicit_mtt_q + {2'd0, split_implicit_q};
            stack_chroma[stack_count_q + 6'd1] <= split_chroma_q;
            stack_count_q <= stack_count_q + 6'd2;
          end else begin
            stack_x[stack_count_q] <= split_x_q;
            stack_y[stack_count_q] <= split_y_q + (split_h_q >> 1);
            stack_w[stack_count_q] <= split_w_q;
            stack_h[stack_count_q] <= split_h_q >> 1;
            stack_cqt[stack_count_q] <= split_cqt_q;
            stack_mtt[stack_count_q] <= split_mtt_q + 3'd1;
            stack_implicit_mtt[stack_count_q] <= cur_implicit_mtt_q + {2'd0, split_implicit_q};
            stack_chroma[stack_count_q] <= split_chroma_q;
            stack_x[stack_count_q + 6'd1] <= split_x_q;
            stack_y[stack_count_q + 6'd1] <= split_y_q;
            stack_w[stack_count_q + 6'd1] <= split_w_q;
            stack_h[stack_count_q + 6'd1] <= split_h_q >> 1;
            stack_cqt[stack_count_q + 6'd1] <= split_cqt_q;
            stack_mtt[stack_count_q + 6'd1] <= split_mtt_q + 3'd1;
            stack_implicit_mtt[stack_count_q + 6'd1] <= cur_implicit_mtt_q + {2'd0, split_implicit_q};
            stack_chroma[stack_count_q + 6'd1] <= split_chroma_q;
            stack_count_q <= stack_count_q + 6'd2;
          end
          state_q <= ST_POP;
        end

        ST_LUMA_SPLIT: begin
          if (cur_leaf_writes_split) begin
            m_axis_valid <= 1'b1;
            m_axis_kind <= SYMBOL_BIN_CTX;
            m_axis_data <= {18'd0, cur_leaf_split_ctx, 7'd0, 1'b0};
          end
          state_q <= palette_partition_mode ? ST_PALETTE_LEAF : ST_LUMA_MRL;
        end

        ST_PALETTE_LEAF: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_PALETTE_LEAF;
          m_axis_data <= {cur_x_q, cur_y_q};
          m_axis_last <= (stack_count_q == 6'd0);
          for (mark_y_i = 0; mark_y_i < LUMA_NEIGHBOUR_GRID; mark_y_i = mark_y_i + 1) begin
            for (mark_x_i = 0; mark_x_i < LUMA_NEIGHBOUR_GRID; mark_x_i = mark_x_i + 1) begin
              if (((mark_x_i * LUMA_MAX_LEAF_SIZE) >= cur_x_q) &&
                  ((mark_x_i * LUMA_MAX_LEAF_SIZE) < (cur_x_q + cur_w_q)) &&
                  ((mark_y_i * LUMA_MAX_LEAF_SIZE) >= cur_y_q) &&
                  ((mark_y_i * LUMA_MAX_LEAF_SIZE) < (cur_y_q + cur_h_q))) begin
                luma_neighbour_valid[(mark_y_i * LUMA_NEIGHBOUR_GRID) + mark_x_i] <= 1'b1;
                luma_neighbour_width[(mark_y_i * LUMA_NEIGHBOUR_GRID) + mark_x_i] <= cur_w_q;
                luma_neighbour_height[(mark_y_i * LUMA_NEIGHBOUR_GRID) + mark_x_i] <= cur_h_q;
                luma_neighbour_qt_depth[(mark_y_i * LUMA_NEIGHBOUR_GRID) + mark_x_i] <= cur_cqt_q;
              end
            end
          end
          state_q <= ST_POP;
        end

        ST_LUMA_MRL: begin
          if (sps_mrl_enabled_flag && (cur_y_q != 16'd0)) begin
            m_axis_valid <= 1'b1;
            m_axis_kind <= SYMBOL_BIN_CTX;
            m_axis_data <= {18'd0, CTX_MULTI_REF_LINE_IDX_0, 7'd0, 1'b0};
          end
          state_q <= ST_LUMA_MPM;
        end

        ST_LUMA_MPM: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= {18'd0, CTX_INTRA_LUMA_MPM_FLAG, 7'd0, 1'b0};
          state_q <= ST_LUMA_MODE;
        end

        ST_LUMA_MODE: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BINS_EP;
          m_axis_data <= (32'd26 << 6) | 32'd6;
          state_q <= ST_LUMA_CBF;
        end

        ST_LUMA_CBF: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= {18'd0, CTX_QT_CBF_Y_0, 7'd0, leaf_cbf_q};
          for (mark_y_i = 0; mark_y_i < LUMA_NEIGHBOUR_GRID; mark_y_i = mark_y_i + 1) begin
            for (mark_x_i = 0; mark_x_i < LUMA_NEIGHBOUR_GRID; mark_x_i = mark_x_i + 1) begin
              if (((mark_x_i * LUMA_MAX_LEAF_SIZE) >= cur_x_q) &&
                  ((mark_x_i * LUMA_MAX_LEAF_SIZE) < (cur_x_q + cur_w_q)) &&
                  ((mark_y_i * LUMA_MAX_LEAF_SIZE) >= cur_y_q) &&
                  ((mark_y_i * LUMA_MAX_LEAF_SIZE) < (cur_y_q + cur_h_q))) begin
                luma_neighbour_valid[(mark_y_i * LUMA_NEIGHBOUR_GRID) + mark_x_i] <= 1'b1;
                luma_neighbour_width[(mark_y_i * LUMA_NEIGHBOUR_GRID) + mark_x_i] <= cur_w_q;
                luma_neighbour_height[(mark_y_i * LUMA_NEIGHBOUR_GRID) + mark_x_i] <= cur_h_q;
                luma_neighbour_qt_depth[(mark_y_i * LUMA_NEIGHBOUR_GRID) + mark_x_i] <= cur_cqt_q;
              end
            end
          end
          residual_step_q <= 4'd0;
          state_q <= leaf_cbf_q ? ST_LUMA_RESIDUAL : ST_POP;
        end

        ST_LUMA_RESIDUAL: begin
          m_axis_valid <= 1'b1;
          case (residual_step_q)
            4'd0: begin
              m_axis_kind <= SYMBOL_BIN_CTX;
              m_axis_data <= {18'd0, cur_last_sig_x_ctx, 7'd0, 1'b0};
              residual_step_q <= 4'd1;
            end
            4'd1: begin
              m_axis_kind <= SYMBOL_BIN_CTX;
              m_axis_data <= {18'd0, cur_last_sig_y_ctx, 7'd0, 1'b0};
              residual_step_q <= 4'd2;
            end
            4'd2: begin
              m_axis_kind <= SYMBOL_BIN_CTX;
              m_axis_data <= {18'd0, CTX_ABS_LEVEL_GTX_FLAG_0, 7'd0, luma_abs_level > 5'd1};
              residual_step_q <= (luma_abs_level <= 5'd1) ? 4'd7 : 4'd3;
            end
            4'd3: begin
              m_axis_kind <= SYMBOL_BIN_CTX;
              m_axis_data <= {18'd0, CTX_PAR_LEVEL_FLAG_0, 7'd0, luma_abs_level[0]};
              residual_step_q <= 4'd4;
            end
            4'd4: begin
              m_axis_kind <= SYMBOL_BIN_CTX;
              m_axis_data <= {18'd0, CTX_ABS_LEVEL_GTX_FLAG_32, 7'd0, luma_abs_level > 5'd3};
              residual_step_q <= (luma_abs_level <= 5'd3) ? 4'd7 : 4'd5;
            end
            4'd5: begin
              m_axis_kind <= SYMBOL_BINS_EP;
              m_axis_data <= (rem_prefix_pattern << 6) | {26'd0, rem_prefix_count};
              residual_step_q <= 4'd6;
            end
            4'd6: begin
              m_axis_kind <= SYMBOL_BINS_EP;
              m_axis_data <= (rem_suffix_pattern << 6) | {26'd0, rem_suffix_count};
              residual_step_q <= 4'd7;
            end
            default: begin
              m_axis_kind <= SYMBOL_BIN_EP;
              m_axis_data <= {31'd0, luma_negative};
              state_q <= ST_POP;
            end
          endcase
        end

        ST_CHROMA_SPLIT: begin
          if (cur_leaf_writes_split) begin
            m_axis_valid <= 1'b1;
            m_axis_kind <= SYMBOL_BIN_CTX;
            m_axis_data <= {18'd0, cur_leaf_split_ctx, 7'd0, 1'b0};
          end
          state_q <= (sps_cclm_enabled_flag && cur_chroma_cclm_allowed) ? ST_CHROMA_CCLM : ST_CHROMA_MODE;
        end

        ST_CHROMA_CCLM: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= {18'd0, CTX_CCLM_MODE_FLAG, 7'd0, 1'b0};
          state_q <= ST_CHROMA_MODE;
        end

        ST_CHROMA_MODE: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= {18'd0, CTX_INTRA_CHROMA_PRED_MODE_0, 7'd0, 1'b0};
          chroma_cbf_cb_q <= 1'b0;
          residual_step_q <= 4'd0;
          state_q <= ST_CHROMA_CBF_CB;
        end

        ST_CHROMA_CBF_CB: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= {18'd0, CTX_QT_CBF_CB_0, 7'd0, chroma_cbf_cb_q};
          state_q <= ST_CHROMA_CBF_CR;
        end

        ST_CHROMA_CBF_CR: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= {18'd0, CTX_QT_CBF_CR_0, 7'd0, 1'b0};
          state_q <= chroma_cbf_cb_q ? ST_CHROMA_RESIDUAL : ST_POP;
        end

        ST_CHROMA_RESIDUAL: begin
          m_axis_valid <= 1'b1;
          case (residual_step_q)
            4'd0: begin
              m_axis_kind <= SYMBOL_BINS_EP;
              m_axis_data <= (cb_rem_prefix_pattern << 6) | {26'd0, cb_rem_prefix_count};
              residual_step_q <= 4'd1;
            end
            4'd1: begin
              m_axis_kind <= SYMBOL_BINS_EP;
              m_axis_data <= (cb_rem_suffix_pattern << 6) | {26'd0, cb_rem_suffix_count};
              residual_step_q <= 4'd2;
            end
            default: begin
              m_axis_kind <= SYMBOL_BIN_EP;
              m_axis_data <= {31'd0, cb_negative};
              state_q <= ST_POP;
            end
          endcase
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
