`timescale 1ns/1ps

module ff_av2_encoder_seq_stream (
  input  logic [15:0] stream_lookup_index_w,
  input  logic [15:0] seq_end_index_w,
  input  logic [15:0] seq_stream_index_w,
  input  logic [7:0]  seq_mem_q [0:15],
  input  logic [6:0]  seq_bits_left_q,
  input  logic [15:0] seq_bit_pos_q,
  output logic [7:0]  seq_stream_byte_w,
  output logic [3:0]  seq_byte_remaining_w,
  output logic [3:0]  seq_write_step_w
);

  always_comb begin
    seq_stream_byte_w = 8'd0;
    if ((stream_lookup_index_w >= 16'd4) && (stream_lookup_index_w < seq_end_index_w)) begin
      seq_stream_byte_w = seq_mem_q[seq_stream_index_w];
    end
  end

  assign seq_byte_remaining_w =
    (seq_bit_pos_q[2:0] == 3'd0) ? 4'd8 :
      (4'd8 - {1'b0, seq_bit_pos_q[2:0]});

  assign seq_write_step_w =
    (seq_bits_left_q < {3'd0, seq_byte_remaining_w}) ?
      {1'b0, seq_bits_left_q[2:0]} : seq_byte_remaining_w;

endmodule
