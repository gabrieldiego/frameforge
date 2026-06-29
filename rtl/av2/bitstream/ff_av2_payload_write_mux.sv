`timescale 1ns/1ps

module ff_av2_payload_write_mux (
  input  logic        start,
  input  logic        state_partition,
  input  logic        state_leaf,
  input  logic        state_finish_push,
  input  logic        state_carry_write,
  input  logic        state_payload_prefix,
  input  logic        pending_push_valid,
  input  logic [15:0] precarry_len,
  input  logic [15:0] pending_push_word,
  input  logic        op_valid,
  input  logic [1:0]  norm_push_count,
  input  logic [15:0] norm_push0,
  input  logic signed [7:0] finish_s,
  input  logic [63:0] finish_e,
  input  logic signed [7:0] finish_c,
  input  logic [15:0] carry_group_addr,
  input  logic [15:0] carry_group_strobe,
  input  logic [127:0] carry_group_data,
  input  logic        tile_is_last,
  input  logic [1:0]  payload_prefix_index,
  input  logic [15:0] payload_len,
  input  logic [7:0]  payload_prefix_byte,
  output logic        precarry_write_valid,
  output logic [15:0] precarry_write_addr,
  output logic [15:0] precarry_write_data,
  output logic        payload_write_valid,
  output logic [15:0] payload_write_addr,
  output logic [15:0] payload_write_strobe,
  output logic [127:0] payload_write_data
);

  logic [15:0] payload_prefix_addr_w;

  assign payload_prefix_addr_w =
    payload_len + ((payload_prefix_index == 2'd3) ? 16'd3 : {14'd0, payload_prefix_index});

  always @* begin
    precarry_write_valid = 1'b0;
    precarry_write_addr = precarry_len;
    precarry_write_data = 16'd0;

    if (!start && pending_push_valid) begin
      precarry_write_valid = 1'b1;
      precarry_write_addr = precarry_len;
      precarry_write_data = pending_push_word;
    end else if (!start) begin
      if (state_partition || state_leaf) begin
        if (op_valid && norm_push_count != 2'd0) begin
          precarry_write_valid = 1'b1;
          precarry_write_addr = precarry_len;
          precarry_write_data = norm_push0;
        end
      end else if (state_finish_push) begin
        if (finish_s > 8'sd0) begin
          precarry_write_valid = 1'b1;
          precarry_write_addr = precarry_len;
          precarry_write_data = (finish_e >> (finish_c[5:0] + 6'd16)) & 16'hffff;
        end
      end
    end
  end

  always @* begin
    payload_write_valid = 1'b0;
    payload_write_addr = 16'd0;
    payload_write_strobe = 16'd0;
    payload_write_data = 128'd0;

    if (!start) begin
      if (state_carry_write) begin
        payload_write_valid = 1'b1;
        payload_write_addr = carry_group_addr;
        payload_write_strobe = carry_group_strobe;
        payload_write_data =
          (carry_group_data << ({3'd0, carry_group_addr[3:0]} << 3));
      end else if (state_payload_prefix && !tile_is_last) begin
        payload_write_valid = 1'b1;
        payload_write_addr = payload_prefix_addr_w;
        payload_write_strobe = 16'h0001 << payload_prefix_addr_w[3:0];
        payload_write_data =
          ({120'd0, payload_prefix_byte} <<
           ({3'd0, payload_prefix_addr_w[3:0]} << 3));
      end
    end
  end

endmodule
