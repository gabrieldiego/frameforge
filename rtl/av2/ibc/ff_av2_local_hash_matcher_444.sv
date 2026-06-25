`timescale 1ns/1ps

module ff_av2_local_hash_matcher_444 #(
  parameter int SAMPLE_BITS = 8
) (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       start,
  input  logic       sample_fire,
  input  logic       packet_fire,
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,
  input  logic [SAMPLE_BITS - 1:0] sample,
  input  logic       sample_last,
  input  logic [8*SAMPLE_BITS - 1:0] packet_samples,
  input  logic [3:0] packet_count,
  input  logic       packet_last,
  output logic       done,
  output logic       any_copy,
  output logic [63:0] copy_mask,
  output logic [63:0] above_copy_mask,
  output logic [127:0] drl_idx_table
);

  localparam logic [1:0] ST_IDLE = 2'd0;
  localparam logic [1:0] ST_READ = 2'd1;
  localparam logic [1:0] ST_DECIDE = 2'd2;
  localparam logic [1:0] ST_DONE = 2'd3;
  localparam logic [31:0] HASH_OFFSET = 32'h811c_9dc5;

  logic [1:0] state_q;
  logic [2:0] last_block_col_q;
  logic [2:0] last_block_row_q;
  logic [5:0] block_id_q;
  logic [5:0] decide_index_q;
  logic [7:0] block_sample_q;
  logic [31:0] current_hash_q;
  logic [31:0] hash_table_q [0:63];
  logic [63:0] coded_mask_q;

  logic [31:0] hash_after_xor_w;
  logic [31:0] hash_after_mix0_w;
  logic [31:0] hash_after_mix1_w;
  logic [31:0] hash_after_sample_w;
  logic [31:0] hash_after_packet_w;
  logic [5:0] decide_block_id_w;
  logic [5:0] above_block_id_w;
  logic [5:0] left_block_id_w;
  logic [5:0] top_right_block_id_w;
  logic [5:0] top_left_block_id_w;
  logic [5:0] bottom_left_block_id_w;
  logic [5:0] second_left_block_id_w;
  logic [6:0] decide_drl_bit_index_w;
  logic [1:0] direct0_vec_w;
  logic [1:0] direct1_vec_w;
  logic [1:0] direct_count_w;
  logic [1:0] spatial0_vec_w;
  logic [1:0] spatial1_vec_w;
  logic spatial0_valid_w;
  logic spatial1_valid_w;
  logic [1:0] above_drl_idx_w;
  logic [1:0] left_drl_idx_w;
  logic [1:0] candidate_drl_idx_w;
  logic above_in_tile_w;
  logic left_in_tile_w;
  logic top_right_in_tile_w;
  logic top_left_in_tile_w;
  logic bottom_left_in_tile_w;
  logic second_left_in_tile_w;
  logic decide_block_visible_w;
  logic terminal_tile_row_w;
  logic direct_left_valid_w;
  logic direct_above_valid_w;
  logic bottom_left_valid_w;
  logic top_right_valid_w;
  logic top_left_valid_w;
  logic second_left_valid_w;
  logic direct_left_vec_above_w;
  logic direct_above_vec_above_w;
  logic bottom_left_vec_above_w;
  logic top_right_vec_above_w;
  logic top_left_vec_above_w;
  logic second_left_vec_above_w;
  logic above_drl_valid_w;
  logic left_drl_valid_w;
  logic block_complete_w;
  logic above_match_w;
  logic left_match_w;
  logic copy_match_w;
  logic candidate_above_w;
  logic enabled_w;
  logic [7:0] packet_last_sample_w;
  logic packet_block_complete_w;
  integer packet_lane_q;

  assign enabled_w = (SAMPLE_BITS == 8);
  assign hash_after_xor_w = current_hash_q ^ {24'd0, sample[7:0]};
  assign hash_after_mix0_w = hash_after_xor_w ^ (hash_after_xor_w << 13);
  assign hash_after_mix1_w = hash_after_mix0_w ^ (hash_after_mix0_w >> 17);
  assign hash_after_sample_w = hash_after_mix1_w ^ (hash_after_mix1_w << 5);
  always_comb begin
    hash_after_packet_w = current_hash_q;
    for (packet_lane_q = 0; packet_lane_q < 8; packet_lane_q = packet_lane_q + 1) begin
      if (packet_lane_q < packet_count) begin
        hash_after_packet_w =
          hash_after_packet_w ^ {24'd0, packet_samples[packet_lane_q * SAMPLE_BITS +: 8]};
        hash_after_packet_w = hash_after_packet_w ^ (hash_after_packet_w << 13);
        hash_after_packet_w = hash_after_packet_w ^ (hash_after_packet_w >> 17);
        hash_after_packet_w = hash_after_packet_w ^ (hash_after_packet_w << 5);
      end
    end
  end
  assign above_block_id_w = decide_block_id_w - 6'd8;
  assign left_block_id_w = decide_block_id_w - 6'd1;
  assign top_right_block_id_w = decide_block_id_w - 6'd7;
  assign top_left_block_id_w = decide_block_id_w - 6'd9;
  assign bottom_left_block_id_w = decide_block_id_w + 6'd7;
  assign second_left_block_id_w = decide_block_id_w - 6'd2;
  assign decide_drl_bit_index_w = {decide_block_id_w, 1'b0};
  assign above_in_tile_w = decide_block_id_w[5:3] != 3'd0;
  assign left_in_tile_w = decide_block_id_w[2:0] != 3'd0;
  assign top_right_in_tile_w =
    (decide_block_id_w[5:3] != 3'd0) &&
    (decide_block_id_w[2:0] != last_block_col_q) &&
    ((decide_block_id_w[2:0] + 3'd1) <= last_block_col_q);
  assign top_left_in_tile_w = above_in_tile_w && left_in_tile_w;
  assign bottom_left_in_tile_w =
    (decide_block_id_w[5:3] != last_block_row_q) &&
    ((decide_block_id_w[5:3] + 3'd1) <= last_block_row_q) &&
    left_in_tile_w;
  assign second_left_in_tile_w = decide_block_id_w[2:0] >= 3'd2;
  assign decide_block_visible_w =
    (decide_block_id_w[5:3] <= last_block_row_q) &&
    (decide_block_id_w[2:0] <= last_block_col_q);
  assign direct_left_valid_w =
    left_in_tile_w && coded_mask_q[left_block_id_w] && copy_mask[left_block_id_w];
  assign direct_above_valid_w =
    above_in_tile_w && coded_mask_q[above_block_id_w] && copy_mask[above_block_id_w];
  assign bottom_left_valid_w =
    bottom_left_in_tile_w && coded_mask_q[bottom_left_block_id_w] &&
    copy_mask[bottom_left_block_id_w];
  assign top_right_valid_w =
    top_right_in_tile_w && coded_mask_q[top_right_block_id_w] &&
    copy_mask[top_right_block_id_w];
  assign top_left_valid_w =
    top_left_in_tile_w && coded_mask_q[top_left_block_id_w] &&
    copy_mask[top_left_block_id_w];
  assign second_left_valid_w =
    second_left_in_tile_w && coded_mask_q[second_left_block_id_w] &&
    copy_mask[second_left_block_id_w];
  assign direct_left_vec_above_w = above_copy_mask[left_block_id_w];
  assign direct_above_vec_above_w = above_copy_mask[above_block_id_w];
  assign bottom_left_vec_above_w = above_copy_mask[bottom_left_block_id_w];
  assign top_right_vec_above_w = above_copy_mask[top_right_block_id_w];
  assign top_left_vec_above_w = above_copy_mask[top_left_block_id_w];
  assign second_left_vec_above_w = above_copy_mask[second_left_block_id_w];
  assign direct0_vec_w = spatial0_vec_w;
  assign direct1_vec_w = spatial1_vec_w;
  assign direct_count_w =
    spatial1_valid_w ? 2'd2 : (spatial0_valid_w ? 2'd1 : 2'd0);
  assign above_drl_valid_w =
    (direct_count_w != 2'd0 && direct0_vec_w == 2'd1) ||
    (direct_count_w == 2'd2 && direct1_vec_w == 2'd1) ||
    (direct_count_w <= 2'd1);
  assign above_drl_idx_w =
    (direct_count_w != 2'd0 && direct0_vec_w == 2'd1) ? 2'd0 :
    ((direct_count_w == 2'd2 && direct1_vec_w == 2'd1) ? 2'd1 :
      (direct_count_w + 2'd2));
  assign left_drl_valid_w =
    (direct_count_w != 2'd0 && direct0_vec_w == 2'd0) ||
    (direct_count_w == 2'd2 && direct1_vec_w == 2'd0) ||
    (direct_count_w == 2'd0);
  assign left_drl_idx_w =
    (direct_count_w != 2'd0 && direct0_vec_w == 2'd0) ? 2'd0 :
    ((direct_count_w == 2'd2 && direct1_vec_w == 2'd0) ? 2'd1 : 2'd3);
  assign block_complete_w = sample_fire && (block_sample_q == 8'd191);
  assign packet_last_sample_w = block_sample_q + {4'd0, packet_count} - 8'd1;
  assign packet_block_complete_w = packet_fire && (packet_last_sample_w >= 8'd191);
  assign terminal_tile_row_w = decide_block_id_w[5:3] == last_block_row_q;
  // AV2 v1.0.0 av2_is_dv_in_local_range() accepts the local above 8x8 BV
  // when the referenced block is coded inside the same 64x64 tile. Keep this
  // expansion on the terminal 8x8 row and the default setup_ref_mv_list() BVP
  // slot until the RTL mirrors AVM's full is_mi_coded/pseudo-coded
  // availability map for shifted slots and follow-on vertical IBC contexts.
  assign above_match_w =
    enabled_w &&
    above_in_tile_w &&
    terminal_tile_row_w &&
    coded_mask_q[above_block_id_w] &&
    above_drl_valid_w &&
    (above_drl_idx_w == 2'd2) &&
    (hash_table_q[above_block_id_w] == hash_table_q[decide_block_id_w]);
  assign left_match_w =
    enabled_w &&
    above_in_tile_w &&
    left_in_tile_w &&
    coded_mask_q[left_block_id_w] &&
    left_drl_valid_w &&
    (hash_table_q[left_block_id_w] == hash_table_q[decide_block_id_w]);
  assign copy_match_w = above_match_w || left_match_w;
  assign candidate_above_w =
    above_match_w && (!left_match_w || (above_drl_idx_w <= left_drl_idx_w));
  assign candidate_drl_idx_w = candidate_above_w ? above_drl_idx_w : left_drl_idx_w;

  always @* begin
    // AV2 v1.0.0 setup_ref_mv_list() scans spatial IntraBC candidates before
    // appending default BVs. FrameForge's fixed 8x8 leaves can carry only the
    // local above/left vectors today, so the unique spatial stack needs at most
    // two entries while preserving AVM scan order for intrabc_drl_idx.
    spatial0_valid_w = 1'b0;
    spatial0_vec_w = 2'd0;
    spatial1_valid_w = 1'b0;
    spatial1_vec_w = 2'd0;

    if (direct_left_valid_w) begin
      spatial0_valid_w = 1'b1;
      spatial0_vec_w = {1'b0, direct_left_vec_above_w};
    end
    if (direct_above_valid_w) begin
      if (!spatial0_valid_w) begin
        spatial0_valid_w = 1'b1;
        spatial0_vec_w = {1'b0, direct_above_vec_above_w};
      end else if (!spatial1_valid_w &&
                   spatial0_vec_w != {1'b0, direct_above_vec_above_w}) begin
        spatial1_valid_w = 1'b1;
        spatial1_vec_w = {1'b0, direct_above_vec_above_w};
      end
    end
    if (bottom_left_valid_w) begin
      if (!spatial0_valid_w) begin
        spatial0_valid_w = 1'b1;
        spatial0_vec_w = {1'b0, bottom_left_vec_above_w};
      end else if (!spatial1_valid_w &&
                   spatial0_vec_w != {1'b0, bottom_left_vec_above_w}) begin
        spatial1_valid_w = 1'b1;
        spatial1_vec_w = {1'b0, bottom_left_vec_above_w};
      end
    end
    if (top_right_valid_w) begin
      if (!spatial0_valid_w) begin
        spatial0_valid_w = 1'b1;
        spatial0_vec_w = {1'b0, top_right_vec_above_w};
      end else if (!spatial1_valid_w &&
                   spatial0_vec_w != {1'b0, top_right_vec_above_w}) begin
        spatial1_valid_w = 1'b1;
        spatial1_vec_w = {1'b0, top_right_vec_above_w};
      end
    end
    if (top_left_valid_w) begin
      if (!spatial0_valid_w) begin
        spatial0_valid_w = 1'b1;
        spatial0_vec_w = {1'b0, top_left_vec_above_w};
      end else if (!spatial1_valid_w &&
                   spatial0_vec_w != {1'b0, top_left_vec_above_w}) begin
        spatial1_valid_w = 1'b1;
        spatial1_vec_w = {1'b0, top_left_vec_above_w};
      end
    end
    if (second_left_valid_w) begin
      if (!spatial0_valid_w) begin
        spatial0_valid_w = 1'b1;
        spatial0_vec_w = {1'b0, second_left_vec_above_w};
      end else if (!spatial1_valid_w &&
                   spatial0_vec_w != {1'b0, second_left_vec_above_w}) begin
        spatial1_valid_w = 1'b1;
        spatial1_vec_w = {1'b0, second_left_vec_above_w};
      end
    end
  end

  // Fixed 8x8 leaf walk for a 64x64 superblock. The partition traversal visits
  // 2x2 leaf groups recursively, which is the bit permutation
  // row={b5,b3,b1}, col={b4,b2,b0}; keep it structural instead of a 64-way
  // decode table.
  assign decide_block_id_w = {
    decide_index_q[5],
    decide_index_q[3],
    decide_index_q[1],
    decide_index_q[4],
    decide_index_q[2],
    decide_index_q[0]
  };

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_IDLE;
      last_block_col_q <= 3'd0;
      last_block_row_q <= 3'd0;
      block_id_q <= 6'd0;
      decide_index_q <= 6'd0;
      block_sample_q <= 8'd0;
      current_hash_q <= HASH_OFFSET;
      coded_mask_q <= 64'd0;
      done <= 1'b0;
      any_copy <= 1'b0;
      copy_mask <= 64'd0;
      above_copy_mask <= 64'd0;
      drl_idx_table <= 128'd0;
    end else if (start) begin
      state_q <= ST_READ;
      last_block_col_q <= (visible_width == 16'd64) ? 3'd7 : (visible_width[5:3] - 3'd1);
      last_block_row_q <= (visible_height == 16'd64) ? 3'd7 : (visible_height[5:3] - 3'd1);
      block_id_q <= 6'd0;
      decide_index_q <= 6'd0;
      block_sample_q <= 8'd0;
      current_hash_q <= HASH_OFFSET;
      coded_mask_q <= 64'd0;
      done <= 1'b0;
      any_copy <= 1'b0;
      copy_mask <= 64'd0;
      above_copy_mask <= 64'd0;
      drl_idx_table <= 128'd0;
    end else begin
      case (state_q)
        ST_READ: begin
          if (packet_fire) begin
            if (packet_block_complete_w) begin
              // AV2 v1.0.0 IntraBC syntax carries a block vector. This stage
              // stores 32-bit hashes for the whole 64x64 tile. A second pass
              // below walks the fixed 8x8 partition-tree order to mirror the
              // decoder BVP availability before selecting any DRL index.
              hash_table_q[block_id_q] <= hash_after_packet_w;
              current_hash_q <= HASH_OFFSET;
              block_sample_q <= 8'd0;
              if (packet_last) begin
                decide_index_q <= 6'd0;
                state_q <= ST_DECIDE;
              end else if (block_id_q[5:3] == last_block_row_q &&
                           block_id_q[2:0] == last_block_col_q) begin
                decide_index_q <= 6'd0;
                state_q <= ST_DECIDE;
              end else if (block_id_q[2:0] == last_block_col_q) begin
                block_id_q <= {block_id_q[5:3] + 3'd1, 3'd0};
              end else begin
                block_id_q <= block_id_q + 6'd1;
              end
            end else begin
              current_hash_q <= hash_after_packet_w;
              block_sample_q <= block_sample_q + {4'd0, packet_count};
            end
          end else if (sample_fire) begin
            if (block_complete_w) begin
              // AV2 v1.0.0 IntraBC syntax carries a block vector. This stage
              // stores 32-bit hashes for the whole 64x64 tile. A second pass
              // below walks the fixed 8x8 partition-tree order to mirror the
              // decoder BVP availability before selecting any DRL index.
              hash_table_q[block_id_q] <= hash_after_sample_w;
              current_hash_q <= HASH_OFFSET;
              block_sample_q <= 8'd0;
              if (sample_last) begin
                decide_index_q <= 6'd0;
                state_q <= ST_DECIDE;
              end else if (block_id_q[5:3] == last_block_row_q &&
                           block_id_q[2:0] == last_block_col_q) begin
                decide_index_q <= 6'd0;
                state_q <= ST_DECIDE;
              end else if (block_id_q[2:0] == last_block_col_q) begin
                block_id_q <= {block_id_q[5:3] + 3'd1, 3'd0};
              end else begin
                block_id_q <= block_id_q + 6'd1;
              end
            end else begin
              current_hash_q <= hash_after_sample_w;
              block_sample_q <= block_sample_q + 8'd1;
            end
          end
        end
        ST_DECIDE: begin
          if (decide_block_visible_w) begin
            coded_mask_q[decide_block_id_w] <= 1'b1;
            copy_mask[decide_block_id_w] <= copy_match_w;
            above_copy_mask[decide_block_id_w] <= candidate_above_w && copy_match_w;
            drl_idx_table[decide_drl_bit_index_w +: 2] <=
              copy_match_w ? candidate_drl_idx_w : 2'd0;
            any_copy <= any_copy | copy_match_w;
          end
          if (decide_index_q == 6'd63) begin
            done <= 1'b1;
            state_q <= ST_DONE;
          end else begin
            decide_index_q <= decide_index_q + 6'd1;
          end
        end
        ST_DONE: begin
        end
        default: begin
          state_q <= ST_IDLE;
        end
      endcase
    end
  end

endmodule
