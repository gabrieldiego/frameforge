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

  // TODO(av2): replace the byte forwarding path with AV2 OBU/header emission
  // and the first real coding block pipeline as the software model lands.
  logic active_q;
  logic start_invalid_w;
  logic [7:0] sample_byte_w;

  assign busy = active_q;
  assign s_axis_ready = busy && !m_axis_valid;
  assign start_invalid_w =
    (visible_width == 16'd0) ||
    (visible_height == 16'd0) ||
    (visible_width > MAX_VISIBLE_WIDTH) ||
    (visible_height > MAX_VISIBLE_HEIGHT) ||
    (chroma_format_idc == 2'd0);
  assign sample_byte_w = s_axis_data[SAMPLE_BITS - 1 -: 8];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      active_q <= 1'b0;
      input_error <= 1'b0;
      m_axis_valid <= 1'b0;
      m_axis_data <= '0;
      m_axis_last <= 1'b0;
    end else begin
      if (start && !active_q) begin
        input_error <= start_invalid_w;
        active_q <= !start_invalid_w;
      end

      if (m_axis_valid && m_axis_ready) begin
        if (m_axis_last) begin
          active_q <= 1'b0;
        end
        m_axis_valid <= 1'b0;
        m_axis_last <= 1'b0;
      end

      if (s_axis_valid && s_axis_ready) begin
        m_axis_valid <= 1'b1;
        m_axis_data <= sample_byte_w;
        m_axis_last <= s_axis_last;
      end
    end
  end

endmodule
