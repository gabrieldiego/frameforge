`timescale 1ns/1ps

module ff_vvc_byte_queue #(
  parameter int QUEUE_BYTES = 8,
  parameter int QUEUE_BITS = QUEUE_BYTES * 8
) (
  input  logic                         clk,
  input  logic                         rst_n,
  input  logic                         clear,

  input  logic                         load_valid,
  output logic                         load_ready,
  input  logic [3:0]                   load_count,
  input  logic [QUEUE_BITS - 1:0]      load_bytes,
  input  logic                         load_last,

  input  logic                         m_axis_ready,
  output logic                         m_axis_valid,
  output logic [7:0]                   m_axis_data,
  output logic                         m_axis_last,
  output logic                         idle,
  output logic                         last_accepted
);
  logic [3:0] queue_count_q;
  logic [QUEUE_BITS - 1:0] queue_bytes_q;
  logic queue_last_q;

  assign load_ready = queue_count_q == 4'd0;
  assign m_axis_valid = queue_count_q != 4'd0;
  assign m_axis_data = queue_bytes_q[7:0];
  assign m_axis_last = queue_last_q && (queue_count_q == 4'd1);
  assign idle = queue_count_q == 4'd0;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      queue_count_q <= 4'd0;
      queue_bytes_q <= '0;
      queue_last_q <= 1'b0;
      last_accepted <= 1'b0;
    end else if (clear) begin
      queue_count_q <= 4'd0;
      queue_bytes_q <= '0;
      queue_last_q <= 1'b0;
      last_accepted <= 1'b0;
    end else begin
      last_accepted <= 1'b0;

      if (m_axis_valid && m_axis_ready) begin
        last_accepted <= m_axis_last;
        queue_bytes_q <= queue_bytes_q >> 8;
        queue_count_q <= queue_count_q - 4'd1;
        if (queue_count_q == 4'd1) begin
          queue_last_q <= 1'b0;
        end
      end

      if (load_valid && load_ready) begin
        queue_bytes_q <= load_bytes;
        queue_count_q <= load_count;
        queue_last_q <= load_last;
      end
    end
  end
endmodule
