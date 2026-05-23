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
  input  logic [15:0] ctu_visible_width,
  input  logic [15:0] ctu_visible_height,
  input  logic [15:0] ctu_coded_width,
  input  logic [15:0] ctu_coded_height,
  input  logic [MAX_PALETTE_SYMBOLS - 1:0] cu_select_mask,
  input  logic        sample_valid,
  input  logic [1:0]  sample_plane,
  input  logic [SAMPLE_BITS - 1:0] sample,
  input  logic        s_axis_valid,
  output logic        s_axis_ready,
  input  logic [1:0]  s_axis_plane,
  input  logic [SAMPLE_BITS - 1:0] s_axis_sample,
  input  logic        s_axis_last,
  output logic        m_axis_valid,
  input  logic        m_axis_ready,
  output logic [31:0] m_axis_data,
  output logic        m_axis_last,
  output logic [7:0]  symbol_count
);
  localparam logic [1:0] PLANE_Y  = 2'd0;
  localparam logic [1:0] PLANE_CB = 2'd1;
  localparam logic [1:0] PLANE_CR = 2'd2;

  logic [7:0] symbol_y [0:MAX_PALETTE_SYMBOLS - 1];
  logic [7:0] symbol_cb [0:MAX_PALETTE_SYMBOLS - 1];
  logic [7:0] symbol_cr [0:MAX_PALETTE_SYMBOLS - 1];
  logic [1:0] tracked_plane_q;
  logic [15:0] tracked_x_q;
  logic [15:0] tracked_y_q;
  logic [15:0] sample_x;
  logic [15:0] sample_y;
  logic        input_valid;
  logic [1:0]  input_plane;
  logic [SAMPLE_BITS - 1:0] input_sample;
  logic [7:0]  anchor_index;
  logic [7:0]  visible_symbol_count;
  logic [7:0]  last_symbol_index;
  logic [7:0]  last_visible_symbol_index;
  logic        start_drain;
  logic        drain_symbol_selected;
  logic        drain_active_q;
  logic [7:0]  drain_index_q;
  logic [7:0]  drain_symbol_index;

  assign symbol_count =
    enable ? (palette_cu_count_x(ctu_coded_width) * palette_cu_count_y(ctu_coded_height)) : 8'd0;
  assign visible_symbol_count =
    enable ? (palette_cu_count_x(ctu_visible_width) * palette_cu_count_y(ctu_visible_height)) : 8'd0;
  assign s_axis_ready = enable && (!m_axis_valid || m_axis_ready);
  assign input_valid = sample_valid || (s_axis_valid && s_axis_ready);
  assign input_plane = sample_valid ? sample_plane : s_axis_plane;
  assign input_sample = sample_valid ? sample : s_axis_sample;
  assign anchor_index = symbol_index_xy(sample_x, sample_y);
  assign last_symbol_index = symbol_count == 8'd0 ? 8'd0 : symbol_count - 8'd1;
  assign last_visible_symbol_index = visible_symbol_count == 8'd0 ? 8'd0 : visible_symbol_count - 8'd1;
  assign start_drain = input_valid && is_symbol_anchor_xy(sample_x, sample_y) &&
                       (input_plane == PLANE_CR) && (anchor_index == last_visible_symbol_index);
  assign drain_symbol_index = coding_order_symbol_index(drain_index_q);
  assign drain_symbol_selected = cu_select_mask[MAX_PALETTE_SYMBOLS - 1 - drain_index_q];

  always_comb begin
    if (sample_plane != tracked_plane_q) begin
      sample_x = 16'd0;
      sample_y = 16'd0;
    end else begin
      sample_x = tracked_x_q;
      sample_y = tracked_y_q;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tracked_plane_q <= PLANE_Y;
      tracked_x_q <= 16'd0;
      tracked_y_q <= 16'd0;
      m_axis_valid <= 1'b0;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;
      drain_active_q <= 1'b0;
      drain_index_q <= 8'd0;
      for (int i = 0; i < MAX_PALETTE_SYMBOLS; i = i + 1) begin
        symbol_y[i] <= 8'd0;
        symbol_cb[i] <= 8'd0;
        symbol_cr[i] <= 8'd0;
      end
    end else if (clear || !enable) begin
      tracked_plane_q <= PLANE_Y;
      tracked_x_q <= 16'd0;
      tracked_y_q <= 16'd0;
      m_axis_valid <= 1'b0;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;
      drain_active_q <= 1'b0;
      drain_index_q <= 8'd0;
      for (int i = 0; i < MAX_PALETTE_SYMBOLS; i = i + 1) begin
        symbol_y[i] <= 8'd0;
        symbol_cb[i] <= 8'd0;
        symbol_cr[i] <= 8'd0;
      end
    end else begin
      if (m_axis_valid && m_axis_ready) begin
        m_axis_valid <= 1'b0;
        m_axis_data <= 32'd0;
        m_axis_last <= 1'b0;
      end
      if (drain_active_q && (!m_axis_valid || m_axis_ready)) begin
        m_axis_valid <= 1'b1;
        m_axis_data <= {
          7'd0,
          drain_symbol_selected,
          symbol_y[drain_symbol_index],
          symbol_cb[drain_symbol_index],
          symbol_cr[drain_symbol_index]
        };
        m_axis_last <= drain_index_q == last_symbol_index;
        if (drain_index_q == last_symbol_index) begin
          drain_active_q <= 1'b0;
          drain_index_q <= 8'd0;
        end else begin
          drain_index_q <= drain_index_q + 8'd1;
        end
      end
      if (input_valid) begin
        if (is_symbol_anchor_xy(sample_x, sample_y)) begin
          case (input_plane)
            PLANE_Y: begin
              symbol_y[anchor_index] <= sample_to_8bit(input_sample);
            end
            PLANE_CB: begin
              symbol_cb[anchor_index] <= sample_to_8bit(input_sample);
            end
            PLANE_CR: begin
              symbol_cr[anchor_index] <= sample_to_8bit(input_sample);
            end
            default: begin
            end
          endcase
        end
        if (start_drain) begin
          drain_active_q <= 1'b1;
          drain_index_q <= 8'd0;
        end
        tracked_plane_q <= input_plane;
        if (sample_x + 16'd1 >= ctu_visible_width) begin
          tracked_x_q <= 16'd0;
          tracked_y_q <= sample_y + 16'd1;
        end else begin
          tracked_x_q <= sample_x + 16'd1;
          tracked_y_q <= sample_y;
        end
      end
    end
  end

  function automatic logic is_symbol_anchor_xy(
    input logic [15:0] x,
    input logic [15:0] y
  );
    begin
      is_symbol_anchor_xy = ((x % PALETTE_CU_SIZE) == 0) && ((y % PALETTE_CU_SIZE) == 0);
    end
  endfunction

  function automatic logic [7:0] palette_cu_count_x(input logic [15:0] width);
    logic [15:0] count;
    begin
      count = (width + PALETTE_CU_SIZE - 1) / PALETTE_CU_SIZE;
      palette_cu_count_x = count[7:0];
    end
  endfunction

  function automatic logic [7:0] palette_cu_count_y(input logic [15:0] height);
    logic [15:0] count;
    begin
      count = (height + PALETTE_CU_SIZE - 1) / PALETTE_CU_SIZE;
      palette_cu_count_y = count[7:0];
    end
  endfunction

  function automatic logic [7:0] symbol_index_xy(
    input logic [15:0] x,
    input logic [15:0] y
  );
    logic [15:0] tiles_x;
    logic [15:0] index;
    begin
      tiles_x = palette_cu_count_x(ctu_visible_width);
      index = (y / PALETTE_CU_SIZE) * tiles_x + (x / PALETTE_CU_SIZE);
      symbol_index_xy = index[7:0];
    end
  endfunction

  function automatic logic [31:0] coding_order_position(input logic [7:0] index);
    logic [15:0] origin_x;
    logic [15:0] origin_y;
    logic [7:0]  index_in_32;
    logic [7:0]  index_in_16;
    begin
      origin_x = 16'd0;
      origin_y = 16'd0;
      if (ctu_coded_width == 16'd64 && ctu_coded_height == 16'd64) begin
        origin_x = index[4] ? 16'd32 : 16'd0;
        origin_y = index[5] ? 16'd32 : 16'd0;
        index_in_32 = {4'd0, index[3:0]};
      end else begin
        index_in_32 = index;
      end

      if (ctu_coded_width >= 16'd32 && ctu_coded_height >= 16'd32) begin
        origin_x = origin_x + (index_in_32[2] ? 16'd16 : 16'd0);
        origin_y = origin_y + (index_in_32[3] ? 16'd16 : 16'd0);
        index_in_16 = {6'd0, index_in_32[1:0]};
      end else begin
        index_in_16 = index_in_32;
      end

      if (ctu_coded_width >= 16'd16 && ctu_coded_height >= 16'd16) begin
        origin_x = origin_x + (index_in_16[0] ? PALETTE_CU_SIZE : 16'd0);
        origin_y = origin_y + (index_in_16[1] ? PALETTE_CU_SIZE : 16'd0);
      end else begin
        origin_x = index_in_16[2:0] * PALETTE_CU_SIZE;
        origin_y = index_in_16[5:3] * PALETTE_CU_SIZE;
      end

      coding_order_position = {origin_x, origin_y};
    end
  endfunction

  function automatic logic [7:0] coding_order_symbol_index(input logic [7:0] index);
    logic [31:0] pos;
    logic [15:0] clamped_x;
    logic [15:0] clamped_y;
    begin
      pos = coding_order_position(index);
      clamped_x = (pos[31:16] < ctu_visible_width) ? pos[31:16] : ctu_visible_width - 16'd1;
      clamped_y = (pos[15:0] < ctu_visible_height) ? pos[15:0] : ctu_visible_height - 16'd1;
      coding_order_symbol_index = symbol_index_xy(clamped_x, clamped_y);
    end
  endfunction

  function automatic logic [7:0] sample_to_8bit(input logic [SAMPLE_BITS - 1:0] raw);
    begin
      if (SAMPLE_BITS <= 8) begin
        sample_to_8bit = raw[7:0];
      end else begin
        sample_to_8bit = raw >> (SAMPLE_BITS - 8);
      end
    end
  endfunction
endmodule
