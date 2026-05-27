`timescale 1ns/1ps

module ff_vvc_cabac_context_model #(
  parameter int VVC_CTX_COUNT = 32,
  parameter int VVC_CTX_QP = 32
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        reset_contexts,

  input  logic [4:0]  query_ctx_id,
  input  logic [15:0] query_range,
  output logic [4:0]  query_bank_id,
  output logic [8:0]  query_lps,
  output logic        query_mps,

  input  logic        update_valid,
  input  logic [4:0]  update_ctx_id,
  input  logic        update_bin
);
  localparam int VVC_PROB_MODEL_BITS = 40;

  typedef logic [VVC_PROB_MODEL_BITS - 1:0] vvc_prob_model_t;

  vvc_prob_model_t ctx_model_q [0:VVC_CTX_COUNT - 1];
  logic [4:0] update_bank_id;
  integer ctx_i;

  assign query_bank_id = vvc_context_bank_id(query_ctx_id);
  assign update_bank_id = vvc_context_bank_id(update_ctx_id);
  assign query_lps = vvc_prob_model_lps(ctx_model_q[query_bank_id], query_range);
  assign query_mps = vvc_prob_model_mps(ctx_model_q[query_bank_id]);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (ctx_i = 0; ctx_i < VVC_CTX_COUNT; ctx_i = ctx_i + 1) begin
        ctx_model_q[ctx_i] <= vvc_context_model_init(ctx_i[4:0]);
      end
    end else if (reset_contexts) begin
      for (ctx_i = 0; ctx_i < VVC_CTX_COUNT; ctx_i = ctx_i + 1) begin
        ctx_model_q[ctx_i] <= vvc_context_model_init(ctx_i[4:0]);
      end
    end else if (update_valid) begin
      ctx_model_q[update_bank_id] <= vvc_prob_model_update(ctx_model_q[update_bank_id], update_bin);
    end
  end

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
endmodule
