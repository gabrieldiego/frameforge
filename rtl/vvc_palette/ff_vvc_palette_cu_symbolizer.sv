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
  localparam logic [3:0] PALETTE_PKT_ESCAPE_Y  = 4'h6;
  localparam logic [3:0] PALETTE_PKT_ESCAPE_CB = 4'h7;
  localparam logic [3:0] PALETTE_PKT_ESCAPE_CR = 4'h8;
  localparam int MAX_CU_SAMPLES = CU_SIZE * CU_SIZE;
  localparam int PALETTE_ENTRY_BANK_BITS = 8 * MAX_PALETTE_ENTRIES;
  localparam logic [4:0] MAX_PALETTE_ENTRIES_L = MAX_PALETTE_ENTRIES;

  typedef enum logic [3:0] {
    ST_BUILD,
    ST_DRAIN_START,
    ST_DRAIN_ENTRY_Y,
    ST_DRAIN_ENTRY_CB,
    ST_DRAIN_ENTRY_CR,
    ST_DRAIN_ESCAPE_Y,
    ST_DRAIN_ESCAPE_CB,
    ST_DRAIN_ESCAPE_CR,
    ST_DRAIN_INDEX
  } state_t;

  state_t state_q;
  logic [4:0] palette_size_q;
  logic [6:0] sample_count_q;
  logic [4:0] drain_entry_q;
  logic [6:0] drain_sample_q;
  logic [PALETTE_ENTRY_BANK_BITS - 1:0] entry_y_q;
  logic [PALETTE_ENTRY_BANK_BITS - 1:0] entry_cb_q;
  logic [PALETTE_ENTRY_BANK_BITS - 1:0] entry_cr_q;
  logic [4:0] indices_q [0:MAX_CU_SAMPLES - 1];
  // TODO(area): these full-CU escape banks are temporary. The palette path
  // should eventually stream escape samples toward CABAC in subset order
  // instead of storing 3x64 bytes here and draining them after entries.
  logic [7:0] escape_y_q [0:MAX_CU_SAMPLES - 1];
  logic [7:0] escape_cb_q [0:MAX_CU_SAMPLES - 1];
  logic [7:0] escape_cr_q [0:MAX_CU_SAMPLES - 1];
  logic escape_present_q;
  logic found;
  logic [4:0] found_index;
  logic [2:0] scan_x;
  logic [5:0] scan_index;
  logic accepted_sample;
  integer index_clear_i;

  assign s_axis_ready = enable && (state_q == ST_BUILD);
  assign accepted_sample = s_axis_valid && s_axis_ready;
  assign scan_x = (drain_sample_q[3] == 1'b0) ?
                  drain_sample_q[2:0] :
                  (3'd7 - drain_sample_q[2:0]);
  assign scan_index = {drain_sample_q[5:3], scan_x};
  always @* begin
    found = 1'b0;
    found_index = 5'd0;
    for (int entry = 0; entry < MAX_PALETTE_ENTRIES; entry = entry + 1) begin
      if ((palette_size_q > entry[4:0]) &&
          (entry_y_q[entry * 8 +: 8] == s_axis_y) &&
          (entry_cb_q[entry * 8 +: 8] == s_axis_cb) &&
          (entry_cr_q[entry * 8 +: 8] == s_axis_cr)) begin
        found = 1'b1;
        found_index = entry[4:0];
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_BUILD;
      palette_size_q <= 5'd0;
      sample_count_q <= 7'd0;
      drain_entry_q <= 5'd0;
      drain_sample_q <= 7'd0;
      m_axis_valid <= 1'b0;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;
      entry_y_q <= '0;
      entry_cb_q <= '0;
      entry_cr_q <= '0;
      escape_present_q <= 1'b0;
      for (index_clear_i = 0; index_clear_i < MAX_CU_SAMPLES; index_clear_i = index_clear_i + 1) begin
        indices_q[index_clear_i] <= 5'd0;
        escape_y_q[index_clear_i] <= 8'd0;
        escape_cb_q[index_clear_i] <= 8'd0;
        escape_cr_q[index_clear_i] <= 8'd0;
      end
    end else if (clear || !enable) begin
      state_q <= ST_BUILD;
      palette_size_q <= 5'd0;
      sample_count_q <= 7'd0;
      drain_entry_q <= 5'd0;
      drain_sample_q <= 7'd0;
      m_axis_valid <= 1'b0;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;
      entry_y_q <= '0;
      entry_cb_q <= '0;
      entry_cr_q <= '0;
      escape_present_q <= 1'b0;
      for (index_clear_i = 0; index_clear_i < MAX_CU_SAMPLES; index_clear_i = index_clear_i + 1) begin
        indices_q[index_clear_i] <= 5'd0;
        escape_y_q[index_clear_i] <= 8'd0;
        escape_cb_q[index_clear_i] <= 8'd0;
        escape_cr_q[index_clear_i] <= 8'd0;
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
              indices_q[sample_count_q[5:0]] <= found_index;
            end else if (palette_size_q < MAX_PALETTE_ENTRIES_L) begin
              entry_y_q[palette_size_q * 8 +: 8] <= s_axis_y;
              entry_cb_q[palette_size_q * 8 +: 8] <= s_axis_cb;
              entry_cr_q[palette_size_q * 8 +: 8] <= s_axis_cr;
              indices_q[sample_count_q[5:0]] <= palette_size_q;
              palette_size_q <= palette_size_q + 5'd1;
            end else begin
              // H.266 7.3.11.6 / 7.4.12.6: once the simple first-come
              // palette reaches 31 entries, non-matching samples use
              // MaxPaletteIndex as an escape index and carry raw component
              // values through palette_escape_val. The slice header selects
              // SliceQpY 4 so H.266 8.4.5.3 reconstructs these 8-bit escape
              // samples exactly.
              indices_q[sample_count_q[5:0]] <= MAX_PALETTE_ENTRIES_L;
              escape_y_q[sample_count_q[5:0]] <= s_axis_y;
              escape_cb_q[sample_count_q[5:0]] <= s_axis_cb;
              escape_cr_q[sample_count_q[5:0]] <= s_axis_cr;
              escape_present_q <= 1'b1;
            end
            sample_count_q <= sample_count_q + 7'd1;
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
              2'd0,
              escape_present_q,
              cu_selected,
              {3'd0, palette_size_q},
              16'd0
            };
            m_axis_last <= (!cu_selected || (palette_size_q == 5'd0));
            if (!cu_selected || (palette_size_q == 5'd0)) begin
              state_q <= ST_BUILD;
              palette_size_q <= 5'd0;
              sample_count_q <= 7'd0;
            end else begin
              state_q <= ST_DRAIN_ENTRY_Y;
              drain_entry_q <= 5'd0;
            end
          end
        end

        ST_DRAIN_ENTRY_Y: begin
          if (!m_axis_valid || m_axis_ready) begin
            m_axis_valid <= 1'b1;
            m_axis_data <= {PALETTE_PKT_ENTRY_Y, 20'd0, entry_y_q[drain_entry_q * 8 +: 8]};
            m_axis_last <= 1'b0;
            if ((drain_entry_q + 5'd1) >= palette_size_q) begin
              state_q <= ST_DRAIN_ENTRY_CB;
              drain_entry_q <= 5'd0;
            end else begin
              drain_entry_q <= drain_entry_q + 5'd1;
            end
          end
        end

        ST_DRAIN_ENTRY_CB: begin
          if (!m_axis_valid || m_axis_ready) begin
            m_axis_valid <= 1'b1;
            m_axis_data <= {PALETTE_PKT_ENTRY_CB, 20'd0, entry_cb_q[drain_entry_q * 8 +: 8]};
            m_axis_last <= 1'b0;
            if ((drain_entry_q + 5'd1) >= palette_size_q) begin
              state_q <= ST_DRAIN_ENTRY_CR;
              drain_entry_q <= 5'd0;
            end else begin
              drain_entry_q <= drain_entry_q + 5'd1;
            end
          end
        end

        ST_DRAIN_ENTRY_CR: begin
          if (!m_axis_valid || m_axis_ready) begin
            m_axis_valid <= 1'b1;
            m_axis_data <= {PALETTE_PKT_ENTRY_CR, 20'd0, entry_cr_q[drain_entry_q * 8 +: 8]};
            m_axis_last <= (palette_size_q <= 5'd1) && !escape_present_q &&
                           ((drain_entry_q + 5'd1) >= palette_size_q);
            if ((drain_entry_q + 5'd1) >= palette_size_q) begin
              if (escape_present_q) begin
                state_q <= ST_DRAIN_ESCAPE_Y;
                drain_sample_q <= 7'd0;
              end else if (palette_size_q <= 5'd1) begin
                state_q <= ST_BUILD;
                palette_size_q <= 5'd0;
                sample_count_q <= 7'd0;
              end else begin
                state_q <= ST_DRAIN_INDEX;
                drain_sample_q <= 7'd0;
              end
            end else begin
              drain_entry_q <= drain_entry_q + 5'd1;
            end
          end
        end

        ST_DRAIN_ESCAPE_Y: begin
          // TODO(area): this drains the temporary full-CU escape banks. A
          // later streamer should emit escape packets as index subsets become
          // available, removing the escape_y/cb/cr_q arrays above.
          if (drain_sample_q >= sample_count_q) begin
            if (!m_axis_valid || m_axis_ready) begin
              state_q <= ST_DRAIN_ESCAPE_CB;
              drain_sample_q <= 7'd0;
            end
          end else if (indices_q[scan_index] == MAX_PALETTE_ENTRIES_L) begin
            if (!m_axis_valid || m_axis_ready) begin
              m_axis_valid <= 1'b1;
              m_axis_data <= {PALETTE_PKT_ESCAPE_Y, 14'd0, drain_sample_q[5:0], escape_y_q[scan_index]};
              m_axis_last <= 1'b0;
              drain_sample_q <= drain_sample_q + 7'd1;
            end
          end else begin
            drain_sample_q <= drain_sample_q + 7'd1;
          end
        end

        ST_DRAIN_ESCAPE_CB: begin
          if (drain_sample_q >= sample_count_q) begin
            if (!m_axis_valid || m_axis_ready) begin
              state_q <= ST_DRAIN_ESCAPE_CR;
              drain_sample_q <= 7'd0;
            end
          end else if (indices_q[scan_index] == MAX_PALETTE_ENTRIES_L) begin
            if (!m_axis_valid || m_axis_ready) begin
              m_axis_valid <= 1'b1;
              m_axis_data <= {PALETTE_PKT_ESCAPE_CB, 14'd0, drain_sample_q[5:0], escape_cb_q[scan_index]};
              m_axis_last <= 1'b0;
              drain_sample_q <= drain_sample_q + 7'd1;
            end
          end else begin
            drain_sample_q <= drain_sample_q + 7'd1;
          end
        end

        ST_DRAIN_ESCAPE_CR: begin
          if (drain_sample_q >= sample_count_q) begin
            if (!m_axis_valid || m_axis_ready) begin
              state_q <= ST_DRAIN_INDEX;
              drain_sample_q <= 7'd0;
            end
          end else if (indices_q[scan_index] == MAX_PALETTE_ENTRIES_L) begin
            if (!m_axis_valid || m_axis_ready) begin
              m_axis_valid <= 1'b1;
              m_axis_data <= {PALETTE_PKT_ESCAPE_CR, 14'd0, drain_sample_q[5:0], escape_cr_q[scan_index]};
              m_axis_last <= 1'b0;
              drain_sample_q <= drain_sample_q + 7'd1;
            end
          end else begin
            drain_sample_q <= drain_sample_q + 7'd1;
          end
        end

        ST_DRAIN_INDEX: begin
          if (!m_axis_valid || m_axis_ready) begin
            m_axis_valid <= 1'b1;
            m_axis_data <= {PALETTE_PKT_INDEX, 20'd0, 3'd0, indices_q[scan_index]};
            m_axis_last <= (drain_sample_q + 7'd1) >= sample_count_q;
            if ((drain_sample_q + 7'd1) >= sample_count_q) begin
              state_q <= ST_BUILD;
              palette_size_q <= 5'd0;
              sample_count_q <= 7'd0;
              drain_sample_q <= 7'd0;
              escape_present_q <= 1'b0;
            end else begin
              drain_sample_q <= drain_sample_q + 7'd1;
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
