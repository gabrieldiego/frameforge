`timescale 1ns/1ps

module ff_vvc_cu_activity_mask #(
  parameter int CTU_SIZE = 64,
  parameter int CU_SIZE = 8,
  parameter int CU_COUNT =
    ((CTU_SIZE + CU_SIZE - 1) / CU_SIZE) *
    ((CTU_SIZE + CU_SIZE - 1) / CU_SIZE)
) (
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,
  output logic [CU_COUNT - 1:0] cu_active_mask
);
  always_comb begin
    cu_active_mask = '0;
    for (int i = 0; i < CU_COUNT; i = i + 1) begin
      cu_active_mask[CU_COUNT - 1 - i] = cu_origin_is_visible(i[7:0]);
    end
  end

  function automatic logic cu_origin_is_visible(input logic [7:0] index);
    logic [31:0] pos;
    begin
      pos = coding_order_position(index);
      cu_origin_is_visible =
        (pos[31:16] < visible_width) && (pos[15:0] < visible_height);
    end
  endfunction

  function automatic logic [31:0] coding_order_position(input logic [7:0] index);
    logic [15:0] origin_x;
    logic [15:0] origin_y;
    logic [7:0]  index_in_32;
    logic [7:0]  index_in_16;
    begin
      origin_x = 16'd0;
      origin_y = 16'd0;
      if (CTU_SIZE == 64) begin
        origin_x = index[4] ? 16'd32 : 16'd0;
        origin_y = index[5] ? 16'd32 : 16'd0;
        index_in_32 = {4'd0, index[3:0]};
      end else begin
        index_in_32 = index;
      end

      if (CTU_SIZE >= 32) begin
        origin_x = origin_x + (index_in_32[2] ? 16'd16 : 16'd0);
        origin_y = origin_y + (index_in_32[3] ? 16'd16 : 16'd0);
        index_in_16 = {6'd0, index_in_32[1:0]};
      end else begin
        index_in_16 = index_in_32;
      end

      if (CTU_SIZE >= 16) begin
        origin_x = origin_x + (index_in_16[0] ? CU_SIZE : 16'd0);
        origin_y = origin_y + (index_in_16[1] ? CU_SIZE : 16'd0);
      end else begin
        origin_x = index_in_16[2:0] * CU_SIZE;
        origin_y = index_in_16[5:3] * CU_SIZE;
      end

      coding_order_position = {origin_x, origin_y};
    end
  endfunction
endmodule
