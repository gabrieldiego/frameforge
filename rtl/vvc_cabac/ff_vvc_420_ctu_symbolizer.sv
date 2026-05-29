`timescale 1ns/1ps

module ff_vvc_420_ctu_symbolizer (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        clear,
  input  logic        start,
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,
  input  logic [4:0]  luma_abs_level,
  input  logic        luma_negative,

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
  logic [5:0] extra_luma_index;
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
  assign small_square_visible =
    (visible_width <= MIN_VISIBLE_AXIS) && (visible_height <= MIN_VISIBLE_AXIS);
  assign luma_base_count = min_axis_visible ? 6'd5 : 6'd4;
  assign residual_start = luma_base_count;
  assign residual_count =
    (luma_abs_level == 5'd0) ? 6'd0 :
    ((luma_abs_level <= 5'd1) ? 6'd3 :
    ((luma_abs_level <= 5'd3) ? 6'd5 : 6'd7));
  assign luma_tail_count = min_axis_visible ? 6'd3 : 6'd1;
  assign extra_luma_count = extra_luma_leaf_visible ? 6'd6 : 6'd0;
  assign chroma_start = luma_base_count + residual_count + luma_tail_count + extra_luma_count;
  assign chroma_leaf1_start = chroma_start + (min_axis_visible ? 6'd1 : 6'd2);
  assign chroma_leaf2_start = chroma_start + 6'd6;
  assign last_index =
    small_square_visible ? (chroma_start + 6'd4) :
    extra_luma_leaf_visible ? (chroma_start + 6'd11) :
    (min_axis_visible ? (chroma_start + 6'd4) : (chroma_start + 6'd5));
  assign residual_index = index_q - residual_start;
  assign extra_luma_index = index_q - (chroma_start - extra_luma_count);

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

    if (min_axis_visible && index_q == 6'd0) begin
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
          SYMBOL_BIN_CTX, 19'd0, (visible_width >= 16'd16 ? 5'd8 : 5'd6), 7'd0, 1'b0, 1'b0
        };
        6'd1: symbol_next = {
          SYMBOL_BIN_CTX, 19'd0, (visible_height >= 16'd16 ? 5'd9 : 5'd7), 7'd0,
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
    end else if (!min_axis_visible && index_q == chroma_start) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd1, 7'd0, 1'b0, 1'b0};
    end else if (min_axis_visible && index_q == chroma_start) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd13, 7'd0, 1'b0, 1'b0};
    end else if (!min_axis_visible && index_q == chroma_start + 6'd1) begin
      symbol_next = {SYMBOL_BIN_CTX, 19'd0, 5'd13, 7'd0, 1'b0, 1'b0};
    end else if (index_q >= chroma_leaf1_start && index_q < chroma_leaf1_start + 6'd4) begin
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
