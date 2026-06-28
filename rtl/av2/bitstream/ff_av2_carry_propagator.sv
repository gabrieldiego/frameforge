`timescale 1ns/1ps

module ff_av2_carry_propagator (
  input  logic [15:0] carry,
  input  logic [15:0] carry_index,
  input  logic [15:0] payload_tile_start,
  input  logic [255:0] precarry_read_word_data,
  output logic [15:0] precarry_read_addr,
  output logic [15:0] precarry_read_data,
  output logic [15:0] carry_sum,
  output logic [15:0] carry_group_addr,
  output logic [15:0] carry_index_after_step,
  output logic [15:0] carry_after_step,
  output logic [127:0] carry_group_data,
  output logic [15:0] carry_group_strobe,
  output logic        carry_done_after_step,
  output logic [11:0] carry_read_after_current_word_addr,
  output logic [11:0] carry_read_after_next_word_addr
);

  logic [15:0] precarry_read_prev_data_w;
  logic [15:0] precarry_read_prev2_data_w;
  logic [15:0] precarry_read_prev3_data_w;
  logic [15:0] precarry_read_prev4_data_w;
  logic [15:0] precarry_read_prev5_data_w;
  logic [15:0] precarry_read_prev6_data_w;
  logic [15:0] precarry_read_prev7_data_w;
  logic [15:0] precarry_read_prev8_data_w;
  logic [15:0] precarry_read_prev9_data_w;
  logic [15:0] precarry_read_prev10_data_w;
  logic [15:0] precarry_read_prev11_data_w;
  logic [15:0] precarry_read_prev12_data_w;
  logic [15:0] precarry_read_prev13_data_w;
  logic [15:0] precarry_read_prev14_data_w;
  logic [15:0] precarry_read_prev15_data_w;
  logic [15:0] carry_pair_sum_w;
  logic [15:0] carry_quad_sum2_w;
  logic [15:0] carry_quad_sum3_w;
  logic [15:0] carry_oct_sum4_w;
  logic [15:0] carry_oct_sum5_w;
  logic [15:0] carry_oct_sum6_w;
  logic [15:0] carry_oct_sum7_w;
  logic [15:0] carry_hex_sum8_w;
  logic [15:0] carry_hex_sum9_w;
  logic [15:0] carry_hex_sum10_w;
  logic [15:0] carry_hex_sum11_w;
  logic [15:0] carry_hex_sum12_w;
  logic [15:0] carry_hex_sum13_w;
  logic [15:0] carry_hex_sum14_w;
  logic [15:0] carry_hex_sum15_w;
  logic [15:0] carry_single_addr_w;
  logic [15:0] carry_next_single_addr_w;
  logic [15:0] carry_index_after_next_step_w;
  logic [4:0] carry_step_w;
  logic [4:0] carry_next_step_w;
  logic [4:0] carry_precarry_limit_w;
  logic [4:0] carry_payload_limit_w;
  logic [4:0] carry_next_precarry_limit_w;
  logic [4:0] carry_next_payload_limit_w;
  logic [16:0] carry_group_strobe_ext_w;
  logic carry_next_done_w;

  assign carry_sum = carry + precarry_read_data;
  assign carry_pair_sum_w = (carry_sum >> 8) + precarry_read_prev_data_w;
  assign carry_quad_sum2_w = (carry_pair_sum_w >> 8) + precarry_read_prev2_data_w;
  assign carry_quad_sum3_w = (carry_quad_sum2_w >> 8) + precarry_read_prev3_data_w;
  assign carry_oct_sum4_w = (carry_quad_sum3_w >> 8) + precarry_read_prev4_data_w;
  assign carry_oct_sum5_w = (carry_oct_sum4_w >> 8) + precarry_read_prev5_data_w;
  assign carry_oct_sum6_w = (carry_oct_sum5_w >> 8) + precarry_read_prev6_data_w;
  assign carry_oct_sum7_w = (carry_oct_sum6_w >> 8) + precarry_read_prev7_data_w;
  assign carry_hex_sum8_w = (carry_oct_sum7_w >> 8) + precarry_read_prev8_data_w;
  assign carry_hex_sum9_w = (carry_hex_sum8_w >> 8) + precarry_read_prev9_data_w;
  assign carry_hex_sum10_w = (carry_hex_sum9_w >> 8) + precarry_read_prev10_data_w;
  assign carry_hex_sum11_w = (carry_hex_sum10_w >> 8) + precarry_read_prev11_data_w;
  assign carry_hex_sum12_w = (carry_hex_sum11_w >> 8) + precarry_read_prev12_data_w;
  assign carry_hex_sum13_w = (carry_hex_sum12_w >> 8) + precarry_read_prev13_data_w;
  assign carry_hex_sum14_w = (carry_hex_sum13_w >> 8) + precarry_read_prev14_data_w;
  assign carry_hex_sum15_w = (carry_hex_sum14_w >> 8) + precarry_read_prev15_data_w;
  assign carry_single_addr_w = payload_tile_start + carry_index;
  assign carry_next_single_addr_w = payload_tile_start + carry_index_after_step;

  // AV2 range coder carry propagation is byte-order preserving when processed
  // from the end of the precarry buffer. The group size is the largest run up
  // to 16 bytes that stays inside both the current precarry read word and
  // the current 16-byte masked payload write word.
  assign carry_precarry_limit_w =
    (carry_index[3:0] == 4'd15) ? 5'd16 : {1'b0, carry_index[3:0]} + 5'd1;
  assign carry_payload_limit_w = {1'b0, carry_single_addr_w[3:0]} + 5'd1;
  assign carry_step_w =
    (carry_precarry_limit_w < carry_payload_limit_w) ?
      carry_precarry_limit_w : carry_payload_limit_w;
  assign carry_group_addr =
    payload_tile_start + carry_index - {11'd0, carry_step_w - 5'd1};
  assign carry_index_after_step = carry_index - {11'd0, carry_step_w};
  assign carry_done_after_step = carry_index < {11'd0, carry_step_w};
  assign carry_next_precarry_limit_w =
    (carry_index_after_step[3:0] == 4'd15) ?
      5'd16 : ({1'b0, carry_index_after_step[3:0]} + 5'd1);
  assign carry_next_payload_limit_w = {1'b0, carry_next_single_addr_w[3:0]} + 5'd1;
  assign carry_next_step_w =
    (carry_next_precarry_limit_w < carry_next_payload_limit_w) ?
      carry_next_precarry_limit_w : carry_next_payload_limit_w;
  assign carry_index_after_next_step_w =
    carry_index_after_step - {11'd0, carry_next_step_w};
  assign carry_next_done_w =
    carry_index_after_step < {11'd0, carry_next_step_w};
  assign carry_read_after_current_word_addr =
    carry_done_after_step ? 12'd0 : carry_index_after_step[15:4];
  assign carry_read_after_next_word_addr =
    (carry_done_after_step || carry_next_done_w) ?
      12'd0 : carry_index_after_next_step_w[15:4];
  assign carry_after_step =
    (carry_step_w == 5'd16) ? (carry_hex_sum15_w >> 8) :
    ((carry_step_w == 5'd15) ? (carry_hex_sum14_w >> 8) :
    ((carry_step_w == 5'd14) ? (carry_hex_sum13_w >> 8) :
    ((carry_step_w == 5'd13) ? (carry_hex_sum12_w >> 8) :
    ((carry_step_w == 5'd12) ? (carry_hex_sum11_w >> 8) :
    ((carry_step_w == 5'd11) ? (carry_hex_sum10_w >> 8) :
    ((carry_step_w == 5'd10) ? (carry_hex_sum9_w >> 8) :
    ((carry_step_w == 5'd9) ? (carry_hex_sum8_w >> 8) :
    ((carry_step_w == 5'd8) ? (carry_oct_sum7_w >> 8) :
    ((carry_step_w == 5'd7) ? (carry_oct_sum6_w >> 8) :
    ((carry_step_w == 5'd6) ? (carry_oct_sum5_w >> 8) :
    ((carry_step_w == 5'd5) ? (carry_oct_sum4_w >> 8) :
    ((carry_step_w == 5'd4) ? (carry_quad_sum3_w >> 8) :
    ((carry_step_w == 5'd3) ? (carry_quad_sum2_w >> 8) :
    ((carry_step_w == 5'd2) ? (carry_pair_sum_w >> 8) :
                               (carry_sum >> 8)))))))))))))));
  assign carry_group_strobe_ext_w =
    ((17'd1 << carry_step_w) - 17'd1) << carry_group_addr[3:0];
  assign carry_group_strobe = carry_group_strobe_ext_w[15:0];

  always @* begin
    case (carry_step_w)
      5'd16: begin
        carry_group_data = {
          carry_sum[7:0],
          carry_pair_sum_w[7:0],
          carry_quad_sum2_w[7:0],
          carry_quad_sum3_w[7:0],
          carry_oct_sum4_w[7:0],
          carry_oct_sum5_w[7:0],
          carry_oct_sum6_w[7:0],
          carry_oct_sum7_w[7:0],
          carry_hex_sum8_w[7:0],
          carry_hex_sum9_w[7:0],
          carry_hex_sum10_w[7:0],
          carry_hex_sum11_w[7:0],
          carry_hex_sum12_w[7:0],
          carry_hex_sum13_w[7:0],
          carry_hex_sum14_w[7:0],
          carry_hex_sum15_w[7:0]
        };
      end
      5'd15: begin
        carry_group_data = {
          8'd0,
          carry_sum[7:0],
          carry_pair_sum_w[7:0],
          carry_quad_sum2_w[7:0],
          carry_quad_sum3_w[7:0],
          carry_oct_sum4_w[7:0],
          carry_oct_sum5_w[7:0],
          carry_oct_sum6_w[7:0],
          carry_oct_sum7_w[7:0],
          carry_hex_sum8_w[7:0],
          carry_hex_sum9_w[7:0],
          carry_hex_sum10_w[7:0],
          carry_hex_sum11_w[7:0],
          carry_hex_sum12_w[7:0],
          carry_hex_sum13_w[7:0],
          carry_hex_sum14_w[7:0]
        };
      end
      5'd14: begin
        carry_group_data = {
          16'd0,
          carry_sum[7:0],
          carry_pair_sum_w[7:0],
          carry_quad_sum2_w[7:0],
          carry_quad_sum3_w[7:0],
          carry_oct_sum4_w[7:0],
          carry_oct_sum5_w[7:0],
          carry_oct_sum6_w[7:0],
          carry_oct_sum7_w[7:0],
          carry_hex_sum8_w[7:0],
          carry_hex_sum9_w[7:0],
          carry_hex_sum10_w[7:0],
          carry_hex_sum11_w[7:0],
          carry_hex_sum12_w[7:0],
          carry_hex_sum13_w[7:0]
        };
      end
      5'd13: begin
        carry_group_data = {
          24'd0,
          carry_sum[7:0],
          carry_pair_sum_w[7:0],
          carry_quad_sum2_w[7:0],
          carry_quad_sum3_w[7:0],
          carry_oct_sum4_w[7:0],
          carry_oct_sum5_w[7:0],
          carry_oct_sum6_w[7:0],
          carry_oct_sum7_w[7:0],
          carry_hex_sum8_w[7:0],
          carry_hex_sum9_w[7:0],
          carry_hex_sum10_w[7:0],
          carry_hex_sum11_w[7:0],
          carry_hex_sum12_w[7:0]
        };
      end
      5'd12: begin
        carry_group_data = {
          32'd0,
          carry_sum[7:0],
          carry_pair_sum_w[7:0],
          carry_quad_sum2_w[7:0],
          carry_quad_sum3_w[7:0],
          carry_oct_sum4_w[7:0],
          carry_oct_sum5_w[7:0],
          carry_oct_sum6_w[7:0],
          carry_oct_sum7_w[7:0],
          carry_hex_sum8_w[7:0],
          carry_hex_sum9_w[7:0],
          carry_hex_sum10_w[7:0],
          carry_hex_sum11_w[7:0]
        };
      end
      5'd11: begin
        carry_group_data = {
          40'd0,
          carry_sum[7:0],
          carry_pair_sum_w[7:0],
          carry_quad_sum2_w[7:0],
          carry_quad_sum3_w[7:0],
          carry_oct_sum4_w[7:0],
          carry_oct_sum5_w[7:0],
          carry_oct_sum6_w[7:0],
          carry_oct_sum7_w[7:0],
          carry_hex_sum8_w[7:0],
          carry_hex_sum9_w[7:0],
          carry_hex_sum10_w[7:0]
        };
      end
      5'd10: begin
        carry_group_data = {
          48'd0,
          carry_sum[7:0],
          carry_pair_sum_w[7:0],
          carry_quad_sum2_w[7:0],
          carry_quad_sum3_w[7:0],
          carry_oct_sum4_w[7:0],
          carry_oct_sum5_w[7:0],
          carry_oct_sum6_w[7:0],
          carry_oct_sum7_w[7:0],
          carry_hex_sum8_w[7:0],
          carry_hex_sum9_w[7:0]
        };
      end
      5'd9: begin
        carry_group_data = {
          56'd0,
          carry_sum[7:0],
          carry_pair_sum_w[7:0],
          carry_quad_sum2_w[7:0],
          carry_quad_sum3_w[7:0],
          carry_oct_sum4_w[7:0],
          carry_oct_sum5_w[7:0],
          carry_oct_sum6_w[7:0],
          carry_oct_sum7_w[7:0],
          carry_hex_sum8_w[7:0]
        };
      end
      5'd8: begin
        carry_group_data = {
          64'd0,
          carry_sum[7:0],
          carry_pair_sum_w[7:0],
          carry_quad_sum2_w[7:0],
          carry_quad_sum3_w[7:0],
          carry_oct_sum4_w[7:0],
          carry_oct_sum5_w[7:0],
          carry_oct_sum6_w[7:0],
          carry_oct_sum7_w[7:0]
        };
      end
      5'd7: begin
        carry_group_data = {
          72'd0,
          carry_sum[7:0],
          carry_pair_sum_w[7:0],
          carry_quad_sum2_w[7:0],
          carry_quad_sum3_w[7:0],
          carry_oct_sum4_w[7:0],
          carry_oct_sum5_w[7:0],
          carry_oct_sum6_w[7:0]
        };
      end
      5'd6: begin
        carry_group_data = {
          80'd0,
          carry_sum[7:0],
          carry_pair_sum_w[7:0],
          carry_quad_sum2_w[7:0],
          carry_quad_sum3_w[7:0],
          carry_oct_sum4_w[7:0],
          carry_oct_sum5_w[7:0]
        };
      end
      5'd5: begin
        carry_group_data = {
          88'd0,
          carry_sum[7:0],
          carry_pair_sum_w[7:0],
          carry_quad_sum2_w[7:0],
          carry_quad_sum3_w[7:0],
          carry_oct_sum4_w[7:0]
        };
      end
      5'd4: begin
        carry_group_data = {
          96'd0,
          carry_sum[7:0],
          carry_pair_sum_w[7:0],
          carry_quad_sum2_w[7:0],
          carry_quad_sum3_w[7:0]
        };
      end
      5'd3: begin
        carry_group_data = {
          104'd0,
          carry_sum[7:0],
          carry_pair_sum_w[7:0],
          carry_quad_sum2_w[7:0]
        };
      end
      5'd2: begin
        carry_group_data = {112'd0, carry_sum[7:0], carry_pair_sum_w[7:0]};
      end
      default: begin
        carry_group_data = {120'd0, carry_sum[7:0]};
      end
    endcase
  end

  assign precarry_read_addr = carry_index;
  assign precarry_read_data =
    precarry_read_word_data[{carry_index[3:0], 4'b0000} +: 16];
  assign precarry_read_prev_data_w =
    (carry_index[3:0] >= 4'd1) ?
      precarry_read_word_data[{carry_index[3:0] - 4'd1, 4'b0000} +: 16] : 16'd0;
  assign precarry_read_prev2_data_w =
    (carry_index[3:0] >= 4'd2) ?
      precarry_read_word_data[{carry_index[3:0] - 4'd2, 4'b0000} +: 16] : 16'd0;
  assign precarry_read_prev3_data_w =
    (carry_index[3:0] >= 4'd3) ?
      precarry_read_word_data[{carry_index[3:0] - 4'd3, 4'b0000} +: 16] : 16'd0;
  assign precarry_read_prev4_data_w =
    (carry_index[3:0] >= 4'd4) ?
      precarry_read_word_data[{carry_index[3:0] - 4'd4, 4'b0000} +: 16] : 16'd0;
  assign precarry_read_prev5_data_w =
    (carry_index[3:0] >= 4'd5) ?
      precarry_read_word_data[{carry_index[3:0] - 4'd5, 4'b0000} +: 16] : 16'd0;
  assign precarry_read_prev6_data_w =
    (carry_index[3:0] >= 4'd6) ?
      precarry_read_word_data[{carry_index[3:0] - 4'd6, 4'b0000} +: 16] : 16'd0;
  assign precarry_read_prev7_data_w =
    (carry_index[3:0] >= 4'd7) ?
      precarry_read_word_data[{carry_index[3:0] - 4'd7, 4'b0000} +: 16] : 16'd0;
  assign precarry_read_prev8_data_w =
    (carry_index[3:0] >= 4'd8) ?
      precarry_read_word_data[{carry_index[3:0] - 4'd8, 4'b0000} +: 16] : 16'd0;
  assign precarry_read_prev9_data_w =
    (carry_index[3:0] >= 4'd9) ?
      precarry_read_word_data[{carry_index[3:0] - 4'd9, 4'b0000} +: 16] : 16'd0;
  assign precarry_read_prev10_data_w =
    (carry_index[3:0] >= 4'd10) ?
      precarry_read_word_data[{carry_index[3:0] - 4'd10, 4'b0000} +: 16] : 16'd0;
  assign precarry_read_prev11_data_w =
    (carry_index[3:0] >= 4'd11) ?
      precarry_read_word_data[{carry_index[3:0] - 4'd11, 4'b0000} +: 16] : 16'd0;
  assign precarry_read_prev12_data_w =
    (carry_index[3:0] >= 4'd12) ?
      precarry_read_word_data[{carry_index[3:0] - 4'd12, 4'b0000} +: 16] : 16'd0;
  assign precarry_read_prev13_data_w =
    (carry_index[3:0] >= 4'd13) ?
      precarry_read_word_data[{carry_index[3:0] - 4'd13, 4'b0000} +: 16] : 16'd0;
  assign precarry_read_prev14_data_w =
    (carry_index[3:0] >= 4'd14) ?
      precarry_read_word_data[{carry_index[3:0] - 4'd14, 4'b0000} +: 16] : 16'd0;
  assign precarry_read_prev15_data_w =
    (carry_index[3:0] == 4'd15) ? precarry_read_word_data[15:0] : 16'd0;

endmodule
