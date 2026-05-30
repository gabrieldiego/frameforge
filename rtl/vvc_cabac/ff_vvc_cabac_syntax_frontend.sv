`timescale 1ns/1ps

module ff_vvc_cabac_syntax_frontend (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        clear,

  input  logic        raw_symbol_valid,
  output logic        raw_symbol_ready,
  input  logic [7:0]  raw_symbol_kind,
  input  logic [31:0] raw_symbol_data,
  input  logic        raw_symbol_last,

  input  logic        ctu_valid,
  output logic        ctu_ready,
  input  logic [15:0] ctu_x,
  input  logic [15:0] ctu_y,
  input  logic [15:0] ctu_visible_width,
  input  logic [15:0] ctu_visible_height,
  input  logic [4:0]  ctu_luma_dc_abs_level,
  input  logic        ctu_luma_dc_negative,
  input  logic        ctu_luma_only,
  input  logic        ctu_last,

  output logic        m_axis_valid,
  input  logic        m_axis_ready,
  output logic [7:0]  m_axis_kind,
  output logic [31:0] m_axis_data,
  output logic        m_axis_last
);
  logic unused_inputs;

  assign raw_symbol_ready = m_axis_ready;
  assign ctu_ready = 1'b0;

  assign m_axis_valid = raw_symbol_valid;
  assign m_axis_kind = raw_symbol_kind;
  assign m_axis_data = raw_symbol_data;
  assign m_axis_last = raw_symbol_last;

  assign unused_inputs = clk || rst_n || clear || ctu_valid || (|ctu_x) || (|ctu_y) ||
    (|ctu_visible_width) || (|ctu_visible_height) || (|ctu_luma_dc_abs_level) ||
    ctu_luma_dc_negative || ctu_luma_only || ctu_last;
endmodule
