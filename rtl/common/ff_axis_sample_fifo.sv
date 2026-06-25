`timescale 1ns/1ps

module ff_axis_sample_fifo #(
  parameter int DATA_BITS = 8,
  parameter int DEPTH = 128
) (
  input  logic                 clk,
  input  logic                 rst_n,
  input  logic                 clear,

  input  logic                 s_axis_valid,
  output logic                 s_axis_ready,
  input  logic [DATA_BITS-1:0] s_axis_data,
  input  logic                 s_axis_last,

  output logic                 m_axis_valid,
  input  logic                 m_axis_ready,
  output logic [DATA_BITS-1:0] m_axis_data,
  output logic                 m_axis_last,
  output logic [$clog2(DEPTH + 1)-1:0] level
);
  localparam int PTR_BITS = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
  localparam int COUNT_BITS = $clog2(DEPTH + 1);

  logic [DATA_BITS-1:0] data_q [0:DEPTH-1];
  logic                 last_q [0:DEPTH-1];
  logic [PTR_BITS-1:0]  wr_ptr_q;
  logic [PTR_BITS-1:0]  rd_ptr_q;
  logic [COUNT_BITS-1:0] count_q;
  logic push_w;
  logic pop_w;
  logic stored_pop_w;
  logic stored_push_w;
  logic bypass_w;
  logic [PTR_BITS-1:0] wr_ptr_next_w;
  logic [PTR_BITS-1:0] rd_ptr_next_w;

  assign bypass_w = count_q == '0;
  assign m_axis_valid = (count_q != '0) || s_axis_valid;
  assign m_axis_data = bypass_w ? s_axis_data : data_q[rd_ptr_q];
  assign m_axis_last = bypass_w ? s_axis_last : last_q[rd_ptr_q];
  assign s_axis_ready = (count_q < COUNT_BITS'(DEPTH)) || pop_w;
  assign push_w = s_axis_valid && s_axis_ready;
  assign pop_w = m_axis_valid && m_axis_ready;
  assign stored_pop_w = pop_w && (count_q != '0);
  assign stored_push_w = push_w && !(bypass_w && pop_w);
  assign wr_ptr_next_w = (wr_ptr_q == PTR_BITS'(DEPTH - 1)) ? '0 : (wr_ptr_q + 1'b1);
  assign rd_ptr_next_w = (rd_ptr_q == PTR_BITS'(DEPTH - 1)) ? '0 : (rd_ptr_q + 1'b1);
  assign level = count_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr_q <= '0;
      rd_ptr_q <= '0;
      count_q <= '0;
    end else if (clear) begin
      wr_ptr_q <= '0;
      rd_ptr_q <= '0;
      count_q <= '0;
    end else begin
      if (stored_push_w) begin
        data_q[wr_ptr_q] <= s_axis_data;
        last_q[wr_ptr_q] <= s_axis_last;
        wr_ptr_q <= wr_ptr_next_w;
      end
      if (stored_pop_w) begin
        rd_ptr_q <= rd_ptr_next_w;
      end

      case ({stored_push_w, stored_pop_w})
        2'b10: count_q <= count_q + 1'b1;
        2'b01: count_q <= count_q - 1'b1;
        default: begin
        end
      endcase
    end
  end
endmodule
