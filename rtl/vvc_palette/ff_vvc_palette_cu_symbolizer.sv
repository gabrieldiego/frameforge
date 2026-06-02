`timescale 1ns/1ps

module ff_vvc_palette_cu_symbolizer #(
  parameter int CU_SIZE = 8,
  parameter int MAX_PALETTE_ENTRIES = 31
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        clear,
  input  logic        enable,
  input  logic        cu_selected,
  input  logic        s_axis_valid,
  output logic        s_axis_ready,
  input  logic [7:0]  s_axis_y,
  input  logic [7:0]  s_axis_cb,
  input  logic [7:0]  s_axis_cr,
  input  logic        s_axis_last,
  output logic        m_axis_valid,
  input  logic        m_axis_ready,
  output logic [31:0] m_axis_data,
  output logic        m_axis_last
);
  localparam logic [3:0] PALETTE_PKT_CU_START = 4'h1;
  localparam logic [3:0] PALETTE_PKT_ENTRY_Y  = 4'h2;
  localparam logic [3:0] PALETTE_PKT_INDEX    = 4'h3;
  localparam logic [3:0] PALETTE_PKT_ENTRY_CB = 4'h4;
  localparam logic [3:0] PALETTE_PKT_ENTRY_CR = 4'h5;
  localparam int MAX_CU_SAMPLES = CU_SIZE * CU_SIZE;

  typedef enum logic [2:0] {
    ST_BUILD,
    ST_DRAIN_START,
    ST_DRAIN_ENTRY_Y,
    ST_DRAIN_ENTRY_CB,
    ST_DRAIN_ENTRY_CR,
    ST_DRAIN_INDEX
  } state_t;

  state_t state_q;
  logic [7:0] palette_size_q;
  logic [7:0] sample_count_q;
  logic [7:0] drain_entry_q;
  logic [7:0] drain_sample_q;
  logic [7:0] entry_y [0:MAX_PALETTE_ENTRIES - 1];
  logic [7:0] entry_cb [0:MAX_PALETTE_ENTRIES - 1];
  logic [7:0] entry_cr [0:MAX_PALETTE_ENTRIES - 1];
  logic [7:0] indices [0:MAX_CU_SAMPLES - 1];
  logic found;
  logic [7:0] found_index;
  logic [7:0] scan_y;
  logic [7:0] scan_x;
  logic [7:0] scan_index;
  logic accepted_sample;

  assign s_axis_ready = enable && (state_q == ST_BUILD);
  assign accepted_sample = s_axis_valid && s_axis_ready;
  assign scan_y = {5'd0, drain_sample_q[5:3]};
  assign scan_x = (drain_sample_q[3] == 1'b0) ?
                  {5'd0, drain_sample_q[2:0]} :
                  (8'd7 - {5'd0, drain_sample_q[2:0]});
  assign scan_index = (scan_y * 8'd8) + scan_x;

  always @* begin
    found = 1'b0;
    found_index = 8'd0;
    for (int entry = 0; entry < MAX_PALETTE_ENTRIES; entry = entry + 1) begin
      if ((entry < palette_size_q) &&
          (entry_y[entry] == s_axis_y) &&
          (entry_cb[entry] == s_axis_cb) &&
          (entry_cr[entry] == s_axis_cr)) begin
        found = 1'b1;
        found_index = entry[7:0];
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_BUILD;
      palette_size_q <= 8'd0;
      sample_count_q <= 8'd0;
      drain_entry_q <= 8'd0;
      drain_sample_q <= 8'd0;
      m_axis_valid <= 1'b0;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;
      for (int i = 0; i < MAX_PALETTE_ENTRIES; i = i + 1) begin
        entry_y[i] <= 8'd0;
        entry_cb[i] <= 8'd0;
        entry_cr[i] <= 8'd0;
      end
      for (int i = 0; i < MAX_CU_SAMPLES; i = i + 1) begin
        indices[i] <= 8'd0;
      end
    end else if (clear || !enable) begin
      state_q <= ST_BUILD;
      palette_size_q <= 8'd0;
      sample_count_q <= 8'd0;
      drain_entry_q <= 8'd0;
      drain_sample_q <= 8'd0;
      m_axis_valid <= 1'b0;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;
      for (int i = 0; i < MAX_PALETTE_ENTRIES; i = i + 1) begin
        entry_y[i] <= 8'd0;
        entry_cb[i] <= 8'd0;
        entry_cr[i] <= 8'd0;
      end
      for (int i = 0; i < MAX_CU_SAMPLES; i = i + 1) begin
        indices[i] <= 8'd0;
      end
    end else begin
      if (m_axis_valid && m_axis_ready) begin
        m_axis_valid <= 1'b0;
        m_axis_data <= 32'd0;
        m_axis_last <= 1'b0;
      end

      case (state_q)
        ST_BUILD: begin
          if (accepted_sample && cu_selected) begin
            if (found) begin
              indices[sample_count_q] <= found_index;
            end else if (palette_size_q < MAX_PALETTE_ENTRIES) begin
              entry_y[palette_size_q] <= s_axis_y;
              entry_cb[palette_size_q] <= s_axis_cb;
              entry_cr[palette_size_q] <= s_axis_cr;
              indices[sample_count_q] <= palette_size_q;
              palette_size_q <= palette_size_q + 8'd1;
            end else begin
              // TODO: add escape-coded sample support for more than 31 colors per CU.
              indices[sample_count_q] <= 8'd30;
            end
            sample_count_q <= sample_count_q + 8'd1;
          end
          if (accepted_sample && s_axis_last) begin
            state_q <= ST_DRAIN_START;
          end
        end

        ST_DRAIN_START: begin
          if (!m_axis_valid || m_axis_ready) begin
            m_axis_valid <= 1'b1;
            m_axis_data <= {
              PALETTE_PKT_CU_START,
              3'd0,
              cu_selected,
              palette_size_q,
              16'd0
            };
            m_axis_last <= (!cu_selected || (palette_size_q == 8'd0));
            if (!cu_selected || (palette_size_q == 8'd0)) begin
              state_q <= ST_BUILD;
              palette_size_q <= 8'd0;
              sample_count_q <= 8'd0;
            end else begin
              state_q <= ST_DRAIN_ENTRY_Y;
              drain_entry_q <= 8'd0;
            end
          end
        end

        ST_DRAIN_ENTRY_Y: begin
          if (!m_axis_valid || m_axis_ready) begin
            m_axis_valid <= 1'b1;
            m_axis_data <= {PALETTE_PKT_ENTRY_Y, 20'd0, entry_y[drain_entry_q]};
            m_axis_last <= 1'b0;
            if ((drain_entry_q + 8'd1) >= palette_size_q) begin
              state_q <= ST_DRAIN_ENTRY_CB;
              drain_entry_q <= 8'd0;
            end else begin
              drain_entry_q <= drain_entry_q + 8'd1;
            end
          end
        end

        ST_DRAIN_ENTRY_CB: begin
          if (!m_axis_valid || m_axis_ready) begin
            m_axis_valid <= 1'b1;
            m_axis_data <= {PALETTE_PKT_ENTRY_CB, 20'd0, entry_cb[drain_entry_q]};
            m_axis_last <= 1'b0;
            if ((drain_entry_q + 8'd1) >= palette_size_q) begin
              state_q <= ST_DRAIN_ENTRY_CR;
              drain_entry_q <= 8'd0;
            end else begin
              drain_entry_q <= drain_entry_q + 8'd1;
            end
          end
        end

        ST_DRAIN_ENTRY_CR: begin
          if (!m_axis_valid || m_axis_ready) begin
            m_axis_valid <= 1'b1;
            m_axis_data <= {PALETTE_PKT_ENTRY_CR, 20'd0, entry_cr[drain_entry_q]};
            m_axis_last <= (palette_size_q <= 8'd1) &&
                           ((drain_entry_q + 8'd1) >= palette_size_q);
            if ((drain_entry_q + 8'd1) >= palette_size_q) begin
              if (palette_size_q <= 8'd1) begin
                state_q <= ST_BUILD;
                palette_size_q <= 8'd0;
                sample_count_q <= 8'd0;
              end else begin
                state_q <= ST_DRAIN_INDEX;
                drain_sample_q <= 8'd0;
              end
            end else begin
              drain_entry_q <= drain_entry_q + 8'd1;
            end
          end
        end

        ST_DRAIN_INDEX: begin
          if (!m_axis_valid || m_axis_ready) begin
            m_axis_valid <= 1'b1;
            m_axis_data <= {PALETTE_PKT_INDEX, 20'd0, indices[scan_index]};
            m_axis_last <= (drain_sample_q + 8'd1) >= sample_count_q;
            if ((drain_sample_q + 8'd1) >= sample_count_q) begin
              state_q <= ST_BUILD;
              palette_size_q <= 8'd0;
              sample_count_q <= 8'd0;
              drain_sample_q <= 8'd0;
            end else begin
              drain_sample_q <= drain_sample_q + 8'd1;
            end
          end
        end

        default: begin
          state_q <= ST_BUILD;
        end
      endcase
    end
  end
endmodule
