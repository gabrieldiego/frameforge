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
  input  logic       chroma_fetch_start,
  input  logic       chroma_fetch_plane_v,
  input  logic [4:0] chroma_fetch_txb_row_mi,
  input  logic [4:0] chroma_fetch_txb_col_mi,
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
  output logic [1:0] query_identity_row_flag,
  output logic       chroma_fetch_done,
  output logic [127:0] chroma_fetch_txb_samples,
  output logic [31:0] chroma_fetch_predictor_samples
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
  logic [6:0] block_chroma_sample_q;
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
  logic fetch_active_q;
  logic fetch_start_q;
  logic fetch_plane_v_q;
  logic [4:0] fetch_txb_row_mi_q;
  logic [4:0] fetch_txb_col_mi_q;
  logic [4:0] fetch_step_q;
  logic fetch_read_pending_q;
  logic fetch_read_is_pred_q;
  logic [4:0] fetch_capture_step_q;
  logic [11:0] fetch_read_addr_q;
  logic [11:0] chroma_write_addr_w;
  logic [11:0] chroma_read_addr_w;
  logic chroma_write_u_w;
  logic chroma_write_v_w;
  logic [7:0] chroma_read_u_w;
  logic [7:0] chroma_read_v_w;
  logic [11:0] fetch_txb_read_addr_w;
  logic [11:0] fetch_pred_read_addr_w;
  logic [5:0] fetch_txb_block_id_w;
  logic [5:0] fetch_txb_local_base_w;
  logic [5:0] fetch_txb_local_index_w;
  logic [5:0] fetch_pred_block_id_w;
  logic [5:0] fetch_pred_local_index_w;
  logic [5:0] fetch_pred_x_w;
  logic [5:0] fetch_pred_y_w;
  logic [5:0] fetch_above_pred_y_w;
  integer color_index_q;
  integer pack_index_q;
  integer block_index_q;

  assign sample_u8_w = sample[7:0];
  assign black_sample_ok_w = (sample == {SAMPLE_BITS{1'b0}});
  assign black_next_w = black_ok_q && black_sample_ok_w;
  assign sample_ready = (state_q == ST_READ) || (state_q == ST_DRAIN_CHROMA);

  // Palette analysis is block-local. The top-level input contract presents each
  // 8x8 block as 64 Y samples, 64 U samples, then 64 V samples. AV2 v1.0.0
  // Sections 5.20.8.1 and 5.20.8.4 signal palette syntax only for luma; the
  // chroma samples are still consumed in the same block packet so the external
  // interface matches the VVC 4:4:4 8x8-leaf packing without a frame buffer.
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
  // AV2 v1.0.0 Section 5.20.7 residual syntax scans 4x4 TXBs. The query
  // coordinates are MI units, so bit 0 selects the bottom/right 4x4 quadrant
  // inside the current 8x8 packet: row offset 4*8 samples, column offset 4.
  assign fetch_txb_block_id_w = {fetch_txb_row_mi_q[3:1], fetch_txb_col_mi_q[3:1]};
  assign fetch_txb_local_base_w =
    {fetch_txb_row_mi_q[0], 5'b00000} + {3'd0, fetch_txb_col_mi_q[0], 2'b00};
  assign fetch_txb_local_index_w =
    fetch_txb_local_base_w + {fetch_step_q[3:2], 3'b000} + {4'd0, fetch_step_q[1:0]};
  assign fetch_above_pred_y_w = {fetch_txb_row_mi_q, 2'b00} - 6'd1;
  assign chroma_write_addr_w = {block_id_q, block_chroma_sample_q[5:0]};
  assign chroma_read_addr_w =
    fetch_read_pending_q ? fetch_read_addr_q :
    (fetch_step_q < 5'd16) ? fetch_txb_read_addr_w : fetch_pred_read_addr_w;
  assign chroma_write_u_w =
    (state_q == ST_DRAIN_CHROMA) && sample_fire && !block_chroma_sample_q[6];
  assign chroma_write_v_w =
    (state_q == ST_DRAIN_CHROMA) && sample_fire && block_chroma_sample_q[6];
  assign fetch_txb_read_addr_w = {fetch_txb_block_id_w, fetch_txb_local_index_w};
  assign fetch_pred_read_addr_w = {fetch_pred_block_id_w, fetch_pred_local_index_w};

  ff_av2_chroma_sample_store chroma_sample_store (
    .clk(clk),
    .write_u_en(chroma_write_u_w),
    .write_v_en(chroma_write_v_w),
    .write_addr(chroma_write_addr_w),
    .write_data(sample_u8_w),
    .read_addr(chroma_read_addr_w),
    .read_u_data(chroma_read_u_w),
    .read_v_data(chroma_read_v_w)
  );

  always @* begin
    if (fetch_txb_col_mi_q != 5'd0) begin
      fetch_pred_x_w = {fetch_txb_col_mi_q, 2'b00} - 6'd1;
      fetch_pred_y_w = {fetch_txb_row_mi_q, 2'b00} + {4'd0, fetch_step_q[1:0]};
    end else if (fetch_txb_row_mi_q != 5'd0) begin
      fetch_pred_x_w = 6'd0;
      fetch_pred_y_w = fetch_above_pred_y_w;
    end else begin
      fetch_pred_x_w = 6'd0;
      fetch_pred_y_w = 6'd0;
    end
    fetch_pred_block_id_w = {fetch_pred_y_w[5:3], fetch_pred_x_w[5:3]};
    fetch_pred_local_index_w = {fetch_pred_y_w[2:0], fetch_pred_x_w[2:0]};
  end

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
      block_chroma_sample_q <= 7'd0;
      candidate_q <= 8'd0;
      collected_count_q <= 4'd0;
      target_palette_size_q <= 4'd2;
      sort_pass_q <= 4'd0;
      sort_index_q <= 3'd0;
      black_ok_q <= 1'b0;
      palette_supported_q <= 1'b0;
      fetch_active_q <= 1'b0;
      fetch_start_q <= 1'b0;
      fetch_plane_v_q <= 1'b0;
      fetch_txb_row_mi_q <= 5'd0;
      fetch_txb_col_mi_q <= 5'd0;
      fetch_step_q <= 5'd0;
      fetch_read_pending_q <= 1'b0;
      fetch_read_is_pred_q <= 1'b0;
      fetch_capture_step_q <= 5'd0;
      fetch_read_addr_q <= 12'd0;
      chroma_fetch_done <= 1'b0;
      chroma_fetch_txb_samples <= 128'd0;
      chroma_fetch_predictor_samples <= 32'd0;
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
      block_chroma_sample_q <= 7'd0;
      candidate_q <= 8'd0;
      collected_count_q <= 4'd0;
      target_palette_size_q <= 4'd2;
      sort_pass_q <= 4'd0;
      sort_index_q <= 3'd0;
      black_ok_q <= 1'b1;
      fetch_active_q <= 1'b0;
      fetch_start_q <= 1'b0;
      fetch_step_q <= 5'd0;
      fetch_read_pending_q <= 1'b0;
      chroma_fetch_done <= 1'b0;
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
      fetch_start_q <= chroma_fetch_start;
      if (chroma_fetch_start && !fetch_start_q) begin
        fetch_active_q <= 1'b1;
        fetch_plane_v_q <= chroma_fetch_plane_v;
        fetch_txb_row_mi_q <= chroma_fetch_txb_row_mi;
        fetch_txb_col_mi_q <= chroma_fetch_txb_col_mi;
        fetch_step_q <= 5'd0;
        fetch_read_pending_q <= 1'b0;
        chroma_fetch_done <= 1'b0;
      end else if (fetch_active_q) begin
        if (fetch_read_pending_q) begin
          if (fetch_read_is_pred_q) begin
            chroma_fetch_predictor_samples[(fetch_capture_step_q - 5'd16) * 8 +: 8] <=
              fetch_plane_v_q ? chroma_read_v_w : chroma_read_u_w;
          end else begin
            chroma_fetch_txb_samples[fetch_capture_step_q * 8 +: 8] <=
              fetch_plane_v_q ? chroma_read_v_w : chroma_read_u_w;
          end
          fetch_read_pending_q <= 1'b0;
          if (fetch_capture_step_q == 5'd19) begin
            fetch_active_q <= 1'b0;
            chroma_fetch_done <= 1'b1;
          end else begin
            fetch_step_q <= fetch_capture_step_q + 5'd1;
          end
        end else if (fetch_step_q < 5'd16) begin
          fetch_read_addr_q <= fetch_txb_read_addr_w;
          fetch_capture_step_q <= fetch_step_q;
          fetch_read_is_pred_q <= 1'b0;
          fetch_read_pending_q <= 1'b1;
        end else if (fetch_step_q < 5'd20) begin
          if (fetch_txb_col_mi_q == 5'd0 && fetch_txb_row_mi_q == 5'd0) begin
            chroma_fetch_predictor_samples[(fetch_step_q - 5'd16) * 8 +: 8] <= 8'd129;
            if (fetch_step_q == 5'd19) begin
              fetch_active_q <= 1'b0;
              chroma_fetch_done <= 1'b1;
            end else begin
              fetch_step_q <= fetch_step_q + 5'd1;
            end
          end else begin
            fetch_read_addr_q <= fetch_pred_read_addr_w;
            fetch_capture_step_q <= fetch_step_q;
            fetch_read_is_pred_q <= 1'b1;
            fetch_read_pending_q <= 1'b1;
          end
        end else begin
          fetch_active_q <= 1'b0;
          chroma_fetch_done <= 1'b1;
        end
      end else if (!chroma_fetch_start) begin
        chroma_fetch_done <= 1'b0;
      end

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
          block_chroma_sample_q <= 7'd0;
          state_q <= ST_DRAIN_CHROMA;
        end
        ST_DRAIN_CHROMA: begin
          if (sample_fire) begin
            black_ok_q <= black_next_w;
            sample_index_q <= sample_index_q + 32'd1;
            if (block_chroma_sample_q == 7'd127) begin
              if (block_id_q[5:3] == last_block_row_q && block_id_q[2:0] == last_block_col_q) begin
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
              end else if (block_id_q[2:0] == last_block_col_q) begin
                block_id_q <= {block_id_q[5:3] + 3'd1, 3'd0};
                block_sample_q <= 6'd0;
                block_chroma_sample_q <= 7'd0;
                state_q <= ST_READ;
              end else begin
                block_id_q <= block_id_q + 6'd1;
                block_sample_q <= 6'd0;
                block_chroma_sample_q <= 7'd0;
                state_q <= ST_READ;
              end
            end else if (sample_last) begin
              unsupported <= 1'b1;
              done <= 1'b1;
              state_q <= ST_DONE;
            end else begin
              block_chroma_sample_q <= block_chroma_sample_q + 7'd1;
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
