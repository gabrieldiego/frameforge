`timescale 1ns/1ps

module ff_av2_encoder_ibc_controls #(
  parameter int SAMPLE_BITS = 8
) (
  input  logic [4:0]  block_row_mi_q,
  input  logic [4:0]  block_col_mi_q,
  input  logic [63:0] palette_analyzer_block_ready_mask_w,
  input  logic        palette_analyzer_done_w,
  input  logic        frame_ibc_mode_q,
  input  logic [63:0] ibc_ready_mask_w,
  input  logic        ibc_done_w,
  input  logic [4:0]  block_w_mi_q,
  input  logic [4:0]  block_h_mi_q,
  input  logic [63:0] ibc_copy_mask_w,
  input  logic [127:0] ibc_drl_idx_table_w,
  input  logic        ibc_above_ctx_w,
  input  logic        ibc_left_ctx_w,
  input  logic        skip_above_ctx_w,
  input  logic        skip_left_ctx_w,
  output logic        s_axis_valid,
  output logic [SAMPLE_BITS - 1:0] s_axis_data,
  output logic        s_axis_last,
  output logic        s_axis_ready,
  output logic [5:0]  ibc_current_block_id_w,
  output logic [5:0]  current_leaf_block_id_w,
  output logic        current_leaf_ready_w,
  output logic [6:0]  ibc_drl_idx_bit_index_w,
  output logic        ibc_use_copy_w,
  output logic [1:0]  ibc_drl_idx_w,
  output logic [1:0]  intrabc_ctx_w,
  output logic [1:0]  intrabc_skip_ctx_w
);

  assign s_axis_valid = 1'b0;
  assign s_axis_data = '0;
  assign s_axis_last = 1'b0;
  assign s_axis_ready = 1'b0;

  assign ibc_current_block_id_w = {block_row_mi_q[3:1], block_col_mi_q[3:1]};
  assign current_leaf_block_id_w = ibc_current_block_id_w;

  assign current_leaf_ready_w =
    (palette_analyzer_block_ready_mask_w[current_leaf_block_id_w] ||
     palette_analyzer_done_w) &&
    (!frame_ibc_mode_q ||
     ibc_ready_mask_w[current_leaf_block_id_w] ||
     ibc_done_w);

  assign ibc_drl_idx_bit_index_w = {ibc_current_block_id_w, 1'b0};
  assign ibc_use_copy_w =
    frame_ibc_mode_q &&
    (block_w_mi_q == 5'd2) &&
    (block_h_mi_q == 5'd2) &&
    ibc_copy_mask_w[ibc_current_block_id_w];

  assign ibc_drl_idx_w = ibc_drl_idx_table_w[ibc_drl_idx_bit_index_w +: 2];

  assign intrabc_ctx_w =
    {1'b0, ibc_above_ctx_w} + {1'b0, ibc_left_ctx_w};

  assign intrabc_skip_ctx_w =
    {1'b0, skip_above_ctx_w} + {1'b0, skip_left_ctx_w};

endmodule
