`timescale 1ns/1ps

module ff_ffbs_gray4x4_encoder (
  input  logic       clk,
  input  logic       rst_n,

  input  logic       s_axis_valid,
  output logic       s_axis_ready,
  input  logic [7:0] s_axis_data,
  input  logic       s_axis_last,

  output logic       m_axis_valid,
  input  logic       m_axis_ready,
  output logic [7:0] m_axis_data,
  output logic       m_axis_last
);
  localparam int HEADER_LEN = 15;
  localparam int SAMPLE_LEN = 16;
  localparam int TOTAL_LEN  = HEADER_LEN + SAMPLE_LEN;

  typedef enum logic [1:0] {
    ST_INPUT,
    ST_EMIT
  } state_t;

  state_t state_q;
  logic [4:0] in_count_q;
  logic [5:0] out_count_q;
  logic [7:0] samples_q [0:SAMPLE_LEN-1];

  assign s_axis_ready = (state_q == ST_INPUT);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q      <= ST_INPUT;
      in_count_q   <= '0;
      out_count_q  <= '0;
      m_axis_valid <= 1'b0;
      m_axis_data  <= '0;
      m_axis_last  <= 1'b0;
    end else begin
      case (state_q)
        ST_INPUT: begin
          m_axis_valid <= 1'b0;
          m_axis_last  <= 1'b0;
          if (s_axis_valid && s_axis_ready) begin
            samples_q[in_count_q] <= s_axis_data;
            if (in_count_q == SAMPLE_LEN - 1) begin
              state_q     <= ST_EMIT;
              out_count_q <= '0;
            end
            in_count_q <= in_count_q + 1'b1;
          end
        end

        ST_EMIT: begin
          if (!m_axis_valid || m_axis_ready) begin
            m_axis_valid <= 1'b1;
            m_axis_data  <= output_byte(out_count_q);
            m_axis_last  <= (out_count_q == TOTAL_LEN - 1);
            if (out_count_q == TOTAL_LEN - 1) begin
              state_q     <= ST_INPUT;
              in_count_q  <= '0;
              out_count_q <= '0;
            end else begin
              out_count_q <= out_count_q + 1'b1;
            end
          end
        end

        default: state_q <= ST_INPUT;
      endcase
    end
  end

  function automatic logic [7:0] output_byte(input logic [5:0] index);
    case (index)
      6'd0:  output_byte = 8'h46; // F
      6'd1:  output_byte = 8'h46; // F
      6'd2:  output_byte = 8'h42; // B
      6'd3:  output_byte = 8'h53; // S
      6'd4:  output_byte = 8'h01; // version
      6'd5:  output_byte = 8'h01; // raw gray8 intra codec id
      6'd6:  output_byte = 8'h00; // width high
      6'd7:  output_byte = 8'h04; // width low
      6'd8:  output_byte = 8'h00; // height high
      6'd9:  output_byte = 8'h04; // height low
      6'd10: output_byte = 8'h01; // gray8 format id
      6'd11: output_byte = 8'h00; // payload length
      6'd12: output_byte = 8'h00;
      6'd13: output_byte = 8'h00;
      6'd14: output_byte = 8'h10;
      default: output_byte = samples_q[index - HEADER_LEN];
    endcase
  endfunction
endmodule
