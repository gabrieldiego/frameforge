`timescale 1ns/1ps

module ff_vvc_cabac_stream_writer #(
  parameter int VVC_CABAC_CTX_ID_BITS = 10
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        start,
  input  logic        clear,

  input  logic        s_axis_valid,
  output logic        s_axis_ready,
  input  logic [2:0]  s_axis_kind,
  input  logic        s_axis_bin,
  input  logic [31:0] s_axis_bins_pattern,
  input  logic [5:0]  s_axis_bins_count,
  input  logic        s_axis_ctx_valid,
  input  logic [VVC_CABAC_CTX_ID_BITS - 1:0] s_axis_ctx_id,
  input  logic [8:0]  s_axis_lps,
  input  logic        s_axis_mps,
  input  logic        s_axis_last,

  input  logic        m_axis_ready,
  output logic        m_axis_valid,
  output logic [7:0]  m_axis_data,
  output logic        m_axis_last,
  output logic [2:0]  stream_last_byte_bits,
  output logic        done
);
  localparam logic [2:0] CABAC_BIN_EP  = 3'd0;
  localparam logic [2:0] CABAC_BIN_TRM = 3'd1;
  localparam logic [2:0] CABAC_BIN_CTX = 3'd2;
  localparam logic [2:0] CABAC_BINS_EP = 3'd3;

  typedef enum logic [4:0] {
    ST_RUN,
    ST_WRITE_OUT,
    ST_EMIT_BYTE,
    ST_EMIT_REPEAT,
    ST_FINISH_DECIDE,
    ST_FINISH_BUFFERED,
    ST_FINISH_REPEAT,
    ST_FINISH_FINAL_BITS,
    ST_FINISH_FLUSH,
    ST_BINS_EP_CONT,
    ST_WAIT_EMIT
  } state_t;

  state_t state_q;
  state_t return_state_q;
  logic [31:0] low_q;
  logic [15:0] range_q;
  logic [7:0] bits_left_q;
  logic [8:0] buffered_byte_q;
  logic [7:0] num_buffered_bytes_q;
  logic finish_after_write_q;
  logic finish_carry_q;
  logic [5:0] final_bits_q;

  logic [VVC_CABAC_CTX_ID_BITS - 1:0] engine_ctx_bank_id;
  logic [8:0] context_ctx_lps;
  logic context_ctx_mps;
  logic [8:0] selected_ctx_lps;
  logic selected_ctx_mps;
  logic [31:0] engine_low;
  logic [15:0] engine_range;
  logic [7:0] engine_bits_left;
  logic engine_write_out;
  logic context_update_valid;

  logic emit_valid_q;
  logic emit_flush_q;
  logic emit_last_q;
  logic [31:0] emit_value_q;
  logic [5:0] emit_count_q;
  logic bit_writer_ready;
  logic bit_writer_done;
  logic bit_writer_idle;
  logic [2:0] bit_writer_partial_bits;
  logic [2:0] stream_last_byte_bits_q;

  logic [8:0] lead_byte;
  logic [31:0] low_mask;
  logic [31:0] finish_test;
  logic [31:0] final_bits_value;
  logic [31:0] bins_ep_low_next;
  logic [7:0] bins_ep_bits_left_next;
  logic [31:0] bins_ep_source_pattern;
  logic [5:0]  bins_ep_source_count;
  logic        bins_ep_source_last;
  logic [5:0]  bins_ep_available_count;
  logic [5:0]  bins_ep_consume_count;
  logic [5:0]  bins_ep_remaining_count;
  logic [31:0] s_axis_bins_mask;
  logic [31:0] bins_ep_consume_mask;
  logic [31:0] bins_ep_consume_pattern;
  logic [31:0] bins_ep_remaining_mask;
  logic [31:0] bins_ep_remaining_pattern;
  logic        bins_ep_pending_q;
  logic [31:0] bins_ep_pending_pattern_q;
  logic [5:0]  bins_ep_pending_count_q;
  logic        bins_ep_pending_last_q;

  assign selected_ctx_lps = (s_axis_kind == CABAC_BIN_CTX) ?
    (s_axis_ctx_valid ? context_ctx_lps : s_axis_lps) :
    9'd0;
  assign selected_ctx_mps = (s_axis_kind == CABAC_BIN_CTX) ?
    (s_axis_ctx_valid ? context_ctx_mps : s_axis_mps) :
    1'b0;
  assign s_axis_ready = (state_q == ST_RUN) && !bins_ep_pending_q;
  assign context_update_valid = s_axis_valid && s_axis_ready &&
                                (s_axis_kind == CABAC_BIN_CTX) && s_axis_ctx_valid;
  assign lead_byte = low_q >> (24 - bits_left_q);
  assign low_mask = 32'hffff_ffff >> (bits_left_q + 8'd8);
  assign finish_test = low_q >> (32 - bits_left_q);
  assign final_bits_value = low_q >> 8;
  assign s_axis_bins_mask =
    (s_axis_bins_count == 6'd0) ? 32'd0 :
    ((s_axis_bins_count >= 6'd32) ? 32'hffff_ffff :
     ((32'd1 << s_axis_bins_count) - 32'd1));
  assign bins_ep_source_pattern = bins_ep_pending_q ?
    bins_ep_pending_pattern_q : (s_axis_bins_pattern & s_axis_bins_mask);
  assign bins_ep_source_count = bins_ep_pending_q ? bins_ep_pending_count_q : s_axis_bins_count;
  assign bins_ep_source_last = bins_ep_pending_q ? bins_ep_pending_last_q : s_axis_last;
  assign bins_ep_available_count = (bits_left_q > 8'd11) ? (bits_left_q[5:0] - 6'd11) : 6'd1;
  assign bins_ep_consume_count =
    (bins_ep_source_count == 6'd0) ? 6'd0 :
    ((bins_ep_source_count > bins_ep_available_count) ? bins_ep_available_count :
     bins_ep_source_count);
  assign bins_ep_remaining_count = bins_ep_source_count - bins_ep_consume_count;
  assign bins_ep_consume_mask =
    (bins_ep_consume_count == 6'd0) ? 32'd0 :
    ((bins_ep_consume_count >= 6'd32) ? 32'hffff_ffff :
     ((32'd1 << bins_ep_consume_count) - 32'd1));
  assign bins_ep_consume_pattern =
    (bins_ep_source_pattern >> bins_ep_remaining_count) & bins_ep_consume_mask;
  assign bins_ep_remaining_mask =
    (bins_ep_remaining_count == 6'd0) ? 32'd0 :
    ((bins_ep_remaining_count >= 6'd32) ? 32'hffff_ffff :
     ((32'd1 << bins_ep_remaining_count) - 32'd1));
  assign bins_ep_remaining_pattern = bins_ep_source_pattern & bins_ep_remaining_mask;
  assign bins_ep_low_next =
    (low_q << bins_ep_consume_count) + (range_q * bins_ep_consume_pattern);
  assign bins_ep_bits_left_next = bits_left_q - {2'd0, bins_ep_consume_count};
  assign stream_last_byte_bits = stream_last_byte_bits_q;

  ff_vvc_cabac_context_model #(
    .VVC_CABAC_CTX_ID_BITS(VVC_CABAC_CTX_ID_BITS)
  ) context_model (
    .clk(clk),
    .rst_n(rst_n),
    .reset_contexts(clear || start),
    .query_ctx_id(s_axis_ctx_id),
    .query_range(range_q),
    .query_bank_id(engine_ctx_bank_id),
    .query_lps(context_ctx_lps),
    .query_mps(context_ctx_mps),
    .update_valid(context_update_valid),
    .update_ctx_id(s_axis_ctx_id),
    .update_bin(s_axis_bin)
  );

  ff_vvc_cabac_bin_engine bin_engine (
    .bin_kind(s_axis_kind),
    .bin_value(s_axis_bin),
    .ctx_lps(selected_ctx_lps),
    .ctx_mps(selected_ctx_mps),
    .low_in(low_q),
    .range_in(range_q),
    .bits_left_in(bits_left_q),
    .low_out(engine_low),
    .range_out(engine_range),
    .bits_left_out(engine_bits_left),
    .write_out(engine_write_out)
  );

  ff_vvc_cabac_bit_writer bit_writer (
    .clk(clk),
    .rst_n(rst_n),
    .clear(clear || start),
    .s_axis_valid(emit_valid_q),
    .s_axis_ready(bit_writer_ready),
    .s_axis_value(emit_value_q),
    .s_axis_bit_count(emit_count_q),
    .s_axis_flush_zero(emit_flush_q),
    .s_axis_last(emit_last_q),
    .m_axis_ready(m_axis_ready),
    .m_axis_valid(m_axis_valid),
    .m_axis_data(m_axis_data),
    .m_axis_last(m_axis_last),
    .total_bit_count(),
    .partial_bit_count(bit_writer_partial_bits),
    .idle(bit_writer_idle),
    .done(bit_writer_done)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_RUN;
      return_state_q <= ST_RUN;
      low_q <= 32'd0;
      range_q <= 16'd510;
      bits_left_q <= 8'd23;
      buffered_byte_q <= 9'h0ff;
      num_buffered_bytes_q <= 8'd0;
      finish_after_write_q <= 1'b0;
      finish_carry_q <= 1'b0;
      final_bits_q <= 6'd0;
      emit_valid_q <= 1'b0;
      emit_flush_q <= 1'b0;
      emit_last_q <= 1'b0;
      emit_value_q <= 32'd0;
      emit_count_q <= 6'd0;
      stream_last_byte_bits_q <= 3'd0;
      bins_ep_pending_q <= 1'b0;
      bins_ep_pending_pattern_q <= 32'd0;
      bins_ep_pending_count_q <= 6'd0;
      bins_ep_pending_last_q <= 1'b0;
      done <= 1'b0;
    end else if (clear) begin
      state_q <= ST_RUN;
      return_state_q <= ST_RUN;
      low_q <= 32'd0;
      range_q <= 16'd510;
      bits_left_q <= 8'd23;
      buffered_byte_q <= 9'h0ff;
      num_buffered_bytes_q <= 8'd0;
      finish_after_write_q <= 1'b0;
      finish_carry_q <= 1'b0;
      final_bits_q <= 6'd0;
      emit_valid_q <= 1'b0;
      emit_flush_q <= 1'b0;
      emit_last_q <= 1'b0;
      emit_value_q <= 32'd0;
      emit_count_q <= 6'd0;
      stream_last_byte_bits_q <= 3'd0;
      bins_ep_pending_q <= 1'b0;
      bins_ep_pending_pattern_q <= 32'd0;
      bins_ep_pending_count_q <= 6'd0;
      bins_ep_pending_last_q <= 1'b0;
      done <= 1'b0;
    end else begin
      done <= 1'b0;
      if (emit_valid_q && bit_writer_ready) begin
        emit_valid_q <= 1'b0;
      end

      if (start) begin
        state_q <= ST_RUN;
        return_state_q <= ST_RUN;
        low_q <= 32'd0;
        range_q <= 16'd510;
        bits_left_q <= 8'd23;
        buffered_byte_q <= 9'h0ff;
        num_buffered_bytes_q <= 8'd0;
        finish_after_write_q <= 1'b0;
        finish_carry_q <= 1'b0;
        final_bits_q <= 6'd0;
        emit_valid_q <= 1'b0;
        emit_flush_q <= 1'b0;
        emit_last_q <= 1'b0;
        emit_value_q <= 32'd0;
        emit_count_q <= 6'd0;
        stream_last_byte_bits_q <= 3'd0;
        bins_ep_pending_q <= 1'b0;
        bins_ep_pending_pattern_q <= 32'd0;
        bins_ep_pending_count_q <= 6'd0;
        bins_ep_pending_last_q <= 1'b0;
      end else begin
        case (state_q)
          ST_RUN: begin
            if (s_axis_valid) begin
              if (s_axis_kind == CABAC_BINS_EP) begin
                low_q <= bins_ep_low_next;
                bits_left_q <= bins_ep_bits_left_next;
                bins_ep_pending_q <= bins_ep_remaining_count != 6'd0;
                bins_ep_pending_pattern_q <= bins_ep_remaining_pattern;
                bins_ep_pending_count_q <= bins_ep_remaining_count;
                bins_ep_pending_last_q <= bins_ep_source_last;
                finish_after_write_q <= (bins_ep_remaining_count == 6'd0) && bins_ep_source_last;
                if (bins_ep_bits_left_next < 8'd12) begin
                  state_q <= ST_WRITE_OUT;
                end else if (bins_ep_remaining_count != 6'd0) begin
                  state_q <= ST_BINS_EP_CONT;
                end else if (bins_ep_source_last) begin
                  state_q <= ST_FINISH_DECIDE;
                end
              end else begin
                low_q <= engine_low;
                range_q <= engine_range;
                bits_left_q <= engine_bits_left;
                finish_after_write_q <= s_axis_last;
                if (engine_write_out) begin
                  state_q <= ST_WRITE_OUT;
                end else if (s_axis_last) begin
                  state_q <= ST_FINISH_DECIDE;
                end
              end
            end
          end

          ST_WRITE_OUT: begin
            bits_left_q <= bits_left_q + 8'd8;
            low_q <= low_q & low_mask;
            if (lead_byte == 9'h0ff) begin
              num_buffered_bytes_q <= num_buffered_bytes_q + 8'd1;
              state_q <= bins_ep_pending_q ? ST_BINS_EP_CONT :
                         (finish_after_write_q ? ST_FINISH_DECIDE : ST_RUN);
            end else if (num_buffered_bytes_q != 8'd0) begin
              finish_carry_q <= lead_byte[8];
              emit_value_q <= {23'd0, buffered_byte_q + {8'd0, lead_byte[8]}};
              emit_count_q <= 6'd8;
              emit_flush_q <= 1'b0;
              emit_last_q <= 1'b0;
              emit_valid_q <= 1'b1;
              buffered_byte_q <= {1'b0, lead_byte[7:0]};
              return_state_q <= (num_buffered_bytes_q > 8'd1) ? ST_EMIT_REPEAT :
                                (bins_ep_pending_q ? ST_BINS_EP_CONT :
                                 (finish_after_write_q ? ST_FINISH_DECIDE : ST_RUN));
              state_q <= ST_WAIT_EMIT;
            end else begin
              num_buffered_bytes_q <= 8'd1;
              buffered_byte_q <= lead_byte;
              state_q <= bins_ep_pending_q ? ST_BINS_EP_CONT :
                         (finish_after_write_q ? ST_FINISH_DECIDE : ST_RUN);
            end
          end

          ST_EMIT_REPEAT: begin
            emit_value_q <= {24'd0, finish_carry_q ? 8'h00 : 8'hff};
            emit_count_q <= 6'd8;
            emit_flush_q <= 1'b0;
            emit_last_q <= 1'b0;
            emit_valid_q <= 1'b1;
            num_buffered_bytes_q <= num_buffered_bytes_q - 8'd1;
            return_state_q <= (num_buffered_bytes_q > 8'd2) ? ST_EMIT_REPEAT :
                              (bins_ep_pending_q ? ST_BINS_EP_CONT :
                               (finish_after_write_q ? ST_FINISH_DECIDE : ST_RUN));
            state_q <= ST_WAIT_EMIT;
          end

          ST_BINS_EP_CONT: begin
            low_q <= bins_ep_low_next;
            bits_left_q <= bins_ep_bits_left_next;
            bins_ep_pending_q <= bins_ep_remaining_count != 6'd0;
            bins_ep_pending_pattern_q <= bins_ep_remaining_pattern;
            bins_ep_pending_count_q <= bins_ep_remaining_count;
            bins_ep_pending_last_q <= bins_ep_source_last;
            finish_after_write_q <= (bins_ep_remaining_count == 6'd0) && bins_ep_source_last;
            if (bins_ep_bits_left_next < 8'd12) begin
              state_q <= ST_WRITE_OUT;
            end else if (bins_ep_remaining_count != 6'd0) begin
              state_q <= ST_BINS_EP_CONT;
            end else if (bins_ep_source_last) begin
              state_q <= ST_FINISH_DECIDE;
            end else begin
              state_q <= ST_RUN;
            end
          end

          ST_FINISH_DECIDE: begin
            final_bits_q <= 6'(24 - bits_left_q);
            if (finish_test != 32'd0) begin
              finish_carry_q <= 1'b1;
              low_q <= low_q - (32'd1 << (32 - bits_left_q));
              state_q <= ST_FINISH_BUFFERED;
            end else begin
              finish_carry_q <= 1'b0;
              if (num_buffered_bytes_q != 8'd0) begin
                state_q <= ST_FINISH_BUFFERED;
              end else if ((24 - bits_left_q) != 0) begin
                state_q <= ST_FINISH_FINAL_BITS;
              end else begin
                emit_value_q <= 32'd0;
                emit_count_q <= 6'd0;
                emit_flush_q <= 1'b1;
                emit_last_q <= 1'b1;
                emit_valid_q <= 1'b1;
                stream_last_byte_bits_q <= 3'd0;
                return_state_q <= ST_RUN;
                state_q <= ST_WAIT_EMIT;
              end
            end
          end

          ST_FINISH_BUFFERED: begin
            emit_value_q <= {23'd0, buffered_byte_q + {8'd0, finish_carry_q}};
            emit_count_q <= 6'd8;
            emit_flush_q <= 1'b0;
            emit_last_q <= (num_buffered_bytes_q <= 8'd1) && (final_bits_q == 6'd0);
            emit_valid_q <= 1'b1;
            if ((num_buffered_bytes_q <= 8'd1) && (final_bits_q == 6'd0)) begin
              stream_last_byte_bits_q <= 3'd0;
            end
            if (num_buffered_bytes_q > 8'd1) begin
              num_buffered_bytes_q <= num_buffered_bytes_q - 8'd1;
              return_state_q <= ST_FINISH_REPEAT;
            end else if (final_bits_q != 6'd0) begin
              return_state_q <= ST_FINISH_FINAL_BITS;
            end else begin
              return_state_q <= ST_RUN;
            end
            state_q <= ST_WAIT_EMIT;
          end

          ST_FINISH_REPEAT: begin
            emit_value_q <= {24'd0, finish_carry_q ? 8'h00 : 8'hff};
            emit_count_q <= 6'd8;
            emit_flush_q <= 1'b0;
            emit_last_q <= (num_buffered_bytes_q <= 8'd1) && (final_bits_q == 6'd0);
            emit_valid_q <= 1'b1;
            if ((num_buffered_bytes_q <= 8'd1) && (final_bits_q == 6'd0)) begin
              stream_last_byte_bits_q <= 3'd0;
            end
            if (num_buffered_bytes_q > 8'd1) begin
              num_buffered_bytes_q <= num_buffered_bytes_q - 8'd1;
              return_state_q <= ST_FINISH_REPEAT;
            end else if (final_bits_q != 6'd0) begin
              return_state_q <= ST_FINISH_FINAL_BITS;
            end else begin
              return_state_q <= ST_RUN;
            end
            state_q <= ST_WAIT_EMIT;
          end

          ST_FINISH_FINAL_BITS: begin
            emit_value_q <= final_bits_value;
            emit_count_q <= final_bits_q;
            emit_flush_q <= 1'b0;
            emit_last_q <= final_bits_q[2:0] == 3'd0;
            emit_valid_q <= 1'b1;
            stream_last_byte_bits_q <= final_bits_q[2:0];
            return_state_q <= (final_bits_q[2:0] == 3'd0) ? ST_RUN : ST_FINISH_FLUSH;
            state_q <= ST_WAIT_EMIT;
          end

          ST_FINISH_FLUSH: begin
            emit_value_q <= 32'd0;
            emit_count_q <= 6'd0;
            emit_flush_q <= 1'b1;
            emit_last_q <= 1'b1;
            emit_valid_q <= 1'b1;
            return_state_q <= ST_RUN;
            state_q <= ST_WAIT_EMIT;
          end

          ST_WAIT_EMIT: begin
            if (!emit_valid_q && bit_writer_idle) begin
              if (return_state_q == ST_RUN) begin
                done <= emit_last_q;
              end
              state_q <= return_state_q;
            end
          end

          default: begin
            state_q <= ST_RUN;
          end
        endcase
      end
    end
  end
endmodule
