`timescale 1ns/1ps

module ff_av2_payload_write_mux (
  input  logic        start,
  input  logic        state_partition,
  input  logic        state_leaf,
  input  logic        state_finish_push,
  input  logic        state_payload_prefix,
  input  logic        pending_push_valid,
  input  logic [15:0] pending_push_word,
  input  logic        op_valid,
  input  logic [1:0]  norm_push_count,
  input  logic [15:0] norm_push0,
  input  logic signed [7:0] finish_s,
  input  logic [63:0] finish_e,
  input  logic signed [7:0] finish_c,
  output logic        precarry_push_valid,
  output logic [15:0] precarry_push_word
);

  always @* begin
    precarry_push_valid = 1'b0;
    precarry_push_word = 16'd0;

    if (!start && pending_push_valid) begin
      precarry_push_valid = 1'b1;
      precarry_push_word = pending_push_word;
    end else if (!start) begin
      if (state_partition || state_leaf) begin
        if (op_valid && norm_push_count != 2'd0) begin
          precarry_push_valid = 1'b1;
          precarry_push_word = norm_push0;
        end
      end else if (state_finish_push) begin
        if (finish_s > 8'sd0) begin
          precarry_push_valid = 1'b1;
          precarry_push_word = (finish_e >> (finish_c[5:0] + 6'd16)) & 16'hffff;
        end
      end
    end
  end

endmodule
