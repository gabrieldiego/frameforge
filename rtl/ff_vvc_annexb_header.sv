`timescale 1ns/1ps

module ff_vvc_annexb_header (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        clear,
  input  logic        start,
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,
  input  logic        m_axis_ready,
  output logic        m_axis_valid,
  output logic [7:0]  m_axis_data,
  output logic        m_axis_last,
  output logic        done
);
  localparam logic [15:0] CODED_GRANULARITY = 16'd8;
  localparam logic [15:0] MIN_CODED_AXIS = 16'd8;
  localparam logic [15:0] BASE_CODED_AXIS = 16'd16;
  localparam logic [3:0] FIELD_SPS_START_CODE      = 4'd0;
  localparam logic [3:0] FIELD_SPS_NAL_HEADER      = 4'd1;
  localparam logic [3:0] FIELD_SPS_RBSP            = 4'd2;
  localparam logic [3:0] FIELD_PPS_START_CODE      = 4'd3;
  localparam logic [3:0] FIELD_PPS_NAL_HEADER      = 4'd4;
  localparam logic [3:0] FIELD_PPS_RBSP            = 4'd5;
  localparam logic [4:0] NAL_UNIT_TYPE_TRAIL       = 5'd0;
  localparam logic [4:0] NAL_UNIT_TYPE_SPS         = 5'd15;
  localparam logic [4:0] NAL_UNIT_TYPE_PPS         = 5'd16;
  localparam logic [5:0] NAL_LAYER_ID              = 6'd0;
  localparam logic [2:0] NAL_TEMPORAL_ID_PLUS1     = 3'd1;

  logic [15:0] coded_width;
  logic [15:0] coded_height;
  logic min_axis_visible;
  logic width_uses_min_axis;
  logic width_has_extra_leaf;
  logic height_has_extra_leaf;
  logic [3:0] field_q;
  logic [3:0] field_next;
  logic [5:0] field_byte_index_q;
  logic [5:0] field_len;
  logic [4:0] nal_unit_type;
  logic [7:0] byte_next;
  logic active_q;

  assign coded_width = (visible_width + CODED_GRANULARITY - 16'd1) & ~(CODED_GRANULARITY - 16'd1);
  assign coded_height = (visible_height + CODED_GRANULARITY - 16'd1) & ~(CODED_GRANULARITY - 16'd1);
  assign min_axis_visible = (coded_width == MIN_CODED_AXIS) || (coded_height == MIN_CODED_AXIS);
  assign width_uses_min_axis = coded_width == MIN_CODED_AXIS;
  assign width_has_extra_leaf = coded_width > BASE_CODED_AXIS;
  assign height_has_extra_leaf = coded_height > BASE_CODED_AXIS;
  assign m_axis_valid = active_q;
  assign m_axis_data = active_q ? byte_next : 8'h00;
  assign m_axis_last = active_q &&
                       (field_q == FIELD_PPS_RBSP) &&
                       (field_byte_index_q == field_len - 6'd1);

  always_comb begin
    field_len = 6'd1;
    case (field_q)
      FIELD_SPS_START_CODE,
      FIELD_PPS_START_CODE: field_len = 6'd4;
      FIELD_SPS_NAL_HEADER,
      FIELD_PPS_NAL_HEADER: field_len = 6'd2;
      FIELD_SPS_RBSP: field_len = 6'd31;
      FIELD_PPS_RBSP: field_len = 6'd14;
      default: field_len = 6'd1;
    endcase
  end

  always_comb begin
    field_next = FIELD_SPS_START_CODE;
    case (field_q)
      FIELD_SPS_START_CODE: field_next = FIELD_SPS_NAL_HEADER;
      FIELD_SPS_NAL_HEADER: field_next = FIELD_SPS_RBSP;
      FIELD_SPS_RBSP: field_next = FIELD_PPS_START_CODE;
      FIELD_PPS_START_CODE: field_next = FIELD_PPS_NAL_HEADER;
      FIELD_PPS_NAL_HEADER: field_next = FIELD_PPS_RBSP;
      FIELD_PPS_RBSP: field_next = FIELD_SPS_START_CODE;
      default: field_next = FIELD_SPS_START_CODE;
    endcase
  end

  always_comb begin
    nal_unit_type = NAL_UNIT_TYPE_TRAIL;
    case (field_q)
      FIELD_SPS_NAL_HEADER: nal_unit_type = NAL_UNIT_TYPE_SPS;
      FIELD_PPS_NAL_HEADER: nal_unit_type = NAL_UNIT_TYPE_PPS;
      default: nal_unit_type = NAL_UNIT_TYPE_TRAIL;
    endcase
  end

  always_comb begin
    byte_next = 8'h00;
    case (field_q)
      FIELD_SPS_START_CODE,
      FIELD_PPS_START_CODE: begin
        case (field_byte_index_q)
          6'd0, 6'd1, 6'd2: byte_next = 8'h00;
          6'd3: byte_next = 8'h01;
          default: byte_next = 8'h00;
        endcase
      end
      FIELD_SPS_NAL_HEADER,
      FIELD_PPS_NAL_HEADER: begin
        if (field_byte_index_q == 6'd0) begin
          byte_next = {2'b00, NAL_LAYER_ID};
        end else begin
          byte_next = {nal_unit_type, NAL_TEMPORAL_ID_PLUS1};
        end
      end
      FIELD_SPS_RBSP: begin
        case (field_byte_index_q)
          6'd0: byte_next = 8'h00;
          6'd1: byte_next = 8'h0b;
          6'd2: byte_next = 8'h02;
          6'd3: byte_next = 8'h00;
          6'd4: byte_next = 8'h80;
          6'd5: byte_next = 8'h00;
          6'd6: byte_next = min_axis_visible ? (width_uses_min_axis ? 8'h42 : 8'h41) : 8'h41;
          6'd7: byte_next = min_axis_visible ? (width_uses_min_axis ? 8'h42 : 8'h11) :
                                               (width_has_extra_leaf ? 8'h90 : 8'h10);
          6'd8: byte_next = min_axis_visible ? 8'h3f : (height_has_extra_leaf ? 8'hcf : 8'h8f);
          6'd9: byte_next = min_axis_visible ? 8'h54 : 8'hd5;
          6'd10: byte_next = min_axis_visible ? 8'h07 : 8'h01;
          6'd11: byte_next = min_axis_visible ? 8'hd1 : 8'hf4;
          6'd12: byte_next = min_axis_visible ? 8'h1b : 8'h46;
          6'd13: byte_next = min_axis_visible ? 8'ha2 : 8'he8;
          6'd14: byte_next = min_axis_visible ? 8'h11 : 8'h84;
          6'd15: byte_next = min_axis_visible ? 8'ha2 : 8'h68;
          6'd16: byte_next = min_axis_visible ? 8'h10 : 8'h84;
          6'd17: byte_next = min_axis_visible ? 8'h91 : 8'h24;
          6'd18: byte_next = min_axis_visible ? 8'h84 : 8'h61;
          6'd19: byte_next = min_axis_visible ? 8'hd8 : 8'h36;
          6'd20: byte_next = min_axis_visible ? 8'ha3 : 8'h28;
          6'd21: byte_next = min_axis_visible ? 8'h15 : 8'hc5;
          6'd22: byte_next = min_axis_visible ? 8'h0c : 8'h43;
          6'd23: byte_next = min_axis_visible ? 8'h1a : 8'h06;
          6'd24: byte_next = min_axis_visible ? 8'h02 : 8'h80;
          6'd25: byte_next = min_axis_visible ? 8'hae : 8'hab;
          6'd26: byte_next = min_axis_visible ? 8'h3f : 8'h8f;
          6'd27: byte_next = min_axis_visible ? 8'h82 : 8'he0;
          6'd28: byte_next = min_axis_visible ? 8'hb0 : 8'hac;
          6'd29: byte_next = min_axis_visible ? 8'h40 : 8'h10;
          6'd30: byte_next = min_axis_visible ? 8'h80 : 8'h20;
          default: byte_next = 8'h00;
        endcase
      end
      FIELD_PPS_RBSP: begin
        case (field_byte_index_q)
          6'd0: byte_next = 8'h00;
          6'd1: byte_next = min_axis_visible ? (width_uses_min_axis ? 8'h02 : 8'h01) : 8'h01;
          6'd2: byte_next = min_axis_visible ? (width_uses_min_axis ? 8'h42 : 8'h11) :
                                               (width_has_extra_leaf ? 8'h90 : 8'h10);
          6'd3: byte_next = min_axis_visible ? 8'h22 : (height_has_extra_leaf ? 8'hc8 : 8'h88);
          6'd4: byte_next = min_axis_visible ? 8'h90 : 8'ha4;
          6'd5: byte_next = min_axis_visible ? 8'h80 : 8'h20;
          6'd6: byte_next = min_axis_visible ? 8'h31 : 8'h0c;
          6'd7: byte_next = min_axis_visible ? 8'hec : 8'h7b;
          6'd8: byte_next = min_axis_visible ? 8'h85 : 8'h21;
          6'd9: byte_next = min_axis_visible ? 8'h16 : 8'h45;
          6'd10: byte_next = min_axis_visible ? 8'h51 : 8'h94;
          6'd11: byte_next = min_axis_visible ? 8'h65 : 8'h59;
          6'd12: byte_next = min_axis_visible ? 8'h16 : 8'h45;
          6'd13: byte_next = min_axis_visible ? 8'h20 : 8'h88;
          default: byte_next = 8'h00;
        endcase
      end
      default: byte_next = 8'h00;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      field_q <= FIELD_SPS_START_CODE;
      field_byte_index_q <= 6'd0;
      active_q <= 1'b0;
      done <= 1'b0;
    end else if (clear) begin
      field_q <= FIELD_SPS_START_CODE;
      field_byte_index_q <= 6'd0;
      active_q <= 1'b0;
      done <= 1'b0;
    end else begin
      done <= 1'b0;

      if (start) begin
        field_q <= FIELD_SPS_START_CODE;
        field_byte_index_q <= 6'd0;
        active_q <= 1'b1;
      end else if (m_axis_valid && m_axis_ready) begin
        if (m_axis_last) begin
          field_q <= FIELD_SPS_START_CODE;
          field_byte_index_q <= 6'd0;
          active_q <= 1'b0;
          done <= 1'b1;
        end else if (field_byte_index_q == field_len - 6'd1) begin
          field_q <= field_next;
          field_byte_index_q <= 6'd0;
        end else begin
          field_byte_index_q <= field_byte_index_q + 6'd1;
        end
      end
    end
  end
endmodule
