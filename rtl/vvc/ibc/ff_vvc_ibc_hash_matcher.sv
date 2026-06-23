`timescale 1ns/1ps

module ff_vvc_ibc_hash_matcher #(
  parameter int CTU_SIZE = 64,
  parameter int CU_SIZE = 8,
  parameter int CU_COUNT = (CTU_SIZE / CU_SIZE) * (CTU_SIZE / CU_SIZE)
) (
  input  logic clk,
  input  logic rst_n,
  input  logic clear,
  input  logic enable,

  input  logic sample_valid,
  input  logic [63:0] sample_data,
  input  logic [3:0] sample_count,
  input  logic [5:0] cu_index,
  input  logic [15:0] cu_origin_x,
  input  logic [15:0] cu_origin_y,
  input  logic cu_full_visible,
  input  logic cu_last_sample,
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,
  input  logic ctu_last_sample,

  output logic idle,
  output logic [CU_COUNT - 1:0] ibc_cu_mask,
  output logic [(6 * CU_COUNT) - 1:0] ibc_ref_indices
);
  localparam logic [31:0] HASH_OFFSET = 32'h811c_9dc5;

  logic [31:0] current_hash_q;
  logic [31:0] hash_lane_q [0:8];
  logic [31:0] hash_after_packet;
  logic [7:0] hash_sample_w [0:7];
  logic [31:0] hash_table_q [0:CU_COUNT - 1];
  logic hash_valid_q [0:CU_COUNT - 1];
  logic [5:0] ref_index_q [0:CU_COUNT - 1];

  logic [2:0] cu_col_w;
  logic [2:0] cu_row_w;
  logic [5:0] left_index_w;
  logic [5:0] above_index_w;
  logic [5:0] top_left_index_w;
  logic left_available_w;
  logic above_available_w;
  logic top_left_available_w;
  logic left_match_w;
  logic above_match_w;
  logic top_left_match_w;
  logic selected_match_w;
  logic [5:0] selected_index_w;

  integer clear_i;
  genvar pack_i;

  always @* begin
    hash_lane_q[0] = current_hash_q;
    for (int i = 0; i < 8; i = i + 1) begin
      hash_sample_w[i] = sample_data[i * 8 +: 8];
      if (i < sample_count) begin
        hash_lane_q[i + 1] =
          ((hash_lane_q[i] ^ {24'd0, hash_sample_w[i]}) ^
           ((hash_lane_q[i] ^ {24'd0, hash_sample_w[i]}) << 13));
        hash_lane_q[i + 1] =
          hash_lane_q[i + 1] ^ (hash_lane_q[i + 1] >> 17);
        hash_lane_q[i + 1] =
          hash_lane_q[i + 1] ^ (hash_lane_q[i + 1] << 5);
      end else begin
        hash_lane_q[i + 1] = hash_lane_q[i];
      end
    end
    hash_after_packet = hash_lane_q[8];
  end

  assign cu_col_w = cu_index[2:0];
  assign cu_row_w = cu_index[5:3];
  assign left_index_w = cu_index - 6'd1;
  assign above_index_w = cu_index - 6'd8;
  assign top_left_index_w = cu_index - 6'd9;
  assign left_available_w = cu_col_w != 3'd0;
  assign above_available_w = cu_row_w != 3'd0;
  assign top_left_available_w = left_available_w && above_available_w;
  assign left_match_w =
    left_available_w && hash_valid_q[left_index_w] &&
    (hash_table_q[left_index_w] == hash_after_packet);
  assign above_match_w =
    above_available_w && hash_valid_q[above_index_w] &&
    (hash_table_q[above_index_w] == hash_after_packet);
  assign top_left_match_w =
    top_left_available_w && hash_valid_q[top_left_index_w] &&
    (hash_table_q[top_left_index_w] == hash_after_packet);

  // H.266 8.6.2 IBC only references already coded blocks. This first
  // synthesis-oriented hash subset keeps the same A1/B1/B0 local candidate
  // order as src/vvc/ibc.rs so exact-hash decisions are available at the end
  // of each 8x8 TU without a wide CTU-scoped search.
  always @* begin
    selected_match_w = 1'b0;
    selected_index_w = 6'd0;
    if (left_match_w) begin
      selected_match_w = 1'b1;
      selected_index_w = left_index_w;
    end else if (above_match_w) begin
      selected_match_w = 1'b1;
      selected_index_w = above_index_w;
    end else if (top_left_match_w) begin
      selected_match_w = 1'b1;
      selected_index_w = top_left_index_w;
    end
  end

  assign idle = 1'b1;

  generate
    for (pack_i = 0; pack_i < CU_COUNT; pack_i = pack_i + 1) begin : gen_pack_outputs
      assign ibc_ref_indices[pack_i * 6 +: 6] = ref_index_q[pack_i];
    end
  endgenerate

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      current_hash_q <= HASH_OFFSET;
      ibc_cu_mask <= '0;
      for (clear_i = 0; clear_i < CU_COUNT; clear_i = clear_i + 1) begin
        hash_table_q[clear_i] <= 32'd0;
        hash_valid_q[clear_i] <= 1'b0;
        ref_index_q[clear_i] <= 6'd0;
      end
    end else if (clear || !enable) begin
      current_hash_q <= HASH_OFFSET;
      ibc_cu_mask <= '0;
      for (clear_i = 0; clear_i < CU_COUNT; clear_i = clear_i + 1) begin
        hash_table_q[clear_i] <= 32'd0;
        hash_valid_q[clear_i] <= 1'b0;
        ref_index_q[clear_i] <= 6'd0;
      end
    end else if (sample_valid) begin
      if (cu_last_sample) begin
        current_hash_q <= HASH_OFFSET;
        ibc_cu_mask[cu_index] <= 1'b0;
        ref_index_q[cu_index] <= 6'd0;
        if (cu_full_visible) begin
          hash_table_q[cu_index] <= hash_after_packet;
          hash_valid_q[cu_index] <= 1'b1;
          ibc_cu_mask[cu_index] <= selected_match_w;
          ref_index_q[cu_index] <= selected_match_w ? selected_index_w : 6'd0;
        end else begin
          hash_table_q[cu_index] <= 32'd0;
          hash_valid_q[cu_index] <= 1'b0;
        end
      end else begin
        current_hash_q <= hash_after_packet;
      end
    end
  end

  // Keep current public ports stable while this bounded IBC subset only needs
  // the compact raster CU index. Future wider-search IBC work can reuse these.
  logic unused_inputs;
  assign unused_inputs = ^{cu_origin_x, cu_origin_y, visible_width, visible_height, ctu_last_sample};
endmodule
