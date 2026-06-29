`timescale 1ns/1ps

module ff_av2_residual_contexts (
  input  logic        phase_v_coeff,
  input  logic [1:0]  chroma_format_idc,
  input  logic [7:0]  luma_above_context,
  input  logic [7:0]  luma_left_context,
  input  logic [7:0]  u_above_context,
  input  logic [7:0]  u_left_context,
  input  logic [7:0]  v_above_context,
  input  logic [7:0]  v_left_context,
  input  logic        last_u_txb_nonzero,
  input  logic [15:0] txb_row,
  input  logic [15:0] txb_col,
  output logic [3:0]  luma_skip_ctx,
  output logic [1:0]  luma_dc_sign_ctx,
  output logic [3:0]  chroma_bdpcm_skip_ctx,
  output logic [31:0] y_txb_nonzero_fh,
  output logic [31:0] u_txb_nonzero_fh,
  output logic [31:0] v_txb_nonzero_fh,
  output logic [31:0] y_dc_sign_fl
);

  logic [2:0] luma_top_level_w;
  logic [2:0] luma_left_level_w;
  logic signed [3:0] luma_top_sign_w;
  logic signed [3:0] luma_left_sign_w;
  logic signed [5:0] luma_sign_sum_w;

  assign luma_top_level_w =
    ((luma_above_context & 8'd7) > 8'd4) ? 3'd4 : luma_above_context[2:0];
  assign luma_left_level_w =
    ((luma_left_context & 8'd7) > 8'd4) ? 3'd4 : luma_left_context[2:0];
  assign luma_skip_ctx =
    (luma_top_level_w == 3'd0 && luma_left_level_w == 3'd0) ? 4'd1 :
    ((luma_top_level_w == 3'd0 && luma_left_level_w <= 3'd2) ||
     (luma_left_level_w == 3'd0 && luma_top_level_w <= 3'd2) ||
     (luma_top_level_w == 3'd1 && luma_left_level_w == 3'd1)) ? 4'd2 :
    ((luma_top_level_w == 3'd0) ||
     (luma_left_level_w == 3'd0) ||
     (luma_top_level_w == 3'd1 && luma_left_level_w >= 3'd2 && luma_left_level_w <= 3'd3) ||
     (luma_left_level_w == 3'd1 && luma_top_level_w >= 3'd2 && luma_top_level_w <= 3'd3) ||
     (luma_top_level_w == 3'd2 && luma_left_level_w == 3'd2)) ? 4'd3 :
    (((luma_top_level_w >= 3'd1 && luma_top_level_w <= 3'd2) && luma_left_level_w == 3'd4) ||
     ((luma_left_level_w >= 3'd1 && luma_left_level_w <= 3'd2) && luma_top_level_w == 3'd4) ||
     ((luma_top_level_w >= 3'd2 && luma_top_level_w <= 3'd3) &&
      (luma_left_level_w >= 3'd2 && luma_left_level_w <= 3'd3))) ? 4'd4 : 4'd5;

  assign luma_top_sign_w =
    (luma_above_context[4:3] == 2'd1) ? -4'sd1 :
    (luma_above_context[4:3] == 2'd2) ? 4'sd1 : 4'sd0;
  assign luma_left_sign_w =
    (luma_left_context[4:3] == 2'd1) ? -4'sd1 :
    (luma_left_context[4:3] == 2'd2) ? 4'sd1 : 4'sd0;
  assign luma_sign_sum_w = luma_top_sign_w + luma_left_sign_w;
  assign luma_dc_sign_ctx =
    (luma_sign_sum_w < 0) ? 2'd1 :
    (luma_sign_sum_w > 0) ? 2'd2 : 2'd0;

  assign chroma_bdpcm_skip_ctx =
    phase_v_coeff ?
      (((chroma_format_idc == 2'd1) ? 4'd0 : 4'd3) +
       {3'd0, v_above_context != 8'd0} +
       {3'd0, v_left_context != 8'd0} +
       (last_u_txb_nonzero ? 4'd6 : 4'd0)) :
      (4'd6 +
       {3'd0, u_above_context != 8'd0} +
       {3'd0, u_left_context != 8'd0});

  always @* begin
    if (txb_row == 16'd0 && txb_col == 16'd0) begin
      y_txb_nonzero_fh = 32'd31669;
      u_txb_nonzero_fh = 32'd23870;
      // AV2 v1.0.0 read_tx_block()/get_txb_ctx(): V TXB skip contexts use
      // the retained U-plane EOB flag. 4:4:4 adds the chroma-block-larger-
      // than-TXB offset, landing on ctx9..11 here; 4:2:0 chroma is exactly
      // one 4x4 TXB per 8x8 luma block, landing on ctx6..8 instead.
      v_txb_nonzero_fh = (chroma_format_idc == 2'd1) ? 32'd25120 : 32'd16384;
      y_dc_sign_fl = 32'd16937;
    end else if (txb_row == 16'd0 || txb_col == 16'd0) begin
      y_txb_nonzero_fh = 32'd24824;
      u_txb_nonzero_fh = 32'd19113;
      v_txb_nonzero_fh = (chroma_format_idc == 2'd1) ? 32'd16620 : 32'd16384;
      y_dc_sign_fl = 32'd19136;
    end else begin
      y_txb_nonzero_fh = 32'd3692;
      u_txb_nonzero_fh = 32'd10420;
      v_txb_nonzero_fh = (chroma_format_idc == 2'd1) ? 32'd8203 : 32'd16384;
      y_dc_sign_fl = 32'd19136;
    end
  end

endmodule
