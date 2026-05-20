`timescale 1ns/1ps

module ff_min_encoder_stub #(
  parameter int DATA_WIDTH = 64
) (
  input  logic                  clk,
  input  logic                  rst_n,

  input  logic                  s_axis_valid,
  output logic                  s_axis_ready,
  input  logic [DATA_WIDTH-1:0] s_axis_data,
  input  logic                  s_axis_last,

  output logic                  m_axis_valid,
  input  logic                  m_axis_ready,
  output logic [DATA_WIDTH-1:0] m_axis_data,
  output logic                  m_axis_last
);
  localparam logic [DATA_WIDTH-1:0] FF_PLACEHOLDER_WORD = 64'h4646_454e_435f_3031;

  typedef enum logic [1:0] {
    ST_IDLE,
    ST_DRAIN_INPUT,
    ST_EMIT
  } state_t;

  state_t state_q;

  assign s_axis_ready = (state_q == ST_IDLE) || (state_q == ST_DRAIN_INPUT);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q       <= ST_IDLE;
      m_axis_valid  <= 1'b0;
      m_axis_data   <= '0;
      m_axis_last   <= 1'b0;
    end else begin
      if (m_axis_valid && m_axis_ready) begin
        m_axis_valid <= 1'b0;
        m_axis_last  <= 1'b0;
      end

      unique case (state_q)
        ST_IDLE: begin
          if (s_axis_valid && s_axis_ready) begin
            state_q <= s_axis_last ? ST_EMIT : ST_DRAIN_INPUT;
          end
        end

        ST_DRAIN_INPUT: begin
          if (s_axis_valid && s_axis_ready && s_axis_last) begin
            state_q <= ST_EMIT;
          end
        end

        ST_EMIT: begin
          if (!m_axis_valid || m_axis_ready) begin
            m_axis_valid <= 1'b1;
            m_axis_data  <= FF_PLACEHOLDER_WORD;
            m_axis_last  <= 1'b1;
            state_q      <= ST_IDLE;
          end
        end

        default: state_q <= ST_IDLE;
      endcase
    end
  end
endmodule

