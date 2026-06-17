`timescale 1ns/1ps

module ff_av2_range_coder_step (
  input  logic [63:0] low,
  input  logic [31:0] rng,
  input  integer      cnt,
  input  logic        op_literal,
  input  logic [31:0] op_literal_value,
  input  logic [4:0]  op_literal_bits,
  input  logic [31:0] op_fl,
  input  logic [31:0] op_fh,
  input  logic [4:0]  op_fl_inc,
  input  logic [4:0]  op_fh_inc,
  output logic [1:0]  norm_push_count,
  output logic [15:0] norm_push0,
  output logic [15:0] norm_push1,
  output logic [63:0] norm_low,
  output logic [31:0] norm_rng,
  output integer      norm_cnt
);

  logic [63:0] raw_low_w;
  logic [31:0] raw_rng_w;
  integer raw_bypass_bits_w;
  logic [31:0] rr_w;
  logic [31:0] pp_fl_w;
  logic [31:0] pp_fh_w;
  logic [31:0] scaled_u_w;
  logic [31:0] scaled_v_w;
  integer ilog_rng_w;
  integer norm_c_w;
  integer norm_d_w;
  integer norm_s_w;
  integer norm_c_after_w;
  integer norm_s_after_w;
  logic [63:0] norm_mask_w;
  logic [63:0] norm_low_work_w;

  always @* begin
    rr_w = rng >> 8;
    pp_fl_w = (((op_fl >> 7) << 4) + op_fl_inc);
    pp_fh_w = (((op_fh >> 7) << 4) + op_fh_inc);
    scaled_u_w = (((rr_w * pp_fl_w[31:0]) >> 7) << 3);
    scaled_v_w = (((rr_w * pp_fh_w[31:0]) >> 7) << 3);

    if (op_literal) begin
      raw_low_w = (low << op_literal_bits) + (rng * op_literal_value);
      raw_rng_w = rng;
      raw_bypass_bits_w = op_literal_bits;
    end else if (op_fl < 32'd32768) begin
      raw_low_w = low + (rng - scaled_u_w);
      raw_rng_w = scaled_u_w - scaled_v_w;
      raw_bypass_bits_w = 0;
    end else begin
      raw_low_w = low;
      raw_rng_w = rng - scaled_v_w;
      raw_bypass_bits_w = 0;
    end

    casez (raw_rng_w[15:0])
      16'b1???_????_????_????: ilog_rng_w = 16;
      16'b01??_????_????_????: ilog_rng_w = 15;
      16'b001?_????_????_????: ilog_rng_w = 14;
      16'b0001_????_????_????: ilog_rng_w = 13;
      16'b0000_1???_????_????: ilog_rng_w = 12;
      16'b0000_01??_????_????: ilog_rng_w = 11;
      16'b0000_001?_????_????: ilog_rng_w = 10;
      16'b0000_0001_????_????: ilog_rng_w = 9;
      16'b0000_0000_1???_????: ilog_rng_w = 8;
      16'b0000_0000_01??_????: ilog_rng_w = 7;
      16'b0000_0000_001?_????: ilog_rng_w = 6;
      16'b0000_0000_0001_????: ilog_rng_w = 5;
      16'b0000_0000_0000_1???: ilog_rng_w = 4;
      16'b0000_0000_0000_01??: ilog_rng_w = 3;
      16'b0000_0000_0000_001?: ilog_rng_w = 2;
      default: ilog_rng_w = 1;
    endcase

    norm_c_w = cnt;
    if (raw_bypass_bits_w > 0) begin
      norm_c_w = cnt + raw_bypass_bits_w;
      norm_d_w = 0;
    end else begin
      norm_d_w = 16 - ilog_rng_w;
    end
    norm_s_w = norm_c_w + norm_d_w;
    norm_low_work_w = raw_low_w;
    norm_c_after_w = norm_c_w;
    norm_s_after_w = norm_s_w;
    norm_push_count = 2'd0;
    norm_push0 = 16'd0;
    norm_push1 = 16'd0;
    norm_mask_w = 64'd0;

    if (norm_s_w >= 0) begin
      norm_c_after_w = norm_c_w + 16;
      if (norm_c_after_w >= 64) norm_mask_w = 64'hffff_ffff_ffff_ffff;
      else if (norm_c_after_w <= 0) norm_mask_w = 64'd0;
      else norm_mask_w = (64'd1 << norm_c_after_w) - 64'd1;

      if (norm_s_w >= 8) begin
        norm_push0 = (norm_low_work_w >> norm_c_after_w) & 16'hffff;
        norm_low_work_w = norm_low_work_w & norm_mask_w;
        norm_c_after_w = norm_c_after_w - 8;
        norm_mask_w = norm_mask_w >> 8;
        norm_push1 = (norm_low_work_w >> norm_c_after_w) & 16'hffff;
        norm_push_count = 2'd2;
      end else begin
        norm_push0 = (norm_low_work_w >> norm_c_after_w) & 16'hffff;
        norm_push_count = 2'd1;
      end
      norm_s_after_w = norm_c_after_w + norm_d_w - 24;
      norm_low_work_w = norm_low_work_w & norm_mask_w;
    end

    norm_low = norm_low_work_w << norm_d_w;
    norm_rng = raw_rng_w << norm_d_w;
    norm_cnt = norm_s_after_w;
  end

endmodule
