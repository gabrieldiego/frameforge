`timescale 1ns/1ps

module ff_av2_partition_context_bank #(
  parameter int CONTEXT_DIM = 16
) (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       clear,
  input  logic       update,
  input  logic [4:0] block_row_mi,
  input  logic [4:0] block_col_mi,
  input  logic [4:0] block_w_mi,
  input  logic [4:0] block_h_mi,
  input  logic [7:0] update_above,
  input  logic [7:0] update_left,
  output logic [7:0] selected_above,
  output logic [7:0] selected_left
);

  logic [7:0] above_q [0:CONTEXT_DIM - 1];
  logic [7:0] left_q [0:CONTEXT_DIM - 1];
  integer context_i;

  assign selected_above = above_q[block_col_mi];
  assign selected_left = left_q[block_row_mi];

  always_ff @(posedge clk) begin
    if (!rst_n || clear) begin
      for (context_i = 0; context_i < CONTEXT_DIM; context_i = context_i + 1) begin
        above_q[context_i] <= 8'd0;
        left_q[context_i] <= 8'd0;
      end
    end else if (update) begin
      for (context_i = 0; context_i < CONTEXT_DIM; context_i = context_i + 1) begin
        if (context_i >= block_col_mi && context_i < (block_col_mi + block_w_mi)) begin
          above_q[context_i] <= update_above;
        end
        if (context_i >= block_row_mi && context_i < (block_row_mi + block_h_mi)) begin
          left_q[context_i] <= update_left;
        end
      end
    end
  end

endmodule
