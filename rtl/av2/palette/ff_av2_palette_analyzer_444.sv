`timescale 1ns/1ps

module ff_av2_palette_analyzer_444 #(
  parameter int SAMPLE_BITS = 8,
  parameter int SUPPORT_PALETTE_444 = 1
) (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       start,
  input  logic       sample_fire,
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,
  input  logic [1:0]  chroma_format_idc,
  input  logic [63:0] ibc_copy_mask,
  input  logic [SAMPLE_BITS - 1:0] sample,
  input  logic       sample_last,
  input  logic       packet_fire,
  input  logic [8*SAMPLE_BITS - 1:0] packet_samples,
  input  logic [3:0] packet_count,
  input  logic       packet_last,
  output logic       sample_ready,
  input  logic [4:0] query_block_row_mi,
  input  logic [4:0] query_block_col_mi,
  input  logic [5:0] query_row,
  input  logic [5:0] query_col,
  input  logic       query_start,
  input  logic       chroma_fetch_start,
  input  logic       chroma_fetch_plane_v,
  input  logic       chroma_fetch_horz,
  input  logic       chroma_fetch_predictor_only,
  input  logic [4:0] chroma_fetch_txb_row_mi,
  input  logic [4:0] chroma_fetch_txb_col_mi,
  input  logic       luma_fetch_start,
  input  logic [4:0] luma_fetch_txb_row_mi,
  input  logic [4:0] luma_fetch_txb_col_mi,
  input  logic [4:0] lossy420_direct_luma_txb_row_mi,
  input  logic [4:0] lossy420_direct_luma_txb_col_mi,
  input  logic [4:0] lossy420_direct_chroma_txb_row_mi,
  input  logic [4:0] lossy420_direct_chroma_txb_col_mi,
  input  logic       lossy420_direct_chroma_plane_v,
  output logic       done,
  output logic       unsupported,
  output logic       black_mode,
  output logic       luma_palette_mode,
  output logic       query_done,
  output logic [3:0] palette_size,
  output logic [4:0] palette_cache_size,
  output logic [63:0] palette_colors,
  output logic [1:0] query_luma_mode,
  output logic [2:0] query_index,
  output logic [2:0] query_left_index,
  output logic [2:0] query_top_index,
  output logic [2:0] query_top_left_index,
  output logic       query_luma_residual_zero,
  output logic       query_chroma_bdpcm_horz,
  output logic [7:0] palette_first_color,
  output logic [1:0] palette_delta_bits_minus5,
  output logic [55:0] palette_delta_minus1,
  output logic [34:0] palette_delta_literal_bits,
  output logic [1:0] query_identity_row_flag,
  output logic       chroma_fetch_done,
  output logic [127:0] chroma_fetch_txb_samples,
  output logic [31:0] chroma_fetch_predictor_samples,
  output logic [127:0] chroma_fetch_u_txb_samples,
  output logic [31:0] chroma_fetch_u_predictor_samples,
  output logic [127:0] chroma_fetch_v_txb_samples,
  output logic [31:0] chroma_fetch_v_predictor_samples,
  output logic       luma_fetch_done,
  output logic [127:0] luma_fetch_txb_samples,
  output logic [127:0] luma_fetch_u_txb_samples,
  output logic [127:0] luma_fetch_v_txb_samples,
  output logic [127:0] luma_fetch_predictor_samples,
  output logic [11:0]  luma_fetch_sample_sum,
  output logic [11:0]  chroma_fetch_sample_sum,
  output logic [11:0]  lossy420_luma_sample_sum_now,
  output logic [11:0]  lossy420_chroma_sample_sum_now
);

  localparam logic [3:0] ST_IDLE = 4'd0;
  localparam logic [3:0] ST_READ = 4'd1;
  localparam logic [3:0] ST_BLOCK_INIT = 4'd2;
  localparam logic [3:0] ST_PAD = 4'd4;
  localparam logic [3:0] ST_SORT = 4'd5;
  localparam logic [3:0] ST_STORE_COLORS = 4'd6;
  localparam logic [3:0] ST_MAP = 4'd7;
  localparam logic [3:0] ST_NEXT_BLOCK = 4'd8;
  localparam logic [3:0] ST_DRAIN_CHROMA = 4'd9;
  localparam logic [3:0] ST_DONE = 4'd10;
  localparam logic [1:0] LUMA_MODE_DC = 2'd0;
  localparam logic [1:0] LUMA_MODE_V = 2'd1;
  localparam logic [1:0] LUMA_MODE_H = 2'd2;
  localparam logic [15:0] LUMA_MODE_SWITCH_SAD_MARGIN = 16'd64;

  logic [3:0] state_q;
  logic [2:0] last_block_col_q;
  logic [2:0] last_block_row_q;
  logic [5:0] block_id_q;
  logic [5:0] block_sample_q;
  logic [6:0] block_chroma_sample_q;
  logic [7:0] candidate_q;
  logic [3:0] collected_count_q;
  logic [3:0] collected_next_count_w;
  logic [3:0] target_palette_size_q;
  logic [3:0] sort_pass_q;
  logic chroma_complete_q;
  logic black_ok_q;
  logic palette_supported_q;

  logic [7:0] block_luma_sample_q [0:63];
  logic [11:0] lossy420_y_sum_q [0:255];
  logic [11:0] lossy420_u_sum_q [0:63];
  logic [11:0] lossy420_v_sum_q [0:63];
  logic [191:0] current_palette_index_q;
  logic [1:0] block_luma_mode_q [0:63];
  logic [63:0] terminal_luma_predictor_edge_q;
  logic [63:0] terminal_luma_predictor_inner_edge_q;
  logic block_luma_residual_zero_q [0:63];
  logic [7:0] palette_color_q [0:7];
  logic [63:0] block_palette_colors_q [0:63];
  logic [3:0] block_palette_size_q [0:63];
  logic [63:0] left_predictor_edge_q;
  logic [63:0] above_predictor_edge_q [0:7];
  logic [15:0] palette_sad_q;
  logic [15:0] vertical_sad_q;
  logic [15:0] horizontal_sad_q;
  logic [7:0] current_row_same_left_q;
  logic [7:0] current_row_same_above_q;
  logic [7:0] row_same_left_q [0:63];
  logic [7:0] row_same_above_q [0:63];
  logic block_chroma_bdpcm_horz_q [0:63];
  logic query_chroma_bdpcm_horz_q;
  logic [15:0] chroma_h_sad_q;
  logic [15:0] chroma_v_sad_q;
  logic [63:0] chroma_prev_row_q;
  logic [63:0] chroma_left_u_edge_q;
  logic [63:0] chroma_left_v_edge_q;
  logic [63:0] chroma_above_u_edge_q [0:7];
  logic [63:0] chroma_above_v_edge_q [0:7];
  logic [63:0] chroma_current_u_right_edge_q;
  logic [63:0] chroma_current_v_right_edge_q;
  logic [7:0] chroma_bottom_h_u_predictor_q;
  logic [7:0] chroma_bottom_h_v_predictor_q;
  logic [63:0] packet_chroma_left_edge_w;
  logic [63:0] packet_chroma_above_edge_w;
  logic [63:0] packet_chroma_right_edge_w;
  logic [63:0] packet_chroma_next_right_edge_w;
  logic [15:0] packet_chroma_h_sad_w;
  logic [15:0] packet_chroma_v_sad_w;
  logic [2:0] query_palette_index_q [0:63];
  logic [1:0] query_luma_mode_q;
  logic [63:0] query_luma_predictor_edge_q;
  logic [63:0] query_luma_predictor_inner_edge_q;
  logic [63:0] query_palette_colors_q;
  logic [3:0] query_palette_size_q;
  logic [4:0] query_palette_cache_size_q;
  logic [7:0] query_palette_first_color_q;
  logic [1:0] query_palette_delta_bits_minus5_q;
  logic [55:0] query_palette_delta_minus1_q;
  logic [34:0] query_palette_delta_literal_bits_q;
  logic query_luma_residual_zero_q;
  logic [7:0] query_row_same_left_q;
  logic [7:0] query_row_same_above_q;

  logic known_sample_w;
  logic candidate_known_w;
  logic collect_add_w;
  logic [2:0] nearest_index_w;
  logic [7:0] nearest_delta_w;
  logic [7:0] nearest_color_w;
  logic [7:0] collect_sample_w;
  logic [7:0] map_sample_w;
  logic [7:0] map_abs_delta_w;
  logic [7:0] vertical_predictor_sample_w;
  logic [7:0] horizontal_predictor_sample_w;
  logic [7:0] vertical_abs_delta_w;
  logic [7:0] horizontal_abs_delta_w;
  logic [7:0] map_row_bit_offset_w;
  logic [7:0] map_sample_lane_w [0:7];
  logic [7:0] map_nearest_color_w [0:7];
  logic [7:0] map_palette_abs_delta_w [0:7];
  logic [7:0] map_vertical_predictor_sample_w [0:7];
  logic [7:0] map_horizontal_predictor_sample_w [0:7];
  logic [2:0] map_nearest_index_w [0:7];
  logic [7:0] map_nearest_delta_w [0:7];
  logic [7:0] map_vertical_abs_delta_w [0:7];
  logic [7:0] map_horizontal_abs_delta_w [0:7];
  logic [11:0] map_palette_sad_sum_w;
  logic [11:0] map_vertical_sad_sum_w;
  logic [11:0] map_horizontal_sad_sum_w;
  logic [23:0] map_row_indices_pack_w;
  logic map_row_same_left_w;
  logic map_row_same_above_w;
  logic [7:0] sample_u8_w;
  logic black_sample_ok_w;
  logic black_next_w;
  logic [5:0] query_block_id_w;
  logic [5:0] query_local_index_w;
  logic [5:0] query_left_local_index_w;
  logic [5:0] query_top_local_index_w;
  logic [5:0] query_top_left_local_index_w;
  logic [7:0] block_sample_bit_offset_w;
  logic [7:0] block_sample_left_bit_offset_w;
  logic [7:0] block_sample_top_bit_offset_w;
  logic [5:0] block_sample_row_bit_offset_w;
  logic [5:0] block_sample_col_bit_offset_w;
  logic fetch_active_q;
  logic fetch_start_q;
  logic fetch_horz_q;
  logic query_start_q;
  logic query_active_q;
  logic [5:0] query_load_block_id_q;
  logic luma_fetch_start_q;
  logic luma_fetch_active_q;
  logic fetch_plane_v_q;
  logic [4:0] fetch_txb_row_mi_q;
  logic [4:0] fetch_txb_col_mi_q;
  logic [4:0] luma_fetch_txb_row_mi_q;
  logic [4:0] luma_fetch_txb_col_mi_q;
  logic [4:0] fetch_step_q;
  logic [4:0] luma_fetch_step_q;
  logic fetch_read_pending_q;
  logic fetch_read_is_pred_q;
  logic [4:0] fetch_capture_step_q;
  logic luma_fetch_read_pending_q;
  logic [4:0] luma_fetch_capture_step_q;
  logic [11:0] fetch_read_addr_q;
  logic [11:0] sample_store_read_addr_w;
  logic [11:0] chroma_read_addr_w;
  logic [5:0] palette_index_read_addr_w;
  logic [191:0] palette_index_read_data_w;
  logic [7:0] luma_read_y_w;
  logic [7:0] chroma_read_u_w;
  logic [7:0] chroma_read_v_w;
  logic [63:0] sample_store_y_row_w;
  logic [63:0] sample_store_u_row_w;
  logic [63:0] sample_store_v_row_w;
  logic [11:0] fetch_txb_read_addr_w;
  logic [11:0] fetch_pred_read_addr_w;
  logic [11:0] luma_fetch_read_addr_w;
  logic [5:0] fetch_txb_block_id_w;
  logic [5:0] fetch_txb_local_base_w;
  logic [5:0] fetch_txb_local_index_w;
  logic [5:0] fetch_chroma_txb_local_index_w;
  logic [5:0] luma_fetch_txb_block_id_w;
  logic [5:0] luma_fetch_txb_local_base_w;
  logic [5:0] luma_fetch_local_index_w;
  logic [5:0] luma_fetch_capture_local_index_w;
  logic [5:0] luma_fetch_capture_row_bit_offset_w;
  logic [5:0] luma_fetch_capture_col_bit_offset_w;
  logic [2:0] luma_fetch_capture_palette_index_w;
  logic [7:0] luma_fetch_predictor_sample_w;
  logic [31:0] luma_fetch_y_row_slice_w;
  logic [31:0] luma_fetch_u_row_slice_w;
  logic [31:0] luma_fetch_v_row_slice_w;
  logic [31:0] luma_fetch_predictor_row_slice_w;
  logic [5:0] luma_fetch_row_local_index_w;
  logic [2:0] luma_fetch_row_col_w;
  logic [2:0] luma_fetch_row_row_w;
  logic [2:0] luma_fetch_row_palette_index_w;
  logic [7:0] luma_fetch_row_predictor_sample_w;
  logic [1:0] selected_luma_mode_w;
  logic [15:0] selected_luma_sad_w;
  logic [63:0] selected_luma_predictor_edge_w;
  logic [63:0] selected_luma_predictor_inner_edge_w;
  logic [63:0] vertical_inner_predictor_edge_w;
  logic [63:0] horizontal_inner_predictor_edge_w;
  logic [63:0] palette_colors_pack_w;
  logic [63:0] query_load_palette_colors_w;
  logic [3:0] query_load_palette_size_w;
  logic [7:0] query_load_color_w [0:7];
  logic [7:0] query_load_delta_w [0:6];
  logic [7:0] query_load_max_delta_w;
  logic [4:0] query_load_base_delta_bits_w;
  logic [4:0] query_load_delta_limit_w;
  logic [4:0] query_load_delta_bits_w [0:6];
  logic [8:0] query_load_delta_range_w;
  logic [4:0] query_palette_cache_size_w;
  logic fixed_mode_ctx0_w;
  logic above_mode_dc_or_unavailable_w;
  logic left_mode_dc_or_unavailable_w;
  logic terminal_tile_leaf_w;
  logic [5:0] next_block_id_w;
  logic chroma_drain_state_w;
  logic chroma_sample_fire_w;
  logic lossy420_mode_w;
  logic packet_luma_fire_w;
  logic packet_chroma_fire_w;
  logic packet_black_ok_w;
  logic [7:0] packet_lane_w [0:7];
  logic [7:0] packet_palette_color_next_w [0:7];
  logic [3:0] packet_collected_next_count_w;
  logic packet_insert_known_w;
  logic [11:0] packet_luma_left_sum_w;
  logic [11:0] packet_luma_right_sum_w;
  logic [11:0] packet_chroma_sum_w;
  logic [5:0] packet_luma_last_sample_w;
  logic [6:0] packet_chroma_last_sample_w;
  logic packet_luma_done_w;
  logic packet_chroma_done_w;
  logic packet_chroma_plane_v_w;
  logic packet_luma_input_error_w;
  logic packet_chroma_input_error_w;
  logic packet_chroma_u_plane_done_w;
  logic [2:0] packet_chroma_row_w;
  logic [5:0] packet_chroma_row_bit_offset_w;
  logic [7:0] packet_chroma_h_predictor_w [0:7];
  logic [7:0] packet_chroma_v_predictor_w [0:7];
  logic [7:0] lossy420_y_sum_left_index_w;
  logic [7:0] lossy420_y_sum_right_index_w;
  logic [7:0] lossy420_y_sum_clear0_index_w;
  logic [7:0] lossy420_y_sum_clear1_index_w;
  logic [7:0] lossy420_y_sum_clear2_index_w;
  logic [7:0] lossy420_y_sum_clear3_index_w;
  logic [7:0] lossy420_next_y_sum_clear0_index_w;
  logic [7:0] lossy420_next_y_sum_clear1_index_w;
  logic [7:0] lossy420_next_y_sum_clear2_index_w;
  logic [7:0] lossy420_next_y_sum_clear3_index_w;
  logic [7:0] lossy420_luma_fetch_sum_index_w;
  logic [5:0] lossy420_chroma_fetch_sum_index_w;
  logic sample_store_row_write_y_w;
  logic sample_store_row_write_u_w;
  logic sample_store_row_write_v_w;
  logic [8:0] sample_store_row_write_addr_w;
  logic chroma_sample_done_w;
  logic chroma_input_error_w;
  logic [6:0] block_chroma_sample_last_w;
  logic [6:0] block_chroma_plane_samples_w;
  logic [5:0] block_chroma_local_sample_w;
  logic block_chroma_plane_v_w;
  logic final_black_w;
  logic [5:0] fetch_pred_block_id_w;
  logic [5:0] fetch_pred_local_index_w;
  logic [5:0] fetch_pred_x_w;
  logic [5:0] fetch_pred_y_w;
  logic [5:0] fetch_above_pred_y_w;
  integer color_index_q;
  integer pack_index_q;
  integer edge_index_q;
  integer inner_index_q;
  integer delta_index_q;
  integer packet_lane_q;
  integer packet_insert_lane_q;
  integer packet_insert_index_q;
  integer map_lane_q;
  integer map_color_index_q;
  integer luma_fetch_lane_q;

  assign sample_u8_w = sample[7:0];
  assign black_sample_ok_w = (sample == {SAMPLE_BITS{1'b0}});
  assign lossy420_mode_w = (chroma_format_idc == 2'd1);
  always @* begin
    packet_black_ok_w = 1'b1;
    for (packet_lane_q = 0; packet_lane_q < 8; packet_lane_q = packet_lane_q + 1) begin
      packet_lane_w[packet_lane_q] = packet_samples[packet_lane_q * SAMPLE_BITS +: 8];
      if (packet_lane_q < packet_count &&
          packet_samples[packet_lane_q * SAMPLE_BITS +: SAMPLE_BITS] != {SAMPLE_BITS{1'b0}}) begin
        packet_black_ok_w = 1'b0;
      end
    end
  end
  assign black_next_w =
    black_ok_q &&
    ((packet_luma_fire_w || packet_chroma_fire_w) ? packet_black_ok_w : black_sample_ok_w);
  assign chroma_drain_state_w =
    (state_q == ST_PAD) ||
    (state_q == ST_SORT) ||
    (state_q == ST_STORE_COLORS) ||
    (state_q == ST_MAP) ||
    (state_q == ST_NEXT_BLOCK) ||
    (state_q == ST_DRAIN_CHROMA);
  assign sample_ready =
    lossy420_mode_w ?
      ((state_q == ST_READ) || ((state_q == ST_DRAIN_CHROMA) && !chroma_complete_q)) :
      ((state_q == ST_READ) || (chroma_drain_state_w && !chroma_complete_q));

  // Palette analysis is block-local. The top-level input contract presents each
  // 8x8 block as 64 Y samples followed by the matching U and V samples: 16+16
  // samples for 4:2:0, 64+64 samples for 4:4:4. AV2 v1.0.0 Sections 5.20.8.1
  // and 5.20.8.4 signal palette syntax only for luma; chroma is still consumed
  // in the same packet so the external interface matches VVC's 8x8 leaf stream
  // contract without a frame buffer.
  // AV2 8x8 palette leaves are addressed by 3-bit block row/column indices
  // inside the 64x64 superblock. The MI origin is in 4x4 units, so [3:1]
  // converts it to 8x8 block coordinates without truncating high row bits.
  assign query_block_id_w = {query_block_row_mi[3:1], query_block_col_mi[3:1]};
  assign query_local_index_w = {query_row[2:0], query_col[2:0]};
  assign query_left_local_index_w =
    (query_col[2:0] == 3'd0) ? query_local_index_w : (query_local_index_w - 6'd1);
  assign query_top_local_index_w =
    (query_row[2:0] == 3'd0) ? query_local_index_w : (query_local_index_w - 6'd8);
  assign query_top_left_local_index_w =
    (query_row[2:0] == 3'd0 || query_col[2:0] == 3'd0) ?
      query_local_index_w : (query_local_index_w - 6'd9);
  assign block_sample_bit_offset_w = {2'd0, block_sample_q} * 8'd3;
  assign block_sample_left_bit_offset_w = {2'd0, block_sample_q - 6'd1} * 8'd3;
  assign block_sample_top_bit_offset_w = {2'd0, block_sample_q - 6'd8} * 8'd3;
  assign block_sample_row_bit_offset_w = {block_sample_q[5:3], 3'b000};
  assign block_sample_col_bit_offset_w = {block_sample_q[2:0], 3'b000};
  assign above_mode_dc_or_unavailable_w =
    (block_id_q[5:3] == 3'd0) || (block_luma_mode_q[block_id_q - 6'd8] == LUMA_MODE_DC);
  assign left_mode_dc_or_unavailable_w =
    (block_id_q[2:0] == 3'd0) || (block_luma_mode_q[block_id_q - 6'd1] == LUMA_MODE_DC);
  assign fixed_mode_ctx0_w = above_mode_dc_or_unavailable_w && left_mode_dc_or_unavailable_w;
  assign terminal_tile_leaf_w =
    (block_id_q[5:3] == last_block_row_q) && (block_id_q[2:0] == last_block_col_q);
  assign next_block_id_w =
    (block_id_q[2:0] == last_block_col_q) ?
      {block_id_q[5:3] + 3'd1, 3'd0} :
      (block_id_q + 6'd1);
  assign chroma_sample_fire_w =
    !lossy420_mode_w && sample_fire && chroma_drain_state_w && !chroma_complete_q;
  assign packet_luma_fire_w =
    packet_fire && (state_q == ST_READ);
  assign packet_chroma_fire_w =
    packet_fire &&
    (lossy420_mode_w ? (state_q == ST_DRAIN_CHROMA) : chroma_drain_state_w) &&
    !chroma_complete_q;
  assign block_chroma_sample_last_w =
    (chroma_format_idc == 2'd1) ? 7'd31 : 7'd127;
  assign block_chroma_plane_samples_w =
    (chroma_format_idc == 2'd1) ? 7'd16 : 7'd64;
  assign block_chroma_plane_v_w =
    block_chroma_sample_q >= block_chroma_plane_samples_w;
  assign block_chroma_local_sample_w =
    (chroma_format_idc == 2'd1) ?
      {2'd0, block_chroma_sample_q[3:0]} :
      block_chroma_sample_q[5:0];
  assign chroma_sample_done_w =
    chroma_sample_fire_w && (block_chroma_sample_q == block_chroma_sample_last_w);
  assign chroma_input_error_w =
    chroma_sample_fire_w &&
    (sample_last !=
      (terminal_tile_leaf_w && (block_chroma_sample_q == block_chroma_sample_last_w)));
  assign final_black_w = chroma_sample_done_w ? black_next_w : black_ok_q;
  assign palette_colors_pack_w = {
    palette_color_q[7],
    palette_color_q[6],
    palette_color_q[5],
    palette_color_q[4],
    palette_color_q[3],
    palette_color_q[2],
    palette_color_q[1],
    palette_color_q[0]
  };
  assign query_load_palette_colors_w = block_palette_colors_q[query_load_block_id_q];
  assign query_load_palette_size_w = block_palette_size_q[query_load_block_id_q];
  // AV2 v1.0.0 Section 5.20.7 residual syntax scans 4x4 TXBs. The query
  // coordinates are MI units, so bit 0 selects the bottom/right 4x4 quadrant
  // inside the current 8x8 packet: row offset 4*8 samples, column offset 4.
  assign fetch_txb_block_id_w = {fetch_txb_row_mi_q[3:1], fetch_txb_col_mi_q[3:1]};
  assign fetch_txb_local_base_w =
    {fetch_txb_row_mi_q[0], 5'b00000} + {3'd0, fetch_txb_col_mi_q[0], 2'b00};
  assign fetch_txb_local_index_w =
    fetch_txb_local_base_w + {fetch_step_q[3:2], 3'b000} + {4'd0, fetch_step_q[1:0]};
  // 4:4:4 chroma samples share the luma 8x8 packet layout, but 4:2:0 chroma
  // packets are compact 4x4 TXBs. AV2 v1.0.0 residual syntax still scans a
  // TX_4X4, so subsampled fetches must use a 4-sample row stride.
  assign fetch_chroma_txb_local_index_w =
    (chroma_format_idc == 2'd1) ?
      {2'd0, fetch_step_q[3:0]} :
      fetch_txb_local_index_w;
  assign fetch_above_pred_y_w = {fetch_txb_row_mi_q, 2'b00} - 6'd1;
  assign luma_fetch_txb_block_id_w = {luma_fetch_txb_row_mi_q[3:1], luma_fetch_txb_col_mi_q[3:1]};
  assign luma_fetch_txb_local_base_w =
    {luma_fetch_txb_row_mi_q[0], 5'b00000} + {3'd0, luma_fetch_txb_col_mi_q[0], 2'b00};
  assign chroma_read_addr_w =
    (fetch_step_q < 5'd16) ? fetch_txb_read_addr_w : fetch_pred_read_addr_w;
  assign luma_fetch_local_index_w =
    luma_fetch_txb_local_base_w +
    {luma_fetch_step_q[1:0], 3'b000};
  assign luma_fetch_capture_local_index_w =
    luma_fetch_txb_local_base_w +
    {luma_fetch_capture_step_q[3:2], 3'b000} +
    {4'd0, luma_fetch_capture_step_q[1:0]};
  assign luma_fetch_capture_row_bit_offset_w = {luma_fetch_capture_local_index_w[5:3], 3'b000};
  assign luma_fetch_capture_col_bit_offset_w = {luma_fetch_capture_local_index_w[2:0], 3'b000};
  assign luma_fetch_capture_palette_index_w =
    query_palette_index_q[luma_fetch_capture_local_index_w];
  assign luma_fetch_read_addr_w = {luma_fetch_txb_block_id_w, luma_fetch_local_index_w};
  assign sample_store_read_addr_w = luma_fetch_active_q ? luma_fetch_read_addr_w : chroma_read_addr_w;
  assign palette_index_read_addr_w =
    (query_start && !query_start_q) ? query_block_id_w : query_load_block_id_q;
  assign fetch_txb_read_addr_w = {fetch_txb_block_id_w, fetch_chroma_txb_local_index_w};
  assign fetch_pred_read_addr_w = {fetch_pred_block_id_w, fetch_pred_local_index_w};
  assign packet_luma_last_sample_w =
    block_sample_q + {2'd0, packet_count} - 6'd1;
  assign packet_chroma_last_sample_w =
    block_chroma_sample_q + {3'd0, packet_count} - 7'd1;
  assign packet_luma_done_w =
    packet_luma_fire_w && (packet_luma_last_sample_w >= 6'd63);
  assign packet_chroma_done_w =
    packet_chroma_fire_w && (packet_chroma_last_sample_w >= block_chroma_sample_last_w);
  assign packet_chroma_u_plane_done_w =
    packet_chroma_fire_w && !packet_chroma_plane_v_w && (packet_chroma_last_sample_w >= 7'd63);
  assign packet_chroma_plane_v_w =
    block_chroma_sample_q >= block_chroma_plane_samples_w;
  assign packet_chroma_row_w = block_chroma_local_sample_w[5:3];
  assign packet_chroma_row_bit_offset_w = {packet_chroma_row_w, 3'b000};
  assign packet_luma_input_error_w =
    packet_luma_fire_w && packet_last;
  assign packet_chroma_input_error_w =
    packet_chroma_fire_w &&
    (packet_last != (terminal_tile_leaf_w && packet_chroma_done_w));
  assign lossy420_y_sum_left_index_w = {
    block_id_q[5:3],
    block_sample_q[5],
    block_id_q[2:0],
    1'b0
  };
  assign lossy420_y_sum_right_index_w = {
    block_id_q[5:3],
    block_sample_q[5],
    block_id_q[2:0],
    1'b1
  };
  assign lossy420_y_sum_clear0_index_w = {block_id_q[5:3], 1'b0, block_id_q[2:0], 1'b0};
  assign lossy420_y_sum_clear1_index_w = {block_id_q[5:3], 1'b0, block_id_q[2:0], 1'b1};
  assign lossy420_y_sum_clear2_index_w = {block_id_q[5:3], 1'b1, block_id_q[2:0], 1'b0};
  assign lossy420_y_sum_clear3_index_w = {block_id_q[5:3], 1'b1, block_id_q[2:0], 1'b1};
  assign lossy420_next_y_sum_clear0_index_w =
    {next_block_id_w[5:3], 1'b0, next_block_id_w[2:0], 1'b0};
  assign lossy420_next_y_sum_clear1_index_w =
    {next_block_id_w[5:3], 1'b0, next_block_id_w[2:0], 1'b1};
  assign lossy420_next_y_sum_clear2_index_w =
    {next_block_id_w[5:3], 1'b1, next_block_id_w[2:0], 1'b0};
  assign lossy420_next_y_sum_clear3_index_w =
    {next_block_id_w[5:3], 1'b1, next_block_id_w[2:0], 1'b1};
  assign lossy420_luma_fetch_sum_index_w = {
    luma_fetch_txb_row_mi_q[3:0],
    luma_fetch_txb_col_mi_q[3:0]
  };
  assign lossy420_chroma_fetch_sum_index_w = {
    fetch_txb_row_mi_q[3:1],
    fetch_txb_col_mi_q[3:1]
  };
  assign lossy420_luma_sample_sum_now =
    lossy420_y_sum_q[
      {lossy420_direct_luma_txb_row_mi[3:0], lossy420_direct_luma_txb_col_mi[3:0]}
    ];
  assign lossy420_chroma_sample_sum_now =
    lossy420_direct_chroma_plane_v ?
      lossy420_v_sum_q[
        {lossy420_direct_chroma_txb_row_mi[3:1], lossy420_direct_chroma_txb_col_mi[3:1]}
      ] :
      lossy420_u_sum_q[
        {lossy420_direct_chroma_txb_row_mi[3:1], lossy420_direct_chroma_txb_col_mi[3:1]}
      ];
  assign sample_store_row_write_y_w =
    !lossy420_mode_w && packet_luma_fire_w;
  assign sample_store_row_write_u_w =
    !lossy420_mode_w && packet_chroma_fire_w && !packet_chroma_plane_v_w;
  assign sample_store_row_write_v_w =
    !lossy420_mode_w && packet_chroma_fire_w && packet_chroma_plane_v_w;
  assign sample_store_row_write_addr_w =
    packet_luma_fire_w ?
      {block_id_q, block_sample_q[5:3]} :
      {block_id_q, block_chroma_local_sample_w[5:3]};

  ff_av2_chroma_sample_store chroma_sample_store (
    .clk(clk),
    .row_write_y_en(sample_store_row_write_y_w),
    .row_write_u_en(sample_store_row_write_u_w),
    .row_write_v_en(sample_store_row_write_v_w),
    .row_write_addr(sample_store_row_write_addr_w),
    .row_write_data(packet_samples),
    .read_addr(sample_store_read_addr_w),
    .read_y_data(luma_read_y_w),
    .read_u_data(chroma_read_u_w),
    .read_v_data(chroma_read_v_w),
    .read_y_row_data(sample_store_y_row_w),
    .read_u_row_data(sample_store_u_row_w),
    .read_v_row_data(sample_store_v_row_w)
  );

  // One 192-bit palette-index word per 8x8 leaf. Query setup already has a
  // registered phase, so keep this table in synchronous RAM instead of a
  // 64-entry flip-flop bank.
  ff_sync_block_ram_1r1w #(
    .DATA_BITS(192),
    .ADDR_BITS(6),
    .DEPTH(64)
  ) palette_index_mem (
    .clk(clk),
    .write_valid(state_q == ST_NEXT_BLOCK),
    .write_addr(block_id_q),
    .write_data(current_palette_index_q),
    .read_addr(palette_index_read_addr_w),
    .read_data(palette_index_read_data_w)
  );

  always @* begin
    packet_chroma_left_edge_w =
      packet_chroma_plane_v_w ? chroma_left_v_edge_q : chroma_left_u_edge_q;
    packet_chroma_above_edge_w =
      packet_chroma_plane_v_w ?
        chroma_above_v_edge_q[block_id_q[2:0]] :
        chroma_above_u_edge_q[block_id_q[2:0]];
    packet_chroma_right_edge_w =
      packet_chroma_plane_v_w ? chroma_current_v_right_edge_q : chroma_current_u_right_edge_q;
    packet_chroma_next_right_edge_w = packet_chroma_right_edge_w;
    packet_chroma_next_right_edge_w[packet_chroma_row_bit_offset_w +: 8] = packet_lane_w[7];
    packet_luma_left_sum_w = 12'd0;
    packet_luma_right_sum_w = 12'd0;
    packet_chroma_sum_w = 12'd0;
    packet_chroma_h_sad_w = 16'd0;
    packet_chroma_v_sad_w = 16'd0;
    for (packet_lane_q = 0; packet_lane_q < 8; packet_lane_q = packet_lane_q + 1) begin
      if (packet_lane_q < packet_count) begin
        if (({1'b0, block_sample_q[2:0]} + packet_lane_q[3:0]) < 4'd4) begin
          packet_luma_left_sum_w =
            packet_luma_left_sum_w + {4'd0, packet_lane_w[packet_lane_q]};
        end else begin
          packet_luma_right_sum_w =
            packet_luma_right_sum_w + {4'd0, packet_lane_w[packet_lane_q]};
        end
        packet_chroma_sum_w =
          packet_chroma_sum_w + {4'd0, packet_lane_w[packet_lane_q]};
        // AV2 v1.0.0 Section 7.11 intra prediction plus Section 5.20.7
        // residual coding: score the same boundary predictors that the 4x4
        // chroma BDPCM coefficient path will use. This is still only a cheap
        // SAD estimate, but it avoids choosing an axis from internal edges
        // while ignoring the first row/column of each TXB.
        if (packet_lane_q[1:0] != 2'd0) begin
          packet_chroma_h_predictor_w[packet_lane_q] = packet_lane_w[packet_lane_q - 1];
        end else if (packet_lane_q[2] || (block_id_q[2:0] != 3'd0)) begin
          packet_chroma_h_predictor_w[packet_lane_q] =
            packet_lane_q[2] ?
              packet_lane_w[3] :
              packet_chroma_left_edge_w[packet_chroma_row_bit_offset_w +: 8];
        end else if (packet_chroma_row_w[2] || (block_id_q[5:3] != 3'd0)) begin
          packet_chroma_h_predictor_w[packet_lane_q] =
            packet_chroma_row_w[2] ?
              ((packet_chroma_row_w[1:0] == 2'd0) ?
                chroma_prev_row_q[7:0] :
                (packet_chroma_plane_v_w ?
                  chroma_bottom_h_v_predictor_q :
                  chroma_bottom_h_u_predictor_q)) :
              packet_chroma_above_edge_w[7:0];
        end else begin
          packet_chroma_h_predictor_w[packet_lane_q] = 8'd129;
        end

        if (packet_chroma_row_w[1:0] != 2'd0) begin
          packet_chroma_v_predictor_w[packet_lane_q] = chroma_prev_row_q[packet_lane_q * 8 +: 8];
        end else if (packet_chroma_row_w[2] || (block_id_q[5:3] != 3'd0)) begin
          packet_chroma_v_predictor_w[packet_lane_q] =
            packet_chroma_row_w[2] ?
              chroma_prev_row_q[packet_lane_q * 8 +: 8] :
              packet_chroma_above_edge_w[packet_lane_q * 8 +: 8];
        end else if (packet_lane_q[2] || (block_id_q[2:0] != 3'd0)) begin
          packet_chroma_v_predictor_w[packet_lane_q] =
            packet_lane_q[2] ?
              packet_lane_w[3] :
              packet_chroma_left_edge_w[7:0];
        end else begin
          packet_chroma_v_predictor_w[packet_lane_q] = 8'd127;
        end

        if (packet_lane_w[packet_lane_q] >= packet_chroma_h_predictor_w[packet_lane_q]) begin
          packet_chroma_h_sad_w =
            packet_chroma_h_sad_w +
            {8'd0, packet_lane_w[packet_lane_q] - packet_chroma_h_predictor_w[packet_lane_q]};
        end else begin
          packet_chroma_h_sad_w =
            packet_chroma_h_sad_w +
            {8'd0, packet_chroma_h_predictor_w[packet_lane_q] - packet_lane_w[packet_lane_q]};
        end
        if (packet_lane_w[packet_lane_q] >= packet_chroma_v_predictor_w[packet_lane_q]) begin
          packet_chroma_v_sad_w =
            packet_chroma_v_sad_w +
            {8'd0, packet_lane_w[packet_lane_q] - packet_chroma_v_predictor_w[packet_lane_q]};
        end else begin
          packet_chroma_v_sad_w =
            packet_chroma_v_sad_w +
            {8'd0, packet_chroma_v_predictor_w[packet_lane_q] - packet_lane_w[packet_lane_q]};
        end
      end else begin
        packet_chroma_h_predictor_w[packet_lane_q] = 8'd0;
        packet_chroma_v_predictor_w[packet_lane_q] = 8'd0;
      end
    end
  end

  always @* begin
    for (packet_insert_index_q = 0; packet_insert_index_q < 8; packet_insert_index_q = packet_insert_index_q + 1) begin
      packet_palette_color_next_w[packet_insert_index_q] = palette_color_q[packet_insert_index_q];
    end
    packet_collected_next_count_w = collected_count_q;

    // AV2 v1.0.0 Section 5.11.39 writes palette colors in sorted order, but
    // the collection order is not syntax-visible. Keep packet ingress cheap by
    // appending unique colors here, then use ST_SORT to order the final list
    // before the palette-color symbols are emitted.
    for (packet_insert_lane_q = 0; packet_insert_lane_q < 8; packet_insert_lane_q = packet_insert_lane_q + 1) begin
      packet_insert_known_w = 1'b0;
      for (packet_insert_index_q = 0; packet_insert_index_q < 8; packet_insert_index_q = packet_insert_index_q + 1) begin
        if (packet_insert_index_q < packet_collected_next_count_w &&
            packet_palette_color_next_w[packet_insert_index_q] ==
              packet_lane_w[packet_insert_lane_q]) begin
          packet_insert_known_w = 1'b1;
        end
      end

      if (packet_insert_lane_q < packet_count &&
          !packet_insert_known_w &&
          packet_collected_next_count_w < 4'd8) begin
        packet_palette_color_next_w[packet_collected_next_count_w] =
          packet_lane_w[packet_insert_lane_q];
        packet_collected_next_count_w = packet_collected_next_count_w + 4'd1;
      end
    end
  end

  always @* begin
    if (fetch_horz_q) begin
      if (fetch_txb_col_mi_q != 5'd0) begin
        fetch_pred_x_w = {fetch_txb_col_mi_q, 2'b00} - 6'd1;
        fetch_pred_y_w = {fetch_txb_row_mi_q, 2'b00} + {4'd0, fetch_step_q[1:0]};
      end else if (fetch_txb_row_mi_q != 5'd0) begin
        fetch_pred_x_w = 6'd0;
        fetch_pred_y_w = fetch_above_pred_y_w;
      end else begin
        fetch_pred_x_w = 6'd0;
        fetch_pred_y_w = 6'd0;
      end
    end else if (fetch_txb_row_mi_q != 5'd0) begin
      fetch_pred_x_w = {fetch_txb_col_mi_q, 2'b00} + {4'd0, fetch_step_q[1:0]};
      fetch_pred_y_w = fetch_above_pred_y_w;
    end else if (fetch_txb_col_mi_q != 5'd0) begin
      fetch_pred_x_w = {fetch_txb_col_mi_q, 2'b00} - 6'd1;
      fetch_pred_y_w = {fetch_txb_row_mi_q, 2'b00};
    end else begin
      fetch_pred_x_w = 6'd0;
      fetch_pred_y_w = 6'd0;
    end
    fetch_pred_block_id_w = {fetch_pred_y_w[5:3], fetch_pred_x_w[5:3]};
    fetch_pred_local_index_w = {fetch_pred_y_w[2:0], fetch_pred_x_w[2:0]};
  end

  always @* begin
    known_sample_w = 1'b0;
    candidate_known_w = 1'b0;
    collect_sample_w = (state_q == ST_READ) ? sample_u8_w : block_luma_sample_q[block_sample_q];
    for (color_index_q = 0; color_index_q < 8; color_index_q = color_index_q + 1) begin
      if (color_index_q < collected_count_q && palette_color_q[color_index_q] == collect_sample_w) begin
        known_sample_w = 1'b1;
      end
      if (color_index_q < collected_count_q && palette_color_q[color_index_q] == candidate_q) begin
        candidate_known_w = 1'b1;
      end
    end
    collect_add_w = !known_sample_w && (collected_count_q < 4'd8);
    collected_next_count_w = collected_count_q + {3'd0, collect_add_w};
  end

  always @* begin
    map_sample_w = block_luma_sample_q[block_sample_q];
    nearest_index_w = 3'd0;
    nearest_delta_w = 8'hff;
    nearest_color_w = 8'd0;
    map_abs_delta_w = 8'd0;
    // AV2 v1.0.0 Section 5.11.41 predicts each 4x4 transform block from the
    // already reconstructed edge. For an 8x8 leaf, the bottom/right 4x4 TXBs
    // therefore see the internal row/column reconstructed by the top/left TXB,
    // not the outer 8x8 edge used by the first TXB.
    if (block_sample_q[5:3] >= 3'd4) begin
      vertical_predictor_sample_w =
        block_luma_sample_q[6'd24 + {3'd0, block_sample_q[2:0]}];
    end else begin
      vertical_predictor_sample_w =
        above_predictor_edge_q[block_id_q[2:0]][block_sample_col_bit_offset_w +: 8];
    end
    if (block_sample_q[2:0] >= 3'd4) begin
      horizontal_predictor_sample_w =
        block_luma_sample_q[{block_sample_q[5:3], 3'b000} + 6'd3];
    end else begin
      horizontal_predictor_sample_w =
        left_predictor_edge_q[block_sample_row_bit_offset_w +: 8];
    end
    vertical_abs_delta_w = 8'd0;
    horizontal_abs_delta_w = 8'd0;
    if (map_sample_w >= vertical_predictor_sample_w) begin
      vertical_abs_delta_w = map_sample_w - vertical_predictor_sample_w;
    end else begin
      vertical_abs_delta_w = vertical_predictor_sample_w - map_sample_w;
    end
    if (map_sample_w >= horizontal_predictor_sample_w) begin
      horizontal_abs_delta_w = map_sample_w - horizontal_predictor_sample_w;
    end else begin
      horizontal_abs_delta_w = horizontal_predictor_sample_w - map_sample_w;
    end
    for (color_index_q = 0; color_index_q < 8; color_index_q = color_index_q + 1) begin
      if (color_index_q < target_palette_size_q) begin
        nearest_color_w = palette_color_q[color_index_q];
        if (map_sample_w >= nearest_color_w) begin
          map_abs_delta_w = map_sample_w - nearest_color_w;
        end else begin
          map_abs_delta_w = nearest_color_w - map_sample_w;
        end
        if (map_abs_delta_w < nearest_delta_w) begin
          nearest_delta_w = map_abs_delta_w;
          nearest_index_w = color_index_q[2:0];
        end
      end
    end
  end

  always @* begin
    map_row_bit_offset_w = {5'd0, block_sample_q[5:3]} * 8'd24;
    map_palette_sad_sum_w = 12'd0;
    map_vertical_sad_sum_w = 12'd0;
    map_horizontal_sad_sum_w = 12'd0;
    map_row_indices_pack_w = 24'd0;
    map_row_same_left_w = 1'b1;
    map_row_same_above_w = (block_sample_q[5:3] != 3'd0);

    for (map_lane_q = 0; map_lane_q < 8; map_lane_q = map_lane_q + 1) begin
      map_sample_lane_w[map_lane_q] =
        block_luma_sample_q[{block_sample_q[5:3], map_lane_q[2:0]}];
      map_nearest_index_w[map_lane_q] = 3'd0;
      map_nearest_delta_w[map_lane_q] = 8'hff;
      map_nearest_color_w[map_lane_q] = 8'd0;
      map_palette_abs_delta_w[map_lane_q] = 8'd0;
      map_vertical_predictor_sample_w[map_lane_q] = 8'd0;
      map_horizontal_predictor_sample_w[map_lane_q] = 8'd0;
      map_vertical_abs_delta_w[map_lane_q] = 8'd0;
      map_horizontal_abs_delta_w[map_lane_q] = 8'd0;

      for (map_color_index_q = 0; map_color_index_q < 8; map_color_index_q = map_color_index_q + 1) begin
        if (map_color_index_q < target_palette_size_q) begin
          map_nearest_color_w[map_lane_q] = palette_color_q[map_color_index_q];
          if (map_sample_lane_w[map_lane_q] >= map_nearest_color_w[map_lane_q]) begin
            map_palette_abs_delta_w[map_lane_q] =
              map_sample_lane_w[map_lane_q] - map_nearest_color_w[map_lane_q];
          end else begin
            map_palette_abs_delta_w[map_lane_q] =
              map_nearest_color_w[map_lane_q] - map_sample_lane_w[map_lane_q];
          end
          if (map_palette_abs_delta_w[map_lane_q] < map_nearest_delta_w[map_lane_q]) begin
            map_nearest_delta_w[map_lane_q] = map_palette_abs_delta_w[map_lane_q];
            map_nearest_index_w[map_lane_q] = map_color_index_q[2:0];
          end
        end
      end

      if (block_sample_q[5:3] >= 3'd4) begin
        map_vertical_predictor_sample_w[map_lane_q] =
          block_luma_sample_q[6'd24 + map_lane_q[5:0]];
      end else begin
        map_vertical_predictor_sample_w[map_lane_q] =
          above_predictor_edge_q[block_id_q[2:0]][map_lane_q * 8 +: 8];
      end
      if (map_sample_lane_w[map_lane_q] >= map_vertical_predictor_sample_w[map_lane_q]) begin
        map_vertical_abs_delta_w[map_lane_q] =
          map_sample_lane_w[map_lane_q] - map_vertical_predictor_sample_w[map_lane_q];
      end else begin
        map_vertical_abs_delta_w[map_lane_q] =
          map_vertical_predictor_sample_w[map_lane_q] - map_sample_lane_w[map_lane_q];
      end

      if (map_lane_q >= 4) begin
        map_horizontal_predictor_sample_w[map_lane_q] =
          block_luma_sample_q[{block_sample_q[5:3], 3'b000} + 6'd3];
      end else begin
        map_horizontal_predictor_sample_w[map_lane_q] =
          left_predictor_edge_q[{block_sample_q[5:3], 3'b000} +: 8];
      end
      if (map_sample_lane_w[map_lane_q] >= map_horizontal_predictor_sample_w[map_lane_q]) begin
        map_horizontal_abs_delta_w[map_lane_q] =
          map_sample_lane_w[map_lane_q] - map_horizontal_predictor_sample_w[map_lane_q];
      end else begin
        map_horizontal_abs_delta_w[map_lane_q] =
          map_horizontal_predictor_sample_w[map_lane_q] - map_sample_lane_w[map_lane_q];
      end

      map_palette_sad_sum_w =
        map_palette_sad_sum_w + {4'd0, map_nearest_delta_w[map_lane_q]};
      map_vertical_sad_sum_w =
        map_vertical_sad_sum_w + {4'd0, map_vertical_abs_delta_w[map_lane_q]};
      map_horizontal_sad_sum_w =
        map_horizontal_sad_sum_w + {4'd0, map_horizontal_abs_delta_w[map_lane_q]};
      map_row_indices_pack_w[map_lane_q * 3 +: 3] = map_nearest_index_w[map_lane_q];

      if (map_lane_q != 0 &&
          map_nearest_index_w[map_lane_q] != map_nearest_index_w[map_lane_q - 1]) begin
        map_row_same_left_w = 1'b0;
      end
      if (block_sample_q[5:3] != 3'd0) begin
        if (map_nearest_index_w[map_lane_q] !=
            current_palette_index_q[(map_row_bit_offset_w - 8'd24) + (map_lane_q * 3) +: 3]) begin
          map_row_same_above_w = 1'b0;
        end
      end
    end
  end

  always @* begin
    query_palette_cache_size_w = 5'd0;
    // AV2 v1.0.0 palette_mode_info() derives its color cache from neighboring
    // MB_MODE_INFO palette sizes. IntraBC leaves return before palette syntax,
    // so they contribute a zero palette size even when the block analyzer had
    // found luma colors during the input prepass.
    if (query_load_block_id_q[5:3] != 3'd0 &&
        !ibc_copy_mask[query_load_block_id_q - 6'd8] &&
        block_luma_mode_q[query_load_block_id_q - 6'd8] == LUMA_MODE_DC) begin
      query_palette_cache_size_w =
        query_palette_cache_size_w + {1'd0, block_palette_size_q[query_load_block_id_q - 6'd8]};
    end
    if (query_load_block_id_q[2:0] != 3'd0 &&
        !ibc_copy_mask[query_load_block_id_q - 6'd1] &&
        block_luma_mode_q[query_load_block_id_q - 6'd1] == LUMA_MODE_DC) begin
      query_palette_cache_size_w =
        query_palette_cache_size_w + {1'd0, block_palette_size_q[query_load_block_id_q - 6'd1]};
    end
  end

  always @* begin
    if (query_luma_mode_q == LUMA_MODE_V) begin
      luma_fetch_predictor_sample_w =
        luma_fetch_txb_row_mi_q[0] ?
          query_luma_predictor_inner_edge_q[luma_fetch_capture_col_bit_offset_w +: 8] :
          query_luma_predictor_edge_q[luma_fetch_capture_col_bit_offset_w +: 8];
    end else if (query_luma_mode_q == LUMA_MODE_H) begin
      luma_fetch_predictor_sample_w =
        luma_fetch_txb_col_mi_q[0] ?
          query_luma_predictor_inner_edge_q[luma_fetch_capture_row_bit_offset_w +: 8] :
          query_luma_predictor_edge_q[luma_fetch_capture_row_bit_offset_w +: 8];
    end else begin
      case (luma_fetch_capture_palette_index_w)
        3'd0: luma_fetch_predictor_sample_w = query_palette_colors_q[7:0];
        3'd1: luma_fetch_predictor_sample_w = query_palette_colors_q[15:8];
        3'd2: luma_fetch_predictor_sample_w = query_palette_colors_q[23:16];
        3'd3: luma_fetch_predictor_sample_w = query_palette_colors_q[31:24];
        3'd4: luma_fetch_predictor_sample_w = query_palette_colors_q[39:32];
        3'd5: luma_fetch_predictor_sample_w = query_palette_colors_q[47:40];
        3'd6: luma_fetch_predictor_sample_w = query_palette_colors_q[55:48];
        default: luma_fetch_predictor_sample_w = query_palette_colors_q[63:56];
      endcase
    end
  end

  always @* begin
    luma_fetch_y_row_slice_w = 32'd0;
    luma_fetch_u_row_slice_w = 32'd0;
    luma_fetch_v_row_slice_w = 32'd0;
    luma_fetch_predictor_row_slice_w = 32'd0;
    for (luma_fetch_lane_q = 0; luma_fetch_lane_q < 4; luma_fetch_lane_q = luma_fetch_lane_q + 1) begin
      luma_fetch_row_row_w =
        {luma_fetch_txb_row_mi_q[0], 2'b00} + luma_fetch_capture_step_q[1:0];
      luma_fetch_row_col_w =
        {luma_fetch_txb_col_mi_q[0], 2'b00} + luma_fetch_lane_q[2:0];
      luma_fetch_row_local_index_w = {luma_fetch_row_row_w, luma_fetch_row_col_w};
      luma_fetch_row_palette_index_w = query_palette_index_q[luma_fetch_row_local_index_w];

      luma_fetch_y_row_slice_w[luma_fetch_lane_q * 8 +: 8] =
        sample_store_y_row_w[{luma_fetch_row_col_w, 3'b000} +: 8];
      luma_fetch_u_row_slice_w[luma_fetch_lane_q * 8 +: 8] =
        sample_store_u_row_w[{luma_fetch_row_col_w, 3'b000} +: 8];
      luma_fetch_v_row_slice_w[luma_fetch_lane_q * 8 +: 8] =
        sample_store_v_row_w[{luma_fetch_row_col_w, 3'b000} +: 8];

      if (query_luma_mode_q == LUMA_MODE_V) begin
        luma_fetch_row_predictor_sample_w =
          luma_fetch_txb_row_mi_q[0] ?
            query_luma_predictor_inner_edge_q[{luma_fetch_row_col_w, 3'b000} +: 8] :
            query_luma_predictor_edge_q[{luma_fetch_row_col_w, 3'b000} +: 8];
      end else if (query_luma_mode_q == LUMA_MODE_H) begin
        luma_fetch_row_predictor_sample_w =
          luma_fetch_txb_col_mi_q[0] ?
            query_luma_predictor_inner_edge_q[{luma_fetch_row_row_w, 3'b000} +: 8] :
            query_luma_predictor_edge_q[{luma_fetch_row_row_w, 3'b000} +: 8];
      end else begin
        case (luma_fetch_row_palette_index_w)
          3'd0: luma_fetch_row_predictor_sample_w = query_palette_colors_q[7:0];
          3'd1: luma_fetch_row_predictor_sample_w = query_palette_colors_q[15:8];
          3'd2: luma_fetch_row_predictor_sample_w = query_palette_colors_q[23:16];
          3'd3: luma_fetch_row_predictor_sample_w = query_palette_colors_q[31:24];
          3'd4: luma_fetch_row_predictor_sample_w = query_palette_colors_q[39:32];
          3'd5: luma_fetch_row_predictor_sample_w = query_palette_colors_q[47:40];
          3'd6: luma_fetch_row_predictor_sample_w = query_palette_colors_q[55:48];
          default: luma_fetch_row_predictor_sample_w = query_palette_colors_q[63:56];
        endcase
      end
      luma_fetch_predictor_row_slice_w[luma_fetch_lane_q * 8 +: 8] =
        luma_fetch_row_predictor_sample_w;
    end
  end

  always @* begin
    for (inner_index_q = 0; inner_index_q < 8; inner_index_q = inner_index_q + 1) begin
      vertical_inner_predictor_edge_w[inner_index_q * 8 +: 8] =
        block_luma_sample_q[24 + inner_index_q];
      horizontal_inner_predictor_edge_w[inner_index_q * 8 +: 8] =
        block_luma_sample_q[inner_index_q * 8 + 3];
    end
  end

  always @* begin
    selected_luma_mode_w = LUMA_MODE_DC;
    selected_luma_sad_w = palette_sad_q;
    selected_luma_predictor_edge_w = 64'd0;
    selected_luma_predictor_inner_edge_w = 64'd0;
    // AV2 v1.0.0 Sections 5.20.5.5 and 5.20.5.6, implemented in AVM as
    // get_y_mode_idx_ctx()/get_y_intra_mode_set(), derive the y_mode_idx
    // context and mode list from above-right and bottom-left directional
    // neighbors. The current symbolizer writes only the non-directional-neighbor
    // context, so H/V is limited to a terminal 8x8 tile leaf that cannot seed a
    // later block's directional context.
    if (fixed_mode_ctx0_w &&
        terminal_tile_leaf_w &&
        block_id_q[5:3] != 3'd0 &&
        block_luma_mode_q[block_id_q - 6'd8] == LUMA_MODE_DC &&
        (vertical_sad_q + LUMA_MODE_SWITCH_SAD_MARGIN) < selected_luma_sad_w) begin
      selected_luma_mode_w = LUMA_MODE_V;
      selected_luma_sad_w = vertical_sad_q;
      selected_luma_predictor_edge_w = above_predictor_edge_q[block_id_q[2:0]];
      selected_luma_predictor_inner_edge_w = vertical_inner_predictor_edge_w;
    end
    if (fixed_mode_ctx0_w &&
        terminal_tile_leaf_w &&
        block_id_q[2:0] != 3'd0 &&
        block_luma_mode_q[block_id_q - 6'd1] == LUMA_MODE_DC &&
        (horizontal_sad_q + LUMA_MODE_SWITCH_SAD_MARGIN) < selected_luma_sad_w) begin
      selected_luma_mode_w = LUMA_MODE_H;
      selected_luma_sad_w = horizontal_sad_q;
      selected_luma_predictor_edge_w = left_predictor_edge_q;
      selected_luma_predictor_inner_edge_w = horizontal_inner_predictor_edge_w;
    end
  end

  always @* begin
    for (delta_index_q = 0; delta_index_q < 8; delta_index_q = delta_index_q + 1) begin
      query_load_color_w[delta_index_q] =
        query_load_palette_colors_w[delta_index_q * 8 +: 8];
    end

    query_load_max_delta_w = 8'd1;
    for (delta_index_q = 0; delta_index_q < 7; delta_index_q = delta_index_q + 1) begin
      if (delta_index_q + 1 < query_load_palette_size_w) begin
        query_load_delta_w[delta_index_q] =
          query_load_color_w[delta_index_q + 1] - query_load_color_w[delta_index_q];
        if (query_load_delta_w[delta_index_q] > query_load_max_delta_w) begin
          query_load_max_delta_w = query_load_delta_w[delta_index_q];
        end
      end else begin
        query_load_delta_w[delta_index_q] = 8'd1;
      end
    end

    if (query_load_max_delta_w <= 8'd32) begin
      query_load_base_delta_bits_w = 5'd5;
    end else if (query_load_max_delta_w <= 8'd64) begin
      query_load_base_delta_bits_w = 5'd6;
    end else if (query_load_max_delta_w <= 8'd128) begin
      query_load_base_delta_bits_w = 5'd7;
    end else begin
      query_load_base_delta_bits_w = 5'd8;
    end

    for (delta_index_q = 0; delta_index_q < 7; delta_index_q = delta_index_q + 1) begin
      // AV2 v1.0.0 Section 5.20.8.1 palette_mode_info(): each delta is
      // bounded by the remaining sample range after the previous colors. Since
      // FrameForge stores sorted palette entries, that range is 255-color[i].
      query_load_delta_range_w = 9'd255 - {1'b0, query_load_color_w[delta_index_q]};
      if (query_load_delta_range_w <= 9'd2) begin
        query_load_delta_limit_w = 5'd1;
      end else if (query_load_delta_range_w <= 9'd4) begin
        query_load_delta_limit_w = 5'd2;
      end else if (query_load_delta_range_w <= 9'd8) begin
        query_load_delta_limit_w = 5'd3;
      end else if (query_load_delta_range_w <= 9'd16) begin
        query_load_delta_limit_w = 5'd4;
      end else if (query_load_delta_range_w <= 9'd32) begin
        query_load_delta_limit_w = 5'd5;
      end else if (query_load_delta_range_w <= 9'd64) begin
        query_load_delta_limit_w = 5'd6;
      end else if (query_load_delta_range_w <= 9'd128) begin
        query_load_delta_limit_w = 5'd7;
      end else begin
        query_load_delta_limit_w = 5'd8;
      end

      query_load_delta_bits_w[delta_index_q] =
        (query_load_base_delta_bits_w < query_load_delta_limit_w) ?
          query_load_base_delta_bits_w : query_load_delta_limit_w;
    end
  end

  always @* begin
    for (pack_index_q = 0; pack_index_q < 8; pack_index_q = pack_index_q + 1) begin
      palette_colors[pack_index_q * 8 +: 8] =
        query_palette_colors_q[pack_index_q * 8 +: 8];
    end
    palette_size = query_palette_size_q;
    palette_cache_size = query_palette_cache_size_q;
    palette_first_color = query_palette_first_color_q;
    palette_delta_bits_minus5 = query_palette_delta_bits_minus5_q;
    palette_delta_minus1 = query_palette_delta_minus1_q;
    palette_delta_literal_bits = query_palette_delta_literal_bits_q;
    query_luma_mode = query_luma_mode_q;
    query_index = query_palette_index_q[query_local_index_w];
    query_left_index = query_palette_index_q[query_left_local_index_w];
    query_top_index = query_palette_index_q[query_top_local_index_w];
    query_top_left_index = query_palette_index_q[query_top_left_local_index_w];
    query_luma_residual_zero = query_luma_residual_zero_q;
    query_chroma_bdpcm_horz = query_chroma_bdpcm_horz_q;
    if (query_row[2:0] != 3'd0 && query_row_same_above_q[query_row[2:0]]) begin
      query_identity_row_flag = 2'd2;
    end else if (query_row_same_left_q[query_row[2:0]]) begin
      query_identity_row_flag = 2'd1;
    end else begin
      query_identity_row_flag = 2'd0;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_IDLE;
      last_block_col_q <= 3'd0;
      last_block_row_q <= 3'd0;
      block_id_q <= 6'd0;
      block_sample_q <= 6'd0;
      block_chroma_sample_q <= 7'd0;
      candidate_q <= 8'd0;
      collected_count_q <= 4'd0;
      target_palette_size_q <= 4'd0;
      sort_pass_q <= 4'd0;
      chroma_complete_q <= 1'b0;
      black_ok_q <= 1'b0;
      palette_supported_q <= 1'b0;
      fetch_active_q <= 1'b0;
      fetch_start_q <= 1'b0;
      query_start_q <= 1'b0;
      query_active_q <= 1'b0;
      query_load_block_id_q <= 6'd0;
      luma_fetch_start_q <= 1'b0;
      luma_fetch_active_q <= 1'b0;
      fetch_plane_v_q <= 1'b0;
      fetch_txb_row_mi_q <= 5'd0;
      fetch_txb_col_mi_q <= 5'd0;
      luma_fetch_txb_row_mi_q <= 5'd0;
      luma_fetch_txb_col_mi_q <= 5'd0;
      fetch_step_q <= 5'd0;
      luma_fetch_step_q <= 5'd0;
      fetch_read_pending_q <= 1'b0;
      fetch_read_is_pred_q <= 1'b0;
      fetch_capture_step_q <= 5'd0;
      luma_fetch_read_pending_q <= 1'b0;
      luma_fetch_capture_step_q <= 5'd0;
      fetch_read_addr_q <= 12'd0;
      chroma_fetch_done <= 1'b0;
      chroma_fetch_txb_samples <= 128'd0;
      chroma_fetch_predictor_samples <= 32'd0;
      chroma_fetch_u_txb_samples <= 128'd0;
      chroma_fetch_u_predictor_samples <= 32'd0;
      chroma_fetch_v_txb_samples <= 128'd0;
      chroma_fetch_v_predictor_samples <= 32'd0;
      luma_fetch_done <= 1'b0;
      luma_fetch_txb_samples <= 128'd0;
      luma_fetch_u_txb_samples <= 128'd0;
      luma_fetch_v_txb_samples <= 128'd0;
      luma_fetch_predictor_samples <= 128'd0;
      luma_fetch_sample_sum <= 12'd0;
      chroma_fetch_sample_sum <= 12'd0;
      query_done <= 1'b0;
      current_palette_index_q <= 192'd0;
      current_row_same_left_q <= 8'd0;
      current_row_same_above_q <= 8'd0;
      left_predictor_edge_q <= 64'd0;
      palette_sad_q <= 16'd0;
      vertical_sad_q <= 16'd0;
      horizontal_sad_q <= 16'd0;
      chroma_h_sad_q <= 16'd0;
      chroma_v_sad_q <= 16'd0;
      chroma_prev_row_q <= 64'd0;
      chroma_left_u_edge_q <= 64'd0;
      chroma_left_v_edge_q <= 64'd0;
      chroma_current_u_right_edge_q <= 64'd0;
      chroma_current_v_right_edge_q <= 64'd0;
      chroma_bottom_h_u_predictor_q <= 8'd0;
      chroma_bottom_h_v_predictor_q <= 8'd0;
      for (pack_index_q = 0; pack_index_q < 64; pack_index_q = pack_index_q + 1) begin
        query_palette_index_q[pack_index_q] <= 3'd0;
        block_chroma_bdpcm_horz_q[pack_index_q] <= 1'b1;
      end
      query_luma_mode_q <= LUMA_MODE_DC;
      query_luma_predictor_edge_q <= 64'd0;
      query_luma_predictor_inner_edge_q <= 64'd0;
      query_palette_colors_q <= 64'd0;
      query_palette_size_q <= 4'd2;
      query_palette_cache_size_q <= 5'd0;
      query_palette_first_color_q <= 8'd0;
      query_palette_delta_bits_minus5_q <= 2'd0;
      query_palette_delta_minus1_q <= 56'd0;
      query_palette_delta_literal_bits_q <= 35'd0;
      query_luma_residual_zero_q <= 1'b0;
      query_chroma_bdpcm_horz_q <= 1'b1;
      query_row_same_left_q <= 8'd0;
      query_row_same_above_q <= 8'd0;
      terminal_luma_predictor_edge_q <= 64'd0;
      terminal_luma_predictor_inner_edge_q <= 64'd0;
      for (edge_index_q = 0; edge_index_q < 8; edge_index_q = edge_index_q + 1) begin
        above_predictor_edge_q[edge_index_q] <= 64'd0;
        chroma_above_u_edge_q[edge_index_q] <= 64'd0;
        chroma_above_v_edge_q[edge_index_q] <= 64'd0;
      end
      done <= 1'b0;
      unsupported <= 1'b0;
      black_mode <= 1'b0;
      luma_palette_mode <= 1'b0;
    end else if (start) begin
      state_q <= ST_BLOCK_INIT;
      last_block_col_q <= (visible_width == 16'd64) ? 3'd7 : (visible_width[5:3] - 3'd1);
      last_block_row_q <= (visible_height == 16'd64) ? 3'd7 : (visible_height[5:3] - 3'd1);
      block_id_q <= 6'd0;
      block_sample_q <= 6'd0;
      block_chroma_sample_q <= 7'd0;
      candidate_q <= 8'd0;
      collected_count_q <= 4'd0;
      target_palette_size_q <= 4'd0;
      sort_pass_q <= 4'd0;
      chroma_complete_q <= 1'b0;
      black_ok_q <= 1'b1;
      fetch_active_q <= 1'b0;
      fetch_start_q <= 1'b0;
      fetch_horz_q <= 1'b1;
      query_start_q <= 1'b0;
      query_active_q <= 1'b0;
      luma_fetch_start_q <= 1'b0;
      luma_fetch_active_q <= 1'b0;
      fetch_step_q <= 5'd0;
      luma_fetch_step_q <= 5'd0;
      fetch_read_pending_q <= 1'b0;
      luma_fetch_read_pending_q <= 1'b0;
      chroma_fetch_done <= 1'b0;
      luma_fetch_done <= 1'b0;
      luma_fetch_sample_sum <= 12'd0;
      chroma_fetch_sample_sum <= 12'd0;
      query_done <= 1'b0;
      current_palette_index_q <= 192'd0;
      current_row_same_left_q <= 8'd0;
      current_row_same_above_q <= 8'd0;
      left_predictor_edge_q <= 64'd0;
      palette_sad_q <= 16'd0;
      vertical_sad_q <= 16'd0;
      horizontal_sad_q <= 16'd0;
      chroma_h_sad_q <= 16'd0;
      chroma_v_sad_q <= 16'd0;
      chroma_prev_row_q <= 64'd0;
      chroma_left_u_edge_q <= 64'd0;
      chroma_left_v_edge_q <= 64'd0;
      chroma_current_u_right_edge_q <= 64'd0;
      chroma_current_v_right_edge_q <= 64'd0;
      chroma_bottom_h_u_predictor_q <= 8'd0;
      chroma_bottom_h_v_predictor_q <= 8'd0;
      query_luma_mode_q <= LUMA_MODE_DC;
      query_luma_predictor_edge_q <= 64'd0;
      query_luma_predictor_inner_edge_q <= 64'd0;
      query_palette_first_color_q <= 8'd0;
      query_palette_delta_bits_minus5_q <= 2'd0;
      query_palette_delta_minus1_q <= 56'd0;
      query_palette_delta_literal_bits_q <= 35'd0;
      query_luma_residual_zero_q <= 1'b0;
      query_chroma_bdpcm_horz_q <= 1'b1;
      terminal_luma_predictor_edge_q <= 64'd0;
      terminal_luma_predictor_inner_edge_q <= 64'd0;
      for (edge_index_q = 0; edge_index_q < 8; edge_index_q = edge_index_q + 1) begin
        above_predictor_edge_q[edge_index_q] <= 64'd0;
        chroma_above_u_edge_q[edge_index_q] <= 64'd0;
        chroma_above_v_edge_q[edge_index_q] <= 64'd0;
      end
      palette_supported_q <=
        (SUPPORT_PALETTE_444 != 0) &&
        (chroma_format_idc == 2'd3) &&
        (SAMPLE_BITS == 8) &&
        (visible_width != 16'd0) &&
        (visible_height != 16'd0) &&
        (visible_width <= 16'd64) &&
        (visible_height <= 16'd64) &&
        (visible_width[2:0] == 3'd0) &&
        (visible_height[2:0] == 3'd0);
      done <= 1'b0;
      unsupported <= 1'b0;
      black_mode <= 1'b0;
      luma_palette_mode <= 1'b0;
    end else begin
      if (chroma_sample_fire_w) begin
        black_ok_q <= black_next_w;
        if (block_chroma_sample_q == block_chroma_sample_last_w) begin
          chroma_complete_q <= 1'b1;
        end else begin
          block_chroma_sample_q <= block_chroma_sample_q + 7'd1;
        end
      end
      if (!lossy420_mode_w && packet_chroma_fire_w) begin
        black_ok_q <= black_next_w;
        chroma_h_sad_q <= chroma_h_sad_q + packet_chroma_h_sad_w;
        chroma_v_sad_q <= chroma_v_sad_q + packet_chroma_v_sad_w;
        chroma_prev_row_q <= packet_samples[63:0];
        if (packet_chroma_plane_v_w) begin
          chroma_current_v_right_edge_q <= packet_chroma_next_right_edge_w;
          if (packet_chroma_row_w == 3'd3) begin
            chroma_bottom_h_v_predictor_q <= packet_lane_w[0];
          end
          if (packet_chroma_done_w) begin
            chroma_left_v_edge_q <= packet_chroma_next_right_edge_w;
            chroma_above_v_edge_q[block_id_q[2:0]] <= packet_samples[63:0];
          end
        end else begin
          chroma_current_u_right_edge_q <= packet_chroma_next_right_edge_w;
          if (packet_chroma_row_w == 3'd3) begin
            chroma_bottom_h_u_predictor_q <= packet_lane_w[0];
          end
          if (packet_chroma_u_plane_done_w) begin
            chroma_left_u_edge_q <= packet_chroma_next_right_edge_w;
            chroma_above_u_edge_q[block_id_q[2:0]] <= packet_samples[63:0];
          end
        end
        if (packet_chroma_done_w) begin
          // AV2 v1.0.0 read_intra_uv_mode() carries one DPCM direction bit
          // for the leaf. The analyzer picks the lower boundary-aware U/V
          // residual SAD so chroma coefficients stay lossless while avoiding
          // avoidable tokens.
          block_chroma_bdpcm_horz_q[block_id_q] <=
            ((chroma_h_sad_q + packet_chroma_h_sad_w) <=
             (chroma_v_sad_q + packet_chroma_v_sad_w));
        end
        if (packet_chroma_done_w) begin
          chroma_complete_q <= 1'b1;
        end else begin
          block_chroma_sample_q <= block_chroma_sample_q + {3'd0, packet_count};
        end
      end

      query_start_q <= query_start;
      if (query_start && !query_start_q) begin
        query_active_q <= 1'b1;
        query_load_block_id_q <= query_block_id_w;
        query_done <= 1'b0;
      end else if (query_active_q) begin
        for (pack_index_q = 0; pack_index_q < 64; pack_index_q = pack_index_q + 1) begin
          query_palette_index_q[pack_index_q] <=
            palette_index_read_data_w[pack_index_q * 3 +: 3];
        end
        query_palette_colors_q <= block_palette_colors_q[query_load_block_id_q];
        query_palette_size_q <= block_palette_size_q[query_load_block_id_q];
        query_palette_cache_size_q <= query_palette_cache_size_w;
        query_palette_first_color_q <= query_load_color_w[0];
        query_palette_delta_bits_minus5_q <= query_load_base_delta_bits_w - 5'd5;
        for (delta_index_q = 0; delta_index_q < 7; delta_index_q = delta_index_q + 1) begin
          query_palette_delta_minus1_q[delta_index_q * 8 +: 8] <=
            query_load_delta_w[delta_index_q] - 8'd1;
          query_palette_delta_literal_bits_q[delta_index_q * 5 +: 5] <=
            query_load_delta_bits_w[delta_index_q];
        end
        query_luma_mode_q <= block_luma_mode_q[query_load_block_id_q];
        // The current H/V intra mode selector is intentionally limited to the
        // terminal 8x8 leaf so directional context cannot leak into later
        // blocks. Store only that terminal predictor pair instead of a
        // 64-entry predictor-edge register bank.
        query_luma_predictor_edge_q <= terminal_luma_predictor_edge_q;
        query_luma_predictor_inner_edge_q <= terminal_luma_predictor_inner_edge_q;
        query_luma_residual_zero_q <= block_luma_residual_zero_q[query_load_block_id_q];
        query_chroma_bdpcm_horz_q <= block_chroma_bdpcm_horz_q[query_load_block_id_q];
        query_row_same_left_q <= row_same_left_q[query_load_block_id_q];
        query_row_same_above_q <= row_same_above_q[query_load_block_id_q];
        query_active_q <= 1'b0;
        query_done <= 1'b1;
      end else if (!query_start) begin
        query_done <= 1'b0;
      end

      luma_fetch_start_q <= luma_fetch_start;
      if (luma_fetch_start && !luma_fetch_start_q) begin
        luma_fetch_txb_row_mi_q <= luma_fetch_txb_row_mi;
        luma_fetch_txb_col_mi_q <= luma_fetch_txb_col_mi;
        luma_fetch_step_q <= 5'd0;
        luma_fetch_read_pending_q <= 1'b0;
        if (lossy420_mode_w) begin
          luma_fetch_active_q <= 1'b0;
          luma_fetch_sample_sum <=
            lossy420_y_sum_q[{luma_fetch_txb_row_mi[3:0], luma_fetch_txb_col_mi[3:0]}];
          luma_fetch_done <= 1'b1;
        end else begin
          luma_fetch_active_q <= 1'b1;
          luma_fetch_done <= 1'b0;
        end
      end else if (luma_fetch_active_q) begin
        if (luma_fetch_read_pending_q) begin
          luma_fetch_txb_samples[luma_fetch_capture_step_q[1:0] * 32 +: 32] <=
            luma_fetch_y_row_slice_w;
          luma_fetch_u_txb_samples[luma_fetch_capture_step_q[1:0] * 32 +: 32] <=
            luma_fetch_u_row_slice_w;
          luma_fetch_v_txb_samples[luma_fetch_capture_step_q[1:0] * 32 +: 32] <=
            luma_fetch_v_row_slice_w;
          luma_fetch_predictor_samples[luma_fetch_capture_step_q[1:0] * 32 +: 32] <=
            luma_fetch_predictor_row_slice_w;
          if (luma_fetch_capture_step_q == 5'd3) begin
            luma_fetch_active_q <= 1'b0;
            luma_fetch_read_pending_q <= 1'b0;
            luma_fetch_done <= 1'b1;
          end else begin
            luma_fetch_capture_step_q <= luma_fetch_capture_step_q + 5'd1;
            if (luma_fetch_capture_step_q < 5'd2) begin
              luma_fetch_step_q <= luma_fetch_capture_step_q + 5'd2;
            end
          end
        end else begin
          luma_fetch_capture_step_q <= 5'd0;
          luma_fetch_step_q <= 5'd1;
          luma_fetch_read_pending_q <= 1'b1;
        end
      end else if (!luma_fetch_start) begin
        luma_fetch_done <= 1'b0;
      end

      fetch_start_q <= chroma_fetch_start;
      if (chroma_fetch_start && !fetch_start_q) begin
        fetch_plane_v_q <= chroma_fetch_plane_v;
        fetch_horz_q <= chroma_fetch_horz;
        fetch_txb_row_mi_q <= chroma_fetch_txb_row_mi;
        fetch_txb_col_mi_q <= chroma_fetch_txb_col_mi;
        fetch_step_q <= chroma_fetch_predictor_only ? 5'd16 : 5'd0;
        fetch_read_pending_q <= 1'b0;
        if (lossy420_mode_w) begin
          fetch_active_q <= 1'b0;
          chroma_fetch_sample_sum <=
            chroma_fetch_plane_v ?
              lossy420_v_sum_q[{chroma_fetch_txb_row_mi[3:1], chroma_fetch_txb_col_mi[3:1]}] :
              lossy420_u_sum_q[{chroma_fetch_txb_row_mi[3:1], chroma_fetch_txb_col_mi[3:1]}];
          chroma_fetch_done <= 1'b1;
        end else begin
          fetch_active_q <= 1'b1;
          chroma_fetch_done <= 1'b0;
        end
      end else if (fetch_active_q) begin
        if (fetch_read_pending_q) begin
          if (fetch_read_is_pred_q) begin
            chroma_fetch_predictor_samples[(fetch_capture_step_q - 5'd16) * 8 +: 8] <=
              fetch_plane_v_q ? chroma_read_v_w : chroma_read_u_w;
            chroma_fetch_u_predictor_samples[(fetch_capture_step_q - 5'd16) * 8 +: 8] <=
              chroma_read_u_w;
            chroma_fetch_v_predictor_samples[(fetch_capture_step_q - 5'd16) * 8 +: 8] <=
              chroma_read_v_w;
            if (fetch_capture_step_q == 5'd19) begin
              fetch_active_q <= 1'b0;
              fetch_read_pending_q <= 1'b0;
              chroma_fetch_done <= 1'b1;
            end else begin
              fetch_capture_step_q <= fetch_capture_step_q + 5'd1;
              if (fetch_capture_step_q < 5'd18) begin
                fetch_step_q <= fetch_capture_step_q + 5'd2;
              end
            end
          end else begin
            chroma_fetch_txb_samples[fetch_capture_step_q * 8 +: 8] <=
              fetch_plane_v_q ? chroma_read_v_w : chroma_read_u_w;
            chroma_fetch_u_txb_samples[fetch_capture_step_q * 8 +: 8] <= chroma_read_u_w;
            chroma_fetch_v_txb_samples[fetch_capture_step_q * 8 +: 8] <= chroma_read_v_w;
            if (fetch_capture_step_q < 5'd15) begin
              fetch_capture_step_q <= fetch_capture_step_q + 5'd1;
              if (fetch_capture_step_q < 5'd14) begin
                fetch_step_q <= fetch_capture_step_q + 5'd2;
              end
            end else begin
              fetch_read_pending_q <= 1'b0;
              fetch_step_q <= 5'd16;
            end
          end
        end else if (fetch_step_q < 5'd16) begin
          fetch_capture_step_q <= fetch_step_q;
          fetch_read_is_pred_q <= 1'b0;
          fetch_step_q <= fetch_step_q + 5'd1;
          fetch_read_pending_q <= 1'b1;
        end else if (fetch_step_q < 5'd20) begin
          if (fetch_txb_col_mi_q == 5'd0 && fetch_txb_row_mi_q == 5'd0) begin
            // AV2 v1.0.0 Section 7.11 intra prediction, mirrored from AVM
            // reconintra.c: unavailable H_PRED left edges use base+1, while
            // unavailable V_PRED above edges use base-1.
            chroma_fetch_predictor_samples[(fetch_step_q - 5'd16) * 8 +: 8] <=
              fetch_horz_q ? 8'd129 : 8'd127;
            chroma_fetch_u_predictor_samples[(fetch_step_q - 5'd16) * 8 +: 8] <=
              fetch_horz_q ? 8'd129 : 8'd127;
            chroma_fetch_v_predictor_samples[(fetch_step_q - 5'd16) * 8 +: 8] <=
              fetch_horz_q ? 8'd129 : 8'd127;
            if (fetch_step_q == 5'd19) begin
              fetch_active_q <= 1'b0;
              chroma_fetch_done <= 1'b1;
            end else begin
              fetch_step_q <= fetch_step_q + 5'd1;
            end
          end else begin
            fetch_read_addr_q <= fetch_pred_read_addr_w;
            fetch_capture_step_q <= fetch_step_q;
            fetch_read_is_pred_q <= 1'b1;
            fetch_step_q <= fetch_step_q + 5'd1;
            fetch_read_pending_q <= 1'b1;
          end
        end else begin
          fetch_active_q <= 1'b0;
          chroma_fetch_done <= 1'b1;
        end
      end else if (!chroma_fetch_start) begin
        chroma_fetch_done <= 1'b0;
      end

      if (chroma_input_error_w || packet_luma_input_error_w || packet_chroma_input_error_w) begin
        unsupported <= 1'b1;
        done <= 1'b1;
        state_q <= ST_DONE;
      end else begin
        case (state_q)
          ST_IDLE: begin
          end
          ST_READ: begin
            if (lossy420_mode_w) begin
              if (packet_luma_fire_w) begin
                black_ok_q <= black_next_w;
                lossy420_y_sum_q[lossy420_y_sum_left_index_w] <=
                  lossy420_y_sum_q[lossy420_y_sum_left_index_w] + packet_luma_left_sum_w;
                lossy420_y_sum_q[lossy420_y_sum_right_index_w] <=
                  lossy420_y_sum_q[lossy420_y_sum_right_index_w] + packet_luma_right_sum_w;
                if (packet_luma_done_w) begin
                  block_chroma_sample_q <= 7'd0;
                  chroma_complete_q <= 1'b0;
                  state_q <= ST_DRAIN_CHROMA;
                end else begin
                  block_sample_q <= block_sample_q + {2'd0, packet_count};
                end
              end
            end else if (packet_luma_fire_w) begin
              black_ok_q <= black_next_w;
              for (packet_lane_q = 0; packet_lane_q < 8; packet_lane_q = packet_lane_q + 1) begin
                if (packet_lane_q < packet_count) begin
                  block_luma_sample_q[block_sample_q + packet_lane_q[5:0]] <=
                    packet_lane_w[packet_lane_q];
                end
              end
              for (color_index_q = 0; color_index_q < 8; color_index_q = color_index_q + 1) begin
                palette_color_q[color_index_q] <= packet_palette_color_next_w[color_index_q];
              end
              collected_count_q <= packet_collected_next_count_w;
              if (packet_luma_done_w) begin
                block_chroma_sample_q <= 7'd0;
                chroma_complete_q <= 1'b0;
                candidate_q <= 8'd0;
                state_q <= ST_PAD;
              end else begin
                block_sample_q <= block_sample_q + {2'd0, packet_count};
              end
            end else if (sample_fire) begin
              black_ok_q <= black_next_w;
              block_luma_sample_q[block_sample_q] <= sample_u8_w;
              if (collect_add_w) begin
                palette_color_q[collected_count_q] <= sample_u8_w;
                collected_count_q <= collected_next_count_w;
              end
              if (sample_last) begin
                unsupported <= 1'b1;
                done <= 1'b1;
                state_q <= ST_DONE;
              end else if (block_sample_q == 6'd63) begin
                block_chroma_sample_q <= 7'd0;
                chroma_complete_q <= 1'b0;
                candidate_q <= 8'd0;
                state_q <= ST_PAD;
              end else begin
                block_sample_q <= block_sample_q + 6'd1;
              end
            end
          end
          ST_BLOCK_INIT: begin
            block_sample_q <= 6'd0;
            candidate_q <= 8'd0;
            collected_count_q <= 4'd0;
            target_palette_size_q <= 4'd0;
            sort_pass_q <= 4'd0;
            current_palette_index_q <= 192'd0;
            current_row_same_left_q <= 8'd0;
            current_row_same_above_q <= 8'd0;
            palette_sad_q <= 16'd0;
            vertical_sad_q <= 16'd0;
            horizontal_sad_q <= 16'd0;
            chroma_h_sad_q <= 16'd0;
            chroma_v_sad_q <= 16'd0;
            chroma_prev_row_q <= 64'd0;
            chroma_current_u_right_edge_q <= 64'd0;
            chroma_current_v_right_edge_q <= 64'd0;
            chroma_bottom_h_u_predictor_q <= 8'd0;
            chroma_bottom_h_v_predictor_q <= 8'd0;
            for (color_index_q = 0; color_index_q < 8; color_index_q = color_index_q + 1) begin
              palette_color_q[color_index_q] <= 8'd0;
            end
            if (lossy420_mode_w) begin
              lossy420_y_sum_q[lossy420_y_sum_clear0_index_w] <= 12'd0;
              lossy420_y_sum_q[lossy420_y_sum_clear1_index_w] <= 12'd0;
              lossy420_y_sum_q[lossy420_y_sum_clear2_index_w] <= 12'd0;
              lossy420_y_sum_q[lossy420_y_sum_clear3_index_w] <= 12'd0;
              lossy420_u_sum_q[block_id_q] <= 12'd0;
              lossy420_v_sum_q[block_id_q] <= 12'd0;
            end
            state_q <= ST_READ;
          end
          ST_PAD: begin
            if (target_palette_size_q == 4'd0) begin
              // Decide the coded palette size after the final luma sample has
              // registered. AV2 Section 5.11.39 only observes the padded,
              // sorted palette, so this avoids a packet-data to target-size
              // timing path without changing syntax.
              if (collected_count_q <= 4'd2) begin
                target_palette_size_q <= 4'd2;
              end else if (collected_count_q <= 4'd4) begin
                target_palette_size_q <= 4'd4;
              end else begin
                target_palette_size_q <= 4'd8;
            end
          end else if (collected_count_q < target_palette_size_q) begin
              if (!candidate_known_w) begin
                palette_color_q[collected_count_q] <= candidate_q;
                collected_count_q <= collected_count_q + 4'd1;
              end
              candidate_q <= candidate_q + 8'd1;
            end else begin
              sort_pass_q <= 4'd0;
              state_q <= ST_SORT;
            end
          end
          ST_SORT: begin
            // AV2 v1.0.0 Section 5.11.39 writes palette colors sorted in
            // increasing order. Use a six-layer 8-input sorting network
            // instead of the old one-compare-per-cycle bubble pass; each layer
            // uses independent compare-swaps, and inactive palette lanes are
            // skipped for 2- and 4-color palettes.
            if (target_palette_size_q <= 4'd2) begin
              if (palette_color_q[0] > palette_color_q[1]) begin
                palette_color_q[0] <= palette_color_q[1];
                palette_color_q[1] <= palette_color_q[0];
              end
              state_q <= ST_STORE_COLORS;
            end else if (target_palette_size_q <= 4'd4) begin
              case (sort_pass_q)
                4'd0: begin
                  if (palette_color_q[0] > palette_color_q[2]) begin
                    palette_color_q[0] <= palette_color_q[2];
                    palette_color_q[2] <= palette_color_q[0];
                  end
                  if (palette_color_q[1] > palette_color_q[3]) begin
                    palette_color_q[1] <= palette_color_q[3];
                    palette_color_q[3] <= palette_color_q[1];
                  end
                  sort_pass_q <= 4'd1;
                end
                4'd1: begin
                  if (palette_color_q[0] > palette_color_q[1]) begin
                    palette_color_q[0] <= palette_color_q[1];
                    palette_color_q[1] <= palette_color_q[0];
                  end
                  if (palette_color_q[2] > palette_color_q[3]) begin
                    palette_color_q[2] <= palette_color_q[3];
                    palette_color_q[3] <= palette_color_q[2];
                  end
                  sort_pass_q <= 4'd2;
                end
                default: begin
                  if (palette_color_q[1] > palette_color_q[2]) begin
                    palette_color_q[1] <= palette_color_q[2];
                    palette_color_q[2] <= palette_color_q[1];
                  end
                  state_q <= ST_STORE_COLORS;
                end
              endcase
            end else begin
              case (sort_pass_q)
                4'd0: begin
                  if (palette_color_q[0] > palette_color_q[2]) begin
                    palette_color_q[0] <= palette_color_q[2];
                    palette_color_q[2] <= palette_color_q[0];
                  end
                  if (palette_color_q[1] > palette_color_q[3]) begin
                    palette_color_q[1] <= palette_color_q[3];
                    palette_color_q[3] <= palette_color_q[1];
                  end
                  if (palette_color_q[4] > palette_color_q[6]) begin
                    palette_color_q[4] <= palette_color_q[6];
                    palette_color_q[6] <= palette_color_q[4];
                  end
                  if (palette_color_q[5] > palette_color_q[7]) begin
                    palette_color_q[5] <= palette_color_q[7];
                    palette_color_q[7] <= palette_color_q[5];
                  end
                  sort_pass_q <= 4'd1;
                end
                4'd1: begin
                  if (palette_color_q[0] > palette_color_q[4]) begin
                    palette_color_q[0] <= palette_color_q[4];
                    palette_color_q[4] <= palette_color_q[0];
                  end
                  if (palette_color_q[1] > palette_color_q[5]) begin
                    palette_color_q[1] <= palette_color_q[5];
                    palette_color_q[5] <= palette_color_q[1];
                  end
                  if (palette_color_q[2] > palette_color_q[6]) begin
                    palette_color_q[2] <= palette_color_q[6];
                    palette_color_q[6] <= palette_color_q[2];
                  end
                  if (palette_color_q[3] > palette_color_q[7]) begin
                    palette_color_q[3] <= palette_color_q[7];
                    palette_color_q[7] <= palette_color_q[3];
                  end
                  sort_pass_q <= 4'd2;
                end
                4'd2: begin
                  if (palette_color_q[0] > palette_color_q[1]) begin
                    palette_color_q[0] <= palette_color_q[1];
                    palette_color_q[1] <= palette_color_q[0];
                  end
                  if (palette_color_q[2] > palette_color_q[3]) begin
                    palette_color_q[2] <= palette_color_q[3];
                    palette_color_q[3] <= palette_color_q[2];
                  end
                  if (palette_color_q[4] > palette_color_q[5]) begin
                    palette_color_q[4] <= palette_color_q[5];
                    palette_color_q[5] <= palette_color_q[4];
                  end
                  if (palette_color_q[6] > palette_color_q[7]) begin
                    palette_color_q[6] <= palette_color_q[7];
                    palette_color_q[7] <= palette_color_q[6];
                  end
                  sort_pass_q <= 4'd3;
                end
                4'd3: begin
                  if (palette_color_q[2] > palette_color_q[4]) begin
                    palette_color_q[2] <= palette_color_q[4];
                    palette_color_q[4] <= palette_color_q[2];
                  end
                  if (palette_color_q[3] > palette_color_q[5]) begin
                    palette_color_q[3] <= palette_color_q[5];
                    palette_color_q[5] <= palette_color_q[3];
                  end
                  sort_pass_q <= 4'd4;
                end
                4'd4: begin
                  if (palette_color_q[1] > palette_color_q[4]) begin
                    palette_color_q[1] <= palette_color_q[4];
                    palette_color_q[4] <= palette_color_q[1];
                  end
                  if (palette_color_q[3] > palette_color_q[6]) begin
                    palette_color_q[3] <= palette_color_q[6];
                    palette_color_q[6] <= palette_color_q[3];
                  end
                  sort_pass_q <= 4'd5;
                end
                default: begin
                  if (palette_color_q[1] > palette_color_q[2]) begin
                    palette_color_q[1] <= palette_color_q[2];
                    palette_color_q[2] <= palette_color_q[1];
                  end
                  if (palette_color_q[3] > palette_color_q[4]) begin
                    palette_color_q[3] <= palette_color_q[4];
                    palette_color_q[4] <= palette_color_q[3];
                  end
                  if (palette_color_q[5] > palette_color_q[6]) begin
                    palette_color_q[5] <= palette_color_q[6];
                    palette_color_q[6] <= palette_color_q[5];
                  end
                  state_q <= ST_STORE_COLORS;
                end
              endcase
            end
          end
          ST_STORE_COLORS: begin
            block_palette_size_q[block_id_q] <= target_palette_size_q;
            block_palette_colors_q[block_id_q] <= palette_colors_pack_w;
            block_sample_q <= 6'd0;
            state_q <= ST_MAP;
          end
          ST_MAP: begin
            current_palette_index_q[map_row_bit_offset_w +: 24] <= map_row_indices_pack_w;
            palette_sad_q <= palette_sad_q + {4'd0, map_palette_sad_sum_w};
            vertical_sad_q <= vertical_sad_q + {4'd0, map_vertical_sad_sum_w};
            horizontal_sad_q <= horizontal_sad_q + {4'd0, map_horizontal_sad_sum_w};
            current_row_same_left_q[block_sample_q[5:3]] <= map_row_same_left_w;
            current_row_same_above_q[block_sample_q[5:3]] <= map_row_same_above_w;
            if (block_sample_q[5:3] == 3'd7) begin
              state_q <= ST_NEXT_BLOCK;
            end else begin
              block_sample_q <= block_sample_q + 6'd8;
            end
          end
          ST_NEXT_BLOCK: begin
            block_luma_mode_q[block_id_q] <= selected_luma_mode_w;
            if (selected_luma_mode_w != LUMA_MODE_DC) begin
              terminal_luma_predictor_edge_q <= selected_luma_predictor_edge_w;
              terminal_luma_predictor_inner_edge_q <= selected_luma_predictor_inner_edge_w;
            end
            block_luma_residual_zero_q[block_id_q] <= (selected_luma_sad_w == 16'd0);
            row_same_left_q[block_id_q] <= current_row_same_left_q;
            row_same_above_q[block_id_q] <= current_row_same_above_q;
            for (edge_index_q = 0; edge_index_q < 8; edge_index_q = edge_index_q + 1) begin
              left_predictor_edge_q[edge_index_q * 8 +: 8] <=
                block_luma_sample_q[edge_index_q * 8 + 7];
              above_predictor_edge_q[block_id_q[2:0]][edge_index_q * 8 +: 8] <=
                block_luma_sample_q[56 + edge_index_q];
            end
            if (chroma_complete_q || chroma_sample_done_w ||
                (!lossy420_mode_w && packet_chroma_done_w)) begin
              if (terminal_tile_leaf_w) begin
                black_mode <= packet_chroma_done_w ? black_next_w : final_black_w;
                luma_palette_mode <=
                  palette_supported_q && !(packet_chroma_done_w ? black_next_w : final_black_w);
                done <= 1'b1;
                state_q <= ST_DONE;
              end else if (block_id_q[2:0] == last_block_col_q) begin
                block_id_q <= {block_id_q[5:3] + 3'd1, 3'd0};
                block_sample_q <= 6'd0;
                block_chroma_sample_q <= 7'd0;
                chroma_complete_q <= 1'b0;
                state_q <= ST_BLOCK_INIT;
              end else begin
                block_id_q <= block_id_q + 6'd1;
                block_sample_q <= 6'd0;
                block_chroma_sample_q <= 7'd0;
                chroma_complete_q <= 1'b0;
                state_q <= ST_BLOCK_INIT;
              end
            end else begin
              state_q <= ST_DRAIN_CHROMA;
            end
          end
          ST_DRAIN_CHROMA: begin
            if (lossy420_mode_w) begin
              if (packet_chroma_fire_w) begin
                black_ok_q <= black_next_w;
                if (packet_chroma_plane_v_w) begin
                  lossy420_v_sum_q[block_id_q] <=
                    lossy420_v_sum_q[block_id_q] + packet_chroma_sum_w;
                end else begin
                  lossy420_u_sum_q[block_id_q] <=
                    lossy420_u_sum_q[block_id_q] + packet_chroma_sum_w;
                end
                if (packet_chroma_done_w) begin
                  if (terminal_tile_leaf_w) begin
                    black_mode <= black_next_w;
                    luma_palette_mode <= 1'b0;
                    done <= 1'b1;
                    state_q <= ST_DONE;
                  end else begin
                    // 4:2:0 skips palette pad/sort/map. Clear the next
                    // block's residual sums while advancing out of chroma
                    // drain so the next leaf starts one cycle earlier.
                    block_id_q <= next_block_id_w;
                    block_sample_q <= 6'd0;
                    block_chroma_sample_q <= 7'd0;
                    chroma_complete_q <= 1'b0;
                    lossy420_y_sum_q[lossy420_next_y_sum_clear0_index_w] <= 12'd0;
                    lossy420_y_sum_q[lossy420_next_y_sum_clear1_index_w] <= 12'd0;
                    lossy420_y_sum_q[lossy420_next_y_sum_clear2_index_w] <= 12'd0;
                    lossy420_y_sum_q[lossy420_next_y_sum_clear3_index_w] <= 12'd0;
                    lossy420_u_sum_q[next_block_id_w] <= 12'd0;
                    lossy420_v_sum_q[next_block_id_w] <= 12'd0;
                    state_q <= ST_READ;
                  end
                end else begin
                  block_chroma_sample_q <= block_chroma_sample_q + {3'd0, packet_count};
                end
              end
            end else if (chroma_complete_q || chroma_sample_done_w ||
                         (!lossy420_mode_w && packet_chroma_done_w)) begin
              if (terminal_tile_leaf_w) begin
                black_mode <= packet_chroma_done_w ? black_next_w : final_black_w;
                luma_palette_mode <=
                  palette_supported_q && !(packet_chroma_done_w ? black_next_w : final_black_w);
                done <= 1'b1;
                state_q <= ST_DONE;
              end else if (block_id_q[2:0] == last_block_col_q) begin
                block_id_q <= {block_id_q[5:3] + 3'd1, 3'd0};
                block_sample_q <= 6'd0;
                block_chroma_sample_q <= 7'd0;
                chroma_complete_q <= 1'b0;
                state_q <= ST_BLOCK_INIT;
              end else begin
                block_id_q <= block_id_q + 6'd1;
                block_sample_q <= 6'd0;
                block_chroma_sample_q <= 7'd0;
                chroma_complete_q <= 1'b0;
                state_q <= ST_BLOCK_INIT;
              end
            end
          end
          ST_DONE: begin
          end
          default: begin
            state_q <= ST_IDLE;
          end
        endcase
      end
    end
  end

endmodule
