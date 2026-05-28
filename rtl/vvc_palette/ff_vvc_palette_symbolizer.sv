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
  localparam logic [3:0] PALETTE_PKT_CU_START = 4'h1;
  localparam logic [3:0] PALETTE_PKT_ENTRY_Y  = 4'h2;
  localparam logic [3:0] PALETTE_PKT_INDEX    = 4'h3;
  localparam logic [3:0] PALETTE_PKT_ENTRY_CB = 4'h4;
  localparam logic [3:0] PALETTE_PKT_ENTRY_CR = 4'h5;
  localparam int MAX_CU_SAMPLES = PALETTE_CU_SIZE * PALETTE_CU_SIZE;

  typedef enum logic [2:0] {
    ST_INPUT,
    ST_DRAIN_START,
    ST_DRAIN_ENTRY_Y,
    ST_DRAIN_ENTRY_CB,
    ST_DRAIN_ENTRY_CR,
    ST_DRAIN_INDEX
  } state_t;

  state_t state_q;
  logic [7:0] captured_y_q;
  logic [7:0] captured_cb_q;
  logic [7:0] captured_cr_q;
  logic       captured_y_valid_q;
  logic       captured_cb_valid_q;
  logic       captured_cr_valid_q;
  logic [7:0] drain_index_q;
  logic [7:0] drain_sample_index_q;
  logic [15:0] coded_cu_count_x;
  logic [15:0] coded_cu_count_y;
  logic [15:0] root_leaf_count_value;
  logic [7:0] last_symbol_index;
  logic [7:0] input_sample_8bit;
  logic input_valid;
  logic input_last_cr;
  logic drain_symbol_selected;
  logic drain_is_last_symbol;
  logic drain_index_is_last;

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

  assign drain_symbol_selected = cu_select_mask[MAX_PALETTE_SYMBOLS - 1 - drain_index_q];
  assign drain_is_last_symbol = drain_index_q == last_symbol_index;
  assign drain_index_is_last = drain_sample_index_q == (MAX_CU_SAMPLES - 1);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_INPUT;
      captured_y_q <= 8'd0;
      captured_cb_q <= 8'd0;
      captured_cr_q <= 8'd0;
      captured_y_valid_q <= 1'b0;
      captured_cb_valid_q <= 1'b0;
      captured_cr_valid_q <= 1'b0;
      drain_index_q <= 8'd0;
      drain_sample_index_q <= 8'd0;
      m_axis_valid <= 1'b0;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;
    end else if (clear || !enable) begin
      state_q <= ST_INPUT;
      captured_y_q <= 8'd0;
      captured_cb_q <= 8'd0;
      captured_cr_q <= 8'd0;
      captured_y_valid_q <= 1'b0;
      captured_cb_valid_q <= 1'b0;
      captured_cr_valid_q <= 1'b0;
      drain_index_q <= 8'd0;
      drain_sample_index_q <= 8'd0;
      m_axis_valid <= 1'b0;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;
    end else begin
      if (m_axis_valid && m_axis_ready) begin
        m_axis_valid <= 1'b0;
        m_axis_data <= 32'd0;
        m_axis_last <= 1'b0;
      end

      if (input_valid) begin
        if ((s_axis_plane == PLANE_Y) && !captured_y_valid_q) begin
          captured_y_q <= input_sample_8bit;
          captured_y_valid_q <= 1'b1;
        end
        if ((s_axis_plane == PLANE_CB) && !captured_cb_valid_q) begin
          captured_cb_q <= input_sample_8bit;
          captured_cb_valid_q <= 1'b1;
        end
        if ((s_axis_plane == PLANE_CR) && !captured_cr_valid_q) begin
          captured_cr_q <= input_sample_8bit;
          captured_cr_valid_q <= 1'b1;
        end
        if (input_last_cr) begin
          state_q <= ST_DRAIN_START;
          drain_index_q <= 8'd0;
          drain_sample_index_q <= 8'd0;
        end
      end

      if (!input_valid) begin
        case (state_q)
          ST_INPUT: begin
          end

          ST_DRAIN_START: begin
            if (!m_axis_valid || m_axis_ready) begin
              m_axis_valid <= 1'b1;
              m_axis_data <= {
                PALETTE_PKT_CU_START,
                3'd0,
                drain_symbol_selected,
                drain_symbol_selected ? 8'd1 : 8'd0,
                16'd0
              };
              m_axis_last <= (!drain_symbol_selected) && drain_is_last_symbol;
              if (!drain_symbol_selected) begin
                if (drain_is_last_symbol) begin
                  state_q <= ST_INPUT;
                  drain_index_q <= 8'd0;
                end else begin
                  drain_index_q <= drain_index_q + 8'd1;
                end
              end else begin
                state_q <= ST_DRAIN_ENTRY_Y;
              end
            end
          end

          ST_DRAIN_ENTRY_Y: begin
            if (!m_axis_valid || m_axis_ready) begin
              m_axis_valid <= 1'b1;
              m_axis_data <= {PALETTE_PKT_ENTRY_Y, 20'd0, captured_y_q};
              m_axis_last <= 1'b0;
              state_q <= ST_DRAIN_ENTRY_CB;
            end
          end

          ST_DRAIN_ENTRY_CB: begin
            if (!m_axis_valid || m_axis_ready) begin
              m_axis_valid <= 1'b1;
              m_axis_data <= {PALETTE_PKT_ENTRY_CB, 20'd0, captured_cb_q};
              m_axis_last <= 1'b0;
              state_q <= ST_DRAIN_ENTRY_CR;
            end
          end

          ST_DRAIN_ENTRY_CR: begin
            if (!m_axis_valid || m_axis_ready) begin
              m_axis_valid <= 1'b1;
              m_axis_data <= {PALETTE_PKT_ENTRY_CR, 20'd0, captured_cr_q};
              m_axis_last <= 1'b0;
              state_q <= ST_DRAIN_INDEX;
              drain_sample_index_q <= 8'd0;
            end
          end

          ST_DRAIN_INDEX: begin
            if (!m_axis_valid || m_axis_ready) begin
              m_axis_valid <= 1'b1;
              m_axis_data <= {PALETTE_PKT_INDEX, 20'd0, 8'd0};
              m_axis_last <= drain_index_is_last && drain_is_last_symbol;
              if (drain_index_is_last) begin
                drain_sample_index_q <= 8'd0;
                if (drain_is_last_symbol) begin
                  state_q <= ST_INPUT;
                  drain_index_q <= 8'd0;
                end else begin
                  drain_index_q <= drain_index_q + 8'd1;
                  state_q <= ST_DRAIN_START;
                end
              end else begin
                drain_sample_index_q <= drain_sample_index_q + 8'd1;
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
