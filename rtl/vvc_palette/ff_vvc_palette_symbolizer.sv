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
  localparam logic [3:0] PALETTE_PKT_CU_START            = 4'h1;
  localparam logic [3:0] PALETTE_PKT_ENTRY_Y             = 4'h2;
  localparam logic [3:0] PALETTE_PKT_INDEX               = 4'h3;
  localparam logic [3:0] PALETTE_PKT_ENTRY_CB            = 4'h4;
  localparam logic [3:0] PALETTE_PKT_ENTRY_CR            = 4'h5;
  localparam int MAX_CTU_SAMPLES = CTU_SIZE * CTU_SIZE;
  localparam int MAX_CU_SAMPLES = PALETTE_CU_SIZE * PALETTE_CU_SIZE;
  localparam int MAX_PALETTE_ENTRIES = 31;
  localparam logic [2:0] DRAIN_IDLE  = 3'd0;
  localparam logic [2:0] DRAIN_START = 3'd1;
  localparam logic [2:0] DRAIN_ENTRY_Y = 3'd2;
  localparam logic [2:0] DRAIN_INDEX = 3'd3;
  localparam logic [2:0] DRAIN_ENTRY_CB = 3'd4;
  localparam logic [2:0] DRAIN_ENTRY_CR = 3'd5;

  logic [7:0] plane_y [0:MAX_CTU_SAMPLES - 1];
  logic [7:0] plane_cb [0:MAX_CTU_SAMPLES - 1];
  logic [7:0] plane_cr [0:MAX_CTU_SAMPLES - 1];
  logic [7:0] cu_entry_y [0:MAX_PALETTE_ENTRIES - 1];
  logic [7:0] cu_entry_cb [0:MAX_PALETTE_ENTRIES - 1];
  logic [7:0] cu_entry_cr [0:MAX_PALETTE_ENTRIES - 1];
  logic [7:0] cu_indices [0:MAX_CU_SAMPLES - 1];
  logic [1:0] tracked_plane_q;
  logic [15:0] tracked_x_q;
  logic [15:0] tracked_y_q;
  logic [15:0] sample_x;
  logic [15:0] sample_y;
  logic [15:0] selected_width;
  logic [15:0] selected_height;
  logic [15:0] input_sample_index;
  logic        input_valid;
  logic        input_last;
  logic [1:0]  input_plane;
  logic [SAMPLE_BITS - 1:0] input_sample;
  logic [7:0]  anchor_index;
  logic [7:0]  selected_cu_count_x;
  logic [7:0]  selected_cu_count_y;
  logic [7:0]  visible_symbol_count;
  logic [15:0] root_size_value;
  logic [15:0] root_leaf_count_value;
  logic [7:0]  last_symbol_index;
  logic        start_drain;
  logic        drain_symbol_selected;
  logic [2:0]  drain_state_q;
  logic [7:0]  drain_index_q;
  logic [7:0]  drain_symbol_index;
  logic [7:0]  drain_entry_index_q;
  logic [7:0]  drain_sample_index_q;
  logic [7:0]  cu_palette_size_q;
  logic [7:0]  cu_sample_count_q;

  assign symbol_count = enable ? root_leaf_count_value[7:0] : 8'd0;
  assign visible_symbol_count =
    enable ? (selected_cu_count_x * selected_cu_count_y) : 8'd0;
  assign s_axis_ready = enable && (!m_axis_valid || m_axis_ready);
  assign input_valid = s_axis_valid && s_axis_ready;
  assign input_last = s_axis_last && s_axis_valid && s_axis_ready;
  assign input_plane = s_axis_plane;
  assign input_sample = s_axis_sample;
  assign anchor_index = symbol_index_xy(sample_x, sample_y);
  assign last_symbol_index = symbol_count == 8'd0 ? 8'd0 : symbol_count - 8'd1;
  assign selected_width = {8'd0, selected_cu_count_x} * PALETTE_CU_SIZE;
  assign selected_height = {8'd0, selected_cu_count_y} * PALETTE_CU_SIZE;
  assign input_sample_index = (sample_y * selected_width) + sample_x;
  assign start_drain = input_valid && input_last && (input_plane == PLANE_CR);
  assign drain_symbol_index = coding_order_symbol_index(drain_index_q);
  assign drain_symbol_selected = cu_select_mask[MAX_PALETTE_SYMBOLS - 1 - drain_index_q];

  always_comb begin
    logic [31:0] pos;
    logic [7:0] idx;
    logic [15:0] root_cus_per_side;

    root_size_value = CTU_SIZE;
    root_cus_per_side = root_size_value / PALETTE_CU_SIZE;
    root_leaf_count_value = root_cus_per_side * root_cus_per_side;
    selected_cu_count_x = 8'd0;
    selected_cu_count_y = 8'd0;
    for (int i = 0; i < MAX_PALETTE_SYMBOLS; i = i + 1) begin
      if (cu_select_mask[MAX_PALETTE_SYMBOLS - 1 - i]) begin
        idx = i;
        pos = coding_order_position(idx);
        if (((pos[31:16] / PALETTE_CU_SIZE) + 1) > selected_cu_count_x) begin
          selected_cu_count_x = ((pos[31:16] / PALETTE_CU_SIZE) + 1);
        end
        if (((pos[15:0] / PALETTE_CU_SIZE) + 1) > selected_cu_count_y) begin
          selected_cu_count_y = ((pos[15:0] / PALETTE_CU_SIZE) + 1);
        end
      end
    end
  end

  always_comb begin
    if (input_plane != tracked_plane_q) begin
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
      drain_state_q <= DRAIN_IDLE;
      drain_index_q <= 8'd0;
      drain_entry_index_q <= 8'd0;
      drain_sample_index_q <= 8'd0;
      cu_palette_size_q <= 8'd0;
      cu_sample_count_q <= 8'd0;
      for (int i = 0; i < MAX_CTU_SAMPLES; i = i + 1) begin
        plane_y[i] <= 8'd0;
        plane_cb[i] <= 8'd0;
        plane_cr[i] <= 8'd0;
      end
      for (int i = 0; i < MAX_PALETTE_ENTRIES; i = i + 1) begin
        cu_entry_y[i] <= 8'd0;
        cu_entry_cb[i] <= 8'd0;
        cu_entry_cr[i] <= 8'd0;
      end
      for (int i = 0; i < MAX_CU_SAMPLES; i = i + 1) begin
        cu_indices[i] <= 8'd0;
      end
    end else if (clear || !enable) begin
      tracked_plane_q <= PLANE_Y;
      tracked_x_q <= 16'd0;
      tracked_y_q <= 16'd0;
      m_axis_valid <= 1'b0;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;
      drain_state_q <= DRAIN_IDLE;
      drain_index_q <= 8'd0;
      drain_entry_index_q <= 8'd0;
      drain_sample_index_q <= 8'd0;
      cu_palette_size_q <= 8'd0;
      cu_sample_count_q <= 8'd0;
      for (int i = 0; i < MAX_CTU_SAMPLES; i = i + 1) begin
        plane_y[i] <= 8'd0;
        plane_cb[i] <= 8'd0;
        plane_cr[i] <= 8'd0;
      end
      for (int i = 0; i < MAX_PALETTE_ENTRIES; i = i + 1) begin
        cu_entry_y[i] <= 8'd0;
        cu_entry_cb[i] <= 8'd0;
        cu_entry_cr[i] <= 8'd0;
      end
      for (int i = 0; i < MAX_CU_SAMPLES; i = i + 1) begin
        cu_indices[i] <= 8'd0;
      end
    end else begin
      if (m_axis_valid && m_axis_ready) begin
        m_axis_valid <= 1'b0;
        m_axis_data <= 32'd0;
        m_axis_last <= 1'b0;
      end
      if ((drain_state_q != DRAIN_IDLE) && (!m_axis_valid || m_axis_ready)) begin
        case (drain_state_q)
          DRAIN_START: begin
            m_axis_valid <= 1'b1;
            m_axis_data <= {
              PALETTE_PKT_CU_START,
              3'd0,
              drain_symbol_selected,
              cu_palette_size_q,
              16'd0
            };
            m_axis_last <= (!drain_symbol_selected || (cu_palette_size_q == 8'd0)) &&
                           (drain_index_q == last_symbol_index);
            if (!drain_symbol_selected || (cu_palette_size_q == 8'd0)) begin
              advance_drain_cu(last_symbol_index);
            end else begin
              drain_state_q <= DRAIN_ENTRY_Y;
              drain_entry_index_q <= 8'd0;
            end
          end
          DRAIN_ENTRY_Y: begin
            m_axis_valid <= 1'b1;
            m_axis_data <= {
              PALETTE_PKT_ENTRY_Y,
              20'd0,
              cu_entry_y[drain_entry_index_q]
            };
            m_axis_last <= 1'b0;
            if ((drain_entry_index_q + 8'd1) >= cu_palette_size_q) begin
              drain_state_q <= DRAIN_ENTRY_CB;
              drain_entry_index_q <= 8'd0;
            end else begin
              drain_entry_index_q <= drain_entry_index_q + 8'd1;
            end
          end
          DRAIN_ENTRY_CB: begin
            m_axis_valid <= 1'b1;
            m_axis_data <= {
              PALETTE_PKT_ENTRY_CB,
              20'd0,
              cu_entry_cb[drain_entry_index_q]
            };
            m_axis_last <= 1'b0;
            if ((drain_entry_index_q + 8'd1) >= cu_palette_size_q) begin
              drain_state_q <= DRAIN_ENTRY_CR;
              drain_entry_index_q <= 8'd0;
            end else begin
              drain_entry_index_q <= drain_entry_index_q + 8'd1;
            end
          end
          DRAIN_ENTRY_CR: begin
            m_axis_valid <= 1'b1;
            m_axis_data <= {
              PALETTE_PKT_ENTRY_CR,
              20'd0,
              cu_entry_cr[drain_entry_index_q]
            };
            m_axis_last <= (cu_palette_size_q <= 8'd1) &&
                           ((drain_entry_index_q + 8'd1) >= cu_palette_size_q) &&
                           (drain_index_q == last_symbol_index);
            if ((drain_entry_index_q + 8'd1) >= cu_palette_size_q) begin
              if (cu_palette_size_q <= 8'd1) begin
                advance_drain_cu(last_symbol_index);
              end else begin
                drain_state_q <= DRAIN_INDEX;
                drain_sample_index_q <= 8'd0;
              end
            end else begin
              drain_entry_index_q <= drain_entry_index_q + 8'd1;
            end
          end
          DRAIN_INDEX: begin
            m_axis_valid <= 1'b1;
            m_axis_data <= {
              PALETTE_PKT_INDEX,
              20'd0,
              cu_indices[palette_scan_raster_index(drain_sample_index_q)]
            };
            m_axis_last <= ((drain_sample_index_q + 8'd1) >= cu_sample_count_q) &&
                           (drain_index_q == last_symbol_index);
            if ((drain_sample_index_q + 8'd1) >= cu_sample_count_q) begin
              advance_drain_cu(last_symbol_index);
            end else begin
              drain_sample_index_q <= drain_sample_index_q + 8'd1;
            end
          end
          default: begin
            drain_state_q <= DRAIN_IDLE;
          end
        endcase
      end
      if (input_valid) begin
        case (input_plane)
          PLANE_Y: begin
            plane_y[input_sample_index] <= sample_to_8bit(input_sample);
          end
          PLANE_CB: begin
            plane_cb[input_sample_index] <= sample_to_8bit(input_sample);
          end
          PLANE_CR: begin
            plane_cr[input_sample_index] <= sample_to_8bit(input_sample);
          end
          default: begin
          end
        endcase
        if (start_drain) begin
          build_drain_cu(8'd0);
          drain_state_q <= DRAIN_START;
          drain_index_q <= 8'd0;
        end
        tracked_plane_q <= input_plane;
        if (sample_x + 16'd1 >= selected_width) begin
          tracked_x_q <= 16'd0;
          tracked_y_q <= sample_y + 16'd1;
        end else begin
          tracked_x_q <= sample_x + 16'd1;
          tracked_y_q <= sample_y;
        end
      end
    end
  end

  task automatic advance_drain_cu(input logic [7:0] last_index);
    logic [7:0] next_index;
    begin
      if (drain_index_q == last_index) begin
        drain_state_q <= DRAIN_IDLE;
        drain_index_q <= 8'd0;
      end else begin
        next_index = drain_index_q + 8'd1;
        build_drain_cu(next_index);
        drain_state_q <= DRAIN_START;
        drain_index_q <= next_index;
      end
      drain_entry_index_q <= 8'd0;
      drain_sample_index_q <= 8'd0;
    end
  endtask

  task automatic build_drain_cu(input logic [7:0] coding_index);
    logic [7:0] symbol_index;
    logic [31:0] pos;
    logic [15:0] origin_x;
    logic [15:0] origin_y;
    logic [15:0] frame_width;
    logic [15:0] frame_height;
    logic [15:0] sx;
    logic [15:0] sy;
    logic [15:0] sample_index;
    logic [7:0] y_value;
    logic [7:0] cb_value;
    logic [7:0] cr_value;
    logic [7:0] palette_index;
    logic found;
    logic [7:0] sample_count;
    logic [7:0] palette_size;
    begin
      for (int i = 0; i < MAX_PALETTE_ENTRIES; i = i + 1) begin
        cu_entry_y[i] = 8'd0;
        cu_entry_cb[i] = 8'd0;
        cu_entry_cr[i] = 8'd0;
      end
      for (int i = 0; i < MAX_CU_SAMPLES; i = i + 1) begin
        cu_indices[i] = 8'd0;
      end

      if (!cu_select_mask[MAX_PALETTE_SYMBOLS - 1 - coding_index]) begin
        cu_palette_size_q = 8'd0;
        cu_sample_count_q = 8'd0;
      end else begin
        symbol_index = coding_order_symbol_index(coding_index);
        pos = coding_order_position(coding_index);
        origin_x = pos[31:16];
        origin_y = pos[15:0];
        frame_width = {8'd0, selected_cu_count_x} * PALETTE_CU_SIZE;
        frame_height = {8'd0, selected_cu_count_y} * PALETTE_CU_SIZE;
        sample_count = 8'd0;
        palette_size = 8'd0;

        for (int y_off = 0; y_off < PALETTE_CU_SIZE; y_off = y_off + 1) begin
          for (int x_off = 0; x_off < PALETTE_CU_SIZE; x_off = x_off + 1) begin
            sx = origin_x + x_off[15:0];
            sy = origin_y + y_off[15:0];
            if ((sx < frame_width) && (sy < frame_height)) begin
              sample_index = (sy * frame_width) + sx;
              y_value = plane_y[sample_index];
              cb_value = plane_cb[sample_index];
              if (input_valid && (input_plane == PLANE_CR) && (sample_index == input_sample_index)) begin
                cr_value = sample_to_8bit(input_sample);
              end else begin
                cr_value = plane_cr[sample_index];
              end
              found = 1'b0;
              palette_index = 8'd0;
              for (int entry = 0; entry < MAX_PALETTE_ENTRIES; entry = entry + 1) begin
                if ((entry < palette_size) &&
                    (cu_entry_y[entry] == y_value) &&
                    (cu_entry_cb[entry] == cb_value) &&
                    (cu_entry_cr[entry] == cr_value)) begin
                  found = 1'b1;
                  palette_index = entry[7:0];
                end
              end
              if (!found) begin
                if (palette_size < MAX_PALETTE_ENTRIES) begin
                  cu_entry_y[palette_size] = y_value;
                  cu_entry_cb[palette_size] = cb_value;
                  cu_entry_cr[palette_size] = cr_value;
                  palette_index = palette_size;
                  palette_size = palette_size + 8'd1;
                end else begin
                  // TODO: add escape-coded sample support for more than 31 colors per CU.
                  palette_index = 8'd30;
                end
              end
              cu_indices[sample_count] = palette_index;
              sample_count = sample_count + 8'd1;
            end
          end
        end
        cu_palette_size_q = palette_size;
        cu_sample_count_q = sample_count;
      end
    end
  endtask

  function automatic logic is_symbol_anchor_xy(
    input logic [15:0] x,
    input logic [15:0] y
  );
    begin
      is_symbol_anchor_xy = ((x % PALETTE_CU_SIZE) == 0) && ((y % PALETTE_CU_SIZE) == 0);
    end
  endfunction

  function automatic logic [15:0] selected_sample_width(input logic unused);
    begin
      selected_sample_width = {8'd0, selected_cu_count_x} * PALETTE_CU_SIZE;
    end
  endfunction

  function automatic logic [15:0] selected_sample_height(input logic unused);
    begin
      selected_sample_height = {8'd0, selected_cu_count_y} * PALETTE_CU_SIZE;
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

  function automatic logic [7:0] palette_scan_raster_index(input logic [7:0] scan_index);
    logic [7:0] y;
    logic [7:0] x;
    begin
      y = scan_index >> 3;
      if (y[0] == 1'b0) begin
        x = {5'd0, scan_index[2:0]};
      end else begin
        x = 8'd7 - {5'd0, scan_index[2:0]};
      end
      palette_scan_raster_index = (y * 8'd8) + x;
    end
  endfunction

  function automatic logic [7:0] symbol_index_xy(
    input logic [15:0] x,
    input logic [15:0] y
  );
    logic [15:0] tiles_x;
    logic [15:0] index;
    begin
      tiles_x = selected_cu_count_x;
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
      if (palette_root_size() == 16'd64) begin
        origin_x = index[4] ? 16'd32 : 16'd0;
        origin_y = index[5] ? 16'd32 : 16'd0;
        index_in_32 = {4'd0, index[3:0]};
      end else begin
        index_in_32 = index;
      end

      if (palette_root_size() >= 16'd32) begin
        origin_x = origin_x + (index_in_32[2] ? 16'd16 : 16'd0);
        origin_y = origin_y + (index_in_32[3] ? 16'd16 : 16'd0);
        index_in_16 = {6'd0, index_in_32[1:0]};
      end else begin
        index_in_16 = index_in_32;
      end

      if (palette_root_size() >= 16'd16) begin
        origin_x = origin_x + (index_in_16[0] ? PALETTE_CU_SIZE : 16'd0);
        origin_y = origin_y + (index_in_16[1] ? PALETTE_CU_SIZE : 16'd0);
      end else begin
        origin_x = index_in_16[2:0] * PALETTE_CU_SIZE;
        origin_y = index_in_16[5:3] * PALETTE_CU_SIZE;
      end

      coding_order_position = {origin_x, origin_y};
    end
  endfunction

  function automatic logic [15:0] palette_root_size();
    begin
      palette_root_size = CTU_SIZE;
    end
  endfunction

  function automatic logic [7:0] coding_order_symbol_index(input logic [7:0] index);
    logic [31:0] pos;
    logic [15:0] clamped_x;
    logic [15:0] clamped_y;
    begin
      pos = coding_order_position(index);
      clamped_x = (pos[31:16] < selected_sample_width(1'b0)) ? pos[31:16] : selected_sample_width(1'b0) - 16'd1;
      clamped_y = (pos[15:0] < selected_sample_height(1'b0)) ? pos[15:0] : selected_sample_height(1'b0) - 16'd1;
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
