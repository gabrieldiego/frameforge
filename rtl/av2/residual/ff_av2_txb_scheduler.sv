`timescale 1ns/1ps

module ff_av2_txb_scheduler (
  input  logic        start,
  input  logic        pending_push_valid,
  input  logic        state_leaf,
  input  logic        state_chroma_fetch,
  input  logic        phase_intra,
  input  logic        phase_palette_header,
  input  logic        phase_palette_map,
  input  logic        phase_y_coeff,
  input  logic        phase_u_coeff,
  input  logic        phase_v_coeff,
  input  logic [1:0]  chroma_format_idc,
  input  logic        palette_mode,
  input  logic        leaf_chroma_bdpcm_horz,
  input  logic        residual_mode,
  input  logic        lossy_420_mode,
  input  logic [4:0]  block_row_mi,
  input  logic [4:0]  block_col_mi,
  input  logic [4:0]  block_w_mi,
  input  logic [4:0]  block_h_mi,
  input  logic [4:0]  visible_cols_mi,
  input  logic [4:0]  visible_rows_mi,
  input  logic [4:0]  txb_local_row,
  input  logic [4:0]  txb_local_col,
  input  logic [15:0] txb_index,
  input  logic [15:0] current_txb_count,
  input  logic [15:0] current_txb_width,
  input  logic        txb_prefetch_started,
  input  logic        txb_prefetch_done,
  input  logic        txb_prefetch_chroma,
  input  logic        txb_prefetch_plane_v,
  input  logic [1:0]  txb_prefetch_index,
  input  logic        luma_fetch_done,
  input  logic        chroma_fetch_done,
  input  logic [3:0]  cached_chroma_samples_valid,
  input  logic [3:0]  cached_v_valid,
  input  logic        left_edge_valid,
  input  logic [4:0]  left_edge_row_mi,
  input  logic [4:0]  left_edge_col_mi,
  input  logic        above_col0_valid,
  input  logic [4:0]  above_col0_row_mi,
  output logic        chroma_fetch_start,
  output logic        luma_fetch_start,
  output logic [4:0]  leaf_visible_txb_w,
  output logic [4:0]  leaf_visible_txb_h,
  output logic [15:0] txb_width,
  output logic [15:0] txb_count,
  output logic [15:0] chroma_txb_width,
  output logic [15:0] chroma_txb_count,
  output logic        chroma_subsampled_phase,
  output logic [15:0] txb_row,
  output logic [15:0] txb_col,
  output logic        same_phase_has_next_txb,
  output logic        cross_phase_has_next_txb,
  output logic [4:0]  next_txb_local_row,
  output logic [4:0]  next_txb_local_col,
  output logic [15:0] next_txb_row,
  output logic [15:0] next_txb_col,
  output logic        txb_fetch_done,
  output logic        txb_prefetch_fetch_done,
  output logic        v_chroma_cache_hit,
  output logic        u_chroma_cache_hit,
  output logic        chroma_fetch_current_cache_hit,
  output logic [1:0]  chroma_fetch_cache_index,
  output logic [1:0]  luma_fetch_cache_index,
  output logic        chroma_fetch_req_cross_phase,
  output logic        chroma_fetch_req_next_txb,
  output logic [1:0]  chroma_fetch_req_index,
  output logic        chroma_predictor_compute_valid,
  output logic        chroma_fetch_req_predictor_compute,
  output logic        chroma_external_left_predictor_valid,
  output logic        chroma_req_external_left_predictor_valid,
  output logic        chroma_external_above_predictor_valid,
  output logic        chroma_req_external_above_predictor_valid,
  output logic        chroma_fetch_req_ready,
  output logic        chroma_fetch_predictor_only,
  output logic        chroma_fetch_completed_u,
  output logic        luma_fetch_completed,
  output logic        txb_prefetch_chroma_target_v,
  output logic        txb_prefetch_luma_start,
  output logic        txb_prefetch_chroma_start,
  output logic        txb_prefetch_cross_phase,
  output logic        txb_prefetch_first_luma,
  output logic [4:0]  luma_fetch_req_row_mi,
  output logic [4:0]  luma_fetch_req_col_mi,
  output logic [4:0]  chroma_fetch_current_storage_row_mi,
  output logic [4:0]  chroma_fetch_current_storage_col_mi,
  output logic [4:0]  chroma_fetch_next_storage_row_mi,
  output logic [4:0]  chroma_fetch_next_storage_col_mi,
  output logic [4:0]  chroma_fetch_req_row_mi,
  output logic [4:0]  chroma_fetch_req_col_mi,
  output logic        chroma_fetch_req_plane_v,
  output logic [1:0]  chroma_left_source_index,
  output logic [1:0]  chroma_above_source_index
);

  assign chroma_fetch_start =
    (state_chroma_fetch &&
     !txb_prefetch_started &&
     (phase_u_coeff || phase_v_coeff) &&
     !chroma_fetch_current_cache_hit) ||
    txb_prefetch_chroma_start ||
    (txb_prefetch_started && !txb_prefetch_done && txb_prefetch_chroma);
  assign luma_fetch_start =
    (state_chroma_fetch &&
     !txb_prefetch_started &&
     phase_y_coeff) ||
    txb_prefetch_luma_start ||
    (txb_prefetch_started && !txb_prefetch_done && !txb_prefetch_chroma);

  assign leaf_visible_txb_w =
    ((block_col_mi + block_w_mi) > visible_cols_mi) ?
      (visible_cols_mi - block_col_mi) : block_w_mi;
  assign leaf_visible_txb_h =
    ((block_row_mi + block_h_mi) > visible_rows_mi) ?
      (visible_rows_mi - block_row_mi) : block_h_mi;
  assign txb_width = {11'd0, leaf_visible_txb_w};
  assign txb_count = {11'd0, leaf_visible_txb_w} * {11'd0, leaf_visible_txb_h};
  assign chroma_txb_width =
    (chroma_format_idc == 2'd1) ? {11'd0, leaf_visible_txb_w[4:1]} : txb_width;
  assign chroma_txb_count =
    (chroma_format_idc == 2'd1) ?
      ({11'd0, leaf_visible_txb_w[4:1]} * {11'd0, leaf_visible_txb_h[4:1]}) :
      txb_count;
  assign chroma_subsampled_phase =
    (chroma_format_idc == 2'd1) && (phase_u_coeff || phase_v_coeff);
  assign txb_row = chroma_subsampled_phase ?
    {11'd0, (block_row_mi >> 1) + txb_local_row} :
    {11'd0, block_row_mi + txb_local_row};
  assign txb_col = chroma_subsampled_phase ?
    {11'd0, (block_col_mi >> 1) + txb_local_col} :
    {11'd0, block_col_mi + txb_local_col};

  assign same_phase_has_next_txb =
    residual_mode &&
    (phase_y_coeff || phase_u_coeff || phase_v_coeff) &&
    (txb_index != (current_txb_count - 16'd1));
  assign cross_phase_has_next_txb =
    residual_mode &&
    (txb_index == (current_txb_count - 16'd1)) &&
    (phase_y_coeff || phase_u_coeff);
  assign next_txb_local_col =
    (txb_local_col == (current_txb_width[4:0] - 5'd1)) ? 5'd0 : (txb_local_col + 5'd1);
  assign next_txb_local_row =
    (txb_local_col == (current_txb_width[4:0] - 5'd1)) ?
      (txb_local_row + 5'd1) : txb_local_row;
  assign next_txb_row = {11'd0, block_row_mi + next_txb_local_row};
  assign next_txb_col = {11'd0, block_col_mi + next_txb_local_col};
  assign txb_fetch_done =
    phase_y_coeff ? luma_fetch_done :
    phase_u_coeff ? chroma_fetch_done :
    phase_v_coeff ? (chroma_fetch_done || v_chroma_cache_hit) : 1'b0;
  assign txb_prefetch_fetch_done = luma_fetch_done || chroma_fetch_done;

  assign v_chroma_cache_hit =
    palette_mode &&
    phase_v_coeff &&
    (cached_v_valid[txb_index[1:0]] || chroma_predictor_compute_valid);
  assign u_chroma_cache_hit =
    palette_mode &&
    phase_u_coeff &&
    leaf_chroma_bdpcm_horz &&
    chroma_predictor_compute_valid;
  assign chroma_fetch_current_cache_hit = u_chroma_cache_hit || v_chroma_cache_hit;
  assign chroma_fetch_cache_index =
    txb_prefetch_started ? txb_prefetch_index : txb_index[1:0];
  assign luma_fetch_cache_index =
    txb_prefetch_started ? txb_prefetch_index : txb_index[1:0];

  assign chroma_fetch_req_cross_phase =
    state_leaf &&
    cross_phase_has_next_txb &&
    !(same_phase_has_next_txb && (phase_u_coeff || phase_v_coeff));
  assign chroma_fetch_req_next_txb =
    state_leaf &&
    ((same_phase_has_next_txb && (phase_u_coeff || phase_v_coeff)) ||
     cross_phase_has_next_txb);
  assign chroma_fetch_req_index =
    chroma_fetch_req_cross_phase ? 2'd0 :
    (chroma_fetch_req_next_txb ? (txb_index[1:0] + 2'd1) : txb_index[1:0]);

  // The cached predictor shortcut is intentionally limited to cases that
  // match ff_av2_palette_analyzer_444's fetch_pred_read_addr_w sequence: the
  // tile top-left constant and left-edge predictors from the previous 4x4 TXB.
  assign chroma_predictor_compute_valid =
    leaf_chroma_bdpcm_horz &&
    cached_chroma_samples_valid[txb_index[1:0]] &&
    (((txb_row[4:0] == 5'd0) && (txb_col[4:0] == 5'd0)) ||
     txb_col[0] ||
     chroma_external_left_predictor_valid ||
     chroma_external_above_predictor_valid ||
     ((txb_col[4:0] == 5'd0) && txb_row[0]));
  assign chroma_fetch_req_predictor_compute =
    leaf_chroma_bdpcm_horz &&
    cached_chroma_samples_valid[chroma_fetch_req_index] &&
    (((chroma_fetch_req_row_mi == 5'd0) && (chroma_fetch_req_col_mi == 5'd0)) ||
     chroma_fetch_req_col_mi[0] ||
     chroma_req_external_left_predictor_valid ||
     chroma_req_external_above_predictor_valid ||
     ((chroma_fetch_req_col_mi == 5'd0) && chroma_fetch_req_row_mi[0]));
  assign chroma_external_left_predictor_valid =
    (txb_col[4:0] != 5'd0) &&
    !txb_col[0] &&
    left_edge_valid &&
    (left_edge_row_mi == block_row_mi) &&
    ((left_edge_col_mi + 5'd2) == block_col_mi);
  assign chroma_req_external_left_predictor_valid =
    (chroma_fetch_req_col_mi != 5'd0) &&
    !chroma_fetch_req_col_mi[0] &&
    left_edge_valid &&
    (left_edge_row_mi == block_row_mi) &&
    ((left_edge_col_mi + 5'd2) == block_col_mi);
  assign chroma_external_above_predictor_valid =
    (txb_col[4:0] == 5'd0) &&
    (txb_row[4:0] != 5'd0) &&
    !txb_row[0] &&
    above_col0_valid &&
    ((above_col0_row_mi + 5'd2) == block_row_mi);
  assign chroma_req_external_above_predictor_valid =
    (chroma_fetch_req_col_mi == 5'd0) &&
    (chroma_fetch_req_row_mi != 5'd0) &&
    !chroma_fetch_req_row_mi[0] &&
    above_col0_valid &&
    ((above_col0_row_mi + 5'd2) == block_row_mi);
  assign chroma_fetch_req_ready =
    palette_mode &&
    (chroma_fetch_req_predictor_compute ||
     (chroma_fetch_req_plane_v && cached_v_valid[chroma_fetch_req_index]));
  assign chroma_fetch_predictor_only =
    palette_mode &&
    cached_chroma_samples_valid[chroma_fetch_req_index] &&
    !chroma_fetch_req_predictor_compute;
  assign chroma_fetch_completed_u =
    chroma_fetch_done &&
    (txb_prefetch_started ?
      (txb_prefetch_chroma && !txb_prefetch_plane_v) :
      phase_u_coeff);
  assign luma_fetch_completed =
    luma_fetch_done &&
    (txb_prefetch_started ? !txb_prefetch_chroma : phase_y_coeff);

  assign txb_prefetch_chroma_target_v =
    ((same_phase_has_next_txb && phase_v_coeff) ||
     (cross_phase_has_next_txb && phase_u_coeff));
  assign txb_prefetch_luma_start =
    !start &&
    !pending_push_valid &&
    !lossy_420_mode &&
    state_leaf &&
    ((same_phase_has_next_txb && phase_y_coeff) ||
     ((phase_intra || phase_palette_header || phase_palette_map) &&
      residual_mode &&
      (txb_index == 16'd0))) &&
    !txb_prefetch_started &&
    !luma_fetch_done;
  assign txb_prefetch_chroma_start =
    !start &&
    !pending_push_valid &&
    !lossy_420_mode &&
    state_leaf &&
    ((same_phase_has_next_txb && (phase_u_coeff || phase_v_coeff)) ||
     cross_phase_has_next_txb) &&
    !txb_prefetch_started &&
    !txb_prefetch_chroma_target_v &&
    !chroma_fetch_req_predictor_compute &&
    !chroma_fetch_done;
  assign txb_prefetch_cross_phase =
    txb_prefetch_chroma_start && chroma_fetch_req_cross_phase;
  assign txb_prefetch_first_luma =
    txb_prefetch_luma_start &&
    (phase_intra || phase_palette_header || phase_palette_map);

  assign luma_fetch_req_row_mi =
    txb_prefetch_first_luma ? block_row_mi :
    (txb_prefetch_luma_start ? next_txb_row[4:0] : txb_row[4:0]);
  assign luma_fetch_req_col_mi =
    txb_prefetch_first_luma ? block_col_mi :
    (txb_prefetch_luma_start ? next_txb_col[4:0] : txb_col[4:0]);
  assign chroma_fetch_current_storage_row_mi =
    (chroma_format_idc == 2'd1) ?
      (block_row_mi + (txb_local_row << 1)) :
      txb_row[4:0];
  assign chroma_fetch_current_storage_col_mi =
    (chroma_format_idc == 2'd1) ?
      (block_col_mi + (txb_local_col << 1)) :
      txb_col[4:0];
  assign chroma_fetch_next_storage_row_mi =
    (chroma_format_idc == 2'd1) ?
      (block_row_mi + (next_txb_local_row << 1)) :
      next_txb_row[4:0];
  assign chroma_fetch_next_storage_col_mi =
    (chroma_format_idc == 2'd1) ?
      (block_col_mi + (next_txb_local_col << 1)) :
      next_txb_col[4:0];
  assign chroma_fetch_req_row_mi =
    chroma_fetch_req_cross_phase ? block_row_mi :
    (chroma_fetch_req_next_txb ?
      chroma_fetch_next_storage_row_mi :
      chroma_fetch_current_storage_row_mi);
  assign chroma_fetch_req_col_mi =
    chroma_fetch_req_cross_phase ? block_col_mi :
    (chroma_fetch_req_next_txb ?
      chroma_fetch_next_storage_col_mi :
      chroma_fetch_current_storage_col_mi);
  assign chroma_fetch_req_plane_v =
    chroma_fetch_req_cross_phase ? phase_u_coeff : phase_v_coeff;

  assign chroma_left_source_index = txb_index[1:0] - 2'd1;
  assign chroma_above_source_index = txb_index[1:0] - current_txb_width[1:0];

endmodule
