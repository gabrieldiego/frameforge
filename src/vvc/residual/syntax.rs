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
            VvcResidualCabacSymbol::BypassAbsLevel {
                value, rice_param, ..
            } => {
                cabac.encode_rem_abs_ep(value, u32::from(rice_param));
            }
            VvcResidualCabacSymbol::CoeffSignPattern { bits, count } => {
                cabac.encode_bins_ep(bits, u32::from(count));
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

    pub(in crate::vvc) fn emit_default_tool_control_hooks(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        state: &VvcResidualPass1State,
    ) {
        self.emit_transform_skip_flag(
            cabac,
            state.config.component,
            state.config.transform_skip,
            state.config.bdpcm,
        );
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
        bdpcm: bool,
    ) {
        if bdpcm {
            // H.266 7.4.12.11: intra_bdpcm_*_flag=1 infers
            // transform_skip_flag to 1 instead of coding it.
            debug_assert!(transform_skip);
            return;
        }
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

    #[cfg(test)]
    pub(in crate::vvc) fn luma_subset(
        log2_zo_tb_width: u8,
        log2_zo_tb_height: u8,
        last_significant_x: u8,
        last_significant_y: u8,
    ) -> Self {
        Self::subset(
            VvcResidualComponent::Luma,
            log2_zo_tb_width,
            log2_zo_tb_height,
            last_significant_x,
            last_significant_y,
        )
    }

    pub(in crate::vvc) fn subset(
        component: VvcResidualComponent,
        log2_zo_tb_width: u8,
        log2_zo_tb_height: u8,
        last_significant_x: u8,
        last_significant_y: u8,
    ) -> Self {
        debug_assert!((2..=6).contains(&log2_zo_tb_width));
        debug_assert!((2..=6).contains(&log2_zo_tb_height));
        Self {
            component,
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
    BypassAbsLevel {
        x: u8,
        y: u8,
        value: u32,
        rice_param: u8,
    },
    CoeffSignPattern {
        bits: u32,
        count: u8,
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
            sb_coded: vec![false; config.subblock_count()],
        }
    }

    pub(in crate::vvc) fn set_pass1_coeff(&mut self, x: u8, y: u8, abs_level: u8, _negative: bool) {
        let index = self.config.coefficient_index(x, y);
        self.sig_coeff[index] = abs_level != 0;
        // VTM CoeffCodingContext::sigCtxIdAbs uses
        // min(4 + (absLevel & 1), absLevel) for the local template sum and
        // then reuses sumAbs - numPos for the par/gt context offset.
        // Keep that exact template magnitude here instead of an artificial
        // pass-1 clip so AC contexts track H.266 9.3.4.2.8/9.
        self.abs_level_pass1[index] = template_abs_sum_level(abs_level);
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

    pub(in crate::vvc) fn sb_coded_at(&self, x_s: u8, y_s: u8) -> bool {
        self.sb_coded[self.config.subblock_index(x_s, y_s)]
    }
}

impl VvcResidualCabacSymbolStream {
    pub(in crate::vvc) fn luma_coefficients(
        log2_tb_width: u8,
        log2_tb_height: u8,
        coeff_levels: &[i16],
    ) -> Self {
        Self::coefficients(
            VvcResidualComponent::Luma,
            log2_tb_width,
            log2_tb_height,
            coeff_levels,
        )
    }

    pub(in crate::vvc) fn luma_transform_skip_coefficients(
        log2_tb_width: u8,
        log2_tb_height: u8,
        coeff_levels: &[i16],
    ) -> Self {
        Self::coefficients_with_transform_skip(
            VvcResidualComponent::Luma,
            log2_tb_width,
            log2_tb_height,
            coeff_levels,
            true,
        )
    }

    pub(in crate::vvc) fn luma_bdpcm_transform_skip_coefficients(
        log2_tb_width: u8,
        log2_tb_height: u8,
        coeff_levels: &[i16],
    ) -> Self {
        Self::coefficients_with_tool_flags(
            VvcResidualComponent::Luma,
            log2_tb_width,
            log2_tb_height,
            coeff_levels,
            true,
            true,
        )
    }

    pub(in crate::vvc) fn chroma_coefficients(
        component: VvcResidualComponent,
        log2_tb_width: u8,
        log2_tb_height: u8,
        coeff_levels: &[i16],
    ) -> Self {
        debug_assert!(matches!(
            component,
            VvcResidualComponent::ChromaCb | VvcResidualComponent::ChromaCr
        ));
        Self::coefficients(component, log2_tb_width, log2_tb_height, coeff_levels)
    }

    pub(in crate::vvc) fn chroma_transform_skip_coefficients(
        component: VvcResidualComponent,
        log2_tb_width: u8,
        log2_tb_height: u8,
        coeff_levels: &[i16],
    ) -> Self {
        debug_assert!(matches!(
            component,
            VvcResidualComponent::ChromaCb | VvcResidualComponent::ChromaCr
        ));
        Self::coefficients_with_transform_skip(
            component,
            log2_tb_width,
            log2_tb_height,
            coeff_levels,
            true,
        )
    }

    pub(in crate::vvc) fn chroma_bdpcm_transform_skip_coefficients(
        component: VvcResidualComponent,
        log2_tb_width: u8,
        log2_tb_height: u8,
        coeff_levels: &[i16],
    ) -> Self {
        debug_assert!(matches!(
            component,
            VvcResidualComponent::ChromaCb | VvcResidualComponent::ChromaCr
        ));
        Self::coefficients_with_tool_flags(
            component,
            log2_tb_width,
            log2_tb_height,
            coeff_levels,
            true,
            true,
        )
    }

    fn coefficients(
        component: VvcResidualComponent,
        log2_tb_width: u8,
        log2_tb_height: u8,
        coeff_levels: &[i16],
    ) -> Self {
        Self::coefficients_with_transform_skip(
            component,
            log2_tb_width,
            log2_tb_height,
            coeff_levels,
            false,
        )
    }

    fn coefficients_with_transform_skip(
        component: VvcResidualComponent,
        log2_tb_width: u8,
        log2_tb_height: u8,
        coeff_levels: &[i16],
        transform_skip: bool,
    ) -> Self {
        Self::coefficients_with_tool_flags(
            component,
            log2_tb_width,
            log2_tb_height,
            coeff_levels,
            transform_skip,
            false,
        )
    }

    fn coefficients_with_tool_flags(
        component: VvcResidualComponent,
        log2_tb_width: u8,
        log2_tb_height: u8,
        coeff_levels: &[i16],
        transform_skip: bool,
        bdpcm: bool,
    ) -> Self {
        // H.266 7.3.11.11 residual_coding() first codes the last significant
        // coefficient position and then walks earlier scan positions with
        // sig_coeff_flag and level/sign syntax. VTM's CoeffCodingContext uses
        // SCAN_GROUPED_4x4 with diagonal scan (CommonLib/Rom.cpp). This subset
        // is intentionally limited to coefficients in the first 4x4 subblock
        // while larger scan-position suffix and sb_coded_flag generation remain
        // labelled future work.
        //
        // H.266 7.3.11.11 still uses this residual_coding() syntax for
        // transform-skipped TUs when sh_ts_residual_coding_disabled_flag is 1.
        // The 4:4:4 screen-content residual subset relies on that normative
        // switch so transform_skip_flag affects reconstruction without adding
        // residual_codingTS()'s separate sign-context and neighbour-modulated
        // level syntax yet.
        let width = 1usize << log2_tb_width;
        let height = 1usize << log2_tb_height;
        assert_eq!(coeff_levels.len(), width * height);

        let scan = grouped_4x4_diag_scan(width, height);
        let last_scan_pos = scan
            .iter()
            .rposition(|pos| coeff_levels[pos.raster_index] != 0)
            .unwrap_or(0);
        let last_x = scan[last_scan_pos].x as u8;
        let last_y = scan[last_scan_pos].y as u8;
        assert!(
            last_x < 4 && last_y < 4,
            "AC subset currently supports first 4x4 subblock"
        );

        let mut config =
            VvcResidualCtxConfig::subset(component, log2_tb_width, log2_tb_height, last_x, last_y);
        config.transform_skip = transform_skip;
        config.ts_residual_coding_disabled = true;
        config.bdpcm = bdpcm;
        let mut pass1_state = VvcResidualPass1State::new(config);
        for pos in scan.iter().take(last_scan_pos + 1) {
            let level = coeff_levels[pos.raster_index];
            let x = pos.x as u8;
            let y = pos.y as u8;
            let abs_level = level.unsigned_abs().min(u8::MAX as u16) as u8;
            pass1_state.set_pass1_coeff(x, y, abs_level, level < 0);
        }
        pass1_state.set_sb_coded(0, 0, coeff_levels.iter().any(|level| *level != 0));

        let mut symbols = Vec::new();
        Self::append_last_sig_coeff_prefix(&mut symbols, true, log2_tb_width, last_x);
        Self::append_last_sig_coeff_prefix(&mut symbols, false, log2_tb_height, last_y);

        let mut remainder_symbols = Vec::new();
        let mut bypass_symbols = Vec::new();
        let mut sign_bits = 0u32;
        let mut sign_count = 0u8;
        let mut residual_state = 0u8;
        let mut rem_reg_bins = regular_bin_limit(width, height);
        let mut first_pos_2nd_pass: Option<usize> = None;
        let mut next_scan_pos = last_scan_pos as isize;
        let infer_sig_pos = last_scan_pos as isize;
        let mut num_nonzero = 0usize;

        while next_scan_pos >= 0 && rem_reg_bins >= 4 {
            let scan_pos = next_scan_pos as usize;
            let pos = scan[scan_pos];
            let x = pos.x as u8;
            let y = pos.y as u8;
            let level = coeff_levels[pos.raster_index];
            let abs_level = level.unsigned_abs().min(u8::MAX as u16) as u8;
            let significant = abs_level != 0;
            if num_nonzero != 0 || next_scan_pos != infer_sig_pos {
                symbols.push(VvcResidualCabacSymbol::SigCoeffFlag { x, y, significant });
                rem_reg_bins -= 1;
            }
            if significant {
                num_nonzero += 1;
                Self::append_regular_level_symbols(&mut symbols, x, y, abs_level);
                rem_reg_bins -= regular_level_bin_count(abs_level);
                if abs_level > 3 {
                    first_pos_2nd_pass =
                        Some(first_pos_2nd_pass.map_or(scan_pos, |first| first.max(scan_pos)));
                }
                append_sign_bit(&mut sign_bits, &mut sign_count, level < 0);
            }
            residual_state = disabled_dep_quant_state_transition(residual_state, abs_level);
            next_scan_pos -= 1;
        }

        let min_pos_2nd_pass = next_scan_pos;
        if let Some(first_pos_2nd_pass) = first_pos_2nd_pass {
            for scan_pos in ((min_pos_2nd_pass + 1) as usize..=first_pos_2nd_pass).rev() {
                let pos = scan[scan_pos];
                let abs_level = coeff_levels[pos.raster_index]
                    .unsigned_abs()
                    .min(u8::MAX as u16) as u8;
                if abs_level >= 4 {
                    let x = pos.x as u8;
                    let y = pos.y as u8;
                    remainder_symbols.push(VvcResidualCabacSymbol::AbsRemainder {
                        x,
                        y,
                        value: u32::from((abs_level - 4) >> 1),
                        rice_param: derive_rice_param(scan_pos, coeff_levels, width, &scan, 4),
                    });
                }
            }
        }

        if min_pos_2nd_pass >= 0 {
            for scan_pos in (0..=min_pos_2nd_pass as usize).rev() {
                let pos = scan[scan_pos];
                let level = coeff_levels[pos.raster_index];
                let abs_level = level.unsigned_abs().min(u8::MAX as u16) as u8;
                let rice_param = derive_rice_param(scan_pos, coeff_levels, width, &scan, 0);
                let zero_pos = go_rice_zero_position(residual_state, rice_param);
                let rem_value = if abs_level == 0 {
                    zero_pos
                } else if u32::from(abs_level) <= zero_pos {
                    u32::from(abs_level - 1)
                } else {
                    u32::from(abs_level)
                };
                bypass_symbols.push(VvcResidualCabacSymbol::BypassAbsLevel {
                    x: pos.x as u8,
                    y: pos.y as u8,
                    value: rem_value,
                    rice_param,
                });
                residual_state = disabled_dep_quant_state_transition(residual_state, abs_level);
                if abs_level != 0 {
                    append_sign_bit(&mut sign_bits, &mut sign_count, level < 0);
                }
            }
        }
        // H.266 7.3.11.11 / residual_coding_subblock(): Go-Rice remainders
        // are emitted in a second pass after all regular significant/gt/par
        // bins for the subblock. If the regular-bin budget is exhausted, the
        // remaining dec_abs_level values are bypass-coded before the grouped
        // coefficient signs. See VTM CABACWriter::residual_coding_subblock().
        symbols.extend(remainder_symbols);
        symbols.extend(bypass_symbols);
        if sign_count > 0 {
            symbols.push(VvcResidualCabacSymbol::CoeffSignPattern {
                bits: sign_bits,
                count: sign_count,
            });
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
    ) {
        // H.266 7.3.11.11 residual_coding_subblock regular-pass order: gt1,
        // parity, gt2. Remainder and sign bypass bins are collected and
        // emitted after this pass for the whole subblock.
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
        }
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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct VvcScanPosition {
    x: usize,
    y: usize,
    raster_index: usize,
}

fn grouped_4x4_diag_scan(width: usize, height: usize) -> Vec<VvcScanPosition> {
    debug_assert!(width >= 4);
    debug_assert!(height >= 4);
    let group_width = 4;
    let group_height = 4;
    let groups_wide = width / group_width;
    let groups_high = height / group_height;
    let mut scan = Vec::with_capacity(width * height);
    for group in diag_scan_positions(groups_wide, groups_high) {
        let group_x = group.x * group_width;
        let group_y = group.y * group_height;
        for local in diag_scan_positions(group_width, group_height) {
            let x = group_x + local.x;
            let y = group_y + local.y;
            scan.push(VvcScanPosition {
                x,
                y,
                raster_index: y * width + x,
            });
        }
    }
    scan
}

fn diag_scan_positions(width: usize, height: usize) -> Vec<VvcScanPosition> {
    let mut line = 0usize;
    let mut column = 0usize;
    let mut scan = Vec::with_capacity(width * height);
    for _ in 0..(width * height) {
        scan.push(VvcScanPosition {
            x: column,
            y: line,
            raster_index: line * width + column,
        });

        if column == width - 1 || line == 0 {
            line += column + 1;
            column = 0;
            if line >= height {
                column += line - (height - 1);
                line = height - 1;
            }
        } else {
            column += 1;
            line -= 1;
        }
    }
    scan
}

fn template_abs_sum_level(abs_level: u8) -> u8 {
    abs_level.min(4 + (abs_level & 1))
}

fn regular_bin_limit(width: usize, height: usize) -> i32 {
    // H.266 7.3.11.11 residual_coding() initializes remBinsPass1 as
    // ((1 << (Log2ZoTbWidth + Log2ZoTbHeight)) * 7) >> 2. VTM expresses the
    // same value as (TbAreaAfterCoefZeroOut * MAX_TU_LEVEL_CTX_CODED_BIN_*) >>
    // 4; VTM 24.0 sets both luma and chroma constraints to 28.
    ((width * height * 28) >> 4) as i32
}

fn regular_level_bin_count(abs_level: u8) -> i32 {
    if abs_level > 1 {
        3
    } else {
        1
    }
}

fn append_sign_bit(sign_bits: &mut u32, sign_count: &mut u8, negative: bool) {
    if *sign_count != 0 {
        *sign_bits <<= 1;
    }
    *sign_bits |= u32::from(negative);
    *sign_count += 1;
}

fn disabled_dep_quant_state_transition(_state: u8, _abs_level: u8) -> u8 {
    // VTM passes stateTransTable = 0 when dependent quantization is disabled,
    // so the residual state remains zero for both regular and bypass passes.
    0
}

fn derive_rice_param(
    scan_pos: usize,
    coeff_levels: &[i16],
    width: usize,
    scan: &[VvcScanPosition],
    base_level: i16,
) -> u8 {
    const GO_RICE_PARS_COEFF: [u8; 32] = [
        0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 3,
        3, 3,
    ];
    let sum_abs = rice_template_abs_sum(scan_pos, coeff_levels, width, scan);
    let clipped = (sum_abs - 5 * base_level).clamp(0, 31) as usize;
    GO_RICE_PARS_COEFF[clipped]
}

fn rice_template_abs_sum(
    scan_pos: usize,
    coeff_levels: &[i16],
    width: usize,
    scan: &[VvcScanPosition],
) -> i16 {
    let pos = scan[scan_pos];
    let height = coeff_levels.len() / width;
    let x = pos.x;
    let y = pos.y;
    let mut sum = 0i16;
    if x + 1 < width {
        sum += coeff_abs_at(coeff_levels, width, x + 1, y);
        if x + 2 < width {
            sum += coeff_abs_at(coeff_levels, width, x + 2, y);
        }
        if y + 1 < height {
            sum += coeff_abs_at(coeff_levels, width, x + 1, y + 1);
        }
    }
    if y + 1 < height {
        sum += coeff_abs_at(coeff_levels, width, x, y + 1);
        if y + 2 < height {
            sum += coeff_abs_at(coeff_levels, width, x, y + 2);
        }
    }
    sum
}

fn coeff_abs_at(coeff_levels: &[i16], width: usize, x: usize, y: usize) -> i16 {
    coeff_levels[y * width + x].abs()
}

fn go_rice_zero_position(state: u8, rice_param: u8) -> u32 {
    u32::from(if state < 2 { 1u8 } else { 2u8 }) << rice_param
}
