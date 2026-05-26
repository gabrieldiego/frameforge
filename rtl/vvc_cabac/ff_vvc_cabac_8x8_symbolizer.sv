`timescale 1ns/1ps

module ff_vvc_cabac_8x8_symbolizer (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       start,
  input  logic       clear,
  input  logic [4:0] luma_rem,
  input  logic [4:0] cb_rem,

  output logic       m_axis_valid,
  input  logic       m_axis_ready,
  output logic [2:0] m_axis_kind,
  output logic       m_axis_bin,
  output logic [8:0] m_axis_lps,
  output logic       m_axis_mps,
  output logic       m_axis_last,
  output logic       done
);
  localparam logic [2:0] CABAC_BIN_EP  = 3'd0;
  localparam logic [2:0] CABAC_BIN_TRM = 3'd1;
  localparam logic [2:0] CABAC_BIN_CTX = 3'd2;
  localparam int VVC_PROB_MODEL_BITS = 40;
  localparam int VVC_CTX_QP = 32;

  typedef logic [VVC_PROB_MODEL_BITS - 1:0] vvc_prob_model_t;

  localparam logic [3:0] PH_LUMA_SPLIT_A = 4'd0;
  localparam logic [3:0] PH_LUMA_SPLIT_B = 4'd1;
  localparam logic [3:0] PH_LUMA_CBF     = 4'd2;
  localparam logic [3:0] PH_LUMA_REM     = 4'd3;
  localparam logic [3:0] PH_LUMA_SIGN    = 4'd4;
  localparam logic [3:0] PH_LUMA_MODE_A  = 4'd5;
  localparam logic [3:0] PH_LUMA_MODE_B  = 4'd6;
  localparam logic [3:0] PH_CHROMA_CBF   = 4'd7;
  localparam logic [3:0] PH_CHROMA_REM   = 4'd8;
  localparam logic [3:0] PH_CHROMA_SIGN  = 4'd9;
  localparam logic [3:0] PH_TRM          = 4'd10;

  logic       active_q;
  logic [3:0] phase_q;
  logic [7:0] phase_bin_q;

  always_comb begin
    m_axis_valid = active_q;
    m_axis_kind = CABAC_BIN_CTX;
    m_axis_bin = 1'b0;
    m_axis_lps = 9'd0;
    m_axis_mps = 1'b0;
    m_axis_last = 1'b0;

    unique case (phase_q)
      PH_LUMA_SPLIT_A: begin
        m_axis_kind = CABAC_BIN_CTX;
        m_axis_bin = pattern_bit(8'b0000_0101, 8'd4, phase_bin_q);
        m_axis_lps = vvc_ctx_lps_from_model(5'd0 + phase_bin_q[4:0]);
        m_axis_mps = vvc_ctx_mps_from_model(5'd0 + phase_bin_q[4:0]);
      end
      PH_LUMA_SPLIT_B: begin
        m_axis_kind = CABAC_BIN_CTX;
        m_axis_bin = pattern_bit(8'b0000_0010, 8'd4, phase_bin_q);
        m_axis_lps = vvc_ctx_lps_from_model(5'd4 + phase_bin_q[4:0]);
        m_axis_mps = vvc_ctx_mps_from_model(5'd4 + phase_bin_q[4:0]);
      end
      PH_LUMA_CBF: begin
        m_axis_kind = CABAC_BIN_CTX;
        m_axis_bin = 1'b1;
        m_axis_lps = vvc_ctx_lps_from_model(5'd8);
        m_axis_mps = vvc_ctx_mps_from_model(5'd8);
      end
      PH_LUMA_REM: begin
        m_axis_kind = CABAC_BIN_EP;
        m_axis_bin = rem_abs_bit(luma_rem, phase_bin_q);
      end
      PH_LUMA_SIGN: begin
        m_axis_kind = CABAC_BIN_EP;
        m_axis_bin = 1'b1;
      end
      PH_LUMA_MODE_A: begin
        m_axis_kind = CABAC_BIN_CTX;
        m_axis_bin = pattern_bit(8'b0000_1011, 8'd4, phase_bin_q);
        m_axis_lps = vvc_ctx_lps_from_model(5'd9 + phase_bin_q[4:0]);
        m_axis_mps = vvc_ctx_mps_from_model(5'd9 + phase_bin_q[4:0]);
      end
      PH_LUMA_MODE_B: begin
        m_axis_kind = CABAC_BIN_CTX;
        m_axis_bin = pattern_bit(8'b0000_0100, 8'd3, phase_bin_q);
        m_axis_lps = vvc_ctx_lps_from_model(5'd13 + phase_bin_q[4:0]);
        m_axis_mps = vvc_ctx_mps_from_model(5'd13 + phase_bin_q[4:0]);
      end
      PH_CHROMA_CBF: begin
        m_axis_kind = CABAC_BIN_CTX;
        m_axis_bin = pattern_bit(8'b0000_0101, 8'd3, phase_bin_q);
        m_axis_lps = vvc_ctx_lps_from_model(5'd16 + phase_bin_q[4:0]);
        m_axis_mps = vvc_ctx_mps_from_model(5'd16 + phase_bin_q[4:0]);
      end
      PH_CHROMA_REM: begin
        m_axis_kind = CABAC_BIN_EP;
        m_axis_bin = rem_abs_bit(cb_rem, phase_bin_q);
      end
      PH_CHROMA_SIGN: begin
        m_axis_kind = CABAC_BIN_EP;
        m_axis_bin = 1'b1;
      end
      default: begin
        m_axis_kind = CABAC_BIN_TRM;
        m_axis_bin = 1'b1;
        m_axis_last = active_q;
      end
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      active_q <= 1'b0;
      phase_q <= PH_LUMA_SPLIT_A;
      phase_bin_q <= 8'd0;
      done <= 1'b0;
    end else if (clear) begin
      active_q <= 1'b0;
      phase_q <= PH_LUMA_SPLIT_A;
      phase_bin_q <= 8'd0;
      done <= 1'b0;
    end else begin
      done <= 1'b0;
      if (start) begin
        active_q <= 1'b1;
        phase_q <= PH_LUMA_SPLIT_A;
        phase_bin_q <= 8'd0;
      end else if (m_axis_valid && m_axis_ready) begin
        if (m_axis_last) begin
          active_q <= 1'b0;
          phase_q <= PH_LUMA_SPLIT_A;
          phase_bin_q <= 8'd0;
          done <= 1'b1;
        end else if (phase_bin_q + 8'd1 < phase_length(phase_q, luma_rem, cb_rem)) begin
          phase_bin_q <= phase_bin_q + 8'd1;
        end else begin
          phase_q <= next_phase(phase_q);
          phase_bin_q <= 8'd0;
        end
      end
    end
  end

  function automatic logic [3:0] next_phase(input logic [3:0] phase);
    begin
      if (phase == PH_TRM) begin
        next_phase = PH_TRM;
      end else begin
        next_phase = phase + 4'd1;
      end
    end
  endfunction

  function automatic logic [7:0] phase_length(
    input logic [3:0] phase,
    input logic [4:0] rem,
    input logic [4:0] cb_rem_in
  );
    begin
      unique case (phase)
        PH_LUMA_SPLIT_A: phase_length = 8'd4;
        PH_LUMA_SPLIT_B: phase_length = 8'd4;
        PH_LUMA_CBF:     phase_length = 8'd1;
        PH_LUMA_REM:     phase_length = rem_abs_len(rem);
        PH_LUMA_SIGN:    phase_length = 8'd1;
        PH_LUMA_MODE_A:  phase_length = 8'd4;
        PH_LUMA_MODE_B:  phase_length = 8'd3;
        PH_CHROMA_CBF:   phase_length = 8'd3;
        PH_CHROMA_REM:   phase_length = rem_abs_len(cb_rem_in);
        PH_CHROMA_SIGN:  phase_length = 8'd1;
        default:         phase_length = 8'd1;
      endcase
    end
  endfunction

  function automatic logic pattern_bit(
    input logic [7:0] pattern,
    input logic [7:0] len,
    input logic [7:0] bit_index
  );
    begin
      pattern_bit = pattern[len - 8'd1 - bit_index];
    end
  endfunction

  function automatic logic [2:0] rem_abs_prefix_len(input logic [4:0] value);
    logic [5:0] code_value;
    begin
      code_value = {1'b0, value} - 6'd5;
      if (code_value <= 6'd0) begin
        rem_abs_prefix_len = 3'd0;
      end else if (code_value <= 6'd2) begin
        rem_abs_prefix_len = 3'd1;
      end else if (code_value <= 6'd6) begin
        rem_abs_prefix_len = 3'd2;
      end else if (code_value <= 6'd14) begin
        rem_abs_prefix_len = 3'd3;
      end else begin
        rem_abs_prefix_len = 3'd4;
      end
    end
  endfunction

  function automatic logic [7:0] rem_abs_len(input logic [4:0] value);
    logic [2:0] prefix_length;
    begin
      if (value < 5'd5) begin
        rem_abs_len = {3'd0, value} + 8'd1;
      end else begin
        prefix_length = rem_abs_prefix_len(value);
        rem_abs_len = 8'd5 + {5'd0, prefix_length} + {5'd0, prefix_length} + 8'd1;
      end
    end
  endfunction

  function automatic logic rem_abs_bit(input logic [4:0] value, input logic [7:0] bit_index);
    logic [5:0] code_value;
    logic [2:0] prefix_length;
    logic [5:0] total_prefix_length;
    logic [5:0] suffix_length;
    logic [31:0] pattern;
    logic [7:0] len;
    begin
      if (value < 5'd5) begin
        len = {3'd0, value} + 8'd1;
        pattern = (32'd1 << len) - 32'd2;
      end else begin
        code_value = {1'b0, value} - 6'd5;
        prefix_length = rem_abs_prefix_len(value);
        total_prefix_length = {3'd0, prefix_length} + 6'd5;
        suffix_length = {3'd0, prefix_length} + 6'd1;
        len = {2'd0, total_prefix_length} + {2'd0, suffix_length};
        pattern =
          (((32'd1 << total_prefix_length) - 32'd1) << suffix_length) |
          (code_value - ((6'd1 << prefix_length) - 6'd1));
      end
      rem_abs_bit = pattern[len - 8'd1 - bit_index];
    end
  endfunction

  function automatic logic [8:0] vvc_ctx_lps_from_model(input logic [4:0] index);
    begin
      // TODO(vvc): the streamed writer should own context-state update and
      // use its live arithmetic range. This is the initial-state formula used
      // to keep the symbol interface synthesis-shaped while the old byte path
      // is still the conformance reference.
      vvc_ctx_lps_from_model = vvc_prob_model_lps(vvc_8x8_ctx_model(index), 16'd510);
    end
  endfunction

  function automatic logic vvc_ctx_mps_from_model(input logic [4:0] index);
    begin
      vvc_ctx_mps_from_model = vvc_prob_model_mps(vvc_8x8_ctx_model(index));
    end
  endfunction

  function automatic vvc_prob_model_t vvc_8x8_ctx_model(input logic [4:0] index);
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
        init_value = vvc_intra_luma_planar_flag_init(index[3:0] - 4'd13);
        log2_window_size = vvc_intra_luma_planar_flag_log2_window(index[3:0] - 4'd13);
      end else begin
        init_value = vvc_qt_cbf_cb_init(index[3:0]);
        log2_window_size = vvc_qt_cbf_cb_log2_window(index[3:0]);
      end
      vvc_8x8_ctx_model = vvc_prob_model_init(init_value, log2_window_size, VVC_CTX_QP);
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

  function automatic logic [7:0] vvc_split_flag_init(input logic [3:0] index);
    begin
      vvc_split_flag_init = 8'd19 + ({4'd0, index} * 8'd3);
    end
  endfunction

  function automatic logic [3:0] vvc_split_flag_log2_window(input logic [3:0] index);
    begin
      vvc_split_flag_log2_window = 4'd8 + index[1:0];
    end
  endfunction

  function automatic logic [7:0] vvc_split_qt_flag_init(input logic [3:0] index);
    begin
      vvc_split_qt_flag_init = 8'd27 - ({4'd0, index} * 8'd4);
    end
  endfunction

  function automatic logic [3:0] vvc_split_qt_flag_log2_window(input logic [3:0] index);
    begin
      vvc_split_qt_flag_log2_window = {2'd0, index[1:0]} << 2;
    end
  endfunction

  function automatic logic [7:0] vvc_multi_ref_line_idx_init(input logic [3:0] index);
    begin
      vvc_multi_ref_line_idx_init = 8'd25 + ({4'd0, index} * 8'd4);
    end
  endfunction

  function automatic logic [3:0] vvc_multi_ref_line_idx_log2_window(input logic [3:0] index);
    begin
      vvc_multi_ref_line_idx_log2_window = 4'd5 + index[1:0];
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
      vvc_intra_luma_planar_flag_init = 8'd13 + ({4'd0, index} * 8'd5);
    end
  endfunction

  function automatic logic [3:0] vvc_intra_luma_planar_flag_log2_window(input logic [3:0] index);
    begin
      vvc_intra_luma_planar_flag_log2_window = 4'd1 + index[2:0];
    end
  endfunction

  function automatic logic [7:0] vvc_qt_cbf_y_init(input logic [3:0] index);
    begin
      vvc_qt_cbf_y_init = 8'd15 - ({4'd0, index} * 8'd3);
    end
  endfunction

  function automatic logic [3:0] vvc_qt_cbf_y_log2_window(input logic [3:0] index);
    begin
      vvc_qt_cbf_y_log2_window = 4'd5 + index[1:0];
    end
  endfunction

  function automatic logic [7:0] vvc_qt_cbf_cb_init(input logic [3:0] index);
    begin
      vvc_qt_cbf_cb_init = 8'd17 + ({4'd0, index} * 8'd2);
    end
  endfunction

  function automatic logic [3:0] vvc_qt_cbf_cb_log2_window(input logic [3:0] index);
    begin
      vvc_qt_cbf_cb_log2_window = 4'd5 + index[1:0];
    end
  endfunction

  function automatic logic [7:0] vvc_mts_idx_init(input logic [3:0] index);
    begin
      vvc_mts_idx_init = 8'd29 - ({4'd0, index} * 8'd2);
    end
  endfunction

  function automatic logic [3:0] vvc_mts_idx_log2_window(input logic [3:0] index);
    begin
      vvc_mts_idx_log2_window = 4'd8 + index[0];
    end
  endfunction
endmodule
