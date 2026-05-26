pub(super) mod transform;

#[cfg(test)]
pub(super) use transform::quantize_vvc_4x4_chroma;
pub(super) use transform::{
    inverse_transform_vvc_4x4_luma_dc, quantize_vvc_4x4_chroma_sample, quantize_vvc_4x4_luma_dc,
    reconstruct_vvc_4x4_chroma, transform_vvc_4x4_luma, VVC_LUMA_DC_BASE,
};

use super::{
    Vvc4x4SampledColor, Vvc4x4SampledFrame, VvcCabacContext, VvcCabacContexts, VvcCabacEncoder,
    VvcLastSigCoeffPrefixCtxInput, VvcVideoGeometry,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Vvc4x4QuantizedColor {
    pub y: u8,
    pub u: u8,
    pub v: u8,
    pub(super) luma_rem: u8,
    pub(super) luma_ac_tokens: [u8; 15],
    pub(super) second_luma_rem: u8,
    pub(super) second_luma_ac_tokens: [u8; 15],
    pub(super) luma_tu_remainders: [u8; MAX_VVC_LUMA_TUS],
    pub(super) luma_tu_ac0_tokens: [u8; MAX_VVC_LUMA_TUS],
    pub(super) luma_tu_count: usize,
    pub(super) cb_rem: u8,
    pub(super) cr_rem: u8,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct Vvc4x4TransformBlock {
    pub(super) dc_coeff: i16,
    pub(super) ac_coeffs: [i16; 15],
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct Vvc4x4QuantizedTransformBlock {
    pub(super) reconstructed_dc_coeff: i16,
    pub(super) reconstructed_ac_coeffs: [i16; 15],
    pub(super) abs_remainder: u8,
    pub(super) ac_tokens: [u8; 15],
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct Vvc4x4ReconstructedLumaBlock {
    pub(super) samples: [u8; 16],
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[allow(dead_code)]
pub(super) enum VvcResidualComponent {
    Luma,
    ChromaCb,
    ChromaCr,
}

pub fn quantize_vvc_4x4_color(color: Vvc4x4SampledColor) -> Vvc4x4QuantizedColor {
    quantize_vvc_4x4_frame(Vvc4x4SampledFrame::solid(color))
}

pub(super) fn quantize_vvc_4x4_frame(frame: Vvc4x4SampledFrame) -> Vvc4x4QuantizedColor {
    let quantized_luma_tus = quantize_vvc_4x4_luma_tus(&frame);
    let quantized_luma = quantized_luma_tus[0];
    let reconstructed_luma = inverse_transform_vvc_4x4_luma_dc(quantized_luma);
    let second_luma = quantized_luma_tus.get(1).copied();
    let color = frame.sampled_color();
    let cb_rem = quantize_vvc_4x4_chroma_sample(color.u);
    let cr_rem = quantize_vvc_4x4_chroma_sample(color.v);
    let reconstructed_cb = reconstruct_vvc_4x4_chroma(cb_rem);
    let reconstructed_cr = reconstruct_vvc_4x4_chroma(cr_rem);
    let mut luma_tu_remainders = [quantized_luma.abs_remainder; MAX_VVC_LUMA_TUS];
    let mut luma_tu_ac0_tokens = [quantized_luma.ac_tokens[0]; MAX_VVC_LUMA_TUS];
    for (index, quantized) in quantized_luma_tus.iter().enumerate() {
        luma_tu_remainders[index] = quantized.abs_remainder;
        luma_tu_ac0_tokens[index] = quantized.ac_tokens[0];
    }
    Vvc4x4QuantizedColor {
        y: reconstructed_luma.samples[0],
        u: reconstructed_cb,
        v: reconstructed_cr,
        luma_rem: quantized_luma.abs_remainder,
        luma_ac_tokens: quantized_luma.ac_tokens,
        second_luma_rem: second_luma
            .map(|block| block.abs_remainder)
            .unwrap_or(quantized_luma.abs_remainder),
        second_luma_ac_tokens: second_luma
            .map(|block| block.ac_tokens)
            .unwrap_or(quantized_luma.ac_tokens),
        luma_tu_remainders,
        luma_tu_ac0_tokens,
        luma_tu_count: quantized_luma_tus.len(),
        cb_rem,
        cr_rem,
    }
}

fn quantize_vvc_4x4_luma_tus(frame: &Vvc4x4SampledFrame) -> Vec<Vvc4x4QuantizedTransformBlock> {
    luma_tu_origins(frame.geometry)
        .into_iter()
        .map(|(x, y)| {
            let block = residual_luma_block_at(frame, x, y);
            let transform = transform_vvc_4x4_luma(block);
            quantize_vvc_4x4_luma_dc(transform)
        })
        .collect()
}

fn luma_tu_origins(geometry: VvcVideoGeometry) -> Vec<(usize, usize)> {
    let mut origins = Vec::new();
    for y in (0..geometry.height).step_by(VVC_RESIDUAL_CB_SIZE) {
        for x in (0..geometry.width).step_by(VVC_RESIDUAL_CB_SIZE) {
            origins.push((x, y));
        }
    }
    origins
}

#[cfg(test)]
pub(super) fn first_residual_luma_block(
    frame: &Vvc4x4SampledFrame,
) -> [u8; VVC_RESIDUAL_LUMA_SAMPLES] {
    residual_luma_block_at(frame, 0, 0)
}

#[cfg(test)]
pub(super) fn second_residual_luma_block(
    frame: &Vvc4x4SampledFrame,
) -> Option<[u8; VVC_RESIDUAL_LUMA_SAMPLES]> {
    luma_tu_origins(frame.geometry)
        .get(1)
        .map(|(x, y)| residual_luma_block_at(frame, *x, *y))
}

fn residual_luma_block_at(
    frame: &Vvc4x4SampledFrame,
    origin_x: usize,
    origin_y: usize,
) -> [u8; VVC_RESIDUAL_LUMA_SAMPLES] {
    let mut block = [0; VVC_RESIDUAL_LUMA_SAMPLES];
    let cb_width = VVC_RESIDUAL_CB_SIZE.min(frame.geometry.width - origin_x);
    let cb_height = VVC_RESIDUAL_CB_SIZE.min(frame.geometry.height - origin_y);
    for y in 0..cb_height {
        let src = (origin_y + y) * frame.geometry.width + origin_x;
        let dst = y * VVC_RESIDUAL_CB_SIZE;
        block[dst..dst + cb_width].copy_from_slice(&frame.luma[src..src + cb_width]);
    }
    block
}

pub(super) const VVC_RESIDUAL_CB_SIZE: usize = 4;
pub(super) const VVC_RESIDUAL_LUMA_SAMPLES: usize = VVC_RESIDUAL_CB_SIZE * VVC_RESIDUAL_CB_SIZE;
pub(super) const MAX_VVC_LUMA_TUS: usize = 16 * 16;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[allow(dead_code)]
pub(super) struct VvcResidualCabacOptions {
    pub(super) transform_skip_enabled: bool,
    pub(super) explicit_mts_intra_enabled: bool,
    pub(super) dependent_quantization_enabled: bool,
    pub(super) sign_data_hiding_enabled: bool,
    pub(super) lfnst_enabled: bool,
    pub(super) sbt_enabled: bool,
}

#[allow(dead_code)]
impl VvcResidualCabacOptions {
    pub(super) fn current_intra_subset() -> Self {
        Self {
            // Keep disabled syntax paths labelled. The current parameter sets
            // infer transform_skip_flag=0 and mts_idx=0 in most paths, but the
            // encoder can switch these on once the surrounding CU syntax is
            // fully spec-generated.
            transform_skip_enabled: false,
            explicit_mts_intra_enabled: false,
            dependent_quantization_enabled: false,
            sign_data_hiding_enabled: false,
            lfnst_enabled: false,
            sbt_enabled: false,
        }
    }
}

#[allow(dead_code)]
pub(super) struct VvcResidualCabacEncoder<'a> {
    contexts: &'a mut VvcCabacContexts,
    options: VvcResidualCabacOptions,
}

#[allow(dead_code)]
impl<'a> VvcResidualCabacEncoder<'a> {
    pub(super) fn new(
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

    pub(super) fn emit_last_sig_coeff_prefixes_4x4(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        component: VvcResidualComponent,
        last_x: u8,
        last_y: u8,
    ) {
        // For a 4x4 TB, Log2ZoTbWidth/Height are 2 and prefix values 0..3
        // represent coordinates directly. Larger TBs need the suffix mapping
        // from residual_coding() before this helper can be generalized.
        debug_assert!(last_x < 4);
        debug_assert!(last_y < 4);
        self.emit_last_sig_coeff_prefix(cabac, component, true, 2, last_x);
        self.emit_last_sig_coeff_prefix(cabac, component, false, 2, last_y);
    }

    fn emit_last_sig_coeff_prefix(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        component: VvcResidualComponent,
        x_prefix: bool,
        log2_tb_size: u8,
        prefix: u8,
    ) {
        let cmax = (log2_tb_size << 1) - 1;
        debug_assert!(prefix <= cmax);
        for bin_idx in 0..prefix {
            self.emit_last_sig_coeff_prefix_bin(
                cabac,
                component,
                x_prefix,
                log2_tb_size,
                bin_idx,
                true,
            );
        }
        if prefix < cmax {
            self.emit_last_sig_coeff_prefix_bin(
                cabac,
                component,
                x_prefix,
                log2_tb_size,
                prefix,
                false,
            );
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

    pub(super) fn emit_sb_coded_flag(
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

    pub(super) fn emit_sig_coeff_flag(
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

    pub(super) fn emit_par_level_flag(
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

    pub(super) fn emit_abs_level_gtx_flag(
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

    pub(super) fn emit_coeff_sign_flag(
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

    pub(super) fn emit_transform_skip_flag(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        component: VvcResidualComponent,
        transform_skip: bool,
    ) {
        if !self.options.transform_skip_enabled {
            debug_assert!(!transform_skip);
            return;
        }

        let ctx_inc = match component {
            VvcResidualComponent::Luma => 0,
            VvcResidualComponent::ChromaCb | VvcResidualComponent::ChromaCr => 1,
        };
        self.contexts.encode(
            cabac,
            VvcCabacContext::TransformSkipFlag(ctx_inc),
            transform_skip,
        );
    }

    pub(super) fn emit_mts_idx_zero(&mut self, cabac: &mut VvcCabacEncoder) {
        if !self.options.explicit_mts_intra_enabled {
            return;
        }

        // Table 132 maps mts_idx binIdx 0..3 to ctxInc 0..3. For mts_idx=0
        // under TR(cMax=4,cRiceParam=0), only the first zero bin is emitted.
        // Future non-zero MTS indices should extend this with the remaining
        // truncated-Rice bins instead of bypassing this helper.
        self.contexts
            .encode(cabac, VvcCabacContext::MtsIdx(0), false);
    }

    pub(super) fn emit_current_unused_tool_placeholders(&self) {
        // These labels are intentionally kept next to the residual encoder so
        // later work can wire the corresponding syntax without re-auditing the
        // current subset assumptions.
        let _dependent_quantization_path_enabled = self.options.dependent_quantization_enabled;
        let _sign_data_hiding_path_enabled = self.options.sign_data_hiding_enabled;
        let _lfnst_path_enabled = self.options.lfnst_enabled;
        let _sbt_path_enabled = self.options.sbt_enabled;
    }
}

impl VvcLastSigCoeffPrefixCtxInput {
    pub(super) fn ctx_inc(self) -> u8 {
        // VVC 9.3.4.2.4 derives ctxInc for last_sig_coeff_x_prefix and
        // last_sig_coeff_y_prefix from binIdx, component, and transform block
        // size. See docs/vvc-cabac-subset.md.
        if self.is_luma {
            const OFFSET_Y: [u8; 6] = [0, 0, 3, 6, 10, 15];
            let offset = OFFSET_Y[(self.log2_tb_size - 1) as usize];
            let shift = (self.log2_tb_size + 1) >> 2;
            (self.bin_idx >> shift) + offset
        } else {
            let shift = ((2 * self.log2_tb_size) >> 3).min(2);
            (self.bin_idx >> shift) + 20
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[allow(dead_code)]
pub(super) struct VvcResidualCtxConfig {
    pub(super) component: VvcResidualComponent,
    pub(super) log2_zo_tb_width: u8,
    pub(super) log2_zo_tb_height: u8,
    pub(super) q_state: u8,
    pub(super) transform_skip: bool,
    pub(super) ts_residual_coding_disabled: bool,
    pub(super) bdpcm: bool,
    pub(super) last_significant_x: u8,
    pub(super) last_significant_y: u8,
}

#[allow(dead_code)]
impl VvcResidualCtxConfig {
    pub(super) fn luma_4x4_subset(last_significant_x: u8, last_significant_y: u8) -> Self {
        Self {
            component: VvcResidualComponent::Luma,
            log2_zo_tb_width: 2,
            log2_zo_tb_height: 2,
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
}

#[derive(Debug, Clone, PartialEq, Eq)]
#[allow(dead_code)]
pub(super) struct VvcResidualPass1State {
    pub(super) config: VvcResidualCtxConfig,
    pub(super) sig_coeff: Vec<bool>,
    pub(super) abs_level_pass1: Vec<u8>,
    pub(super) coeff_sign_level: Vec<i8>,
    pub(super) sb_coded: Vec<bool>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[allow(dead_code)]
pub(super) struct VvcResidualLocalStats {
    pub(super) loc_num_sig: u8,
    pub(super) loc_sum_abs_pass1: u8,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[allow(dead_code)]
pub(super) enum VvcResidualCabacSymbol {
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
#[allow(dead_code)]
pub(super) struct VvcResidualCabacSymbolStream {
    pub(super) config: VvcResidualCtxConfig,
    pub(super) pass1_state: VvcResidualPass1State,
    pub(super) symbols: Vec<VvcResidualCabacSymbol>,
}

#[allow(dead_code)]
impl VvcResidualPass1State {
    pub(super) fn new(config: VvcResidualCtxConfig) -> Self {
        Self {
            config,
            sig_coeff: vec![false; config.coefficient_count()],
            abs_level_pass1: vec![0; config.coefficient_count()],
            coeff_sign_level: vec![0; config.coefficient_count()],
            sb_coded: vec![false; config.subblock_count()],
        }
    }

    pub(super) fn set_pass1_coeff(&mut self, x: u8, y: u8, abs_level_pass1: u8, negative: bool) {
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

    pub(super) fn set_sb_coded(&mut self, x_s: u8, y_s: u8, coded: bool) {
        let index = self.config.subblock_index(x_s, y_s);
        self.sb_coded[index] = coded;
    }

    pub(super) fn sb_coded_flag_ctx_inc(&self, x_s: u8, y_s: u8) -> u8 {
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

    pub(super) fn sig_coeff_flag_ctx_inc(&self, x: u8, y: u8) -> u8 {
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

    pub(super) fn par_level_flag_ctx_inc(&self, x: u8, y: u8) -> u8 {
        self.par_or_abs_level_ctx_inc(x, y, false, 0)
    }

    pub(super) fn abs_level_gtx_flag_ctx_inc(&self, x: u8, y: u8, gtx_idx: u8) -> u8 {
        self.par_or_abs_level_ctx_inc(x, y, true, gtx_idx)
    }

    pub(super) fn coeff_sign_flag_ts_ctx_inc(&self, x: u8, y: u8) -> u8 {
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

    pub(super) fn local_stats(&self, x: u8, y: u8) -> VvcResidualLocalStats {
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

    pub(super) fn sig_coeff_at(&self, x: u8, y: u8) -> bool {
        self.sig_coeff[self.config.coefficient_index(x, y)]
    }

    pub(super) fn abs_level_pass1_at(&self, x: u8, y: u8) -> u8 {
        self.abs_level_pass1[self.config.coefficient_index(x, y)]
    }

    pub(super) fn coeff_sign_level_at(&self, x: u8, y: u8) -> i8 {
        self.coeff_sign_level[self.config.coefficient_index(x, y)]
    }

    pub(super) fn sb_coded_at(&self, x_s: u8, y_s: u8) -> bool {
        self.sb_coded[self.config.subblock_index(x_s, y_s)]
    }
}

#[allow(dead_code)]
impl VvcResidualCabacSymbolStream {
    pub(super) fn from_quantized_luma_4x4_dc(block: Vvc4x4QuantizedTransformBlock) -> Self {
        Self::luma_4x4_dc_only(
            block.abs_remainder,
            block.reconstructed_dc_coeff < 0 && block.abs_remainder != 0,
        )
    }

    pub(super) fn luma_4x4_dc_only(abs_level: u8, negative: bool) -> Self {
        Self::luma_dc_only(2, 2, abs_level, negative)
    }

    pub(super) fn luma_dc_only(
        log2_tb_width: u8,
        log2_tb_height: u8,
        abs_level: u8,
        negative: bool,
    ) -> Self {
        // This is the first generated residual subset: one luma TU with only
        // the DC coefficient significant. AC coefficient scan syntax should
        // extend this stream from syntax decisions.
        let config = VvcResidualCtxConfig::luma_subset(log2_tb_width, log2_tb_height, 0, 0);
        let mut pass1_state = VvcResidualPass1State::new(config);
        pass1_state.set_sb_coded(0, 0, abs_level != 0);
        pass1_state.set_pass1_coeff(0, 0, abs_level.min(3), negative);

        let mut symbols = vec![
            VvcResidualCabacSymbol::LastSigCoeffXPrefix {
                bin_idx: 0,
                bin: false,
            },
            VvcResidualCabacSymbol::LastSigCoeffYPrefix {
                bin_idx: 0,
                bin: false,
            },
        ];

        if abs_level != 0 {
            // VVC residual_coding_subblock infers sig_coeff_flag for the sole
            // DC coefficient when last_sig_coeff points to scan position zero.
            // The regular-pass level order is gt1, parity, gt2, then remainder.
            symbols.push(VvcResidualCabacSymbol::AbsLevelGtxFlag {
                x: 0,
                y: 0,
                gtx_idx: 0,
                greater_than: abs_level > 1,
            });
            if abs_level > 1 {
                symbols.push(VvcResidualCabacSymbol::ParLevelFlag {
                    x: 0,
                    y: 0,
                    par_level: (abs_level & 1) != 0,
                });
                symbols.push(VvcResidualCabacSymbol::AbsLevelGtxFlag {
                    x: 0,
                    y: 0,
                    gtx_idx: 1,
                    greater_than: abs_level > 3,
                });
                if abs_level > 3 {
                    symbols.push(VvcResidualCabacSymbol::AbsRemainder {
                        x: 0,
                        y: 0,
                        value: u32::from((abs_level - 4) >> 1),
                        rice_param: 0,
                    });
                }
            }
            symbols.push(VvcResidualCabacSymbol::CoeffSignFlag {
                x: 0,
                y: 0,
                negative,
            });
        }

        Self {
            config,
            pass1_state,
            symbols,
        }
    }

    pub(super) fn emit(
        &self,
        encoder: &mut VvcResidualCabacEncoder<'_>,
        cabac: &mut VvcCabacEncoder,
    ) {
        debug_assert_eq!(self.config, self.pass1_state.config);
        for symbol in &self.symbols {
            encoder.emit_residual_symbol(cabac, &self.pass1_state, *symbol);
        }
    }
}

#[allow(dead_code)]
impl VvcResidualCtxConfig {
    pub(super) fn luma_subset(
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
