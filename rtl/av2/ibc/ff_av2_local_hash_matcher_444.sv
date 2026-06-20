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
  output logic [63:0] above_copy_mask
);

  localparam logic [1:0] ST_IDLE = 2'd0;
  localparam logic [1:0] ST_READ = 2'd1;
  localparam logic [1:0] ST_DONE = 2'd2;
  localparam logic [31:0] HASH_OFFSET = 32'h811c_9dc5;

  logic [1:0] state_q;
  logic [2:0] last_block_col_q;
  logic [2:0] last_block_row_q;
  logic [5:0] block_id_q;
  logic [7:0] block_sample_q;
  logic [31:0] current_hash_q;
  logic [31:0] hash_table_q [0:63];

  logic [31:0] hash_after_xor_w;
  logic [31:0] hash_after_mix0_w;
  logic [31:0] hash_after_mix1_w;
  logic [31:0] hash_after_sample_w;
  logic [5:0] above_block_id_w;
  logic [5:0] left_block_id_w;
  logic above_in_tile_w;
  logic left_in_tile_w;
  logic terminal_visible_leaf_w;
  logic fixed_drl_candidate_supported_w;
  logic block_complete_w;
  logic above_match_w;
  logic left_match_w;
  logic copy_match_w;
  logic enabled_w;

  assign enabled_w = (SUPPORT_EXACT_HASH_IBC_444 != 0) && (SAMPLE_BITS == 8);
  assign hash_after_xor_w = current_hash_q ^ {24'd0, sample[7:0]};
  assign hash_after_mix0_w = hash_after_xor_w ^ (hash_after_xor_w << 13);
  assign hash_after_mix1_w = hash_after_mix0_w ^ (hash_after_mix0_w >> 17);
  assign hash_after_sample_w = hash_after_mix1_w ^ (hash_after_mix1_w << 5);
  assign above_block_id_w = block_id_q - 6'd8;
  assign left_block_id_w = block_id_q - 6'd1;
  assign above_in_tile_w = block_id_q[5:3] != 3'd0;
  assign left_in_tile_w = block_id_q[2:0] != 3'd0;
  assign terminal_visible_leaf_w =
    (block_id_q[5:3] == last_block_row_q) &&
    (block_id_q[2:0] == last_block_col_q);
  assign fixed_drl_candidate_supported_w =
    terminal_visible_leaf_w && (block_id_q[5:3] != 3'd7);
  assign block_complete_w = sample_fire && (block_sample_q == 8'd191);
  assign above_match_w =
    enabled_w &&
    above_in_tile_w &&
    fixed_drl_candidate_supported_w &&
    !copy_mask[above_block_id_w] &&
    (hash_table_q[above_block_id_w] == hash_after_sample_w);
  assign left_match_w =
    enabled_w &&
    left_in_tile_w &&
    fixed_drl_candidate_supported_w &&
    !copy_mask[left_block_id_w] &&
    (hash_table_q[left_block_id_w] == hash_after_sample_w);
  assign copy_match_w = above_match_w || left_match_w;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_IDLE;
      last_block_col_q <= 3'd0;
      last_block_row_q <= 3'd0;
      block_id_q <= 6'd0;
      block_sample_q <= 8'd0;
      current_hash_q <= HASH_OFFSET;
      done <= 1'b0;
      any_copy <= 1'b0;
      copy_mask <= 64'd0;
      above_copy_mask <= 64'd0;
    end else if (start) begin
      state_q <= ST_READ;
      last_block_col_q <= (visible_width == 16'd64) ? 3'd7 : (visible_width[5:3] - 3'd1);
      last_block_row_q <= (visible_height == 16'd64) ? 3'd7 : (visible_height[5:3] - 3'd1);
      block_id_q <= 6'd0;
      block_sample_q <= 8'd0;
      current_hash_q <= HASH_OFFSET;
      done <= 1'b0;
      any_copy <= 1'b0;
      copy_mask <= 64'd0;
      above_copy_mask <= 64'd0;
    end else begin
      case (state_q)
        ST_READ: begin
          if (sample_fire) begin
            if (block_complete_w) begin
              // AV2 v1.0.0 IntraBC syntax carries a block vector. This
              // hardware-oriented search stores only local 8x8 hashes and
              // selects AVM's default reference-BV entries: DRL 2 for the
              // above block, DRL 3 for the left block. Keep this fixed-DRL
              // subset terminal-leaf only and off the full-height bottom row:
              // non-terminal copies shift the neighboring BVP stack for later
              // leaves until the full candidate stack is implemented. The
              // raster 8x8 tile scan writes every above/left hash before it is
              // read, so no separate valid-bit bank is needed.
              hash_table_q[block_id_q] <= hash_after_sample_w;
              copy_mask[block_id_q] <= copy_match_w;
              above_copy_mask[block_id_q] <= above_match_w;
              any_copy <= any_copy | copy_match_w;
              current_hash_q <= HASH_OFFSET;
              block_sample_q <= 8'd0;
              if (sample_last) begin
                done <= 1'b1;
                state_q <= ST_DONE;
              end else if (block_id_q[5:3] == last_block_row_q &&
                           block_id_q[2:0] == last_block_col_q) begin
                done <= 1'b1;
                state_q <= ST_DONE;
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
        ST_DONE: begin
        end
        default: begin
          state_q <= ST_IDLE;
        end
      endcase
    end
  end

endmodule
