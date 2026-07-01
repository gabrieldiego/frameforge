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
  // TODO(av2-delete-buffer): remove AV2_MAX_TILE_BYTES and the staged
  // precarry/payload RAMs once the entropy/carry path streams directly to the
  // AXI packet writer. This whole-tile buffer is a temporary area/bubble
  // liability; larger future pictures must not scale this memory by frame.
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
  localparam int OUTPUT_PACKET_BYTES = 16;
  localparam int OUTPUT_PACKET_COUNT_BITS = 5;
  typedef enum logic [4:0] {
    ST_IDLE,
    ST_TILE_START,
    ST_INPUT_READ,
    ST_SEQ_LOAD,
    ST_SEQ_WRITE,
    ST_LOAD_BLOCK,
    ST_PARTITION,
    ST_LEAF_WAIT,
    ST_PALETTE_QUERY,
    ST_LEAF,
    ST_FINISH_INIT,
    ST_FINISH_PUSH,
    ST_CHROMA_FETCH,
    ST_CARRY_READ,
    ST_CARRY_WRITE,
    ST_PAYLOAD_PREFIX,
    ST_OUTPUT_PREP,
    ST_OUTPUT_VALID,
    ST_OUTPUT_PAYLOAD_WAIT,
    ST_OUTPUT_PAYLOAD_LOAD
  } state_t;

  localparam int AV2_STACK_DEPTH = 16;
  localparam int AV2_PARTITION_CONTEXT_DIM = 16;

  localparam logic [2:0] PHASE_INTRA = 3'd0;
  localparam logic [2:0] PHASE_PALETTE_HEADER = 3'd1;
  localparam logic [2:0] PHASE_PALETTE_MAP = 3'd2;
  localparam logic [2:0] PHASE_Y_COEFF = 3'd3;
  localparam logic [2:0] PHASE_U_COEFF = 3'd4;
  localparam logic [2:0] PHASE_V_COEFF = 3'd5;
  localparam logic [2:0] PHASE_INTRABC = 3'd6;

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
  logic       reader_axis_valid;
  logic       reader_axis_ready;
  localparam int INPUT_PACKET_SAMPLES = 8;
  localparam int INPUT_PACKET_BITS = INPUT_PACKET_SAMPLES * SAMPLE_BITS;
  localparam int INPUT_FIFO_BITS = INPUT_PACKET_BITS + 4;
  localparam int INPUT_PACKET_FIFO_DEPTH = 16;
  localparam int INPUT_PACKET_FIFO_LEVEL_BITS = $clog2(INPUT_PACKET_FIFO_DEPTH + 1);
  logic [INPUT_PACKET_BITS - 1:0] reader_axis_data;
  logic [3:0] reader_axis_count;
  logic       reader_axis_last;
  logic       packet_axis_valid;
  logic       packet_axis_ready;
  logic [INPUT_FIFO_BITS - 1:0] packet_axis_data;
  logic       packet_axis_last;
  logic [3:0] packet_axis_count_w;
  logic [INPUT_PACKET_FIFO_LEVEL_BITS - 1:0] input_fifo_level_w;
  logic       m_axis_valid;
  logic       m_axis_ready;
  logic [AXI_DATA_BITS - 1:0] m_axis_data;
  logic [OUTPUT_PACKET_COUNT_BITS - 1:0] m_axis_count;
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
  logic state_idle_w;
  logic state_tile_start_w;
  logic state_input_read_w;
  logic state_partition_w;
  logic state_palette_query_w;
  logic state_leaf_w;
  logic state_chroma_fetch_w;
  logic state_finish_push_w;
  logic state_carry_write_w;
  logic state_payload_prefix_w;
  logic state_output_valid_w;
  logic start_invalid_w;
  logic [AV2_MAX_SEQUENCE_BYTES - 1:0][7:0] seq_mem_q;
  logic [15:0] precarry_read_addr_q;
  logic [11:0] precarry_read_word_addr_q;
  logic [255:0] precarry_read_word_data_w;
  logic [15:0] precarry_read_data_q;
  logic precarry_write_valid_w;
  logic [15:0] precarry_write_addr_w;
  logic [15:0] precarry_write_data_w;
  logic payload_write_valid_w;
  logic [15:0] payload_write_addr_w;
  logic [15:0] payload_write_strobe_w;
  logic [127:0] payload_write_data_w;
  logic [11:0] payload_read_word_addr_q;
  logic [11:0] payload_read_data_word_addr_q;
  logic [127:0] payload_read_data_w;
  logic pending_push_valid_q;
  logic [15:0] pending_push_word_q;
  logic [15:0] precarry_len_q;
  logic [15:0] tile_len_q;
  logic [15:0] payload_len_q;
  logic [1:0] payload_prefix_index_q;
  logic [15:0] seq_len_q;
  logic [15:0] stream_index_q;
  logic [31:0] frame_index_q;
  logic [AXI_ADDR_BITS - 1:0] input_frame_offset_q;
  logic [3:0] output_byte_phase_q;
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
  logic tile_input_active_q;
  logic frame_palette_mode_q;
  logic [7:0] seq_op_q;
  logic [6:0] seq_bits_left_q;
  logic [63:0] seq_value_q;
  logic [15:0] seq_bit_pos_q;
  logic [3:0] seq_byte_remaining_w;
  logic [3:0] seq_write_step_w;
  logic [63:0] low_q;
  logic [31:0] rng_q;
  logic signed [7:0] cnt_q;
  logic [2:0] phase_q;
  logic [6:0] step_q;
  logic phase_intra_w;
  logic phase_palette_header_w;
  logic phase_palette_map_w;
  logic phase_y_coeff_w;
  logic phase_u_coeff_w;
  logic phase_v_coeff_w;
  logic phase_intrabc_w;
  
  logic [5:0] palette_row_q;
  logic [5:0] palette_col_q;
  logic [1:0] palette_identity_row_ctx_q;
  logic palette_mode_q;
  logic lossy_420_mode_q;
  logic [1:0] leaf_luma_mode_q;
  logic leaf_chroma_bdpcm_horz_q;
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
  logic [3:0][127:0] cached_v_txb_samples_q;
  logic [3:0][31:0] cached_v_predictor_samples_q;
  logic [3:0][127:0] cached_u_txb_samples_q;
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
  logic [AV2_STACK_DEPTH - 1:0][4:0] stack_row_mi_q;
  logic [AV2_STACK_DEPTH - 1:0][4:0] stack_col_mi_q;
  logic [AV2_STACK_DEPTH - 1:0][4:0] stack_w_mi_q;
  logic [AV2_STACK_DEPTH - 1:0][4:0] stack_h_mi_q;
  logic [63:0] finish_e_q;
  logic signed [7:0] finish_c_q;
  logic signed [7:0] finish_s_q;
  logic [15:0] carry_q;
  logic [15:0] carry_index_q;
  logic last_u_txb_nonzero_q;
  logic txb_context_clear_w;
  logic txb_context_clear_leaf_w;
  logic txb_context_set_luma_w;
  logic txb_context_set_u_w;
  logic txb_context_set_v_w;
  logic [7:0] txb_context_luma_update_w;
  logic [7:0] txb_context_u_update_w;
  logic [7:0] txb_context_v_update_w;
  logic [7:0] txb_context_luma_above_w;
  logic [7:0] txb_context_luma_left_w;
  logic [7:0] txb_context_u_above_w;
  logic [7:0] txb_context_u_left_w;
  logic [7:0] txb_context_v_above_w;
  logic [7:0] txb_context_v_left_w;

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
  logic [3:0] tile_width_blocks_w;
  logic [3:0] tile_height_blocks_w;
  logic [7:0] tile_block_count_w;
  logic [15:0] tile_count_w;
  logic [31:0] tile_luma_samples_w;
  logic [31:0] tile_samples_w;
  logic tile_input_last_w;
  logic tile_is_last_w;
  logic multi_tile_w;
  logic frame_ibc_mode_q;
  logic ibc_done_w;
  logic [63:0] ibc_copy_mask_w;
  logic [63:0] ibc_above_copy_mask_w;
  logic [63:0] ibc_ready_mask_w;
  logic [127:0] ibc_drl_idx_table_w;
  logic [5:0] ibc_current_block_id_w;
  logic [6:0] ibc_drl_idx_bit_index_w;
  logic ibc_use_copy_w;
  logic [1:0] ibc_drl_idx_w;
  logic decision_ibc_use_copy_w;
  logic [1:0] decision_ibc_drl_idx_w;
  logic [1:0] intrabc_ctx_w;
  logic [1:0] intrabc_skip_ctx_w;
  logic ibc_context_clear_w;
  logic ibc_context_set_leaf_w;
  logic ibc_context_clear_leaf_w;
  logic ibc_above_ctx_w;
  logic ibc_left_ctx_w;
  logic skip_above_ctx_w;
  logic skip_left_ctx_w;
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
  logic [15:0] output_next_stream_index_w;
  logic [15:0] output_payload_addr_w;
  logic [11:0] output_next_payload_word_addr_w;
  logic [11:0] output_after_current_payload_word_addr_w;
  logic [11:0] output_after_next_payload_word_addr_w;
  logic [3:0] output_next_byte_phase_w;
  logic output_after_current_payload_w;
  logic output_after_next_payload_w;
  logic [OUTPUT_PACKET_COUNT_BITS - 1:0] output_payload_count_w;
  logic [OUTPUT_PACKET_COUNT_BITS - 1:0] output_next_payload_count_w;
  logic [127:0] output_payload_packet_data_w;
  logic [127:0] output_next_payload_packet_data_w;
  logic output_current_packet_last_w;
  logic output_next_packet_last_w;
  logic [7:0] output_byte_w;
  logic [7:0] output_lookup_byte_w;
  logic output_lookup_last_w;
  logic frame_is_last_w;
  logic output_last_q;
  logic output_tile_payload_w;
  logic [15:0] carry_sum_w;
  logic [15:0] carry_group_addr_w;
  logic [15:0] carry_index_after_step_w;
  logic [15:0] carry_after_step_w;
  logic [127:0] carry_group_data_w;
  logic [15:0] carry_group_strobe_w;
  logic carry_done_after_step_w;
  logic [11:0] carry_read_after_current_word_addr_w;
  logic [11:0] carry_read_after_next_word_addr_w;
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
  logic input_packet_fire_w;
  logic input_fire_w;
  logic [3:0] input_fire_count_w;
  logic input_axis_last_w;
  logic input_fire_error_w;
  logic palette_analyzer_sample_ready_w;
  logic palette_analyzer_done_w;
  logic palette_analyzer_unsupported_w;
  logic palette_analyzer_black_w;
  logic palette_analyzer_nonblack_seen_w;
  logic palette_analyzer_luma_mode_w;
  logic [63:0] palette_analyzer_block_ready_mask_w;
  logic tile_entropy_start_ready_w;
  logic tile_entropy_palette_mode_w;
  logic tile_entropy_lossy420_mode_w;
  logic tile_entropy_ibc_mode_w;
  logic [5:0] current_leaf_block_id_w;
  logic current_leaf_ready_w;
  logic palette_query_start_w;
  logic palette_query_done_w;
  logic [3:0] palette_size_w;
  logic [4:0] palette_cache_size_w;
  logic [7:0] palette_first_color_w;
  logic [1:0] palette_delta_bits_minus5_w;
  logic [55:0] palette_delta_minus1_w;
  logic [34:0] palette_delta_literal_bits_w;
  logic [1:0] palette_luma_mode_w;
  logic [1:0] decision_leaf_luma_mode_w;
  logic leaf_luma_palette_w;
  logic [2:0] palette_current_index_w;
  logic [2:0] palette_left_index_w;
  logic [2:0] palette_top_index_w;
  logic [2:0] palette_top_left_index_w;
  logic palette_luma_residual_zero_w;
  logic palette_chroma_bdpcm_horz_w;
  logic decision_leaf_chroma_bdpcm_horz_w;
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
  logic [11:0] luma_fetch_sample_sum_w;
  logic [11:0] chroma_fetch_sample_sum_w;
  logic [11:0] lossy420_luma_sample_sum_now_w;
  logic [11:0] lossy420_chroma_sample_sum_now_w;
  logic [3:0] luma_residual_skip_ctx_w;
  logic [1:0] luma_residual_dc_sign_ctx_w;
  logic [7:0] lossy420_luma_residual_recon_sample_w;
  logic luma_residual_op_valid_w;
  logic luma_residual_op_literal_w;
  logic [31:0] luma_residual_op_literal_value_w;
  logic [4:0] luma_residual_op_literal_bits_w;
  logic [31:0] luma_residual_op_fl_w;
  logic [31:0] luma_residual_op_fh_w;
  logic [4:0] luma_residual_op_fl_inc_w;
  logic [4:0] luma_residual_op_fh_inc_w;
  logic palette_luma_residual_known_zero_w;
  logic luma_residual_txb_done_w;
  logic [7:0] luma_residual_entropy_context_w;
  logic [3:0] chroma_bdpcm_skip_ctx_w;
  logic [7:0] lossy420_chroma_bdpcm_recon_sample_w;
  logic chroma_bdpcm_op_valid_w;
  logic chroma_bdpcm_op_literal_w;
  logic [31:0] chroma_bdpcm_op_literal_value_w;
  logic [4:0] chroma_bdpcm_op_literal_bits_w;
  logic [31:0] chroma_bdpcm_op_fl_w;
  logic [31:0] chroma_bdpcm_op_fh_w;
  logic [4:0] chroma_bdpcm_op_fl_inc_w;
  logic [4:0] chroma_bdpcm_op_fh_inc_w;
  logic chroma_bdpcm_txb_done_w;
  logic chroma_bdpcm_txb_nonzero_w;
  logic [7:0] chroma_bdpcm_entropy_context_w;
  logic [127:0] chroma_bdpcm_txb_samples_w;
  logic [31:0] chroma_bdpcm_predictor_samples_w;
  logic [3:0][7:0] lossy420_luma_recon_q;
  logic [15:0][7:0] lossy420_luma_above_q;
  logic [15:0] lossy420_luma_above_valid_q;
  logic [15:0][7:0] lossy420_luma_left_top_q;
  logic [15:0][7:0] lossy420_luma_left_bottom_q;
  logic [15:0][4:0] lossy420_luma_left_col_mi_q;
  logic [15:0] lossy420_luma_left_valid_q;
  logic [7:0] lossy420_luma_predictor_w;
  logic [3:0] lossy420_luma_left_row_index_w;
  logic signed [9:0] lossy420_luma_delta_w;
  logic lossy420_luma_known_zero_w;
  logic [15:0][7:0] lossy420_u_above_q;
  logic [15:0][7:0] lossy420_v_above_q;
  logic [15:0] lossy420_u_above_valid_q;
  logic [15:0] lossy420_v_above_valid_q;
  logic [15:0][7:0] lossy420_u_left_q;
  logic [15:0][7:0] lossy420_v_left_q;
  logic [15:0][4:0] lossy420_u_left_col_mi_q;
  logic [15:0][4:0] lossy420_v_left_col_mi_q;
  logic [15:0] lossy420_u_left_valid_q;
  logic [15:0] lossy420_v_left_valid_q;
  logic [7:0] lossy420_chroma_predictor_w;
  logic [3:0] lossy420_chroma_left_row_index_w;
  logic signed [9:0] lossy420_chroma_delta_w;
  logic lossy420_chroma_known_zero_w;
  logic [4:0] visible_rows_mi_w;
  logic [4:0] visible_cols_mi_w;
  logic block_visible_w;
  logic [4:0] block_half_w_mi_w;
  logic [4:0] block_half_h_mi_w;
  logic allowed_none_w;
  logic allowed_horz_w;
  logic allowed_vert_w;
  logic forced_valid_w;
  logic [1:0] forced_partition_w;
  logic [1:0] chosen_partition_w;
  logic partition_need_do_split_w;
  logic partition_need_rect_w;
  logic partition_emit_do_split_w;
  logic partition_emit_rect_w;
  logic partition_emit_done_w;
  logic [5:0] partition_split_ctx_w;
  logic [5:0] partition_rect_ctx_w;
  logic [1:0] partition_raw_ctx_w;
  logic [31:0] partition_do_cdf0_w;
  logic [31:0] partition_rect_cdf0_w;
  logic [7:0] partition_above_ctx_w;
  logic [7:0] partition_left_ctx_w;
  logic partition_context_clear_w;
  logic partition_context_update_w;
  logic [7:0] partition_update_above_w;
  logic [7:0] partition_update_left_w;
  logic [4:0] leaf_visible_txb_w_w;
  logic [4:0] leaf_visible_txb_h_w;
  logic luma_residual_enable_w;
  logic chroma_bdpcm_enable_w;
  logic chroma_subsampled_phase_w;

  ff_av2_state_phase_decode #(
    .ST_IDLE(ST_IDLE),
    .ST_TILE_START(ST_TILE_START),
    .ST_INPUT_READ(ST_INPUT_READ),
    .ST_PARTITION(ST_PARTITION),
    .ST_PALETTE_QUERY(ST_PALETTE_QUERY),
    .ST_LEAF(ST_LEAF),
    .ST_CHROMA_FETCH(ST_CHROMA_FETCH),
    .ST_FINISH_PUSH(ST_FINISH_PUSH),
    .ST_CARRY_WRITE(ST_CARRY_WRITE),
    .ST_PAYLOAD_PREFIX(ST_PAYLOAD_PREFIX),
    .ST_OUTPUT_VALID(ST_OUTPUT_VALID),
    .PHASE_INTRA(PHASE_INTRA),
    .PHASE_PALETTE_HEADER(PHASE_PALETTE_HEADER),
    .PHASE_PALETTE_MAP(PHASE_PALETTE_MAP),
    .PHASE_Y_COEFF(PHASE_Y_COEFF),
    .PHASE_U_COEFF(PHASE_U_COEFF),
    .PHASE_V_COEFF(PHASE_V_COEFF),
    .PHASE_INTRABC(PHASE_INTRABC)
  ) state_phase_decode (
    .state_q(state_q),
    .phase_q(phase_q),
    .state_idle_w(state_idle_w),
    .state_tile_start_w(state_tile_start_w),
    .state_input_read_w(state_input_read_w),
    .state_partition_w(state_partition_w),
    .state_palette_query_w(state_palette_query_w),
    .state_leaf_w(state_leaf_w),
    .state_chroma_fetch_w(state_chroma_fetch_w),
    .state_finish_push_w(state_finish_push_w),
    .state_carry_write_w(state_carry_write_w),
    .state_payload_prefix_w(state_payload_prefix_w),
    .state_output_valid_w(state_output_valid_w),
    .phase_intra_w(phase_intra_w),
    .phase_palette_header_w(phase_palette_header_w),
    .phase_palette_map_w(phase_palette_map_w),
    .phase_y_coeff_w(phase_y_coeff_w),
    .phase_u_coeff_w(phase_u_coeff_w),
    .phase_v_coeff_w(phase_v_coeff_w),
    .phase_intrabc_w(phase_intrabc_w)
  );

  ff_av2_encoder_context_controls context_controls (
    .state_input_read_w(state_input_read_w),
    .state_partition_w(state_partition_w),
    .state_leaf_w(state_leaf_w),
    .state_output_valid_w(state_output_valid_w),
    .state_idle_w(state_idle_w),
    .start(start),
    .start_invalid_w(start_invalid_w),
    .tile_entropy_start_ready_w(tile_entropy_start_ready_w),
    .palette_analyzer_unsupported_w(palette_analyzer_unsupported_w),
    .op_valid_w(op_valid_w),
    .partition_q(partition_q),
    .phase_intrabc_w(phase_intrabc_w),
    .phase_y_coeff_w(phase_y_coeff_w),
    .phase_u_coeff_w(phase_u_coeff_w),
    .phase_v_coeff_w(phase_v_coeff_w),
    .partition_emit_do_split_w(partition_emit_do_split_w),
    .partition_need_rect_w(partition_need_rect_w),
    .m_axis_valid(m_axis_valid),
    .m_axis_ready(m_axis_ready),
    .output_last_q(output_last_q),
    .frame_is_last_w(frame_is_last_w),
    .step_q(step_q[4:0]),
    .ibc_drl_idx_w(decision_ibc_drl_idx_w),
    .residual_mode_w(residual_mode_w),
    .luma_residual_txb_done_w(luma_residual_txb_done_w),
    .chroma_bdpcm_txb_done_w(chroma_bdpcm_txb_done_w),
    .txb_count_q(txb_count_q),
    .txb_index_q(txb_index_q),
    .luma_residual_entropy_context_w(luma_residual_entropy_context_w),
    .chroma_bdpcm_entropy_context_w(chroma_bdpcm_entropy_context_w),
    .partition_context_clear_w(partition_context_clear_w),
    .partition_context_update_w(partition_context_update_w),
    .txb_context_clear_w(txb_context_clear_w),
    .txb_context_clear_leaf_w(txb_context_clear_leaf_w),
    .txb_context_set_luma_w(txb_context_set_luma_w),
    .txb_context_set_u_w(txb_context_set_u_w),
    .txb_context_set_v_w(txb_context_set_v_w),
    .txb_context_luma_update_w(txb_context_luma_update_w),
    .txb_context_u_update_w(txb_context_u_update_w),
    .txb_context_v_update_w(txb_context_v_update_w),
    .ibc_context_clear_w(ibc_context_clear_w),
    .ibc_context_set_leaf_w(ibc_context_set_leaf_w),
    .ibc_context_clear_leaf_w(ibc_context_clear_leaf_w)
  );

  ff_av2_context_banks #(
    .CONTEXT_DIM(AV2_PARTITION_CONTEXT_DIM)
  ) context_banks (
    .clk(clk),
    .rst_n(rst_n),
    .partition_clear(partition_context_clear_w),
    .partition_update(partition_context_update_w),
    .block_row_mi(block_row_mi_q),
    .block_col_mi(block_col_mi_q),
    .block_w_mi(block_w_mi_q),
    .block_h_mi(block_h_mi_q),
    .partition_update_above(partition_update_above_w),
    .partition_update_left(partition_update_left_w),
    .partition_selected_above(partition_above_ctx_w),
    .partition_selected_left(partition_left_ctx_w),
    .txb_clear(txb_context_clear_w),
    .txb_clear_leaf(txb_context_clear_leaf_w),
    .txb_set_luma(txb_context_set_luma_w),
    .txb_set_u(txb_context_set_u_w),
    .txb_set_v(txb_context_set_v_w),
    .txb_row_mi(txb_row_w[4:0]),
    .txb_col_mi(txb_col_w[4:0]),
    .txb_luma_context(txb_context_luma_update_w),
    .txb_u_context(txb_context_u_update_w),
    .txb_v_context(txb_context_v_update_w),
    .txb_selected_luma_above(txb_context_luma_above_w),
    .txb_selected_luma_left(txb_context_luma_left_w),
    .txb_selected_u_above(txb_context_u_above_w),
    .txb_selected_u_left(txb_context_u_left_w),
    .txb_selected_v_above(txb_context_v_above_w),
    .txb_selected_v_left(txb_context_v_left_w),
    .ibc_clear(ibc_context_clear_w),
    .ibc_set_leaf(ibc_context_set_leaf_w),
    .ibc_clear_leaf(ibc_context_clear_leaf_w),
    .ibc_selected_above(ibc_above_ctx_w),
    .ibc_selected_left(ibc_left_ctx_w),
    .ibc_selected_skip_above(skip_above_ctx_w),
    .ibc_selected_skip_left(skip_left_ctx_w)
  );

  ff_av2_partition_controller partition_controller (
    .tile_width(tile_width_q),
    .tile_height(tile_height_q),
    .block_row_mi(block_row_mi_q),
    .block_col_mi(block_col_mi_q),
    .block_w_mi(block_w_mi_q),
    .block_h_mi(block_h_mi_q),
    .partition(partition_q),
    .partition_emit_step(partition_emit_step_q),
    .palette_mode(palette_mode_q),
    .partition_above_ctx(partition_above_ctx_w),
    .partition_left_ctx(partition_left_ctx_w),
    .visible_rows_mi(visible_rows_mi_w),
    .visible_cols_mi(visible_cols_mi_w),
    .block_visible(block_visible_w),
    .block_half_w_mi(block_half_w_mi_w),
    .block_half_h_mi(block_half_h_mi_w),
    .allowed_none(allowed_none_w),
    .allowed_horz(allowed_horz_w),
    .allowed_vert(allowed_vert_w),
    .forced_valid(forced_valid_w),
    .forced_partition(forced_partition_w),
    .chosen_partition(chosen_partition_w),
    .partition_need_do_split(partition_need_do_split_w),
    .partition_need_rect(partition_need_rect_w),
    .partition_emit_do_split(partition_emit_do_split_w),
    .partition_emit_rect(partition_emit_rect_w),
    .partition_emit_done(partition_emit_done_w),
    .partition_split_ctx(partition_split_ctx_w),
    .partition_rect_ctx(partition_rect_ctx_w),
    .partition_raw_ctx(partition_raw_ctx_w),
    .partition_update_above(partition_update_above_w),
    .partition_update_left(partition_update_left_w),
    .leaf_fsc_symbol(leaf_fsc_symbol_w),
    .leaf_fsc_fh(leaf_fsc_fh_w)
  );

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
    .OUTPUT_SAMPLES(INPUT_PACKET_SAMPLES),
    .RASTER_BLOCK_ORDER(1'b1),
    .ENABLE_420_PREFETCH(1'b1)
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
    .src_frame_offset(input_frame_offset_q),
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
    .sample_valid(reader_axis_valid),
    .sample_ready(reader_axis_ready),
    .sample_data(reader_axis_data),
    .sample_count(reader_axis_count),
    .sample_last(reader_axis_last),
    .busy(frame_reader_busy_w),
    .done(frame_reader_done_w),
    .error(frame_reader_error_w)
  );

  ff_axis_sample_fifo #(
    .DATA_BITS(INPUT_FIFO_BITS),
    .DEPTH(INPUT_PACKET_FIFO_DEPTH)
  ) input_sample_fifo (
    .clk(clk),
    .rst_n(rst_n),
    .clear(frame_reader_start_w),
    .s_axis_valid(reader_axis_valid),
    .s_axis_ready(reader_axis_ready),
    .s_axis_data({reader_axis_count, reader_axis_data}),
    .s_axis_last(reader_axis_last),
    .m_axis_valid(packet_axis_valid),
    .m_axis_ready(packet_axis_ready),
    .m_axis_data(packet_axis_data),
    .m_axis_last(packet_axis_last),
    .level(input_fifo_level_w)
  );

  assign packet_axis_count_w = packet_axis_data[INPUT_FIFO_BITS - 1:INPUT_PACKET_BITS];

  ff_axi4_bitstream_packet_writer #(
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
    .s_axis_count(m_axis_count),
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

  ff_av2_geometry geometry (
    .visible_width(visible_width),
    .visible_height(visible_height),
    .coded_width(width_q),
    .coded_height(height_q),
    .tile_col(tile_col_q),
    .tile_row(tile_row_q),
    .width_bits(width_bits_w),
    .height_bits(height_bits_w),
    .tile_cols(tile_cols_w),
    .tile_rows(tile_rows_w),
    .tile_count(tile_count_w),
    .tile_width(tile_width_w),
    .tile_height(tile_height_w),
    .tile_width_blocks(tile_width_blocks_w),
    .tile_height_blocks(tile_height_blocks_w),
    .tile_block_count(tile_block_count_w)
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

  ff_av2_output_packetizer #(
    .OUTPUT_PACKET_COUNT_BITS(OUTPUT_PACKET_COUNT_BITS)
  ) output_packetizer (
    .state_output_valid(state_output_valid_w),
    .axis_valid(m_axis_valid),
    .axis_ready(m_axis_ready),
    .output_last(output_last_q),
    .stream_index(stream_index_q),
    .axis_count(m_axis_count),
    .output_byte_phase(output_byte_phase_q),
    .tile_payload_start(tile_payload_start_w),
    .total_stream_len(total_stream_len_w),
    .output_tile_payload(output_tile_payload_w),
    .output_byte(output_byte_w),
    .payload_read_data(payload_read_data_w),
    .stream_lookup_index(stream_lookup_index_w),
    .output_next_stream_index(output_next_stream_index_w),
    .output_payload_addr(output_payload_addr_w),
    .output_next_payload_word_addr(output_next_payload_word_addr_w),
    .output_after_current_payload_word_addr(output_after_current_payload_word_addr_w),
    .output_after_next_payload_word_addr(output_after_next_payload_word_addr_w),
    .output_next_byte_phase(output_next_byte_phase_w),
    .output_after_current_payload(output_after_current_payload_w),
    .output_after_next_payload(output_after_next_payload_w),
    .output_payload_count(output_payload_count_w),
    .output_next_payload_count(output_next_payload_count_w),
    .output_payload_packet_data(output_payload_packet_data_w),
    .output_next_payload_packet_data(output_next_payload_packet_data_w),
    .output_current_packet_last(output_current_packet_last_w),
    .output_next_packet_last(output_next_packet_last_w),
    .output_lookup_byte(output_lookup_byte_w),
    .output_lookup_last(output_lookup_last_w)
  );

  ff_av2_carry_propagator carry_propagator (
    .carry(carry_q),
    .carry_index(carry_index_q),
    .payload_tile_start(payload_tile_start_w),
    .precarry_read_word_data(precarry_read_word_data_w),
    .precarry_read_addr(precarry_read_addr_q),
    .precarry_read_data(precarry_read_data_q),
    .carry_sum(carry_sum_w),
    .carry_group_addr(carry_group_addr_w),
    .carry_index_after_step(carry_index_after_step_w),
    .carry_after_step(carry_after_step_w),
    .carry_group_data(carry_group_data_w),
    .carry_group_strobe(carry_group_strobe_w),
    .carry_done_after_step(carry_done_after_step_w),
    .carry_read_after_current_word_addr(carry_read_after_current_word_addr_w),
    .carry_read_after_next_word_addr(carry_read_after_next_word_addr_w)
  );

  ff_av2_payload_write_mux payload_write_mux (
    .start(start),
    .state_partition(state_partition_w),
    .state_leaf(state_leaf_w),
    .state_finish_push(state_finish_push_w),
    .state_carry_write(state_carry_write_w),
    .state_payload_prefix(state_payload_prefix_w),
    .pending_push_valid(pending_push_valid_q),
    .precarry_len(precarry_len_q),
    .pending_push_word(pending_push_word_q),
    .op_valid(op_valid_w),
    .norm_push_count(norm_push_count_w),
    .norm_push0(norm_push0_w),
    .finish_s(finish_s_q),
    .finish_e(finish_e_q),
    .finish_c(finish_c_q),
    .carry_group_addr(carry_group_addr_w),
    .carry_group_strobe(carry_group_strobe_w),
    .carry_group_data(carry_group_data_w),
    .tile_is_last(tile_is_last_w),
    .payload_prefix_index(payload_prefix_index_q),
    .payload_len(payload_len_q),
    .payload_prefix_byte(payload_prefix_byte_w),
    .precarry_write_valid(precarry_write_valid_w),
    .precarry_write_addr(precarry_write_addr_w),
    .precarry_write_data(precarry_write_data_w),
    .payload_write_valid(payload_write_valid_w),
    .payload_write_addr(payload_write_addr_w),
    .payload_write_strobe(payload_write_strobe_w),
    .payload_write_data(payload_write_data_w)
  );

  ff_av2_local_hash_matcher_444 #(
    .SAMPLE_BITS(SAMPLE_BITS)
  ) local_hash_ibc (
    .clk(clk),
    .rst_n(rst_n),
    .start(palette_analyzer_start_w && (chroma_format_idc == 2'd3)),
    .sample_fire(input_sample_fire_w),
    .packet_fire(input_packet_fire_w && (chroma_format_idc == 2'd3)),
    .visible_width(tile_width_q),
    .visible_height(tile_height_q),
    .sample(s_axis_data),
    .sample_last(tile_input_last_w),
    .packet_samples(packet_axis_data[INPUT_PACKET_BITS - 1:0]),
    .packet_count(packet_axis_count_w),
    .packet_last(tile_input_last_w),
    .done(ibc_done_w),
    .copy_mask(ibc_copy_mask_w),
    .above_copy_mask(ibc_above_copy_mask_w),
    .ready_mask(ibc_ready_mask_w),
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
    .packet_fire(input_packet_fire_w),
    .packet_samples(packet_axis_data[INPUT_PACKET_BITS - 1:0]),
    .packet_count(packet_axis_count_w),
    .packet_last(tile_input_last_w),
    .sample_ready(palette_analyzer_sample_ready_w),
    .query_block_row_mi(block_row_mi_q),
    .query_block_col_mi(block_col_mi_q),
    .query_row(palette_row_q),
    .query_col(palette_col_q),
    .query_start(palette_query_start_w),
    .chroma_fetch_start(chroma_fetch_start_w),
    .chroma_fetch_plane_v(chroma_fetch_req_plane_v_w),
    .chroma_fetch_horz(leaf_chroma_bdpcm_horz_q),
    .chroma_fetch_predictor_only(chroma_fetch_predictor_only_w),
    .chroma_fetch_txb_row_mi(chroma_fetch_req_row_mi_w),
    .chroma_fetch_txb_col_mi(chroma_fetch_req_col_mi_w),
    .luma_fetch_start(luma_fetch_start_w),
    .luma_fetch_txb_row_mi(luma_fetch_req_row_mi_w),
    .luma_fetch_txb_col_mi(luma_fetch_req_col_mi_w),
    .lossy420_direct_luma_txb_row_mi(txb_row_w[4:0]),
    .lossy420_direct_luma_txb_col_mi(txb_col_w[4:0]),
    .lossy420_direct_chroma_txb_row_mi(chroma_fetch_current_storage_row_mi_w),
    .lossy420_direct_chroma_txb_col_mi(chroma_fetch_current_storage_col_mi_w),
    .lossy420_direct_chroma_plane_v(phase_v_coeff_w),
    .done(palette_analyzer_done_w),
    .unsupported(palette_analyzer_unsupported_w),
    .black_mode(palette_analyzer_black_w),
    .nonblack_seen(palette_analyzer_nonblack_seen_w),
    .luma_palette_mode(palette_analyzer_luma_mode_w),
    .block_ready_mask(palette_analyzer_block_ready_mask_w),
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
    .query_chroma_bdpcm_horz(palette_chroma_bdpcm_horz_w),
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
    .luma_fetch_predictor_samples(luma_fetch_predictor_samples_w),
    .luma_fetch_sample_sum(luma_fetch_sample_sum_w),
    .chroma_fetch_sample_sum(chroma_fetch_sample_sum_w),
    .lossy420_luma_sample_sum_now(lossy420_luma_sample_sum_now_w),
    .lossy420_chroma_sample_sum_now(lossy420_chroma_sample_sum_now_w)
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

  ff_av2_residual_contexts residual_contexts (
    .phase_v_coeff(phase_v_coeff_w),
    .chroma_format_idc(chroma_format_idc),
    .luma_above_context(txb_context_luma_above_w),
    .luma_left_context(txb_context_luma_left_w),
    .u_above_context(txb_context_u_above_w),
    .u_left_context(txb_context_u_left_w),
    .v_above_context(txb_context_v_above_w),
    .v_left_context(txb_context_v_left_w),
    .last_u_txb_nonzero(last_u_txb_nonzero_q),
    .txb_row(txb_row_w),
    .txb_col(txb_col_w),
    .luma_skip_ctx(luma_residual_skip_ctx_w),
    .luma_dc_sign_ctx(luma_residual_dc_sign_ctx_w),
    .chroma_bdpcm_skip_ctx(chroma_bdpcm_skip_ctx_w),
    .y_txb_nonzero_fh(y_txb_nonzero_fh_w),
    .u_txb_nonzero_fh(u_txb_nonzero_fh_w),
    .v_txb_nonzero_fh(v_txb_nonzero_fh_w),
    .y_dc_sign_fl(y_dc_sign_fl_w)
  );

  ff_av2_residual_top residual_top (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .pending_push_valid(pending_push_valid_q),
    .state_leaf(state_leaf_w),
    .state_chroma_fetch(state_chroma_fetch_w),
    .phase_y_coeff(phase_y_coeff_w),
    .phase_u_coeff(phase_u_coeff_w),
    .phase_v_coeff(phase_v_coeff_w),
    .palette_mode(palette_mode_q),
    .lossy_420_mode(lossy_420_mode_q),
    .leaf_chroma_bdpcm_horz(leaf_chroma_bdpcm_horz_q),
    .palette_luma_residual_zero(palette_luma_residual_zero_w),
    .luma_fetch_done(luma_fetch_done_w),
    .chroma_fetch_done(chroma_fetch_done_w),
    .chroma_fetch_current_cache_hit(chroma_fetch_current_cache_hit_w),
    .luma_residual_skip_ctx(luma_residual_skip_ctx_w),
    .luma_residual_dc_sign_ctx(luma_residual_dc_sign_ctx_w),
    .chroma_bdpcm_skip_ctx(chroma_bdpcm_skip_ctx_w),
    .luma_fetch_txb_samples(luma_fetch_txb_samples_w),
    .luma_fetch_predictor_samples(luma_fetch_predictor_samples_w),
    .lossy420_luma_sample_sum(lossy420_luma_sample_sum_now_w),
    .lossy420_luma_predictor(lossy420_luma_predictor_w),
    .chroma_bdpcm_txb_samples(chroma_bdpcm_txb_samples_w),
    .chroma_bdpcm_predictor_samples(chroma_bdpcm_predictor_samples_w),
    .lossy420_chroma_sample_sum(lossy420_chroma_sample_sum_now_w),
    .lossy420_chroma_predictor(lossy420_chroma_predictor_w),
    .residual_mode(residual_mode_w),
    .luma_residual_enable(luma_residual_enable_w),
    .chroma_bdpcm_enable(chroma_bdpcm_enable_w),
    .luma_residual_op_valid(luma_residual_op_valid_w),
    .luma_residual_op_literal(luma_residual_op_literal_w),
    .luma_residual_op_literal_value(luma_residual_op_literal_value_w),
    .luma_residual_op_literal_bits(luma_residual_op_literal_bits_w),
    .luma_residual_op_fl(luma_residual_op_fl_w),
    .luma_residual_op_fh(luma_residual_op_fh_w),
    .luma_residual_op_fl_inc(luma_residual_op_fl_inc_w),
    .luma_residual_op_fh_inc(luma_residual_op_fh_inc_w),
    .luma_residual_txb_done(luma_residual_txb_done_w),
    .luma_residual_entropy_context(luma_residual_entropy_context_w),
    .lossy420_luma_residual_recon_sample(lossy420_luma_residual_recon_sample_w),
    .lossy420_luma_delta(lossy420_luma_delta_w),
    .lossy420_luma_known_zero(lossy420_luma_known_zero_w),
    .palette_luma_residual_known_zero(palette_luma_residual_known_zero_w),
    .chroma_bdpcm_op_valid(chroma_bdpcm_op_valid_w),
    .chroma_bdpcm_op_literal(chroma_bdpcm_op_literal_w),
    .chroma_bdpcm_op_literal_value(chroma_bdpcm_op_literal_value_w),
    .chroma_bdpcm_op_literal_bits(chroma_bdpcm_op_literal_bits_w),
    .chroma_bdpcm_op_fl(chroma_bdpcm_op_fl_w),
    .chroma_bdpcm_op_fh(chroma_bdpcm_op_fh_w),
    .chroma_bdpcm_op_fl_inc(chroma_bdpcm_op_fl_inc_w),
    .chroma_bdpcm_op_fh_inc(chroma_bdpcm_op_fh_inc_w),
    .chroma_bdpcm_txb_done(chroma_bdpcm_txb_done_w),
    .chroma_bdpcm_txb_nonzero(chroma_bdpcm_txb_nonzero_w),
    .chroma_bdpcm_entropy_context(chroma_bdpcm_entropy_context_w),
    .lossy420_chroma_bdpcm_recon_sample(lossy420_chroma_bdpcm_recon_sample_w),
    .lossy420_chroma_delta(lossy420_chroma_delta_w),
    .lossy420_chroma_known_zero(lossy420_chroma_known_zero_w)
  );

  ff_av2_entropy_coder entropy_coder (
    .partition_active(state_partition_w),
    .leaf_active(state_leaf_w),
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
    .ibc_use_copy(decision_ibc_use_copy_w),
    .ibc_drl_idx(decision_ibc_drl_idx_w),
    .intrabc_ctx(intrabc_ctx_w),
    .intrabc_skip_ctx(intrabc_skip_ctx_w),
    .leaf_luma_mode(leaf_luma_mode_q),
    .leaf_fsc_symbol(leaf_fsc_symbol_w),
    .leaf_fsc_fh(leaf_fsc_fh_w),
    .palette_mode(palette_mode_q),
    .chroma_bdpcm_horz(leaf_chroma_bdpcm_horz_q),
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

  ff_av2_frontend_control #(
    .SUPPORT_PALETTE_444(SUPPORT_PALETTE_444)
  ) frontend_control (
    .start(start),
    .state_idle(state_idle_w),
    .state_tile_start(state_tile_start_w),
    .state_palette_query(state_palette_query_w),
    .chroma_format_idc(chroma_format_idc),
    .frame_count(frame_count),
    .visible_width(visible_width),
    .visible_height(visible_height),
    .packet_axis_valid(packet_axis_valid),
    .packet_axis_last(packet_axis_last),
    .packet_axis_count(packet_axis_count_w),
    .tile_input_index(tile_input_index_q),
    .tile_input_active(tile_input_active_q),
    .tile_block_count(tile_block_count_w),
    .tile_count(tile_count_q),
    .tile_index(tile_index_q),
    .payload_len(payload_len_q),
    .frame_index(frame_index_q),
    .palette_analyzer_sample_ready(palette_analyzer_sample_ready_w),
    .palette_analyzer_done(palette_analyzer_done_w),
    .palette_analyzer_nonblack_seen(palette_analyzer_nonblack_seen_w),
    .palette_analyzer_luma_mode(palette_analyzer_luma_mode_w),
    .palette_analyzer_black(palette_analyzer_black_w),
    .palette_analyzer_block_ready_mask(palette_analyzer_block_ready_mask_w),
    .bitstream_writer_frame_done(bitstream_writer_frame_done_w),
    .frame_reader_error(frame_reader_error_w),
    .bitstream_writer_error(bitstream_writer_error_w),
    .start_invalid(start_invalid_w),
    .packet_axis_ready(packet_axis_ready),
    .palette_analyzer_start(palette_analyzer_start_w),
    .input_sample_fire(input_sample_fire_w),
    .input_packet_fire(input_packet_fire_w),
    .input_fire(input_fire_w),
    .input_fire_count(input_fire_count_w),
    .input_axis_last(input_axis_last_w),
    .tile_input_last(tile_input_last_w),
    .input_fire_error(input_fire_error_w),
    .frame_is_last(frame_is_last_w),
    .palette_query_start(palette_query_start_w),
    .busy(busy),
    .frame_reader_start(frame_reader_start_w),
    .bitstream_writer_start(bitstream_writer_start_w),
    .done(done),
    .axi_error(axi_error),
    .tile_luma_samples(tile_luma_samples_w),
    .tile_samples(tile_samples_w),
    .tile_is_last(tile_is_last_w),
    .multi_tile(multi_tile_w),
    .payload_tile_start(payload_tile_start_w),
    .tile_entropy_start_ready(tile_entropy_start_ready_w),
    .tile_entropy_palette_mode(tile_entropy_palette_mode_w),
    .tile_entropy_lossy420_mode(tile_entropy_lossy420_mode_w),
    .tile_entropy_ibc_mode(tile_entropy_ibc_mode_w)
  );

  ff_av2_txb_scheduler txb_scheduler (
    .start(start),
    .pending_push_valid(pending_push_valid_q),
    .state_leaf(state_leaf_w),
    .state_chroma_fetch(state_chroma_fetch_w),
    .phase_intra(phase_intra_w),
    .phase_palette_header(phase_palette_header_w),
    .phase_palette_map(phase_palette_map_w),
    .phase_y_coeff(phase_y_coeff_w),
    .phase_u_coeff(phase_u_coeff_w),
    .phase_v_coeff(phase_v_coeff_w),
    .chroma_format_idc(chroma_format_idc),
    .palette_mode(palette_mode_q),
    .leaf_chroma_bdpcm_horz(leaf_chroma_bdpcm_horz_q),
    .residual_mode(residual_mode_w),
    .lossy_420_mode(lossy_420_mode_q),
    .block_row_mi(block_row_mi_q),
    .block_col_mi(block_col_mi_q),
    .block_w_mi(block_w_mi_q),
    .block_h_mi(block_h_mi_q),
    .visible_cols_mi(visible_cols_mi_q),
    .visible_rows_mi(visible_rows_mi_q),
    .txb_local_row(txb_local_row_q),
    .txb_local_col(txb_local_col_q),
    .txb_index(txb_index_q),
    .current_txb_count(txb_count_q),
    .current_txb_width(txb_width_q),
    .txb_prefetch_started(txb_prefetch_started_q),
    .txb_prefetch_done(txb_prefetch_done_q),
    .txb_prefetch_chroma(txb_prefetch_chroma_q),
    .txb_prefetch_plane_v(txb_prefetch_plane_v_q),
    .txb_prefetch_index(txb_prefetch_index_q),
    .luma_fetch_done(luma_fetch_done_w),
    .chroma_fetch_done(chroma_fetch_done_w),
    .cached_chroma_samples_valid(cached_chroma_samples_valid_q),
    .cached_v_valid(cached_v_valid_q),
    .left_edge_valid(left_edge_valid_q),
    .left_edge_row_mi(left_edge_row_mi_q),
    .left_edge_col_mi(left_edge_col_mi_q),
    .above_col0_valid(above_col0_valid_q),
    .above_col0_row_mi(above_col0_row_mi_q),
    .chroma_fetch_start(chroma_fetch_start_w),
    .luma_fetch_start(luma_fetch_start_w),
    .leaf_visible_txb_w(leaf_visible_txb_w_w),
    .leaf_visible_txb_h(leaf_visible_txb_h_w),
    .txb_width(txb_width_w),
    .txb_count(txb_count_w),
    .chroma_txb_width(chroma_txb_width_w),
    .chroma_txb_count(chroma_txb_count_w),
    .chroma_subsampled_phase(chroma_subsampled_phase_w),
    .txb_row(txb_row_w),
    .txb_col(txb_col_w),
    .same_phase_has_next_txb(same_phase_has_next_txb_w),
    .cross_phase_has_next_txb(cross_phase_has_next_txb_w),
    .next_txb_local_row(next_txb_local_row_w),
    .next_txb_local_col(next_txb_local_col_w),
    .next_txb_row(next_txb_row_w),
    .next_txb_col(next_txb_col_w),
    .txb_fetch_done(txb_fetch_done_w),
    .txb_prefetch_fetch_done(txb_prefetch_fetch_done_w),
    .v_chroma_cache_hit(v_chroma_cache_hit_w),
    .u_chroma_cache_hit(u_chroma_cache_hit_w),
    .chroma_fetch_current_cache_hit(chroma_fetch_current_cache_hit_w),
    .chroma_fetch_cache_index(chroma_fetch_cache_index_w),
    .luma_fetch_cache_index(luma_fetch_cache_index_w),
    .chroma_fetch_req_cross_phase(chroma_fetch_req_cross_phase_w),
    .chroma_fetch_req_next_txb(chroma_fetch_req_next_txb_w),
    .chroma_fetch_req_index(chroma_fetch_req_index_w),
    .chroma_predictor_compute_valid(chroma_predictor_compute_valid_w),
    .chroma_fetch_req_predictor_compute(chroma_fetch_req_predictor_compute_w),
    .chroma_external_left_predictor_valid(chroma_external_left_predictor_valid_w),
    .chroma_req_external_left_predictor_valid(chroma_req_external_left_predictor_valid_w),
    .chroma_external_above_predictor_valid(chroma_external_above_predictor_valid_w),
    .chroma_req_external_above_predictor_valid(chroma_req_external_above_predictor_valid_w),
    .chroma_fetch_req_ready(chroma_fetch_req_ready_w),
    .chroma_fetch_predictor_only(chroma_fetch_predictor_only_w),
    .chroma_fetch_completed_u(chroma_fetch_completed_u_w),
    .luma_fetch_completed(luma_fetch_completed_w),
    .txb_prefetch_chroma_target_v(txb_prefetch_chroma_target_v_w),
    .txb_prefetch_luma_start(txb_prefetch_luma_start_w),
    .txb_prefetch_chroma_start(txb_prefetch_chroma_start_w),
    .txb_prefetch_cross_phase(txb_prefetch_cross_phase_w),
    .txb_prefetch_first_luma(txb_prefetch_first_luma_w),
    .luma_fetch_req_row_mi(luma_fetch_req_row_mi_w),
    .luma_fetch_req_col_mi(luma_fetch_req_col_mi_w),
    .chroma_fetch_current_storage_row_mi(chroma_fetch_current_storage_row_mi_w),
    .chroma_fetch_current_storage_col_mi(chroma_fetch_current_storage_col_mi_w),
    .chroma_fetch_next_storage_row_mi(chroma_fetch_next_storage_row_mi_w),
    .chroma_fetch_next_storage_col_mi(chroma_fetch_next_storage_col_mi_w),
    .chroma_fetch_req_row_mi(chroma_fetch_req_row_mi_w),
    .chroma_fetch_req_col_mi(chroma_fetch_req_col_mi_w),
    .chroma_fetch_req_plane_v(chroma_fetch_req_plane_v_w),
    .chroma_left_source_index(chroma_left_source_index_w),
    .chroma_above_source_index(chroma_above_source_index_w)
  );

  ff_av2_lossy420_predictors lossy420_predictors (
    .phase_v_coeff(phase_v_coeff_w),
    .block_row_mi(block_row_mi_q),
    .block_col_mi(block_col_mi_q),
    .txb_row(txb_row_w),
    .txb_col(txb_col_w),
    .txb_index(txb_index_q),
    .luma_recon0(lossy420_luma_recon_q[0]),
    .luma_recon1(lossy420_luma_recon_q[1]),
    .luma_recon2(lossy420_luma_recon_q[2]),
    .luma_recon3(lossy420_luma_recon_q[3]),
    .luma_above(lossy420_luma_above_q[txb_col_w[3:0]]),
    .luma_above_valid(lossy420_luma_above_valid_q[txb_col_w[3:0]]),
    .luma_left_top(lossy420_luma_left_top_q[block_row_mi_q[3:0]]),
    .luma_left_bottom(lossy420_luma_left_bottom_q[block_row_mi_q[3:0]]),
    .luma_left_col_mi(lossy420_luma_left_col_mi_q[block_row_mi_q[3:0]]),
    .luma_left_valid(lossy420_luma_left_valid_q[block_row_mi_q[3:0]]),
    .u_above(lossy420_u_above_q[txb_col_w[3:0]]),
    .v_above(lossy420_v_above_q[txb_col_w[3:0]]),
    .u_above_valid(lossy420_u_above_valid_q[txb_col_w[3:0]]),
    .v_above_valid(lossy420_v_above_valid_q[txb_col_w[3:0]]),
    .u_left(lossy420_u_left_q[txb_row_w[3:0]]),
    .v_left(lossy420_v_left_q[txb_row_w[3:0]]),
    .u_left_col_mi(lossy420_u_left_col_mi_q[txb_row_w[3:0]]),
    .v_left_col_mi(lossy420_v_left_col_mi_q[txb_row_w[3:0]]),
    .u_left_valid(lossy420_u_left_valid_q[txb_row_w[3:0]]),
    .v_left_valid(lossy420_v_left_valid_q[txb_row_w[3:0]]),
    .luma_left_row_index(lossy420_luma_left_row_index_w),
    .chroma_left_row_index(lossy420_chroma_left_row_index_w),
    .luma_predictor(lossy420_luma_predictor_w),
    .chroma_predictor(lossy420_chroma_predictor_w)
  );

  // AV2 4:4:4 bring-up path: traverse one 64x64 superblock, split visible
  // coding leaves down to 8x8, and generate syntax through the range coder.
  // Any TX_4X4 loops below are AV2 transform blocks, not public input blocks.
  // AV2 bring-up input order is a visible 8x8 block packet: 64 Y samples,
  // 64 U samples, then 64 V samples. This mirrors the VVC 4:4:4 8x8-leaf
  // packing at the interface while allowing the AV2 superblock walker to keep
  // its own partition/leaf order internally.
  ff_av2_encoder_ibc_controls #(
    .SAMPLE_BITS(SAMPLE_BITS)
  ) ibc_controls (
    .block_row_mi_q(block_row_mi_q),
    .block_col_mi_q(block_col_mi_q),
    .palette_analyzer_block_ready_mask_w(palette_analyzer_block_ready_mask_w),
    .palette_analyzer_done_w(palette_analyzer_done_w),
    .frame_ibc_mode_q(frame_ibc_mode_q),
    .ibc_ready_mask_w(ibc_ready_mask_w),
    .ibc_done_w(ibc_done_w),
    .block_w_mi_q(block_w_mi_q),
    .block_h_mi_q(block_h_mi_q),
    .ibc_copy_mask_w(ibc_copy_mask_w),
    .ibc_drl_idx_table_w(ibc_drl_idx_table_w),
    .ibc_above_ctx_w(ibc_above_ctx_w),
    .ibc_left_ctx_w(ibc_left_ctx_w),
    .skip_above_ctx_w(skip_above_ctx_w),
    .skip_left_ctx_w(skip_left_ctx_w),
    .s_axis_valid(s_axis_valid),
    .s_axis_data(s_axis_data),
    .s_axis_last(s_axis_last),
    .s_axis_ready(s_axis_ready),
    .ibc_current_block_id_w(ibc_current_block_id_w),
    .current_leaf_block_id_w(current_leaf_block_id_w),
    .current_leaf_ready_w(current_leaf_ready_w),
    .ibc_drl_idx_bit_index_w(ibc_drl_idx_bit_index_w),
    .ibc_use_copy_w(ibc_use_copy_w),
    .ibc_drl_idx_w(ibc_drl_idx_w),
    .intrabc_ctx_w(intrabc_ctx_w),
    .intrabc_skip_ctx_w(intrabc_skip_ctx_w)
  );

  ff_av2_prediction_decision prediction_decision (
    .palette_mode(palette_mode_q),
    .lossy_420_mode(lossy_420_mode_q),
    .ibc_use_copy(ibc_use_copy_w),
    .ibc_drl_idx(ibc_drl_idx_w),
    .current_leaf_luma_mode(leaf_luma_mode_q),
    .analyzed_luma_mode(palette_luma_mode_w),
    .analyzed_chroma_bdpcm_horz(palette_chroma_bdpcm_horz_w),
    .selected_ibc_use_copy(decision_ibc_use_copy_w),
    .selected_ibc_drl_idx(decision_ibc_drl_idx_w),
    .selected_leaf_luma_mode(decision_leaf_luma_mode_w),
    .selected_leaf_chroma_bdpcm_horz(decision_leaf_chroma_bdpcm_horz_w),
    .leaf_luma_palette(leaf_luma_palette_w),
    .residual_mode(residual_mode_w)
  );
  ff_av2_chroma_predictor_cache chroma_predictor_cache (
    .lossy_420_mode(lossy_420_mode_q),
    .phase_u_coeff(phase_u_coeff_w),
    .phase_v_coeff(phase_v_coeff_w),
    .txb_row(txb_row_w),
    .txb_col(txb_col_w),
    .txb_index(txb_index_q),
    .chroma_left_source_index(chroma_left_source_index_w),
    .chroma_above_source_index(chroma_above_source_index_w),
    .chroma_predictor_compute_valid(chroma_predictor_compute_valid_w),
    .chroma_external_left_predictor_valid(chroma_external_left_predictor_valid_w),
    .chroma_external_above_predictor_valid(chroma_external_above_predictor_valid_w),
    .cached_chroma_samples_valid(cached_chroma_samples_valid_q),
    .cached_v_valid(cached_v_valid_q),
    .cached_u_txb_samples0(cached_u_txb_samples_q[0]),
    .cached_u_txb_samples1(cached_u_txb_samples_q[1]),
    .cached_u_txb_samples2(cached_u_txb_samples_q[2]),
    .cached_u_txb_samples3(cached_u_txb_samples_q[3]),
    .cached_v_txb_samples0(cached_v_txb_samples_q[0]),
    .cached_v_txb_samples1(cached_v_txb_samples_q[1]),
    .cached_v_txb_samples2(cached_v_txb_samples_q[2]),
    .cached_v_txb_samples3(cached_v_txb_samples_q[3]),
    .cached_v_predictor_samples0(cached_v_predictor_samples_q[0]),
    .cached_v_predictor_samples1(cached_v_predictor_samples_q[1]),
    .cached_v_predictor_samples2(cached_v_predictor_samples_q[2]),
    .cached_v_predictor_samples3(cached_v_predictor_samples_q[3]),
    .left_edge_u_top(left_edge_u_top_q),
    .left_edge_u_bottom(left_edge_u_bottom_q),
    .left_edge_v_top(left_edge_v_top_q),
    .left_edge_v_bottom(left_edge_v_bottom_q),
    .above_col0_u(above_col0_u_q),
    .above_col0_v(above_col0_v_q),
    .chroma_fetch_txb_samples(chroma_fetch_txb_samples_w),
    .chroma_fetch_predictor_samples(chroma_fetch_predictor_samples_w),
    .chroma_cached_predictor_samples(chroma_cached_predictor_samples_w),
    .current_u_right_edge_top(current_u_right_edge_top_w),
    .current_u_right_edge_bottom(current_u_right_edge_bottom_w),
    .current_v_right_edge_top(current_v_right_edge_top_w),
    .current_v_right_edge_bottom(current_v_right_edge_bottom_w),
    .current_u_col0_above_edge(current_u_col0_above_edge_w),
    .current_v_col0_above_edge(current_v_col0_above_edge_w),
    .chroma_bdpcm_txb_samples(chroma_bdpcm_txb_samples_w),
    .chroma_bdpcm_predictor_samples(chroma_bdpcm_predictor_samples_w)
  );
  ff_av2_encoder_payload_word_delay payload_word_delay (
    .clk(clk),
    .rst_n(rst_n),
    .payload_read_word_addr_q(payload_read_word_addr_q),
    .payload_read_data_word_addr_q(payload_read_data_word_addr_q)
  );

  ff_sync_halfword_write_quad_read_ram_1r1w #(
    .ADDR_BITS(16),
    .DEPTH_HALFWORDS(AV2_MAX_TILE_BYTES),
    .READ_HALFWORDS(16)
  ) precarry_ram (
    .clk(clk),
    .write_valid(precarry_write_valid_w),
    .write_addr(precarry_write_addr_w),
    .write_data(precarry_write_data_w),
    .read_word_addr(precarry_read_word_addr_q),
    .read_data(precarry_read_word_data_w)
  );

  ff_sync_byte_write_word_ram_1r1w #(
    .ADDR_BITS(16),
    .DEPTH_BYTES(AV2_MAX_TILE_BYTES)
  ) payload_ram (
    .clk(clk),
    .write_valid(payload_write_valid_w),
    .write_addr(payload_write_addr_w),
    .write_strobe(payload_write_strobe_w),
    .write_data(payload_write_data_w),
    .read_word_addr(payload_read_word_addr_q),
    .read_data(payload_read_data_w)
  );

  ff_av2_encoder_seq_stream seq_stream (
    .stream_lookup_index_w(stream_lookup_index_w),
    .seq_end_index_w(seq_end_index_w),
    .seq_stream_index_w(seq_stream_index_w),
    .seq_mem_q(seq_mem_q),
    .seq_bits_left_q(seq_bits_left_q),
    .seq_bit_pos_q(seq_bit_pos_q),
    .seq_stream_byte_w(seq_stream_byte_w),
    .seq_byte_remaining_w(seq_byte_remaining_w),
    .seq_write_step_w(seq_write_step_w)
  );

  ff_av2_encoder_control_fsm control_fsm (
    .clk(clk),
    .rst_n(rst_n),
    .state_q(state_q),
    .above_col0_row_mi_q(above_col0_row_mi_q),
    .above_col0_u_q(above_col0_u_q),
    .above_col0_v_q(above_col0_v_q),
    .above_col0_valid_q(above_col0_valid_q),
    .bitstream_writer_error_w(bitstream_writer_error_w),
    .block_col_mi_q(block_col_mi_q),
    .block_h_mi_q(block_h_mi_q),
    .block_half_h_mi_w(block_half_h_mi_w),
    .block_half_w_mi_w(block_half_w_mi_w),
    .block_row_mi_q(block_row_mi_q),
    .block_visible_w(block_visible_w),
    .block_w_mi_q(block_w_mi_q),
    .cached_chroma_samples_valid_q(cached_chroma_samples_valid_q),
    .cached_u_txb_samples_q(cached_u_txb_samples_q),
    .cached_v_predictor_samples_q(cached_v_predictor_samples_q),
    .cached_v_txb_samples_q(cached_v_txb_samples_q),
    .cached_v_valid_q(cached_v_valid_q),
    .carry_after_step_w(carry_after_step_w),
    .carry_done_after_step_w(carry_done_after_step_w),
    .carry_index_after_step_w(carry_index_after_step_w),
    .carry_index_q(carry_index_q),
    .carry_q(carry_q),
    .carry_read_after_current_word_addr_w(carry_read_after_current_word_addr_w),
    .carry_read_after_next_word_addr_w(carry_read_after_next_word_addr_w),
    .chosen_partition_w(chosen_partition_w),
    .chroma_bdpcm_txb_done_w(chroma_bdpcm_txb_done_w),
    .chroma_bdpcm_txb_nonzero_w(chroma_bdpcm_txb_nonzero_w),
    .chroma_fetch_cache_index_w(chroma_fetch_cache_index_w),
    .chroma_fetch_completed_u_w(chroma_fetch_completed_u_w),
    .chroma_fetch_current_cache_hit_w(chroma_fetch_current_cache_hit_w),
    .chroma_fetch_done_w(chroma_fetch_done_w),
    .chroma_fetch_req_plane_v_w(chroma_fetch_req_plane_v_w),
    .chroma_fetch_req_ready_w(chroma_fetch_req_ready_w),
    .chroma_fetch_v_predictor_samples_w(chroma_fetch_v_predictor_samples_w),
    .chroma_fetch_v_txb_samples_w(chroma_fetch_v_txb_samples_w),
    .chroma_txb_count_w(chroma_txb_count_w),
    .chroma_txb_width_w(chroma_txb_width_w),
    .cnt_q(cnt_q),
    .current_leaf_ready_w(current_leaf_ready_w),
    .current_u_col0_above_edge_w(current_u_col0_above_edge_w),
    .current_u_right_edge_bottom_w(current_u_right_edge_bottom_w),
    .current_u_right_edge_top_w(current_u_right_edge_top_w),
    .current_v_col0_above_edge_w(current_v_col0_above_edge_w),
    .current_v_right_edge_bottom_w(current_v_right_edge_bottom_w),
    .current_v_right_edge_top_w(current_v_right_edge_top_w),
    .finish_c_q(finish_c_q),
    .finish_e_q(finish_e_q),
    .finish_s_q(finish_s_q),
    .frame_ibc_mode_q(frame_ibc_mode_q),
    .frame_index_q(frame_index_q),
    .frame_is_last_w(frame_is_last_w),
    .frame_palette_mode_q(frame_palette_mode_q),
    .frame_reader_error_w(frame_reader_error_w),
    .height_bits_q(height_bits_q),
    .height_bits_w(height_bits_w),
    .height_q(height_q),
    .decision_ibc_drl_idx_w(decision_ibc_drl_idx_w),
    .decision_ibc_use_copy_w(decision_ibc_use_copy_w),
    .input_error(input_error),
    .input_fire_count_w(input_fire_count_w),
    .input_fire_error_w(input_fire_error_w),
    .input_fire_w(input_fire_w),
    .input_frame_offset_q(input_frame_offset_q),
    .last_u_txb_nonzero_q(last_u_txb_nonzero_q),
    .leaf_chroma_bdpcm_horz_q(leaf_chroma_bdpcm_horz_q),
    .leaf_fsc_symbol_w(leaf_fsc_symbol_w),
    .leaf_luma_mode_q(leaf_luma_mode_q),
    .leaf_luma_palette_w(leaf_luma_palette_w),
    .left_edge_col_mi_q(left_edge_col_mi_q),
    .left_edge_row_mi_q(left_edge_row_mi_q),
    .left_edge_u_bottom_q(left_edge_u_bottom_q),
    .left_edge_u_top_q(left_edge_u_top_q),
    .left_edge_v_bottom_q(left_edge_v_bottom_q),
    .left_edge_v_top_q(left_edge_v_top_q),
    .left_edge_valid_q(left_edge_valid_q),
    .lossy420_chroma_bdpcm_recon_sample_w(lossy420_chroma_bdpcm_recon_sample_w),
    .lossy420_chroma_left_row_index_w(lossy420_chroma_left_row_index_w),
    .lossy420_luma_above_q(lossy420_luma_above_q),
    .lossy420_luma_above_valid_q(lossy420_luma_above_valid_q),
    .lossy420_luma_left_bottom_q(lossy420_luma_left_bottom_q),
    .lossy420_luma_left_col_mi_q(lossy420_luma_left_col_mi_q),
    .lossy420_luma_left_row_index_w(lossy420_luma_left_row_index_w),
    .lossy420_luma_left_top_q(lossy420_luma_left_top_q),
    .lossy420_luma_left_valid_q(lossy420_luma_left_valid_q),
    .lossy420_luma_recon_q(lossy420_luma_recon_q),
    .lossy420_luma_residual_recon_sample_w(lossy420_luma_residual_recon_sample_w),
    .lossy420_u_above_q(lossy420_u_above_q),
    .lossy420_u_above_valid_q(lossy420_u_above_valid_q),
    .lossy420_u_left_col_mi_q(lossy420_u_left_col_mi_q),
    .lossy420_u_left_q(lossy420_u_left_q),
    .lossy420_u_left_valid_q(lossy420_u_left_valid_q),
    .lossy420_v_above_q(lossy420_v_above_q),
    .lossy420_v_above_valid_q(lossy420_v_above_valid_q),
    .lossy420_v_left_col_mi_q(lossy420_v_left_col_mi_q),
    .lossy420_v_left_q(lossy420_v_left_q),
    .lossy420_v_left_valid_q(lossy420_v_left_valid_q),
    .lossy_420_mode_q(lossy_420_mode_q),
    .low_q(low_q),
    .luma_fetch_cache_index_w(luma_fetch_cache_index_w),
    .luma_fetch_completed_w(luma_fetch_completed_w),
    .luma_fetch_done_w(luma_fetch_done_w),
    .luma_fetch_u_txb_samples_w(luma_fetch_u_txb_samples_w),
    .luma_fetch_v_txb_samples_w(luma_fetch_v_txb_samples_w),
    .luma_residual_txb_done_w(luma_residual_txb_done_w),
    .m_axis_count(m_axis_count),
    .m_axis_data(m_axis_data),
    .m_axis_last(m_axis_last),
    .m_axis_ready(m_axis_ready),
    .m_axis_valid(m_axis_valid),
    .norm_cnt_w(norm_cnt_w),
    .norm_low_w(norm_low_w),
    .norm_push1_w(norm_push1_w),
    .norm_push_count_w(norm_push_count_w),
    .norm_rng_w(norm_rng_w),
    .op_last_w(op_last_w),
    .op_valid_w(op_valid_w),
    .output_after_current_payload_w(output_after_current_payload_w),
    .output_after_current_payload_word_addr_w(output_after_current_payload_word_addr_w),
    .output_after_next_payload_w(output_after_next_payload_w),
    .output_after_next_payload_word_addr_w(output_after_next_payload_word_addr_w),
    .output_byte_phase_q(output_byte_phase_q),
    .output_current_packet_last_w(output_current_packet_last_w),
    .output_last_q(output_last_q),
    .output_lookup_byte_w(output_lookup_byte_w),
    .output_lookup_last_w(output_lookup_last_w),
    .output_next_byte_phase_w(output_next_byte_phase_w),
    .output_next_packet_last_w(output_next_packet_last_w),
    .output_next_payload_count_w(output_next_payload_count_w),
    .output_next_payload_packet_data_w(output_next_payload_packet_data_w),
    .output_next_payload_word_addr_w(output_next_payload_word_addr_w),
    .output_next_stream_index_w(output_next_stream_index_w),
    .output_payload_count_w(output_payload_count_w),
    .output_payload_packet_data_w(output_payload_packet_data_w),
    .palette_analyzer_done_w(palette_analyzer_done_w),
    .palette_analyzer_unsupported_w(palette_analyzer_unsupported_w),
    .decision_leaf_chroma_bdpcm_horz_w(decision_leaf_chroma_bdpcm_horz_w),
    .palette_col_q(palette_col_q),
    .palette_header_last_step_w(palette_header_last_step_w),
    .palette_identity_row_ctx_q(palette_identity_row_ctx_q),
    .palette_identity_row_flag_w(palette_identity_row_flag_w),
    .decision_leaf_luma_mode_w(decision_leaf_luma_mode_w),
    .palette_map_token_required_w(palette_map_token_required_w),
    .palette_mode_q(palette_mode_q),
    .palette_query_done_w(palette_query_done_w),
    .palette_row_q(palette_row_q),
    .partition_emit_do_split_w(partition_emit_do_split_w),
    .partition_emit_step_q(partition_emit_step_q),
    .partition_need_rect_w(partition_need_rect_w),
    .partition_q(partition_q),
    .payload_len_q(payload_len_q),
    .payload_prefix_index_q(payload_prefix_index_q),
    .payload_read_data_word_addr_q(payload_read_data_word_addr_q),
    .payload_read_word_addr_q(payload_read_word_addr_q),
    .pending_push_valid_q(pending_push_valid_q),
    .pending_push_word_q(pending_push_word_q),
    .phase_q(phase_q),
    .precarry_len_q(precarry_len_q),
    .precarry_read_word_addr_q(precarry_read_word_addr_q),
    .residual_mode_w(residual_mode_w),
    .rng_q(rng_q),
    .seq_bit_pos_q(seq_bit_pos_q),
    .seq_bits_left_q(seq_bits_left_q),
    .seq_len_q(seq_len_q),
    .seq_load_bits_w(seq_load_bits_w),
    .seq_load_value_w(seq_load_value_w),
    .seq_mem_q(seq_mem_q),
    .seq_op_q(seq_op_q),
    .seq_value_q(seq_value_q),
    .seq_write_step_w(seq_write_step_w),
    .src_frame_stride(src_frame_stride),
    .stack_col_mi_q(stack_col_mi_q),
    .stack_h_mi_q(stack_h_mi_q),
    .stack_row_mi_q(stack_row_mi_q),
    .stack_sp_q(stack_sp_q),
    .stack_w_mi_q(stack_w_mi_q),
    .start(start),
    .start_invalid_w(start_invalid_w),
    .step_q(step_q),
    .stream_index_q(stream_index_q),
    .tile_col_q(tile_col_q),
    .tile_cols_q(tile_cols_q),
    .tile_cols_w(tile_cols_w),
    .tile_count_q(tile_count_q),
    .tile_count_w(tile_count_w),
    .tile_entropy_ibc_mode_w(tile_entropy_ibc_mode_w),
    .tile_entropy_lossy420_mode_w(tile_entropy_lossy420_mode_w),
    .tile_entropy_palette_mode_w(tile_entropy_palette_mode_w),
    .tile_entropy_start_ready_w(tile_entropy_start_ready_w),
    .tile_height_q(tile_height_q),
    .tile_index_q(tile_index_q),
    .tile_input_active_q(tile_input_active_q),
    .tile_input_index_q(tile_input_index_q),
    .tile_is_last_w(tile_is_last_w),
    .tile_len_q(tile_len_q),
    .tile_payload_start_w(tile_payload_start_w),
    .tile_row_q(tile_row_q),
    .tile_rows_q(tile_rows_q),
    .tile_rows_w(tile_rows_w),
    .tile_width_q(tile_width_q),
    .txb_col_w(txb_col_w),
    .txb_count_q(txb_count_q),
    .txb_count_w(txb_count_w),
    .txb_index_q(txb_index_q),
    .txb_local_col_q(txb_local_col_q),
    .txb_local_row_q(txb_local_row_q),
    .txb_prefetch_chroma_q(txb_prefetch_chroma_q),
    .txb_prefetch_chroma_start_w(txb_prefetch_chroma_start_w),
    .txb_prefetch_cross_phase_w(txb_prefetch_cross_phase_w),
    .txb_prefetch_done_q(txb_prefetch_done_q),
    .txb_prefetch_fetch_done_w(txb_prefetch_fetch_done_w),
    .txb_prefetch_first_luma_w(txb_prefetch_first_luma_w),
    .txb_prefetch_index_q(txb_prefetch_index_q),
    .txb_prefetch_luma_start_w(txb_prefetch_luma_start_w),
    .txb_prefetch_plane_v_q(txb_prefetch_plane_v_q),
    .txb_prefetch_started_q(txb_prefetch_started_q),
    .txb_width_q(txb_width_q),
    .txb_width_w(txb_width_w),
    .visible_cols_mi_q(visible_cols_mi_q),
    .visible_cols_mi_w(visible_cols_mi_w),
    .visible_height(visible_height),
    .visible_rows_mi_q(visible_rows_mi_q),
    .visible_rows_mi_w(visible_rows_mi_w),
    .visible_width(visible_width),
    .width_bits_q(width_bits_q),
    .width_bits_w(width_bits_w),
    .width_q(width_q)
  );

endmodule
