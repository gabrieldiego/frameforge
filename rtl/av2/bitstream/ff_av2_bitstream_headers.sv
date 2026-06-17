`timescale 1ns/1ps

module ff_av2_bitstream_headers (
  input  logic [15:0] width,
  input  logic [15:0] height,
  input  logic [4:0]  width_bits,
  input  logic [4:0]  height_bits,
  input  logic [7:0]  seq_op,
  input  logic [15:0] seq_bit_pos,
  input  logic        frame_palette_mode,
  input  logic        frame_ibc_mode,
  input  logic [15:0] tile_cols,
  input  logic [15:0] tile_rows,
  input  logic        multi_tile,
  input  logic [15:0] tile_len,
  input  logic [1:0]  payload_prefix_index,
  input  logic [15:0] seq_len,
  input  logic [15:0] payload_len,
  input  logic [15:0] stream_index,
  input  logic [7:0]  seq_stream_byte,
  output logic [63:0] seq_load_value,
  output logic [6:0]  seq_load_bits,
  output logic [7:0]  payload_prefix_byte,
  output logic [3:0]  closed_header_len,
  output logic [15:0] closed_len,
  output logic [1:0]  closed_leb_len,
  output logic [15:0] seq_end_index,
  output logic [15:0] closed_leb_start,
  output logic [15:0] closed_header_start,
  output logic [15:0] total_stream_len,
  output logic [15:0] tile_payload_start,
  output logic [15:0] seq_stream_index,
  output logic [15:0] closed_leb_index,
  output logic [15:0] tile_stream_index,
  output logic        output_tile_payload,
  output logic [7:0]  output_byte
);

  localparam int AV2_MAX_CLOSED_HEADER_BYTES = 8;

  logic [15:0] payload_prefix_value_w;
  logic [2:0] tile_log2_cols_w;
  logic [2:0] tile_log2_rows_w;
  logic [63:0] closed_header_bits_w;
  logic [7:0] closed_header_byte_w;
  logic [15:0] closed_header_payload_index_w;
  logic [2:0] closed_header_index_w;
  integer closed_bit_index_w;
  integer closed_loop_index_w;

  always @* begin
    seq_load_value = 64'd0;
    seq_load_bits = 7'd0;
    case (seq_op)
      8'd0: begin seq_load_value = 64'd1; seq_load_bits = 7'd1; end
      8'd1: begin seq_load_value = 64'd4; seq_load_bits = 7'd5; end
      8'd2: begin seq_load_value = 64'd1; seq_load_bits = 7'd1; end
      8'd3: begin seq_load_value = 64'd0; seq_load_bits = 7'd5; end
      8'd4: begin seq_load_value = 64'd3; seq_load_bits = 7'd3; end
      8'd5: begin seq_load_value = 64'd2; seq_load_bits = 7'd3; end
      8'd6: begin seq_load_value = {60'd0, width_bits[3:0] - 4'd1}; seq_load_bits = 7'd4; end
      8'd7: begin seq_load_value = {60'd0, height_bits[3:0] - 4'd1}; seq_load_bits = 7'd4; end
      8'd8: begin seq_load_value = {48'd0, width - 16'd1}; seq_load_bits = {2'd0, width_bits}; end
      8'd9: begin seq_load_value = {48'd0, height - 16'd1}; seq_load_bits = {2'd0, height_bits}; end
      8'd10: begin seq_load_value = 64'd0; seq_load_bits = 7'd6; end
      8'd11: begin seq_load_value = 64'd0; seq_load_bits = 7'd2; end
      8'd12: begin seq_load_value = 64'd0; seq_load_bits = 7'd8; end
      8'd13: begin
        if (frame_ibc_mode) begin
          seq_load_value = 64'd28;
          seq_load_bits = 7'd6;
        end else begin
          seq_load_value = 64'd8;
          seq_load_bits = 7'd5;
        end
      end
      8'd14: begin seq_load_value = 64'd32878; seq_load_bits = 7'd17; end
      8'd15: begin seq_load_value = 64'd1; seq_load_bits = 7'd7; end
      8'd16: begin seq_load_value = 64'd0; seq_load_bits = 7'd3; end
      8'd17: begin
        if (seq_bit_pos[2:0] == 3'd0) begin
          seq_load_value = 64'h80;
          seq_load_bits = 7'd8;
        end else begin
          seq_load_bits = 7'd8 - {4'd0, seq_bit_pos[2:0]};
          seq_load_value = 64'd1 << (seq_load_bits - 7'd1);
        end
      end
      default: begin seq_load_value = 64'd0; seq_load_bits = 7'd0; end
    endcase
  end

  always @* begin
    tile_log2_cols_w = 3'd0;
    if (tile_cols > 16'd1) tile_log2_cols_w = 3'd1;
    if (tile_cols > 16'd2) tile_log2_cols_w = 3'd2;
    if (tile_cols > 16'd4) tile_log2_cols_w = 3'd3;
    if (tile_cols > 16'd8) tile_log2_cols_w = 3'd4;
    if (tile_cols > 16'd16) tile_log2_cols_w = 3'd5;
    if (tile_cols > 16'd32) tile_log2_cols_w = 3'd6;

    tile_log2_rows_w = 3'd0;
    if (tile_rows > 16'd1) tile_log2_rows_w = 3'd1;
    if (tile_rows > 16'd2) tile_log2_rows_w = 3'd2;
    if (tile_rows > 16'd4) tile_log2_rows_w = 3'd3;
    if (tile_rows > 16'd8) tile_log2_rows_w = 3'd4;
    if (tile_rows > 16'd16) tile_log2_rows_w = 3'd5;
    if (tile_rows > 16'd32) tile_log2_rows_w = 3'd6;
  end

  always @* begin
    closed_header_bits_w = 64'd0;
    closed_bit_index_w = 0;

    // AV2 v1.0.0 Sections 5.19 and 5.20.1: first tile group plus the
    // minimum uncompressed header used by the MVP still-picture path.
    closed_header_bits_w[(AV2_MAX_CLOSED_HEADER_BYTES * 8 - 1) - closed_bit_index_w] = 1'b1;
    closed_bit_index_w = closed_bit_index_w + 1;
    closed_header_bits_w[(AV2_MAX_CLOSED_HEADER_BYTES * 8 - 1) - closed_bit_index_w] = 1'b1;
    closed_bit_index_w = closed_bit_index_w + 1;
    closed_header_bits_w[(AV2_MAX_CLOSED_HEADER_BYTES * 8 - 1) - closed_bit_index_w] = 1'b1;
    closed_bit_index_w = closed_bit_index_w + 1;

    closed_header_bits_w[(AV2_MAX_CLOSED_HEADER_BYTES * 8 - 1) - closed_bit_index_w] =
      frame_palette_mode;
    closed_bit_index_w = closed_bit_index_w + 1;
    if (frame_palette_mode) begin
      // cur_frame_force_integer_mv = 0
      closed_bit_index_w = closed_bit_index_w + 1;
    end

    closed_header_bits_w[(AV2_MAX_CLOSED_HEADER_BYTES * 8 - 1) - closed_bit_index_w] =
      frame_ibc_mode;
    closed_bit_index_w = closed_bit_index_w + 1;
    if (frame_ibc_mode) begin
      // AV2 v1.0.0 read_intrabc_params(): allow_global_intrabc=0 makes
      // AVM infer local IntraBC availability for this tile-local MVP path.
      closed_bit_index_w = closed_bit_index_w + 1;
    end
    closed_header_bits_w[(AV2_MAX_CLOSED_HEADER_BYTES * 8 - 1) - closed_bit_index_w] = 1'b1;
    closed_bit_index_w = closed_bit_index_w + 1;
    closed_header_bits_w[(AV2_MAX_CLOSED_HEADER_BYTES * 8 - 1) - closed_bit_index_w] = 1'b1;
    closed_bit_index_w = closed_bit_index_w + 1;

    // AV2 v1.0.0 write_tile_info_max_tile(): uniform_spacing_flag followed
    // by one increment bit per log2 tile column/row above the Level 2.0
    // minimum. The current 64x64-SB subset keeps min_log2 at zero.
    for (closed_loop_index_w = 0; closed_loop_index_w < 6; closed_loop_index_w = closed_loop_index_w + 1) begin
      if (closed_loop_index_w < tile_log2_cols_w) begin
        closed_header_bits_w[(AV2_MAX_CLOSED_HEADER_BYTES * 8 - 1) - closed_bit_index_w] = 1'b1;
        closed_bit_index_w = closed_bit_index_w + 1;
      end
    end
    for (closed_loop_index_w = 0; closed_loop_index_w < 6; closed_loop_index_w = closed_loop_index_w + 1) begin
      if (closed_loop_index_w < tile_log2_rows_w) begin
        closed_header_bits_w[(AV2_MAX_CLOSED_HEADER_BYTES * 8 - 1) - closed_bit_index_w] = 1'b1;
        closed_bit_index_w = closed_bit_index_w + 1;
      end
    end
    if (multi_tile) begin
      closed_header_bits_w[(AV2_MAX_CLOSED_HEADER_BYTES * 8 - 1) - closed_bit_index_w] = 1'b1;
      closed_bit_index_w = closed_bit_index_w + 1;
      closed_header_bits_w[(AV2_MAX_CLOSED_HEADER_BYTES * 8 - 1) - closed_bit_index_w] = 1'b1;
      closed_bit_index_w = closed_bit_index_w + 1;
    end

    // quantization.base_qindex, segmentation.enabled, qmatrix, and
    // reduced_tx_set_used are all zero in the MVP. For multi-tile single
    // tile-group OBUs, tile_start_and_end_present_flag is also zero.
    closed_bit_index_w = closed_bit_index_w + 12;
    if (multi_tile) begin
      closed_bit_index_w = closed_bit_index_w + 1;
    end
    if (closed_bit_index_w[2:0] != 3'd0) begin
      closed_bit_index_w = closed_bit_index_w + (8 - closed_bit_index_w[2:0]);
    end
    closed_header_len = closed_bit_index_w[5:3];
  end

  always @* begin
    case (closed_header_index_w)
      3'd0: closed_header_byte_w = closed_header_bits_w[63:56];
      3'd1: closed_header_byte_w = closed_header_bits_w[55:48];
      3'd2: closed_header_byte_w = closed_header_bits_w[47:40];
      3'd3: closed_header_byte_w = closed_header_bits_w[39:32];
      3'd4: closed_header_byte_w = closed_header_bits_w[31:24];
      3'd5: closed_header_byte_w = closed_header_bits_w[23:16];
      3'd6: closed_header_byte_w = closed_header_bits_w[15:8];
      default: closed_header_byte_w = closed_header_bits_w[7:0];
    endcase
  end

  assign payload_prefix_value_w = tile_len - 16'd1;
  assign payload_prefix_byte =
    (payload_prefix_index == 2'd0) ? payload_prefix_value_w[7:0] :
    (payload_prefix_index == 2'd1) ? payload_prefix_value_w[15:8] :
    8'd0;

  assign closed_len = {12'd0, closed_header_len} + 16'd1 + payload_len;
  // AV2 v1.0.0 Section 5.3 uses unsigned LEB128 for OBU payload lengths.
  // Lossless high-colour 64x64 4:4:4 tiles can exceed the two-byte LEB128
  // range, so keep the staged writer correct through the current 16-bit bound.
  assign closed_leb_len =
    (closed_len >= 16'd16384) ? 2'd3 :
    (closed_len >= 16'd128) ? 2'd2 : 2'd1;
  assign seq_end_index = 16'd4 + seq_len;
  assign closed_leb_start = seq_end_index;
  assign closed_header_start = closed_leb_start + {14'd0, closed_leb_len};
  assign total_stream_len =
    closed_header_start + 16'd1 + {12'd0, closed_header_len} + payload_len;
  assign tile_payload_start = closed_header_start + 16'd1 + {12'd0, closed_header_len};
  assign seq_stream_index = stream_index - 16'd4;
  assign closed_leb_index = stream_index - closed_leb_start;
  assign tile_stream_index = stream_index - tile_payload_start;
  assign closed_header_payload_index_w = stream_index - closed_header_start - 16'd1;
  assign closed_header_index_w = closed_header_payload_index_w[2:0];
  assign output_tile_payload = (stream_index >= tile_payload_start);

  always @* begin
    output_byte = 8'h00;
    if (stream_index == 16'd0) begin
      output_byte = 8'h01;
    end else if (stream_index == 16'd1) begin
      output_byte = 8'h08;
    end else if (stream_index == 16'd2) begin
      output_byte = 8'd1 + seq_len[7:0];
    end else if (stream_index == 16'd3) begin
      output_byte = 8'h04;
    end else if (stream_index < seq_end_index) begin
      output_byte = seq_stream_byte;
    end else if (stream_index < closed_header_start) begin
      if (closed_leb_index == 16'd0 && closed_leb_len != 2'd1) begin
        output_byte = closed_len[6:0] | 8'h80;
      end else if (closed_leb_index == 16'd0) begin
        output_byte = closed_len[7:0];
      end else if (closed_leb_index == 16'd1 && closed_leb_len == 2'd3) begin
        output_byte = {1'b0, closed_len[13:7]} | 8'h80;
      end else if (closed_leb_index == 16'd1) begin
        output_byte = {1'b0, closed_len[13:7]};
      end else begin
        output_byte = {6'd0, closed_len[15:14]};
      end
    end else if (stream_index == closed_header_start) begin
      output_byte = 8'h10;
    end else if (stream_index < tile_payload_start) begin
      output_byte = closed_header_byte_w;
    end else begin
      output_byte = 8'h00;
    end
  end

endmodule
