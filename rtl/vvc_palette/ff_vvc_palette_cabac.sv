`timescale 1ns/1ps

module ff_vvc_palette_cabac #(
  parameter int MAX_PALETTE_SYMBOLS = 64
) (
  input  logic clk,
  input  logic rst_n,
  input  logic start,
  input  logic clear,
  input  logic enable,
  input  logic [15:0] coded_width,
  input  logic [15:0] coded_height,
  input  logic [7:0]  symbol_count,
  input  logic        s_axis_valid,
  output logic        s_axis_ready,
  input  logic [31:0] s_axis_data,
  input  logic        s_axis_last,
  input  logic        m_axis_ready,
  output logic        m_axis_valid,
  output logic [7:0]  m_axis_data,
  output logic        m_axis_last,
  output logic [2:0]  stream_last_byte_bits
);
  localparam logic [3:0] PALETTE_PKT_CU_START = 4'h1;
  localparam logic [3:0] PALETTE_PKT_ENTRY_Y  = 4'h2;
  localparam logic [3:0] PALETTE_PKT_INDEX    = 4'h3;
  localparam logic [3:0] PALETTE_PKT_ENTRY_CB = 4'h4;
  localparam logic [3:0] PALETTE_PKT_ENTRY_CR = 4'h5;

  typedef enum logic [1:0] {
    ST_RUN,
    ST_FLUSH,
    ST_WAIT_DONE
  } state_t;

  state_t state_q;
  logic [7:0] accepted_symbols_q;
  logic [31:0] symbol_payload;
  logic [5:0] symbol_bits;
  logic symbol_selected;
  logic bit_writer_valid;
  logic bit_writer_ready;
  logic bit_writer_flush_zero;
  logic bit_writer_last;
  logic bit_writer_done;
  logic bit_writer_idle;

  assign symbol_selected = s_axis_data[24];

  always @* begin
    symbol_payload = s_axis_data;
    symbol_bits = 6'd32;
    case (s_axis_data[31:28])
      PALETTE_PKT_CU_START: begin
        symbol_payload = {23'd0, symbol_selected, s_axis_data[23:16]};
        symbol_bits = 6'd9;
      end
      PALETTE_PKT_ENTRY_Y,
      PALETTE_PKT_ENTRY_CB,
      PALETTE_PKT_ENTRY_CR: begin
        symbol_payload = {24'd0, s_axis_data[7:0]};
        symbol_bits = 6'd8;
      end
      PALETTE_PKT_INDEX: begin
        symbol_payload = {24'd0, s_axis_data[7:0]};
        symbol_bits = 6'd8;
      end
      default: begin
        symbol_payload = {28'd0, s_axis_data[31:28]};
        symbol_bits = 6'd4;
      end
    endcase
  end

  assign s_axis_ready = enable && (state_q == ST_RUN) && bit_writer_ready;
  assign bit_writer_valid =
    (enable && (state_q == ST_RUN) && s_axis_valid && bit_writer_ready) ||
    (enable && (state_q == ST_FLUSH) && bit_writer_ready);
  assign bit_writer_flush_zero = state_q == ST_FLUSH;
  assign bit_writer_last = state_q == ST_FLUSH;

  ff_vvc_cabac_bit_writer bit_writer (
    .clk(clk),
    .rst_n(rst_n),
    .clear(clear || start || !enable),
    .s_axis_valid(bit_writer_valid),
    .s_axis_ready(bit_writer_ready),
    .s_axis_value((state_q == ST_FLUSH) ? 32'd0 : symbol_payload),
    .s_axis_bit_count((state_q == ST_FLUSH) ? 6'd0 : symbol_bits),
    .s_axis_flush_zero(bit_writer_flush_zero),
    .s_axis_last(bit_writer_last),
    .m_axis_ready(m_axis_ready),
    .m_axis_valid(m_axis_valid),
    .m_axis_data(m_axis_data),
    .m_axis_last(m_axis_last),
    .total_bit_count(),
    .partial_bit_count(stream_last_byte_bits),
    .idle(bit_writer_idle),
    .done(bit_writer_done)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_RUN;
      accepted_symbols_q <= 8'd0;
    end else if (clear || start || !enable) begin
      state_q <= ST_RUN;
      accepted_symbols_q <= 8'd0;
    end else begin
      case (state_q)
        ST_RUN: begin
          if (s_axis_valid && s_axis_ready) begin
            accepted_symbols_q <= accepted_symbols_q + 8'd1;
            if (s_axis_last || ((accepted_symbols_q + 8'd1) >= symbol_count)) begin
              state_q <= ST_FLUSH;
            end
          end
        end

        ST_FLUSH: begin
          if (bit_writer_ready) begin
            state_q <= ST_WAIT_DONE;
          end
        end

        ST_WAIT_DONE: begin
          if (bit_writer_done) begin
            state_q <= ST_RUN;
            accepted_symbols_q <= 8'd0;
          end
        end

        default: begin
          state_q <= ST_RUN;
        end
      endcase
    end
  end

  logic unused_inputs;
  assign unused_inputs = ^{coded_width, coded_height, MAX_PALETTE_SYMBOLS[7:0], bit_writer_idle};
endmodule
