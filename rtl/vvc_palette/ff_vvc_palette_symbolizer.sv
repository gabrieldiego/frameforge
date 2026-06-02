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

  typedef enum logic [2:0] {
    ST_INPUT,
    ST_WAIT_CU,
    ST_FEED_CU,
    ST_DRAIN_CU
  } state_t;

  state_t state_q;
  logic [PLANE_COUNT_BITS - 1:0] y_write_count_q;
  logic [PLANE_COUNT_BITS - 1:0] cb_write_count_q;
  logic [PLANE_COUNT_BITS - 1:0] cr_write_count_q;
  logic [7:0] drain_cu_index_q;
  logic [7:0] feed_sample_q;
  logic [15:0] coded_cu_count_x;
  logic [15:0] coded_cu_count_y;
  logic [15:0] root_leaf_count_value;
  logic [7:0] last_symbol_index;
  logic [7:0] input_sample_8bit;
  logic input_valid;
  logic input_last_cr;
  logic drain_cu_selected;
  logic drain_cu_is_last_selected;
  logic selected_after_current;
  logic [15:0] drain_origin_x;
  logic [15:0] drain_origin_y;
  logic [15:0] drain_origin_x_q;
  logic [15:0] drain_origin_y_q;
  logic        drain_cu_is_last_selected_q;
  logic [7:0] drain_index_in_32;
  logic [7:0] drain_index_in_16;
  logic [15:0] feed_x;
  logic [15:0] feed_y;
  logic [15:0] feed_abs_x;
  logic [15:0] feed_abs_y;
  logic [31:0] feed_frame_index;
  logic [7:0] feed_y_sample;
  logic [7:0] feed_cb_sample;
  logic [7:0] feed_cr_sample;
  logic cu_s_axis_valid;
  logic cu_s_axis_ready;
  logic cu_s_axis_last;
  logic cu_m_axis_valid;
  logic cu_m_axis_ready;
  logic [31:0] cu_m_axis_data;
  logic cu_m_axis_last;

  logic [7:0] frame_y [0:MAX_PLANE_SAMPLES - 1];
  logic [7:0] frame_cb [0:MAX_PLANE_SAMPLES - 1];
  logic [7:0] frame_cr [0:MAX_PLANE_SAMPLES - 1];

  assign coded_cu_count_x = (ctu_coded_width + PALETTE_CU_SIZE - 1) / PALETTE_CU_SIZE;
  assign coded_cu_count_y = (ctu_coded_height + PALETTE_CU_SIZE - 1) / PALETTE_CU_SIZE;
  assign root_leaf_count_value = coded_cu_count_x * coded_cu_count_y;
  assign symbol_count = enable ? root_leaf_count_value[7:0] : 8'd0;
  assign last_symbol_index = symbol_count == 8'd0 ? 8'd0 : symbol_count - 8'd1;

  assign input_valid = s_axis_valid && s_axis_ready;
  assign input_sample_8bit = (SAMPLE_BITS <= 8) ? s_axis_sample[7:0] :
                             (s_axis_sample >> (SAMPLE_BITS - 8));
  assign input_last_cr = input_valid && s_axis_last && (s_axis_plane == PLANE_CR);
  assign s_axis_ready = enable && (state_q == ST_INPUT);

  assign cu_request_ready = enable && (state_q == ST_WAIT_CU);
  assign drain_cu_selected = 1'b1;
  assign drain_cu_is_last_selected = drain_cu_is_last_selected_q;

  always @* begin
    selected_after_current = 1'b0;
    for (int i = 0; i < MAX_PALETTE_SYMBOLS; i = i + 1) begin
      if ((i > drain_cu_index_q) && cu_select_mask[MAX_PALETTE_SYMBOLS - 1 - i]) begin
        selected_after_current = 1'b1;
      end
    end
  end

  always @* begin
    drain_origin_x = drain_origin_x_q;
    drain_origin_y = drain_origin_y_q;
    drain_index_in_32 = drain_cu_index_q;
    drain_index_in_16 = drain_cu_index_q;
  end

  assign feed_x = {13'd0, feed_sample_q[2:0]};
  assign feed_y = {13'd0, feed_sample_q[5:3]};
  assign feed_abs_x = drain_origin_x + feed_x;
  assign feed_abs_y = drain_origin_y + feed_y;
  assign feed_frame_index = (feed_abs_y * ctu_coded_width) + feed_abs_x;
  assign feed_y_sample = frame_y[feed_frame_index];
  assign feed_cb_sample = frame_cb[feed_frame_index];
  assign feed_cr_sample = frame_cr[feed_frame_index];
  assign cu_s_axis_valid = (state_q == ST_FEED_CU);
  assign cu_s_axis_last = feed_sample_q == (MAX_CU_SAMPLES - 1);
  assign cu_m_axis_ready = m_axis_ready;
  assign m_axis_valid = cu_m_axis_valid;
  assign m_axis_data = cu_m_axis_data;
  assign m_axis_last = cu_m_axis_last && drain_cu_is_last_selected;
  assign m_axis_cu_last = cu_m_axis_last;

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
    end else begin
      if (input_valid) begin
        case (s_axis_plane)
          PLANE_Y: begin
            frame_y[y_write_count_q] <= input_sample_8bit;
            y_write_count_q <= y_write_count_q + {{(PLANE_COUNT_BITS - 1){1'b0}}, 1'b1};
          end
          PLANE_CB: begin
            frame_cb[cb_write_count_q] <= input_sample_8bit;
            cb_write_count_q <= cb_write_count_q + {{(PLANE_COUNT_BITS - 1){1'b0}}, 1'b1};
          end
          default: begin
            frame_cr[cr_write_count_q] <= input_sample_8bit;
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
              state_q <= ST_FEED_CU;
              feed_sample_q <= 8'd0;
            end
          end

          ST_FEED_CU: begin
            if (cu_s_axis_ready) begin
              if (cu_s_axis_last) begin
                state_q <= ST_DRAIN_CU;
                feed_sample_q <= 8'd0;
              end else begin
                feed_sample_q <= feed_sample_q + 8'd1;
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
endmodule
