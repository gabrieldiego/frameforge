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
  input  logic        ctu_last,

  output logic        m_axis_valid,
  input  logic        m_axis_ready,
  output logic [7:0]  m_axis_kind,
  output logic [31:0] m_axis_data,
  output logic        m_axis_last
);
  logic unused_ctu_inputs;

  // Migration bridge: currently only forwards already-generated CABAC symbols.
  // CTU/residual/palette syntax producers will replace this raw path as they
  // are moved out of the monolithic generated body.
  assign raw_symbol_ready = m_axis_ready;
  assign m_axis_valid = raw_symbol_valid;
  assign m_axis_kind = raw_symbol_kind;
  assign m_axis_data = raw_symbol_data;
  assign m_axis_last = raw_symbol_last;

  // CTU syntax generation is intentionally not implemented here yet. Keeping a
  // real handshake boundary makes it clear where partition, intra, residual,
  // palette, and future inter syntax producers plug into the CABAC pipeline.
  assign ctu_ready = 1'b0;
  assign unused_ctu_inputs = ctu_valid || ctu_last || (|ctu_x) || (|ctu_y) ||
                             (|ctu_visible_width) || (|ctu_visible_height) ||
                             clk || rst_n || clear;
endmodule
