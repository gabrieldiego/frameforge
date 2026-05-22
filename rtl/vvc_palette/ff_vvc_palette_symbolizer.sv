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

  assign symbol_count =
    enable ? (((visible_width + 16'd7) >> 3) * ((visible_height + 16'd7) >> 3)) : 8'd0;

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
      for (int i = 0; i < MAX_PALETTE_SYMBOLS; i = i + 1) begin
        symbol_y[i] <= 8'd0;
        symbol_cb[i] <= 8'd0;
        symbol_cr[i] <= 8'd0;
      end
    end else if (clear || !enable) begin
      tracked_plane_q <= PLANE_Y;
      tracked_x_q <= 16'd0;
      tracked_y_q <= 16'd0;
      for (int i = 0; i < MAX_PALETTE_SYMBOLS; i = i + 1) begin
        symbol_y[i] <= 8'd0;
        symbol_cb[i] <= 8'd0;
        symbol_cr[i] <= 8'd0;
      end
    end else if (sample_valid) begin
      if (is_symbol_anchor_xy(sample_x, sample_y)) begin
        case (sample_plane)
          PLANE_Y: begin
            symbol_y[symbol_index_xy(sample_x, sample_y)] <= sample_to_8bit(sample);
          end
          PLANE_CB: begin
            symbol_cb[symbol_index_xy(sample_x, sample_y)] <= sample_to_8bit(sample);
          end
          PLANE_CR: begin
            symbol_cr[symbol_index_xy(sample_x, sample_y)] <= sample_to_8bit(sample);
          end
          default: begin
          end
        endcase
      end
      tracked_plane_q <= sample_plane;
      if (sample_x + 16'd1 >= visible_width) begin
        tracked_x_q <= 16'd0;
        tracked_y_q <= sample_y + 16'd1;
      end else begin
        tracked_x_q <= sample_x + 16'd1;
        tracked_y_q <= sample_y;
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
