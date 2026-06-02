`timescale 1ns/1ps

module ff_vvc_cabac_symbol_binarizer #(
  parameter int VVC_CABAC_CTX_ID_BITS = 10
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        clear,

  input  logic        s_axis_valid,
  output logic        s_axis_ready,
  input  logic [7:0]  s_axis_kind,
  input  logic [31:0] s_axis_data,
  input  logic        s_axis_last,

  output logic        m_axis_valid,
  input  logic        m_axis_ready,
  output logic [2:0]  m_axis_kind,
  output logic        m_axis_bin,
  output logic [31:0] m_axis_bins_pattern,
  output logic [5:0]  m_axis_bins_count,
  output logic        m_axis_ctx_valid,
  output logic [VVC_CABAC_CTX_ID_BITS - 1:0] m_axis_ctx_id,
  output logic [8:0]  m_axis_lps,
  output logic        m_axis_mps,
  output logic        m_axis_last
);
  localparam logic [7:0] SYMBOL_BIN_EP  = 8'd0;
  localparam logic [7:0] SYMBOL_BIN_TRM = 8'd1;
  localparam logic [7:0] SYMBOL_BIN_CTX = 8'd2;
  localparam logic [7:0] SYMBOL_BIN_CTX_DIRECT = 8'd3;
  localparam logic [7:0] SYMBOL_BINS_EP = 8'd4;

  localparam logic [2:0] CABAC_BIN_EP  = 3'd0;
  localparam logic [2:0] CABAC_BIN_TRM = 3'd1;
  localparam logic [2:0] CABAC_BIN_CTX = 3'd2;
  localparam logic [2:0] CABAC_BINS_EP = 3'd3;

  logic        valid_q;
  logic [2:0]  kind_q;
  logic        bin_q;
  logic [31:0] bins_pattern_q;
  logic [5:0]  bins_count_q;
  logic        ctx_valid_q;
  logic [VVC_CABAC_CTX_ID_BITS - 1:0] ctx_id_q;
  logic [8:0]  lps_q;
  logic        mps_q;
  logic        last_q;
  logic [2:0]  symbol_kind_mapped;

  assign s_axis_ready = !valid_q || m_axis_ready;
  assign m_axis_valid = valid_q;
  assign m_axis_kind = kind_q;
  assign m_axis_bin = bin_q;
  assign m_axis_bins_pattern = bins_pattern_q;
  assign m_axis_bins_count = bins_count_q;
  assign m_axis_ctx_valid = ctx_valid_q;
  assign m_axis_ctx_id = ctx_id_q;
  assign m_axis_lps = lps_q;
  assign m_axis_mps = mps_q;
  assign m_axis_last = last_q;

  always_comb begin
    case (s_axis_kind)
      SYMBOL_BIN_TRM: symbol_kind_mapped = CABAC_BIN_TRM;
      SYMBOL_BIN_CTX,
      SYMBOL_BIN_CTX_DIRECT: symbol_kind_mapped = CABAC_BIN_CTX;
      SYMBOL_BINS_EP: symbol_kind_mapped = CABAC_BINS_EP;
      default: symbol_kind_mapped = CABAC_BIN_EP;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_q <= 1'b0;
      kind_q <= CABAC_BIN_EP;
      bin_q <= 1'b0;
      bins_pattern_q <= 32'd0;
      bins_count_q <= 6'd1;
      ctx_valid_q <= 1'b0;
      ctx_id_q <= 6'd0;
      lps_q <= 9'd4;
      mps_q <= 1'b0;
      last_q <= 1'b0;
    end else if (clear) begin
      valid_q <= 1'b0;
      kind_q <= CABAC_BIN_EP;
      bin_q <= 1'b0;
      bins_pattern_q <= 32'd0;
      bins_count_q <= 6'd1;
      ctx_valid_q <= 1'b0;
      ctx_id_q <= 6'd0;
      lps_q <= 9'd4;
      mps_q <= 1'b0;
      last_q <= 1'b0;
    end else if (s_axis_ready) begin
      valid_q <= s_axis_valid;
      kind_q <= symbol_kind_mapped;
      bin_q <= s_axis_data[0];
      bins_pattern_q <= (s_axis_kind == SYMBOL_BINS_EP) ? (s_axis_data >> 6) : {31'd0, s_axis_data[0]};
      bins_count_q <= (s_axis_kind == SYMBOL_BINS_EP) ? s_axis_data[5:0] : 6'd1;
      ctx_valid_q <= s_axis_kind == SYMBOL_BIN_CTX;
      ctx_id_q <= s_axis_data[8 +: VVC_CABAC_CTX_ID_BITS];
      lps_q <= s_axis_data[24:16];
      mps_q <= s_axis_data[25];
      last_q <= s_axis_last;
    end
  end
endmodule
