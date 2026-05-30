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

  localparam logic [15:0] CTU_SIZE_L = CTU_SIZE;
  localparam logic [15:0] LUMA_MAX_LEAF_SIZE = 16'd32;
  localparam logic [15:0] CHROMA_MAX_LEAF_SIZE = 16'd16;
  localparam int STACK_DEPTH = 32;

  localparam logic [4:0] CTX_SPLIT_FLAG_0 = 5'd0;
  localparam logic [4:0] CTX_SPLIT_FLAG_6 = 5'd1;
  localparam logic [4:0] CTX_SPLIT_QT_FLAG_3 = 5'd2;
  localparam logic [4:0] CTX_SPLIT_FLAG_3 = 5'd3;
  localparam logic [4:0] CTX_INTRA_LUMA_MPM_FLAG = 5'd4;
  localparam logic [4:0] CTX_QT_CBF_Y_0 = 5'd5;
  localparam logic [4:0] CTX_LAST_SIG_X_PREFIX_3 = 5'd6;
  localparam logic [4:0] CTX_LAST_SIG_Y_PREFIX_3 = 5'd7;
  localparam logic [4:0] CTX_LAST_SIG_X_PREFIX_6 = 5'd8;
  localparam logic [4:0] CTX_LAST_SIG_Y_PREFIX_6 = 5'd9;
  localparam logic [4:0] CTX_ABS_LEVEL_GTX_FLAG_0 = 5'd10;
  localparam logic [4:0] CTX_PAR_LEVEL_FLAG_0 = 5'd11;
  localparam logic [4:0] CTX_ABS_LEVEL_GTX_FLAG_32 = 5'd12;
  localparam logic [4:0] CTX_CCLM_MODE_FLAG = 5'd13;
  localparam logic [4:0] CTX_INTRA_CHROMA_PRED_MODE_0 = 5'd14;
  localparam logic [4:0] CTX_QT_CBF_CB_0 = 5'd15;
  localparam logic [4:0] CTX_QT_CBF_CR_0 = 5'd16;
  localparam logic [4:0] CTX_LAST_SIG_X_PREFIX_10 = 5'd17;
  localparam logic [4:0] CTX_LAST_SIG_Y_PREFIX_10 = 5'd18;
  localparam logic [4:0] CTX_SPLIT_FLAG_7 = 5'd19;
  localparam logic [4:0] CTX_SPLIT_QT_FLAG_0 = 5'd20;
  localparam logic [4:0] CTX_MULTI_REF_LINE_IDX_0 = 5'd21;
  localparam logic [4:0] CTX_LAST_SIG_X_PREFIX_15 = 5'd22;
  localparam logic [4:0] CTX_LAST_SIG_Y_PREFIX_15 = 5'd23;
  localparam logic [4:0] CTX_MTT_SPLIT_CU_VERTICAL_3 = 5'd24;
  localparam logic [4:0] CTX_MTT_SPLIT_CU_BINARY_1 = 5'd25;
  localparam logic [4:0] CTX_MTT_SPLIT_CU_BINARY_3 = 5'd26;
  localparam logic [4:0] CTX_SPLIT_FLAG_1 = 5'd27;
  localparam logic [4:0] CTX_SPLIT_FLAG_2 = 5'd28;
  localparam logic [4:0] CTX_MTT_SPLIT_CU_VERTICAL_0 = 5'd29;

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
  localparam logic [4:0] ST_DONE = 5'd19;

  logic [4:0] state_q;
  logic [5:0] stack_count_q;
  logic [15:0] stack_x [0:STACK_DEPTH - 1];
  logic [15:0] stack_y [0:STACK_DEPTH - 1];
  logic [15:0] stack_w [0:STACK_DEPTH - 1];
  logic [15:0] stack_h [0:STACK_DEPTH - 1];
  logic [2:0] stack_cqt [0:STACK_DEPTH - 1];
  logic [2:0] stack_mtt [0:STACK_DEPTH - 1];
  logic stack_chroma [0:STACK_DEPTH - 1];

  logic [15:0] cur_x_q;
  logic [15:0] cur_y_q;
  logic [15:0] cur_w_q;
  logic [15:0] cur_h_q;
  logic [2:0] cur_cqt_q;
  logic [2:0] cur_mtt_q;
  logic cur_chroma_q;
  logic chroma_started_q;

  logic split_is_qt_q;
  logic split_vertical_q;
  logic split_chroma_q;
  logic [15:0] split_x_q;
  logic [15:0] split_y_q;
  logic [15:0] split_w_q;
  logic [15:0] split_h_q;
  logic [2:0] split_cqt_q;
  logic [2:0] split_mtt_q;
  logic [4:0] split_ctx_q;
  logic split_write_split_q;
  logic [4:0] split_qt_ctx_q;
  logic split_qt_bin_q;
  logic split_write_qt_q;
  logic split_write_mtt_q;
  logic [4:0] split_mtt_ctx_q;
  logic split_write_binary_q;
  logic [4:0] split_binary_ctx_q;

  logic leaf_cbf_q;
  logic [3:0] residual_step_q;
  logic [4:0] rem_abs_value;
  logic [4:0] rem_code_value;
  logic [2:0] rem_prefix_extra_len;
  logic [5:0] rem_prefix_count;
  logic [31:0] rem_prefix_pattern;
  logic [5:0] rem_suffix_count;
  logic [31:0] rem_suffix_pattern;
  logic [4:0] cur_last_sig_x_ctx;
  logic [4:0] cur_last_sig_y_ctx;
  logic [4:0] cur_leaf_split_ctx;
  logic cur_leaf_writes_split;
  logic [15:0] cur_visible_width;
  logic [15:0] cur_visible_height;
  logic [15:0] cur_leaf_max;
  logic [16:0] cur_right;
  logic [16:0] cur_bottom;
  logic cur_intersects;
  logic cur_fits;
  logic cur_bottom_left_in_pic;
  logic cur_top_right_in_pic;
  logic fits_split_vertical;
  logic [2:0] unused_luma_log2;

  assign busy = (state_q != ST_IDLE) || m_axis_valid;
  assign cur_visible_width = cur_chroma_q ? (visible_width >> 1) : visible_width;
  assign cur_visible_height = cur_chroma_q ? (visible_height >> 1) : visible_height;
  assign cur_leaf_max = cur_chroma_q ? CHROMA_MAX_LEAF_SIZE : LUMA_MAX_LEAF_SIZE;
  assign cur_right = {1'b0, cur_x_q} + {1'b0, cur_w_q} - 17'd1;
  assign cur_bottom = {1'b0, cur_y_q} + {1'b0, cur_h_q} - 17'd1;
  assign cur_intersects = (cur_x_q < cur_visible_width) && (cur_y_q < cur_visible_height);
  assign cur_fits = (cur_right < {1'b0, cur_visible_width}) && (cur_bottom < {1'b0, cur_visible_height});
  assign cur_bottom_left_in_pic = (cur_x_q < cur_visible_width) && (cur_bottom < {1'b0, cur_visible_height});
  assign cur_top_right_in_pic = (cur_right < {1'b0, cur_visible_width}) && (cur_y_q < cur_visible_height);
  assign fits_split_vertical = (cur_w_q > cur_leaf_max) && ((cur_h_q <= cur_leaf_max) || (cur_w_q >= cur_h_q));
  assign unused_luma_log2 = luma_log2_tb_width ^ luma_log2_tb_height;

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
      cur_leaf_writes_split = (cur_w_q != 16'd4) || (cur_h_q != 16'd4);
      if ((cur_w_q == 16'd4) || (cur_h_q == 16'd4)) begin
        cur_leaf_split_ctx = CTX_SPLIT_FLAG_0;
      end else if (cur_mtt_q != 3'd0) begin
        cur_leaf_split_ctx = CTX_SPLIT_FLAG_3;
      end else begin
        cur_leaf_split_ctx = CTX_SPLIT_FLAG_6;
      end
    end else begin
      cur_leaf_writes_split = (cur_w_q != 16'd4) || (cur_h_q != 16'd4);
      if (cur_mtt_q == 3'd0 && cur_cqt_q >= 3'd3) begin
        if ((cur_x_q[3:0] != 4'd0) && (cur_y_q[3:0] != 4'd0)) begin
          cur_leaf_split_ctx = CTX_SPLIT_FLAG_2;
        end else if ((cur_x_q[3:0] != 4'd0) || (cur_y_q[3:0] != 4'd0)) begin
          cur_leaf_split_ctx = CTX_SPLIT_FLAG_1;
        end else begin
          cur_leaf_split_ctx = CTX_SPLIT_FLAG_0;
        end
      end else if (cur_mtt_q == 3'd0) begin
        cur_leaf_split_ctx = CTX_SPLIT_FLAG_6;
      end else begin
        cur_leaf_split_ctx = CTX_SPLIT_FLAG_3;
      end
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
      cur_chroma_q <= 1'b0;
      split_is_qt_q <= 1'b0;
      split_vertical_q <= 1'b0;
      split_chroma_q <= 1'b0;
      split_x_q <= 16'd0;
      split_y_q <= 16'd0;
      split_w_q <= 16'd0;
      split_h_q <= 16'd0;
      split_cqt_q <= 3'd0;
      split_mtt_q <= 3'd0;
      split_ctx_q <= 5'd0;
      split_write_split_q <= 1'b0;
      split_qt_ctx_q <= 5'd0;
      split_qt_bin_q <= 1'b0;
      split_write_qt_q <= 1'b0;
      split_write_mtt_q <= 1'b0;
      split_mtt_ctx_q <= 5'd0;
      split_write_binary_q <= 1'b0;
      split_binary_ctx_q <= 5'd0;
      leaf_cbf_q <= 1'b0;
      residual_step_q <= 4'd0;
    end else if (clear) begin
      state_q <= ST_IDLE;
      stack_count_q <= 6'd0;
      chroma_started_q <= 1'b0;
      m_axis_valid <= 1'b0;
      m_axis_kind <= 8'd0;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;
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
            stack_x[0] <= 16'd0;
            stack_y[0] <= 16'd0;
            stack_w[0] <= CTU_SIZE_L;
            stack_h[0] <= CTU_SIZE_L;
            stack_cqt[0] <= 3'd0;
            stack_mtt[0] <= 3'd0;
            stack_chroma[0] <= 1'b0;
            stack_count_q <= 6'd1;
            chroma_started_q <= 1'b0;
            state_q <= ST_POP;
          end
        end

        ST_POP: begin
          if (stack_count_q == 6'd0) begin
            if (!chroma_started_q) begin
              stack_x[0] <= 16'd0;
              stack_y[0] <= 16'd0;
              stack_w[0] <= (CTU_SIZE_L >> 1);
              stack_h[0] <= (CTU_SIZE_L >> 1);
              stack_cqt[0] <= 3'd0;
              stack_mtt[0] <= 3'd0;
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
            cur_chroma_q <= stack_chroma[stack_count_q - 6'd1];
            stack_count_q <= stack_count_q - 6'd1;
            state_q <= ST_DISPATCH;
          end
        end

        ST_DISPATCH: begin
          if (!cur_intersects) begin
            state_q <= ST_POP;
          end else if (cur_fits && (cur_w_q <= cur_leaf_max) && (cur_h_q <= cur_leaf_max)) begin
            leaf_cbf_q <= !cur_chroma_q && (cur_x_q == 16'd0) && (cur_y_q == 16'd0) && (luma_abs_level != 5'd0);
            residual_step_q <= 4'd0;
            state_q <= cur_chroma_q ? ST_CHROMA_SPLIT : ST_LUMA_SPLIT;
          end else if (!cur_fits) begin
            if (!cur_bottom_left_in_pic && !cur_top_right_in_pic) begin
              split_is_qt_q <= 1'b1;
              split_chroma_q <= cur_chroma_q;
              split_x_q <= cur_x_q;
              split_y_q <= cur_y_q;
              split_w_q <= cur_w_q;
              split_h_q <= cur_h_q;
              split_cqt_q <= cur_cqt_q;
              split_mtt_q <= cur_mtt_q;
              state_q <= ST_SPLIT_PUSH;
            end else begin
              split_is_qt_q <= 1'b0;
              split_vertical_q <= !cur_top_right_in_pic;
              split_chroma_q <= cur_chroma_q;
              split_x_q <= cur_x_q;
              split_y_q <= cur_y_q;
              split_w_q <= cur_w_q;
              split_h_q <= cur_h_q;
              split_cqt_q <= cur_cqt_q;
              split_mtt_q <= cur_mtt_q;
              split_ctx_q <= CTX_SPLIT_FLAG_3;
              split_write_split_q <= 1'b0;
              split_qt_ctx_q <= (cur_cqt_q >= 3'd2) ? CTX_SPLIT_QT_FLAG_3 : CTX_SPLIT_QT_FLAG_0;
              split_qt_bin_q <= 1'b0;
              split_write_qt_q <= 1'b1;
              split_write_mtt_q <= 1'b0;
              split_mtt_ctx_q <= CTX_MTT_SPLIT_CU_VERTICAL_3;
              split_write_binary_q <= 1'b0;
              split_binary_ctx_q <= !cur_top_right_in_pic ? CTX_MTT_SPLIT_CU_BINARY_3 : CTX_MTT_SPLIT_CU_BINARY_1;
              state_q <= ST_SPLIT_FLAG;
            end
          end else if (!cur_chroma_q && cur_mtt_q != 3'd0) begin
            split_is_qt_q <= 1'b0;
            split_vertical_q <= fits_split_vertical;
            split_chroma_q <= 1'b0;
            split_x_q <= cur_x_q;
            split_y_q <= cur_y_q;
            split_w_q <= cur_w_q;
            split_h_q <= cur_h_q;
            split_cqt_q <= cur_cqt_q;
            split_mtt_q <= cur_mtt_q;
            split_ctx_q <= CTX_SPLIT_FLAG_3;
            split_write_split_q <= 1'b1;
            split_qt_ctx_q <= (cur_cqt_q >= 3'd2) ? CTX_SPLIT_QT_FLAG_3 : CTX_SPLIT_QT_FLAG_0;
            split_qt_bin_q <= 1'b0;
            split_write_qt_q <= 1'b1;
            split_write_mtt_q <= 1'b1;
            split_mtt_ctx_q <= CTX_MTT_SPLIT_CU_VERTICAL_0;
            split_write_binary_q <= 1'b0;
            split_binary_ctx_q <= fits_split_vertical ? CTX_MTT_SPLIT_CU_BINARY_3 : CTX_MTT_SPLIT_CU_BINARY_1;
            state_q <= ST_SPLIT_FLAG;
          end else begin
            split_is_qt_q <= 1'b1;
            split_chroma_q <= cur_chroma_q;
            split_x_q <= cur_x_q;
            split_y_q <= cur_y_q;
            split_w_q <= cur_w_q;
            split_h_q <= cur_h_q;
            split_cqt_q <= cur_cqt_q;
            split_mtt_q <= cur_mtt_q;
            split_ctx_q <= cur_chroma_q ?
              ((cur_cqt_q == 3'd0) ? CTX_SPLIT_FLAG_3 : CTX_SPLIT_FLAG_6) :
              (((cur_cqt_q == 3'd0) && (cur_mtt_q == 3'd0)) ? CTX_SPLIT_FLAG_0 : CTX_SPLIT_FLAG_6);
            split_write_split_q <= 1'b1;
            split_qt_ctx_q <= (cur_cqt_q >= 3'd2) ? CTX_SPLIT_QT_FLAG_3 : CTX_SPLIT_QT_FLAG_0;
            split_qt_bin_q <= 1'b1;
            split_write_qt_q <= cur_chroma_q || (cur_cqt_q != 3'd0) || (cur_mtt_q != 3'd0);
            split_write_mtt_q <= 1'b0;
            split_mtt_ctx_q <= 5'd0;
            split_write_binary_q <= 1'b0;
            split_binary_ctx_q <= 5'd0;
            state_q <= ST_SPLIT_FLAG;
          end
        end

        ST_SPLIT_FLAG: begin
          if (split_write_split_q) begin
            m_axis_valid <= 1'b1;
            m_axis_kind <= SYMBOL_BIN_CTX;
            m_axis_data <= {19'd0, split_ctx_q, 7'd0, 1'b1};
          end
          state_q <= ST_SPLIT_QT;
        end

        ST_SPLIT_QT: begin
          if (split_write_qt_q) begin
            m_axis_valid <= 1'b1;
            m_axis_kind <= SYMBOL_BIN_CTX;
            m_axis_data <= {19'd0, split_qt_ctx_q, 7'd0, split_qt_bin_q};
            state_q <= ST_SPLIT_MTT;
          end else begin
            state_q <= ST_SPLIT_MTT;
          end
        end

        ST_SPLIT_MTT: begin
          if (split_write_mtt_q) begin
            m_axis_valid <= 1'b1;
            m_axis_kind <= SYMBOL_BIN_CTX;
            m_axis_data <= {19'd0, split_mtt_ctx_q, 7'd0, split_vertical_q};
            state_q <= ST_SPLIT_BIN;
          end else begin
            state_q <= ST_SPLIT_BIN;
          end
        end

        ST_SPLIT_BIN: begin
          if (split_write_binary_q) begin
            m_axis_valid <= 1'b1;
            m_axis_kind <= SYMBOL_BIN_CTX;
            m_axis_data <= {19'd0, split_binary_ctx_q, 7'd0, 1'b1};
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
            stack_chroma[stack_count_q] <= split_chroma_q;
            stack_x[stack_count_q + 6'd1] <= split_x_q;
            stack_y[stack_count_q + 6'd1] <= split_y_q + (split_h_q >> 1);
            stack_w[stack_count_q + 6'd1] <= split_w_q >> 1;
            stack_h[stack_count_q + 6'd1] <= split_h_q >> 1;
            stack_cqt[stack_count_q + 6'd1] <= split_cqt_q + 3'd1;
            stack_mtt[stack_count_q + 6'd1] <= 3'd0;
            stack_chroma[stack_count_q + 6'd1] <= split_chroma_q;
            stack_x[stack_count_q + 6'd2] <= split_x_q + (split_w_q >> 1);
            stack_y[stack_count_q + 6'd2] <= split_y_q;
            stack_w[stack_count_q + 6'd2] <= split_w_q >> 1;
            stack_h[stack_count_q + 6'd2] <= split_h_q >> 1;
            stack_cqt[stack_count_q + 6'd2] <= split_cqt_q + 3'd1;
            stack_mtt[stack_count_q + 6'd2] <= 3'd0;
            stack_chroma[stack_count_q + 6'd2] <= split_chroma_q;
            stack_x[stack_count_q + 6'd3] <= split_x_q;
            stack_y[stack_count_q + 6'd3] <= split_y_q;
            stack_w[stack_count_q + 6'd3] <= split_w_q >> 1;
            stack_h[stack_count_q + 6'd3] <= split_h_q >> 1;
            stack_cqt[stack_count_q + 6'd3] <= split_cqt_q + 3'd1;
            stack_mtt[stack_count_q + 6'd3] <= 3'd0;
            stack_chroma[stack_count_q + 6'd3] <= split_chroma_q;
            stack_count_q <= stack_count_q + 6'd4;
          end else if (split_vertical_q) begin
            stack_x[stack_count_q] <= split_x_q + (split_w_q >> 1);
            stack_y[stack_count_q] <= split_y_q;
            stack_w[stack_count_q] <= split_w_q >> 1;
            stack_h[stack_count_q] <= split_h_q;
            stack_cqt[stack_count_q] <= split_cqt_q;
            stack_mtt[stack_count_q] <= split_mtt_q + 3'd1;
            stack_chroma[stack_count_q] <= split_chroma_q;
            stack_x[stack_count_q + 6'd1] <= split_x_q;
            stack_y[stack_count_q + 6'd1] <= split_y_q;
            stack_w[stack_count_q + 6'd1] <= split_w_q >> 1;
            stack_h[stack_count_q + 6'd1] <= split_h_q;
            stack_cqt[stack_count_q + 6'd1] <= split_cqt_q;
            stack_mtt[stack_count_q + 6'd1] <= split_mtt_q + 3'd1;
            stack_chroma[stack_count_q + 6'd1] <= split_chroma_q;
            stack_count_q <= stack_count_q + 6'd2;
          end else begin
            stack_x[stack_count_q] <= split_x_q;
            stack_y[stack_count_q] <= split_y_q + (split_h_q >> 1);
            stack_w[stack_count_q] <= split_w_q;
            stack_h[stack_count_q] <= split_h_q >> 1;
            stack_cqt[stack_count_q] <= split_cqt_q;
            stack_mtt[stack_count_q] <= split_mtt_q + 3'd1;
            stack_chroma[stack_count_q] <= split_chroma_q;
            stack_x[stack_count_q + 6'd1] <= split_x_q;
            stack_y[stack_count_q + 6'd1] <= split_y_q;
            stack_w[stack_count_q + 6'd1] <= split_w_q;
            stack_h[stack_count_q + 6'd1] <= split_h_q >> 1;
            stack_cqt[stack_count_q + 6'd1] <= split_cqt_q;
            stack_mtt[stack_count_q + 6'd1] <= split_mtt_q + 3'd1;
            stack_chroma[stack_count_q + 6'd1] <= split_chroma_q;
            stack_count_q <= stack_count_q + 6'd2;
          end
          state_q <= ST_POP;
        end

        ST_LUMA_SPLIT: begin
          if (cur_leaf_writes_split) begin
            m_axis_valid <= 1'b1;
            m_axis_kind <= SYMBOL_BIN_CTX;
            m_axis_data <= {19'd0, cur_leaf_split_ctx, 7'd0, 1'b0};
          end
          state_q <= ST_LUMA_MRL;
        end

        ST_LUMA_MRL: begin
          if (cur_y_q != 16'd0) begin
            m_axis_valid <= 1'b1;
            m_axis_kind <= SYMBOL_BIN_CTX;
            m_axis_data <= {19'd0, CTX_MULTI_REF_LINE_IDX_0, 7'd0, 1'b0};
          end
          state_q <= ST_LUMA_MPM;
        end

        ST_LUMA_MPM: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= {19'd0, CTX_INTRA_LUMA_MPM_FLAG, 7'd0, 1'b0};
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
          m_axis_data <= {19'd0, CTX_QT_CBF_Y_0, 7'd0, leaf_cbf_q};
          residual_step_q <= 4'd0;
          state_q <= leaf_cbf_q ? ST_LUMA_RESIDUAL : ST_POP;
        end

        ST_LUMA_RESIDUAL: begin
          m_axis_valid <= 1'b1;
          case (residual_step_q)
            4'd0: begin
              m_axis_kind <= SYMBOL_BIN_CTX;
              m_axis_data <= {19'd0, cur_last_sig_x_ctx, 7'd0, 1'b0};
              residual_step_q <= 4'd1;
            end
            4'd1: begin
              m_axis_kind <= SYMBOL_BIN_CTX;
              m_axis_data <= {19'd0, cur_last_sig_y_ctx, 7'd0, 1'b0};
              residual_step_q <= 4'd2;
            end
            4'd2: begin
              m_axis_kind <= SYMBOL_BIN_CTX;
              m_axis_data <= {19'd0, CTX_ABS_LEVEL_GTX_FLAG_0, 7'd0, luma_abs_level > 5'd1};
              residual_step_q <= (luma_abs_level <= 5'd1) ? 4'd7 : 4'd3;
            end
            4'd3: begin
              m_axis_kind <= SYMBOL_BIN_CTX;
              m_axis_data <= {19'd0, CTX_PAR_LEVEL_FLAG_0, 7'd0, luma_abs_level[0]};
              residual_step_q <= 4'd4;
            end
            4'd4: begin
              m_axis_kind <= SYMBOL_BIN_CTX;
              m_axis_data <= {19'd0, CTX_ABS_LEVEL_GTX_FLAG_32, 7'd0, luma_abs_level > 5'd3};
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
            m_axis_data <= {19'd0, cur_leaf_split_ctx, 7'd0, 1'b0};
          end
          state_q <= ST_CHROMA_CCLM;
        end

        ST_CHROMA_CCLM: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= {19'd0, CTX_CCLM_MODE_FLAG, 7'd0, 1'b0};
          state_q <= ST_CHROMA_MODE;
        end

        ST_CHROMA_MODE: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= {19'd0, CTX_INTRA_CHROMA_PRED_MODE_0, 7'd0, 1'b0};
          state_q <= ST_CHROMA_CBF_CB;
        end

        ST_CHROMA_CBF_CB: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= {19'd0, CTX_QT_CBF_CB_0, 7'd0, 1'b0};
          state_q <= ST_CHROMA_CBF_CR;
        end

        ST_CHROMA_CBF_CR: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= {19'd0, CTX_QT_CBF_CR_0, 7'd0, 1'b0};
          state_q <= ST_POP;
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
