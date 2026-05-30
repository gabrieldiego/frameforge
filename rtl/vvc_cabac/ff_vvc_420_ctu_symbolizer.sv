`timescale 1ns/1ps

module ff_vvc_420_ctu_symbolizer #(
  parameter int CTU_SIZE = 64
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        clear,
  input  logic        start,
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,
  input  logic [4:0]  luma_abs_level,
  input  logic        luma_negative,
  input  logic [2:0]  luma_log2_tb_width,
  input  logic [2:0]  luma_log2_tb_height,

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
  localparam logic [15:0] MIN_VISIBLE_AXIS = 16'd8;
  localparam logic [15:0] BASE_VISIBLE_AXIS = 16'd16;
  localparam logic [4:0] CTX_LAST_SIG_X_PREFIX_3 = 5'd6;
  localparam logic [4:0] CTX_LAST_SIG_Y_PREFIX_3 = 5'd7;
  localparam logic [4:0] CTX_LAST_SIG_X_PREFIX_6 = 5'd8;
  localparam logic [4:0] CTX_LAST_SIG_Y_PREFIX_6 = 5'd9;
  localparam logic [4:0] CTX_LAST_SIG_X_PREFIX_10 = 5'd17;
  localparam logic [4:0] CTX_LAST_SIG_Y_PREFIX_10 = 5'd18;
  localparam logic [4:0] CTX_LAST_SIG_X_PREFIX_15 = 5'd22;
  localparam logic [4:0] CTX_LAST_SIG_Y_PREFIX_15 = 5'd23;

  logic [5:0] index_q;
  logic [5:0] last_index;
  logic [5:0] luma_base_count;
  logic [5:0] luma_tail_count;
  logic [5:0] extra_luma_count;
  logic [5:0] chroma_start;
  logic [5:0] chroma_leaf1_start;
  logic [5:0] chroma_leaf2_start;
  logic min_axis_visible;
  logic extra_luma_leaf_visible;
  logic extra_luma_leaf_is_below;
  logic both_axes_extra_visible;
  logic full_ctu_visible;
  logic wide_luma_leaf_visible;
  logic small_square_visible;
  logic [4:0] rem_abs_value;
  logic [4:0] rem_code_value;
  logic [2:0] rem_prefix_extra_len;
  logic [5:0] rem_prefix_count;
  logic [31:0] rem_prefix_pattern;
  logic [5:0] rem_suffix_count;
  logic [31:0] rem_suffix_pattern;
  logic [5:0] residual_count;
  logic [5:0] residual_start;
  logic [5:0] residual_index;
  logic [5:0] wide_leaf_chroma_start;
  logic [5:0] wide_leaf_residual_count;
  logic [5:0] wide_leaf_residual_index;
  logic [5:0] full_ctu_residual_count;
  logic [5:0] full_ctu_chroma_start;
  logic [5:0] full_ctu_residual_index;
  logic [5:0] extra_luma_index;
  logic [4:0] luma_last_sig_x_ctx;
  logic [4:0] luma_last_sig_y_ctx;
  logic [40:0] symbol_next;

  assign busy = index_q != 6'd63;
  assign min_axis_visible =
    ((visible_width == MIN_VISIBLE_AXIS) && (visible_height >= BASE_VISIBLE_AXIS)) ||
    ((visible_height == MIN_VISIBLE_AXIS) && (visible_width >= BASE_VISIBLE_AXIS));
  assign extra_luma_leaf_visible =
    ((visible_width > BASE_VISIBLE_AXIS) && (visible_height == BASE_VISIBLE_AXIS)) ||
    ((visible_height > BASE_VISIBLE_AXIS) && (visible_width == BASE_VISIBLE_AXIS));
  assign extra_luma_leaf_is_below =
    (visible_height > BASE_VISIBLE_AXIS) && (visible_width == BASE_VISIBLE_AXIS);
  assign both_axes_extra_visible =
    (visible_width > BASE_VISIBLE_AXIS) && (visible_height > BASE_VISIBLE_AXIS);
  assign full_ctu_visible =
    (visible_width == CTU_SIZE[15:0]) && (visible_height == CTU_SIZE[15:0]);
  assign wide_luma_leaf_visible =
    (visible_width == (BASE_VISIBLE_AXIS << 1)) && (visible_height == BASE_VISIBLE_AXIS);
  assign small_square_visible =
    (visible_width <= MIN_VISIBLE_AXIS) && (visible_height <= MIN_VISIBLE_AXIS);
  assign luma_base_count = min_axis_visible ? 6'd5 : 6'd4;
  assign residual_start = luma_base_count;
  assign residual_count =
    (luma_abs_level == 5'd0) ? 6'd0 :
    ((luma_abs_level <= 5'd1) ? 6'd3 :
    ((luma_abs_level <= 5'd3) ? 6'd5 : 6'd7));
  assign luma_tail_count = min_axis_visible ? 6'd3 : 6'd1;
  assign extra_luma_count =
    both_axes_extra_visible ? 6'd16 :
    !extra_luma_leaf_visible ? 6'd0 :
    (extra_luma_leaf_is_below ? 6'd6 : 6'd5);
  assign chroma_start = luma_base_count + residual_count + luma_tail_count + extra_luma_count;
  assign chroma_leaf1_start = chroma_start + (min_axis_visible ? 6'd1 : 6'd2);
  assign chroma_leaf2_start = chroma_start + 6'd6;
  assign wide_leaf_residual_count = residual_count + ((luma_abs_level == 5'd0) ? 6'd0 : 6'd1);
  assign wide_leaf_chroma_start = 6'd5 + wide_leaf_residual_count;
  assign full_ctu_residual_count =
    (luma_abs_level == 5'd0) ? 6'd0 :
    ((luma_abs_level <= 5'd1) ? 6'd5 :
    ((luma_abs_level <= 5'd3) ? 6'd6 : 6'd8));
  assign full_ctu_chroma_start = 6'd4 + full_ctu_residual_count;
  assign last_index =
    full_ctu_visible ? (full_ctu_chroma_start + 6'd5) :
    wide_luma_leaf_visible ? (wide_leaf_chroma_start + 6'd6) :
    small_square_visible ? (chroma_start + 6'd4) :
    both_axes_extra_visible ? (chroma_start + 6'd21) :
    extra_luma_leaf_visible ? (chroma_start + 6'd11) :
    (min_axis_visible ? (chroma_start + 6'd4) : (chroma_start + 6'd5));
  assign residual_index = index_q - residual_start;
  assign wide_leaf_residual_index = index_q - 6'd5;
  assign full_ctu_residual_index = index_q - 6'd4;
  assign extra_luma_index = index_q - (chroma_start - extra_luma_count);

  always_comb begin
    if (luma_log2_tb_width >= 3'd6) begin
      luma_last_sig_x_ctx = CTX_LAST_SIG_X_PREFIX_15;
    end else if (luma_log2_tb_width >= 3'd5) begin
      luma_last_sig_x_ctx = CTX_LAST_SIG_X_PREFIX_10;
    end else if (luma_log2_tb_width >= 3'd4) begin
      luma_last_sig_x_ctx = CTX_LAST_SIG_X_PREFIX_6;
    end else begin
      luma_last_sig_x_ctx = CTX_LAST_SIG_X_PREFIX_3;
    end

    if (luma_log2_tb_height >= 3'd6) begin
      luma_last_sig_y_ctx = CTX_LAST_SIG_Y_PREFIX_15;
    end else if (luma_log2_tb_height >= 3'd5) begin
      luma_last_sig_y_ctx = CTX_LAST_SIG_Y_PREFIX_10;
    end else if (luma_log2_tb_height >= 3'd4) begin
      luma_last_sig_y_ctx = CTX_LAST_SIG_Y_PREFIX_6;
    end else begin
      luma_last_sig_y_ctx = CTX_LAST_SIG_Y_PREFIX_3;
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

  always_comb begin
    symbol_next = {SYMBOL_BIN_TRM, 31'd0, 1'b1, 1'b1};

    if (full_ctu_visible && index_q == 6'd0) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd0, 7'd0, 1'b0, 1'b0};
    end else if (full_ctu_visible && index_q == 6'd1) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd4, 7'd0, 1'b0, 1'b0};
    end else if (full_ctu_visible && index_q == 6'd2) begin
      symbol_next = {SYMBOL_BINS_EP, (32'd26 << 6) | 32'd6, 1'b0};
    end else if (full_ctu_visible && index_q == 6'd3) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd5, 7'd0, luma_abs_level != 5'd0, 1'b0};
    end else if (full_ctu_visible &&
                 index_q >= 6'd4 && index_q < (6'd4 + full_ctu_residual_count)) begin
      case (full_ctu_residual_index)
        6'd0: symbol_next = {SYMBOL_BIN_CTX, 19'd0, luma_last_sig_x_ctx, 7'd0, 1'b0, 1'b0};
        6'd1: symbol_next = {SYMBOL_BIN_CTX, 19'd0, luma_last_sig_y_ctx, 7'd0, 1'b0, 1'b0};
        6'd2: symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd10, 7'd0, luma_abs_level > 5'd1, 1'b0};
        6'd3: symbol_next =
          (full_ctu_residual_count == 6'd5) ? {SYMBOL_BIN_EP, 31'd0, luma_negative, 1'b0} :
          {SYMBOL_BIN_CTX, 19'd0, 5'd11, 7'd0, luma_abs_level[0], 1'b0};
        6'd4: symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd12, 7'd0, luma_abs_level > 5'd3, 1'b0};
        6'd5: symbol_next =
          (full_ctu_residual_count == 6'd6) ? {SYMBOL_BIN_EP, 31'd0, luma_negative, 1'b0} :
          {SYMBOL_BINS_EP, (rem_prefix_pattern << 6) | {26'd0, rem_prefix_count}, 1'b0};
        6'd6: symbol_next = {SYMBOL_BINS_EP, (rem_suffix_pattern << 6) | {26'd0, rem_suffix_count}, 1'b0};
        default: symbol_next = {SYMBOL_BIN_EP, 31'd0, luma_negative, 1'b0};
      endcase
    end else if (full_ctu_visible && index_q == full_ctu_chroma_start) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd3, 7'd0, 1'b0, 1'b0};
    end else if (full_ctu_visible && index_q == full_ctu_chroma_start + 6'd1) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd13, 7'd0, 1'b0, 1'b0};
    end else if (full_ctu_visible && index_q == full_ctu_chroma_start + 6'd2) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd14, 7'd0, 1'b0, 1'b0};
    end else if (full_ctu_visible && index_q == full_ctu_chroma_start + 6'd3) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd15, 7'd0, 1'b0, 1'b0};
    end else if (full_ctu_visible && index_q == full_ctu_chroma_start + 6'd4) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd16, 7'd0, 1'b0, 1'b0};
    end else if (wide_luma_leaf_visible && index_q == 6'd0) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd20, 7'd0, 1'b0, 1'b0};
    end else if (wide_luma_leaf_visible && index_q == 6'd1) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd3, 7'd0, 1'b0, 1'b0};
    end else if (wide_luma_leaf_visible && index_q == 6'd2) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd4, 7'd0, 1'b0, 1'b0};
    end else if (wide_luma_leaf_visible && index_q == 6'd3) begin
      symbol_next = {SYMBOL_BINS_EP, (32'd26 << 6) | 32'd6, 1'b0};
    end else if (wide_luma_leaf_visible && index_q == 6'd4) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd5, 7'd0, luma_abs_level != 5'd0, 1'b0};
    end else if (wide_luma_leaf_visible &&
                 index_q >= 6'd5 && index_q < (6'd5 + wide_leaf_residual_count)) begin
      case (wide_leaf_residual_index)
        6'd0: symbol_next = {SYMBOL_BIN_CTX, 19'd0, luma_last_sig_x_ctx, 7'd0, 1'b0, 1'b0};
        6'd1: symbol_next = {SYMBOL_BIN_CTX, 19'd0, luma_last_sig_y_ctx, 7'd0, residual_count == 6'd2, 1'b0};
        6'd2: symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd10, 7'd0, luma_abs_level > 5'd1, 1'b0};
        6'd3: symbol_next =
          (residual_count == 6'd3) ? {SYMBOL_BIN_EP, 31'd0, luma_negative, 1'b0} :
          {SYMBOL_BIN_CTX, 19'd0, 5'd11, 7'd0, luma_abs_level[0], 1'b0};
        6'd4: symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd12, 7'd0, luma_abs_level > 5'd3, 1'b0};
        6'd5: symbol_next = {SYMBOL_BINS_EP, (rem_prefix_pattern << 6) | {26'd0, rem_prefix_count}, 1'b0};
        6'd6: symbol_next = {SYMBOL_BINS_EP, (rem_suffix_pattern << 6) | {26'd0, rem_suffix_count}, 1'b0};
        default: symbol_next = {SYMBOL_BIN_EP, 31'd0, luma_negative, 1'b0};
      endcase
    end else if (wide_luma_leaf_visible && index_q == wide_leaf_chroma_start) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd20, 7'd0, 1'b0, 1'b0};
    end else if (wide_luma_leaf_visible && index_q == wide_leaf_chroma_start + 6'd1) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd3, 7'd0, 1'b0, 1'b0};
    end else if (wide_luma_leaf_visible && index_q == wide_leaf_chroma_start + 6'd2) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd13, 7'd0, 1'b0, 1'b0};
    end else if (wide_luma_leaf_visible && index_q == wide_leaf_chroma_start + 6'd3) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd14, 7'd0, 1'b0, 1'b0};
    end else if (wide_luma_leaf_visible && index_q == wide_leaf_chroma_start + 6'd4) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd15, 7'd0, 1'b0, 1'b0};
    end else if (wide_luma_leaf_visible && index_q == wide_leaf_chroma_start + 6'd5) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd16, 7'd0, 1'b0, 1'b0};
    end else if (min_axis_visible && index_q == 6'd0) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd2, 7'd0, 1'b0, 1'b0};
    end else if (min_axis_visible && index_q == 6'd1) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd3, 7'd0, 1'b0, 1'b0};
    end else if (!min_axis_visible && index_q == 6'd0) begin
      symbol_next = {
        SYMBOL_BIN_CTX, 19'd0,
        ((visible_width <= MIN_VISIBLE_AXIS) && (visible_height <= MIN_VISIBLE_AXIS)) ? 5'd0 : 5'd1,
        7'd0, 1'b0, 1'b0
      };
    end else if (index_q == (min_axis_visible ? 6'd2 : 6'd1)) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd4, 7'd0, 1'b0, 1'b0};
    end else if (index_q == (min_axis_visible ? 6'd3 : 6'd2)) begin
      symbol_next = {SYMBOL_BINS_EP, (32'd26 << 6) | 32'd6, 1'b0};
    end else if (index_q == (min_axis_visible ? 6'd4 : 6'd3)) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd5, 7'd0, luma_abs_level != 5'd0, 1'b0};
    end else if (index_q >= residual_start && index_q < (residual_start + residual_count)) begin
      case (residual_index)
        6'd0: symbol_next = {
          SYMBOL_BIN_CTX, 19'd0, luma_last_sig_x_ctx, 7'd0, 1'b0, 1'b0
        };
        6'd1: symbol_next = {
          SYMBOL_BIN_CTX, 19'd0, luma_last_sig_y_ctx, 7'd0,
          residual_count == 6'd2, 1'b0
        };
        6'd2: symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd10, 7'd0, luma_abs_level > 5'd1, 1'b0};
        6'd3: symbol_next =
          (residual_count == 6'd3) ? {SYMBOL_BIN_EP, 31'd0, luma_negative, 1'b0} :
          {SYMBOL_BIN_CTX, 19'd0, 5'd11, 7'd0, luma_abs_level[0], 1'b0};
        6'd4: symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd12, 7'd0, luma_abs_level > 5'd3, 1'b0};
        6'd5: symbol_next = {SYMBOL_BINS_EP, (rem_prefix_pattern << 6) | {26'd0, rem_prefix_count}, 1'b0};
        default: symbol_next = {SYMBOL_BINS_EP, (rem_suffix_pattern << 6) | {26'd0, rem_suffix_count}, 1'b0};
      endcase
    end else if (index_q == (residual_start + residual_count)) begin
      symbol_next = (luma_abs_level == 5'd0) ?
        (min_axis_visible ? {SYMBOL_BIN_CTX, 19'd0, 5'd2, 7'd0, 1'b0, 1'b0}
                          : {SYMBOL_BIN_CTX, 19'd0, 5'd1, 7'd0, 1'b0, 1'b0}) :
        {SYMBOL_BIN_EP, 31'd0, luma_negative, 1'b0};
    end else if (min_axis_visible && index_q == (residual_start + residual_count + 6'd1)) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd2, 7'd0, 1'b0, 1'b0};
    end else if (min_axis_visible && index_q == (residual_start + residual_count + 6'd2)) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd0, 7'd0, 1'b0, 1'b0};
    end else if (both_axes_extra_visible && index_q >= (chroma_start - extra_luma_count) && index_q < chroma_start) begin
      case (extra_luma_index)
        6'd0:  symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd2, 7'd0, 1'b0, 1'b0};
        6'd1:  symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd3, 7'd0, 1'b0, 1'b0};
        6'd2:  symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd4, 7'd0, 1'b0, 1'b0};
        6'd3:  symbol_next = {SYMBOL_BINS_EP, (32'd26 << 6) | 32'd6, 1'b0};
        6'd4:  symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd5, 7'd0, 1'b0, 1'b0};
        6'd5:  symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd2, 7'd0, 1'b0, 1'b0};
        6'd6:  symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd3, 7'd0, 1'b0, 1'b0};
        6'd7:  symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd21, 7'd0, 1'b0, 1'b0};
        6'd8:  symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd4, 7'd0, 1'b0, 1'b0};
        6'd9:  symbol_next = {SYMBOL_BINS_EP, (32'd26 << 6) | 32'd6, 1'b0};
        6'd10: symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd5, 7'd0, 1'b0, 1'b0};
        6'd11: symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd0, 7'd0, 1'b0, 1'b0};
        6'd12: symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd21, 7'd0, 1'b0, 1'b0};
        6'd13: symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd4, 7'd0, 1'b0, 1'b0};
        6'd14: symbol_next = {SYMBOL_BINS_EP, (32'd26 << 6) | 32'd6, 1'b0};
        default: symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd5, 7'd0, 1'b0, 1'b0};
      endcase
    end else if (extra_luma_leaf_visible && index_q >= (chroma_start - extra_luma_count) && index_q < chroma_start) begin
      case (extra_luma_index)
        6'd0: symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd2, 7'd0, 1'b0, 1'b0};
        6'd1: symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd3, 7'd0, 1'b0, 1'b0};
        6'd2: symbol_next = extra_luma_leaf_is_below ? {SYMBOL_BIN_CTX, 19'd0, 5'd21, 7'd0, 1'b0, 1'b0}
                                                      : {SYMBOL_BIN_CTX, 19'd0, 5'd4, 7'd0, 1'b0, 1'b0};
        6'd3: symbol_next = extra_luma_leaf_is_below ? {SYMBOL_BIN_CTX, 19'd0, 5'd4, 7'd0, 1'b0, 1'b0}
                                                      : {SYMBOL_BINS_EP, (32'd26 << 6) | 32'd6, 1'b0};
        6'd4: symbol_next = extra_luma_leaf_is_below ? {SYMBOL_BINS_EP, (32'd26 << 6) | 32'd6, 1'b0}
                                                      : {SYMBOL_BIN_CTX, 19'd0, 5'd5, 7'd0, 1'b0, 1'b0};
        default: symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd5, 7'd0, 1'b0, 1'b0};
      endcase
    end else if (small_square_visible && index_q == chroma_start) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd13, 7'd0, 1'b0, 1'b0};
    end else if (small_square_visible && index_q == chroma_start + 6'd1) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd14, 7'd0, 1'b0, 1'b0};
    end else if (small_square_visible && index_q == chroma_start + 6'd2) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd15, 7'd0, 1'b0, 1'b0};
    end else if (small_square_visible && index_q == chroma_start + 6'd3) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd16, 7'd0, 1'b0, 1'b0};
    end else if (both_axes_extra_visible && index_q == chroma_start) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd1, 7'd0, 1'b0, 1'b0};
    end else if (both_axes_extra_visible && index_q == chroma_start + 6'd1) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd13, 7'd0, 1'b0, 1'b0};
    end else if (both_axes_extra_visible && index_q == chroma_start + 6'd2) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd14, 7'd0, 1'b0, 1'b0};
    end else if (both_axes_extra_visible && index_q == chroma_start + 6'd3) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd15, 7'd0, 1'b0, 1'b0};
    end else if (both_axes_extra_visible && index_q == chroma_start + 6'd4) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd16, 7'd0, 1'b0, 1'b0};
    end else if (both_axes_extra_visible && index_q == chroma_start + 6'd5) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd2, 7'd0, 1'b0, 1'b0};
    end else if (both_axes_extra_visible && index_q == chroma_start + 6'd6) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd0, 7'd0, 1'b0, 1'b0};
    end else if (both_axes_extra_visible && index_q == chroma_start + 6'd7) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd13, 7'd0, 1'b0, 1'b0};
    end else if (both_axes_extra_visible && index_q == chroma_start + 6'd8) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd14, 7'd0, 1'b0, 1'b0};
    end else if (both_axes_extra_visible && index_q == chroma_start + 6'd9) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd15, 7'd0, 1'b0, 1'b0};
    end else if (both_axes_extra_visible && index_q == chroma_start + 6'd10) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd16, 7'd0, 1'b0, 1'b0};
    end else if (both_axes_extra_visible && index_q == chroma_start + 6'd11) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd2, 7'd0, 1'b0, 1'b0};
    end else if (both_axes_extra_visible && index_q == chroma_start + 6'd12) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd0, 7'd0, 1'b0, 1'b0};
    end else if (both_axes_extra_visible && index_q == chroma_start + 6'd13) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd13, 7'd0, 1'b0, 1'b0};
    end else if (both_axes_extra_visible && index_q == chroma_start + 6'd14) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd14, 7'd0, 1'b0, 1'b0};
    end else if (both_axes_extra_visible && index_q == chroma_start + 6'd15) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd15, 7'd0, 1'b0, 1'b0};
    end else if (both_axes_extra_visible && index_q == chroma_start + 6'd16) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd16, 7'd0, 1'b0, 1'b0};
    end else if (both_axes_extra_visible && index_q == chroma_start + 6'd17) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd13, 7'd0, 1'b0, 1'b0};
    end else if (both_axes_extra_visible && index_q == chroma_start + 6'd18) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd14, 7'd0, 1'b0, 1'b0};
    end else if (both_axes_extra_visible && index_q == chroma_start + 6'd19) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd15, 7'd0, 1'b0, 1'b0};
    end else if (both_axes_extra_visible && index_q == chroma_start + 6'd20) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd16, 7'd0, 1'b0, 1'b0};
    end else if (!min_axis_visible && index_q == chroma_start) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd1, 7'd0, 1'b0, 1'b0};
    end else if (min_axis_visible && index_q == chroma_start) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd13, 7'd0, 1'b0, 1'b0};
    end else if (!min_axis_visible && index_q == chroma_start + 6'd1) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd13, 7'd0, 1'b0, 1'b0};
    end else if (index_q >= chroma_leaf1_start &&
                 index_q < chroma_leaf1_start + (extra_luma_leaf_visible ? 6'd3 : 6'd4)) begin
      case (index_q - chroma_leaf1_start)
        6'd0: symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd14, 7'd0, 1'b0, 1'b0};
        6'd1: symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd15, 7'd0, 1'b0, 1'b0};
        6'd2: symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd16, 7'd0, 1'b0, 1'b0};
        default: symbol_next = extra_luma_leaf_visible ?
          {SYMBOL_BIN_CTX, 19'd0, 5'd16, 7'd0, 1'b0, 1'b0} :
          {SYMBOL_BIN_TRM, 31'd0, 1'b1, 1'b1};
      endcase
    end else if (extra_luma_leaf_visible && index_q == chroma_start + 6'd5) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd2, 7'd0, 1'b0, 1'b0};
    end else if (index_q == chroma_leaf2_start) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd0, 7'd0, 1'b0, 1'b0};
    end else if (index_q == chroma_leaf2_start + 6'd1) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd13, 7'd0, 1'b0, 1'b0};
    end else if (index_q == chroma_leaf2_start + 6'd2) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd14, 7'd0, 1'b0, 1'b0};
    end else if (index_q == chroma_leaf2_start + 6'd3) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd15, 7'd0, 1'b0, 1'b0};
    end else if (index_q == chroma_leaf2_start + 6'd4) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd16, 7'd0, 1'b0, 1'b0};
    end

    if (index_q == last_index) begin
      symbol_next = {SYMBOL_BIN_TRM, 31'd0, 1'b1, 1'b1};
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      index_q <= 6'd63;
      m_axis_valid <= 1'b0;
      m_axis_kind <= 8'd0;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;
    end else if (clear) begin
      index_q <= 6'd63;
      m_axis_valid <= 1'b0;
      m_axis_kind <= 8'd0;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;
    end else begin
      if (start) begin
        index_q <= 6'd0;
        m_axis_valid <= 1'b0;
        m_axis_last <= 1'b0;
      end else if (busy && (!m_axis_valid || m_axis_ready)) begin
        m_axis_valid <= 1'b1;
        {m_axis_kind, m_axis_data, m_axis_last} <= symbol_next;
        if (index_q == last_index) begin
          index_q <= 6'd63;
        end else begin
          index_q <= index_q + 6'd1;
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
