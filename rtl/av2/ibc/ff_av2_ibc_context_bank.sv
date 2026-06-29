`timescale 1ns/1ps

module ff_av2_ibc_context_bank #(
  parameter int CONTEXT_DIM = 16
) (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       clear,
  input  logic       set_leaf,
  input  logic       clear_leaf,
  input  logic [4:0] block_row_mi,
  input  logic [4:0] block_col_mi,
  input  logic [4:0] block_w_mi,
  input  logic [4:0] block_h_mi,
  output logic       selected_ibc_above,
  output logic       selected_ibc_left,
  output logic       selected_skip_above,
  output logic       selected_skip_left
);

  logic ibc_above_q [0:CONTEXT_DIM - 1];
  logic ibc_left_q [0:CONTEXT_DIM - 1];
  logic skip_above_q [0:CONTEXT_DIM - 1];
  logic skip_left_q [0:CONTEXT_DIM - 1];
  integer context_i;

  assign selected_ibc_above = ibc_above_q[block_col_mi];
  assign selected_ibc_left = ibc_left_q[block_row_mi];
  assign selected_skip_above = skip_above_q[block_col_mi];
  assign selected_skip_left = skip_left_q[block_row_mi];

  always_ff @(posedge clk) begin
    if (!rst_n || clear) begin
      for (context_i = 0; context_i < CONTEXT_DIM; context_i = context_i + 1) begin
        ibc_above_q[context_i] <= 1'b0;
        ibc_left_q[context_i] <= 1'b0;
        skip_above_q[context_i] <= 1'b0;
        skip_left_q[context_i] <= 1'b0;
      end
    end else if (set_leaf || clear_leaf) begin
      for (context_i = 0; context_i < CONTEXT_DIM; context_i = context_i + 1) begin
        if (context_i >= block_col_mi && context_i < (block_col_mi + block_w_mi)) begin
          ibc_above_q[context_i] <= set_leaf;
          skip_above_q[context_i] <= set_leaf;
        end
        if (context_i >= block_row_mi && context_i < (block_row_mi + block_h_mi)) begin
          ibc_left_q[context_i] <= set_leaf;
          skip_left_q[context_i] <= set_leaf;
        end
      end
    end
  end

endmodule
