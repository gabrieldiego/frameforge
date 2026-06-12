`timescale 1ns/1ps

module ff_vvc_tu_order_8x8 (
  input  logic [3:0] visible_cols,
  input  logic [3:0] visible_rows,
  input  logic [2:0] sample_col,
  input  logic [2:0] sample_row,
  input  logic [5:0] target_index,
  output logic       sample_valid,
  output logic [5:0] sample_index,
  output logic       target_valid,
  output logic [2:0] target_col,
  output logic [2:0] target_row
);
  logic [3:0] root_left_cols;
  logic [3:0] root_right_cols;
  logic [3:0] root_top_rows;
  logic [3:0] root_bottom_rows;
  logic [6:0] root_count_tl;
  logic [6:0] root_count_tr;
  logic [6:0] root_count_bl;
  logic [6:0] root_count_total;

  logic [2:0] target_base_col_0;
  logic [2:0] target_base_row_0;
  logic [3:0] target_cols_0;
  logic [3:0] target_rows_0;
  logic [6:0] target_rem_0;
  logic [2:0] target_base_col_1;
  logic [2:0] target_base_row_1;
  logic [3:0] target_cols_1;
  logic [3:0] target_rows_1;
  logic [6:0] target_rem_1;
  logic [3:0] target_left_cols;
  logic [3:0] target_right_cols;
  logic [3:0] target_top_rows;
  logic [3:0] target_bottom_rows;
  logic [6:0] target_count_tl;
  logic [6:0] target_count_tr;
  logic [6:0] target_count_bl;

  logic [2:0] sample_local_col_0;
  logic [2:0] sample_local_row_0;
  logic [3:0] sample_cols_0;
  logic [3:0] sample_rows_0;
  logic [6:0] sample_base_0;
  logic [2:0] sample_local_col_1;
  logic [2:0] sample_local_row_1;
  logic [3:0] sample_cols_1;
  logic [3:0] sample_rows_1;
  logic [6:0] sample_base_1;
  logic [3:0] sample_left_cols;
  logic [3:0] sample_right_cols;
  logic [3:0] sample_top_rows;
  logic [3:0] sample_bottom_rows;
  logic [6:0] sample_count_tl;
  logic [6:0] sample_count_tr;
  logic [6:0] sample_count_bl;

  always @* begin
    root_left_cols = (visible_cols > 4'd4) ? 4'd4 : visible_cols;
    root_right_cols = (visible_cols > 4'd4) ? (visible_cols - 4'd4) : 4'd0;
    root_top_rows = (visible_rows > 4'd4) ? 4'd4 : visible_rows;
    root_bottom_rows = (visible_rows > 4'd4) ? (visible_rows - 4'd4) : 4'd0;
    root_count_tl = root_left_cols * root_top_rows;
    root_count_tr = root_right_cols * root_top_rows;
    root_count_bl = root_left_cols * root_bottom_rows;
    root_count_total = visible_cols * visible_rows;

    target_valid = {1'b0, target_index} < root_count_total;
    target_base_col_0 = 3'd0;
    target_base_row_0 = 3'd0;
    target_cols_0 = root_left_cols;
    target_rows_0 = root_top_rows;
    target_rem_0 = {1'b0, target_index};
    if (target_index >= root_count_tl + root_count_tr + root_count_bl) begin
      target_base_col_0 = 3'd4;
      target_base_row_0 = 3'd4;
      target_cols_0 = root_right_cols;
      target_rows_0 = root_bottom_rows;
      target_rem_0 = target_index - root_count_tl - root_count_tr - root_count_bl;
    end else if (target_index >= root_count_tl + root_count_tr) begin
      target_base_col_0 = 3'd0;
      target_base_row_0 = 3'd4;
      target_cols_0 = root_left_cols;
      target_rows_0 = root_bottom_rows;
      target_rem_0 = target_index - root_count_tl - root_count_tr;
    end else if (target_index >= root_count_tl) begin
      target_base_col_0 = 3'd4;
      target_base_row_0 = 3'd0;
      target_cols_0 = root_right_cols;
      target_rows_0 = root_top_rows;
      target_rem_0 = target_index - root_count_tl;
    end

    target_left_cols = (target_cols_0 > 4'd2) ? 4'd2 : target_cols_0;
    target_right_cols = (target_cols_0 > 4'd2) ? (target_cols_0 - 4'd2) : 4'd0;
    target_top_rows = (target_rows_0 > 4'd2) ? 4'd2 : target_rows_0;
    target_bottom_rows = (target_rows_0 > 4'd2) ? (target_rows_0 - 4'd2) : 4'd0;
    target_count_tl = target_left_cols * target_top_rows;
    target_count_tr = target_right_cols * target_top_rows;
    target_count_bl = target_left_cols * target_bottom_rows;

    target_base_col_1 = target_base_col_0;
    target_base_row_1 = target_base_row_0;
    target_cols_1 = target_left_cols;
    target_rows_1 = target_top_rows;
    target_rem_1 = target_rem_0;
    if (target_rem_0 >= target_count_tl + target_count_tr + target_count_bl) begin
      target_base_col_1 = target_base_col_0 + 3'd2;
      target_base_row_1 = target_base_row_0 + 3'd2;
      target_cols_1 = target_right_cols;
      target_rows_1 = target_bottom_rows;
      target_rem_1 = target_rem_0 - target_count_tl - target_count_tr - target_count_bl;
    end else if (target_rem_0 >= target_count_tl + target_count_tr) begin
      target_base_col_1 = target_base_col_0;
      target_base_row_1 = target_base_row_0 + 3'd2;
      target_cols_1 = target_left_cols;
      target_rows_1 = target_bottom_rows;
      target_rem_1 = target_rem_0 - target_count_tl - target_count_tr;
    end else if (target_rem_0 >= target_count_tl) begin
      target_base_col_1 = target_base_col_0 + 3'd2;
      target_base_row_1 = target_base_row_0;
      target_cols_1 = target_right_cols;
      target_rows_1 = target_top_rows;
      target_rem_1 = target_rem_0 - target_count_tl;
    end

    target_left_cols = (target_cols_1 > 4'd1) ? 4'd1 : target_cols_1;
    target_right_cols = (target_cols_1 > 4'd1) ? (target_cols_1 - 4'd1) : 4'd0;
    target_top_rows = (target_rows_1 > 4'd1) ? 4'd1 : target_rows_1;
    target_bottom_rows = (target_rows_1 > 4'd1) ? (target_rows_1 - 4'd1) : 4'd0;
    target_count_tl = target_left_cols * target_top_rows;
    target_count_tr = target_right_cols * target_top_rows;
    target_count_bl = target_left_cols * target_bottom_rows;

    target_col = target_base_col_1;
    target_row = target_base_row_1;
    if (target_rem_1 >= target_count_tl + target_count_tr + target_count_bl) begin
      target_col = target_base_col_1 + 3'd1;
      target_row = target_base_row_1 + 3'd1;
    end else if (target_rem_1 >= target_count_tl + target_count_tr) begin
      target_col = target_base_col_1;
      target_row = target_base_row_1 + 3'd1;
    end else if (target_rem_1 >= target_count_tl) begin
      target_col = target_base_col_1 + 3'd1;
      target_row = target_base_row_1;
    end

    sample_valid = ({1'b0, sample_col} < visible_cols) &&
                   ({1'b0, sample_row} < visible_rows);
    sample_local_col_0 = sample_col;
    sample_local_row_0 = sample_row;
    sample_cols_0 = root_left_cols;
    sample_rows_0 = root_top_rows;
    sample_base_0 = 7'd0;
    if (sample_col[2] && sample_row[2]) begin
      sample_local_col_0 = sample_col - 3'd4;
      sample_local_row_0 = sample_row - 3'd4;
      sample_cols_0 = root_right_cols;
      sample_rows_0 = root_bottom_rows;
      sample_base_0 = root_count_tl + root_count_tr + root_count_bl;
    end else if (sample_row[2]) begin
      sample_local_col_0 = sample_col;
      sample_local_row_0 = sample_row - 3'd4;
      sample_cols_0 = root_left_cols;
      sample_rows_0 = root_bottom_rows;
      sample_base_0 = root_count_tl + root_count_tr;
    end else if (sample_col[2]) begin
      sample_local_col_0 = sample_col - 3'd4;
      sample_local_row_0 = sample_row;
      sample_cols_0 = root_right_cols;
      sample_rows_0 = root_top_rows;
      sample_base_0 = root_count_tl;
    end

    sample_left_cols = (sample_cols_0 > 4'd2) ? 4'd2 : sample_cols_0;
    sample_right_cols = (sample_cols_0 > 4'd2) ? (sample_cols_0 - 4'd2) : 4'd0;
    sample_top_rows = (sample_rows_0 > 4'd2) ? 4'd2 : sample_rows_0;
    sample_bottom_rows = (sample_rows_0 > 4'd2) ? (sample_rows_0 - 4'd2) : 4'd0;
    sample_count_tl = sample_left_cols * sample_top_rows;
    sample_count_tr = sample_right_cols * sample_top_rows;
    sample_count_bl = sample_left_cols * sample_bottom_rows;
    sample_local_col_1 = sample_local_col_0[1:0];
    sample_local_row_1 = sample_local_row_0[1:0];
    sample_cols_1 = sample_left_cols;
    sample_rows_1 = sample_top_rows;
    sample_base_1 = sample_base_0;
    if (sample_local_col_0[1] && sample_local_row_0[1]) begin
      sample_local_col_1 = {1'b0, sample_local_col_0[0]};
      sample_local_row_1 = {1'b0, sample_local_row_0[0]};
      sample_cols_1 = sample_right_cols;
      sample_rows_1 = sample_bottom_rows;
      sample_base_1 = sample_base_0 + sample_count_tl + sample_count_tr + sample_count_bl;
    end else if (sample_local_row_0[1]) begin
      sample_local_col_1 = sample_local_col_0;
      sample_local_row_1 = {1'b0, sample_local_row_0[0]};
      sample_cols_1 = sample_left_cols;
      sample_rows_1 = sample_bottom_rows;
      sample_base_1 = sample_base_0 + sample_count_tl + sample_count_tr;
    end else if (sample_local_col_0[1]) begin
      sample_local_col_1 = {1'b0, sample_local_col_0[0]};
      sample_local_row_1 = sample_local_row_0;
      sample_cols_1 = sample_right_cols;
      sample_rows_1 = sample_top_rows;
      sample_base_1 = sample_base_0 + sample_count_tl;
    end

    sample_left_cols = (sample_cols_1 > 4'd1) ? 4'd1 : sample_cols_1;
    sample_right_cols = (sample_cols_1 > 4'd1) ? (sample_cols_1 - 4'd1) : 4'd0;
    sample_top_rows = (sample_rows_1 > 4'd1) ? 4'd1 : sample_rows_1;
    sample_bottom_rows = (sample_rows_1 > 4'd1) ? (sample_rows_1 - 4'd1) : 4'd0;
    sample_count_tl = sample_left_cols * sample_top_rows;
    sample_count_tr = sample_right_cols * sample_top_rows;
    sample_count_bl = sample_left_cols * sample_bottom_rows;
    sample_index = sample_base_1[5:0];
    if (sample_local_col_1[0] && sample_local_row_1[0]) begin
      sample_index = sample_base_1 + sample_count_tl + sample_count_tr + sample_count_bl;
    end else if (sample_local_row_1[0]) begin
      sample_index = sample_base_1 + sample_count_tl + sample_count_tr;
    end else if (sample_local_col_1[0]) begin
      sample_index = sample_base_1 + sample_count_tl;
    end
  end
endmodule

module ff_vvc_luma_tu_node_8x8 #(
  parameter int CTU_SIZE = 64
) (
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,
  input  logic [5:0]  target_index,
  output logic        valid,
  output logic [15:0] tu_x,
  output logic [15:0] tu_y
);
  localparam logic [15:0] LUMA_TU_SIZE = 16'd8;

  logic [3:0] visible_tu_cols;
  logic [3:0] visible_tu_rows;
  logic [2:0] target_tu_col;
  logic [2:0] target_tu_row;

  ff_vvc_tu_order_8x8 order (
    .visible_cols(visible_tu_cols),
    .visible_rows(visible_tu_rows),
    .sample_col(3'd0),
    .sample_row(3'd0),
    .target_index(target_index),
    .sample_valid(),
    .sample_index(),
    .target_valid(valid),
    .target_col(target_tu_col),
    .target_row(target_tu_row)
  );

  always @* begin
    visible_tu_cols = (visible_width + LUMA_TU_SIZE - 16'd1) >> 3;
    visible_tu_rows = (visible_height + LUMA_TU_SIZE - 16'd1) >> 3;
    // H.266 7.3.11.4 coding_tree() visits QT children in TL, TR, BL, BR
    // order before H.266 7.3.11.10 transform_unit(). With fixed 8x8 luma
    // TUs, this maps the compact stream index to CTU-local leaf coordinates.
    tu_x = {13'd0, target_tu_col, 3'b000};
    tu_y = {13'd0, target_tu_row, 3'b000};
  end
endmodule

module ff_vvc_chroma_tu_order_420 #(
  parameter int CTU_SIZE = 64,
  parameter int STACK_DEPTH = 64
) (
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,
  input  logic [15:0] sample_x,
  input  logic [15:0] sample_y,
  input  logic [5:0]  target_index,
  output logic        sample_valid,
  output logic [5:0]  sample_tu_index,
  output logic        target_valid,
  output logic [15:0] target_x,
  output logic [15:0] target_y
);
  localparam logic [15:0] CHROMA_TU_SIZE = 16'd4;
  localparam logic [15:0] CHROMA_TU_LUMA_SIZE = 16'd8;

  logic [3:0] visible_tu_cols;
  logic [3:0] visible_tu_rows;
  logic [2:0] sample_tu_col;
  logic [2:0] sample_tu_row;
  logic [2:0] target_tu_col;
  logic [2:0] target_tu_row;

  ff_vvc_tu_order_8x8 order (
    .visible_cols(visible_tu_cols),
    .visible_rows(visible_tu_rows),
    .sample_col(sample_tu_col),
    .sample_row(sample_tu_row),
    .target_index(target_index),
    .sample_valid(sample_valid),
    .sample_index(sample_tu_index),
    .target_valid(target_valid),
    .target_col(target_tu_col),
    .target_row(target_tu_row)
  );

  always @* begin
    visible_tu_cols = (visible_width + CHROMA_TU_LUMA_SIZE - 16'd1) >> 3;
    visible_tu_rows = (visible_height + CHROMA_TU_LUMA_SIZE - 16'd1) >> 3;
    sample_tu_col = sample_x[4:2];
    sample_tu_row = sample_y[4:2];
    // Current fixed 4:2:0 subset maps each visible 8x8 luma leaf to one 4x4
    // chroma TU, preserving coding_tree() leaf traversal for CABAC.
    target_x = {13'd0, target_tu_col, 2'b00};
    target_y = {13'd0, target_tu_row, 2'b00};
  end
endmodule

module ff_vvc_chroma_tu_mapper_420 #(
  parameter int CTU_SIZE = 64,
  parameter int STACK_DEPTH = 64
) (
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,
  input  logic [15:0] sample_x,
  input  logic [15:0] sample_y,
  output logic        sample_valid,
  output logic [5:0]  tu_index,
  output logic [15:0] tu_width,
  output logic [15:0] tu_height,
  output logic [15:0] tu_local_x,
  output logic [15:0] tu_local_y
);
  localparam logic [15:0] CHROMA_TU_SIZE = 16'd4;

  logic [15:0] visible_chroma_width;
  logic [15:0] visible_chroma_height;
  logic        order_sample_valid_w;
  logic [5:0]  order_sample_tu_index_w;

  ff_vvc_chroma_tu_order_420 #(
    .CTU_SIZE(CTU_SIZE),
    .STACK_DEPTH(STACK_DEPTH)
  ) order (
    .visible_width(visible_width),
    .visible_height(visible_height),
    .sample_x(sample_x),
    .sample_y(sample_y),
    .target_index(6'd0),
    .sample_valid(order_sample_valid_w),
    .sample_tu_index(order_sample_tu_index_w),
    .target_valid(),
    .target_x(),
    .target_y()
  );

  always @* begin
    visible_chroma_width = visible_width >> 1;
    visible_chroma_height = visible_height >> 1;

    // Current residual subset: H.266 7.3.11.10 transform_unit() is only
    // emitted for 8x8 luma-coordinate leaves, i.e. fixed 4x4 chroma TUs in
    // 4:2:0. TU indices follow coding_tree() leaf traversal, matching the
    // software encoder and CABAC symbolizer.
    sample_valid =
      (sample_x < visible_chroma_width) && (sample_y < visible_chroma_height) &&
      order_sample_valid_w;
    tu_index = order_sample_tu_index_w;
    tu_width = CHROMA_TU_SIZE;
    tu_height = CHROMA_TU_SIZE;
    tu_local_x = {14'd0, sample_x[1:0]};
    tu_local_y = {14'd0, sample_y[1:0]};
  end
endmodule

module ff_vvc_chroma_tu_node_420 #(
  parameter int CTU_SIZE = 64,
  parameter int STACK_DEPTH = 64
) (
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,
  input  logic [5:0]  target_index,
  output logic        valid,
  output logic [15:0] tu_x,
  output logic [15:0] tu_y,
  output logic [15:0] tu_width,
  output logic [15:0] tu_height
);
  localparam logic [15:0] CHROMA_TU_SIZE = 16'd4;

  logic        order_target_valid_w;
  logic [15:0] order_target_x_w;
  logic [15:0] order_target_y_w;

  ff_vvc_chroma_tu_order_420 #(
    .CTU_SIZE(CTU_SIZE),
    .STACK_DEPTH(STACK_DEPTH)
  ) order (
    .visible_width(visible_width),
    .visible_height(visible_height),
    .sample_x(16'd0),
    .sample_y(16'd0),
    .target_index(target_index),
    .sample_valid(),
    .sample_tu_index(),
    .target_valid(order_target_valid_w),
    .target_x(order_target_x_w),
    .target_y(order_target_y_w)
  );

  always @* begin
    tu_x = order_target_x_w;
    tu_y = order_target_y_w;
    tu_width = CHROMA_TU_SIZE;
    tu_height = CHROMA_TU_SIZE;
    valid = order_target_valid_w;
  end
endmodule
