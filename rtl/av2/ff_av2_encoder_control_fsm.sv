// Generated control FSM module for AV2 top-level orchestration.
module ff_av2_encoder_control_fsm #(
  parameter int AXI_ADDR_BITS = 32,
  parameter int AXI_DATA_BITS = 128,
  parameter int OUTPUT_PACKET_COUNT_BITS = 5,
  parameter int AV2_MAX_SEQUENCE_BYTES = 16,
  parameter int AV2_STACK_DEPTH = 16,
  parameter int AV2_PARTITION_CONTEXT_DIM = 16
) (
  input  logic       clk,
  input  logic       rst_n,
  output  logic [4:0] state_q,
  output logic [4:0] above_col0_row_mi_q,
  output logic [31:0] above_col0_u_q,
  output logic [31:0] above_col0_v_q,
  output logic above_col0_valid_q,
  input logic       bitstream_writer_error_w,
  output logic [4:0] block_col_mi_q,
  output logic [4:0] block_h_mi_q,
  input logic [4:0] block_half_h_mi_w,
  input logic [4:0] block_half_w_mi_w,
  output logic [4:0] block_row_mi_q,
  input logic block_visible_w,
  output logic [4:0] block_w_mi_q,
  output logic [3:0] cached_chroma_samples_valid_q,
  output logic [3:0][127:0] cached_u_txb_samples_q,
  output logic [3:0][31:0] cached_v_predictor_samples_q,
  output logic [3:0][127:0] cached_v_txb_samples_q,
  output logic [3:0] cached_v_valid_q,
  input logic [15:0] carry_after_step_w,
  input logic carry_done_after_step_w,
  input logic [15:0] carry_index_after_step_w,
  output logic [15:0] carry_index_q,
  output logic [15:0] carry_q,
  input logic [11:0] carry_read_after_current_word_addr_w,
  input logic [11:0] carry_read_after_next_word_addr_w,
  input logic [1:0] chosen_partition_w,
  input logic chroma_bdpcm_txb_done_w,
  input logic chroma_bdpcm_txb_nonzero_w,
  input logic [1:0] chroma_fetch_cache_index_w,
  input logic chroma_fetch_completed_u_w,
  input logic chroma_fetch_current_cache_hit_w,
  input logic chroma_fetch_done_w,
  input logic chroma_fetch_req_plane_v_w,
  input logic chroma_fetch_req_ready_w,
  input logic [31:0] chroma_fetch_v_predictor_samples_w,
  input logic [127:0] chroma_fetch_v_txb_samples_w,
  input logic [15:0] chroma_txb_count_w,
  input logic [15:0] chroma_txb_width_w,
  output logic signed [7:0] cnt_q,
  input logic current_leaf_ready_w,
  input logic [31:0] current_u_col0_above_edge_w,
  input logic [31:0] current_u_right_edge_bottom_w,
  input logic [31:0] current_u_right_edge_top_w,
  input logic [31:0] current_v_col0_above_edge_w,
  input logic [31:0] current_v_right_edge_bottom_w,
  input logic [31:0] current_v_right_edge_top_w,
  output logic signed [7:0] finish_c_q,
  output logic [63:0] finish_e_q,
  output logic signed [7:0] finish_s_q,
  output logic frame_ibc_mode_q,
  output logic [31:0] frame_index_q,
  input logic frame_is_last_w,
  output logic frame_palette_mode_q,
  input logic       frame_reader_error_w,
  output logic [4:0] height_bits_q,
  input logic [4:0] height_bits_w,
  output logic [15:0] height_q,
  input logic [1:0] ibc_drl_idx_w,
  input logic ibc_use_copy_w,
  output logic       input_error,
  input logic [3:0] input_fire_count_w,
  input logic input_fire_error_w,
  input logic input_fire_w,
  output logic [AXI_ADDR_BITS - 1:0] input_frame_offset_q,
  output logic last_u_txb_nonzero_q,
  output logic leaf_chroma_bdpcm_horz_q,
  input logic leaf_fsc_symbol_w,
  output logic [1:0] leaf_luma_mode_q,
  input logic leaf_luma_palette_w,
  output logic [4:0] left_edge_col_mi_q,
  output logic [4:0] left_edge_row_mi_q,
  output logic [31:0] left_edge_u_bottom_q,
  output logic [31:0] left_edge_u_top_q,
  output logic [31:0] left_edge_v_bottom_q,
  output logic [31:0] left_edge_v_top_q,
  output logic left_edge_valid_q,
  input logic [7:0] lossy420_chroma_bdpcm_recon_sample_w,
  input logic [3:0] lossy420_chroma_left_row_index_w,
  output logic [15:0][7:0] lossy420_luma_above_q,
  output logic [15:0] lossy420_luma_above_valid_q,
  output logic [15:0][7:0] lossy420_luma_left_bottom_q,
  output logic [15:0][4:0] lossy420_luma_left_col_mi_q,
  input logic [3:0] lossy420_luma_left_row_index_w,
  output logic [15:0][7:0] lossy420_luma_left_top_q,
  output logic [15:0] lossy420_luma_left_valid_q,
  output logic [3:0][7:0] lossy420_luma_recon_q,
  input logic [7:0] lossy420_luma_residual_recon_sample_w,
  output logic [15:0][7:0] lossy420_u_above_q,
  output logic [15:0] lossy420_u_above_valid_q,
  output logic [15:0][4:0] lossy420_u_left_col_mi_q,
  output logic [15:0][7:0] lossy420_u_left_q,
  output logic [15:0] lossy420_u_left_valid_q,
  output logic [15:0][7:0] lossy420_v_above_q,
  output logic [15:0] lossy420_v_above_valid_q,
  output logic [15:0][4:0] lossy420_v_left_col_mi_q,
  output logic [15:0][7:0] lossy420_v_left_q,
  output logic [15:0] lossy420_v_left_valid_q,
  output logic lossy_420_mode_q,
  output logic [63:0] low_q,
  input logic [1:0] luma_fetch_cache_index_w,
  input logic luma_fetch_completed_w,
  input logic luma_fetch_done_w,
  input logic [127:0] luma_fetch_u_txb_samples_w,
  input logic [127:0] luma_fetch_v_txb_samples_w,
  input logic luma_residual_txb_done_w,
  output logic [OUTPUT_PACKET_COUNT_BITS - 1:0] m_axis_count,
  output logic [AXI_DATA_BITS - 1:0] m_axis_data,
  output logic       m_axis_last,
  input logic       m_axis_ready,
  output logic       m_axis_valid,
  input logic signed [7:0] norm_cnt_w,
  input logic [63:0] norm_low_w,
  input logic [15:0] norm_push1_w,
  input logic [1:0] norm_push_count_w,
  input logic [31:0] norm_rng_w,
  input logic        op_last_w,
  input logic        op_valid_w,
  input logic output_after_current_payload_w,
  input logic [11:0] output_after_current_payload_word_addr_w,
  input logic output_after_next_payload_w,
  input logic [11:0] output_after_next_payload_word_addr_w,
  output logic [3:0] output_byte_phase_q,
  input logic output_current_packet_last_w,
  output logic output_last_q,
  input logic [7:0] output_lookup_byte_w,
  input logic output_lookup_last_w,
  input logic [3:0] output_next_byte_phase_w,
  input logic output_next_packet_last_w,
  input logic [OUTPUT_PACKET_COUNT_BITS - 1:0] output_next_payload_count_w,
  input logic [127:0] output_next_payload_packet_data_w,
  input logic [11:0] output_next_payload_word_addr_w,
  input logic [15:0] output_next_stream_index_w,
  input logic [OUTPUT_PACKET_COUNT_BITS - 1:0] output_payload_count_w,
  input logic [127:0] output_payload_packet_data_w,
  input logic palette_analyzer_done_w,
  input logic palette_analyzer_unsupported_w,
  input logic palette_chroma_bdpcm_horz_w,
  output logic [5:0] palette_col_q,
  input logic palette_header_last_step_w,
  output logic [1:0] palette_identity_row_ctx_q,
  input logic [1:0] palette_identity_row_flag_w,
  input logic [1:0] palette_luma_mode_w,
  input logic palette_map_token_required_w,
  output logic palette_mode_q,
  input logic palette_query_done_w,
  output logic [5:0] palette_row_q,
  input logic partition_emit_do_split_w,
  output logic partition_emit_step_q,
  input logic partition_need_rect_w,
  output logic [1:0] partition_q,
  output logic [15:0] payload_len_q,
  output logic [1:0] payload_prefix_index_q,
  input logic [11:0] payload_read_data_word_addr_q,
  output logic [11:0] payload_read_word_addr_q,
  output logic pending_push_valid_q,
  output logic [15:0] pending_push_word_q,
  output logic [2:0] phase_q,
  output logic [15:0] precarry_len_q,
  output logic [11:0] precarry_read_word_addr_q,
  input logic residual_mode_w,
  output logic [31:0] rng_q,
  output logic [15:0] seq_bit_pos_q,
  output logic [6:0] seq_bits_left_q,
  output logic [15:0] seq_len_q,
  input logic [6:0] seq_load_bits_w,
  input logic [63:0] seq_load_value_w,
  output logic [AV2_MAX_SEQUENCE_BYTES - 1:0][7:0] seq_mem_q,
  output logic [7:0] seq_op_q,
  output logic [63:0] seq_value_q,
  input logic [3:0] seq_write_step_w,
  input logic [31:0] src_frame_stride,
  output logic [AV2_STACK_DEPTH - 1:0][4:0] stack_col_mi_q,
  output logic [AV2_STACK_DEPTH - 1:0][4:0] stack_h_mi_q,
  output logic [AV2_STACK_DEPTH - 1:0][4:0] stack_row_mi_q,
  output logic [4:0] stack_sp_q,
  output logic [AV2_STACK_DEPTH - 1:0][4:0] stack_w_mi_q,
  input logic       start,
  input logic start_invalid_w,
  output logic [6:0] step_q,
  output logic [15:0] stream_index_q,
  output logic [15:0] tile_col_q,
  output logic [15:0] tile_cols_q,
  input logic [15:0] tile_cols_w,
  output logic [15:0] tile_count_q,
  input logic [15:0] tile_count_w,
  input logic tile_entropy_ibc_mode_w,
  input logic tile_entropy_lossy420_mode_w,
  input logic tile_entropy_palette_mode_w,
  input logic tile_entropy_start_ready_w,
  output logic [15:0] tile_height_q,
  output logic [15:0] tile_index_q,
  output logic tile_input_active_q,
  output logic [31:0] tile_input_index_q,
  input logic tile_is_last_w,
  output logic [15:0] tile_len_q,
  input logic [15:0] tile_payload_start_w,
  output logic [15:0] tile_row_q,
  output logic [15:0] tile_rows_q,
  input logic [15:0] tile_rows_w,
  output logic [15:0] tile_width_q,
  input logic [15:0] txb_col_w,
  output logic [15:0] txb_count_q,
  input logic [15:0] txb_count_w,
  output logic [15:0] txb_index_q,
  output logic [4:0] txb_local_col_q,
  output logic [4:0] txb_local_row_q,
  output logic txb_prefetch_chroma_q,
  input logic txb_prefetch_chroma_start_w,
  input logic txb_prefetch_cross_phase_w,
  output logic txb_prefetch_done_q,
  input logic txb_prefetch_fetch_done_w,
  input logic txb_prefetch_first_luma_w,
  output logic [1:0] txb_prefetch_index_q,
  input logic txb_prefetch_luma_start_w,
  output logic txb_prefetch_plane_v_q,
  output logic txb_prefetch_started_q,
  output logic [15:0] txb_width_q,
  input logic [15:0] txb_width_w,
  output logic [4:0] visible_cols_mi_q,
  input logic [4:0] visible_cols_mi_w,
  input logic [15:0] visible_height,
  output logic [4:0] visible_rows_mi_q,
  input logic [4:0] visible_rows_mi_w,
  input logic [15:0] visible_width,
  output logic [4:0] width_bits_q,
  input logic [4:0] width_bits_w,
  output logic [15:0] width_q
);


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

  localparam logic [4:0] ST_IDLE = 5'd0;
  localparam logic [4:0] ST_TILE_START = 5'd1;
  localparam logic [4:0] ST_INPUT_READ = 5'd2;
  localparam logic [4:0] ST_SEQ_LOAD = 5'd3;
  localparam logic [4:0] ST_SEQ_WRITE = 5'd4;
  localparam logic [4:0] ST_LOAD_BLOCK = 5'd5;
  localparam logic [4:0] ST_PARTITION = 5'd6;
  localparam logic [4:0] ST_LEAF_WAIT = 5'd7;
  localparam logic [4:0] ST_PALETTE_QUERY = 5'd8;
  localparam logic [4:0] ST_LEAF = 5'd9;
  localparam logic [4:0] ST_FINISH_INIT = 5'd10;
  localparam logic [4:0] ST_FINISH_PUSH = 5'd11;
  localparam logic [4:0] ST_CHROMA_FETCH = 5'd12;
  localparam logic [4:0] ST_CARRY_READ = 5'd13;
  localparam logic [4:0] ST_CARRY_WRITE = 5'd14;
  localparam logic [4:0] ST_PAYLOAD_PREFIX = 5'd15;
  localparam logic [4:0] ST_OUTPUT_PREP = 5'd16;
  localparam logic [4:0] ST_OUTPUT_VALID = 5'd17;
  localparam logic [4:0] ST_OUTPUT_PAYLOAD_WAIT = 5'd18;
  localparam logic [4:0] ST_OUTPUT_PAYLOAD_LOAD = 5'd19;
  localparam int SEQ_MEM_ADDR_BITS = (AV2_MAX_SEQUENCE_BYTES > 1) ? $clog2(AV2_MAX_SEQUENCE_BYTES) : 1;

  integer context_index_q;
  integer seq_write_i;
  integer seq_mem_pack_i;
  logic [7:0] seq_mem_u [0:AV2_MAX_SEQUENCE_BYTES - 1];
  logic [SEQ_MEM_ADDR_BITS - 1:0] seq_mem_addr_q;

  always_comb begin
    for (seq_mem_pack_i = 0; seq_mem_pack_i < AV2_MAX_SEQUENCE_BYTES; seq_mem_pack_i = seq_mem_pack_i + 1) begin
      seq_mem_q[seq_mem_pack_i] = seq_mem_u[seq_mem_pack_i];
    end
  end

  // Sequence buffer stores one byte every 8 bits. Convert from bit position to
  // byte address using bits [3:].
  assign seq_mem_addr_q = seq_bit_pos_q[SEQ_MEM_ADDR_BITS + 2:3];

`include "ff_av2_encoder_control_logic.sv"

endmodule
