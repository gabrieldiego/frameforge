package ff_vvc_reconstruction_pkg;
  function automatic logic signed [9:0] ff_vvc_reconstructed_luma_dc_coeff_from_rem(
    input logic [4:0] rem
  );
    begin
      ff_vvc_reconstructed_luma_dc_coeff_from_rem =
        $signed({2'b00, ff_vvc_reconstructed_luma_from_rem(rem)}) - 10'sd114;
    end
  endfunction

  function automatic logic [7:0] ff_vvc_inverse_luma_dc_coeff(input logic signed [9:0] coeff);
    begin
      if (coeff <= -10'sd114) begin
        ff_vvc_inverse_luma_dc_coeff = 8'd0;
      end else if (coeff >= 10'sd141) begin
        ff_vvc_inverse_luma_dc_coeff = 8'd255;
      end else begin
        ff_vvc_inverse_luma_dc_coeff = coeff + 10'sd114;
      end
    end
  endfunction

  function automatic logic [7:0] ff_vvc_reconstructed_luma_from_rem(input logic [4:0] rem);
    logic [8:0] scaled;
    begin
      scaled = ((9'd16 - rem) * 9'd114) + 9'd8;
      ff_vvc_reconstructed_luma_from_rem = scaled >> 4;
    end
  endfunction
endpackage
