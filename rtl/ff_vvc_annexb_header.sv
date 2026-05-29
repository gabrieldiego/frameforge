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
  output logic        supported,
  output logic        done
);
  localparam int HEADER_BYTES = 66;
  localparam logic [15:0] CODED_GRANULARITY = 16'd8;
  localparam logic [15:0] MIN_CODED_AXIS = 16'd8;
  localparam logic [15:0] BASE_CODED_AXIS = 16'd16;
  localparam logic [15:0] MAX_CODED_AXIS = 16'd24;

  logic [15:0] coded_width;
  logic [15:0] coded_height;
  logic min_axis_visible;
  logic width_uses_min_axis;
  logic width_has_extra_leaf;
  logic height_has_extra_leaf;
  logic [7:0] index_q;
  logic [7:0] byte_next;
  logic active_q;

  assign coded_width = (visible_width + CODED_GRANULARITY - 16'd1) & ~(CODED_GRANULARITY - 16'd1);
  assign coded_height = (visible_height + CODED_GRANULARITY - 16'd1) & ~(CODED_GRANULARITY - 16'd1);
  assign min_axis_visible = (coded_width == MIN_CODED_AXIS) || (coded_height == MIN_CODED_AXIS);
  assign width_uses_min_axis = coded_width == MIN_CODED_AXIS;
  assign width_has_extra_leaf = coded_width > BASE_CODED_AXIS;
  assign height_has_extra_leaf = coded_height > BASE_CODED_AXIS;
  assign supported =
    (coded_width >= MIN_CODED_AXIS) &&
    (coded_height >= MIN_CODED_AXIS) &&
    (coded_width <= MAX_CODED_AXIS) &&
    (coded_height <= MAX_CODED_AXIS) &&
    ((coded_width == BASE_CODED_AXIS) || (coded_height == BASE_CODED_AXIS)) &&
    !((coded_width == MIN_CODED_AXIS) && (coded_height == MIN_CODED_AXIS));
  assign m_axis_valid = active_q;
  assign m_axis_data = active_q ? byte_next : 8'h00;
  assign m_axis_last = active_q && (index_q == HEADER_BYTES[7:0] - 8'd1);

  always_comb begin
    byte_next = 8'h00;
    case (index_q)
      8'd0: byte_next = 8'h00;
      8'd1: byte_next = 8'h00;
      8'd2: byte_next = 8'h00;
      8'd3: byte_next = 8'h01;
      8'd4: byte_next = 8'h00;
      8'd5: byte_next = 8'h79;
      8'd6: byte_next = 8'h00;
      8'd7: byte_next = 8'h0b;
      8'd8: byte_next = 8'h02;
      8'd9: byte_next = 8'h00;
      8'd10: byte_next = 8'h80;
      8'd11: byte_next = 8'h00;
      8'd12: byte_next = min_axis_visible ? (width_uses_min_axis ? 8'h42 : 8'h41) : 8'h41;
      8'd13: byte_next = min_axis_visible ? (width_uses_min_axis ? 8'h42 : 8'h11) :
                                           (width_has_extra_leaf ? 8'h90 : 8'h10);
      8'd14: byte_next = min_axis_visible ? 8'h3f : (height_has_extra_leaf ? 8'hcf : 8'h8f);
      8'd15: byte_next = min_axis_visible ? 8'h54 : 8'hd5;
      8'd16: byte_next = min_axis_visible ? 8'h07 : 8'h01;
      8'd17: byte_next = min_axis_visible ? 8'hd1 : 8'hf4;
      8'd18: byte_next = min_axis_visible ? 8'h1b : 8'h46;
      8'd19: byte_next = min_axis_visible ? 8'ha2 : 8'he8;
      8'd20: byte_next = min_axis_visible ? 8'h11 : 8'h84;
      8'd21: byte_next = min_axis_visible ? 8'ha2 : 8'h68;
      8'd22: byte_next = min_axis_visible ? 8'h10 : 8'h84;
      8'd23: byte_next = min_axis_visible ? 8'h91 : 8'h24;
      8'd24: byte_next = min_axis_visible ? 8'h84 : 8'h61;
      8'd25: byte_next = min_axis_visible ? 8'hd8 : 8'h36;
      8'd26: byte_next = min_axis_visible ? 8'ha3 : 8'h28;
      8'd27: byte_next = min_axis_visible ? 8'h15 : 8'hc5;
      8'd28: byte_next = min_axis_visible ? 8'h0c : 8'h43;
      8'd29: byte_next = min_axis_visible ? 8'h1a : 8'h06;
      8'd30: byte_next = min_axis_visible ? 8'h02 : 8'h80;
      8'd31: byte_next = min_axis_visible ? 8'hae : 8'hab;
      8'd32: byte_next = min_axis_visible ? 8'h3f : 8'h8f;
      8'd33: byte_next = min_axis_visible ? 8'h82 : 8'he0;
      8'd34: byte_next = min_axis_visible ? 8'hb0 : 8'hac;
      8'd35: byte_next = min_axis_visible ? 8'h40 : 8'h10;
      8'd36: byte_next = min_axis_visible ? 8'h80 : 8'h20;
      8'd37: byte_next = 8'h00;
      8'd38: byte_next = 8'h00;
      8'd39: byte_next = 8'h00;
      8'd40: byte_next = 8'h01;
      8'd41: byte_next = 8'h00;
      8'd42: byte_next = 8'h81;
      8'd43: byte_next = 8'h00;
      8'd44: byte_next = min_axis_visible ? (width_uses_min_axis ? 8'h02 : 8'h01) : 8'h01;
      8'd45: byte_next = min_axis_visible ? (width_uses_min_axis ? 8'h42 : 8'h11) :
                                           (width_has_extra_leaf ? 8'h90 : 8'h10);
      8'd46: byte_next = min_axis_visible ? 8'h22 : (height_has_extra_leaf ? 8'hc8 : 8'h88);
      8'd47: byte_next = min_axis_visible ? 8'h90 : 8'ha4;
      8'd48: byte_next = min_axis_visible ? 8'h80 : 8'h20;
      8'd49: byte_next = min_axis_visible ? 8'h31 : 8'h0c;
      8'd50: byte_next = min_axis_visible ? 8'hec : 8'h7b;
      8'd51: byte_next = min_axis_visible ? 8'h85 : 8'h21;
      8'd52: byte_next = min_axis_visible ? 8'h16 : 8'h45;
      8'd53: byte_next = min_axis_visible ? 8'h51 : 8'h94;
      8'd54: byte_next = min_axis_visible ? 8'h65 : 8'h59;
      8'd55: byte_next = min_axis_visible ? 8'h16 : 8'h45;
      8'd56: byte_next = min_axis_visible ? 8'h20 : 8'h88;
      8'd57: byte_next = 8'h00;
      8'd58: byte_next = 8'h00;
      8'd59: byte_next = 8'h00;
      8'd60: byte_next = 8'h01;
      8'd61: byte_next = 8'h00;
      8'd62: byte_next = 8'h41;
      8'd63: byte_next = 8'hc4;
      8'd64: byte_next = 8'h00;
      8'd65: byte_next = 8'h70;
      default: byte_next = 8'h00;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      index_q <= 8'd0;
      active_q <= 1'b0;
      done <= 1'b0;
    end else if (clear) begin
      index_q <= 8'd0;
      active_q <= 1'b0;
      done <= 1'b0;
    end else begin
      done <= 1'b0;

      if (start) begin
        index_q <= 8'd0;
        active_q <= supported;
        done <= !supported;
      end else if (m_axis_valid && m_axis_ready) begin
        if (m_axis_last) begin
          index_q <= 8'd0;
          active_q <= 1'b0;
          done <= 1'b1;
        end else begin
          index_q <= index_q + 8'd1;
        end
      end
    end
  end
endmodule
