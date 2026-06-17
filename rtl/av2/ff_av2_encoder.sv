`timescale 1ns/1ps

module ff_av2_encoder #(
  parameter int MAX_VISIBLE_WIDTH = 1024,
  parameter int MAX_VISIBLE_HEIGHT = 1024,
  // TODO(av2): revisit this shared integration name once AV2 block/superblock
  // terminology is finalized in the implementation.
  parameter int CTU_SIZE = 64,
  parameter int SAMPLE_BITS = 8,
  parameter int SOURCE_SAMPLE_BITS = SAMPLE_BITS,
  parameter int SUPPORT_PALETTE_444 = 1,
  parameter int SUPPORT_EXACT_HASH_IBC_444 = 1,
  // TODO(av2): replace this staged carry/tile buffer with a streaming carry
  // resolver. Lossless high-colour 64x64 4:4:4 vectors need about 20 KiB
  // today, while larger future pictures must not scale this buffer by frame.
  parameter int AV2_MAX_TILE_BYTES = 32768
) (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       start,
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,
  // Shared chroma format IDs: 1=4:2:0, 2=4:2:2, 3=4:4:4.
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

  localparam int AV2_MAX_SEQUENCE_BYTES = 16;
  localparam int AV2_MAX_CLOSED_HEADER_BYTES = 8;
  localparam int AV2_TILE_SIZE_BYTES = 4;
  typedef enum logic [4:0] {
    ST_IDLE,
    ST_TILE_START,
    ST_INPUT_READ,
    ST_SEQ_LOAD,
    ST_SEQ_WRITE,
    ST_LOAD_BLOCK,
    ST_PARTITION,
    ST_PALETTE_QUERY,
    ST_LEAF,
    ST_FINISH_INIT,
    ST_FINISH_PUSH,
    ST_CHROMA_FETCH,
    ST_CARRY_READ,
    ST_CARRY_WRITE,
    ST_PAYLOAD_PREFIX,
    ST_PAYLOAD_COPY_READ,
    ST_PAYLOAD_COPY_WRITE,
    ST_OUTPUT_PREP,
    ST_OUTPUT_PAYLOAD_READ,
    ST_OUTPUT_PAYLOAD_LOAD,
    ST_OUTPUT_VALID
  } state_t;

  localparam logic [1:0] PARTITION_NONE = 2'd0;
  localparam logic [1:0] PARTITION_HORZ = 2'd1;
  localparam logic [1:0] PARTITION_VERT = 2'd2;
  localparam logic [2:0] PHASE_INTRA = 3'd0;
  localparam logic [2:0] PHASE_PALETTE_HEADER = 3'd1;
  localparam logic [2:0] PHASE_PALETTE_MAP = 3'd2;
  localparam logic [2:0] PHASE_Y_COEFF = 3'd3;
  localparam logic [2:0] PHASE_U_COEFF = 3'd4;
  localparam logic [2:0] PHASE_V_COEFF = 3'd5;
  localparam logic [2:0] PHASE_INTRABC = 3'd6;
  localparam logic [1:0] LUMA_MODE_DC = 2'd0;
  localparam logic [1:0] LUMA_MODE_V = 2'd1;
  localparam logic [1:0] LUMA_MODE_H = 2'd2;
  localparam int AV2_STACK_DEPTH = 16;
  localparam int AV2_PARTITION_CONTEXT_DIM = 16;

  state_t state_q;
  logic start_invalid_w;
  logic [15:0] precarry_mem_q [0:AV2_MAX_TILE_BYTES - 1];
  logic [7:0] payload_mem_q [0:AV2_MAX_TILE_BYTES - 1];
  logic [7:0] seq_mem_q [0:AV2_MAX_SEQUENCE_BYTES - 1];
  logic [15:0] precarry_read_addr_q;
  logic [15:0] precarry_read_data_q;
  logic precarry_write_valid_w;
  logic [15:0] precarry_write_addr_w;
  logic [15:0] precarry_write_data_w;
  logic pending_push_valid_q;
  logic [15:0] pending_push_word_q;
  logic [15:0] precarry_len_q;
  logic [15:0] tile_len_q;
  logic [15:0] payload_len_q;
  logic [15:0] payload_copy_index_q;
  logic [1:0] payload_prefix_index_q;
  logic [15:0] seq_len_q;
  logic [15:0] stream_index_q;
  logic [15:0] width_q;
  logic [15:0] height_q;
  logic [4:0] width_bits_q;
  logic [4:0] height_bits_q;
  logic [15:0] tile_cols_q;
  logic [15:0] tile_rows_q;
  logic [15:0] tile_count_q;
  logic [15:0] tile_index_q;
  logic [15:0] tile_col_q;
  logic [15:0] tile_row_q;
  logic [15:0] tile_width_q;
  logic [15:0] tile_height_q;
  logic [31:0] tile_input_index_q;
  logic frame_palette_mode_q;
  logic [7:0] seq_op_q;
  logic [6:0] seq_bits_left_q;
  logic [63:0] seq_value_q;
  logic [15:0] seq_bit_pos_q;
  logic [63:0] low_q;
  logic [31:0] rng_q;
  integer cnt_q;
  logic [2:0] phase_q;
  logic [6:0] step_q;
  logic [5:0] palette_row_q;
  logic [5:0] palette_col_q;
  logic [1:0] palette_identity_row_ctx_q;
  logic palette_mode_q;
  logic [1:0] leaf_luma_mode_q;
  logic [15:0] txb_index_q;
  logic [15:0] txb_width_q;
  logic [15:0] txb_count_q;
  logic [4:0] txb_local_row_q;
  logic [4:0] txb_local_col_q;
  logic [4:0] visible_rows_mi_q;
  logic [4:0] visible_cols_mi_q;
  logic [4:0] block_row_mi_q;
  logic [4:0] block_col_mi_q;
  logic [4:0] block_w_mi_q;
  logic [4:0] block_h_mi_q;
  logic [1:0] partition_q;
  logic partition_emit_step_q;
  logic [4:0] stack_sp_q;
  logic [4:0] stack_row_mi_q [0:AV2_STACK_DEPTH - 1];
  logic [4:0] stack_col_mi_q [0:AV2_STACK_DEPTH - 1];
  logic [4:0] stack_w_mi_q [0:AV2_STACK_DEPTH - 1];
  logic [4:0] stack_h_mi_q [0:AV2_STACK_DEPTH - 1];
  logic [7:0] partition_above_q [0:AV2_PARTITION_CONTEXT_DIM - 1];
  logic [7:0] partition_left_q [0:AV2_PARTITION_CONTEXT_DIM - 1];
  logic [63:0] finish_e_q;
  integer finish_c_q;
  integer finish_s_q;
  logic [15:0] carry_q;
  logic [15:0] carry_index_q;
  integer context_index_q;
  logic [7:0] y_txb_above_q [0:AV2_PARTITION_CONTEXT_DIM - 1];
  logic [7:0] y_txb_left_q [0:AV2_PARTITION_CONTEXT_DIM - 1];
  logic [7:0] u_txb_above_q [0:AV2_PARTITION_CONTEXT_DIM - 1];
  logic [7:0] u_txb_left_q [0:AV2_PARTITION_CONTEXT_DIM - 1];
  logic [7:0] v_txb_above_q [0:AV2_PARTITION_CONTEXT_DIM - 1];
  logic [7:0] v_txb_left_q [0:AV2_PARTITION_CONTEXT_DIM - 1];
  logic ibc_above_q [0:AV2_PARTITION_CONTEXT_DIM - 1];
  logic ibc_left_q [0:AV2_PARTITION_CONTEXT_DIM - 1];
  logic skip_above_q [0:AV2_PARTITION_CONTEXT_DIM - 1];
  logic skip_left_q [0:AV2_PARTITION_CONTEXT_DIM - 1];
  logic last_u_txb_nonzero_q;

  logic        op_valid_w;
  logic        op_last_w;
  logic [1:0] norm_push_count_w;
  logic [15:0] norm_push0_w;
  logic [15:0] norm_push1_w;
  logic [63:0] norm_low_w;
  logic [31:0] norm_rng_w;
  integer norm_cnt_w;
  logic [63:0] seq_load_value_w;
  logic [6:0] seq_load_bits_w;
  logic [4:0] width_bits_w;
  logic [4:0] height_bits_w;
  logic [15:0] tile_cols_w;
  logic [15:0] tile_rows_w;
  logic [15:0] tile_width_w;
  logic [15:0] tile_height_w;
  logic [31:0] tile_samples_w;
  logic tile_input_last_w;
  logic tile_is_last_w;
  logic multi_tile_w;
  logic frame_ibc_mode_q;
  logic ibc_done_w;
  logic ibc_any_left_copy_w;
  logic [63:0] ibc_left_copy_mask_w;
  logic [5:0] ibc_current_block_id_w;
  logic ibc_use_left_copy_w;
  logic [1:0] intrabc_ctx_w;
  logic [1:0] intrabc_skip_ctx_w;
  logic [2:0] tile_log2_cols_w;
  logic [2:0] tile_log2_rows_w;
  logic [5:0] closed_header_bit_count_w;
  logic [3:0] closed_header_len_w;
  logic [63:0] closed_header_bits_w;
  logic [7:0] closed_header_byte_w;
  logic [2:0] closed_header_index_w;
  logic [15:0] payload_prefix_value_w;
  logic [7:0] payload_prefix_byte_w;
  integer closed_bit_index_w;
  integer closed_loop_index_w;
  logic [15:0] closed_len_w;
  logic [1:0] closed_leb_len_w;
  logic [15:0] seq_end_index_w;
  logic [15:0] closed_leb_start_w;
  logic [15:0] closed_header_start_w;
  logic [15:0] total_stream_len_w;
  logic [15:0] tile_payload_start_w;
  logic [15:0] tile_stream_index_w;
  logic [15:0] closed_header_payload_index_w;
  logic [15:0] seq_stream_index_w;
  logic [15:0] closed_leb_index_w;
  logic [7:0] output_byte_w;
  logic [7:0] output_byte_q;
  logic output_last_q;
  logic output_tile_payload_w;
  logic [15:0] carry_sum_w;
  logic leaf_fsc_symbol_w;
  logic [31:0] leaf_fsc_fh_w;
  logic [15:0] txb_width_w;
  logic [15:0] txb_count_w;
  logic [15:0] txb_row_w;
  logic [15:0] txb_col_w;
  logic palette_analyzer_start_w;
  logic input_sample_fire_w;
  logic palette_analyzer_sample_ready_w;
  logic palette_analyzer_done_w;
  logic palette_analyzer_unsupported_w;
  logic palette_analyzer_black_w;
  logic palette_analyzer_luma_mode_w;
  logic palette_query_start_w;
  logic palette_query_done_w;
  logic [3:0] palette_size_w;
  logic [4:0] palette_cache_size_w;
  logic [63:0] palette_colors_w;
  logic [1:0] palette_luma_mode_w;
  logic leaf_luma_palette_w;
  logic [2:0] palette_current_index_w;
  logic [2:0] palette_left_index_w;
  logic [2:0] palette_top_index_w;
  logic [2:0] palette_top_left_index_w;
  logic [1:0] palette_identity_row_flag_w;
  logic palette_op_valid_w;
  logic palette_op_literal_w;
  logic [31:0] palette_op_literal_value_w;
  logic [4:0] palette_op_literal_bits_w;
  logic [31:0] palette_op_fl_w;
  logic [31:0] palette_op_fh_w;
  logic [4:0] palette_op_fl_inc_w;
  logic [4:0] palette_op_fh_inc_w;
  logic palette_header_last_step_w;
  logic palette_map_token_required_w;
  logic [31:0] y_txb_nonzero_fh_w;
  logic [31:0] u_txb_nonzero_fh_w;
  logic [31:0] v_txb_nonzero_fh_w;
  logic [31:0] y_dc_sign_fl_w;
  logic chroma_fetch_start_w;
  logic luma_fetch_start_w;
  logic chroma_fetch_done_w;
  logic luma_fetch_done_w;
  logic [127:0] chroma_fetch_txb_samples_w;
  logic [31:0] chroma_fetch_predictor_samples_w;
  logic [127:0] luma_fetch_txb_samples_w;
  logic [127:0] luma_fetch_predictor_samples_w;
  logic [3:0] luma_residual_skip_ctx_w;
  logic [1:0] luma_residual_dc_sign_ctx_w;
  logic [2:0] luma_residual_top_level_w;
  logic [2:0] luma_residual_left_level_w;
  logic signed [3:0] luma_residual_top_sign_w;
  logic signed [3:0] luma_residual_left_sign_w;
  logic signed [5:0] luma_residual_sign_sum_w;
  logic luma_residual_op_valid_w;
  logic luma_residual_op_literal_w;
  logic [31:0] luma_residual_op_literal_value_w;
  logic [4:0] luma_residual_op_literal_bits_w;
  logic [31:0] luma_residual_op_fl_w;
  logic [31:0] luma_residual_op_fh_w;
  logic [4:0] luma_residual_op_fl_inc_w;
  logic [4:0] luma_residual_op_fh_inc_w;
  logic luma_residual_advance_w;
  logic luma_residual_txb_done_w;
  logic [7:0] luma_residual_entropy_context_w;
  logic [3:0] chroma_bdpcm_skip_ctx_w;
  logic chroma_bdpcm_op_valid_w;
  logic chroma_bdpcm_op_literal_w;
  logic [31:0] chroma_bdpcm_op_literal_value_w;
  logic [4:0] chroma_bdpcm_op_literal_bits_w;
  logic [31:0] chroma_bdpcm_op_fl_w;
  logic [31:0] chroma_bdpcm_op_fh_w;
  logic [4:0] chroma_bdpcm_op_fl_inc_w;
  logic [4:0] chroma_bdpcm_op_fh_inc_w;
  logic chroma_bdpcm_advance_w;
  logic chroma_bdpcm_txb_done_w;
  logic chroma_bdpcm_txb_nonzero_w;
  logic [7:0] chroma_bdpcm_entropy_context_w;
  logic [4:0] visible_rows_mi_w;
  logic [4:0] visible_cols_mi_w;
  logic block_visible_w;
  logic block_partition_point_w;
  logic block_square_w;
  logic block_tall_w;
  logic [4:0] block_half_w_mi_w;
  logic [4:0] block_half_h_mi_w;
  logic [4:0] block_quarter_w_mi_w;
  logic [4:0] block_quarter_h_mi_w;
  logic has_rows_w;
  logic has_cols_w;
  logic sub_has_rows_w;
  logic sub_has_cols_w;
  logic rect_implied_horz_w;
  logic rect_implied_vert_w;
  logic aspect_none_w;
  logic aspect_horz_w;
  logic aspect_vert_w;
  logic [8:0] block_w_mi_ext_w;
  logic [8:0] block_h_mi_ext_w;
  logic [8:0] block_half_w_mi_ext_w;
  logic [8:0] block_half_h_mi_ext_w;
  logic allowed_none_pre_w;
  logic allowed_horz_pre_w;
  logic allowed_vert_pre_w;
  logic allowed_none_w;
  logic allowed_horz_w;
  logic allowed_vert_w;
  logic allowed_any_w;
  logic allowed_only_w;
  logic forced_valid_w;
  logic [1:0] forced_partition_w;
  logic palette_preferred_valid_w;
  logic [1:0] palette_preferred_partition_w;
  logic preferred_valid_w;
  logic [1:0] preferred_partition_w;
  logic [1:0] chosen_partition_w;
  logic chosen_do_split_w;
  logic partition_forced_implied_w;
  logic partition_need_do_split_w;
  logic partition_need_rect_w;
  logic partition_emit_do_split_w;
  logic partition_emit_rect_w;
  logic partition_emit_done_w;
  logic [5:0] partition_split_ctx_w;
  logic [5:0] partition_rect_ctx_w;
  logic [1:0] partition_raw_ctx_w;
  logic [1:0] partition_above_shift_w;
  logic [1:0] partition_left_shift_w;
  logic [7:0] partition_above_ctx_w;
  logic [7:0] partition_left_ctx_w;
  logic partition_above_bit_w;
  logic partition_left_bit_w;
  logic [3:0] bsize_map_w;
  logic [3:0] bsize_rect_map_w;
  logic [31:0] partition_do_cdf0_w;
  logic [31:0] partition_rect_cdf0_w;
  logic [7:0] partition_update_above_w;
  logic [7:0] partition_update_left_w;
  logic [4:0] leaf_visible_txb_w_w;
  logic [4:0] leaf_visible_txb_h_w;

  ff_av2_partition_cdf_lut partition_cdf_lut (
    .split_ctx(partition_split_ctx_w),
    .rect_ctx(partition_rect_ctx_w),
    .do_split_cdf0(partition_do_cdf0_w),
    .rect_type_cdf0(partition_rect_cdf0_w)
  );

  ff_av2_left_hash_matcher_444 #(
    .SAMPLE_BITS(SAMPLE_BITS),
    .SUPPORT_EXACT_HASH_IBC_444(SUPPORT_EXACT_HASH_IBC_444)
  ) left_hash_ibc (
    .clk(clk),
    .rst_n(rst_n),
    .start(palette_analyzer_start_w),
    .sample_fire(input_sample_fire_w),
    .visible_width(tile_width_q),
    .visible_height(tile_height_q),
    .sample(s_axis_data),
    .sample_last(tile_input_last_w),
    .done(ibc_done_w),
    .any_left_copy(ibc_any_left_copy_w),
    .left_copy_mask(ibc_left_copy_mask_w)
  );

  ff_av2_palette_analyzer_444 #(
    .SAMPLE_BITS(SAMPLE_BITS),
    .SUPPORT_PALETTE_444(SUPPORT_PALETTE_444)
  ) palette_analyzer (
    .clk(clk),
    .rst_n(rst_n),
    .start(palette_analyzer_start_w),
    .sample_fire(input_sample_fire_w),
    .visible_width(tile_width_q),
    .visible_height(tile_height_q),
    .sample(s_axis_data),
    .sample_last(tile_input_last_w),
    .sample_ready(palette_analyzer_sample_ready_w),
    .query_block_row_mi(block_row_mi_q),
    .query_block_col_mi(block_col_mi_q),
    .query_row(palette_row_q),
    .query_col(palette_col_q),
    .query_start(palette_query_start_w),
    .chroma_fetch_start(chroma_fetch_start_w),
    .chroma_fetch_plane_v(phase_q == PHASE_V_COEFF),
    .chroma_fetch_txb_row_mi(txb_row_w[4:0]),
    .chroma_fetch_txb_col_mi(txb_col_w[4:0]),
    .luma_fetch_start(luma_fetch_start_w),
    .luma_fetch_txb_row_mi(txb_row_w[4:0]),
    .luma_fetch_txb_col_mi(txb_col_w[4:0]),
    .done(palette_analyzer_done_w),
    .unsupported(palette_analyzer_unsupported_w),
    .black_mode(palette_analyzer_black_w),
    .luma_palette_mode(palette_analyzer_luma_mode_w),
    .query_done(palette_query_done_w),
    .palette_size(palette_size_w),
    .palette_cache_size(palette_cache_size_w),
    .palette_colors(palette_colors_w),
    .query_luma_mode(palette_luma_mode_w),
    .query_index(palette_current_index_w),
    .query_left_index(palette_left_index_w),
    .query_top_index(palette_top_index_w),
    .query_top_left_index(palette_top_left_index_w),
    .query_identity_row_flag(palette_identity_row_flag_w),
    .chroma_fetch_done(chroma_fetch_done_w),
    .chroma_fetch_txb_samples(chroma_fetch_txb_samples_w),
    .chroma_fetch_predictor_samples(chroma_fetch_predictor_samples_w),
    .luma_fetch_done(luma_fetch_done_w),
    .luma_fetch_txb_samples(luma_fetch_txb_samples_w),
    .luma_fetch_predictor_samples(luma_fetch_predictor_samples_w)
  );

  ff_av2_luma_palette_symbolizer luma_palette_symbolizer (
    .enable(leaf_luma_palette_w),
    .phase(phase_q),
    .step(step_q[4:0]),
    .row(palette_row_q),
    .col(palette_col_q),
    .palette_size(palette_size_w),
    .palette_cache_size(palette_cache_size_w),
    .palette_colors(palette_colors_w),
    .current_index(palette_current_index_w),
    .left_index(palette_left_index_w),
    .top_index(palette_top_index_w),
    .top_left_index(palette_top_left_index_w),
    .identity_row_flag(palette_identity_row_flag_w),
    .identity_row_ctx(palette_identity_row_ctx_q),
    .op_valid(palette_op_valid_w),
    .op_literal(palette_op_literal_w),
    .op_literal_value(palette_op_literal_value_w),
    .op_literal_bits(palette_op_literal_bits_w),
    .op_fl(palette_op_fl_w),
    .op_fh(palette_op_fh_w),
    .op_fl_inc(palette_op_fl_inc_w),
    .op_fh_inc(palette_op_fh_inc_w),
    .header_last_step(palette_header_last_step_w),
    .map_token_required(palette_map_token_required_w)
  );

  ff_av2_chroma_bdpcm_symbolizer #(
    .LUMA_PALETTE_RESIDUAL(1)
  ) luma_palette_residual_symbolizer (
    .clk(clk),
    .rst_n(rst_n),
    .enable(palette_mode_q &&
            (state_q == ST_LEAF) &&
            (phase_q == PHASE_Y_COEFF)),
    .advance(luma_residual_advance_w),
    .plane_v(1'b0),
    .skip_ctx(luma_residual_skip_ctx_w),
    .dc_sign_ctx(luma_residual_dc_sign_ctx_w),
    .txb_samples(luma_fetch_txb_samples_w),
    .predictor_samples(32'd0),
    .predictor_txb_samples(luma_fetch_predictor_samples_w),
    .op_valid(luma_residual_op_valid_w),
    .op_literal(luma_residual_op_literal_w),
    .op_literal_value(luma_residual_op_literal_value_w),
    .op_literal_bits(luma_residual_op_literal_bits_w),
    .op_fl(luma_residual_op_fl_w),
    .op_fh(luma_residual_op_fh_w),
    .op_fl_inc(luma_residual_op_fl_inc_w),
    .op_fh_inc(luma_residual_op_fh_inc_w),
    .txb_done(luma_residual_txb_done_w),
    .txb_nonzero(),
    .entropy_context(luma_residual_entropy_context_w)
  );

  ff_av2_chroma_bdpcm_symbolizer #(
    .LUMA_PALETTE_RESIDUAL(0)
  ) chroma_bdpcm_symbolizer (
    .clk(clk),
    .rst_n(rst_n),
    .enable(palette_mode_q &&
            (state_q == ST_LEAF) &&
            (phase_q == PHASE_U_COEFF || phase_q == PHASE_V_COEFF)),
    .advance(chroma_bdpcm_advance_w),
    .plane_v(phase_q == PHASE_V_COEFF),
    .skip_ctx(chroma_bdpcm_skip_ctx_w),
    .dc_sign_ctx(2'd0),
    .txb_samples(chroma_fetch_txb_samples_w),
    .predictor_samples(chroma_fetch_predictor_samples_w),
    .predictor_txb_samples(128'd0),
    .op_valid(chroma_bdpcm_op_valid_w),
    .op_literal(chroma_bdpcm_op_literal_w),
    .op_literal_value(chroma_bdpcm_op_literal_value_w),
    .op_literal_bits(chroma_bdpcm_op_literal_bits_w),
    .op_fl(chroma_bdpcm_op_fl_w),
    .op_fh(chroma_bdpcm_op_fh_w),
    .op_fl_inc(chroma_bdpcm_op_fl_inc_w),
    .op_fh_inc(chroma_bdpcm_op_fh_inc_w),
    .txb_done(chroma_bdpcm_txb_done_w),
    .txb_nonzero(chroma_bdpcm_txb_nonzero_w),
    .entropy_context(chroma_bdpcm_entropy_context_w)
  );

  ff_av2_entropy_coder entropy_coder (
    .partition_active(state_q == ST_PARTITION),
    .leaf_active(state_q == ST_LEAF),
    .low(low_q),
    .rng(rng_q),
    .cnt(cnt_q),
    .phase(phase_q),
    .step(step_q),
    .partition(partition_q),
    .partition_emit_do_split(partition_emit_do_split_w),
    .partition_emit_rect(partition_emit_rect_w),
    .partition_do_cdf0(partition_do_cdf0_w),
    .partition_rect_cdf0(partition_rect_cdf0_w),
    .ibc_use_left_copy(ibc_use_left_copy_w),
    .intrabc_ctx(intrabc_ctx_w),
    .intrabc_skip_ctx(intrabc_skip_ctx_w),
    .leaf_luma_mode(leaf_luma_mode_q),
    .leaf_fsc_symbol(leaf_fsc_symbol_w),
    .leaf_fsc_fh(leaf_fsc_fh_w),
    .palette_mode(palette_mode_q),
    .leaf_luma_palette(leaf_luma_palette_w),
    .palette_op_valid(palette_op_valid_w),
    .palette_op_literal(palette_op_literal_w),
    .palette_op_literal_value(palette_op_literal_value_w),
    .palette_op_literal_bits(palette_op_literal_bits_w),
    .palette_op_fl(palette_op_fl_w),
    .palette_op_fh(palette_op_fh_w),
    .palette_op_fl_inc(palette_op_fl_inc_w),
    .palette_op_fh_inc(palette_op_fh_inc_w),
    .luma_residual_op_valid(luma_residual_op_valid_w),
    .luma_residual_op_literal(luma_residual_op_literal_w),
    .luma_residual_op_literal_value(luma_residual_op_literal_value_w),
    .luma_residual_op_literal_bits(luma_residual_op_literal_bits_w),
    .luma_residual_op_fl(luma_residual_op_fl_w),
    .luma_residual_op_fh(luma_residual_op_fh_w),
    .luma_residual_op_fl_inc(luma_residual_op_fl_inc_w),
    .luma_residual_op_fh_inc(luma_residual_op_fh_inc_w),
    .chroma_bdpcm_op_valid(chroma_bdpcm_op_valid_w),
    .chroma_bdpcm_op_literal(chroma_bdpcm_op_literal_w),
    .chroma_bdpcm_op_literal_value(chroma_bdpcm_op_literal_value_w),
    .chroma_bdpcm_op_literal_bits(chroma_bdpcm_op_literal_bits_w),
    .chroma_bdpcm_op_fl(chroma_bdpcm_op_fl_w),
    .chroma_bdpcm_op_fh(chroma_bdpcm_op_fh_w),
    .chroma_bdpcm_op_fl_inc(chroma_bdpcm_op_fl_inc_w),
    .chroma_bdpcm_op_fh_inc(chroma_bdpcm_op_fh_inc_w),
    .y_txb_nonzero_fh(y_txb_nonzero_fh_w),
    .u_txb_nonzero_fh(u_txb_nonzero_fh_w),
    .v_txb_nonzero_fh(v_txb_nonzero_fh_w),
    .y_dc_sign_fl(y_dc_sign_fl_w),
    .txb_index(txb_index_q),
    .txb_count(txb_count_q),
    .chroma_bdpcm_txb_done(chroma_bdpcm_txb_done_w),
    .stack_empty(stack_sp_q == 5'd0),
    .op_valid(op_valid_w),
    .op_last(op_last_w),
    .norm_push_count(norm_push_count_w),
    .norm_push0(norm_push0_w),
    .norm_push1(norm_push1_w),
    .norm_low(norm_low_w),
    .norm_rng(norm_rng_w),
    .norm_cnt(norm_cnt_w)
  );

  assign start_invalid_w =
    (chroma_format_idc != 2'd3) ||
    (visible_width == 16'd0) ||
    (visible_height == 16'd0) ||
    (visible_width[2:0] != 3'd0) ||
    (visible_height[2:0] != 3'd0);
  assign palette_analyzer_start_w = (state_q == ST_TILE_START);
  assign input_sample_fire_w = (state_q == ST_INPUT_READ) && s_axis_valid && s_axis_ready;
  assign tile_input_last_w = input_sample_fire_w && (tile_input_index_q == (tile_samples_w - 32'd1));
  assign palette_query_start_w = (state_q == ST_PALETTE_QUERY);
  assign leaf_luma_palette_w = palette_mode_q && (leaf_luma_mode_q == LUMA_MODE_DC);
  assign chroma_fetch_start_w =
    (state_q == ST_CHROMA_FETCH) &&
    (phase_q == PHASE_U_COEFF || phase_q == PHASE_V_COEFF);
  assign luma_fetch_start_w =
    (state_q == ST_CHROMA_FETCH) &&
    (phase_q == PHASE_Y_COEFF);
  assign luma_residual_advance_w =
    !start &&
    !pending_push_valid_q &&
    (state_q == ST_LEAF) &&
    palette_mode_q &&
    (phase_q == PHASE_Y_COEFF) &&
    luma_residual_op_valid_w;
  assign chroma_bdpcm_advance_w =
    !start &&
    !pending_push_valid_q &&
    (state_q == ST_LEAF) &&
    palette_mode_q &&
    (phase_q == PHASE_U_COEFF || phase_q == PHASE_V_COEFF) &&
    chroma_bdpcm_op_valid_w;

  // AV2 4:4:4 bring-up path: traverse one 64x64 superblock, split visible
  // coding leaves down to 8x8, and generate syntax through the range coder.
  // Any TX_4X4 loops below are AV2 transform blocks, not public input blocks.
  assign busy = (state_q != ST_IDLE);
  // AV2 bring-up input order is a visible 8x8 block packet: 64 Y samples,
  // 64 U samples, then 64 V samples. This mirrors the VVC 4:4:4 8x8-leaf
  // packing at the interface while allowing the AV2 superblock walker to keep
  // its own partition/leaf order internally.
  assign s_axis_ready =
    (state_q == ST_INPUT_READ) &&
    palette_analyzer_sample_ready_w &&
    !palette_analyzer_done_w;
  assign tile_cols_w = (visible_width + 16'd63) >> 6;
  assign tile_rows_w = (visible_height + 16'd63) >> 6;
  assign tile_width_w =
    (tile_col_q == (tile_cols_q - 16'd1)) ?
      (width_q - (tile_col_q << 6)) : 16'd64;
  assign tile_height_w =
    (tile_row_q == (tile_rows_q - 16'd1)) ?
      (height_q - (tile_row_q << 6)) : 16'd64;
  assign tile_samples_w = ({16'd0, tile_width_q} * {16'd0, tile_height_q}) * 32'd3;
  assign tile_is_last_w = (tile_index_q == (tile_count_q - 16'd1));
  assign multi_tile_w = (tile_count_q != 16'd1);
  assign payload_prefix_value_w = tile_len_q - 16'd1;
  assign payload_prefix_byte_w =
    (payload_prefix_index_q == 2'd0) ? payload_prefix_value_w[7:0] :
    (payload_prefix_index_q == 2'd1) ? payload_prefix_value_w[15:8] :
    8'd0;

  assign closed_len_w = {12'd0, closed_header_len_w} + 16'd1 + payload_len_q;
  // AV2 v1.0.0 Section 5.3 uses unsigned LEB128 for OBU payload lengths.
  // Lossless high-colour 64x64 4:4:4 tiles can exceed the two-byte LEB128
  // range, so keep the staged writer correct through the current 16-bit bound.
  assign closed_leb_len_w =
    (closed_len_w >= 16'd16384) ? 2'd3 :
    (closed_len_w >= 16'd128) ? 2'd2 : 2'd1;
  assign seq_end_index_w = 16'd4 + seq_len_q;
  assign closed_leb_start_w = seq_end_index_w;
  assign closed_header_start_w = closed_leb_start_w + {14'd0, closed_leb_len_w};
  assign total_stream_len_w =
    closed_header_start_w + 16'd1 + {12'd0, closed_header_len_w} + payload_len_q;
  assign tile_payload_start_w = closed_header_start_w + 16'd1 + {12'd0, closed_header_len_w};
  assign seq_stream_index_w = stream_index_q - 16'd4;
  assign closed_leb_index_w = stream_index_q - closed_leb_start_w;
  assign tile_stream_index_w = stream_index_q - tile_payload_start_w;
  assign closed_header_payload_index_w = stream_index_q - closed_header_start_w - 16'd1;
  assign closed_header_index_w = closed_header_payload_index_w[2:0];
  assign output_tile_payload_w = (stream_index_q >= tile_payload_start_w);
  assign carry_sum_w = carry_q + precarry_read_data_q;
  assign visible_rows_mi_w = tile_height_q[6:2];
  assign visible_cols_mi_w = tile_width_q[6:2];
  assign ibc_current_block_id_w = {block_row_mi_q[3:1], block_col_mi_q[3:1]};
  assign ibc_use_left_copy_w =
    frame_ibc_mode_q &&
    (block_w_mi_q == 5'd2) &&
    (block_h_mi_q == 5'd2) &&
    ibc_left_copy_mask_w[ibc_current_block_id_w];
  assign intrabc_ctx_w =
    {1'd0, ibc_above_q[block_col_mi_q]} + {1'd0, ibc_left_q[block_row_mi_q]};
  assign intrabc_skip_ctx_w =
    {1'd0, skip_above_q[block_col_mi_q]} + {1'd0, skip_left_q[block_row_mi_q]};
  assign block_visible_w =
    (block_row_mi_q < visible_rows_mi_q) &&
    (block_col_mi_q < visible_cols_mi_q);
  assign block_partition_point_w =
    !((block_w_mi_q == 5'd2 && block_h_mi_q == 5'd16) ||
      (block_w_mi_q == 5'd16 && block_h_mi_q == 5'd2));
  assign block_square_w = (block_w_mi_q == block_h_mi_q);
  assign block_tall_w = (block_h_mi_q > block_w_mi_q);
  assign block_half_w_mi_w = block_w_mi_q >> 1;
  assign block_half_h_mi_w = block_h_mi_q >> 1;
  assign block_quarter_w_mi_w = block_w_mi_q >> 2;
  assign block_quarter_h_mi_w = block_h_mi_q >> 2;
  assign block_w_mi_ext_w = {4'd0, block_w_mi_q};
  assign block_h_mi_ext_w = {4'd0, block_h_mi_q};
  assign block_half_w_mi_ext_w = {4'd0, block_half_w_mi_w};
  assign block_half_h_mi_ext_w = {4'd0, block_half_h_mi_w};
  assign has_rows_w = (block_row_mi_q + block_half_h_mi_w) < visible_rows_mi_q;
  assign has_cols_w = (block_col_mi_q + block_half_w_mi_w) < visible_cols_mi_q;
  assign sub_has_rows_w = (block_row_mi_q + block_quarter_h_mi_w) < visible_rows_mi_q;
  assign sub_has_cols_w = (block_col_mi_q + block_quarter_w_mi_w) < visible_cols_mi_q;
  assign rect_implied_horz_w =
    (block_w_mi_q == 5'd2 && block_h_mi_q == 5'd8) ||
    (block_w_mi_q == 5'd4 && block_h_mi_q == 5'd16) ||
    (block_w_mi_q == 5'd2 && block_h_mi_q == 5'd16);
  assign rect_implied_vert_w =
    (block_w_mi_q == 5'd8 && block_h_mi_q == 5'd2) ||
    (block_w_mi_q == 5'd16 && block_h_mi_q == 5'd4) ||
    (block_w_mi_q == 5'd16 && block_h_mi_q == 5'd2);
  assign aspect_none_w =
    !((block_w_mi_ext_w > (block_h_mi_ext_w << 3)) ||
      (block_h_mi_ext_w > (block_w_mi_ext_w << 3)));
  assign aspect_horz_w =
    !((block_w_mi_ext_w >= (block_half_h_mi_ext_w << 3)) ||
      (block_half_h_mi_ext_w >= (block_w_mi_ext_w << 3)));
  assign aspect_vert_w =
    !((block_half_w_mi_ext_w >= (block_h_mi_ext_w << 3)) ||
      (block_h_mi_ext_w >= (block_half_w_mi_ext_w << 3)));
  assign allowed_none_pre_w = has_rows_w && has_cols_w && aspect_none_w;
  assign allowed_horz_pre_w =
    (block_h_mi_q >= 5'd2) && !rect_implied_vert_w && aspect_horz_w;
  assign allowed_vert_pre_w =
    (block_w_mi_q >= 5'd2) && !rect_implied_horz_w && aspect_vert_w;
  assign allowed_any_w = allowed_none_pre_w || allowed_horz_pre_w || allowed_vert_pre_w;
  assign allowed_none_w = allowed_none_pre_w || !allowed_any_w;
  assign allowed_horz_w = allowed_horz_pre_w;
  assign allowed_vert_w = allowed_vert_pre_w;
  assign allowed_only_w =
    (allowed_none_w && !allowed_horz_w && !allowed_vert_w) ||
    (!allowed_none_w && allowed_horz_w && !allowed_vert_w) ||
    (!allowed_none_w && !allowed_horz_w && allowed_vert_w);
  assign preferred_valid_w =
    block_partition_point_w &&
    !((block_w_mi_q == 5'd2) && (block_h_mi_q == 5'd2)) &&
    (preferred_partition_w != PARTITION_NONE);
  assign preferred_partition_w =
    block_square_w ?
      ((block_h_mi_q > 5'd2 && allowed_horz_w) ? PARTITION_HORZ :
       (block_w_mi_q > 5'd2 && allowed_vert_w) ? PARTITION_VERT :
       PARTITION_NONE) :
    (block_w_mi_q > block_h_mi_q) ?
      ((block_w_mi_q > 5'd2 && allowed_vert_w) ? PARTITION_VERT :
       (block_h_mi_q > 5'd2 && allowed_horz_w) ? PARTITION_HORZ :
       PARTITION_NONE) :
      ((block_h_mi_q > 5'd2 && allowed_horz_w) ? PARTITION_HORZ :
       (block_w_mi_q > 5'd2 && allowed_vert_w) ? PARTITION_VERT :
       PARTITION_NONE);
  assign chosen_do_split_w = (partition_q != PARTITION_NONE);
  assign partition_forced_implied_w =
    forced_valid_w &&
    (forced_partition_w == partition_q) &&
    (((forced_partition_w == PARTITION_NONE) && allowed_none_w) ||
     ((forced_partition_w == PARTITION_HORZ) && allowed_horz_w) ||
     ((forced_partition_w == PARTITION_VERT) && allowed_vert_w));
  assign partition_need_do_split_w =
    !(partition_forced_implied_w || allowed_only_w) && allowed_none_w;
  assign partition_need_rect_w =
    !(partition_forced_implied_w || allowed_only_w) &&
    chosen_do_split_w &&
    allowed_horz_w &&
    allowed_vert_w &&
    !(rect_implied_horz_w || rect_implied_vert_w);
  assign partition_emit_do_split_w = !partition_emit_step_q && partition_need_do_split_w;
  assign partition_emit_rect_w =
    (!partition_emit_step_q && !partition_need_do_split_w && partition_need_rect_w) ||
    (partition_emit_step_q && partition_need_do_split_w && partition_need_rect_w);
  assign partition_emit_done_w =
    (!partition_need_do_split_w && !partition_need_rect_w) ||
    (partition_emit_step_q && partition_need_rect_w) ||
    (!partition_emit_step_q && partition_need_do_split_w && !partition_need_rect_w);
  assign partition_above_shift_w =
    (block_w_mi_q == 5'd2) ? 2'd0 :
    (block_w_mi_q == 5'd4) ? 2'd1 :
    (block_w_mi_q == 5'd8) ? 2'd2 : 2'd3;
  assign partition_left_shift_w =
    (block_h_mi_q == 5'd2) ? 2'd0 :
    (block_h_mi_q == 5'd4) ? 2'd1 :
    (block_h_mi_q == 5'd8) ? 2'd2 : 2'd3;
  assign partition_above_ctx_w = partition_above_q[block_col_mi_q];
  assign partition_left_ctx_w = partition_left_q[block_row_mi_q];
  assign partition_above_bit_w =
    (partition_above_shift_w == 2'd0) ? partition_above_ctx_w[0] :
    (partition_above_shift_w == 2'd1) ? partition_above_ctx_w[1] :
    (partition_above_shift_w == 2'd2) ? partition_above_ctx_w[2] :
                                        partition_above_ctx_w[3];
  assign partition_left_bit_w =
    (partition_left_shift_w == 2'd0) ? partition_left_ctx_w[0] :
    (partition_left_shift_w == 2'd1) ? partition_left_ctx_w[1] :
    (partition_left_shift_w == 2'd2) ? partition_left_ctx_w[2] :
                                       partition_left_ctx_w[3];
  assign partition_raw_ctx_w = {partition_left_bit_w, partition_above_bit_w};
  assign txb_width_w = {11'd0, leaf_visible_txb_w_w};
  assign txb_count_w = {11'd0, leaf_visible_txb_w_w} * {11'd0, leaf_visible_txb_h_w};
  assign txb_row_w = {11'd0, block_row_mi_q + txb_local_row_q};
  assign txb_col_w = {11'd0, block_col_mi_q + txb_local_col_q};
  assign luma_residual_top_level_w =
    ((y_txb_above_q[txb_col_w[4:0]] & 8'd7) > 8'd4) ?
      3'd4 : y_txb_above_q[txb_col_w[4:0]][2:0];
  assign luma_residual_left_level_w =
    ((y_txb_left_q[txb_row_w[4:0]] & 8'd7) > 8'd4) ?
      3'd4 : y_txb_left_q[txb_row_w[4:0]][2:0];
  assign luma_residual_skip_ctx_w =
    (luma_residual_top_level_w == 3'd0 && luma_residual_left_level_w == 3'd0) ? 4'd1 :
    ((luma_residual_top_level_w == 3'd0 && luma_residual_left_level_w <= 3'd2) ||
     (luma_residual_left_level_w == 3'd0 && luma_residual_top_level_w <= 3'd2) ||
     (luma_residual_top_level_w == 3'd1 && luma_residual_left_level_w == 3'd1)) ? 4'd2 :
    ((luma_residual_top_level_w == 3'd0) ||
     (luma_residual_left_level_w == 3'd0) ||
     (luma_residual_top_level_w == 3'd1 && luma_residual_left_level_w >= 3'd2 && luma_residual_left_level_w <= 3'd3) ||
     (luma_residual_left_level_w == 3'd1 && luma_residual_top_level_w >= 3'd2 && luma_residual_top_level_w <= 3'd3) ||
     (luma_residual_top_level_w == 3'd2 && luma_residual_left_level_w == 3'd2)) ? 4'd3 :
    (((luma_residual_top_level_w >= 3'd1 && luma_residual_top_level_w <= 3'd2) && luma_residual_left_level_w == 3'd4) ||
     ((luma_residual_left_level_w >= 3'd1 && luma_residual_left_level_w <= 3'd2) && luma_residual_top_level_w == 3'd4) ||
     ((luma_residual_top_level_w >= 3'd2 && luma_residual_top_level_w <= 3'd3) &&
      (luma_residual_left_level_w >= 3'd2 && luma_residual_left_level_w <= 3'd3))) ? 4'd4 : 4'd5;
  assign luma_residual_top_sign_w =
    (y_txb_above_q[txb_col_w[4:0]][4:3] == 2'd1) ? -4'sd1 :
    (y_txb_above_q[txb_col_w[4:0]][4:3] == 2'd2) ? 4'sd1 : 4'sd0;
  assign luma_residual_left_sign_w =
    (y_txb_left_q[txb_row_w[4:0]][4:3] == 2'd1) ? -4'sd1 :
    (y_txb_left_q[txb_row_w[4:0]][4:3] == 2'd2) ? 4'sd1 : 4'sd0;
  assign luma_residual_sign_sum_w = luma_residual_top_sign_w + luma_residual_left_sign_w;
  assign luma_residual_dc_sign_ctx_w =
    (luma_residual_sign_sum_w < 0) ? 2'd1 :
    (luma_residual_sign_sum_w > 0) ? 2'd2 : 2'd0;
  assign chroma_bdpcm_skip_ctx_w =
    (phase_q == PHASE_V_COEFF) ?
      (4'd3 +
       {3'd0, v_txb_above_q[txb_col_w[4:0]] != 8'd0} +
       {3'd0, v_txb_left_q[txb_row_w[4:0]] != 8'd0} +
       (last_u_txb_nonzero_q ? 4'd6 : 4'd0)) :
      (4'd6 +
       {3'd0, u_txb_above_q[txb_col_w[4:0]] != 8'd0} +
       {3'd0, u_txb_left_q[txb_row_w[4:0]] != 8'd0});
  assign leaf_visible_txb_w_w =
    ((block_col_mi_q + block_w_mi_q) > visible_cols_mi_q) ?
      (visible_cols_mi_q - block_col_mi_q) : block_w_mi_q;
  assign leaf_visible_txb_h_w =
    ((block_row_mi_q + block_h_mi_q) > visible_rows_mi_q) ?
      (visible_rows_mi_q - block_row_mi_q) : block_h_mi_q;

  always @* begin
    precarry_write_valid_w = 1'b0;
    precarry_write_addr_w = precarry_len_q;
    precarry_write_data_w = 16'd0;

    if (!start && pending_push_valid_q) begin
      precarry_write_valid_w = 1'b1;
      precarry_write_addr_w = precarry_len_q;
      precarry_write_data_w = pending_push_word_q;
    end else if (!start) begin
      case (state_q)
        ST_PARTITION,
        ST_LEAF: begin
          if (op_valid_w && norm_push_count_w != 2'd0) begin
            precarry_write_valid_w = 1'b1;
            precarry_write_addr_w = precarry_len_q;
            precarry_write_data_w = norm_push0_w;
          end
        end
        ST_FINISH_PUSH: begin
          if (finish_s_q > 0) begin
            precarry_write_valid_w = 1'b1;
            precarry_write_addr_w = precarry_len_q;
            precarry_write_data_w = (finish_e_q >> (finish_c_q + 16)) & 16'hffff;
          end
        end
        ST_CARRY_WRITE: begin
          precarry_write_valid_w = 1'b1;
          precarry_write_addr_w = carry_index_q;
          precarry_write_data_w = {8'd0, carry_sum_w[7:0]};
        end
        default: begin
          precarry_write_valid_w = 1'b0;
        end
      endcase
    end
  end

  always_ff @(posedge clk) begin
    precarry_read_data_q <= precarry_mem_q[precarry_read_addr_q];
    if (precarry_write_valid_w) begin
      precarry_mem_q[precarry_write_addr_w] <= precarry_write_data_w;
    end
  end

  always @* begin
    if (visible_width <= 16'd8) width_bits_w = 5'd3;
    else if (visible_width <= 16'd16) width_bits_w = 5'd4;
    else if (visible_width <= 16'd32) width_bits_w = 5'd5;
    else if (visible_width <= 16'd64) width_bits_w = 5'd6;
    else if (visible_width <= 16'd128) width_bits_w = 5'd7;
    else if (visible_width <= 16'd256) width_bits_w = 5'd8;
    else if (visible_width <= 16'd512) width_bits_w = 5'd9;
    else if (visible_width <= 16'd1024) width_bits_w = 5'd10;
    else if (visible_width <= 16'd2048) width_bits_w = 5'd11;
    else if (visible_width <= 16'd4096) width_bits_w = 5'd12;
    else if (visible_width <= 16'd8192) width_bits_w = 5'd13;
    else if (visible_width <= 16'd16384) width_bits_w = 5'd14;
    else if (visible_width <= 16'd32768) width_bits_w = 5'd15;
    else width_bits_w = 5'd16;

    if (visible_height <= 16'd8) height_bits_w = 5'd3;
    else if (visible_height <= 16'd16) height_bits_w = 5'd4;
    else if (visible_height <= 16'd32) height_bits_w = 5'd5;
    else if (visible_height <= 16'd64) height_bits_w = 5'd6;
    else if (visible_height <= 16'd128) height_bits_w = 5'd7;
    else if (visible_height <= 16'd256) height_bits_w = 5'd8;
    else if (visible_height <= 16'd512) height_bits_w = 5'd9;
    else if (visible_height <= 16'd1024) height_bits_w = 5'd10;
    else if (visible_height <= 16'd2048) height_bits_w = 5'd11;
    else if (visible_height <= 16'd4096) height_bits_w = 5'd12;
    else if (visible_height <= 16'd8192) height_bits_w = 5'd13;
    else if (visible_height <= 16'd16384) height_bits_w = 5'd14;
    else if (visible_height <= 16'd32768) height_bits_w = 5'd15;
    else height_bits_w = 5'd16;
  end

  always @* begin
    tile_log2_cols_w = 3'd0;
    if (tile_cols_q > 16'd1) tile_log2_cols_w = 3'd1;
    if (tile_cols_q > 16'd2) tile_log2_cols_w = 3'd2;
    if (tile_cols_q > 16'd4) tile_log2_cols_w = 3'd3;
    if (tile_cols_q > 16'd8) tile_log2_cols_w = 3'd4;
    if (tile_cols_q > 16'd16) tile_log2_cols_w = 3'd5;
    if (tile_cols_q > 16'd32) tile_log2_cols_w = 3'd6;

    tile_log2_rows_w = 3'd0;
    if (tile_rows_q > 16'd1) tile_log2_rows_w = 3'd1;
    if (tile_rows_q > 16'd2) tile_log2_rows_w = 3'd2;
    if (tile_rows_q > 16'd4) tile_log2_rows_w = 3'd3;
    if (tile_rows_q > 16'd8) tile_log2_rows_w = 3'd4;
    if (tile_rows_q > 16'd16) tile_log2_rows_w = 3'd5;
    if (tile_rows_q > 16'd32) tile_log2_rows_w = 3'd6;
  end

  always @* begin
    closed_header_bits_w = 64'd0;
    closed_bit_index_w = 0;

    // AV2 v1.0.0 Sections 5.19 and 5.20.1: first tile group plus the
    // minimum uncompressed header used by the MVP still-picture path.
    closed_header_bits_w[(AV2_MAX_CLOSED_HEADER_BYTES * 8 - 1) - closed_bit_index_w] = 1'b1;
    closed_bit_index_w = closed_bit_index_w + 1;
    closed_header_bits_w[(AV2_MAX_CLOSED_HEADER_BYTES * 8 - 1) - closed_bit_index_w] = 1'b1;
    closed_bit_index_w = closed_bit_index_w + 1;
    closed_header_bits_w[(AV2_MAX_CLOSED_HEADER_BYTES * 8 - 1) - closed_bit_index_w] = 1'b1;
    closed_bit_index_w = closed_bit_index_w + 1;

    closed_header_bits_w[(AV2_MAX_CLOSED_HEADER_BYTES * 8 - 1) - closed_bit_index_w] =
      frame_palette_mode_q;
    closed_bit_index_w = closed_bit_index_w + 1;
    if (frame_palette_mode_q) begin
      // cur_frame_force_integer_mv = 0
      closed_bit_index_w = closed_bit_index_w + 1;
    end

    closed_header_bits_w[(AV2_MAX_CLOSED_HEADER_BYTES * 8 - 1) - closed_bit_index_w] =
      frame_ibc_mode_q;
    closed_bit_index_w = closed_bit_index_w + 1;
    if (frame_ibc_mode_q) begin
      // AV2 v1.0.0 read_intrabc_params(): allow_global_intrabc=0 makes
      // AVM infer local IntraBC availability for this tile-local MVP path.
      closed_bit_index_w = closed_bit_index_w + 1;
    end
    closed_header_bits_w[(AV2_MAX_CLOSED_HEADER_BYTES * 8 - 1) - closed_bit_index_w] = 1'b1;
    closed_bit_index_w = closed_bit_index_w + 1;
    closed_header_bits_w[(AV2_MAX_CLOSED_HEADER_BYTES * 8 - 1) - closed_bit_index_w] = 1'b1;
    closed_bit_index_w = closed_bit_index_w + 1;

    // AV2 v1.0.0 write_tile_info_max_tile(): uniform_spacing_flag followed
    // by one increment bit per log2 tile column/row above the Level 2.0
    // minimum. The current 64x64-SB subset keeps min_log2 at zero.
    for (closed_loop_index_w = 0; closed_loop_index_w < 6; closed_loop_index_w = closed_loop_index_w + 1) begin
      if (closed_loop_index_w < tile_log2_cols_w) begin
        closed_header_bits_w[(AV2_MAX_CLOSED_HEADER_BYTES * 8 - 1) - closed_bit_index_w] = 1'b1;
        closed_bit_index_w = closed_bit_index_w + 1;
      end
    end
    for (closed_loop_index_w = 0; closed_loop_index_w < 6; closed_loop_index_w = closed_loop_index_w + 1) begin
      if (closed_loop_index_w < tile_log2_rows_w) begin
        closed_header_bits_w[(AV2_MAX_CLOSED_HEADER_BYTES * 8 - 1) - closed_bit_index_w] = 1'b1;
        closed_bit_index_w = closed_bit_index_w + 1;
      end
    end
    if (multi_tile_w) begin
      closed_header_bits_w[(AV2_MAX_CLOSED_HEADER_BYTES * 8 - 1) - closed_bit_index_w] = 1'b1;
      closed_bit_index_w = closed_bit_index_w + 1;
      closed_header_bits_w[(AV2_MAX_CLOSED_HEADER_BYTES * 8 - 1) - closed_bit_index_w] = 1'b1;
      closed_bit_index_w = closed_bit_index_w + 1;
    end

    // quantization.base_qindex, segmentation.enabled, qmatrix, and
    // reduced_tx_set_used are all zero in the MVP. For multi-tile single
    // tile-group OBUs, tile_start_and_end_present_flag is also zero.
    closed_bit_index_w = closed_bit_index_w + 12;
    if (multi_tile_w) begin
      closed_bit_index_w = closed_bit_index_w + 1;
    end
    if (closed_bit_index_w[2:0] != 3'd0) begin
      closed_bit_index_w = closed_bit_index_w + (8 - closed_bit_index_w[2:0]);
    end
    closed_header_bit_count_w = closed_bit_index_w[5:0];
    closed_header_len_w = closed_bit_index_w[5:3];

    case (closed_header_index_w)
      3'd0: closed_header_byte_w = closed_header_bits_w[63:56];
      3'd1: closed_header_byte_w = closed_header_bits_w[55:48];
      3'd2: closed_header_byte_w = closed_header_bits_w[47:40];
      3'd3: closed_header_byte_w = closed_header_bits_w[39:32];
      3'd4: closed_header_byte_w = closed_header_bits_w[31:24];
      3'd5: closed_header_byte_w = closed_header_bits_w[23:16];
      3'd6: closed_header_byte_w = closed_header_bits_w[15:8];
      default: closed_header_byte_w = closed_header_bits_w[7:0];
    endcase
  end

  always @* begin
    forced_valid_w = 1'b0;
    forced_partition_w = PARTITION_NONE;
    if (!block_partition_point_w) begin
      forced_valid_w = 1'b1;
      forced_partition_w = PARTITION_NONE;
    end else if (!(has_rows_w && has_cols_w)) begin
      forced_valid_w = 1'b1;
      if (block_square_w) begin
        forced_partition_w = (has_rows_w && !has_cols_w) ? PARTITION_VERT : PARTITION_HORZ;
      end else if (block_tall_w) begin
        if (!has_rows_w) begin
          forced_partition_w = PARTITION_HORZ;
        end else if (block_w_mi_q >= 5'd4 && !sub_has_cols_w) begin
          forced_partition_w = PARTITION_HORZ;
        end else begin
          forced_valid_w = 1'b0;
        end
      end else begin
        if (!has_cols_w) begin
          forced_partition_w = PARTITION_VERT;
        end else if (block_h_mi_q >= 5'd4 && !sub_has_rows_w) begin
          forced_partition_w = PARTITION_VERT;
        end else begin
          forced_valid_w = 1'b0;
        end
      end
    end

    palette_preferred_partition_w = PARTITION_NONE;
    if (block_square_w) begin
      if (block_h_mi_q > 5'd2 && allowed_horz_w) begin
        palette_preferred_partition_w = PARTITION_HORZ;
      end else if (block_w_mi_q > 5'd2 && allowed_vert_w) begin
        palette_preferred_partition_w = PARTITION_VERT;
      end
    end else if (block_w_mi_q > block_h_mi_q) begin
      if (block_w_mi_q > 5'd2 && allowed_vert_w) begin
        palette_preferred_partition_w = PARTITION_VERT;
      end else if (block_h_mi_q > 5'd2 && allowed_horz_w) begin
        palette_preferred_partition_w = PARTITION_HORZ;
      end
    end else begin
      if (block_h_mi_q > 5'd2 && allowed_horz_w) begin
        palette_preferred_partition_w = PARTITION_HORZ;
      end else if (block_w_mi_q > 5'd2 && allowed_vert_w) begin
        palette_preferred_partition_w = PARTITION_VERT;
      end
    end

    palette_preferred_valid_w =
      palette_mode_q &&
      block_partition_point_w &&
      !((block_w_mi_q == 5'd2) && (block_h_mi_q == 5'd2)) &&
      (palette_preferred_partition_w != PARTITION_NONE);

    chosen_partition_w = PARTITION_NONE;
    if (!block_partition_point_w) begin
      chosen_partition_w = PARTITION_NONE;
    end else if (
      forced_valid_w &&
      (((forced_partition_w == PARTITION_NONE) && allowed_none_w) ||
       ((forced_partition_w == PARTITION_HORZ) && allowed_horz_w) ||
       ((forced_partition_w == PARTITION_VERT) && allowed_vert_w))
    ) begin
      chosen_partition_w = forced_partition_w;
    end else if (palette_preferred_valid_w) begin
      chosen_partition_w = palette_preferred_partition_w;
    end else if (
      preferred_valid_w &&
      (((preferred_partition_w == PARTITION_HORZ) && allowed_horz_w) ||
       ((preferred_partition_w == PARTITION_VERT) && allowed_vert_w))
    ) begin
      chosen_partition_w = preferred_partition_w;
    end else if (allowed_only_w) begin
      if (allowed_none_w) chosen_partition_w = PARTITION_NONE;
      else if (allowed_horz_w) chosen_partition_w = PARTITION_HORZ;
      else chosen_partition_w = PARTITION_VERT;
    end else if (allowed_none_w) begin
      chosen_partition_w = PARTITION_NONE;
    end else if ((block_row_mi_q + block_h_mi_q) > visible_rows_mi_q && allowed_horz_w) begin
      chosen_partition_w = PARTITION_HORZ;
    end else if ((block_col_mi_q + block_w_mi_q) > visible_cols_mi_q && allowed_vert_w) begin
      chosen_partition_w = PARTITION_VERT;
    end else if (allowed_horz_w) begin
      chosen_partition_w = PARTITION_HORZ;
    end else if (allowed_vert_w) begin
      chosen_partition_w = PARTITION_VERT;
    end

    bsize_map_w = 4'd0;
    case ({block_w_mi_q, block_h_mi_q})
      {5'd2, 5'd2}: bsize_map_w = 4'd0;
      {5'd2, 5'd4},
      {5'd4, 5'd2},
      {5'd4, 5'd4}: bsize_map_w = 4'd1;
      {5'd4, 5'd8},
      {5'd8, 5'd4},
      {5'd8, 5'd8}: bsize_map_w = 4'd2;
      {5'd8, 5'd16},
      {5'd16, 5'd8},
      {5'd16, 5'd16}: bsize_map_w = 4'd3;
      {5'd2, 5'd8}: bsize_map_w = 4'd12;
      {5'd8, 5'd2}: bsize_map_w = 4'd13;
      {5'd4, 5'd16}: bsize_map_w = 4'd14;
      {5'd16, 5'd4}: bsize_map_w = 4'd15;
      default: bsize_map_w = 4'd0;
    endcase

    bsize_rect_map_w = 4'd0;
    case ({block_w_mi_q, block_h_mi_q})
      {5'd2, 5'd2},
      {5'd4, 5'd4}: bsize_rect_map_w = 4'd0;
      {5'd2, 5'd4},
      {5'd4, 5'd8}: bsize_rect_map_w = 4'd1;
      {5'd4, 5'd2},
      {5'd8, 5'd4}: bsize_rect_map_w = 4'd2;
      {5'd8, 5'd8}: bsize_rect_map_w = 4'd3;
      {5'd8, 5'd16}: bsize_rect_map_w = 4'd4;
      {5'd16, 5'd8}: bsize_rect_map_w = 4'd5;
      {5'd16, 5'd16}: bsize_rect_map_w = 4'd6;
      {5'd2, 5'd8},
      {5'd4, 5'd16}: bsize_rect_map_w = 4'd13;
      {5'd8, 5'd2},
      {5'd16, 5'd4}: bsize_rect_map_w = 4'd14;
      default: bsize_rect_map_w = 4'd0;
    endcase

    partition_split_ctx_w = {bsize_map_w, 2'b00} + {4'd0, partition_raw_ctx_w};
    partition_rect_ctx_w = {bsize_rect_map_w, 2'b00} + {4'd0, partition_raw_ctx_w};

    partition_update_above_w = 8'd56;
    partition_update_left_w = 8'd56;
    case ({block_w_mi_q, block_h_mi_q})
      {5'd2, 5'd2}: begin partition_update_above_w = 8'd62; partition_update_left_w = 8'd62; end
      {5'd2, 5'd4}: begin partition_update_above_w = 8'd62; partition_update_left_w = 8'd60; end
      {5'd4, 5'd2}: begin partition_update_above_w = 8'd60; partition_update_left_w = 8'd62; end
      {5'd4, 5'd4}: begin partition_update_above_w = 8'd60; partition_update_left_w = 8'd60; end
      {5'd4, 5'd8}: begin partition_update_above_w = 8'd60; partition_update_left_w = 8'd56; end
      {5'd8, 5'd4}: begin partition_update_above_w = 8'd56; partition_update_left_w = 8'd60; end
      {5'd8, 5'd8}: begin partition_update_above_w = 8'd56; partition_update_left_w = 8'd56; end
      {5'd8, 5'd16}: begin partition_update_above_w = 8'd56; partition_update_left_w = 8'd48; end
      {5'd16, 5'd8}: begin partition_update_above_w = 8'd48; partition_update_left_w = 8'd56; end
      {5'd16, 5'd16}: begin partition_update_above_w = 8'd48; partition_update_left_w = 8'd48; end
      {5'd2, 5'd8}: begin partition_update_above_w = 8'd62; partition_update_left_w = 8'd56; end
      {5'd8, 5'd2}: begin partition_update_above_w = 8'd56; partition_update_left_w = 8'd62; end
      {5'd4, 5'd16}: begin partition_update_above_w = 8'd60; partition_update_left_w = 8'd48; end
      {5'd16, 5'd4}: begin partition_update_above_w = 8'd48; partition_update_left_w = 8'd60; end
      {5'd2, 5'd16}: begin partition_update_above_w = 8'd62; partition_update_left_w = 8'd48; end
      {5'd16, 5'd2}: begin partition_update_above_w = 8'd48; partition_update_left_w = 8'd62; end
    endcase

    leaf_fsc_symbol_w = (block_w_mi_q <= 5'd8) && (block_h_mi_q <= 5'd8);
    leaf_fsc_fh_w = 32'd0;
    case ({block_w_mi_q, block_h_mi_q})
      {5'd2, 5'd2}: leaf_fsc_fh_w = 32'd514;
      {5'd2, 5'd4},
      {5'd4, 5'd2}: leaf_fsc_fh_w = 32'd444;
      {5'd4, 5'd4},
      {5'd2, 5'd8},
      {5'd8, 5'd2}: leaf_fsc_fh_w = 32'd186;
      {5'd4, 5'd8},
      {5'd8, 5'd4},
      {5'd8, 5'd8}: leaf_fsc_fh_w = 32'd77;
      default: leaf_fsc_fh_w = 32'd0;
    endcase

    if (txb_row_w == 16'd0 && txb_col_w == 16'd0) begin
      y_txb_nonzero_fh_w = 32'd31669;
      u_txb_nonzero_fh_w = 32'd23870;
      v_txb_nonzero_fh_w = 32'd16384;
      y_dc_sign_fl_w = 32'd16937;
    end else if (txb_row_w == 16'd0 || txb_col_w == 16'd0) begin
      y_txb_nonzero_fh_w = 32'd24824;
      u_txb_nonzero_fh_w = 32'd19113;
      v_txb_nonzero_fh_w = 32'd16384;
      y_dc_sign_fl_w = 32'd19136;
    end else begin
      y_txb_nonzero_fh_w = 32'd3692;
      u_txb_nonzero_fh_w = 32'd10420;
      v_txb_nonzero_fh_w = 32'd16384;
      y_dc_sign_fl_w = 32'd19136;
    end
  end

  always @* begin
    seq_load_value_w = 64'd0;
    seq_load_bits_w = 7'd0;
    case (seq_op_q)
      8'd0: begin seq_load_value_w = 64'd1; seq_load_bits_w = 7'd1; end
      8'd1: begin seq_load_value_w = 64'd4; seq_load_bits_w = 7'd5; end
      8'd2: begin seq_load_value_w = 64'd1; seq_load_bits_w = 7'd1; end
      8'd3: begin seq_load_value_w = 64'd0; seq_load_bits_w = 7'd5; end
      8'd4: begin seq_load_value_w = 64'd3; seq_load_bits_w = 7'd3; end
      8'd5: begin seq_load_value_w = 64'd2; seq_load_bits_w = 7'd3; end
      8'd6: begin seq_load_value_w = {60'd0, width_bits_q[3:0] - 4'd1}; seq_load_bits_w = 7'd4; end
      8'd7: begin seq_load_value_w = {60'd0, height_bits_q[3:0] - 4'd1}; seq_load_bits_w = 7'd4; end
      8'd8: begin seq_load_value_w = {48'd0, width_q - 16'd1}; seq_load_bits_w = {2'd0, width_bits_q}; end
      8'd9: begin seq_load_value_w = {48'd0, height_q - 16'd1}; seq_load_bits_w = {2'd0, height_bits_q}; end
      8'd10: begin seq_load_value_w = 64'd0; seq_load_bits_w = 7'd6; end
      8'd11: begin seq_load_value_w = 64'd0; seq_load_bits_w = 7'd2; end
      8'd12: begin seq_load_value_w = 64'd0; seq_load_bits_w = 7'd8; end
      8'd13: begin
        if (frame_ibc_mode_q) begin
          seq_load_value_w = 64'd28;
          seq_load_bits_w = 7'd6;
        end else begin
          seq_load_value_w = 64'd8;
          seq_load_bits_w = 7'd5;
        end
      end
      8'd14: begin seq_load_value_w = 64'd32878; seq_load_bits_w = 7'd17; end
      8'd15: begin seq_load_value_w = 64'd1; seq_load_bits_w = 7'd7; end
      8'd16: begin seq_load_value_w = 64'd0; seq_load_bits_w = 7'd3; end
      8'd17: begin
        if (seq_bit_pos_q[2:0] == 3'd0) begin
          seq_load_value_w = 64'h80;
          seq_load_bits_w = 7'd8;
        end else begin
          seq_load_bits_w = 7'd8 - {4'd0, seq_bit_pos_q[2:0]};
          seq_load_value_w = 64'd1 << (seq_load_bits_w - 7'd1);
        end
      end
      default: begin seq_load_value_w = 64'd0; seq_load_bits_w = 7'd0; end
    endcase
  end

  always @* begin
    output_byte_w = 8'h00;
    if (stream_index_q == 16'd0) begin
      output_byte_w = 8'h01;
    end else if (stream_index_q == 16'd1) begin
      output_byte_w = 8'h08;
    end else if (stream_index_q == 16'd2) begin
      output_byte_w = 8'd1 + seq_len_q[7:0];
    end else if (stream_index_q == 16'd3) begin
      output_byte_w = 8'h04;
    end else if (stream_index_q < seq_end_index_w) begin
      output_byte_w = seq_mem_q[seq_stream_index_w];
    end else if (stream_index_q < closed_header_start_w) begin
      if (closed_leb_index_w == 16'd0 && closed_leb_len_w != 2'd1) begin
        output_byte_w = closed_len_w[6:0] | 8'h80;
      end else if (closed_leb_index_w == 16'd0) begin
        output_byte_w = closed_len_w[7:0];
      end else if (closed_leb_index_w == 16'd1 && closed_leb_len_w == 2'd3) begin
        output_byte_w = {1'b0, closed_len_w[13:7]} | 8'h80;
      end else if (closed_leb_index_w == 16'd1) begin
        output_byte_w = {1'b0, closed_len_w[13:7]};
      end else begin
        output_byte_w = {6'd0, closed_len_w[15:14]};
      end
    end else if (stream_index_q == closed_header_start_w) begin
      output_byte_w = 8'h10;
    end else if (stream_index_q < tile_payload_start_w) begin
      output_byte_w = closed_header_byte_w;
    end else begin
      output_byte_w = 8'h00;
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      input_error <= 1'b0;
      state_q <= ST_IDLE;
      m_axis_valid <= 1'b0;
      m_axis_data <= 8'd0;
      m_axis_last <= 1'b0;
      low_q <= 64'd0;
      rng_q <= 32'h8000;
      cnt_q <= -9;
      precarry_read_addr_q <= 16'd0;
      pending_push_valid_q <= 1'b0;
      pending_push_word_q <= 16'd0;
      precarry_len_q <= 16'd0;
      tile_len_q <= 16'd0;
      payload_len_q <= 16'd0;
      payload_copy_index_q <= 16'd0;
      payload_prefix_index_q <= 2'd0;
      seq_len_q <= 16'd0;
      stream_index_q <= 16'd0;
      width_q <= 16'd0;
      height_q <= 16'd0;
      width_bits_q <= 5'd0;
      height_bits_q <= 5'd0;
      tile_cols_q <= 16'd1;
      tile_rows_q <= 16'd1;
      tile_count_q <= 16'd1;
      tile_index_q <= 16'd0;
      tile_col_q <= 16'd0;
      tile_row_q <= 16'd0;
      tile_width_q <= 16'd64;
      tile_height_q <= 16'd64;
      tile_input_index_q <= 32'd0;
      frame_palette_mode_q <= 1'b0;
      frame_ibc_mode_q <= 1'b0;
      seq_op_q <= 8'd0;
      seq_bits_left_q <= 7'd0;
      seq_value_q <= 64'd0;
      seq_bit_pos_q <= 16'd0;
      phase_q <= PHASE_INTRA;
      step_q <= 5'd0;
      palette_row_q <= 6'd0;
      palette_col_q <= 6'd0;
      palette_identity_row_ctx_q <= 2'd3;
      palette_mode_q <= 1'b0;
      leaf_luma_mode_q <= LUMA_MODE_DC;
      txb_index_q <= 16'd0;
      txb_width_q <= 16'd0;
      txb_count_q <= 16'd0;
      txb_local_row_q <= 5'd0;
      txb_local_col_q <= 5'd0;
      last_u_txb_nonzero_q <= 1'b0;
      visible_rows_mi_q <= 5'd0;
      visible_cols_mi_q <= 5'd0;
      block_row_mi_q <= 5'd0;
      block_col_mi_q <= 5'd0;
      block_w_mi_q <= 5'd0;
      block_h_mi_q <= 5'd0;
      partition_q <= PARTITION_NONE;
      partition_emit_step_q <= 1'b0;
      stack_sp_q <= 5'd0;
      finish_e_q <= 64'd0;
      finish_c_q <= 0;
      finish_s_q <= 0;
      carry_q <= 16'd0;
      carry_index_q <= 16'd0;
      output_byte_q <= 8'd0;
      output_last_q <= 1'b0;
      for (context_index_q = 0; context_index_q < AV2_PARTITION_CONTEXT_DIM; context_index_q = context_index_q + 1) begin
        partition_above_q[context_index_q] <= 8'd0;
        partition_left_q[context_index_q] <= 8'd0;
        y_txb_above_q[context_index_q] <= 8'd0;
        y_txb_left_q[context_index_q] <= 8'd0;
        u_txb_above_q[context_index_q] <= 8'd0;
        u_txb_left_q[context_index_q] <= 8'd0;
        v_txb_above_q[context_index_q] <= 8'd0;
        v_txb_left_q[context_index_q] <= 8'd0;
        ibc_above_q[context_index_q] <= 1'b0;
        ibc_left_q[context_index_q] <= 1'b0;
        skip_above_q[context_index_q] <= 1'b0;
        skip_left_q[context_index_q] <= 1'b0;
      end
    end else begin
      input_error <= 1'b0;
      if (start) begin
        input_error <= start_invalid_w;
        if (!start_invalid_w && state_q == ST_IDLE) begin
          state_q <= ST_INPUT_READ;
          m_axis_valid <= 1'b0;
          m_axis_last <= 1'b0;
          width_q <= visible_width;
          height_q <= visible_height;
          width_bits_q <= width_bits_w;
          height_bits_q <= height_bits_w;
          seq_op_q <= 8'd0;
          seq_bits_left_q <= 7'd0;
          seq_value_q <= 64'd0;
          seq_bit_pos_q <= 16'd0;
          seq_len_q <= 16'd0;
          payload_len_q <= 16'd0;
          payload_copy_index_q <= 16'd0;
          payload_prefix_index_q <= 2'd0;
          seq_mem_q[0] <= 8'd0;
          seq_mem_q[1] <= 8'd0;
          seq_mem_q[2] <= 8'd0;
          seq_mem_q[3] <= 8'd0;
          seq_mem_q[4] <= 8'd0;
          seq_mem_q[5] <= 8'd0;
          seq_mem_q[6] <= 8'd0;
          seq_mem_q[7] <= 8'd0;
          seq_mem_q[8] <= 8'd0;
          seq_mem_q[9] <= 8'd0;
          seq_mem_q[10] <= 8'd0;
          seq_mem_q[11] <= 8'd0;
          seq_mem_q[12] <= 8'd0;
          seq_mem_q[13] <= 8'd0;
          seq_mem_q[14] <= 8'd0;
          seq_mem_q[15] <= 8'd0;
          low_q <= 64'd0;
          rng_q <= 32'h8000;
          cnt_q <= -9;
          precarry_read_addr_q <= 16'd0;
          pending_push_valid_q <= 1'b0;
          pending_push_word_q <= 16'd0;
          precarry_len_q <= 16'd0;
          tile_len_q <= 16'd0;
          stream_index_q <= 16'd0;
          tile_cols_q <= tile_cols_w;
          tile_rows_q <= tile_rows_w;
          tile_count_q <= tile_cols_w * tile_rows_w;
          tile_index_q <= 16'd0;
          tile_col_q <= 16'd0;
          tile_row_q <= 16'd0;
          tile_width_q <= (tile_cols_w == 16'd1) ? visible_width : 16'd64;
          tile_height_q <= (tile_rows_w == 16'd1) ? visible_height : 16'd64;
          tile_input_index_q <= 32'd0;
          frame_palette_mode_q <= 1'b0;
          frame_ibc_mode_q <= 1'b0;
          phase_q <= PHASE_INTRA;
          step_q <= 5'd0;
          palette_row_q <= 6'd0;
          palette_col_q <= 6'd0;
          palette_identity_row_ctx_q <= 2'd3;
          palette_mode_q <= 1'b0;
          leaf_luma_mode_q <= LUMA_MODE_DC;
          txb_index_q <= 16'd0;
          txb_width_q <= 16'd0;
          txb_count_q <= 16'd0;
          txb_local_row_q <= 5'd0;
          txb_local_col_q <= 5'd0;
          last_u_txb_nonzero_q <= 1'b0;
          visible_rows_mi_q <= visible_rows_mi_w;
          visible_cols_mi_q <= visible_cols_mi_w;
          block_row_mi_q <= 5'd0;
          block_col_mi_q <= 5'd0;
          block_w_mi_q <= 5'd16;
          block_h_mi_q <= 5'd16;
          partition_q <= PARTITION_NONE;
          partition_emit_step_q <= 1'b0;
          stack_sp_q <= 5'd0;
          output_byte_q <= 8'd0;
          output_last_q <= 1'b0;
          state_q <= ST_TILE_START;
        end
      end else if (pending_push_valid_q) begin
        precarry_len_q <= precarry_len_q + 16'd1;
        pending_push_valid_q <= 1'b0;
      end else begin
        case (state_q)
          ST_IDLE: begin
            m_axis_valid <= 1'b0;
            m_axis_last <= 1'b0;
          end
          ST_TILE_START: begin
            tile_input_index_q <= 32'd0;
            state_q <= ST_INPUT_READ;
          end
          ST_INPUT_READ: begin
            if (input_sample_fire_w) begin
              tile_input_index_q <= tile_input_index_q + 32'd1;
              if (s_axis_last != (tile_is_last_w && tile_input_last_w)) begin
                input_error <= 1'b1;
                state_q <= ST_IDLE;
              end
            end
            if (palette_analyzer_done_w) begin
              if (palette_analyzer_unsupported_w) begin
                input_error <= 1'b1;
                state_q <= ST_IDLE;
              end else begin
                palette_mode_q <= palette_analyzer_luma_mode_w;
                frame_palette_mode_q <= frame_palette_mode_q | palette_analyzer_luma_mode_w;
                // AV2 v1.0.0 read_intrabc_params()/read_intra_frame_mode_info():
                // allow_intrabc is a frame-header decision, while the MVP RTL
                // analyzes one 64x64 tile at a time before outputting the final
                // OBU. Enable the syntax whenever the 4:4:4 palette path is
                // active, then use the hash matcher only to choose whether each
                // leaf writes use_intrabc=1.
                frame_ibc_mode_q <= frame_ibc_mode_q | palette_analyzer_luma_mode_w;
                low_q <= 64'd0;
                rng_q <= 32'h8000;
                cnt_q <= -9;
                precarry_read_addr_q <= 16'd0;
                pending_push_valid_q <= 1'b0;
                pending_push_word_q <= 16'd0;
                precarry_len_q <= 16'd0;
                tile_len_q <= 16'd0;
                phase_q <= frame_ibc_mode_q ? PHASE_INTRABC : PHASE_INTRA;
                step_q <= 5'd0;
                palette_row_q <= 6'd0;
                palette_col_q <= 6'd0;
                palette_identity_row_ctx_q <= 2'd3;
                leaf_luma_mode_q <= LUMA_MODE_DC;
                txb_index_q <= 16'd0;
                txb_width_q <= 16'd0;
                txb_count_q <= 16'd0;
                txb_local_row_q <= 5'd0;
                txb_local_col_q <= 5'd0;
                last_u_txb_nonzero_q <= 1'b0;
                visible_rows_mi_q <= visible_rows_mi_w;
                visible_cols_mi_q <= visible_cols_mi_w;
                block_row_mi_q <= 5'd0;
                block_col_mi_q <= 5'd0;
                block_w_mi_q <= 5'd16;
                block_h_mi_q <= 5'd16;
                partition_q <= PARTITION_NONE;
                partition_emit_step_q <= 1'b0;
                stack_sp_q <= 5'd0;
                for (context_index_q = 0; context_index_q < AV2_PARTITION_CONTEXT_DIM; context_index_q = context_index_q + 1) begin
                  partition_above_q[context_index_q] <= 8'd0;
                  partition_left_q[context_index_q] <= 8'd0;
                  y_txb_above_q[context_index_q] <= 8'd0;
                  y_txb_left_q[context_index_q] <= 8'd0;
                  u_txb_above_q[context_index_q] <= 8'd0;
                  u_txb_left_q[context_index_q] <= 8'd0;
                  v_txb_above_q[context_index_q] <= 8'd0;
                  v_txb_left_q[context_index_q] <= 8'd0;
                  ibc_above_q[context_index_q] <= 1'b0;
                  ibc_left_q[context_index_q] <= 1'b0;
                  skip_above_q[context_index_q] <= 1'b0;
                  skip_left_q[context_index_q] <= 1'b0;
                end
                state_q <= (tile_index_q == 16'd0) ? ST_SEQ_LOAD : ST_LOAD_BLOCK;
              end
            end
          end
          ST_SEQ_LOAD: begin
            if (seq_op_q == 8'd18) begin
              seq_len_q <= (seq_bit_pos_q + 16'd7) >> 3;
              state_q <= ST_LOAD_BLOCK;
            end else begin
              seq_value_q <= seq_load_value_w;
              seq_bits_left_q <= seq_load_bits_w;
              state_q <= ST_SEQ_WRITE;
            end
          end
          ST_SEQ_WRITE: begin
            seq_mem_q[seq_bit_pos_q[15:3]][7 - seq_bit_pos_q[2:0]] <= seq_value_q[seq_bits_left_q - 7'd1];
            seq_bit_pos_q <= seq_bit_pos_q + 16'd1;
            if (seq_bits_left_q == 7'd1) begin
              seq_bits_left_q <= 7'd0;
              seq_op_q <= seq_op_q + 8'd1;
              state_q <= ST_SEQ_LOAD;
            end else begin
              seq_bits_left_q <= seq_bits_left_q - 7'd1;
            end
          end
          ST_LOAD_BLOCK: begin
            if (!block_visible_w) begin
              if (stack_sp_q != 5'd0) begin
                block_row_mi_q <= stack_row_mi_q[stack_sp_q - 5'd1];
                block_col_mi_q <= stack_col_mi_q[stack_sp_q - 5'd1];
                block_w_mi_q <= stack_w_mi_q[stack_sp_q - 5'd1];
                block_h_mi_q <= stack_h_mi_q[stack_sp_q - 5'd1];
                stack_sp_q <= stack_sp_q - 5'd1;
              end else begin
                state_q <= ST_FINISH_INIT;
              end
            end else begin
              partition_q <= chosen_partition_w;
              partition_emit_step_q <= 1'b0;
              state_q <= ST_PARTITION;
            end
          end
          ST_PARTITION: begin
            if (op_valid_w) begin
              if (norm_push_count_w != 2'd0) begin
                precarry_len_q <= precarry_len_q + 16'd1;
              end
              if (norm_push_count_w == 2'd2) begin
                pending_push_valid_q <= 1'b1;
                pending_push_word_q <= norm_push1_w;
              end
              low_q <= norm_low_w;
              rng_q <= norm_rng_w;
              cnt_q <= norm_cnt_w;

              if (partition_emit_do_split_w && partition_need_rect_w) begin
                partition_emit_step_q <= 1'b1;
              end else if (partition_q == PARTITION_NONE) begin
                for (context_index_q = 0; context_index_q < AV2_PARTITION_CONTEXT_DIM; context_index_q = context_index_q + 1) begin
                  if (context_index_q >= block_col_mi_q && context_index_q < (block_col_mi_q + block_w_mi_q)) begin
                    partition_above_q[context_index_q] <= partition_update_above_w;
                  end
                  if (context_index_q >= block_row_mi_q && context_index_q < (block_row_mi_q + block_h_mi_q)) begin
                    partition_left_q[context_index_q] <= partition_update_left_w;
                  end
                end
                phase_q <= frame_ibc_mode_q ? PHASE_INTRABC : PHASE_INTRA;
                step_q <= 5'd0;
                palette_row_q <= 6'd0;
                palette_col_q <= 6'd0;
                palette_identity_row_ctx_q <= 2'd3;
                txb_index_q <= 16'd0;
                txb_local_row_q <= 5'd0;
                txb_local_col_q <= 5'd0;
                last_u_txb_nonzero_q <= 1'b0;
                txb_width_q <= txb_width_w;
                txb_count_q <= txb_count_w;
                state_q <= frame_ibc_mode_q ? ST_LEAF :
                           (palette_mode_q ? ST_PALETTE_QUERY : ST_LEAF);
              end else if (partition_q == PARTITION_HORZ) begin
                stack_row_mi_q[stack_sp_q] <= block_row_mi_q + block_half_h_mi_w;
                stack_col_mi_q[stack_sp_q] <= block_col_mi_q;
                stack_w_mi_q[stack_sp_q] <= block_w_mi_q;
                stack_h_mi_q[stack_sp_q] <= block_half_h_mi_w;
                stack_sp_q <= stack_sp_q + 5'd1;
                block_h_mi_q <= block_half_h_mi_w;
                state_q <= ST_LOAD_BLOCK;
              end else begin
                stack_row_mi_q[stack_sp_q] <= block_row_mi_q;
                stack_col_mi_q[stack_sp_q] <= block_col_mi_q + block_half_w_mi_w;
                stack_w_mi_q[stack_sp_q] <= block_half_w_mi_w;
                stack_h_mi_q[stack_sp_q] <= block_h_mi_q;
                stack_sp_q <= stack_sp_q + 5'd1;
                block_w_mi_q <= block_half_w_mi_w;
                state_q <= ST_LOAD_BLOCK;
              end
            end else if (partition_q == PARTITION_NONE) begin
              for (context_index_q = 0; context_index_q < AV2_PARTITION_CONTEXT_DIM; context_index_q = context_index_q + 1) begin
                if (context_index_q >= block_col_mi_q && context_index_q < (block_col_mi_q + block_w_mi_q)) begin
                  partition_above_q[context_index_q] <= partition_update_above_w;
                end
                if (context_index_q >= block_row_mi_q && context_index_q < (block_row_mi_q + block_h_mi_q)) begin
                  partition_left_q[context_index_q] <= partition_update_left_w;
                end
              end
              phase_q <= frame_ibc_mode_q ? PHASE_INTRABC : PHASE_INTRA;
              step_q <= 5'd0;
              palette_row_q <= 6'd0;
              palette_col_q <= 6'd0;
              palette_identity_row_ctx_q <= 2'd3;
              leaf_luma_mode_q <= LUMA_MODE_DC;
              txb_index_q <= 16'd0;
              txb_local_row_q <= 5'd0;
              txb_local_col_q <= 5'd0;
              last_u_txb_nonzero_q <= 1'b0;
              txb_width_q <= txb_width_w;
              txb_count_q <= txb_count_w;
              state_q <= frame_ibc_mode_q ? ST_LEAF :
                         (palette_mode_q ? ST_PALETTE_QUERY : ST_LEAF);
            end else if (partition_q == PARTITION_HORZ) begin
              stack_row_mi_q[stack_sp_q] <= block_row_mi_q + block_half_h_mi_w;
              stack_col_mi_q[stack_sp_q] <= block_col_mi_q;
              stack_w_mi_q[stack_sp_q] <= block_w_mi_q;
              stack_h_mi_q[stack_sp_q] <= block_half_h_mi_w;
              stack_sp_q <= stack_sp_q + 5'd1;
              block_h_mi_q <= block_half_h_mi_w;
              state_q <= ST_LOAD_BLOCK;
            end else begin
              stack_row_mi_q[stack_sp_q] <= block_row_mi_q;
              stack_col_mi_q[stack_sp_q] <= block_col_mi_q + block_half_w_mi_w;
              stack_w_mi_q[stack_sp_q] <= block_half_w_mi_w;
              stack_h_mi_q[stack_sp_q] <= block_h_mi_q;
              stack_sp_q <= stack_sp_q + 5'd1;
              block_w_mi_q <= block_half_w_mi_w;
              state_q <= ST_LOAD_BLOCK;
            end
          end
          ST_PALETTE_QUERY: begin
            if (palette_query_done_w) begin
              leaf_luma_mode_q <= palette_luma_mode_w;
              state_q <= ST_LEAF;
            end else if (!palette_mode_q) begin
              state_q <= ST_LEAF;
            end
          end
          ST_LEAF: begin
            if (op_valid_w) begin
              if (norm_push_count_w != 2'd0) begin
                precarry_len_q <= precarry_len_q + 16'd1;
              end
              if (norm_push_count_w == 2'd2) begin
                pending_push_valid_q <= 1'b1;
                pending_push_word_q <= norm_push1_w;
              end
              low_q <= norm_low_w;
              rng_q <= norm_rng_w;
              cnt_q <= norm_cnt_w;

              if (phase_q == PHASE_INTRABC) begin
                if (step_q == 5'd0 && !ibc_use_left_copy_w) begin
                  phase_q <= PHASE_INTRA;
                  step_q <= 5'd0;
                  leaf_luma_mode_q <= LUMA_MODE_DC;
                  state_q <= palette_mode_q ? ST_PALETTE_QUERY : ST_LEAF;
                end else if (step_q == 5'd5) begin
                  for (context_index_q = 0; context_index_q < AV2_PARTITION_CONTEXT_DIM; context_index_q = context_index_q + 1) begin
                    if (context_index_q >= block_col_mi_q && context_index_q < (block_col_mi_q + block_w_mi_q)) begin
                      ibc_above_q[context_index_q] <= 1'b1;
                      skip_above_q[context_index_q] <= 1'b1;
                      y_txb_above_q[context_index_q] <= 8'd0;
                      u_txb_above_q[context_index_q] <= 8'd0;
                      v_txb_above_q[context_index_q] <= 8'd0;
                    end
                    if (context_index_q >= block_row_mi_q && context_index_q < (block_row_mi_q + block_h_mi_q)) begin
                      ibc_left_q[context_index_q] <= 1'b1;
                      skip_left_q[context_index_q] <= 1'b1;
                      y_txb_left_q[context_index_q] <= 8'd0;
                      u_txb_left_q[context_index_q] <= 8'd0;
                      v_txb_left_q[context_index_q] <= 8'd0;
                    end
                  end
                  if (stack_sp_q != 5'd0) begin
                    block_row_mi_q <= stack_row_mi_q[stack_sp_q - 5'd1];
                    block_col_mi_q <= stack_col_mi_q[stack_sp_q - 5'd1];
                    block_w_mi_q <= stack_w_mi_q[stack_sp_q - 5'd1];
                    block_h_mi_q <= stack_h_mi_q[stack_sp_q - 5'd1];
                    stack_sp_q <= stack_sp_q - 5'd1;
                    state_q <= ST_LOAD_BLOCK;
                  end else begin
                    state_q <= ST_FINISH_INIT;
                  end
                end else begin
                  step_q <= step_q + 5'd1;
                end
              end else if (op_last_w) begin
                state_q <= ST_FINISH_INIT;
              end else if (phase_q == PHASE_INTRA) begin
                if (step_q == 5'd2 && !leaf_fsc_symbol_w) begin
                  step_q <= 5'd4;
                end else if (step_q == 5'd5) begin
                  phase_q <= leaf_luma_palette_w ? PHASE_PALETTE_HEADER : PHASE_Y_COEFF;
                  step_q <= 5'd0;
                  palette_row_q <= 6'd0;
                  palette_col_q <= 6'd0;
                  palette_identity_row_ctx_q <= 2'd3;
                  txb_index_q <= 16'd0;
                  txb_local_row_q <= 5'd0;
                  txb_local_col_q <= 5'd0;
                  last_u_txb_nonzero_q <= 1'b0;
                  if (palette_mode_q && !leaf_luma_palette_w) begin
                    state_q <= ST_CHROMA_FETCH;
                  end
                end else begin
                  step_q <= step_q + 5'd1;
                end
              end else if (phase_q == PHASE_PALETTE_HEADER) begin
                if (palette_header_last_step_w) begin
                  phase_q <= PHASE_PALETTE_MAP;
                  step_q <= 5'd0;
                  palette_row_q <= 6'd0;
                  palette_col_q <= 6'd0;
                  palette_identity_row_ctx_q <= 2'd3;
                end else begin
                  step_q <= step_q + 5'd1;
                end
              end else if (phase_q == PHASE_PALETTE_MAP) begin
                if (step_q == 5'd0) begin
                  step_q <= 5'd1;
                end else if (step_q == 5'd1) begin
                  palette_identity_row_ctx_q <= palette_identity_row_flag_w;
                  if (palette_map_token_required_w) begin
                    step_q <= 5'd2;
                  end else if (palette_row_q == 6'd7) begin
                    phase_q <= PHASE_Y_COEFF;
                    step_q <= 5'd0;
                    txb_index_q <= 16'd0;
                    txb_local_row_q <= 5'd0;
                    txb_local_col_q <= 5'd0;
                    state_q <= ST_CHROMA_FETCH;
                  end else begin
                    palette_row_q <= palette_row_q + 6'd1;
                    palette_col_q <= 6'd0;
                    step_q <= 5'd1;
                  end
                end else if (palette_identity_row_flag_w == 2'd0 && palette_col_q != 6'd7) begin
                  palette_col_q <= palette_col_q + 6'd1;
                  step_q <= 5'd2;
                end else if (palette_row_q == 6'd7) begin
                  phase_q <= PHASE_Y_COEFF;
                  step_q <= 5'd0;
                  txb_index_q <= 16'd0;
                  txb_local_row_q <= 5'd0;
                  txb_local_col_q <= 5'd0;
                  state_q <= ST_CHROMA_FETCH;
                end else begin
                  palette_row_q <= palette_row_q + 6'd1;
                  palette_col_q <= 6'd0;
                  step_q <= 5'd1;
                end
              end else if (phase_q == PHASE_Y_COEFF) begin
                if ((palette_mode_q && luma_residual_txb_done_w) || (!palette_mode_q && step_q == 5'd8)) begin
                  if (palette_mode_q) begin
                    y_txb_above_q[txb_col_w[4:0]] <= luma_residual_entropy_context_w;
                    y_txb_left_q[txb_row_w[4:0]] <= luma_residual_entropy_context_w;
                  end
                  if (txb_index_q == (txb_count_q - 16'd1)) begin
                    phase_q <= PHASE_U_COEFF;
                    step_q <= 5'd0;
                    txb_index_q <= 16'd0;
                    txb_local_row_q <= 5'd0;
                    txb_local_col_q <= 5'd0;
                    last_u_txb_nonzero_q <= 1'b0;
                    if (palette_mode_q) begin
                      state_q <= ST_CHROMA_FETCH;
                    end
                  end else begin
                    step_q <= 5'd0;
                    txb_index_q <= txb_index_q + 16'd1;
                    if (txb_local_col_q == (txb_width_q[4:0] - 5'd1)) begin
                      txb_local_col_q <= 5'd0;
                      txb_local_row_q <= txb_local_row_q + 5'd1;
                    end else begin
                      txb_local_col_q <= txb_local_col_q + 5'd1;
                    end
                    if (palette_mode_q) begin
                      state_q <= ST_CHROMA_FETCH;
                    end
                  end
                end else begin
                  step_q <= step_q + 5'd1;
                end
              end else begin
                if ((palette_mode_q && chroma_bdpcm_txb_done_w) || (!palette_mode_q && step_q == 7'd7)) begin
                  if (palette_mode_q) begin
                    if (phase_q == PHASE_U_COEFF) begin
                      u_txb_above_q[txb_col_w[4:0]] <= chroma_bdpcm_entropy_context_w;
                      u_txb_left_q[txb_row_w[4:0]] <= chroma_bdpcm_entropy_context_w;
                      last_u_txb_nonzero_q <= chroma_bdpcm_txb_nonzero_w;
                    end else begin
                      v_txb_above_q[txb_col_w[4:0]] <= chroma_bdpcm_entropy_context_w;
                      v_txb_left_q[txb_row_w[4:0]] <= chroma_bdpcm_entropy_context_w;
                    end
                  end
                  if (txb_index_q == (txb_count_q - 16'd1)) begin
                    if (phase_q == PHASE_U_COEFF) begin
                      phase_q <= PHASE_V_COEFF;
                      step_q <= 5'd0;
                      txb_index_q <= 16'd0;
                      txb_local_row_q <= 5'd0;
                      txb_local_col_q <= 5'd0;
                      if (palette_mode_q) begin
                        state_q <= ST_CHROMA_FETCH;
                      end
                    end else begin
                      for (context_index_q = 0; context_index_q < AV2_PARTITION_CONTEXT_DIM; context_index_q = context_index_q + 1) begin
                        if (context_index_q >= block_col_mi_q && context_index_q < (block_col_mi_q + block_w_mi_q)) begin
                          ibc_above_q[context_index_q] <= 1'b0;
                          skip_above_q[context_index_q] <= 1'b0;
                        end
                        if (context_index_q >= block_row_mi_q && context_index_q < (block_row_mi_q + block_h_mi_q)) begin
                          ibc_left_q[context_index_q] <= 1'b0;
                          skip_left_q[context_index_q] <= 1'b0;
                        end
                      end
                      if (stack_sp_q != 5'd0) begin
                        block_row_mi_q <= stack_row_mi_q[stack_sp_q - 5'd1];
                        block_col_mi_q <= stack_col_mi_q[stack_sp_q - 5'd1];
                        block_w_mi_q <= stack_w_mi_q[stack_sp_q - 5'd1];
                        block_h_mi_q <= stack_h_mi_q[stack_sp_q - 5'd1];
                        stack_sp_q <= stack_sp_q - 5'd1;
                        state_q <= ST_LOAD_BLOCK;
                      end else begin
                        state_q <= ST_FINISH_INIT;
                      end
                    end
                  end else begin
                    step_q <= 5'd0;
                    txb_index_q <= txb_index_q + 16'd1;
                    if (txb_local_col_q == (txb_width_q[4:0] - 5'd1)) begin
                      txb_local_col_q <= 5'd0;
                      txb_local_row_q <= txb_local_row_q + 5'd1;
                    end else begin
                      txb_local_col_q <= txb_local_col_q + 5'd1;
                    end
                    if (palette_mode_q) begin
                      state_q <= ST_CHROMA_FETCH;
                    end
                  end
                end else begin
                  step_q <= step_q + 5'd1;
                end
              end
            end
          end
          ST_CHROMA_FETCH: begin
            if ((phase_q == PHASE_Y_COEFF && luma_fetch_done_w) ||
                ((phase_q == PHASE_U_COEFF || phase_q == PHASE_V_COEFF) && chroma_fetch_done_w)) begin
              step_q <= 5'd0;
              state_q <= ST_LEAF;
            end
          end
          ST_FINISH_INIT: begin
            finish_e_q <= ((low_q + 64'h3fff) & ~64'h3fff) | 64'h4000;
            finish_c_q <= cnt_q;
            finish_s_q <= cnt_q + 10;
            state_q <= ST_FINISH_PUSH;
          end
          ST_FINISH_PUSH: begin
            if (finish_s_q > 0) begin
              precarry_len_q <= precarry_len_q + 16'd1;
              if ((finish_c_q + 16) >= 64) begin
                finish_e_q <= 64'd0;
              end else if ((finish_c_q + 16) <= 0) begin
                finish_e_q <= finish_e_q;
              end else begin
                finish_e_q <= finish_e_q & ((64'd1 << (finish_c_q + 16)) - 64'd1);
              end
              finish_c_q <= finish_c_q - 8;
              finish_s_q <= finish_s_q - 8;
            end else begin
              carry_q <= 16'd0;
              carry_index_q <= precarry_len_q - 16'd1;
              precarry_read_addr_q <= precarry_len_q - 16'd1;
              tile_len_q <= precarry_len_q;
              state_q <= ST_CARRY_READ;
            end
          end
          ST_CARRY_READ: begin
            state_q <= ST_CARRY_WRITE;
          end
          ST_CARRY_WRITE: begin
            carry_q <= carry_sum_w >> 8;
            if (carry_index_q == 0) begin
              payload_prefix_index_q <= 2'd0;
              payload_copy_index_q <= 16'd0;
              precarry_read_addr_q <= 16'd0;
              state_q <= ST_PAYLOAD_PREFIX;
            end else begin
              carry_index_q <= carry_index_q - 1;
              precarry_read_addr_q <= carry_index_q - 16'd1;
              state_q <= ST_CARRY_READ;
            end
          end
          ST_PAYLOAD_PREFIX: begin
            if (!tile_is_last_w && payload_prefix_index_q != 2'd3) begin
              payload_mem_q[payload_len_q + {14'd0, payload_prefix_index_q}] <= payload_prefix_byte_w;
              payload_prefix_index_q <= payload_prefix_index_q + 2'd1;
            end else if (!tile_is_last_w) begin
              payload_mem_q[payload_len_q + 16'd3] <= payload_prefix_byte_w;
              payload_len_q <= payload_len_q + 16'd4;
              payload_copy_index_q <= 16'd0;
              precarry_read_addr_q <= 16'd0;
              state_q <= ST_PAYLOAD_COPY_READ;
            end else begin
              payload_copy_index_q <= 16'd0;
              precarry_read_addr_q <= 16'd0;
              state_q <= ST_PAYLOAD_COPY_READ;
            end
          end
          ST_PAYLOAD_COPY_READ: begin
            state_q <= ST_PAYLOAD_COPY_WRITE;
          end
          ST_PAYLOAD_COPY_WRITE: begin
            payload_mem_q[payload_len_q + payload_copy_index_q] <= precarry_read_data_q[7:0];
            if (payload_copy_index_q == (tile_len_q - 16'd1)) begin
              payload_len_q <= payload_len_q + tile_len_q;
              if (tile_is_last_w) begin
                stream_index_q <= 16'd0;
                state_q <= ST_OUTPUT_PREP;
              end else begin
                tile_index_q <= tile_index_q + 16'd1;
                if (tile_col_q == (tile_cols_q - 16'd1)) begin
                  tile_col_q <= 16'd0;
                  tile_row_q <= tile_row_q + 16'd1;
                end else begin
                  tile_col_q <= tile_col_q + 16'd1;
                end
                if (tile_col_q == (tile_cols_q - 16'd1)) begin
                  tile_width_q <= (tile_cols_q == 16'd1) ? width_q : 16'd64;
                  tile_height_q <=
                    ((tile_row_q + 16'd1) == (tile_rows_q - 16'd1)) ?
                      (height_q - ((tile_row_q + 16'd1) << 6)) : 16'd64;
                end else begin
                  tile_width_q <=
                    ((tile_col_q + 16'd1) == (tile_cols_q - 16'd1)) ?
                      (width_q - ((tile_col_q + 16'd1) << 6)) : 16'd64;
                  tile_height_q <= tile_height_q;
                end
                state_q <= ST_TILE_START;
              end
            end else begin
              payload_copy_index_q <= payload_copy_index_q + 16'd1;
              precarry_read_addr_q <= payload_copy_index_q + 16'd1;
              state_q <= ST_PAYLOAD_COPY_READ;
            end
          end
          ST_OUTPUT_PREP: begin
            m_axis_valid <= 1'b0;
            if (output_tile_payload_w) begin
              precarry_read_addr_q <= tile_stream_index_w;
              state_q <= ST_OUTPUT_PAYLOAD_READ;
            end else begin
              output_byte_q <= output_byte_w;
              output_last_q <= (stream_index_q == (total_stream_len_w - 16'd1));
              state_q <= ST_OUTPUT_VALID;
            end
          end
          ST_OUTPUT_PAYLOAD_READ: begin
            state_q <= ST_OUTPUT_PAYLOAD_LOAD;
          end
          ST_OUTPUT_PAYLOAD_LOAD: begin
            output_byte_q <= payload_mem_q[tile_stream_index_w];
            output_last_q <= (stream_index_q == (total_stream_len_w - 16'd1));
            state_q <= ST_OUTPUT_VALID;
          end
          ST_OUTPUT_VALID: begin
            if (!m_axis_valid) begin
              m_axis_valid <= 1'b1;
              m_axis_data <= output_byte_q;
              m_axis_last <= output_last_q;
            end else if (m_axis_ready) begin
              if (output_last_q) begin
                m_axis_valid <= 1'b0;
                m_axis_last <= 1'b0;
                state_q <= ST_IDLE;
                stream_index_q <= 16'd0;
              end else begin
                m_axis_valid <= 1'b0;
                m_axis_last <= 1'b0;
                stream_index_q <= stream_index_q + 16'd1;
                state_q <= ST_OUTPUT_PREP;
              end
            end
          end
          default: state_q <= ST_IDLE;
      endcase
    end
  end
  end

  wire _unused_inputs_w = &{
    1'b0,
    CTU_SIZE[0],
    SOURCE_SAMPLE_BITS[0],
    ibc_any_left_copy_w,
    ibc_done_w
  };

endmodule
