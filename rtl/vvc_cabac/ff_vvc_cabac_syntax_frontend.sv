`timescale 1ns/1ps

module ff_vvc_cabac_syntax_frontend #(
  parameter int VVC_CABAC_CTX_ID_BITS = 10
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        clear,

  input  logic        raw_symbol_valid,
  output logic        raw_symbol_ready,
  input  logic [7:0]  raw_symbol_kind,
  input  logic [31:0] raw_symbol_data,
  input  logic        raw_symbol_last,

  input  logic        ctu_valid,
  output logic        ctu_ready,
  input  logic [15:0] ctu_x,
  input  logic [15:0] ctu_y,
  input  logic [15:0] ctu_visible_width,
  input  logic [15:0] ctu_visible_height,
  input  logic [7:0]  ctu_luma_dc_abs_level,
  input  logic        ctu_luma_dc_negative,
  input  logic        ctu_luma_only,
  input  logic        ctu_last,

  output logic        m_axis_valid,
  input  logic        m_axis_ready,
  output logic [7:0]  m_axis_kind,
  output logic [31:0] m_axis_data,
  output logic        m_axis_last
);
  localparam logic [7:0] SYMBOL_BIN_EP  = 8'd0;
  localparam logic [7:0] SYMBOL_BIN_TRM = 8'd1;
  localparam logic [7:0] SYMBOL_BIN_CTX = 8'd2;
  localparam logic [7:0] SYMBOL_BINS_EP = 8'd4;

  localparam logic [7:0] PALETTE_PKT_CU_START = 8'h81;
  localparam logic [7:0] PALETTE_PKT_ENTRY_Y  = 8'h82;
  localparam logic [7:0] PALETTE_PKT_INDEX    = 8'h83;
  localparam logic [7:0] PALETTE_PKT_ENTRY_CB = 8'h84;
  localparam logic [7:0] PALETTE_PKT_ENTRY_CR = 8'h85;

  localparam logic [VVC_CABAC_CTX_ID_BITS - 1:0] VVC_CTX_SPLIT_FLAG_0 = 10'd0;
  localparam logic [VVC_CABAC_CTX_ID_BITS - 1:0] VVC_CTX_PRED_MODE_PLT_FLAG = 10'd42;
  localparam logic [VVC_CABAC_CTX_ID_BITS - 1:0] VVC_CTX_PALETTE_TRANSPOSE_FLAG = 10'd43;
  localparam logic [VVC_CABAC_CTX_ID_BITS - 1:0] VVC_CTX_COPY_ABOVE_PALETTE_FLAG = 10'd44;
  localparam logic [VVC_CABAC_CTX_ID_BITS - 1:0] VVC_CTX_RUN_COPY_FLAG_0 = 10'd45;

  typedef enum logic [3:0] {
    ST_IDLE,
    ST_PAL_PRED_MODE,
    ST_PAL_PREDICTOR_RUN,
    ST_PAL_ENTRY_COUNT,
    ST_PAL_ESCAPE_FLAG,
    ST_PAL_INDEX_TRANSPOSE,
    ST_PAL_INDEX_RUN_FLAG,
    ST_PAL_INDEX_COPY_ABOVE,
    ST_PAL_INDEX_LEVEL,
    ST_PAL_TERMINATE
  } state_t;

  state_t state_q;
  logic pending_raw_last_q;
  logic [7:0] palette_entry_count_q;
  logic [7:0] palette_entry_cr_count_q;
  logic [7:0] palette_index_count_q;
  logic       palette_have_previous_cu_q;
  logic       palette_predictor_run_present_q;
  logic [7:0] palette_indices_q [0:63];
  logic       palette_run_copy_flags_q [0:15];
  logic [7:0] index_cur_pos_q;
  logic [7:0] index_min_sub_pos_q;
  logic [7:0] index_max_sub_pos_q;
  logic [7:0] index_level_pos_q;
  logic [7:0] index_prev_run_pos_q;
  logic       index_previous_run_type_copy_above_q;
  logic [7:0] index_prev_index_q;
  logic [31:0] eg0_pattern;
  logic [5:0] eg0_bit_count;
  logic [31:0] eg0_symbol_work;
  logic [5:0] eg0_order_work;
  logic [3:0] eg0_i;
  logic [7:0] index_cur_value;
  logic [7:0] index_prev_scan_value;
  logic [5:0] index_prev_scan_addr;
  logic index_identity;
  logic [7:0] index_dist;
  logic [2:0] index_run_copy_ctx_inc;
  logic [2:0] index_scan_y;
  logic index_copy_above_present;
  logic [31:0] trunc_pattern;
  logic [5:0] trunc_bit_count;
  logic [7:0] trunc_level;
  logic [7:0] trunc_num_symbols;
  logic [5:0] trunc_thresh;
  logic [7:0] trunc_val;
  logic [7:0] trunc_b;
  logic palette_raw_cu_last;
  logic output_slot_ready;

  assign output_slot_ready = !m_axis_valid;
  assign raw_symbol_ready = (state_q == ST_IDLE) && output_slot_ready;
  assign ctu_ready = 1'b0;
  assign palette_raw_cu_last = raw_symbol_data[27];

  always @* begin
    eg0_pattern = 32'd0;
    eg0_bit_count = 6'd0;
    eg0_symbol_work =
      (state_q == ST_PAL_PREDICTOR_RUN) ? 32'd1 : {24'd0, palette_entry_count_q};
    eg0_order_work = 6'd0;
    for (eg0_i = 4'd0; eg0_i < 4'd8; eg0_i = eg0_i + 4'd1) begin
      if (eg0_symbol_work >= (32'd1 << eg0_order_work)) begin
        eg0_pattern = (eg0_pattern << 1) | 32'd1;
        eg0_bit_count = eg0_bit_count + 6'd1;
        eg0_symbol_work = eg0_symbol_work - (32'd1 << eg0_order_work);
        eg0_order_work = eg0_order_work + 6'd1;
      end
    end
    eg0_pattern = (eg0_pattern << 1);
    eg0_bit_count = eg0_bit_count + 6'd1;
    eg0_pattern = (eg0_pattern << eg0_order_work) | eg0_symbol_work;
    eg0_bit_count = eg0_bit_count + eg0_order_work;
  end

  assign index_cur_value = palette_indices_q[index_cur_pos_q[5:0]];
  assign index_prev_scan_addr = index_level_pos_q[5:0] - 6'd1;
  assign index_prev_scan_value = palette_indices_q[index_prev_scan_addr];
  assign index_identity = (index_cur_pos_q > 8'd0) && (index_cur_value == index_prev_index_q);
  assign index_dist = index_cur_pos_q - index_prev_run_pos_q - 8'd1;
  assign index_scan_y = index_cur_pos_q[5:3];
  assign index_copy_above_present = (index_cur_pos_q != 8'd0) && (index_scan_y != 3'd0);

  always @* begin
    if (index_previous_run_type_copy_above_q) begin
      if (index_dist == 8'd0) begin
        index_run_copy_ctx_inc = 3'd5;
      end else if (index_dist <= 8'd2) begin
        index_run_copy_ctx_inc = 3'd6;
      end else begin
        index_run_copy_ctx_inc = 3'd7;
      end
    end else begin
      if (index_dist == 8'd0) begin
        index_run_copy_ctx_inc = 3'd0;
      end else if (index_dist == 8'd1) begin
        index_run_copy_ctx_inc = 3'd1;
      end else if (index_dist == 8'd2) begin
        index_run_copy_ctx_inc = 3'd2;
      end else if (index_dist == 8'd3) begin
        index_run_copy_ctx_inc = 3'd3;
      end else begin
        index_run_copy_ctx_inc = 3'd4;
      end
    end
  end

  always @* begin
    trunc_level = palette_indices_q[index_level_pos_q[5:0]];
    trunc_num_symbols = palette_entry_count_q - {7'd0, (index_level_pos_q > 8'd0)};
    if (index_level_pos_q > 8'd0) begin
      if (trunc_level > index_prev_scan_value) begin
        trunc_level = trunc_level - 8'd1;
      end
    end

    trunc_thresh = 6'd0;
    for (int i = 0; i < 5; i = i + 1) begin
      if ((8'd1 << i) <= trunc_num_symbols) begin
        trunc_thresh = i[5:0];
      end
    end
    trunc_val = 8'd1 << trunc_thresh;
    trunc_b = trunc_num_symbols - trunc_val;
    if (trunc_level < (trunc_val - trunc_b)) begin
      trunc_pattern = {24'd0, trunc_level};
      trunc_bit_count = trunc_thresh;
    end else begin
      trunc_pattern = {24'd0, trunc_level + trunc_val - trunc_b};
      trunc_bit_count = trunc_thresh + 6'd1;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_IDLE;
      pending_raw_last_q <= 1'b0;
      palette_entry_count_q <= 8'd0;
      palette_entry_cr_count_q <= 8'd0;
      palette_index_count_q <= 8'd0;
      palette_have_previous_cu_q <= 1'b0;
      palette_predictor_run_present_q <= 1'b0;
      index_cur_pos_q <= 8'd0;
      index_min_sub_pos_q <= 8'd0;
      index_max_sub_pos_q <= 8'd0;
      index_level_pos_q <= 8'd0;
      index_prev_run_pos_q <= 8'd0;
      index_previous_run_type_copy_above_q <= 1'b0;
      index_prev_index_q <= 8'd0;
      m_axis_valid <= 1'b0;
      m_axis_kind <= SYMBOL_BIN_EP;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;
      for (int i = 0; i < 64; i = i + 1) begin
        palette_indices_q[i] <= 8'd0;
      end
      for (int i = 0; i < 16; i = i + 1) begin
        palette_run_copy_flags_q[i] <= 1'b0;
      end
    end else if (clear) begin
      state_q <= ST_IDLE;
      pending_raw_last_q <= 1'b0;
      palette_entry_count_q <= 8'd0;
      palette_entry_cr_count_q <= 8'd0;
      palette_index_count_q <= 8'd0;
      palette_have_previous_cu_q <= 1'b0;
      palette_predictor_run_present_q <= 1'b0;
      index_cur_pos_q <= 8'd0;
      index_min_sub_pos_q <= 8'd0;
      index_max_sub_pos_q <= 8'd0;
      index_level_pos_q <= 8'd0;
      index_prev_run_pos_q <= 8'd0;
      index_previous_run_type_copy_above_q <= 1'b0;
      index_prev_index_q <= 8'd0;
      m_axis_valid <= 1'b0;
      m_axis_kind <= SYMBOL_BIN_EP;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;
    end else if (m_axis_valid && m_axis_ready) begin
      m_axis_valid <= 1'b0;
      m_axis_kind <= SYMBOL_BIN_EP;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;
    end else if (output_slot_ready) begin
      m_axis_valid <= 1'b0;
      m_axis_kind <= SYMBOL_BIN_EP;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;

      case (state_q)
        ST_PAL_PRED_MODE: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= 32'd1 | ({22'd0, VVC_CTX_PRED_MODE_PLT_FLAG} << 8);
          m_axis_last <= 1'b0;
          state_q <= palette_predictor_run_present_q ? ST_PAL_PREDICTOR_RUN : ST_PAL_ENTRY_COUNT;
        end

        ST_PAL_PREDICTOR_RUN: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BINS_EP;
          m_axis_data <= (eg0_pattern << 6) | {26'd0, eg0_bit_count};
          m_axis_last <= 1'b0;
          state_q <= ST_PAL_ENTRY_COUNT;
        end

        ST_PAL_ENTRY_COUNT: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BINS_EP;
          m_axis_data <= (eg0_pattern << 6) | {26'd0, eg0_bit_count};
          m_axis_last <= 1'b0;
          state_q <= pending_raw_last_q ? ST_PAL_TERMINATE : ST_IDLE;
        end

        ST_PAL_ESCAPE_FLAG: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_EP;
          m_axis_data <= 32'd0;
          m_axis_last <= 1'b0;
          state_q <= pending_raw_last_q ? ST_PAL_TERMINATE : ST_IDLE;
        end

        ST_PAL_INDEX_TRANSPOSE: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= ({22'd0, VVC_CTX_PALETTE_TRANSPOSE_FLAG} << 8);
          m_axis_last <= 1'b0;
          index_cur_pos_q <= 8'd0;
          index_min_sub_pos_q <= 8'd0;
          index_max_sub_pos_q <= (palette_index_count_q < 8'd16) ? palette_index_count_q : 8'd16;
          index_level_pos_q <= 8'd0;
          index_prev_run_pos_q <= 8'd0;
          index_previous_run_type_copy_above_q <= 1'b0;
          index_prev_index_q <= 8'd0;
          for (int i = 0; i < 16; i = i + 1) begin
            palette_run_copy_flags_q[i] <= 1'b0;
          end
          state_q <= ST_PAL_INDEX_RUN_FLAG;
        end

        ST_PAL_INDEX_RUN_FLAG: begin
          if (index_cur_pos_q >= index_max_sub_pos_q) begin
            index_level_pos_q <= index_min_sub_pos_q;
            state_q <= ST_PAL_INDEX_LEVEL;
          end else if (index_cur_pos_q == 8'd0) begin
            palette_run_copy_flags_q[0] <= 1'b0;
            index_prev_run_pos_q <= 8'd0;
            index_previous_run_type_copy_above_q <= 1'b0;
            index_prev_index_q <= index_cur_value;
            index_cur_pos_q <= index_cur_pos_q + 8'd1;
          end else begin
            m_axis_valid <= 1'b1;
            m_axis_kind <= SYMBOL_BIN_CTX;
            m_axis_data <= (({22'd0, VVC_CTX_RUN_COPY_FLAG_0 + index_run_copy_ctx_inc}) << 8) |
                           {31'd0, index_identity};
            m_axis_last <= 1'b0;
            palette_run_copy_flags_q[index_cur_pos_q[3:0]] <= index_identity;
            if (!index_identity) begin
              index_prev_run_pos_q <= index_cur_pos_q;
              index_previous_run_type_copy_above_q <= 1'b0;
            end
            index_prev_index_q <= index_cur_value;
            if (!index_identity && index_copy_above_present) begin
              state_q <= ST_PAL_INDEX_COPY_ABOVE;
            end else begin
              index_cur_pos_q <= index_cur_pos_q + 8'd1;
            end
          end
        end

        ST_PAL_INDEX_COPY_ABOVE: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_CTX;
          m_axis_data <= ({22'd0, VVC_CTX_COPY_ABOVE_PALETTE_FLAG} << 8);
          m_axis_last <= 1'b0;
          index_cur_pos_q <= index_cur_pos_q + 8'd1;
          state_q <= ST_PAL_INDEX_RUN_FLAG;
        end

        ST_PAL_INDEX_LEVEL: begin
          if (index_level_pos_q >= index_max_sub_pos_q) begin
            if (index_max_sub_pos_q >= palette_index_count_q) begin
              state_q <= pending_raw_last_q ? ST_PAL_TERMINATE : ST_IDLE;
            end else begin
              index_min_sub_pos_q <= index_max_sub_pos_q;
              index_max_sub_pos_q <= ((palette_index_count_q - index_max_sub_pos_q) < 8'd16) ?
                                     palette_index_count_q : (index_max_sub_pos_q + 8'd16);
              index_cur_pos_q <= index_max_sub_pos_q;
              for (int i = 0; i < 16; i = i + 1) begin
                palette_run_copy_flags_q[i] <= 1'b0;
              end
              state_q <= ST_PAL_INDEX_RUN_FLAG;
            end
          end else if (palette_run_copy_flags_q[index_level_pos_q[3:0]] ||
                       (trunc_num_symbols <= 8'd1)) begin
            index_level_pos_q <= index_level_pos_q + 8'd1;
          end else begin
            m_axis_valid <= 1'b1;
            m_axis_kind <= SYMBOL_BINS_EP;
            m_axis_data <= (trunc_pattern << 6) | {26'd0, trunc_bit_count};
            m_axis_last <= 1'b0;
            index_level_pos_q <= index_level_pos_q + 8'd1;
          end
        end

        ST_PAL_TERMINATE: begin
          m_axis_valid <= 1'b1;
          m_axis_kind <= SYMBOL_BIN_TRM;
          m_axis_data <= 32'd1;
          m_axis_last <= 1'b1;
          state_q <= ST_IDLE;
        end

        default: begin
          state_q <= ST_IDLE;
          if (raw_symbol_valid) begin
            pending_raw_last_q <= raw_symbol_last;
            case (raw_symbol_kind)
              PALETTE_PKT_CU_START: begin
                palette_entry_count_q <= raw_symbol_data[23:16];
                palette_entry_cr_count_q <= 8'd0;
                palette_index_count_q <= 8'd0;
                if (raw_symbol_data[24]) begin
                  palette_predictor_run_present_q <= palette_have_previous_cu_q;
                  palette_have_previous_cu_q <= 1'b1;
                  // CTU split and leaf no-split decisions are supplied by the
                  // shared partition engine before each palette CU payload.
                  // PALETTE_PKT_CU_START therefore begins at pred_mode_plt_flag.
                  state_q <= ST_PAL_PRED_MODE;
                end else if (raw_symbol_last) begin
                  state_q <= ST_PAL_TERMINATE;
                end
              end

              PALETTE_PKT_ENTRY_Y,
              PALETTE_PKT_ENTRY_CB,
              PALETTE_PKT_ENTRY_CR: begin
                // H.266 cu_palette_info(): new_palette_entries are bypass bins
                // with the bit depth of the component. The RTL palette path is
                // still 8-bit only; widen this producer when SAMPLE_BITS > 8 is
                // carried through the palette symbol stream.
                m_axis_valid <= 1'b1;
                m_axis_kind <= SYMBOL_BINS_EP;
                m_axis_data <= ({24'd0, raw_symbol_data[7:0]} << 6) | 32'd8;
                m_axis_last <= 1'b0;
                if ((raw_symbol_kind == PALETTE_PKT_ENTRY_CR) &&
                    ((palette_entry_cr_count_q + 8'd1) >= palette_entry_count_q)) begin
                  state_q <= ST_PAL_ESCAPE_FLAG;
                end else begin
                  state_q <= raw_symbol_last ? ST_PAL_TERMINATE : ST_IDLE;
                end
                if (raw_symbol_kind == PALETTE_PKT_ENTRY_CR) begin
                  palette_entry_cr_count_q <= palette_entry_cr_count_q + 8'd1;
                end
              end

              PALETTE_PKT_INDEX: begin
                palette_indices_q[palette_index_count_q[5:0]] <= raw_symbol_data[7:0];
                palette_index_count_q <= palette_index_count_q + 8'd1;
                if (palette_entry_count_q > 8'd1) begin
                  // H.266 7.3.11.6/9.3.4.2.11: palette index maps are coded
                  // as a transpose flag, run-copy flags, optional copy-above
                  // flags, and truncated index bins. End-of-CU and end-of-CABAC
                  // are separate signals: every CU must flush its own index map,
                  // while only the final CU terminates the CABAC stream.
                  state_q <= palette_raw_cu_last ? ST_PAL_INDEX_TRANSPOSE : ST_IDLE;
                end else if (raw_symbol_last) begin
                  m_axis_valid <= 1'b1;
                  m_axis_kind <= SYMBOL_BIN_TRM;
                  m_axis_data <= 32'd1;
                  m_axis_last <= 1'b1;
                  state_q <= ST_IDLE;
                end
              end

              default: begin
                m_axis_valid <= 1'b1;
                m_axis_kind <= raw_symbol_kind;
                m_axis_data <= raw_symbol_data;
                m_axis_last <= raw_symbol_last;
              end
            endcase
          end
        end
      endcase
    end
  end

  (* keep = "true" *) logic unused_future_ctu_inputs;
  assign unused_future_ctu_inputs = ctu_valid || (|ctu_x) || (|ctu_y) ||
    (|ctu_visible_width) || (|ctu_visible_height) || (|ctu_luma_dc_abs_level) ||
    ctu_luma_dc_negative || ctu_luma_only || ctu_last;
endmodule
