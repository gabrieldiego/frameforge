`timescale 1ns/1ps

module ff_vvc_emulation_prevention_stream (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       clear,

  input  logic       s_axis_valid,
  output logic       s_axis_ready,
  input  logic [7:0] s_axis_data,
  input  logic       s_axis_last,

  input  logic       m_axis_ready,
  output logic       m_axis_valid,
  output logic [7:0] m_axis_data,
  output logic       m_axis_last,
  output logic       done
);
  typedef enum logic [1:0] {
    ST_STREAM,
    ST_EMIT_HELD
  } state_t;

  state_t state_q;
  logic [1:0] zero_count_q;
  logic [7:0] held_data_q;
  logic       held_last_q;
  logic       need_insert_w;

  assign need_insert_w = (zero_count_q == 2'd2) && (s_axis_data <= 8'h03);
  assign s_axis_ready = (state_q == ST_STREAM) && (!m_axis_valid || m_axis_ready);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_STREAM;
      zero_count_q <= 2'd0;
      held_data_q <= 8'd0;
      held_last_q <= 1'b0;
      m_axis_valid <= 1'b0;
      m_axis_data <= 8'd0;
      m_axis_last <= 1'b0;
      done <= 1'b0;
    end else if (clear) begin
      state_q <= ST_STREAM;
      zero_count_q <= 2'd0;
      held_data_q <= 8'd0;
      held_last_q <= 1'b0;
      m_axis_valid <= 1'b0;
      m_axis_data <= 8'd0;
      m_axis_last <= 1'b0;
      done <= 1'b0;
    end else begin
      done <= 1'b0;

      if (m_axis_valid && !m_axis_ready) begin
        state_q <= state_q;
      end else begin
        m_axis_valid <= 1'b0;
        m_axis_last <= 1'b0;

        case (state_q)
          ST_STREAM: begin
            if (s_axis_valid) begin
              if (need_insert_w) begin
                held_data_q <= s_axis_data;
                held_last_q <= s_axis_last;
                m_axis_valid <= 1'b1;
                m_axis_data <= 8'h03;
                m_axis_last <= 1'b0;
                zero_count_q <= 2'd0;
                state_q <= ST_EMIT_HELD;
              end else begin
                m_axis_valid <= 1'b1;
                m_axis_data <= s_axis_data;
                m_axis_last <= s_axis_last;
                if (s_axis_data == 8'h00) begin
                  zero_count_q <= (zero_count_q == 2'd2) ? 2'd2 : (zero_count_q + 2'd1);
                end else begin
                  zero_count_q <= 2'd0;
                end
                if (s_axis_last) begin
                  done <= 1'b1;
                  zero_count_q <= 2'd0;
                end
              end
            end
          end

          ST_EMIT_HELD: begin
            m_axis_valid <= 1'b1;
            m_axis_data <= held_data_q;
            m_axis_last <= held_last_q;
            if (held_data_q == 8'h00) begin
              zero_count_q <= 2'd1;
            end else begin
              zero_count_q <= 2'd0;
            end
            if (held_last_q) begin
              done <= 1'b1;
              zero_count_q <= 2'd0;
            end
            state_q <= ST_STREAM;
          end

          default: begin
            state_q <= ST_STREAM;
          end
        endcase
      end
    end
  end
endmodule
