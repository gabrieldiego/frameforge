`timescale 1ns/1ps

module ff_av2_chroma_predictor_cache (
  input  logic        lossy_420_mode,
  input  logic        phase_u_coeff,
  input  logic        phase_v_coeff,
  input  logic [15:0] txb_row,
  input  logic [15:0] txb_col,
  input  logic [15:0] txb_index,
  input  logic [1:0]  chroma_left_source_index,
  input  logic [1:0]  chroma_above_source_index,
  input  logic        chroma_predictor_compute_valid,
  input  logic        chroma_external_left_predictor_valid,
  input  logic        chroma_external_above_predictor_valid,
  input  logic [3:0]  cached_chroma_samples_valid,
  input  logic [3:0]  cached_v_valid,
  input  logic [127:0] cached_u_txb_samples0,
  input  logic [127:0] cached_u_txb_samples1,
  input  logic [127:0] cached_u_txb_samples2,
  input  logic [127:0] cached_u_txb_samples3,
  input  logic [127:0] cached_v_txb_samples0,
  input  logic [127:0] cached_v_txb_samples1,
  input  logic [127:0] cached_v_txb_samples2,
  input  logic [127:0] cached_v_txb_samples3,
  input  logic [31:0] cached_v_predictor_samples0,
  input  logic [31:0] cached_v_predictor_samples1,
  input  logic [31:0] cached_v_predictor_samples2,
  input  logic [31:0] cached_v_predictor_samples3,
  input  logic [31:0] left_edge_u_top,
  input  logic [31:0] left_edge_u_bottom,
  input  logic [31:0] left_edge_v_top,
  input  logic [31:0] left_edge_v_bottom,
  input  logic [31:0] above_col0_u,
  input  logic [31:0] above_col0_v,
  input  logic [127:0] chroma_fetch_txb_samples,
  input  logic [31:0] chroma_fetch_predictor_samples,
  output logic [31:0] chroma_cached_predictor_samples,
  output logic [31:0] current_u_right_edge_top,
  output logic [31:0] current_u_right_edge_bottom,
  output logic [31:0] current_v_right_edge_top,
  output logic [31:0] current_v_right_edge_bottom,
  output logic [31:0] current_u_col0_above_edge,
  output logic [31:0] current_v_col0_above_edge,
  output logic [127:0] chroma_bdpcm_txb_samples,
  output logic [31:0] chroma_bdpcm_predictor_samples
);

  logic [127:0] cached_u_left_txb_w;
  logic [127:0] cached_v_left_txb_w;
  logic [127:0] cached_u_above_txb_w;
  logic [127:0] cached_v_above_txb_w;
  logic [127:0] cached_u_current_txb_w;
  logic [127:0] cached_v_current_txb_w;
  logic [31:0] cached_v_current_predictor_w;
  logic [31:0] cached_u_left_predictor_w;
  logic [31:0] cached_v_left_predictor_w;
  logic [31:0] cached_u_above_predictor_w;
  logic [31:0] cached_v_above_predictor_w;
  logic [31:0] cached_u_external_left_predictor_w;
  logic [31:0] cached_v_external_left_predictor_w;

  assign cached_u_left_txb_w =
    (chroma_left_source_index == 2'd0) ? cached_u_txb_samples0 :
    (chroma_left_source_index == 2'd1) ? cached_u_txb_samples1 :
    (chroma_left_source_index == 2'd2) ? cached_u_txb_samples2 :
      cached_u_txb_samples3;
  assign cached_v_left_txb_w =
    (chroma_left_source_index == 2'd0) ? cached_v_txb_samples0 :
    (chroma_left_source_index == 2'd1) ? cached_v_txb_samples1 :
    (chroma_left_source_index == 2'd2) ? cached_v_txb_samples2 :
      cached_v_txb_samples3;
  assign cached_u_above_txb_w =
    (chroma_above_source_index == 2'd0) ? cached_u_txb_samples0 :
    (chroma_above_source_index == 2'd1) ? cached_u_txb_samples1 :
    (chroma_above_source_index == 2'd2) ? cached_u_txb_samples2 :
      cached_u_txb_samples3;
  assign cached_v_above_txb_w =
    (chroma_above_source_index == 2'd0) ? cached_v_txb_samples0 :
    (chroma_above_source_index == 2'd1) ? cached_v_txb_samples1 :
    (chroma_above_source_index == 2'd2) ? cached_v_txb_samples2 :
      cached_v_txb_samples3;
  assign cached_u_current_txb_w =
    (txb_index[1:0] == 2'd0) ? cached_u_txb_samples0 :
    (txb_index[1:0] == 2'd1) ? cached_u_txb_samples1 :
    (txb_index[1:0] == 2'd2) ? cached_u_txb_samples2 :
      cached_u_txb_samples3;
  assign cached_v_current_txb_w =
    (txb_index[1:0] == 2'd0) ? cached_v_txb_samples0 :
    (txb_index[1:0] == 2'd1) ? cached_v_txb_samples1 :
    (txb_index[1:0] == 2'd2) ? cached_v_txb_samples2 :
      cached_v_txb_samples3;
  assign cached_v_current_predictor_w =
    (txb_index[1:0] == 2'd0) ? cached_v_predictor_samples0 :
    (txb_index[1:0] == 2'd1) ? cached_v_predictor_samples1 :
    (txb_index[1:0] == 2'd2) ? cached_v_predictor_samples2 :
      cached_v_predictor_samples3;

  assign cached_u_left_predictor_w = {
    cached_u_left_txb_w[15 * 8 +: 8],
    cached_u_left_txb_w[11 * 8 +: 8],
    cached_u_left_txb_w[7 * 8 +: 8],
    cached_u_left_txb_w[3 * 8 +: 8]
  };
  assign cached_v_left_predictor_w = {
    cached_v_left_txb_w[15 * 8 +: 8],
    cached_v_left_txb_w[11 * 8 +: 8],
    cached_v_left_txb_w[7 * 8 +: 8],
    cached_v_left_txb_w[3 * 8 +: 8]
  };
  assign cached_u_above_predictor_w = {
    cached_u_above_txb_w[12 * 8 +: 8],
    cached_u_above_txb_w[12 * 8 +: 8],
    cached_u_above_txb_w[12 * 8 +: 8],
    cached_u_above_txb_w[12 * 8 +: 8]
  };
  assign cached_v_above_predictor_w = {
    cached_v_above_txb_w[12 * 8 +: 8],
    cached_v_above_txb_w[12 * 8 +: 8],
    cached_v_above_txb_w[12 * 8 +: 8],
    cached_v_above_txb_w[12 * 8 +: 8]
  };
  assign cached_u_external_left_predictor_w = txb_row[0] ? left_edge_u_bottom : left_edge_u_top;
  assign cached_v_external_left_predictor_w = txb_row[0] ? left_edge_v_bottom : left_edge_v_top;
  assign chroma_cached_predictor_samples =
    ((txb_row[4:0] == 5'd0) && (txb_col[4:0] == 5'd0)) ? 32'h81818181 :
    txb_col[0] ?
      (phase_v_coeff ? cached_v_left_predictor_w : cached_u_left_predictor_w) :
    chroma_external_left_predictor_valid ?
      (phase_v_coeff ? cached_v_external_left_predictor_w : cached_u_external_left_predictor_w) :
    chroma_external_above_predictor_valid ?
      (phase_v_coeff ? above_col0_v : above_col0_u) :
      (phase_v_coeff ? cached_v_above_predictor_w : cached_u_above_predictor_w);

  assign current_u_right_edge_top = {
    cached_u_txb_samples1[15 * 8 +: 8],
    cached_u_txb_samples1[11 * 8 +: 8],
    cached_u_txb_samples1[7 * 8 +: 8],
    cached_u_txb_samples1[3 * 8 +: 8]
  };
  assign current_u_right_edge_bottom = {
    cached_u_txb_samples3[15 * 8 +: 8],
    cached_u_txb_samples3[11 * 8 +: 8],
    cached_u_txb_samples3[7 * 8 +: 8],
    cached_u_txb_samples3[3 * 8 +: 8]
  };
  assign current_v_right_edge_top = {
    cached_v_txb_samples1[15 * 8 +: 8],
    cached_v_txb_samples1[11 * 8 +: 8],
    cached_v_txb_samples1[7 * 8 +: 8],
    cached_v_txb_samples1[3 * 8 +: 8]
  };
  assign current_v_right_edge_bottom = {
    cached_v_txb_samples3[15 * 8 +: 8],
    cached_v_txb_samples3[11 * 8 +: 8],
    cached_v_txb_samples3[7 * 8 +: 8],
    cached_v_txb_samples3[3 * 8 +: 8]
  };
  assign current_u_col0_above_edge = {
    cached_u_txb_samples2[12 * 8 +: 8],
    cached_u_txb_samples2[12 * 8 +: 8],
    cached_u_txb_samples2[12 * 8 +: 8],
    cached_u_txb_samples2[12 * 8 +: 8]
  };
  assign current_v_col0_above_edge = {
    cached_v_txb_samples2[12 * 8 +: 8],
    cached_v_txb_samples2[12 * 8 +: 8],
    cached_v_txb_samples2[12 * 8 +: 8],
    cached_v_txb_samples2[12 * 8 +: 8]
  };

  assign chroma_bdpcm_txb_samples =
    lossy_420_mode ? chroma_fetch_txb_samples :
    (phase_v_coeff && cached_chroma_samples_valid[txb_index[1:0]]) ?
      cached_v_current_txb_w :
    (phase_u_coeff && cached_chroma_samples_valid[txb_index[1:0]]) ?
      cached_u_current_txb_w :
      chroma_fetch_txb_samples;
  assign chroma_bdpcm_predictor_samples =
    (phase_v_coeff && cached_v_valid[txb_index[1:0]]) ?
      cached_v_current_predictor_w :
    chroma_predictor_compute_valid ?
      chroma_cached_predictor_samples :
      chroma_fetch_predictor_samples;

endmodule
