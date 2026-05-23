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
  output logic [12:0] stream_bit_count,
  output logic [12:0] stream_byte_count
);
  localparam int PALETTE_MODEL_BITS = 40;
  localparam int PALETTE_CTX_COUNT = 18;
  localparam int PALETTE_MODEL_BANK_BITS = PALETTE_CTX_COUNT * PALETTE_MODEL_BITS;
  localparam int CABAC_PENDING_BYTES = 64;
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
  localparam int PALETTE_CTX_ROTATION_FLAG = 11;
  localparam int PALETTE_CTX_RUN_TYPE_FLAG = 12;
  localparam int PALETTE_CTX_IDX_RUN_0 = 13;
  localparam int PALETTE_CTX_IDX_RUN_1 = 14;
  localparam int PALETTE_CTX_IDX_RUN_2 = 15;
  localparam int PALETTE_CTX_IDX_RUN_3 = 16;
  localparam int PALETTE_CTX_IDX_RUN_4 = 17;
  localparam logic [3:0] PALETTE_PKT_CU_START            = 4'h1;
  localparam logic [3:0] PALETTE_PKT_ENTRY_Y             = 4'h2;
  localparam logic [3:0] PALETTE_PKT_INDEX               = 4'h3;
  localparam logic [3:0] PALETTE_PKT_ENTRY_CB            = 4'h4;
  localparam logic [3:0] PALETTE_PKT_ENTRY_CR            = 4'h5;
  typedef struct packed {
    logic [7:0] bits_left;
    logic [7:0] num_buffered_bytes;
    logic [8:0] buffered_byte;
    logic [15:0] range;
    logic [31:0] low;
  } cabac_core_state_t;

  typedef cabac_core_state_t cabac_state_t;

  typedef struct packed {
    logic [12:0] bit_count;
    logic [12:0] byte_count;
    logic [2:0] partial_bit_count;
    logic [7:0] partial_byte;
    logic [7:0] pending_count;
    logic [CABAC_PENDING_BYTES - 1:0][7:0] pending_bytes;
  } cabac_byte_stream_state_t;

  typedef struct packed {
    cabac_core_state_t core;
    cabac_byte_stream_state_t stream;
  } cabac_writer_state_t;

  typedef struct packed {
    logic [PALETTE_MODEL_BANK_BITS - 1:0] models;
    cabac_writer_state_t cabac;
  } palette_state_t;

  palette_state_t palette_state_q;
  logic [7:0]     stream_symbol_index_q;
  logic           stream_symbol_selected;
  palette_state_t next_palette_state;
  logic [7:0]     current_palette_size_q;
  logic [7:0]     current_entry_count_q;
  logic [7:0]     current_index_count_q;
  logic [(16 * 8) - 1:0] current_scan_indices_q;
  logic [15:0]    current_run_copy_flags_q;
  logic [7:0]     current_previous_index_q;
  logic [7:0]     current_prev_run_pos_q;
  logic [7:0]     current_prev_subblock_last_index_q;
  palette_state_t finished_palette_state;
  palette_state_t accepted_palette_state;
  palette_state_t popped_palette_state;
  logic           final_draining_q;

  assign s_axis_ready = enable && !m_axis_valid &&
                        (palette_state_q.cabac.stream.pending_count == 8'd0);
  assign stream_bit_count = palette_state_q.cabac.stream.bit_count;
  assign stream_byte_count = palette_state_q.cabac.stream.byte_count;
  assign stream_symbol_selected = s_axis_data[24];
  assign finished_palette_state = palette_finish(next_palette_state);
  assign accepted_palette_state = s_axis_last ? finished_palette_state : next_palette_state;
  assign popped_palette_state = palette_pop_pending_byte(palette_state_q);

  always @* begin
    next_palette_state = palette_state_q;
    case (s_axis_data[31:28])
      PALETTE_PKT_CU_START: begin
        if (stream_symbol_selected) begin
          next_palette_state = palette_444_encode_cu_start(
            palette_state_q,
            stream_symbol_index_q,
            s_axis_data[23:16]
          );
        end
      end
      PALETTE_PKT_ENTRY_Y,
      PALETTE_PKT_ENTRY_CB,
      PALETTE_PKT_ENTRY_CR: begin
        next_palette_state = palette_444_encode_entry_component(
          palette_state_q,
          s_axis_data[31:28],
          current_palette_size_q,
          current_entry_count_q,
          s_axis_data[7:0]
        );
      end
      PALETTE_PKT_INDEX: begin
        next_palette_state = palette_444_encode_index_symbol(
            palette_state_q,
            current_palette_size_q,
            current_index_count_q,
            s_axis_data[7:0]
          );
      end
      default: begin
        next_palette_state = palette_state_q;
      end
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      stream_symbol_index_q <= 8'd0;
      palette_state_q <= palette_start();
      current_palette_size_q <= 8'd0;
      current_entry_count_q <= 8'd0;
      current_index_count_q <= 8'd0;
      current_scan_indices_q <= '0;
      current_run_copy_flags_q <= 16'd0;
      current_previous_index_q <= 8'd0;
      current_prev_run_pos_q <= 8'd0;
      current_prev_subblock_last_index_q <= 8'd0;
      final_draining_q <= 1'b0;
      m_axis_valid <= 1'b0;
      m_axis_data <= 8'd0;
      m_axis_last <= 1'b0;
    end else if (clear || !enable) begin
      stream_symbol_index_q <= 8'd0;
      palette_state_q <= palette_start();
      current_palette_size_q <= 8'd0;
      current_entry_count_q <= 8'd0;
      current_index_count_q <= 8'd0;
      current_scan_indices_q <= '0;
      current_run_copy_flags_q <= 16'd0;
      current_previous_index_q <= 8'd0;
      current_prev_run_pos_q <= 8'd0;
      current_prev_subblock_last_index_q <= 8'd0;
      final_draining_q <= 1'b0;
      m_axis_valid <= 1'b0;
      m_axis_data <= 8'd0;
      m_axis_last <= 1'b0;
    end else if (m_axis_valid && m_axis_ready) begin
      palette_state_q <= popped_palette_state;
      if (m_axis_last) begin
        final_draining_q <= 1'b0;
        m_axis_valid <= 1'b0;
        m_axis_data <= 8'd0;
        m_axis_last <= 1'b0;
      end else if (popped_palette_state.cabac.stream.pending_count != 8'd0) begin
        m_axis_data <= palette_pending_first_byte(popped_palette_state);
        m_axis_last <= final_draining_q &&
                       (popped_palette_state.cabac.stream.pending_count == 8'd1);
      end else begin
        m_axis_valid <= 1'b0;
        m_axis_data <= 8'd0;
        m_axis_last <= 1'b0;
      end
    end else if (s_axis_valid && s_axis_ready) begin
      if (s_axis_last) begin
        palette_state_q <= accepted_palette_state;
        stream_symbol_index_q <= 8'd0;
        current_palette_size_q <= 8'd0;
        current_entry_count_q <= 8'd0;
        current_index_count_q <= 8'd0;
        current_scan_indices_q <= '0;
        current_run_copy_flags_q <= 16'd0;
        current_previous_index_q <= 8'd0;
        current_prev_run_pos_q <= 8'd0;
        current_prev_subblock_last_index_q <= 8'd0;
      end else begin
        palette_state_q <= accepted_palette_state;
        case (s_axis_data[31:28])
          PALETTE_PKT_CU_START: begin
            stream_symbol_index_q <= stream_symbol_index_q + 8'd1;
            current_palette_size_q <= s_axis_data[23:16];
            current_entry_count_q <= 8'd0;
            current_index_count_q <= 8'd0;
            current_scan_indices_q <= '0;
            current_run_copy_flags_q <= 16'd0;
            current_previous_index_q <= 8'd0;
            current_prev_run_pos_q <= 8'd0;
            current_prev_subblock_last_index_q <= 8'd0;
          end
          PALETTE_PKT_ENTRY_Y,
          PALETTE_PKT_ENTRY_CB,
          PALETTE_PKT_ENTRY_CR: begin
            if ((current_entry_count_q + 8'd1) >= current_palette_size_q) begin
              current_entry_count_q <= 8'd0;
            end else begin
              current_entry_count_q <= current_entry_count_q + 8'd1;
            end
          end
          PALETTE_PKT_INDEX: begin
            current_scan_indices_q[(current_index_count_q[3:0] * 8) +: 8] <= s_axis_data[7:0];
            current_run_copy_flags_q[current_index_count_q[3:0]] <=
              (current_index_count_q > 8'd0) && (s_axis_data[7:0] == current_previous_index_q);
            if ((current_index_count_q == 8'd0) ||
                (s_axis_data[7:0] != current_previous_index_q)) begin
              current_prev_run_pos_q <= current_index_count_q;
            end
            current_previous_index_q <= s_axis_data[7:0];
            if (current_index_count_q[3:0] == 4'd15) begin
              current_prev_subblock_last_index_q <= s_axis_data[7:0];
            end
            current_index_count_q <= current_index_count_q + 8'd1;
          end
          default: begin
          end
        endcase
      end
      if (accepted_palette_state.cabac.stream.pending_count != 8'd0) begin
        final_draining_q <= s_axis_last;
        m_axis_valid <= 1'b1;
        m_axis_data <= palette_pending_first_byte(accepted_palette_state);
        m_axis_last <= s_axis_last &&
                       (accepted_palette_state.cabac.stream.pending_count == 8'd1);
      end
    end
  end

  function automatic palette_state_t palette_finish(input palette_state_t pst_in);
    palette_state_t pst;
    cabac_writer_state_t st;
    begin
      pst = pst_in;
      st = pst.cabac;
      st = cabac_encode_bin_trm(st, 1'b1);
      st = cabac_finish(st);
      st.stream = cabac_stream_flush_partial_byte(st.stream);
      pst.cabac = st;
      palette_finish = pst;
    end
  endfunction

  function automatic logic [7:0] palette_pending_first_byte(input palette_state_t pst);
    begin
      palette_pending_first_byte =
        pst.cabac.stream.pending_bytes >> ((pst.cabac.stream.pending_count - 8'd1) * 8);
    end
  endfunction

  function automatic palette_state_t palette_pop_pending_byte(input palette_state_t pst_in);
    palette_state_t pst;
    begin
      pst = pst_in;
      if (pst.cabac.stream.pending_count != 8'd0) begin
        pst.cabac.stream.pending_count = pst.cabac.stream.pending_count - 8'd1;
        if (pst.cabac.stream.pending_count == 8'd0) begin
          pst.cabac.stream.pending_bytes = '0;
        end
      end
      palette_pop_pending_byte = pst;
    end
  endfunction

  function automatic palette_state_t palette_444_encode_cu_start(
    input palette_state_t pst_in,
    input logic [7:0] symbol_index,
    input logic [7:0] entry_count
  );
    palette_state_t pst;
    logic [31:0] pos;
    logic [15:0] origin_x;
    logic [15:0] origin_y;
    cabac_writer_state_t st;
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

      pst = palette_encode_ctx(pst, PALETTE_CTX_SPLIT0, 1'b0);    // split_cu_mode split=0 for an 8x8 palette CU
      pst = palette_encode_ctx(pst, PALETTE_CTX_PLT_FLAG, 1'b1);  // pred_mode PLTFlag=1
      st = pst.cabac;
      if (symbol_index != 8'd0) begin
        st = cabac_encode_exp_golomb_ep(st, 6'd1, 6'd0); // palette_predictor_run=1: no reused entries
      end
      st = cabac_encode_exp_golomb_ep(st, entry_count[5:0], 6'd0);
      pst.cabac = st;
      palette_444_encode_cu_start = pst;
    end
  endfunction

  function automatic palette_state_t palette_444_encode_entry_component(
    input palette_state_t pst_in,
    input logic [3:0] packet_kind,
    input logic [7:0] palette_size,
    input logic [7:0] entry_count,
    input logic [7:0] sample
  );
    palette_state_t pst;
    cabac_writer_state_t st;
    begin
      pst = pst_in;
      st = pst.cabac;
      st = cabac_encode_bins_ep(st, {24'd0, sample}, 6'd8);
      if ((packet_kind == PALETTE_PKT_ENTRY_CR) &&
          ((entry_count + 8'd1) >= palette_size)) begin
        st = cabac_encode_bin_ep(st, 1'b0); // palette_escape_val_present_flag=0
      end
      pst.cabac = st;
      palette_444_encode_entry_component = pst;
    end
  endfunction

  function automatic palette_state_t palette_444_encode_index_symbol(
    input palette_state_t pst_in,
    input logic [7:0] palette_size,
    input logic [7:0] index_count,
    input logic [7:0] current_index
  );
    palette_state_t pst;
    cabac_writer_state_t st;
    logic [(16 * 8) - 1:0] subblock_indices;
    logic [15:0] run_copy_flags;
    logic [7:0] previous_index;
    logic [7:0] global_pos;
    logic [7:0] run_dist;
    logic identity;
    logic [31:0] max_symbol;
    logic [31:0] level;
    logic [7:0] prev_level_index;
    begin
      pst = pst_in;
      if (palette_size <= 8'd1) begin
        palette_444_encode_index_symbol = pst;
      end else begin
        subblock_indices = current_scan_indices_q;
        run_copy_flags = current_run_copy_flags_q;
        subblock_indices[(index_count[3:0] * 8) +: 8] = current_index;
        identity = (index_count > 8'd0) && (current_index == current_previous_index_q);
        run_copy_flags[index_count[3:0]] = identity;

        if (index_count == 8'd0) begin
          pst = palette_encode_ctx(pst, PALETTE_CTX_ROTATION_FLAG, 1'b0);
        end

        if (index_count > 8'd0) begin
          run_dist = index_count - current_prev_run_pos_q - 8'd1;
          pst = palette_encode_ctx(pst, palette_idx_run_ctx_id(run_dist), identity);
        end

        if (!identity || (index_count == 8'd0)) begin
          if ((index_count != 8'd0) && (palette_scan_y(index_count) != 8'd0)) begin
            pst = palette_encode_ctx(pst, PALETTE_CTX_RUN_TYPE_FLAG, 1'b0);
          end
        end

        if (index_count[3:0] == 4'd15) begin
          st = pst.cabac;
          for (int local_pos = 0; local_pos < 16; local_pos = local_pos + 1) begin
            global_pos = {index_count[7:4], 4'd0} + local_pos[7:0];
            if (!run_copy_flags[local_pos]) begin
              max_symbol = {24'd0, palette_size} - ((global_pos > 0) ? 32'd1 : 32'd0);
              if (max_symbol > 32'd1) begin
                level = {24'd0, subblock_indices[(local_pos * 8) +: 8]};
                if (global_pos > 8'd0) begin
                  if (local_pos == 0) begin
                    previous_index = current_prev_subblock_last_index_q;
                  end else begin
                    previous_index = subblock_indices[((local_pos - 1) * 8) +: 8];
                  end
                  prev_level_index = previous_index;
                  if (level > {24'd0, prev_level_index}) begin
                    level = level - 32'd1;
                  end
                end
                st = cabac_encode_trunc_bin_ep(st, level, max_symbol);
              end
            end
          end
          pst.cabac = st;
        end
        palette_444_encode_index_symbol = pst;
      end
    end
  endfunction

  function automatic logic [7:0] palette_scan_y(input logic [7:0] scan_index);
    begin
      palette_scan_y = scan_index >> 3;
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

  function automatic int palette_model_lsb(input int ctx_id);
    begin
      palette_model_lsb = ctx_id * PALETTE_MODEL_BITS;
    end
  endfunction

  function automatic palette_state_t palette_start();
    palette_state_t pst;
    begin
      pst = '0;
      pst.cabac = cabac_start();
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
      pst = palette_init_model(pst, PALETTE_CTX_ROTATION_FLAG, 8'd90, 8'd5);
      pst = palette_init_model(pst, PALETTE_CTX_RUN_TYPE_FLAG, 8'd90, 8'd9);
      pst = palette_init_model(pst, PALETTE_CTX_IDX_RUN_0, 8'd106, 8'd9);
      pst = palette_init_model(pst, PALETTE_CTX_IDX_RUN_1, 8'd182, 8'd6);
      pst = palette_init_model(pst, PALETTE_CTX_IDX_RUN_2, 8'd198, 8'd9);
      pst = palette_init_model(pst, PALETTE_CTX_IDX_RUN_3, 8'd202, 8'd10);
      pst = palette_init_model(pst, PALETTE_CTX_IDX_RUN_4, 8'd234, 8'd5);
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
    logic [PALETTE_MODEL_BANK_BITS - 1:0] models;
    int lsb;
    logic [15:0] pstate;
    logic [3:0] rate0;
    logic [3:0] rate1;
    begin
      pst = pst_in;
      models = pst.models;
      lsb = palette_model_lsb(ctx_id);
      pstate = {state, 8'd0};
      models[lsb +: 16] = (pstate >> 1) & 16'h7fe0;
      models[lsb + 16 +: 16] = (pstate >> 1) & 16'h7ffe;
      rate0 = 4'd2 + {2'd0, log2_window_size[3:2]};
      rate1 = 4'd3 + rate0 + {2'd0, log2_window_size[1:0]};
      models[lsb + 32 +: 8] = {rate0, rate1};
      pst.models = models;
      palette_init_model = pst;
    end
  endfunction

  function automatic logic [7:0] palette_model_state(input palette_state_t pst, input int ctx_id);
    int lsb;
    logic [PALETTE_MODEL_BANK_BITS - 1:0] models;
    logic [16:0] sum;
    begin
      models = pst.models;
      lsb = palette_model_lsb(ctx_id);
      sum = {1'b0, models[lsb +: 16]} + {1'b0, models[lsb + 16 +: 16]};
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
    cabac_writer_state_t st;
    begin
      pst = pst_in;
      st = pst.cabac;
      st = cabac_encode_bin(
        st,
        bin,
        palette_model_lps(pst, ctx_id, st.core.range),
        palette_model_mps(pst, ctx_id)
      );
      pst.cabac = st;
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
    logic [PALETTE_MODEL_BANK_BITS - 1:0] models;
    int lsb;
    logic [15:0] state0;
    logic [15:0] state1;
    logic [7:0] rate;
    logic [3:0] rate0;
    logic [3:0] rate1;
    begin
      pst = pst_in;
      models = pst.models;
      lsb = palette_model_lsb(ctx_id);
      state0 = models[lsb +: 16];
      state1 = models[lsb + 16 +: 16];
      rate = models[lsb + 32 +: 8];
      rate0 = rate[7:4];
      rate1 = rate[3:0];
      state0 = state0 - ((state0 >> rate0) & 16'h7fe0);
      state1 = state1 - ((state1 >> rate1) & 16'h7ffe);
      if (bin) begin
        state0 = state0 + ((16'h7fff >> rate0) & 16'h7fe0);
        state1 = state1 + ((16'h7fff >> rate1) & 16'h7ffe);
      end
      models[lsb +: 16] = state0;
      models[lsb + 16 +: 16] = state1;
      pst.models = models;
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

  function automatic int palette_idx_run_ctx_id(input logic [7:0] run_dist);
    begin
      if (run_dist == 8'd0) begin
        palette_idx_run_ctx_id = PALETTE_CTX_IDX_RUN_0;
      end else if (run_dist == 8'd1) begin
        palette_idx_run_ctx_id = PALETTE_CTX_IDX_RUN_1;
      end else if (run_dist == 8'd2) begin
        palette_idx_run_ctx_id = PALETTE_CTX_IDX_RUN_2;
      end else if (run_dist == 8'd3) begin
        palette_idx_run_ctx_id = PALETTE_CTX_IDX_RUN_3;
      end else begin
        palette_idx_run_ctx_id = PALETTE_CTX_IDX_RUN_4;
      end
    end
  endfunction


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

  function automatic cabac_writer_state_t cabac_encode_ctx_bins(
    input cabac_writer_state_t st_in,
    input logic [4:0]   ctx_offset,
    input logic [7:0]   bin_pattern,
    input logic [3:0]   num_bins
  );
    cabac_writer_state_t st;
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

  function automatic cabac_writer_state_t cabac_encode_bin(
    input cabac_writer_state_t st_in,
    input logic         bin,
    input logic [8:0]   lps_in,
    input logic         mps
  );
    cabac_writer_state_t st;
    logic [31:0] low;
    logic [15:0] range;
    logic [8:0]  lps;
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
        num_bits = renorm_bits_sv(range);
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

  function automatic cabac_writer_state_t cabac_encode_bin_ep(
    input cabac_writer_state_t st_in,
    input logic         bin
  );
    cabac_writer_state_t st;
    logic [31:0] low;
    logic [15:0] range;
    integer bits_left;

    begin
      st = st_in;
      low = st.core.low << 1;
      range = st.core.range;
      bits_left = st.core.bits_left - 1;
      if (bin) begin
        low = low + range;
      end
      st.core.low = low;
      st.core.bits_left = bits_left[7:0];
      if (bits_left < 12) begin
        st = cabac_write_out(st);
      end
      cabac_encode_bin_ep = st;
    end
  endfunction

  function automatic cabac_writer_state_t cabac_encode_bins_ep(
    input cabac_writer_state_t st_in,
    input logic [31:0]  bin_pattern_in,
    input logic [5:0]   num_bins_in
  );
    cabac_writer_state_t st;
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
      low = st.core.low;
      range = st.core.range;
      bits_left = st.core.bits_left;

      while (num_bins > 8) begin
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

  function automatic cabac_writer_state_t cabac_encode_rem_abs_ep(
    input cabac_writer_state_t st_in,
    input logic [4:0]   value,
    input logic [2:0]   rice_param
  );
    cabac_writer_state_t st;
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

  function automatic cabac_writer_state_t cabac_encode_trunc_bin_ep(
    input cabac_writer_state_t st_in,
    input logic [31:0]  symbol,
    input logic [31:0]  num_symbols
  );
    cabac_writer_state_t st;
    logic [5:0] thresh;
    logic [31:0] val;
    logic [31:0] b;
    begin
      st = st_in;
      thresh = floor_log2_32(num_symbols);
      val = 32'd1 << thresh;
      b = num_symbols - val;
      if (symbol < (val - b)) begin
        st = cabac_encode_bins_ep(st, symbol, thresh);
      end else begin
        st = cabac_encode_bins_ep(st, symbol + val - b, thresh + 6'd1);
      end
      cabac_encode_trunc_bin_ep = st;
    end
  endfunction

  function automatic logic [5:0] floor_log2_32(input logic [31:0] value);
    logic [5:0] result;
    begin
      result = 6'd0;
      for (int bit_idx = 0; bit_idx < 32; bit_idx = bit_idx + 1) begin
        if (value[bit_idx]) begin
          result = bit_idx[5:0];
        end
      end
      floor_log2_32 = result;
    end
  endfunction

  function automatic cabac_writer_state_t cabac_encode_exp_golomb_ep(
    input cabac_writer_state_t st_in,
    input logic [5:0]   symbol_in,
    input logic [5:0]   count_in
  );
    cabac_writer_state_t st;
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

  function automatic cabac_writer_state_t cabac_encode_bin_trm(
    input cabac_writer_state_t st_in,
    input logic         bin
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

  function automatic cabac_writer_state_t cabac_write_bits(
    input cabac_writer_state_t st_in,
    input logic [31:0]  value,
    input logic [5:0]   bit_count
  );
    cabac_writer_state_t st;
    logic [12:0] len;
    logic [7:0] partial_byte;
    integer partial_bit_count;
    integer i;

    begin
      st = st_in;
      len = st.stream.bit_count;
      partial_byte = st.stream.partial_byte;
      partial_bit_count = st.stream.partial_bit_count;
      for (i = bit_count - 1; i >= 0; i = i - 1) begin
        partial_byte = (partial_byte << 1) | value[i];
        partial_bit_count = partial_bit_count + 1;
        len = len + 13'd1;
        if (partial_bit_count == 8) begin
          st.stream = cabac_stream_append_byte(st.stream, partial_byte);
          partial_byte = 8'd0;
          partial_bit_count = 0;
        end
      end
      st.stream.bit_count = len;
      st.stream.partial_byte = partial_byte;
      st.stream.partial_bit_count = partial_bit_count[2:0];
      cabac_write_bits = st;
    end
  endfunction

  function automatic cabac_byte_stream_state_t cabac_stream_append_byte(
    input cabac_byte_stream_state_t stream_in,
    input logic [7:0] value
  );
    cabac_byte_stream_state_t stream;
    begin
      stream = stream_in;
      if (stream.pending_count < CABAC_PENDING_BYTES[7:0]) begin
        stream.pending_bytes = (stream.pending_bytes << 8) | value;
        stream.pending_count = stream.pending_count + 8'd1;
      end
      stream.byte_count = stream.byte_count + 13'd1;
      cabac_stream_append_byte = stream;
    end
  endfunction

  function automatic cabac_byte_stream_state_t cabac_stream_flush_partial_byte(input cabac_byte_stream_state_t stream_in);
    cabac_byte_stream_state_t stream;
    logic [2:0] pad_bits;
    begin
      stream = stream_in;
      if (stream.partial_bit_count != 3'd0) begin
        pad_bits = 3'd0 - stream.partial_bit_count;
        stream = cabac_stream_append_byte(stream, stream.partial_byte << pad_bits);
        stream.partial_byte = 8'd0;
        stream.partial_bit_count = 3'd0;
      end
      cabac_stream_flush_partial_byte = stream;
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
