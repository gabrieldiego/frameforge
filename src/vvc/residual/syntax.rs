use super::super::{
    VvcCabacContext, VvcCabacContexts, VvcCabacEncoder, VvcLastSigCoeffPrefixCtxInput,
};
use super::VvcResidualComponent;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::vvc) struct VvcResidualCabacOptions {
    pub(in crate::vvc) transform_skip_enabled: bool,
    pub(in crate::vvc) explicit_mts_intra_enabled: bool,
    pub(in crate::vvc) dependent_quantization_enabled: bool,
    pub(in crate::vvc) sign_data_hiding_enabled: bool,
    pub(in crate::vvc) lfnst_enabled: bool,
    pub(in crate::vvc) sbt_enabled: bool,
}

pub(in crate::vvc) struct VvcResidualCabacEncoder<'a> {
    contexts: &'a mut VvcCabacContexts,
    options: VvcResidualCabacOptions,
}

impl<'a> VvcResidualCabacEncoder<'a> {
    pub(in crate::vvc) fn new(
        contexts: &'a mut VvcCabacContexts,
        options: VvcResidualCabacOptions,
    ) -> Self {
        Self { contexts, options }
    }

    fn emit_residual_symbol(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        state: &VvcResidualPass1State,
        symbol: VvcResidualCabacSymbol,
    ) {
        match symbol {
            VvcResidualCabacSymbol::LastSigCoeffXPrefix { bin_idx, bin } => {
                self.emit_last_sig_coeff_prefix_bin(
                    cabac,
                    state.config.component,
                    true,
                    state.config.log2_zo_tb_width,
                    bin_idx,
                    bin,
                );
            }
            VvcResidualCabacSymbol::LastSigCoeffYPrefix { bin_idx, bin } => {
                self.emit_last_sig_coeff_prefix_bin(
                    cabac,
                    state.config.component,
                    false,
                    state.config.log2_zo_tb_height,
                    bin_idx,
                    bin,
                );
            }
            VvcResidualCabacSymbol::SbCodedFlag { x_s, y_s, coded } => {
                self.emit_sb_coded_flag(cabac, state, x_s, y_s, coded);
            }
            VvcResidualCabacSymbol::SigCoeffFlag { x, y, significant } => {
                self.emit_sig_coeff_flag(cabac, state, x, y, significant);
            }
            VvcResidualCabacSymbol::ParLevelFlag { x, y, par_level } => {
                self.emit_par_level_flag(cabac, state, x, y, par_level);
            }
            VvcResidualCabacSymbol::AbsLevelGtxFlag {
                x,
                y,
                gtx_idx,
                greater_than,
            } => {
                self.emit_abs_level_gtx_flag(cabac, state, x, y, gtx_idx, greater_than);
            }
            VvcResidualCabacSymbol::AbsRemainder {
                value, rice_param, ..
            } => {
                cabac.encode_rem_abs_ep(value, u32::from(rice_param));
            }
            VvcResidualCabacSymbol::CoeffSignFlag { x, y, negative } => {
                self.emit_coeff_sign_flag(cabac, state, x, y, negative);
            }
        }
    }

    fn emit_last_sig_coeff_prefix_bin(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        component: VvcResidualComponent,
        x_prefix: bool,
        log2_tb_size: u8,
        bin_idx: u8,
        bin: bool,
    ) {
        let ctx_inc = VvcLastSigCoeffPrefixCtxInput {
            is_luma: component == VvcResidualComponent::Luma,
            log2_tb_size,
            bin_idx,
        }
        .ctx_inc();
        let ctx = if x_prefix {
            VvcCabacContext::LastSigCoeffXPrefix(ctx_inc)
        } else {
            VvcCabacContext::LastSigCoeffYPrefix(ctx_inc)
        };
        self.contexts.encode(cabac, ctx, bin);
    }

    #[cfg(test)]
    pub(in crate::vvc) fn emit_last_sig_coeff_prefixes_4x4(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        component: VvcResidualComponent,
        last_x: u8,
        last_y: u8,
    ) {
        debug_assert!(last_x < 4);
        debug_assert!(last_y < 4);
        Self::append_last_sig_coeff_prefix_4x4(self, cabac, component, true, last_x);
        Self::append_last_sig_coeff_prefix_4x4(self, cabac, component, false, last_y);
    }

    #[cfg(test)]
    fn append_last_sig_coeff_prefix_4x4(
        encoder: &mut Self,
        cabac: &mut VvcCabacEncoder,
        component: VvcResidualComponent,
        x_prefix: bool,
        prefix: u8,
    ) {
        for bin_idx in 0..prefix {
            encoder.emit_last_sig_coeff_prefix_bin(cabac, component, x_prefix, 2, bin_idx, true);
        }
        if prefix < 3 {
            encoder.emit_last_sig_coeff_prefix_bin(cabac, component, x_prefix, 2, prefix, false);
        }
    }

    pub(in crate::vvc) fn emit_sb_coded_flag(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        state: &VvcResidualPass1State,
        x_s: u8,
        y_s: u8,
        coded: bool,
    ) {
        let ctx_inc = state.sb_coded_flag_ctx_inc(x_s, y_s);
        self.contexts
            .encode(cabac, VvcCabacContext::SbCodedFlag(ctx_inc), coded);
    }

    pub(in crate::vvc) fn emit_sig_coeff_flag(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        state: &VvcResidualPass1State,
        x: u8,
        y: u8,
        significant: bool,
    ) {
        let ctx_inc = state.sig_coeff_flag_ctx_inc(x, y);
        self.contexts
            .encode(cabac, VvcCabacContext::SigCoeffFlag(ctx_inc), significant);
    }

    pub(in crate::vvc) fn emit_par_level_flag(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        state: &VvcResidualPass1State,
        x: u8,
        y: u8,
        par_level: bool,
    ) {
        let ctx_inc = state.par_level_flag_ctx_inc(x, y);
        self.contexts
            .encode(cabac, VvcCabacContext::ParLevelFlag(ctx_inc), par_level);
    }

    pub(in crate::vvc) fn emit_abs_level_gtx_flag(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        state: &VvcResidualPass1State,
        x: u8,
        y: u8,
        gtx_idx: u8,
        greater_than: bool,
    ) {
        let ctx_inc = state.abs_level_gtx_flag_ctx_inc(x, y, gtx_idx);
        debug_assert!(
            ctx_inc < 72,
            "cached abs_level_gtx_flag table currently covers ctxInc 0..71"
        );
        self.contexts.encode(
            cabac,
            VvcCabacContext::AbsLevelGtxFlag(ctx_inc),
            greater_than,
        );
    }

    pub(in crate::vvc) fn emit_coeff_sign_flag(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        state: &VvcResidualPass1State,
        x: u8,
        y: u8,
        negative: bool,
    ) {
        if state.config.transform_skip_residual_enabled() {
            let ctx_inc = state.coeff_sign_flag_ts_ctx_inc(x, y);
            self.contexts
                .encode(cabac, VvcCabacContext::CoeffSignFlag(ctx_inc), negative);
        } else {
            cabac.encode_bin_ep(negative);
        }
    }

    pub(in crate::vvc) fn emit_default_tool_control_hooks(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        state: &VvcResidualPass1State,
    ) {
        self.emit_transform_skip_flag(cabac, state.config.component, false);
        self.emit_mts_idx_zero(cabac);
        self.observe_future_chroma_defaults();
        self.observe_current_disabled_tool_defaults();
        let _default_sb_symbol = VvcResidualCabacSymbol::SbCodedFlag {
            x_s: 0,
            y_s: 0,
            coded: false,
        };
        let _default_sb_ctx = state.sb_coded_flag_ctx_inc(0, 0);
    }

    fn emit_transform_skip_flag(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        component: VvcResidualComponent,
        transform_skip: bool,
    ) {
        if !self.options.transform_skip_enabled {
            debug_assert!(!transform_skip);
            return;
        }

        self.contexts.encode(
            cabac,
            VvcCabacContext::TransformSkipFlag(component.transform_skip_ctx_inc()),
            transform_skip,
        );
    }

    fn emit_mts_idx_zero(&mut self, cabac: &mut VvcCabacEncoder) {
        if !self.options.explicit_mts_intra_enabled {
            return;
        }

        // Table 132 maps mts_idx binIdx 0..3 to ctxInc 0..3. For mts_idx=0
        // under TR(cMax=4,cRiceParam=0), only the first zero bin is emitted.
        self.contexts
            .encode(cabac, VvcCabacContext::MtsIdx(0), false);
    }

    fn observe_future_chroma_defaults(&self) {
        let _default_chroma_transform_skip_contexts = (
            VvcResidualComponent::ChromaCb.transform_skip_ctx_inc(),
            VvcResidualComponent::ChromaCr.transform_skip_ctx_inc(),
        );
    }

    fn observe_current_disabled_tool_defaults(&self) {
        let _disabled_tool_defaults = (
            self.options.dependent_quantization_enabled,
            self.options.sign_data_hiding_enabled,
            self.options.lfnst_enabled,
            self.options.sbt_enabled,
        );
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::vvc) struct VvcResidualCtxConfig {
    pub(in crate::vvc) component: VvcResidualComponent,
    pub(in crate::vvc) log2_zo_tb_width: u8,
    pub(in crate::vvc) log2_zo_tb_height: u8,
    pub(in crate::vvc) q_state: u8,
    pub(in crate::vvc) transform_skip: bool,
    pub(in crate::vvc) ts_residual_coding_disabled: bool,
    pub(in crate::vvc) bdpcm: bool,
    pub(in crate::vvc) last_significant_x: u8,
    pub(in crate::vvc) last_significant_y: u8,
}

impl VvcResidualCtxConfig {
    #[cfg(test)]
    pub(in crate::vvc) fn luma_4x4_subset(last_significant_x: u8, last_significant_y: u8) -> Self {
        Self::luma_subset(2, 2, last_significant_x, last_significant_y)
    }

    pub(in crate::vvc) fn luma_subset(
        log2_zo_tb_width: u8,
        log2_zo_tb_height: u8,
        last_significant_x: u8,
        last_significant_y: u8,
    ) -> Self {
        debug_assert!((2..=6).contains(&log2_zo_tb_width));
        debug_assert!((2..=6).contains(&log2_zo_tb_height));
        Self {
            component: VvcResidualComponent::Luma,
            log2_zo_tb_width,
            log2_zo_tb_height,
            q_state: 0,
            transform_skip: false,
            ts_residual_coding_disabled: true,
            bdpcm: false,
            last_significant_x,
            last_significant_y,
        }
    }

    fn is_luma(self) -> bool {
        self.component == VvcResidualComponent::Luma
    }

    fn transform_skip_residual_enabled(self) -> bool {
        self.transform_skip && !self.ts_residual_coding_disabled
    }

    fn tb_width(self) -> usize {
        1usize << self.log2_zo_tb_width
    }

    fn tb_height(self) -> usize {
        1usize << self.log2_zo_tb_height
    }

    fn coefficient_count(self) -> usize {
        self.tb_width() * self.tb_height()
    }

    fn coefficient_index(self, x: u8, y: u8) -> usize {
        assert!((x as usize) < self.tb_width());
        assert!((y as usize) < self.tb_height());
        y as usize * self.tb_width() + x as usize
    }

    fn log2_sb_width(self) -> u8 {
        let mut log2_sb_width = if self.log2_zo_tb_width.min(self.log2_zo_tb_height) < 2 {
            1
        } else {
            2
        };
        if self.log2_zo_tb_width < 2 && self.is_luma() {
            log2_sb_width = self.log2_zo_tb_width;
        } else if self.log2_zo_tb_height < 2 && self.is_luma() {
            log2_sb_width = 4 - self.log2_zo_tb_height;
        }
        log2_sb_width
    }

    fn log2_sb_height(self) -> u8 {
        let mut log2_sb_height = if self.log2_zo_tb_width.min(self.log2_zo_tb_height) < 2 {
            1
        } else {
            2
        };
        if self.log2_zo_tb_width < 2 && self.is_luma() {
            log2_sb_height = 4 - self.log2_zo_tb_width;
        } else if self.log2_zo_tb_height < 2 && self.is_luma() {
            log2_sb_height = self.log2_zo_tb_height;
        }
        log2_sb_height
    }

    fn subblocks_wide(self) -> usize {
        1usize << (self.log2_zo_tb_width - self.log2_sb_width())
    }

    fn subblocks_high(self) -> usize {
        1usize << (self.log2_zo_tb_height - self.log2_sb_height())
    }

    fn subblock_count(self) -> usize {
        self.subblocks_wide() * self.subblocks_high()
    }

    fn subblock_index(self, x_s: u8, y_s: u8) -> usize {
        assert!((x_s as usize) < self.subblocks_wide());
        assert!((y_s as usize) < self.subblocks_high());
        y_s as usize * self.subblocks_wide() + x_s as usize
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(in crate::vvc) struct VvcResidualPass1State {
    pub(in crate::vvc) config: VvcResidualCtxConfig,
    pub(in crate::vvc) sig_coeff: Vec<bool>,
    pub(in crate::vvc) abs_level_pass1: Vec<u8>,
    pub(in crate::vvc) coeff_sign_level: Vec<i8>,
    pub(in crate::vvc) sb_coded: Vec<bool>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::vvc) struct VvcResidualLocalStats {
    pub(in crate::vvc) loc_num_sig: u8,
    pub(in crate::vvc) loc_sum_abs_pass1: u8,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::vvc) enum VvcResidualCabacSymbol {
    LastSigCoeffXPrefix {
        bin_idx: u8,
        bin: bool,
    },
    LastSigCoeffYPrefix {
        bin_idx: u8,
        bin: bool,
    },
    SbCodedFlag {
        x_s: u8,
        y_s: u8,
        coded: bool,
    },
    SigCoeffFlag {
        x: u8,
        y: u8,
        significant: bool,
    },
    ParLevelFlag {
        x: u8,
        y: u8,
        par_level: bool,
    },
    AbsLevelGtxFlag {
        x: u8,
        y: u8,
        gtx_idx: u8,
        greater_than: bool,
    },
    AbsRemainder {
        x: u8,
        y: u8,
        value: u32,
        rice_param: u8,
    },
    CoeffSignFlag {
        x: u8,
        y: u8,
        negative: bool,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(in crate::vvc) struct VvcResidualCabacSymbolStream {
    pub(in crate::vvc) config: VvcResidualCtxConfig,
    pub(in crate::vvc) pass1_state: VvcResidualPass1State,
    pub(in crate::vvc) symbols: Vec<VvcResidualCabacSymbol>,
}

impl VvcResidualPass1State {
    pub(in crate::vvc) fn new(config: VvcResidualCtxConfig) -> Self {
        Self {
            config,
            sig_coeff: vec![false; config.coefficient_count()],
            abs_level_pass1: vec![0; config.coefficient_count()],
            coeff_sign_level: vec![0; config.coefficient_count()],
            sb_coded: vec![false; config.subblock_count()],
        }
    }

    pub(in crate::vvc) fn set_pass1_coeff(
        &mut self,
        x: u8,
        y: u8,
        abs_level_pass1: u8,
        negative: bool,
    ) {
        let index = self.config.coefficient_index(x, y);
        self.sig_coeff[index] = abs_level_pass1 != 0;
        self.abs_level_pass1[index] = abs_level_pass1;
        self.coeff_sign_level[index] = if abs_level_pass1 == 0 {
            0
        } else if negative {
            -1
        } else {
            1
        };
    }

    pub(in crate::vvc) fn set_sb_coded(&mut self, x_s: u8, y_s: u8, coded: bool) {
        let index = self.config.subblock_index(x_s, y_s);
        self.sb_coded[index] = coded;
    }

    pub(in crate::vvc) fn sb_coded_flag_ctx_inc(&self, x_s: u8, y_s: u8) -> u8 {
        // VVC 9.3.4.2.6. Keep transform-skip and regular residual paths
        // separate because future screen-content tools will use both.
        let mut csbf_ctx = 0;
        if self.config.transform_skip_residual_enabled() {
            if x_s > 0 && self.sb_coded_at(x_s - 1, y_s) {
                csbf_ctx += 1;
            }
            if y_s > 0 && self.sb_coded_at(x_s, y_s - 1) {
                csbf_ctx += 1;
            }
            4 + csbf_ctx
        } else {
            if (x_s as usize) + 1 < self.config.subblocks_wide() && self.sb_coded_at(x_s + 1, y_s) {
                csbf_ctx += 1;
            }
            if (y_s as usize) + 1 < self.config.subblocks_high() && self.sb_coded_at(x_s, y_s + 1) {
                csbf_ctx += 1;
            }
            if self.config.is_luma() {
                csbf_ctx.min(1)
            } else {
                2 + csbf_ctx.min(1)
            }
        }
    }

    pub(in crate::vvc) fn sig_coeff_flag_ctx_inc(&self, x: u8, y: u8) -> u8 {
        // VVC 9.3.4.2.8. QState is kept explicit even though the current
        // subset initializes it to zero for the simple residual path.
        let stats = self.local_stats(x, y);
        if self.config.transform_skip_residual_enabled() {
            60 + stats.loc_num_sig
        } else {
            let d = x + y;
            let sum_bucket = ((stats.loc_sum_abs_pass1 + 1) >> 1).min(3);
            let q_bucket = 12 * self.config.q_state.saturating_sub(1);
            if self.config.is_luma() {
                q_bucket
                    + sum_bucket
                    + if d < 2 {
                        8
                    } else if d < 5 {
                        4
                    } else {
                        0
                    }
            } else {
                36 + (8 * self.config.q_state.saturating_sub(1))
                    + sum_bucket
                    + if d < 2 { 4 } else { 0 }
            }
        }
    }

    pub(in crate::vvc) fn par_level_flag_ctx_inc(&self, x: u8, y: u8) -> u8 {
        self.par_or_abs_level_ctx_inc(x, y, false, 0)
    }

    pub(in crate::vvc) fn abs_level_gtx_flag_ctx_inc(&self, x: u8, y: u8, gtx_idx: u8) -> u8 {
        self.par_or_abs_level_ctx_inc(x, y, true, gtx_idx)
    }

    pub(in crate::vvc) fn coeff_sign_flag_ts_ctx_inc(&self, x: u8, y: u8) -> u8 {
        // VVC 9.3.4.2.10 is used only for transform-skip sign contexts.
        // Regular residual sign bins remain bypass-coded in the current path.
        debug_assert!(self.config.transform_skip_residual_enabled());
        let left_sign = if x == 0 {
            0
        } else {
            self.coeff_sign_level_at(x - 1, y)
        };
        let above_sign = if y == 0 {
            0
        } else {
            self.coeff_sign_level_at(x, y - 1)
        };
        if (left_sign == 0 && above_sign == 0) || left_sign == -above_sign {
            if self.config.bdpcm {
                3
            } else {
                0
            }
        } else if left_sign >= 0 && above_sign >= 0 {
            if self.config.bdpcm {
                4
            } else {
                1
            }
        } else if self.config.bdpcm {
            5
        } else {
            2
        }
    }

    pub(in crate::vvc) fn local_stats(&self, x: u8, y: u8) -> VvcResidualLocalStats {
        // VVC 9.3.4.2.7. The regular transform path looks forward in raster
        // coordinates because coefficients are scanned in reverse order.
        let mut loc_num_sig = 0;
        let mut loc_sum_abs_pass1 = 0;
        if self.config.transform_skip_residual_enabled() {
            if x > 0 {
                self.accumulate_local(x - 1, y, &mut loc_num_sig, &mut loc_sum_abs_pass1);
            }
            if y > 0 {
                self.accumulate_local(x, y - 1, &mut loc_num_sig, &mut loc_sum_abs_pass1);
            }
        } else {
            if (x as usize) + 1 < self.config.tb_width() {
                self.accumulate_local(x + 1, y, &mut loc_num_sig, &mut loc_sum_abs_pass1);
                if (x as usize) + 2 < self.config.tb_width() {
                    self.accumulate_local(x + 2, y, &mut loc_num_sig, &mut loc_sum_abs_pass1);
                }
                if (y as usize) + 1 < self.config.tb_height() {
                    self.accumulate_local(x + 1, y + 1, &mut loc_num_sig, &mut loc_sum_abs_pass1);
                }
            }
            if (y as usize) + 1 < self.config.tb_height() {
                self.accumulate_local(x, y + 1, &mut loc_num_sig, &mut loc_sum_abs_pass1);
                if (y as usize) + 2 < self.config.tb_height() {
                    self.accumulate_local(x, y + 2, &mut loc_num_sig, &mut loc_sum_abs_pass1);
                }
            }
        }
        VvcResidualLocalStats {
            loc_num_sig,
            loc_sum_abs_pass1,
        }
    }

    fn par_or_abs_level_ctx_inc(&self, x: u8, y: u8, abs_level_gtx: bool, gtx_idx: u8) -> u8 {
        // VVC 9.3.4.2.9. Only abs_level_gtx_flag[n][0] is wired to the cached
        // context table today; gtx_idx > 0 is labelled here for the upcoming
        // larger residual-level implementation.
        if self.config.transform_skip_residual_enabled() {
            if !abs_level_gtx {
                return 32;
            }
            if gtx_idx > 0 {
                return 67 + gtx_idx;
            }
            if self.config.bdpcm {
                return 67;
            }
            return 64
                + if x > 0 && self.sig_coeff_at(x - 1, y) {
                    1
                } else {
                    0
                }
                + if y > 0 && self.sig_coeff_at(x, y - 1) {
                    1
                } else {
                    0
                };
        }

        let base = if x == self.config.last_significant_x && y == self.config.last_significant_y {
            if self.config.is_luma() {
                0
            } else {
                21
            }
        } else {
            let stats = self.local_stats(x, y);
            let ctx_offset = stats
                .loc_sum_abs_pass1
                .saturating_sub(stats.loc_num_sig)
                .min(4);
            let d = x + y;
            if self.config.is_luma() {
                1 + ctx_offset
                    + if d == 0 {
                        15
                    } else if d < 3 {
                        10
                    } else if d < 10 {
                        5
                    } else {
                        0
                    }
            } else {
                22 + ctx_offset + if d == 0 { 5 } else { 0 }
            }
        };
        base + if abs_level_gtx && gtx_idx == 1 { 32 } else { 0 }
    }

    fn accumulate_local(&self, x: u8, y: u8, loc_num_sig: &mut u8, loc_sum_abs_pass1: &mut u8) {
        if self.sig_coeff_at(x, y) {
            *loc_num_sig += 1;
        }
        *loc_sum_abs_pass1 = loc_sum_abs_pass1.saturating_add(self.abs_level_pass1_at(x, y));
    }

    pub(in crate::vvc) fn sig_coeff_at(&self, x: u8, y: u8) -> bool {
        self.sig_coeff[self.config.coefficient_index(x, y)]
    }

    pub(in crate::vvc) fn abs_level_pass1_at(&self, x: u8, y: u8) -> u8 {
        self.abs_level_pass1[self.config.coefficient_index(x, y)]
    }

    pub(in crate::vvc) fn coeff_sign_level_at(&self, x: u8, y: u8) -> i8 {
        self.coeff_sign_level[self.config.coefficient_index(x, y)]
    }

    pub(in crate::vvc) fn sb_coded_at(&self, x_s: u8, y_s: u8) -> bool {
        self.sb_coded[self.config.subblock_index(x_s, y_s)]
    }
}

impl VvcResidualCabacSymbolStream {
    #[cfg(test)]
    pub(in crate::vvc) fn from_quantized_luma_dc(
        log2_tb_width: u8,
        log2_tb_height: u8,
        block: super::VvcQuantizedTransformBlock,
    ) -> Self {
        Self::luma_dc_only(
            log2_tb_width,
            log2_tb_height,
            block.abs_remainder,
            block.reconstructed_dc_coeff < 0 && block.abs_remainder != 0,
        )
    }

    #[cfg(test)]
    pub(in crate::vvc) fn luma_dc_only(
        log2_tb_width: u8,
        log2_tb_height: u8,
        abs_level: u8,
        negative: bool,
    ) -> Self {
        let signed_level = if abs_level == 0 {
            0
        } else if negative {
            -(abs_level as i16)
        } else {
            abs_level as i16
        };
        let mut levels = vec![0; (1usize << log2_tb_width) * (1usize << log2_tb_height)];
        levels[0] = signed_level;
        Self::luma_coefficients(log2_tb_width, log2_tb_height, &levels)
    }

    pub(in crate::vvc) fn luma_coefficients(
        log2_tb_width: u8,
        log2_tb_height: u8,
        coeff_levels: &[i16],
    ) -> Self {
        // H.266 7.3.11.11 residual_coding() first codes the last significant
        // coefficient position and then walks earlier scan positions with
        // sig_coeff_flag and level/sign syntax. This subset is intentionally
        // limited to coefficients in the first 4x4 subblock while AC plumbing
        // is being audited; larger scan-position suffix and sb_coded_flag
        // generation remain labelled future work.
        let width = 1usize << log2_tb_width;
        let height = 1usize << log2_tb_height;
        assert_eq!(coeff_levels.len(), width * height);

        let last_index = coeff_levels
            .iter()
            .rposition(|level| *level != 0)
            .unwrap_or(0);
        let last_x = (last_index % width) as u8;
        let last_y = (last_index / width) as u8;
        assert!(
            last_x < 4 && last_y < 4,
            "AC subset currently supports first 4x4 subblock"
        );

        let config =
            VvcResidualCtxConfig::luma_subset(log2_tb_width, log2_tb_height, last_x, last_y);
        let mut pass1_state = VvcResidualPass1State::new(config);
        for (index, level) in coeff_levels
            .iter()
            .copied()
            .enumerate()
            .take(last_index + 1)
        {
            let x = (index % width) as u8;
            let y = (index / width) as u8;
            let abs_level = level.unsigned_abs().min(3) as u8;
            pass1_state.set_pass1_coeff(x, y, abs_level, level < 0);
        }
        pass1_state.set_sb_coded(0, 0, coeff_levels.iter().any(|level| *level != 0));

        let mut symbols = Vec::new();
        Self::append_last_sig_coeff_prefix(&mut symbols, true, log2_tb_width, last_x);
        Self::append_last_sig_coeff_prefix(&mut symbols, false, log2_tb_height, last_y);

        for index in (0..=last_index).rev() {
            let x = (index % width) as u8;
            let y = (index / width) as u8;
            let level = coeff_levels[index];
            let abs_level = level.unsigned_abs().min(u8::MAX as u16) as u8;
            let significant = abs_level != 0;
            if index != last_index {
                symbols.push(VvcResidualCabacSymbol::SigCoeffFlag { x, y, significant });
            }
            if significant {
                Self::append_regular_level_symbols(&mut symbols, x, y, abs_level, level < 0);
            }
        }

        Self {
            config,
            pass1_state,
            symbols,
        }
    }

    fn append_last_sig_coeff_prefix(
        symbols: &mut Vec<VvcResidualCabacSymbol>,
        x_prefix: bool,
        log2_tb_size: u8,
        prefix: u8,
    ) {
        let cmax = (log2_tb_size << 1) - 1;
        assert!(prefix <= cmax);
        for bin_idx in 0..prefix {
            if x_prefix {
                symbols.push(VvcResidualCabacSymbol::LastSigCoeffXPrefix { bin_idx, bin: true });
            } else {
                symbols.push(VvcResidualCabacSymbol::LastSigCoeffYPrefix { bin_idx, bin: true });
            }
        }
        if prefix < cmax {
            if x_prefix {
                symbols.push(VvcResidualCabacSymbol::LastSigCoeffXPrefix {
                    bin_idx: prefix,
                    bin: false,
                });
            } else {
                symbols.push(VvcResidualCabacSymbol::LastSigCoeffYPrefix {
                    bin_idx: prefix,
                    bin: false,
                });
            }
        }
    }

    fn append_regular_level_symbols(
        symbols: &mut Vec<VvcResidualCabacSymbol>,
        x: u8,
        y: u8,
        abs_level: u8,
        negative: bool,
    ) {
        // H.266 7.3.11.11 residual_coding_subblock regular-pass order: gt1,
        // parity, gt2, remainder, then sign. Rice adaptation is kept fixed at
        // zero in this subset until the full state update is added.
        symbols.push(VvcResidualCabacSymbol::AbsLevelGtxFlag {
            x,
            y,
            gtx_idx: 0,
            greater_than: abs_level > 1,
        });
        if abs_level > 1 {
            symbols.push(VvcResidualCabacSymbol::ParLevelFlag {
                x,
                y,
                par_level: (abs_level & 1) != 0,
            });
            symbols.push(VvcResidualCabacSymbol::AbsLevelGtxFlag {
                x,
                y,
                gtx_idx: 1,
                greater_than: abs_level > 3,
            });
            if abs_level > 3 {
                symbols.push(VvcResidualCabacSymbol::AbsRemainder {
                    x,
                    y,
                    value: u32::from((abs_level - 4) >> 1),
                    rice_param: 0,
                });
            }
        }
        symbols.push(VvcResidualCabacSymbol::CoeffSignFlag { x, y, negative });
    }

    pub(in crate::vvc) fn emit(
        &self,
        encoder: &mut VvcResidualCabacEncoder<'_>,
        cabac: &mut VvcCabacEncoder,
    ) {
        debug_assert_eq!(self.config, self.pass1_state.config);
        encoder.emit_default_tool_control_hooks(cabac, &self.pass1_state);
        for symbol in &self.symbols {
            encoder.emit_residual_symbol(cabac, &self.pass1_state, *symbol);
        }
    }
}
