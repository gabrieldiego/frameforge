`timescale 1ns/1ps

module ff_vvc_skeleton_encoder (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       start,
  output logic       busy,

  output logic       m_axis_valid,
  input  logic       m_axis_ready,
  output logic [7:0] m_axis_data,
  output logic       m_axis_last
);
  localparam int STREAM_LEN = 40;

  logic [5:0] index_q;

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
        m_axis_data  <= stream_byte(6'd0);
        m_axis_last  <= 1'b0;
        index_q      <= 6'd1;
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

  function automatic logic [7:0] stream_byte(input logic [5:0] index);
    case (index)
      6'd0:  stream_byte = 8'h00;
      6'd1:  stream_byte = 8'h00;
      6'd2:  stream_byte = 8'h00;
      6'd3:  stream_byte = 8'h01;
      6'd4:  stream_byte = 8'h00;
      6'd5:  stream_byte = 8'h71;
      6'd6:  stream_byte = 8'h80;
      6'd7:  stream_byte = 8'h00;
      6'd8:  stream_byte = 8'h00;
      6'd9:  stream_byte = 8'h00;
      6'd10: stream_byte = 8'h01;
      6'd11: stream_byte = 8'h00;
      6'd12: stream_byte = 8'h79;
      6'd13: stream_byte = 8'h80;
      6'd14: stream_byte = 8'h00;
      6'd15: stream_byte = 8'h00;
      6'd16: stream_byte = 8'h00;
      6'd17: stream_byte = 8'h01;
      6'd18: stream_byte = 8'h00;
      6'd19: stream_byte = 8'h81;
      6'd20: stream_byte = 8'h80;
      6'd21: stream_byte = 8'h00;
      6'd22: stream_byte = 8'h00;
      6'd23: stream_byte = 8'h00;
      6'd24: stream_byte = 8'h01;
      6'd25: stream_byte = 8'h00;
      6'd26: stream_byte = 8'h41;
      6'd27: stream_byte = 8'h80;
      6'd28: stream_byte = 8'h00;
      6'd29: stream_byte = 8'h00;
      6'd30: stream_byte = 8'h00;
      6'd31: stream_byte = 8'h01;
      6'd32: stream_byte = 8'h00;
      6'd33: stream_byte = 8'ha9;
      6'd34: stream_byte = 8'h00;
      6'd35: stream_byte = 8'h00;
      6'd36: stream_byte = 8'h00;
      6'd37: stream_byte = 8'h01;
      6'd38: stream_byte = 8'h00;
      6'd39: stream_byte = 8'hb1;
      default: stream_byte = 8'h00;
    endcase
  endfunction
endmodule
