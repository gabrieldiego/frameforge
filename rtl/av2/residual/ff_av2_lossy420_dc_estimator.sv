`timescale 1ns/1ps

module ff_av2_lossy420_dc_estimator (
  input  logic [11:0]  sample_sum,
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
  logic signed [15:0] predictor_sum_w;

  assign predictor_sum_w = $signed({4'd0, predictor, 4'd0});

  always @* begin
    sum_w = $signed({4'd0, sample_sum}) - predictor_sum_w;

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
