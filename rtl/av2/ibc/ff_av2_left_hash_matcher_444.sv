`timescale 1ns/1ps

module ff_av2_left_hash_matcher_444 #(
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
  output logic       any_left_copy,
  output logic [63:0] left_copy_mask
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
  logic hash_valid_q [0:63];

  logic [31:0] hash_after_xor_w;
  logic [31:0] hash_after_mix0_w;
  logic [31:0] hash_after_mix1_w;
  logic [31:0] hash_after_sample_w;
  logic [5:0] left_block_id_w;
  logic left_in_tile_w;
  logic terminal_visible_leaf_w;
  logic block_complete_w;
  logic left_match_w;
  logic enabled_w;

  integer clear_i;

  assign enabled_w = (SUPPORT_EXACT_HASH_IBC_444 != 0) && (SAMPLE_BITS == 8);
  assign hash_after_xor_w = current_hash_q ^ {24'd0, sample[7:0]};
  assign hash_after_mix0_w = hash_after_xor_w ^ (hash_after_xor_w << 13);
  assign hash_after_mix1_w = hash_after_mix0_w ^ (hash_after_mix0_w >> 17);
  assign hash_after_sample_w = hash_after_mix1_w ^ (hash_after_mix1_w << 5);
  assign left_block_id_w = block_id_q - 6'd1;
  assign left_in_tile_w = block_id_q[2:0] != 3'd0;
  assign terminal_visible_leaf_w =
    (block_id_q[5:3] == last_block_row_q) &&
    (block_id_q[2:0] == last_block_col_q);
  assign block_complete_w = sample_fire && (block_sample_q == 8'd191);
  assign left_match_w =
    enabled_w &&
    left_in_tile_w &&
    terminal_visible_leaf_w &&
    hash_valid_q[left_block_id_w] &&
    !left_copy_mask[left_block_id_w] &&
    (hash_table_q[left_block_id_w] == hash_after_sample_w);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_IDLE;
      last_block_col_q <= 3'd0;
      last_block_row_q <= 3'd0;
      block_id_q <= 6'd0;
      block_sample_q <= 8'd0;
      current_hash_q <= HASH_OFFSET;
      done <= 1'b0;
      any_left_copy <= 1'b0;
      left_copy_mask <= 64'd0;
      for (clear_i = 0; clear_i < 64; clear_i = clear_i + 1) begin
        hash_table_q[clear_i] <= 32'd0;
        hash_valid_q[clear_i] <= 1'b0;
      end
    end else if (start) begin
      state_q <= ST_READ;
      last_block_col_q <= (visible_width == 16'd64) ? 3'd7 : (visible_width[5:3] - 3'd1);
      last_block_row_q <= (visible_height == 16'd64) ? 3'd7 : (visible_height[5:3] - 3'd1);
      block_id_q <= 6'd0;
      block_sample_q <= 8'd0;
      current_hash_q <= HASH_OFFSET;
      done <= 1'b0;
      any_left_copy <= 1'b0;
      left_copy_mask <= 64'd0;
      for (clear_i = 0; clear_i < 64; clear_i = clear_i + 1) begin
        hash_table_q[clear_i] <= 32'd0;
        hash_valid_q[clear_i] <= 1'b0;
      end
    end else begin
      case (state_q)
        ST_READ: begin
          if (sample_fire) begin
            if (block_complete_w) begin
              // AV2 v1.0.0 IntraBC syntax carries a block vector; this first
              // hardware search only keeps a block hash and enables the
              // immediate-left 8x8 vector when the whole YUV444 block matches.
              // Keep this first fixed-DRL implementation terminal-leaf only:
              // AV2/AVM derives BVs and later contexts from neighboring
              // MB_MODE_INFO, so later leaves must not consume incomplete
              // post-IBC state until the full context model is implemented.
              hash_table_q[block_id_q] <= hash_after_sample_w;
              hash_valid_q[block_id_q] <= enabled_w;
              left_copy_mask[block_id_q] <= left_match_w;
              any_left_copy <= any_left_copy | left_match_w;
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
