`timescale 1ns/1ps

module ff_av2_range_coder_step (
  input  logic [63:0] low,
  input  logic [31:0] rng,
  input  logic signed [7:0] cnt,
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
  output logic signed [7:0] norm_cnt
);

  logic [63:0] raw_low_w;
  logic [15:0] raw_rng_w;
  logic signed [7:0] raw_bypass_bits_w;
  logic [15:0] rng16_w;
  logic [7:0] rr_w;
  logic [12:0] pp_fl_w;
  logic [12:0] pp_fh_w;
  logic [20:0] scaled_u_product_w;
  logic [20:0] scaled_v_product_w;
  logic [31:0] literal_product_lo_w;
  logic [31:0] literal_product_hi_w;
  logic [63:0] literal_product_w;
  logic [15:0] scaled_u_w;
  logic [15:0] scaled_v_w;
  logic signed [7:0] ilog_rng_w;
  logic signed [7:0] norm_c_w;
  logic signed [7:0] norm_d_w;
  logic signed [7:0] norm_s_w;
  logic signed [7:0] norm_c_after_w;
  logic signed [7:0] norm_s_after_w;
  logic [63:0] norm_mask_w;
  logic [63:0] norm_low_work_w;
  integer prob_mul_bit_q;
  integer literal_mul_bit_q;

  always @* begin
    // AV2 v1.0.0 entropy coding keeps rng within 16 bits before normalize();
    // see the software model's normalize() assertion. Keep the probability
    // scaling datapath at that width instead of synthesizing 32-bit multiplies.
    rng16_w = rng[15:0];
    rr_w = rng16_w[15:8];
    pp_fl_w = {op_fl[15:7], 4'd0} + {8'd0, op_fl_inc};
    pp_fh_w = {op_fh[15:7], 4'd0} + {8'd0, op_fh_inc};
    scaled_u_product_w = 21'd0;
    scaled_v_product_w = 21'd0;
    for (prob_mul_bit_q = 0; prob_mul_bit_q < 8; prob_mul_bit_q = prob_mul_bit_q + 1) begin
      if (rr_w[prob_mul_bit_q]) begin
        scaled_u_product_w =
          scaled_u_product_w + ({8'd0, pp_fl_w} << prob_mul_bit_q);
        scaled_v_product_w =
          scaled_v_product_w + ({8'd0, pp_fh_w} << prob_mul_bit_q);
      end
    end
    // AV2 v1.0.0 Section 9.4.3.3 aom_write_literal() updates low by
    // rng * literal_value. The encoder invariant keeps rng normalized to
    // 16 bits. Keep this as fixed shift/add fabric instead of unregistered
    // range-coder DSPs; Vivado otherwise spends timing optimization effort on
    // this combinational entropy step.
    literal_product_lo_w = 32'd0;
    literal_product_hi_w = 32'd0;
    for (literal_mul_bit_q = 0; literal_mul_bit_q < 16; literal_mul_bit_q = literal_mul_bit_q + 1) begin
      if (op_literal_value[literal_mul_bit_q]) begin
        literal_product_lo_w =
          literal_product_lo_w + ({16'd0, rng16_w} << literal_mul_bit_q);
      end
      if (op_literal_value[16 + literal_mul_bit_q]) begin
        literal_product_hi_w =
          literal_product_hi_w + ({16'd0, rng16_w} << literal_mul_bit_q);
      end
    end
    literal_product_w =
      {32'd0, literal_product_lo_w} +
      {16'd0, literal_product_hi_w, 16'd0};
    scaled_u_w = {scaled_u_product_w[19:7], 3'd0};
    scaled_v_w = {scaled_v_product_w[19:7], 3'd0};

    if (op_literal) begin
      raw_low_w = (low << op_literal_bits) + literal_product_w;
      raw_rng_w = rng16_w;
      raw_bypass_bits_w = {3'd0, op_literal_bits};
    end else if (op_fl < 32'd32768) begin
      raw_low_w = low + {48'd0, (rng16_w - scaled_u_w)};
      raw_rng_w = scaled_u_w - scaled_v_w;
      raw_bypass_bits_w = 8'sd0;
    end else begin
      raw_low_w = low;
      raw_rng_w = rng16_w - scaled_v_w;
      raw_bypass_bits_w = 8'sd0;
    end

    casez (raw_rng_w[15:0])
      16'b1???_????_????_????: ilog_rng_w = 8'sd16;
      16'b01??_????_????_????: ilog_rng_w = 8'sd15;
      16'b001?_????_????_????: ilog_rng_w = 8'sd14;
      16'b0001_????_????_????: ilog_rng_w = 8'sd13;
      16'b0000_1???_????_????: ilog_rng_w = 8'sd12;
      16'b0000_01??_????_????: ilog_rng_w = 8'sd11;
      16'b0000_001?_????_????: ilog_rng_w = 8'sd10;
      16'b0000_0001_????_????: ilog_rng_w = 8'sd9;
      16'b0000_0000_1???_????: ilog_rng_w = 8'sd8;
      16'b0000_0000_01??_????: ilog_rng_w = 8'sd7;
      16'b0000_0000_001?_????: ilog_rng_w = 8'sd6;
      16'b0000_0000_0001_????: ilog_rng_w = 8'sd5;
      16'b0000_0000_0000_1???: ilog_rng_w = 8'sd4;
      16'b0000_0000_0000_01??: ilog_rng_w = 8'sd3;
      16'b0000_0000_0000_001?: ilog_rng_w = 8'sd2;
      default: ilog_rng_w = 8'sd1;
    endcase

    norm_c_w = cnt;
    if (raw_bypass_bits_w > 8'sd0) begin
      norm_c_w = cnt + raw_bypass_bits_w;
      norm_d_w = 8'sd0;
    end else begin
      norm_d_w = 8'sd16 - ilog_rng_w;
    end
    norm_s_w = norm_c_w + norm_d_w;
    norm_low_work_w = raw_low_w;
    norm_c_after_w = norm_c_w;
    norm_s_after_w = norm_s_w;
    norm_push_count = 2'd0;
    norm_push0 = 16'd0;
    norm_push1 = 16'd0;
    norm_mask_w = 64'd0;

    if (norm_s_w >= 8'sd0) begin
      norm_c_after_w = norm_c_w + 8'sd16;
      if (norm_c_after_w >= 8'sd64) norm_mask_w = 64'hffff_ffff_ffff_ffff;
      else if (norm_c_after_w <= 8'sd0) norm_mask_w = 64'd0;
      else norm_mask_w = (64'd1 << norm_c_after_w[5:0]) - 64'd1;

      if (norm_s_w >= 8'sd8) begin
        norm_push0 = (norm_low_work_w >> norm_c_after_w[5:0]) & 16'hffff;
        norm_low_work_w = norm_low_work_w & norm_mask_w;
        norm_c_after_w = norm_c_after_w - 8'sd8;
        norm_mask_w = norm_mask_w >> 8;
        norm_push1 = (norm_low_work_w >> norm_c_after_w[5:0]) & 16'hffff;
        norm_push_count = 2'd2;
      end else begin
        norm_push0 = (norm_low_work_w >> norm_c_after_w[5:0]) & 16'hffff;
        norm_push_count = 2'd1;
      end
      norm_s_after_w = norm_c_after_w + norm_d_w - 8'sd24;
      norm_low_work_w = norm_low_work_w & norm_mask_w;
    end

    norm_low = norm_low_work_w << norm_d_w[5:0];
    norm_rng = {16'd0, raw_rng_w << norm_d_w[3:0]};
    norm_cnt = norm_s_after_w;
  end

endmodule
