`timescale 1ns/1ps

module ff_vvc_cabac_context_model #(
  parameter int VVC_CTX_COUNT = 295,
  parameter int VVC_CTX_QP = 32,
  parameter int VVC_CABAC_CTX_ID_BITS = 10
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        reset_contexts,
  input  logic        lossless_slice_qp,

  input  logic [VVC_CABAC_CTX_ID_BITS - 1:0] query_ctx_id,
  input  logic [15:0] query_range,
  output logic [VVC_CABAC_CTX_ID_BITS - 1:0] query_bank_id,
  output logic [8:0]  query_lps,
  output logic        query_mps,

  input  logic        update_valid,
  input  logic [VVC_CABAC_CTX_ID_BITS - 1:0] update_ctx_id,
  input  logic        update_bin
);
  // Compact context bank used by the current VVC intra subset. The bank ID is
  // carried by SYMBOL_BIN_CTX and maps to a named VVC context, not to a stream
  // position. Extend this table when new syntax producers need new contexts.
  `include "ff_vvc_cabac_context_ids.svh"
  localparam logic [VVC_CABAC_CTX_ID_BITS - 1:0] VVC_CTX_COUNT_LIMIT = VVC_CTX_COUNT;

  // H.266 Table 132 defines residual context ranges for residual_coding().
  // The compact bank keeps the full last_sig_coeff, sb_coded, sig_coeff,
  // par_level, and abs_level_gtx ranges initialized even before every RTL
  // producer emits each context.
  localparam logic [(VVC_CTX_COUNT * 8) - 1:0] INIT_VALUE_LUT = {
    8'd12, // 294: CuCodedFlag(2)
    8'd5, // 293: CuCodedFlag(1)
    8'd6, // 292: CuCodedFlag(0)
    8'd36, // 291: AbsMvdGreater1Flag(2)
    8'd43, // 290: AbsMvdGreater1Flag(1)
    8'd45, // 289: AbsMvdGreater1Flag(0)
    8'd51, // 288: AbsMvdGreater0Flag(2)
    8'd44, // 287: AbsMvdGreater0Flag(1)
    8'd14, // 286: AbsMvdGreater0Flag(0)
    8'd6, // 285: GeneralMergeFlag(2)
    8'd21, // 284: GeneralMergeFlag(1)
    8'd26, // 283: GeneralMergeFlag(0)
    8'd45, // 282: PredModeIbcFlag(8)
    8'd43, // 281: PredModeIbcFlag(7)
    8'd0, // 280: PredModeIbcFlag(6)
    8'd44, // 279: PredModeIbcFlag(5)
    8'd57, // 278: PredModeIbcFlag(4)
    8'd0, // 277: PredModeIbcFlag(3)
    8'd36, // 276: PredModeIbcFlag(2)
    8'd42, // 275: PredModeIbcFlag(1)
    8'd17, // 274: PredModeIbcFlag(0)
    8'd46, // 273: CuSkipFlag(8)
    8'd60, // 272: CuSkipFlag(7)
    8'd57, // 271: CuSkipFlag(6)
    8'd45, // 270: CuSkipFlag(5)
    8'd59, // 269: CuSkipFlag(4)
    8'd57, // 268: CuSkipFlag(3)
    8'd28, // 267: CuSkipFlag(2)
    8'd26, // 266: CuSkipFlag(1)
    8'd0, // 265: CuSkipFlag(0)
    8'd3, // 264: AbsLevelGtxFlag(71)
    8'd3, // 263: AbsLevelGtxFlag(70)
    8'd3, // 262: AbsLevelGtxFlag(69)
    8'd10, // 261: AbsLevelGtxFlag(68)
    8'd14, // 260: AbsLevelGtxFlag(67)
    8'd5, // 259: AbsLevelGtxFlag(66)
    8'd5, // 258: AbsLevelGtxFlag(65)
    8'd11, // 257: AbsLevelGtxFlag(64)
    8'd11, // 256: AbsLevelGtxFlag(37)
    8'd33, // 255: AbsLevelGtxFlag(36)
    8'd25, // 254: AbsLevelGtxFlag(35)
    8'd40, // 253: AbsLevelGtxFlag(34)
    8'd1, // 252: AbsLevelGtxFlag(33)
    8'd21, // 251: AbsLevelGtxFlag(5)
    8'd20, // 250: AbsLevelGtxFlag(4)
    8'd27, // 249: AbsLevelGtxFlag(3)
    8'd11, // 248: AbsLevelGtxFlag(2)
    8'd25, // 247: AbsLevelGtxFlag(1)
    8'd11, // 246: ParLevelFlag(32)
    8'd27, // 245: ParLevelFlag(5)
    8'd34, // 244: ParLevelFlag(4)
    8'd26, // 243: ParLevelFlag(3)
    8'd18, // 242: ParLevelFlag(2)
    8'd25, // 241: ParLevelFlag(1)
    8'd38, // 240: SigCoeffFlag(62)
    8'd28, // 239: SigCoeffFlag(61)
    8'd25, // 238: SigCoeffFlag(60)
    8'd39, // 237: SigCoeffFlag(59)
    8'd39, // 236: SigCoeffFlag(58)
    8'd39, // 235: SigCoeffFlag(57)
    8'd19, // 234: SigCoeffFlag(56)
    8'd39, // 233: SigCoeffFlag(55)
    8'd39, // 232: SigCoeffFlag(54)
    8'd39, // 231: SigCoeffFlag(53)
    8'd11, // 230: SigCoeffFlag(52)
    8'd39, // 229: SigCoeffFlag(51)
    8'd39, // 228: SigCoeffFlag(50)
    8'd39, // 227: SigCoeffFlag(49)
    8'd52, // 226: SigCoeffFlag(48)
    8'd39, // 225: SigCoeffFlag(47)
    8'd38, // 224: SigCoeffFlag(46)
    8'd46, // 223: SigCoeffFlag(45)
    8'd19, // 222: SigCoeffFlag(44)
    8'd39, // 221: SigCoeffFlag(35)
    8'd39, // 220: SigCoeffFlag(34)
    8'd39, // 219: SigCoeffFlag(33)
    8'd0, // 218: SigCoeffFlag(32)
    8'd39, // 217: SigCoeffFlag(31)
    8'd39, // 216: SigCoeffFlag(30)
    8'd39, // 215: SigCoeffFlag(29)
    8'd27, // 214: SigCoeffFlag(28)
    8'd39, // 213: SigCoeffFlag(27)
    8'd39, // 212: SigCoeffFlag(26)
    8'd39, // 211: SigCoeffFlag(25)
    8'd18, // 210: SigCoeffFlag(24)
    8'd39, // 209: SigCoeffFlag(23)
    8'd39, // 208: SigCoeffFlag(22)
    8'd39, // 207: SigCoeffFlag(21)
    8'd44, // 206: SigCoeffFlag(20)
    8'd39, // 205: SigCoeffFlag(19)
    8'd39, // 204: SigCoeffFlag(18)
    8'd39, // 203: SigCoeffFlag(17)
    8'd27, // 202: SigCoeffFlag(16)
    8'd54, // 201: SigCoeffFlag(15)
    8'd46, // 200: SigCoeffFlag(14)
    8'd38, // 199: SigCoeffFlag(13)
    8'd11, // 198: SigCoeffFlag(12)
    8'd38, // 197: SbCodedFlag(6)
    8'd20, // 196: SbCodedFlag(5)
    8'd18, // 195: SbCodedFlag(4)
    8'd15, // 194: SbCodedFlag(3)
    8'd25, // 193: SbCodedFlag(2)
    8'd31, // 192: SbCodedFlag(1)
    8'd18, // 191: SbCodedFlag(0)
    8'd34, // 190: LastSigCoeffYPrefix(19)
    8'd42, // 189: LastSigCoeffXPrefix(19)
    8'd20, // 188: LastSigCoeffYPrefix(18)
    8'd13, // 187: LastSigCoeffXPrefix(18)
    8'd29, // 186: LastSigCoeffYPrefix(17)
    8'd22, // 185: LastSigCoeffXPrefix(17)
    8'd22, // 184: LastSigCoeffYPrefix(16)
    8'd30, // 183: LastSigCoeffXPrefix(16)
    8'd3, // 182: LastSigCoeffYPrefix(14)
    8'd11, // 181: LastSigCoeffXPrefix(14)
    8'd4, // 180: LastSigCoeffYPrefix(13)
    8'd5, // 179: LastSigCoeffXPrefix(13)
    8'd6, // 178: LastSigCoeffYPrefix(12)
    8'd14, // 177: LastSigCoeffXPrefix(12)
    8'd22, // 176: LastSigCoeffYPrefix(11)
    8'd7, // 175: LastSigCoeffXPrefix(11)
    8'd3, // 174: LastSigCoeffYPrefix(9)
    8'd11, // 173: LastSigCoeffXPrefix(9)
    8'd5, // 172: LastSigCoeffYPrefix(8)
    8'd21, // 171: LastSigCoeffXPrefix(8)
    8'd6, // 170: LastSigCoeffYPrefix(7)
    8'd14, // 169: LastSigCoeffXPrefix(7)
    8'd11, // 168: LastSigCoeffYPrefix(5)
    8'd4, // 167: LastSigCoeffXPrefix(5)
    8'd4, // 166: LastSigCoeffYPrefix(2)
    8'd4, // 165: LastSigCoeffXPrefix(2)
    8'd5, // 164: LastSigCoeffYPrefix(1)
    8'd5, // 163: LastSigCoeffXPrefix(1)
    8'd13, // 162: LastSigCoeffYPrefix(0)
    8'd13, // 161: LastSigCoeffXPrefix(0)
    8'd22, // 160: AbsLevelGtxFlag(52)
    8'd28, // 159: AbsLevelGtxFlag(51)
    8'd20, // 158: AbsLevelGtxFlag(50)
    8'd19, // 157: AbsLevelGtxFlag(49)
    8'd33, // 156: AbsLevelGtxFlag(48)
    8'd13, // 155: AbsLevelGtxFlag(47)
    8'd19, // 154: AbsLevelGtxFlag(46)
    8'd33, // 153: AbsLevelGtxFlag(44)
    8'd4, // 152: AbsLevelGtxFlag(42)
    8'd18, // 151: AbsLevelGtxFlag(41)
    8'd25, // 150: AbsLevelGtxFlag(40)
    8'd17, // 149: AbsLevelGtxFlag(38)
    8'd23, // 148: AbsLevelGtxFlag(20)
    8'd30, // 147: AbsLevelGtxFlag(19)
    8'd45, // 146: AbsLevelGtxFlag(18)
    8'd29, // 145: AbsLevelGtxFlag(17)
    8'd36, // 144: AbsLevelGtxFlag(16)
    8'd30, // 143: AbsLevelGtxFlag(15)
    8'd29, // 142: AbsLevelGtxFlag(14)
    8'd28, // 141: AbsLevelGtxFlag(12)
    8'd22, // 140: AbsLevelGtxFlag(10)
    8'd21, // 139: AbsLevelGtxFlag(9)
    8'd28, // 138: AbsLevelGtxFlag(8)
    8'd33, // 137: AbsLevelGtxFlag(6)
    8'd20, // 136: ParLevelFlag(20)
    8'd43, // 135: ParLevelFlag(19)
    8'd20, // 134: ParLevelFlag(18)
    8'd42, // 133: ParLevelFlag(17)
    8'd34, // 132: ParLevelFlag(16)
    8'd35, // 131: ParLevelFlag(15)
    8'd35, // 130: ParLevelFlag(14)
    8'd19, // 129: ParLevelFlag(12)
    8'd35, // 128: ParLevelFlag(10)
    8'd42, // 127: ParLevelFlag(9)
    8'd19, // 126: ParLevelFlag(8)
    8'd25, // 125: ParLevelFlag(6)
    8'd38, // 124: SigCoeffFlag(11)
    8'd30, // 123: SigCoeffFlag(10)
    8'd19, // 122: SigCoeffFlag(8)
    8'd30, // 121: SigCoeffFlag(7)
    8'd14, // 120: SigCoeffFlag(3)
    8'd28, // 119: SigCoeffFlag(2)
    8'd25, // 118: SigCoeffFlag(0)
    8'd37, // 117: AbsLevelGtxFlag(63)
    8'd28, // 116: AbsLevelGtxFlag(62)
    8'd35, // 115: AbsLevelGtxFlag(61)
    8'd26, // 114: AbsLevelGtxFlag(60)
    8'd25, // 113: AbsLevelGtxFlag(59)
    8'd35, // 112: AbsLevelGtxFlag(58)
    8'd26, // 111: AbsLevelGtxFlag(57)
    8'd18, // 110: AbsLevelGtxFlag(56)
    8'd25, // 109: AbsLevelGtxFlag(55)
    8'd9,  // 108: AbsLevelGtxFlag(54)
    8'd40, // 107: AbsLevelGtxFlag(53)
    8'd46, // 106: AbsLevelGtxFlag(31)
    8'd38, // 105: AbsLevelGtxFlag(30)
    8'd45, // 104: AbsLevelGtxFlag(29)
    8'd37, // 103: AbsLevelGtxFlag(28)
    8'd36, // 102: AbsLevelGtxFlag(27)
    8'd37, // 101: AbsLevelGtxFlag(26)
    8'd21, // 100: AbsLevelGtxFlag(25)
    8'd28, //  99: AbsLevelGtxFlag(24)
    8'd27, //  98: AbsLevelGtxFlag(23)
    8'd33, //  97: AbsLevelGtxFlag(22)
    8'd40, //  96: AbsLevelGtxFlag(21)
    8'd43, //  95: ParLevelFlag(31)
    8'd20, //  94: ParLevelFlag(30)
    8'd35, //  93: ParLevelFlag(29)
    8'd50, //  92: ParLevelFlag(28)
    8'd26, //  91: ParLevelFlag(27)
    8'd27, //  90: ParLevelFlag(26)
    8'd19, //  89: ParLevelFlag(25)
    8'd42, //  88: ParLevelFlag(24)
    8'd26, //  87: ParLevelFlag(23)
    8'd25, //  86: ParLevelFlag(22)
    8'd33, //  85: ParLevelFlag(21)
    8'd46, //  84: SigCoeffFlag(43)
    8'd53, //  83: SigCoeffFlag(42)
    8'd53, //  82: SigCoeffFlag(41)
    8'd34, //  81: SigCoeffFlag(40)
    8'd37, //  80: SigCoeffFlag(39)
    8'd28, //  79: SigCoeffFlag(38)
    8'd27, //  78: SigCoeffFlag(37)
    8'd25, //  77: SigCoeffFlag(36)
    8'd3,  //  76: LastSigCoeffYPrefix(22)
    8'd3,  //  75: LastSigCoeffXPrefix(22)
    8'd4,  //  74: LastSigCoeffYPrefix(21)
    8'd4,  //  73: LastSigCoeffXPrefix(21)
    8'd12, //  72: LastSigCoeffYPrefix(20)
    8'd12, //  71: LastSigCoeffXPrefix(20)
    8'd28, //  70: QtCbfCr(1)
    8'd26, // 69: AbsLevelGtxFlag(45)
    8'd27, // 68: ParLevelFlag(13)
    8'd29, // 67: AbsLevelGtxFlag(13)
    8'd25, // 66: AbsLevelGtxFlag(39)
    8'd26, // 65: ParLevelFlag(7)
    8'd12, // 64: AbsLevelGtxFlag(7)
    8'd29, // 63: SigCoeffFlag(6)
    8'd17, // 62: AbsLevelGtxFlag(43)
    8'd33, // 61: ParLevelFlag(11)
    8'd34, // 60: AbsLevelGtxFlag(11)
    8'd37, // 59: SigCoeffFlag(9)
    8'd20, // 58: SigCoeffFlag(5)
    8'd25, // 57: SigCoeffFlag(4)
    8'd19, // 56: SigCoeffFlag(1)
    8'd13, // 55: LastSigCoeffYPrefix(4)
    8'd14, // 54: LastSigCoeffXPrefix(4)
    8'd28, // 53: IntraLumaPlanarFlag(1)
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
    4'd4,  // 294: CuCodedFlag(2)
    4'd4,  // 293: CuCodedFlag(1)
    4'd4,  // 292: CuCodedFlag(0)
    4'd5,  // 291: AbsMvdGreater1Flag(2)
    4'd5,  // 290: AbsMvdGreater1Flag(1)
    4'd5,  // 289: AbsMvdGreater1Flag(0)
    4'd9,  // 288: AbsMvdGreater0Flag(2)
    4'd9,  // 287: AbsMvdGreater0Flag(1)
    4'd9,  // 286: AbsMvdGreater0Flag(0)
    4'd4,  // 285: GeneralMergeFlag(2)
    4'd4,  // 284: GeneralMergeFlag(1)
    4'd4,  // 283: GeneralMergeFlag(0)
    4'd8,  // 282: PredModeIbcFlag(8)
    4'd5,  // 281: PredModeIbcFlag(7)
    4'd1,  // 280: PredModeIbcFlag(6)
    4'd8,  // 279: PredModeIbcFlag(5)
    4'd5,  // 278: PredModeIbcFlag(4)
    4'd1,  // 277: PredModeIbcFlag(3)
    4'd8,  // 276: PredModeIbcFlag(2)
    4'd5,  // 275: PredModeIbcFlag(1)
    4'd1,  // 274: PredModeIbcFlag(0)
    4'd8,  // 273: CuSkipFlag(8)
    4'd4,  // 272: CuSkipFlag(7)
    4'd5,  // 271: CuSkipFlag(6)
    4'd8,  // 270: CuSkipFlag(5)
    4'd4,  // 269: CuSkipFlag(4)
    4'd5,  // 268: CuSkipFlag(3)
    4'd8,  // 267: CuSkipFlag(2)
    4'd4,  // 266: CuSkipFlag(1)
    4'd5,  // 265: CuSkipFlag(0)
    4'd1,  // 264: AbsLevelGtxFlag(71)
    4'd1,  // 263: AbsLevelGtxFlag(70)
    4'd1,  // 262: AbsLevelGtxFlag(69)
    4'd1,  // 261: AbsLevelGtxFlag(68)
    4'd6,  // 260: AbsLevelGtxFlag(67)
    4'd1,  // 259: AbsLevelGtxFlag(66)
    4'd2,  // 258: AbsLevelGtxFlag(65)
    4'd4,  // 257: AbsLevelGtxFlag(64)
    4'd6,  // 256: AbsLevelGtxFlag(37)
    4'd9,  // 255: AbsLevelGtxFlag(36)
    4'd9,  // 254: AbsLevelGtxFlag(35)
    4'd9,  // 253: AbsLevelGtxFlag(34)
    4'd5,  // 252: AbsLevelGtxFlag(33)
    4'd10,  // 251: AbsLevelGtxFlag(5)
    4'd13,  // 250: AbsLevelGtxFlag(4)
    4'd13,  // 249: AbsLevelGtxFlag(3)
    4'd10,  // 248: AbsLevelGtxFlag(2)
    4'd5,  // 247: AbsLevelGtxFlag(1)
    4'd6,  // 246: ParLevelFlag(32)
    4'd13,  // 245: ParLevelFlag(5)
    4'd13,  // 244: ParLevelFlag(4)
    4'd13,  // 243: ParLevelFlag(3)
    4'd12,  // 242: ParLevelFlag(2)
    4'd9,  // 241: ParLevelFlag(1)
    4'd8,  // 240: SigCoeffFlag(62)
    4'd13,  // 239: SigCoeffFlag(61)
    4'd13,  // 238: SigCoeffFlag(60)
    4'd0,  // 237: SigCoeffFlag(59)
    4'd0,  // 236: SigCoeffFlag(58)
    4'd0,  // 235: SigCoeffFlag(57)
    4'd4,  // 234: SigCoeffFlag(56)
    4'd8,  // 233: SigCoeffFlag(55)
    4'd8,  // 232: SigCoeffFlag(54)
    4'd8,  // 231: SigCoeffFlag(53)
    4'd8,  // 230: SigCoeffFlag(52)
    4'd0,  // 229: SigCoeffFlag(51)
    4'd0,  // 228: SigCoeffFlag(50)
    4'd0,  // 227: SigCoeffFlag(49)
    4'd4,  // 226: SigCoeffFlag(48)
    4'd8,  // 225: SigCoeffFlag(47)
    4'd12,  // 224: SigCoeffFlag(46)
    4'd12,  // 223: SigCoeffFlag(45)
    4'd8,  // 222: SigCoeffFlag(44)
    4'd0,  // 221: SigCoeffFlag(35)
    4'd0,  // 220: SigCoeffFlag(34)
    4'd0,  // 219: SigCoeffFlag(33)
    4'd0,  // 218: SigCoeffFlag(32)
    4'd4,  // 217: SigCoeffFlag(31)
    4'd4,  // 216: SigCoeffFlag(30)
    4'd0,  // 215: SigCoeffFlag(29)
    4'd8,  // 214: SigCoeffFlag(28)
    4'd8,  // 213: SigCoeffFlag(27)
    4'd8,  // 212: SigCoeffFlag(26)
    4'd8,  // 211: SigCoeffFlag(25)
    4'd8,  // 210: SigCoeffFlag(24)
    4'd0,  // 209: SigCoeffFlag(23)
    4'd0,  // 208: SigCoeffFlag(22)
    4'd0,  // 207: SigCoeffFlag(21)
    4'd8,  // 206: SigCoeffFlag(20)
    4'd5,  // 205: SigCoeffFlag(19)
    4'd8,  // 204: SigCoeffFlag(18)
    4'd8,  // 203: SigCoeffFlag(17)
    4'd8,  // 202: SigCoeffFlag(16)
    4'd8,  // 201: SigCoeffFlag(15)
    4'd8,  // 200: SigCoeffFlag(14)
    4'd13,  // 199: SigCoeffFlag(13)
    4'd9,  // 198: SigCoeffFlag(12)
    4'd8,  // 197: SbCodedFlag(6)
    4'd8,  // 196: SbCodedFlag(5)
    4'd5,  // 195: SbCodedFlag(4)
    4'd8,  // 194: SbCodedFlag(3)
    4'd5,  // 193: SbCodedFlag(2)
    4'd5,  // 192: SbCodedFlag(1)
    4'd8,  // 191: SbCodedFlag(0)
    4'd0,  // 190: LastSigCoeffYPrefix(19)
    4'd0,  // 189: LastSigCoeffXPrefix(19)
    4'd0,  // 188: LastSigCoeffYPrefix(18)
    4'd0,  // 187: LastSigCoeffXPrefix(18)
    4'd0,  // 186: LastSigCoeffYPrefix(17)
    4'd0,  // 185: LastSigCoeffXPrefix(17)
    4'd4,  // 184: LastSigCoeffYPrefix(16)
    4'd1,  // 183: LastSigCoeffXPrefix(16)
    4'd0,  // 182: LastSigCoeffYPrefix(14)
    4'd0,  // 181: LastSigCoeffXPrefix(14)
    4'd0,  // 180: LastSigCoeffYPrefix(13)
    4'd0,  // 179: LastSigCoeffXPrefix(13)
    4'd1,  // 178: LastSigCoeffYPrefix(12)
    4'd0,  // 177: LastSigCoeffXPrefix(12)
    4'd4,  // 176: LastSigCoeffYPrefix(11)
    4'd1,  // 175: LastSigCoeffXPrefix(11)
    4'd0,  // 174: LastSigCoeffYPrefix(9)
    4'd0,  // 173: LastSigCoeffXPrefix(9)
    4'd4,  // 172: LastSigCoeffYPrefix(8)
    4'd1,  // 171: LastSigCoeffXPrefix(8)
    4'd5,  // 170: LastSigCoeffYPrefix(7)
    4'd4,  // 169: LastSigCoeffXPrefix(7)
    4'd4,  // 168: LastSigCoeffYPrefix(5)
    4'd4,  // 167: LastSigCoeffXPrefix(5)
    4'd8,  // 166: LastSigCoeffYPrefix(2)
    4'd4,  // 165: LastSigCoeffXPrefix(2)
    4'd5,  // 164: LastSigCoeffYPrefix(1)
    4'd5,  // 163: LastSigCoeffXPrefix(1)
    4'd8,  // 162: LastSigCoeffYPrefix(0)
    4'd8,  // 161: LastSigCoeffXPrefix(0)
    4'd10,  // 160: AbsLevelGtxFlag(52)
    4'd9,  // 159: AbsLevelGtxFlag(51)
    4'd9,  // 158: AbsLevelGtxFlag(50)
    4'd8,  // 157: AbsLevelGtxFlag(49)
    4'd6,  // 156: AbsLevelGtxFlag(48)
    4'd9,  // 155: AbsLevelGtxFlag(47)
    4'd9,  // 154: AbsLevelGtxFlag(46)
    4'd9,  // 153: AbsLevelGtxFlag(44)
    4'd9,  // 152: AbsLevelGtxFlag(42)
    4'd10,  // 151: AbsLevelGtxFlag(41)
    4'd10,  // 150: AbsLevelGtxFlag(40)
    4'd5,  // 149: AbsLevelGtxFlag(38)
    4'd13,  // 148: AbsLevelGtxFlag(20)
    4'd10,  // 147: AbsLevelGtxFlag(19)
    4'd10,  // 146: AbsLevelGtxFlag(18)
    4'd9,  // 145: AbsLevelGtxFlag(17)
    4'd8,  // 144: AbsLevelGtxFlag(16)
    4'd13,  // 143: AbsLevelGtxFlag(15)
    4'd10,  // 142: AbsLevelGtxFlag(14)
    4'd10,  // 141: AbsLevelGtxFlag(12)
    4'd13,  // 140: AbsLevelGtxFlag(10)
    4'd13,  // 139: AbsLevelGtxFlag(9)
    4'd13,  // 138: AbsLevelGtxFlag(8)
    4'd9,  // 137: AbsLevelGtxFlag(6)
    4'd13,  // 136: ParLevelFlag(20)
    4'd13,  // 135: ParLevelFlag(19)
    4'd13,  // 134: ParLevelFlag(18)
    4'd13,  // 133: ParLevelFlag(17)
    4'd10,  // 132: ParLevelFlag(16)
    4'd13,  // 131: ParLevelFlag(15)
    4'd13,  // 130: ParLevelFlag(14)
    4'd13,  // 129: ParLevelFlag(12)
    4'd13,  // 128: ParLevelFlag(10)
    4'd13,  // 127: ParLevelFlag(9)
    4'd13,  // 126: ParLevelFlag(8)
    4'd10,  // 125: ParLevelFlag(6)
    4'd10,  // 124: SigCoeffFlag(11)
    4'd8,  // 123: SigCoeffFlag(10)
    4'd8,  // 122: SigCoeffFlag(8)
    4'd10,  // 121: SigCoeffFlag(7)
    4'd10,  // 120: SigCoeffFlag(3)
    4'd9,  // 119: SigCoeffFlag(2)
    4'd12,  // 118: SigCoeffFlag(0)
    4'd9,  // 117: AbsLevelGtxFlag(63)
    4'd8,  // 116: AbsLevelGtxFlag(62)
    4'd8,  // 115: AbsLevelGtxFlag(61)
    4'd9,  // 114: AbsLevelGtxFlag(60)
    4'd6,  // 113: AbsLevelGtxFlag(59)
    4'd6,  // 112: AbsLevelGtxFlag(58)
    4'd9,  // 111: AbsLevelGtxFlag(57)
    4'd8,  // 110: AbsLevelGtxFlag(56)
    4'd8,  // 109: AbsLevelGtxFlag(55)
    4'd5,  // 108: AbsLevelGtxFlag(54)
    4'd1,  // 107: AbsLevelGtxFlag(53)
    4'd13, // 106: AbsLevelGtxFlag(31)
    4'd9,  // 105: AbsLevelGtxFlag(30)
    4'd9,  // 104: AbsLevelGtxFlag(29)
    4'd9,  // 103: AbsLevelGtxFlag(28)
    4'd5,  // 102: AbsLevelGtxFlag(27)
    4'd10, // 101: AbsLevelGtxFlag(26)
    4'd12, // 100: AbsLevelGtxFlag(25)
    4'd12, //  99: AbsLevelGtxFlag(24)
    4'd9,  //  98: AbsLevelGtxFlag(23)
    4'd8,  //  97: AbsLevelGtxFlag(22)
    4'd8,  //  96: AbsLevelGtxFlag(21)
    4'd13, //  95: ParLevelFlag(31)
    4'd13, //  94: ParLevelFlag(30)
    4'd13, //  93: ParLevelFlag(29)
    4'd13, //  92: ParLevelFlag(28)
    4'd13, //  91: ParLevelFlag(27)
    4'd13, //  90: ParLevelFlag(26)
    4'd13, //  89: ParLevelFlag(25)
    4'd12, //  88: ParLevelFlag(24)
    4'd12, //  87: ParLevelFlag(23)
    4'd12, //  86: ParLevelFlag(22)
    4'd8,  //  85: ParLevelFlag(21)
    4'd9,  //  84: SigCoeffFlag(43)
    4'd8,  //  83: SigCoeffFlag(42)
    4'd5,  //  82: SigCoeffFlag(41)
    4'd4,  //  81: SigCoeffFlag(40)
    4'd13, //  80: SigCoeffFlag(39)
    4'd9,  //  79: SigCoeffFlag(38)
    4'd12, //  78: SigCoeffFlag(37)
    4'd12, //  77: SigCoeffFlag(36)
    4'd5,  //  76: LastSigCoeffYPrefix(22)
    4'd4,  //  75: LastSigCoeffXPrefix(22)
    4'd5,  //  74: LastSigCoeffYPrefix(21)
    4'd4,  //  73: LastSigCoeffXPrefix(21)
    4'd6,  //  72: LastSigCoeffYPrefix(20)
    4'd5,  //  71: LastSigCoeffXPrefix(20)
    4'd1,  //  70: QtCbfCr(1)
    4'd9,  // 69: AbsLevelGtxFlag(45)
    4'd13, // 68: ParLevelFlag(13)
    4'd10, // 67: AbsLevelGtxFlag(13)
    4'd9,  // 66: AbsLevelGtxFlag(39)
    4'd13, // 65: ParLevelFlag(7)
    4'd10, // 64: AbsLevelGtxFlag(7)
    4'd9,  // 63: SigCoeffFlag(6)
    4'd9,  // 62: AbsLevelGtxFlag(43)
    4'd13, // 61: ParLevelFlag(11)
    4'd9,  // 60: AbsLevelGtxFlag(11)
    4'd8,  // 59: SigCoeffFlag(9)
    4'd9,  // 58: SigCoeffFlag(5)
    4'd9,  // 57: SigCoeffFlag(4)
    4'd9,  // 56: SigCoeffFlag(1)
    4'd5,  // 55: LastSigCoeffYPrefix(4)
    4'd4,  // 54: LastSigCoeffXPrefix(4)
    4'd5,  // 53: IntraLumaPlanarFlag(1)
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

  typedef logic [15:0] vvc_prob_state_t;

  vvc_prob_state_t ctx_state0_q [0:VVC_CTX_COUNT - 1];
  vvc_prob_state_t ctx_state1_q [0:VVC_CTX_COUNT - 1];
  vvc_prob_state_t ctx_init_state0 [0:VVC_CTX_COUNT - 1];
  vvc_prob_state_t ctx_init_state1 [0:VVC_CTX_COUNT - 1];
  logic [7:0] ctx_rate [0:VVC_CTX_COUNT - 1];
  // Synthesis note: context reset clears only this valid bitmap. Until a
  // context is updated after reset, query/update paths use the init state,
  // preserving H.266 context initialization without building a one-cycle reset
  // mux over every probability-state bit in the expanded residual bank.
  logic [VVC_CTX_COUNT - 1:0] ctx_valid_q;
  logic [VVC_CABAC_CTX_ID_BITS - 1:0] update_bank_id;
  logic [VVC_CABAC_CTX_ID_BITS - 1:0] query_bank_id_next;
  logic [VVC_CABAC_CTX_ID_BITS - 1:0] update_bank_id_next;
  logic [16:0] query_state_sum;
  logic [7:0] query_state;
  logic [15:0] query_q;
  logic [15:0] query_lps_full;
  logic [15:0] query_state0;
  logic [15:0] query_state1;
  logic [15:0] update_state0_base;
  logic [15:0] update_state1_base;
  logic [15:0] update_state0_next;
  logic [15:0] update_state1_next;
  logic [7:0] update_rate;
  logic [3:0] update_rate0;
  logic [3:0] update_rate1;
  (* keep = "true" *) logic unused_query_range_bits;

  genvar init_i;
  generate
    for (init_i = 0; init_i < VVC_CTX_COUNT; init_i = init_i + 1) begin : gen_ctx_init
      localparam int INIT_VALUE = INIT_VALUE_LUT[init_i * 8 +: 8];
      localparam int LOG2_WINDOW = LOG2_WINDOW_LUT[init_i * 4 +: 4];
      localparam int signed INIT_SLOPE = (INIT_VALUE >> 3) - 4;
      localparam int signed INIT_OFFSET = ((INIT_VALUE & 8'd7) * 18) + 1;
      localparam int signed INIT_STATE_RAW_DEFAULT =
        ((INIT_SLOPE * (VVC_CTX_QP - 16)) >>> 1) + INIT_OFFSET;
      localparam int signed INIT_STATE_RAW_QP4 =
        ((INIT_SLOPE * (4 - 16)) >>> 1) + INIT_OFFSET;
      localparam int INIT_STATE_DEFAULT =
        (INIT_STATE_RAW_DEFAULT < 1) ? 1 :
        ((INIT_STATE_RAW_DEFAULT > 127) ? 127 : INIT_STATE_RAW_DEFAULT);
      localparam int INIT_STATE_QP4 =
        (INIT_STATE_RAW_QP4 < 1) ? 1 :
        ((INIT_STATE_RAW_QP4 > 127) ? 127 : INIT_STATE_RAW_QP4);
      localparam int INIT_RATE0 = 2 + ((LOG2_WINDOW >> 2) & 3);
      localparam int INIT_RATE1 = 3 + INIT_RATE0 + (LOG2_WINDOW & 3);
      localparam logic [7:0] INIT_RATE_BYTE =
        (((INIT_RATE0 & 8'h0f) << 4) | (INIT_RATE1 & 8'h0f));
      localparam logic [15:0] INIT_STATE0_DEFAULT = (INIT_STATE_DEFAULT << 8) & 16'h7fe0;
      localparam logic [15:0] INIT_STATE1_DEFAULT = (INIT_STATE_DEFAULT << 8) & 16'h7ffe;
      localparam logic [15:0] INIT_STATE0_QP4 = (INIT_STATE_QP4 << 8) & 16'h7fe0;
      localparam logic [15:0] INIT_STATE1_QP4 = (INIT_STATE_QP4 << 8) & 16'h7ffe;
      assign ctx_init_state0[init_i] = lossless_slice_qp ? INIT_STATE0_QP4 : INIT_STATE0_DEFAULT;
      assign ctx_init_state1[init_i] = lossless_slice_qp ? INIT_STATE1_QP4 : INIT_STATE1_DEFAULT;
      assign ctx_rate[init_i] = INIT_RATE_BYTE;
    end
  endgenerate

  assign query_bank_id = query_bank_id_next;
  assign update_bank_id = update_bank_id_next;
  assign unused_query_range_bits = query_range[15] || (|query_range[4:0]);
  assign query_state0 = ctx_valid_q[query_bank_id_next] ?
    ctx_state0_q[query_bank_id_next] : ctx_init_state0[query_bank_id_next];
  assign query_state1 = ctx_valid_q[query_bank_id_next] ?
    ctx_state1_q[query_bank_id_next] : ctx_init_state1[query_bank_id_next];
  assign update_state0_base = ctx_valid_q[update_bank_id_next] ?
    ctx_state0_q[update_bank_id_next] : ctx_init_state0[update_bank_id_next];
  assign update_state1_base = ctx_valid_q[update_bank_id_next] ?
    ctx_state1_q[update_bank_id_next] : ctx_init_state1[update_bank_id_next];
  assign update_rate = ctx_rate[update_bank_id_next];
  assign update_rate0 = update_rate[7:4];
  assign update_rate1 = update_rate[3:0];

  always @* begin
    query_bank_id_next = query_ctx_id;
    if (query_ctx_id >= VVC_CTX_COUNT_LIMIT) begin
      query_bank_id_next = '0;
    end

    update_bank_id_next = update_ctx_id;
    if (update_ctx_id >= VVC_CTX_COUNT_LIMIT) begin
      update_bank_id_next = '0;
    end
  end

  always @* begin
    query_state_sum = {1'b0, query_state0} + {1'b0, query_state1};
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
    update_state0_next =
      update_state0_base - ((update_state0_base >> update_rate0) & 16'h7fe0);
    update_state1_next =
      update_state1_base - ((update_state1_base >> update_rate1) & 16'h7ffe);
    if (update_bin) begin
      update_state0_next =
        update_state0_next + ((16'h7fff >> update_rate0) & 16'h7fe0);
      update_state1_next =
        update_state1_next + ((16'h7fff >> update_rate1) & 16'h7ffe);
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ctx_valid_q <= '0;
    end else if (reset_contexts) begin
      ctx_valid_q <= '0;
    end else if (update_valid) begin
      ctx_state0_q[update_bank_id] <= update_state0_next;
      ctx_state1_q[update_bank_id] <= update_state1_next;
      ctx_valid_q[update_bank_id] <= 1'b1;
    end
  end
endmodule
