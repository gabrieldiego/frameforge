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

  localparam logic [15:0] FIXED_BLACK_444_WIDTH = 16'd64;
  localparam logic [15:0] FIXED_BLACK_444_HEIGHT = 16'd64;
  localparam int FIXED_BLACK_444_OBU_BYTES = 39;

  // TODO(av2): remove this simulation-only fixed black-frame OBU stream as
  // soon as the first real AV2 header/picture pipeline exists. This mirrors
  // the current Rust fixed 64x64 yuv444p8 black-frame encoder and deliberately
  // ignores input samples. It is not intended to be synthesizable hardware.
  logic active_q;
  logic start_invalid_w;
  logic [$clog2(FIXED_BLACK_444_OBU_BYTES):0] payload_index_q;
  logic [7:0] payload_byte_w;
  logic payload_next_done_w;

  assign busy = active_q;
  assign s_axis_ready = 1'b0;
  assign start_invalid_w =
    (visible_width != FIXED_BLACK_444_WIDTH) ||
    (visible_height != FIXED_BLACK_444_HEIGHT) ||
    (visible_width > MAX_VISIBLE_WIDTH) ||
    (visible_height > MAX_VISIBLE_HEIGHT) ||
    (chroma_format_idc != 2'd3);
  assign payload_next_done_w = ((payload_index_q + 1'b1) == (FIXED_BLACK_444_OBU_BYTES - 1));

  // synthesis translate_off
  always_comb begin
    payload_byte_w = 8'h00;
    case (payload_index_q)
      0: payload_byte_w = 8'h01;
      1: payload_byte_w = 8'h08;
      2: payload_byte_w = 8'h0d;
      3: payload_byte_w = 8'h04;
      4: payload_byte_w = 8'h92;
      5: payload_byte_w = 8'h06;
      6: payload_byte_w = 8'h95;
      7: payload_byte_w = 8'h7f;
      8: payload_byte_w = 8'hfc;
      9: payload_byte_w = 8'h70;
      10: payload_byte_w = 8'he7;
      11: payload_byte_w = 8'h36;
      12: payload_byte_w = 8'h11;
      13: payload_byte_w = 8'hb8;
      14: payload_byte_w = 8'h08;
      15: payload_byte_w = 8'h80;
      16: payload_byte_w = 8'h16;
      17: payload_byte_w = 8'h10;
      18: payload_byte_w = 8'he2;
      19: payload_byte_w = 8'h00;
      20: payload_byte_w = 8'h00;
      21: payload_byte_w = 8'h00;
      22: payload_byte_w = 8'h12;
      23: payload_byte_w = 8'h2e;
      24: payload_byte_w = 8'h6a;
      25: payload_byte_w = 8'h24;
      26: payload_byte_w = 8'hb3;
      27: payload_byte_w = 8'he1;
      28: payload_byte_w = 8'h80;
      29: payload_byte_w = 8'hd0;
      30: payload_byte_w = 8'h4c;
      31: payload_byte_w = 8'h79;
      32: payload_byte_w = 8'hff;
      33: payload_byte_w = 8'h4e;
      34: payload_byte_w = 8'hdb;
      35: payload_byte_w = 8'h90;
      36: payload_byte_w = 8'h36;
      37: payload_byte_w = 8'he7;
      38: payload_byte_w = 8'hc0;
      default: payload_byte_w = 8'h00;
    endcase
  end

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
          m_axis_data <= payload_byte_w;
          m_axis_last <= (FIXED_BLACK_444_OBU_BYTES == 1);
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
          case (payload_index_q + 1'b1)
            0: m_axis_data <= 8'h01;
            1: m_axis_data <= 8'h08;
            2: m_axis_data <= 8'h0d;
            3: m_axis_data <= 8'h04;
            4: m_axis_data <= 8'h92;
            5: m_axis_data <= 8'h06;
            6: m_axis_data <= 8'h95;
            7: m_axis_data <= 8'h7f;
            8: m_axis_data <= 8'hfc;
            9: m_axis_data <= 8'h70;
            10: m_axis_data <= 8'he7;
            11: m_axis_data <= 8'h36;
            12: m_axis_data <= 8'h11;
            13: m_axis_data <= 8'hb8;
            14: m_axis_data <= 8'h08;
            15: m_axis_data <= 8'h80;
            16: m_axis_data <= 8'h16;
            17: m_axis_data <= 8'h10;
            18: m_axis_data <= 8'he2;
            19: m_axis_data <= 8'h00;
            20: m_axis_data <= 8'h00;
            21: m_axis_data <= 8'h00;
            22: m_axis_data <= 8'h12;
            23: m_axis_data <= 8'h2e;
            24: m_axis_data <= 8'h6a;
            25: m_axis_data <= 8'h24;
            26: m_axis_data <= 8'hb3;
            27: m_axis_data <= 8'he1;
            28: m_axis_data <= 8'h80;
            29: m_axis_data <= 8'hd0;
            30: m_axis_data <= 8'h4c;
            31: m_axis_data <= 8'h79;
            32: m_axis_data <= 8'hff;
            33: m_axis_data <= 8'h4e;
            34: m_axis_data <= 8'hdb;
            35: m_axis_data <= 8'h90;
            36: m_axis_data <= 8'h36;
            37: m_axis_data <= 8'he7;
            38: m_axis_data <= 8'hc0;
            default: m_axis_data <= 8'h00;
          endcase
          m_axis_last <= payload_next_done_w;
        end
      end
    end
  end
  // synthesis translate_on

endmodule
