`timescale 1ns/1ps

module ff_vvc_annexb_header (
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,
  input  logic [7:0]  index,
  output logic [7:0]  byte_value,
  output logic [7:0]  byte_count,
  output logic        supported
);
  // Temporary integration fixture: this byte sequence mirrors the Rust
  // generated 16x16 yuv420p8 SPS/PPS/slice prefix so the RTL byte-stream
  // interface can be validated end-to-end. Replace this with parameter-driven
  // SPS/PPS/slice-header writers before expanding RTL Annex-B support.
  assign supported = (visible_width == 16'd16) && (visible_height == 16'd16);
  assign byte_count = supported ? 8'd66 : 8'd0;

  always_comb begin
    byte_value = 8'h00;
    if (supported) begin
      case (index)
        8'd0: byte_value = 8'h00;
        8'd1: byte_value = 8'h00;
        8'd2: byte_value = 8'h00;
        8'd3: byte_value = 8'h01;
        8'd4: byte_value = 8'h00;
        8'd5: byte_value = 8'h79;
        8'd6: byte_value = 8'h00;
        8'd7: byte_value = 8'h0b;
        8'd8: byte_value = 8'h02;
        8'd9: byte_value = 8'h00;
        8'd10: byte_value = 8'h80;
        8'd11: byte_value = 8'h00;
        8'd12: byte_value = 8'h41;
        8'd13: byte_value = 8'h10;
        8'd14: byte_value = 8'h8f;
        8'd15: byte_value = 8'hd5;
        8'd16: byte_value = 8'h01;
        8'd17: byte_value = 8'hf4;
        8'd18: byte_value = 8'h46;
        8'd19: byte_value = 8'he8;
        8'd20: byte_value = 8'h84;
        8'd21: byte_value = 8'h68;
        8'd22: byte_value = 8'h84;
        8'd23: byte_value = 8'h24;
        8'd24: byte_value = 8'h61;
        8'd25: byte_value = 8'h36;
        8'd26: byte_value = 8'h28;
        8'd27: byte_value = 8'hc5;
        8'd28: byte_value = 8'h43;
        8'd29: byte_value = 8'h06;
        8'd30: byte_value = 8'h80;
        8'd31: byte_value = 8'hab;
        8'd32: byte_value = 8'h8f;
        8'd33: byte_value = 8'he0;
        8'd34: byte_value = 8'hac;
        8'd35: byte_value = 8'h10;
        8'd36: byte_value = 8'h20;
        8'd37: byte_value = 8'h00;
        8'd38: byte_value = 8'h00;
        8'd39: byte_value = 8'h00;
        8'd40: byte_value = 8'h01;
        8'd41: byte_value = 8'h00;
        8'd42: byte_value = 8'h81;
        8'd43: byte_value = 8'h00;
        8'd44: byte_value = 8'h01;
        8'd45: byte_value = 8'h10;
        8'd46: byte_value = 8'h88;
        8'd47: byte_value = 8'ha4;
        8'd48: byte_value = 8'h20;
        8'd49: byte_value = 8'h0c;
        8'd50: byte_value = 8'h7b;
        8'd51: byte_value = 8'h21;
        8'd52: byte_value = 8'h45;
        8'd53: byte_value = 8'h94;
        8'd54: byte_value = 8'h59;
        8'd55: byte_value = 8'h45;
        8'd56: byte_value = 8'h88;
        8'd57: byte_value = 8'h00;
        8'd58: byte_value = 8'h00;
        8'd59: byte_value = 8'h00;
        8'd60: byte_value = 8'h01;
        8'd61: byte_value = 8'h00;
        8'd62: byte_value = 8'h41;
        8'd63: byte_value = 8'hc4;
        8'd64: byte_value = 8'h00;
        8'd65: byte_value = 8'h70;
        default: byte_value = 8'h00;
      endcase
    end
  end
endmodule
