`timescale 1ns/1ps

module ff_av2_txb_context_bank #(
  parameter int CONTEXT_DIM = 16
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        clear,
  input  logic        clear_leaf,
  input  logic        set_luma,
  input  logic        set_u,
  input  logic        set_v,
  input  logic [4:0]  txb_row_mi,
  input  logic [4:0]  txb_col_mi,
  input  logic [4:0]  block_row_mi,
  input  logic [4:0]  block_col_mi,
  input  logic [4:0]  block_w_mi,
  input  logic [4:0]  block_h_mi,
  input  logic [7:0]  luma_context,
  input  logic [7:0]  u_context,
  input  logic [7:0]  v_context,
  output logic [7:0]  luma_above_context,
  output logic [7:0]  luma_left_context,
  output logic [7:0]  u_above_context,
  output logic [7:0]  u_left_context,
  output logic [7:0]  v_above_context,
  output logic [7:0]  v_left_context
);

  logic [7:0] y_txb_above_q [0:CONTEXT_DIM - 1];
  logic [7:0] y_txb_left_q [0:CONTEXT_DIM - 1];
  logic [7:0] u_txb_above_q [0:CONTEXT_DIM - 1];
  logic [7:0] u_txb_left_q [0:CONTEXT_DIM - 1];
  logic [7:0] v_txb_above_q [0:CONTEXT_DIM - 1];
  logic [7:0] v_txb_left_q [0:CONTEXT_DIM - 1];
  integer txb_context_i;

  assign luma_above_context = y_txb_above_q[txb_col_mi];
  assign luma_left_context = y_txb_left_q[txb_row_mi];
  assign u_above_context = u_txb_above_q[txb_col_mi];
  assign u_left_context = u_txb_left_q[txb_row_mi];
  assign v_above_context = v_txb_above_q[txb_col_mi];
  assign v_left_context = v_txb_left_q[txb_row_mi];

  always_ff @(posedge clk) begin
    if (!rst_n || clear) begin
      for (txb_context_i = 0; txb_context_i < CONTEXT_DIM; txb_context_i = txb_context_i + 1) begin
        y_txb_above_q[txb_context_i] <= 8'd0;
        y_txb_left_q[txb_context_i] <= 8'd0;
        u_txb_above_q[txb_context_i] <= 8'd0;
        u_txb_left_q[txb_context_i] <= 8'd0;
        v_txb_above_q[txb_context_i] <= 8'd0;
        v_txb_left_q[txb_context_i] <= 8'd0;
      end
    end else begin
      if (clear_leaf) begin
        for (txb_context_i = 0; txb_context_i < CONTEXT_DIM; txb_context_i = txb_context_i + 1) begin
          if (txb_context_i >= block_col_mi && txb_context_i < (block_col_mi + block_w_mi)) begin
            y_txb_above_q[txb_context_i] <= 8'd0;
            u_txb_above_q[txb_context_i] <= 8'd0;
            v_txb_above_q[txb_context_i] <= 8'd0;
          end
          if (txb_context_i >= block_row_mi && txb_context_i < (block_row_mi + block_h_mi)) begin
            y_txb_left_q[txb_context_i] <= 8'd0;
            u_txb_left_q[txb_context_i] <= 8'd0;
            v_txb_left_q[txb_context_i] <= 8'd0;
          end
        end
      end

      if (set_luma) begin
        y_txb_above_q[txb_col_mi] <= luma_context;
        y_txb_left_q[txb_row_mi] <= luma_context;
      end
      if (set_u) begin
        u_txb_above_q[txb_col_mi] <= u_context;
        u_txb_left_q[txb_row_mi] <= u_context;
      end
      if (set_v) begin
        v_txb_above_q[txb_col_mi] <= v_context;
        v_txb_left_q[txb_row_mi] <= v_context;
      end
    end
  end

endmodule
