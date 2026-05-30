`timescale 1ns/1ps

module ff_vvc_cabac_syntax_frontend (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        clear,

  input  logic        raw_symbol_valid,
  output logic        raw_symbol_ready,
  input  logic [7:0]  raw_symbol_kind,
  input  logic [31:0] raw_symbol_data,
  input  logic        raw_symbol_last,

  input  logic        ctu_valid,
  output logic        ctu_ready,
  input  logic [15:0] ctu_x,
  input  logic [15:0] ctu_y,
  input  logic [15:0] ctu_visible_width,
  input  logic [15:0] ctu_visible_height,
  input  logic [4:0]  ctu_luma_dc_abs_level,
  input  logic        ctu_luma_dc_negative,
  input  logic        ctu_luma_only,
  input  logic        ctu_last,

  output logic        m_axis_valid,
  input  logic        m_axis_ready,
  output logic [7:0]  m_axis_kind,
  output logic [31:0] m_axis_data,
  output logic        m_axis_last
);
  localparam logic [7:0] SYMBOL_BIN_EP  = 8'd0;
  localparam logic [7:0] SYMBOL_BIN_CTX = 8'd2;
  localparam logic [7:0] SYMBOL_BINS_EP = 8'd4;

  localparam logic [4:0] CTX_SPLIT_FLAG_6 = 5'd1;
  localparam logic [4:0] CTX_INTRA_LUMA_MPM_FLAG = 5'd4;
  localparam logic [4:0] CTX_QT_CBF_Y_0 = 5'd5;
  localparam logic [4:0] CTX_LAST_SIG_X_PREFIX_3 = 5'd6;
  localparam logic [4:0] CTX_LAST_SIG_Y_PREFIX_3 = 5'd7;
  localparam logic [4:0] CTX_LAST_SIG_X_PREFIX_6 = 5'd8;
  localparam logic [4:0] CTX_LAST_SIG_Y_PREFIX_6 = 5'd9;
  localparam logic [4:0] CTX_ABS_LEVEL_GTX_FLAG_0 = 5'd10;
  localparam logic [4:0] CTX_PAR_LEVEL_FLAG_0 = 5'd11;
  localparam logic [4:0] CTX_ABS_LEVEL_GTX_FLAG_32 = 5'd12;
  localparam logic [4:0] CTX_LAST_SIG_X_PREFIX_10 = 5'd17;
  localparam logic [4:0] CTX_LAST_SIG_Y_PREFIX_10 = 5'd18;
  localparam logic [4:0] CTX_LAST_SIG_X_PREFIX_15 = 5'd22;
  localparam logic [4:0] CTX_LAST_SIG_Y_PREFIX_15 = 5'd23;
  localparam logic [15:0] CTU_SIZE = 16'd64;
  localparam logic [15:0] CURRENT_LUMA_LEAF_SIZE = 16'd16;

  localparam logic [3:0] ST_IDLE = 4'd0;
  localparam logic [3:0] ST_SPLIT = 4'd1;
  localparam logic [3:0] ST_SPLIT_LEAF = 4'd2;
  localparam logic [3:0] ST_MPM = 4'd3;
  localparam logic [3:0] ST_LUMA_MODE = 4'd4;
  localparam logic [3:0] ST_CBF = 4'd5;
  localparam logic [3:0] ST_LAST_X = 4'd6;
  localparam logic [3:0] ST_LAST_Y = 4'd7;
  localparam logic [3:0] ST_GTX0 = 4'd8;
  localparam logic [3:0] ST_PAR = 4'd9;
  localparam logic [3:0] ST_GTX32 = 4'd10;
  localparam logic [3:0] ST_REM_PREFIX = 4'd11;
  localparam logic [3:0] ST_REM_SUFFIX = 4'd12;
  localparam logic [3:0] ST_SIGN = 4'd13;

  logic ctu_path_active_q;
  logic [3:0] ctu_state_q;
  logic [4:0] luma_abs_q;
  logic luma_negative_q;
  logic [4:0] last_sig_x_ctx;
  logic [4:0] last_sig_y_ctx;
  logic [4:0] rem_abs_value;
  logic [4:0] rem_code_value;
  logic [2:0] rem_prefix_extra_len;
  logic [5:0] rem_prefix_count;
  logic [31:0] rem_prefix_pattern;
  logic [5:0] rem_suffix_count;
  logic [31:0] rem_suffix_pattern;
  logic [7:0] ctu_symbol_kind;
  logic [31:0] ctu_symbol_data;
  logic ctu_symbol_last;
  logic ctu_symbol_valid;
  logic [4:0] first_luma_split_ctx;
  logic split_leaf_needed;
  logic raw_path_selected;
  logic ctu_transfer;
  logic luma_only_q;
  logic luma_anchor_full_ctu;
  logic luma_anchor_wide_leaf;
  logic unused_position_inputs;

  assign raw_path_selected = !ctu_path_active_q;
  assign raw_symbol_ready = raw_path_selected && m_axis_ready;
  assign ctu_ready = !ctu_path_active_q && !raw_symbol_valid;
  assign luma_anchor_full_ctu =
    (ctu_visible_width == CTU_SIZE) && (ctu_visible_height == CTU_SIZE);
  assign luma_anchor_wide_leaf =
    (ctu_visible_width == (CURRENT_LUMA_LEAF_SIZE << 1)) &&
    (ctu_visible_height == CURRENT_LUMA_LEAF_SIZE);
  assign last_sig_x_ctx =
    luma_anchor_full_ctu ? CTX_LAST_SIG_X_PREFIX_15 :
    (luma_anchor_wide_leaf ? CTX_LAST_SIG_X_PREFIX_10 :
    ((ctu_visible_width >= CURRENT_LUMA_LEAF_SIZE) ? CTX_LAST_SIG_X_PREFIX_6 : CTX_LAST_SIG_X_PREFIX_3));
  assign last_sig_y_ctx =
    luma_anchor_full_ctu ? CTX_LAST_SIG_Y_PREFIX_15 :
    ((ctu_visible_height >= CURRENT_LUMA_LEAF_SIZE) ? CTX_LAST_SIG_Y_PREFIX_6 : CTX_LAST_SIG_Y_PREFIX_3);
  assign first_luma_split_ctx =
    luma_anchor_full_ctu ? 5'd0 :
    ((ctu_visible_width <= 16'd8) && (ctu_visible_height <= 16'd8)) ? 5'd0 :
    ((((ctu_visible_width == 16'd8) && (ctu_visible_height >= 16'd16)) ||
     ((ctu_visible_height == 16'd8) && (ctu_visible_width >= 16'd16))) ?
    5'd2 : CTX_SPLIT_FLAG_6);
  assign split_leaf_needed = first_luma_split_ctx == 5'd2;
  assign rem_abs_value = (luma_abs_q - 5'd4) >> 1;
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
  assign ctu_symbol_valid = ctu_path_active_q;
  assign ctu_transfer = ctu_symbol_valid && m_axis_ready;
  assign m_axis_valid = raw_path_selected ? raw_symbol_valid : ctu_symbol_valid;
  assign m_axis_kind = raw_path_selected ? raw_symbol_kind : ctu_symbol_kind;
  assign m_axis_data = raw_path_selected ? raw_symbol_data : ctu_symbol_data;
  assign m_axis_last = raw_path_selected ? raw_symbol_last : ctu_symbol_last;
  assign unused_position_inputs = (|ctu_x) || (|ctu_y) || ctu_last;

  always_comb begin
    ctu_symbol_kind = SYMBOL_BIN_CTX;
    ctu_symbol_data = 32'd0;
    ctu_symbol_last = 1'b0;
    case (ctu_state_q)
      ST_SPLIT: begin
        ctu_symbol_data = {19'd0, first_luma_split_ctx, 7'd0, 1'b0};
      end
      ST_SPLIT_LEAF: begin
        ctu_symbol_data = {19'd0, 5'd3, 7'd0, 1'b0};
      end
      ST_MPM: begin
        ctu_symbol_data = {19'd0, CTX_INTRA_LUMA_MPM_FLAG, 7'd0, 1'b0};
      end
      ST_LUMA_MODE: begin
        ctu_symbol_kind = SYMBOL_BINS_EP;
        ctu_symbol_data = (32'd26 << 6) | 32'd6;
      end
      ST_CBF: begin
        ctu_symbol_data = {19'd0, CTX_QT_CBF_Y_0, 7'd0, luma_abs_q != 5'd0};
        ctu_symbol_last = luma_only_q && (luma_abs_q == 5'd0);
      end
      ST_LAST_X: begin
        ctu_symbol_data = {19'd0, last_sig_x_ctx, 7'd0, 1'b0};
      end
      ST_LAST_Y: begin
        ctu_symbol_data = {19'd0, last_sig_y_ctx, 7'd0, 1'b0};
      end
      ST_GTX0: begin
        ctu_symbol_data = {19'd0, CTX_ABS_LEVEL_GTX_FLAG_0, 7'd0, luma_abs_q > 5'd1};
      end
      ST_PAR: begin
        ctu_symbol_data = {19'd0, CTX_PAR_LEVEL_FLAG_0, 7'd0, luma_abs_q[0]};
      end
      ST_GTX32: begin
        ctu_symbol_data = {19'd0, CTX_ABS_LEVEL_GTX_FLAG_32, 7'd0, luma_abs_q > 5'd3};
      end
      ST_REM_PREFIX: begin
        ctu_symbol_kind = SYMBOL_BINS_EP;
        ctu_symbol_data = (rem_prefix_pattern << 6) | {26'd0, rem_prefix_count};
      end
      ST_REM_SUFFIX: begin
        ctu_symbol_kind = SYMBOL_BINS_EP;
        ctu_symbol_data = (rem_suffix_pattern << 6) | {26'd0, rem_suffix_count};
      end
      ST_SIGN: begin
        ctu_symbol_kind = SYMBOL_BIN_EP;
        ctu_symbol_data = {31'd0, luma_negative_q};
        ctu_symbol_last = luma_only_q;
      end
      default: begin
        ctu_symbol_kind = SYMBOL_BIN_CTX;
        ctu_symbol_data = 32'd0;
        ctu_symbol_last = 1'b0;
      end
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ctu_path_active_q <= 1'b0;
      ctu_state_q <= ST_IDLE;
      luma_abs_q <= 5'd0;
      luma_negative_q <= 1'b0;
      luma_only_q <= 1'b0;
    end else if (clear) begin
      ctu_path_active_q <= 1'b0;
      ctu_state_q <= ST_IDLE;
      luma_abs_q <= 5'd0;
      luma_negative_q <= 1'b0;
      luma_only_q <= 1'b0;
    end else begin
      if (ctu_valid && ctu_ready) begin
        ctu_path_active_q <= 1'b1;
        ctu_state_q <= ST_SPLIT;
        luma_abs_q <= ctu_luma_dc_abs_level;
        luma_negative_q <= ctu_luma_dc_negative && (ctu_luma_dc_abs_level != 5'd0);
        luma_only_q <= ctu_luma_only;
      end else if (ctu_transfer) begin
        case (ctu_state_q)
          ST_SPLIT: ctu_state_q <= split_leaf_needed ? ST_SPLIT_LEAF : ST_MPM;
          ST_SPLIT_LEAF: ctu_state_q <= ST_MPM;
          ST_MPM: ctu_state_q <= ST_LUMA_MODE;
          ST_LUMA_MODE: ctu_state_q <= ST_CBF;
          ST_CBF: begin
            if (luma_abs_q == 5'd0) begin
              ctu_path_active_q <= 1'b0;
              ctu_state_q <= ST_IDLE;
            end else begin
              ctu_state_q <= ST_LAST_X;
            end
          end
          ST_LAST_X: ctu_state_q <= ST_LAST_Y;
          ST_LAST_Y: ctu_state_q <= ST_GTX0;
          ST_GTX0: ctu_state_q <= (luma_abs_q <= 5'd1) ? ST_SIGN : ST_PAR;
          ST_PAR: ctu_state_q <= ST_GTX32;
          ST_GTX32: ctu_state_q <= (luma_abs_q <= 5'd3) ? ST_SIGN : ST_REM_PREFIX;
          ST_REM_PREFIX: ctu_state_q <= ST_REM_SUFFIX;
          ST_REM_SUFFIX: ctu_state_q <= ST_SIGN;
          ST_SIGN: begin
            ctu_path_active_q <= 1'b0;
            ctu_state_q <= ST_IDLE;
          end
          default: begin
            ctu_path_active_q <= 1'b0;
            ctu_state_q <= ST_IDLE;
          end
        endcase
      end
    end
  end
endmodule
