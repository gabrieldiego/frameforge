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
  localparam int CABAC_PENDING_BYTES = 8;
  localparam int CABAC_PENDING_BITS = CABAC_PENDING_BYTES * 8;
  localparam int VVC_PROB_MODEL_BITS = 40;
  localparam int VVC_CTX_COUNT = 32;
  localparam int VVC_CTX_QP = 32;

  typedef logic [VVC_PROB_MODEL_BITS - 1:0] vvc_prob_model_t;

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
  vvc_prob_model_t ctx_model_q [0:VVC_CTX_COUNT - 1];
  logic finishing_q;
  logic final_pending_q;
  logic queue_load_valid;
  logic queue_load_ready;
  logic queue_load_last;
  logic [3:0] queue_load_count;
  logic [CABAC_PENDING_BITS - 1:0] queue_load_bytes;
  logic queue_idle;
  logic queue_last_accepted;
  integer ctx_i;

  assign s_axis_ready = queue_idle && (writer_q.stream.pending_count == 4'd0) && !finishing_q;
  assign stream_last_byte_bits = writer_q.stream.bit_count[2:0];
  assign queue_load_valid = writer_q.stream.pending_count != 4'd0;
  assign queue_load_count = writer_q.stream.pending_count;
  assign queue_load_bytes = writer_q.stream.pending_bytes;
  assign queue_load_last = final_pending_q && (writer_q.stream.partial_bit_count == 3'd0);

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
      for (ctx_i = 0; ctx_i < VVC_CTX_COUNT; ctx_i = ctx_i + 1) begin
        ctx_model_q[ctx_i] <= vvc_context_model_init(ctx_i[4:0]);
      end
      finishing_q <= 1'b0;
      final_pending_q <= 1'b0;
      done <= 1'b0;
    end else if (clear) begin
      writer_q <= cabac_start();
      for (ctx_i = 0; ctx_i < VVC_CTX_COUNT; ctx_i = ctx_i + 1) begin
        ctx_model_q[ctx_i] <= vvc_context_model_init(ctx_i[4:0]);
      end
      finishing_q <= 1'b0;
      final_pending_q <= 1'b0;
      done <= 1'b0;
    end else begin
      done <= 1'b0;

      if (start) begin
        writer_q <= cabac_start();
        for (ctx_i = 0; ctx_i < VVC_CTX_COUNT; ctx_i = ctx_i + 1) begin
          ctx_model_q[ctx_i] <= vvc_context_model_init(ctx_i[4:0]);
        end
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
                vvc_context_bank_id(s_axis_ctx_id),
                writer_q.core.range,
                vvc_prob_model_lps(ctx_model_q[vvc_context_bank_id(s_axis_ctx_id)], writer_q.core.range),
                vvc_prob_model_mps(ctx_model_q[vvc_context_bank_id(s_axis_ctx_id)]),
                s_axis_bin
              );
`endif
              writer_q <= cabac_encode_bin(
                writer_q,
                s_axis_bin,
                vvc_prob_model_lps(ctx_model_q[vvc_context_bank_id(s_axis_ctx_id)], writer_q.core.range),
                vvc_prob_model_mps(ctx_model_q[vvc_context_bank_id(s_axis_ctx_id)])
              );
              ctx_model_q[vvc_context_bank_id(s_axis_ctx_id)] <=
                vvc_prob_model_update(ctx_model_q[vvc_context_bank_id(s_axis_ctx_id)], s_axis_bin);
            end else begin
              writer_q <= cabac_encode_bin(writer_q, s_axis_bin, s_axis_lps, s_axis_mps);
            end
          end
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

  function automatic cabac_writer_state_t cabac_encode_bin_ep(
    input cabac_writer_state_t st_in,
    input logic bin
  );
    cabac_writer_state_t st;
    logic [31:0] low;
    logic [7:0] bits_left;
    begin
      st = st_in;
      low = st.core.low << 1;
      bits_left = st.core.bits_left - 8'd1;
      if (bin) begin
        low = low + st.core.range;
      end
      st.core.low = low;
      st.core.bits_left = bits_left;
      if (bits_left < 8'd12) begin
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
    logic [7:0] bits_left;
    logic [3:0] num_bits;
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
        st.core.bits_left = bits_left;
        if (bits_left < 8'd12) begin
          st = cabac_write_out(st);
        end
      end else if (range < 16'd256) begin
        num_bits = 4'd1;
        bits_left = bits_left - num_bits;
        low = low << num_bits;
        range = range << num_bits;
        st.core.low = low;
        st.core.range = range;
        st.core.bits_left = bits_left;
        if (bits_left < 8'd12) begin
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
    logic [7:0] bits_left;
    begin
      st = st_in;
      low = st.core.low;
      range = st.core.range - 16'd2;
      bits_left = st.core.bits_left;
      if (bin) begin
        low = low + range;
        low = low << 7;
        range = 16'd256;
        bits_left = bits_left - 8'd7;
      end else if (range < 16'd256) begin
        low = low << 1;
        range = range << 1;
        bits_left = bits_left - 8'd1;
      end
      st.core.low = low;
      st.core.range = range;
      st.core.bits_left = bits_left;
      if (bits_left < 8'd12) begin
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
      if (final_bits > 0) begin
        st = cabac_write_bits(st, low >> 8, final_bits[5:0]);
      end
      cabac_finish = st;
    end
  endfunction

  function automatic logic [3:0] floor_log2_u16(input logic [15:0] value);
    integer i;
    begin
      floor_log2_u16 = 4'd0;
      for (i = 0; i < 16; i = i + 1) begin
        if (value[i]) begin
          floor_log2_u16 = i[3:0];
        end
      end
    end
  endfunction

  function automatic logic [3:0] renorm_bits_sv(input logic [15:0] range_in);
    begin
      renorm_bits_sv = (range_in >= 16'd256) ? 4'd0 : (4'd8 - floor_log2_u16(range_in));
    end
  endfunction

  function automatic vvc_prob_model_t vvc_context_model_init(input logic [4:0] index);
    logic [7:0] init_value;
    logic [3:0] log2_window_size;
    begin
      init_value = 8'd31;
      log2_window_size = 4'd8;
      if (index < 5'd4) begin
        init_value = vvc_split_flag_init(index[3:0]);
        log2_window_size = vvc_split_flag_log2_window(index[3:0]);
      end else if (index < 5'd8) begin
        init_value = vvc_split_qt_flag_init(index[3:0] - 4'd4);
        log2_window_size = vvc_split_qt_flag_log2_window(index[3:0] - 4'd4);
      end else if (index == 5'd8) begin
        init_value = vvc_qt_cbf_y_init(4'd0);
        log2_window_size = vvc_qt_cbf_y_log2_window(4'd0);
      end else if (index < 5'd13) begin
        init_value = (index == 5'd9) ? vvc_multi_ref_line_idx_init(4'd0) :
          ((index == 5'd10) ? vvc_intra_luma_mpm_flag_init() :
          ((index == 5'd11) ? vvc_intra_luma_planar_flag_init(4'd1) :
                              vvc_mts_idx_init(4'd0)));
        log2_window_size = (index == 5'd9) ? vvc_multi_ref_line_idx_log2_window(4'd0) :
          ((index == 5'd10) ? vvc_intra_luma_mpm_flag_log2_window() :
          ((index == 5'd11) ? vvc_intra_luma_planar_flag_log2_window(4'd1) :
                              vvc_mts_idx_log2_window(4'd0)));
      end else if (index < 5'd16) begin
        init_value = vvc_intra_luma_planar_flag_init((index == 5'd13) ? 4'd0 : 4'd1);
        log2_window_size = vvc_intra_luma_planar_flag_log2_window((index == 5'd13) ? 4'd0 : 4'd1);
      end else begin
        init_value = vvc_qt_cbf_cb_init((index[3:0] == 4'd0) ? 4'd0 : 4'd1);
        log2_window_size = vvc_qt_cbf_cb_log2_window((index[3:0] == 4'd0) ? 4'd0 : 4'd1);
      end
      vvc_context_model_init = vvc_prob_model_init(init_value, log2_window_size, VVC_CTX_QP);
    end
  endfunction

  function automatic logic [4:0] vvc_context_bank_id(input logic [4:0] index);
    begin
      if ((index == 5'd14) || (index == 5'd15)) begin
        vvc_context_bank_id = 5'd11;
      end else if (index > 5'd17) begin
        vvc_context_bank_id = 5'd17;
      end else begin
        vvc_context_bank_id = index;
      end
    end
  endfunction

  function automatic vvc_prob_model_t vvc_prob_model_init(
    input logic [7:0] init_value,
    input logic [3:0] log2_window_size,
    input integer qp
  );
    integer slope;
    integer offset;
    integer inistate;
    logic [15:0] p_state;
    integer rate0;
    integer rate1;
    begin
      slope = (init_value >> 3) - 4;
      offset = ((init_value & 8'd7) * 18) + 1;
      inistate = ((slope * (qp - 16)) >>> 1) + offset;
      if (inistate < 1) begin
        inistate = 1;
      end else if (inistate > 127) begin
        inistate = 127;
      end
      p_state = inistate[15:0] << 8;
      rate0 = 2 + ((log2_window_size >> 2) & 3);
      rate1 = 3 + rate0 + (log2_window_size & 3);
      vvc_prob_model_init[0 +: 16] = p_state & 16'h7fe0;
      vvc_prob_model_init[16 +: 16] = p_state & 16'h7ffe;
      vvc_prob_model_init[32 +: 8] = ((rate0 & 8'h0f) << 4) | (rate1 & 8'h0f);
    end
  endfunction

  function automatic logic [7:0] vvc_prob_model_state(input vvc_prob_model_t model);
    logic [16:0] state_sum;
    begin
      state_sum = {1'b0, model[0 +: 16]} + {1'b0, model[16 +: 16]};
      vvc_prob_model_state = state_sum[15:8];
    end
  endfunction

  function automatic logic vvc_prob_model_mps(input vvc_prob_model_t model);
    logic [7:0] state;
    begin
      state = vvc_prob_model_state(model);
      vvc_prob_model_mps = state[7];
    end
  endfunction

  function automatic logic [8:0] vvc_prob_model_lps(
    input vvc_prob_model_t model,
    input logic [15:0] range
  );
    logic [15:0] q;
    logic [15:0] lps_full;
    begin
      q = {8'd0, vvc_prob_model_state(model)};
      if (q[7]) begin
        q = q ^ 16'h00ff;
      end
      lps_full = (((q >> 2) * (range >> 5)) >> 1) + 16'd4;
      vvc_prob_model_lps = lps_full[8:0];
    end
  endfunction

  function automatic vvc_prob_model_t vvc_prob_model_update(
    input vvc_prob_model_t model_in,
    input logic bin
  );
    logic [15:0] state0;
    logic [15:0] state1;
    logic [7:0] rate;
    integer rate0;
    integer rate1;
    begin
      state0 = model_in[0 +: 16];
      state1 = model_in[16 +: 16];
      rate = model_in[32 +: 8];
      rate0 = rate[7:4];
      rate1 = rate[3:0];
      state0 = state0 - ((state0 >> rate0) & 16'h7fe0);
      state1 = state1 - ((state1 >> rate1) & 16'h7ffe);
      if (bin) begin
        state0 = state0 + ((16'h7fff >> rate0) & 16'h7fe0);
        state1 = state1 + ((16'h7fff >> rate1) & 16'h7ffe);
      end
      vvc_prob_model_update = model_in;
      vvc_prob_model_update[0 +: 16] = state0;
      vvc_prob_model_update[16 +: 16] = state1;
    end
  endfunction

  function automatic logic [7:0] vvc_split_flag_init(input logic [3:0] index);
    begin
      case (index)
        4'd0: vvc_split_flag_init = 8'd19;
        4'd1: vvc_split_flag_init = 8'd28;
        4'd2: vvc_split_flag_init = 8'd38;
        4'd3: vvc_split_flag_init = 8'd27;
        4'd4: vvc_split_flag_init = 8'd29;
        4'd5: vvc_split_flag_init = 8'd38;
        4'd6: vvc_split_flag_init = 8'd20;
        4'd7: vvc_split_flag_init = 8'd30;
        default: vvc_split_flag_init = 8'd31;
      endcase
    end
  endfunction

  function automatic logic [3:0] vvc_split_flag_log2_window(input logic [3:0] index);
    begin
      case (index)
        4'd0: vvc_split_flag_log2_window = 4'd12;
        4'd1: vvc_split_flag_log2_window = 4'd13;
        4'd2: vvc_split_flag_log2_window = 4'd8;
        4'd3: vvc_split_flag_log2_window = 4'd8;
        4'd4: vvc_split_flag_log2_window = 4'd13;
        4'd5: vvc_split_flag_log2_window = 4'd12;
        4'd6: vvc_split_flag_log2_window = 4'd5;
        4'd7: vvc_split_flag_log2_window = 4'd9;
        default: vvc_split_flag_log2_window = 4'd9;
      endcase
    end
  endfunction

  function automatic logic [7:0] vvc_split_qt_flag_init(input logic [3:0] index);
    begin
      case (index)
        4'd0: vvc_split_qt_flag_init = 8'd27;
        4'd1: vvc_split_qt_flag_init = 8'd6;
        4'd2: vvc_split_qt_flag_init = 8'd15;
        4'd3: vvc_split_qt_flag_init = 8'd25;
        4'd4: vvc_split_qt_flag_init = 8'd19;
        default: vvc_split_qt_flag_init = 8'd37;
      endcase
    end
  endfunction

  function automatic logic [3:0] vvc_split_qt_flag_log2_window(input logic [3:0] index);
    begin
      case (index)
        4'd0: vvc_split_qt_flag_log2_window = 4'd0;
        4'd1: vvc_split_qt_flag_log2_window = 4'd8;
        4'd2: vvc_split_qt_flag_log2_window = 4'd8;
        4'd3: vvc_split_qt_flag_log2_window = 4'd12;
        4'd4: vvc_split_qt_flag_log2_window = 4'd12;
        default: vvc_split_qt_flag_log2_window = 4'd8;
      endcase
    end
  endfunction

  function automatic logic [7:0] vvc_multi_ref_line_idx_init(input logic [3:0] index);
    begin
      vvc_multi_ref_line_idx_init = (index == 4'd0) ? 8'd25 : 8'd60;
    end
  endfunction

  function automatic logic [3:0] vvc_multi_ref_line_idx_log2_window(input logic [3:0] index);
    begin
      vvc_multi_ref_line_idx_log2_window = (index == 4'd0) ? 4'd5 : 4'd8;
    end
  endfunction

  function automatic logic [7:0] vvc_intra_luma_mpm_flag_init();
    begin
      vvc_intra_luma_mpm_flag_init = 8'd45;
    end
  endfunction

  function automatic logic [3:0] vvc_intra_luma_mpm_flag_log2_window();
    begin
      vvc_intra_luma_mpm_flag_log2_window = 4'd6;
    end
  endfunction

  function automatic logic [7:0] vvc_intra_luma_planar_flag_init(input logic [3:0] index);
    begin
      vvc_intra_luma_planar_flag_init = (index == 4'd0) ? 8'd13 : 8'd28;
    end
  endfunction

  function automatic logic [3:0] vvc_intra_luma_planar_flag_log2_window(input logic [3:0] index);
    begin
      vvc_intra_luma_planar_flag_log2_window = (index == 4'd0) ? 4'd1 : 4'd5;
    end
  endfunction

  function automatic logic [7:0] vvc_qt_cbf_y_init(input logic [3:0] index);
    begin
      case (index)
        4'd0: vvc_qt_cbf_y_init = 8'd15;
        4'd1: vvc_qt_cbf_y_init = 8'd12;
        4'd2: vvc_qt_cbf_y_init = 8'd5;
        default: vvc_qt_cbf_y_init = 8'd7;
      endcase
    end
  endfunction

  function automatic logic [3:0] vvc_qt_cbf_y_log2_window(input logic [3:0] index);
    begin
      case (index)
        4'd0: vvc_qt_cbf_y_log2_window = 4'd5;
        4'd1: vvc_qt_cbf_y_log2_window = 4'd1;
        4'd2: vvc_qt_cbf_y_log2_window = 4'd8;
        default: vvc_qt_cbf_y_log2_window = 4'd9;
      endcase
    end
  endfunction

  function automatic logic [7:0] vvc_qt_cbf_cb_init(input logic [3:0] index);
    begin
      vvc_qt_cbf_cb_init = 8'd12;
    end
  endfunction

  function automatic logic [3:0] vvc_qt_cbf_cb_log2_window(input logic [3:0] index);
    begin
      vvc_qt_cbf_cb_log2_window = (index == 4'd0) ? 4'd5 : 4'd4;
    end
  endfunction

  function automatic logic [7:0] vvc_mts_idx_init(input logic [3:0] index);
    begin
      case (index)
        4'd0: vvc_mts_idx_init = 8'd29;
        4'd1: vvc_mts_idx_init = 8'd0;
        4'd2: vvc_mts_idx_init = 8'd28;
        default: vvc_mts_idx_init = 8'd0;
      endcase
    end
  endfunction

  function automatic logic [3:0] vvc_mts_idx_log2_window(input logic [3:0] index);
    begin
      case (index)
        4'd0: vvc_mts_idx_log2_window = 4'd8;
        4'd1: vvc_mts_idx_log2_window = 4'd0;
        4'd2: vvc_mts_idx_log2_window = 4'd9;
        default: vvc_mts_idx_log2_window = 4'd0;
      endcase
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
        st = cabac_write_bits(st, st.stream.partial_byte << pad_bits, pad_bits);
        st.stream.partial_byte = 8'd0;
        st.stream.partial_bit_count = 3'd0;
      end
      cabac_flush_partial_byte = st;
    end
  endfunction
endmodule
