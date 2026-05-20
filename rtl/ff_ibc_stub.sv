`timescale 1ns/1ps

module ff_ibc_stub #(
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
  // Future intra-block-copy placeholder. Not implemented.
  assign s_axis_ready = !m_axis_valid || m_axis_ready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      m_axis_valid <= 1'b0;
      m_axis_data  <= '0;
      m_axis_last  <= 1'b0;
    end else if (s_axis_ready) begin
      m_axis_valid <= s_axis_valid;
      m_axis_data  <= s_axis_data;
      m_axis_last  <= s_axis_last;
    end
  end
endmodule

