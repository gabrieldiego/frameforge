`timescale 1ns/1ps

module ff_vvc_fixture4x4_encoder (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       start,
  output logic       busy,

  output logic       m_axis_valid,
  input  logic       m_axis_ready,
  output logic [7:0] m_axis_data,
  output logic       m_axis_last
);
  localparam int STREAM_LEN = 73;

  logic [6:0] index_q;

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
        m_axis_data  <= stream_byte(7'd0);
        m_axis_last  <= 1'b0;
        index_q      <= 7'd1;
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

  function automatic logic [7:0] stream_byte(input logic [6:0] index);
    case (index)
      7'd0:  stream_byte = 8'h00;
      7'd1:  stream_byte = 8'h00;
      7'd2:  stream_byte = 8'h00;
      7'd3:  stream_byte = 8'h01;
      7'd4:  stream_byte = 8'h00;
      7'd5:  stream_byte = 8'h79;
      7'd6:  stream_byte = 8'h00;
      7'd7:  stream_byte = 8'h0b;
      7'd8:  stream_byte = 8'h02;
      7'd9:  stream_byte = 8'h00;
      7'd10: stream_byte = 8'h80;
      7'd11: stream_byte = 8'h00;
      7'd12: stream_byte = 8'h42;
      7'd13: stream_byte = 8'h44;
      7'd14: stream_byte = 8'hee;
      7'd15: stream_byte = 8'hd5;
      7'd16: stream_byte = 8'h01;
      7'd17: stream_byte = 8'hf4;
      7'd18: stream_byte = 8'h46;
      7'd19: stream_byte = 8'he8;
      7'd20: stream_byte = 8'h84;
      7'd21: stream_byte = 8'h68;
      7'd22: stream_byte = 8'h84;
      7'd23: stream_byte = 8'h24;
      7'd24: stream_byte = 8'h61;
      7'd25: stream_byte = 8'h36;
      7'd26: stream_byte = 8'h28;
      7'd27: stream_byte = 8'hc5;
      7'd28: stream_byte = 8'h43;
      7'd29: stream_byte = 8'h06;
      7'd30: stream_byte = 8'h80;
      7'd31: stream_byte = 8'hab;
      7'd32: stream_byte = 8'h8f;
      7'd33: stream_byte = 8'he0;
      7'd34: stream_byte = 8'hac;
      7'd35: stream_byte = 8'h10;
      7'd36: stream_byte = 8'h20;
      7'd37: stream_byte = 8'h00;
      7'd38: stream_byte = 8'h00;
      7'd39: stream_byte = 8'h00;
      7'd40: stream_byte = 8'h01;
      7'd41: stream_byte = 8'h00;
      7'd42: stream_byte = 8'h81;
      7'd43: stream_byte = 8'h00;
      7'd44: stream_byte = 8'h02;
      7'd45: stream_byte = 8'h44;
      7'd46: stream_byte = 8'h8a;
      7'd47: stream_byte = 8'h42;
      7'd48: stream_byte = 8'h00;
      7'd49: stream_byte = 8'hc7;
      7'd50: stream_byte = 8'hb2;
      7'd51: stream_byte = 8'h14;
      7'd52: stream_byte = 8'h59;
      7'd53: stream_byte = 8'h45;
      7'd54: stream_byte = 8'h94;
      7'd55: stream_byte = 8'h58;
      7'd56: stream_byte = 8'h80;
      7'd57: stream_byte = 8'h00;
      7'd58: stream_byte = 8'h00;
      7'd59: stream_byte = 8'h01;
      7'd60: stream_byte = 8'h00;
      7'd61: stream_byte = 8'h41;
      7'd62: stream_byte = 8'hc4;
      7'd63: stream_byte = 8'h00;
      7'd64: stream_byte = 8'h70;
      7'd65: stream_byte = 8'h80;
      7'd66: stream_byte = 8'h62;
      7'd67: stream_byte = 8'hf5;
      7'd68: stream_byte = 8'hb7;
      7'd69: stream_byte = 8'heb;
      7'd70: stream_byte = 8'hcb;
      7'd71: stream_byte = 8'h1f;
      7'd72: stream_byte = 8'h80;
      default: stream_byte = 8'h00;
    endcase
  endfunction
endmodule
