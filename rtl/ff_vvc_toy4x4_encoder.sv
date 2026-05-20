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
  localparam int ACCESS_UNIT_LEN  = 74;
  localparam int SPS_PAYLOAD_LEN  = 31;
  localparam int PPS_PAYLOAD_LEN  = 14;
  localparam int SLICE_PAYLOAD_LEN = 11;

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
      2'd2: stream_len = 8'd148;
      default: stream_len = 8'd74;
    endcase
  endfunction

  function automatic logic [7:0] stream_byte(input logic [7:0] index);
    logic second_access_unit;
    logic [6:0] access_unit_index;

    begin
      second_access_unit = (index >= 8'd74);
      access_unit_index = second_access_unit ? (index - 8'd74) : index[6:0];
      stream_byte = access_unit_byte(access_unit_index, second_access_unit);
    end
  endfunction

  function automatic logic [7:0] access_unit_byte(
    input logic [6:0] index,
    input logic       cra_picture
  );
    begin
      if (index < 7'd37) begin
        access_unit_byte = nal_byte(2'd0, index, cra_picture);
      end else if (index < 7'd57) begin
        access_unit_byte = nal_byte(2'd1, index - 7'd37, cra_picture);
      end else begin
        access_unit_byte = nal_byte(2'd2, index - 7'd57, cra_picture);
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
    case (index)
      7'd0:  sps_payload_byte = 8'h00;
      7'd1:  sps_payload_byte = 8'h0b;
      7'd2:  sps_payload_byte = 8'h02;
      7'd3:  sps_payload_byte = 8'h00;
      7'd4:  sps_payload_byte = 8'h80;
      7'd5:  sps_payload_byte = 8'h00;
      7'd6:  sps_payload_byte = 8'h42;
      7'd7:  sps_payload_byte = 8'h44;
      7'd8:  sps_payload_byte = 8'hee;
      7'd9:  sps_payload_byte = 8'hd5;
      7'd10: sps_payload_byte = 8'h01;
      7'd11: sps_payload_byte = 8'hf4;
      7'd12: sps_payload_byte = 8'h46;
      7'd13: sps_payload_byte = 8'he8;
      7'd14: sps_payload_byte = 8'h84;
      7'd15: sps_payload_byte = 8'h68;
      7'd16: sps_payload_byte = 8'h84;
      7'd17: sps_payload_byte = 8'h24;
      7'd18: sps_payload_byte = 8'h61;
      7'd19: sps_payload_byte = 8'h36;
      7'd20: sps_payload_byte = 8'h28;
      7'd21: sps_payload_byte = 8'hc5;
      7'd22: sps_payload_byte = 8'h43;
      7'd23: sps_payload_byte = 8'h06;
      7'd24: sps_payload_byte = 8'h80;
      7'd25: sps_payload_byte = 8'hab;
      7'd26: sps_payload_byte = 8'h8f;
      7'd27: sps_payload_byte = 8'he0;
      7'd28: sps_payload_byte = 8'hac;
      7'd29: sps_payload_byte = 8'h10;
      7'd30: sps_payload_byte = 8'h20;
      default: sps_payload_byte = 8'h00;
    endcase
  endfunction

  function automatic logic [7:0] pps_payload_byte(input logic [6:0] index);
    case (index)
      7'd0:  pps_payload_byte = 8'h00;
      7'd1:  pps_payload_byte = 8'h02;
      7'd2:  pps_payload_byte = 8'h44;
      7'd3:  pps_payload_byte = 8'h8a;
      7'd4:  pps_payload_byte = 8'h42;
      7'd5:  pps_payload_byte = 8'h00;
      7'd6:  pps_payload_byte = 8'hc7;
      7'd7:  pps_payload_byte = 8'hb2;
      7'd8:  pps_payload_byte = 8'h14;
      7'd9:  pps_payload_byte = 8'h59;
      7'd10: pps_payload_byte = 8'h45;
      7'd11: pps_payload_byte = 8'h94;
      7'd12: pps_payload_byte = 8'h58;
      7'd13: pps_payload_byte = 8'h80;
      default: pps_payload_byte = 8'h00;
    endcase
  endfunction

  function automatic logic [7:0] slice_payload_byte(
    input logic [6:0] index,
    input logic       cra_picture
  );
    case (index)
      7'd0:  slice_payload_byte = 8'hc4;
      7'd1:  slice_payload_byte = cra_picture ? 8'h04 : 8'h00;
      7'd2:  slice_payload_byte = cra_picture ? 8'h78 : 8'h70;
      7'd3:  slice_payload_byte = 8'h80;
      7'd4:  slice_payload_byte = 8'h62;
      7'd5:  slice_payload_byte = 8'hf5;
      7'd6:  slice_payload_byte = 8'hb7;
      7'd7:  slice_payload_byte = 8'heb;
      7'd8:  slice_payload_byte = 8'hcb;
      7'd9:  slice_payload_byte = 8'h1f;
      7'd10: slice_payload_byte = 8'h80;
      default: slice_payload_byte = 8'h00;
    endcase
  endfunction
endmodule
