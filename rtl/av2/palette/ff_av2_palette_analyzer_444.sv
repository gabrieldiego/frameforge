`timescale 1ns/1ps

module ff_av2_palette_analyzer_444 #(
  parameter int SAMPLE_BITS = 8,
  parameter int SUPPORT_PALETTE_444 = 1
) (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       start,
  input  logic       sample_fire,
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,
  input  logic [SAMPLE_BITS - 1:0] sample,
  input  logic       sample_last,
  output logic       sample_ready,
  input  logic [4:0] query_block_row_mi,
  input  logic [4:0] query_block_col_mi,
  input  logic [5:0] query_row,
  input  logic [5:0] query_col,
  output logic       done,
  output logic       unsupported,
  output logic       black_mode,
  output logic       luma_palette_mode,
  output logic [3:0] palette_size,
  output logic [4:0] palette_cache_size,
  output logic [63:0] palette_colors,
  output logic [2:0] query_index,
  output logic [2:0] query_left_index,
  output logic [2:0] query_top_index,
  output logic [2:0] query_top_left_index,
  output logic [1:0] query_identity_row_flag
);

  localparam logic [3:0] ST_IDLE = 4'd0;
  localparam logic [3:0] ST_READ = 4'd1;
  localparam logic [3:0] ST_BLOCK_INIT = 4'd2;
  localparam logic [3:0] ST_COLLECT = 4'd3;
  localparam logic [3:0] ST_PAD = 4'd4;
  localparam logic [3:0] ST_SORT = 4'd5;
  localparam logic [3:0] ST_STORE_COLORS = 4'd6;
  localparam logic [3:0] ST_MAP = 4'd7;
  localparam logic [3:0] ST_NEXT_BLOCK = 4'd8;
  localparam logic [3:0] ST_DRAIN_CHROMA = 4'd9;
  localparam logic [3:0] ST_DONE = 4'd10;

  logic [3:0] state_q;
  logic [31:0] area_q;
  logic [31:0] frame_samples_q;
  logic [31:0] sample_index_q;
  logic [2:0] last_block_col_q;
  logic [2:0] last_block_row_q;
  logic [5:0] block_id_q;
  logic [5:0] block_sample_q;
  logic [7:0] candidate_q;
  logic [3:0] collected_count_q;
  logic [3:0] collected_next_count_w;
  logic [3:0] target_palette_size_q;
  logic [3:0] sort_pass_q;
  logic [2:0] sort_index_q;
  logic black_ok_q;
  logic palette_supported_q;

  logic [7:0] block_luma_sample_q [0:63];
  logic [191:0] block_palette_index_q [0:63];
  logic [7:0] palette_color_q [0:7];
  logic [7:0] block_palette_color_q [0:63][0:7];
  logic [3:0] block_palette_size_q [0:63];
  logic [7:0] row_same_left_q [0:63];
  logic [7:0] row_same_above_q [0:63];

  logic known_sample_w;
  logic candidate_known_w;
  logic collect_add_w;
  logic [2:0] nearest_index_w;
  logic [7:0] nearest_delta_w;
  logic [7:0] nearest_color_w;
  logic [7:0] collect_sample_w;
  logic [7:0] map_sample_w;
  logic [7:0] map_abs_delta_w;
  logic [7:0] sample_u8_w;
  logic final_sample_w;
  logic black_sample_ok_w;
  logic black_next_w;
  logic [5:0] query_block_id_w;
  logic [5:0] query_above_block_id_w;
  logic [5:0] query_left_block_id_w;
  logic [5:0] query_local_index_w;
  logic [5:0] query_left_local_index_w;
  logic [5:0] query_top_local_index_w;
  logic [5:0] query_top_left_local_index_w;
  logic [7:0] query_bit_offset_w;
  logic [7:0] query_left_bit_offset_w;
  logic [7:0] query_top_bit_offset_w;
  logic [7:0] query_top_left_bit_offset_w;
  logic [7:0] block_sample_bit_offset_w;
  logic [7:0] block_sample_left_bit_offset_w;
  logic [7:0] block_sample_top_bit_offset_w;
  integer color_index_q;
  integer pack_index_q;
  integer block_index_q;

  assign sample_u8_w = sample[7:0];
  assign final_sample_w = sample_fire && (sample_index_q == (frame_samples_q - 32'd1));
  assign black_sample_ok_w = (sample == {SAMPLE_BITS{1'b0}});
  assign black_next_w = black_ok_q && black_sample_ok_w;
  assign sample_ready = (state_q == ST_READ) || (state_q == ST_DRAIN_CHROMA);

  // Palette analysis is block-local. The top-level input contract presents the
  // luma plane in 8x8 block order, followed by the chroma planes. This keeps
  // the analyzer at one 8x8 luma buffer plus per-block palette maps instead of
  // a full 64x64 random-access luma buffer.
  // AV2 8x8 palette leaves are addressed by 3-bit block row/column indices
  // inside the 64x64 superblock. The MI origin is in 4x4 units, so [3:1]
  // converts it to 8x8 block coordinates without truncating high row bits.
  assign query_block_id_w = {query_block_row_mi[3:1], query_block_col_mi[3:1]};
  assign query_local_index_w = {query_row[2:0], query_col[2:0]};
  assign query_left_local_index_w =
    (query_col[2:0] == 3'd0) ? query_local_index_w : (query_local_index_w - 6'd1);
  assign query_top_local_index_w =
    (query_row[2:0] == 3'd0) ? query_local_index_w : (query_local_index_w - 6'd8);
  assign query_top_left_local_index_w =
    (query_row[2:0] == 3'd0 || query_col[2:0] == 3'd0) ?
      query_local_index_w : (query_local_index_w - 6'd9);
  assign query_bit_offset_w = {2'd0, query_local_index_w} * 8'd3;
  assign query_left_bit_offset_w = {2'd0, query_left_local_index_w} * 8'd3;
  assign query_top_bit_offset_w = {2'd0, query_top_local_index_w} * 8'd3;
  assign query_top_left_bit_offset_w = {2'd0, query_top_left_local_index_w} * 8'd3;
  assign block_sample_bit_offset_w = {2'd0, block_sample_q} * 8'd3;
  assign block_sample_left_bit_offset_w = {2'd0, block_sample_q - 6'd1} * 8'd3;
  assign block_sample_top_bit_offset_w = {2'd0, block_sample_q - 6'd8} * 8'd3;
  assign query_above_block_id_w = query_block_id_w - 6'd8;
  assign query_left_block_id_w = query_block_id_w - 6'd1;

  always @* begin
    known_sample_w = 1'b0;
    candidate_known_w = 1'b0;
    collect_sample_w = block_luma_sample_q[block_sample_q];
    for (color_index_q = 0; color_index_q < 8; color_index_q = color_index_q + 1) begin
      if (color_index_q < collected_count_q && palette_color_q[color_index_q] == collect_sample_w) begin
        known_sample_w = 1'b1;
      end
      if (color_index_q < collected_count_q && palette_color_q[color_index_q] == candidate_q) begin
        candidate_known_w = 1'b1;
      end
    end
    collect_add_w = !known_sample_w && (collected_count_q < 4'd8);
    collected_next_count_w = collected_count_q + {3'd0, collect_add_w};
  end

  always @* begin
    map_sample_w = block_luma_sample_q[block_sample_q];
    nearest_index_w = 3'd0;
    nearest_delta_w = 8'hff;
    nearest_color_w = 8'd0;
    map_abs_delta_w = 8'd0;
    for (color_index_q = 0; color_index_q < 8; color_index_q = color_index_q + 1) begin
      if (color_index_q < target_palette_size_q) begin
        nearest_color_w = palette_color_q[color_index_q];
        if (map_sample_w >= nearest_color_w) begin
          map_abs_delta_w = map_sample_w - nearest_color_w;
        end else begin
          map_abs_delta_w = nearest_color_w - map_sample_w;
        end
        if (map_abs_delta_w < nearest_delta_w) begin
          nearest_delta_w = map_abs_delta_w;
          nearest_index_w = color_index_q[2:0];
        end
      end
    end
  end

  always @* begin
    for (pack_index_q = 0; pack_index_q < 8; pack_index_q = pack_index_q + 1) begin
      palette_colors[pack_index_q * 8 +: 8] =
        block_palette_color_q[query_block_id_w][pack_index_q];
      end
      palette_size = block_palette_size_q[query_block_id_w];
      palette_cache_size = 5'd0;
    if (query_block_id_w[5:3] != 3'd0) begin
      palette_cache_size = palette_cache_size + {1'd0, block_palette_size_q[query_above_block_id_w]};
    end
    if (query_block_id_w[2:0] != 3'd0) begin
        palette_cache_size = palette_cache_size + {1'd0, block_palette_size_q[query_left_block_id_w]};
      end
      query_index = block_palette_index_q[query_block_id_w][query_bit_offset_w +: 3];
      query_left_index = block_palette_index_q[query_block_id_w][query_left_bit_offset_w +: 3];
      query_top_index = block_palette_index_q[query_block_id_w][query_top_bit_offset_w +: 3];
      query_top_left_index = block_palette_index_q[query_block_id_w][query_top_left_bit_offset_w +: 3];
      if (query_row[2:0] != 3'd0 && row_same_above_q[query_block_id_w][query_row[2:0]]) begin
        query_identity_row_flag = 2'd2;
      end else if (row_same_left_q[query_block_id_w][query_row[2:0]]) begin
        query_identity_row_flag = 2'd1;
      end else begin
        query_identity_row_flag = 2'd0;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_IDLE;
      area_q <= 32'd0;
      frame_samples_q <= 32'd0;
      sample_index_q <= 32'd0;
      last_block_col_q <= 3'd0;
      last_block_row_q <= 3'd0;
      block_id_q <= 6'd0;
      block_sample_q <= 6'd0;
      candidate_q <= 8'd0;
      collected_count_q <= 4'd0;
      target_palette_size_q <= 4'd2;
      sort_pass_q <= 4'd0;
      sort_index_q <= 3'd0;
      black_ok_q <= 1'b0;
      palette_supported_q <= 1'b0;
      done <= 1'b0;
      unsupported <= 1'b0;
      black_mode <= 1'b0;
      luma_palette_mode <= 1'b0;
      for (block_index_q = 0; block_index_q < 64; block_index_q = block_index_q + 1) begin
        block_luma_sample_q[block_index_q] <= 8'd0;
      end
      for (color_index_q = 0; color_index_q < 8; color_index_q = color_index_q + 1) begin
        palette_color_q[color_index_q] <= 8'd0;
      end
      for (block_index_q = 0; block_index_q < 64; block_index_q = block_index_q + 1) begin
        block_palette_index_q[block_index_q] <= 192'd0;
        block_palette_size_q[block_index_q] <= 4'd2;
        row_same_left_q[block_index_q] <= 8'd0;
        row_same_above_q[block_index_q] <= 8'd0;
        for (color_index_q = 0; color_index_q < 8; color_index_q = color_index_q + 1) begin
          block_palette_color_q[block_index_q][color_index_q] <= 8'd0;
        end
      end
    end else if (start) begin
      state_q <= ST_READ;
      area_q <= {16'd0, visible_width} * {16'd0, visible_height};
      frame_samples_q <= ({16'd0, visible_width} * {16'd0, visible_height}) * 32'd3;
      sample_index_q <= 32'd0;
      last_block_col_q <= (visible_width == 16'd64) ? 3'd7 : (visible_width[5:3] - 3'd1);
      last_block_row_q <= (visible_height == 16'd64) ? 3'd7 : (visible_height[5:3] - 3'd1);
      block_id_q <= 6'd0;
      block_sample_q <= 6'd0;
      candidate_q <= 8'd0;
      collected_count_q <= 4'd0;
      target_palette_size_q <= 4'd2;
      sort_pass_q <= 4'd0;
      sort_index_q <= 3'd0;
      black_ok_q <= 1'b1;
      palette_supported_q <=
        (SUPPORT_PALETTE_444 != 0) &&
        (SAMPLE_BITS == 8) &&
        (visible_width != 16'd0) &&
        (visible_height != 16'd0) &&
        (visible_width <= 16'd64) &&
        (visible_height <= 16'd64) &&
        (visible_width[2:0] == 3'd0) &&
        (visible_height[2:0] == 3'd0);
      done <= 1'b0;
      unsupported <= 1'b0;
      black_mode <= 1'b0;
      luma_palette_mode <= 1'b0;
    end else begin
      case (state_q)
        ST_IDLE: begin
        end
        ST_READ: begin
          if (sample_fire) begin
            black_ok_q <= black_next_w;
            sample_index_q <= sample_index_q + 32'd1;
            block_luma_sample_q[block_sample_q] <= sample_u8_w;
            if (sample_last) begin
              unsupported <= 1'b1;
              done <= 1'b1;
              state_q <= ST_DONE;
            end else if (block_sample_q == 6'd63) begin
              block_sample_q <= 6'd0;
              state_q <= ST_BLOCK_INIT;
            end else begin
              block_sample_q <= block_sample_q + 6'd1;
            end
          end
        end
        ST_BLOCK_INIT: begin
          block_sample_q <= 6'd0;
          candidate_q <= 8'd0;
          collected_count_q <= 4'd0;
          target_palette_size_q <= 4'd2;
          sort_pass_q <= 4'd0;
          sort_index_q <= 3'd0;
          for (color_index_q = 0; color_index_q < 8; color_index_q = color_index_q + 1) begin
            palette_color_q[color_index_q] <= 8'd0;
          end
          state_q <= ST_COLLECT;
        end
        ST_COLLECT: begin
          if (collect_add_w) begin
            palette_color_q[collected_count_q] <= collect_sample_w;
            collected_count_q <= collected_next_count_w;
          end
          if (block_sample_q == 6'd63) begin
            if (collected_next_count_w <= 4'd2) begin
              target_palette_size_q <= 4'd2;
            end else if (collected_next_count_w <= 4'd4) begin
              target_palette_size_q <= 4'd4;
            end else begin
              target_palette_size_q <= 4'd8;
            end
            candidate_q <= 8'd0;
            state_q <= ST_PAD;
          end else begin
            block_sample_q <= block_sample_q + 6'd1;
          end
        end
        ST_PAD: begin
          if (collected_count_q < target_palette_size_q) begin
            if (!candidate_known_w) begin
              palette_color_q[collected_count_q] <= candidate_q;
              collected_count_q <= collected_count_q + 4'd1;
            end
            candidate_q <= candidate_q + 8'd1;
          end else begin
            sort_pass_q <= 4'd0;
            sort_index_q <= 3'd0;
            state_q <= ST_SORT;
          end
        end
        ST_SORT: begin
          if (sort_pass_q < target_palette_size_q) begin
            if ({1'b0, sort_index_q} + 4'd1 < target_palette_size_q - sort_pass_q) begin
              if (palette_color_q[sort_index_q] > palette_color_q[sort_index_q + 3'd1]) begin
                palette_color_q[sort_index_q] <= palette_color_q[sort_index_q + 3'd1];
                palette_color_q[sort_index_q + 3'd1] <= palette_color_q[sort_index_q];
              end
              sort_index_q <= sort_index_q + 3'd1;
            end else begin
              sort_index_q <= 3'd0;
              sort_pass_q <= sort_pass_q + 4'd1;
            end
          end else begin
            state_q <= ST_STORE_COLORS;
          end
        end
        ST_STORE_COLORS: begin
          block_palette_size_q[block_id_q] <= target_palette_size_q;
          for (color_index_q = 0; color_index_q < 8; color_index_q = color_index_q + 1) begin
            block_palette_color_q[block_id_q][color_index_q] <= palette_color_q[color_index_q];
          end
          block_sample_q <= 6'd0;
          state_q <= ST_MAP;
        end
        ST_MAP: begin
          block_palette_index_q[block_id_q][block_sample_bit_offset_w +: 3] <= nearest_index_w;
          if (block_sample_q[2:0] == 3'd0) begin
            row_same_left_q[block_id_q][block_sample_q[5:3]] <= 1'b1;
            row_same_above_q[block_id_q][block_sample_q[5:3]] <= (block_sample_q[5:3] != 3'd0);
          end else if (nearest_index_w != block_palette_index_q[block_id_q][block_sample_left_bit_offset_w +: 3]) begin
            row_same_left_q[block_id_q][block_sample_q[5:3]] <= 1'b0;
          end
          if (block_sample_q[5:3] != 3'd0 && nearest_index_w != block_palette_index_q[block_id_q][block_sample_top_bit_offset_w +: 3]) begin
            row_same_above_q[block_id_q][block_sample_q[5:3]] <= 1'b0;
          end
          if (block_sample_q == 6'd63) begin
            state_q <= ST_NEXT_BLOCK;
          end else begin
            block_sample_q <= block_sample_q + 6'd1;
          end
        end
        ST_NEXT_BLOCK: begin
          if (block_id_q[5:3] == last_block_row_q && block_id_q[2:0] == last_block_col_q) begin
            state_q <= ST_DRAIN_CHROMA;
          end else if (block_id_q[2:0] == last_block_col_q) begin
            block_id_q <= {block_id_q[5:3] + 3'd1, 3'd0};
            block_sample_q <= 6'd0;
            state_q <= ST_READ;
          end else begin
            block_id_q <= block_id_q + 6'd1;
            block_sample_q <= 6'd0;
            state_q <= ST_READ;
          end
        end
        ST_DRAIN_CHROMA: begin
          if (sample_fire) begin
            black_ok_q <= black_next_w;
            sample_index_q <= sample_index_q + 32'd1;
            if (final_sample_w) begin
              if (!sample_last) begin
                unsupported <= 1'b1;
              end else if (black_next_w || !palette_supported_q) begin
                black_mode <= 1'b1;
                luma_palette_mode <= 1'b0;
              end else begin
                black_mode <= 1'b0;
                luma_palette_mode <= 1'b1;
              end
              done <= 1'b1;
              state_q <= ST_DONE;
            end else if (sample_last) begin
              unsupported <= 1'b1;
              done <= 1'b1;
              state_q <= ST_DONE;
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
