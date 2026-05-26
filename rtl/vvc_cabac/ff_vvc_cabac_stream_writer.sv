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
    logic [7:0]  pending_byte0;
    logic [7:0]  pending_byte1;
    logic [7:0]  pending_byte2;
    logic [7:0]  pending_byte3;
    logic [7:0]  pending_byte4;
    logic [7:0]  pending_byte5;
    logic [7:0]  pending_byte6;
    logic [7:0]  pending_byte7;
    logic        overflow;
  } cabac_stream_state_t;

  typedef struct packed {
    cabac_core_state_t core;
    cabac_stream_state_t stream;
  } cabac_writer_state_t;

  cabac_writer_state_t writer_q;
  logic finishing_q;
  logic final_pending_q;

  assign s_axis_ready = !m_axis_valid && (writer_q.stream.pending_count == 4'd0) && !finishing_q;
  assign stream_last_byte_bits = writer_q.stream.bit_count[2:0];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      writer_q <= cabac_start();
      finishing_q <= 1'b0;
      final_pending_q <= 1'b0;
      m_axis_valid <= 1'b0;
      m_axis_data <= 8'd0;
      m_axis_last <= 1'b0;
      done <= 1'b0;
    end else if (clear) begin
      writer_q <= cabac_start();
      finishing_q <= 1'b0;
      final_pending_q <= 1'b0;
      m_axis_valid <= 1'b0;
      m_axis_data <= 8'd0;
      m_axis_last <= 1'b0;
      done <= 1'b0;
    end else begin
      done <= 1'b0;

      if (start) begin
        writer_q <= cabac_start();
        finishing_q <= 1'b0;
        final_pending_q <= 1'b0;
        m_axis_valid <= 1'b0;
        m_axis_data <= 8'd0;
        m_axis_last <= 1'b0;
      end else if (m_axis_valid && !m_axis_ready) begin
        m_axis_valid <= m_axis_valid;
        m_axis_data <= m_axis_data;
        m_axis_last <= m_axis_last;
      end else if (m_axis_valid && m_axis_ready) begin
        m_axis_valid <= 1'b0;
        m_axis_data <= 8'd0;
        if (m_axis_last) begin
          m_axis_last <= 1'b0;
          done <= 1'b1;
          finishing_q <= 1'b0;
          final_pending_q <= 1'b0;
          writer_q <= cabac_start();
        end else begin
          m_axis_last <= 1'b0;
        end
      end else if (writer_q.stream.pending_count != 4'd0) begin
        m_axis_valid <= 1'b1;
        m_axis_data <= writer_q.stream.pending_byte0;
        m_axis_last <= final_pending_q &&
                       (writer_q.stream.pending_count == 4'd1) &&
                       (writer_q.stream.partial_bit_count == 3'd0);
        writer_q <= cabac_pop_pending_byte(writer_q);
        if (final_pending_q && (writer_q.stream.pending_count == 4'd1) &&
            (writer_q.stream.partial_bit_count == 3'd0)) begin
          finishing_q <= 1'b0;
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
          CABAC_BIN_CTX: writer_q <= cabac_encode_bin(writer_q, s_axis_bin, s_axis_lps, s_axis_mps);
          CABAC_BIN_TRM: writer_q <= cabac_encode_bin_trm(writer_q, s_axis_bin);
          default:       writer_q <= cabac_encode_bin_ep(writer_q, s_axis_bin);
        endcase
        if (s_axis_last) begin
          finishing_q <= 1'b1;
        end
      end
    end
  end

  function automatic cabac_writer_state_t cabac_start();
    begin
      cabac_start = '0;
      cabac_start.core.low = 32'd0;
      cabac_start.core.range = 16'd510;
      cabac_start.core.buffered_byte = 9'h0ff;
      cabac_start.core.num_buffered_bytes = 8'd0;
      cabac_start.core.bits_left = 8'd23;
    end
  endfunction

  function automatic cabac_writer_state_t cabac_encode_bin_ep(
    input cabac_writer_state_t st_in,
    input logic bin
  );
    cabac_writer_state_t st;
    logic [31:0] low;
    integer bits_left;
    begin
      st = st_in;
      low = st.core.low << 1;
      bits_left = st.core.bits_left - 1;
      if (bin) begin
        low = low + st.core.range;
      end
      st.core.low = low;
      st.core.bits_left = bits_left[7:0];
      if (bits_left < 12) begin
        st = cabac_write_out(st);
      end
      cabac_encode_bin_ep = st;
    end
  endfunction

  function automatic cabac_writer_state_t cabac_encode_bin(
    input cabac_writer_state_t st_in,
    input logic bin,
    input logic [8:0] lps_in,
    input logic mps
  );
    cabac_writer_state_t st;
    logic [31:0] low;
    logic [15:0] range;
    logic [8:0] lps;
    integer bits_left;
    integer num_bits;
    begin
      st = st_in;
      low = st.core.low;
      range = st.core.range;
      bits_left = st.core.bits_left;
      lps = lps_in;

      range = range - lps;
      if (bin != mps) begin
        num_bits = renorm_bits_sv(lps);
        bits_left = bits_left - num_bits;
        low = low + range;
        low = low << num_bits;
        range = lps << num_bits;
        st.core.low = low;
        st.core.range = range;
        st.core.bits_left = bits_left[7:0];
        if (bits_left < 12) begin
          st = cabac_write_out(st);
        end
      end else if (range < 16'd256) begin
        num_bits = 1;
        bits_left = bits_left - num_bits;
        low = low << num_bits;
        range = range << num_bits;
        st.core.low = low;
        st.core.range = range;
        st.core.bits_left = bits_left[7:0];
        if (bits_left < 12) begin
          st = cabac_write_out(st);
        end
      end else begin
        st.core.range = range;
      end
      cabac_encode_bin = st;
    end
  endfunction

  function automatic cabac_writer_state_t cabac_encode_bin_trm(
    input cabac_writer_state_t st_in,
    input logic bin
  );
    cabac_writer_state_t st;
    logic [31:0] low;
    logic [15:0] range;
    integer bits_left;
    begin
      st = st_in;
      low = st.core.low;
      range = st.core.range - 16'd2;
      bits_left = st.core.bits_left;
      if (bin) begin
        low = low + range;
        low = low << 7;
        range = 16'd256;
        bits_left = bits_left - 7;
      end else if (range < 16'd256) begin
        low = low << 1;
        range = range << 1;
        bits_left = bits_left - 1;
      end
      st.core.low = low;
      st.core.range = range;
      st.core.bits_left = bits_left[7:0];
      if (bits_left < 12) begin
        st = cabac_write_out(st);
      end
      cabac_encode_bin_trm = st;
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
    integer bits_left;
    begin
      st = st_in;
      low = st.core.low;
      bits_left = st.core.bits_left;
      buffered_byte = st.core.buffered_byte;
      num_buffered_bytes = st.core.num_buffered_bytes;
      lead_byte = low >> (24 - bits_left);
      bits_left = bits_left + 8;
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
        while (num_buffered_bytes > 8'd1) begin
          st = cabac_write_bits(st, repeated_byte, 6'd8);
          num_buffered_bytes = num_buffered_bytes - 8'd1;
          st.core.num_buffered_bytes = num_buffered_bytes;
        end
      end else begin
        num_buffered_bytes = 8'd1;
        buffered_byte = lead_byte[7:0];
      end

      st.core.low = low;
      st.core.buffered_byte = buffered_byte;
      st.core.num_buffered_bytes = num_buffered_bytes;
      st.core.bits_left = bits_left[7:0];
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
    begin
      st = st_in;
      low = st.core.low;
      buffered_byte = st.core.buffered_byte;
      num_buffered_bytes = st.core.num_buffered_bytes;
      bits_left = st.core.bits_left;

      if ((low >> (32 - bits_left)) != 0) begin
        st = cabac_write_bits(st, buffered_byte + 9'd1, 6'd8);
        num_buffered_bytes = st.core.num_buffered_bytes;
        while (num_buffered_bytes > 8'd1) begin
          st = cabac_write_bits(st, 9'd0, 6'd8);
          num_buffered_bytes = num_buffered_bytes - 8'd1;
          st.core.num_buffered_bytes = num_buffered_bytes;
        end
        low = low - (32'd1 << (32 - bits_left));
        st.core.low = low;
      end else begin
        if (num_buffered_bytes > 8'd0) begin
          st = cabac_write_bits(st, buffered_byte, 6'd8);
        end
        num_buffered_bytes = st.core.num_buffered_bytes;
        while (num_buffered_bytes > 8'd1) begin
          st = cabac_write_bits(st, 9'h0ff, 6'd8);
          num_buffered_bytes = num_buffered_bytes - 8'd1;
          st.core.num_buffered_bytes = num_buffered_bytes;
        end
      end

      final_bits = 24 - bits_left;
      if (final_bits > 0) begin
        st = cabac_write_bits(st, low >> 8, final_bits[5:0]);
      end
      cabac_finish = st;
    end
  endfunction

  function automatic logic [3:0] renorm_bits_sv(input logic [15:0] range_in);
    logic [15:0] range;
    logic [3:0] count;
    begin
      range = range_in;
      count = 4'd0;
      while (range < 16'd256) begin
        range = range << 1;
        count = count + 4'd1;
      end
      renorm_bits_sv = count;
    end
  endfunction

  function automatic cabac_writer_state_t cabac_write_bits(
    input cabac_writer_state_t st_in,
    input logic [31:0] value,
    input logic [5:0] bit_count
  );
    cabac_writer_state_t st;
    logic [7:0] partial_byte;
    integer partial_bit_count;
    integer i;
    begin
      st = st_in;
      partial_byte = st.stream.partial_byte;
      partial_bit_count = st.stream.partial_bit_count;
      for (i = bit_count - 1; i >= 0; i = i - 1) begin
        partial_byte = (partial_byte << 1) | value[i];
        partial_bit_count = partial_bit_count + 1;
        st.stream.bit_count = st.stream.bit_count + 13'd1;
        if (partial_bit_count == 8) begin
          st = cabac_append_pending_byte(st, partial_byte);
          partial_byte = 8'd0;
          partial_bit_count = 0;
        end
      end
      st.stream.partial_byte = partial_byte;
      st.stream.partial_bit_count = partial_bit_count[2:0];
      cabac_write_bits = st;
    end
  endfunction

  function automatic cabac_writer_state_t cabac_append_pending_byte(
    input cabac_writer_state_t st_in,
    input logic [7:0] value
  );
    cabac_writer_state_t st;
    begin
      st = st_in;
      case (st.stream.pending_count)
        4'd0: begin
          st.stream.pending_byte0 = value;
          st.stream.pending_count = 4'd1;
        end
        4'd1: begin
          st.stream.pending_byte1 = value;
          st.stream.pending_count = 4'd2;
        end
        4'd2: begin
          st.stream.pending_byte2 = value;
          st.stream.pending_count = 4'd3;
        end
        4'd3: begin
          st.stream.pending_byte3 = value;
          st.stream.pending_count = 4'd4;
        end
        4'd4: begin
          st.stream.pending_byte4 = value;
          st.stream.pending_count = 4'd5;
        end
        4'd5: begin
          st.stream.pending_byte5 = value;
          st.stream.pending_count = 4'd6;
        end
        4'd6: begin
          st.stream.pending_byte6 = value;
          st.stream.pending_count = 4'd7;
        end
        4'd7: begin
          st.stream.pending_byte7 = value;
          st.stream.pending_count = 4'd8;
        end
        default: begin
          st.stream.overflow = 1'b1;
        end
      endcase
      cabac_append_pending_byte = st;
    end
  endfunction

  function automatic cabac_writer_state_t cabac_pop_pending_byte(input cabac_writer_state_t st_in);
    cabac_writer_state_t st;
    begin
      st = st_in;
      if (st.stream.pending_count != 4'd0) begin
        st.stream.pending_byte0 = st.stream.pending_byte1;
        st.stream.pending_byte1 = st.stream.pending_byte2;
        st.stream.pending_byte2 = st.stream.pending_byte3;
        st.stream.pending_byte3 = st.stream.pending_byte4;
        st.stream.pending_byte4 = st.stream.pending_byte5;
        st.stream.pending_byte5 = st.stream.pending_byte6;
        st.stream.pending_byte6 = st.stream.pending_byte7;
        st.stream.pending_byte7 = 8'd0;
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
        st = cabac_write_bits(st, st.stream.partial_byte << pad_bits, pad_bits);
        st.stream.partial_byte = 8'd0;
        st.stream.partial_bit_count = 3'd0;
      end
      cabac_flush_partial_byte = st;
    end
  endfunction
endmodule
