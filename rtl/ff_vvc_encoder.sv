`timescale 1ns/1ps

module ff_vvc_encoder #(
  parameter int MAX_VISIBLE_WIDTH = 1024,
  parameter int MAX_VISIBLE_HEIGHT = 1024,
  parameter int CTU_SIZE = 64,
  parameter int SAMPLE_BITS = 8,
  parameter int SOURCE_SAMPLE_BITS = SAMPLE_BITS,
  parameter bit SUPPORT_PALETTE_444 = 1'b1,
  parameter bit SUPPORT_EXACT_HASH_IBC_444 = 1'b0
) (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       start,
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,
  // VVC chroma_format_idc values: 1=4:2:0, 2=4:2:2, 3=4:4:4.
  input  logic [1:0] chroma_format_idc,
  output logic       busy,

  input  logic       s_axis_valid,
  output logic       s_axis_ready,
  input  logic [SAMPLE_BITS - 1:0] s_axis_data,
  input  logic       s_axis_last,
  output logic       input_error,

  output logic       m_axis_valid,
  input  logic       m_axis_ready,
  output logic [7:0] m_axis_data,
  output logic       m_axis_last
);
  localparam int CODED_DIMENSION_GRANULARITY = 8;
  localparam int NAL_OVERHEAD_LEN = 6;
  localparam int MAX_CTU_STREAM_SAMPLES = CTU_SIZE * CTU_SIZE * 3;
  localparam int INPUT_COUNT_BITS = $clog2(MAX_CTU_STREAM_SAMPLES + 1);
  localparam int VVC_LUMA_TU_SIZE = 8;
  localparam int VVC_CHROMA_TU_SIZE = 4;
  localparam logic [15:0] CTU_SIZE_L = CTU_SIZE;
  localparam logic [15:0] VVC_LUMA_TU_SIZE_L = VVC_LUMA_TU_SIZE;
  localparam int VVC_RESIDUAL_LUMA_SAMPLES = VVC_LUMA_TU_SIZE * VVC_LUMA_TU_SIZE;
  localparam int VVC_CHROMA_TU_SAMPLES = VVC_CHROMA_TU_SIZE * VVC_CHROMA_TU_SIZE;
  localparam int VVC_LUMA_TU_SAMPLE_BITS = 8 * VVC_RESIDUAL_LUMA_SAMPLES;
  localparam int VVC_CHROMA_TU_SAMPLE_BITS = 8 * VVC_CHROMA_TU_SAMPLES;
  localparam int VVC_RESIDUAL_AC_BITS = 4;
  localparam int VVC_LUMA_AC_COEFFS = 15;
  localparam int VVC_CHROMA_AC_COEFFS = 3;
  localparam int VVC_LUMA_TU_COLS = CTU_SIZE / VVC_LUMA_TU_SIZE;
  localparam logic [5:0] VVC_LUMA_TU_COLS_L = VVC_LUMA_TU_COLS;
  localparam int VVC_LUMA_TUS_PER_CTU =
    (CTU_SIZE / VVC_LUMA_TU_SIZE) * (CTU_SIZE / VVC_LUMA_TU_SIZE);
  localparam int VVC_CHROMA_TUS_PER_CTU = VVC_LUMA_TUS_PER_CTU;
  localparam int VVC_CHROMA_CTU_WIDTH = CTU_SIZE / 2;
  localparam int VVC_CHROMA_TU_COLS = VVC_CHROMA_CTU_WIDTH / VVC_CHROMA_TU_SIZE;
  localparam logic [15:0] VVC_CHROMA_TU_SIZE_L = VVC_CHROMA_TU_SIZE;
  localparam int PALETTE_CU_SIZE = 8;
  localparam int MAX_CTU_PALETTE_SYMBOLS =
    ((CTU_SIZE + PALETTE_CU_SIZE - 1) / PALETTE_CU_SIZE) *
    ((CTU_SIZE + PALETTE_CU_SIZE - 1) / PALETTE_CU_SIZE);
  localparam logic [2:0] GENERATED_OUT_IDLE     = 3'd0;
  localparam logic [2:0] GENERATED_OUT_PREAMBLE = 3'd1;
  localparam logic [2:0] GENERATED_OUT_CABAC    = 3'd2;
  localparam logic [2:0] GENERATED_OUT_SLICE_START = 3'd3;
  localparam logic [2:0] GENERATED_OUT_PICTURE_HEADER = 3'd4;
  localparam logic [7:0] SYMBOL_PALETTE_LEAF = 8'hfe;
  localparam logic [7:0] IBC_PKT_CU = 8'h89;
  localparam logic [1:0] PALETTE_MUX_PARTITION = 2'd0;
  localparam logic [1:0] PALETTE_MUX_CU = 2'd1;
  localparam logic [4:0] VVC_NAL_UNIT_TYPE_IDR_W_RADL = 5'd8;
  localparam logic [4:0] VVC_NAL_UNIT_TYPE_CRA = 5'd9;

  logic [INPUT_COUNT_BITS - 1:0] input_count_q;
  logic [INPUT_COUNT_BITS - 1:0] input_len_q;
  logic       input_active_q;
  logic [7:0] quant_luma_rem_ctu_q [0:VVC_LUMA_TUS_PER_CTU - 1];
  logic       quant_luma_negative_ctu_q [0:VVC_LUMA_TUS_PER_CTU - 1];
  logic [(VVC_RESIDUAL_AC_BITS * VVC_LUMA_AC_COEFFS) - 1:0] quant_luma_ac_levels_ctu_q [0:VVC_LUMA_TUS_PER_CTU - 1];
  logic signed [8:0] quant_cb_dc_level_ctu_q [0:VVC_CHROMA_TUS_PER_CTU - 1];
  logic signed [8:0] quant_cr_dc_level_ctu_q [0:VVC_CHROMA_TUS_PER_CTU - 1];
  logic [(VVC_RESIDUAL_AC_BITS * VVC_CHROMA_AC_COEFFS) - 1:0] quant_cb_ac_levels_ctu_q [0:VVC_CHROMA_TUS_PER_CTU - 1];
  logic [(VVC_RESIDUAL_AC_BITS * VVC_CHROMA_AC_COEFFS) - 1:0] quant_cr_ac_levels_ctu_q [0:VVC_CHROMA_TUS_PER_CTU - 1];
  logic [15:0] coding_tree_coded_width;
  logic [15:0] coding_tree_coded_height;
  logic        cabac_enable;
  logic [7:0]  palette_symbol_count;
  logic [MAX_CTU_PALETTE_SYMBOLS - 1:0] ctu_cu_active_mask;
  logic [MAX_CTU_PALETTE_SYMBOLS - 1:0] ctu_cu_ibc_mask;
  logic [MAX_CTU_PALETTE_SYMBOLS - 1:0] ctu_cu_runtime_ibc_mask_q;
  logic [MAX_CTU_PALETTE_SYMBOLS - 1:0] ctu_cu_effective_ibc_mask_w;
  logic [MAX_CTU_PALETTE_SYMBOLS - 1:0] ctu_cu_palette_mask;
  logic [MAX_CTU_PALETTE_SYMBOLS - 1:0] ctu_cu_residual_mask;
  logic [(16 * MAX_CTU_PALETTE_SYMBOLS) - 1:0] ctu_cu_ibc_mvd_x;
  logic [(16 * MAX_CTU_PALETTE_SYMBOLS) - 1:0] ctu_cu_ibc_mvd_y;
  logic        ctu_screen_444_mode;
  logic        ibc_sample_valid;
  logic        ibc_cu_full_visible_w;
  logic        ibc_cu_last_sample_w;
  logic        exact_ibc_hash_enabled_w;
  logic        ibc_matcher_idle;
  logic        palette_sample_valid;
  logic [1:0]  palette_sample_plane;
  logic        palette_stream_valid;
  logic        palette_stream_ready;
  logic [31:0] palette_stream_data;
  logic        palette_stream_last;
  logic        palette_stream_cu_last;
  logic        palette_stream_cu_ibc_mode;
  logic        palette_leaf_marker_valid;
  logic        palette_request_valid;
  logic        palette_request_ready;
  logic [15:0] palette_request_origin_x;
  logic [15:0] palette_request_origin_y;
  logic        palette_request_last;
  logic [5:0]  palette_leaf_index_w;
  logic [2:0]  palette_leaf_col_w;
  logic [2:0]  palette_leaf_row_w;
  logic        palette_leaf_is_ibc_w;
  logic        palette_leaf_ibc_left_w;
  logic        palette_leaf_ibc_above_w;
  logic [2:0]  palette_leaf_ibc_ctx_w;
  logic signed [15:0] palette_leaf_ibc_mvd_x_w;
  logic signed [15:0] palette_leaf_ibc_mvd_y_w;
  logic [31:0] ibc_source_symbol_data_w;
  logic [31:0] palette_source_symbol_data_w;
  logic        ctu_symbol_valid;
  logic        ctu_symbol_ready;
  logic [7:0]  ctu_symbol_kind;
  logic [31:0] ctu_symbol_data;
  logic        ctu_symbol_last;
  logic        source_symbol_valid;
  logic        source_symbol_ready;
  logic [7:0]  source_symbol_kind;
  logic [31:0] source_symbol_data;
  logic        source_symbol_last;
  logic        cabac_input_valid_q;
  logic [7:0]  cabac_input_kind_q;
  logic [31:0] cabac_input_data_q;
  logic        cabac_input_last_q;
  logic [1:0]  palette_mux_state_q;
  logic [2:0]  palette_current_pred_ibc_ctx_q;
  logic [5:0]  palette_current_leaf_index_q;
  logic        cabac_symbol_ready;
  logic        cabac_stream_valid;
  logic        cabac_stream_ready;
  logic [7:0]  cabac_stream_data;
  logic        cabac_stream_last;
  logic [2:0]  cabac_stream_last_byte_bits;
  logic        rbsp_payload_valid;
  logic        rbsp_payload_ready;
  logic        rbsp_output_ready;
  logic        rbsp_ep_input_ready;
  logic        rbsp_palette_ep_input_ready;
  logic [7:0]  rbsp_payload_data;
  logic        rbsp_payload_last;
  logic        rbsp_protected_valid;
  logic        rbsp_protected_ready;
  logic [7:0]  rbsp_protected_data;
  logic        rbsp_protected_last;
  logic        slice_stream_ready;
  logic        slice_stream_valid;
  logic [7:0]  slice_stream_data;
  logic        slice_stream_last;
  logic        cabac_start_q;
  logic        pending_output_q;
  logic        resume_input_q;
  logic        frame_clear_q;
  logic        chroma_tu_quant_pending_q;
  logic        chroma_tu_quant_frame_last_q;
  logic [63:0] frame_index_q;
  logic [2:0]  generated_out_state_q;
  logic        generated_slice_cra_q;
  logic        generated_header_start_q;
  logic        generated_picture_header_start_q;
  logic        generated_header_ready_w;
  logic        generated_header_valid_w;
  logic [7:0]  generated_header_byte_w;
  logic        generated_header_last_w;
  logic        generated_header_done_w;
  logic        picture_header_ready_w;
  logic        picture_header_valid_w;
  logic [7:0]  picture_header_byte_w;
  logic        picture_header_last_w;
  logic        picture_header_done_w;
  logic [15:0] current_slice_q;
  logic [15:0] current_ctu_x_q;
  logic [15:0] current_ctu_y_q;
  logic [15:0] coded_width_w;
  logic [15:0] coded_height_w;
  logic [15:0] ctu_cols_w;
  logic [15:0] ctu_rows_w;
  logic [15:0] ctu_count_w;
  logic [15:0] current_ctu_origin_x_w;
  logic [15:0] current_ctu_origin_y_w;
  logic [15:0] current_ctu_remaining_width_w;
  logic [15:0] current_ctu_remaining_height_w;
  logic [15:0] ctu_visible_width_w;
  logic [15:0] ctu_visible_height_w;
  logic [5:0]  slice_address_bits_w;
  logic        multi_slice_picture_w;
  logic        current_slice_last_w;
  logic        ctu_has_palette_cu;
  logic [1:0]  chroma_subsample_x_w;
  logic [1:0]  chroma_subsample_y_w;
  logic [INPUT_COUNT_BITS - 1:0] frame_samples_w;
  logic [INPUT_COUNT_BITS - 1:0] luma_tu_stream_samples_w;
  logic [INPUT_COUNT_BITS - 1:0] chroma_tu_stream_samples_w;
  logic [INPUT_COUNT_BITS - 1:0] cb_tu_stream_base_w;
  logic [INPUT_COUNT_BITS - 1:0] cr_tu_stream_base_w;
  logic [INPUT_COUNT_BITS - 1:0] input_len_w;
  logic [INPUT_COUNT_BITS - 1:0] v_sample_index_w;
  logic        input_frame_last_w;
  logic [6:0]  input_stream_leaf_q;
  logic [1:0]  input_stream_component_q;
  logic [5:0]  input_stream_sample_q;
  logic [6:0]  input_stream_leaf_next_w;
  logic [1:0]  input_stream_component_next_w;
  logic [5:0]  input_stream_sample_next_w;
  logic [5:0]  input_chroma_stream_last_sample_w;
  logic        input_stream_component_last_w;
  logic [1:0]  palette_sample_plane_w;
  logic [3:0]  active_luma_tu_cols_w;
  logic [3:0]  active_luma_tu_rows_w;
  logic [6:0]  active_luma_tu_count_w;
  logic [6:0]  active_chroma_tu_count_w;
  logic [6:0]  input_luma_tu_ordinal_w;
  logic        input_luma_tu_valid_w;
  logic [15:0] input_luma_tu_origin_x_w;
  logic [15:0] input_luma_tu_origin_y_w;
  logic [15:0] input_luma_x_w;
  logic [15:0] input_luma_y_w;
  logic [15:0] input_luma_ctu_local_x_w;
  logic [15:0] input_luma_ctu_local_y_w;
  logic        residual_luma_sample_w;
  logic        input_luma_tu_sample_w;
  logic        input_luma_tu_last_sample_w;
  logic [5:0]  input_luma_tu_sample_index_w;
  logic [5:0]  residual_luma_sample_index_w;
  logic [15:0] input_luma_tu_index_full_w;
  logic [5:0]  input_luma_tu_index_w;
  logic [7:0]  input_sample_8bit_w;
  logic [15:0] input_chroma_width_w;
  logic [15:0] input_chroma_height_w;
  logic [15:0] input_chroma_x_w;
  logic [15:0] input_chroma_y_w;
  logic [15:0] input_chroma_ctu_local_x_w;
  logic [15:0] input_chroma_ctu_local_y_w;
  logic        input_chroma_tu_valid_w;
  logic        input_chroma_tu_sample_w;
  logic        input_chroma_tu_last_cr_sample_w;
  logic [5:0]  input_chroma_tu_index_w;
  logic [6:0]  input_chroma_tu_index_full_w;
  logic [15:0] input_chroma_tu_origin_x_w;
  logic [15:0] input_chroma_tu_origin_y_w;
  logic [15:0] input_chroma_tu_width_w;
  logic [15:0] input_chroma_tu_height_w;
  logic [15:0] input_chroma_tu_local_x_w;
  logic [15:0] input_chroma_tu_local_y_w;
  logic [5:0]  input_chroma_tu_sample_index_w;
  logic [VVC_LUMA_TU_SAMPLE_BITS - 1:0] luma_sample_tu_q;
  logic [(8 * VVC_LUMA_TU_SIZE) - 1:0] luma_top_ref_row_q [0:VVC_LUMA_TU_COLS - 1];
  logic [(8 * VVC_LUMA_TU_SIZE) - 1:0] luma_left_ref_col_q [0:VVC_LUMA_TU_COLS - 1];
  logic        luma_tu_quant_pending_q;
  logic [VVC_CHROMA_TU_SAMPLE_BITS - 1:0] cb_sample_tu_q;
  logic [VVC_CHROMA_TU_SAMPLE_BITS - 1:0] cr_sample_tu_q;
  logic [(8 * VVC_CHROMA_TU_SIZE) - 1:0] chroma_cb_top_ref_row_q [0:VVC_CHROMA_TU_COLS - 1];
  logic [(8 * VVC_CHROMA_TU_SIZE) - 1:0] chroma_cb_left_ref_col_q [0:VVC_CHROMA_TU_COLS - 1];
  logic [(8 * VVC_CHROMA_TU_SIZE) - 1:0] chroma_cr_top_ref_row_q [0:VVC_CHROMA_TU_COLS - 1];
  logic [(8 * VVC_CHROMA_TU_SIZE) - 1:0] chroma_cr_left_ref_col_q [0:VVC_CHROMA_TU_COLS - 1];
  logic [(8 * VVC_LUMA_TUS_PER_CTU) - 1:0] selected_quant_luma_rem_w;
  logic [VVC_LUMA_TUS_PER_CTU - 1:0] selected_quant_luma_negative_w;
  logic [(VVC_RESIDUAL_AC_BITS * VVC_LUMA_AC_COEFFS * VVC_LUMA_TUS_PER_CTU) - 1:0] selected_quant_luma_ac_levels_w;
  logic [(9 * VVC_CHROMA_TUS_PER_CTU) - 1:0] selected_quant_cb_dc_levels_w;
  logic [(9 * VVC_CHROMA_TUS_PER_CTU) - 1:0] selected_quant_cr_dc_levels_w;
  logic [(VVC_RESIDUAL_AC_BITS * VVC_CHROMA_AC_COEFFS * VVC_CHROMA_TUS_PER_CTU) - 1:0] selected_quant_cb_ac_levels_w;
  logic [(VVC_RESIDUAL_AC_BITS * VVC_CHROMA_AC_COEFFS * VVC_CHROMA_TUS_PER_CTU) - 1:0] selected_quant_cr_ac_levels_w;
  logic [2:0]  luma_log2_tb_width_w;
  logic [2:0]  luma_log2_tb_height_w;
  logic        frame_pipeline_clear_w;
  logic [5:0]  luma_quant_tu_q;
  logic [15:0] luma_quant_ctu_visible_width_w;
  logic [15:0] luma_quant_ctu_visible_height_w;
  logic [15:0] luma_quant_tu_origin_x_w;
  logic [15:0] luma_quant_tu_origin_y_w;
  logic        luma_quant_tu_visible_w;
  logic [2:0]  luma_quant_tu_col_w;
  logic [2:0]  luma_quant_tu_row_w;
  logic [VVC_LUMA_TU_SAMPLE_BITS - 1:0] luma_quant_sample_tu_w;

  logic        vvc_tool_transform_skip_enabled;
  logic        vvc_tool_mts_enabled;
  logic        vvc_tool_lfnst_enabled;
  logic        vvc_tool_joint_cbcr_enabled;
  logic        vvc_tool_mrl_enabled;
  logic        vvc_tool_cclm_enabled;
  logic        vvc_tool_dep_quant_enabled;
  logic        vvc_tool_sign_data_hiding_enabled;
  logic        vvc_tool_palette_enabled;
  logic        vvc_tool_ibc_enabled;
  logic        vvc_sps_ref_pic_resampling_enabled;
  logic        vvc_sps_entry_point_offsets_present;
  integer      luma_pack_tu_i;
  integer      chroma_pack_tu_i;
  integer      luma_quant_pack_i;
  integer      chroma_quant_x_i;
  integer      chroma_quant_y_i;
  integer      chroma_quant_pack_i;
  integer      luma_ref_i;
  logic [15:0] luma_quant_ref_x_tmp;
  logic [15:0] luma_quant_ref_y_tmp;
  logic [(8 * VVC_RESIDUAL_LUMA_SAMPLES) - 1:0] luma_quant_samples_w;
  logic [15:0] luma_quant_tu_remaining_width_w;
  logic [15:0] luma_quant_tu_remaining_height_w;
  logic [3:0]  luma_quant_visible_cols_w;
  logic [3:0]  luma_quant_visible_rows_w;
  logic [(8 * VVC_LUMA_TU_SIZE) - 1:0] luma_quant_top_ref_w;
  logic [(8 * VVC_LUMA_TU_SIZE) - 1:0] luma_quant_left_ref_w;
  logic [7:0] luma_quant_abs_level_w;
  logic luma_quant_negative_w;
  logic [(VVC_RESIDUAL_AC_BITS * VVC_LUMA_AC_COEFFS) - 1:0] luma_quant_ac_levels_w;
  logic [(8 * VVC_LUMA_TU_SIZE) - 1:0] luma_quant_bottom_ref_w;
  logic [(8 * VVC_LUMA_TU_SIZE) - 1:0] luma_quant_right_ref_w;
  logic luma_quant_start_q;
  logic luma_quant_done_w;
  logic luma_quant_busy_w;
  logic luma_quant_active_q;
  logic chroma_quant_start_q;
  logic chroma_quant_done_w;
  logic chroma_quant_busy_w;
  logic chroma_quant_cb_done_w;
  logic chroma_quant_cr_done_w;
  logic chroma_quant_cb_busy_w;
  logic chroma_quant_cr_busy_w;
  logic chroma_quant_active_q;
  logic [5:0]  chroma_quant_tu_q;
  logic [15:0] chroma_quant_ctu_visible_width_w;
  logic [15:0] chroma_quant_ctu_visible_height_w;
  logic [15:0] chroma_quant_visible_chroma_width_w;
  logic [15:0] chroma_quant_visible_chroma_height_w;
  logic        chroma_quant_tu_valid_w;
  logic [15:0] chroma_quant_tu_origin_x_w;
  logic [15:0] chroma_quant_tu_origin_y_w;
  logic [15:0] chroma_quant_tu_width_w;
  logic [15:0] chroma_quant_tu_height_w;
  logic [2:0]  chroma_quant_tu_col_w;
  logic [2:0]  chroma_quant_tu_row_w;
  logic [(8 * VVC_CHROMA_TU_SAMPLES) - 1:0] chroma_quant_cb_samples_w;
  logic [(8 * VVC_CHROMA_TU_SAMPLES) - 1:0] chroma_quant_cr_samples_w;
  logic [(8 * VVC_CHROMA_TU_SIZE) - 1:0] chroma_quant_cb_top_ref_w;
  logic [(8 * VVC_CHROMA_TU_SIZE) - 1:0] chroma_quant_cb_left_ref_w;
  logic [(8 * VVC_CHROMA_TU_SIZE) - 1:0] chroma_quant_cr_top_ref_w;
  logic [(8 * VVC_CHROMA_TU_SIZE) - 1:0] chroma_quant_cr_left_ref_w;
  logic signed [8:0] chroma_quant_cb_dc_level_w;
  logic signed [8:0] chroma_quant_cr_dc_level_w;
  logic [(VVC_RESIDUAL_AC_BITS * VVC_CHROMA_AC_COEFFS) - 1:0] chroma_quant_cb_ac_levels_w;
  logic [(VVC_RESIDUAL_AC_BITS * VVC_CHROMA_AC_COEFFS) - 1:0] chroma_quant_cr_ac_levels_w;
  logic [(8 * VVC_CHROMA_TU_SIZE) - 1:0] chroma_quant_cb_bottom_ref_w;
  logic [(8 * VVC_CHROMA_TU_SIZE) - 1:0] chroma_quant_cr_bottom_ref_w;
  logic [(8 * VVC_CHROMA_TU_SIZE) - 1:0] chroma_quant_cb_right_ref_w;
  logic [(8 * VVC_CHROMA_TU_SIZE) - 1:0] chroma_quant_cr_right_ref_w;
  logic [15:0] chroma_quant_ref_x_tmp;
  logic [15:0] chroma_quant_ref_y_tmp;
  logic [VVC_CHROMA_TU_SAMPLE_BITS - 1:0] chroma_quant_cb_sample_tu_w;
  logic [VVC_CHROMA_TU_SAMPLE_BITS - 1:0] chroma_quant_cr_sample_tu_w;

  // Current subset policy: 4:4:4 input selects the screen-content path. Each
  // visible 8x8 CU enters the palette symbolizer, which may emit runtime
  // left-neighbour transform-skip IBC or palette syntax. 4:2:0 remains on the
  // residual path.
  assign ctu_screen_444_mode = SUPPORT_PALETTE_444 && (chroma_format_idc == 2'd3);
  assign ctu_cu_palette_mask =
    ctu_screen_444_mode ? (ctu_cu_active_mask & ~ctu_cu_ibc_mask) : '0;
  assign ctu_cu_residual_mask = ctu_screen_444_mode ? '0 : ctu_cu_active_mask;

  // The output/CABAC mux is still slice-wide. For the current subset, a 4:4:4
  // picture has all active CUs in screen-content mode; the leaf marker mux
  // chooses IBC or palette per CU.
  assign ctu_has_palette_cu = ctu_screen_444_mode;
  // Keep the active VVC syntax flags in one place and wire them into SPS,
  // slice-header, and CABAC-producing blocks. This mirrors the Rust
  // VvcSliceSyntaxConfig for the current residual/palette subset.
  assign vvc_tool_transform_skip_enabled = ctu_screen_444_mode;
  assign vvc_tool_mts_enabled = 1'b0;
  assign vvc_tool_lfnst_enabled = 1'b0;
  assign vvc_tool_joint_cbcr_enabled = 1'b0;
  assign vvc_tool_mrl_enabled = !ctu_has_palette_cu;
  assign vvc_tool_cclm_enabled = !ctu_has_palette_cu && (chroma_format_idc != 2'd0);
  assign vvc_tool_dep_quant_enabled = 1'b0;
  assign vvc_tool_sign_data_hiding_enabled = 1'b0;
  assign vvc_tool_palette_enabled = ctu_screen_444_mode;
  assign vvc_tool_ibc_enabled = ctu_screen_444_mode;
  assign vvc_sps_ref_pic_resampling_enabled = 1'b1;
  assign vvc_sps_entry_point_offsets_present = 1'b1;
  assign chroma_subsample_x_w = ((chroma_format_idc == 2'd1) || (chroma_format_idc == 2'd2)) ?
                                2'd2 : 2'd1;
  assign chroma_subsample_y_w = (chroma_format_idc == 2'd1) ? 2'd2 : 2'd1;
  assign coded_width_w =
    (visible_width + CODED_DIMENSION_GRANULARITY - 16'd1) &
    ~(CODED_DIMENSION_GRANULARITY - 16'd1);
  assign coded_height_w =
    (visible_height + CODED_DIMENSION_GRANULARITY - 16'd1) &
    ~(CODED_DIMENSION_GRANULARITY - 16'd1);
  assign ctu_cols_w = (coded_width_w + 16'd63) >> 6;
  assign ctu_rows_w = (coded_height_w + 16'd63) >> 6;
  always @* begin
    case (ctu_rows_w[4:0])
      5'd0: ctu_count_w = 16'd0;
      5'd1: ctu_count_w = ctu_cols_w;
      5'd2: ctu_count_w = ctu_cols_w << 1;
      5'd3: ctu_count_w = (ctu_cols_w << 1) + ctu_cols_w;
      5'd4: ctu_count_w = ctu_cols_w << 2;
      5'd5: ctu_count_w = (ctu_cols_w << 2) + ctu_cols_w;
      5'd6: ctu_count_w = (ctu_cols_w << 2) + (ctu_cols_w << 1);
      5'd7: ctu_count_w = (ctu_cols_w << 3) - ctu_cols_w;
      5'd8: ctu_count_w = ctu_cols_w << 3;
      5'd9: ctu_count_w = (ctu_cols_w << 3) + ctu_cols_w;
      5'd10: ctu_count_w = (ctu_cols_w << 3) + (ctu_cols_w << 1);
      5'd11: ctu_count_w = (ctu_cols_w << 3) + (ctu_cols_w << 1) + ctu_cols_w;
      5'd12: ctu_count_w = (ctu_cols_w << 3) + (ctu_cols_w << 2);
      5'd13: ctu_count_w = (ctu_cols_w << 3) + (ctu_cols_w << 2) + ctu_cols_w;
      5'd14: ctu_count_w = (ctu_cols_w << 4) - (ctu_cols_w << 1);
      5'd15: ctu_count_w = (ctu_cols_w << 4) - ctu_cols_w;
      5'd16: ctu_count_w = ctu_cols_w << 4;
      default: ctu_count_w = 16'd0;
    endcase
  end
  assign multi_slice_picture_w = ctu_count_w > 16'd1;
  assign current_slice_last_w = (current_slice_q + 16'd1) >= ctu_count_w;
  always @* begin
    slice_address_bits_w = 6'd0;
    if (ctu_count_w > 16'd1) begin
      slice_address_bits_w = 6'd1;
    end
    if (ctu_count_w > 16'd2) begin
      slice_address_bits_w = 6'd2;
    end
    if (ctu_count_w > 16'd4) begin
      slice_address_bits_w = 6'd3;
    end
    if (ctu_count_w > 16'd8) begin
      slice_address_bits_w = 6'd4;
    end
    if (ctu_count_w > 16'd16) begin
      slice_address_bits_w = 6'd5;
    end
    if (ctu_count_w > 16'd32) begin
      slice_address_bits_w = 6'd6;
    end
    if (ctu_count_w > 16'd64) begin
      slice_address_bits_w = 6'd7;
    end
    if (ctu_count_w > 16'd128) begin
      slice_address_bits_w = 6'd8;
    end
  end
  assign current_ctu_origin_x_w = current_ctu_x_q << 6;
  assign current_ctu_origin_y_w = current_ctu_y_q << 6;
  assign current_ctu_remaining_width_w =
    (visible_width > current_ctu_origin_x_w) ?
      (visible_width - current_ctu_origin_x_w) : 16'd1;
  assign current_ctu_remaining_height_w =
    (visible_height > current_ctu_origin_y_w) ?
      (visible_height - current_ctu_origin_y_w) : 16'd1;
  assign ctu_visible_width_w =
    (current_ctu_remaining_width_w > CTU_SIZE_L) ? CTU_SIZE_L :
    current_ctu_remaining_width_w;
  assign ctu_visible_height_w =
    (current_ctu_remaining_height_w > CTU_SIZE_L) ? CTU_SIZE_L :
    current_ctu_remaining_height_w;
  assign active_luma_tu_cols_w =
    (ctu_visible_width_w == 16'd0) ? 4'd1 : ((ctu_visible_width_w + 16'd7) >> 3);
  assign active_luma_tu_rows_w =
    (ctu_visible_height_w == 16'd0) ? 4'd1 : ((ctu_visible_height_w + 16'd7) >> 3);
  always @* begin
    case (active_luma_tu_rows_w)
      4'd0: active_luma_tu_count_w = 7'd0;
      4'd1: active_luma_tu_count_w = {3'd0, active_luma_tu_cols_w};
      4'd2: active_luma_tu_count_w = {2'd0, active_luma_tu_cols_w, 1'b0};
      4'd3: active_luma_tu_count_w = {2'd0, active_luma_tu_cols_w, 1'b0} +
                                      {3'd0, active_luma_tu_cols_w};
      4'd4: active_luma_tu_count_w = {1'd0, active_luma_tu_cols_w, 2'b00};
      4'd5: active_luma_tu_count_w = {1'd0, active_luma_tu_cols_w, 2'b00} +
                                      {3'd0, active_luma_tu_cols_w};
      4'd6: active_luma_tu_count_w = {1'd0, active_luma_tu_cols_w, 2'b00} +
                                      {2'd0, active_luma_tu_cols_w, 1'b0};
      4'd7: active_luma_tu_count_w = {active_luma_tu_cols_w, 3'b000} -
                                      {3'd0, active_luma_tu_cols_w};
      default: active_luma_tu_count_w = {active_luma_tu_cols_w, 3'b000};
    endcase
  end
  assign active_chroma_tu_count_w = active_luma_tu_count_w;
  assign luma_tu_stream_samples_w =
    active_luma_tu_count_w << 6;
  assign chroma_tu_stream_samples_w =
    ctu_has_palette_cu ?
      (active_luma_tu_count_w << 6) :
      (active_chroma_tu_count_w << 4);
  assign cb_tu_stream_base_w = luma_tu_stream_samples_w;
  assign cr_tu_stream_base_w = luma_tu_stream_samples_w + chroma_tu_stream_samples_w;
  assign frame_samples_w = luma_tu_stream_samples_w + (chroma_tu_stream_samples_w << 1);
  assign input_len_w = frame_samples_w;
  assign v_sample_index_w = cr_tu_stream_base_w;
  assign input_frame_last_w = input_active_q && (input_count_q == input_len_q - 1'b1);
  // RTL input stream contract for the current fixed-TU subset:
  // samples arrive in CTU-local coding-tree leaf order, one 8x8 leaf at a
  // time. Each leaf carries all luma samples first, then the colocated Cb
  // block, then the colocated Cr block. For 4:2:0 residual mode the chroma
  // blocks are 4x4; for 4:4:4 palette mode they are 8x8. This intentionally
  // differs from planar YUV file storage and from xk265's raster CTU fetch
  // buffer: the contract keeps the input-side live storage at TU scale
  // instead of buffering a full 64x64 CTU. If future dynamic partitioning is
  // added, this interface can be widened to 16x16 leaves or full CTUs.
  assign input_chroma_stream_last_sample_w = ctu_has_palette_cu ? 6'd63 : 6'd15;
  assign input_stream_component_last_w =
    (input_stream_component_q == 2'd0) ?
      (input_stream_sample_q == 6'd63) :
      (input_stream_sample_q == input_chroma_stream_last_sample_w);
  always @* begin
    input_stream_leaf_next_w = input_stream_leaf_q;
    input_stream_component_next_w = input_stream_component_q;
    input_stream_sample_next_w = input_stream_sample_q;
    if (input_stream_component_last_w) begin
      input_stream_sample_next_w = 6'd0;
      if (input_stream_component_q == 2'd0) begin
        input_stream_component_next_w = 2'd1;
      end else if (input_stream_component_q == 2'd1) begin
        input_stream_component_next_w = 2'd2;
      end else begin
        input_stream_component_next_w = 2'd0;
        input_stream_leaf_next_w = input_stream_leaf_q + 7'd1;
      end
    end else begin
      input_stream_sample_next_w = input_stream_sample_q + 6'd1;
    end
  end

  assign palette_sample_plane_w = input_stream_component_q;
  assign input_luma_tu_ordinal_w = input_stream_leaf_q;
  assign input_luma_tu_sample_index_w = input_stream_sample_q;
  assign input_luma_x_w = input_luma_tu_origin_x_w + {13'd0, input_luma_tu_sample_index_w[2:0]};
  assign input_luma_y_w = input_luma_tu_origin_y_w + {13'd0, input_luma_tu_sample_index_w[5:3]};
  assign input_luma_ctu_local_x_w = input_luma_x_w;
  assign input_luma_ctu_local_y_w = input_luma_y_w;
  assign residual_luma_sample_w =
    !ctu_has_palette_cu &&
    (input_stream_component_q == 2'd0) &&
    (input_luma_ctu_local_x_w < CTU_SIZE_L) &&
    (input_luma_ctu_local_y_w < CTU_SIZE_L);
  assign input_luma_tu_index_full_w =
    {input_luma_tu_origin_y_w[5:3], 3'b000} +
    {13'd0, input_luma_tu_origin_x_w[5:3]};
  assign input_luma_tu_index_w = input_luma_tu_index_full_w[5:0];
  assign input_luma_tu_sample_w =
    residual_luma_sample_w &&
    input_luma_tu_valid_w &&
    (input_luma_tu_ordinal_w < active_luma_tu_count_w) &&
    (input_luma_tu_index_full_w < VVC_LUMA_TUS_PER_CTU);
  assign input_luma_tu_last_sample_w =
    input_luma_tu_sample_w && (input_luma_tu_sample_index_w == 6'd63);
  assign residual_luma_sample_index_w = input_luma_tu_sample_index_w;
  assign luma_quant_ctu_visible_width_w = ctu_visible_width_w;
  assign luma_quant_ctu_visible_height_w = ctu_visible_height_w;
  assign luma_quant_tu_col_w = luma_quant_tu_q % VVC_LUMA_TU_COLS_L;
  assign luma_quant_tu_row_w = luma_quant_tu_q / VVC_LUMA_TU_COLS_L;
  assign luma_quant_tu_origin_x_w = {10'd0, luma_quant_tu_col_w, 3'b000};
  assign luma_quant_tu_origin_y_w = {10'd0, luma_quant_tu_row_w, 3'b000};
  assign luma_quant_tu_visible_w =
    (luma_quant_tu_origin_x_w < luma_quant_ctu_visible_width_w) &&
    (luma_quant_tu_origin_y_w < luma_quant_ctu_visible_height_w);
  assign luma_quant_tu_remaining_width_w =
    (luma_quant_ctu_visible_width_w > luma_quant_tu_origin_x_w) ?
      (luma_quant_ctu_visible_width_w - luma_quant_tu_origin_x_w) : 16'd0;
  assign luma_quant_tu_remaining_height_w =
    (luma_quant_ctu_visible_height_w > luma_quant_tu_origin_y_w) ?
      (luma_quant_ctu_visible_height_w - luma_quant_tu_origin_y_w) : 16'd0;
  assign luma_quant_visible_cols_w =
    !luma_quant_tu_visible_w ? 4'd0 :
    ((luma_quant_tu_remaining_width_w > VVC_LUMA_TU_SIZE_L) ?
      4'd8 : luma_quant_tu_remaining_width_w[3:0]);
  assign luma_quant_visible_rows_w =
    !luma_quant_tu_visible_w ? 4'd0 :
    ((luma_quant_tu_remaining_height_w > VVC_LUMA_TU_SIZE_L) ?
      4'd8 : luma_quant_tu_remaining_height_w[3:0]);
  assign luma_quant_sample_tu_w = luma_sample_tu_q;

  ff_vvc_luma_tu_node_8x8 #(
    .CTU_SIZE(CTU_SIZE)
  ) input_luma_tu_node (
    .visible_width(ctu_visible_width_w),
    .visible_height(ctu_visible_height_w),
    .target_index(input_luma_tu_ordinal_w[5:0]),
    .valid(input_luma_tu_valid_w),
    .tu_x(input_luma_tu_origin_x_w),
    .tu_y(input_luma_tu_origin_y_w)
  );
  assign chroma_quant_ctu_visible_width_w = ctu_visible_width_w;
  assign chroma_quant_ctu_visible_height_w = ctu_visible_height_w;
  assign chroma_quant_visible_chroma_width_w = chroma_quant_ctu_visible_width_w >> 1;
  assign chroma_quant_visible_chroma_height_w = chroma_quant_ctu_visible_height_w >> 1;
  assign chroma_quant_tu_col_w = chroma_quant_tu_origin_x_w[4:2];
  assign chroma_quant_tu_row_w = chroma_quant_tu_origin_y_w[4:2];

  assign input_sample_8bit_w =
    (SAMPLE_BITS <= 8) ? s_axis_data[7:0] : (s_axis_data >> (SAMPLE_BITS - 8));
  assign input_chroma_width_w =
    (chroma_subsample_x_w == 2'd2) ? (visible_width >> 1) : visible_width;
  assign input_chroma_height_w =
    (chroma_subsample_y_w == 2'd2) ? (visible_height >> 1) : visible_height;
  assign input_chroma_tu_index_full_w = input_stream_leaf_q;
  assign input_chroma_tu_index_w = input_chroma_tu_index_full_w[5:0];
  assign input_chroma_tu_sample_index_w = input_stream_sample_q;
  assign input_chroma_tu_local_x_w = {14'd0, input_chroma_tu_sample_index_w[1:0]};
  assign input_chroma_tu_local_y_w = {14'd0, input_chroma_tu_sample_index_w[3:2]};
  assign input_chroma_x_w = input_chroma_tu_origin_x_w + input_chroma_tu_local_x_w;
  assign input_chroma_y_w = input_chroma_tu_origin_y_w + input_chroma_tu_local_y_w;
  assign input_chroma_ctu_local_x_w = input_chroma_x_w;
  assign input_chroma_ctu_local_y_w = input_chroma_y_w;
  assign input_chroma_tu_sample_w =
    !ctu_has_palette_cu &&
    (input_stream_component_q != 2'd0) &&
    input_chroma_tu_valid_w &&
    (input_chroma_tu_index_full_w < active_chroma_tu_count_w) &&
    (input_chroma_tu_local_x_w < input_chroma_tu_width_w) &&
    (input_chroma_tu_local_y_w < input_chroma_tu_height_w) &&
    (input_chroma_x_w < input_chroma_width_w) &&
    (input_chroma_y_w < input_chroma_height_w);
  assign input_chroma_tu_last_cr_sample_w =
    !ctu_has_palette_cu &&
    (chroma_format_idc == 2'd1) &&
    (input_stream_component_q == 2'd2) &&
    input_chroma_tu_valid_w &&
    (input_chroma_tu_index_full_w < active_chroma_tu_count_w) &&
    (input_chroma_tu_sample_index_w == input_chroma_stream_last_sample_w);

  ff_vvc_chroma_tu_node_420 #(
    .CTU_SIZE(CTU_SIZE)
  ) input_chroma_tu_node (
    .visible_width(ctu_visible_width_w),
    .visible_height(ctu_visible_height_w),
    .target_index(input_chroma_tu_index_w),
    .valid(input_chroma_tu_valid_w),
    .tu_x(input_chroma_tu_origin_x_w),
    .tu_y(input_chroma_tu_origin_y_w),
    .tu_width(input_chroma_tu_width_w),
    .tu_height(input_chroma_tu_height_w)
  );

  assign chroma_quant_cb_sample_tu_w = cb_sample_tu_q;
  assign chroma_quant_cr_sample_tu_w = cr_sample_tu_q;

  always @* begin
    luma_quant_samples_w = '0;
    luma_quant_top_ref_w = {VVC_LUMA_TU_SIZE{8'd128}};
    luma_quant_left_ref_w = {VVC_LUMA_TU_SIZE{8'd128}};
    luma_quant_ref_x_tmp = 16'd0;
    luma_quant_ref_y_tmp = 16'd0;

    if (luma_quant_tu_visible_w) begin
      luma_quant_samples_w = luma_quant_sample_tu_w;

      for (luma_quant_pack_i = 0; luma_quant_pack_i < VVC_LUMA_TU_SIZE; luma_quant_pack_i = luma_quant_pack_i + 1) begin
        if (luma_quant_tu_origin_y_w != 16'd0) begin
          luma_quant_ref_x_tmp = luma_quant_tu_origin_x_w + luma_quant_pack_i[15:0];
          if (luma_quant_ref_x_tmp >= luma_quant_ctu_visible_width_w) begin
            luma_quant_ref_x_tmp = luma_quant_ctu_visible_width_w - 16'd1;
          end
          luma_quant_top_ref_w[luma_quant_pack_i * 8 +: 8] =
            luma_top_ref_row_q[luma_quant_tu_col_w][luma_quant_ref_x_tmp[2:0] * 8 +: 8];
        end else if ((luma_quant_tu_origin_x_w != 16'd0) &&
                     (luma_quant_tu_origin_y_w < luma_quant_ctu_visible_height_w)) begin
          // H.266 8.4.4.2 reference sample substitution: when the top row is
          // unavailable but a left TU exists, substitute p[-1][0], not a
          // lower-left edge sample from the previous TU.
          luma_quant_top_ref_w[luma_quant_pack_i * 8 +: 8] =
            luma_left_ref_col_q[luma_quant_tu_row_w][0 +: 8];
        end

        if (luma_quant_tu_origin_x_w != 16'd0) begin
          luma_quant_ref_y_tmp = luma_quant_tu_origin_y_w + luma_quant_pack_i[15:0];
          if (luma_quant_ref_y_tmp >= luma_quant_ctu_visible_height_w) begin
            luma_quant_ref_y_tmp = luma_quant_ctu_visible_height_w - 16'd1;
          end
          luma_quant_left_ref_w[luma_quant_pack_i * 8 +: 8] =
            luma_left_ref_col_q[luma_quant_tu_row_w][luma_quant_ref_y_tmp[2:0] * 8 +: 8];
        end else if ((luma_quant_tu_origin_y_w != 16'd0) &&
                     (luma_quant_tu_origin_x_w < luma_quant_ctu_visible_width_w)) begin
          luma_quant_left_ref_w[luma_quant_pack_i * 8 +: 8] =
            luma_top_ref_row_q[luma_quant_tu_col_w][0 +: 8];
        end
      end
    end
  end

  ff_vvc_chroma_tu_node_420 #(
    .CTU_SIZE(CTU_SIZE)
  ) chroma_quant_node (
    .visible_width(chroma_quant_ctu_visible_width_w),
    .visible_height(chroma_quant_ctu_visible_height_w),
    .target_index(chroma_quant_tu_q),
    .valid(chroma_quant_tu_valid_w),
    .tu_x(chroma_quant_tu_origin_x_w),
    .tu_y(chroma_quant_tu_origin_y_w),
    .tu_width(chroma_quant_tu_width_w),
    .tu_height(chroma_quant_tu_height_w)
  );

  always @* begin
    chroma_quant_cb_samples_w = '0;
    chroma_quant_cr_samples_w = '0;
    chroma_quant_cb_top_ref_w = {VVC_CHROMA_TU_SIZE{8'd128}};
    chroma_quant_cb_left_ref_w = {VVC_CHROMA_TU_SIZE{8'd128}};
    chroma_quant_cr_top_ref_w = {VVC_CHROMA_TU_SIZE{8'd128}};
    chroma_quant_cr_left_ref_w = {VVC_CHROMA_TU_SIZE{8'd128}};
    chroma_quant_ref_x_tmp = 16'd0;
    chroma_quant_ref_y_tmp = 16'd0;

    if (chroma_quant_tu_valid_w) begin
      chroma_quant_cb_samples_w = chroma_quant_cb_sample_tu_w;
      chroma_quant_cr_samples_w = chroma_quant_cr_sample_tu_w;

      for (chroma_quant_pack_i = 0; chroma_quant_pack_i < VVC_CHROMA_TU_SIZE; chroma_quant_pack_i = chroma_quant_pack_i + 1) begin
        if (chroma_quant_pack_i[15:0] < chroma_quant_tu_width_w) begin
          if (chroma_quant_tu_origin_y_w != 16'd0) begin
            chroma_quant_ref_x_tmp = chroma_quant_tu_origin_x_w + chroma_quant_pack_i[15:0];
            if (chroma_quant_ref_x_tmp >= chroma_quant_visible_chroma_width_w) begin
              chroma_quant_ref_x_tmp = chroma_quant_visible_chroma_width_w - 16'd1;
            end
            chroma_quant_cb_top_ref_w[chroma_quant_pack_i * 8 +: 8] =
              chroma_cb_top_ref_row_q[chroma_quant_tu_col_w][chroma_quant_ref_x_tmp[1:0] * 8 +: 8];
            chroma_quant_cr_top_ref_w[chroma_quant_pack_i * 8 +: 8] =
              chroma_cr_top_ref_row_q[chroma_quant_tu_col_w][chroma_quant_ref_x_tmp[1:0] * 8 +: 8];
          end else if ((chroma_quant_tu_origin_x_w != 16'd0) &&
                       (chroma_quant_tu_origin_y_w < chroma_quant_visible_chroma_height_w)) begin
            chroma_quant_cb_top_ref_w[chroma_quant_pack_i * 8 +: 8] =
              chroma_cb_left_ref_col_q[chroma_quant_tu_row_w][0 +: 8];
            chroma_quant_cr_top_ref_w[chroma_quant_pack_i * 8 +: 8] =
              chroma_cr_left_ref_col_q[chroma_quant_tu_row_w][0 +: 8];
          end
        end

        if (chroma_quant_pack_i[15:0] < chroma_quant_tu_height_w) begin
          if (chroma_quant_tu_origin_x_w != 16'd0) begin
            chroma_quant_ref_y_tmp = chroma_quant_tu_origin_y_w + chroma_quant_pack_i[15:0];
            if (chroma_quant_ref_y_tmp >= chroma_quant_visible_chroma_height_w) begin
              chroma_quant_ref_y_tmp = chroma_quant_visible_chroma_height_w - 16'd1;
            end
            chroma_quant_cb_left_ref_w[chroma_quant_pack_i * 8 +: 8] =
              chroma_cb_left_ref_col_q[chroma_quant_tu_row_w][chroma_quant_ref_y_tmp[1:0] * 8 +: 8];
            chroma_quant_cr_left_ref_w[chroma_quant_pack_i * 8 +: 8] =
              chroma_cr_left_ref_col_q[chroma_quant_tu_row_w][chroma_quant_ref_y_tmp[1:0] * 8 +: 8];
          end else if ((chroma_quant_tu_origin_y_w != 16'd0) &&
                       (chroma_quant_tu_origin_x_w < chroma_quant_visible_chroma_width_w)) begin
            chroma_quant_cb_left_ref_w[chroma_quant_pack_i * 8 +: 8] =
              chroma_cb_top_ref_row_q[chroma_quant_tu_col_w][0 +: 8];
            chroma_quant_cr_left_ref_w[chroma_quant_pack_i * 8 +: 8] =
              chroma_cr_top_ref_row_q[chroma_quant_tu_col_w][0 +: 8];
          end
        end
      end
    end
  end

  ff_vvc_luma_quant_recon_8x8 luma_quant_recon (
    .clk(clk),
    .rst_n(rst_n),
    .clear(frame_pipeline_clear_w),
    .start(luma_quant_start_q),
    .samples(luma_quant_samples_w),
    .visible_cols(luma_quant_visible_cols_w),
    .visible_rows(luma_quant_visible_rows_w),
    .top_ref(luma_quant_top_ref_w),
    .left_ref(luma_quant_left_ref_w),
    .abs_level(luma_quant_abs_level_w),
    .negative(luma_quant_negative_w),
    .ac_levels(luma_quant_ac_levels_w),
    .bottom_ref(luma_quant_bottom_ref_w),
    .right_ref(luma_quant_right_ref_w),
    .done(luma_quant_done_w),
    .busy(luma_quant_busy_w)
  );

  ff_vvc_chroma_quant_recon_420 cb_chroma_quant_recon (
    .clk(clk),
    .rst_n(rst_n),
    .clear(frame_pipeline_clear_w),
    .start(chroma_quant_start_q),
    .samples(chroma_quant_cb_samples_w),
    .top_ref(chroma_quant_cb_top_ref_w),
    .left_ref(chroma_quant_cb_left_ref_w),
    .dc_level(chroma_quant_cb_dc_level_w),
    .ac_levels(chroma_quant_cb_ac_levels_w),
    .bottom_ref(chroma_quant_cb_bottom_ref_w),
    .right_ref(chroma_quant_cb_right_ref_w),
    .done(chroma_quant_cb_done_w),
    .busy(chroma_quant_cb_busy_w)
  );

  ff_vvc_chroma_quant_recon_420 cr_chroma_quant_recon (
    .clk(clk),
    .rst_n(rst_n),
    .clear(frame_pipeline_clear_w),
    .start(chroma_quant_start_q),
    .samples(chroma_quant_cr_samples_w),
    .top_ref(chroma_quant_cr_top_ref_w),
    .left_ref(chroma_quant_cr_left_ref_w),
    .dc_level(chroma_quant_cr_dc_level_w),
    .ac_levels(chroma_quant_cr_ac_levels_w),
    .bottom_ref(chroma_quant_cr_bottom_ref_w),
    .right_ref(chroma_quant_cr_right_ref_w),
    .done(chroma_quant_cr_done_w),
    .busy(chroma_quant_cr_busy_w)
  );

  assign chroma_quant_done_w = chroma_quant_cb_done_w && chroma_quant_cr_done_w;
  assign chroma_quant_busy_w = chroma_quant_cb_busy_w || chroma_quant_cr_busy_w;

  always @* begin
    selected_quant_luma_rem_w = '0;
    selected_quant_luma_negative_w = '0;
    selected_quant_luma_ac_levels_w = '0;
    selected_quant_cb_dc_levels_w = '0;
    selected_quant_cr_dc_levels_w = '0;
    selected_quant_cb_ac_levels_w = '0;
    selected_quant_cr_ac_levels_w = '0;
    for (luma_pack_tu_i = 0; luma_pack_tu_i < VVC_LUMA_TUS_PER_CTU; luma_pack_tu_i = luma_pack_tu_i + 1) begin
      selected_quant_luma_rem_w[luma_pack_tu_i * 8 +: 8] =
        quant_luma_rem_ctu_q[luma_pack_tu_i];
      selected_quant_luma_negative_w[luma_pack_tu_i] =
        quant_luma_negative_ctu_q[luma_pack_tu_i];
      selected_quant_luma_ac_levels_w[
        luma_pack_tu_i * (VVC_RESIDUAL_AC_BITS * VVC_LUMA_AC_COEFFS) +:
          (VVC_RESIDUAL_AC_BITS * VVC_LUMA_AC_COEFFS)
      ] =
        quant_luma_ac_levels_ctu_q[luma_pack_tu_i];
    end
    for (chroma_pack_tu_i = 0; chroma_pack_tu_i < VVC_CHROMA_TUS_PER_CTU; chroma_pack_tu_i = chroma_pack_tu_i + 1) begin
      selected_quant_cb_dc_levels_w[chroma_pack_tu_i * 9 +: 9] =
        quant_cb_dc_level_ctu_q[chroma_pack_tu_i];
      selected_quant_cr_dc_levels_w[chroma_pack_tu_i * 9 +: 9] =
        quant_cr_dc_level_ctu_q[chroma_pack_tu_i];
      selected_quant_cb_ac_levels_w[
        chroma_pack_tu_i * (VVC_RESIDUAL_AC_BITS * VVC_CHROMA_AC_COEFFS) +:
          (VVC_RESIDUAL_AC_BITS * VVC_CHROMA_AC_COEFFS)
      ] =
        quant_cb_ac_levels_ctu_q[chroma_pack_tu_i];
      selected_quant_cr_ac_levels_w[
        chroma_pack_tu_i * (VVC_RESIDUAL_AC_BITS * VVC_CHROMA_AC_COEFFS) +:
          (VVC_RESIDUAL_AC_BITS * VVC_CHROMA_AC_COEFFS)
      ] =
        quant_cr_ac_levels_ctu_q[chroma_pack_tu_i];
    end
  end

  // Current residual subset uses one 8x8 luma TU and emits the first 4x4
  // coefficient group: DC plus bounded AC levels from the residual transform.
  assign luma_log2_tb_width_w = 3'd3;
  assign luma_log2_tb_height_w = 3'd3;

  assign busy = input_active_q || pending_output_q || resume_input_q || frame_clear_q ||
                chroma_tu_quant_pending_q || chroma_quant_active_q || chroma_quant_busy_w ||
                luma_tu_quant_pending_q || luma_quant_active_q || luma_quant_busy_w ||
                m_axis_valid ||
                (generated_out_state_q != GENERATED_OUT_IDLE);
  assign frame_pipeline_clear_w = (start && !busy) || frame_clear_q;
  assign cabac_enable = 1'b1;
  assign cabac_stream_ready = rbsp_payload_ready;
  assign rbsp_output_ready =
    (generated_out_state_q == GENERATED_OUT_CABAC) && (!m_axis_valid || m_axis_ready);
  assign rbsp_protected_ready = 1'b0;
  assign rbsp_ep_input_ready = slice_stream_ready;
  assign ctu_cu_effective_ibc_mask_w = ctu_cu_ibc_mask | ctu_cu_runtime_ibc_mask_q;
  assign palette_leaf_col_w = ctu_symbol_data[21:19];
  assign palette_leaf_row_w = ctu_symbol_data[5:3];
  assign palette_leaf_index_w = {palette_leaf_row_w, palette_leaf_col_w};
  assign palette_leaf_is_ibc_w = ctu_cu_ibc_mask[palette_leaf_index_w];
  assign palette_leaf_ibc_left_w =
    (palette_leaf_col_w != 3'd0) && ctu_cu_effective_ibc_mask_w[palette_leaf_index_w - 6'd1];
  assign palette_leaf_ibc_above_w =
    (palette_leaf_row_w != 3'd0) && ctu_cu_effective_ibc_mask_w[palette_leaf_index_w - 6'd8];
  assign palette_leaf_ibc_ctx_w =
    {2'd0, palette_leaf_ibc_left_w} + {2'd0, palette_leaf_ibc_above_w};
  assign palette_leaf_ibc_mvd_x_w =
    ctu_cu_ibc_mvd_x[palette_leaf_index_w * 16 +: 16];
  assign palette_leaf_ibc_mvd_y_w =
    ctu_cu_ibc_mvd_y[palette_leaf_index_w * 16 +: 16];
  assign ibc_source_symbol_data_w = {
    3'd0,
    palette_leaf_ibc_ctx_w,
    palette_leaf_ibc_mvd_y_w[12:0],
    palette_leaf_ibc_mvd_x_w[12:0]
  };
  assign palette_source_symbol_data_w =
    palette_stream_data |
    (palette_stream_cu_last ? 32'h0800_0000 : 32'd0) |
    ((palette_stream_data[31:28] == 4'h1) ?
      {29'd0, palette_current_pred_ibc_ctx_q} : 32'd0);
  assign palette_leaf_marker_valid =
    ctu_has_palette_cu && (palette_mux_state_q == PALETTE_MUX_PARTITION) &&
    ctu_symbol_valid && (ctu_symbol_kind == SYMBOL_PALETTE_LEAF);
  assign palette_request_valid =
    palette_leaf_marker_valid && (generated_out_state_q == GENERATED_OUT_CABAC) &&
    !cabac_start_q && !palette_leaf_is_ibc_w;
  assign palette_request_origin_x = ctu_symbol_data[31:16];
  assign palette_request_origin_y = ctu_symbol_data[15:0];
  assign palette_request_last = ctu_symbol_last;
  assign source_symbol_valid = ctu_has_palette_cu ?
    ((palette_mux_state_q == PALETTE_MUX_CU) ? palette_stream_valid :
     ((palette_mux_state_q == PALETTE_MUX_PARTITION) &&
      ctu_symbol_valid &&
      ((ctu_symbol_kind != SYMBOL_PALETTE_LEAF) || palette_leaf_is_ibc_w))) :
    ctu_symbol_valid;
  assign source_symbol_kind = ctu_has_palette_cu ?
    ((palette_mux_state_q == PALETTE_MUX_CU) ? {4'h8, palette_stream_data[31:28]} :
     ((ctu_symbol_kind == SYMBOL_PALETTE_LEAF) ? IBC_PKT_CU : ctu_symbol_kind)) :
    ctu_symbol_kind;
  assign source_symbol_data = ctu_has_palette_cu ?
    ((palette_mux_state_q == PALETTE_MUX_CU) ?
      palette_source_symbol_data_w :
      ((ctu_symbol_kind == SYMBOL_PALETTE_LEAF) ? ibc_source_symbol_data_w : ctu_symbol_data)) :
    ctu_symbol_data;
  assign source_symbol_last = ctu_has_palette_cu ?
    ((palette_mux_state_q == PALETTE_MUX_CU) ? palette_stream_last : ctu_symbol_last) :
    ctu_symbol_last;
  assign source_symbol_ready =
    (generated_out_state_q == GENERATED_OUT_CABAC) && !cabac_start_q && !cabac_input_valid_q;
  assign palette_stream_ready =
    ctu_has_palette_cu && (palette_mux_state_q == PALETTE_MUX_CU) && source_symbol_ready;
  ff_vvc_cu_activity_mask #(
    .CTU_SIZE(CTU_SIZE),
    .CU_SIZE(PALETTE_CU_SIZE),
    .CU_COUNT(MAX_CTU_PALETTE_SYMBOLS)
  ) ctu_cu_activity_mask (
    .visible_width(ctu_visible_width_w),
    .visible_height(ctu_visible_height_w),
    .cu_active_mask(ctu_cu_active_mask)
  );

  generate
    if (SUPPORT_EXACT_HASH_IBC_444) begin : gen_exact_hash_ibc
      // H.266 8.6.2.2 builds the IBC BVP list from already decoded
      // neighbouring IBC CUs and HMVP entries. This legacy exact-hash matcher
      // runs before the runtime transform-skip IBC decisions are final, so it
      // is not part of the default conformance/synthesis configuration.
      assign exact_ibc_hash_enabled_w = ctu_screen_444_mode;
      assign ibc_sample_valid =
        exact_ibc_hash_enabled_w && input_active_q && s_axis_valid && s_axis_ready &&
        (input_count_q < frame_samples_w);
      assign ibc_cu_full_visible_w =
        input_luma_tu_valid_w &&
        ((input_luma_tu_origin_x_w + 16'd8) <= ctu_visible_width_w) &&
        ((input_luma_tu_origin_y_w + 16'd8) <= ctu_visible_height_w);
      assign ibc_cu_last_sample_w =
        ibc_sample_valid &&
        (input_stream_component_q == 2'd2) &&
        (input_stream_sample_q == 6'd63);

      ff_vvc_ibc_hash_matcher #(
        .CTU_SIZE(CTU_SIZE),
        .CU_SIZE(PALETTE_CU_SIZE),
        .CU_COUNT(MAX_CTU_PALETTE_SYMBOLS)
      ) ibc_hash_matcher (
        .clk(clk),
        .rst_n(rst_n),
        .clear(frame_pipeline_clear_w),
        .enable(exact_ibc_hash_enabled_w),
        .sample_valid(ibc_sample_valid),
        .sample_data(input_sample_8bit_w),
        .cu_index(input_luma_tu_index_w),
        .cu_origin_x(input_luma_tu_origin_x_w),
        .cu_origin_y(input_luma_tu_origin_y_w),
        .cu_full_visible(ibc_cu_full_visible_w),
        .cu_last_sample(ibc_cu_last_sample_w),
        .idle(ibc_matcher_idle),
        .ibc_cu_mask(ctu_cu_ibc_mask),
        .ibc_ref_indices(),
        .ibc_mvd_x(ctu_cu_ibc_mvd_x),
        .ibc_mvd_y(ctu_cu_ibc_mvd_y)
      );
    end else begin : gen_no_exact_hash_ibc
      assign exact_ibc_hash_enabled_w = 1'b0;
      assign ibc_sample_valid = 1'b0;
      assign ibc_cu_full_visible_w = 1'b0;
      assign ibc_cu_last_sample_w = 1'b0;
      assign ibc_matcher_idle = 1'b1;
      assign ctu_cu_ibc_mask = '0;
      assign ctu_cu_ibc_mvd_x = '0;
      assign ctu_cu_ibc_mvd_y = '0;
    end
  endgenerate

  ff_vvc_coding_tree_scheduler #(
    .CTU_SIZE(CTU_SIZE)
  ) coding_tree_scheduler (
    .visible_width(ctu_visible_width_w),
    .visible_height(ctu_visible_height_w),
    .coded_width(coding_tree_coded_width),
    .coded_height(coding_tree_coded_height)
  );

  ff_vvc_annexb_header #(
    .CTU_SIZE(CTU_SIZE),
    .MAX_VISIBLE_WIDTH(MAX_VISIBLE_WIDTH),
    .MAX_VISIBLE_HEIGHT(MAX_VISIBLE_HEIGHT)
  ) annexb_header (
    .clk(clk),
    .rst_n(rst_n),
    .clear(start && !busy),
    .start(generated_header_start_q),
    .visible_width(visible_width),
    .visible_height(visible_height),
    .chroma_format_idc(chroma_format_idc),
    .sps_palette_enabled_flag(vvc_tool_palette_enabled),
    .sps_ibc_enabled_flag(vvc_tool_ibc_enabled),
    .sps_ref_pic_resampling_enabled_flag(vvc_sps_ref_pic_resampling_enabled),
    .sps_entry_point_offsets_present_flag(vvc_sps_entry_point_offsets_present),
    .sps_transform_skip_enabled_flag(vvc_tool_transform_skip_enabled),
    .sps_mts_enabled_flag(vvc_tool_mts_enabled),
    .sps_lfnst_enabled_flag(vvc_tool_lfnst_enabled),
    .sps_joint_cbcr_enabled_flag(vvc_tool_joint_cbcr_enabled),
    .sps_mrl_enabled_flag(vvc_tool_mrl_enabled),
    .sps_cclm_enabled_flag(vvc_tool_cclm_enabled),
    .sps_dep_quant_enabled_flag(vvc_tool_dep_quant_enabled),
    .sps_sign_data_hiding_enabled_flag(vvc_tool_sign_data_hiding_enabled),
    .m_axis_ready(generated_header_ready_w),
    .m_axis_valid(generated_header_valid_w),
    .m_axis_data(generated_header_byte_w),
    .m_axis_last(generated_header_last_w),
    .done(generated_header_done_w)
  );

  assign generated_header_ready_w =
    (generated_out_state_q == GENERATED_OUT_PREAMBLE) &&
    (!m_axis_valid || m_axis_ready);

  ff_vvc_annexb_picture_header_stream picture_header_stream (
    .clk(clk),
    .rst_n(rst_n),
    .clear(start && !busy),
    .start(generated_picture_header_start_q),
    .poc_lsb(frame_index_q[15:0]),
    .sps_joint_cbcr_enabled_flag(vvc_tool_joint_cbcr_enabled),
    .m_axis_ready(picture_header_ready_w),
    .m_axis_valid(picture_header_valid_w),
    .m_axis_data(picture_header_byte_w),
    .m_axis_last(picture_header_last_w),
    .done(picture_header_done_w)
  );

  assign picture_header_ready_w =
    (generated_out_state_q == GENERATED_OUT_PICTURE_HEADER) &&
    (!m_axis_valid || m_axis_ready);

  always @* begin
    palette_sample_valid = 1'b0;
    palette_sample_plane = 2'd0;
    if (ctu_has_palette_cu && input_active_q && s_axis_valid &&
        (input_count_q < frame_samples_w)) begin
      palette_sample_valid = 1'b1;
      palette_sample_plane = palette_sample_plane_w;
    end
  end

  generate
    if (SUPPORT_PALETTE_444) begin : gen_palette_symbolizer
      ff_vvc_palette_symbolizer #(
        .CTU_SIZE(CTU_SIZE),
        .PALETTE_CU_SIZE(PALETTE_CU_SIZE),
        .SAMPLE_BITS(SAMPLE_BITS),
        .MAX_PALETTE_SYMBOLS(MAX_CTU_PALETTE_SYMBOLS)
      ) palette_symbolizer (
        .clk(clk),
        .rst_n(rst_n),
        .clear(frame_pipeline_clear_w),
        .enable(ctu_has_palette_cu),
        .ctu_coded_width(coding_tree_coded_width),
        .ctu_coded_height(coding_tree_coded_height),
        .ctu_visible_width(ctu_visible_width_w),
        .ctu_visible_height(ctu_visible_height_w),
        .cu_select_mask(ctu_cu_palette_mask),
        .cu_ibc_mask(ctu_cu_effective_ibc_mask_w),
        .cu_request_valid(palette_request_valid),
        .cu_request_ready(palette_request_ready),
        .cu_request_origin_x(palette_request_origin_x),
        .cu_request_origin_y(palette_request_origin_y),
        .cu_request_last(palette_request_last),
        .s_axis_valid(palette_sample_valid),
        .s_axis_ready(),
        .s_axis_plane(palette_sample_plane),
        .s_axis_sample(s_axis_data),
        .s_axis_last(s_axis_last),
        .m_axis_valid(palette_stream_valid),
        .m_axis_ready(palette_stream_ready),
        .m_axis_data(palette_stream_data),
        .m_axis_last(palette_stream_last),
        .m_axis_cu_last(palette_stream_cu_last),
        .m_axis_cu_ibc_mode(palette_stream_cu_ibc_mode),
        .symbol_count(palette_symbol_count)
      );
    end else begin : gen_no_palette_symbolizer
      assign palette_request_ready = 1'b0;
      assign palette_stream_valid = 1'b0;
      assign palette_stream_data = 32'd0;
      assign palette_stream_last = 1'b0;
      assign palette_stream_cu_last = 1'b0;
      assign palette_stream_cu_ibc_mode = 1'b0;
      assign palette_symbol_count = 8'd0;
    end
  endgenerate

  ff_vvc_cabac cabac_writer (
    .clk(clk),
    .rst_n(rst_n),
    .start(cabac_start_q),
    .enable(cabac_enable),
    .lossless_slice_qp(ctu_has_palette_cu),
    .s_axis_valid(!cabac_start_q && cabac_input_valid_q),
    .s_axis_ready(cabac_symbol_ready),
    .s_axis_kind(cabac_input_kind_q),
    .s_axis_data(cabac_input_data_q),
    .s_axis_last(cabac_input_last_q),
    .m_axis_ready(cabac_stream_ready),
    .m_axis_valid(cabac_stream_valid),
    .m_axis_data(cabac_stream_data),
    .m_axis_last(cabac_stream_last),
    .stream_last_byte_bits(cabac_stream_last_byte_bits)
  );

  ff_vvc_rbsp_payload_stream rbsp_payload_stream (
    .clk(clk),
    .rst_n(rst_n),
    .clear(cabac_start_q),
    .s_axis_valid(cabac_stream_valid),
    .s_axis_ready(rbsp_payload_ready),
    .s_axis_data(cabac_stream_data),
    .s_axis_last(cabac_stream_last),
    .s_axis_last_byte_bits(cabac_stream_last_byte_bits),
    .m_axis_ready(rbsp_ep_input_ready),
    .m_axis_valid(rbsp_payload_valid),
    .m_axis_data(rbsp_payload_data),
    .m_axis_last(rbsp_payload_last),
    .done()
  );

  ff_vvc_emulation_prevention_stream rbsp_emulation_prevention (
    .clk(clk),
    .rst_n(rst_n),
    .clear(cabac_start_q),
    .s_axis_valid(1'b0),
    .s_axis_ready(rbsp_palette_ep_input_ready),
    .s_axis_data(rbsp_payload_data),
    .s_axis_last(rbsp_payload_last),
    .m_axis_ready(rbsp_protected_ready),
    .m_axis_valid(rbsp_protected_valid),
    .m_axis_data(rbsp_protected_data),
    .m_axis_last(rbsp_protected_last),
    .done()
  );

  ff_vvc_annexb_slice_stream annexb_slice_stream (
    .clk(clk),
    .rst_n(rst_n),
    .clear(start && !busy),
    .start(cabac_start_q),
    .nal_unit_type(generated_slice_cra_q ? VVC_NAL_UNIT_TYPE_CRA : VVC_NAL_UNIT_TYPE_IDR_W_RADL),
    .poc_lsb(frame_index_q[15:0]),
    .include_picture_header(!multi_slice_picture_w),
    .multi_slice_picture(multi_slice_picture_w),
    .slice_address(current_slice_q),
    .slice_address_bits(slice_address_bits_w),
    .sps_joint_cbcr_enabled_flag(vvc_tool_joint_cbcr_enabled),
    .sh_dep_quant_used_flag(vvc_tool_dep_quant_enabled),
    .sh_sign_data_hiding_used_flag(vvc_tool_sign_data_hiding_enabled),
    .sh_ts_residual_coding_disabled_flag(vvc_tool_transform_skip_enabled &&
                                         !vvc_tool_dep_quant_enabled &&
                                         !vvc_tool_sign_data_hiding_enabled),
    .palette_lossless_qp(ctu_has_palette_cu),
    .s_axis_ready(slice_stream_ready),
    .s_axis_valid(rbsp_payload_valid),
    .s_axis_data(rbsp_payload_data),
    .s_axis_last(rbsp_payload_last),
    .m_axis_ready(rbsp_output_ready),
    .m_axis_valid(slice_stream_valid),
    .m_axis_data(slice_stream_data),
    .m_axis_last(slice_stream_last),
    .done()
  );

  ff_vvc_ctu_symbolizer #(
    .CTU_SIZE(CTU_SIZE),
    .LUMA_TUS_PER_CTU(VVC_LUMA_TUS_PER_CTU),
    .CHROMA_TUS_PER_CTU(VVC_CHROMA_TUS_PER_CTU)
  ) ctu_symbols (
    .clk(clk),
    .rst_n(rst_n),
    .clear(frame_pipeline_clear_w),
    .start(cabac_start_q),
    .visible_width(ctu_visible_width_w),
    .visible_height(ctu_visible_height_w),
    .chroma_format_idc(chroma_format_idc),
    .luma_abs_levels(selected_quant_luma_rem_w),
    .luma_negative(selected_quant_luma_negative_w),
    .luma_ac_levels(selected_quant_luma_ac_levels_w),
    .cb_dc_levels(selected_quant_cb_dc_levels_w),
    .cr_dc_levels(selected_quant_cr_dc_levels_w),
    .cb_ac_levels(selected_quant_cb_ac_levels_w),
    .cr_ac_levels(selected_quant_cr_ac_levels_w),
    .luma_log2_tb_width(luma_log2_tb_width_w),
    .luma_log2_tb_height(luma_log2_tb_height_w),
    .sps_mrl_enabled_flag(vvc_tool_mrl_enabled),
    .sps_cclm_enabled_flag(vvc_tool_cclm_enabled),
    .palette_partition_mode(ctu_has_palette_cu),
    .m_axis_valid(ctu_symbol_valid),
    .m_axis_ready(ctu_symbol_ready),
    .m_axis_kind(ctu_symbol_kind),
    .m_axis_data(ctu_symbol_data),
    .m_axis_last(ctu_symbol_last),
    .busy()
  );

  assign ctu_symbol_ready =
    ctu_has_palette_cu ?
      ((palette_mux_state_q == PALETTE_MUX_PARTITION) &&
       ((ctu_symbol_kind == SYMBOL_PALETTE_LEAF) ?
         (palette_leaf_is_ibc_w ? source_symbol_ready : palette_request_ready) :
         source_symbol_ready)) :
      source_symbol_ready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      input_count_q <= '0;
      input_len_q   <= '0;
      input_stream_leaf_q <= 7'd0;
      input_stream_component_q <= 2'd0;
      input_stream_sample_q <= 6'd0;
      input_active_q <= 1'b0;
      s_axis_ready <= 1'b0;
      input_error  <= 1'b0;
      m_axis_valid <= 1'b0;
      m_axis_data  <= '0;
      m_axis_last  <= 1'b0;
      cabac_start_q <= 1'b0;
      pending_output_q <= 1'b0;
      resume_input_q <= 1'b0;
      frame_clear_q <= 1'b0;
      chroma_tu_quant_pending_q <= 1'b0;
      chroma_tu_quant_frame_last_q <= 1'b0;
      chroma_quant_tu_q <= 6'd0;
      chroma_quant_start_q <= 1'b0;
      chroma_quant_active_q <= 1'b0;
      luma_quant_tu_q <= 6'd0;
      luma_quant_start_q <= 1'b0;
      luma_quant_active_q <= 1'b0;
      luma_tu_quant_pending_q <= 1'b0;
      luma_sample_tu_q <= '0;
      cb_sample_tu_q <= '0;
      cr_sample_tu_q <= '0;
      for (luma_ref_i = 0; luma_ref_i < VVC_LUMA_TU_COLS; luma_ref_i = luma_ref_i + 1) begin
        luma_top_ref_row_q[luma_ref_i] <= {VVC_LUMA_TU_SIZE{8'd128}};
        luma_left_ref_col_q[luma_ref_i] <= {VVC_LUMA_TU_SIZE{8'd128}};
        chroma_cb_top_ref_row_q[luma_ref_i] <= {VVC_CHROMA_TU_SIZE{8'd128}};
        chroma_cb_left_ref_col_q[luma_ref_i] <= {VVC_CHROMA_TU_SIZE{8'd128}};
        chroma_cr_top_ref_row_q[luma_ref_i] <= {VVC_CHROMA_TU_SIZE{8'd128}};
        chroma_cr_left_ref_col_q[luma_ref_i] <= {VVC_CHROMA_TU_SIZE{8'd128}};
      end
      frame_index_q <= 64'd0;
      generated_out_state_q <= GENERATED_OUT_IDLE;
      generated_slice_cra_q <= 1'b0;
      generated_header_start_q <= 1'b0;
      generated_picture_header_start_q <= 1'b0;
      current_slice_q <= 16'd0;
      current_ctu_x_q <= 16'd0;
      current_ctu_y_q <= 16'd0;
      cabac_input_valid_q <= 1'b0;
      cabac_input_kind_q <= 8'd0;
      cabac_input_data_q <= 32'd0;
      cabac_input_last_q <= 1'b0;
      palette_mux_state_q <= PALETTE_MUX_PARTITION;
      palette_current_pred_ibc_ctx_q <= 3'd0;
      palette_current_leaf_index_q <= 6'd0;
      ctu_cu_runtime_ibc_mask_q <= '0;
    end else begin
      cabac_start_q <= 1'b0;
      generated_header_start_q <= 1'b0;
      generated_picture_header_start_q <= 1'b0;
      frame_clear_q <= 1'b0;
      luma_quant_start_q <= 1'b0;
      chroma_quant_start_q <= 1'b0;
      if (m_axis_valid && m_axis_ready) begin
        m_axis_valid <= 1'b0;
        m_axis_last <= 1'b0;
      end
      if (start && !busy) begin
        input_active_q <= 1'b1;
        s_axis_ready   <= 1'b1;
        input_count_q  <= '0;
        input_len_q    <= input_len_w;
        input_stream_leaf_q <= 7'd0;
        input_stream_component_q <= 2'd0;
        input_stream_sample_q <= 6'd0;
        input_error    <= (visible_width == 16'd0) || (visible_height == 16'd0) ||
                          (visible_width > MAX_VISIBLE_WIDTH) ||
                          (visible_height > MAX_VISIBLE_HEIGHT);
        m_axis_valid   <= 1'b0;
        m_axis_last    <= 1'b0;
        pending_output_q <= 1'b0;
        resume_input_q <= 1'b0;
        frame_clear_q <= 1'b0;
        chroma_tu_quant_pending_q <= 1'b0;
        chroma_tu_quant_frame_last_q <= 1'b0;
        chroma_quant_tu_q <= 6'd0;
        chroma_quant_active_q <= 1'b0;
        luma_quant_tu_q <= 6'd0;
        luma_quant_active_q <= 1'b0;
        luma_tu_quant_pending_q <= 1'b0;
        luma_sample_tu_q <= '0;
        cb_sample_tu_q <= '0;
        cr_sample_tu_q <= '0;
        for (luma_ref_i = 0; luma_ref_i < VVC_LUMA_TU_COLS; luma_ref_i = luma_ref_i + 1) begin
          luma_top_ref_row_q[luma_ref_i] <= {VVC_LUMA_TU_SIZE{8'd128}};
          luma_left_ref_col_q[luma_ref_i] <= {VVC_LUMA_TU_SIZE{8'd128}};
          chroma_cb_top_ref_row_q[luma_ref_i] <= {VVC_CHROMA_TU_SIZE{8'd128}};
          chroma_cb_left_ref_col_q[luma_ref_i] <= {VVC_CHROMA_TU_SIZE{8'd128}};
          chroma_cr_top_ref_row_q[luma_ref_i] <= {VVC_CHROMA_TU_SIZE{8'd128}};
          chroma_cr_left_ref_col_q[luma_ref_i] <= {VVC_CHROMA_TU_SIZE{8'd128}};
        end
        frame_index_q <= 64'd0;
        generated_out_state_q <= GENERATED_OUT_IDLE;
        generated_slice_cra_q <= 1'b0;
        generated_header_start_q <= 1'b0;
        generated_picture_header_start_q <= 1'b0;
        current_slice_q <= 16'd0;
        current_ctu_x_q <= 16'd0;
        current_ctu_y_q <= 16'd0;
        cabac_input_valid_q <= 1'b0;
        cabac_input_kind_q <= 8'd0;
        cabac_input_data_q <= 32'd0;
        cabac_input_last_q <= 1'b0;
        palette_mux_state_q <= PALETTE_MUX_PARTITION;
        palette_current_pred_ibc_ctx_q <= 3'd0;
        palette_current_leaf_index_q <= 6'd0;
        ctu_cu_runtime_ibc_mask_q <= '0;
      end else if (resume_input_q) begin
        resume_input_q <= 1'b0;
        input_active_q <= 1'b1;
        s_axis_ready <= 1'b1;
        input_count_q <= '0;
        input_len_q <= input_len_w;
        input_stream_leaf_q <= 7'd0;
        input_stream_component_q <= 2'd0;
        input_stream_sample_q <= 6'd0;
        chroma_tu_quant_pending_q <= 1'b0;
        chroma_tu_quant_frame_last_q <= 1'b0;
        chroma_quant_tu_q <= 6'd0;
        chroma_quant_active_q <= 1'b0;
        luma_quant_tu_q <= 6'd0;
        luma_quant_active_q <= 1'b0;
        luma_tu_quant_pending_q <= 1'b0;
        luma_sample_tu_q <= '0;
        cb_sample_tu_q <= '0;
        cr_sample_tu_q <= '0;
        for (luma_ref_i = 0; luma_ref_i < VVC_LUMA_TU_COLS; luma_ref_i = luma_ref_i + 1) begin
          luma_top_ref_row_q[luma_ref_i] <= {VVC_LUMA_TU_SIZE{8'd128}};
          luma_left_ref_col_q[luma_ref_i] <= {VVC_LUMA_TU_SIZE{8'd128}};
          chroma_cb_top_ref_row_q[luma_ref_i] <= {VVC_CHROMA_TU_SIZE{8'd128}};
          chroma_cb_left_ref_col_q[luma_ref_i] <= {VVC_CHROMA_TU_SIZE{8'd128}};
          chroma_cr_top_ref_row_q[luma_ref_i] <= {VVC_CHROMA_TU_SIZE{8'd128}};
          chroma_cr_left_ref_col_q[luma_ref_i] <= {VVC_CHROMA_TU_SIZE{8'd128}};
        end
        cabac_input_valid_q <= 1'b0;
        cabac_input_kind_q <= 8'd0;
        cabac_input_data_q <= 32'd0;
        cabac_input_last_q <= 1'b0;
        palette_mux_state_q <= PALETTE_MUX_PARTITION;
        palette_current_pred_ibc_ctx_q <= 3'd0;
        palette_current_leaf_index_q <= 6'd0;
        ctu_cu_runtime_ibc_mask_q <= '0;
      end else if (input_active_q && s_axis_valid && s_axis_ready) begin
        input_stream_leaf_q <= input_stream_leaf_next_w;
        input_stream_component_q <= input_stream_component_next_w;
        input_stream_sample_q <= input_stream_sample_next_w;
        if (s_axis_last != input_frame_last_w) begin
          input_error <= 1'b1;
        end
        if (input_luma_tu_sample_w) begin
          luma_sample_tu_q[residual_luma_sample_index_w * 8 +: 8] <=
            input_sample_8bit_w;
        end
        if ((chroma_format_idc == 2'd1) &&
            (input_stream_component_q == 2'd1) &&
            input_chroma_tu_sample_w) begin
          cb_sample_tu_q[input_chroma_tu_sample_index_w * 8 +: 8] <=
            input_sample_8bit_w;
        end
        if ((chroma_format_idc == 2'd1) &&
            (input_stream_component_q == 2'd2) &&
            input_chroma_tu_sample_w) begin
          cr_sample_tu_q[input_chroma_tu_sample_index_w * 8 +: 8] <=
            input_sample_8bit_w;
        end

        if (input_frame_last_w) begin
          input_active_q <= 1'b0;
          s_axis_ready   <= 1'b0;
          if (ctu_has_palette_cu) begin
            pending_output_q <= 1'b1;
          end else if (input_chroma_tu_last_cr_sample_w) begin
            chroma_tu_quant_pending_q <= 1'b1;
            chroma_tu_quant_frame_last_q <= 1'b1;
            chroma_quant_tu_q <= input_chroma_tu_index_w;
          end else begin
            pending_output_q <= 1'b1;
          end
          luma_quant_tu_q <= 6'd0;
        end else if (input_luma_tu_last_sample_w) begin
          input_active_q <= 1'b0;
          s_axis_ready <= 1'b0;
          luma_tu_quant_pending_q <= 1'b1;
          luma_quant_tu_q <= input_luma_tu_index_w;
          luma_quant_active_q <= 1'b0;
          input_count_q <= input_count_q + 1'b1;
        end else if (input_chroma_tu_last_cr_sample_w) begin
          input_active_q <= 1'b0;
          s_axis_ready <= 1'b0;
          chroma_tu_quant_pending_q <= 1'b1;
          chroma_tu_quant_frame_last_q <= 1'b0;
          chroma_quant_tu_q <= input_chroma_tu_index_w;
          input_count_q <= input_count_q + 1'b1;
        end else begin
          input_count_q <= input_count_q + 1'b1;
        end
      end else if (luma_tu_quant_pending_q) begin
        // H.266 8.4.5 reconstructed-neighbor prediction, H.266 7.3.11.10
        // transform_unit() residual payload generation, and H.266 8.7.3
        // inverse coefficient scaling are implemented in
        // ff_vvc_luma_quant_recon_8x8. This stage consumes one streamed 8x8
        // luma TU and keeps only reconstructed neighbour edges for the next TU.
        if (!luma_quant_active_q && !luma_quant_busy_w) begin
          luma_quant_start_q <= 1'b1;
          luma_quant_active_q <= 1'b1;
        end else if (luma_quant_done_w) begin
          quant_luma_rem_ctu_q[luma_quant_tu_q] <= luma_quant_abs_level_w;
          quant_luma_negative_ctu_q[luma_quant_tu_q] <= luma_quant_negative_w;
          quant_luma_ac_levels_ctu_q[luma_quant_tu_q] <= luma_quant_ac_levels_w;
          for (luma_ref_i = 0; luma_ref_i < VVC_LUMA_TU_SIZE; luma_ref_i = luma_ref_i + 1) begin
            luma_top_ref_row_q[luma_quant_tu_col_w][luma_ref_i * 8 +: 8] <=
              luma_quant_bottom_ref_w[luma_ref_i * 8 +: 8];
            luma_left_ref_col_q[luma_quant_tu_row_w][luma_ref_i * 8 +: 8] <=
              luma_quant_right_ref_w[luma_ref_i * 8 +: 8];
          end
          luma_quant_active_q <= 1'b0;
          luma_tu_quant_pending_q <= 1'b0;
          input_active_q <= 1'b1;
          s_axis_ready <= 1'b1;
        end
      end else if (chroma_tu_quant_pending_q) begin
        if (!chroma_quant_tu_valid_w) begin
          quant_cb_dc_level_ctu_q[chroma_quant_tu_q] <= 9'sd0;
          quant_cr_dc_level_ctu_q[chroma_quant_tu_q] <= 9'sd0;
          quant_cb_ac_levels_ctu_q[chroma_quant_tu_q] <= '0;
          quant_cr_ac_levels_ctu_q[chroma_quant_tu_q] <= '0;
          chroma_tu_quant_pending_q <= 1'b0;
          chroma_quant_active_q <= 1'b0;
          cb_sample_tu_q <= '0;
          cr_sample_tu_q <= '0;
          if (chroma_tu_quant_frame_last_q) begin
            chroma_tu_quant_frame_last_q <= 1'b0;
            pending_output_q <= 1'b1;
            luma_quant_tu_q <= 6'd0;
            luma_quant_active_q <= 1'b0;
          end else begin
            input_active_q <= 1'b1;
            s_axis_ready <= 1'b1;
          end
        end else if (!chroma_quant_active_q && !chroma_quant_busy_w) begin
          chroma_quant_start_q <= 1'b1;
          chroma_quant_active_q <= 1'b1;
        end else if (chroma_quant_done_w) begin
          quant_cb_dc_level_ctu_q[chroma_quant_tu_q] <= chroma_quant_cb_dc_level_w;
          quant_cr_dc_level_ctu_q[chroma_quant_tu_q] <= chroma_quant_cr_dc_level_w;
          quant_cb_ac_levels_ctu_q[chroma_quant_tu_q] <= chroma_quant_cb_ac_levels_w;
          quant_cr_ac_levels_ctu_q[chroma_quant_tu_q] <= chroma_quant_cr_ac_levels_w;
          for (luma_ref_i = 0; luma_ref_i < VVC_CHROMA_TU_SIZE; luma_ref_i = luma_ref_i + 1) begin
            chroma_cb_top_ref_row_q[chroma_quant_tu_col_w][luma_ref_i * 8 +: 8] <=
              chroma_quant_cb_bottom_ref_w[luma_ref_i * 8 +: 8];
            chroma_cr_top_ref_row_q[chroma_quant_tu_col_w][luma_ref_i * 8 +: 8] <=
              chroma_quant_cr_bottom_ref_w[luma_ref_i * 8 +: 8];
            chroma_cb_left_ref_col_q[chroma_quant_tu_row_w][luma_ref_i * 8 +: 8] <=
              chroma_quant_cb_right_ref_w[luma_ref_i * 8 +: 8];
            chroma_cr_left_ref_col_q[chroma_quant_tu_row_w][luma_ref_i * 8 +: 8] <=
              chroma_quant_cr_right_ref_w[luma_ref_i * 8 +: 8];
          end
          chroma_tu_quant_pending_q <= 1'b0;
          chroma_quant_active_q <= 1'b0;
          cb_sample_tu_q <= '0;
          cr_sample_tu_q <= '0;
          if (chroma_tu_quant_frame_last_q) begin
            chroma_tu_quant_frame_last_q <= 1'b0;
            pending_output_q <= 1'b1;
            luma_quant_tu_q <= 6'd0;
            luma_quant_active_q <= 1'b0;
          end else begin
            input_active_q <= 1'b1;
            s_axis_ready <= 1'b1;
          end
        end
      end else if (pending_output_q &&
                   (!ctu_has_palette_cu || ibc_matcher_idle) &&
                   (generated_out_state_q == GENERATED_OUT_IDLE)) begin
        pending_output_q <= 1'b0;
        generated_slice_cra_q <= frame_index_q != 64'd0;
        if ((frame_index_q == 64'd0) && (current_slice_q == 16'd0)) begin
          generated_out_state_q <= GENERATED_OUT_PREAMBLE;
          generated_header_start_q <= 1'b1;
        end else if (multi_slice_picture_w && (current_slice_q == 16'd0)) begin
          generated_out_state_q <= GENERATED_OUT_PICTURE_HEADER;
          generated_picture_header_start_q <= 1'b1;
        end else begin
          generated_out_state_q <= GENERATED_OUT_SLICE_START;
        end
        m_axis_valid <= 1'b0;
        m_axis_data <= 8'd0;
        m_axis_last <= 1'b0;
      end
      if (cabac_start_q) begin
        cabac_input_valid_q <= 1'b0;
        cabac_input_kind_q <= 8'd0;
        cabac_input_data_q <= 32'd0;
        cabac_input_last_q <= 1'b0;
        palette_mux_state_q <= PALETTE_MUX_PARTITION;
        palette_current_pred_ibc_ctx_q <= 3'd0;
      end else if (cabac_input_valid_q && cabac_symbol_ready) begin
        cabac_input_valid_q <= 1'b0;
      end else if (!cabac_input_valid_q && source_symbol_valid && source_symbol_ready) begin
        cabac_input_valid_q <= 1'b1;
        cabac_input_kind_q <= source_symbol_kind;
        cabac_input_data_q <= source_symbol_data;
        cabac_input_last_q <= source_symbol_last;
      end
      if (ctu_has_palette_cu && !cabac_start_q &&
          (generated_out_state_q == GENERATED_OUT_CABAC)) begin
        if ((palette_mux_state_q == PALETTE_MUX_PARTITION) &&
            ctu_symbol_valid && ctu_symbol_ready &&
            (ctu_symbol_kind == SYMBOL_PALETTE_LEAF) && !palette_leaf_is_ibc_w) begin
          palette_mux_state_q <= PALETTE_MUX_CU;
          palette_current_pred_ibc_ctx_q <= palette_leaf_ibc_ctx_w;
          palette_current_leaf_index_q <= palette_leaf_index_w;
        end else if ((palette_mux_state_q == PALETTE_MUX_CU) &&
                     palette_stream_valid && palette_stream_ready &&
                     palette_stream_cu_last) begin
          palette_mux_state_q <= PALETTE_MUX_PARTITION;
          if (palette_stream_cu_ibc_mode) begin
            ctu_cu_runtime_ibc_mask_q[palette_current_leaf_index_q] <= 1'b1;
          end
        end
      end
      if ((generated_out_state_q != GENERATED_OUT_IDLE) &&
          (!m_axis_valid || m_axis_ready)) begin
        case (generated_out_state_q)
          GENERATED_OUT_PREAMBLE: begin
            if (generated_header_valid_w) begin
              m_axis_valid <= 1'b1;
              m_axis_data <= generated_header_byte_w;
              m_axis_last <= 1'b0;
              if (generated_header_last_w && generated_header_ready_w) begin
                if (multi_slice_picture_w) begin
                  generated_picture_header_start_q <= 1'b1;
                  generated_out_state_q <= GENERATED_OUT_PICTURE_HEADER;
                end else begin
                  cabac_start_q <= 1'b1;
                  generated_out_state_q <= GENERATED_OUT_CABAC;
                end
              end
            end else if (generated_header_done_w) begin
              m_axis_valid <= 1'b0;
              m_axis_last <= 1'b0;
              if (multi_slice_picture_w) begin
                generated_picture_header_start_q <= 1'b1;
                generated_out_state_q <= GENERATED_OUT_PICTURE_HEADER;
              end else begin
                cabac_start_q <= 1'b1;
                generated_out_state_q <= GENERATED_OUT_CABAC;
              end
            end else begin
              m_axis_valid <= 1'b0;
              m_axis_last <= 1'b0;
            end
          end
          GENERATED_OUT_PICTURE_HEADER: begin
            if (picture_header_valid_w) begin
              m_axis_valid <= 1'b1;
              m_axis_data <= picture_header_byte_w;
              m_axis_last <= 1'b0;
              if (picture_header_last_w && picture_header_ready_w) begin
                cabac_start_q <= 1'b1;
                generated_out_state_q <= GENERATED_OUT_CABAC;
              end
            end else if (picture_header_done_w) begin
              m_axis_valid <= 1'b0;
              m_axis_last <= 1'b0;
              cabac_start_q <= 1'b1;
              generated_out_state_q <= GENERATED_OUT_CABAC;
            end else begin
              m_axis_valid <= 1'b0;
              m_axis_last <= 1'b0;
            end
          end
          GENERATED_OUT_SLICE_START: begin
            m_axis_valid <= 1'b0;
            m_axis_last <= 1'b0;
            cabac_start_q <= 1'b1;
            generated_out_state_q <= GENERATED_OUT_CABAC;
          end

          GENERATED_OUT_CABAC: begin
            if (slice_stream_valid) begin
              m_axis_valid <= 1'b1;
              m_axis_data <= slice_stream_data;
              m_axis_last <= slice_stream_last && current_slice_last_w;
              if (slice_stream_last) begin
                generated_out_state_q <= GENERATED_OUT_IDLE;
                frame_clear_q <= 1'b1;
                resume_input_q <= 1'b1;
                if (current_slice_last_w) begin
                  // VPS/SPS/PPS are emitted once. Multi-CTU pictures emit a
                  // standalone picture header followed by one CTU slice per
                  // tile, matching the Rust one-slice-per-CTU model.
                  frame_index_q <= frame_index_q + 64'd1;
                  current_slice_q <= 16'd0;
                  current_ctu_x_q <= 16'd0;
                  current_ctu_y_q <= 16'd0;
                end else begin
                  current_slice_q <= current_slice_q + 16'd1;
                  if ((current_ctu_x_q + 16'd1) >= ctu_cols_w) begin
                    current_ctu_x_q <= 16'd0;
                    current_ctu_y_q <= current_ctu_y_q + 16'd1;
                  end else begin
                    current_ctu_x_q <= current_ctu_x_q + 16'd1;
                  end
                end
              end
            end else begin
              m_axis_valid <= 1'b0;
              m_axis_last <= 1'b0;
            end
          end
          default: begin
            generated_out_state_q <= GENERATED_OUT_IDLE;
          end
        endcase
      end
    end
  end

endmodule
