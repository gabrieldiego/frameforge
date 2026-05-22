`timescale 1ns/1ps

module ff_vvc_palette_cabac #(
  parameter int MAX_PALETTE_SYMBOLS = 64,
  parameter int MAX_SLICE_PAYLOAD_BITS = 4096
) (
  input  logic clk,
  input  logic rst_n,
  input  logic clear,
  input  logic enable,
  input  logic [15:0] coded_width,
  input  logic [15:0] coded_height,
  input  logic [7:0]  symbol_count,
  input  logic        s_axis_valid,
  output logic        s_axis_ready,
  input  logic [31:0] s_axis_data,
  input  logic        s_axis_last,
  output logic [12:0] payload_bit_len,
  output logic [MAX_SLICE_PAYLOAD_BITS - 1:0] payload_bits
);
  localparam int CABAC_BITS_LSB = 0;
  localparam int CABAC_LEN_LSB = CABAC_BITS_LSB + MAX_SLICE_PAYLOAD_BITS;
  localparam int CABAC_LOW_LSB = CABAC_LEN_LSB + 13;
  localparam int CABAC_RANGE_LSB = CABAC_LOW_LSB + 32;
  localparam int CABAC_BUFFERED_BYTE_LSB = CABAC_RANGE_LSB + 16;
  localparam int CABAC_NUM_BUFFERED_BYTES_LSB = CABAC_BUFFERED_BYTE_LSB + 9;
  localparam int CABAC_BITS_LEFT_LSB = CABAC_NUM_BUFFERED_BYTES_LSB + 8;
  localparam int CABAC_STATE_BITS = CABAC_BITS_LEFT_LSB + 8;
  localparam int PALETTE_MODEL_BITS = 40;
  localparam int PALETTE_CTX_COUNT = 11;
  localparam int PALETTE_CTX_SPLIT0 = 0;
  localparam int PALETTE_CTX_SPLIT6 = 1;
  localparam int PALETTE_CTX_SPLIT7 = 2;
  localparam int PALETTE_CTX_SPLIT8 = 3;
  localparam int PALETTE_CTX_SPLIT_QT9 = 4;
  localparam int PALETTE_CTX_SPLIT_QT10 = 5;
  localparam int PALETTE_CTX_SPLIT_QT11 = 6;
  localparam int PALETTE_CTX_SPLIT_QT12 = 7;
  localparam int PALETTE_CTX_SPLIT_QT13 = 8;
  localparam int PALETTE_CTX_SPLIT_QT14 = 9;
  localparam int PALETTE_CTX_PLT_FLAG = 10;
  localparam int PALETTE_CABAC_LSB = 0;
  localparam int PALETTE_MODEL_LSB = PALETTE_CABAC_LSB + CABAC_STATE_BITS;
  localparam int PALETTE_STATE_BITS = PALETTE_MODEL_LSB + (PALETTE_CTX_COUNT * PALETTE_MODEL_BITS);

  typedef logic [CABAC_STATE_BITS - 1:0] cabac_state_t;
  typedef logic [PALETTE_STATE_BITS - 1:0] palette_state_t;

  palette_state_t palette_state_q;
  logic [7:0]     stream_symbol_index_q;

  assign s_axis_ready = enable && (stream_symbol_index_q < symbol_count);
  assign payload_bit_len = palette_state_q[PALETTE_CABAC_LSB + CABAC_LEN_LSB +: 13];
  assign payload_bits = palette_state_q[PALETTE_CABAC_LSB + CABAC_BITS_LSB +: MAX_SLICE_PAYLOAD_BITS];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      stream_symbol_index_q <= 8'd0;
      palette_state_q <= palette_start();
    end else if (clear || !enable) begin
      stream_symbol_index_q <= 8'd0;
      palette_state_q <= palette_start();
    end else if (s_axis_valid && s_axis_ready) begin
      if (s_axis_last) begin
        palette_state_q <= palette_finish(palette_444_encode_next_symbol(
          palette_state_q,
          stream_symbol_index_q,
          s_axis_data[23:0]
        ));
        stream_symbol_index_q <= 8'd0;
      end else begin
        palette_state_q <= palette_444_encode_next_symbol(
          palette_state_q,
          stream_symbol_index_q,
          s_axis_data[23:0]
        );
        stream_symbol_index_q <= stream_symbol_index_q + 8'd1;
      end
    end
  end

  function automatic palette_state_t palette_finish(input palette_state_t pst_in);
    palette_state_t pst;
    cabac_state_t st;
    begin
      pst = pst_in;
      st = pst[PALETTE_CABAC_LSB +: CABAC_STATE_BITS];
      st = cabac_encode_bin_trm(st, 1'b1);
      st = cabac_finish(st);
      pst[PALETTE_CABAC_LSB +: CABAC_STATE_BITS] = st;
      palette_finish = pst;
    end
  endfunction

  function automatic palette_state_t palette_444_encode_next_symbol(
    input palette_state_t pst_in,
    input logic [7:0] symbol_index,
    input logic [23:0] symbol
  );
    palette_state_t pst;
    logic [31:0] pos;
    logic [15:0] origin_x;
    logic [15:0] origin_y;
    begin
      pst = pst_in;
      pos = palette_coding_order_position(symbol_index);
      origin_x = pos[31:16];
      origin_y = pos[15:0];

      if (coded_width == 16'd64 && coded_height == 16'd64 && symbol_index == 8'd0) begin
        pst = palette_encode_ctx(pst, PALETTE_CTX_SPLIT0, 1'b1);
      end
      if (coded_width >= 16'd32 && coded_height >= 16'd32 && symbol_index[3:0] == 4'd0) begin
        pst = palette_encode_ctx(pst, palette_split_ctx_id(origin_x, origin_y, 16'd32), 1'b1);
        pst = palette_encode_ctx(pst, palette_split_qt_ctx_id(origin_x, origin_y, 16'd32, 1'b1), 1'b1);
      end
      if (coded_width >= 16'd16 && coded_height >= 16'd16 && symbol_index[1:0] == 2'd0) begin
        pst = palette_encode_ctx(pst, palette_split_ctx_id(origin_x, origin_y, 16'd16), 1'b1);
        pst = palette_encode_ctx(pst, palette_split_qt_ctx_id(origin_x, origin_y, 16'd16, 1'b0), 1'b1);
      end

      pst = palette_444_encode_8x8_symbol(pst, origin_x, origin_y, symbol_index == 8'd0, symbol);
      palette_444_encode_next_symbol = pst;
    end
  endfunction

  function automatic logic [31:0] palette_coding_order_position(input logic [7:0] index);
    logic [15:0] origin_x;
    logic [15:0] origin_y;
    logic [7:0]  index_in_32;
    logic [7:0]  index_in_16;
    begin
      origin_x = 16'd0;
      origin_y = 16'd0;
      if (coded_width == 16'd64 && coded_height == 16'd64) begin
        origin_x = index[4] ? 16'd32 : 16'd0;
        origin_y = index[5] ? 16'd32 : 16'd0;
        index_in_32 = {4'd0, index[3:0]};
      end else begin
        index_in_32 = index;
      end

      if (coded_width >= 16'd32 && coded_height >= 16'd32) begin
        origin_x = origin_x + (index_in_32[2] ? 16'd16 : 16'd0);
        origin_y = origin_y + (index_in_32[3] ? 16'd16 : 16'd0);
        index_in_16 = {6'd0, index_in_32[1:0]};
      end else begin
        index_in_16 = index_in_32;
      end

      if (coded_width >= 16'd16 && coded_height >= 16'd16) begin
        origin_x = origin_x + (index_in_16[0] ? 16'd8 : 16'd0);
        origin_y = origin_y + (index_in_16[1] ? 16'd8 : 16'd0);
      end else begin
        origin_x = (index_in_16[2:0] << 3);
        origin_y = (index_in_16[5:3] << 3);
      end

      palette_coding_order_position = {origin_x, origin_y};
    end
  endfunction

  function automatic palette_state_t palette_444_encode_8x8_symbol(
    input palette_state_t pst_in,
    input logic [15:0] origin_x,
    input logic [15:0] origin_y,
    input logic signal_new_entry,
    input logic [23:0] symbol
  );
    palette_state_t pst;
    cabac_state_t st;
    logic [7:0] entry_y;
    logic [7:0] entry_u;
    logic [7:0] entry_v;
    begin
      pst = pst_in;
      pst = palette_encode_ctx(pst, PALETTE_CTX_SPLIT0, 1'b0);    // split_cu_mode split=0 for an 8x8 palette CU
      pst = palette_encode_ctx(pst, PALETTE_CTX_PLT_FLAG, 1'b1);  // pred_mode PLTFlag=1
      st = pst[PALETTE_CABAC_LSB +: CABAC_STATE_BITS];
      entry_y = symbol[23:16];
      entry_u = symbol[15:8];
      entry_v = symbol[7:0];
      if (!signal_new_entry) begin
        st = cabac_encode_exp_golomb_ep(st, 6'd1, 6'd0); // palette_predictor_run=1: no reused entries
      end
      st = cabac_encode_exp_golomb_ep(st, 6'd1, 6'd0); // num_signalled_palette_entries=1
      st = cabac_encode_bins_ep(st, {24'd0, entry_y}, 6'd8);
      st = cabac_encode_bins_ep(st, {24'd0, entry_u}, 6'd8);
      st = cabac_encode_bins_ep(st, {24'd0, entry_v}, 6'd8);
      st = cabac_encode_bin_ep(st, 1'b0); // palette_escape_val_present_flag=0
      pst[PALETTE_CABAC_LSB +: CABAC_STATE_BITS] = st;
      palette_444_encode_8x8_symbol = pst;
    end
  endfunction

  function automatic int palette_model_lsb(input int ctx_id);
    begin
      palette_model_lsb = PALETTE_MODEL_LSB + (ctx_id * PALETTE_MODEL_BITS);
    end
  endfunction

  function automatic palette_state_t palette_start();
    palette_state_t pst;
    begin
      pst = '0;
      pst[PALETTE_CABAC_LSB +: CABAC_STATE_BITS] = cabac_start();
      pst = palette_init_model(pst, PALETTE_CTX_SPLIT0, 8'd78, 8'd12);
      pst = palette_init_model(pst, PALETTE_CTX_SPLIT6, 8'd114, 8'd5);
      pst = palette_init_model(pst, PALETTE_CTX_SPLIT7, 8'd202, 8'd9);
      pst = palette_init_model(pst, PALETTE_CTX_SPLIT8, 8'd238, 8'd9);
      pst = palette_init_model(pst, PALETTE_CTX_SPLIT_QT9, 8'd94, 8'd0);
      pst = palette_init_model(pst, PALETTE_CTX_SPLIT_QT10, 8'd154, 8'd8);
      pst = palette_init_model(pst, PALETTE_CTX_SPLIT_QT11, 8'd206, 8'd8);
      pst = palette_init_model(pst, PALETTE_CTX_SPLIT_QT12, 8'd22, 8'd12);
      pst = palette_init_model(pst, PALETTE_CTX_SPLIT_QT13, 8'd78, 8'd12);
      pst = palette_init_model(pst, PALETTE_CTX_SPLIT_QT14, 8'd182, 8'd8);
      pst = palette_init_model(pst, PALETTE_CTX_PLT_FLAG, 8'd22, 8'd1);
      palette_start = pst;
    end
  endfunction

  function automatic palette_state_t palette_init_model(
    input palette_state_t pst_in,
    input int ctx_id,
    input logic [7:0] state,
    input logic [7:0] log2_window_size
  );
    palette_state_t pst;
    int lsb;
    logic [15:0] pstate;
    logic [3:0] rate0;
    logic [3:0] rate1;
    begin
      pst = pst_in;
      lsb = palette_model_lsb(ctx_id);
      pstate = {state, 8'd0};
      pst[lsb +: 16] = (pstate >> 1) & 16'h7fe0;
      pst[lsb + 16 +: 16] = (pstate >> 1) & 16'h7ffe;
      rate0 = 4'd2 + {2'd0, log2_window_size[3:2]};
      rate1 = 4'd3 + rate0 + {2'd0, log2_window_size[1:0]};
      pst[lsb + 32 +: 8] = {rate0, rate1};
      palette_init_model = pst;
    end
  endfunction

  function automatic logic [7:0] palette_model_state(input palette_state_t pst, input int ctx_id);
    int lsb;
    logic [16:0] sum;
    begin
      lsb = palette_model_lsb(ctx_id);
      sum = {1'b0, pst[lsb +: 16]} + {1'b0, pst[lsb + 16 +: 16]};
      palette_model_state = sum[15:8];
    end
  endfunction

  function automatic logic palette_model_mps(input palette_state_t pst, input int ctx_id);
    logic [7:0] state;
    begin
      state = palette_model_state(pst, ctx_id);
      palette_model_mps = state[7];
    end
  endfunction

  function automatic logic [8:0] palette_model_lps(
    input palette_state_t pst,
    input int ctx_id,
    input logic [15:0] range
  );
    logic [7:0] q;
    begin
      q = palette_model_state(pst, ctx_id);
      if (q[7]) begin
        q = q ^ 8'hff;
      end
      palette_model_lps = ((({1'b0, q >> 2}) * ({1'b0, range >> 5})) >> 1) + 9'd4;
    end
  endfunction

  function automatic palette_state_t palette_encode_ctx(
    input palette_state_t pst_in,
    input int ctx_id,
    input logic bin
  );
    palette_state_t pst;
    cabac_state_t st;
    begin
      pst = pst_in;
      st = pst[PALETTE_CABAC_LSB +: CABAC_STATE_BITS];
      st = cabac_encode_bin(
        st,
        bin,
        palette_model_lps(pst, ctx_id, st[CABAC_RANGE_LSB +: 16]),
        palette_model_mps(pst, ctx_id)
      );
      pst[PALETTE_CABAC_LSB +: CABAC_STATE_BITS] = st;
      pst = palette_update_model(pst, ctx_id, bin);
      palette_encode_ctx = pst;
    end
  endfunction

  function automatic palette_state_t palette_update_model(
    input palette_state_t pst_in,
    input int ctx_id,
    input logic bin
  );
    palette_state_t pst;
    int lsb;
    logic [15:0] state0;
    logic [15:0] state1;
    logic [7:0] rate;
    logic [3:0] rate0;
    logic [3:0] rate1;
    begin
      pst = pst_in;
      lsb = palette_model_lsb(ctx_id);
      state0 = pst[lsb +: 16];
      state1 = pst[lsb + 16 +: 16];
      rate = pst[lsb + 32 +: 8];
      rate0 = rate[7:4];
      rate1 = rate[3:0];
      state0 = state0 - ((state0 >> rate0) & 16'h7fe0);
      state1 = state1 - ((state1 >> rate1) & 16'h7ffe);
      if (bin) begin
        state0 = state0 + ((16'h7fff >> rate0) & 16'h7fe0);
        state1 = state1 + ((16'h7fff >> rate1) & 16'h7ffe);
      end
      pst[lsb +: 16] = state0;
      pst[lsb + 16 +: 16] = state1;
      palette_update_model = pst;
    end
  endfunction

  function automatic int palette_position_ctx_index(
    input logic [15:0] x,
    input logic [15:0] y,
    input logic [15:0] step
  );
    begin
      palette_position_ctx_index = ((x >= step) ? 1 : 0) + ((y >= step) ? 1 : 0);
    end
  endfunction

  function automatic int palette_split_ctx_id(
    input logic [15:0] x,
    input logic [15:0] y,
    input logic [15:0] step
  );
    int idx;
    begin
      idx = palette_position_ctx_index(x, y, step);
      if (idx == 0) begin
        palette_split_ctx_id = PALETTE_CTX_SPLIT6;
      end else if (idx == 1) begin
        palette_split_ctx_id = PALETTE_CTX_SPLIT7;
      end else begin
        palette_split_ctx_id = PALETTE_CTX_SPLIT8;
      end
    end
  endfunction

  function automatic int palette_split_qt_ctx_id(
    input logic [15:0] x,
    input logic [15:0] y,
    input logic [15:0] step,
    input logic large_base
  );
    int idx;
    begin
      idx = palette_position_ctx_index(x, y, step);
      if (large_base) begin
        if (idx == 0) begin
          palette_split_qt_ctx_id = PALETTE_CTX_SPLIT_QT9;
        end else if (idx == 1) begin
          palette_split_qt_ctx_id = PALETTE_CTX_SPLIT_QT10;
        end else begin
          palette_split_qt_ctx_id = PALETTE_CTX_SPLIT_QT11;
        end
      end else begin
        if (idx == 0) begin
          palette_split_qt_ctx_id = PALETTE_CTX_SPLIT_QT12;
        end else if (idx == 1) begin
          palette_split_qt_ctx_id = PALETTE_CTX_SPLIT_QT13;
        end else begin
          palette_split_qt_ctx_id = PALETTE_CTX_SPLIT_QT14;
        end
      end
    end
  endfunction


  function automatic cabac_state_t cabac_start();
    begin
      cabac_start = '0;
      cabac_start[CABAC_LOW_LSB +: 32] = 32'd0;
      cabac_start[CABAC_RANGE_LSB +: 16] = 16'd510;
      cabac_start[CABAC_BUFFERED_BYTE_LSB +: 9] = 9'h0ff;
      cabac_start[CABAC_NUM_BUFFERED_BYTES_LSB +: 8] = 8'd0;
      cabac_start[CABAC_BITS_LEFT_LSB +: 8] = 8'd23;
    end
  endfunction

  function automatic cabac_state_t cabac_encode_ctx_bins(
    input cabac_state_t st_in,
    input logic [4:0]   ctx_offset,
    input logic [7:0]   bin_pattern,
    input logic [3:0]   num_bins
  );
    cabac_state_t st;
    integer i;

    begin
      st = st_in;
      for (i = 0; i < num_bins; i = i + 1) begin
        st = cabac_encode_bin(
          st,
          bin_pattern[num_bins - 1 - i],
          vvc_ctx_lps(ctx_offset + i[4:0]),
          vvc_ctx_mps(ctx_offset + i[4:0])
        );
      end
      cabac_encode_ctx_bins = st;
    end
  endfunction

  function automatic cabac_state_t cabac_encode_bin(
    input cabac_state_t st_in,
    input logic         bin,
    input logic [8:0]   lps_in,
    input logic         mps
  );
    cabac_state_t st;
    logic [31:0] low;
    logic [15:0] range;
    logic [8:0]  lps;
    integer bits_left;
    integer num_bits;

    begin
      st = st_in;
      low = st[CABAC_LOW_LSB +: 32];
      range = st[CABAC_RANGE_LSB +: 16];
      bits_left = st[CABAC_BITS_LEFT_LSB +: 8];
      lps = lps_in;

      range = range - lps;
      if (bin != mps) begin
        num_bits = renorm_bits_sv(lps);
        bits_left = bits_left - num_bits;
        low = low + range;
        low = low << num_bits;
        range = lps << num_bits;
        st[CABAC_LOW_LSB +: 32] = low;
        st[CABAC_RANGE_LSB +: 16] = range;
        st[CABAC_BITS_LEFT_LSB +: 8] = bits_left[7:0];
        if (bits_left < 12) begin
          st = cabac_write_out(st);
        end
      end else if (range < 16'd256) begin
        num_bits = renorm_bits_sv(range);
        bits_left = bits_left - num_bits;
        low = low << num_bits;
        range = range << num_bits;
        st[CABAC_LOW_LSB +: 32] = low;
        st[CABAC_RANGE_LSB +: 16] = range;
        st[CABAC_BITS_LEFT_LSB +: 8] = bits_left[7:0];
        if (bits_left < 12) begin
          st = cabac_write_out(st);
        end
      end else begin
        st[CABAC_RANGE_LSB +: 16] = range;
      end
      cabac_encode_bin = st;
    end
  endfunction

  function automatic cabac_state_t cabac_encode_bin_ep(
    input cabac_state_t st_in,
    input logic         bin
  );
    cabac_state_t st;
    logic [31:0] low;
    logic [15:0] range;
    integer bits_left;

    begin
      st = st_in;
      low = st[CABAC_LOW_LSB +: 32] << 1;
      range = st[CABAC_RANGE_LSB +: 16];
      bits_left = st[CABAC_BITS_LEFT_LSB +: 8] - 1;
      if (bin) begin
        low = low + range;
      end
      st[CABAC_LOW_LSB +: 32] = low;
      st[CABAC_BITS_LEFT_LSB +: 8] = bits_left[7:0];
      if (bits_left < 12) begin
        st = cabac_write_out(st);
      end
      cabac_encode_bin_ep = st;
    end
  endfunction

  function automatic cabac_state_t cabac_encode_bins_ep(
    input cabac_state_t st_in,
    input logic [31:0]  bin_pattern_in,
    input logic [5:0]   num_bins_in
  );
    cabac_state_t st;
    logic [31:0] low;
    logic [31:0] bin_pattern;
    logic [15:0] range;
    logic [31:0] pattern;
    integer bits_left;
    integer num_bins;

      begin
      st = st_in;
      bin_pattern = bin_pattern_in;
      num_bins = num_bins_in;
      low = st[CABAC_LOW_LSB +: 32];
      range = st[CABAC_RANGE_LSB +: 16];
      bits_left = st[CABAC_BITS_LEFT_LSB +: 8];

      while (num_bins > 8) begin
        num_bins = num_bins - 8;
        pattern = bin_pattern >> num_bins;
        low = low << 8;
        low = low + (range * pattern);
        bin_pattern = bin_pattern - (pattern << num_bins);
        bits_left = bits_left - 8;
        st[CABAC_LOW_LSB +: 32] = low;
        st[CABAC_BITS_LEFT_LSB +: 8] = bits_left[7:0];
        if (bits_left < 12) begin
          st = cabac_write_out(st);
          low = st[CABAC_LOW_LSB +: 32];
          bits_left = st[CABAC_BITS_LEFT_LSB +: 8];
        end
      end

      low = low << num_bins;
      low = low + (range * bin_pattern);
      bits_left = bits_left - num_bins;
      st[CABAC_LOW_LSB +: 32] = low;
      st[CABAC_BITS_LEFT_LSB +: 8] = bits_left[7:0];
      if (bits_left < 12) begin
        st = cabac_write_out(st);
      end
      cabac_encode_bins_ep = st;
    end
  endfunction

  function automatic cabac_state_t cabac_encode_rem_abs_ep(
    input cabac_state_t st_in,
    input logic [4:0]   value,
    input logic [2:0]   rice_param
  );
    cabac_state_t st;
    logic [5:0] threshold;
    logic [5:0] length;
    logic [5:0] code_value;
    logic [5:0] prefix_length;
    logic [5:0] total_prefix_length;
    logic [5:0] suffix_length;
    logic [31:0] prefix;
    logic [31:0] suffix;

    begin
      st = st_in;
      threshold = 6'd5 << rice_param;
      if (value < threshold) begin
        length = (value >> rice_param) + 6'd1;
        st = cabac_encode_bins_ep(st, (32'd1 << length) - 32'd2, length);
        st = cabac_encode_bins_ep(st, value & ((32'd1 << rice_param) - 32'd1), rice_param);
      end else begin
        code_value = (value >> rice_param) - 6'd5;
        prefix_length = 6'd0;
        while (code_value > ((6'd2 << prefix_length) - 6'd2)) begin
          prefix_length = prefix_length + 6'd1;
        end
        total_prefix_length = prefix_length + 6'd5;
        suffix_length = prefix_length + rice_param + 6'd1;
        prefix = (32'd1 << total_prefix_length) - 32'd1;
        suffix = ((code_value - ((6'd1 << prefix_length) - 6'd1)) << rice_param)
          | (value & ((32'd1 << rice_param) - 32'd1));
        st = cabac_encode_bins_ep(st, prefix, total_prefix_length);
        st = cabac_encode_bins_ep(st, suffix, suffix_length);
      end
      cabac_encode_rem_abs_ep = st;
    end
  endfunction

  function automatic cabac_state_t cabac_encode_exp_golomb_ep(
    input cabac_state_t st_in,
    input logic [5:0]   symbol_in,
    input logic [5:0]   count_in
  );
    cabac_state_t st;
    logic [31:0] eg_bins;
    logic [5:0] eg_symbol;
    logic [5:0] eg_count;
    logic [5:0] num_bins;
    begin
      st = st_in;
      eg_symbol = symbol_in;
      eg_count = count_in;
      eg_bins = 32'd0;
      num_bins = 6'd0;
      while (eg_symbol >= (6'd1 << eg_count)) begin
        eg_bins = eg_bins << 1;
        eg_bins = eg_bins + 32'd1;
        num_bins = num_bins + 6'd1;
        eg_symbol = eg_symbol - (6'd1 << eg_count);
        eg_count = eg_count + 6'd1;
      end
      eg_bins = eg_bins << 1;
      num_bins = num_bins + 6'd1;
      st = cabac_encode_bins_ep(st, eg_bins, num_bins);
      st = cabac_encode_bins_ep(st, {26'd0, eg_symbol}, eg_count);
      cabac_encode_exp_golomb_ep = st;
    end
  endfunction

  function automatic cabac_state_t cabac_encode_bin_trm(
    input cabac_state_t st_in,
    input logic         bin
  );
    cabac_state_t st;
    logic [31:0] low;
    logic [15:0] range;
    integer bits_left;

    begin
      st = st_in;
      low = st[CABAC_LOW_LSB +: 32];
      range = st[CABAC_RANGE_LSB +: 16] - 16'd2;
      bits_left = st[CABAC_BITS_LEFT_LSB +: 8];
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
      st[CABAC_LOW_LSB +: 32] = low;
      st[CABAC_RANGE_LSB +: 16] = range;
      st[CABAC_BITS_LEFT_LSB +: 8] = bits_left[7:0];
      if (bits_left < 12) begin
        st = cabac_write_out(st);
      end
      cabac_encode_bin_trm = st;
    end
  endfunction

  function automatic cabac_state_t cabac_finish(input cabac_state_t st_in);
    cabac_state_t st;
    logic [31:0] low;
    logic [8:0] buffered_byte;
    logic [7:0] num_buffered_bytes;
    integer bits_left;
    integer final_bits;

    begin
      st = st_in;
      low = st[CABAC_LOW_LSB +: 32];
      buffered_byte = st[CABAC_BUFFERED_BYTE_LSB +: 9];
      num_buffered_bytes = st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8];
      bits_left = st[CABAC_BITS_LEFT_LSB +: 8];

      if ((low >> (32 - bits_left)) != 0) begin
        st = cabac_write_bits(st, buffered_byte + 9'd1, 6'd8);
        num_buffered_bytes = st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8];
        while (num_buffered_bytes > 8'd1) begin
          st = cabac_write_bits(st, 9'd0, 6'd8);
          num_buffered_bytes = num_buffered_bytes - 8'd1;
          st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8] = num_buffered_bytes;
        end
        low = low - (32'd1 << (32 - bits_left));
        st[CABAC_LOW_LSB +: 32] = low;
      end else begin
        if (num_buffered_bytes > 8'd0) begin
          st = cabac_write_bits(st, buffered_byte, 6'd8);
        end
        num_buffered_bytes = st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8];
        while (num_buffered_bytes > 8'd1) begin
          st = cabac_write_bits(st, 9'h0ff, 6'd8);
          num_buffered_bytes = num_buffered_bytes - 8'd1;
          st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8] = num_buffered_bytes;
        end
      end

      final_bits = 24 - bits_left;
      if (final_bits > 0) begin
        st = cabac_write_bits(st, low >> 8, final_bits[5:0]);
      end
      cabac_finish = st;
    end
  endfunction

  function automatic cabac_state_t cabac_write_out(input cabac_state_t st_in);
    cabac_state_t st;
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
      low = st[CABAC_LOW_LSB +: 32];
      bits_left = st[CABAC_BITS_LEFT_LSB +: 8];
      buffered_byte = st[CABAC_BUFFERED_BYTE_LSB +: 9];
      num_buffered_bytes = st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8];
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
        st[CABAC_LOW_LSB +: 32] = low;
        st[CABAC_BUFFERED_BYTE_LSB +: 9] = buffered_byte;
        st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8] = num_buffered_bytes;
        st[CABAC_BITS_LEFT_LSB +: 8] = bits_left[7:0];
        st = cabac_write_bits(st, byte_value, 6'd8);
        repeated_byte = (9'h0ff + carry) & 9'h0ff;
        num_buffered_bytes = st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8];
        while (num_buffered_bytes > 8'd1) begin
          st = cabac_write_bits(st, repeated_byte, 6'd8);
          num_buffered_bytes = num_buffered_bytes - 8'd1;
          st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8] = num_buffered_bytes;
        end
      end else begin
        num_buffered_bytes = 8'd1;
        buffered_byte = lead_byte[7:0];
      end

      st[CABAC_LOW_LSB +: 32] = low;
      st[CABAC_BUFFERED_BYTE_LSB +: 9] = buffered_byte;
      st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8] = num_buffered_bytes;
      st[CABAC_BITS_LEFT_LSB +: 8] = bits_left[7:0];
      cabac_write_out = st;
    end
  endfunction

  function automatic cabac_state_t cabac_write_bits(
    input cabac_state_t st_in,
    input logic [31:0]  value,
    input logic [5:0]   bit_count
  );
    cabac_state_t st;
    logic [MAX_SLICE_PAYLOAD_BITS - 1:0] bits;
    logic [12:0] len;
    integer i;

    begin
      st = st_in;
      bits = st[CABAC_BITS_LSB +: MAX_SLICE_PAYLOAD_BITS];
      len = st[CABAC_LEN_LSB +: 13];
      for (i = bit_count - 1; i >= 0; i = i - 1) begin
        bits = (bits << 1) | value[i];
        len = len + 13'd1;
      end
      st[CABAC_BITS_LSB +: MAX_SLICE_PAYLOAD_BITS] = bits;
      st[CABAC_LEN_LSB +: 13] = len;
      cabac_write_bits = st;
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

  function automatic logic [8:0] vvc_ctx_lps(input logic [4:0] index);
    begin
      case (index)
        5'd0: vvc_ctx_lps = 9'd146;
        5'd1: vvc_ctx_lps = 9'd81;
        5'd2: vvc_ctx_lps = 9'd128;
        5'd3: vvc_ctx_lps = 9'd52;
        5'd4: vvc_ctx_lps = 9'd160;
        5'd5: vvc_ctx_lps = 9'd129;
        5'd6: vvc_ctx_lps = 9'd24;
        5'd7: vvc_ctx_lps = 9'd58;
        5'd8: vvc_ctx_lps = 9'd29;
        5'd9: vvc_ctx_lps = 9'd172;
        5'd10: vvc_ctx_lps = 9'd107;
        5'd11: vvc_ctx_lps = 9'd136;
        5'd12: vvc_ctx_lps = 9'd128;
        5'd13: vvc_ctx_lps = 9'd125;
        5'd14: vvc_ctx_lps = 9'd184;
        5'd15: vvc_ctx_lps = 9'd112;
        5'd16: vvc_ctx_lps = 9'd28;
        5'd17: vvc_ctx_lps = 9'd67;
        default: vvc_ctx_lps = 9'd26;
      endcase
    end
  endfunction

  function automatic logic vvc_ctx_mps(input logic [4:0] index);
    begin
      case (index)
        5'd0: vvc_ctx_mps = 1'b0;
        5'd1, 5'd2, 5'd3, 5'd4, 5'd5, 5'd9, 5'd12: vvc_ctx_mps = 1'b1;
        default: vvc_ctx_mps = 1'b0;
      endcase
    end
  endfunction

endmodule
