`timescale 1ns/1ps

module ff_vvc_palette_symbolizer #(
  parameter int CTU_SIZE = 64,
  parameter int PALETTE_CU_SIZE = 8,
  parameter int SAMPLE_BITS = 8,
  parameter int MAX_PALETTE_SYMBOLS =
    ((CTU_SIZE + PALETTE_CU_SIZE - 1) / PALETTE_CU_SIZE) *
    ((CTU_SIZE + PALETTE_CU_SIZE - 1) / PALETTE_CU_SIZE)
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        clear,
  input  logic        enable,
  input  logic [15:0] ctu_coded_width,
  input  logic [15:0] ctu_coded_height,
  input  logic [15:0] ctu_visible_width,
  input  logic [15:0] ctu_visible_height,
  input  logic [MAX_PALETTE_SYMBOLS - 1:0] cu_select_mask,
  input  logic [MAX_PALETTE_SYMBOLS - 1:0] cu_ibc_mask,
  input  logic        cu_request_valid,
  output logic        cu_request_ready,
  input  logic [15:0] cu_request_origin_x,
  input  logic [15:0] cu_request_origin_y,
  input  logic        cu_request_last,
  input  logic        cu_request_prior_ibc_seen,
  input  logic        s_axis_valid,
  output logic        s_axis_ready,
  input  logic [1:0]  s_axis_plane,
  input  logic [8*SAMPLE_BITS - 1:0] s_axis_samples,
  input  logic [3:0]  s_axis_count,
  input  logic        s_axis_last,
  output logic        m_axis_valid,
  input  logic        m_axis_ready,
  output logic [31:0] m_axis_data,
  output logic        m_axis_last,
  output logic        m_axis_cu_last,
  output logic        m_axis_cu_ibc_mode,
  output logic [7:0]  symbol_count
);
  localparam logic [1:0] PLANE_Y  = 2'd0;
  localparam logic [1:0] PLANE_CB = 2'd1;
  localparam logic [1:0] PLANE_CR = 2'd2;
  localparam logic [3:0] PALETTE_PKT_CU_START = 4'h1;
  localparam logic [3:0] PALETTE_PKT_ENTRY_Y  = 4'h2;
  localparam logic [3:0] PALETTE_PKT_ENTRY_CB = 4'h4;
  localparam logic [3:0] PALETTE_PKT_ENTRY_CR = 4'h5;
  localparam logic [3:0] TS_PKT_CU_START  = 4'hA;
  localparam logic [3:0] TS_PKT_COEFF_Y   = 4'hB;
  localparam logic [3:0] TS_PKT_COEFF_CB  = 4'hC;
  localparam logic [3:0] TS_PKT_COEFF_CR  = 4'hD;
  localparam logic [3:0] BDPCM_PKT_CU_START = 4'hE;
  localparam int MAX_CU_SAMPLES = PALETTE_CU_SIZE * PALETTE_CU_SIZE;
  localparam int MAX_PLANE_SAMPLES = CTU_SIZE * CTU_SIZE;
  localparam int MAX_PLANE_ROWS = MAX_PLANE_SAMPLES / PALETTE_CU_SIZE;
  localparam int PLANE_COUNT_BITS = $clog2(MAX_PLANE_SAMPLES + 1);
  localparam int PLANE_ROW_BITS = $clog2(MAX_PLANE_ROWS);
  localparam logic [PLANE_COUNT_BITS - 1:0] MAX_CU_SAMPLES_L = MAX_CU_SAMPLES;

  typedef enum logic [2:0] {
    ST_INPUT,
    ST_WAIT_CU,
    ST_FEED_READ,
    ST_FEED_CU,
    ST_SELECT_CU,
    ST_DRAIN_CU,
    ST_DRAIN_TS_START,
    ST_DRAIN_TS_COEFF
  } state_t;

  state_t state_q;
  logic [PLANE_COUNT_BITS - 1:0] y_write_count_q;
  logic [PLANE_COUNT_BITS - 1:0] cb_write_count_q;
  logic [PLANE_COUNT_BITS - 1:0] cr_write_count_q;
  logic [7:0] drain_cu_index_q;
  logic [7:0] available_cu_count_q;
  logic [7:0] feed_sample_q;
  logic [3:0] coded_cu_count_x;
  logic [3:0] coded_cu_count_y;
  logic [7:0] root_leaf_count_value;
  logic input_valid;
  logic [3:0] input_lane_i;
  logic [7:0] input_lane_sample_w [0:7];
  logic [PLANE_ROW_BITS - 1:0] y_write_row_w;
  logic [PLANE_ROW_BITS - 1:0] cb_write_row_w;
  logic [PLANE_ROW_BITS - 1:0] cr_write_row_w;
  logic [2:0] y_write_lane_w;
  logic [2:0] cb_write_lane_w;
  logic [2:0] cr_write_lane_w;
  logic [PLANE_COUNT_BITS - 1:0] drain_cu_order_index_ext_w;
  logic [PLANE_COUNT_BITS - 1:0] feed_sample_ext_w;
  logic drain_cu_selected;
  logic drain_cu_is_last_selected;
  logic [15:0] drain_origin_x;
  logic [15:0] drain_origin_y;
  logic [15:0] drain_origin_x_q;
  logic [15:0] drain_origin_y_q;
  logic        drain_cu_is_last_selected_q;
  logic [15:0] feed_x;
  logic [15:0] feed_y;
  logic [15:0] feed_abs_x;
  logic [15:0] feed_abs_y;
  logic [7:0] feed_next_sample_w;
  logic [15:0] feed_next_y;
  logic [PLANE_COUNT_BITS - 1:0] feed_frame_index;
  logic [PLANE_COUNT_BITS - 1:0] feed_next_sample_ext_w;
  logic [PLANE_COUNT_BITS - 1:0] feed_next_frame_index;
  logic [3:0] visible_cu_cols_w;
  logic [3:0] visible_cu_rows_w;
  logic [2:0] drain_cu_col_w;
  logic [2:0] drain_cu_row_w;
  logic       drain_cu_order_valid_w;
  logic [5:0] drain_cu_order_index_w;
  logic [2:0] feed_left_cu_col_w;
  logic       feed_left_order_valid_w;
  logic [5:0] feed_left_order_index_w;
  logic [PLANE_COUNT_BITS - 1:0] feed_left_order_index_ext_w;
  logic [7:0] feed_y_sample;
  logic [7:0] feed_cb_sample;
  logic [7:0] feed_cr_sample;
  logic [7:0] feed_y_sample_q;
  logic [7:0] feed_cb_sample_q;
  logic [7:0] feed_cr_sample_q;
  logic [7:0] feed_left_y_sample_q;
  logic [7:0] feed_left_cb_sample_q;
  logic [7:0] feed_left_cr_sample_q;
  logic [7:0] feed_left_boundary_y_sample_q;
  logic [7:0] feed_left_boundary_cb_sample_q;
  logic [7:0] feed_left_boundary_cr_sample_q;
  logic [63:0] feed_y_row_q;
  logic [63:0] feed_cb_row_q;
  logic [63:0] feed_cr_row_q;
  logic [63:0] feed_left_y_row_q;
  logic [63:0] feed_left_cb_row_q;
  logic [63:0] feed_left_cr_row_q;
  logic [7:0] row_y_sample_w [0:7];
  logic [7:0] row_cb_sample_w [0:7];
  logic [7:0] row_cr_sample_w [0:7];
  logic [7:0] row_left_y_sample_w [0:7];
  logic [7:0] row_left_cb_sample_w [0:7];
  logic [7:0] row_left_cr_sample_w [0:7];
  logic signed [8:0] row_ts_y_diff_w [0:7];
  logic signed [8:0] row_ts_cb_diff_w [0:7];
  logic signed [8:0] row_ts_cr_diff_w [0:7];
  logic signed [8:0] row_bdpcm_y_diff_w [0:7];
  logic signed [8:0] row_bdpcm_cb_diff_w [0:7];
  logic signed [8:0] row_bdpcm_cr_diff_w [0:7];
  logic [3:0] row_coeff_lane_w [0:7];
  logic row_ts_cbf_y_w;
  logic row_ts_cbf_cb_w;
  logic row_ts_cbf_cr_w;
  logic row_bdpcm_cbf_y_w;
  logic row_bdpcm_cbf_cb_w;
  logic row_bdpcm_cbf_cr_w;
  logic row_ts_outside_nonzero_w;
  logic row_bdpcm_outside_nonzero_w;
  logic       feed_sample_last_q;
  logic       feed_sample_valid_q;
  logic       ts_candidate_q;
  logic       ts_cbf_y_q;
  logic       ts_cbf_cb_q;
  logic       ts_cbf_cr_q;
  logic [(9 * 16) - 1:0] ts_y_coeff_q;
  logic [(9 * 16) - 1:0] ts_cb_coeff_q;
  logic [(9 * 16) - 1:0] ts_cr_coeff_q;
  logic       bdpcm_candidate_q;
  logic       bdpcm_cbf_y_q;
  logic       bdpcm_cbf_cb_q;
  logic       bdpcm_cbf_cr_q;
  logic [(9 * 16) - 1:0] bdpcm_y_coeff_q;
  logic [(9 * 16) - 1:0] bdpcm_cb_coeff_q;
  logic [(9 * 16) - 1:0] bdpcm_cr_coeff_q;
  logic [7:0] bdpcm_prev_y_sample_q;
  logic [7:0] bdpcm_prev_cb_sample_q;
  logic [7:0] bdpcm_prev_cr_sample_q;
  logic       drain_bdpcm_q;
  logic [3:0] ts_coeff_index_q;
  logic [1:0] ts_coeff_component_q;
  logic cu_s_axis_valid;
  logic cu_s_axis_ready;
  logic cu_s_axis_last;
  logic cu_symbolizer_clear_w;
  logic cu_m_axis_valid;
  logic cu_m_axis_ready;
  logic [31:0] cu_m_axis_data;
  logic cu_m_axis_last;
  logic ts_residual_selected_w;
  logic bdpcm_residual_selected_w;
  logic residual_selected_w;
  logic ts_residual_drain_w;
  logic ts_coeff_last_w;
  logic [3:0] ts_coeff_packet_kind_w;
  logic signed [8:0] feed_y_diff_w;
  logic signed [8:0] feed_cb_diff_w;
  logic signed [8:0] feed_cr_diff_w;
  logic signed [8:0] feed_bdpcm_y_coeff_w;
  logic signed [8:0] feed_bdpcm_cb_coeff_w;
  logic signed [8:0] feed_bdpcm_cr_coeff_w;
  logic [3:0] feed_coeff_lane_w;
  logic feed_in_ts_subset_w;
  logic row_in_ts_subset_w [0:7];
  logic prior_runtime_ibc_seen_q;
  logic [2:0] request_cu_col_w;
  logic [2:0] request_cu_row_w;
  logic [5:0] request_cu_index_w;
  logic request_cu_left_ibc_w;
  logic request_cu_above_ibc_w;
  logic [PLANE_COUNT_BITS - 1:0] feed_left_frame_index;
  logic [PLANE_COUNT_BITS - 1:0] feed_left_boundary_frame_index;
  logic [PLANE_COUNT_BITS - 1:0] feed_next_left_frame_index;
  logic [PLANE_COUNT_BITS - 1:0] feed_next_left_boundary_frame_index;
  logic feed_read_enable_w;
  logic feed_read_next_w;
  logic [PLANE_COUNT_BITS - 1:0] feed_read_frame_index_w;
  logic [PLANE_COUNT_BITS - 1:0] feed_read_left_frame_index_w;
  logic [PLANE_COUNT_BITS - 1:0] feed_read_left_boundary_frame_index_w;
  logic [PLANE_ROW_BITS - 1:0] feed_read_row_w;
  logic [PLANE_ROW_BITS - 1:0] feed_read_left_row_w;
  logic [PLANE_ROW_BITS - 1:0] feed_read_left_boundary_row_w;
  logic [2:0] feed_read_lane_w;
  logic [2:0] feed_read_left_lane_w;
  logic [2:0] feed_read_left_boundary_lane_w;
  logic signed [8:0] ts_coeff_value_w;
  logic signed [8:0] bdpcm_coeff_value_w;
  logic signed [8:0] residual_coeff_value_w;
  logic [3:0] residual_start_packet_kind_w;
  logic residual_cbf_y_w;
  logic residual_cbf_cb_w;
  logic residual_cbf_cr_w;
  logic [PLANE_COUNT_BITS:0] cr_write_count_next_w;
  logic cr_cu_complete_w;
  logic cu_available_for_request_w;

  (* ram_style = "block" *) logic [63:0] frame_y [0:MAX_PLANE_ROWS - 1];
  (* ram_style = "block" *) logic [63:0] frame_cb [0:MAX_PLANE_ROWS - 1];
  (* ram_style = "block" *) logic [63:0] frame_cr [0:MAX_PLANE_ROWS - 1];

  assign coded_cu_count_x = (ctu_coded_width + 16'd7) >> 3;
  assign coded_cu_count_y = (ctu_coded_height + 16'd7) >> 3;
  always @* begin
    case (coded_cu_count_y)
      4'd0: root_leaf_count_value = 8'd0;
      4'd1: root_leaf_count_value = {4'd0, coded_cu_count_x};
      4'd2: root_leaf_count_value = {3'd0, coded_cu_count_x, 1'b0};
      4'd3: root_leaf_count_value = {3'd0, coded_cu_count_x, 1'b0} +
                                     {4'd0, coded_cu_count_x};
      4'd4: root_leaf_count_value = {2'd0, coded_cu_count_x, 2'b00};
      4'd5: root_leaf_count_value = {2'd0, coded_cu_count_x, 2'b00} +
                                     {4'd0, coded_cu_count_x};
      4'd6: root_leaf_count_value = {2'd0, coded_cu_count_x, 2'b00} +
                                     {3'd0, coded_cu_count_x, 1'b0};
      4'd7: root_leaf_count_value = {1'd0, coded_cu_count_x, 3'b000} -
                                     {4'd0, coded_cu_count_x};
      default: root_leaf_count_value = {1'd0, coded_cu_count_x, 3'b000};
    endcase
  end
  assign symbol_count = enable ? root_leaf_count_value : 8'd0;

  assign input_valid = s_axis_valid && s_axis_ready && (s_axis_count != 4'd0);
  assign cr_write_count_next_w =
    {1'b0, cr_write_count_q} +
    {{(PLANE_COUNT_BITS - 3){1'b0}}, s_axis_count};
  assign cr_cu_complete_w =
    input_valid && (s_axis_plane == PLANE_CR) &&
    (cr_write_count_next_w[5:0] == 6'd0);
  assign cu_available_for_request_w =
    drain_cu_index_q < available_cu_count_q;
  assign s_axis_ready = enable;
  assign y_write_row_w = y_write_count_q[PLANE_COUNT_BITS - 1:3];
  assign cb_write_row_w = cb_write_count_q[PLANE_COUNT_BITS - 1:3];
  assign cr_write_row_w = cr_write_count_q[PLANE_COUNT_BITS - 1:3];
  assign y_write_lane_w = y_write_count_q[2:0];
  assign cb_write_lane_w = cb_write_count_q[2:0];
  assign cr_write_lane_w = cr_write_count_q[2:0];

  always @* begin
    for (int i = 0; i < 8; i = i + 1) begin
      if (SAMPLE_BITS <= 8) begin
        input_lane_sample_w[i] =
          {{(8 - SAMPLE_BITS){1'b0}},
           s_axis_samples[i * SAMPLE_BITS +: SAMPLE_BITS]};
      end else begin
        input_lane_sample_w[i] =
          s_axis_samples[(i * SAMPLE_BITS) + (SAMPLE_BITS - 8) +: 8];
      end
    end
  end

  assign cu_request_ready =
    enable &&
    ((state_q == ST_WAIT_CU) ||
     ((state_q == ST_INPUT) && cu_available_for_request_w));
  assign drain_cu_selected = 1'b1;
  assign drain_cu_is_last_selected = drain_cu_is_last_selected_q;

  always @* begin
    drain_origin_x = drain_origin_x_q;
    drain_origin_y = drain_origin_y_q;
  end

  assign feed_x = {13'd0, feed_sample_q[2:0]};
  assign feed_y = {13'd0, feed_sample_q[5:3]};
  assign feed_abs_x = drain_origin_x + feed_x;
  assign feed_abs_y = drain_origin_y + feed_y;
  assign feed_next_sample_w = feed_sample_q + 8'd8;
  assign feed_next_y = {13'd0, feed_next_sample_w[5:3]};
  assign visible_cu_cols_w = coded_cu_count_x;
  assign visible_cu_rows_w = coded_cu_count_y;
  assign drain_cu_col_w = drain_origin_x_q[5:3];
  assign drain_cu_row_w = drain_origin_y_q[5:3];
  assign drain_cu_order_index_ext_w =
    {{(PLANE_COUNT_BITS - 6){1'b0}}, drain_cu_order_index_w};
  assign feed_left_order_index_ext_w =
    {{(PLANE_COUNT_BITS - 6){1'b0}}, feed_left_order_index_w};
  assign feed_sample_ext_w = {{(PLANE_COUNT_BITS - 8){1'b0}}, feed_sample_q};
  assign feed_next_sample_ext_w =
    {{(PLANE_COUNT_BITS - 8){1'b0}}, feed_next_sample_w};
  // H.266 7.3.11.4 coding_tree() leaf traversal requests the CU payload by
  // origin. The input stream is the compact fixed-8x8 TU order used by the
  // top-level interface, so address the stored block by origin rather than by
  // request ordinal.
  assign feed_frame_index =
    ((drain_cu_order_valid_w ? drain_cu_order_index_ext_w : '0) *
     MAX_CU_SAMPLES_L) + feed_sample_ext_w;
  assign feed_next_frame_index =
    ((drain_cu_order_valid_w ? drain_cu_order_index_ext_w : '0) *
     MAX_CU_SAMPLES_L) + feed_next_sample_ext_w;
  assign feed_left_cu_col_w = drain_cu_col_w - 3'd1;
  // H.266 8.6.2.2 uses spatial A1 as the left IBC neighbour. The TU input
  // stream is coding-tree ordered, so the left CU is not always the preceding
  // entry in memory; map (x - 8, y) through the same order table before
  // fetching predictor samples.
  assign feed_left_frame_index =
    (drain_cu_order_valid_w && (drain_cu_col_w != 3'd0) && feed_left_order_valid_w) ?
    ((feed_left_order_index_ext_w * MAX_CU_SAMPLES_L) + feed_sample_ext_w) : '0;
  assign feed_left_boundary_frame_index =
    (drain_cu_order_valid_w && (drain_cu_col_w != 3'd0) && feed_left_order_valid_w) ?
    ((feed_left_order_index_ext_w * MAX_CU_SAMPLES_L) +
     {{(PLANE_COUNT_BITS - 6){1'b0}}, feed_y[2:0], 3'b111}) : '0;
  assign feed_next_left_frame_index =
    (drain_cu_order_valid_w && (drain_cu_col_w != 3'd0) && feed_left_order_valid_w) ?
    ((feed_left_order_index_ext_w * MAX_CU_SAMPLES_L) + feed_next_sample_ext_w) : '0;
  assign feed_next_left_boundary_frame_index =
    (drain_cu_order_valid_w && (drain_cu_col_w != 3'd0) && feed_left_order_valid_w) ?
    ((feed_left_order_index_ext_w * MAX_CU_SAMPLES_L) +
     {{(PLANE_COUNT_BITS - 6){1'b0}}, feed_next_y[2:0], 3'b111}) : '0;
  assign feed_read_next_w =
    (state_q == ST_FEED_CU) && cu_s_axis_ready && feed_sample_valid_q &&
    !feed_sample_last_q;
  assign feed_read_enable_w =
    (state_q == ST_FEED_READ) || feed_read_next_w;
  assign feed_read_frame_index_w =
    feed_read_next_w ? feed_next_frame_index : feed_frame_index;
  assign feed_read_left_frame_index_w =
    feed_read_next_w ? feed_next_left_frame_index : feed_left_frame_index;
  assign feed_read_left_boundary_frame_index_w =
    feed_read_next_w ? feed_next_left_boundary_frame_index : feed_left_boundary_frame_index;
  assign feed_read_row_w = feed_read_frame_index_w[PLANE_COUNT_BITS - 1:3];
  assign feed_read_left_row_w = feed_read_left_frame_index_w[PLANE_COUNT_BITS - 1:3];
  assign feed_read_left_boundary_row_w =
    feed_read_left_boundary_frame_index_w[PLANE_COUNT_BITS - 1:3];
  assign feed_read_lane_w = feed_read_frame_index_w[2:0];
  assign feed_read_left_lane_w = feed_read_left_frame_index_w[2:0];
  assign feed_read_left_boundary_lane_w = feed_read_left_boundary_frame_index_w[2:0];
  assign feed_y_sample = feed_y_sample_q;
  assign feed_cb_sample = feed_cb_sample_q;
  assign feed_cr_sample = feed_cr_sample_q;
  assign cu_s_axis_valid = (state_q == ST_FEED_CU) && feed_sample_valid_q;
  assign cu_s_axis_last = feed_sample_last_q;
  assign ts_residual_selected_w =
    ts_candidate_q && (ts_cbf_y_q || ts_cbf_cb_q || ts_cbf_cr_q) &&
    (ts_cbf_cb_q || ts_cbf_cr_q);
  assign bdpcm_residual_selected_w =
    bdpcm_candidate_q && (bdpcm_cbf_y_q || bdpcm_cbf_cb_q || bdpcm_cbf_cr_q);
  assign residual_selected_w = ts_residual_selected_w || bdpcm_residual_selected_w;
  assign ts_residual_drain_w =
    (state_q == ST_DRAIN_TS_START) || (state_q == ST_DRAIN_TS_COEFF);
  assign ts_coeff_last_w =
    (state_q == ST_DRAIN_TS_COEFF) &&
    (ts_coeff_component_q == 2'd2) && (ts_coeff_index_q == 4'd15);
  assign ts_coeff_packet_kind_w =
    (ts_coeff_component_q == 2'd0) ? TS_PKT_COEFF_Y :
    ((ts_coeff_component_q == 2'd1) ? TS_PKT_COEFF_CB : TS_PKT_COEFF_CR);
  always @* begin
    case (ts_coeff_component_q)
      2'd0: ts_coeff_value_w = ts_y_coeff_q[ts_coeff_index_q * 9 +: 9];
      2'd1: ts_coeff_value_w = ts_cb_coeff_q[ts_coeff_index_q * 9 +: 9];
      default: ts_coeff_value_w = ts_cr_coeff_q[ts_coeff_index_q * 9 +: 9];
    endcase
  end
  always @* begin
    case (ts_coeff_component_q)
      2'd0: bdpcm_coeff_value_w = bdpcm_y_coeff_q[ts_coeff_index_q * 9 +: 9];
      2'd1: bdpcm_coeff_value_w = bdpcm_cb_coeff_q[ts_coeff_index_q * 9 +: 9];
      default: bdpcm_coeff_value_w = bdpcm_cr_coeff_q[ts_coeff_index_q * 9 +: 9];
    endcase
  end
  assign residual_coeff_value_w = drain_bdpcm_q ? bdpcm_coeff_value_w : ts_coeff_value_w;
  assign residual_start_packet_kind_w = drain_bdpcm_q ? BDPCM_PKT_CU_START : TS_PKT_CU_START;
  assign residual_cbf_y_w = drain_bdpcm_q ? bdpcm_cbf_y_q : ts_cbf_y_q;
  assign residual_cbf_cb_w = drain_bdpcm_q ? bdpcm_cbf_cb_q : ts_cbf_cb_q;
  assign residual_cbf_cr_w = drain_bdpcm_q ? bdpcm_cbf_cr_q : ts_cbf_cr_q;
  assign cu_symbolizer_clear_w = clear || !enable || ts_residual_drain_w ||
                                 ((state_q == ST_SELECT_CU) && residual_selected_w);
  assign cu_m_axis_ready = ts_residual_drain_w ? 1'b0 : m_axis_ready;
  assign m_axis_valid = ts_residual_drain_w ? 1'b1 : cu_m_axis_valid;
  assign m_axis_data =
    (state_q == ST_DRAIN_TS_START) ?
      {residual_start_packet_kind_w, 25'd0, residual_cbf_cr_w, residual_cbf_cb_w, residual_cbf_y_w} :
    (state_q == ST_DRAIN_TS_COEFF) ?
      {ts_coeff_packet_kind_w, 15'd0, ts_coeff_index_q, residual_coeff_value_w} :
      cu_m_axis_data;
  assign m_axis_last = ts_residual_drain_w ?
    (ts_coeff_last_w && drain_cu_is_last_selected) :
    (cu_m_axis_last && drain_cu_is_last_selected);
  assign m_axis_cu_last = ts_residual_drain_w ? ts_coeff_last_w : cu_m_axis_last;
  assign m_axis_cu_ibc_mode = ts_residual_drain_w && !drain_bdpcm_q;
  assign feed_y_diff_w = $signed({1'b0, feed_y_sample_q}) -
                         $signed({1'b0, feed_left_y_sample_q});
  assign feed_cb_diff_w = $signed({1'b0, feed_cb_sample_q}) -
                          $signed({1'b0, feed_left_cb_sample_q});
  assign feed_cr_diff_w = $signed({1'b0, feed_cr_sample_q}) -
                          $signed({1'b0, feed_left_cr_sample_q});
  assign feed_bdpcm_y_coeff_w = (feed_x == 16'd0) ?
    ($signed({1'b0, feed_y_sample_q}) - $signed({1'b0, feed_left_boundary_y_sample_q})) :
    ($signed({1'b0, feed_y_sample_q}) - $signed({1'b0, bdpcm_prev_y_sample_q}));
  assign feed_bdpcm_cb_coeff_w = (feed_x == 16'd0) ?
    ($signed({1'b0, feed_cb_sample_q}) - $signed({1'b0, feed_left_boundary_cb_sample_q})) :
    ($signed({1'b0, feed_cb_sample_q}) - $signed({1'b0, bdpcm_prev_cb_sample_q}));
  assign feed_bdpcm_cr_coeff_w = (feed_x == 16'd0) ?
    ($signed({1'b0, feed_cr_sample_q}) - $signed({1'b0, feed_left_boundary_cr_sample_q})) :
    ($signed({1'b0, feed_cr_sample_q}) - $signed({1'b0, bdpcm_prev_cr_sample_q}));
  assign feed_in_ts_subset_w = (feed_x < 16'd4) && (feed_y < 16'd4);
  assign feed_coeff_lane_w = {feed_y[1:0], feed_x[1:0]};
  always @* begin
    row_ts_cbf_y_w = 1'b0;
    row_ts_cbf_cb_w = 1'b0;
    row_ts_cbf_cr_w = 1'b0;
    row_bdpcm_cbf_y_w = 1'b0;
    row_bdpcm_cbf_cb_w = 1'b0;
    row_bdpcm_cbf_cr_w = 1'b0;
    row_ts_outside_nonzero_w = 1'b0;
    row_bdpcm_outside_nonzero_w = 1'b0;
    for (int lane = 0; lane < 8; lane = lane + 1) begin
      row_y_sample_w[lane] = feed_y_row_q[lane * 8 +: 8];
      row_cb_sample_w[lane] = feed_cb_row_q[lane * 8 +: 8];
      row_cr_sample_w[lane] = feed_cr_row_q[lane * 8 +: 8];
      row_left_y_sample_w[lane] = feed_left_y_row_q[lane * 8 +: 8];
      row_left_cb_sample_w[lane] = feed_left_cb_row_q[lane * 8 +: 8];
      row_left_cr_sample_w[lane] = feed_left_cr_row_q[lane * 8 +: 8];
      row_ts_y_diff_w[lane] =
        $signed({1'b0, row_y_sample_w[lane]}) -
        $signed({1'b0, row_left_y_sample_w[lane]});
      row_ts_cb_diff_w[lane] =
        $signed({1'b0, row_cb_sample_w[lane]}) -
        $signed({1'b0, row_left_cb_sample_w[lane]});
      row_ts_cr_diff_w[lane] =
        $signed({1'b0, row_cr_sample_w[lane]}) -
        $signed({1'b0, row_left_cr_sample_w[lane]});
      if (lane == 0) begin
        row_bdpcm_y_diff_w[lane] =
          $signed({1'b0, row_y_sample_w[lane]}) -
          $signed({1'b0, feed_left_y_row_q[7 * 8 +: 8]});
        row_bdpcm_cb_diff_w[lane] =
          $signed({1'b0, row_cb_sample_w[lane]}) -
          $signed({1'b0, feed_left_cb_row_q[7 * 8 +: 8]});
        row_bdpcm_cr_diff_w[lane] =
          $signed({1'b0, row_cr_sample_w[lane]}) -
          $signed({1'b0, feed_left_cr_row_q[7 * 8 +: 8]});
      end else begin
        row_bdpcm_y_diff_w[lane] =
          $signed({1'b0, row_y_sample_w[lane]}) -
          $signed({1'b0, row_y_sample_w[lane - 1]});
        row_bdpcm_cb_diff_w[lane] =
          $signed({1'b0, row_cb_sample_w[lane]}) -
          $signed({1'b0, row_cb_sample_w[lane - 1]});
        row_bdpcm_cr_diff_w[lane] =
          $signed({1'b0, row_cr_sample_w[lane]}) -
          $signed({1'b0, row_cr_sample_w[lane - 1]});
      end
      row_in_ts_subset_w[lane] = (feed_y < 16'd4) && (lane[2:0] < 3'd4);
      row_coeff_lane_w[lane] = {feed_y[1:0], lane[1:0]};
      if (row_in_ts_subset_w[lane]) begin
        row_ts_cbf_y_w = row_ts_cbf_y_w || (row_ts_y_diff_w[lane] != 9'sd0);
        row_ts_cbf_cb_w = row_ts_cbf_cb_w || (row_ts_cb_diff_w[lane] != 9'sd0);
        row_ts_cbf_cr_w = row_ts_cbf_cr_w || (row_ts_cr_diff_w[lane] != 9'sd0);
        row_bdpcm_cbf_y_w = row_bdpcm_cbf_y_w || (row_bdpcm_y_diff_w[lane] != 9'sd0);
        row_bdpcm_cbf_cb_w = row_bdpcm_cbf_cb_w || (row_bdpcm_cb_diff_w[lane] != 9'sd0);
        row_bdpcm_cbf_cr_w = row_bdpcm_cbf_cr_w || (row_bdpcm_cr_diff_w[lane] != 9'sd0);
      end
      if (!row_in_ts_subset_w[lane] &&
          ((row_ts_y_diff_w[lane] != 9'sd0) ||
           (row_ts_cb_diff_w[lane] != 9'sd0) ||
           (row_ts_cr_diff_w[lane] != 9'sd0))) begin
        row_ts_outside_nonzero_w = 1'b1;
      end
      if (!row_in_ts_subset_w[lane] &&
          ((row_bdpcm_y_diff_w[lane] != 9'sd0) ||
           (row_bdpcm_cb_diff_w[lane] != 9'sd0) ||
           (row_bdpcm_cr_diff_w[lane] != 9'sd0))) begin
        row_bdpcm_outside_nonzero_w = 1'b1;
      end
    end
  end
  assign request_cu_col_w = cu_request_origin_x[5:3];
  assign request_cu_row_w = cu_request_origin_y[5:3];
  assign request_cu_index_w = {request_cu_row_w, request_cu_col_w};
  assign request_cu_left_ibc_w =
    (request_cu_col_w != 3'd0) && cu_ibc_mask[request_cu_index_w - 6'd1];
  assign request_cu_above_ibc_w =
    (request_cu_row_w != 3'd0) && cu_ibc_mask[request_cu_index_w - 6'd8];

  ff_vvc_tu_order_8x8 palette_input_order (
    .visible_cols(visible_cu_cols_w),
    .visible_rows(visible_cu_rows_w),
    .sample_col(drain_cu_col_w),
    .sample_row(drain_cu_row_w),
    .target_index(6'd0),
    .sample_valid(drain_cu_order_valid_w),
    .sample_index(drain_cu_order_index_w),
    .target_valid(),
    .target_col(),
    .target_row()
  );

  ff_vvc_tu_order_8x8 palette_left_order (
    .visible_cols(visible_cu_cols_w),
    .visible_rows(visible_cu_rows_w),
    .sample_col(feed_left_cu_col_w),
    .sample_row(drain_cu_row_w),
    .target_index(6'd0),
    .sample_valid(feed_left_order_valid_w),
    .sample_index(feed_left_order_index_w),
    .target_valid(),
    .target_col(),
    .target_row()
  );

  ff_vvc_palette_cu_symbolizer #(
    .CU_SIZE(PALETTE_CU_SIZE)
  ) cu_symbolizer (
    .clk(clk),
    .rst_n(rst_n),
    .clear(cu_symbolizer_clear_w),
    .enable(enable),
    .cu_selected(drain_cu_selected),
    .s_axis_valid(cu_s_axis_valid),
    .s_axis_ready(cu_s_axis_ready),
    .s_axis_y(feed_y_row_q),
    .s_axis_cb(feed_cb_row_q),
    .s_axis_cr(feed_cr_row_q),
    .s_axis_count(4'd8),
    .s_axis_last(cu_s_axis_last),
    .m_axis_valid(cu_m_axis_valid),
    .m_axis_ready(cu_m_axis_ready),
    .m_axis_data(cu_m_axis_data),
    .m_axis_last(cu_m_axis_last)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_INPUT;
      y_write_count_q <= '0;
      cb_write_count_q <= '0;
      cr_write_count_q <= '0;
      drain_cu_index_q <= 8'd0;
      available_cu_count_q <= 8'd0;
      feed_sample_q <= 8'd0;
      drain_origin_x_q <= 16'd0;
      drain_origin_y_q <= 16'd0;
      drain_cu_is_last_selected_q <= 1'b0;
      feed_sample_last_q <= 1'b0;
      feed_sample_valid_q <= 1'b0;
      feed_y_row_q <= 64'd0;
      feed_cb_row_q <= 64'd0;
      feed_cr_row_q <= 64'd0;
      feed_left_y_row_q <= 64'd0;
      feed_left_cb_row_q <= 64'd0;
      feed_left_cr_row_q <= 64'd0;
      ts_candidate_q <= 1'b0;
      ts_cbf_y_q <= 1'b0;
      ts_cbf_cb_q <= 1'b0;
      ts_cbf_cr_q <= 1'b0;
      ts_y_coeff_q <= '0;
      ts_cb_coeff_q <= '0;
      ts_cr_coeff_q <= '0;
      bdpcm_candidate_q <= 1'b0;
      bdpcm_cbf_y_q <= 1'b0;
      bdpcm_cbf_cb_q <= 1'b0;
      bdpcm_cbf_cr_q <= 1'b0;
      bdpcm_y_coeff_q <= '0;
      bdpcm_cb_coeff_q <= '0;
      bdpcm_cr_coeff_q <= '0;
      bdpcm_prev_y_sample_q <= 8'd0;
      bdpcm_prev_cb_sample_q <= 8'd0;
      bdpcm_prev_cr_sample_q <= 8'd0;
      drain_bdpcm_q <= 1'b0;
      ts_coeff_index_q <= 4'd0;
      ts_coeff_component_q <= 2'd0;
      prior_runtime_ibc_seen_q <= 1'b0;
    end else if (clear || !enable) begin
      state_q <= ST_INPUT;
      y_write_count_q <= '0;
      cb_write_count_q <= '0;
      cr_write_count_q <= '0;
      drain_cu_index_q <= 8'd0;
      available_cu_count_q <= 8'd0;
      feed_sample_q <= 8'd0;
      drain_origin_x_q <= 16'd0;
      drain_origin_y_q <= 16'd0;
      drain_cu_is_last_selected_q <= 1'b0;
      feed_sample_last_q <= 1'b0;
      feed_sample_valid_q <= 1'b0;
      feed_y_row_q <= 64'd0;
      feed_cb_row_q <= 64'd0;
      feed_cr_row_q <= 64'd0;
      feed_left_y_row_q <= 64'd0;
      feed_left_cb_row_q <= 64'd0;
      feed_left_cr_row_q <= 64'd0;
      ts_candidate_q <= 1'b0;
      ts_cbf_y_q <= 1'b0;
      ts_cbf_cb_q <= 1'b0;
      ts_cbf_cr_q <= 1'b0;
      ts_y_coeff_q <= '0;
      ts_cb_coeff_q <= '0;
      ts_cr_coeff_q <= '0;
      bdpcm_candidate_q <= 1'b0;
      bdpcm_cbf_y_q <= 1'b0;
      bdpcm_cbf_cb_q <= 1'b0;
      bdpcm_cbf_cr_q <= 1'b0;
      bdpcm_y_coeff_q <= '0;
      bdpcm_cb_coeff_q <= '0;
      bdpcm_cr_coeff_q <= '0;
      bdpcm_prev_y_sample_q <= 8'd0;
      bdpcm_prev_cb_sample_q <= 8'd0;
      bdpcm_prev_cr_sample_q <= 8'd0;
      drain_bdpcm_q <= 1'b0;
      ts_coeff_index_q <= 4'd0;
      ts_coeff_component_q <= 2'd0;
      prior_runtime_ibc_seen_q <= 1'b0;
    end else begin
      if (input_valid) begin
        case (s_axis_plane)
          PLANE_Y: begin
            y_write_count_q <= y_write_count_q +
              {{(PLANE_COUNT_BITS - 4){1'b0}}, s_axis_count};
          end
          PLANE_CB: begin
            cb_write_count_q <= cb_write_count_q +
              {{(PLANE_COUNT_BITS - 4){1'b0}}, s_axis_count};
          end
          default: begin
            cr_write_count_q <= cr_write_count_q +
              {{(PLANE_COUNT_BITS - 4){1'b0}}, s_axis_count};
          end
        endcase
        if (cr_cu_complete_w) begin
          available_cu_count_q <= available_cu_count_q + 8'd1;
        end
      end

      case (state_q)
          ST_INPUT,
          ST_WAIT_CU: begin
            if (cu_request_valid && cu_request_ready) begin
              drain_origin_x_q <= cu_request_origin_x;
              drain_origin_y_q <= cu_request_origin_y;
              drain_cu_is_last_selected_q <= cu_request_last;
              state_q <= ST_FEED_READ;
              feed_sample_q <= 8'd0;
              feed_sample_valid_q <= 1'b0;
              ts_candidate_q <=
                (cu_request_origin_x >= 16'd8) &&
                ((cu_request_origin_x + 16'd8) <= ctu_visible_width) &&
                ((cu_request_origin_y + 16'd8) <= ctu_visible_height) &&
                // H.266 8.6.2.2 builds the IBC BVP list from A1/B1/HMVP/zero.
                // This first TS-residual subset hardcodes MVD -8,0, so allow
                // it only while the local BVP history is still zero. Exact-hash
                // IBC CUs are emitted by the top partition mux, so the request
                // carries whether any prior coded IBC CU has populated HMVP.
                !request_cu_left_ibc_w && !request_cu_above_ibc_w &&
                !cu_request_prior_ibc_seen &&
                !prior_runtime_ibc_seen_q;
              bdpcm_candidate_q <=
                (cu_request_origin_x >= 16'd8) &&
                ((cu_request_origin_x + 16'd8) <= ctu_visible_width) &&
                ((cu_request_origin_y + 16'd8) <= ctu_visible_height);
              ts_cbf_y_q <= 1'b0;
              ts_cbf_cb_q <= 1'b0;
              ts_cbf_cr_q <= 1'b0;
              ts_y_coeff_q <= '0;
              ts_cb_coeff_q <= '0;
              ts_cr_coeff_q <= '0;
              bdpcm_cbf_y_q <= 1'b0;
              bdpcm_cbf_cb_q <= 1'b0;
              bdpcm_cbf_cr_q <= 1'b0;
              bdpcm_y_coeff_q <= '0;
              bdpcm_cb_coeff_q <= '0;
              bdpcm_cr_coeff_q <= '0;
              bdpcm_prev_y_sample_q <= 8'd0;
              bdpcm_prev_cb_sample_q <= 8'd0;
              bdpcm_prev_cr_sample_q <= 8'd0;
              drain_bdpcm_q <= 1'b0;
              ts_coeff_index_q <= 4'd0;
              ts_coeff_component_q <= 2'd0;
            end
          end

          ST_FEED_READ: begin
            feed_sample_last_q <= feed_sample_q >= (MAX_CU_SAMPLES - 8);
            feed_sample_valid_q <= 1'b1;
            state_q <= ST_FEED_CU;
          end

          ST_FEED_CU: begin
            if (cu_s_axis_ready && feed_sample_valid_q) begin
              if (ts_candidate_q) begin
                for (int lane = 0; lane < 8; lane = lane + 1) begin
                  if (row_in_ts_subset_w[lane]) begin
                    ts_y_coeff_q[row_coeff_lane_w[lane] * 9 +: 9] <= row_ts_y_diff_w[lane];
                    ts_cb_coeff_q[row_coeff_lane_w[lane] * 9 +: 9] <= row_ts_cb_diff_w[lane];
                    ts_cr_coeff_q[row_coeff_lane_w[lane] * 9 +: 9] <= row_ts_cr_diff_w[lane];
                  end
                end
                ts_cbf_y_q <= ts_cbf_y_q || row_ts_cbf_y_w;
                ts_cbf_cb_q <= ts_cbf_cb_q || row_ts_cbf_cb_w;
                ts_cbf_cr_q <= ts_cbf_cr_q || row_ts_cbf_cr_w;
                if (row_ts_outside_nonzero_w) begin
                  ts_candidate_q <= 1'b0;
                end
              end
              if (bdpcm_candidate_q) begin
                for (int lane = 0; lane < 8; lane = lane + 1) begin
                  if (row_in_ts_subset_w[lane]) begin
                    bdpcm_y_coeff_q[row_coeff_lane_w[lane] * 9 +: 9] <= row_bdpcm_y_diff_w[lane];
                    bdpcm_cb_coeff_q[row_coeff_lane_w[lane] * 9 +: 9] <= row_bdpcm_cb_diff_w[lane];
                    bdpcm_cr_coeff_q[row_coeff_lane_w[lane] * 9 +: 9] <= row_bdpcm_cr_diff_w[lane];
                  end
                end
                bdpcm_cbf_y_q <= bdpcm_cbf_y_q || row_bdpcm_cbf_y_w;
                bdpcm_cbf_cb_q <= bdpcm_cbf_cb_q || row_bdpcm_cbf_cb_w;
                bdpcm_cbf_cr_q <= bdpcm_cbf_cr_q || row_bdpcm_cbf_cr_w;
                if (row_bdpcm_outside_nonzero_w) begin
                  bdpcm_candidate_q <= 1'b0;
                end
              end
              if (cu_s_axis_last) begin
                state_q <= ST_SELECT_CU;
                feed_sample_q <= 8'd0;
                feed_sample_valid_q <= 1'b0;
              end else begin
                feed_sample_q <= feed_next_sample_w;
                feed_sample_last_q <= feed_next_sample_w >= (MAX_CU_SAMPLES - 8);
                feed_sample_valid_q <= 1'b1;
                state_q <= ST_FEED_CU;
              end
            end
          end

          ST_SELECT_CU: begin
            state_q <= residual_selected_w ? ST_DRAIN_TS_START : ST_DRAIN_CU;
            drain_bdpcm_q <= (!ts_residual_selected_w) && bdpcm_residual_selected_w;
            ts_coeff_index_q <= 4'd0;
            ts_coeff_component_q <= 2'd0;
          end

          ST_DRAIN_CU: begin
            if (cu_m_axis_valid && cu_m_axis_ready && cu_m_axis_last) begin
              if (drain_cu_is_last_selected) begin
                state_q <= ST_INPUT;
                drain_cu_index_q <= 8'd0;
                available_cu_count_q <= 8'd0;
              end else begin
                state_q <= ST_INPUT;
                drain_cu_index_q <= drain_cu_index_q + 8'd1;
              end
            end
          end

          ST_DRAIN_TS_START: begin
            if (m_axis_ready) begin
              state_q <= ST_DRAIN_TS_COEFF;
              ts_coeff_index_q <= 4'd0;
              ts_coeff_component_q <= 2'd0;
            end
          end

          ST_DRAIN_TS_COEFF: begin
            if (m_axis_ready) begin
              if (ts_coeff_last_w) begin
                if (!drain_bdpcm_q) begin
                  prior_runtime_ibc_seen_q <= 1'b1;
                end
                drain_bdpcm_q <= 1'b0;
                if (drain_cu_is_last_selected) begin
                  state_q <= ST_INPUT;
                  drain_cu_index_q <= 8'd0;
                  available_cu_count_q <= 8'd0;
                end else begin
                  state_q <= ST_INPUT;
                  drain_cu_index_q <= drain_cu_index_q + 8'd1;
                end
              end else if (ts_coeff_index_q == 4'd15) begin
                ts_coeff_index_q <= 4'd0;
                ts_coeff_component_q <= ts_coeff_component_q + 2'd1;
              end else begin
                ts_coeff_index_q <= ts_coeff_index_q + 4'd1;
              end
            end
          end

        default: begin
          state_q <= ST_INPUT;
        end
      endcase
    end
  end

  always_ff @(posedge clk) begin
    if (input_valid) begin
      case (s_axis_plane)
        PLANE_Y: begin
          for (input_lane_i = 4'd0; input_lane_i < 4'd8; input_lane_i = input_lane_i + 4'd1) begin
            if (input_lane_i < s_axis_count) begin
              frame_y[y_write_row_w][(y_write_lane_w + input_lane_i[2:0]) * 8 +: 8] <=
                input_lane_sample_w[input_lane_i];
            end
          end
        end
        PLANE_CB: begin
          for (input_lane_i = 4'd0; input_lane_i < 4'd8; input_lane_i = input_lane_i + 4'd1) begin
            if (input_lane_i < s_axis_count) begin
              frame_cb[cb_write_row_w][(cb_write_lane_w + input_lane_i[2:0]) * 8 +: 8] <=
                input_lane_sample_w[input_lane_i];
            end
          end
        end
        default: begin
          for (input_lane_i = 4'd0; input_lane_i < 4'd8; input_lane_i = input_lane_i + 4'd1) begin
            if (input_lane_i < s_axis_count) begin
              frame_cr[cr_write_row_w][(cr_write_lane_w + input_lane_i[2:0]) * 8 +: 8] <=
                input_lane_sample_w[input_lane_i];
            end
          end
        end
      endcase
    end

    if (feed_read_enable_w) begin
      feed_y_row_q <= frame_y[feed_read_row_w];
      feed_cb_row_q <= frame_cb[feed_read_row_w];
      feed_cr_row_q <= frame_cr[feed_read_row_w];
      feed_left_y_row_q <= frame_y[feed_read_left_row_w];
      feed_left_cb_row_q <= frame_cb[feed_read_left_row_w];
      feed_left_cr_row_q <= frame_cr[feed_read_left_row_w];
      feed_y_sample_q <= frame_y[feed_read_row_w][feed_read_lane_w * 8 +: 8];
      feed_cb_sample_q <= frame_cb[feed_read_row_w][feed_read_lane_w * 8 +: 8];
      feed_cr_sample_q <= frame_cr[feed_read_row_w][feed_read_lane_w * 8 +: 8];
      feed_left_y_sample_q <= frame_y[feed_read_left_row_w][feed_read_left_lane_w * 8 +: 8];
      feed_left_cb_sample_q <= frame_cb[feed_read_left_row_w][feed_read_left_lane_w * 8 +: 8];
      feed_left_cr_sample_q <= frame_cr[feed_read_left_row_w][feed_read_left_lane_w * 8 +: 8];
      feed_left_boundary_y_sample_q <=
        frame_y[feed_read_left_boundary_row_w][feed_read_left_boundary_lane_w * 8 +: 8];
      feed_left_boundary_cb_sample_q <=
        frame_cb[feed_read_left_boundary_row_w][feed_read_left_boundary_lane_w * 8 +: 8];
      feed_left_boundary_cr_sample_q <=
        frame_cr[feed_read_left_boundary_row_w][feed_read_left_boundary_lane_w * 8 +: 8];
    end
  end
endmodule
