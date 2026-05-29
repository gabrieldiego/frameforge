`timescale 1ns/1ps

module ff_vvc_residual_dc_symbolizer (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       clear,
  input  logic       start,
  input  logic [4:0] abs_level,
  input  logic       negative,
  input  logic [2:0] log2_tb_size,

  output logic        m_axis_valid,
  input  logic        m_axis_ready,
  output logic [7:0]  m_axis_kind,
  output logic [31:0] m_axis_data,
  output logic        m_axis_last,
  output logic        busy
);
  localparam logic [7:0] SYMBOL_BIN_EP  = 8'd0;
  localparam logic [7:0] SYMBOL_BIN_CTX = 8'd2;
  localparam logic [7:0] SYMBOL_BINS_EP = 8'd4;
  localparam logic [4:0] CTX_LAST_SIG_COEFF_X_PREFIX_3 = 5'd6;
  localparam logic [4:0] CTX_LAST_SIG_COEFF_Y_PREFIX_3 = 5'd7;
  localparam logic [4:0] CTX_LAST_SIG_COEFF_X_PREFIX_6 = 5'd8;
  localparam logic [4:0] CTX_LAST_SIG_COEFF_Y_PREFIX_6 = 5'd9;
  localparam logic [4:0] CTX_ABS_LEVEL_GTX_0 = 5'd10;
  localparam logic [4:0] CTX_PAR_LEVEL_0 = 5'd11;
  localparam logic [4:0] CTX_ABS_LEVEL_GTX_32 = 5'd12;

  logic [3:0] index_q;
  logic [3:0] last_index;
  logic [4:0] last_sig_x_ctx;
  logic [4:0] last_sig_y_ctx;
  logic [4:0] rem_abs_value;
  logic [4:0] rem_code_value;
  logic [2:0] rem_prefix_extra_len;
  logic [5:0] rem_prefix_count;
  logic [31:0] rem_prefix_pattern;
  logic [5:0] rem_suffix_count;
  logic [31:0] rem_suffix_pattern;
  logic [40:0] symbol_next;

  assign busy = index_q != 4'd15;
  assign last_index =
    (abs_level == 5'd0) ? 4'd1 :
    ((abs_level <= 5'd1) ? 4'd3 :
    ((abs_level <= 5'd3) ? 4'd5 : 4'd7));
  assign last_sig_x_ctx =
    (log2_tb_size >= 3'd4) ? CTX_LAST_SIG_COEFF_X_PREFIX_6 : CTX_LAST_SIG_COEFF_X_PREFIX_3;
  assign last_sig_y_ctx =
    (log2_tb_size >= 3'd4) ? CTX_LAST_SIG_COEFF_Y_PREFIX_6 : CTX_LAST_SIG_COEFF_Y_PREFIX_3;
  assign rem_abs_value = (abs_level - 5'd4) >> 1;
  assign rem_code_value = rem_abs_value - 5'd5;
  assign rem_prefix_extra_len =
    (rem_code_value <= 5'd0) ? 3'd0 :
    ((rem_code_value <= 5'd2) ? 3'd1 :
    ((rem_code_value <= 5'd6) ? 3'd2 : 3'd3));
  assign rem_prefix_count =
    (rem_abs_value < 5'd5) ? {1'b0, rem_abs_value + 5'd1} : {3'd0, rem_prefix_extra_len} + 6'd5;
  assign rem_prefix_pattern =
    (rem_abs_value < 5'd5) ?
    ((32'd1 << rem_prefix_count) - 32'd2) :
    ((32'd1 << rem_prefix_count) - 32'd1);
  assign rem_suffix_count = (rem_abs_value < 5'd5) ? 6'd0 : {3'd0, rem_prefix_extra_len} + 6'd1;
  assign rem_suffix_pattern =
    (rem_abs_value < 5'd5) ? 32'd0 :
    (rem_code_value - ((32'd1 << rem_prefix_extra_len) - 32'd1));

  always_comb begin
    case (index_q)
      4'd0: symbol_next = {
        SYMBOL_BIN_CTX, 19'd0, last_sig_x_ctx, 8'd0, 1'b0
      };
      4'd1: symbol_next = {
        SYMBOL_BIN_CTX, 19'd0, last_sig_y_ctx, 8'd0, last_index == 4'd1
      };
      4'd2: symbol_next = {
        SYMBOL_BIN_CTX, 19'd0, CTX_ABS_LEVEL_GTX_0, 7'd0, abs_level > 5'd1, 1'b0
      };
      4'd3: begin
        if (last_index == 4'd3) begin
          symbol_next = {SYMBOL_BIN_EP, 31'd0, negative, 1'b1};
        end else begin
          symbol_next = {SYMBOL_BIN_CTX, 19'd0, CTX_PAR_LEVEL_0, 7'd0, abs_level[0], 1'b0};
        end
      end
      4'd4: symbol_next = {
        SYMBOL_BIN_CTX, 19'd0, CTX_ABS_LEVEL_GTX_32, 7'd0, abs_level > 5'd3, last_index == 4'd4
      };
      4'd5: begin
        if (last_index == 4'd5) begin
          symbol_next = {SYMBOL_BIN_EP, 31'd0, negative, 1'b1};
        end else begin
          symbol_next = {
            SYMBOL_BINS_EP,
            (rem_prefix_pattern << 6) | {26'd0, rem_prefix_count},
            1'b0
          };
        end
      end
      4'd6: symbol_next = {
        SYMBOL_BINS_EP,
        (rem_suffix_pattern << 6) | {26'd0, rem_suffix_count},
        1'b0
      };
      default: symbol_next = {SYMBOL_BIN_EP, 31'd0, negative, 1'b1};
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      index_q <= 4'd15;
      m_axis_valid <= 1'b0;
      m_axis_kind <= 8'd0;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;
    end else if (clear) begin
      index_q <= 4'd15;
      m_axis_valid <= 1'b0;
      m_axis_kind <= 8'd0;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;
    end else begin
      if (start) begin
        index_q <= 4'd0;
        m_axis_valid <= 1'b0;
        m_axis_last <= 1'b0;
      end else if (busy && (!m_axis_valid || m_axis_ready)) begin
        m_axis_valid <= 1'b1;
        {m_axis_kind, m_axis_data, m_axis_last} <= symbol_next;
        if (index_q == last_index) begin
          index_q <= 4'd15;
        end else begin
          index_q <= index_q + 4'd1;
        end
      end else if (m_axis_valid && m_axis_ready) begin
        m_axis_valid <= 1'b0;
        m_axis_kind <= 8'd0;
        m_axis_data <= 32'd0;
        m_axis_last <= 1'b0;
      end
    end
  end
endmodule
