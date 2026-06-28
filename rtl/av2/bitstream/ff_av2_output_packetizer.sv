`timescale 1ns/1ps

module ff_av2_output_packetizer #(
  parameter int OUTPUT_PACKET_COUNT_BITS = 5
) (
  input  logic        state_output_valid,
  input  logic        axis_valid,
  input  logic        axis_ready,
  input  logic        output_last,
  input  logic [15:0] stream_index,
  input  logic [OUTPUT_PACKET_COUNT_BITS - 1:0] axis_count,
  input  logic [3:0]  output_byte_phase,
  input  logic [15:0] tile_payload_start,
  input  logic [15:0] total_stream_len,
  input  logic        output_tile_payload,
  input  logic [7:0]  output_byte,
  input  logic [127:0] payload_read_data,
  output logic [15:0] stream_lookup_index,
  output logic [15:0] output_next_stream_index,
  output logic [15:0] output_payload_addr,
  output logic [11:0] output_next_payload_word_addr,
  output logic [11:0] output_after_current_payload_word_addr,
  output logic [11:0] output_after_next_payload_word_addr,
  output logic [3:0]  output_next_byte_phase,
  output logic        output_after_current_payload,
  output logic        output_after_next_payload,
  output logic [OUTPUT_PACKET_COUNT_BITS - 1:0] output_payload_count,
  output logic [OUTPUT_PACKET_COUNT_BITS - 1:0] output_next_payload_count,
  output logic [127:0] output_payload_packet_data,
  output logic [127:0] output_next_payload_packet_data,
  output logic        output_current_packet_last,
  output logic        output_next_packet_last,
  output logic [7:0]  output_lookup_byte,
  output logic        output_lookup_last
);

  logic [15:0] output_payload_remaining_w;
  logic [15:0] output_next_payload_addr_w;
  logic [15:0] output_next_payload_remaining_w;
  logic [15:0] output_after_current_stream_index_w;
  logic [15:0] output_after_next_stream_index_w;
  logic [15:0] output_after_current_payload_addr_w;
  logic [15:0] output_after_next_payload_addr_w;
  logic [OUTPUT_PACKET_COUNT_BITS - 1:0] output_packet_space_w;
  logic [OUTPUT_PACKET_COUNT_BITS - 1:0] output_payload_bank_space_w;
  logic [OUTPUT_PACKET_COUNT_BITS - 1:0] output_payload_word_space_w;
  logic [OUTPUT_PACKET_COUNT_BITS - 1:0] output_next_packet_space_w;
  logic [OUTPUT_PACKET_COUNT_BITS - 1:0] output_next_payload_bank_space_w;
  logic [OUTPUT_PACKET_COUNT_BITS - 1:0] output_next_payload_word_space_w;
  logic [127:0] output_payload_mask_w;
  logic [127:0] output_next_payload_mask_w;
  logic [127:0] output_payload_shifted_data_w;
  logic [127:0] output_next_payload_shifted_data_w;

  assign stream_lookup_index =
    (state_output_valid && axis_valid && axis_ready && !output_last) ?
      output_next_stream_index : stream_index;
  assign output_lookup_last = (stream_lookup_index == (total_stream_len - 16'd1));
  assign output_lookup_byte =
    output_tile_payload ?
      payload_read_data[{stream_lookup_index[3:0], 3'b000} +: 8] :
      output_byte;

  assign output_next_stream_index = stream_index + {11'd0, axis_count};
  assign output_payload_addr = stream_index - tile_payload_start;
  assign output_payload_remaining_w = total_stream_len - stream_index;
  assign output_next_payload_addr_w = output_next_stream_index - tile_payload_start;
  assign output_next_payload_remaining_w = total_stream_len - output_next_stream_index;
  assign output_next_payload_word_addr = output_next_payload_addr_w[15:4];
  assign output_after_current_stream_index_w =
    stream_index + {11'd0, output_payload_count};
  assign output_after_next_stream_index_w =
    output_next_stream_index + {11'd0, output_next_payload_count};
  assign output_after_current_payload_addr_w =
    output_after_current_stream_index_w - tile_payload_start;
  assign output_after_next_payload_addr_w =
    output_after_next_stream_index_w - tile_payload_start;
  assign output_after_current_payload_word_addr =
    output_after_current_payload_addr_w[15:4];
  assign output_after_next_payload_word_addr =
    output_after_next_payload_addr_w[15:4];
  assign output_next_byte_phase = output_byte_phase + axis_count[3:0];
  assign output_after_current_payload =
    (output_after_current_stream_index_w >= tile_payload_start) &&
    (output_after_current_stream_index_w < total_stream_len);
  assign output_after_next_payload =
    (output_after_next_stream_index_w >= tile_payload_start) &&
    (output_after_next_stream_index_w < total_stream_len);

  assign output_packet_space_w =
    (output_byte_phase == 4'd0) ?
      OUTPUT_PACKET_COUNT_BITS'(16) :
      (OUTPUT_PACKET_COUNT_BITS'(16) - {1'b0, output_byte_phase});
  assign output_payload_bank_space_w =
    (output_payload_addr[3:0] == 4'd0) ?
      OUTPUT_PACKET_COUNT_BITS'(16) :
      (OUTPUT_PACKET_COUNT_BITS'(16) - {1'b0, output_payload_addr[3:0]});
  assign output_payload_word_space_w =
    (output_packet_space_w < output_payload_bank_space_w) ?
      output_packet_space_w : output_payload_bank_space_w;
  assign output_payload_count =
    (output_payload_remaining_w > {11'd0, output_payload_word_space_w}) ?
      output_payload_word_space_w :
      output_payload_remaining_w[OUTPUT_PACKET_COUNT_BITS - 1:0];
  assign output_payload_shifted_data_w =
    payload_read_data >> ({3'd0, output_payload_addr[3:0]} << 3);
  assign output_payload_mask_w =
    (output_payload_count == OUTPUT_PACKET_COUNT_BITS'(0)) ?
      128'd0 :
      ((output_payload_count == OUTPUT_PACKET_COUNT_BITS'(16)) ?
        {128{1'b1}} :
        ({128{1'b1}} >> ((OUTPUT_PACKET_COUNT_BITS'(16) - output_payload_count) << 3)));
  assign output_payload_packet_data = output_payload_shifted_data_w & output_payload_mask_w;
  assign output_current_packet_last =
    ((stream_index + {11'd0, output_payload_count}) >= total_stream_len);

  assign output_next_packet_space_w =
    (output_next_byte_phase == 4'd0) ?
      OUTPUT_PACKET_COUNT_BITS'(16) :
      (OUTPUT_PACKET_COUNT_BITS'(16) - {1'b0, output_next_byte_phase});
  assign output_next_payload_bank_space_w =
    (output_next_payload_addr_w[3:0] == 4'd0) ?
      OUTPUT_PACKET_COUNT_BITS'(16) :
      (OUTPUT_PACKET_COUNT_BITS'(16) - {1'b0, output_next_payload_addr_w[3:0]});
  assign output_next_payload_word_space_w =
    (output_next_packet_space_w < output_next_payload_bank_space_w) ?
      output_next_packet_space_w : output_next_payload_bank_space_w;
  assign output_next_payload_count =
    (output_next_payload_remaining_w > {11'd0, output_next_payload_word_space_w}) ?
      output_next_payload_word_space_w :
      output_next_payload_remaining_w[OUTPUT_PACKET_COUNT_BITS - 1:0];
  assign output_next_payload_shifted_data_w =
    payload_read_data >> ({3'd0, output_next_payload_addr_w[3:0]} << 3);
  assign output_next_payload_mask_w =
    (output_next_payload_count == OUTPUT_PACKET_COUNT_BITS'(0)) ?
      128'd0 :
      ((output_next_payload_count == OUTPUT_PACKET_COUNT_BITS'(16)) ?
        {128{1'b1}} :
        ({128{1'b1}} >> ((OUTPUT_PACKET_COUNT_BITS'(16) - output_next_payload_count) << 3)));
  assign output_next_payload_packet_data =
    output_next_payload_shifted_data_w & output_next_payload_mask_w;
  assign output_next_packet_last =
    ((output_next_stream_index + {11'd0, output_next_payload_count}) >= total_stream_len);

endmodule
