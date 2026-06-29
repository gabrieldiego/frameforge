`timescale 1ns/1ps

module ff_av2_partition_controller (
  input  logic [15:0] tile_width,
  input  logic [15:0] tile_height,
  input  logic [4:0]  block_row_mi,
  input  logic [4:0]  block_col_mi,
  input  logic [4:0]  block_w_mi,
  input  logic [4:0]  block_h_mi,
  input  logic [1:0]  partition,
  input  logic        partition_emit_step,
  input  logic        palette_mode,
  input  logic [7:0]  partition_above_ctx,
  input  logic [7:0]  partition_left_ctx,
  output logic [4:0]  visible_rows_mi,
  output logic [4:0]  visible_cols_mi,
  output logic        block_visible,
  output logic [4:0]  block_half_w_mi,
  output logic [4:0]  block_half_h_mi,
  output logic        allowed_none,
  output logic        allowed_horz,
  output logic        allowed_vert,
  output logic        forced_valid,
  output logic [1:0]  forced_partition,
  output logic [1:0]  chosen_partition,
  output logic        partition_need_do_split,
  output logic        partition_need_rect,
  output logic        partition_emit_do_split,
  output logic        partition_emit_rect,
  output logic        partition_emit_done,
  output logic [5:0]  partition_split_ctx,
  output logic [5:0]  partition_rect_ctx,
  output logic [1:0]  partition_raw_ctx,
  output logic [7:0]  partition_update_above,
  output logic [7:0]  partition_update_left,
  output logic        leaf_fsc_symbol,
  output logic [31:0] leaf_fsc_fh
);

  localparam logic [1:0] PARTITION_NONE = 2'd0;
  localparam logic [1:0] PARTITION_HORZ = 2'd1;
  localparam logic [1:0] PARTITION_VERT = 2'd2;

  logic block_partition_point_w;
  logic block_square_w;
  logic block_tall_w;
  logic [4:0] block_quarter_w_mi_w;
  logic [4:0] block_quarter_h_mi_w;
  logic has_rows_w;
  logic has_cols_w;
  logic sub_has_rows_w;
  logic sub_has_cols_w;
  logic rect_implied_horz_w;
  logic rect_implied_vert_w;
  logic aspect_none_w;
  logic aspect_horz_w;
  logic aspect_vert_w;
  logic [8:0] block_w_mi_ext_w;
  logic [8:0] block_h_mi_ext_w;
  logic [8:0] block_half_w_mi_ext_w;
  logic [8:0] block_half_h_mi_ext_w;
  logic allowed_none_pre_w;
  logic allowed_horz_pre_w;
  logic allowed_vert_pre_w;
  logic allowed_any_w;
  logic allowed_only_w;
  logic palette_preferred_valid_w;
  logic [1:0] palette_preferred_partition_w;
  logic preferred_valid_w;
  logic [1:0] preferred_partition_w;
  logic chosen_do_split_w;
  logic partition_forced_implied_w;
  logic [1:0] partition_above_shift_w;
  logic [1:0] partition_left_shift_w;
  logic partition_above_bit_w;
  logic partition_left_bit_w;
  logic [3:0] bsize_map_w;
  logic [3:0] bsize_rect_map_w;

  assign visible_rows_mi = tile_height[6:2];
  assign visible_cols_mi = tile_width[6:2];
  assign block_visible =
    (block_row_mi < visible_rows_mi) &&
    (block_col_mi < visible_cols_mi);
  assign block_partition_point_w =
    !((block_w_mi == 5'd2 && block_h_mi == 5'd16) ||
      (block_w_mi == 5'd16 && block_h_mi == 5'd2));
  assign block_square_w = (block_w_mi == block_h_mi);
  assign block_tall_w = (block_h_mi > block_w_mi);
  assign block_half_w_mi = block_w_mi >> 1;
  assign block_half_h_mi = block_h_mi >> 1;
  assign block_quarter_w_mi_w = block_w_mi >> 2;
  assign block_quarter_h_mi_w = block_h_mi >> 2;
  assign block_w_mi_ext_w = {4'd0, block_w_mi};
  assign block_h_mi_ext_w = {4'd0, block_h_mi};
  assign block_half_w_mi_ext_w = {4'd0, block_half_w_mi};
  assign block_half_h_mi_ext_w = {4'd0, block_half_h_mi};
  assign has_rows_w = (block_row_mi + block_half_h_mi) < visible_rows_mi;
  assign has_cols_w = (block_col_mi + block_half_w_mi) < visible_cols_mi;
  assign sub_has_rows_w = (block_row_mi + block_quarter_h_mi_w) < visible_rows_mi;
  assign sub_has_cols_w = (block_col_mi + block_quarter_w_mi_w) < visible_cols_mi;
  assign rect_implied_horz_w =
    (block_w_mi == 5'd2 && block_h_mi == 5'd8) ||
    (block_w_mi == 5'd4 && block_h_mi == 5'd16) ||
    (block_w_mi == 5'd2 && block_h_mi == 5'd16);
  assign rect_implied_vert_w =
    (block_w_mi == 5'd8 && block_h_mi == 5'd2) ||
    (block_w_mi == 5'd16 && block_h_mi == 5'd4) ||
    (block_w_mi == 5'd16 && block_h_mi == 5'd2);
  assign aspect_none_w =
    !((block_w_mi_ext_w > (block_h_mi_ext_w << 3)) ||
      (block_h_mi_ext_w > (block_w_mi_ext_w << 3)));
  assign aspect_horz_w =
    !((block_w_mi_ext_w >= (block_half_h_mi_ext_w << 3)) ||
      (block_half_h_mi_ext_w >= (block_w_mi_ext_w << 3)));
  assign aspect_vert_w =
    !((block_half_w_mi_ext_w >= (block_h_mi_ext_w << 3)) ||
      (block_h_mi_ext_w >= (block_half_w_mi_ext_w << 3)));
  assign allowed_none_pre_w = has_rows_w && has_cols_w && aspect_none_w;
  assign allowed_horz_pre_w =
    (block_h_mi >= 5'd2) && !rect_implied_vert_w && aspect_horz_w;
  assign allowed_vert_pre_w =
    (block_w_mi >= 5'd2) && !rect_implied_horz_w && aspect_vert_w;
  assign allowed_any_w = allowed_none_pre_w || allowed_horz_pre_w || allowed_vert_pre_w;
  assign allowed_none = allowed_none_pre_w || !allowed_any_w;
  assign allowed_horz = allowed_horz_pre_w;
  assign allowed_vert = allowed_vert_pre_w;
  assign allowed_only_w =
    (allowed_none && !allowed_horz && !allowed_vert) ||
    (!allowed_none && allowed_horz && !allowed_vert) ||
    (!allowed_none && !allowed_horz && allowed_vert);
  assign preferred_valid_w =
    block_partition_point_w &&
    !((block_w_mi == 5'd2) && (block_h_mi == 5'd2)) &&
    (preferred_partition_w != PARTITION_NONE);
  assign preferred_partition_w =
    block_square_w ?
      ((block_h_mi > 5'd2 && allowed_horz) ? PARTITION_HORZ :
       (block_w_mi > 5'd2 && allowed_vert) ? PARTITION_VERT :
       PARTITION_NONE) :
    (block_w_mi > block_h_mi) ?
      ((block_w_mi > 5'd2 && allowed_vert) ? PARTITION_VERT :
       (block_h_mi > 5'd2 && allowed_horz) ? PARTITION_HORZ :
       PARTITION_NONE) :
      ((block_h_mi > 5'd2 && allowed_horz) ? PARTITION_HORZ :
       (block_w_mi > 5'd2 && allowed_vert) ? PARTITION_VERT :
       PARTITION_NONE);
  assign chosen_do_split_w = (partition != PARTITION_NONE);
  assign partition_forced_implied_w =
    forced_valid &&
    (forced_partition == partition) &&
    (((forced_partition == PARTITION_NONE) && allowed_none) ||
     ((forced_partition == PARTITION_HORZ) && allowed_horz) ||
     ((forced_partition == PARTITION_VERT) && allowed_vert));
  assign partition_need_do_split =
    !(partition_forced_implied_w || allowed_only_w) && allowed_none;
  assign partition_need_rect =
    !(partition_forced_implied_w || allowed_only_w) &&
    chosen_do_split_w &&
    allowed_horz &&
    allowed_vert &&
    !(rect_implied_horz_w || rect_implied_vert_w);
  assign partition_emit_do_split = !partition_emit_step && partition_need_do_split;
  assign partition_emit_rect =
    (!partition_emit_step && !partition_need_do_split && partition_need_rect) ||
    (partition_emit_step && partition_need_do_split && partition_need_rect);
  assign partition_emit_done =
    (!partition_need_do_split && !partition_need_rect) ||
    (partition_emit_step && partition_need_rect) ||
    (!partition_emit_step && partition_need_do_split && !partition_need_rect);
  assign partition_above_shift_w =
    (block_w_mi == 5'd2) ? 2'd0 :
    (block_w_mi == 5'd4) ? 2'd1 :
    (block_w_mi == 5'd8) ? 2'd2 : 2'd3;
  assign partition_left_shift_w =
    (block_h_mi == 5'd2) ? 2'd0 :
    (block_h_mi == 5'd4) ? 2'd1 :
    (block_h_mi == 5'd8) ? 2'd2 : 2'd3;
  assign partition_above_bit_w =
    (partition_above_shift_w == 2'd0) ? partition_above_ctx[0] :
    (partition_above_shift_w == 2'd1) ? partition_above_ctx[1] :
    (partition_above_shift_w == 2'd2) ? partition_above_ctx[2] :
                                        partition_above_ctx[3];
  assign partition_left_bit_w =
    (partition_left_shift_w == 2'd0) ? partition_left_ctx[0] :
    (partition_left_shift_w == 2'd1) ? partition_left_ctx[1] :
    (partition_left_shift_w == 2'd2) ? partition_left_ctx[2] :
                                       partition_left_ctx[3];
  assign partition_raw_ctx = {partition_left_bit_w, partition_above_bit_w};

  always @* begin
    forced_valid = 1'b0;
    forced_partition = PARTITION_NONE;
    if (!block_partition_point_w) begin
      forced_valid = 1'b1;
      forced_partition = PARTITION_NONE;
    end else if (!(has_rows_w && has_cols_w)) begin
      forced_valid = 1'b1;
      if (block_square_w) begin
        forced_partition = (has_rows_w && !has_cols_w) ? PARTITION_VERT : PARTITION_HORZ;
      end else if (block_tall_w) begin
        if (!has_rows_w) begin
          forced_partition = PARTITION_HORZ;
        end else if (block_w_mi >= 5'd4 && !sub_has_cols_w) begin
          forced_partition = PARTITION_HORZ;
        end else begin
          forced_valid = 1'b0;
        end
      end else begin
        if (!has_cols_w) begin
          forced_partition = PARTITION_VERT;
        end else if (block_h_mi >= 5'd4 && !sub_has_rows_w) begin
          forced_partition = PARTITION_VERT;
        end else begin
          forced_valid = 1'b0;
        end
      end
    end

    palette_preferred_partition_w = PARTITION_NONE;
    if (block_square_w) begin
      if (block_h_mi > 5'd2 && allowed_horz) begin
        palette_preferred_partition_w = PARTITION_HORZ;
      end else if (block_w_mi > 5'd2 && allowed_vert) begin
        palette_preferred_partition_w = PARTITION_VERT;
      end
    end else if (block_w_mi > block_h_mi) begin
      if (block_w_mi > 5'd2 && allowed_vert) begin
        palette_preferred_partition_w = PARTITION_VERT;
      end else if (block_h_mi > 5'd2 && allowed_horz) begin
        palette_preferred_partition_w = PARTITION_HORZ;
      end
    end else begin
      if (block_h_mi > 5'd2 && allowed_horz) begin
        palette_preferred_partition_w = PARTITION_HORZ;
      end else if (block_w_mi > 5'd2 && allowed_vert) begin
        palette_preferred_partition_w = PARTITION_VERT;
      end
    end

    palette_preferred_valid_w =
      palette_mode &&
      block_partition_point_w &&
      !((block_w_mi == 5'd2) && (block_h_mi == 5'd2)) &&
      (palette_preferred_partition_w != PARTITION_NONE);

    chosen_partition = PARTITION_NONE;
    if (!block_partition_point_w) begin
      chosen_partition = PARTITION_NONE;
    end else if (
      forced_valid &&
      (((forced_partition == PARTITION_NONE) && allowed_none) ||
       ((forced_partition == PARTITION_HORZ) && allowed_horz) ||
       ((forced_partition == PARTITION_VERT) && allowed_vert))
    ) begin
      chosen_partition = forced_partition;
    end else if (palette_preferred_valid_w) begin
      chosen_partition = palette_preferred_partition_w;
    end else if (
      preferred_valid_w &&
      (((preferred_partition_w == PARTITION_HORZ) && allowed_horz) ||
       ((preferred_partition_w == PARTITION_VERT) && allowed_vert))
    ) begin
      chosen_partition = preferred_partition_w;
    end else if (allowed_only_w) begin
      if (allowed_none) chosen_partition = PARTITION_NONE;
      else if (allowed_horz) chosen_partition = PARTITION_HORZ;
      else chosen_partition = PARTITION_VERT;
    end else if (allowed_none) begin
      chosen_partition = PARTITION_NONE;
    end else if ((block_row_mi + block_h_mi) > visible_rows_mi && allowed_horz) begin
      chosen_partition = PARTITION_HORZ;
    end else if ((block_col_mi + block_w_mi) > visible_cols_mi && allowed_vert) begin
      chosen_partition = PARTITION_VERT;
    end else if (allowed_horz) begin
      chosen_partition = PARTITION_HORZ;
    end else if (allowed_vert) begin
      chosen_partition = PARTITION_VERT;
    end

    bsize_map_w = 4'd0;
    case ({block_w_mi, block_h_mi})
      {5'd2, 5'd2}: bsize_map_w = 4'd0;
      {5'd2, 5'd4},
      {5'd4, 5'd2},
      {5'd4, 5'd4}: bsize_map_w = 4'd1;
      {5'd4, 5'd8},
      {5'd8, 5'd4},
      {5'd8, 5'd8}: bsize_map_w = 4'd2;
      {5'd8, 5'd16},
      {5'd16, 5'd8},
      {5'd16, 5'd16}: bsize_map_w = 4'd3;
      {5'd2, 5'd8}: bsize_map_w = 4'd12;
      {5'd8, 5'd2}: bsize_map_w = 4'd13;
      {5'd4, 5'd16}: bsize_map_w = 4'd14;
      {5'd16, 5'd4}: bsize_map_w = 4'd15;
      default: bsize_map_w = 4'd0;
    endcase

    bsize_rect_map_w = 4'd0;
    case ({block_w_mi, block_h_mi})
      {5'd2, 5'd2},
      {5'd4, 5'd4}: bsize_rect_map_w = 4'd0;
      {5'd2, 5'd4},
      {5'd4, 5'd8}: bsize_rect_map_w = 4'd1;
      {5'd4, 5'd2},
      {5'd8, 5'd4}: bsize_rect_map_w = 4'd2;
      {5'd8, 5'd8}: bsize_rect_map_w = 4'd3;
      {5'd8, 5'd16}: bsize_rect_map_w = 4'd4;
      {5'd16, 5'd8}: bsize_rect_map_w = 4'd5;
      {5'd16, 5'd16}: bsize_rect_map_w = 4'd6;
      {5'd2, 5'd8},
      {5'd4, 5'd16}: bsize_rect_map_w = 4'd13;
      {5'd8, 5'd2},
      {5'd16, 5'd4}: bsize_rect_map_w = 4'd14;
      default: bsize_rect_map_w = 4'd0;
    endcase

    partition_split_ctx = {bsize_map_w, 2'b00} + {4'd0, partition_raw_ctx};
    partition_rect_ctx = {bsize_rect_map_w, 2'b00} + {4'd0, partition_raw_ctx};

    partition_update_above = 8'd56;
    partition_update_left = 8'd56;
    case ({block_w_mi, block_h_mi})
      {5'd2, 5'd2}: begin partition_update_above = 8'd62; partition_update_left = 8'd62; end
      {5'd2, 5'd4}: begin partition_update_above = 8'd62; partition_update_left = 8'd60; end
      {5'd4, 5'd2}: begin partition_update_above = 8'd60; partition_update_left = 8'd62; end
      {5'd4, 5'd4}: begin partition_update_above = 8'd60; partition_update_left = 8'd60; end
      {5'd4, 5'd8}: begin partition_update_above = 8'd60; partition_update_left = 8'd56; end
      {5'd8, 5'd4}: begin partition_update_above = 8'd56; partition_update_left = 8'd60; end
      {5'd8, 5'd8}: begin partition_update_above = 8'd56; partition_update_left = 8'd56; end
      {5'd8, 5'd16}: begin partition_update_above = 8'd56; partition_update_left = 8'd48; end
      {5'd16, 5'd8}: begin partition_update_above = 8'd48; partition_update_left = 8'd56; end
      {5'd16, 5'd16}: begin partition_update_above = 8'd48; partition_update_left = 8'd48; end
      {5'd2, 5'd8}: begin partition_update_above = 8'd62; partition_update_left = 8'd56; end
      {5'd8, 5'd2}: begin partition_update_above = 8'd56; partition_update_left = 8'd62; end
      {5'd4, 5'd16}: begin partition_update_above = 8'd60; partition_update_left = 8'd48; end
      {5'd16, 5'd4}: begin partition_update_above = 8'd48; partition_update_left = 8'd60; end
      {5'd2, 5'd16}: begin partition_update_above = 8'd62; partition_update_left = 8'd48; end
      {5'd16, 5'd2}: begin partition_update_above = 8'd48; partition_update_left = 8'd62; end
    endcase

    leaf_fsc_symbol = (block_w_mi <= 5'd8) && (block_h_mi <= 5'd8);
    leaf_fsc_fh = 32'd0;
    case ({block_w_mi, block_h_mi})
      {5'd2, 5'd2}: leaf_fsc_fh = 32'd514;
      {5'd2, 5'd4},
      {5'd4, 5'd2}: leaf_fsc_fh = 32'd444;
      {5'd4, 5'd4},
      {5'd2, 5'd8},
      {5'd8, 5'd2}: leaf_fsc_fh = 32'd186;
      {5'd4, 5'd8},
      {5'd8, 5'd4},
      {5'd8, 5'd8}: leaf_fsc_fh = 32'd77;
      default: leaf_fsc_fh = 32'd0;
    endcase
  end

endmodule
