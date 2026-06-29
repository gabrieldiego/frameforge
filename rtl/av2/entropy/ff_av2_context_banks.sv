`timescale 1ns/1ps

module ff_av2_context_banks #(
  parameter int CONTEXT_DIM = 16
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        partition_clear,
  input  logic        partition_update,
  input  logic [4:0]  block_row_mi,
  input  logic [4:0]  block_col_mi,
  input  logic [4:0]  block_w_mi,
  input  logic [4:0]  block_h_mi,
  input  logic [7:0]  partition_update_above,
  input  logic [7:0]  partition_update_left,
  output logic [7:0]  partition_selected_above,
  output logic [7:0]  partition_selected_left,

  input  logic        txb_clear,
  input  logic        txb_clear_leaf,
  input  logic        txb_set_luma,
  input  logic        txb_set_u,
  input  logic        txb_set_v,
  input  logic [4:0]  txb_row_mi,
  input  logic [4:0]  txb_col_mi,
  input  logic [7:0]  txb_luma_context,
  input  logic [7:0]  txb_u_context,
  input  logic [7:0]  txb_v_context,
  output logic [7:0]  txb_selected_luma_above,
  output logic [7:0]  txb_selected_luma_left,
  output logic [7:0]  txb_selected_u_above,
  output logic [7:0]  txb_selected_u_left,
  output logic [7:0]  txb_selected_v_above,
  output logic [7:0]  txb_selected_v_left,

  input  logic        ibc_clear,
  input  logic        ibc_set_leaf,
  input  logic        ibc_clear_leaf,
  output logic        ibc_selected_above,
  output logic        ibc_selected_left,
  output logic        ibc_selected_skip_above,
  output logic        ibc_selected_skip_left
);

  ff_av2_partition_context_bank #(
    .CONTEXT_DIM(CONTEXT_DIM)
  ) partition_context_bank (
    .clk(clk),
    .rst_n(rst_n),
    .clear(partition_clear),
    .update(partition_update),
    .block_row_mi(block_row_mi),
    .block_col_mi(block_col_mi),
    .block_w_mi(block_w_mi),
    .block_h_mi(block_h_mi),
    .update_above(partition_update_above),
    .update_left(partition_update_left),
    .selected_above(partition_selected_above),
    .selected_left(partition_selected_left)
  );

  ff_av2_txb_context_bank #(
    .CONTEXT_DIM(CONTEXT_DIM)
  ) txb_context_bank (
    .clk(clk),
    .rst_n(rst_n),
    .clear(txb_clear),
    .clear_leaf(txb_clear_leaf),
    .set_luma(txb_set_luma),
    .set_u(txb_set_u),
    .set_v(txb_set_v),
    .txb_row_mi(txb_row_mi),
    .txb_col_mi(txb_col_mi),
    .block_row_mi(block_row_mi),
    .block_col_mi(block_col_mi),
    .block_w_mi(block_w_mi),
    .block_h_mi(block_h_mi),
    .luma_context(txb_luma_context),
    .u_context(txb_u_context),
    .v_context(txb_v_context),
    .luma_above_context(txb_selected_luma_above),
    .luma_left_context(txb_selected_luma_left),
    .u_above_context(txb_selected_u_above),
    .u_left_context(txb_selected_u_left),
    .v_above_context(txb_selected_v_above),
    .v_left_context(txb_selected_v_left)
  );

  ff_av2_ibc_context_bank #(
    .CONTEXT_DIM(CONTEXT_DIM)
  ) ibc_context_bank (
    .clk(clk),
    .rst_n(rst_n),
    .clear(ibc_clear),
    .set_leaf(ibc_set_leaf),
    .clear_leaf(ibc_clear_leaf),
    .block_row_mi(block_row_mi),
    .block_col_mi(block_col_mi),
    .block_w_mi(block_w_mi),
    .block_h_mi(block_h_mi),
    .selected_ibc_above(ibc_selected_above),
    .selected_ibc_left(ibc_selected_left),
    .selected_skip_above(ibc_selected_skip_above),
    .selected_skip_left(ibc_selected_skip_left)
  );

endmodule
