`timescale 1ns/1ps

module ff_av2_local_hash_matcher_444 #(
  parameter int SAMPLE_BITS = 8,
  parameter int SUPPORT_EXACT_HASH_IBC_444 = 1
) (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       start,
  input  logic       sample_fire,
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,
  input  logic [SAMPLE_BITS - 1:0] sample,
  input  logic       sample_last,
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
  logic direct_left_valid_w;
  logic direct_above_valid_w;
  logic direct_left_vec_above_w;
  logic direct_above_vec_above_w;
  logic non_direct_spatial_copy_w;
  logic above_drl_valid_w;
  logic left_drl_valid_w;
  logic block_complete_w;
  logic above_match_w;
  logic left_match_w;
  logic copy_match_w;
  logic candidate_above_w;
  logic enabled_w;

  assign enabled_w = (SUPPORT_EXACT_HASH_IBC_444 != 0) && (SAMPLE_BITS == 8);
  assign hash_after_xor_w = current_hash_q ^ {24'd0, sample[7:0]};
  assign hash_after_mix0_w = hash_after_xor_w ^ (hash_after_xor_w << 13);
  assign hash_after_mix1_w = hash_after_mix0_w ^ (hash_after_mix0_w >> 17);
  assign hash_after_sample_w = hash_after_mix1_w ^ (hash_after_mix1_w << 5);
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
  assign direct_left_vec_above_w = above_copy_mask[left_block_id_w];
  assign direct_above_vec_above_w = above_copy_mask[above_block_id_w];
  assign non_direct_spatial_copy_w =
    (bottom_left_in_tile_w && coded_mask_q[bottom_left_block_id_w] &&
     copy_mask[bottom_left_block_id_w]) ||
    (top_right_in_tile_w && coded_mask_q[top_right_block_id_w] &&
     copy_mask[top_right_block_id_w]) ||
    (top_left_in_tile_w && coded_mask_q[top_left_block_id_w] &&
     copy_mask[top_left_block_id_w]) ||
    (second_left_in_tile_w && coded_mask_q[second_left_block_id_w] &&
     copy_mask[second_left_block_id_w]);
  assign direct0_vec_w =
    direct_left_valid_w ? {1'b0, direct_left_vec_above_w} :
    (direct_above_valid_w ? {1'b0, direct_above_vec_above_w} : 2'd0);
  assign direct1_vec_w =
    (direct_left_valid_w && direct_above_valid_w &&
     (direct_left_vec_above_w != direct_above_vec_above_w)) ?
      {1'b0, direct_above_vec_above_w} : 2'd0;
  assign direct_count_w =
    direct_left_valid_w ?
      ((direct_above_valid_w && (direct_left_vec_above_w != direct_above_vec_above_w)) ? 2'd2 : 2'd1) :
      (direct_above_valid_w ? 2'd1 : 2'd0);
  assign above_drl_valid_w =
    (direct_count_w != 2'd0 && direct0_vec_w == 2'd1) ||
    (direct_count_w == 2'd2 && direct1_vec_w == 2'd1) ||
    (!non_direct_spatial_copy_w && (direct_count_w <= 2'd1));
  assign above_drl_idx_w =
    (direct_count_w != 2'd0 && direct0_vec_w == 2'd1) ? 2'd0 :
    ((direct_count_w == 2'd2 && direct1_vec_w == 2'd1) ? 2'd1 :
      (direct_count_w + 2'd2));
  assign left_drl_valid_w =
    (direct_count_w != 2'd0 && direct0_vec_w == 2'd0) ||
    (direct_count_w == 2'd2 && direct1_vec_w == 2'd0) ||
    (!non_direct_spatial_copy_w && (direct_count_w == 2'd0));
  assign left_drl_idx_w =
    (direct_count_w != 2'd0 && direct0_vec_w == 2'd0) ? 2'd0 :
    ((direct_count_w == 2'd2 && direct1_vec_w == 2'd0) ? 2'd1 : 2'd3);
  assign block_complete_w = sample_fire && (block_sample_q == 8'd191);
  assign above_match_w =
    // Keep this MVP exact-match IBC selector left-copy-only until the RTL has
    // a complete AVM is_mi_coded availability mirror for vertical local BVs.
    1'b0;
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
    case (decide_index_q)
      6'd0: decide_block_id_w = 6'd0;
      6'd1: decide_block_id_w = 6'd1;
      6'd2: decide_block_id_w = 6'd8;
      6'd3: decide_block_id_w = 6'd9;
      6'd4: decide_block_id_w = 6'd2;
      6'd5: decide_block_id_w = 6'd3;
      6'd6: decide_block_id_w = 6'd10;
      6'd7: decide_block_id_w = 6'd11;
      6'd8: decide_block_id_w = 6'd16;
      6'd9: decide_block_id_w = 6'd17;
      6'd10: decide_block_id_w = 6'd24;
      6'd11: decide_block_id_w = 6'd25;
      6'd12: decide_block_id_w = 6'd18;
      6'd13: decide_block_id_w = 6'd19;
      6'd14: decide_block_id_w = 6'd26;
      6'd15: decide_block_id_w = 6'd27;
      6'd16: decide_block_id_w = 6'd4;
      6'd17: decide_block_id_w = 6'd5;
      6'd18: decide_block_id_w = 6'd12;
      6'd19: decide_block_id_w = 6'd13;
      6'd20: decide_block_id_w = 6'd6;
      6'd21: decide_block_id_w = 6'd7;
      6'd22: decide_block_id_w = 6'd14;
      6'd23: decide_block_id_w = 6'd15;
      6'd24: decide_block_id_w = 6'd20;
      6'd25: decide_block_id_w = 6'd21;
      6'd26: decide_block_id_w = 6'd28;
      6'd27: decide_block_id_w = 6'd29;
      6'd28: decide_block_id_w = 6'd22;
      6'd29: decide_block_id_w = 6'd23;
      6'd30: decide_block_id_w = 6'd30;
      6'd31: decide_block_id_w = 6'd31;
      6'd32: decide_block_id_w = 6'd32;
      6'd33: decide_block_id_w = 6'd33;
      6'd34: decide_block_id_w = 6'd40;
      6'd35: decide_block_id_w = 6'd41;
      6'd36: decide_block_id_w = 6'd34;
      6'd37: decide_block_id_w = 6'd35;
      6'd38: decide_block_id_w = 6'd42;
      6'd39: decide_block_id_w = 6'd43;
      6'd40: decide_block_id_w = 6'd48;
      6'd41: decide_block_id_w = 6'd49;
      6'd42: decide_block_id_w = 6'd56;
      6'd43: decide_block_id_w = 6'd57;
      6'd44: decide_block_id_w = 6'd50;
      6'd45: decide_block_id_w = 6'd51;
      6'd46: decide_block_id_w = 6'd58;
      6'd47: decide_block_id_w = 6'd59;
      6'd48: decide_block_id_w = 6'd36;
      6'd49: decide_block_id_w = 6'd37;
      6'd50: decide_block_id_w = 6'd44;
      6'd51: decide_block_id_w = 6'd45;
      6'd52: decide_block_id_w = 6'd38;
      6'd53: decide_block_id_w = 6'd39;
      6'd54: decide_block_id_w = 6'd46;
      6'd55: decide_block_id_w = 6'd47;
      6'd56: decide_block_id_w = 6'd52;
      6'd57: decide_block_id_w = 6'd53;
      6'd58: decide_block_id_w = 6'd60;
      6'd59: decide_block_id_w = 6'd61;
      6'd60: decide_block_id_w = 6'd54;
      6'd61: decide_block_id_w = 6'd55;
      6'd62: decide_block_id_w = 6'd62;
      default: decide_block_id_w = 6'd63;
    endcase
  end

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
          if (sample_fire) begin
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
