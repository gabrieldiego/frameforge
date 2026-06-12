`timescale 1ns/1ps

module ff_av2_encoder #(
  parameter int MAX_VISIBLE_WIDTH = 1024,
  parameter int MAX_VISIBLE_HEIGHT = 1024,
  // TODO(av2): revisit this shared integration name once AV2 block/superblock
  // terminology is finalized in the implementation.
  parameter int CTU_SIZE = 64,
  parameter int SAMPLE_BITS = 8,
  parameter int SOURCE_SAMPLE_BITS = SAMPLE_BITS
) (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       start,
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,
  // Shared chroma format IDs: 1=4:2:0, 2=4:2:2, 3=4:4:4.
  input  logic [1:0] chroma_format_idc,
  output logic       busy,

  input  logic       s_axis_valid,
  output logic       s_axis_ready,
  input  logic [SAMPLE_BITS - 1:0] s_axis_data,
  input  logic       s_axis_last,
  output logic       input_error,

  output logic       m_axis_valid,
  input  logic       m_axis_ready,
  output logic [7:0] m_axis_data,
  output logic       m_axis_last
);

  localparam logic [15:0] TEMP_BLACK_444_WIDTH = 16'd64;
  localparam logic [15:0] TEMP_BLACK_444_HEIGHT = 16'd64;
  localparam int TEMP_BLACK_444_BYTES = TEMP_BLACK_444_WIDTH * TEMP_BLACK_444_HEIGHT * 3;

  // TODO(av2): remove this simulation-only fixed black-frame payload as soon
  // as the first real AV2 header/picture pipeline exists. This deliberately
  // ignores input samples and is not intended to be synthesizable hardware.
  logic active_q;
  logic start_invalid_w;
  logic [$clog2(TEMP_BLACK_444_BYTES):0] payload_index_q;
  logic payload_next_done_w;

  assign busy = active_q;
  assign s_axis_ready = 1'b0;
  assign start_invalid_w =
    (visible_width != TEMP_BLACK_444_WIDTH) ||
    (visible_height != TEMP_BLACK_444_HEIGHT) ||
    (visible_width > MAX_VISIBLE_WIDTH) ||
    (visible_height > MAX_VISIBLE_HEIGHT) ||
    (chroma_format_idc != 2'd3);
  assign payload_next_done_w = ((payload_index_q + 1'b1) == (TEMP_BLACK_444_BYTES - 1));

  // synthesis translate_off
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      active_q <= 1'b0;
      payload_index_q <= '0;
      input_error <= 1'b0;
      m_axis_valid <= 1'b0;
      m_axis_data <= '0;
      m_axis_last <= 1'b0;
    end else begin
      if (start && !active_q) begin
        input_error <= start_invalid_w;
        active_q <= !start_invalid_w;
        payload_index_q <= '0;
        if (!start_invalid_w) begin
          m_axis_valid <= 1'b1;
          m_axis_data <= 8'h00;
          m_axis_last <= (TEMP_BLACK_444_BYTES == 1);
        end
      end

      if (m_axis_valid && m_axis_ready) begin
        if (m_axis_last) begin
          active_q <= 1'b0;
          payload_index_q <= '0;
          m_axis_valid <= 1'b0;
          m_axis_last <= 1'b0;
        end else begin
          payload_index_q <= payload_index_q + 1'b1;
          m_axis_valid <= 1'b1;
          m_axis_data <= 8'h00;
          m_axis_last <= payload_next_done_w;
        end
      end
    end
  end
  // synthesis translate_on

endmodule
