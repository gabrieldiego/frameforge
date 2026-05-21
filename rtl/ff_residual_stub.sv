`timescale 1ns/1ps

module ff_residual_stub (
  input  logic [127:0] luma_samples,
  output logic [4:0]   quant_luma_rem,
  output logic [119:0] quant_luma_ac_tokens,
  output logic [7:0]   recon_luma_sample
);
  logic signed [9:0] dc_coeff;
  logic signed [9:0] quantized_dc_coeff;
  logic [7:0] dc_sample;

  assign dc_sample = forward_luma_dc_sample(luma_samples);
  assign dc_coeff = $signed({ 2'b00, dc_sample }) - 10'sd114;
  assign quant_luma_rem = quant_luma_rem_from_dc_coeff(dc_coeff);
  assign quant_luma_ac_tokens = quant_ac_tokens(luma_samples, dc_sample);
  assign quantized_dc_coeff = reconstructed_dc_coeff_from_rem(quant_luma_rem);
  assign recon_luma_sample = inverse_luma_dc_coeff(quantized_dc_coeff);

  function automatic logic [7:0] forward_luma_dc_sample(input logic [127:0] samples);
    logic [12:0] sum;
    begin
      // Current token generation still emits only the DC coefficient, but the
      // residual block consumes all luma samples so SW and RTL share the same
      // first transform boundary.
      sum =
        {5'd0, samples[127:120]} + {5'd0, samples[119:112]} +
        {5'd0, samples[111:104]} + {5'd0, samples[103:96]}  +
        {5'd0, samples[95:88]}   + {5'd0, samples[87:80]}   +
        {5'd0, samples[79:72]}   + {5'd0, samples[71:64]}   +
        {5'd0, samples[63:56]}   + {5'd0, samples[55:48]}   +
        {5'd0, samples[47:40]}   + {5'd0, samples[39:32]}   +
        {5'd0, samples[31:24]}   + {5'd0, samples[23:16]}   +
        {5'd0, samples[15:8]}    + {5'd0, samples[7:0]};
      forward_luma_dc_sample = (sum + 13'd8) >> 4;
    end
  endfunction

  function automatic logic [119:0] quant_ac_tokens(
    input logic [127:0] samples,
    input logic [7:0]   dc
  );
    logic [119:0] tokens;
    integer i;
    begin
      tokens = '0;
      for (i = 1; i < 16; i = i + 1) begin
        tokens = (tokens << 8) | quant_ac_token(sample_at(samples, i[3:0]), dc);
      end
      quant_ac_tokens = tokens;
    end
  endfunction

  function automatic logic [7:0] sample_at(input logic [127:0] samples, input logic [3:0] index);
    begin
      sample_at = samples[(15 - index) * 8 +: 8];
    end
  endfunction

  function automatic logic [7:0] quant_ac_token(input logic [7:0] sample, input logic [7:0] dc);
    logic signed [9:0] coeff;
    logic [8:0] abs_coeff;
    logic [4:0] magnitude;
    logic negative;
    begin
      coeff = $signed({ 2'b00, sample }) - $signed({ 2'b00, dc });
      negative = coeff < 0;
      abs_coeff = negative ? -coeff : coeff;
      magnitude = (abs_coeff + 9'd8) >> 4;
      if (magnitude > 5'd8) begin
        magnitude = 5'd8;
      end
      quant_ac_token = 8'h40 | { 2'b00, negative, magnitude };
    end
  endfunction

  function automatic logic [4:0] quant_luma_rem_from_dc_coeff(input logic signed [9:0] coeff);
    logic [7:0] sample;
    begin
      sample = inverse_luma_dc_coeff(coeff);
      quant_luma_rem_from_dc_coeff = quant_luma_rem_from_sample(sample);
    end
  endfunction

  function automatic logic signed [9:0] reconstructed_dc_coeff_from_rem(input logic [4:0] rem);
    begin
      reconstructed_dc_coeff_from_rem = $signed({ 2'b00, reconstructed_luma_from_rem(rem) }) - 10'sd114;
    end
  endfunction

  function automatic logic [7:0] inverse_luma_dc_coeff(input logic signed [9:0] coeff);
    begin
      if (coeff <= -10'sd114) begin
        inverse_luma_dc_coeff = 8'd0;
      end else if (coeff >= 10'sd141) begin
        inverse_luma_dc_coeff = 8'd255;
      end else begin
        inverse_luma_dc_coeff = coeff + 10'sd114;
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
