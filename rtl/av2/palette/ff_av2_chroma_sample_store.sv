`timescale 1ns/1ps

(* keep_hierarchy = "yes" *)
module ff_av2_chroma_sample_store (
  input  logic        clk,
  input  logic        row_write_y_en,
  input  logic        row_write_u_en,
  input  logic        row_write_v_en,
  input  logic [8:0]  row_write_addr,
  input  logic [63:0] row_write_data,
  input  logic [11:0] read_addr,
  output logic [7:0]  read_y_data,
  output logic [7:0]  read_u_data,
  output logic [7:0]  read_v_data,
  output logic [63:0] read_y_row_data,
  output logic [63:0] read_u_row_data,
  output logic [63:0] read_v_row_data
);

  logic [63:0] y_mem_q [0:511];
  logic [63:0] u_mem_q [0:511];
  logic [63:0] v_mem_q [0:511];
  logic [63:0] y_read_word_q;
  logic [63:0] u_read_word_q;
  logic [63:0] v_read_word_q;
  logic [2:0]  read_col_q;
  logic [8:0]  read_word_addr_w;

  assign read_word_addr_w = read_addr[11:3];

  always_ff @(posedge clk) begin
    if (row_write_y_en) begin
      y_mem_q[row_write_addr] <= row_write_data;
    end
    if (row_write_u_en) begin
      u_mem_q[row_write_addr] <= row_write_data;
    end
    if (row_write_v_en) begin
      v_mem_q[row_write_addr] <= row_write_data;
    end
    y_read_word_q <= y_mem_q[read_word_addr_w];
    u_read_word_q <= u_mem_q[read_word_addr_w];
    v_read_word_q <= v_mem_q[read_word_addr_w];
    read_col_q <= read_addr[2:0];
  end

  assign read_y_data = y_read_word_q[{read_col_q, 3'b000} +: 8];
  assign read_u_data = u_read_word_q[{read_col_q, 3'b000} +: 8];
  assign read_v_data = v_read_word_q[{read_col_q, 3'b000} +: 8];
  assign read_y_row_data = y_read_word_q;
  assign read_u_row_data = u_read_word_q;
  assign read_v_row_data = v_read_word_q;

endmodule
