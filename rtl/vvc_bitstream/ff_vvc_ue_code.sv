`timescale 1ns/1ps

module ff_vvc_ue_code (
  input  logic [15:0] value,
  output logic [31:0] code_value,
  output logic [5:0]  bit_count
);
  logic [16:0] code_num;
  logic [5:0] code_num_bits;
  integer bit_index;

  always_comb begin
    code_num = {1'b0, value} + 17'd1;
    code_num_bits = 6'd1;
    for (bit_index = 0; bit_index < 17; bit_index = bit_index + 1) begin
      if (code_num[bit_index]) begin
        code_num_bits = bit_index[5:0] + 6'd1;
      end
    end
    code_value = {15'd0, code_num};
    bit_count = (code_num_bits << 1) - 6'd1;
  end
endmodule
