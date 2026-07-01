`timescale 1ns/1ps

// AV2 v1.0.0 Sections 5.20.5 and 5.20.8: centralizes the MVP leaf prediction
// policy. IntraBC copy leaves bypass intra/palette/residual syntax; non-copy
// leaves use the analyzer-selected luma intra mode and chroma BDPCM direction.
module ff_av2_prediction_decision (
  input  logic        palette_mode,
  input  logic        lossy_420_mode,
  input  logic        ibc_use_copy,
  input  logic [1:0]  ibc_drl_idx,
  input  logic [1:0]  current_leaf_luma_mode,
  input  logic [1:0]  analyzed_luma_mode,
  input  logic        analyzed_chroma_bdpcm_horz,
  output logic        selected_ibc_use_copy,
  output logic [1:0]  selected_ibc_drl_idx,
  output logic [1:0]  selected_leaf_luma_mode,
  output logic        selected_leaf_chroma_bdpcm_horz,
  output logic        leaf_luma_palette,
  output logic        residual_mode
);

  localparam logic [1:0] LUMA_MODE_DC = 2'd0;

  assign selected_ibc_use_copy = ibc_use_copy;
  assign selected_ibc_drl_idx = ibc_drl_idx;

  assign selected_leaf_luma_mode =
    palette_mode ? analyzed_luma_mode : LUMA_MODE_DC;
  assign selected_leaf_chroma_bdpcm_horz =
    palette_mode ? analyzed_chroma_bdpcm_horz : 1'b1;

  assign leaf_luma_palette =
    palette_mode && (current_leaf_luma_mode == LUMA_MODE_DC);
  assign residual_mode = palette_mode || lossy_420_mode;

endmodule
