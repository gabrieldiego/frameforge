`timescale 1ns/1ps

module ff_vvc_cabac_syntax_frontend #(
  parameter int VVC_CABAC_CTX_ID_BITS = 10
) (
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
  input  logic [7:0]  ctu_luma_dc_abs_level,
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
  localparam logic [7:0] SYMBOL_BIN_TRM = 8'd1;
  localparam logic [7:0] SYMBOL_BIN_CTX = 8'd2;
  localparam logic [7:0] SYMBOL_BINS_EP = 8'd4;

  localparam logic [7:0] PALETTE_PKT_CU_START = 8'h81;
  localparam logic [7:0] PALETTE_PKT_ENTRY_Y  = 8'h82;
  localparam logic [7:0] PALETTE_PKT_INDEX    = 8'h83;
  localparam logic [7:0] PALETTE_PKT_ENTRY_CB = 8'h84;
  localparam logic [7:0] PALETTE_PKT_ENTRY_CR = 8'h85;
  localparam logic [7:0] PALETTE_PKT_ESCAPE_Y  = 8'h86;
  localparam logic [7:0] PALETTE_PKT_ESCAPE_CB = 8'h87;
  localparam logic [7:0] PALETTE_PKT_ESCAPE_CR = 8'h88;
  localparam logic [7:0] IBC_PKT_CU            = 8'h89;
  localparam logic [7:0] TS_PKT_CU_START       = 8'h8A;
  localparam logic [7:0] TS_PKT_COEFF_Y        = 8'h8B;
  localparam logic [7:0] TS_PKT_COEFF_CB       = 8'h8C;
  localparam logic [7:0] TS_PKT_COEFF_CR       = 8'h8D;

  `include "ff_vvc_cabac_context_ids.svh"

  typedef enum logic [5:0] {
    ST_IDLE,
    ST_PAL_CU_SKIP,
    ST_PAL_PRED_MODE_IBC,
    ST_PAL_PRED_MODE,
    ST_PAL_PREDICTOR_RUN,
    ST_PAL_PREDICTOR_RUN_SUFFIX,
    ST_PAL_ENTRY_COUNT,
    ST_PAL_ENTRY_COUNT_SUFFIX,
    ST_PAL_ESCAPE_FLAG,
    ST_PAL_INDEX_TRANSPOSE,
    ST_PAL_INDEX_RUN_FLAG,
    ST_PAL_INDEX_COPY_ABOVE,
    ST_PAL_INDEX_LEVEL,
    ST_PAL_ESCAPE_PREFIX,
    ST_PAL_ESCAPE_SUFFIX,
    ST_IBC_CU_SKIP,
    ST_IBC_PRED_MODE,
    ST_IBC_GENERAL_MERGE,
    ST_IBC_MVD_GT0_X,
    ST_IBC_MVD_GT0_Y,
    ST_IBC_MVD_GT1_X,
    ST_IBC_MVD_GT1_Y,
    ST_IBC_MVD_MINUS2_X_PREFIX,
    ST_IBC_MVD_MINUS2_X_SUFFIX,
    ST_IBC_MVD_SIGN_X,
    ST_IBC_MVD_MINUS2_Y_PREFIX,
    ST_IBC_MVD_MINUS2_Y_SUFFIX,
    ST_IBC_MVD_SIGN_Y,
    ST_IBC_CU_CODED,
    ST_TS_CBF_CB,
    ST_TS_CBF_CR,
    ST_TS_CBF_Y,
    ST_TS_SELECT_COMPONENT,
    ST_TS_COLLECT_COMPONENT,
    ST_TS_SKIP_COMPONENT,
    ST_TS_FLAG,
    ST_TS_START_RESIDUAL,
    ST_TS_WAIT_RESIDUAL,
    ST_PAL_TERMINATE
  } state_t;

  state_t state_q;
  logic pending_raw_last_q;
  logic [7:0] palette_entry_count_q;
  logic [7:0] palette_entry_cr_count_q;
  logic [7:0] palette_index_count_q;
  logic [7:0] palette_max_index_q;
  logic       palette_escape_present_q;
  logic       palette_have_previous_cu_q;
  logic       palette_predictor_run_present_q;
  logic [7:0] palette_indices_q [0:63];
  // TODO(area): these escape banks mirror the upstream CU symbolizer storage.
  // Replace them with a subset-level escape stream so palette_escape_val can
  // be coded as packets arrive instead of buffering 3x64 bytes per palette CU.
  logic [7:0] palette_escape_y_q [0:63];
  logic [7:0] palette_escape_cb_q [0:63];
  logic [7:0] palette_escape_cr_q [0:63];
  logic       palette_run_copy_flags_q [0:15];
  logic [7:0] index_cur_pos_q;
  logic [7:0] index_min_sub_pos_q;
  logic [7:0] index_max_sub_pos_q;
  logic [7:0] index_level_pos_q;
  logic [7:0] index_prev_run_pos_q;
  logic       index_previous_run_type_copy_above_q;
  logic [7:0] index_prev_index_q;
  logic [31:0] eg0_prefix_pattern;
  logic [5:0] eg0_prefix_count;
  logic [31:0] eg0_suffix_pattern;
  logic [5:0] eg0_suffix_count;
  logic [31:0] eg0_symbol_work;
  logic [5:0] eg0_order_work;
  logic [3:0] eg0_i;
  logic [31:0] eg5_prefix_pattern;
  logic [5:0] eg5_prefix_count;
  logic [31:0] eg5_suffix_pattern;
  logic [5:0] eg5_suffix_count;
  logic [31:0] eg5_symbol_work;
  logic [5:0] eg5_order_work;
  logic [3:0] eg5_i;
  logic [31:0] eg1_prefix_pattern;
  logic [5:0] eg1_prefix_count;
  logic [31:0] eg1_suffix_pattern;
  logic [5:0] eg1_suffix_count;
  logic [31:0] eg1_symbol_work;
  logic [5:0] eg1_order_work;
  logic [3:0] eg1_i;
  logic signed [15:0] ibc_mvd_x_q;
  logic signed [15:0] ibc_mvd_y_q;
  logic ibc_residual_q;
  logic [15:0] ibc_abs_mvd_x;
  logic [15:0] ibc_abs_mvd_y;
  logic [15:0] ibc_abs_mvd_cur;
  logic [2:0] ibc_pred_mode_ctx_q;
  logic ts_cbf_y_q;
  logic ts_cbf_cb_q;
  logic ts_cbf_cr_q;
  logic [(9 * 16) - 1:0] ts_coeff_q;
  logic [1:0] ts_component_q;
  logic [3:0] ts_collect_count_q;
  logic ts_component_cbf_w;
  logic residual_emitter_start_q;
  logic residual_emitter_seen_busy_q;
  logic residual_axis_valid;
  logic residual_axis_ready;
  logic [7:0] residual_axis_kind;
  logic [31:0] residual_axis_data;
  logic residual_emitter_done;
  logic residual_emitter_busy;
  logic [7:0] index_cur_value;
  logic [7:0] index_prev_scan_value;
  logic [5:0] index_prev_scan_addr;
  logic index_identity;
  logic [7:0] index_dist;
  logic [2:0] index_run_copy_ctx_inc;
  logic [2:0] index_scan_y;
  logic index_copy_above_present;
  logic [31:0] trunc_pattern;
  logic [5:0] trunc_bit_count;
  logic [7:0] trunc_level;
  logic [7:0] trunc_num_symbols;
  logic [5:0] trunc_thresh;
  logic [7:0] trunc_val;
  logic [7:0] trunc_b;
  logic [7:0] escape_pos_q;
  logic [1:0] escape_component_q;
  logic [7:0] escape_cur_value;
  logic palette_raw_cu_last;
  logic output_slot_ready;

  assign output_slot_ready = !m_axis_valid;
  assign raw_symbol_ready =
    ((state_q == ST_IDLE) ||
     (state_q == ST_TS_COLLECT_COMPONENT) ||
     (state_q == ST_TS_SKIP_COMPONENT)) && output_slot_ready;
  assign ctu_ready = 1'b0;
  assign palette_raw_cu_last = raw_symbol_data[27];
  assign residual_axis_ready = output_slot_ready;

  always @* begin
    case (ts_component_q)
      2'd0: begin
        ts_component_cbf_w = ts_cbf_y_q;
      end
      2'd1: begin
        ts_component_cbf_w = ts_cbf_cb_q;
      end
      default: begin
        ts_component_cbf_w = ts_cbf_cr_q;
      end
    endcase
  end

  always @* begin
    eg0_prefix_pattern = 32'd0;
    eg0_prefix_count = 6'd0;
    eg0_suffix_pattern = 32'd0;
    eg0_suffix_count = 6'd0;
    eg0_symbol_work =
      ((state_q == ST_PAL_PREDICTOR_RUN) ||
       (state_q == ST_PAL_PREDICTOR_RUN_SUFFIX)) ? 32'd1 : {24'd0, palette_entry_count_q};
    eg0_order_work = 6'd0;
    for (eg0_i = 4'd0; eg0_i < 4'd8; eg0_i = eg0_i + 4'd1) begin
      if (eg0_symbol_work >= (32'd1 << eg0_order_work)) begin
        eg0_prefix_pattern = (eg0_prefix_pattern << 1) | 32'd1;
        eg0_prefix_count = eg0_prefix_count + 6'd1;
        eg0_symbol_work = eg0_symbol_work - (32'd1 << eg0_order_work);
        eg0_order_work = eg0_order_work + 6'd1;
      end
    end
    eg0_prefix_pattern = (eg0_prefix_pattern << 1);
    eg0_prefix_count = eg0_prefix_count + 6'd1;
    eg0_suffix_pattern = eg0_symbol_work;
    eg0_suffix_count = eg0_order_work;
  end

  always @* begin
    case (escape_component_q)
      2'd0: escape_cur_value = palette_escape_y_q[escape_pos_q[5:0]];
      2'd1: escape_cur_value = palette_escape_cb_q[escape_pos_q[5:0]];
      default: escape_cur_value = palette_escape_cr_q[escape_pos_q[5:0]];
    endcase
  end

  always @* begin
    eg5_prefix_pattern = 32'd0;
    eg5_prefix_count = 6'd0;
    eg5_suffix_pattern = 32'd0;
    eg5_suffix_count = 6'd0;
    eg5_symbol_work = {24'd0, escape_cur_value};
    eg5_order_work = 6'd5;
    for (eg5_i = 4'd0; eg5_i < 4'd4; eg5_i = eg5_i + 4'd1) begin
      if (eg5_symbol_work >= (32'd1 << eg5_order_work)) begin
        eg5_prefix_pattern = (eg5_prefix_pattern << 1) | 32'd1;
        eg5_prefix_count = eg5_prefix_count + 6'd1;
        eg5_symbol_work = eg5_symbol_work - (32'd1 << eg5_order_work);
        eg5_order_work = eg5_order_work + 6'd1;
      end
    end
    eg5_prefix_pattern = eg5_prefix_pattern << 1;
    eg5_prefix_count = eg5_prefix_count + 6'd1;
    eg5_suffix_pattern = eg5_symbol_work;
    eg5_suffix_count = eg5_order_work;
  end

  always @* begin
    eg1_prefix_pattern = 32'd0;
    eg1_prefix_count = 6'd0;
    eg1_suffix_pattern = 32'd0;
    eg1_suffix_count = 6'd0;
    eg1_symbol_work = {16'd0, ibc_abs_mvd_cur - 16'd2};
    eg1_order_work = 6'd1;
    for (eg1_i = 4'd0; eg1_i < 4'd15; eg1_i = eg1_i + 4'd1) begin
      if (eg1_symbol_work >= (32'd1 << eg1_order_work)) begin
        eg1_prefix_pattern = (eg1_prefix_pattern << 1) | 32'd1;
        eg1_prefix_count = eg1_prefix_count + 6'd1;
        eg1_symbol_work = eg1_symbol_work - (32'd1 << eg1_order_work);
        eg1_order_work = eg1_order_work + 6'd1;
      end
    end
    eg1_prefix_pattern = eg1_prefix_pattern << 1;
    eg1_prefix_count = eg1_prefix_count + 6'd1;
    eg1_suffix_pattern = eg1_symbol_work;
    eg1_suffix_count = eg1_order_work;
  end

  always @* begin
    ibc_abs_mvd_x = ibc_mvd_x_q[15] ? (~ibc_mvd_x_q + 16'sd1) : ibc_mvd_x_q;
    ibc_abs_mvd_y = ibc_mvd_y_q[15] ? (~ibc_mvd_y_q + 16'sd1) : ibc_mvd_y_q;
    ibc_abs_mvd_cur =
      ((state_q == ST_IBC_MVD_MINUS2_X_PREFIX) ||
       (state_q == ST_IBC_MVD_MINUS2_X_SUFFIX)) ? ibc_abs_mvd_x : ibc_abs_mvd_y;
  end

  assign index_cur_value = palette_indices_q[index_cur_pos_q[5:0]];
  assign index_prev_scan_addr = index_level_pos_q[5:0] - 6'd1;
  assign index_prev_scan_value = palette_indices_q[index_prev_scan_addr];
  assign index_identity = (index_cur_pos_q > 8'd0) && (index_cur_value == index_prev_index_q);
  assign index_dist = index_cur_pos_q - index_prev_run_pos_q - 8'd1;
  assign index_scan_y = index_cur_pos_q[5:3];
  assign index_copy_above_present = (index_cur_pos_q != 8'd0) && (index_scan_y != 3'd0);

  always @* begin
    if (index_previous_run_type_copy_above_q) begin
      if (index_dist == 8'd0) begin
        index_run_copy_ctx_inc = 3'd5;
      end else if (index_dist <= 8'd2) begin
        index_run_copy_ctx_inc = 3'd6;
      end else begin
        index_run_copy_ctx_inc = 3'd7;
      end
    end else begin
      if (index_dist == 8'd0) begin
        index_run_copy_ctx_inc = 3'd0;
      end else if (index_dist == 8'd1) begin
        index_run_copy_ctx_inc = 3'd1;
      end else if (index_dist == 8'd2) begin
        index_run_copy_ctx_inc = 3'd2;
      end else if (index_dist == 8'd3) begin
        index_run_copy_ctx_inc = 3'd3;
      end else begin
        index_run_copy_ctx_inc = 3'd4;
      end
    end
  end

  always @* begin
    trunc_level = palette_indices_q[index_level_pos_q[5:0]];
    trunc_num_symbols = palette_max_index_q + 8'd1 - {7'd0, (index_level_pos_q > 8'd0)};
    if (index_level_pos_q > 8'd0) begin
      if (trunc_level > index_prev_scan_value) begin
        trunc_level = trunc_level - 8'd1;
      end
    end

    trunc_thresh = 6'd0;
    for (int i = 0; i < 5; i = i + 1) begin
      if ((8'd1 << i) <= trunc_num_symbols) begin
        trunc_thresh = i[5:0];
      end
    end
    trunc_val = 8'd1 << trunc_thresh;
    trunc_b = trunc_num_symbols - trunc_val;
    if (trunc_level < (trunc_val - trunc_b)) begin
      trunc_pattern = {24'd0, trunc_level};
      trunc_bit_count = trunc_thresh;
    end else begin
      trunc_pattern = {24'd0, trunc_level + trunc_val - trunc_b};
      trunc_bit_count = trunc_thresh + 6'd1;
    end
  end

  ff_vvc_residual_symbol_emitter_4x4 #(
    .RAW_COEFF_MODE(1)
  ) ts_residual_symbol_emitter (
    .clk(clk),
    .rst_n(rst_n),
    .clear(clear),
    .start(residual_emitter_start_q),
    .chroma_mode(ts_component_q != 2'd0),
    .tb_width(16'd8),
    .tb_height(16'd8),
    .luma_dc_abs(8'd0),
    .luma_dc_negative(1'b0),
    .luma_ac_levels({(4 * 15){1'b0}}),
    .chroma_dc_level(9'sd0),
    .chroma_ac_levels({(4 * 3){1'b0}}),
    .raw_coeff_levels(ts_coeff_q),
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
      pending_raw_last_q <= 1'b0;
      palette_entry_count_q <= 8'd0;
      palette_entry_cr_count_q <= 8'd0;
      palette_index_count_q <= 8'd0;
      palette_max_index_q <= 8'd0;
      palette_escape_present_q <= 1'b0;
      palette_have_previous_cu_q <= 1'b0;
      palette_predictor_run_present_q <= 1'b0;
      index_cur_pos_q <= 8'd0;
      index_min_sub_pos_q <= 8'd0;
      index_max_sub_pos_q <= 8'd0;
      index_level_pos_q <= 8'd0;
      index_prev_run_pos_q <= 8'd0;
      index_previous_run_type_copy_above_q <= 1'b0;
      index_prev_index_q <= 8'd0;
      escape_pos_q <= 8'd0;
      escape_component_q <= 2'd0;
      ibc_mvd_x_q <= 16'sd0;
      ibc_mvd_y_q <= 16'sd0;
      ibc_residual_q <= 1'b0;
      ibc_pred_mode_ctx_q <= 3'd0;
      ts_cbf_y_q <= 1'b0;
      ts_cbf_cb_q <= 1'b0;
      ts_cbf_cr_q <= 1'b0;
      ts_coeff_q <= '0;
      ts_component_q <= 2'd0;
      ts_collect_count_q <= 4'd0;
      residual_emitter_start_q <= 1'b0;
      residual_emitter_seen_busy_q <= 1'b0;
      m_axis_valid <= 1'b0;
      m_axis_kind <= SYMBOL_BIN_EP;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;
      for (int i = 0; i < 64; i = i + 1) begin
        palette_indices_q[i] <= 8'd0;
        palette_escape_y_q[i] <= 8'd0;
        palette_escape_cb_q[i] <= 8'd0;
        palette_escape_cr_q[i] <= 8'd0;
      end
      for (int i = 0; i < 16; i = i + 1) begin
        palette_run_copy_flags_q[i] <= 1'b0;
      end
    end else if (clear) begin
      state_q <= ST_IDLE;
      pending_raw_last_q <= 1'b0;
      palette_entry_count_q <= 8'd0;
      palette_entry_cr_count_q <= 8'd0;
      palette_index_count_q <= 8'd0;
      palette_max_index_q <= 8'd0;
      palette_escape_present_q <= 1'b0;
      palette_have_previous_cu_q <= 1'b0;
      palette_predictor_run_present_q <= 1'b0;
      index_cur_pos_q <= 8'd0;
      index_min_sub_pos_q <= 8'd0;
      index_max_sub_pos_q <= 8'd0;
      index_level_pos_q <= 8'd0;
      index_prev_run_pos_q <= 8'd0;
      index_previous_run_type_copy_above_q <= 1'b0;
      index_prev_index_q <= 8'd0;
      escape_pos_q <= 8'd0;
      escape_component_q <= 2'd0;
      ibc_mvd_x_q <= 16'sd0;
      ibc_mvd_y_q <= 16'sd0;
      ibc_residual_q <= 1'b0;
      ibc_pred_mode_ctx_q <= 3'd0;
      ts_cbf_y_q <= 1'b0;
      ts_cbf_cb_q <= 1'b0;
      ts_cbf_cr_q <= 1'b0;
      ts_coeff_q <= '0;
      ts_component_q <= 2'd0;
      ts_collect_count_q <= 4'd0;
      residual_emitter_start_q <= 1'b0;
      residual_emitter_seen_busy_q <= 1'b0;
      m_axis_valid <= 1'b0;
      m_axis_kind <= SYMBOL_BIN_EP;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;
    end else if (m_axis_valid && m_axis_ready) begin
      residual_emitter_start_q <= 1'b0;
      m_axis_valid <= 1'b0;
      m_axis_kind <= SYMBOL_BIN_EP;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;
    end else if (output_slot_ready) begin
      residual_emitter_start_q <= 1'b0;
      m_axis_valid <= 1'b0;
      m_axis_kind <= SYMBOL_BIN_EP;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;

      case (state_q)
        ST_PAL_PRED_MODE: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= 32'd1 | ({22'd0, CTX_PRED_MODE_PLT_FLAG} << 8);
          m_axis_last <= 1'b0;
          state_q <= palette_predictor_run_present_q ? ST_PAL_PREDICTOR_RUN : ST_PAL_ENTRY_COUNT;
        end

        ST_PAL_CU_SKIP: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= ({22'd0, CTX_CU_SKIP_FLAG_0} << 8);
          m_axis_last <= 1'b0;
          state_q <= ST_PAL_PRED_MODE_IBC;
        end

        ST_PAL_PRED_MODE_IBC: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= ({22'd0, CTX_PRED_MODE_IBC_FLAG_0 + ibc_pred_mode_ctx_q} << 8);
          m_axis_last <= 1'b0;
          state_q <= ST_PAL_PRED_MODE;
        end

        ST_PAL_PREDICTOR_RUN: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BINS_EP;
          // H.266 cu_palette_info() codes palette_predictor_run as EG0
          // bypass syntax. Keep prefix and suffix as separate bypass groups
          // so the RTL CABAC stream matches the Rust reference byte-for-byte.
          m_axis_data <= (eg0_prefix_pattern << 6) | {26'd0, eg0_prefix_count};
          m_axis_last <= 1'b0;
          state_q <= ST_PAL_PREDICTOR_RUN_SUFFIX;
        end

        ST_PAL_PREDICTOR_RUN_SUFFIX: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BINS_EP;
          m_axis_data <= (eg0_suffix_pattern << 6) | {26'd0, eg0_suffix_count};
          m_axis_last <= 1'b0;
          state_q <= ST_PAL_ENTRY_COUNT;
        end

        ST_PAL_ENTRY_COUNT: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BINS_EP;
          // H.266 cu_palette_info() codes num_signalled_palette_entries as
          // EG0 bypass syntax, matching encode_exp_golomb_ep() in software.
          m_axis_data <= (eg0_prefix_pattern << 6) | {26'd0, eg0_prefix_count};
          m_axis_last <= 1'b0;
          state_q <= ST_PAL_ENTRY_COUNT_SUFFIX;
        end

        ST_PAL_ENTRY_COUNT_SUFFIX: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BINS_EP;
          m_axis_data <= (eg0_suffix_pattern << 6) | {26'd0, eg0_suffix_count};
          m_axis_last <= 1'b0;
          state_q <= pending_raw_last_q ? ST_PAL_TERMINATE : ST_IDLE;
        end

        ST_PAL_ESCAPE_FLAG: begin
          m_axis_valid <= 1'b1;
          // H.266 cu_palette_info() carries palette_escape_val_present_flag
          // as a fixed-length bypass syntax element, which the software model
          // emits through encode_bins_ep(value=flag, bit_count=1).
          m_axis_kind <= SYMBOL_BINS_EP;
          m_axis_data <= ({31'd0, palette_escape_present_q} << 6) | 32'd1;
          m_axis_last <= 1'b0;
          state_q <= pending_raw_last_q ? ST_PAL_TERMINATE : ST_IDLE;
        end

        ST_PAL_INDEX_TRANSPOSE: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= ({22'd0, CTX_PALETTE_TRANSPOSE_FLAG} << 8);
          m_axis_last <= 1'b0;
          index_cur_pos_q <= 8'd0;
          index_min_sub_pos_q <= 8'd0;
          index_max_sub_pos_q <= (palette_index_count_q < 8'd16) ? palette_index_count_q : 8'd16;
          index_level_pos_q <= 8'd0;
          index_prev_run_pos_q <= 8'd0;
          index_previous_run_type_copy_above_q <= 1'b0;
          index_prev_index_q <= 8'd0;
          for (int i = 0; i < 16; i = i + 1) begin
            palette_run_copy_flags_q[i] <= 1'b0;
          end
          state_q <= ST_PAL_INDEX_RUN_FLAG;
        end

        ST_PAL_INDEX_RUN_FLAG: begin
          if (index_cur_pos_q >= index_max_sub_pos_q) begin
            index_level_pos_q <= index_min_sub_pos_q;
            state_q <= ST_PAL_INDEX_LEVEL;
          end else if (index_cur_pos_q == 8'd0) begin
            palette_run_copy_flags_q[0] <= 1'b0;
            index_prev_run_pos_q <= 8'd0;
            index_previous_run_type_copy_above_q <= 1'b0;
            index_prev_index_q <= index_cur_value;
            index_cur_pos_q <= index_cur_pos_q + 8'd1;
          end else begin
            m_axis_valid <= 1'b1;
            m_axis_kind <= SYMBOL_BIN_CTX;
            m_axis_data <= (({22'd0, CTX_RUN_COPY_FLAG_0 + index_run_copy_ctx_inc}) << 8) |
                           {31'd0, index_identity};
            m_axis_last <= 1'b0;
            palette_run_copy_flags_q[index_cur_pos_q[3:0]] <= index_identity;
            if (!index_identity) begin
              index_prev_run_pos_q <= index_cur_pos_q;
              index_previous_run_type_copy_above_q <= 1'b0;
            end
            index_prev_index_q <= index_cur_value;
            if (!index_identity && index_copy_above_present) begin
              state_q <= ST_PAL_INDEX_COPY_ABOVE;
            end else begin
              index_cur_pos_q <= index_cur_pos_q + 8'd1;
            end
          end
        end

        ST_PAL_INDEX_COPY_ABOVE: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= ({22'd0, CTX_COPY_ABOVE_PALETTE_FLAG} << 8);
          m_axis_last <= 1'b0;
          index_cur_pos_q <= index_cur_pos_q + 8'd1;
          state_q <= ST_PAL_INDEX_RUN_FLAG;
        end

        ST_PAL_INDEX_LEVEL: begin
          if (index_level_pos_q >= index_max_sub_pos_q) begin
            if (palette_escape_present_q) begin
              escape_pos_q <= index_min_sub_pos_q;
              escape_component_q <= 2'd0;
              state_q <= ST_PAL_ESCAPE_PREFIX;
            end else if (index_max_sub_pos_q >= palette_index_count_q) begin
              state_q <= pending_raw_last_q ? ST_PAL_TERMINATE : ST_IDLE;
            end else begin
              index_min_sub_pos_q <= index_max_sub_pos_q;
              index_max_sub_pos_q <= ((palette_index_count_q - index_max_sub_pos_q) < 8'd16) ?
                                     palette_index_count_q : (index_max_sub_pos_q + 8'd16);
              index_cur_pos_q <= index_max_sub_pos_q;
              for (int i = 0; i < 16; i = i + 1) begin
                palette_run_copy_flags_q[i] <= 1'b0;
              end
              state_q <= ST_PAL_INDEX_RUN_FLAG;
            end
          end else if (palette_run_copy_flags_q[index_level_pos_q[3:0]] ||
                       (trunc_num_symbols <= 8'd1)) begin
            index_level_pos_q <= index_level_pos_q + 8'd1;
          end else begin
            m_axis_valid <= 1'b1;
            m_axis_kind <= SYMBOL_BINS_EP;
            m_axis_data <= (trunc_pattern << 6) | {26'd0, trunc_bit_count};
            m_axis_last <= 1'b0;
            index_level_pos_q <= index_level_pos_q + 8'd1;
          end
        end

        ST_PAL_ESCAPE_PREFIX: begin
          if (escape_pos_q >= index_max_sub_pos_q) begin
            if (escape_component_q < 2'd2) begin
              escape_component_q <= escape_component_q + 2'd1;
              escape_pos_q <= index_min_sub_pos_q;
            end else if (index_max_sub_pos_q >= palette_index_count_q) begin
              state_q <= pending_raw_last_q ? ST_PAL_TERMINATE : ST_IDLE;
            end else begin
              index_min_sub_pos_q <= index_max_sub_pos_q;
              index_max_sub_pos_q <= ((palette_index_count_q - index_max_sub_pos_q) < 8'd16) ?
                                     palette_index_count_q : (index_max_sub_pos_q + 8'd16);
              index_cur_pos_q <= index_max_sub_pos_q;
              for (int i = 0; i < 16; i = i + 1) begin
                palette_run_copy_flags_q[i] <= 1'b0;
              end
              state_q <= ST_PAL_INDEX_RUN_FLAG;
            end
          end else if (palette_indices_q[escape_pos_q[5:0]] == palette_max_index_q) begin
            m_axis_valid <= 1'b1;
            m_axis_kind <= SYMBOL_BINS_EP;
            // H.266 7.3.11.6 places palette_escape_val after each 16-sample
            // index subset. Table 130 marks it as bypass-coded and 9.3.3 uses
            // EG5 binarization, split here into prefix and suffix groups to
            // mirror the Rust CABAC writer.
            // TODO(area): once escape values are streamed by subset, consume
            // the live escape packet here instead of indexing the full-CU
            // palette_escape_*_q banks.
            m_axis_data <= (eg5_prefix_pattern << 6) | {26'd0, eg5_prefix_count};
            m_axis_last <= 1'b0;
            state_q <= ST_PAL_ESCAPE_SUFFIX;
          end else begin
            escape_pos_q <= escape_pos_q + 8'd1;
          end
        end

        ST_PAL_ESCAPE_SUFFIX: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BINS_EP;
          m_axis_data <= (eg5_suffix_pattern << 6) | {26'd0, eg5_suffix_count};
          m_axis_last <= 1'b0;
          escape_pos_q <= escape_pos_q + 8'd1;
          state_q <= ST_PAL_ESCAPE_PREFIX;
        end

        ST_IBC_CU_SKIP: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= ({22'd0, CTX_CU_SKIP_FLAG_0} << 8);
          m_axis_last <= 1'b0;
          state_q <= ST_IBC_PRED_MODE;
        end

        ST_IBC_PRED_MODE: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= 32'd1 | ({22'd0, CTX_PRED_MODE_IBC_FLAG_0 + ibc_pred_mode_ctx_q} << 8);
          m_axis_last <= 1'b0;
          state_q <= ST_IBC_GENERAL_MERGE;
        end

        ST_IBC_GENERAL_MERGE: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= ({22'd0, CTX_GENERAL_MERGE_FLAG_0} << 8);
          m_axis_last <= 1'b0;
          state_q <= ST_IBC_MVD_GT0_X;
        end

        ST_IBC_MVD_GT0_X: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= ({22'd0, CTX_ABS_MVD_GREATER0_FLAG_0} << 8) |
                         {31'd0, (ibc_abs_mvd_x != 16'd0)};
          m_axis_last <= 1'b0;
          state_q <= ST_IBC_MVD_GT0_Y;
        end

        ST_IBC_MVD_GT0_Y: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= ({22'd0, CTX_ABS_MVD_GREATER0_FLAG_0} << 8) |
                         {31'd0, (ibc_abs_mvd_y != 16'd0)};
          m_axis_last <= 1'b0;
          state_q <= (ibc_abs_mvd_x != 16'd0) ? ST_IBC_MVD_GT1_X :
                     ((ibc_abs_mvd_y != 16'd0) ? ST_IBC_MVD_GT1_Y : ST_IBC_CU_CODED);
        end

        ST_IBC_MVD_GT1_X: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= ({22'd0, CTX_ABS_MVD_GREATER1_FLAG_0} << 8) |
                         {31'd0, (ibc_abs_mvd_x > 16'd1)};
          m_axis_last <= 1'b0;
          state_q <= (ibc_abs_mvd_y != 16'd0) ? ST_IBC_MVD_GT1_Y :
                     ((ibc_abs_mvd_x > 16'd1) ? ST_IBC_MVD_MINUS2_X_PREFIX :
                      ST_IBC_MVD_SIGN_X);
        end

        ST_IBC_MVD_GT1_Y: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= ({22'd0, CTX_ABS_MVD_GREATER1_FLAG_0} << 8) |
                         {31'd0, (ibc_abs_mvd_y > 16'd1)};
          m_axis_last <= 1'b0;
          if ((ibc_abs_mvd_x != 16'd0) && (ibc_abs_mvd_x > 16'd1)) begin
            state_q <= ST_IBC_MVD_MINUS2_X_PREFIX;
          end else if (ibc_abs_mvd_x != 16'd0) begin
            state_q <= ST_IBC_MVD_SIGN_X;
          end else if (ibc_abs_mvd_y > 16'd1) begin
            state_q <= ST_IBC_MVD_MINUS2_Y_PREFIX;
          end else begin
            state_q <= ST_IBC_MVD_SIGN_Y;
          end
        end

        ST_IBC_MVD_MINUS2_X_PREFIX: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BINS_EP;
          m_axis_data <= (eg1_prefix_pattern << 6) | {26'd0, eg1_prefix_count};
          m_axis_last <= 1'b0;
          state_q <= ST_IBC_MVD_MINUS2_X_SUFFIX;
        end

        ST_IBC_MVD_MINUS2_X_SUFFIX: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BINS_EP;
          m_axis_data <= (eg1_suffix_pattern << 6) | {26'd0, eg1_suffix_count};
          m_axis_last <= 1'b0;
          state_q <= ST_IBC_MVD_SIGN_X;
        end

        ST_IBC_MVD_SIGN_X: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_EP;
          m_axis_data <= {31'd0, ibc_mvd_x_q[15]};
          m_axis_last <= 1'b0;
          if (ibc_abs_mvd_y > 16'd1) begin
            state_q <= ST_IBC_MVD_MINUS2_Y_PREFIX;
          end else if (ibc_abs_mvd_y != 16'd0) begin
            state_q <= ST_IBC_MVD_SIGN_Y;
          end else begin
            state_q <= ST_IBC_CU_CODED;
          end
        end

        ST_IBC_MVD_MINUS2_Y_PREFIX: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BINS_EP;
          m_axis_data <= (eg1_prefix_pattern << 6) | {26'd0, eg1_prefix_count};
          m_axis_last <= 1'b0;
          state_q <= ST_IBC_MVD_MINUS2_Y_SUFFIX;
        end

        ST_IBC_MVD_MINUS2_Y_SUFFIX: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BINS_EP;
          m_axis_data <= (eg1_suffix_pattern << 6) | {26'd0, eg1_suffix_count};
          m_axis_last <= 1'b0;
          state_q <= ST_IBC_MVD_SIGN_Y;
        end

        ST_IBC_MVD_SIGN_Y: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_EP;
          m_axis_data <= {31'd0, ibc_mvd_y_q[15]};
          m_axis_last <= 1'b0;
          state_q <= ST_IBC_CU_CODED;
        end

        ST_IBC_CU_CODED: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= ({22'd0, CTX_CU_CODED_FLAG_0} << 8) |
                         {31'd0, ibc_residual_q};
          m_axis_last <= 1'b0;
          state_q <= ibc_residual_q ? ST_TS_CBF_CB :
                     (pending_raw_last_q ? ST_PAL_TERMINATE : ST_IDLE);
        end

        ST_TS_CBF_CB: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= ({22'd0, CTX_QT_CBF_CB_0} << 8) | {31'd0, ts_cbf_cb_q};
          m_axis_last <= 1'b0;
          state_q <= ST_TS_CBF_CR;
        end

        ST_TS_CBF_CR: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= ({22'd0, (ts_cbf_cb_q ? CTX_QT_CBF_CR_1 : CTX_QT_CBF_CR_0)} << 8) |
                         {31'd0, ts_cbf_cr_q};
          m_axis_last <= 1'b0;
          state_q <= ST_TS_CBF_Y;
        end

        ST_TS_CBF_Y: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= ({22'd0, CTX_QT_CBF_Y_0} << 8) | {31'd0, ts_cbf_y_q};
          m_axis_last <= 1'b0;
          ts_component_q <= 2'd0;
          state_q <= ST_TS_SELECT_COMPONENT;
        end

        ST_TS_SELECT_COMPONENT: begin
          if (ts_component_q >= 2'd3) begin
            ibc_residual_q <= 1'b0;
            state_q <= pending_raw_last_q ? ST_PAL_TERMINATE : ST_IDLE;
          end else if (ts_component_cbf_w) begin
            ts_coeff_q <= '0;
            ts_collect_count_q <= 4'd0;
            state_q <= ST_TS_COLLECT_COMPONENT;
          end else begin
            ts_collect_count_q <= 4'd0;
            state_q <= ST_TS_SKIP_COMPONENT;
          end
        end

        ST_TS_COLLECT_COMPONENT: begin
          if (raw_symbol_valid) begin
            pending_raw_last_q <= raw_symbol_last;
            ts_coeff_q[ts_collect_count_q * 9 +: 9] <= raw_symbol_data[8:0];
            if (ts_collect_count_q == 4'd15) begin
              ts_collect_count_q <= 4'd0;
              state_q <= ST_TS_FLAG;
            end else begin
              ts_collect_count_q <= ts_collect_count_q + 4'd1;
            end
          end
        end

        ST_TS_SKIP_COMPONENT: begin
          if (raw_symbol_valid) begin
            pending_raw_last_q <= raw_symbol_last;
            if (ts_collect_count_q == 4'd15) begin
              ts_collect_count_q <= 4'd0;
              ts_component_q <= ts_component_q + 2'd1;
              state_q <= ST_TS_SELECT_COMPONENT;
            end else begin
              ts_collect_count_q <= ts_collect_count_q + 4'd1;
            end
          end
        end

        ST_TS_FLAG: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= ({22'd0,
                           ((ts_component_q == 2'd0) ?
                            CTX_TRANSFORM_SKIP_FLAG_0 : CTX_TRANSFORM_SKIP_FLAG_1)} << 8) |
                         32'd1;
          m_axis_last <= 1'b0;
          state_q <= ST_TS_START_RESIDUAL;
        end

        ST_TS_START_RESIDUAL: begin
          residual_emitter_start_q <= 1'b1;
          residual_emitter_seen_busy_q <= 1'b0;
          state_q <= ST_TS_WAIT_RESIDUAL;
        end

        ST_TS_WAIT_RESIDUAL: begin
          if (residual_emitter_busy) begin
            residual_emitter_seen_busy_q <= 1'b1;
          end
          if (residual_axis_valid) begin
            m_axis_valid <= 1'b1;
            m_axis_kind <= residual_axis_kind;
            m_axis_data <= residual_axis_data;
            m_axis_last <= 1'b0;
          end else if (residual_emitter_seen_busy_q &&
                       residual_emitter_done && !residual_emitter_busy) begin
            ts_component_q <= ts_component_q + 2'd1;
            state_q <= ST_TS_SELECT_COMPONENT;
          end
        end

        ST_PAL_TERMINATE: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_TRM;
          m_axis_data <= 32'd1;
          m_axis_last <= 1'b1;
          state_q <= ST_IDLE;
        end

        default: begin
          state_q <= ST_IDLE;
          if (raw_symbol_valid) begin
            pending_raw_last_q <= raw_symbol_last;
            case (raw_symbol_kind)
              PALETTE_PKT_CU_START: begin
                palette_entry_count_q <= raw_symbol_data[23:16];
                palette_escape_present_q <= raw_symbol_data[25];
                palette_max_index_q <= (raw_symbol_data[23:16] == 8'd0) ? 8'd0 :
                  (raw_symbol_data[23:16] - 8'd1 + {7'd0, raw_symbol_data[25]});
                palette_entry_cr_count_q <= 8'd0;
                palette_index_count_q <= 8'd0;
                if (raw_symbol_data[24]) begin
                  palette_predictor_run_present_q <= palette_have_previous_cu_q;
                  palette_have_previous_cu_q <= 1'b1;
                  ibc_pred_mode_ctx_q <= raw_symbol_data[2:0];
                  // CTU split and leaf no-split decisions are supplied by the
                  // shared partition engine before each palette CU payload.
                  // With IBC enabled in the 4:4:4 SPS, this packet begins at
                  // cu_skip_flag=0, then pred_mode_ibc_flag=0, then
                  // pred_mode_plt_flag=1.
                  state_q <= ST_PAL_CU_SKIP;
                end else if (raw_symbol_last) begin
                  state_q <= ST_PAL_TERMINATE;
                end
              end

              PALETTE_PKT_ENTRY_Y,
              PALETTE_PKT_ENTRY_CB,
              PALETTE_PKT_ENTRY_CR: begin
                // H.266 cu_palette_info(): new_palette_entries are bypass bins
                // with the bit depth of the component. The RTL palette path is
                // still 8-bit only; widen this producer when SAMPLE_BITS > 8 is
                // carried through the palette symbol stream.
                m_axis_valid <= 1'b1;
                m_axis_kind <= SYMBOL_BINS_EP;
                m_axis_data <= ({24'd0, raw_symbol_data[7:0]} << 6) | 32'd8;
                m_axis_last <= 1'b0;
                if ((raw_symbol_kind == PALETTE_PKT_ENTRY_CR) &&
                    ((palette_entry_cr_count_q + 8'd1) >= palette_entry_count_q)) begin
                  state_q <= ST_PAL_ESCAPE_FLAG;
                end else begin
                  state_q <= raw_symbol_last ? ST_PAL_TERMINATE : ST_IDLE;
                end
                if (raw_symbol_kind == PALETTE_PKT_ENTRY_CR) begin
                  palette_entry_cr_count_q <= palette_entry_cr_count_q + 8'd1;
                end
              end

              PALETTE_PKT_INDEX: begin
                palette_indices_q[palette_index_count_q[5:0]] <= raw_symbol_data[7:0];
                palette_index_count_q <= palette_index_count_q + 8'd1;
                if (palette_max_index_q > 8'd0) begin
                  // H.266 7.3.11.6/9.3.4.2.11: palette index maps are coded
                  // as a transpose flag, run-copy flags, optional copy-above
                  // flags, and truncated index bins. End-of-CU and end-of-CABAC
                  // are separate signals: every CU must flush its own index map,
                  // while only the final CU terminates the CABAC stream.
                  state_q <= palette_raw_cu_last ? ST_PAL_INDEX_TRANSPOSE : ST_IDLE;
                end else if (raw_symbol_last) begin
                  m_axis_valid <= 1'b1;
                  m_axis_kind <= SYMBOL_BIN_TRM;
                  m_axis_data <= 32'd1;
                  m_axis_last <= 1'b1;
                  state_q <= ST_IDLE;
                end
              end

              PALETTE_PKT_ESCAPE_Y: begin
                palette_escape_y_q[raw_symbol_data[13:8]] <= raw_symbol_data[7:0];
                state_q <= raw_symbol_last ? ST_PAL_TERMINATE : ST_IDLE;
              end

              PALETTE_PKT_ESCAPE_CB: begin
                palette_escape_cb_q[raw_symbol_data[13:8]] <= raw_symbol_data[7:0];
                state_q <= raw_symbol_last ? ST_PAL_TERMINATE : ST_IDLE;
              end

              PALETTE_PKT_ESCAPE_CR: begin
                palette_escape_cr_q[raw_symbol_data[13:8]] <= raw_symbol_data[7:0];
                state_q <= raw_symbol_last ? ST_PAL_TERMINATE : ST_IDLE;
              end

              IBC_PKT_CU: begin
                ibc_mvd_x_q <= {{3{raw_symbol_data[12]}}, raw_symbol_data[12:0]};
                ibc_mvd_y_q <= {{3{raw_symbol_data[25]}}, raw_symbol_data[25:13]};
                ibc_pred_mode_ctx_q <= raw_symbol_data[28:26];
                ibc_residual_q <= 1'b0;
                state_q <= ST_IBC_CU_SKIP;
              end

              TS_PKT_CU_START: begin
                ts_cbf_y_q <= raw_symbol_data[0];
                ts_cbf_cb_q <= raw_symbol_data[1];
                ts_cbf_cr_q <= raw_symbol_data[2];
                ts_coeff_q <= '0;
                ts_component_q <= 2'd0;
                ts_collect_count_q <= 4'd0;
                ibc_mvd_x_q <= -16'sd8;
                ibc_mvd_y_q <= 16'sd0;
                ibc_pred_mode_ctx_q <= 3'd0;
                ibc_residual_q <= 1'b1;
                state_q <= ST_IBC_CU_SKIP;
              end

              TS_PKT_COEFF_Y: begin
                state_q <= raw_symbol_last ? ST_PAL_TERMINATE : ST_IDLE;
              end

              TS_PKT_COEFF_CB: begin
                state_q <= raw_symbol_last ? ST_PAL_TERMINATE : ST_IDLE;
              end

              TS_PKT_COEFF_CR: begin
                state_q <= (raw_symbol_data[12:9] == 4'd15) ? ST_IBC_CU_SKIP :
                           (raw_symbol_last ? ST_PAL_TERMINATE : ST_IDLE);
              end

              default: begin
                m_axis_valid <= 1'b1;
                m_axis_kind <= raw_symbol_kind;
                m_axis_data <= raw_symbol_data;
                m_axis_last <= raw_symbol_last;
              end
            endcase
          end
        end
      endcase
    end
  end

  (* keep = "true" *) logic unused_future_ctu_inputs;
  assign unused_future_ctu_inputs = ctu_valid || (|ctu_x) || (|ctu_y) ||
    (|ctu_visible_width) || (|ctu_visible_height) || (|ctu_luma_dc_abs_level) ||
    ctu_luma_dc_negative || ctu_luma_only || ctu_last;
endmodule
