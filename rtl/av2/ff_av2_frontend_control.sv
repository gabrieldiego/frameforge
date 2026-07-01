`timescale 1ns/1ps

module ff_av2_frontend_control #(
  parameter int SUPPORT_PALETTE_444 = 1
) (
  input  logic        start,
  input  logic        state_idle,
  input  logic        state_tile_start,
  input  logic        state_palette_query,
  input  logic [1:0]  chroma_format_idc,
  input  logic [31:0] frame_count,
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,
  input  logic        packet_axis_valid,
  input  logic        packet_axis_last,
  input  logic [3:0]  packet_axis_count,
  input  logic [31:0] tile_input_index,
  input  logic        tile_input_active,
  input  logic [7:0]  tile_block_count,
  input  logic [15:0] tile_count,
  input  logic [15:0] tile_index,
  input  logic [15:0] payload_len,
  input  logic [31:0] frame_index,
  input  logic        palette_analyzer_sample_ready,
  input  logic        palette_analyzer_done,
  input  logic        palette_analyzer_nonblack_seen,
  input  logic        palette_analyzer_luma_mode,
  input  logic        palette_analyzer_black,
  input  logic [63:0] palette_analyzer_block_ready_mask,
  input  logic        bitstream_writer_frame_done,
  input  logic        frame_reader_error,
  input  logic        bitstream_writer_error,
  output logic        start_invalid,
  output logic        packet_axis_ready,
  output logic        palette_analyzer_start,
  output logic        input_sample_fire,
  output logic        input_packet_fire,
  output logic        input_fire,
  output logic [3:0]  input_fire_count,
  output logic        input_axis_last,
  output logic        tile_input_last,
  output logic        input_fire_error,
  output logic        frame_is_last,
  output logic        palette_query_start,
  output logic        busy,
  output logic        frame_reader_start,
  output logic        bitstream_writer_start,
  output logic        done,
  output logic        axi_error,
  output logic [31:0] tile_luma_samples,
  output logic [31:0] tile_samples,
  output logic        tile_is_last,
  output logic        multi_tile,
  output logic [15:0] payload_tile_start,
  output logic        tile_entropy_start_ready,
  output logic        tile_entropy_palette_mode,
  output logic        tile_entropy_lossy420_mode,
  output logic        tile_entropy_ibc_mode
);

  logic tile_entropy_start_early_444_w;
  logic tile_entropy_start_early_420_w;

  assign start_invalid =
    !((chroma_format_idc == 2'd1) || (chroma_format_idc == 2'd3)) ||
    (frame_count == 32'd0) ||
    (visible_width == 16'd0) ||
    (visible_height == 16'd0) ||
    (visible_width[2:0] != 3'd0) ||
    (visible_height[2:0] != 3'd0);

  assign busy = !state_idle;
  assign palette_analyzer_start = state_tile_start;
  assign frame_reader_start = state_tile_start;
  assign bitstream_writer_start = start && state_idle;
  assign done = bitstream_writer_frame_done;
  assign axi_error = frame_reader_error || bitstream_writer_error;

  assign packet_axis_ready =
    tile_input_active &&
    palette_analyzer_sample_ready &&
    !palette_analyzer_done;
  assign input_sample_fire = 1'b0;
  assign input_packet_fire = packet_axis_valid && packet_axis_ready;
  assign input_fire = input_packet_fire;
  assign input_fire_count = packet_axis_count;
  assign input_axis_last = packet_axis_last;
  assign tile_input_last =
    input_fire &&
    ((tile_input_index + {28'd0, input_fire_count}) >= tile_samples);
  assign input_fire_error =
    input_fire &&
    (input_axis_last != (tile_is_last && tile_input_last));

  assign frame_is_last = ((frame_index + 32'd1) >= frame_count);
  assign palette_query_start = state_palette_query;

  assign tile_luma_samples = {18'd0, tile_block_count, 6'd0};
  assign tile_samples =
    (chroma_format_idc == 2'd1) ?
      (tile_luma_samples + (tile_luma_samples >> 1)) :
      (tile_luma_samples + (tile_luma_samples << 1));
  assign tile_is_last = (tile_index == (tile_count - 16'd1));
  assign multi_tile = (tile_count != 16'd1);
  assign payload_tile_start = payload_len + (tile_is_last ? 16'd0 : 16'd4);

  assign tile_entropy_start_early_444_w =
    (chroma_format_idc == 2'd3) &&
    (SUPPORT_PALETTE_444 != 0) &&
    palette_analyzer_nonblack_seen &&
    palette_analyzer_block_ready_mask[0];
  assign tile_entropy_start_early_420_w =
    (chroma_format_idc == 2'd1) &&
    palette_analyzer_nonblack_seen &&
    palette_analyzer_block_ready_mask[0];
  assign tile_entropy_start_ready =
    palette_analyzer_done ||
    tile_entropy_start_early_444_w ||
    tile_entropy_start_early_420_w;
  assign tile_entropy_palette_mode =
    tile_entropy_start_early_444_w ? 1'b1 :
      (tile_entropy_start_early_420_w ? 1'b0 : palette_analyzer_luma_mode);
  assign tile_entropy_lossy420_mode =
    tile_entropy_start_early_444_w ? 1'b0 :
      (tile_entropy_start_early_420_w ? 1'b1 :
        ((chroma_format_idc == 2'd1) && !palette_analyzer_black));
  assign tile_entropy_ibc_mode =
    tile_entropy_start_early_444_w ? 1'b1 :
      (tile_entropy_start_early_420_w ? 1'b0 : palette_analyzer_luma_mode);

endmodule
