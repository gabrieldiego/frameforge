`timescale 1ns/1ps

module ff_vvc_fixture4x4_2frame_encoder (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       start,
  output logic       busy,

  output logic       m_axis_valid,
  input  logic       m_axis_ready,
  output logic [7:0] m_axis_data,
  output logic       m_axis_last
);
  localparam int STREAM_LEN = 146;

  logic [7:0] index_q;

  assign busy = m_axis_valid || (index_q != 0);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      index_q      <= '0;
      m_axis_valid <= 1'b0;
      m_axis_data  <= '0;
      m_axis_last  <= 1'b0;
    end else begin
      if (start && !busy) begin
        m_axis_valid <= 1'b1;
        m_axis_data  <= stream_byte(8'd0);
        m_axis_last  <= 1'b0;
        index_q      <= 8'd1;
      end else if (m_axis_valid && m_axis_ready) begin
        if (index_q == STREAM_LEN) begin
          m_axis_valid <= 1'b0;
          m_axis_last  <= 1'b0;
          index_q      <= '0;
        end else begin
          m_axis_data <= stream_byte(index_q);
          m_axis_last <= (index_q == STREAM_LEN - 1);
          index_q     <= index_q + 1'b1;
        end
      end
    end
  end

  function automatic logic [7:0] stream_byte(input logic [7:0] index);
    logic second_access_unit;
    logic [6:0] frame_index;

    begin
      second_access_unit = (index >= 8'd73);
      frame_index = second_access_unit ? (index - 8'd73) : index[6:0];
      stream_byte = access_unit_byte(frame_index);
      if (second_access_unit) begin
        case (frame_index)
          7'd61: stream_byte = 8'h49; // CRA NAL header for frame 1.
          7'd63: stream_byte = 8'h04;
          7'd64: stream_byte = 8'h78;
          default: begin end
        endcase
      end
    end
  endfunction

  function automatic logic [7:0] access_unit_byte(input logic [6:0] index);
    case (index)
      7'd0:  access_unit_byte = 8'h00;
      7'd1:  access_unit_byte = 8'h00;
      7'd2:  access_unit_byte = 8'h00;
      7'd3:  access_unit_byte = 8'h01;
      7'd4:  access_unit_byte = 8'h00;
      7'd5:  access_unit_byte = 8'h79;
      7'd6:  access_unit_byte = 8'h00;
      7'd7:  access_unit_byte = 8'h0b;
      7'd8:  access_unit_byte = 8'h02;
      7'd9:  access_unit_byte = 8'h00;
      7'd10: access_unit_byte = 8'h80;
      7'd11: access_unit_byte = 8'h00;
      7'd12: access_unit_byte = 8'h42;
      7'd13: access_unit_byte = 8'h44;
      7'd14: access_unit_byte = 8'hee;
      7'd15: access_unit_byte = 8'hd5;
      7'd16: access_unit_byte = 8'h01;
      7'd17: access_unit_byte = 8'hf4;
      7'd18: access_unit_byte = 8'h46;
      7'd19: access_unit_byte = 8'he8;
      7'd20: access_unit_byte = 8'h84;
      7'd21: access_unit_byte = 8'h68;
      7'd22: access_unit_byte = 8'h84;
      7'd23: access_unit_byte = 8'h24;
      7'd24: access_unit_byte = 8'h61;
      7'd25: access_unit_byte = 8'h36;
      7'd26: access_unit_byte = 8'h28;
      7'd27: access_unit_byte = 8'hc5;
      7'd28: access_unit_byte = 8'h43;
      7'd29: access_unit_byte = 8'h06;
      7'd30: access_unit_byte = 8'h80;
      7'd31: access_unit_byte = 8'hab;
      7'd32: access_unit_byte = 8'h8f;
      7'd33: access_unit_byte = 8'he0;
      7'd34: access_unit_byte = 8'hac;
      7'd35: access_unit_byte = 8'h10;
      7'd36: access_unit_byte = 8'h20;
      7'd37: access_unit_byte = 8'h00;
      7'd38: access_unit_byte = 8'h00;
      7'd39: access_unit_byte = 8'h00;
      7'd40: access_unit_byte = 8'h01;
      7'd41: access_unit_byte = 8'h00;
      7'd42: access_unit_byte = 8'h81;
      7'd43: access_unit_byte = 8'h00;
      7'd44: access_unit_byte = 8'h02;
      7'd45: access_unit_byte = 8'h44;
      7'd46: access_unit_byte = 8'h8a;
      7'd47: access_unit_byte = 8'h42;
      7'd48: access_unit_byte = 8'h00;
      7'd49: access_unit_byte = 8'hc7;
      7'd50: access_unit_byte = 8'hb2;
      7'd51: access_unit_byte = 8'h14;
      7'd52: access_unit_byte = 8'h59;
      7'd53: access_unit_byte = 8'h45;
      7'd54: access_unit_byte = 8'h94;
      7'd55: access_unit_byte = 8'h58;
      7'd56: access_unit_byte = 8'h80;
      7'd57: access_unit_byte = 8'h00;
      7'd58: access_unit_byte = 8'h00;
      7'd59: access_unit_byte = 8'h01;
      7'd60: access_unit_byte = 8'h00;
      7'd61: access_unit_byte = 8'h41;
      7'd62: access_unit_byte = 8'hc4;
      7'd63: access_unit_byte = 8'h00;
      7'd64: access_unit_byte = 8'h70;
      7'd65: access_unit_byte = 8'h80;
      7'd66: access_unit_byte = 8'h62;
      7'd67: access_unit_byte = 8'hf5;
      7'd68: access_unit_byte = 8'hb7;
      7'd69: access_unit_byte = 8'heb;
      7'd70: access_unit_byte = 8'hcb;
      7'd71: access_unit_byte = 8'h1f;
      7'd72: access_unit_byte = 8'h80;
      default: access_unit_byte = 8'h00;
    endcase
  endfunction
endmodule
