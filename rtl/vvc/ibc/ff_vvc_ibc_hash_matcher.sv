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
  input  logic [7:0] sample_data,
  input  logic [5:0] cu_index,
  input  logic [15:0] cu_origin_x,
  input  logic [15:0] cu_origin_y,
  input  logic cu_full_visible,
  input  logic cu_last_sample,

  output logic idle,
  output logic [CU_COUNT - 1:0] ibc_cu_mask,
  output logic [(6 * CU_COUNT) - 1:0] ibc_ref_indices,
  output logic [(16 * CU_COUNT) - 1:0] ibc_mvd_x,
  output logic [(16 * CU_COUNT) - 1:0] ibc_mvd_y
);
  localparam logic [31:0] HASH_OFFSET = 32'h811c_9dc5;
  localparam int CU_COLS = CTU_SIZE / CU_SIZE;
  localparam int BV_SAMPLE_SHIFT = 7;

  logic [31:0] current_hash_q;
  logic [31:0] hash_after_xor;
  logic [31:0] hash_after_mix0;
  logic [31:0] hash_after_mix1;
  logic [31:0] hash_after_sample;
  logic [31:0] hash_table_q [0:CU_COUNT - 1];
  logic hash_valid_q [0:CU_COUNT - 1];
  logic signed [15:0] bv_x_q [0:CU_COUNT - 1];
  logic signed [15:0] bv_y_q [0:CU_COUNT - 1];
  logic [5:0] ref_index_q [0:CU_COUNT - 1];
  logic signed [15:0] mvd_x_q [0:CU_COUNT - 1];
  logic signed [15:0] mvd_y_q [0:CU_COUNT - 1];
  logic signed [15:0] hmvp_bv_x_q;
  logic signed [15:0] hmvp_bv_y_q;
  logic hmvp_valid_q;
  logic scan_active_q;
  logic [5:0] scan_pos_q;
  logic [31:0] pending_hash_q;
  logic [5:0] pending_cu_index_q;
  logic [2:0] pending_cur_col_q;
  logic [2:0] pending_cur_row_q;
  logic scan_match_valid_q;
  logic [5:0] scan_match_index_q;
  logic scan_hit_w;
  logic scan_done_w;
  logic scan_selected_valid_w;
  logic [5:0] scan_selected_index_w;
  logic [2:0] ref_col_w;
  logic [2:0] ref_row_w;
  logic signed [4:0] delta_col_w;
  logic signed [4:0] delta_row_w;
  logic signed [15:0] candidate_bv_x_w;
  logic signed [15:0] candidate_bv_y_w;
  logic signed [15:0] pred_bv_x_w;
  logic signed [15:0] pred_bv_y_w;
  logic signed [15:0] bvd_x_w;
  logic signed [15:0] bvd_y_w;
  logic [5:0] left_index_w;
  logic [5:0] above_index_w;
  logic [5:0] scan_index_w;

  integer clear_i;
  genvar pack_i;

  assign hash_after_xor = current_hash_q ^ {24'd0, sample_data};
  assign hash_after_mix0 = hash_after_xor ^ (hash_after_xor << 13);
  assign hash_after_mix1 = hash_after_mix0 ^ (hash_after_mix0 >> 17);
  assign hash_after_sample = hash_after_mix1 ^ (hash_after_mix1 << 5);

  // Search one 8x8 CU hash candidate per cycle. The next CU needs 192
  // sample cycles in 4:4:4 mode, so a 64-entry CTU-local search completes
  // before the following CU can request its final IBC decision.
  assign scan_index_w = {
    scan_pos_q[5],
    scan_pos_q[3],
    scan_pos_q[1],
    scan_pos_q[4],
    scan_pos_q[2],
    scan_pos_q[0]
  };
  assign scan_hit_w =
    scan_active_q &&
    hash_valid_q[scan_index_w] &&
    (hash_table_q[scan_index_w] == pending_hash_q);
  assign scan_done_w = scan_active_q && (scan_pos_q == (CU_COUNT - 1));
  assign scan_selected_valid_w = scan_match_valid_q || scan_hit_w;
  assign scan_selected_index_w = scan_match_valid_q ? scan_match_index_q : scan_index_w;

  assign ref_col_w = scan_selected_index_w[2:0];
  assign ref_row_w = scan_selected_index_w[5:3];
  assign delta_col_w = {2'b00, ref_col_w} - {2'b00, pending_cur_col_q};
  assign delta_row_w = {2'b00, ref_row_w} - {2'b00, pending_cur_row_q};
  assign candidate_bv_x_w = $signed(delta_col_w) <<< BV_SAMPLE_SHIFT;
  assign candidate_bv_y_w = $signed(delta_row_w) <<< BV_SAMPLE_SHIFT;
  assign left_index_w = pending_cu_index_q - 6'd1;
  assign above_index_w = pending_cu_index_q - 6'd8;
  assign bvd_x_w = candidate_bv_x_w - pred_bv_x_w;
  assign bvd_y_w = candidate_bv_y_w - pred_bv_y_w;
  assign idle = !scan_active_q;

  always @* begin
    pred_bv_x_w = 16'sd0;
    pred_bv_y_w = 16'sd0;
    // H.266 8.6.2.2 with MaxNumIbcMergeCand equal to 1: A1, then B1,
    // then the newest HMVP candidate, then zero. Store BVs in 1/16-sample
    // units and store mvd_* below in integer-sample units for mvd_coding().
    if ((pending_cur_col_q != 3'd0) && ibc_cu_mask[left_index_w]) begin
      pred_bv_x_w = bv_x_q[left_index_w];
      pred_bv_y_w = bv_y_q[left_index_w];
    end else if ((pending_cur_row_q != 3'd0) && ibc_cu_mask[above_index_w]) begin
      pred_bv_x_w = bv_x_q[above_index_w];
      pred_bv_y_w = bv_y_q[above_index_w];
    end else if (hmvp_valid_q) begin
      pred_bv_x_w = hmvp_bv_x_q;
      pred_bv_y_w = hmvp_bv_y_q;
    end
  end

  generate
    for (pack_i = 0; pack_i < CU_COUNT; pack_i = pack_i + 1) begin : gen_pack_outputs
      assign ibc_ref_indices[pack_i * 6 +: 6] = ref_index_q[pack_i];
      assign ibc_mvd_x[pack_i * 16 +: 16] = mvd_x_q[pack_i];
      assign ibc_mvd_y[pack_i * 16 +: 16] = mvd_y_q[pack_i];
    end
  endgenerate

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      current_hash_q <= HASH_OFFSET;
      ibc_cu_mask <= '0;
      hmvp_bv_x_q <= 16'sd0;
      hmvp_bv_y_q <= 16'sd0;
      hmvp_valid_q <= 1'b0;
      scan_active_q <= 1'b0;
      scan_pos_q <= 6'd0;
      pending_hash_q <= 32'd0;
      pending_cu_index_q <= 6'd0;
      pending_cur_col_q <= 3'd0;
      pending_cur_row_q <= 3'd0;
      scan_match_valid_q <= 1'b0;
      scan_match_index_q <= 6'd0;
      for (clear_i = 0; clear_i < CU_COUNT; clear_i = clear_i + 1) begin
        hash_table_q[clear_i] <= 32'd0;
        hash_valid_q[clear_i] <= 1'b0;
        bv_x_q[clear_i] <= 16'sd0;
        bv_y_q[clear_i] <= 16'sd0;
        ref_index_q[clear_i] <= 6'd0;
        mvd_x_q[clear_i] <= 16'sd0;
        mvd_y_q[clear_i] <= 16'sd0;
      end
    end else if (clear || !enable) begin
      current_hash_q <= HASH_OFFSET;
      ibc_cu_mask <= '0;
      hmvp_bv_x_q <= 16'sd0;
      hmvp_bv_y_q <= 16'sd0;
      hmvp_valid_q <= 1'b0;
      scan_active_q <= 1'b0;
      scan_pos_q <= 6'd0;
      pending_hash_q <= 32'd0;
      pending_cu_index_q <= 6'd0;
      pending_cur_col_q <= 3'd0;
      pending_cur_row_q <= 3'd0;
      scan_match_valid_q <= 1'b0;
      scan_match_index_q <= 6'd0;
      for (clear_i = 0; clear_i < CU_COUNT; clear_i = clear_i + 1) begin
        hash_table_q[clear_i] <= 32'd0;
        hash_valid_q[clear_i] <= 1'b0;
        bv_x_q[clear_i] <= 16'sd0;
        bv_y_q[clear_i] <= 16'sd0;
        ref_index_q[clear_i] <= 6'd0;
        mvd_x_q[clear_i] <= 16'sd0;
        mvd_y_q[clear_i] <= 16'sd0;
      end
    end else begin
      if (scan_active_q) begin
        if (scan_hit_w && !scan_match_valid_q) begin
          scan_match_valid_q <= 1'b1;
          scan_match_index_q <= scan_index_w;
        end

        if (scan_done_w) begin
          scan_active_q <= 1'b0;
          scan_pos_q <= 6'd0;
          scan_match_valid_q <= 1'b0;
          scan_match_index_q <= 6'd0;
          ibc_cu_mask[pending_cu_index_q] <= scan_selected_valid_w;
          hash_table_q[pending_cu_index_q] <= pending_hash_q;
          hash_valid_q[pending_cu_index_q] <= 1'b1;
          ref_index_q[pending_cu_index_q] <=
            scan_selected_valid_w ? scan_selected_index_w : 6'd0;
          if (scan_selected_valid_w) begin
            bv_x_q[pending_cu_index_q] <= candidate_bv_x_w;
            bv_y_q[pending_cu_index_q] <= candidate_bv_y_w;
            mvd_x_q[pending_cu_index_q] <= bvd_x_w >>> 4;
            mvd_y_q[pending_cu_index_q] <= bvd_y_w >>> 4;
            hmvp_bv_x_q <= candidate_bv_x_w;
            hmvp_bv_y_q <= candidate_bv_y_w;
            hmvp_valid_q <= 1'b1;
          end else begin
            bv_x_q[pending_cu_index_q] <= 16'sd0;
            bv_y_q[pending_cu_index_q] <= 16'sd0;
            mvd_x_q[pending_cu_index_q] <= 16'sd0;
            mvd_y_q[pending_cu_index_q] <= 16'sd0;
          end
        end else begin
          scan_pos_q <= scan_pos_q + 6'd1;
        end
      end

      if (sample_valid) begin
        if (cu_last_sample) begin
          current_hash_q <= HASH_OFFSET;
          if (cu_full_visible) begin
            scan_active_q <= 1'b1;
            scan_pos_q <= 6'd0;
            pending_hash_q <= hash_after_sample;
            pending_cu_index_q <= cu_index;
            pending_cur_col_q <= cu_origin_x[5:3];
            pending_cur_row_q <= cu_origin_y[5:3];
            scan_match_valid_q <= 1'b0;
            scan_match_index_q <= 6'd0;
          end else begin
            ibc_cu_mask[cu_index] <= 1'b0;
            hash_table_q[cu_index] <= 32'd0;
            hash_valid_q[cu_index] <= 1'b0;
            ref_index_q[cu_index] <= 6'd0;
            bv_x_q[cu_index] <= 16'sd0;
            bv_y_q[cu_index] <= 16'sd0;
            mvd_x_q[cu_index] <= 16'sd0;
            mvd_y_q[cu_index] <= 16'sd0;
          end
        end else begin
          current_hash_q <= hash_after_sample;
        end
      end
    end
  end
endmodule
