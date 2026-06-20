`timescale 1ns/1ps

module ff_av2_lossy420_dc_estimator (
  input  logic [127:0] samples,
  input  logic [7:0]   predictor,
  output logic signed [9:0] delta,
  output logic [7:0]   recon_sample,
  output logic         zero_delta
);

  logic signed [15:0] sum_w;
  logic signed [15:0] avg_w;
  logic signed [15:0] abs_avg_w;
  logic signed [15:0] quant_abs_w;
  logic signed [15:0] quant_w;
  logic signed [15:0] clamped_w;
  logic signed [15:0] recon_sum_w;
  logic [8:0]  sample_pair0_w;
  logic [8:0]  sample_pair1_w;
  logic [8:0]  sample_pair2_w;
  logic [8:0]  sample_pair3_w;
  logic [8:0]  sample_pair4_w;
  logic [8:0]  sample_pair5_w;
  logic [8:0]  sample_pair6_w;
  logic [8:0]  sample_pair7_w;
  logic [9:0]  sample_quad0_w;
  logic [9:0]  sample_quad1_w;
  logic [9:0]  sample_quad2_w;
  logic [9:0]  sample_quad3_w;
  logic [10:0] sample_oct0_w;
  logic [10:0] sample_oct1_w;
  logic [11:0] sample_sum_w;
  logic signed [15:0] predictor_sum_w;

  assign sample_pair0_w = {1'b0, samples[0 * 8 +: 8]} + {1'b0, samples[1 * 8 +: 8]};
  assign sample_pair1_w = {1'b0, samples[2 * 8 +: 8]} + {1'b0, samples[3 * 8 +: 8]};
  assign sample_pair2_w = {1'b0, samples[4 * 8 +: 8]} + {1'b0, samples[5 * 8 +: 8]};
  assign sample_pair3_w = {1'b0, samples[6 * 8 +: 8]} + {1'b0, samples[7 * 8 +: 8]};
  assign sample_pair4_w = {1'b0, samples[8 * 8 +: 8]} + {1'b0, samples[9 * 8 +: 8]};
  assign sample_pair5_w = {1'b0, samples[10 * 8 +: 8]} + {1'b0, samples[11 * 8 +: 8]};
  assign sample_pair6_w = {1'b0, samples[12 * 8 +: 8]} + {1'b0, samples[13 * 8 +: 8]};
  assign sample_pair7_w = {1'b0, samples[14 * 8 +: 8]} + {1'b0, samples[15 * 8 +: 8]};
  assign sample_quad0_w = {1'b0, sample_pair0_w} + {1'b0, sample_pair1_w};
  assign sample_quad1_w = {1'b0, sample_pair2_w} + {1'b0, sample_pair3_w};
  assign sample_quad2_w = {1'b0, sample_pair4_w} + {1'b0, sample_pair5_w};
  assign sample_quad3_w = {1'b0, sample_pair6_w} + {1'b0, sample_pair7_w};
  assign sample_oct0_w = {1'b0, sample_quad0_w} + {1'b0, sample_quad1_w};
  assign sample_oct1_w = {1'b0, sample_quad2_w} + {1'b0, sample_quad3_w};
  assign sample_sum_w = {1'b0, sample_oct0_w} + {1'b0, sample_oct1_w};
  assign predictor_sum_w = $signed({4'd0, predictor, 4'd0});

  always @* begin
    sum_w = $signed({4'd0, sample_sum_w}) - predictor_sum_w;

    // Rust Av2Lossy420TileState::quantized_dc_delta(): round the TX_4X4
    // average, quantize it to step 8, then clamp the signed delta.
    if (sum_w >= 0) begin
      avg_w = (sum_w + 16'sd8) >>> 4;
    end else begin
      avg_w = -(((-sum_w) + 16'sd8) >>> 4);
    end

    abs_avg_w = (avg_w < 0) ? -avg_w : avg_w;
    zero_delta = (abs_avg_w < 16'sd4);
    quant_abs_w = ((abs_avg_w + 16'sd4) >>> 3) <<< 3;
    quant_w = (avg_w < 0) ? -quant_abs_w : quant_abs_w;

    if (quant_w > 16'sd255) begin
      clamped_w = 16'sd255;
    end else if (quant_w < -16'sd255) begin
      clamped_w = -16'sd255;
    end else begin
      clamped_w = quant_w;
    end

    delta = clamped_w[9:0];
    recon_sum_w = $signed({1'b0, predictor}) + clamped_w;
    if (recon_sum_w < 16'sd0) begin
      recon_sample = 8'd0;
    end else if (recon_sum_w > 16'sd255) begin
      recon_sample = 8'd255;
    end else begin
      recon_sample = recon_sum_w[7:0];
    end
  end

endmodule
