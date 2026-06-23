`timescale 1ns/1ps

module ff_vvc_rbsp_payload_stream (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       clear,

  input  logic       s_axis_valid,
  output logic       s_axis_ready,
  input  logic [7:0] s_axis_data,
  input  logic       s_axis_last,
  input  logic [2:0] s_axis_last_byte_bits,

  input  logic       m_axis_ready,
  output logic       m_axis_valid,
  output logic [7:0] m_axis_data,
  output logic       m_axis_last,
  output logic       done
);
  typedef enum logic [1:0] {
    ST_STREAM,
    ST_TAIL_FINAL,
    ST_TAIL_HELD,
    ST_TAIL_EXTRA
  } state_t;

  state_t state_q;
  logic hold_valid_q;
  logic [7:0] hold_byte_q;
  logic [7:0] tail_byte_q;

  logic [7:0] rbsp_tail_byte;

  always @* begin
    case (s_axis_last_byte_bits)
      3'd1: rbsp_tail_byte = (s_axis_data & 8'b1000_0000) | 8'h40;
      3'd2: rbsp_tail_byte = (s_axis_data & 8'b1100_0000) | 8'h20;
      3'd3: rbsp_tail_byte = (s_axis_data & 8'b1110_0000) | 8'h10;
      3'd4: rbsp_tail_byte = (s_axis_data & 8'b1111_0000) | 8'h08;
      3'd5: rbsp_tail_byte = (s_axis_data & 8'b1111_1000) | 8'h04;
      3'd6: rbsp_tail_byte = (s_axis_data & 8'b1111_1100) | 8'h02;
      3'd7: rbsp_tail_byte = (s_axis_data & 8'b1111_1110) | 8'h01;
      default: rbsp_tail_byte = 8'h80;
    endcase
  end

  assign s_axis_ready = (state_q == ST_STREAM) && (!hold_valid_q || m_axis_ready);
  assign m_axis_valid = (state_q == ST_STREAM) ? hold_valid_q : 1'b1;
  assign m_axis_data = (state_q == ST_STREAM) ? hold_byte_q : tail_byte_q;
  assign m_axis_last =
    (state_q == ST_TAIL_FINAL) || (state_q == ST_TAIL_EXTRA);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_STREAM;
      hold_valid_q <= 1'b0;
      hold_byte_q <= 8'd0;
      tail_byte_q <= 8'd0;
      done <= 1'b0;
    end else if (clear) begin
      state_q <= ST_STREAM;
      hold_valid_q <= 1'b0;
      hold_byte_q <= 8'd0;
      tail_byte_q <= 8'd0;
      done <= 1'b0;
    end else begin
      done <= 1'b0;

      case (state_q)
        ST_STREAM: begin
          if (hold_valid_q && m_axis_ready) begin
            hold_valid_q <= 1'b0;
          end
          if (s_axis_valid && s_axis_ready) begin
            if (s_axis_last) begin
              hold_valid_q <= 1'b0;
              if (s_axis_last_byte_bits == 3'd0) begin
                // H.266 7.3.7 byte_alignment(): byte-aligned CABAC payloads
                // keep the final CABAC byte, then append rbsp_trailing_bits().
                tail_byte_q <= s_axis_data;
                state_q <= ST_TAIL_HELD;
              end else begin
                // H.266 7.3.7 byte_alignment(): non-byte-aligned final bytes
                // replace unused bits with a stop bit and zero padding.
                tail_byte_q <= rbsp_tail_byte;
                state_q <= ST_TAIL_FINAL;
              end
            end else begin
              hold_valid_q <= 1'b1;
              hold_byte_q <= s_axis_data;
            end
          end
        end

        ST_TAIL_HELD: begin
          if (m_axis_ready) begin
            tail_byte_q <= 8'h80;
            state_q <= ST_TAIL_EXTRA;
          end
        end

        ST_TAIL_FINAL,
        ST_TAIL_EXTRA: begin
          if (m_axis_ready) begin
            done <= 1'b1;
            state_q <= ST_STREAM;
          end
        end

        default: begin
          state_q <= ST_STREAM;
        end
      endcase
    end
  end
endmodule
