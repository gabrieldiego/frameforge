`timescale 1ns/1ps

module ff_vvc_palette_symbolizer #(
  parameter int CTU_SIZE = 64,
  parameter int PALETTE_CU_SIZE = 8,
  parameter int SAMPLE_BITS = 8,
  parameter int MAX_PALETTE_SYMBOLS =
    ((CTU_SIZE + PALETTE_CU_SIZE - 1) / PALETTE_CU_SIZE) *
    ((CTU_SIZE + PALETTE_CU_SIZE - 1) / PALETTE_CU_SIZE)
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        clear,
  input  logic        enable,
  input  logic [15:0] ctu_coded_width,
  input  logic [15:0] ctu_coded_height,
  input  logic [MAX_PALETTE_SYMBOLS - 1:0] cu_select_mask,
  input  logic        cu_request_valid,
  output logic        cu_request_ready,
  input  logic [15:0] cu_request_origin_x,
  input  logic [15:0] cu_request_origin_y,
  input  logic        cu_request_last,
  input  logic        s_axis_valid,
  output logic        s_axis_ready,
  input  logic [1:0]  s_axis_plane,
  input  logic [SAMPLE_BITS - 1:0] s_axis_sample,
  input  logic        s_axis_last,
  output logic        m_axis_valid,
  input  logic        m_axis_ready,
  output logic [31:0] m_axis_data,
  output logic        m_axis_last,
  output logic        m_axis_cu_last,
  output logic [7:0]  symbol_count
);
  localparam logic [1:0] PLANE_Y  = 2'd0;
  localparam logic [1:0] PLANE_CB = 2'd1;
  localparam logic [1:0] PLANE_CR = 2'd2;
  localparam logic [3:0] PALETTE_PKT_CU_START = 4'h1;
  localparam logic [3:0] PALETTE_PKT_ENTRY_Y  = 4'h2;
  localparam logic [3:0] PALETTE_PKT_INDEX    = 4'h3;
  localparam logic [3:0] PALETTE_PKT_ENTRY_CB = 4'h4;
  localparam logic [3:0] PALETTE_PKT_ENTRY_CR = 4'h5;
  localparam int MAX_CU_SAMPLES = PALETTE_CU_SIZE * PALETTE_CU_SIZE;
  localparam int MAX_PLANE_SAMPLES = CTU_SIZE * CTU_SIZE;
  localparam int PLANE_COUNT_BITS = $clog2(MAX_PLANE_SAMPLES + 1);
  localparam logic [PLANE_COUNT_BITS - 1:0] MAX_CU_SAMPLES_L = MAX_CU_SAMPLES;

  typedef enum logic [2:0] {
    ST_INPUT,
    ST_WAIT_CU,
    ST_FEED_READ,
    ST_FEED_CU,
    ST_DRAIN_CU
  } state_t;

  state_t state_q;
  logic [PLANE_COUNT_BITS - 1:0] y_write_count_q;
  logic [PLANE_COUNT_BITS - 1:0] cb_write_count_q;
  logic [PLANE_COUNT_BITS - 1:0] cr_write_count_q;
  logic [7:0] drain_cu_index_q;
  logic [7:0] feed_sample_q;
  logic [3:0] coded_cu_count_x;
  logic [3:0] coded_cu_count_y;
  logic [7:0] root_leaf_count_value;
  logic [7:0] input_sample_8bit;
  logic input_valid;
  logic input_last_cr;
  logic [PLANE_COUNT_BITS - 1:0] drain_cu_order_index_ext_w;
  logic [PLANE_COUNT_BITS - 1:0] feed_sample_ext_w;
  logic drain_cu_selected;
  logic drain_cu_is_last_selected;
  logic [15:0] drain_origin_x;
  logic [15:0] drain_origin_y;
  logic [15:0] drain_origin_x_q;
  logic [15:0] drain_origin_y_q;
  logic        drain_cu_is_last_selected_q;
  logic [15:0] feed_x;
  logic [15:0] feed_y;
  logic [15:0] feed_abs_x;
  logic [15:0] feed_abs_y;
  logic [PLANE_COUNT_BITS - 1:0] feed_frame_index;
  logic [3:0] visible_cu_cols_w;
  logic [3:0] visible_cu_rows_w;
  logic [2:0] drain_cu_col_w;
  logic [2:0] drain_cu_row_w;
  logic       drain_cu_order_valid_w;
  logic [5:0] drain_cu_order_index_w;
  logic [7:0] feed_y_sample;
  logic [7:0] feed_cb_sample;
  logic [7:0] feed_cr_sample;
  logic [7:0] feed_y_sample_q;
  logic [7:0] feed_cb_sample_q;
  logic [7:0] feed_cr_sample_q;
  logic       feed_sample_last_q;
  logic       feed_sample_valid_q;
  logic cu_s_axis_valid;
  logic cu_s_axis_ready;
  logic cu_s_axis_last;
  logic cu_m_axis_valid;
  logic cu_m_axis_ready;
  logic [31:0] cu_m_axis_data;
  logic cu_m_axis_last;

  (* ram_style = "block" *) logic [7:0] frame_y [0:MAX_PLANE_SAMPLES - 1];
  (* ram_style = "block" *) logic [7:0] frame_cb [0:MAX_PLANE_SAMPLES - 1];
  (* ram_style = "block" *) logic [7:0] frame_cr [0:MAX_PLANE_SAMPLES - 1];

  assign coded_cu_count_x = (ctu_coded_width + 16'd7) >> 3;
  assign coded_cu_count_y = (ctu_coded_height + 16'd7) >> 3;
  always @* begin
    case (coded_cu_count_y)
      4'd0: root_leaf_count_value = 8'd0;
      4'd1: root_leaf_count_value = {4'd0, coded_cu_count_x};
      4'd2: root_leaf_count_value = {3'd0, coded_cu_count_x, 1'b0};
      4'd3: root_leaf_count_value = {3'd0, coded_cu_count_x, 1'b0} +
                                     {4'd0, coded_cu_count_x};
      4'd4: root_leaf_count_value = {2'd0, coded_cu_count_x, 2'b00};
      4'd5: root_leaf_count_value = {2'd0, coded_cu_count_x, 2'b00} +
                                     {4'd0, coded_cu_count_x};
      4'd6: root_leaf_count_value = {2'd0, coded_cu_count_x, 2'b00} +
                                     {3'd0, coded_cu_count_x, 1'b0};
      4'd7: root_leaf_count_value = {1'd0, coded_cu_count_x, 3'b000} -
                                     {4'd0, coded_cu_count_x};
      default: root_leaf_count_value = {1'd0, coded_cu_count_x, 3'b000};
    endcase
  end
  assign symbol_count = enable ? root_leaf_count_value : 8'd0;

  assign input_valid = s_axis_valid && s_axis_ready;
  assign input_sample_8bit = (SAMPLE_BITS <= 8) ? s_axis_sample[7:0] :
                             (s_axis_sample >> (SAMPLE_BITS - 8));
  assign input_last_cr = input_valid && s_axis_last && (s_axis_plane == PLANE_CR);
  assign s_axis_ready = enable && (state_q == ST_INPUT);

  assign cu_request_ready = enable && (state_q == ST_WAIT_CU);
  assign drain_cu_selected = 1'b1;
  assign drain_cu_is_last_selected = drain_cu_is_last_selected_q;

  always @* begin
    drain_origin_x = drain_origin_x_q;
    drain_origin_y = drain_origin_y_q;
  end

  assign feed_x = {13'd0, feed_sample_q[2:0]};
  assign feed_y = {13'd0, feed_sample_q[5:3]};
  assign feed_abs_x = drain_origin_x + feed_x;
  assign feed_abs_y = drain_origin_y + feed_y;
  assign visible_cu_cols_w = coded_cu_count_x;
  assign visible_cu_rows_w = coded_cu_count_y;
  assign drain_cu_col_w = drain_origin_x_q[5:3];
  assign drain_cu_row_w = drain_origin_y_q[5:3];
  assign drain_cu_order_index_ext_w =
    {{(PLANE_COUNT_BITS - 6){1'b0}}, drain_cu_order_index_w};
  assign feed_sample_ext_w = {{(PLANE_COUNT_BITS - 8){1'b0}}, feed_sample_q};
  // H.266 7.3.11.4 coding_tree() leaf traversal requests the CU payload by
  // origin. The input stream is the compact fixed-8x8 TU order used by the
  // top-level interface, so address the stored block by origin rather than by
  // request ordinal.
  assign feed_frame_index =
    ((drain_cu_order_valid_w ? drain_cu_order_index_ext_w : '0) *
     MAX_CU_SAMPLES_L) + feed_sample_ext_w;
  assign feed_y_sample = feed_y_sample_q;
  assign feed_cb_sample = feed_cb_sample_q;
  assign feed_cr_sample = feed_cr_sample_q;
  assign cu_s_axis_valid = (state_q == ST_FEED_CU) && feed_sample_valid_q;
  assign cu_s_axis_last = feed_sample_last_q;
  assign cu_m_axis_ready = m_axis_ready;
  assign m_axis_valid = cu_m_axis_valid;
  assign m_axis_data = cu_m_axis_data;
  assign m_axis_last = cu_m_axis_last && drain_cu_is_last_selected;
  assign m_axis_cu_last = cu_m_axis_last;

  ff_vvc_tu_order_8x8 palette_input_order (
    .visible_cols(visible_cu_cols_w),
    .visible_rows(visible_cu_rows_w),
    .sample_col(drain_cu_col_w),
    .sample_row(drain_cu_row_w),
    .target_index(6'd0),
    .sample_valid(drain_cu_order_valid_w),
    .sample_index(drain_cu_order_index_w),
    .target_valid(),
    .target_col(),
    .target_row()
  );

  ff_vvc_palette_cu_symbolizer #(
    .CU_SIZE(PALETTE_CU_SIZE)
  ) cu_symbolizer (
    .clk(clk),
    .rst_n(rst_n),
    .clear(clear || !enable),
    .enable(enable),
    .cu_selected(drain_cu_selected),
    .s_axis_valid(cu_s_axis_valid),
    .s_axis_ready(cu_s_axis_ready),
    .s_axis_y(feed_y_sample),
    .s_axis_cb(feed_cb_sample),
    .s_axis_cr(feed_cr_sample),
    .s_axis_last(cu_s_axis_last),
    .m_axis_valid(cu_m_axis_valid),
    .m_axis_ready(cu_m_axis_ready),
    .m_axis_data(cu_m_axis_data),
    .m_axis_last(cu_m_axis_last)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_INPUT;
      y_write_count_q <= '0;
      cb_write_count_q <= '0;
      cr_write_count_q <= '0;
      drain_cu_index_q <= 8'd0;
      feed_sample_q <= 8'd0;
      drain_origin_x_q <= 16'd0;
      drain_origin_y_q <= 16'd0;
      drain_cu_is_last_selected_q <= 1'b0;
      feed_sample_last_q <= 1'b0;
      feed_sample_valid_q <= 1'b0;
    end else if (clear || !enable) begin
      state_q <= ST_INPUT;
      y_write_count_q <= '0;
      cb_write_count_q <= '0;
      cr_write_count_q <= '0;
      drain_cu_index_q <= 8'd0;
      feed_sample_q <= 8'd0;
      drain_origin_x_q <= 16'd0;
      drain_origin_y_q <= 16'd0;
      drain_cu_is_last_selected_q <= 1'b0;
      feed_sample_last_q <= 1'b0;
      feed_sample_valid_q <= 1'b0;
    end else begin
      if (input_valid) begin
        case (s_axis_plane)
          PLANE_Y: begin
            y_write_count_q <= y_write_count_q + {{(PLANE_COUNT_BITS - 1){1'b0}}, 1'b1};
          end
          PLANE_CB: begin
            cb_write_count_q <= cb_write_count_q + {{(PLANE_COUNT_BITS - 1){1'b0}}, 1'b1};
          end
          default: begin
            cr_write_count_q <= cr_write_count_q + {{(PLANE_COUNT_BITS - 1){1'b0}}, 1'b1};
          end
        endcase
        if (input_last_cr) begin
          state_q <= ST_WAIT_CU;
          drain_cu_index_q <= 8'd0;
          feed_sample_q <= 8'd0;
        end
      end

      if (!input_valid) begin
        case (state_q)
          ST_INPUT: begin
          end

          ST_WAIT_CU: begin
            if (cu_request_valid && cu_request_ready) begin
              drain_origin_x_q <= cu_request_origin_x;
              drain_origin_y_q <= cu_request_origin_y;
              drain_cu_is_last_selected_q <= cu_request_last;
              state_q <= ST_FEED_READ;
              feed_sample_q <= 8'd0;
              feed_sample_valid_q <= 1'b0;
            end
          end

          ST_FEED_READ: begin
            feed_sample_last_q <= feed_sample_q == (MAX_CU_SAMPLES - 1);
            feed_sample_valid_q <= 1'b1;
            state_q <= ST_FEED_CU;
          end

          ST_FEED_CU: begin
            if (cu_s_axis_ready && feed_sample_valid_q) begin
              if (cu_s_axis_last) begin
                state_q <= ST_DRAIN_CU;
                feed_sample_q <= 8'd0;
                feed_sample_valid_q <= 1'b0;
              end else begin
                feed_sample_q <= feed_sample_q + 8'd1;
                feed_sample_valid_q <= 1'b0;
                state_q <= ST_FEED_READ;
              end
            end
          end

          ST_DRAIN_CU: begin
            if (cu_m_axis_valid && cu_m_axis_ready && cu_m_axis_last) begin
              if (drain_cu_is_last_selected) begin
                state_q <= ST_INPUT;
                drain_cu_index_q <= 8'd0;
              end else begin
                state_q <= ST_WAIT_CU;
                drain_cu_index_q <= drain_cu_index_q + 8'd1;
              end
            end
          end

          default: begin
            state_q <= ST_INPUT;
          end
        endcase
      end
    end
  end

  always_ff @(posedge clk) begin
    if (input_valid) begin
      case (s_axis_plane)
        PLANE_Y: begin
          frame_y[y_write_count_q] <= input_sample_8bit;
        end
        PLANE_CB: begin
          frame_cb[cb_write_count_q] <= input_sample_8bit;
        end
        default: begin
          frame_cr[cr_write_count_q] <= input_sample_8bit;
        end
      endcase
    end

    if (!input_valid && (state_q == ST_FEED_READ)) begin
      feed_y_sample_q <= frame_y[feed_frame_index];
      feed_cb_sample_q <= frame_cb[feed_frame_index];
      feed_cr_sample_q <= frame_cr[feed_frame_index];
    end
  end
endmodule
