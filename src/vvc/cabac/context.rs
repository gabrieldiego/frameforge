use super::writer::{VvcCabacDumpContextEvent, VvcCabacDumpSymbol, VvcCabacEncoder, VvcCtxEvent};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::vvc) struct VvcLastSigCoeffPrefixCtxInput {
    pub(in crate::vvc) is_luma: bool,
    pub(in crate::vvc) log2_tb_size: u8,
    pub(in crate::vvc) bin_idx: u8,
}

impl VvcLastSigCoeffPrefixCtxInput {
    pub(in crate::vvc) fn ctx_inc(self) -> u8 {
        // VVC 9.3.4.2.4 derives ctxInc for last_sig_coeff_x_prefix and
        // last_sig_coeff_y_prefix from binIdx, component, and transform block
        // size. See docs/vvc/cabac-subset.md.
        if self.is_luma {
            const OFFSET_Y: [u8; 6] = [0, 0, 3, 6, 10, 15];
            let offset = OFFSET_Y[(self.log2_tb_size - 1) as usize];
            let shift = (self.log2_tb_size + 1) >> 2;
            (self.bin_idx >> shift) + offset
        } else {
            // H.266 9.3.4.2.4 derives the chroma ctxShift from the transform
            // block size, i.e. Clip3(0, 2, (1 << log2TbSize) >> 3). VTM
            // CoeffCodingContext mirrors this as Clip3(0, 2, width >> 3).
            let shift = ((1u16 << self.log2_tb_size) >> 3).min(2) as u8;
            (self.bin_idx >> shift) + 20
        }
    }
}

fn missing_rtl_context_ordinal(ctx: u8, max_ctx: u8, explicitly_mapped: &[u8]) -> Option<u16> {
    if ctx > max_ctx || explicitly_mapped.contains(&ctx) {
        return None;
    }
    let prior_explicit = explicitly_mapped
        .iter()
        .filter(|&&mapped_ctx| mapped_ctx < ctx)
        .count();
    Some(u16::from(ctx) - prior_explicit as u16)
}

#[derive(Debug, Clone, Copy)]
pub(in crate::vvc) enum VvcCabacContext {
    SplitFlag(u8),
    SplitQtFlag(u8),
    MttSplitCuVerticalFlag(u8),
    MttSplitCuBinaryFlag(u8),
    MultiRefLineIdx(u8),
    IntraLumaMpmFlag,
    IntraLumaPlanarFlag(u8),
    CclmModeFlag,
    IntraChromaPredMode(u8),
    QtCbfY(u8),
    QtCbfCb(u8),
    QtCbfCr(u8),
    TransformSkipFlag(u8),
    BdpcmMode(u8),
    MtsIdx(u8),
    CuSkipFlag(u8),
    PredModeIbcFlag(u8),
    GeneralMergeFlag(u8),
    AbsMvdGreater0Flag(u8),
    AbsMvdGreater1Flag(u8),
    CuCodedFlag(u8),
    LastSigCoeffXPrefix(u8),
    LastSigCoeffYPrefix(u8),
    SbCodedFlag(u8),
    SigCoeffFlag(u8),
    ParLevelFlag(u8),
    AbsLevelGtxFlag(u8),
    CoeffSignFlag(u8),
    PredModePltFlag,
    PaletteTransposeFlag,
    CopyAbovePaletteIndicesFlag,
    RunCopyFlag(u8),
}

impl VvcCabacContext {
    pub(in crate::vvc) fn rtl_context_id(self) -> Option<u16> {
        match self {
            VvcCabacContext::SplitFlag(0) => Some(0),
            VvcCabacContext::SplitFlag(6) => Some(1),
            VvcCabacContext::SplitQtFlag(3) => Some(2),
            VvcCabacContext::SplitFlag(3) => Some(3),
            VvcCabacContext::IntraLumaMpmFlag => Some(4),
            VvcCabacContext::IntraLumaPlanarFlag(1) => Some(53),
            VvcCabacContext::QtCbfY(0) => Some(5),
            VvcCabacContext::LastSigCoeffXPrefix(3) => Some(6),
            VvcCabacContext::LastSigCoeffYPrefix(3) => Some(7),
            VvcCabacContext::LastSigCoeffXPrefix(4) => Some(54),
            VvcCabacContext::LastSigCoeffYPrefix(4) => Some(55),
            VvcCabacContext::LastSigCoeffXPrefix(6) => Some(8),
            VvcCabacContext::LastSigCoeffYPrefix(6) => Some(9),
            VvcCabacContext::AbsLevelGtxFlag(0) => Some(10),
            VvcCabacContext::ParLevelFlag(0) => Some(11),
            VvcCabacContext::AbsLevelGtxFlag(32) => Some(12),
            VvcCabacContext::CclmModeFlag => Some(13),
            VvcCabacContext::IntraChromaPredMode(0) => Some(14),
            VvcCabacContext::QtCbfCb(0) => Some(15),
            VvcCabacContext::QtCbfCr(0) => Some(16),
            VvcCabacContext::QtCbfCr(1) => Some(70),
            VvcCabacContext::LastSigCoeffXPrefix(10) => Some(17),
            VvcCabacContext::LastSigCoeffYPrefix(10) => Some(18),
            VvcCabacContext::SplitFlag(7) => Some(19),
            VvcCabacContext::SplitQtFlag(0) => Some(20),
            VvcCabacContext::MultiRefLineIdx(0) => Some(21),
            VvcCabacContext::LastSigCoeffXPrefix(15) => Some(22),
            VvcCabacContext::LastSigCoeffYPrefix(15) => Some(23),
            VvcCabacContext::MttSplitCuVerticalFlag(3) => Some(24),
            VvcCabacContext::MttSplitCuBinaryFlag(1) => Some(25),
            VvcCabacContext::MttSplitCuBinaryFlag(3) => Some(26),
            VvcCabacContext::MttSplitCuBinaryFlag(0) => Some(31),
            VvcCabacContext::MttSplitCuBinaryFlag(2) => Some(32),
            VvcCabacContext::SplitFlag(1) => Some(27),
            VvcCabacContext::SplitFlag(2) => Some(28),
            VvcCabacContext::MttSplitCuVerticalFlag(0) => Some(29),
            VvcCabacContext::MttSplitCuVerticalFlag(4) => Some(30),
            VvcCabacContext::MttSplitCuVerticalFlag(1) => Some(40),
            VvcCabacContext::MttSplitCuVerticalFlag(2) => Some(41),
            VvcCabacContext::SplitFlag(4) => Some(33),
            VvcCabacContext::SplitQtFlag(1) => Some(34),
            VvcCabacContext::SplitQtFlag(2) => Some(35),
            VvcCabacContext::SplitQtFlag(4) => Some(36),
            VvcCabacContext::SplitQtFlag(5) => Some(37),
            VvcCabacContext::SplitFlag(5) => Some(38),
            VvcCabacContext::SplitFlag(8) => Some(39),
            VvcCabacContext::PredModePltFlag => Some(42),
            VvcCabacContext::PaletteTransposeFlag => Some(43),
            VvcCabacContext::CopyAbovePaletteIndicesFlag => Some(44),
            VvcCabacContext::RunCopyFlag(0) => Some(45),
            VvcCabacContext::RunCopyFlag(1) => Some(46),
            VvcCabacContext::RunCopyFlag(2) => Some(47),
            VvcCabacContext::RunCopyFlag(3) => Some(48),
            VvcCabacContext::RunCopyFlag(4) => Some(49),
            VvcCabacContext::RunCopyFlag(5) => Some(50),
            VvcCabacContext::RunCopyFlag(6) => Some(51),
            VvcCabacContext::RunCopyFlag(7) => Some(52),
            VvcCabacContext::SigCoeffFlag(1) => Some(56),
            VvcCabacContext::SigCoeffFlag(4) => Some(57),
            VvcCabacContext::SigCoeffFlag(5) => Some(58),
            VvcCabacContext::SigCoeffFlag(9) => Some(59),
            VvcCabacContext::AbsLevelGtxFlag(11) => Some(60),
            VvcCabacContext::ParLevelFlag(11) => Some(61),
            VvcCabacContext::AbsLevelGtxFlag(43) => Some(62),
            VvcCabacContext::SigCoeffFlag(6) => Some(63),
            VvcCabacContext::AbsLevelGtxFlag(7) => Some(64),
            VvcCabacContext::ParLevelFlag(7) => Some(65),
            VvcCabacContext::AbsLevelGtxFlag(39) => Some(66),
            VvcCabacContext::AbsLevelGtxFlag(13) => Some(67),
            VvcCabacContext::ParLevelFlag(13) => Some(68),
            VvcCabacContext::AbsLevelGtxFlag(45) => Some(69),
            VvcCabacContext::LastSigCoeffXPrefix(ctx @ 20..=22) => {
                Some(71 + (u16::from(ctx - 20) * 2))
            }
            VvcCabacContext::LastSigCoeffYPrefix(ctx @ 20..=22) => {
                Some(72 + (u16::from(ctx - 20) * 2))
            }
            VvcCabacContext::SigCoeffFlag(ctx @ 36..=43) => Some(77 + u16::from(ctx - 36)),
            VvcCabacContext::ParLevelFlag(ctx @ 21..=31) => Some(85 + u16::from(ctx - 21)),
            VvcCabacContext::AbsLevelGtxFlag(ctx @ 21..=31) => Some(96 + u16::from(ctx - 21)),
            VvcCabacContext::AbsLevelGtxFlag(ctx @ 53..=63) => Some(107 + u16::from(ctx - 53)),
            // H.266 Table 132 plus clauses 9.3.4.2.8 and 9.3.4.2.9 require
            // these luma residual contexts for the current regular,
            // non-transform-skip, first-4x4 coefficient group at QState 0.
            VvcCabacContext::SigCoeffFlag(0) => Some(118),
            VvcCabacContext::SigCoeffFlag(2) => Some(119),
            VvcCabacContext::SigCoeffFlag(3) => Some(120),
            VvcCabacContext::SigCoeffFlag(7) => Some(121),
            VvcCabacContext::SigCoeffFlag(8) => Some(122),
            VvcCabacContext::SigCoeffFlag(10) => Some(123),
            VvcCabacContext::SigCoeffFlag(11) => Some(124),
            VvcCabacContext::ParLevelFlag(6) => Some(125),
            VvcCabacContext::ParLevelFlag(8) => Some(126),
            VvcCabacContext::ParLevelFlag(9) => Some(127),
            VvcCabacContext::ParLevelFlag(10) => Some(128),
            VvcCabacContext::ParLevelFlag(12) => Some(129),
            VvcCabacContext::ParLevelFlag(14) => Some(130),
            VvcCabacContext::ParLevelFlag(15) => Some(131),
            VvcCabacContext::ParLevelFlag(16) => Some(132),
            VvcCabacContext::ParLevelFlag(17) => Some(133),
            VvcCabacContext::ParLevelFlag(18) => Some(134),
            VvcCabacContext::ParLevelFlag(19) => Some(135),
            VvcCabacContext::ParLevelFlag(20) => Some(136),
            VvcCabacContext::AbsLevelGtxFlag(6) => Some(137),
            VvcCabacContext::AbsLevelGtxFlag(8) => Some(138),
            VvcCabacContext::AbsLevelGtxFlag(9) => Some(139),
            VvcCabacContext::AbsLevelGtxFlag(10) => Some(140),
            VvcCabacContext::AbsLevelGtxFlag(12) => Some(141),
            VvcCabacContext::AbsLevelGtxFlag(14) => Some(142),
            VvcCabacContext::AbsLevelGtxFlag(15) => Some(143),
            VvcCabacContext::AbsLevelGtxFlag(16) => Some(144),
            VvcCabacContext::AbsLevelGtxFlag(17) => Some(145),
            VvcCabacContext::AbsLevelGtxFlag(18) => Some(146),
            VvcCabacContext::AbsLevelGtxFlag(19) => Some(147),
            VvcCabacContext::AbsLevelGtxFlag(20) => Some(148),
            VvcCabacContext::AbsLevelGtxFlag(38) => Some(149),
            VvcCabacContext::AbsLevelGtxFlag(40) => Some(150),
            VvcCabacContext::AbsLevelGtxFlag(41) => Some(151),
            VvcCabacContext::AbsLevelGtxFlag(42) => Some(152),
            VvcCabacContext::AbsLevelGtxFlag(44) => Some(153),
            VvcCabacContext::AbsLevelGtxFlag(46) => Some(154),
            VvcCabacContext::AbsLevelGtxFlag(47) => Some(155),
            VvcCabacContext::AbsLevelGtxFlag(48) => Some(156),
            VvcCabacContext::AbsLevelGtxFlag(49) => Some(157),
            VvcCabacContext::AbsLevelGtxFlag(50) => Some(158),
            VvcCabacContext::AbsLevelGtxFlag(51) => Some(159),
            VvcCabacContext::AbsLevelGtxFlag(52) => Some(160),
            // H.266 Table 132 assigns residual context ranges for the complete
            // residual_coding() syntax. Keep the compact RTL bank populated for
            // all residual contexts, even before every producer can emit them.
            VvcCabacContext::LastSigCoeffXPrefix(ctx) => {
                const EXPLICIT: &[u8] = &[3, 4, 6, 10, 15, 20, 21, 22];
                missing_rtl_context_ordinal(ctx, 22, EXPLICIT).map(|ordinal| 161 + (ordinal * 2))
            }
            VvcCabacContext::LastSigCoeffYPrefix(ctx) => {
                const EXPLICIT: &[u8] = &[3, 4, 6, 10, 15, 20, 21, 22];
                missing_rtl_context_ordinal(ctx, 22, EXPLICIT).map(|ordinal| 162 + (ordinal * 2))
            }
            VvcCabacContext::SbCodedFlag(ctx @ 0..=6) => Some(191 + u16::from(ctx)),
            VvcCabacContext::SigCoeffFlag(ctx) => {
                const EXPLICIT: &[u8] = &[
                    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 36, 37, 38, 39, 40, 41, 42, 43,
                ];
                missing_rtl_context_ordinal(ctx, 62, EXPLICIT).map(|ordinal| 198 + ordinal)
            }
            VvcCabacContext::ParLevelFlag(ctx) => {
                const EXPLICIT: &[u8] = &[
                    0, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25,
                    26, 27, 28, 29, 30, 31,
                ];
                missing_rtl_context_ordinal(ctx, 32, EXPLICIT).map(|ordinal| 241 + ordinal)
            }
            VvcCabacContext::AbsLevelGtxFlag(ctx) => {
                const EXPLICIT: &[u8] = &[
                    0, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25,
                    26, 27, 28, 29, 30, 31, 32, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50,
                    51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63,
                ];
                missing_rtl_context_ordinal(ctx, 71, EXPLICIT).map(|ordinal| 247 + ordinal)
            }
            VvcCabacContext::CuSkipFlag(ctx @ 0..=8) => Some(265 + u16::from(ctx)),
            VvcCabacContext::PredModeIbcFlag(ctx @ 0..=8) => Some(274 + u16::from(ctx)),
            VvcCabacContext::GeneralMergeFlag(ctx @ 0..=2) => Some(283 + u16::from(ctx)),
            VvcCabacContext::AbsMvdGreater0Flag(ctx @ 0..=2) => Some(286 + u16::from(ctx)),
            VvcCabacContext::AbsMvdGreater1Flag(ctx @ 0..=2) => Some(289 + u16::from(ctx)),
            VvcCabacContext::CuCodedFlag(ctx @ 0..=2) => Some(292 + u16::from(ctx)),
            VvcCabacContext::TransformSkipFlag(ctx @ 0..=1) => Some(295 + u16::from(ctx)),
            VvcCabacContext::BdpcmMode(ctx @ 0..=3) => Some(297 + u16::from(ctx)),
            VvcCabacContext::QtCbfY(1) => Some(301),
            VvcCabacContext::QtCbfCb(1) => Some(302),
            VvcCabacContext::QtCbfCr(2) => Some(303),
            _ => None,
        }
    }

    pub(in crate::vvc) fn init_value(self) -> u8 {
        match self {
            // ITU-T H.266 CABAC context initialization tables, I-slice
            // initializationType. See docs/vvc/cabac-subset.md.
            VvcCabacContext::SplitFlag(ctx) => {
                const I_SLICE_INIT: [u8; 9] = [19, 28, 38, 27, 29, 38, 20, 30, 31];
                I_SLICE_INIT[ctx as usize]
            }
            VvcCabacContext::SplitQtFlag(ctx) => {
                const I_SLICE_INIT: [u8; 6] = [27, 6, 15, 25, 19, 37];
                I_SLICE_INIT[ctx as usize]
            }
            VvcCabacContext::MttSplitCuVerticalFlag(ctx) => {
                const I_SLICE_INIT: [u8; 15] =
                    [43, 42, 29, 27, 44, 43, 35, 37, 34, 52, 43, 42, 37, 42, 44];
                I_SLICE_INIT[ctx as usize]
            }
            VvcCabacContext::MttSplitCuBinaryFlag(ctx) => {
                // ITU-T H.266 (V4) Table 62, initType 0 / I-slice.
                const I_SLICE_INIT: [u8; 12] = [36, 45, 36, 45, 43, 37, 21, 22, 28, 29, 28, 29];
                I_SLICE_INIT[ctx as usize]
            }
            VvcCabacContext::MultiRefLineIdx(ctx) => {
                const I_SLICE_INIT: [u8; 2] = [25, 60];
                I_SLICE_INIT[ctx as usize]
            }
            VvcCabacContext::IntraLumaMpmFlag => 45,
            VvcCabacContext::IntraLumaPlanarFlag(ctx) => {
                const I_SLICE_INIT: [u8; 2] = [13, 28];
                I_SLICE_INIT[ctx as usize]
            }
            VvcCabacContext::CclmModeFlag => 59,
            VvcCabacContext::IntraChromaPredMode(ctx) => {
                const I_SLICE_INIT: [u8; 2] = [34, 34];
                I_SLICE_INIT[ctx as usize]
            }
            VvcCabacContext::QtCbfY(ctx) => {
                const I_SLICE_INIT: [u8; 4] = [15, 12, 5, 7];
                I_SLICE_INIT[ctx as usize]
            }
            VvcCabacContext::QtCbfCb(ctx) => {
                const I_SLICE_INIT: [u8; 2] = [12, 21];
                I_SLICE_INIT[ctx as usize]
            }
            VvcCabacContext::QtCbfCr(ctx) => {
                const I_SLICE_INIT: [u8; 3] = [33, 28, 36];
                I_SLICE_INIT[ctx as usize]
            }
            VvcCabacContext::TransformSkipFlag(ctx) => {
                const I_SLICE_INIT: [u8; 2] = [25, 9];
                I_SLICE_INIT[ctx as usize]
            }
            VvcCabacContext::BdpcmMode(ctx) => {
                // H.266 Table 78, initType 0 / I-slice.
                const I_SLICE_INIT: [u8; 4] = [19, 35, 1, 27];
                I_SLICE_INIT[ctx as usize]
            }
            VvcCabacContext::MtsIdx(ctx) => {
                const I_SLICE_INIT: [u8; 4] = [29, 0, 28, 0];
                I_SLICE_INIT[ctx as usize]
            }
            VvcCabacContext::CuSkipFlag(ctx) => {
                // H.266 Table 64, initType 0 / I-slice.
                const I_SLICE_INIT: [u8; 9] = [0, 26, 28, 57, 59, 45, 57, 60, 46];
                I_SLICE_INIT[ctx as usize]
            }
            VvcCabacContext::PredModeIbcFlag(ctx) => {
                // H.266 Table 65, initType 0 / I-slice.
                const I_SLICE_INIT: [u8; 9] = [17, 42, 36, 0, 57, 44, 0, 43, 45];
                I_SLICE_INIT[ctx as usize]
            }
            VvcCabacContext::GeneralMergeFlag(ctx) => {
                // H.266 Table 82, initType 0 / I-slice.
                const I_SLICE_INIT: [u8; 3] = [26, 21, 6];
                I_SLICE_INIT[ctx as usize]
            }
            VvcCabacContext::CuCodedFlag(ctx) => {
                // H.266 Table 92, initType 0 / I-slice.
                const I_SLICE_INIT: [u8; 3] = [6, 5, 12];
                I_SLICE_INIT[ctx as usize]
            }
            VvcCabacContext::AbsMvdGreater0Flag(ctx) => {
                // H.266 Table 110.
                const I_SLICE_INIT: [u8; 3] = [14, 44, 51];
                I_SLICE_INIT[ctx as usize]
            }
            VvcCabacContext::AbsMvdGreater1Flag(ctx) => {
                // H.266 Table 111.
                const I_SLICE_INIT: [u8; 3] = [45, 43, 36];
                I_SLICE_INIT[ctx as usize]
            }
            VvcCabacContext::LastSigCoeffXPrefix(ctx) => {
                const I_SLICE_INIT: [u8; 23] = [
                    13, 5, 4, 21, 14, 4, 6, 14, 21, 11, 14, 7, 14, 5, 11, 21, 30, 22, 13, 42, 12,
                    4, 3,
                ];
                I_SLICE_INIT[ctx as usize]
            }
            VvcCabacContext::LastSigCoeffYPrefix(ctx) => {
                const I_SLICE_INIT: [u8; 23] = [
                    13, 5, 4, 6, 13, 11, 14, 6, 5, 3, 14, 22, 6, 4, 3, 6, 22, 29, 20, 34, 12, 4, 3,
                ];
                I_SLICE_INIT[ctx as usize]
            }
            VvcCabacContext::SbCodedFlag(ctx) => {
                const I_SLICE_INIT: [u8; 7] = [18, 31, 25, 15, 18, 20, 38];
                I_SLICE_INIT[ctx as usize]
            }
            VvcCabacContext::SigCoeffFlag(ctx) => {
                const I_SLICE_INIT: [u8; 63] = [
                    25, 19, 28, 14, 25, 20, 29, 30, 19, 37, 30, 38, 11, 38, 46, 54, 27, 39, 39, 39,
                    44, 39, 39, 39, 18, 39, 39, 39, 27, 39, 39, 39, 0, 39, 39, 39, 25, 27, 28, 37,
                    34, 53, 53, 46, 19, 46, 38, 39, 52, 39, 39, 39, 11, 39, 39, 39, 19, 39, 39, 39,
                    25, 28, 38,
                ];
                I_SLICE_INIT[ctx as usize]
            }
            VvcCabacContext::ParLevelFlag(ctx) => {
                const I_SLICE_INIT: [u8; 33] = [
                    33, 25, 18, 26, 34, 27, 25, 26, 19, 42, 35, 33, 19, 27, 35, 35, 34, 42, 20, 43,
                    20, 33, 25, 26, 42, 19, 27, 26, 50, 35, 20, 43, 11,
                ];
                I_SLICE_INIT[ctx as usize]
            }
            VvcCabacContext::AbsLevelGtxFlag(ctx) => {
                const I_SLICE_INIT: [u8; 72] = [
                    25, 25, 11, 27, 20, 21, 33, 12, 28, 21, 22, 34, 28, 29, 29, 30, 36, 29, 45, 30,
                    23, 40, 33, 27, 28, 21, 37, 36, 37, 45, 38, 46, 25, 1, 40, 25, 33, 11, 17, 25,
                    25, 18, 4, 17, 33, 26, 19, 13, 33, 19, 20, 28, 22, 40, 9, 25, 18, 26, 35, 25,
                    26, 35, 28, 37, 11, 5, 5, 14, 10, 3, 3, 3,
                ];
                I_SLICE_INIT[ctx as usize]
            }
            VvcCabacContext::CoeffSignFlag(ctx) => {
                const I_SLICE_INIT: [u8; 6] = [12, 17, 46, 28, 25, 46];
                I_SLICE_INIT[ctx as usize]
            }
            VvcCabacContext::PredModePltFlag => 25,
            VvcCabacContext::PaletteTransposeFlag => 42,
            VvcCabacContext::CopyAbovePaletteIndicesFlag => 42,
            VvcCabacContext::RunCopyFlag(ctx) => {
                const I_SLICE_INIT: [u8; 8] = [50, 37, 45, 30, 46, 45, 38, 46];
                I_SLICE_INIT[ctx as usize]
            }
        }
    }

    pub(in crate::vvc) fn log2_window_size(self) -> u8 {
        match self {
            VvcCabacContext::SplitFlag(ctx) => {
                const LOG2_WINDOW: [u8; 9] = [12, 13, 8, 8, 13, 12, 5, 9, 9];
                LOG2_WINDOW[ctx as usize]
            }
            VvcCabacContext::SplitQtFlag(ctx) => {
                const LOG2_WINDOW: [u8; 6] = [0, 8, 8, 12, 12, 8];
                LOG2_WINDOW[ctx as usize]
            }
            VvcCabacContext::MttSplitCuVerticalFlag(ctx) => {
                const LOG2_WINDOW: [u8; 15] = [9, 8, 9, 8, 5, 9, 8, 9, 8, 5, 9, 8, 9, 8, 5];
                LOG2_WINDOW[ctx as usize]
            }
            VvcCabacContext::MttSplitCuBinaryFlag(ctx) => {
                const LOG2_WINDOW: [u8; 12] = [12, 13, 12, 13, 12, 13, 12, 13, 12, 13, 12, 13];
                LOG2_WINDOW[ctx as usize]
            }
            VvcCabacContext::MultiRefLineIdx(ctx) => {
                const LOG2_WINDOW: [u8; 2] = [5, 8];
                LOG2_WINDOW[ctx as usize]
            }
            VvcCabacContext::IntraLumaMpmFlag => 6,
            VvcCabacContext::IntraLumaPlanarFlag(ctx) => {
                const LOG2_WINDOW: [u8; 2] = [1, 5];
                LOG2_WINDOW[ctx as usize]
            }
            VvcCabacContext::CclmModeFlag => 4,
            VvcCabacContext::IntraChromaPredMode(ctx) => {
                const LOG2_WINDOW: [u8; 2] = [5, 5];
                LOG2_WINDOW[ctx as usize]
            }
            VvcCabacContext::QtCbfY(ctx) => {
                const LOG2_WINDOW: [u8; 4] = [5, 1, 8, 9];
                LOG2_WINDOW[ctx as usize]
            }
            VvcCabacContext::QtCbfCb(ctx) => {
                const LOG2_WINDOW: [u8; 2] = [5, 0];
                LOG2_WINDOW[ctx as usize]
            }
            VvcCabacContext::QtCbfCr(ctx) => {
                const LOG2_WINDOW: [u8; 3] = [2, 1, 0];
                LOG2_WINDOW[ctx as usize]
            }
            VvcCabacContext::TransformSkipFlag(ctx) => {
                const LOG2_WINDOW: [u8; 2] = [1, 1];
                LOG2_WINDOW[ctx as usize]
            }
            VvcCabacContext::BdpcmMode(ctx) => {
                // H.266 Table 78, initType 0 / I-slice.
                const LOG2_WINDOW: [u8; 4] = [1, 4, 1, 0];
                LOG2_WINDOW[ctx as usize]
            }
            VvcCabacContext::MtsIdx(ctx) => {
                const LOG2_WINDOW: [u8; 4] = [8, 0, 9, 0];
                LOG2_WINDOW[ctx as usize]
            }
            VvcCabacContext::CuSkipFlag(ctx) => {
                const LOG2_WINDOW: [u8; 9] = [5, 4, 8, 5, 4, 8, 5, 4, 8];
                LOG2_WINDOW[ctx as usize]
            }
            VvcCabacContext::PredModeIbcFlag(ctx) => {
                const LOG2_WINDOW: [u8; 9] = [1, 5, 8, 1, 5, 8, 1, 5, 8];
                LOG2_WINDOW[ctx as usize]
            }
            VvcCabacContext::GeneralMergeFlag(ctx) => {
                const LOG2_WINDOW: [u8; 3] = [4, 4, 4];
                LOG2_WINDOW[ctx as usize]
            }
            VvcCabacContext::CuCodedFlag(ctx) => {
                const LOG2_WINDOW: [u8; 3] = [4, 4, 4];
                LOG2_WINDOW[ctx as usize]
            }
            VvcCabacContext::AbsMvdGreater0Flag(ctx) => {
                const LOG2_WINDOW: [u8; 3] = [9, 9, 9];
                LOG2_WINDOW[ctx as usize]
            }
            VvcCabacContext::AbsMvdGreater1Flag(ctx) => {
                const LOG2_WINDOW: [u8; 3] = [5, 5, 5];
                LOG2_WINDOW[ctx as usize]
            }
            VvcCabacContext::LastSigCoeffXPrefix(ctx) => {
                const LOG2_WINDOW: [u8; 23] = [
                    8, 5, 4, 5, 4, 4, 5, 4, 1, 0, 4, 1, 0, 0, 0, 0, 1, 0, 0, 0, 5, 4, 4,
                ];
                LOG2_WINDOW[ctx as usize]
            }
            VvcCabacContext::LastSigCoeffYPrefix(ctx) => {
                const LOG2_WINDOW: [u8; 23] = [
                    8, 5, 8, 5, 5, 4, 5, 5, 4, 0, 5, 4, 1, 0, 0, 1, 4, 0, 0, 0, 6, 5, 5,
                ];
                LOG2_WINDOW[ctx as usize]
            }
            VvcCabacContext::SbCodedFlag(ctx) => {
                const LOG2_WINDOW: [u8; 7] = [8, 5, 5, 8, 5, 8, 8];
                LOG2_WINDOW[ctx as usize]
            }
            VvcCabacContext::SigCoeffFlag(ctx) => {
                const LOG2_WINDOW: [u8; 63] = [
                    12, 9, 9, 10, 9, 9, 9, 10, 8, 8, 8, 10, 9, 13, 8, 8, 8, 8, 8, 5, 8, 0, 0, 0, 8,
                    8, 8, 8, 8, 0, 4, 4, 0, 0, 0, 0, 12, 12, 9, 13, 4, 5, 8, 9, 8, 12, 12, 8, 4, 0,
                    0, 0, 8, 8, 8, 8, 4, 0, 0, 0, 13, 13, 8,
                ];
                LOG2_WINDOW[ctx as usize]
            }
            VvcCabacContext::ParLevelFlag(ctx) => {
                const LOG2_WINDOW: [u8; 33] = [
                    8, 9, 12, 13, 13, 13, 10, 13, 13, 13, 13, 13, 13, 13, 13, 13, 10, 13, 13, 13,
                    13, 8, 12, 12, 12, 13, 13, 13, 13, 13, 13, 13, 6,
                ];
                LOG2_WINDOW[ctx as usize]
            }
            VvcCabacContext::AbsLevelGtxFlag(ctx) => {
                const LOG2_WINDOW: [u8; 72] = [
                    9, 5, 10, 13, 13, 10, 9, 10, 13, 13, 13, 9, 10, 10, 10, 13, 8, 9, 10, 10, 13,
                    8, 8, 9, 12, 12, 10, 5, 9, 9, 9, 13, 1, 5, 9, 9, 9, 6, 5, 9, 10, 10, 9, 9, 9,
                    9, 9, 9, 6, 8, 9, 9, 10, 1, 5, 8, 8, 9, 6, 6, 9, 8, 8, 9, 4, 2, 1, 6, 1, 1, 1,
                    1,
                ];
                LOG2_WINDOW[ctx as usize]
            }
            VvcCabacContext::CoeffSignFlag(ctx) => {
                const LOG2_WINDOW: [u8; 6] = [1, 4, 4, 5, 8, 8];
                LOG2_WINDOW[ctx as usize]
            }
            VvcCabacContext::PredModePltFlag => 1,
            VvcCabacContext::PaletteTransposeFlag => 5,
            VvcCabacContext::CopyAbovePaletteIndicesFlag => 9,
            VvcCabacContext::RunCopyFlag(ctx) => {
                const LOG2_WINDOW: [u8; 8] = [9, 6, 9, 10, 5, 0, 9, 5];
                LOG2_WINDOW[ctx as usize]
            }
        }
    }
}

#[derive(Debug, Clone)]
pub(in crate::vvc) struct VvcCabacContexts {
    pub(in crate::vvc) split_flag: [VvcCabacProbModel; 9],
    pub(in crate::vvc) split_qt_flag: [VvcCabacProbModel; 6],
    pub(in crate::vvc) mtt_split_cu_vertical_flag: [VvcCabacProbModel; 15],
    pub(in crate::vvc) mtt_split_cu_binary_flag: [VvcCabacProbModel; 12],
    pub(in crate::vvc) multi_ref_line_idx: [VvcCabacProbModel; 2],
    pub(in crate::vvc) intra_luma_mpm_flag: VvcCabacProbModel,
    pub(in crate::vvc) intra_luma_planar_flag: [VvcCabacProbModel; 2],
    pub(in crate::vvc) cclm_mode_flag: VvcCabacProbModel,
    pub(in crate::vvc) intra_chroma_pred_mode: [VvcCabacProbModel; 2],
    pub(in crate::vvc) qt_cbf_y: [VvcCabacProbModel; 4],
    pub(in crate::vvc) qt_cbf_cb: [VvcCabacProbModel; 2],
    pub(in crate::vvc) qt_cbf_cr: [VvcCabacProbModel; 3],
    pub(in crate::vvc) transform_skip_flag: [VvcCabacProbModel; 2],
    pub(in crate::vvc) bdpcm_mode: [VvcCabacProbModel; 4],
    pub(in crate::vvc) mts_idx: [VvcCabacProbModel; 4],
    pub(in crate::vvc) cu_skip_flag: [VvcCabacProbModel; 9],
    pub(in crate::vvc) pred_mode_ibc_flag: [VvcCabacProbModel; 9],
    pub(in crate::vvc) general_merge_flag: [VvcCabacProbModel; 3],
    pub(in crate::vvc) abs_mvd_greater0_flag: [VvcCabacProbModel; 3],
    pub(in crate::vvc) abs_mvd_greater1_flag: [VvcCabacProbModel; 3],
    pub(in crate::vvc) cu_coded_flag: [VvcCabacProbModel; 3],
    pub(in crate::vvc) last_sig_coeff_x_prefix: [VvcCabacProbModel; 23],
    pub(in crate::vvc) last_sig_coeff_y_prefix: [VvcCabacProbModel; 23],
    pub(in crate::vvc) sb_coded_flag: [VvcCabacProbModel; 7],
    pub(in crate::vvc) sig_coeff_flag: [VvcCabacProbModel; 63],
    pub(in crate::vvc) par_level_flag: [VvcCabacProbModel; 33],
    pub(in crate::vvc) abs_level_gtx_flag: [VvcCabacProbModel; 72],
    pub(in crate::vvc) coeff_sign_flag: [VvcCabacProbModel; 6],
    pub(in crate::vvc) pred_mode_plt_flag: VvcCabacProbModel,
    pub(in crate::vvc) palette_transpose_flag: VvcCabacProbModel,
    pub(in crate::vvc) copy_above_palette_indices_flag: VvcCabacProbModel,
    pub(in crate::vvc) run_copy_flag: [VvcCabacProbModel; 8],
}

impl VvcCabacContexts {
    const DEFAULT_SLICE_QP: i32 = 32;

    pub(in crate::vvc) fn new() -> Self {
        Self::with_slice_qp(Self::DEFAULT_SLICE_QP)
    }

    pub(in crate::vvc) fn with_slice_qp(slice_qp: i32) -> Self {
        Self {
            split_flag: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::SplitFlag(idx as u8).init_value(),
                    slice_qp,
                    VvcCabacContext::SplitFlag(idx as u8).log2_window_size(),
                )
            }),
            split_qt_flag: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::SplitQtFlag(idx as u8).init_value(),
                    slice_qp,
                    VvcCabacContext::SplitQtFlag(idx as u8).log2_window_size(),
                )
            }),
            mtt_split_cu_vertical_flag: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::MttSplitCuVerticalFlag(idx as u8).init_value(),
                    slice_qp,
                    VvcCabacContext::MttSplitCuVerticalFlag(idx as u8).log2_window_size(),
                )
            }),
            mtt_split_cu_binary_flag: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::MttSplitCuBinaryFlag(idx as u8).init_value(),
                    slice_qp,
                    VvcCabacContext::MttSplitCuBinaryFlag(idx as u8).log2_window_size(),
                )
            }),
            multi_ref_line_idx: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::MultiRefLineIdx(idx as u8).init_value(),
                    slice_qp,
                    VvcCabacContext::MultiRefLineIdx(idx as u8).log2_window_size(),
                )
            }),
            intra_luma_mpm_flag: VvcCabacProbModel::from_init_value(
                VvcCabacContext::IntraLumaMpmFlag.init_value(),
                slice_qp,
                VvcCabacContext::IntraLumaMpmFlag.log2_window_size(),
            ),
            intra_luma_planar_flag: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::IntraLumaPlanarFlag(idx as u8).init_value(),
                    slice_qp,
                    VvcCabacContext::IntraLumaPlanarFlag(idx as u8).log2_window_size(),
                )
            }),
            cclm_mode_flag: VvcCabacProbModel::from_init_value(
                VvcCabacContext::CclmModeFlag.init_value(),
                slice_qp,
                VvcCabacContext::CclmModeFlag.log2_window_size(),
            ),
            intra_chroma_pred_mode: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::IntraChromaPredMode(idx as u8).init_value(),
                    slice_qp,
                    VvcCabacContext::IntraChromaPredMode(idx as u8).log2_window_size(),
                )
            }),
            qt_cbf_y: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::QtCbfY(idx as u8).init_value(),
                    slice_qp,
                    VvcCabacContext::QtCbfY(idx as u8).log2_window_size(),
                )
            }),
            qt_cbf_cb: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::QtCbfCb(idx as u8).init_value(),
                    slice_qp,
                    VvcCabacContext::QtCbfCb(idx as u8).log2_window_size(),
                )
            }),
            qt_cbf_cr: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::QtCbfCr(idx as u8).init_value(),
                    slice_qp,
                    VvcCabacContext::QtCbfCr(idx as u8).log2_window_size(),
                )
            }),
            transform_skip_flag: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::TransformSkipFlag(idx as u8).init_value(),
                    slice_qp,
                    VvcCabacContext::TransformSkipFlag(idx as u8).log2_window_size(),
                )
            }),
            bdpcm_mode: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::BdpcmMode(idx as u8).init_value(),
                    slice_qp,
                    VvcCabacContext::BdpcmMode(idx as u8).log2_window_size(),
                )
            }),
            mts_idx: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::MtsIdx(idx as u8).init_value(),
                    slice_qp,
                    VvcCabacContext::MtsIdx(idx as u8).log2_window_size(),
                )
            }),
            cu_skip_flag: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::CuSkipFlag(idx as u8).init_value(),
                    slice_qp,
                    VvcCabacContext::CuSkipFlag(idx as u8).log2_window_size(),
                )
            }),
            pred_mode_ibc_flag: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::PredModeIbcFlag(idx as u8).init_value(),
                    slice_qp,
                    VvcCabacContext::PredModeIbcFlag(idx as u8).log2_window_size(),
                )
            }),
            general_merge_flag: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::GeneralMergeFlag(idx as u8).init_value(),
                    slice_qp,
                    VvcCabacContext::GeneralMergeFlag(idx as u8).log2_window_size(),
                )
            }),
            abs_mvd_greater0_flag: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::AbsMvdGreater0Flag(idx as u8).init_value(),
                    slice_qp,
                    VvcCabacContext::AbsMvdGreater0Flag(idx as u8).log2_window_size(),
                )
            }),
            abs_mvd_greater1_flag: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::AbsMvdGreater1Flag(idx as u8).init_value(),
                    slice_qp,
                    VvcCabacContext::AbsMvdGreater1Flag(idx as u8).log2_window_size(),
                )
            }),
            cu_coded_flag: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::CuCodedFlag(idx as u8).init_value(),
                    slice_qp,
                    VvcCabacContext::CuCodedFlag(idx as u8).log2_window_size(),
                )
            }),
            last_sig_coeff_x_prefix: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::LastSigCoeffXPrefix(idx as u8).init_value(),
                    slice_qp,
                    VvcCabacContext::LastSigCoeffXPrefix(idx as u8).log2_window_size(),
                )
            }),
            last_sig_coeff_y_prefix: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::LastSigCoeffYPrefix(idx as u8).init_value(),
                    slice_qp,
                    VvcCabacContext::LastSigCoeffYPrefix(idx as u8).log2_window_size(),
                )
            }),
            sb_coded_flag: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::SbCodedFlag(idx as u8).init_value(),
                    slice_qp,
                    VvcCabacContext::SbCodedFlag(idx as u8).log2_window_size(),
                )
            }),
            sig_coeff_flag: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::SigCoeffFlag(idx as u8).init_value(),
                    slice_qp,
                    VvcCabacContext::SigCoeffFlag(idx as u8).log2_window_size(),
                )
            }),
            par_level_flag: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::ParLevelFlag(idx as u8).init_value(),
                    slice_qp,
                    VvcCabacContext::ParLevelFlag(idx as u8).log2_window_size(),
                )
            }),
            abs_level_gtx_flag: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::AbsLevelGtxFlag(idx as u8).init_value(),
                    slice_qp,
                    VvcCabacContext::AbsLevelGtxFlag(idx as u8).log2_window_size(),
                )
            }),
            coeff_sign_flag: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::CoeffSignFlag(idx as u8).init_value(),
                    slice_qp,
                    VvcCabacContext::CoeffSignFlag(idx as u8).log2_window_size(),
                )
            }),
            pred_mode_plt_flag: VvcCabacProbModel::from_init_value(
                VvcCabacContext::PredModePltFlag.init_value(),
                slice_qp,
                VvcCabacContext::PredModePltFlag.log2_window_size(),
            ),
            palette_transpose_flag: VvcCabacProbModel::from_init_value(
                VvcCabacContext::PaletteTransposeFlag.init_value(),
                slice_qp,
                VvcCabacContext::PaletteTransposeFlag.log2_window_size(),
            ),
            copy_above_palette_indices_flag: VvcCabacProbModel::from_init_value(
                VvcCabacContext::CopyAbovePaletteIndicesFlag.init_value(),
                slice_qp,
                VvcCabacContext::CopyAbovePaletteIndicesFlag.log2_window_size(),
            ),
            run_copy_flag: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::RunCopyFlag(idx as u8).init_value(),
                    slice_qp,
                    VvcCabacContext::RunCopyFlag(idx as u8).log2_window_size(),
                )
            }),
        }
    }

    pub(in crate::vvc) fn encode(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        ctx: VvcCabacContext,
        bin: bool,
    ) {
        cabac.context_bin_count += 1;
        let model = match ctx {
            VvcCabacContext::SplitFlag(idx) => &self.split_flag[idx as usize],
            VvcCabacContext::SplitQtFlag(idx) => &self.split_qt_flag[idx as usize],
            VvcCabacContext::MttSplitCuVerticalFlag(idx) => {
                &self.mtt_split_cu_vertical_flag[idx as usize]
            }
            VvcCabacContext::MttSplitCuBinaryFlag(idx) => {
                &self.mtt_split_cu_binary_flag[idx as usize]
            }
            VvcCabacContext::MultiRefLineIdx(idx) => &self.multi_ref_line_idx[idx as usize],
            VvcCabacContext::IntraLumaMpmFlag => &self.intra_luma_mpm_flag,
            VvcCabacContext::IntraLumaPlanarFlag(idx) => &self.intra_luma_planar_flag[idx as usize],
            VvcCabacContext::CclmModeFlag => &self.cclm_mode_flag,
            VvcCabacContext::IntraChromaPredMode(idx) => &self.intra_chroma_pred_mode[idx as usize],
            VvcCabacContext::QtCbfY(idx) => &self.qt_cbf_y[idx as usize],
            VvcCabacContext::QtCbfCb(idx) => &self.qt_cbf_cb[idx as usize],
            VvcCabacContext::QtCbfCr(idx) => &self.qt_cbf_cr[idx as usize],
            VvcCabacContext::TransformSkipFlag(idx) => &self.transform_skip_flag[idx as usize],
            VvcCabacContext::BdpcmMode(idx) => &self.bdpcm_mode[idx as usize],
            VvcCabacContext::MtsIdx(idx) => &self.mts_idx[idx as usize],
            VvcCabacContext::CuSkipFlag(idx) => &self.cu_skip_flag[idx as usize],
            VvcCabacContext::PredModeIbcFlag(idx) => &self.pred_mode_ibc_flag[idx as usize],
            VvcCabacContext::GeneralMergeFlag(idx) => &self.general_merge_flag[idx as usize],
            VvcCabacContext::AbsMvdGreater0Flag(idx) => &self.abs_mvd_greater0_flag[idx as usize],
            VvcCabacContext::AbsMvdGreater1Flag(idx) => &self.abs_mvd_greater1_flag[idx as usize],
            VvcCabacContext::CuCodedFlag(idx) => &self.cu_coded_flag[idx as usize],
            VvcCabacContext::LastSigCoeffXPrefix(idx) => {
                &self.last_sig_coeff_x_prefix[idx as usize]
            }
            VvcCabacContext::LastSigCoeffYPrefix(idx) => {
                &self.last_sig_coeff_y_prefix[idx as usize]
            }
            VvcCabacContext::SbCodedFlag(idx) => &self.sb_coded_flag[idx as usize],
            VvcCabacContext::SigCoeffFlag(idx) => &self.sig_coeff_flag[idx as usize],
            VvcCabacContext::ParLevelFlag(idx) => &self.par_level_flag[idx as usize],
            VvcCabacContext::AbsLevelGtxFlag(idx) => &self.abs_level_gtx_flag[idx as usize],
            VvcCabacContext::CoeffSignFlag(idx) => &self.coeff_sign_flag[idx as usize],
            VvcCabacContext::PredModePltFlag => &self.pred_mode_plt_flag,
            VvcCabacContext::PaletteTransposeFlag => &self.palette_transpose_flag,
            VvcCabacContext::CopyAbovePaletteIndicesFlag => &self.copy_above_palette_indices_flag,
            VvcCabacContext::RunCopyFlag(idx) => &self.run_copy_flag[idx as usize],
        };
        if let Some(ctx_id) = ctx.rtl_context_id() {
            cabac
                .semantic_symbols
                .push(VvcCabacDumpSymbol::bin_ctx(bin, ctx_id));
            cabac.context_events.push(VvcCabacDumpContextEvent {
                ctx_id,
                bin,
                range: cabac.range as u16,
                lps: model.lps(cabac.range),
                mps: model.mps(),
            });
        }
        if std::env::var_os("FRAMEFORGE_CABAC_TRACE").is_some() {
            eprintln!(
                "FF_CABAC {:?} range={} lps={} mps={} bin={}",
                ctx,
                cabac.range,
                model.lps(cabac.range),
                u8::from(model.mps()),
                u8::from(bin)
            );
        }
        match ctx {
            VvcCabacContext::SplitFlag(idx) => self.split_flag[idx as usize].encode(cabac, bin),
            VvcCabacContext::SplitQtFlag(idx) => {
                self.split_qt_flag[idx as usize].encode(cabac, bin)
            }
            VvcCabacContext::MttSplitCuVerticalFlag(idx) => {
                self.mtt_split_cu_vertical_flag[idx as usize].encode(cabac, bin)
            }
            VvcCabacContext::MttSplitCuBinaryFlag(idx) => {
                self.mtt_split_cu_binary_flag[idx as usize].encode(cabac, bin)
            }
            VvcCabacContext::MultiRefLineIdx(idx) => {
                self.multi_ref_line_idx[idx as usize].encode(cabac, bin)
            }
            VvcCabacContext::IntraLumaMpmFlag => self.intra_luma_mpm_flag.encode(cabac, bin),
            VvcCabacContext::IntraLumaPlanarFlag(idx) => {
                self.intra_luma_planar_flag[idx as usize].encode(cabac, bin)
            }
            VvcCabacContext::CclmModeFlag => self.cclm_mode_flag.encode(cabac, bin),
            VvcCabacContext::IntraChromaPredMode(idx) => {
                self.intra_chroma_pred_mode[idx as usize].encode(cabac, bin)
            }
            VvcCabacContext::QtCbfY(idx) => self.qt_cbf_y[idx as usize].encode(cabac, bin),
            VvcCabacContext::QtCbfCb(idx) => self.qt_cbf_cb[idx as usize].encode(cabac, bin),
            VvcCabacContext::QtCbfCr(idx) => self.qt_cbf_cr[idx as usize].encode(cabac, bin),
            VvcCabacContext::TransformSkipFlag(idx) => {
                self.transform_skip_flag[idx as usize].encode(cabac, bin)
            }
            VvcCabacContext::BdpcmMode(idx) => self.bdpcm_mode[idx as usize].encode(cabac, bin),
            VvcCabacContext::MtsIdx(idx) => self.mts_idx[idx as usize].encode(cabac, bin),
            VvcCabacContext::CuSkipFlag(idx) => self.cu_skip_flag[idx as usize].encode(cabac, bin),
            VvcCabacContext::PredModeIbcFlag(idx) => {
                self.pred_mode_ibc_flag[idx as usize].encode(cabac, bin)
            }
            VvcCabacContext::GeneralMergeFlag(idx) => {
                self.general_merge_flag[idx as usize].encode(cabac, bin)
            }
            VvcCabacContext::AbsMvdGreater0Flag(idx) => {
                self.abs_mvd_greater0_flag[idx as usize].encode(cabac, bin)
            }
            VvcCabacContext::AbsMvdGreater1Flag(idx) => {
                self.abs_mvd_greater1_flag[idx as usize].encode(cabac, bin)
            }
            VvcCabacContext::CuCodedFlag(idx) => {
                self.cu_coded_flag[idx as usize].encode(cabac, bin)
            }
            VvcCabacContext::LastSigCoeffXPrefix(idx) => {
                self.last_sig_coeff_x_prefix[idx as usize].encode(cabac, bin)
            }
            VvcCabacContext::LastSigCoeffYPrefix(idx) => {
                self.last_sig_coeff_y_prefix[idx as usize].encode(cabac, bin)
            }
            VvcCabacContext::SbCodedFlag(idx) => {
                self.sb_coded_flag[idx as usize].encode(cabac, bin)
            }
            VvcCabacContext::SigCoeffFlag(idx) => {
                self.sig_coeff_flag[idx as usize].encode(cabac, bin)
            }
            VvcCabacContext::ParLevelFlag(idx) => {
                self.par_level_flag[idx as usize].encode(cabac, bin)
            }
            VvcCabacContext::AbsLevelGtxFlag(idx) => {
                self.abs_level_gtx_flag[idx as usize].encode(cabac, bin)
            }
            VvcCabacContext::CoeffSignFlag(idx) => {
                self.coeff_sign_flag[idx as usize].encode(cabac, bin)
            }
            VvcCabacContext::PredModePltFlag => self.pred_mode_plt_flag.encode(cabac, bin),
            VvcCabacContext::PaletteTransposeFlag => self.palette_transpose_flag.encode(cabac, bin),
            VvcCabacContext::CopyAbovePaletteIndicesFlag => {
                self.copy_above_palette_indices_flag.encode(cabac, bin)
            }
            VvcCabacContext::RunCopyFlag(idx) => {
                self.run_copy_flag[idx as usize].encode(cabac, bin)
            }
        }
    }
}

#[derive(Debug, Clone)]
pub(in crate::vvc) struct VvcCabacProbModel {
    state0: u16,
    state1: u16,
    rate: u8,
}

impl VvcCabacProbModel {
    const MASK_0: u16 = 0x7fe0;
    const MASK_1: u16 = 0x7ffe;

    fn from_init_value(init_value: u8, qp: i32, log2_window_size: u8) -> Self {
        let slope = ((init_value >> 3) as i32) - 4;
        let offset = (((init_value & 7) as i32) * 18) + 1;
        let inistate = ((slope * (qp - 16)) >> 1) + offset;
        let clipped = inistate.clamp(1, 127) as u16;
        let mut model = Self {
            state0: 0,
            state1: 0,
            rate: 0,
        };
        model.set_init_state(clipped << 8);
        model.set_log2_window_size(log2_window_size);
        model
    }

    fn set_log2_window_size(&mut self, log2_window_size: u8) {
        let rate0 = 2 + ((log2_window_size >> 2) & 3);
        let rate1 = 3 + rate0 + (log2_window_size & 3);
        self.rate = (16 * rate0) + rate1;
    }

    fn set_init_state(&mut self, probability_state: u16) {
        self.state0 = probability_state & Self::MASK_0;
        self.state1 = probability_state & Self::MASK_1;
    }

    pub(in crate::vvc) fn state(&self) -> u16 {
        (self.state0 + self.state1) >> 8
    }

    pub(in crate::vvc) fn mps(&self) -> bool {
        self.state() >= 128
    }

    pub(in crate::vvc) fn lps(&self, range: u32) -> u16 {
        let mut q = self.state();
        if (q & 0x80) != 0 {
            q ^= 0xff;
        }
        ((((q >> 2) as u32 * (range >> 5)) >> 1) + 4) as u16
    }

    fn encode(&mut self, cabac: &mut VvcCabacEncoder, bin: bool) {
        let event = VvcCtxEvent {
            lps: self.lps(cabac.range),
            mps: self.mps(),
        };
        cabac.encode_bin(bin, event);
        self.update(bin);
    }

    fn update(&mut self, bin: bool) {
        let rate0 = (self.rate >> 4) as u16;
        let rate1 = (self.rate & 15) as u16;
        self.state0 -= (self.state0 >> rate0) & Self::MASK_0;
        self.state1 -= (self.state1 >> rate1) & Self::MASK_1;
        if bin {
            self.state0 += (0x7fff_u16 >> rate0) & Self::MASK_0;
            self.state1 += (0x7fff_u16 >> rate1) & Self::MASK_1;
        }
    }
}
