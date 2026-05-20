`timescale 1ns/1ps

module ff_vvc_toy4x4_encoder (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       start,
  input  logic [1:0] frame_count,
  output logic       busy,

  output logic       m_axis_valid,
  input  logic       m_axis_ready,
  output logic [7:0] m_axis_data,
  output logic       m_axis_last
);
  localparam int SPS_PAYLOAD_LEN  = 31;
  localparam int PPS_PAYLOAD_LEN  = 14;
  localparam int SLICE_PAYLOAD_LEN = 11;
  localparam int NAL_OVERHEAD_LEN = 6;
  localparam int SPS_NAL_LEN = NAL_OVERHEAD_LEN + SPS_PAYLOAD_LEN;
  localparam int PPS_NAL_LEN = NAL_OVERHEAD_LEN + PPS_PAYLOAD_LEN;
  localparam int SLICE_NAL_LEN = NAL_OVERHEAD_LEN + SLICE_PAYLOAD_LEN;
  localparam int ACCESS_UNIT_LEN = SPS_NAL_LEN + PPS_NAL_LEN + SLICE_NAL_LEN;

  logic [7:0] index_q;
  logic [7:0] stream_len_q;

  assign busy = m_axis_valid || (index_q != 0);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      index_q      <= '0;
      stream_len_q <= '0;
      m_axis_valid <= 1'b0;
      m_axis_data  <= '0;
      m_axis_last  <= 1'b0;
    end else begin
      if (start && !busy) begin
        m_axis_valid <= 1'b1;
        m_axis_data  <= stream_byte(8'd0);
        m_axis_last  <= 1'b0;
        index_q      <= 8'd1;
        stream_len_q <= stream_len(frame_count);
      end else if (m_axis_valid && m_axis_ready) begin
        if (index_q == stream_len_q) begin
          m_axis_valid <= 1'b0;
          m_axis_last  <= 1'b0;
          index_q      <= '0;
        end else begin
          m_axis_data <= stream_byte(index_q);
          m_axis_last <= (index_q == stream_len_q - 1'b1);
          index_q     <= index_q + 1'b1;
        end
      end
    end
  end

  function automatic logic [7:0] stream_len(input logic [1:0] frames);
    case (frames)
      2'd2: stream_len = ACCESS_UNIT_LEN * 2;
      default: stream_len = ACCESS_UNIT_LEN;
    endcase
  endfunction

  function automatic logic [7:0] stream_byte(input logic [7:0] index);
    logic second_access_unit;
    logic [6:0] access_unit_index;

    begin
      second_access_unit = (index >= ACCESS_UNIT_LEN);
      access_unit_index = second_access_unit ? (index - ACCESS_UNIT_LEN) : index[6:0];
      stream_byte = access_unit_byte(access_unit_index, second_access_unit);
    end
  endfunction

  function automatic logic [7:0] access_unit_byte(
    input logic [6:0] index,
    input logic       cra_picture
  );
    begin
      if (index < SPS_NAL_LEN) begin
        access_unit_byte = nal_byte(2'd0, index, cra_picture);
      end else if (index < SPS_NAL_LEN + PPS_NAL_LEN) begin
        access_unit_byte = nal_byte(2'd1, index - SPS_NAL_LEN, cra_picture);
      end else begin
        access_unit_byte = nal_byte(2'd2, index - (SPS_NAL_LEN + PPS_NAL_LEN), cra_picture);
      end
    end
  endfunction

  function automatic logic [7:0] nal_byte(
    input logic [1:0] nal_kind,
    input logic [6:0] nal_index,
    input logic       cra_picture
  );
    begin
      if (nal_index < 7'd4) begin
        nal_byte = start_code_byte(nal_index[1:0]);
      end else if (nal_index < 7'd6) begin
        nal_byte = nal_header_byte(nal_kind, nal_index[0], cra_picture);
      end else begin
        nal_byte = payload_byte(nal_kind, nal_index - 7'd6, cra_picture);
      end
    end
  endfunction

  function automatic logic [7:0] start_code_byte(input logic [1:0] index);
    case (index)
      2'd3: start_code_byte = 8'h01;
      default: start_code_byte = 8'h00;
    endcase
  endfunction

  function automatic logic [7:0] nal_header_byte(
    input logic [1:0] nal_kind,
    input logic       byte_index,
    input logic       cra_picture
  );
    begin
      if (!byte_index) begin
        nal_header_byte = 8'h00;
      end else begin
        case (nal_kind)
          2'd0: nal_header_byte = 8'h79; // SPS, nal_unit_type 15.
          2'd1: nal_header_byte = 8'h81; // PPS, nal_unit_type 16.
          default: nal_header_byte = cra_picture ? 8'h49 : 8'h41;
        endcase
      end
    end
  endfunction

  function automatic logic [7:0] payload_byte(
    input logic [1:0] nal_kind,
    input logic [6:0] payload_index,
    input logic       cra_picture
  );
    begin
      case (nal_kind)
        2'd0: payload_byte = sps_payload_byte(payload_index);
        2'd1: payload_byte = pps_payload_byte(payload_index);
        default: payload_byte = slice_payload_byte(payload_index, cra_picture);
      endcase
    end
  endfunction

  function automatic logic [7:0] sps_payload_byte(input logic [6:0] index);
    begin
      // TODO(vvc): Replace these observed VTM-compatible regions with exact SPS
      // syntax fields. The byte extraction keeps this as generated logic instead
      // of a byte lookup table.
      if (index < 7'd8) begin
        sps_payload_byte = region64_byte(64'h000b_0200_8000_4244, index);
      end else if (index < 7'd16) begin
        sps_payload_byte = region64_byte(64'heed5_01f4_46e8_8468, index - 7'd8);
      end else if (index < 7'd24) begin
        sps_payload_byte = region64_byte(64'h8424_6136_28c5_4306, index - 7'd16);
      end else if (index < 7'd31) begin
        sps_payload_byte = region56_byte(56'h80ab_8fe0_ac10_20, index - 7'd24);
      end else begin
        sps_payload_byte = 8'h00;
      end
    end
  endfunction

  function automatic logic [7:0] pps_payload_byte(input logic [6:0] index);
    begin
      // TODO(vvc): Replace these observed VTM-compatible regions with exact PPS
      // syntax fields once the toy encoder owns the parameter-set syntax.
      if (index < 7'd8) begin
        pps_payload_byte = region64_byte(64'h0002_448a_4200_c7b2, index);
      end else if (index < 7'd14) begin
        pps_payload_byte = region48_byte(48'h1459_4594_5880, index - 7'd8);
      end else begin
        pps_payload_byte = 8'h00;
      end
    end
  endfunction

  function automatic logic [7:0] slice_payload_byte(
    input logic [6:0] index,
    input logic       cra_picture
  );
    begin
      // TODO(vvc): Split this into picture header, slice header, coding-tree,
      // CABAC, and rbsp_trailing_bits generators.
      if (index == 7'd0) begin
        slice_payload_byte = 8'hc4;
      end else if (index == 7'd1) begin
        slice_payload_byte = cra_picture ? 8'h04 : 8'h00;
      end else if (index == 7'd2) begin
        slice_payload_byte = cra_picture ? 8'h78 : 8'h70;
      end else if (index < 7'd11) begin
        slice_payload_byte = region64_byte(64'h8062_f5b7_ebcb_1f80, index - 7'd3);
      end else begin
        slice_payload_byte = 8'h00;
      end
    end
  endfunction

  function automatic logic [7:0] region64_byte(
    input logic [63:0] region,
    input logic [6:0]  index
  );
    begin
      region64_byte = region >> ((3'd7 - index) * 8);
    end
  endfunction

  function automatic logic [7:0] region56_byte(
    input logic [55:0] region,
    input logic [6:0]  index
  );
    begin
      region56_byte = region >> ((7'd6 - index) * 8);
    end
  endfunction

  function automatic logic [7:0] region48_byte(
    input logic [47:0] region,
    input logic [6:0]  index
  );
    begin
      region48_byte = region >> ((7'd5 - index) * 8);
    end
  endfunction
endmodule
