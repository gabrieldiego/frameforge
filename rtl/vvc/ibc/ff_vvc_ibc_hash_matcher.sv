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
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,
  input  logic ctu_last_sample,

  output logic idle,
  output logic [CU_COUNT - 1:0] ibc_cu_mask,
  output logic [(6 * CU_COUNT) - 1:0] ibc_ref_indices
);
  localparam logic [31:0] HASH_OFFSET = 32'h811c_9dc5;
  localparam logic [15:0] MIN_CODING_BLOCK_SIZE = 16'd4;
  localparam logic [15:0] MAX_TB_SIZEY = 16'd64;
  localparam logic [15:0] LUMA_MAX_LEAF_SIZE = 16'd8;
  localparam logic [15:0] LUMA_BOUNDARY_BT_SIZE = LUMA_MAX_LEAF_SIZE << 2;
  localparam logic [15:0] LUMA_MIN_QT_SIZE = 16'd8;

  localparam logic [3:0] ST_IDLE = 4'd0;
  localparam logic [3:0] ST_CLEAR = 4'd1;
  localparam logic [3:0] ST_POP = 4'd2;
  localparam logic [3:0] ST_DISPATCH = 4'd3;
  localparam logic [3:0] ST_PUSH = 4'd4;
  localparam logic [3:0] ST_RESOLVE_INIT = 4'd5;
  localparam logic [3:0] ST_RESOLVE_SCAN = 4'd6;
  localparam logic [3:0] ST_RESOLVE_COMMIT = 4'd7;
  localparam logic [3:0] ST_DONE = 4'd8;

  localparam int STACK_DEPTH = 16;

  logic [31:0] current_hash_q;
  logic [31:0] hash_after_xor;
  logic [31:0] hash_after_mix0;
  logic [31:0] hash_after_mix1;
  logic [31:0] hash_after_sample;
  logic [31:0] hash_table_q [0:CU_COUNT - 1];
  logic hash_valid_q [0:CU_COUNT - 1];
  logic [5:0] ref_index_q [0:CU_COUNT - 1];
  logic [3:0] state_q;
  logic [5:0] clear_index_q;
  logic [5:0] stack_count_q;
  logic [STACK_DEPTH - 1:0][3:0] stack_x4;
  logic [STACK_DEPTH - 1:0][3:0] stack_y4;
  logic [STACK_DEPTH - 1:0][2:0] stack_w_log2;
  logic [STACK_DEPTH - 1:0][2:0] stack_h_log2;
  logic [STACK_DEPTH - 1:0][2:0] stack_cqt;
  logic [STACK_DEPTH - 1:0][2:0] stack_mtt;
  logic [STACK_DEPTH - 1:0][2:0] stack_implicit_mtt;
  logic [3:0] stack_pop_index;
  logic [2:0] stack_pop_w_log2;
  logic [2:0] stack_pop_h_log2;
  logic [15:0] stack_pop_w;
  logic [15:0] stack_pop_h;
  logic [15:0] cur_x_q;
  logic [15:0] cur_y_q;
  logic [15:0] cur_w_q;
  logic [15:0] cur_h_q;
  logic [2:0] cur_w_log2_q;
  logic [2:0] cur_h_log2_q;
  logic [2:0] cur_cqt_q;
  logic [2:0] cur_mtt_q;
  logic [2:0] cur_implicit_mtt_q;
  logic split_is_qt_q;
  logic split_vertical_q;
  logic split_implicit_q;
  logic [15:0] split_x_q;
  logic [15:0] split_y_q;
  logic [15:0] split_w_q;
  logic [15:0] split_h_q;
  logic [2:0] split_w_log2_q;
  logic [2:0] split_h_log2_q;
  logic [2:0] split_cqt_q;
  logic [2:0] split_mtt_q;
  logic [2:0] split_implicit_mtt_q;
  logic [1:0] split_push_phase_q;
  logic [3:0] split_x4_w;
  logic [3:0] split_y4_w;
  logic [3:0] split_half_w4_w;
  logic [3:0] split_half_h4_w;
  logic [15:0] cur_right_w;
  logic [15:0] cur_bottom_w;
  logic cur_intersects_w;
  logic cur_fits_w;
  logic cur_leaf_allowed_w;
  logic cur_bottom_left_in_pic_w;
  logic cur_top_right_in_pic_w;
  logic cur_implicit_bt_allowed_w;
  logic fits_split_vertical_w;
  logic cur_qt_flag_can_be_signaled_w;
  logic cur_luma_can_qt_w;
  logic [3:0] cur_luma_max_btt_depth_w;
  logic cur_luma_can_btt_w;
  logic cur_luma_exceeds_bt_size_w;
  logic cur_luma_can_bh_w;
  logic cur_luma_can_bv_w;
  logic cur_luma_can_th_w;
  logic cur_luma_can_tv_w;
  logic [5:0] resolved_order_q [0:CU_COUNT - 1];
  logic [5:0] resolved_count_q;
  logic [5:0] scan_pos_q;
  logic [5:0] pending_cu_index_q;
  logic scan_match_valid_q;
  logic [5:0] scan_match_index_q;
  logic [5:0] scan_candidate_index_w;
  logic scan_hit_w;
  logic scan_last_w;
  logic selected_valid_w;
  logic [5:0] selected_index_w;
  logic [5:0] cur_leaf_index_w;
  logic cur_leaf_hash_valid_w;

  integer clear_i;
  genvar pack_i;

  assign hash_after_xor = current_hash_q ^ {24'd0, sample_data};
  assign hash_after_mix0 = hash_after_xor ^ (hash_after_xor << 13);
  assign hash_after_mix1 = hash_after_mix0 ^ (hash_after_mix0 >> 17);
  assign hash_after_sample = hash_after_mix1 ^ (hash_after_mix1 << 5);

  assign stack_pop_index = stack_count_q[3:0] - 4'd1;
  assign stack_pop_w_log2 = stack_w_log2[stack_pop_index];
  assign stack_pop_h_log2 = stack_h_log2[stack_pop_index];
  assign stack_pop_w = 16'd1 << stack_pop_w_log2;
  assign stack_pop_h = 16'd1 << stack_pop_h_log2;
  assign split_x4_w = split_x_q[5:2];
  assign split_y4_w = split_y_q[5:2];
  assign split_half_w4_w = split_w_q[6:3];
  assign split_half_h4_w = split_h_q[6:3];

  assign cur_right_w = cur_x_q + cur_w_q - 16'd1;
  assign cur_bottom_w = cur_y_q + cur_h_q - 16'd1;
  assign cur_intersects_w = (cur_x_q < visible_width) && (cur_y_q < visible_height);
  assign cur_fits_w = (cur_right_w < visible_width) && (cur_bottom_w < visible_height);
  assign cur_leaf_allowed_w = (cur_w_q <= LUMA_MAX_LEAF_SIZE) &&
    (cur_h_q <= LUMA_MAX_LEAF_SIZE);
  assign cur_bottom_left_in_pic_w = (cur_x_q < visible_width) &&
    (cur_bottom_w < visible_height);
  assign cur_top_right_in_pic_w = (cur_right_w < visible_width) &&
    (cur_y_q < visible_height);
  assign cur_implicit_bt_allowed_w = (cur_w_q <= LUMA_BOUNDARY_BT_SIZE) &&
    (cur_h_q <= LUMA_BOUNDARY_BT_SIZE);
  assign fits_split_vertical_w = (cur_w_q > LUMA_MAX_LEAF_SIZE) &&
    ((cur_h_q <= LUMA_MAX_LEAF_SIZE) || (cur_w_q >= cur_h_q));
  assign cur_qt_flag_can_be_signaled_w = (cur_mtt_q == 3'd0) &&
    (cur_w_q > LUMA_MIN_QT_SIZE) && (cur_h_q > LUMA_MIN_QT_SIZE);
  assign cur_luma_can_qt_w = (cur_mtt_q == 3'd0) &&
    (cur_w_q > LUMA_MIN_QT_SIZE) && (cur_h_q > LUMA_MIN_QT_SIZE);
  assign cur_luma_max_btt_depth_w = 4'd3 + {1'b0, cur_implicit_mtt_q};
  assign cur_luma_can_btt_w = ({1'b0, cur_mtt_q} < cur_luma_max_btt_depth_w) &&
    !((cur_w_q <= MIN_CODING_BLOCK_SIZE) && (cur_h_q <= MIN_CODING_BLOCK_SIZE)) &&
    !((cur_w_q > LUMA_BOUNDARY_BT_SIZE) || (cur_h_q > LUMA_BOUNDARY_BT_SIZE));
  assign cur_luma_exceeds_bt_size_w =
    (cur_w_q > LUMA_BOUNDARY_BT_SIZE) || (cur_h_q > LUMA_BOUNDARY_BT_SIZE);
  assign cur_luma_can_bh_w = cur_luma_can_btt_w && !cur_luma_exceeds_bt_size_w &&
    (cur_h_q > MIN_CODING_BLOCK_SIZE) &&
    !((cur_w_q > MAX_TB_SIZEY) && (cur_h_q <= MAX_TB_SIZEY));
  assign cur_luma_can_bv_w = cur_luma_can_btt_w && !cur_luma_exceeds_bt_size_w &&
    (cur_w_q > MIN_CODING_BLOCK_SIZE) &&
    !((cur_w_q <= MAX_TB_SIZEY) && (cur_h_q > MAX_TB_SIZEY));
  assign cur_luma_can_th_w = cur_luma_can_btt_w &&
    (cur_h_q > (MIN_CODING_BLOCK_SIZE << 1)) &&
    (cur_h_q <= LUMA_BOUNDARY_BT_SIZE) &&
    (cur_w_q <= LUMA_BOUNDARY_BT_SIZE) &&
    (cur_w_q <= MAX_TB_SIZEY) && (cur_h_q <= MAX_TB_SIZEY);
  assign cur_luma_can_tv_w = cur_luma_can_btt_w &&
    (cur_w_q > (MIN_CODING_BLOCK_SIZE << 1)) &&
    (cur_w_q <= LUMA_BOUNDARY_BT_SIZE) &&
    (cur_h_q <= LUMA_BOUNDARY_BT_SIZE) &&
    (cur_w_q <= MAX_TB_SIZEY) && (cur_h_q <= MAX_TB_SIZEY);

  assign cur_leaf_index_w = {cur_y_q[5:3], cur_x_q[5:3]};
  assign cur_leaf_hash_valid_w = hash_valid_q[cur_leaf_index_w];
  assign scan_candidate_index_w = resolved_order_q[scan_pos_q];
  assign scan_hit_w = (state_q == ST_RESOLVE_SCAN) &&
    cur_leaf_hash_valid_w &&
    hash_valid_q[scan_candidate_index_w] &&
    (hash_table_q[scan_candidate_index_w] == hash_table_q[pending_cu_index_q]);
  assign scan_last_w = (scan_pos_q == (resolved_count_q - 6'd1));
  assign selected_valid_w = scan_match_valid_q || scan_hit_w;
  assign selected_index_w = scan_match_valid_q ? scan_match_index_q : scan_candidate_index_w;
  assign idle = (state_q == ST_IDLE);

  generate
    for (pack_i = 0; pack_i < CU_COUNT; pack_i = pack_i + 1) begin : gen_pack_outputs
      assign ibc_ref_indices[pack_i * 6 +: 6] = ref_index_q[pack_i];
    end
  endgenerate

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      current_hash_q <= HASH_OFFSET;
      ibc_cu_mask <= '0;
      state_q <= ST_IDLE;
      clear_index_q <= 6'd0;
      stack_count_q <= 6'd0;
      cur_x_q <= 16'd0;
      cur_y_q <= 16'd0;
      cur_w_q <= 16'd0;
      cur_h_q <= 16'd0;
      cur_w_log2_q <= 3'd0;
      cur_h_log2_q <= 3'd0;
      cur_cqt_q <= 3'd0;
      cur_mtt_q <= 3'd0;
      cur_implicit_mtt_q <= 3'd0;
      split_is_qt_q <= 1'b0;
      split_vertical_q <= 1'b0;
      split_implicit_q <= 1'b0;
      split_x_q <= 16'd0;
      split_y_q <= 16'd0;
      split_w_q <= 16'd0;
      split_h_q <= 16'd0;
      split_w_log2_q <= 3'd0;
      split_h_log2_q <= 3'd0;
      split_cqt_q <= 3'd0;
      split_mtt_q <= 3'd0;
      split_implicit_mtt_q <= 3'd0;
      split_push_phase_q <= 2'd0;
      resolved_count_q <= 6'd0;
      scan_pos_q <= 6'd0;
      pending_cu_index_q <= 6'd0;
      scan_match_valid_q <= 1'b0;
      scan_match_index_q <= 6'd0;
      for (clear_i = 0; clear_i < CU_COUNT; clear_i = clear_i + 1) begin
        hash_table_q[clear_i] <= 32'd0;
        hash_valid_q[clear_i] <= 1'b0;
        ref_index_q[clear_i] <= 6'd0;
        resolved_order_q[clear_i] <= 6'd0;
      end
    end else if (clear || !enable) begin
      current_hash_q <= HASH_OFFSET;
      ibc_cu_mask <= '0;
      state_q <= ST_IDLE;
      clear_index_q <= 6'd0;
      stack_count_q <= 6'd0;
      resolved_count_q <= 6'd0;
      scan_pos_q <= 6'd0;
      pending_cu_index_q <= 6'd0;
      scan_match_valid_q <= 1'b0;
      scan_match_index_q <= 6'd0;
      for (clear_i = 0; clear_i < CU_COUNT; clear_i = clear_i + 1) begin
        hash_table_q[clear_i] <= 32'd0;
        hash_valid_q[clear_i] <= 1'b0;
        ref_index_q[clear_i] <= 6'd0;
        resolved_order_q[clear_i] <= 6'd0;
      end
    end else begin
      case (state_q)
        ST_CLEAR: begin
          ibc_cu_mask[clear_index_q] <= 1'b0;
          ref_index_q[clear_index_q] <= 6'd0;
          resolved_order_q[clear_index_q] <= 6'd0;
          if (clear_index_q == (CU_COUNT - 1)) begin
            stack_x4[0] <= 4'd0;
            stack_y4[0] <= 4'd0;
            stack_w_log2[0] <= 3'd6;
            stack_h_log2[0] <= 3'd6;
            stack_cqt[0] <= 3'd0;
            stack_mtt[0] <= 3'd0;
            stack_implicit_mtt[0] <= 3'd0;
            stack_count_q <= 6'd1;
            clear_index_q <= 6'd0;
            resolved_count_q <= 6'd0;
            state_q <= ST_POP;
          end else begin
            clear_index_q <= clear_index_q + 6'd1;
          end
        end

        ST_POP: begin
          if (stack_count_q == 6'd0) begin
            state_q <= ST_DONE;
          end else begin
            cur_x_q <= {10'd0, stack_x4[stack_pop_index], 2'd0};
            cur_y_q <= {10'd0, stack_y4[stack_pop_index], 2'd0};
            cur_w_q <= stack_pop_w;
            cur_h_q <= stack_pop_h;
            cur_w_log2_q <= stack_pop_w_log2;
            cur_h_log2_q <= stack_pop_h_log2;
            cur_cqt_q <= stack_cqt[stack_pop_index];
            cur_mtt_q <= stack_mtt[stack_pop_index];
            cur_implicit_mtt_q <= stack_implicit_mtt[stack_pop_index];
            stack_count_q <= stack_count_q - 6'd1;
            state_q <= ST_DISPATCH;
          end
        end

        ST_DISPATCH: begin
          if (!cur_intersects_w) begin
            state_q <= ST_POP;
          end else if (cur_fits_w && cur_leaf_allowed_w) begin
            pending_cu_index_q <= cur_leaf_index_w;
            scan_pos_q <= 6'd0;
            scan_match_valid_q <= 1'b0;
            scan_match_index_q <= 6'd0;
            state_q <= ST_RESOLVE_INIT;
          end else begin
            split_x_q <= cur_x_q;
            split_y_q <= cur_y_q;
            split_w_q <= cur_w_q;
            split_h_q <= cur_h_q;
            split_w_log2_q <= cur_w_log2_q;
            split_h_log2_q <= cur_h_log2_q;
            split_cqt_q <= cur_cqt_q;
            split_mtt_q <= cur_mtt_q;
            split_implicit_mtt_q <= cur_implicit_mtt_q;
            split_push_phase_q <= 2'd0;
            if ((!cur_fits_w) &&
                (((!cur_bottom_left_in_pic_w && !cur_top_right_in_pic_w) ||
                  !cur_implicit_bt_allowed_w) ||
                 (!cur_bottom_left_in_pic_w && cur_top_right_in_pic_w &&
                  cur_qt_flag_can_be_signaled_w &&
                  (cur_w_q > LUMA_MAX_LEAF_SIZE) &&
                  (cur_h_q > LUMA_MAX_LEAF_SIZE)))) begin
              split_is_qt_q <= 1'b1;
              split_vertical_q <= 1'b0;
              split_implicit_q <= 1'b0;
            end else if (!cur_fits_w) begin
              split_is_qt_q <= 1'b0;
              split_vertical_q <= !cur_top_right_in_pic_w;
              split_implicit_q <= 1'b1;
            end else if (cur_mtt_q != 3'd0) begin
              split_is_qt_q <= 1'b0;
              split_vertical_q <= fits_split_vertical_w;
              split_implicit_q <= 1'b0;
            end else begin
              split_is_qt_q <= 1'b1;
              split_vertical_q <= 1'b0;
              split_implicit_q <= 1'b0;
            end
            state_q <= ST_PUSH;
          end
        end

        ST_PUSH: begin
          if (split_is_qt_q) begin
            stack_w_log2[stack_count_q] <= split_w_log2_q - 3'd1;
            stack_h_log2[stack_count_q] <= split_h_log2_q - 3'd1;
            stack_cqt[stack_count_q] <= split_cqt_q + 3'd1;
            stack_mtt[stack_count_q] <= 3'd0;
            stack_implicit_mtt[stack_count_q] <= 3'd0;
            case (split_push_phase_q)
              2'd0: begin
                stack_x4[stack_count_q] <= split_x4_w + split_half_w4_w;
                stack_y4[stack_count_q] <= split_y4_w + split_half_h4_w;
              end
              2'd1: begin
                stack_x4[stack_count_q] <= split_x4_w;
                stack_y4[stack_count_q] <= split_y4_w + split_half_h4_w;
              end
              2'd2: begin
                stack_x4[stack_count_q] <= split_x4_w + split_half_w4_w;
                stack_y4[stack_count_q] <= split_y4_w;
              end
              default: begin
                stack_x4[stack_count_q] <= split_x4_w;
                stack_y4[stack_count_q] <= split_y4_w;
              end
            endcase
            stack_count_q <= stack_count_q + 6'd1;
            if (split_push_phase_q == 2'd3) begin
              split_push_phase_q <= 2'd0;
              state_q <= ST_POP;
            end else begin
              split_push_phase_q <= split_push_phase_q + 2'd1;
            end
          end else if (split_vertical_q) begin
            stack_x4[stack_count_q] <=
              (split_push_phase_q == 2'd0) ? (split_x4_w + split_half_w4_w) : split_x4_w;
            stack_y4[stack_count_q] <= split_y4_w;
            stack_w_log2[stack_count_q] <= split_w_log2_q - 3'd1;
            stack_h_log2[stack_count_q] <= split_h_log2_q;
            stack_cqt[stack_count_q] <= split_cqt_q;
            stack_mtt[stack_count_q] <= split_mtt_q + 3'd1;
            stack_implicit_mtt[stack_count_q] <= split_implicit_mtt_q + {2'd0, split_implicit_q};
            stack_count_q <= stack_count_q + 6'd1;
            if (split_push_phase_q == 2'd1) begin
              split_push_phase_q <= 2'd0;
              state_q <= ST_POP;
            end else begin
              split_push_phase_q <= 2'd1;
            end
          end else begin
            stack_x4[stack_count_q] <= split_x4_w;
            stack_y4[stack_count_q] <=
              (split_push_phase_q == 2'd0) ? (split_y4_w + split_half_h4_w) : split_y4_w;
            stack_w_log2[stack_count_q] <= split_w_log2_q;
            stack_h_log2[stack_count_q] <= split_h_log2_q - 3'd1;
            stack_cqt[stack_count_q] <= split_cqt_q;
            stack_mtt[stack_count_q] <= split_mtt_q + 3'd1;
            stack_implicit_mtt[stack_count_q] <= split_implicit_mtt_q + {2'd0, split_implicit_q};
            stack_count_q <= stack_count_q + 6'd1;
            if (split_push_phase_q == 2'd1) begin
              split_push_phase_q <= 2'd0;
              state_q <= ST_POP;
            end else begin
              split_push_phase_q <= 2'd1;
            end
          end
        end

        ST_RESOLVE_INIT: begin
          if (!cur_leaf_hash_valid_w || (resolved_count_q == 6'd0)) begin
            state_q <= ST_RESOLVE_COMMIT;
          end else begin
            state_q <= ST_RESOLVE_SCAN;
          end
        end

        ST_RESOLVE_SCAN: begin
          if (scan_hit_w && !scan_match_valid_q) begin
            scan_match_valid_q <= 1'b1;
            scan_match_index_q <= scan_candidate_index_w;
          end
          if (scan_last_w) begin
            state_q <= ST_RESOLVE_COMMIT;
          end else begin
            scan_pos_q <= scan_pos_q + 6'd1;
          end
        end

        ST_RESOLVE_COMMIT: begin
          // Resolve hash matches only after walking prior leaves in
          // coding-tree order. The top-level mux derives H.266 8.6.2.2
          // BVP/HMVP-dependent MVD values when it emits the CU syntax, because
          // runtime IBC CUs from the palette symbolizer can also populate that
          // state before a later exact-hash IBC CU is written.
          ibc_cu_mask[pending_cu_index_q] <= selected_valid_w;
          ref_index_q[pending_cu_index_q] <= selected_valid_w ? selected_index_w : 6'd0;
          if (cur_leaf_hash_valid_w) begin
            resolved_order_q[resolved_count_q] <= pending_cu_index_q;
            resolved_count_q <= resolved_count_q + 6'd1;
          end
          scan_pos_q <= 6'd0;
          scan_match_valid_q <= 1'b0;
          scan_match_index_q <= 6'd0;
          state_q <= ST_POP;
        end

        ST_DONE: begin
          state_q <= ST_IDLE;
        end

        default: begin
          state_q <= ST_IDLE;
        end
      endcase

      if (sample_valid) begin
        if (cu_last_sample) begin
          current_hash_q <= HASH_OFFSET;
          if (cu_full_visible) begin
            hash_table_q[cu_index] <= hash_after_sample;
            hash_valid_q[cu_index] <= 1'b1;
          end else begin
            ibc_cu_mask[cu_index] <= 1'b0;
            hash_table_q[cu_index] <= 32'd0;
            hash_valid_q[cu_index] <= 1'b0;
            ref_index_q[cu_index] <= 6'd0;
          end
          if (ctu_last_sample) begin
            state_q <= ST_CLEAR;
            clear_index_q <= 6'd0;
          end
        end else begin
          current_hash_q <= hash_after_sample;
        end
      end
    end
  end
endmodule
