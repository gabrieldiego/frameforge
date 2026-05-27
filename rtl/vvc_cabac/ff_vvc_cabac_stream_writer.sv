`timescale 1ns/1ps

module ff_vvc_cabac_stream_writer (
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
  input  logic [4:0]  s_axis_ctx_id,
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
  localparam int CABAC_PENDING_BYTES = 8;
  localparam int CABAC_PENDING_BITS = CABAC_PENDING_BYTES * 8;

  typedef struct packed {
    logic [7:0] bits_left;
    logic [7:0] num_buffered_bytes;
    logic [8:0] buffered_byte;
    logic [15:0] range;
    logic [31:0] low;
  } cabac_core_state_t;

  typedef struct packed {
    logic [12:0] bit_count;
    logic [2:0]  partial_bit_count;
    logic [7:0]  partial_byte;
    logic [3:0]  pending_count;
    logic [CABAC_PENDING_BITS - 1:0] pending_bytes;
    logic        overflow;
  } cabac_stream_state_t;

  typedef struct packed {
    cabac_core_state_t core;
    cabac_stream_state_t stream;
  } cabac_writer_state_t;

  cabac_writer_state_t writer_q;
  logic finishing_q;
  logic final_pending_q;
  logic queue_load_valid;
  logic queue_load_ready;
  logic queue_load_last;
  logic [3:0] queue_load_count;
  logic [CABAC_PENDING_BITS - 1:0] queue_load_bytes;
  logic queue_idle;
  logic queue_last_accepted;
  logic [4:0] engine_ctx_bank_id;
  logic [8:0] context_ctx_lps;
  logic context_ctx_mps;
  logic [8:0] selected_ctx_lps;
  logic selected_ctx_mps;
  logic [31:0] engine_low_in;
  logic [15:0] engine_range_in;
  logic [7:0] engine_bits_left_in;
  logic [15:0] context_range_in;
  logic [31:0] engine_low;
  logic [15:0] engine_range;
  logic [7:0] engine_bits_left;
  logic engine_write_out;
  logic context_update_valid;

  assign s_axis_ready = queue_idle && (writer_q.stream.pending_count == 4'd0) && !finishing_q;
  assign stream_last_byte_bits = writer_q.stream.bit_count[2:0];
  assign queue_load_valid = writer_q.stream.pending_count != 4'd0;
  assign queue_load_count = writer_q.stream.pending_count;
  assign queue_load_bytes = writer_q.stream.pending_bytes;
  assign queue_load_last = final_pending_q && (writer_q.stream.partial_bit_count == 3'd0);
  assign selected_ctx_lps = (s_axis_kind == CABAC_BIN_CTX) ?
    (s_axis_ctx_valid ? context_ctx_lps : s_axis_lps) :
    9'd0;
  assign selected_ctx_mps = (s_axis_kind == CABAC_BIN_CTX) ?
    (s_axis_ctx_valid ? context_ctx_mps : s_axis_mps) :
    1'b0;
  assign engine_low_in = writer_q.core.low;
  assign engine_range_in = writer_q.core.range;
  assign engine_bits_left_in = writer_q.core.bits_left;
  assign context_range_in = writer_q.core.range;
  assign context_update_valid = s_axis_valid && s_axis_ready &&
    (s_axis_kind == CABAC_BIN_CTX) && s_axis_ctx_valid;

  ff_vvc_cabac_context_model context_model (
    .clk(clk),
    .rst_n(rst_n),
    .reset_contexts(clear || start),
    .query_ctx_id(s_axis_ctx_id),
    .query_range(context_range_in),
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
    .low_in(engine_low_in),
    .range_in(engine_range_in),
    .bits_left_in(engine_bits_left_in),
    .low_out(engine_low),
    .range_out(engine_range),
    .bits_left_out(engine_bits_left),
    .write_out(engine_write_out)
  );

  ff_vvc_byte_queue #(
    .QUEUE_BYTES(CABAC_PENDING_BYTES)
  ) byte_queue (
    .clk(clk),
    .rst_n(rst_n),
    .clear(clear || start),
    .load_valid(queue_load_valid),
    .load_ready(queue_load_ready),
    .load_count(queue_load_count),
    .load_bytes(queue_load_bytes),
    .load_last(queue_load_last),
    .m_axis_ready(m_axis_ready),
    .m_axis_valid(m_axis_valid),
    .m_axis_data(m_axis_data),
    .m_axis_last(m_axis_last),
    .idle(queue_idle),
    .last_accepted(queue_last_accepted)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      writer_q <= cabac_start();
      finishing_q <= 1'b0;
      final_pending_q <= 1'b0;
      done <= 1'b0;
    end else if (clear) begin
      writer_q <= cabac_start();
      finishing_q <= 1'b0;
      final_pending_q <= 1'b0;
      done <= 1'b0;
    end else begin
      done <= 1'b0;

      if (start) begin
        writer_q <= cabac_start();
        finishing_q <= 1'b0;
        final_pending_q <= 1'b0;
      end else if (queue_last_accepted) begin
        done <= 1'b1;
        finishing_q <= 1'b0;
        final_pending_q <= 1'b0;
        writer_q <= cabac_start();
      end else if (queue_load_valid) begin
        if (queue_load_ready) begin
          writer_q.stream.pending_count <= 4'd0;
          writer_q.stream.pending_bytes <= '0;
          if (queue_load_last) begin
            finishing_q <= 1'b0;
          end
        end
      end else if (finishing_q) begin
        if (!final_pending_q) begin
          writer_q <= cabac_finish(writer_q);
          final_pending_q <= 1'b1;
        end else if (writer_q.stream.partial_bit_count != 3'd0) begin
          writer_q <= cabac_flush_partial_byte(writer_q);
        end else begin
          done <= 1'b1;
          finishing_q <= 1'b0;
          final_pending_q <= 1'b0;
          writer_q <= cabac_start();
        end
      end else if (s_axis_valid && s_axis_ready) begin
        case (s_axis_kind)
          CABAC_BIN_CTX: begin
            if (s_axis_ctx_valid) begin
`ifdef FRAMEFORGE_RTL_CABAC_TRACE
              $display(
                "FF_RTL_STREAM_CABAC ctx=%0d bank=%0d range=%0d lps=%0d mps=%0d bin=%0d",
                s_axis_ctx_id,
                engine_ctx_bank_id,
                writer_q.core.range,
                selected_ctx_lps,
                selected_ctx_mps,
                s_axis_bin
              );
`endif
              writer_q <= cabac_apply_bin_engine(
                writer_q,
                engine_low,
                engine_range,
                engine_bits_left,
                engine_write_out
              );
            end else begin
              writer_q <= cabac_apply_bin_engine(
                writer_q,
                engine_low,
                engine_range,
                engine_bits_left,
                engine_write_out
              );
            end
          end
          CABAC_BINS_EP: writer_q <= cabac_encode_bins_ep(
            writer_q,
            s_axis_bins_pattern,
            s_axis_bins_count
          );
          default: writer_q <= cabac_apply_bin_engine(
            writer_q,
            engine_low,
            engine_range,
            engine_bits_left,
            engine_write_out
          );
        endcase
        if (s_axis_last) begin
          finishing_q <= 1'b1;
        end
      end
    end
  end

  function automatic cabac_writer_state_t cabac_start();
    cabac_writer_state_t st;
    begin
      st = '0;
      st.core.low = 32'd0;
      st.core.range = 16'd510;
      st.core.buffered_byte = 9'h0ff;
      st.core.num_buffered_bytes = 8'd0;
      st.core.bits_left = 8'd23;
      cabac_start = st;
    end
  endfunction

  function automatic cabac_writer_state_t cabac_apply_bin_engine(
    input cabac_writer_state_t st_in,
    input logic [31:0] low,
    input logic [15:0] range,
    input logic [7:0] bits_left,
    input logic do_write_out
  );
    cabac_writer_state_t st;
    begin
      st = st_in;
      st.core.low = low;
      st.core.range = range;
      st.core.bits_left = bits_left;
      if (do_write_out) begin
        st = cabac_write_out(st);
      end
      cabac_apply_bin_engine = st;
    end
  endfunction

  function automatic cabac_writer_state_t cabac_write_out(input cabac_writer_state_t st_in);
    cabac_writer_state_t st;
    logic [31:0] low;
    logic [31:0] lead_byte;
    logic [31:0] mask;
    logic [8:0] buffered_byte;
    logic [7:0] num_buffered_bytes;
    logic [8:0] byte_value;
    logic [8:0] repeated_byte;
    logic [8:0] carry;
    logic [7:0] bits_left;
    integer repeat_i;
    begin
      st = st_in;
      low = st.core.low;
      bits_left = st.core.bits_left;
      buffered_byte = st.core.buffered_byte;
      num_buffered_bytes = st.core.num_buffered_bytes;
      lead_byte = low >> (8'd24 - bits_left);
      bits_left = bits_left + 8'd8;
      mask = 32'hffff_ffff >> bits_left;
      low = low & mask;

      if (lead_byte == 32'hff) begin
        num_buffered_bytes = num_buffered_bytes + 8'd1;
      end else if (num_buffered_bytes > 8'd0) begin
        carry = lead_byte >> 8;
        byte_value = buffered_byte + carry;
        buffered_byte = lead_byte[7:0];
        st.core.low = low;
        st.core.buffered_byte = buffered_byte;
        st.core.num_buffered_bytes = num_buffered_bytes;
        st.core.bits_left = bits_left[7:0];
        st = cabac_write_bits(st, byte_value, 6'd8);
        repeated_byte = (9'h0ff + carry) & 9'h0ff;
        num_buffered_bytes = st.core.num_buffered_bytes;
        for (repeat_i = 0; repeat_i < CABAC_PENDING_BYTES; repeat_i = repeat_i + 1) begin
          if (num_buffered_bytes > 8'd1) begin
            st = cabac_write_bits(st, repeated_byte, 6'd8);
            num_buffered_bytes = num_buffered_bytes - 8'd1;
            st.core.num_buffered_bytes = num_buffered_bytes;
          end
        end
      end else begin
        num_buffered_bytes = 8'd1;
        buffered_byte = lead_byte[7:0];
      end

      st.core.low = low;
      st.core.buffered_byte = buffered_byte;
      st.core.num_buffered_bytes = num_buffered_bytes;
      st.core.bits_left = bits_left;
      cabac_write_out = st;
    end
  endfunction

  function automatic cabac_writer_state_t cabac_finish(input cabac_writer_state_t st_in);
    cabac_writer_state_t st;
    logic [31:0] low;
    logic [8:0] buffered_byte;
    logic [7:0] num_buffered_bytes;
    integer bits_left;
    integer final_bits;
    integer repeat_i;
    begin
      st = st_in;
      low = st.core.low;
      buffered_byte = st.core.buffered_byte;
      num_buffered_bytes = st.core.num_buffered_bytes;
      bits_left = st.core.bits_left;

      if ((low >> (32 - bits_left)) != 0) begin
        st = cabac_write_bits(st, buffered_byte + 9'd1, 6'd8);
        num_buffered_bytes = st.core.num_buffered_bytes;
        for (repeat_i = 0; repeat_i < CABAC_PENDING_BYTES; repeat_i = repeat_i + 1) begin
          if (num_buffered_bytes > 8'd1) begin
            st = cabac_write_bits(st, 9'd0, 6'd8);
            num_buffered_bytes = num_buffered_bytes - 8'd1;
            st.core.num_buffered_bytes = num_buffered_bytes;
          end
        end
        low = low - (32'd1 << (32 - bits_left));
        st.core.low = low;
      end else begin
        if (num_buffered_bytes > 8'd0) begin
          st = cabac_write_bits(st, buffered_byte, 6'd8);
        end
        num_buffered_bytes = st.core.num_buffered_bytes;
        for (repeat_i = 0; repeat_i < CABAC_PENDING_BYTES; repeat_i = repeat_i + 1) begin
          if (num_buffered_bytes > 8'd1) begin
            st = cabac_write_bits(st, 9'h0ff, 6'd8);
            num_buffered_bytes = num_buffered_bytes - 8'd1;
            st.core.num_buffered_bytes = num_buffered_bytes;
          end
        end
      end

      final_bits = 24 - bits_left;
`ifdef FRAMEFORGE_RTL_CABAC_TRACE
      $display(
        "FF_RTL_STREAM_FINISH low=%08x bits_left=%0d final_bits=%0d partial_count=%0d partial=%02x pending=%0d",
        low,
        bits_left,
        final_bits,
        st.stream.partial_bit_count,
        st.stream.partial_byte,
        st.stream.pending_count
      );
`endif
      if (final_bits > 0) begin
        st = cabac_write_bits(st, low >> 8, final_bits[5:0]);
      end
      cabac_finish = st;
    end
  endfunction

  function automatic cabac_writer_state_t cabac_write_bits(
    input cabac_writer_state_t st_in,
    input logic [31:0] value,
    input logic [5:0] bit_count
  );
    cabac_writer_state_t st;
    logic [7:0] partial_byte;
    logic [3:0] partial_bit_count;
    integer i;
    begin
      st = st_in;
      partial_byte = st.stream.partial_byte;
      partial_bit_count = st.stream.partial_bit_count;
      for (i = 31; i >= 0; i = i - 1) begin
        if (i < bit_count) begin
          partial_byte = (partial_byte << 1) | value[i];
          partial_bit_count = partial_bit_count + 4'd1;
          st.stream.bit_count = st.stream.bit_count + 13'd1;
          if (partial_bit_count == 4'd8) begin
            st = cabac_append_pending_byte(st, partial_byte);
            partial_byte = 8'd0;
            partial_bit_count = 4'd0;
          end
        end
      end
      st.stream.partial_byte = partial_byte;
      st.stream.partial_bit_count = partial_bit_count[2:0];
      cabac_write_bits = st;
    end
  endfunction

  function automatic cabac_writer_state_t cabac_encode_bins_ep(
    input cabac_writer_state_t st_in,
    input logic [31:0] bin_pattern_in,
    input logic [5:0] num_bins_in
  );
    cabac_writer_state_t st;
    logic [31:0] low;
    logic [31:0] bin_pattern;
    logic [15:0] range;
    logic [31:0] pattern;
    integer bits_left;
    integer num_bins;
    integer step_i;
    begin
      st = st_in;
      bin_pattern = bin_pattern_in;
      num_bins = num_bins_in;
      low = st.core.low;
      range = st.core.range;
      bits_left = st.core.bits_left;

      for (step_i = 0; step_i < 4; step_i = step_i + 1) begin
        if (num_bins > 8) begin
          num_bins = num_bins - 8;
          pattern = bin_pattern >> num_bins;
          low = low << 8;
          low = low + (range * pattern);
          bin_pattern = bin_pattern - (pattern << num_bins);
          bits_left = bits_left - 8;
          st.core.low = low;
          st.core.bits_left = bits_left[7:0];
          if (bits_left < 12) begin
            st = cabac_write_out(st);
            low = st.core.low;
            bits_left = st.core.bits_left;
          end
        end
      end

      low = low << num_bins;
      low = low + (range * bin_pattern);
      bits_left = bits_left - num_bins;
      st.core.low = low;
      st.core.bits_left = bits_left[7:0];
      if (bits_left < 12) begin
        st = cabac_write_out(st);
      end
      cabac_encode_bins_ep = st;
    end
  endfunction

  function automatic cabac_writer_state_t cabac_append_pending_byte(
    input cabac_writer_state_t st_in,
    input logic [7:0] value
  );
    cabac_writer_state_t st;
    logic [CABAC_PENDING_BITS - 1:0] shifted_value;
    integer bit_offset;
    begin
      st = st_in;
      if (st.stream.pending_count < CABAC_PENDING_BYTES[3:0]) begin
        bit_offset = st.stream.pending_count * 8;
        shifted_value = {{(CABAC_PENDING_BITS - 8){1'b0}}, value} << bit_offset;
        st.stream.pending_bytes = st.stream.pending_bytes | shifted_value;
        st.stream.pending_count = st.stream.pending_count + 4'd1;
      end else begin
        st.stream.overflow = 1'b1;
      end
      cabac_append_pending_byte = st;
    end
  endfunction

  function automatic cabac_writer_state_t cabac_pop_pending_byte(input cabac_writer_state_t st_in);
    cabac_writer_state_t st;
    begin
      st = st_in;
      if (st.stream.pending_count != 4'd0) begin
        st.stream.pending_bytes = st.stream.pending_bytes >> 8;
        st.stream.pending_count = st.stream.pending_count - 4'd1;
      end
      cabac_pop_pending_byte = st;
    end
  endfunction

  function automatic cabac_writer_state_t cabac_flush_partial_byte(input cabac_writer_state_t st_in);
    cabac_writer_state_t st;
    logic [2:0] pad_bits;
    begin
      st = st_in;
      if (st.stream.partial_bit_count != 3'd0) begin
        pad_bits = 3'd0 - st.stream.partial_bit_count;
        st = cabac_append_pending_byte(st, st.stream.partial_byte << pad_bits);
        st.stream.partial_byte = 8'd0;
        st.stream.partial_bit_count = 3'd0;
      end
      cabac_flush_partial_byte = st;
    end
  endfunction
endmodule
