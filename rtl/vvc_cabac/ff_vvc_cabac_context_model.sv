`timescale 1ns/1ps

module ff_vvc_cabac_context_model #(
  parameter int VVC_CTX_COUNT = 22,
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
  // Compact context bank used by the current VVC intra subset. The bank ID is
  // carried by SYMBOL_BIN_CTX and maps to a named VVC context, not to a stream
  // position. Extend this table when new syntax producers need new contexts.
  localparam int VVC_CTX_SPLIT_FLAG_0             = 0;
  localparam int VVC_CTX_SPLIT_FLAG_6             = 1;
  localparam int VVC_CTX_SPLIT_QT_FLAG_3          = 2;
  localparam int VVC_CTX_SPLIT_FLAG_3             = 3;
  localparam int VVC_CTX_INTRA_LUMA_MPM_FLAG      = 4;
  localparam int VVC_CTX_QT_CBF_Y_0               = 5;
  localparam int VVC_CTX_LAST_SIG_X_PREFIX_3      = 6;
  localparam int VVC_CTX_LAST_SIG_Y_PREFIX_3      = 7;
  localparam int VVC_CTX_LAST_SIG_X_PREFIX_6      = 8;
  localparam int VVC_CTX_LAST_SIG_Y_PREFIX_6      = 9;
  localparam int VVC_CTX_ABS_LEVEL_GTX_FLAG_0     = 10;
  localparam int VVC_CTX_PAR_LEVEL_FLAG_0         = 11;
  localparam int VVC_CTX_ABS_LEVEL_GTX_FLAG_32    = 12;
  localparam int VVC_CTX_CCLM_MODE_FLAG           = 13;
  localparam int VVC_CTX_INTRA_CHROMA_PRED_MODE_0 = 14;
  localparam int VVC_CTX_QT_CBF_CB_0              = 15;
  localparam int VVC_CTX_QT_CBF_CR_0              = 16;
  localparam int VVC_CTX_LAST_SIG_X_PREFIX_10     = 17;
  localparam int VVC_CTX_LAST_SIG_Y_PREFIX_10     = 18;
  localparam int VVC_CTX_SPLIT_FLAG_7             = 19;
  localparam int VVC_CTX_SPLIT_QT_FLAG_0          = 20;
  localparam int VVC_CTX_MULTI_REF_LINE_IDX_0     = 21;
  localparam logic [4:0] VVC_CTX_COUNT_LIMIT = VVC_CTX_COUNT;

  localparam logic [(VVC_CTX_COUNT * 8) - 1:0] INIT_VALUE_LUT = {
    8'd25, // 21: MultiRefLineIdx(0)
    8'd27, // 20: SplitQtFlag(0)
    8'd30, // 19: SplitFlag(7)
    8'd14, // 18: LastSigCoeffYPrefix(10)
    8'd14, // 17: LastSigCoeffXPrefix(10)
    8'd33, // 16: QtCbfCr(0)
    8'd12, // 15: QtCbfCb(0)
    8'd34, // 14: IntraChromaPredMode(0)
    8'd59, // 13: CclmModeFlag
    8'd25, // 12: AbsLevelGtxFlag(32)
    8'd33, // 11: ParLevelFlag(0)
    8'd25, // 10: AbsLevelGtxFlag(0)
    8'd14, //  9: LastSigCoeffYPrefix(6)
    8'd6,  //  8: LastSigCoeffXPrefix(6)
    8'd6,  //  7: LastSigCoeffYPrefix(3)
    8'd21, //  6: LastSigCoeffXPrefix(3)
    8'd15, //  5: QtCbfY(0)
    8'd45, //  4: IntraLumaMpmFlag
    8'd27, //  3: SplitFlag(3)
    8'd25, //  2: SplitQtFlag(3)
    8'd20, //  1: SplitFlag(6)
    8'd19  //  0: SplitFlag(0)
  };
  localparam logic [(VVC_CTX_COUNT * 4) - 1:0] LOG2_WINDOW_LUT = {
    4'd5,  // 21: MultiRefLineIdx(0)
    4'd0,  // 20: SplitQtFlag(0)
    4'd9,  // 19: SplitFlag(7)
    4'd5,  // 18: LastSigCoeffYPrefix(10)
    4'd4,  // 17: LastSigCoeffXPrefix(10)
    4'd2,  // 16: QtCbfCr(0)
    4'd5,  // 15: QtCbfCb(0)
    4'd5,  // 14: IntraChromaPredMode(0)
    4'd4,  // 13: CclmModeFlag
    4'd1,  // 12: AbsLevelGtxFlag(32)
    4'd8,  // 11: ParLevelFlag(0)
    4'd9,  // 10: AbsLevelGtxFlag(0)
    4'd5,  //  9: LastSigCoeffYPrefix(6)
    4'd5,  //  8: LastSigCoeffXPrefix(6)
    4'd5,  //  7: LastSigCoeffYPrefix(3)
    4'd5,  //  6: LastSigCoeffXPrefix(3)
    4'd5,  //  5: QtCbfY(0)
    4'd6,  //  4: IntraLumaMpmFlag
    4'd8,  //  3: SplitFlag(3)
    4'd12, //  2: SplitQtFlag(3)
    4'd5,  //  1: SplitFlag(6)
    4'd12  //  0: SplitFlag(0)
  };

  typedef logic [VVC_PROB_MODEL_BITS - 1:0] vvc_prob_model_t;

  vvc_prob_model_t ctx_model_q [0:VVC_CTX_COUNT - 1];
  vvc_prob_model_t ctx_init_model [0:VVC_CTX_COUNT - 1];
  logic [4:0] update_bank_id;
  logic [4:0] query_bank_id_next;
  logic [4:0] update_bank_id_next;
  logic [16:0] query_state_sum;
  logic [7:0] query_state;
  logic [15:0] query_q;
  logic [15:0] query_lps_full;
  logic [15:0] update_state0;
  logic [15:0] update_state1;
  logic [7:0] update_rate;
  logic [3:0] update_rate0;
  logic [3:0] update_rate1;
  integer ctx_i;
  integer model_i;
  integer slope_i;
  integer offset_i;
  integer inistate_i;
  integer rate0_i;
  integer rate1_i;

  assign query_bank_id = query_bank_id_next;
  assign update_bank_id = update_bank_id_next;

  always_comb begin
    query_bank_id_next = query_ctx_id;
    if (query_ctx_id >= VVC_CTX_COUNT_LIMIT) begin
      query_bank_id_next = VVC_CTX_SPLIT_FLAG_0[4:0];
    end

    update_bank_id_next = update_ctx_id;
    if (update_ctx_id >= VVC_CTX_COUNT_LIMIT) begin
      update_bank_id_next = VVC_CTX_SPLIT_FLAG_0[4:0];
    end
  end

  always_comb begin
    for (model_i = 0; model_i < VVC_CTX_COUNT; model_i = model_i + 1) begin
      slope_i = (INIT_VALUE_LUT[model_i * 8 +: 8] >> 3) - 4;
      offset_i = ((INIT_VALUE_LUT[model_i * 8 +: 8] & 8'd7) * 18) + 1;
      inistate_i = ((slope_i * (VVC_CTX_QP - 16)) >>> 1) + offset_i;
      if (inistate_i < 1) begin
        inistate_i = 1;
      end else if (inistate_i > 127) begin
        inistate_i = 127;
      end
      rate0_i = 2 + ((LOG2_WINDOW_LUT[model_i * 4 +: 4] >> 2) & 3);
      rate1_i = 3 + rate0_i + (LOG2_WINDOW_LUT[model_i * 4 +: 4] & 3);
      ctx_init_model[model_i][0 +: 16] = (inistate_i[15:0] << 8) & 16'h7fe0;
      ctx_init_model[model_i][16 +: 16] = (inistate_i[15:0] << 8) & 16'h7ffe;
      ctx_init_model[model_i][32 +: 8] = ((rate0_i & 8'h0f) << 4) | (rate1_i & 8'h0f);
    end
  end

  always @* begin
    query_state_sum = {1'b0, ctx_model_q[query_bank_id_next][0 +: 16]} +
      {1'b0, ctx_model_q[query_bank_id_next][16 +: 16]};
    query_state = query_state_sum[15:8];
    query_q = {8'd0, query_state};
    if (query_q[7]) begin
      query_q = query_q ^ 16'h00ff;
    end
    query_lps_full = (((query_q >> 2) * (query_range >> 5)) >> 1) + 16'd4;
    query_lps = query_lps_full[8:0];
    query_mps = query_state[7];
  end

  always @* begin
    update_state0 = ctx_model_q[update_bank_id_next][0 +: 16];
    update_state1 = ctx_model_q[update_bank_id_next][16 +: 16];
    update_rate = ctx_model_q[update_bank_id_next][32 +: 8];
    update_rate0 = update_rate[7:4];
    update_rate1 = update_rate[3:0];
    update_state0 = update_state0 - ((update_state0 >> update_rate0) & 16'h7fe0);
    update_state1 = update_state1 - ((update_state1 >> update_rate1) & 16'h7ffe);
    if (update_bin) begin
      update_state0 = update_state0 + ((16'h7fff >> update_rate0) & 16'h7fe0);
      update_state1 = update_state1 + ((16'h7fff >> update_rate1) & 16'h7ffe);
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (ctx_i = 0; ctx_i < VVC_CTX_COUNT; ctx_i = ctx_i + 1) begin
        ctx_model_q[ctx_i] <= ctx_init_model[ctx_i];
      end
    end else if (reset_contexts) begin
      for (ctx_i = 0; ctx_i < VVC_CTX_COUNT; ctx_i = ctx_i + 1) begin
        ctx_model_q[ctx_i] <= ctx_init_model[ctx_i];
      end
    end else if (update_valid) begin
      ctx_model_q[update_bank_id] <= {
        ctx_model_q[update_bank_id][32 +: 8],
        update_state1,
        update_state0
      };
    end
  end
endmodule
