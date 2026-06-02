`timescale 1ns/1ps

module ff_vvc_cabac_context_model #(
  parameter int VVC_CTX_COUNT = 53,
  parameter int VVC_CTX_QP = 32,
  parameter int VVC_CABAC_CTX_ID_BITS = 10
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        reset_contexts,

  input  logic [VVC_CABAC_CTX_ID_BITS - 1:0] query_ctx_id,
  input  logic [15:0] query_range,
  output logic [VVC_CABAC_CTX_ID_BITS - 1:0] query_bank_id,
  output logic [8:0]  query_lps,
  output logic        query_mps,

  input  logic        update_valid,
  input  logic [VVC_CABAC_CTX_ID_BITS - 1:0] update_ctx_id,
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
  localparam int VVC_CTX_LAST_SIG_X_PREFIX_15     = 22;
  localparam int VVC_CTX_LAST_SIG_Y_PREFIX_15     = 23;
  localparam int VVC_CTX_MTT_SPLIT_CU_VERTICAL_3  = 24;
  localparam int VVC_CTX_MTT_SPLIT_CU_BINARY_1    = 25;
  localparam int VVC_CTX_MTT_SPLIT_CU_BINARY_3    = 26;
  localparam int VVC_CTX_SPLIT_FLAG_1             = 27;
  localparam int VVC_CTX_SPLIT_FLAG_2             = 28;
  localparam int VVC_CTX_MTT_SPLIT_CU_VERTICAL_0  = 29;
  localparam int VVC_CTX_MTT_SPLIT_CU_VERTICAL_4  = 30;
  localparam int VVC_CTX_MTT_SPLIT_CU_BINARY_0    = 31;
  localparam int VVC_CTX_MTT_SPLIT_CU_BINARY_2    = 32;
  localparam int VVC_CTX_SPLIT_FLAG_4             = 33;
  localparam int VVC_CTX_SPLIT_QT_FLAG_1          = 34;
  localparam int VVC_CTX_SPLIT_QT_FLAG_2          = 35;
  localparam int VVC_CTX_SPLIT_QT_FLAG_4          = 36;
  localparam int VVC_CTX_SPLIT_QT_FLAG_5          = 37;
  localparam int VVC_CTX_SPLIT_FLAG_5             = 38;
  localparam int VVC_CTX_SPLIT_FLAG_8             = 39;
  localparam int VVC_CTX_MTT_SPLIT_CU_VERTICAL_1  = 40;
  localparam int VVC_CTX_MTT_SPLIT_CU_VERTICAL_2  = 41;
  localparam int VVC_CTX_PRED_MODE_PLT_FLAG        = 42;
  localparam int VVC_CTX_PALETTE_TRANSPOSE_FLAG    = 43;
  localparam int VVC_CTX_COPY_ABOVE_PALETTE_FLAG   = 44;
  localparam int VVC_CTX_RUN_COPY_FLAG_0           = 45;
  localparam int VVC_CTX_RUN_COPY_FLAG_1           = 46;
  localparam int VVC_CTX_RUN_COPY_FLAG_2           = 47;
  localparam int VVC_CTX_RUN_COPY_FLAG_3           = 48;
  localparam int VVC_CTX_RUN_COPY_FLAG_4           = 49;
  localparam int VVC_CTX_RUN_COPY_FLAG_5           = 50;
  localparam int VVC_CTX_RUN_COPY_FLAG_6           = 51;
  localparam int VVC_CTX_RUN_COPY_FLAG_7           = 52;
  localparam logic [VVC_CABAC_CTX_ID_BITS - 1:0] VVC_CTX_COUNT_LIMIT = VVC_CTX_COUNT;

  // ITU-T H.266 (V4) Table 62, initType 0 / I-slice gives
  // mtt_split_cu_binary_flag ctxIdx 0..3 initValue = 36,45,36,45
  // and shiftIdx = 12,13,12,13.
  localparam logic [(VVC_CTX_COUNT * 8) - 1:0] INIT_VALUE_LUT = {
    8'd46, // 52: RunCopyFlag(7) / CopyRunModel(2)
    8'd38, // 51: RunCopyFlag(6) / CopyRunModel(1)
    8'd45, // 50: RunCopyFlag(5) / CopyRunModel(0)
    8'd46, // 49: RunCopyFlag(4) / IdxRunModel(4)
    8'd30, // 48: RunCopyFlag(3) / IdxRunModel(3)
    8'd45, // 47: RunCopyFlag(2) / IdxRunModel(2)
    8'd37, // 46: RunCopyFlag(1) / IdxRunModel(1)
    8'd50, // 45: RunCopyFlag(0) / IdxRunModel(0)
    8'd42, // 44: copy_above_palette_indices_flag / RunTypeFlag
    8'd42, // 43: palette_transpose_flag / RotationFlag
    8'd25, // 42: pred_mode_plt_flag / PLTFlag
    8'd29, // 41: MttSplitCuVerticalFlag(2)
    8'd42, // 40: MttSplitCuVerticalFlag(1)
    8'd31, // 39: SplitFlag(8)
    8'd38, // 38: SplitFlag(5)
    8'd37, // 37: SplitQtFlag(5)
    8'd19, // 36: SplitQtFlag(4)
    8'd15, // 35: SplitQtFlag(2)
    8'd6,  // 34: SplitQtFlag(1)
    8'd29, // 33: SplitFlag(4)
    8'd36, // 32: MttSplitCuBinaryFlag(2)
    8'd36, // 31: MttSplitCuBinaryFlag(0)
    8'd44, // 30: MttSplitCuVerticalFlag(4)
    8'd43, // 29: MttSplitCuVerticalFlag(0)
    8'd38, // 28: SplitFlag(2)
    8'd28, // 27: SplitFlag(1)
    8'd45, // 26: MttSplitCuBinaryFlag(3)
    8'd45, // 25: MttSplitCuBinaryFlag(1)
    8'd27, // 24: MttSplitCuVerticalFlag(3)
    8'd6,  // 23: LastSigCoeffYPrefix(15)
    8'd21, // 22: LastSigCoeffXPrefix(15)
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
    4'd5,  // 52: RunCopyFlag(7) / CopyRunModel(2)
    4'd9,  // 51: RunCopyFlag(6) / CopyRunModel(1)
    4'd0,  // 50: RunCopyFlag(5) / CopyRunModel(0)
    4'd5,  // 49: RunCopyFlag(4) / IdxRunModel(4)
    4'd10, // 48: RunCopyFlag(3) / IdxRunModel(3)
    4'd9,  // 47: RunCopyFlag(2) / IdxRunModel(2)
    4'd6,  // 46: RunCopyFlag(1) / IdxRunModel(1)
    4'd9,  // 45: RunCopyFlag(0) / IdxRunModel(0)
    4'd9,  // 44: copy_above_palette_indices_flag / RunTypeFlag
    4'd5,  // 43: palette_transpose_flag / RotationFlag
    4'd1,  // 42: pred_mode_plt_flag / PLTFlag
    4'd9,  // 41: MttSplitCuVerticalFlag(2)
    4'd8,  // 40: MttSplitCuVerticalFlag(1)
    4'd9,  // 39: SplitFlag(8)
    4'd12, // 38: SplitFlag(5)
    4'd8,  // 37: SplitQtFlag(5)
    4'd12, // 36: SplitQtFlag(4)
    4'd8,  // 35: SplitQtFlag(2)
    4'd8,  // 34: SplitQtFlag(1)
    4'd13, // 33: SplitFlag(4)
    4'd12, // 32: MttSplitCuBinaryFlag(2)
    4'd12, // 31: MttSplitCuBinaryFlag(0)
    4'd5,  // 30: MttSplitCuVerticalFlag(4)
    4'd9,  // 29: MttSplitCuVerticalFlag(0)
    4'd8,  // 28: SplitFlag(2)
    4'd13, // 27: SplitFlag(1)
    4'd13, // 26: MttSplitCuBinaryFlag(3)
    4'd13, // 25: MttSplitCuBinaryFlag(1)
    4'd8,  // 24: MttSplitCuVerticalFlag(3)
    4'd1,  // 23: LastSigCoeffYPrefix(15)
    4'd0,  // 22: LastSigCoeffXPrefix(15)
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
  logic [VVC_CABAC_CTX_ID_BITS - 1:0] update_bank_id;
  logic [VVC_CABAC_CTX_ID_BITS - 1:0] query_bank_id_next;
  logic [VVC_CABAC_CTX_ID_BITS - 1:0] update_bank_id_next;
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
      query_bank_id_next = '0;
    end

    update_bank_id_next = update_ctx_id;
    if (update_ctx_id >= VVC_CTX_COUNT_LIMIT) begin
      update_bank_id_next = '0;
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
