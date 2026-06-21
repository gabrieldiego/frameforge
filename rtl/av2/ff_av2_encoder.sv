`timescale 1ns/1ps

// Public SoC integration port for the AV2 encoder. Control/status is shared
// AXI4-Lite, source pixels are fetched through AXI4 reads, and unmuxed OBUs are
// written through AXI4 writes. The visible 8x8 block sample stream below
// remains internal glue behind the shared frame reader.
module ff_av2_encoder #(
  parameter int MAX_VISIBLE_WIDTH = 1024,
  parameter int MAX_VISIBLE_HEIGHT = 1024,
  // TODO(av2): revisit this shared integration name once AV2 block/superblock
  // terminology is finalized in the implementation.
  parameter int CTU_SIZE = 64,
  parameter int SAMPLE_BITS = 8,
  parameter int SOURCE_SAMPLE_BITS = SAMPLE_BITS,
  parameter int AXI_ADDR_BITS = 32,
  parameter int AXI_DATA_BITS = 128,
  parameter int SUPPORT_PALETTE_444 = 1,
  // TODO(av2): replace this staged carry/tile buffer with a streaming carry
  // resolver. Lossless high-colour 64x64 4:4:4 vectors need about 20 KiB
  // today, while larger future pictures must not scale this buffer by frame.
  parameter int AV2_MAX_TILE_BYTES = 32768
) (
  input  logic       clk,
  input  logic       rst_n,
  input  logic [11:0] s_axil_awaddr,
  input  logic       s_axil_awvalid,
  output logic       s_axil_awready,
  input  logic [31:0] s_axil_wdata,
  input  logic [3:0] s_axil_wstrb,
  input  logic       s_axil_wvalid,
  output logic       s_axil_wready,
  output logic [1:0] s_axil_bresp,
  output logic       s_axil_bvalid,
  input  logic       s_axil_bready,
  input  logic [11:0] s_axil_araddr,
  input  logic       s_axil_arvalid,
  output logic       s_axil_arready,
  output logic [31:0] s_axil_rdata,
  output logic [1:0] s_axil_rresp,
  output logic       s_axil_rvalid,
  input  logic       s_axil_rready,

  output logic                         m_axi_arvalid,
  input  logic                         m_axi_arready,
  output logic [AXI_ADDR_BITS - 1:0]   m_axi_araddr,
  output logic [7:0]                   m_axi_arlen,
  output logic [2:0]                   m_axi_arsize,
  output logic [1:0]                   m_axi_arburst,
  input  logic                         m_axi_rvalid,
  output logic                         m_axi_rready,
  input  logic [AXI_DATA_BITS - 1:0]   m_axi_rdata,
  input  logic [1:0]                   m_axi_rresp,
  input  logic                         m_axi_rlast,

  output logic                         m_axi_awvalid,
  input  logic                         m_axi_awready,
  output logic [AXI_ADDR_BITS - 1:0]   m_axi_awaddr,
  output logic [7:0]                   m_axi_awlen,
  output logic [2:0]                   m_axi_awsize,
  output logic [1:0]                   m_axi_awburst,
  output logic                         m_axi_wvalid,
  input  logic                         m_axi_wready,
  output logic [AXI_DATA_BITS - 1:0]   m_axi_wdata,
  output logic [(AXI_DATA_BITS / 8) - 1:0] m_axi_wstrb,
  output logic                         m_axi_wlast,
  input  logic                         m_axi_bvalid,
  output logic                         m_axi_bready,
  input  logic [1:0]                   m_axi_bresp
);

  localparam int AV2_MAX_SEQUENCE_BYTES = 16;
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
    ST_OUTPUT_PREP,
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

  logic       start;
  logic [15:0] visible_width;
  logic [15:0] visible_height;
  logic [1:0]  chroma_format_idc;
  logic [31:0] frame_count;
  logic [AXI_ADDR_BITS - 1:0] src_y_base;
  logic [AXI_ADDR_BITS - 1:0] src_u_base;
  logic [AXI_ADDR_BITS - 1:0] src_v_base;
  logic [31:0] src_y_stride;
  logic [31:0] src_u_stride;
  logic [31:0] src_v_stride;
  logic [31:0] src_frame_stride;
  logic [AXI_ADDR_BITS - 1:0] dst_bitstream_base;
  logic [31:0] dst_bitstream_capacity;
  logic       busy;
  logic       done;
  logic       input_error;
  logic       axi_error;
  logic [31:0] encoded_byte_count;
  logic       s_axis_valid;
  logic       s_axis_ready;
  logic [SAMPLE_BITS - 1:0] s_axis_data;
  logic       s_axis_last;
  logic       m_axis_valid;
  logic       m_axis_ready;
  logic [7:0] m_axis_data;
  logic       m_axis_last;
  logic       frame_reader_start_w;
  logic       frame_reader_busy_w;
  logic       frame_reader_done_w;
  logic       frame_reader_error_w;
  logic       bitstream_writer_start_w;
  logic       bitstream_writer_busy_w;
  logic       bitstream_writer_frame_done_w;
  logic       bitstream_writer_error_w;

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
  logic signed [7:0] cnt_q;
  logic [2:0] phase_q;
  logic [6:0] step_q;
  logic [5:0] palette_row_q;
  logic [5:0] palette_col_q;
  logic [1:0] palette_identity_row_ctx_q;
  logic palette_mode_q;
  logic lossy_420_mode_q;
  logic [1:0] leaf_luma_mode_q;
  logic [15:0] txb_index_q;
  logic [15:0] txb_width_q;
  logic [15:0] txb_count_q;
  logic [4:0] txb_local_row_q;
  logic [4:0] txb_local_col_q;
  logic txb_prefetch_started_q;
  logic txb_prefetch_done_q;
  logic txb_prefetch_chroma_q;
  logic txb_prefetch_plane_v_q;
  logic [1:0] txb_prefetch_index_q;
  logic [127:0] cached_v_txb_samples_q [0:3];
  logic [31:0] cached_v_predictor_samples_q [0:3];
  logic [127:0] cached_u_txb_samples_q [0:3];
  logic [3:0] cached_v_valid_q;
  logic [3:0] cached_chroma_samples_valid_q;
  logic [31:0] left_edge_u_top_q;
  logic [31:0] left_edge_u_bottom_q;
  logic [31:0] left_edge_v_top_q;
  logic [31:0] left_edge_v_bottom_q;
  logic [4:0] left_edge_row_mi_q;
  logic [4:0] left_edge_col_mi_q;
  logic left_edge_valid_q;
  logic [31:0] above_col0_u_q;
  logic [31:0] above_col0_v_q;
  logic [4:0] above_col0_row_mi_q;
  logic above_col0_valid_q;
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
  logic signed [7:0] finish_c_q;
  logic signed [7:0] finish_s_q;
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
  logic signed [7:0] norm_cnt_w;
  logic [63:0] seq_load_value_w;
  logic [6:0] seq_load_bits_w;
  logic [4:0] width_bits_w;
  logic [4:0] height_bits_w;
  logic [15:0] tile_cols_w;
  logic [15:0] tile_rows_w;
  logic [15:0] tile_width_w;
  logic [15:0] tile_height_w;
  logic [31:0] tile_luma_samples_w;
  logic [31:0] tile_samples_w;
  logic tile_input_last_w;
  logic tile_is_last_w;
  logic multi_tile_w;
  logic frame_ibc_mode_q;
  logic ibc_done_w;
  logic ibc_any_copy_w;
  logic [63:0] ibc_copy_mask_w;
  logic [63:0] ibc_above_copy_mask_w;
  logic [127:0] ibc_drl_idx_table_w;
  logic [5:0] ibc_current_block_id_w;
  logic [6:0] ibc_drl_idx_bit_index_w;
  logic ibc_use_copy_w;
  logic [1:0] ibc_drl_idx_w;
  logic [1:0] intrabc_ctx_w;
  logic [1:0] intrabc_skip_ctx_w;
  logic [3:0] closed_header_len_w;
  logic [7:0] payload_prefix_byte_w;
  logic [15:0] closed_len_w;
  logic [1:0] closed_leb_len_w;
  logic [15:0] seq_end_index_w;
  logic [15:0] closed_leb_start_w;
  logic [15:0] closed_header_start_w;
  logic [15:0] total_stream_len_w;
  logic [15:0] tile_payload_start_w;
  logic [15:0] tile_stream_index_w;
  logic [15:0] seq_stream_index_w;
  logic [7:0] seq_stream_byte_w;
  logic [15:0] closed_leb_index_w;
  logic [15:0] stream_lookup_index_w;
  logic [15:0] payload_tile_start_w;
  logic [7:0] output_byte_w;
  logic [7:0] output_lookup_byte_w;
  logic output_lookup_last_w;
  logic [7:0] output_byte_q;
  logic output_last_q;
  logic output_tile_payload_w;
  logic [15:0] carry_sum_w;
  logic leaf_fsc_symbol_w;
  logic [31:0] leaf_fsc_fh_w;
  logic [15:0] txb_width_w;
  logic [15:0] txb_count_w;
  logic [15:0] chroma_txb_width_w;
  logic [15:0] chroma_txb_count_w;
  logic [15:0] txb_row_w;
  logic [15:0] txb_col_w;
  logic [4:0] next_txb_local_row_w;
  logic [4:0] next_txb_local_col_w;
  logic [15:0] next_txb_row_w;
  logic [15:0] next_txb_col_w;
  logic same_phase_has_next_txb_w;
  logic cross_phase_has_next_txb_w;
  logic txb_prefetch_cross_phase_w;
  logic txb_prefetch_first_luma_w;
  logic txb_prefetch_luma_start_w;
  logic txb_prefetch_chroma_start_w;
  logic txb_prefetch_chroma_target_v_w;
  logic chroma_fetch_req_cross_phase_w;
  logic chroma_fetch_req_next_txb_w;
  logic txb_fetch_done_w;
  logic txb_prefetch_fetch_done_w;
  logic v_chroma_cache_hit_w;
  logic u_chroma_cache_hit_w;
  logic chroma_fetch_current_cache_hit_w;
  logic chroma_predictor_compute_valid_w;
  logic chroma_fetch_req_predictor_compute_w;
  logic chroma_fetch_req_ready_w;
  logic chroma_fetch_completed_u_w;
  logic luma_fetch_completed_w;
  logic [1:0] chroma_fetch_cache_index_w;
  logic [1:0] luma_fetch_cache_index_w;
  logic [1:0] chroma_fetch_req_index_w;
  logic [1:0] chroma_left_source_index_w;
  logic [1:0] chroma_above_source_index_w;
  logic chroma_fetch_predictor_only_w;
  logic [31:0] cached_u_left_predictor_w;
  logic [31:0] cached_v_left_predictor_w;
  logic [31:0] cached_u_above_predictor_w;
  logic [31:0] cached_v_above_predictor_w;
  logic [31:0] cached_u_external_left_predictor_w;
  logic [31:0] cached_v_external_left_predictor_w;
  logic [31:0] cached_u_external_above_predictor_w;
  logic [31:0] cached_v_external_above_predictor_w;
  logic [31:0] chroma_cached_predictor_samples_w;
  logic chroma_external_left_predictor_valid_w;
  logic chroma_req_external_left_predictor_valid_w;
  logic chroma_external_above_predictor_valid_w;
  logic chroma_req_external_above_predictor_valid_w;
  logic [31:0] current_u_right_edge_top_w;
  logic [31:0] current_u_right_edge_bottom_w;
  logic [31:0] current_v_right_edge_top_w;
  logic [31:0] current_v_right_edge_bottom_w;
  logic [31:0] current_u_col0_above_edge_w;
  logic [31:0] current_v_col0_above_edge_w;
  logic [4:0] luma_fetch_req_row_mi_w;
  logic [4:0] luma_fetch_req_col_mi_w;
  logic [4:0] chroma_fetch_req_row_mi_w;
  logic [4:0] chroma_fetch_req_col_mi_w;
  logic [4:0] chroma_fetch_current_storage_row_mi_w;
  logic [4:0] chroma_fetch_current_storage_col_mi_w;
  logic [4:0] chroma_fetch_next_storage_row_mi_w;
  logic [4:0] chroma_fetch_next_storage_col_mi_w;
  logic chroma_fetch_req_plane_v_w;
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
  logic [7:0] palette_first_color_w;
  logic [1:0] palette_delta_bits_minus5_w;
  logic [55:0] palette_delta_minus1_w;
  logic [34:0] palette_delta_literal_bits_w;
  logic [1:0] palette_luma_mode_w;
  logic leaf_luma_palette_w;
  logic [2:0] palette_current_index_w;
  logic [2:0] palette_left_index_w;
  logic [2:0] palette_top_index_w;
  logic [2:0] palette_top_left_index_w;
  logic palette_luma_residual_zero_w;
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
  logic residual_mode_w;
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
  logic [127:0] chroma_fetch_u_txb_samples_w;
  logic [31:0] chroma_fetch_u_predictor_samples_w;
  logic [127:0] chroma_fetch_v_txb_samples_w;
  logic [31:0] chroma_fetch_v_predictor_samples_w;
  logic [127:0] luma_fetch_txb_samples_w;
  logic [127:0] luma_fetch_u_txb_samples_w;
  logic [127:0] luma_fetch_v_txb_samples_w;
  logic [127:0] luma_fetch_predictor_samples_w;
  logic [3:0] luma_residual_skip_ctx_w;
  logic [1:0] luma_residual_dc_sign_ctx_w;
  logic [2:0] luma_residual_top_level_w;
  logic [2:0] luma_residual_left_level_w;
  logic signed [3:0] luma_residual_top_sign_w;
  logic signed [3:0] luma_residual_left_sign_w;
  logic signed [5:0] luma_residual_sign_sum_w;
  logic palette_luma_residual_op_valid_w;
  logic palette_luma_residual_op_literal_w;
  logic [31:0] palette_luma_residual_op_literal_value_w;
  logic [4:0] palette_luma_residual_op_literal_bits_w;
  logic [31:0] palette_luma_residual_op_fl_w;
  logic [31:0] palette_luma_residual_op_fh_w;
  logic [4:0] palette_luma_residual_op_fl_inc_w;
  logic [4:0] palette_luma_residual_op_fh_inc_w;
  logic palette_luma_residual_txb_done_w;
  logic [7:0] palette_luma_residual_entropy_context_w;
  logic lossy420_luma_residual_op_valid_w;
  logic lossy420_luma_residual_op_literal_w;
  logic [31:0] lossy420_luma_residual_op_literal_value_w;
  logic [4:0] lossy420_luma_residual_op_literal_bits_w;
  logic [31:0] lossy420_luma_residual_op_fl_w;
  logic [31:0] lossy420_luma_residual_op_fh_w;
  logic [4:0] lossy420_luma_residual_op_fl_inc_w;
  logic [4:0] lossy420_luma_residual_op_fh_inc_w;
  logic lossy420_luma_residual_txb_done_w;
  logic [7:0] lossy420_luma_residual_entropy_context_w;
  logic [7:0] lossy420_luma_residual_recon_sample_w;
  logic luma_residual_op_valid_w;
  logic luma_residual_op_literal_w;
  logic [31:0] luma_residual_op_literal_value_w;
  logic [4:0] luma_residual_op_literal_bits_w;
  logic [31:0] luma_residual_op_fl_w;
  logic [31:0] luma_residual_op_fh_w;
  logic [4:0] luma_residual_op_fl_inc_w;
  logic [4:0] luma_residual_op_fh_inc_w;
  logic luma_residual_advance_w;
  logic palette_luma_residual_advance_w;
  logic lossy420_luma_residual_advance_w;
  logic luma_residual_txb_done_w;
  logic [7:0] luma_residual_entropy_context_w;
  logic [3:0] chroma_bdpcm_skip_ctx_w;
  logic palette_chroma_bdpcm_op_valid_w;
  logic palette_chroma_bdpcm_op_literal_w;
  logic [31:0] palette_chroma_bdpcm_op_literal_value_w;
  logic [4:0] palette_chroma_bdpcm_op_literal_bits_w;
  logic [31:0] palette_chroma_bdpcm_op_fl_w;
  logic [31:0] palette_chroma_bdpcm_op_fh_w;
  logic [4:0] palette_chroma_bdpcm_op_fl_inc_w;
  logic [4:0] palette_chroma_bdpcm_op_fh_inc_w;
  logic palette_chroma_bdpcm_txb_done_w;
  logic palette_chroma_bdpcm_txb_nonzero_w;
  logic [7:0] palette_chroma_bdpcm_entropy_context_w;
  logic lossy420_chroma_bdpcm_op_valid_w;
  logic lossy420_chroma_bdpcm_op_literal_w;
  logic [31:0] lossy420_chroma_bdpcm_op_literal_value_w;
  logic [4:0] lossy420_chroma_bdpcm_op_literal_bits_w;
  logic [31:0] lossy420_chroma_bdpcm_op_fl_w;
  logic [31:0] lossy420_chroma_bdpcm_op_fh_w;
  logic [4:0] lossy420_chroma_bdpcm_op_fl_inc_w;
  logic [4:0] lossy420_chroma_bdpcm_op_fh_inc_w;
  logic lossy420_chroma_bdpcm_txb_done_w;
  logic lossy420_chroma_bdpcm_txb_nonzero_w;
  logic [7:0] lossy420_chroma_bdpcm_entropy_context_w;
  logic [7:0] lossy420_chroma_bdpcm_recon_sample_w;
  logic chroma_bdpcm_op_valid_w;
  logic chroma_bdpcm_op_literal_w;
  logic [31:0] chroma_bdpcm_op_literal_value_w;
  logic [4:0] chroma_bdpcm_op_literal_bits_w;
  logic [31:0] chroma_bdpcm_op_fl_w;
  logic [31:0] chroma_bdpcm_op_fh_w;
  logic [4:0] chroma_bdpcm_op_fl_inc_w;
  logic [4:0] chroma_bdpcm_op_fh_inc_w;
  logic chroma_bdpcm_advance_w;
  logic palette_chroma_bdpcm_advance_w;
  logic lossy420_chroma_bdpcm_advance_w;
  logic chroma_bdpcm_txb_done_w;
  logic chroma_bdpcm_txb_nonzero_w;
  logic [7:0] chroma_bdpcm_entropy_context_w;
  logic [127:0] chroma_bdpcm_txb_samples_w;
  logic [31:0] chroma_bdpcm_predictor_samples_w;
  logic [7:0] lossy420_luma_recon_q [0:3];
  logic [7:0] lossy420_luma_above_q [0:15];
  logic [15:0] lossy420_luma_above_valid_q;
  logic [7:0] lossy420_luma_left_top_q [0:15];
  logic [7:0] lossy420_luma_left_bottom_q [0:15];
  logic [4:0] lossy420_luma_left_col_mi_q [0:15];
  logic [15:0] lossy420_luma_left_valid_q;
  logic [7:0] lossy420_luma_predictor_w;
  logic lossy420_luma_have_left_w;
  logic lossy420_luma_have_top_w;
  logic lossy420_luma_external_left_valid_w;
  logic [3:0] lossy420_luma_left_row_index_w;
  logic [7:0] lossy420_luma_left_sample_w;
  logic [7:0] lossy420_luma_top_sample_w;
  logic signed [9:0] lossy420_luma_delta_w;
  logic [7:0] lossy420_luma_recon_sample_w;
  logic lossy420_luma_known_zero_w;
  logic [7:0] lossy420_u_above_q [0:15];
  logic [7:0] lossy420_v_above_q [0:15];
  logic [15:0] lossy420_u_above_valid_q;
  logic [15:0] lossy420_v_above_valid_q;
  logic [7:0] lossy420_u_left_q [0:15];
  logic [7:0] lossy420_v_left_q [0:15];
  logic [4:0] lossy420_u_left_col_mi_q [0:15];
  logic [4:0] lossy420_v_left_col_mi_q [0:15];
  logic [15:0] lossy420_u_left_valid_q;
  logic [15:0] lossy420_v_left_valid_q;
  logic [7:0] lossy420_chroma_predictor_w;
  logic lossy420_chroma_have_left_w;
  logic lossy420_chroma_have_top_w;
  logic lossy420_chroma_external_left_valid_w;
  logic [3:0] lossy420_chroma_left_row_index_w;
  logic [7:0] lossy420_chroma_left_sample_w;
  logic [7:0] lossy420_chroma_top_sample_w;
  logic signed [9:0] lossy420_chroma_delta_w;
  logic [7:0] lossy420_chroma_recon_sample_w;
  logic lossy420_chroma_known_zero_w;
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
  logic luma_residual_enable_w;
  logic palette_luma_residual_enable_w;
  logic lossy420_luma_residual_enable_w;
  logic palette_chroma_bdpcm_enable_w;
  logic lossy420_chroma_bdpcm_enable_w;
  logic chroma_residual_phase_w;
  logic chroma_bdpcm_fetch_ready_w;
  logic palette_chroma_bdpcm_cache_ready_w;
  logic chroma_subsampled_phase_w;

  ff_av2_partition_cdf_lut partition_cdf_lut (
    .split_ctx(partition_split_ctx_w),
    .rect_ctx(partition_rect_ctx_w),
    .do_split_cdf0(partition_do_cdf0_w),
    .rect_type_cdf0(partition_rect_cdf0_w)
  );

  ff_encoder_axil_regs #(
    .AXI_ADDR_BITS(AXI_ADDR_BITS),
    .AXIL_ADDR_BITS(12)
  ) control_regs (
    .clk(clk),
    .rst_n(rst_n),
    .s_axil_awaddr(s_axil_awaddr),
    .s_axil_awvalid(s_axil_awvalid),
    .s_axil_awready(s_axil_awready),
    .s_axil_wdata(s_axil_wdata),
    .s_axil_wstrb(s_axil_wstrb),
    .s_axil_wvalid(s_axil_wvalid),
    .s_axil_wready(s_axil_wready),
    .s_axil_bresp(s_axil_bresp),
    .s_axil_bvalid(s_axil_bvalid),
    .s_axil_bready(s_axil_bready),
    .s_axil_araddr(s_axil_araddr),
    .s_axil_arvalid(s_axil_arvalid),
    .s_axil_arready(s_axil_arready),
    .s_axil_rdata(s_axil_rdata),
    .s_axil_rresp(s_axil_rresp),
    .s_axil_rvalid(s_axil_rvalid),
    .s_axil_rready(s_axil_rready),
    .busy(busy),
    .done(done),
    .input_error(input_error),
    .axi_error(axi_error),
    .encoded_byte_count(encoded_byte_count),
    .start_pulse(start),
    .visible_width(visible_width),
    .visible_height(visible_height),
    .chroma_format_idc(chroma_format_idc),
    .frame_count(frame_count),
    .src_y_base(src_y_base),
    .src_u_base(src_u_base),
    .src_v_base(src_v_base),
    .src_y_stride(src_y_stride),
    .src_u_stride(src_u_stride),
    .src_v_stride(src_v_stride),
    .src_frame_stride(src_frame_stride),
    .dst_bitstream_base(dst_bitstream_base),
    .dst_bitstream_capacity(dst_bitstream_capacity)
  );

  // Public SoC data-plane glue. The control pins model the values that an
  // AXI4-Lite register bank will carry; the reader fetches planar 4:2:0 or
  // 4:4:4 frame data through AXI4-MM and emits the existing 8x8 tile-local
  // block stream.
  ff_axi4_frame_reader #(
    .AXI_ADDR_BITS(AXI_ADDR_BITS),
    .AXI_DATA_BITS(AXI_DATA_BITS),
    .SAMPLE_BITS(SAMPLE_BITS),
    .CTU_SIZE(CTU_SIZE),
    .RASTER_BLOCK_ORDER(1'b1)
  ) frame_reader (
    .clk(clk),
    .rst_n(rst_n),
    .start(frame_reader_start_w),
    .visible_width(visible_width),
    .visible_height(visible_height),
    .chroma_format_idc(chroma_format_idc),
    .segment_origin_x(tile_col_q << 6),
    .segment_origin_y(tile_row_q << 6),
    .segment_width(tile_width_w),
    .segment_height(tile_height_w),
    .stream_last_on_segment_end(1'b0),
    .frame_last_segment(tile_is_last_w),
    .src_y_base(src_y_base),
    .src_u_base(src_u_base),
    .src_v_base(src_v_base),
    .src_frame_offset({AXI_ADDR_BITS{1'b0}}),
    .src_y_stride(src_y_stride),
    .src_u_stride(src_u_stride),
    .src_v_stride(src_v_stride),
    .m_axi_arvalid(m_axi_arvalid),
    .m_axi_arready(m_axi_arready),
    .m_axi_araddr(m_axi_araddr),
    .m_axi_arlen(m_axi_arlen),
    .m_axi_arsize(m_axi_arsize),
    .m_axi_arburst(m_axi_arburst),
    .m_axi_rvalid(m_axi_rvalid),
    .m_axi_rready(m_axi_rready),
    .m_axi_rdata(m_axi_rdata),
    .m_axi_rresp(m_axi_rresp),
    .m_axi_rlast(m_axi_rlast),
    .sample_valid(s_axis_valid),
    .sample_ready(s_axis_ready),
    .sample_data(s_axis_data),
    .sample_last(s_axis_last),
    .busy(frame_reader_busy_w),
    .done(frame_reader_done_w),
    .error(frame_reader_error_w)
  );

  ff_axi4_bitstream_writer #(
    .AXI_ADDR_BITS(AXI_ADDR_BITS),
    .AXI_DATA_BITS(AXI_DATA_BITS)
  ) bitstream_writer (
    .clk(clk),
    .rst_n(rst_n),
    .start(bitstream_writer_start_w),
    .dst_base(dst_bitstream_base),
    .dst_capacity(dst_bitstream_capacity),
    .s_axis_valid(m_axis_valid),
    .s_axis_ready(m_axis_ready),
    .s_axis_data(m_axis_data),
    .s_axis_last(m_axis_last),
    .m_axi_awvalid(m_axi_awvalid),
    .m_axi_awready(m_axi_awready),
    .m_axi_awaddr(m_axi_awaddr),
    .m_axi_awlen(m_axi_awlen),
    .m_axi_awsize(m_axi_awsize),
    .m_axi_awburst(m_axi_awburst),
    .m_axi_wvalid(m_axi_wvalid),
    .m_axi_wready(m_axi_wready),
    .m_axi_wdata(m_axi_wdata),
    .m_axi_wstrb(m_axi_wstrb),
    .m_axi_wlast(m_axi_wlast),
    .m_axi_bvalid(m_axi_bvalid),
    .m_axi_bready(m_axi_bready),
    .m_axi_bresp(m_axi_bresp),
    .bytes_written(encoded_byte_count),
    .frame_done(bitstream_writer_frame_done_w),
    .busy(bitstream_writer_busy_w),
    .error(bitstream_writer_error_w)
  );

  ff_av2_bitstream_headers bitstream_headers (
    .width(width_q),
    .height(height_q),
    .width_bits(width_bits_q),
    .height_bits(height_bits_q),
    .chroma_format_idc(chroma_format_idc),
    .seq_op(seq_op_q),
    .seq_bit_pos(seq_bit_pos_q),
    .frame_palette_mode(frame_palette_mode_q),
    .frame_ibc_mode(frame_ibc_mode_q),
    .tile_cols(tile_cols_q),
    .tile_rows(tile_rows_q),
    .multi_tile(multi_tile_w),
    .tile_len(tile_len_q),
    .payload_prefix_index(payload_prefix_index_q),
    .seq_len(seq_len_q),
    .payload_len(payload_len_q),
    .stream_index(stream_lookup_index_w),
    .seq_stream_byte(seq_stream_byte_w),
    .seq_load_value(seq_load_value_w),
    .seq_load_bits(seq_load_bits_w),
    .payload_prefix_byte(payload_prefix_byte_w),
    .closed_header_len(closed_header_len_w),
    .closed_len(closed_len_w),
    .closed_leb_len(closed_leb_len_w),
    .seq_end_index(seq_end_index_w),
    .closed_leb_start(closed_leb_start_w),
    .closed_header_start(closed_header_start_w),
    .total_stream_len(total_stream_len_w),
    .tile_payload_start(tile_payload_start_w),
    .seq_stream_index(seq_stream_index_w),
    .closed_leb_index(closed_leb_index_w),
    .tile_stream_index(tile_stream_index_w),
    .output_tile_payload(output_tile_payload_w),
    .output_byte(output_byte_w)
  );

  ff_av2_local_hash_matcher_444 #(
    .SAMPLE_BITS(SAMPLE_BITS)
  ) local_hash_ibc (
    .clk(clk),
    .rst_n(rst_n),
    .start(palette_analyzer_start_w && (chroma_format_idc == 2'd3)),
    .sample_fire(input_sample_fire_w),
    .visible_width(tile_width_q),
    .visible_height(tile_height_q),
    .sample(s_axis_data),
    .sample_last(tile_input_last_w),
    .done(ibc_done_w),
    .any_copy(ibc_any_copy_w),
    .copy_mask(ibc_copy_mask_w),
    .above_copy_mask(ibc_above_copy_mask_w),
    .drl_idx_table(ibc_drl_idx_table_w)
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
    .chroma_format_idc(chroma_format_idc),
    .ibc_copy_mask(ibc_copy_mask_w),
    .sample(s_axis_data),
    .sample_last(tile_input_last_w),
    .sample_ready(palette_analyzer_sample_ready_w),
    .query_block_row_mi(block_row_mi_q),
    .query_block_col_mi(block_col_mi_q),
    .query_row(palette_row_q),
    .query_col(palette_col_q),
    .query_start(palette_query_start_w),
    .chroma_fetch_start(chroma_fetch_start_w),
    .chroma_fetch_plane_v(chroma_fetch_req_plane_v_w),
    .chroma_fetch_predictor_only(chroma_fetch_predictor_only_w),
    .chroma_fetch_txb_row_mi(chroma_fetch_req_row_mi_w),
    .chroma_fetch_txb_col_mi(chroma_fetch_req_col_mi_w),
    .luma_fetch_start(luma_fetch_start_w),
    .luma_fetch_txb_row_mi(luma_fetch_req_row_mi_w),
    .luma_fetch_txb_col_mi(luma_fetch_req_col_mi_w),
    .done(palette_analyzer_done_w),
    .unsupported(palette_analyzer_unsupported_w),
    .black_mode(palette_analyzer_black_w),
    .luma_palette_mode(palette_analyzer_luma_mode_w),
    .query_done(palette_query_done_w),
    .palette_size(palette_size_w),
    .palette_cache_size(palette_cache_size_w),
    .palette_colors(),
    .query_luma_mode(palette_luma_mode_w),
    .query_index(palette_current_index_w),
    .query_left_index(palette_left_index_w),
    .query_top_index(palette_top_index_w),
    .query_top_left_index(palette_top_left_index_w),
    .query_luma_residual_zero(palette_luma_residual_zero_w),
    .palette_first_color(palette_first_color_w),
    .palette_delta_bits_minus5(palette_delta_bits_minus5_w),
    .palette_delta_minus1(palette_delta_minus1_w),
    .palette_delta_literal_bits(palette_delta_literal_bits_w),
    .query_identity_row_flag(palette_identity_row_flag_w),
    .chroma_fetch_done(chroma_fetch_done_w),
    .chroma_fetch_txb_samples(chroma_fetch_txb_samples_w),
    .chroma_fetch_predictor_samples(chroma_fetch_predictor_samples_w),
    .chroma_fetch_u_txb_samples(chroma_fetch_u_txb_samples_w),
    .chroma_fetch_u_predictor_samples(chroma_fetch_u_predictor_samples_w),
    .chroma_fetch_v_txb_samples(chroma_fetch_v_txb_samples_w),
    .chroma_fetch_v_predictor_samples(chroma_fetch_v_predictor_samples_w),
    .luma_fetch_done(luma_fetch_done_w),
    .luma_fetch_txb_samples(luma_fetch_txb_samples_w),
    .luma_fetch_u_txb_samples(luma_fetch_u_txb_samples_w),
    .luma_fetch_v_txb_samples(luma_fetch_v_txb_samples_w),
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
    .palette_first_color(palette_first_color_w),
    .palette_delta_bits_minus5(palette_delta_bits_minus5_w),
    .palette_delta_minus1(palette_delta_minus1_w),
    .palette_delta_literal_bits(palette_delta_literal_bits_w),
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
    .enable(palette_luma_residual_enable_w),
    .advance(palette_luma_residual_advance_w),
    .plane_v(1'b0),
    .skip_ctx(luma_residual_skip_ctx_w),
    .dc_sign_ctx(luma_residual_dc_sign_ctx_w),
    .txb_samples(luma_fetch_txb_samples_w),
    .predictor_samples(32'd0),
    .predictor_txb_samples(luma_fetch_predictor_samples_w),
    .dc_delta(10'sd0),
    .dc_recon_sample(8'd0),
    .known_zero_txb(palette_luma_residual_zero_w),
    .op_valid(palette_luma_residual_op_valid_w),
    .op_literal(palette_luma_residual_op_literal_w),
    .op_literal_value(palette_luma_residual_op_literal_value_w),
    .op_literal_bits(palette_luma_residual_op_literal_bits_w),
    .op_fl(palette_luma_residual_op_fl_w),
    .op_fh(palette_luma_residual_op_fh_w),
    .op_fl_inc(palette_luma_residual_op_fl_inc_w),
    .op_fh_inc(palette_luma_residual_op_fh_inc_w),
    .txb_done(palette_luma_residual_txb_done_w),
    .txb_nonzero(),
    .entropy_context(palette_luma_residual_entropy_context_w),
    .latched_dc_recon_sample()
  );

  ff_av2_lossy420_dc_estimator lossy420_luma_dc_estimator (
    .samples(luma_fetch_txb_samples_w),
    .predictor(lossy420_luma_predictor_w),
    .delta(lossy420_luma_delta_w),
    .recon_sample(lossy420_luma_recon_sample_w),
    .zero_delta(lossy420_luma_known_zero_w)
  );

  ff_av2_dc_delta_txb_symbolizer #(
    .LUMA_PLANE(1)
  ) lossy420_luma_residual_symbolizer (
    .clk(clk),
    .rst_n(rst_n),
    .enable(lossy420_luma_residual_enable_w),
    .advance(lossy420_luma_residual_advance_w),
    .plane_v(1'b0),
    .skip_ctx(luma_residual_skip_ctx_w),
    .dc_sign_ctx(luma_residual_dc_sign_ctx_w),
    .dc_delta(lossy420_luma_delta_w),
    .dc_recon_sample(lossy420_luma_recon_sample_w),
    .known_zero_txb(lossy420_luma_known_zero_w),
    .op_valid(lossy420_luma_residual_op_valid_w),
    .op_literal(lossy420_luma_residual_op_literal_w),
    .op_literal_value(lossy420_luma_residual_op_literal_value_w),
    .op_literal_bits(lossy420_luma_residual_op_literal_bits_w),
    .op_fl(lossy420_luma_residual_op_fl_w),
    .op_fh(lossy420_luma_residual_op_fh_w),
    .op_fl_inc(lossy420_luma_residual_op_fl_inc_w),
    .op_fh_inc(lossy420_luma_residual_op_fh_inc_w),
    .txb_done(lossy420_luma_residual_txb_done_w),
    .txb_nonzero(),
    .entropy_context(lossy420_luma_residual_entropy_context_w),
    .latched_dc_recon_sample(lossy420_luma_residual_recon_sample_w)
  );

  ff_av2_chroma_bdpcm_symbolizer #(
    .LUMA_PALETTE_RESIDUAL(0)
  ) chroma_bdpcm_symbolizer (
    .clk(clk),
    .rst_n(rst_n),
    .enable(palette_chroma_bdpcm_enable_w),
    .advance(palette_chroma_bdpcm_advance_w),
    .plane_v(phase_q == PHASE_V_COEFF),
    .skip_ctx(chroma_bdpcm_skip_ctx_w),
    .dc_sign_ctx(2'd0),
    .txb_samples(chroma_bdpcm_txb_samples_w),
    .predictor_samples(chroma_bdpcm_predictor_samples_w),
    .predictor_txb_samples(128'd0),
    .dc_delta(10'sd0),
    .dc_recon_sample(8'd0),
    .known_zero_txb(1'b0),
    .op_valid(palette_chroma_bdpcm_op_valid_w),
    .op_literal(palette_chroma_bdpcm_op_literal_w),
    .op_literal_value(palette_chroma_bdpcm_op_literal_value_w),
    .op_literal_bits(palette_chroma_bdpcm_op_literal_bits_w),
    .op_fl(palette_chroma_bdpcm_op_fl_w),
    .op_fh(palette_chroma_bdpcm_op_fh_w),
    .op_fl_inc(palette_chroma_bdpcm_op_fl_inc_w),
    .op_fh_inc(palette_chroma_bdpcm_op_fh_inc_w),
    .txb_done(palette_chroma_bdpcm_txb_done_w),
    .txb_nonzero(palette_chroma_bdpcm_txb_nonzero_w),
    .entropy_context(palette_chroma_bdpcm_entropy_context_w),
    .latched_dc_recon_sample()
  );

  ff_av2_lossy420_dc_estimator lossy420_chroma_dc_estimator (
    .samples(chroma_bdpcm_txb_samples_w),
    .predictor(lossy420_chroma_predictor_w),
    .delta(lossy420_chroma_delta_w),
    .recon_sample(lossy420_chroma_recon_sample_w),
    .zero_delta(lossy420_chroma_known_zero_w)
  );

  ff_av2_dc_delta_txb_symbolizer #(
    .LUMA_PLANE(0)
  ) lossy420_chroma_bdpcm_symbolizer (
    .clk(clk),
    .rst_n(rst_n),
    .enable(lossy420_chroma_bdpcm_enable_w),
    .advance(lossy420_chroma_bdpcm_advance_w),
    .plane_v(phase_q == PHASE_V_COEFF),
    .skip_ctx(chroma_bdpcm_skip_ctx_w),
    .dc_sign_ctx(2'd0),
    .dc_delta(lossy420_chroma_delta_w),
    .dc_recon_sample(lossy420_chroma_recon_sample_w),
    .known_zero_txb(lossy420_chroma_known_zero_w),
    .op_valid(lossy420_chroma_bdpcm_op_valid_w),
    .op_literal(lossy420_chroma_bdpcm_op_literal_w),
    .op_literal_value(lossy420_chroma_bdpcm_op_literal_value_w),
    .op_literal_bits(lossy420_chroma_bdpcm_op_literal_bits_w),
    .op_fl(lossy420_chroma_bdpcm_op_fl_w),
    .op_fh(lossy420_chroma_bdpcm_op_fh_w),
    .op_fl_inc(lossy420_chroma_bdpcm_op_fl_inc_w),
    .op_fh_inc(lossy420_chroma_bdpcm_op_fh_inc_w),
    .txb_done(lossy420_chroma_bdpcm_txb_done_w),
    .txb_nonzero(lossy420_chroma_bdpcm_txb_nonzero_w),
    .entropy_context(lossy420_chroma_bdpcm_entropy_context_w),
    .latched_dc_recon_sample(lossy420_chroma_bdpcm_recon_sample_w)
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
    .ibc_use_copy(ibc_use_copy_w),
    .ibc_drl_idx(ibc_drl_idx_w),
    .intrabc_ctx(intrabc_ctx_w),
    .intrabc_skip_ctx(intrabc_skip_ctx_w),
    .leaf_luma_mode(leaf_luma_mode_q),
    .leaf_fsc_symbol(leaf_fsc_symbol_w),
    .leaf_fsc_fh(leaf_fsc_fh_w),
    .palette_mode(palette_mode_q),
    .residual_mode(residual_mode_w),
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
    !((chroma_format_idc == 2'd1) || (chroma_format_idc == 2'd3)) ||
    (frame_count == 32'd0) ||
    (visible_width == 16'd0) ||
    (visible_height == 16'd0) ||
    (visible_width[2:0] != 3'd0) ||
    (visible_height[2:0] != 3'd0);
  assign palette_analyzer_start_w = (state_q == ST_TILE_START);
  assign input_sample_fire_w = (state_q == ST_INPUT_READ) && s_axis_valid && s_axis_ready;
  assign tile_input_last_w = input_sample_fire_w && (tile_input_index_q == (tile_samples_w - 32'd1));
  assign stream_lookup_index_w =
    (state_q == ST_OUTPUT_VALID && m_axis_valid && m_axis_ready && !output_last_q) ?
      (stream_index_q + 16'd1) : stream_index_q;
  assign output_lookup_last_w = (stream_lookup_index_w == (total_stream_len_w - 16'd1));
  assign output_lookup_byte_w =
    output_tile_payload_w ? payload_mem_q[tile_stream_index_w] : output_byte_w;
  assign palette_query_start_w = (state_q == ST_PALETTE_QUERY);
  assign leaf_luma_palette_w = palette_mode_q && (leaf_luma_mode_q == LUMA_MODE_DC);
  assign residual_mode_w = palette_mode_q || lossy_420_mode_q;
  assign lossy420_luma_left_row_index_w = block_row_mi_q[3:0];
  assign lossy420_luma_external_left_valid_w =
    lossy420_luma_left_valid_q[lossy420_luma_left_row_index_w] &&
    ((lossy420_luma_left_col_mi_q[lossy420_luma_left_row_index_w] + 5'd2) ==
      block_col_mi_q);
  assign lossy420_luma_have_left_w =
    (txb_col_w[4:0] != 5'd0) &&
    (txb_index_q[0] || lossy420_luma_external_left_valid_w);
  assign lossy420_luma_have_top_w =
    (txb_row_w[4:0] != 5'd0) &&
    (txb_index_q[1] || lossy420_luma_above_valid_q[txb_col_w[3:0]]);
  assign lossy420_luma_left_sample_w =
    txb_index_q[0] ?
      lossy420_luma_recon_q[txb_index_q[1:0] - 2'd1] :
      (txb_index_q[1] ?
        lossy420_luma_left_bottom_q[lossy420_luma_left_row_index_w] :
        lossy420_luma_left_top_q[lossy420_luma_left_row_index_w]);
  assign lossy420_luma_top_sample_w =
    txb_index_q[1] ?
      lossy420_luma_recon_q[txb_index_q[1:0] - 2'd2] :
      lossy420_luma_above_q[txb_col_w[3:0]];
  assign lossy420_luma_predictor_w =
    (lossy420_luma_have_left_w && lossy420_luma_have_top_w) ?
      (({1'b0, lossy420_luma_left_sample_w} +
        {1'b0, lossy420_luma_top_sample_w} + 9'd1) >> 1) :
    lossy420_luma_have_left_w ? lossy420_luma_left_sample_w :
    lossy420_luma_have_top_w ? lossy420_luma_top_sample_w :
      8'd128;
  assign lossy420_chroma_left_row_index_w = txb_row_w[3:0];
  assign lossy420_chroma_external_left_valid_w =
    (phase_q == PHASE_V_COEFF) ?
      (lossy420_v_left_valid_q[lossy420_chroma_left_row_index_w] &&
       ((lossy420_v_left_col_mi_q[lossy420_chroma_left_row_index_w] + 5'd1) ==
        txb_col_w[4:0])) :
      (lossy420_u_left_valid_q[lossy420_chroma_left_row_index_w] &&
       ((lossy420_u_left_col_mi_q[lossy420_chroma_left_row_index_w] + 5'd1) ==
        txb_col_w[4:0]));
  assign lossy420_chroma_have_left_w =
    (txb_col_w[4:0] != 5'd0) &&
    lossy420_chroma_external_left_valid_w;
  assign lossy420_chroma_have_top_w =
    (txb_row_w[4:0] != 5'd0) &&
    ((phase_q == PHASE_V_COEFF) ?
      lossy420_v_above_valid_q[txb_col_w[3:0]] :
      lossy420_u_above_valid_q[txb_col_w[3:0]]);
  assign lossy420_chroma_left_sample_w =
    (phase_q == PHASE_V_COEFF) ?
      lossy420_v_left_q[lossy420_chroma_left_row_index_w] :
      lossy420_u_left_q[lossy420_chroma_left_row_index_w];
  assign lossy420_chroma_top_sample_w =
    (phase_q == PHASE_V_COEFF) ?
      lossy420_v_above_q[txb_col_w[3:0]] :
      lossy420_u_above_q[txb_col_w[3:0]];
  assign lossy420_chroma_predictor_w =
    (lossy420_chroma_have_left_w && lossy420_chroma_have_top_w) ?
      (({1'b0, lossy420_chroma_left_sample_w} +
        {1'b0, lossy420_chroma_top_sample_w} + 9'd1) >> 1) :
    lossy420_chroma_have_left_w ? lossy420_chroma_left_sample_w :
    lossy420_chroma_have_top_w ? lossy420_chroma_top_sample_w :
      8'd128;
  assign luma_residual_op_valid_w =
    lossy_420_mode_q ? lossy420_luma_residual_op_valid_w : palette_luma_residual_op_valid_w;
  assign luma_residual_op_literal_w =
    lossy_420_mode_q ? lossy420_luma_residual_op_literal_w : palette_luma_residual_op_literal_w;
  assign luma_residual_op_literal_value_w =
    lossy_420_mode_q ? lossy420_luma_residual_op_literal_value_w : palette_luma_residual_op_literal_value_w;
  assign luma_residual_op_literal_bits_w =
    lossy_420_mode_q ? lossy420_luma_residual_op_literal_bits_w : palette_luma_residual_op_literal_bits_w;
  assign luma_residual_op_fl_w =
    lossy_420_mode_q ? lossy420_luma_residual_op_fl_w : palette_luma_residual_op_fl_w;
  assign luma_residual_op_fh_w =
    lossy_420_mode_q ? lossy420_luma_residual_op_fh_w : palette_luma_residual_op_fh_w;
  assign luma_residual_op_fl_inc_w =
    lossy_420_mode_q ? lossy420_luma_residual_op_fl_inc_w : palette_luma_residual_op_fl_inc_w;
  assign luma_residual_op_fh_inc_w =
    lossy_420_mode_q ? lossy420_luma_residual_op_fh_inc_w : palette_luma_residual_op_fh_inc_w;
  assign luma_residual_txb_done_w =
    lossy_420_mode_q ? lossy420_luma_residual_txb_done_w : palette_luma_residual_txb_done_w;
  assign luma_residual_entropy_context_w =
    lossy_420_mode_q ? lossy420_luma_residual_entropy_context_w : palette_luma_residual_entropy_context_w;
  assign chroma_bdpcm_op_valid_w =
    lossy_420_mode_q ? lossy420_chroma_bdpcm_op_valid_w : palette_chroma_bdpcm_op_valid_w;
  assign chroma_bdpcm_op_literal_w =
    lossy_420_mode_q ? lossy420_chroma_bdpcm_op_literal_w : palette_chroma_bdpcm_op_literal_w;
  assign chroma_bdpcm_op_literal_value_w =
    lossy_420_mode_q ? lossy420_chroma_bdpcm_op_literal_value_w : palette_chroma_bdpcm_op_literal_value_w;
  assign chroma_bdpcm_op_literal_bits_w =
    lossy_420_mode_q ? lossy420_chroma_bdpcm_op_literal_bits_w : palette_chroma_bdpcm_op_literal_bits_w;
  assign chroma_bdpcm_op_fl_w =
    lossy_420_mode_q ? lossy420_chroma_bdpcm_op_fl_w : palette_chroma_bdpcm_op_fl_w;
  assign chroma_bdpcm_op_fh_w =
    lossy_420_mode_q ? lossy420_chroma_bdpcm_op_fh_w : palette_chroma_bdpcm_op_fh_w;
  assign chroma_bdpcm_op_fl_inc_w =
    lossy_420_mode_q ? lossy420_chroma_bdpcm_op_fl_inc_w : palette_chroma_bdpcm_op_fl_inc_w;
  assign chroma_bdpcm_op_fh_inc_w =
    lossy_420_mode_q ? lossy420_chroma_bdpcm_op_fh_inc_w : palette_chroma_bdpcm_op_fh_inc_w;
  assign chroma_bdpcm_txb_done_w =
    lossy_420_mode_q ? lossy420_chroma_bdpcm_txb_done_w : palette_chroma_bdpcm_txb_done_w;
  assign chroma_bdpcm_txb_nonzero_w =
    lossy_420_mode_q ? lossy420_chroma_bdpcm_txb_nonzero_w : palette_chroma_bdpcm_txb_nonzero_w;
  assign chroma_bdpcm_entropy_context_w =
    lossy_420_mode_q ? lossy420_chroma_bdpcm_entropy_context_w : palette_chroma_bdpcm_entropy_context_w;
  assign chroma_fetch_start_w =
    ((state_q == ST_CHROMA_FETCH) &&
     !txb_prefetch_started_q &&
     (phase_q == PHASE_U_COEFF || phase_q == PHASE_V_COEFF) &&
     !chroma_fetch_current_cache_hit_w) ||
    txb_prefetch_chroma_start_w ||
    (txb_prefetch_started_q && !txb_prefetch_done_q && txb_prefetch_chroma_q);
  assign luma_fetch_start_w =
    ((state_q == ST_CHROMA_FETCH) &&
     !txb_prefetch_started_q &&
     (phase_q == PHASE_Y_COEFF)) ||
    txb_prefetch_luma_start_w ||
    (txb_prefetch_started_q && !txb_prefetch_done_q && !txb_prefetch_chroma_q);
  assign luma_residual_advance_w =
    !start &&
    !pending_push_valid_q &&
    (state_q == ST_LEAF) &&
    residual_mode_w &&
    (phase_q == PHASE_Y_COEFF) &&
    luma_residual_op_valid_w;
  assign palette_luma_residual_advance_w = luma_residual_advance_w && palette_mode_q;
  assign lossy420_luma_residual_advance_w = luma_residual_advance_w && lossy_420_mode_q;
  assign luma_residual_enable_w =
    residual_mode_w &&
    (phase_q == PHASE_Y_COEFF) &&
    ((state_q == ST_LEAF) ||
     ((state_q == ST_CHROMA_FETCH) && luma_fetch_done_w));
  assign palette_luma_residual_enable_w = luma_residual_enable_w && palette_mode_q;
  assign lossy420_luma_residual_enable_w = luma_residual_enable_w && lossy_420_mode_q;
  assign chroma_bdpcm_advance_w =
    !start &&
    !pending_push_valid_q &&
    (state_q == ST_LEAF) &&
    residual_mode_w &&
    (phase_q == PHASE_U_COEFF || phase_q == PHASE_V_COEFF) &&
    chroma_bdpcm_op_valid_w;
  assign palette_chroma_bdpcm_advance_w = chroma_bdpcm_advance_w && palette_mode_q;
  assign lossy420_chroma_bdpcm_advance_w = chroma_bdpcm_advance_w && lossy_420_mode_q;
  assign chroma_residual_phase_w =
    residual_mode_w &&
    (phase_q == PHASE_U_COEFF || phase_q == PHASE_V_COEFF);
  assign chroma_bdpcm_fetch_ready_w =
    ((state_q == ST_LEAF) ||
     ((state_q == ST_CHROMA_FETCH) && chroma_fetch_done_w));
  assign palette_chroma_bdpcm_cache_ready_w =
    (state_q == ST_CHROMA_FETCH) && chroma_fetch_current_cache_hit_w;
  assign palette_chroma_bdpcm_enable_w =
    palette_mode_q &&
    chroma_residual_phase_w &&
    (chroma_bdpcm_fetch_ready_w || palette_chroma_bdpcm_cache_ready_w);
  assign lossy420_chroma_bdpcm_enable_w =
    lossy_420_mode_q &&
    chroma_residual_phase_w &&
    chroma_bdpcm_fetch_ready_w;

  // AV2 4:4:4 bring-up path: traverse one 64x64 superblock, split visible
  // coding leaves down to 8x8, and generate syntax through the range coder.
  // Any TX_4X4 loops below are AV2 transform blocks, not public input blocks.
  assign busy = (state_q != ST_IDLE);
  // AV2 bring-up input order is a visible 8x8 block packet: 64 Y samples,
  // 64 U samples, then 64 V samples. This mirrors the VVC 4:4:4 8x8-leaf
  // packing at the interface while allowing the AV2 superblock walker to keep
  // its own partition/leaf order internally.
  assign frame_reader_start_w = (state_q == ST_TILE_START);
  assign bitstream_writer_start_w = start && !busy;
  assign done = bitstream_writer_frame_done_w;
  assign axi_error = frame_reader_error_w || bitstream_writer_error_w;
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
  assign tile_luma_samples_w = {16'd0, tile_width_q} * {16'd0, tile_height_q};
  assign tile_samples_w =
    (chroma_format_idc == 2'd1) ?
      (tile_luma_samples_w + (tile_luma_samples_w >> 1)) :
      (tile_luma_samples_w * 32'd3);
  assign tile_is_last_w = (tile_index_q == (tile_count_q - 16'd1));
  assign multi_tile_w = (tile_count_q != 16'd1);
  assign payload_tile_start_w = payload_len_q + (tile_is_last_w ? 16'd0 : 16'd4);
  assign carry_sum_w = carry_q + precarry_read_data_q;
  assign visible_rows_mi_w = tile_height_q[6:2];
  assign visible_cols_mi_w = tile_width_q[6:2];
  assign ibc_current_block_id_w = {block_row_mi_q[3:1], block_col_mi_q[3:1]};
  assign ibc_drl_idx_bit_index_w = {ibc_current_block_id_w, 1'b0};
  assign ibc_use_copy_w =
    frame_ibc_mode_q &&
    (block_w_mi_q == 5'd2) &&
    (block_h_mi_q == 5'd2) &&
    ibc_copy_mask_w[ibc_current_block_id_w];
  assign ibc_drl_idx_w = ibc_drl_idx_table_w[ibc_drl_idx_bit_index_w +: 2];
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
  assign chroma_subsampled_phase_w =
    (chroma_format_idc == 2'd1) &&
    (phase_q == PHASE_U_COEFF || phase_q == PHASE_V_COEFF);
  assign txb_row_w = chroma_subsampled_phase_w ?
    {11'd0, (block_row_mi_q >> 1) + txb_local_row_q} :
    {11'd0, block_row_mi_q + txb_local_row_q};
  assign txb_col_w = chroma_subsampled_phase_w ?
    {11'd0, (block_col_mi_q >> 1) + txb_local_col_q} :
    {11'd0, block_col_mi_q + txb_local_col_q};
  assign same_phase_has_next_txb_w =
    residual_mode_w &&
    (phase_q == PHASE_Y_COEFF || phase_q == PHASE_U_COEFF || phase_q == PHASE_V_COEFF) &&
    (txb_index_q != (txb_count_q - 16'd1));
  assign cross_phase_has_next_txb_w =
    residual_mode_w &&
    (txb_index_q == (txb_count_q - 16'd1)) &&
    (phase_q == PHASE_Y_COEFF || phase_q == PHASE_U_COEFF);
  assign next_txb_local_col_w =
    (txb_local_col_q == (txb_width_q[4:0] - 5'd1)) ? 5'd0 : (txb_local_col_q + 5'd1);
  assign next_txb_local_row_w =
    (txb_local_col_q == (txb_width_q[4:0] - 5'd1)) ?
      (txb_local_row_q + 5'd1) : txb_local_row_q;
  assign next_txb_row_w = {11'd0, block_row_mi_q + next_txb_local_row_w};
  assign next_txb_col_w = {11'd0, block_col_mi_q + next_txb_local_col_w};
  assign txb_fetch_done_w =
    (phase_q == PHASE_Y_COEFF) ? luma_fetch_done_w :
    (phase_q == PHASE_U_COEFF) ? chroma_fetch_done_w :
    (phase_q == PHASE_V_COEFF) ? (chroma_fetch_done_w || v_chroma_cache_hit_w) : 1'b0;
  assign txb_prefetch_fetch_done_w = luma_fetch_done_w || chroma_fetch_done_w;
  assign v_chroma_cache_hit_w =
    palette_mode_q &&
    (phase_q == PHASE_V_COEFF) &&
    (cached_v_valid_q[txb_index_q[1:0]] || chroma_predictor_compute_valid_w);
  assign u_chroma_cache_hit_w =
    palette_mode_q &&
    (phase_q == PHASE_U_COEFF) &&
    chroma_predictor_compute_valid_w;
  assign chroma_fetch_current_cache_hit_w = u_chroma_cache_hit_w || v_chroma_cache_hit_w;
  assign chroma_fetch_cache_index_w =
    txb_prefetch_started_q ? txb_prefetch_index_q : txb_index_q[1:0];
  assign luma_fetch_cache_index_w =
    txb_prefetch_started_q ? txb_prefetch_index_q : txb_index_q[1:0];
  assign chroma_fetch_req_cross_phase_w =
    (state_q == ST_LEAF) &&
    cross_phase_has_next_txb_w &&
    !(same_phase_has_next_txb_w && (phase_q == PHASE_U_COEFF || phase_q == PHASE_V_COEFF));
  assign chroma_fetch_req_next_txb_w =
    (state_q == ST_LEAF) &&
    ((same_phase_has_next_txb_w && (phase_q == PHASE_U_COEFF || phase_q == PHASE_V_COEFF)) ||
     cross_phase_has_next_txb_w);
  assign chroma_fetch_req_index_w =
    chroma_fetch_req_cross_phase_w ? 2'd0 :
    (chroma_fetch_req_next_txb_w ? (txb_index_q[1:0] + 2'd1) : txb_index_q[1:0]);
  // The cached predictor shortcut is intentionally limited to cases that
  // match ff_av2_palette_analyzer_444's fetch_pred_read_addr_w sequence: the
  // tile top-left constant and left-edge predictors from the previous 4x4 TXB.
  assign chroma_predictor_compute_valid_w =
    cached_chroma_samples_valid_q[txb_index_q[1:0]] &&
    (((txb_row_w[4:0] == 5'd0) && (txb_col_w[4:0] == 5'd0)) ||
     txb_col_w[0] ||
     chroma_external_left_predictor_valid_w ||
     chroma_external_above_predictor_valid_w ||
     ((txb_col_w[4:0] == 5'd0) && txb_row_w[0]));
  assign chroma_fetch_req_predictor_compute_w =
    cached_chroma_samples_valid_q[chroma_fetch_req_index_w] &&
    (((chroma_fetch_req_row_mi_w == 5'd0) && (chroma_fetch_req_col_mi_w == 5'd0)) ||
     chroma_fetch_req_col_mi_w[0] ||
     chroma_req_external_left_predictor_valid_w ||
     chroma_req_external_above_predictor_valid_w ||
     ((chroma_fetch_req_col_mi_w == 5'd0) && chroma_fetch_req_row_mi_w[0]));
  assign chroma_external_left_predictor_valid_w =
    (txb_col_w[4:0] != 5'd0) &&
    !txb_col_w[0] &&
    left_edge_valid_q &&
    (left_edge_row_mi_q == block_row_mi_q) &&
    ((left_edge_col_mi_q + 5'd2) == block_col_mi_q);
  assign chroma_req_external_left_predictor_valid_w =
    (chroma_fetch_req_col_mi_w != 5'd0) &&
    !chroma_fetch_req_col_mi_w[0] &&
    left_edge_valid_q &&
    (left_edge_row_mi_q == block_row_mi_q) &&
    ((left_edge_col_mi_q + 5'd2) == block_col_mi_q);
  assign chroma_external_above_predictor_valid_w =
    (txb_col_w[4:0] == 5'd0) &&
    (txb_row_w[4:0] != 5'd0) &&
    !txb_row_w[0] &&
    above_col0_valid_q &&
    ((above_col0_row_mi_q + 5'd2) == block_row_mi_q);
  assign chroma_req_external_above_predictor_valid_w =
    (chroma_fetch_req_col_mi_w == 5'd0) &&
    (chroma_fetch_req_row_mi_w != 5'd0) &&
    !chroma_fetch_req_row_mi_w[0] &&
    above_col0_valid_q &&
    ((above_col0_row_mi_q + 5'd2) == block_row_mi_q);
  assign chroma_fetch_req_ready_w =
    palette_mode_q &&
    (chroma_fetch_req_predictor_compute_w ||
     (chroma_fetch_req_plane_v_w && cached_v_valid_q[chroma_fetch_req_index_w]));
  assign chroma_fetch_predictor_only_w =
    palette_mode_q &&
    cached_chroma_samples_valid_q[chroma_fetch_req_index_w] &&
    !chroma_fetch_req_predictor_compute_w;
  assign chroma_fetch_completed_u_w =
    chroma_fetch_done_w &&
    (txb_prefetch_started_q ?
      (txb_prefetch_chroma_q && !txb_prefetch_plane_v_q) :
      (phase_q == PHASE_U_COEFF));
  assign luma_fetch_completed_w =
    luma_fetch_done_w &&
    (txb_prefetch_started_q ? !txb_prefetch_chroma_q : (phase_q == PHASE_Y_COEFF));
  assign txb_prefetch_chroma_target_v_w =
    ((same_phase_has_next_txb_w && (phase_q == PHASE_V_COEFF)) ||
     (cross_phase_has_next_txb_w && (phase_q == PHASE_U_COEFF)));
  assign txb_prefetch_luma_start_w =
    !start &&
    !pending_push_valid_q &&
    (state_q == ST_LEAF) &&
    ((same_phase_has_next_txb_w && (phase_q == PHASE_Y_COEFF)) ||
     ((phase_q == PHASE_INTRA ||
       phase_q == PHASE_PALETTE_HEADER ||
       phase_q == PHASE_PALETTE_MAP) &&
      residual_mode_w &&
      (txb_index_q == 16'd0))) &&
    !txb_prefetch_started_q &&
    !luma_fetch_done_w;
  assign txb_prefetch_chroma_start_w =
    !start &&
    !pending_push_valid_q &&
    (state_q == ST_LEAF) &&
    ((same_phase_has_next_txb_w && (phase_q == PHASE_U_COEFF || phase_q == PHASE_V_COEFF)) ||
     cross_phase_has_next_txb_w) &&
    !txb_prefetch_started_q &&
    !txb_prefetch_chroma_target_v_w &&
    !chroma_fetch_req_predictor_compute_w &&
    !chroma_fetch_done_w;
  assign txb_prefetch_cross_phase_w =
    txb_prefetch_chroma_start_w &&
    chroma_fetch_req_cross_phase_w;
  assign txb_prefetch_first_luma_w =
    txb_prefetch_luma_start_w &&
    (phase_q == PHASE_INTRA || phase_q == PHASE_PALETTE_HEADER || phase_q == PHASE_PALETTE_MAP);
  assign luma_fetch_req_row_mi_w =
    txb_prefetch_first_luma_w ? block_row_mi_q :
    (txb_prefetch_luma_start_w ? next_txb_row_w[4:0] : txb_row_w[4:0]);
  assign luma_fetch_req_col_mi_w =
    txb_prefetch_first_luma_w ? block_col_mi_q :
    (txb_prefetch_luma_start_w ? next_txb_col_w[4:0] : txb_col_w[4:0]);
  assign chroma_fetch_current_storage_row_mi_w =
    (chroma_format_idc == 2'd1) ?
      (block_row_mi_q + (txb_local_row_q << 1)) :
      txb_row_w[4:0];
  assign chroma_fetch_current_storage_col_mi_w =
    (chroma_format_idc == 2'd1) ?
      (block_col_mi_q + (txb_local_col_q << 1)) :
      txb_col_w[4:0];
  assign chroma_fetch_next_storage_row_mi_w =
    (chroma_format_idc == 2'd1) ?
      (block_row_mi_q + (next_txb_local_row_w << 1)) :
      next_txb_row_w[4:0];
  assign chroma_fetch_next_storage_col_mi_w =
    (chroma_format_idc == 2'd1) ?
      (block_col_mi_q + (next_txb_local_col_w << 1)) :
      next_txb_col_w[4:0];
  assign chroma_fetch_req_row_mi_w =
    chroma_fetch_req_cross_phase_w ? block_row_mi_q :
    (chroma_fetch_req_next_txb_w ?
      chroma_fetch_next_storage_row_mi_w :
      chroma_fetch_current_storage_row_mi_w);
  assign chroma_fetch_req_col_mi_w =
    chroma_fetch_req_cross_phase_w ? block_col_mi_q :
    (chroma_fetch_req_next_txb_w ?
      chroma_fetch_next_storage_col_mi_w :
      chroma_fetch_current_storage_col_mi_w);
  assign chroma_fetch_req_plane_v_w =
    chroma_fetch_req_cross_phase_w ? (phase_q == PHASE_U_COEFF) : (phase_q == PHASE_V_COEFF);
  assign chroma_left_source_index_w = txb_index_q[1:0] - 2'd1;
  assign chroma_above_source_index_w = txb_index_q[1:0] - txb_width_q[1:0];
  assign cached_u_left_predictor_w = {
    cached_u_txb_samples_q[chroma_left_source_index_w][15 * 8 +: 8],
    cached_u_txb_samples_q[chroma_left_source_index_w][11 * 8 +: 8],
    cached_u_txb_samples_q[chroma_left_source_index_w][7 * 8 +: 8],
    cached_u_txb_samples_q[chroma_left_source_index_w][3 * 8 +: 8]
  };
  assign cached_v_left_predictor_w = {
    cached_v_txb_samples_q[chroma_left_source_index_w][15 * 8 +: 8],
    cached_v_txb_samples_q[chroma_left_source_index_w][11 * 8 +: 8],
    cached_v_txb_samples_q[chroma_left_source_index_w][7 * 8 +: 8],
    cached_v_txb_samples_q[chroma_left_source_index_w][3 * 8 +: 8]
  };
  assign cached_u_above_predictor_w = {
    cached_u_txb_samples_q[chroma_above_source_index_w][12 * 8 +: 8],
    cached_u_txb_samples_q[chroma_above_source_index_w][12 * 8 +: 8],
    cached_u_txb_samples_q[chroma_above_source_index_w][12 * 8 +: 8],
    cached_u_txb_samples_q[chroma_above_source_index_w][12 * 8 +: 8]
  };
  assign cached_v_above_predictor_w = {
    cached_v_txb_samples_q[chroma_above_source_index_w][12 * 8 +: 8],
    cached_v_txb_samples_q[chroma_above_source_index_w][12 * 8 +: 8],
    cached_v_txb_samples_q[chroma_above_source_index_w][12 * 8 +: 8],
    cached_v_txb_samples_q[chroma_above_source_index_w][12 * 8 +: 8]
  };
  assign cached_u_external_left_predictor_w =
    txb_row_w[0] ? left_edge_u_bottom_q : left_edge_u_top_q;
  assign cached_v_external_left_predictor_w =
    txb_row_w[0] ? left_edge_v_bottom_q : left_edge_v_top_q;
  assign cached_u_external_above_predictor_w = above_col0_u_q;
  assign cached_v_external_above_predictor_w = above_col0_v_q;
  assign chroma_cached_predictor_samples_w =
    ((txb_row_w[4:0] == 5'd0) && (txb_col_w[4:0] == 5'd0)) ? 32'h81818181 :
    txb_col_w[0] ?
      ((phase_q == PHASE_V_COEFF) ? cached_v_left_predictor_w : cached_u_left_predictor_w) :
    chroma_external_left_predictor_valid_w ?
      ((phase_q == PHASE_V_COEFF) ?
        cached_v_external_left_predictor_w : cached_u_external_left_predictor_w) :
    chroma_external_above_predictor_valid_w ?
      ((phase_q == PHASE_V_COEFF) ?
        cached_v_external_above_predictor_w : cached_u_external_above_predictor_w) :
      ((phase_q == PHASE_V_COEFF) ? cached_v_above_predictor_w : cached_u_above_predictor_w);
  assign current_u_right_edge_top_w = {
    cached_u_txb_samples_q[2'd1][15 * 8 +: 8],
    cached_u_txb_samples_q[2'd1][11 * 8 +: 8],
    cached_u_txb_samples_q[2'd1][7 * 8 +: 8],
    cached_u_txb_samples_q[2'd1][3 * 8 +: 8]
  };
  assign current_u_right_edge_bottom_w = {
    cached_u_txb_samples_q[2'd3][15 * 8 +: 8],
    cached_u_txb_samples_q[2'd3][11 * 8 +: 8],
    cached_u_txb_samples_q[2'd3][7 * 8 +: 8],
    cached_u_txb_samples_q[2'd3][3 * 8 +: 8]
  };
  assign current_v_right_edge_top_w = {
    cached_v_txb_samples_q[2'd1][15 * 8 +: 8],
    cached_v_txb_samples_q[2'd1][11 * 8 +: 8],
    cached_v_txb_samples_q[2'd1][7 * 8 +: 8],
    cached_v_txb_samples_q[2'd1][3 * 8 +: 8]
  };
  assign current_v_right_edge_bottom_w = {
    cached_v_txb_samples_q[2'd3][15 * 8 +: 8],
    cached_v_txb_samples_q[2'd3][11 * 8 +: 8],
    cached_v_txb_samples_q[2'd3][7 * 8 +: 8],
    cached_v_txb_samples_q[2'd3][3 * 8 +: 8]
  };
  assign current_u_col0_above_edge_w = {
    cached_u_txb_samples_q[2'd2][12 * 8 +: 8],
    cached_u_txb_samples_q[2'd2][12 * 8 +: 8],
    cached_u_txb_samples_q[2'd2][12 * 8 +: 8],
    cached_u_txb_samples_q[2'd2][12 * 8 +: 8]
  };
  assign current_v_col0_above_edge_w = {
    cached_v_txb_samples_q[2'd2][12 * 8 +: 8],
    cached_v_txb_samples_q[2'd2][12 * 8 +: 8],
    cached_v_txb_samples_q[2'd2][12 * 8 +: 8],
    cached_v_txb_samples_q[2'd2][12 * 8 +: 8]
  };
  assign chroma_bdpcm_txb_samples_w =
    lossy_420_mode_q ? chroma_fetch_txb_samples_w :
    ((phase_q == PHASE_V_COEFF) && cached_chroma_samples_valid_q[txb_index_q[1:0]]) ?
      cached_v_txb_samples_q[txb_index_q[1:0]] :
    ((phase_q == PHASE_U_COEFF) && cached_chroma_samples_valid_q[txb_index_q[1:0]]) ?
      cached_u_txb_samples_q[txb_index_q[1:0]] :
      chroma_fetch_txb_samples_w;
  assign chroma_bdpcm_predictor_samples_w =
    ((phase_q == PHASE_V_COEFF) && cached_v_valid_q[txb_index_q[1:0]]) ?
      cached_v_predictor_samples_q[txb_index_q[1:0]] :
    chroma_predictor_compute_valid_w ?
      chroma_cached_predictor_samples_w :
      chroma_fetch_predictor_samples_w;
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
      (((chroma_format_idc == 2'd1) ? 4'd0 : 4'd3) +
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
  assign chroma_txb_width_w =
    (chroma_format_idc == 2'd1) ? {11'd0, leaf_visible_txb_w_w[4:1]} : txb_width_w;
  assign chroma_txb_count_w =
    (chroma_format_idc == 2'd1) ?
      ({11'd0, leaf_visible_txb_w_w[4:1]} * {11'd0, leaf_visible_txb_h_w[4:1]}) :
      txb_count_w;

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
          if (finish_s_q > 8'sd0) begin
            precarry_write_valid_w = 1'b1;
            precarry_write_addr_w = precarry_len_q;
            precarry_write_data_w =
              (finish_e_q >> (finish_c_q[5:0] + 6'd16)) & 16'hffff;
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
    seq_stream_byte_w = 8'd0;
    if ((stream_lookup_index_w >= 16'd4) && (stream_lookup_index_w < seq_end_index_w)) begin
      seq_stream_byte_w = seq_mem_q[seq_stream_index_w];
    end
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
      // AV2 v1.0.0 read_tx_block()/get_txb_ctx(): V TXB skip contexts use
      // the retained U-plane EOB flag. 4:4:4 adds the chroma-block-larger-
      // than-TXB offset, landing on ctx9..11 here; 4:2:0 chroma is exactly
      // one 4x4 TXB per 8x8 luma block, landing on ctx6..8 instead.
      v_txb_nonzero_fh_w = (chroma_format_idc == 2'd1) ? 32'd25120 : 32'd16384;
      y_dc_sign_fl_w = 32'd16937;
    end else if (txb_row_w == 16'd0 || txb_col_w == 16'd0) begin
      y_txb_nonzero_fh_w = 32'd24824;
      u_txb_nonzero_fh_w = 32'd19113;
      v_txb_nonzero_fh_w = (chroma_format_idc == 2'd1) ? 32'd16620 : 32'd16384;
      y_dc_sign_fl_w = 32'd19136;
    end else begin
      y_txb_nonzero_fh_w = 32'd3692;
      u_txb_nonzero_fh_w = 32'd10420;
      v_txb_nonzero_fh_w = (chroma_format_idc == 2'd1) ? 32'd8203 : 32'd16384;
      y_dc_sign_fl_w = 32'd19136;
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      input_error <= frame_reader_error_w || bitstream_writer_error_w;
      state_q <= ST_IDLE;
      m_axis_valid <= 1'b0;
      m_axis_data <= 8'd0;
      m_axis_last <= 1'b0;
      low_q <= 64'd0;
      rng_q <= 32'h8000;
      cnt_q <= -8'sd9;
      precarry_read_addr_q <= 16'd0;
      pending_push_valid_q <= 1'b0;
      pending_push_word_q <= 16'd0;
      precarry_len_q <= 16'd0;
      tile_len_q <= 16'd0;
      payload_len_q <= 16'd0;
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
      lossy_420_mode_q <= 1'b0;
      leaf_luma_mode_q <= LUMA_MODE_DC;
      lossy420_luma_recon_q[0] <= 8'd128;
      lossy420_luma_recon_q[1] <= 8'd128;
      lossy420_luma_recon_q[2] <= 8'd128;
      lossy420_luma_recon_q[3] <= 8'd128;
      lossy420_luma_left_valid_q <= 16'd0;
      lossy420_luma_above_valid_q <= 16'd0;
      lossy420_u_left_valid_q <= 16'd0;
      lossy420_v_left_valid_q <= 16'd0;
      lossy420_u_above_valid_q <= 16'd0;
      lossy420_v_above_valid_q <= 16'd0;
      txb_index_q <= 16'd0;
      txb_width_q <= 16'd0;
      txb_count_q <= 16'd0;
      txb_local_row_q <= 5'd0;
      txb_local_col_q <= 5'd0;
      txb_prefetch_started_q <= 1'b0;
      txb_prefetch_done_q <= 1'b0;
      txb_prefetch_chroma_q <= 1'b0;
      txb_prefetch_plane_v_q <= 1'b0;
      txb_prefetch_index_q <= 2'd0;
      cached_v_valid_q <= 4'd0;
      cached_chroma_samples_valid_q <= 4'd0;
      left_edge_u_top_q <= 32'd0;
      left_edge_u_bottom_q <= 32'd0;
      left_edge_v_top_q <= 32'd0;
      left_edge_v_bottom_q <= 32'd0;
      left_edge_row_mi_q <= 5'd0;
      left_edge_col_mi_q <= 5'd0;
      left_edge_valid_q <= 1'b0;
      above_col0_u_q <= 32'd0;
      above_col0_v_q <= 32'd0;
      above_col0_row_mi_q <= 5'd0;
      above_col0_valid_q <= 1'b0;
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
      finish_c_q <= 8'sd0;
      finish_s_q <= 8'sd0;
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
        lossy420_luma_above_q[context_index_q] <= 8'd128;
        lossy420_luma_left_top_q[context_index_q] <= 8'd128;
        lossy420_luma_left_bottom_q[context_index_q] <= 8'd128;
        lossy420_luma_left_col_mi_q[context_index_q] <= 5'd0;
        lossy420_u_above_q[context_index_q] <= 8'd128;
        lossy420_v_above_q[context_index_q] <= 8'd128;
        lossy420_u_left_q[context_index_q] <= 8'd128;
        lossy420_v_left_q[context_index_q] <= 8'd128;
        lossy420_u_left_col_mi_q[context_index_q] <= 5'd0;
        lossy420_v_left_col_mi_q[context_index_q] <= 5'd0;
      end
    end else begin
      input_error <= 1'b0;
      if (luma_fetch_completed_w) begin
        cached_u_txb_samples_q[luma_fetch_cache_index_w] <= luma_fetch_u_txb_samples_w;
        cached_v_txb_samples_q[luma_fetch_cache_index_w] <= luma_fetch_v_txb_samples_w;
        cached_chroma_samples_valid_q[luma_fetch_cache_index_w] <= 1'b1;
      end
      if (chroma_fetch_completed_u_w) begin
        if (!cached_chroma_samples_valid_q[chroma_fetch_cache_index_w]) begin
          cached_v_txb_samples_q[chroma_fetch_cache_index_w] <= chroma_fetch_v_txb_samples_w;
          cached_chroma_samples_valid_q[chroma_fetch_cache_index_w] <= 1'b1;
        end
        cached_v_predictor_samples_q[chroma_fetch_cache_index_w] <= chroma_fetch_v_predictor_samples_w;
        cached_v_valid_q[chroma_fetch_cache_index_w] <= 1'b1;
      end
      if (start) begin
        input_error <= start_invalid_w;
        if (!start_invalid_w && state_q == ST_IDLE) begin
          state_q <= ST_TILE_START;
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
          cnt_q <= -8'sd9;
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
          lossy_420_mode_q <= 1'b0;
          leaf_luma_mode_q <= LUMA_MODE_DC;
          lossy420_luma_recon_q[0] <= 8'd128;
          lossy420_luma_recon_q[1] <= 8'd128;
          lossy420_luma_recon_q[2] <= 8'd128;
          lossy420_luma_recon_q[3] <= 8'd128;
          lossy420_luma_left_valid_q <= 16'd0;
          lossy420_luma_above_valid_q <= 16'd0;
          lossy420_u_left_valid_q <= 16'd0;
          lossy420_v_left_valid_q <= 16'd0;
          lossy420_u_above_valid_q <= 16'd0;
          lossy420_v_above_valid_q <= 16'd0;
          txb_index_q <= 16'd0;
          txb_width_q <= 16'd0;
          txb_count_q <= 16'd0;
          txb_local_row_q <= 5'd0;
          txb_local_col_q <= 5'd0;
          txb_prefetch_started_q <= 1'b0;
          txb_prefetch_done_q <= 1'b0;
          txb_prefetch_chroma_q <= 1'b0;
          txb_prefetch_plane_v_q <= 1'b0;
          txb_prefetch_index_q <= 2'd0;
          cached_v_valid_q <= 4'd0;
          cached_chroma_samples_valid_q <= 4'd0;
          left_edge_u_top_q <= 32'd0;
          left_edge_u_bottom_q <= 32'd0;
          left_edge_v_top_q <= 32'd0;
          left_edge_v_bottom_q <= 32'd0;
          left_edge_row_mi_q <= 5'd0;
          left_edge_col_mi_q <= 5'd0;
          left_edge_valid_q <= 1'b0;
          above_col0_u_q <= 32'd0;
          above_col0_v_q <= 32'd0;
          above_col0_row_mi_q <= 5'd0;
          above_col0_valid_q <= 1'b0;
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
        if (txb_prefetch_started_q && txb_prefetch_fetch_done_w) begin
          txb_prefetch_done_q <= 1'b1;
        end
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
                lossy_420_mode_q <=
                  (chroma_format_idc == 2'd1) && !palette_analyzer_black_w;
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
                cnt_q <= -8'sd9;
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
                lossy420_luma_recon_q[0] <= 8'd128;
                lossy420_luma_recon_q[1] <= 8'd128;
                lossy420_luma_recon_q[2] <= 8'd128;
                lossy420_luma_recon_q[3] <= 8'd128;
                lossy420_luma_left_valid_q <= 16'd0;
                lossy420_luma_above_valid_q <= 16'd0;
                lossy420_u_left_valid_q <= 16'd0;
                lossy420_v_left_valid_q <= 16'd0;
                lossy420_u_above_valid_q <= 16'd0;
                lossy420_v_above_valid_q <= 16'd0;
                txb_index_q <= 16'd0;
                txb_width_q <= 16'd0;
                txb_count_q <= 16'd0;
                txb_local_row_q <= 5'd0;
                txb_local_col_q <= 5'd0;
                txb_prefetch_started_q <= 1'b0;
                txb_prefetch_done_q <= 1'b0;
                txb_prefetch_chroma_q <= 1'b0;
                txb_prefetch_plane_v_q <= 1'b0;
                txb_prefetch_index_q <= 2'd0;
                cached_v_valid_q <= 4'd0;
                cached_chroma_samples_valid_q <= 4'd0;
                left_edge_u_top_q <= 32'd0;
                left_edge_u_bottom_q <= 32'd0;
                left_edge_v_top_q <= 32'd0;
                left_edge_v_bottom_q <= 32'd0;
                left_edge_row_mi_q <= 5'd0;
                left_edge_col_mi_q <= 5'd0;
                left_edge_valid_q <= 1'b0;
                above_col0_u_q <= 32'd0;
                above_col0_v_q <= 32'd0;
                above_col0_row_mi_q <= 5'd0;
                above_col0_valid_q <= 1'b0;
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
                  lossy420_luma_above_q[context_index_q] <= 8'd128;
                  lossy420_luma_left_top_q[context_index_q] <= 8'd128;
                  lossy420_luma_left_bottom_q[context_index_q] <= 8'd128;
                  lossy420_luma_left_col_mi_q[context_index_q] <= 5'd0;
                  lossy420_u_above_q[context_index_q] <= 8'd128;
                  lossy420_v_above_q[context_index_q] <= 8'd128;
                  lossy420_u_left_q[context_index_q] <= 8'd128;
                  lossy420_v_left_q[context_index_q] <= 8'd128;
                  lossy420_u_left_col_mi_q[context_index_q] <= 5'd0;
                  lossy420_v_left_col_mi_q[context_index_q] <= 5'd0;
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
                txb_prefetch_started_q <= 1'b0;
                txb_prefetch_done_q <= 1'b0;
                txb_prefetch_plane_v_q <= 1'b0;
                txb_prefetch_index_q <= 2'd0;
                cached_v_valid_q <= 4'd0;
                cached_chroma_samples_valid_q <= 4'd0;
                lossy420_luma_recon_q[0] <= 8'd128;
                lossy420_luma_recon_q[1] <= 8'd128;
                lossy420_luma_recon_q[2] <= 8'd128;
                lossy420_luma_recon_q[3] <= 8'd128;
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
              txb_prefetch_started_q <= 1'b0;
              txb_prefetch_done_q <= 1'b0;
              txb_prefetch_plane_v_q <= 1'b0;
              txb_prefetch_index_q <= 2'd0;
              cached_v_valid_q <= 4'd0;
              cached_chroma_samples_valid_q <= 4'd0;
              lossy420_luma_recon_q[0] <= 8'd128;
              lossy420_luma_recon_q[1] <= 8'd128;
              lossy420_luma_recon_q[2] <= 8'd128;
              lossy420_luma_recon_q[3] <= 8'd128;
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
            if (txb_prefetch_luma_start_w || txb_prefetch_chroma_start_w) begin
              txb_prefetch_started_q <= 1'b1;
              txb_prefetch_done_q <= 1'b0;
              txb_prefetch_chroma_q <= txb_prefetch_chroma_start_w;
              txb_prefetch_plane_v_q <= chroma_fetch_req_plane_v_w;
              txb_prefetch_index_q <=
                (txb_prefetch_cross_phase_w || txb_prefetch_first_luma_w) ?
                  2'd0 : (txb_index_q[1:0] + 2'd1);
            end else if (txb_prefetch_started_q && txb_prefetch_fetch_done_w) begin
              txb_prefetch_done_q <= 1'b1;
            end

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
                if (step_q == 5'd0 && !ibc_use_copy_w) begin
                  phase_q <= PHASE_INTRA;
                  step_q <= 5'd0;
                  leaf_luma_mode_q <= LUMA_MODE_DC;
                  state_q <= palette_mode_q ? ST_PALETTE_QUERY : ST_LEAF;
                end else if ((step_q == 5'd3 && ibc_drl_idx_w == 2'd0) ||
                             (step_q == 5'd4 && ibc_drl_idx_w == 2'd1) ||
                             (step_q == 5'd5)) begin
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
                txb_prefetch_started_q <= 1'b0;
                txb_prefetch_done_q <= 1'b0;
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
                  if (residual_mode_w && !leaf_luma_palette_w) begin
                    if (txb_prefetch_done_q) begin
                      txb_prefetch_started_q <= 1'b0;
                      txb_prefetch_done_q <= 1'b0;
                      state_q <= ST_LEAF;
                    end else begin
                      txb_prefetch_started_q <= 1'b0;
                      txb_prefetch_done_q <= 1'b0;
                      state_q <= ST_CHROMA_FETCH;
                    end
                  end else if (!residual_mode_w) begin
                    txb_prefetch_started_q <= 1'b0;
                    txb_prefetch_done_q <= 1'b0;
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
                    if (txb_prefetch_done_q) begin
                      txb_prefetch_started_q <= 1'b0;
                      txb_prefetch_done_q <= 1'b0;
                      state_q <= ST_LEAF;
                    end else begin
                      txb_prefetch_started_q <= txb_prefetch_started_q;
                      txb_prefetch_done_q <= txb_prefetch_done_q;
                      state_q <= ST_CHROMA_FETCH;
                    end
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
                  if (txb_prefetch_done_q) begin
                    txb_prefetch_started_q <= 1'b0;
                    txb_prefetch_done_q <= 1'b0;
                    state_q <= ST_LEAF;
                  end else begin
                    txb_prefetch_started_q <= txb_prefetch_started_q;
                    txb_prefetch_done_q <= txb_prefetch_done_q;
                    state_q <= ST_CHROMA_FETCH;
                  end
                end else begin
                  palette_row_q <= palette_row_q + 6'd1;
                  palette_col_q <= 6'd0;
                  step_q <= 5'd1;
                end
              end else if (phase_q == PHASE_Y_COEFF) begin
                if ((residual_mode_w && luma_residual_txb_done_w) || (!residual_mode_w && step_q == 5'd8)) begin
                  if (residual_mode_w) begin
                    y_txb_above_q[txb_col_w[4:0]] <= luma_residual_entropy_context_w;
                    y_txb_left_q[txb_row_w[4:0]] <= luma_residual_entropy_context_w;
                  end
                  if (lossy_420_mode_q) begin
                    lossy420_luma_recon_q[txb_index_q[1:0]] <=
                      lossy420_luma_residual_recon_sample_w;
                    lossy420_luma_above_q[txb_col_w[3:0]] <=
                      lossy420_luma_residual_recon_sample_w;
                    lossy420_luma_above_valid_q[txb_col_w[3:0]] <= 1'b1;
                    if (txb_index_q[0]) begin
                      if (txb_index_q[1]) begin
                        lossy420_luma_left_bottom_q[lossy420_luma_left_row_index_w] <=
                          lossy420_luma_residual_recon_sample_w;
                        lossy420_luma_left_valid_q[lossy420_luma_left_row_index_w] <= 1'b1;
                        lossy420_luma_left_col_mi_q[lossy420_luma_left_row_index_w] <=
                          block_col_mi_q;
                      end else begin
                        lossy420_luma_left_top_q[lossy420_luma_left_row_index_w] <=
                          lossy420_luma_residual_recon_sample_w;
                      end
                    end
                  end
                  if (txb_index_q == (txb_count_q - 16'd1)) begin
                    phase_q <= PHASE_U_COEFF;
                    step_q <= 5'd0;
                    txb_index_q <= 16'd0;
                    txb_width_q <= chroma_txb_width_w;
                    txb_count_q <= chroma_txb_count_w;
                    txb_local_row_q <= 5'd0;
                    txb_local_col_q <= 5'd0;
                    txb_prefetch_started_q <= 1'b0;
                    txb_prefetch_done_q <= 1'b0;
                    last_u_txb_nonzero_q <= 1'b0;
                    if (residual_mode_w) begin
                      if ((txb_prefetch_done_q && txb_prefetch_chroma_q && !txb_prefetch_plane_v_q) ||
                          chroma_fetch_req_ready_w) begin
                        txb_prefetch_started_q <= 1'b0;
                        txb_prefetch_done_q <= 1'b0;
                        state_q <= ST_LEAF;
                      end else begin
                        txb_prefetch_started_q <= 1'b0;
                        txb_prefetch_done_q <= 1'b0;
                        state_q <= ST_CHROMA_FETCH;
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
                    if (residual_mode_w) begin
                      if (txb_prefetch_done_q && !txb_prefetch_chroma_q) begin
                        txb_prefetch_started_q <= 1'b0;
                        txb_prefetch_done_q <= 1'b0;
                        state_q <= ST_LEAF;
                      end else begin
                        state_q <= ST_CHROMA_FETCH;
                      end
                    end
                  end
                end else begin
                  step_q <= step_q + 5'd1;
                end
              end else begin
                if ((residual_mode_w && chroma_bdpcm_txb_done_w) || (!residual_mode_w && step_q == 7'd7)) begin
                  if (residual_mode_w) begin
                    if (phase_q == PHASE_U_COEFF) begin
                      u_txb_above_q[txb_col_w[4:0]] <= chroma_bdpcm_entropy_context_w;
                      u_txb_left_q[txb_row_w[4:0]] <= chroma_bdpcm_entropy_context_w;
                      last_u_txb_nonzero_q <= chroma_bdpcm_txb_nonzero_w;
                      if (lossy_420_mode_q) begin
                        lossy420_u_above_q[txb_col_w[3:0]] <=
                          lossy420_chroma_bdpcm_recon_sample_w;
                        lossy420_u_above_valid_q[txb_col_w[3:0]] <= 1'b1;
                        lossy420_u_left_q[lossy420_chroma_left_row_index_w] <=
                          lossy420_chroma_bdpcm_recon_sample_w;
                        lossy420_u_left_col_mi_q[lossy420_chroma_left_row_index_w] <=
                          txb_col_w[4:0];
                        lossy420_u_left_valid_q[lossy420_chroma_left_row_index_w] <= 1'b1;
                      end
                    end else begin
                      v_txb_above_q[txb_col_w[4:0]] <= chroma_bdpcm_entropy_context_w;
                      v_txb_left_q[txb_row_w[4:0]] <= chroma_bdpcm_entropy_context_w;
                      if (lossy_420_mode_q) begin
                        lossy420_v_above_q[txb_col_w[3:0]] <=
                          lossy420_chroma_bdpcm_recon_sample_w;
                        lossy420_v_above_valid_q[txb_col_w[3:0]] <= 1'b1;
                        lossy420_v_left_q[lossy420_chroma_left_row_index_w] <=
                          lossy420_chroma_bdpcm_recon_sample_w;
                        lossy420_v_left_col_mi_q[lossy420_chroma_left_row_index_w] <=
                          txb_col_w[4:0];
                        lossy420_v_left_valid_q[lossy420_chroma_left_row_index_w] <= 1'b1;
                      end
                    end
                  end
                  if (txb_index_q == (txb_count_q - 16'd1)) begin
                    if (phase_q == PHASE_U_COEFF) begin
                      phase_q <= PHASE_V_COEFF;
                      step_q <= 5'd0;
                      txb_index_q <= 16'd0;
                      txb_width_q <= chroma_txb_width_w;
                      txb_count_q <= chroma_txb_count_w;
                      txb_local_row_q <= 5'd0;
                      txb_local_col_q <= 5'd0;
                      txb_prefetch_started_q <= 1'b0;
                      txb_prefetch_done_q <= 1'b0;
                      if (residual_mode_w) begin
                        if ((txb_prefetch_done_q && txb_prefetch_chroma_q && txb_prefetch_plane_v_q) ||
                            chroma_fetch_req_ready_w) begin
                          txb_prefetch_started_q <= 1'b0;
                          txb_prefetch_done_q <= 1'b0;
                          state_q <= ST_LEAF;
                        end else begin
                          txb_prefetch_started_q <= 1'b0;
                          txb_prefetch_done_q <= 1'b0;
                          state_q <= ST_CHROMA_FETCH;
                        end
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
                      left_edge_u_top_q <= current_u_right_edge_top_w;
                      left_edge_u_bottom_q <= current_u_right_edge_bottom_w;
                      left_edge_v_top_q <= current_v_right_edge_top_w;
                      left_edge_v_bottom_q <= current_v_right_edge_bottom_w;
                      left_edge_row_mi_q <= block_row_mi_q;
                      left_edge_col_mi_q <= block_col_mi_q;
                      left_edge_valid_q <=
                        cached_chroma_samples_valid_q[2'd1] &&
                        cached_chroma_samples_valid_q[2'd3];
                      if (block_col_mi_q == 5'd0) begin
                        above_col0_u_q <= current_u_col0_above_edge_w;
                        above_col0_v_q <= current_v_col0_above_edge_w;
                        above_col0_row_mi_q <= block_row_mi_q;
                        above_col0_valid_q <= cached_chroma_samples_valid_q[2'd2];
                      end
                      if (stack_sp_q != 5'd0) begin
                        txb_prefetch_started_q <= 1'b0;
                        txb_prefetch_done_q <= 1'b0;
                        block_row_mi_q <= stack_row_mi_q[stack_sp_q - 5'd1];
                        block_col_mi_q <= stack_col_mi_q[stack_sp_q - 5'd1];
                        block_w_mi_q <= stack_w_mi_q[stack_sp_q - 5'd1];
                        block_h_mi_q <= stack_h_mi_q[stack_sp_q - 5'd1];
                        stack_sp_q <= stack_sp_q - 5'd1;
                        state_q <= ST_LOAD_BLOCK;
                      end else begin
                        txb_prefetch_started_q <= 1'b0;
                        txb_prefetch_done_q <= 1'b0;
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
                    if (residual_mode_w) begin
                      if ((txb_prefetch_done_q && txb_prefetch_chroma_q) || chroma_fetch_req_ready_w) begin
                        txb_prefetch_started_q <= 1'b0;
                        txb_prefetch_done_q <= 1'b0;
                        state_q <= ST_LEAF;
                      end else begin
                        txb_prefetch_started_q <= 1'b0;
                        txb_prefetch_done_q <= 1'b0;
                        state_q <= ST_CHROMA_FETCH;
                      end
                    end
                  end
                end else begin
                  step_q <= step_q + 5'd1;
                end
              end
            end
          end
          ST_CHROMA_FETCH: begin
            if (((phase_q == PHASE_Y_COEFF) &&
                 ((txb_prefetch_done_q && !txb_prefetch_chroma_q) || luma_fetch_done_w)) ||
                ((phase_q == PHASE_U_COEFF) &&
                 ((txb_prefetch_done_q && txb_prefetch_chroma_q && !txb_prefetch_plane_v_q) ||
                  chroma_fetch_done_w ||
                  chroma_fetch_current_cache_hit_w)) ||
                ((phase_q == PHASE_V_COEFF) &&
                 ((txb_prefetch_done_q && txb_prefetch_chroma_q && txb_prefetch_plane_v_q) ||
                  chroma_fetch_done_w ||
                  chroma_fetch_current_cache_hit_w))) begin
              step_q <= 5'd0;
              txb_prefetch_started_q <= 1'b0;
              txb_prefetch_done_q <= 1'b0;
              state_q <= ST_LEAF;
            end
          end
          ST_FINISH_INIT: begin
            finish_e_q <= ((low_q + 64'h3fff) & ~64'h3fff) | 64'h4000;
            finish_c_q <= cnt_q;
            finish_s_q <= cnt_q + 8'sd10;
            state_q <= ST_FINISH_PUSH;
          end
          ST_FINISH_PUSH: begin
            if (finish_s_q > 8'sd0) begin
              precarry_len_q <= precarry_len_q + 16'd1;
              if ((finish_c_q + 8'sd16) >= 8'sd64) begin
                finish_e_q <= 64'd0;
              end else if ((finish_c_q + 8'sd16) <= 8'sd0) begin
                finish_e_q <= finish_e_q;
              end else begin
                finish_e_q <=
                  finish_e_q & ((64'd1 << (finish_c_q[5:0] + 6'd16)) - 64'd1);
              end
              finish_c_q <= finish_c_q - 8'sd8;
              finish_s_q <= finish_s_q - 8'sd8;
            end else begin
              carry_q <= 16'd0;
              carry_index_q <= precarry_len_q - 16'd1;
              precarry_read_addr_q <= precarry_len_q - 16'd1;
              tile_len_q <= precarry_len_q;
              state_q <= ST_CARRY_READ;
            end
          end
          ST_CARRY_READ: begin
            if (carry_index_q != 16'd0) begin
              precarry_read_addr_q <= carry_index_q - 16'd1;
            end
            state_q <= ST_CARRY_WRITE;
          end
          ST_CARRY_WRITE: begin
            carry_q <= carry_sum_w >> 8;
            // The carry pass already computes the final tile byte. Stage it in
            // payload order here and avoid the old post-carry copy sweep.
            payload_mem_q[payload_tile_start_w + carry_index_q] <= carry_sum_w[7:0];
            if (carry_index_q == 0) begin
              payload_prefix_index_q <= 2'd0;
              precarry_read_addr_q <= 16'd0;
              state_q <= ST_PAYLOAD_PREFIX;
            end else begin
              carry_index_q <= carry_index_q - 1;
              if (carry_index_q > 16'd1) begin
                precarry_read_addr_q <= carry_index_q - 16'd2;
              end else begin
                precarry_read_addr_q <= 16'd0;
              end
              state_q <= ST_CARRY_WRITE;
            end
          end
          ST_PAYLOAD_PREFIX: begin
            if (!tile_is_last_w && payload_prefix_index_q != 2'd3) begin
              payload_mem_q[payload_len_q + {14'd0, payload_prefix_index_q}] <= payload_prefix_byte_w;
              payload_prefix_index_q <= payload_prefix_index_q + 2'd1;
            end else if (!tile_is_last_w) begin
              payload_mem_q[payload_len_q + 16'd3] <= payload_prefix_byte_w;
              payload_len_q <= payload_len_q + 16'd4 + tile_len_q;
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
            end else begin
              payload_len_q <= payload_len_q + tile_len_q;
              stream_index_q <= 16'd0;
              state_q <= ST_OUTPUT_PREP;
            end
          end
          ST_OUTPUT_PREP: begin
            // The final OBU bytes are already staged in register arrays. Drive
            // the first byte immediately, then keep m_axis_valid asserted in
            // ST_OUTPUT_VALID while advancing the lookup index on each
            // accepted byte.
            output_byte_q <= output_lookup_byte_w;
            output_last_q <= output_lookup_last_w;
            m_axis_valid <= 1'b1;
            m_axis_data <= output_lookup_byte_w;
            m_axis_last <= output_lookup_last_w;
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
                stream_index_q <= stream_index_q + 16'd1;
                output_byte_q <= output_lookup_byte_w;
                output_last_q <= output_lookup_last_w;
                m_axis_valid <= 1'b1;
                m_axis_data <= output_lookup_byte_w;
                m_axis_last <= output_lookup_last_w;
                state_q <= ST_OUTPUT_VALID;
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
    ibc_any_copy_w,
    ibc_done_w
  };

endmodule
