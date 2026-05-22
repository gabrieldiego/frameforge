`timescale 1ns/1ps

module ff_vvc_palette_symbolizer #(
  parameter int MAX_VISIBLE_WIDTH = 64,
  parameter int MAX_VISIBLE_HEIGHT = 64,
  parameter int SAMPLE_BITS = 8,
  parameter int MAX_PALETTE_SYMBOLS = 64
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        clear,
  input  logic        enable,
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,
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
  output logic [7:0]  symbol_count,
  output logic [(24 * MAX_PALETTE_SYMBOLS) - 1:0] symbol_payload
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
  logic [7:0]  last_symbol_index;
  logic        emit_symbol;

  assign symbol_count =
    enable ? (((visible_width + 16'd7) >> 3) * ((visible_height + 16'd7) >> 3)) : 8'd0;
  assign s_axis_ready = enable && (!m_axis_valid || m_axis_ready);
  assign input_valid = sample_valid || (s_axis_valid && s_axis_ready);
  assign input_plane = sample_valid ? sample_plane : s_axis_plane;
  assign input_sample = sample_valid ? sample : s_axis_sample;
  assign anchor_index = symbol_index_xy(sample_x, sample_y);
  assign last_symbol_index = symbol_count == 8'd0 ? 8'd0 : symbol_count - 8'd1;
  assign emit_symbol = input_valid && is_symbol_anchor_xy(sample_x, sample_y) &&
                       (input_plane == PLANE_CR) && (!m_axis_valid || m_axis_ready);

  always_comb begin
    for (int i = 0; i < MAX_PALETTE_SYMBOLS; i = i + 1) begin
      symbol_payload[((MAX_PALETTE_SYMBOLS - 1 - i) * 24) + 16 +: 8] = symbol_y[i];
      symbol_payload[((MAX_PALETTE_SYMBOLS - 1 - i) * 24) + 8 +: 8] = symbol_cb[i];
      symbol_payload[((MAX_PALETTE_SYMBOLS - 1 - i) * 24) +: 8] = symbol_cr[i];
    end
  end

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
        if (emit_symbol) begin
          m_axis_valid <= 1'b1;
          m_axis_data <= {
            8'd0,
            symbol_y[anchor_index],
            symbol_cb[anchor_index],
            sample_to_8bit(input_sample)
          };
          m_axis_last <= anchor_index == last_symbol_index;
        end
      tracked_plane_q <= input_plane;
      if (sample_x + 16'd1 >= visible_width) begin
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
      is_symbol_anchor_xy = (x[2:0] == 3'd0) && (y[2:0] == 3'd0);
    end
  endfunction

  function automatic logic [7:0] symbol_index_xy(
    input logic [15:0] x,
    input logic [15:0] y
  );
    logic [15:0] tiles_x;
    logic [15:0] index;
    begin
      tiles_x = (visible_width + 16'd7) >> 3;
      index = (y >> 3) * tiles_x + (x >> 3);
      symbol_index_xy = index[7:0];
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
