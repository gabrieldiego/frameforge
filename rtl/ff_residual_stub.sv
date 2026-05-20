`timescale 1ns/1ps

module ff_residual_stub (
  input  logic [127:0] luma_samples,
  output logic [4:0]   quant_luma_rem,
  output logic [7:0]   recon_luma_sample
);
  logic [7:0] first_luma_sample;
  logic signed [9:0] dc_coeff;
  logic signed [9:0] quantized_dc_coeff;

  assign first_luma_sample = luma_samples[127:120];
  assign dc_coeff = solid_luma_dc_coeff(luma_samples);
  assign quant_luma_rem = quant_luma_rem_from_dc_coeff(dc_coeff);
  assign quantized_dc_coeff = reconstructed_dc_coeff_from_rem(quant_luma_rem);
  assign recon_luma_sample = inverse_solid_luma_dc_coeff(quantized_dc_coeff);

  function automatic signed [9:0] solid_luma_dc_coeff(input logic [127:0] samples);
    begin
      // Current toy model is intentionally solid-color only. All samples are
      // still carried into this block so later transforms can consume them.
      solid_luma_dc_coeff = $signed({ 2'b00, samples[127:120] }) - 10'sd114;
    end
  endfunction

  function automatic logic [4:0] quant_luma_rem_from_dc_coeff(input logic signed [9:0] coeff);
    logic [7:0] sample;
    begin
      sample = inverse_solid_luma_dc_coeff(coeff);
      quant_luma_rem_from_dc_coeff = quant_luma_rem_from_sample(sample);
    end
  endfunction

  function automatic logic signed [9:0] reconstructed_dc_coeff_from_rem(input logic [4:0] rem);
    begin
      reconstructed_dc_coeff_from_rem = $signed({ 2'b00, reconstructed_luma_from_rem(rem) }) - 10'sd114;
    end
  endfunction

  function automatic logic [7:0] inverse_solid_luma_dc_coeff(input logic signed [9:0] coeff);
    begin
      if (coeff <= -10'sd114) begin
        inverse_solid_luma_dc_coeff = 8'd0;
      end else if (coeff >= 10'sd141) begin
        inverse_solid_luma_dc_coeff = 8'd255;
      end else begin
        inverse_solid_luma_dc_coeff = coeff + 10'sd114;
      end
    end
  endfunction

  function automatic logic [7:0] reconstructed_luma_from_rem(input logic [4:0] rem);
    logic [8:0] scaled;
    begin
      scaled = ((9'd16 - rem) * 9'd114) + 9'd8;
      reconstructed_luma_from_rem = scaled >> 4;
    end
  endfunction

  function automatic logic [4:0] quant_luma_rem_from_sample(input logic [7:0] sample);
    begin
      if (sample >= 8'd111) quant_luma_rem_from_sample = 5'd0;
      else if (sample >= 8'd104) quant_luma_rem_from_sample = 5'd1;
      else if (sample >= 8'd96) quant_luma_rem_from_sample = 5'd2;
      else if (sample >= 8'd89) quant_luma_rem_from_sample = 5'd3;
      else if (sample >= 8'd82) quant_luma_rem_from_sample = 5'd4;
      else if (sample >= 8'd75) quant_luma_rem_from_sample = 5'd5;
      else if (sample >= 8'd68) quant_luma_rem_from_sample = 5'd6;
      else if (sample >= 8'd61) quant_luma_rem_from_sample = 5'd7;
      else if (sample >= 8'd54) quant_luma_rem_from_sample = 5'd8;
      else if (sample >= 8'd46) quant_luma_rem_from_sample = 5'd9;
      else if (sample >= 8'd39) quant_luma_rem_from_sample = 5'd10;
      else if (sample >= 8'd32) quant_luma_rem_from_sample = 5'd11;
      else if (sample >= 8'd25) quant_luma_rem_from_sample = 5'd12;
      else if (sample >= 8'd18) quant_luma_rem_from_sample = 5'd13;
      else if (sample >= 8'd11) quant_luma_rem_from_sample = 5'd14;
      else if (sample >= 8'd4) quant_luma_rem_from_sample = 5'd15;
      else quant_luma_rem_from_sample = 5'd16;
    end
  endfunction
endmodule
