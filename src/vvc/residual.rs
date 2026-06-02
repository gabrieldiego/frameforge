mod quant;
mod recon;
mod syntax;
pub(super) mod transform;

#[cfg(test)]
mod tests;

#[cfg(test)]
pub(super) use transform::quantize_vvc_chroma;
pub(super) use transform::{
    inverse_transform_vvc_luma_dc, quantize_vvc_chroma_sample, quantize_vvc_luma_dc,
    reconstruct_vvc_chroma, reconstruct_vvc_luma_dc_residual_sample, transform_vvc_tu,
    VVC_CHROMA_DC_BASE, VVC_LUMA_DC_BASE,
};

pub use quant::quantize_vvc_color;
pub(super) use quant::quantize_vvc_frame;
#[cfg(test)]
pub(super) use quant::vvc_anchor_luma_tu_size;
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
    pub(super) luma_rem: u8,
    pub(super) luma_ac_levels: [i16; 15],
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
pub(super) struct VvcTransformBlock {
    pub(super) dc_coeff: i16,
    pub(super) ac_coeffs: [i16; 15],
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct VvcQuantizedTransformBlock {
    pub(super) reconstructed_dc_coeff: i16,
    pub(super) reconstructed_ac_coeffs: [i16; 15],
    pub(super) abs_remainder: u8,
    pub(super) ac_tokens: [u8; 15],
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct VvcReconstructedLumaBlock {
    pub(super) samples: [u8; 16],
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
pub(super) const MAX_VVC_LUMA_TUS: usize = 16 * 16;
