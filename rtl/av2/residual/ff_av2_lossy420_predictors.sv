`timescale 1ns/1ps

module ff_av2_lossy420_predictors (
  input  logic        phase_v_coeff,
  input  logic [4:0]  block_row_mi,
  input  logic [4:0]  block_col_mi,
  input  logic [15:0] txb_row,
  input  logic [15:0] txb_col,
  input  logic [15:0] txb_index,
  input  logic [7:0]  luma_recon0,
  input  logic [7:0]  luma_recon1,
  input  logic [7:0]  luma_recon2,
  input  logic [7:0]  luma_recon3,
  input  logic [7:0]  luma_above,
  input  logic        luma_above_valid,
  input  logic [7:0]  luma_left_top,
  input  logic [7:0]  luma_left_bottom,
  input  logic [4:0]  luma_left_col_mi,
  input  logic        luma_left_valid,
  input  logic [7:0]  u_above,
  input  logic [7:0]  v_above,
  input  logic        u_above_valid,
  input  logic        v_above_valid,
  input  logic [7:0]  u_left,
  input  logic [7:0]  v_left,
  input  logic [4:0]  u_left_col_mi,
  input  logic [4:0]  v_left_col_mi,
  input  logic        u_left_valid,
  input  logic        v_left_valid,
  output logic [3:0]  luma_left_row_index,
  output logic [3:0]  chroma_left_row_index,
  output logic [7:0]  luma_predictor,
  output logic [7:0]  chroma_predictor
);

  logic luma_external_left_valid_w;
  logic luma_have_left_w;
  logic luma_have_top_w;
  logic [7:0] luma_left_sample_w;
  logic [7:0] luma_top_sample_w;
  logic chroma_external_left_valid_w;
  logic chroma_have_left_w;
  logic chroma_have_top_w;
  logic [7:0] chroma_left_sample_w;
  logic [7:0] chroma_top_sample_w;

  assign luma_left_row_index = block_row_mi[3:0];
  assign luma_external_left_valid_w =
    luma_left_valid &&
    ((luma_left_col_mi + 5'd2) == block_col_mi);
  assign luma_have_left_w =
    (txb_col[4:0] != 5'd0) &&
    (txb_index[0] || luma_external_left_valid_w);
  assign luma_have_top_w =
    (txb_row[4:0] != 5'd0) &&
    (txb_index[1] || luma_above_valid);
  assign luma_left_sample_w =
    txb_index[0] ?
      (txb_index[1] ? luma_recon2 : luma_recon0) :
      (txb_index[1] ? luma_left_bottom : luma_left_top);
  assign luma_top_sample_w =
    txb_index[1] ?
      (txb_index[0] ? luma_recon1 : luma_recon0) :
      luma_above;
  assign luma_predictor =
    (luma_have_left_w && luma_have_top_w) ?
      (({1'b0, luma_left_sample_w} +
        {1'b0, luma_top_sample_w} + 9'd1) >> 1) :
    luma_have_left_w ? luma_left_sample_w :
    luma_have_top_w ? luma_top_sample_w :
      8'd128;

  assign chroma_left_row_index = txb_row[3:0];
  assign chroma_external_left_valid_w =
    phase_v_coeff ?
      (v_left_valid && ((v_left_col_mi + 5'd1) == txb_col[4:0])) :
      (u_left_valid && ((u_left_col_mi + 5'd1) == txb_col[4:0]));
  assign chroma_have_left_w =
    (txb_col[4:0] != 5'd0) &&
    chroma_external_left_valid_w;
  assign chroma_have_top_w =
    (txb_row[4:0] != 5'd0) &&
    (phase_v_coeff ? v_above_valid : u_above_valid);
  assign chroma_left_sample_w = phase_v_coeff ? v_left : u_left;
  assign chroma_top_sample_w = phase_v_coeff ? v_above : u_above;
  assign chroma_predictor =
    (chroma_have_left_w && chroma_have_top_w) ?
      (({1'b0, chroma_left_sample_w} +
        {1'b0, chroma_top_sample_w} + 9'd1) >> 1) :
    chroma_have_left_w ? chroma_left_sample_w :
    chroma_have_top_w ? chroma_top_sample_w :
      8'd128;

endmodule
