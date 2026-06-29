`timescale 1ns/1ps

module ff_av2_encoder_context_controls (
  input  logic       state_input_read_w,
  input  logic       state_partition_w,
  input  logic       state_leaf_w,
  input  logic       state_output_valid_w,
  input  logic       state_idle_w,
  input  logic       start,
  input  logic       start_invalid_w,
  input  logic       tile_entropy_start_ready_w,
  input  logic       palette_analyzer_unsupported_w,
  input  logic       op_valid_w,
  input  logic [1:0] partition_q,
  input  logic       phase_intrabc_w,
  input  logic       phase_y_coeff_w,
  input  logic       phase_u_coeff_w,
  input  logic       phase_v_coeff_w,
  input  logic       partition_emit_do_split_w,
  input  logic       partition_need_rect_w,
  input  logic       m_axis_valid,
  input  logic       m_axis_ready,
  input  logic       output_last_q,
  input  logic       frame_is_last_w,
  input  logic [4:0] step_q,
  input  logic [1:0] ibc_drl_idx_w,
  input  logic       residual_mode_w,
  input  logic       luma_residual_txb_done_w,
  input  logic       chroma_bdpcm_txb_done_w,
  input  logic [15:0] txb_count_q,
  input  logic [15:0] txb_index_q,
  input  logic [7:0]  luma_residual_entropy_context_w,
  input  logic [7:0]  chroma_bdpcm_entropy_context_w,
  output logic        partition_context_clear_w,
  output logic        partition_context_update_w,
  output logic        txb_context_clear_w,
  output logic        txb_context_clear_leaf_w,
  output logic        txb_context_set_luma_w,
  output logic        txb_context_set_u_w,
  output logic        txb_context_set_v_w,
  output logic [7:0]  txb_context_luma_update_w,
  output logic [7:0]  txb_context_u_update_w,
  output logic [7:0]  txb_context_v_update_w,
  output logic        ibc_context_clear_w,
  output logic        ibc_context_set_leaf_w,
  output logic        ibc_context_clear_leaf_w
);
  localparam logic [1:0] PARTITION_NONE = 2'd0;

  assign partition_context_clear_w =
    state_input_read_w &&
    tile_entropy_start_ready_w &&
    !palette_analyzer_unsupported_w;

  assign partition_context_update_w =
    state_partition_w &&
    (partition_q == PARTITION_NONE) &&
    (!op_valid_w || !(partition_emit_do_split_w && partition_need_rect_w));

  assign txb_context_clear_w =
    (state_idle_w && start && !start_invalid_w) ||
    (state_input_read_w && tile_entropy_start_ready_w && !palette_analyzer_unsupported_w) ||
    (state_output_valid_w && m_axis_valid && m_axis_ready &&
     output_last_q && !frame_is_last_w);

  assign txb_context_clear_leaf_w =
    state_leaf_w &&
    op_valid_w &&
    phase_intrabc_w &&
    ((step_q == 5'd3 && ibc_drl_idx_w == 2'd0) ||
     (step_q == 5'd4 && ibc_drl_idx_w == 2'd1) ||
     (step_q == 5'd5));

  assign txb_context_set_luma_w =
    state_leaf_w &&
    phase_y_coeff_w &&
    residual_mode_w &&
    luma_residual_txb_done_w;
  assign txb_context_set_u_w =
    state_leaf_w &&
    phase_u_coeff_w &&
    residual_mode_w &&
    chroma_bdpcm_txb_done_w;
  assign txb_context_set_v_w =
    state_leaf_w &&
    phase_v_coeff_w &&
    residual_mode_w &&
    chroma_bdpcm_txb_done_w;

  assign txb_context_luma_update_w = luma_residual_entropy_context_w;
  assign txb_context_u_update_w = chroma_bdpcm_entropy_context_w;
  assign txb_context_v_update_w = chroma_bdpcm_entropy_context_w;

  assign ibc_context_clear_w =
    state_input_read_w &&
    tile_entropy_start_ready_w &&
    !palette_analyzer_unsupported_w;

  assign ibc_context_set_leaf_w =
    state_leaf_w &&
    op_valid_w &&
    phase_intrabc_w &&
    (((step_q == 5'd3) && (ibc_drl_idx_w == 2'd0)) ||
     ((step_q == 5'd4) && (ibc_drl_idx_w == 2'd1)) ||
     (step_q == 5'd5));

  assign ibc_context_clear_leaf_w =
    state_leaf_w &&
    op_valid_w &&
    phase_v_coeff_w &&
    (((residual_mode_w && chroma_bdpcm_txb_done_w) ||
      (!residual_mode_w && (step_q == 5'd7))) &&
     (txb_index_q == (txb_count_q - 16'd1)));

endmodule
