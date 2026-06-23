`timescale 1ns/1ps

module ff_axis_sample_packet_unpacker #(
  parameter int SAMPLE_BITS = 8,
  parameter int MAX_SAMPLES = 8
) (
  input  logic                               clk,
  input  logic                               rst_n,
  input  logic                               clear,

  input  logic                               s_axis_valid,
  output logic                               s_axis_ready,
  input  logic [MAX_SAMPLES*SAMPLE_BITS-1:0] s_axis_data,
  input  logic [3:0]                         s_axis_count,
  input  logic                               s_axis_last,

  output logic                               m_axis_valid,
  input  logic                               m_axis_ready,
  output logic [SAMPLE_BITS-1:0]             m_axis_data,
  output logic                               m_axis_last
);
  logic [MAX_SAMPLES*SAMPLE_BITS-1:0] packet_data_q;
  logic [3:0]                         packet_count_q;
  logic [3:0]                         packet_index_q;
  logic                               packet_last_q;
  logic                               valid_q;
  logic                               output_last_sample_w;
  logic                               pop_w;
  logic                               push_w;

  assign output_last_sample_w = (packet_index_q == (packet_count_q - 4'd1));
  assign m_axis_valid = valid_q;
  assign m_axis_data = packet_data_q[packet_index_q * SAMPLE_BITS +: SAMPLE_BITS];
  assign m_axis_last = packet_last_q && output_last_sample_w;
  assign pop_w = m_axis_valid && m_axis_ready;
  assign s_axis_ready = !valid_q || (pop_w && output_last_sample_w);
  assign push_w = s_axis_valid && s_axis_ready && (s_axis_count != 4'd0);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      packet_data_q <= '0;
      packet_count_q <= 4'd0;
      packet_index_q <= 4'd0;
      packet_last_q <= 1'b0;
      valid_q <= 1'b0;
    end else if (clear) begin
      packet_data_q <= '0;
      packet_count_q <= 4'd0;
      packet_index_q <= 4'd0;
      packet_last_q <= 1'b0;
      valid_q <= 1'b0;
    end else begin
      if (push_w) begin
        packet_data_q <= s_axis_data;
        packet_count_q <= s_axis_count;
        packet_index_q <= 4'd0;
        packet_last_q <= s_axis_last;
        valid_q <= 1'b1;
      end else if (pop_w) begin
        if (output_last_sample_w) begin
          valid_q <= 1'b0;
          packet_index_q <= 4'd0;
          packet_last_q <= 1'b0;
        end else begin
          packet_index_q <= packet_index_q + 4'd1;
        end
      end
    end
  end
endmodule
