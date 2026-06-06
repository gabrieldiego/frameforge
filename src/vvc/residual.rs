mod prediction;
mod quant;
mod recon;
mod syntax;
pub(super) mod transform;

#[cfg(test)]
mod tests;

#[cfg(test)]
pub(super) use transform::quantize_vvc_chroma;
pub(super) use transform::{
    inverse_transform_vvc_chroma_residual_levels, inverse_transform_vvc_luma_residual_levels,
    quantize_vvc_chroma_residual_greedy, quantize_vvc_chroma_sample,
    quantize_vvc_luma_residual_greedy, reconstruct_vvc_chroma, transform_vvc_tu,
    VVC_CHROMA_DC_BASE, VVC_LUMA_DC_BASE,
};

pub(super) use prediction::{
    fill_visible_chroma_node, fill_visible_luma_node, predict_vvc_chroma_dc_block,
    predict_vvc_luma_dc_block,
};
pub use quant::quantize_vvc_color;
pub(super) use quant::quantize_vvc_frame;
pub(super) use recon::reconstruct_vvc_residual_frame;
pub(super) use syntax::{
    VvcResidualCabacEncoder, VvcResidualCabacOptions, VvcResidualCabacSymbolStream,
};
#[cfg(test)]
pub(super) use syntax::{
    VvcResidualCabacSymbol, VvcResidualCtxConfig, VvcResidualLocalStats, VvcResidualPass1State,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct VvcQuantizedColor {
    pub y: u8,
    pub u: u8,
    pub v: u8,
    pub(super) luma_tu_remainders: [u8; MAX_VVC_LUMA_TUS],
    pub(super) luma_tu_negative: [bool; MAX_VVC_LUMA_TUS],
    pub(super) luma_tu_ac_levels: [[i16; VVC_LUMA_AC_COEFFS_PER_TU]; MAX_VVC_LUMA_TUS],
    pub(super) luma_tu_count: usize,
    pub(super) chroma_tu_count: usize,
    pub(super) cb_tu_dc_levels: [i16; MAX_VVC_CHROMA_TUS],
    pub(super) cr_tu_dc_levels: [i16; MAX_VVC_CHROMA_TUS],
    pub(super) cb_tu_ac_levels: [[i16; VVC_CHROMA_AC_COEFFS_PER_TU]; MAX_VVC_CHROMA_TUS],
    pub(super) cr_tu_ac_levels: [[i16; VVC_CHROMA_AC_COEFFS_PER_TU]; MAX_VVC_CHROMA_TUS],
    pub(super) cb_rem: u8,
    pub(super) cr_rem: u8,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum VvcTransformComponent {
    Luma,
    ChromaCb,
    ChromaCr,
}

impl VvcTransformComponent {
    pub(super) const fn dc_base(self) -> i16 {
        match self {
            Self::Luma => VVC_LUMA_DC_BASE,
            Self::ChromaCb | Self::ChromaCr => VVC_CHROMA_DC_BASE,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct VvcTuTransformBlock {
    pub(super) component: VvcTransformComponent,
    pub(super) width: u16,
    pub(super) height: u16,
    pub(super) dc_coeff: i16,
    pub(super) ac_coeffs: Vec<i16>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct VvcQuantizedTransformBlock {
    pub(super) reconstructed_dc_coeff: i16,
    pub(super) reconstructed_ac_coeffs: [i16; 15],
    pub(super) abs_remainder: u8,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum VvcResidualComponent {
    Luma,
    ChromaCb,
    ChromaCr,
}

impl VvcResidualComponent {
    pub(super) const fn transform_skip_ctx_inc(self) -> u8 {
        match self {
            Self::Luma => 0,
            Self::ChromaCb | Self::ChromaCr => 1,
        }
    }
}

pub(super) const VVC_CHROMA_TU_SIZE: usize = 4;
pub(super) const VVC_LUMA_AC_COEFFS_PER_TU: usize = 15;
pub(super) const VVC_CHROMA_AC_COEFFS_PER_TU: usize = 3;
// Current lossy 4:2:0 subset stores only the 2x2 low-frequency chroma AC
// positions. H.266 7.3.11.10 still codes them in their normal 4x4 transform
// coordinates; reconstruction and CABAC expand these slots back to (x,y).
pub(super) const VVC_CHROMA_AC_POSITIONS_2X2: [(usize, usize); VVC_CHROMA_AC_COEFFS_PER_TU] =
    [(1, 0), (0, 1), (1, 1)];
pub(super) const MAX_VVC_LUMA_TUS: usize = 16 * 16;
pub(super) const MAX_VVC_CHROMA_TUS: usize = MAX_VVC_LUMA_TUS;
