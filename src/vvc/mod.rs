//! First-target VVC/H.266 syntax experiments.
//!
//! This module contains a clean-room VVC path for small all-intra validation
//! streams across parameterized geometries. It is still intentionally
//! incomplete: CABAC, CTU syntax generation, transform/quant, prediction, and
//! reconstruction semantics need to keep converging toward real implementations
//! before FrameForge can encode arbitrary input pictures.

use crate::picture::{ChromaSampling, Picture, PixelFormat, SampleBitDepth};

mod cabac;
mod nal;
mod palette;
mod residual;
mod syntax;
use cabac::{VvcCabacDumpContextEvent, VvcCabacDumpSymbol, VvcCabacEncoder, VvcCtxEvent};
pub use nal::{
    nal_unit_header_bytes, parse_annex_b_nal_units, write_annex_b, write_nal_unit_header,
    VvcNalHeader, VvcNalInfo, VvcNalUnit, VvcNalUnitType,
};
use palette::vvc_palette_444_annex_b;
pub use palette::vvc_palette_444_cabac_dump_json;
#[cfg(test)]
use palette::{
    vvc_palette_444_binarized_syntax_bits, vvc_palette_444_cu_syntax,
    vvc_palette_444_decode_reconstruction, vvc_palette_444_single_entry_syntax,
    vvc_palette_444_syntax_tokens, VvcPalettePredictorMode, VvcPaletteTreeType,
};
pub use residual::quantize_vvc_4x4_color;
#[cfg(test)]
use residual::{
    inverse_transform_vvc_4x4_luma_dc, quantize_vvc_4x4_chroma, quantize_vvc_4x4_chroma_sample,
    quantize_vvc_4x4_luma_dc, reconstruct_vvc_4x4_chroma, transform_vvc_tu,
    Vvc4x4QuantizedTransformBlock, Vvc4x4ReconstructedLumaBlock, Vvc4x4TransformBlock,
    VvcResidualCabacSymbol, VvcResidualComponent, VvcResidualCtxConfig, VvcResidualLocalStats,
    VvcResidualPass1State, VvcTransformComponent, VvcTuTransformBlock, MAX_VVC_LUMA_TUS,
};
use residual::{
    quantize_vvc_4x4_frame, Vvc4x4QuantizedColor, VvcResidualCabacEncoder, VvcResidualCabacOptions,
    VvcResidualCabacSymbolStream, VVC_LUMA_DC_BASE,
};
pub use syntax::{VvcSyntaxCode, VvcSyntaxField, VvcSyntaxRbsp, VvcSyntaxWriter};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VvcProfileTarget {
    MinimalVvcAllIntra,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct VvcSubset {
    pub all_intra: bool,
    pub single_picture: bool,
    pub one_tile: bool,
    pub one_slice: bool,
}

impl Default for VvcSubset {
    fn default() -> Self {
        Self {
            all_intra: true,
            single_picture: true,
            one_tile: true,
            one_slice: true,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct VvcEncodeParams {
    pub frames: usize,
}

/// Luma coded-picture dimensions are rounded to this granularity before SPS/PPS
/// signaling and crop-offset derivation.
///
/// This is a deliberately narrow property of the current VVC validation path,
/// not a claim about all legal VVC profiles or future FrameForge codec paths.
pub const VVC_CODED_DIMENSION_GRANULARITY: usize = 8;
const VVC_CTU_SIZE: usize = 64;
const VVC_MIN_CODING_BLOCK_SIZE: u16 = 4;
const VVC_MAX_TB_SIZEY: u16 = 64;
const VVC_CURRENT_MAX_LUMA_LEAF_SIZE: u16 = 8;
const VVC_CURRENT_MAX_LUMA_LEAF_HEIGHT: u16 = VVC_CURRENT_MAX_LUMA_LEAF_SIZE;
const VVC_CURRENT_MAX_LUMA_BOUNDARY_BT_SIZE: u16 = VVC_CURRENT_MAX_LUMA_LEAF_SIZE * 4;
const VVC_CURRENT_DUAL_TREE_CHROMA_LUMA_CU_SIZE: u16 = 32;
const VVC_CURRENT_MIN_LUMA_QT_SIZE: u16 = 8;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct VvcVideoGeometry {
    pub width: usize,
    pub height: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct VvcCodedGeometry {
    width: usize,
    height: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct VvcVideoLimits {
    pub max_width: usize,
    pub max_height: usize,
}

impl VvcVideoLimits {
    pub const fn max_64x64() -> Self {
        Self {
            max_width: 64,
            max_height: 64,
        }
    }
}

impl VvcVideoGeometry {
    pub const fn four_by_four() -> Self {
        Self {
            width: 4,
            height: 4,
        }
    }

    pub fn validate_against(self, limits: VvcVideoLimits) -> Result<(), String> {
        self.validate_shape()?;
        if self.width > limits.max_width || self.height > limits.max_height {
            return Err(format!(
                "VVC geometry supports at most {}x{} visible pictures at this entry point; got {}x{}",
                limits.max_width, limits.max_height, self.width, self.height
            ));
        }
        Ok(())
    }

    fn validate_shape(self) -> Result<(), String> {
        if self.width == 0 || self.height == 0 {
            return Err("VVC geometry expects non-zero width and height".to_string());
        }
        if !self.width.is_multiple_of(2) || !self.height.is_multiple_of(2) {
            return Err(format!(
                "VVC geometry currently requires even dimensions for the emitted 4:2:0 stream; got {}x{}",
                self.width, self.height
            ));
        }
        Ok(())
    }

    fn luma_samples(self) -> usize {
        self.width * self.height
    }

    fn coded_width(self) -> usize {
        self.coded().width
    }

    fn coded_height(self) -> usize {
        self.coded().height
    }

    fn coded(self) -> VvcCodedGeometry {
        VvcCodedGeometry {
            width: coded_canvas_dimension(self.width),
            height: coded_canvas_dimension(self.height),
        }
    }

    fn crop_right(self, chroma_sampling: ChromaSampling) -> u32 {
        ((self.coded_width() - self.width) / chroma_subsample_x(chroma_sampling)) as u32
    }

    fn crop_bottom(self, chroma_sampling: ChromaSampling) -> u32 {
        ((self.coded_height() - self.height) / chroma_subsample_y(chroma_sampling)) as u32
    }
}

fn chroma_subsample_x(chroma_sampling: ChromaSampling) -> usize {
    match chroma_sampling {
        ChromaSampling::Monochrome => 1,
        ChromaSampling::Cs420 | ChromaSampling::Cs422 => 2,
        ChromaSampling::Cs444 => 1,
    }
}

fn chroma_subsample_y(chroma_sampling: ChromaSampling) -> usize {
    match chroma_sampling {
        ChromaSampling::Monochrome => 1,
        ChromaSampling::Cs420 => 2,
        ChromaSampling::Cs422 | ChromaSampling::Cs444 => 1,
    }
}

fn coded_canvas_dimension(value: usize) -> usize {
    value.div_ceil(VVC_CODED_DIMENSION_GRANULARITY) * VVC_CODED_DIMENSION_GRANULARITY
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Vvc4x4SampledColor {
    pub y: u8,
    pub u: u8,
    pub v: u8,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct Vvc4x4SampledFrame {
    geometry: VvcVideoGeometry,
    format: Vvc4x4PictureFormat,
    luma: Vec<u8>,
    cb: Vec<u8>,
    cr: Vec<u8>,
    chroma_len: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Vvc4x4PictureFormat {
    chroma_sampling: ChromaSampling,
    bit_depth: SampleBitDepth,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct VvcCodingTreeConfig {
    chroma_sampling: ChromaSampling,
}

impl VvcCodingTreeConfig {
    const fn yuv420() -> Self {
        Self {
            chroma_sampling: ChromaSampling::Cs420,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct VvcSyntaxToolFlags {
    transform_skip_enabled: bool,
    mts_enabled: bool,
    explicit_mts_intra_enabled: bool,
    lfnst_enabled: bool,
    mrl_enabled: bool,
    cclm_enabled: bool,
    dependent_quantization_enabled: bool,
    sign_data_hiding_enabled: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct VvcSliceSyntaxConfig {
    coding_tree: VvcCodingTreeConfig,
    palette_enabled: bool,
    tools: VvcSyntaxToolFlags,
}

impl VvcSyntaxToolFlags {
    const fn from_slice_features(config: VvcCodingTreeConfig, palette_enabled: bool) -> Self {
        Self {
            transform_skip_enabled: false,
            mts_enabled: false,
            explicit_mts_intra_enabled: false,
            lfnst_enabled: false,
            mrl_enabled: !palette_enabled,
            cclm_enabled: !palette_enabled
                && !matches!(config.chroma_sampling, ChromaSampling::Monochrome),
            dependent_quantization_enabled: false,
            sign_data_hiding_enabled: false,
        }
    }
}

impl VvcSliceSyntaxConfig {
    const fn new(coding_tree: VvcCodingTreeConfig, palette_enabled: bool) -> Self {
        Self {
            coding_tree,
            palette_enabled,
            tools: VvcSyntaxToolFlags::from_slice_features(coding_tree, palette_enabled),
        }
    }

    const fn yuv420_residual() -> Self {
        Self::new(VvcCodingTreeConfig::yuv420(), false)
    }

    const fn palette_444() -> Self {
        Self::new(
            VvcCodingTreeConfig {
                chroma_sampling: ChromaSampling::Cs444,
            },
            true,
        )
    }

    const fn residual_options(self) -> VvcResidualCabacOptions {
        VvcResidualCabacOptions {
            transform_skip_enabled: self.tools.transform_skip_enabled,
            explicit_mts_intra_enabled: self.tools.explicit_mts_intra_enabled,
            dependent_quantization_enabled: self.tools.dependent_quantization_enabled,
            sign_data_hiding_enabled: self.tools.sign_data_hiding_enabled,
            lfnst_enabled: self.tools.lfnst_enabled,
            sbt_enabled: false,
        }
    }
}

impl Vvc4x4SampledFrame {
    fn solid(color: Vvc4x4SampledColor) -> Self {
        Self {
            geometry: VvcVideoGeometry {
                width: 8,
                height: 8,
            },
            format: Vvc4x4PictureFormat {
                chroma_sampling: ChromaSampling::Cs420,
                bit_depth: SampleBitDepth::Eight,
            },
            luma: vec![color.y; 64],
            cb: vec![color.u; 16],
            cr: vec![color.v; 16],
            chroma_len: 16,
        }
    }

    fn sampled_color(&self) -> Vvc4x4SampledColor {
        Vvc4x4SampledColor {
            y: self.luma[0],
            u: self.cb[0],
            v: self.cr[0],
        }
    }

    fn decoder_compat_frame(self) -> Self {
        let color = self.sampled_color();
        let chroma_len = self.geometry.luma_samples() / 4;
        Self {
            geometry: self.geometry,
            format: Vvc4x4PictureFormat {
                chroma_sampling: ChromaSampling::Cs420,
                bit_depth: SampleBitDepth::Eight,
            },
            luma: self.luma,
            cb: vec![color.u; chroma_len],
            cr: vec![color.v; chroma_len],
            chroma_len,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Vvc4x4PictureKind {
    Idr,
    Cra,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct VvcCtuPartitionParams {
    root_width: usize,
    root_height: usize,
    visible_width: usize,
    visible_height: usize,
    chroma_sampling: ChromaSampling,
    chroma_tu_count: usize,
    luma_dc_abs_level: u8,
    luma_dc_negative: bool,
    cb_dc_abs_level: u8,
    cb_dc_negative: bool,
}

impl VvcCtuPartitionParams {
    fn chroma_subsample_x(self) -> u16 {
        chroma_subsample_x(self.chroma_sampling) as u16
    }

    fn chroma_subsample_y(self) -> u16 {
        chroma_subsample_y(self.chroma_sampling) as u16
    }

    fn visible_chroma_width(self) -> u16 {
        (self.visible_width / chroma_subsample_x(self.chroma_sampling)) as u16
    }

    fn visible_chroma_height(self) -> u16 {
        (self.visible_height / chroma_subsample_y(self.chroma_sampling)) as u16
    }

    fn current_chroma_tree_nodes(self) -> Vec<VvcCodingTreeNode> {
        if self.chroma_sampling == ChromaSampling::Monochrome {
            return Vec::new();
        }

        let mut nodes = Vec::new();
        let visible_width = self.visible_chroma_width();
        let visible_height = self.visible_chroma_height();
        let step = VVC_CURRENT_DUAL_TREE_CHROMA_LUMA_CU_SIZE;
        for luma_y in (0..self.root_height as u16).step_by(step as usize) {
            for luma_x in (0..self.root_width as u16).step_by(step as usize) {
                let node = self.chroma_tree_node_from_luma_region(luma_x, luma_y, step, step);
                if node.intersects_visible(visible_width, visible_height) {
                    nodes.push(node);
                }
            }
        }
        nodes
    }

    fn chroma_tree_node_from_luma_region(
        self,
        luma_x: u16,
        luma_y: u16,
        luma_width: u16,
        luma_height: u16,
    ) -> VvcCodingTreeNode {
        let sx = self.chroma_subsample_x();
        let sy = self.chroma_subsample_y();
        debug_assert_eq!(luma_x % sx, 0);
        debug_assert_eq!(luma_y % sy, 0);
        debug_assert_eq!(luma_width % sx, 0);
        debug_assert_eq!(luma_height % sy, 0);
        VvcCodingTreeNode {
            x: luma_x / sx,
            y: luma_y / sy,
            width: luma_width / sx,
            height: luma_height / sy,
            cqt_depth: 1,
            mtt_depth: 0,
            implicit_mtt_depth: 0,
            tree_type: VvcTreeType::DualTreeChroma,
            split_history: [VvcPartSplit::Quad, VvcPartSplit::None],
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum VvcCodingTreeStep {
    LumaTransformUnit {
        width: usize,
        height: usize,
    },
    ChromaTransformUnit {
        x: usize,
        y: usize,
        cb_coded: bool,
        cr_coded: bool,
    },
}

#[cfg(test)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum VvcLumaPartitionStep {
    QuadSplit {
        x: usize,
        y: usize,
        width: usize,
        height: usize,
    },
    Leaf {
        x: usize,
        y: usize,
        width: usize,
        height: usize,
    },
}

pub fn eos_annex_b() -> Vec<u8> {
    write_annex_b(&[VvcNalUnit::eos()]).expect("hard-coded EOS NAL should be valid")
}

pub fn vvc_black_yuv420p8_annex_b(params: VvcEncodeParams) -> Result<Vec<u8>, String> {
    validate_vvc_frame_count(params)?;
    vvc_yuv420p8_annex_b(
        params,
        Vvc4x4SampledFrame::solid(Vvc4x4SampledColor { y: 0, u: 0, v: 0 }),
    )
}

pub fn vvc_yuv420p8_annex_b_from_input(
    input: &[u8],
    params: VvcEncodeParams,
) -> Result<Vec<u8>, String> {
    vvc_yuv_annex_b_from_input(
        input,
        params,
        VvcVideoGeometry {
            width: 8,
            height: 8,
        },
        PixelFormat::Yuv420p8,
    )
}

pub fn vvc_yuv420p_annex_b_from_input(
    input: &[u8],
    params: VvcEncodeParams,
    format: PixelFormat,
) -> Result<Vec<u8>, String> {
    vvc_yuv_annex_b_from_input(
        input,
        params,
        VvcVideoGeometry {
            width: 8,
            height: 8,
        },
        format,
    )
}

pub fn vvc_default_yuv_annex_b_from_input(
    input: &[u8],
    params: VvcEncodeParams,
    format: PixelFormat,
) -> Result<Vec<u8>, String> {
    vvc_yuv_annex_b_from_input(
        input,
        params,
        VvcVideoGeometry {
            width: 8,
            height: 8,
        },
        format,
    )
}

pub fn vvc_yuv_annex_b_from_input(
    input: &[u8],
    params: VvcEncodeParams,
    geometry: VvcVideoGeometry,
    format: PixelFormat,
) -> Result<Vec<u8>, String> {
    vvc_yuv_annex_b_from_input_with_limits(
        input,
        params,
        geometry,
        VvcVideoLimits::max_64x64(),
        format,
    )
}

pub fn vvc_yuv_annex_b_from_input_with_limits(
    input: &[u8],
    params: VvcEncodeParams,
    geometry: VvcVideoGeometry,
    limits: VvcVideoLimits,
    format: PixelFormat,
) -> Result<Vec<u8>, String> {
    geometry.validate_against(limits)?;
    let source_frame = sample_vvc_yuv_frame(input, params, geometry, format)?;
    if source_frame.format.chroma_sampling == ChromaSampling::Cs444 {
        return vvc_palette_444_annex_b(params, source_frame);
    }
    let compat_frame = source_frame.decoder_compat_frame();
    vvc_annex_b(params, compat_frame)
}

pub fn vvc_yuv420_cabac_vector_dump_json(
    input: &[u8],
    params: VvcEncodeParams,
    geometry: VvcVideoGeometry,
    format: PixelFormat,
) -> Result<String, String> {
    if format.chroma_sampling() != Some(ChromaSampling::Cs420) {
        return Err(format!(
            "VVC CABAC vector dump currently expects 4:2:0 input; got {format}"
        ));
    }
    let source_frame = sample_vvc_yuv_frame(input, params, geometry, format)?;
    let compat_frame = source_frame.decoder_compat_frame();
    let color = quantize_vvc_4x4_frame(compat_frame.clone());
    let params = vvc_ctu_partition_params(compat_frame.geometry, color).ok_or_else(|| {
        format!(
            "VVC CABAC vector dump has no generated CTU path for coded geometry {}x{}",
            compat_frame.geometry.coded_width(),
            compat_frame.geometry.coded_height()
        )
    })?;
    let dump = vvc_ctu_partition_cabac_dump(params, VvcSliceSyntaxConfig::yuv420_residual());
    Ok(vvc_cabac_vector_dump_json(
        compat_frame.geometry,
        params,
        &dump.symbols,
        &dump.semantic_symbols,
        &dump.context_events,
        &dump.bin_engine_events,
        &dump.bits,
    ))
}

pub fn sample_vvc_first_yuv420p8(
    input: &[u8],
    params: VvcEncodeParams,
) -> Result<Vvc4x4SampledColor, String> {
    Ok(sample_vvc_yuv_frame(
        input,
        params,
        VvcVideoGeometry {
            width: 8,
            height: 8,
        },
        PixelFormat::Yuv420p8,
    )?
    .sampled_color())
}

fn sample_vvc_yuv_frame(
    input: &[u8],
    params: VvcEncodeParams,
    geometry: VvcVideoGeometry,
    format: PixelFormat,
) -> Result<Vvc4x4SampledFrame, String> {
    validate_vvc_frame_count(params)?;
    geometry.validate_shape()?;
    if !format.is_yuv() {
        return Err(format!("VVC input expects planar YUV format; got {format}"));
    }
    Picture::validate_shape(geometry.width, geometry.height, format)?;
    let frame_len = Picture::expected_len(geometry.width, geometry.height, format);
    let expected_len = frame_len * params.frames;
    if input.len() != expected_len {
        return Err(format!(
            "VVC input size mismatch: got {} bytes, expected {} for {}x{} {format} with {} frame(s)",
            input.len(),
            expected_len,
            geometry.width,
            geometry.height,
            params.frames
        ));
    }

    let luma_samples = geometry.luma_samples();
    let mut luma = vec![0; luma_samples];
    let bytes_per_sample = format.bytes_per_sample();
    for (idx, sample) in luma.iter_mut().take(luma_samples).enumerate() {
        let raw = read_vvc_sample_raw(input, idx * bytes_per_sample, format);
        *sample = vvc_sample_to_8bit(raw, format.bit_depth());
    }

    let u_offset = luma_samples * bytes_per_sample;
    let chroma_plane_samples = format
        .chroma_plane_samples(geometry.width, geometry.height)
        .ok_or_else(|| format!("VVC input expects chroma samples; got {format}"))?;
    let v_offset = u_offset + (chroma_plane_samples * bytes_per_sample);
    let mut cb = vec![0; chroma_plane_samples];
    let mut cr = vec![0; chroma_plane_samples];
    for idx in 0..chroma_plane_samples {
        let raw_cb = read_vvc_sample_raw(input, u_offset + idx * bytes_per_sample, format);
        let raw_cr = read_vvc_sample_raw(input, v_offset + idx * bytes_per_sample, format);
        cb[idx] = vvc_sample_to_8bit(raw_cb, format.bit_depth());
        cr[idx] = vvc_sample_to_8bit(raw_cr, format.bit_depth());
    }

    Ok(Vvc4x4SampledFrame {
        geometry,
        format: Vvc4x4PictureFormat {
            chroma_sampling: format
                .chroma_sampling()
                .expect("YUV input has chroma sampling"),
            bit_depth: format.bit_depth(),
        },
        luma,
        cb,
        cr,
        chroma_len: chroma_plane_samples,
    })
}

fn read_vvc_sample_raw(input: &[u8], byte_offset: usize, format: PixelFormat) -> u16 {
    if format.bit_depth().bits() <= 8 {
        return input[byte_offset] as u16;
    }

    u16::from_le_bytes([input[byte_offset], input[byte_offset + 1]])
}

fn vvc_sample_to_8bit(sample: u16, bit_depth: SampleBitDepth) -> u8 {
    let bits = bit_depth.bits();
    if bits <= 8 {
        sample as u8
    } else {
        (sample >> (bits - 8)) as u8
    }
}

fn validate_vvc_frame_count(params: VvcEncodeParams) -> Result<(), String> {
    if params.frames == 0 {
        return Err("VVC encode expects at least one frame".to_string());
    }
    if params.frames > 2 {
        return Err("VVC encode currently supports at most two frames".to_string());
    }
    Ok(())
}

fn vvc_yuv420p8_annex_b(
    params: VvcEncodeParams,
    frame: Vvc4x4SampledFrame,
) -> Result<Vec<u8>, String> {
    vvc_annex_b(params, frame)
}

fn vvc_annex_b(params: VvcEncodeParams, frame: Vvc4x4SampledFrame) -> Result<Vec<u8>, String> {
    let mut units = Vec::with_capacity(params.frames + 3);
    units.push(vvc_4x4_sps_unit(frame.geometry));
    units.push(vvc_4x4_pps_unit(frame.geometry));
    let geometry = frame.geometry;
    let quantized = quantize_vvc_4x4_frame(frame);
    for frame_idx in 0..params.frames {
        units.push(vvc_4x4_slice_unit(frame_idx, geometry, quantized)?);
    }
    write_annex_b(&units)
}

fn vvc_4x4_sps_unit(geometry: VvcVideoGeometry) -> VvcNalUnit {
    vvc_sps_unit(geometry, VvcSliceSyntaxConfig::yuv420_residual())
}

fn vvc_palette_444_sps_unit(geometry: VvcVideoGeometry) -> VvcNalUnit {
    vvc_sps_unit(geometry, VvcSliceSyntaxConfig::palette_444())
}

fn vvc_sps_unit(geometry: VvcVideoGeometry, slice_config: VvcSliceSyntaxConfig) -> VvcNalUnit {
    VvcNalUnit {
        nal_unit_type: VvcNalUnitType::Sps,
        layer_id: 0,
        temporal_id: 0,
        rbsp_payload: vvc_sps_payload(geometry, slice_config),
    }
}

fn vvc_4x4_pps_unit(geometry: VvcVideoGeometry) -> VvcNalUnit {
    VvcNalUnit {
        nal_unit_type: VvcNalUnitType::Pps,
        layer_id: 0,
        temporal_id: 0,
        rbsp_payload: vvc_4x4_pps_payload(geometry),
    }
}

fn vvc_4x4_slice_unit(
    frame_idx: usize,
    geometry: VvcVideoGeometry,
    color: Vvc4x4QuantizedColor,
) -> Result<VvcNalUnit, String> {
    let picture_kind = match frame_idx {
        0 => Vvc4x4PictureKind::Idr,
        1 => Vvc4x4PictureKind::Cra,
        _ => return Err(format!("unsupported VVC frame index {frame_idx}")),
    };

    Ok(VvcNalUnit {
        nal_unit_type: match picture_kind {
            Vvc4x4PictureKind::Idr => VvcNalUnitType::IdrNLp,
            Vvc4x4PictureKind::Cra => VvcNalUnitType::Cra,
        },
        layer_id: 0,
        temporal_id: 0,
        rbsp_payload: vvc_4x4_slice_payload(picture_kind, geometry, color),
    })
}

#[cfg(test)]
fn vvc_4x4_sps_payload(geometry: VvcVideoGeometry) -> Vec<u8> {
    vvc_sps_payload(geometry, VvcSliceSyntaxConfig::yuv420_residual())
}

fn vvc_sps_payload(geometry: VvcVideoGeometry, slice_config: VvcSliceSyntaxConfig) -> Vec<u8> {
    vvc_sps_rbsp(geometry, slice_config).bytes
}

fn vvc_sps_rbsp(geometry: VvcVideoGeometry, slice_config: VvcSliceSyntaxConfig) -> VvcSyntaxRbsp {
    let mut writer = VvcSyntaxWriter::new();
    let config = slice_config.coding_tree;
    let palette_enabled = slice_config.palette_enabled;
    let tool_flags = slice_config.tools;
    writer.write_u("sps_seq_parameter_set_id", 0, 4);
    writer.write_u("sps_video_parameter_set_id", 0, 4);
    writer.write_u("sps_max_sub_layers_minus1", 0, 3);
    writer.write_u(
        "sps_chroma_format_idc",
        chroma_format_idc(config.chroma_sampling) as u64,
        2,
    );
    let sps_log2_ctu_size_minus5: u32 = 1;
    let ctu_log2_size = sps_log2_ctu_size_minus5 + 5;
    writer.write_u(
        "sps_log2_ctu_size_minus5",
        u64::from(sps_log2_ctu_size_minus5),
        2,
    );
    writer.write_flag("sps_ptl_dpb_hrd_params_present_flag", true);
    writer.write_u(
        "general_profile_idc",
        vvc_general_profile_idc(config, palette_enabled) as u64,
        7,
    );
    writer.write_flag("general_tier_flag", false);
    writer.write_u("general_level_idc", 0, 8);
    writer.write_flag("ptl_frame_only_constraint_flag", true);
    writer.write_flag("ptl_multilayer_enabled_flag", false);
    writer.write_flag("gci_present_flag", false);
    for _ in 0..5 {
        writer.write_flag("gci_alignment_zero_bit", false);
    }
    writer.write_u("ptl_num_sub_profiles", 0, 8);
    writer.write_flag("sps_gdr_enabled_flag", false);
    let ref_pic_resampling_enabled = false;
    writer.write_flag(
        "sps_ref_pic_resampling_enabled_flag",
        ref_pic_resampling_enabled,
    );
    if ref_pic_resampling_enabled {
        writer.write_flag("sps_res_change_in_clvs_allowed_flag", false);
    }
    writer.write_ue(
        "sps_pic_width_max_in_luma_samples",
        geometry.coded_width() as u32,
    );
    writer.write_ue(
        "sps_pic_height_max_in_luma_samples",
        geometry.coded_height() as u32,
    );
    writer.write_flag("sps_conformance_window_flag", true);
    writer.write_ue("sps_conf_win_left_offset", 0);
    writer.write_ue(
        "sps_conf_win_right_offset",
        geometry.crop_right(config.chroma_sampling),
    );
    writer.write_ue("sps_conf_win_top_offset", 0);
    writer.write_ue(
        "sps_conf_win_bottom_offset",
        geometry.crop_bottom(config.chroma_sampling),
    );
    writer.write_flag("sps_subpic_info_present_flag", false);
    writer.write_ue("sps_bitdepth_minus8", 0);
    writer.write_flag("sps_entropy_coding_sync_enabled_flag", false);
    writer.write_flag("sps_entry_point_offsets_present_flag", false);
    writer.write_u("sps_log2_max_pic_order_cnt_lsb_minus4", 4, 4);
    writer.write_flag("sps_poc_msb_cycle_flag", false);
    writer.write_u("sps_num_extra_ph_bytes", 0, 2);
    writer.write_u("sps_num_extra_sh_bytes", 0, 2);
    writer.write_ue("dpb_max_dec_pic_buffering_minus1[i]", 0);
    writer.write_ue("dpb_max_num_reorder_pics[i]", 0);
    writer.write_ue("dpb_max_latency_increase_plus1[i]", 0);
    writer.write_ue("sps_log2_min_luma_coding_block_size_minus2", 0);
    writer.write_flag("sps_partition_constraints_override_enabled_flag", true);
    writer.write_ue("sps_log2_diff_min_qt_min_cb_intra_slice_luma", 1);
    writer.write_ue("sps_max_mtt_hierarchy_depth_intra_slice_luma", 3);
    writer.write_ue("sps_log2_diff_max_bt_min_qt_intra_slice_luma", 2);
    writer.write_ue("sps_log2_diff_max_tt_min_qt_intra_slice_luma", 2);
    let dual_tree_intra = config.chroma_sampling != ChromaSampling::Cs444 || !palette_enabled;
    writer.write_flag("sps_qtbtt_dual_tree_intra_flag", dual_tree_intra);
    if dual_tree_intra {
        writer.write_ue("sps_log2_diff_min_qt_min_cb_intra_slice_chroma", 1);
        writer.write_ue("sps_max_mtt_hierarchy_depth_intra_slice_chroma", 3);
        writer.write_ue(
            "sps_log2_diff_max_bt_min_qt_intra_slice_chroma",
            (ctu_log2_size - 3).min(3),
        );
        writer.write_ue("sps_log2_diff_max_tt_min_qt_intra_slice_chroma", 2);
    }
    writer.write_ue("sps_log2_diff_min_qt_min_cb_inter_slice", 1);
    writer.write_ue("sps_max_mtt_hierarchy_depth_inter_slice", 3);
    writer.write_ue(
        "sps_log2_diff_max_bt_min_qt_inter_slice",
        (ctu_log2_size - 3).min(3),
    );
    writer.write_ue(
        "sps_log2_diff_max_tt_min_qt_inter_slice",
        (ctu_log2_size - 3).min(3),
    );
    writer.write_flag("sps_max_luma_transform_size_64_flag", true);
    writer.write_flag(
        "sps_transform_skip_enabled_flag",
        tool_flags.transform_skip_enabled,
    );
    if tool_flags.transform_skip_enabled {
        writer.write_ue("sps_log2_transform_skip_max_size_minus2", 0);
        writer.write_flag("sps_bdpcm_enabled_flag", false);
    }
    writer.write_flag("sps_mts_enabled_flag", tool_flags.mts_enabled);
    if tool_flags.mts_enabled {
        writer.write_flag(
            "sps_explicit_mts_intra_enabled_flag",
            tool_flags.explicit_mts_intra_enabled,
        );
        writer.write_flag("sps_explicit_mts_inter_enabled_flag", false);
    }
    writer.write_flag("sps_lfnst_enabled_flag", tool_flags.lfnst_enabled);
    writer.write_flag("sps_joint_cbcr_enabled_flag", true);
    writer.write_flag("sps_same_qp_table_for_chroma_flag", true);
    writer.write_se("sps_qp_table_starts_minus26", -9);
    writer.write_ue("sps_num_points_in_qp_table_minus1", 2);
    writer.write_ue("sps_delta_qp_in_val_minus1", 9);
    writer.write_ue("sps_delta_qp_diff_val", 5);
    writer.write_ue("sps_delta_qp_in_val_minus1", 4);
    writer.write_ue("sps_delta_qp_diff_val", 1);
    writer.write_ue("sps_delta_qp_in_val_minus1", 11);
    writer.write_ue("sps_delta_qp_diff_val", 12);
    writer.write_flag("sps_sao_enabled_flag", false);
    writer.write_flag("sps_alf_enabled_flag", false);
    writer.write_flag("sps_lmcs_enable_flag", false);
    writer.write_flag("sps_weighted_pred_flag", false);
    writer.write_flag("sps_weighted_bipred_flag", false);
    writer.write_flag("sps_long_term_ref_pics_flag", false);
    writer.write_flag("sps_idr_rpl_present_flag", false);
    writer.write_flag("sps_rpl1_same_as_rpl0_flag", true);
    writer.write_ue("sps_num_ref_pic_lists[0]", 1);
    writer.write_ue("num_ref_entries[listIdx][rplsIdx]", 0);
    writer.write_flag("sps_ref_wraparound_enabled_flag", false);
    let temporal_mvp_enabled = false;
    writer.write_flag("sps_temporal_mvp_enabled_flag", temporal_mvp_enabled);
    if temporal_mvp_enabled {
        writer.write_flag("sps_sbtmvp_enabled_flag", false);
    }
    let amvr_enabled = false;
    writer.write_flag("sps_amvr_enabled_flag", amvr_enabled);
    writer.write_flag("sps_bdof_enabled_flag", false);
    writer.write_flag("sps_smvd_enabled_flag", false);
    writer.write_flag("sps_dmvr_enabled_flag", false);
    let mmvd_enabled = false;
    writer.write_flag("sps_mmvd_enabled_flag", mmvd_enabled);
    if mmvd_enabled {
        writer.write_flag("sps_mmvd_fullpel_only_flag", false);
    }
    writer.write_ue("sps_six_minus_max_num_merge_cand", 0);
    writer.write_flag("sps_sbt_enabled_flag", false);
    let affine_enabled = false;
    writer.write_flag("sps_affine_enabled_flag", affine_enabled);
    if affine_enabled {
        writer.write_ue("sps_five_minus_max_num_subblock_merge_cand", 0);
        writer.write_flag("sps_affine_type_flag", false);
        if amvr_enabled {
            writer.write_flag("sps_affine_amvr_enabled_flag", false);
        }
        writer.write_flag("sps_affine_prof_enabled_flag", false);
    }
    writer.write_flag("sps_bcw_enabled_flag", false);
    writer.write_flag("sps_ciip_enabled_flag", false);
    writer.write_flag("sps_gpm_enabled_flag", false);
    writer.write_ue("sps_log2_parallel_merge_level_minus2", 0);
    writer.write_flag("sps_isp_enabled_flag", false);
    writer.write_flag("sps_mrl_enabled_flag", tool_flags.mrl_enabled);
    writer.write_flag("sps_mip_enabled_flag", false);
    if config.chroma_sampling != ChromaSampling::Monochrome {
        writer.write_flag("sps_cclm_enabled_flag", tool_flags.cclm_enabled);
    }
    if config.chroma_sampling == ChromaSampling::Cs420 {
        writer.write_flag("sps_chroma_horizontal_collocated_flag", true);
        writer.write_flag("sps_chroma_vertical_collocated_flag", false);
    }
    writer.write_flag("sps_palette_enabled_flag", palette_enabled);
    if palette_enabled {
        writer.write_ue("sps_internal_bit_depth_minus_input_bit_depth", 0);
    }
    writer.write_flag("sps_ibc_enabled_flag", false);
    writer.write_flag("sps_ladf_enabled_flag", false);
    writer.write_flag("sps_explicit_scaling_list_enabled_flag", false);
    writer.write_flag(
        "sps_dep_quant_enabled_flag",
        tool_flags.dependent_quantization_enabled,
    );
    writer.write_flag(
        "sps_sign_data_hiding_enabled_flag",
        tool_flags.sign_data_hiding_enabled,
    );
    writer.write_flag("sps_virtual_boundaries_enabled_flag", false);
    writer.write_flag("sps_timing_hrd_params_present_flag", false);
    writer.write_flag("sps_field_seq_flag", false);
    writer.write_flag("sps_vui_parameters_present_flag", false);
    writer.write_flag("sps_extension_present_flag", false);
    writer.rbsp_trailing_bits();
    debug_assert!(writer.is_byte_aligned());
    writer.finish()
}

fn chroma_format_idc(chroma_sampling: ChromaSampling) -> u32 {
    match chroma_sampling {
        ChromaSampling::Monochrome => 0,
        ChromaSampling::Cs420 => 1,
        ChromaSampling::Cs422 => 2,
        ChromaSampling::Cs444 => 3,
    }
}

fn vvc_general_profile_idc(config: VvcCodingTreeConfig, palette_enabled: bool) -> u32 {
    if config.chroma_sampling == ChromaSampling::Cs444 || palette_enabled {
        // TODO(vvc): Signal a concrete 4:4:4-capable profile once the full
        // PTL/GCI constraint set is generated. Profile NONE avoids the Main 10
        // palette-off constraint while this clean-room subset is still forming.
        0
    } else {
        1
    }
}

fn vvc_4x4_pps_payload(geometry: VvcVideoGeometry) -> Vec<u8> {
    vvc_4x4_pps_rbsp(geometry).bytes
}

fn vvc_4x4_pps_rbsp(geometry: VvcVideoGeometry) -> VvcSyntaxRbsp {
    let mut writer = VvcSyntaxWriter::new();
    writer.write_u("pps_pic_parameter_set_id", 0, 6);
    writer.write_u("pps_seq_parameter_set_id", 0, 4);
    writer.write_flag("pps_mixed_nalu_types_in_pic_flag", false);
    writer.write_ue(
        "pps_pic_width_in_luma_samples",
        geometry.coded_width() as u32,
    );
    writer.write_ue(
        "pps_pic_height_in_luma_samples",
        geometry.coded_height() as u32,
    );
    writer.write_flag("pps_conformance_window_flag", false);
    writer.write_flag("pps_scaling_window_explicit_signalling_flag", false);
    writer.write_flag("pps_output_flag_present_flag", false);
    writer.write_flag("pps_no_pic_partition_flag", true);
    writer.write_flag("pps_subpic_id_mapping_present_flag", false);
    writer.write_flag("pps_cabac_init_present_flag", false);
    writer.write_ue("pps_num_ref_idx_default_active_minus1[0]", 3);
    writer.write_ue("pps_num_ref_idx_default_active_minus1[1]", 3);
    writer.write_flag("pps_rpl1_idx_present_flag", false);
    writer.write_flag("pps_weighted_pred_flag", false);
    writer.write_flag("pps_weighted_bipred_flag", false);
    writer.write_flag("pps_ref_wraparound_enabled_flag", false);
    writer.write_se("pps_init_qp_minus26", 6);
    writer.write_flag("pps_cu_qp_delta_enabled_flag", false);
    writer.write_flag("pps_chroma_tool_offsets_present_flag", true);
    writer.write_se("pps_cb_qp_offset", 0);
    writer.write_se("pps_cr_qp_offset", 0);
    writer.write_flag("pps_joint_cbcr_qp_offset_present_flag", true);
    writer.write_se("pps_joint_cbcr_qp_offset_value", -1);
    writer.write_flag("pps_slice_chroma_qp_offsets_present_flag", false);
    writer.write_flag("pps_cu_chroma_qp_offset_list_enabled_flag", false);
    writer.write_flag("pps_deblocking_filter_control_present_flag", true);
    writer.write_flag("pps_deblocking_filter_override_enabled_flag", false);
    writer.write_flag("pps_deblocking_filter_disabled_flag", false);
    writer.write_se("pps_beta_offset_div2", -2);
    writer.write_se("pps_tc_offset_div2", -5);
    writer.write_se("pps_cb_beta_offset_div2", -2);
    writer.write_se("pps_cb_tc_offset_div2", -5);
    writer.write_se("pps_cr_beta_offset_div2", -2);
    writer.write_se("pps_cr_tc_offset_div2", -5);
    writer.write_flag("pps_picture_header_extension_present_flag", false);
    writer.write_flag("pps_slice_header_extension_present_flag", false);
    writer.write_flag("pps_extension_flag", false);
    writer.rbsp_trailing_bits();
    debug_assert!(writer.is_byte_aligned());
    writer.finish()
}

fn vvc_4x4_slice_payload(
    picture_kind: Vvc4x4PictureKind,
    geometry: VvcVideoGeometry,
    color: Vvc4x4QuantizedColor,
) -> Vec<u8> {
    vvc_4x4_slice_rbsp(
        picture_kind,
        geometry,
        color,
        VvcSliceSyntaxConfig::yuv420_residual(),
    )
    .bytes
}

fn vvc_4x4_slice_rbsp(
    picture_kind: Vvc4x4PictureKind,
    geometry: VvcVideoGeometry,
    color: Vvc4x4QuantizedColor,
    slice_config: VvcSliceSyntaxConfig,
) -> VvcSyntaxRbsp {
    let mut writer = VvcSyntaxWriter::new();
    let tool_flags = slice_config.tools;
    writer.write_flag("sh_picture_header_in_slice_header_flag", true);
    writer.write_flag("ph_gdr_or_irap_pic_flag", true);
    writer.write_flag("ph_non_ref_pic_flag", false);
    writer.write_flag("ph_gdr_pic_flag", false);
    writer.write_flag("ph_inter_slice_allowed_flag", false);
    writer.write_ue("ph_pic_parameter_set_id", 0);
    match picture_kind {
        Vvc4x4PictureKind::Idr => {
            writer.write_u("ph_pic_order_cnt_lsb", 0, 8);
        }
        Vvc4x4PictureKind::Cra => {
            writer.write_u("ph_pic_order_cnt_lsb", 1, 8);
        }
    }
    writer.write_flag("ph_partition_constraints_override_flag", false);
    writer.write_flag("ph_joint_cbcr_sign_flag", false);
    writer.write_flag("sh_no_output_of_prior_pics_flag", false);
    writer.write_se("sh_qp_delta", 0);
    if tool_flags.dependent_quantization_enabled {
        writer.write_flag("sh_dep_quant_used_flag", true);
    }
    if tool_flags.sign_data_hiding_enabled && !tool_flags.dependent_quantization_enabled {
        writer.write_flag("sh_sign_data_hiding_used_flag", true);
    }
    writer.write_flag("cabac_alignment_one_bit", true);
    if picture_kind == Vvc4x4PictureKind::Cra {
        writer.write_flag("cabac_alignment_one_bit", true);
    }
    writer.byte_align_zero("cabac_alignment_zero_bit");
    write_vvc_coding_tree_entropy(&mut writer, geometry, color, slice_config);
    writer.rbsp_trailing_bits();
    debug_assert!(writer.is_byte_aligned());
    writer.finish()
}

#[derive(Debug, Clone, Copy)]
enum VvcCabacContext {
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
    MtsIdx(u8),
    LastSigCoeffXPrefix(u8),
    LastSigCoeffYPrefix(u8),
    SbCodedFlag(u8),
    SigCoeffFlag(u8),
    ParLevelFlag(u8),
    AbsLevelGtxFlag(u8),
    CoeffSignFlag(u8),
}

impl VvcCabacContext {
    fn rtl_context_id(self) -> Option<u8> {
        match self {
            VvcCabacContext::SplitFlag(0) => Some(0),
            VvcCabacContext::SplitFlag(6) => Some(1),
            VvcCabacContext::SplitQtFlag(3) => Some(2),
            VvcCabacContext::SplitFlag(3) => Some(3),
            VvcCabacContext::IntraLumaMpmFlag => Some(4),
            VvcCabacContext::QtCbfY(0) => Some(5),
            VvcCabacContext::LastSigCoeffXPrefix(3) => Some(6),
            VvcCabacContext::LastSigCoeffYPrefix(3) => Some(7),
            VvcCabacContext::LastSigCoeffXPrefix(6) => Some(8),
            VvcCabacContext::LastSigCoeffYPrefix(6) => Some(9),
            VvcCabacContext::AbsLevelGtxFlag(0) => Some(10),
            VvcCabacContext::ParLevelFlag(0) => Some(11),
            VvcCabacContext::AbsLevelGtxFlag(32) => Some(12),
            VvcCabacContext::CclmModeFlag => Some(13),
            VvcCabacContext::IntraChromaPredMode(0) => Some(14),
            VvcCabacContext::QtCbfCb(0) => Some(15),
            VvcCabacContext::QtCbfCr(0) => Some(16),
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
            VvcCabacContext::SplitFlag(4) => Some(33),
            VvcCabacContext::SplitQtFlag(1) => Some(34),
            VvcCabacContext::SplitQtFlag(2) => Some(35),
            VvcCabacContext::SplitQtFlag(4) => Some(36),
            VvcCabacContext::SplitQtFlag(5) => Some(37),
            VvcCabacContext::SplitFlag(5) => Some(38),
            VvcCabacContext::SplitFlag(8) => Some(39),
            _ => None,
        }
    }

    fn init_value(self) -> u8 {
        match self {
            // ITU-T H.266 CABAC context initialization tables, I-slice
            // initializationType. See docs/vvc-cabac-subset.md.
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
            VvcCabacContext::MtsIdx(ctx) => {
                const I_SLICE_INIT: [u8; 4] = [29, 0, 28, 0];
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
        }
    }

    fn log2_window_size(self) -> u8 {
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
            VvcCabacContext::MtsIdx(ctx) => {
                const LOG2_WINDOW: [u8; 4] = [8, 0, 9, 0];
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
        }
    }
}

#[derive(Debug, Clone)]
struct VvcCabacContexts {
    split_flag: [VvcCabacProbModel; 9],
    split_qt_flag: [VvcCabacProbModel; 6],
    mtt_split_cu_vertical_flag: [VvcCabacProbModel; 15],
    mtt_split_cu_binary_flag: [VvcCabacProbModel; 12],
    multi_ref_line_idx: [VvcCabacProbModel; 2],
    intra_luma_mpm_flag: VvcCabacProbModel,
    intra_luma_planar_flag: [VvcCabacProbModel; 2],
    cclm_mode_flag: VvcCabacProbModel,
    intra_chroma_pred_mode: [VvcCabacProbModel; 2],
    qt_cbf_y: [VvcCabacProbModel; 4],
    qt_cbf_cb: [VvcCabacProbModel; 2],
    qt_cbf_cr: [VvcCabacProbModel; 3],
    transform_skip_flag: [VvcCabacProbModel; 2],
    mts_idx: [VvcCabacProbModel; 4],
    last_sig_coeff_x_prefix: [VvcCabacProbModel; 23],
    last_sig_coeff_y_prefix: [VvcCabacProbModel; 23],
    sb_coded_flag: [VvcCabacProbModel; 7],
    sig_coeff_flag: [VvcCabacProbModel; 63],
    par_level_flag: [VvcCabacProbModel; 33],
    abs_level_gtx_flag: [VvcCabacProbModel; 72],
    coeff_sign_flag: [VvcCabacProbModel; 6],
}

impl VvcCabacContexts {
    const DEFAULT_SLICE_QP: i32 = 32;

    fn new() -> Self {
        Self {
            split_flag: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::SplitFlag(idx as u8).init_value(),
                    Self::DEFAULT_SLICE_QP,
                    VvcCabacContext::SplitFlag(idx as u8).log2_window_size(),
                )
            }),
            split_qt_flag: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::SplitQtFlag(idx as u8).init_value(),
                    Self::DEFAULT_SLICE_QP,
                    VvcCabacContext::SplitQtFlag(idx as u8).log2_window_size(),
                )
            }),
            mtt_split_cu_vertical_flag: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::MttSplitCuVerticalFlag(idx as u8).init_value(),
                    Self::DEFAULT_SLICE_QP,
                    VvcCabacContext::MttSplitCuVerticalFlag(idx as u8).log2_window_size(),
                )
            }),
            mtt_split_cu_binary_flag: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::MttSplitCuBinaryFlag(idx as u8).init_value(),
                    Self::DEFAULT_SLICE_QP,
                    VvcCabacContext::MttSplitCuBinaryFlag(idx as u8).log2_window_size(),
                )
            }),
            multi_ref_line_idx: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::MultiRefLineIdx(idx as u8).init_value(),
                    Self::DEFAULT_SLICE_QP,
                    VvcCabacContext::MultiRefLineIdx(idx as u8).log2_window_size(),
                )
            }),
            intra_luma_mpm_flag: VvcCabacProbModel::from_init_value(
                VvcCabacContext::IntraLumaMpmFlag.init_value(),
                Self::DEFAULT_SLICE_QP,
                VvcCabacContext::IntraLumaMpmFlag.log2_window_size(),
            ),
            intra_luma_planar_flag: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::IntraLumaPlanarFlag(idx as u8).init_value(),
                    Self::DEFAULT_SLICE_QP,
                    VvcCabacContext::IntraLumaPlanarFlag(idx as u8).log2_window_size(),
                )
            }),
            cclm_mode_flag: VvcCabacProbModel::from_init_value(
                VvcCabacContext::CclmModeFlag.init_value(),
                Self::DEFAULT_SLICE_QP,
                VvcCabacContext::CclmModeFlag.log2_window_size(),
            ),
            intra_chroma_pred_mode: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::IntraChromaPredMode(idx as u8).init_value(),
                    Self::DEFAULT_SLICE_QP,
                    VvcCabacContext::IntraChromaPredMode(idx as u8).log2_window_size(),
                )
            }),
            qt_cbf_y: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::QtCbfY(idx as u8).init_value(),
                    Self::DEFAULT_SLICE_QP,
                    VvcCabacContext::QtCbfY(idx as u8).log2_window_size(),
                )
            }),
            qt_cbf_cb: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::QtCbfCb(idx as u8).init_value(),
                    Self::DEFAULT_SLICE_QP,
                    VvcCabacContext::QtCbfCb(idx as u8).log2_window_size(),
                )
            }),
            qt_cbf_cr: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::QtCbfCr(idx as u8).init_value(),
                    Self::DEFAULT_SLICE_QP,
                    VvcCabacContext::QtCbfCr(idx as u8).log2_window_size(),
                )
            }),
            transform_skip_flag: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::TransformSkipFlag(idx as u8).init_value(),
                    Self::DEFAULT_SLICE_QP,
                    VvcCabacContext::TransformSkipFlag(idx as u8).log2_window_size(),
                )
            }),
            mts_idx: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::MtsIdx(idx as u8).init_value(),
                    Self::DEFAULT_SLICE_QP,
                    VvcCabacContext::MtsIdx(idx as u8).log2_window_size(),
                )
            }),
            last_sig_coeff_x_prefix: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::LastSigCoeffXPrefix(idx as u8).init_value(),
                    Self::DEFAULT_SLICE_QP,
                    VvcCabacContext::LastSigCoeffXPrefix(idx as u8).log2_window_size(),
                )
            }),
            last_sig_coeff_y_prefix: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::LastSigCoeffYPrefix(idx as u8).init_value(),
                    Self::DEFAULT_SLICE_QP,
                    VvcCabacContext::LastSigCoeffYPrefix(idx as u8).log2_window_size(),
                )
            }),
            sb_coded_flag: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::SbCodedFlag(idx as u8).init_value(),
                    Self::DEFAULT_SLICE_QP,
                    VvcCabacContext::SbCodedFlag(idx as u8).log2_window_size(),
                )
            }),
            sig_coeff_flag: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::SigCoeffFlag(idx as u8).init_value(),
                    Self::DEFAULT_SLICE_QP,
                    VvcCabacContext::SigCoeffFlag(idx as u8).log2_window_size(),
                )
            }),
            par_level_flag: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::ParLevelFlag(idx as u8).init_value(),
                    Self::DEFAULT_SLICE_QP,
                    VvcCabacContext::ParLevelFlag(idx as u8).log2_window_size(),
                )
            }),
            abs_level_gtx_flag: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::AbsLevelGtxFlag(idx as u8).init_value(),
                    Self::DEFAULT_SLICE_QP,
                    VvcCabacContext::AbsLevelGtxFlag(idx as u8).log2_window_size(),
                )
            }),
            coeff_sign_flag: std::array::from_fn(|idx| {
                VvcCabacProbModel::from_init_value(
                    VvcCabacContext::CoeffSignFlag(idx as u8).init_value(),
                    Self::DEFAULT_SLICE_QP,
                    VvcCabacContext::CoeffSignFlag(idx as u8).log2_window_size(),
                )
            }),
        }
    }

    fn encode(&mut self, cabac: &mut VvcCabacEncoder, ctx: VvcCabacContext, bin: bool) {
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
            VvcCabacContext::MtsIdx(idx) => &self.mts_idx[idx as usize],
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
            VvcCabacContext::MtsIdx(idx) => self.mts_idx[idx as usize].encode(cabac, bin),
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
        }
    }
}

#[derive(Debug, Clone)]
struct VvcCabacProbModel {
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

    fn state(&self) -> u16 {
        (self.state0 + self.state1) >> 8
    }

    fn mps(&self) -> bool {
        self.state() >= 128
    }

    fn lps(&self, range: u32) -> u16 {
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

fn write_vvc_coding_tree_entropy(
    writer: &mut VvcSyntaxWriter,
    geometry: VvcVideoGeometry,
    color: Vvc4x4QuantizedColor,
    slice_config: VvcSliceSyntaxConfig,
) {
    let bits = vvc_cabac_bits(geometry, color, slice_config);
    writer.write_cabac_bits("cabac_vvc_quantized_residual_bits", &bits);
}

fn vvc_coding_tree_plan(geometry: VvcVideoGeometry) -> Vec<VvcCodingTreeStep> {
    vvc_coding_tree_plan_with_config(geometry, VvcCodingTreeConfig::yuv420())
}

fn vvc_coding_tree_plan_with_config(
    geometry: VvcVideoGeometry,
    config: VvcCodingTreeConfig,
) -> Vec<VvcCodingTreeStep> {
    let mut steps = Vec::new();
    steps.push(VvcCodingTreeStep::LumaTransformUnit {
        width: geometry.coded_width(),
        height: geometry.coded_height(),
    });

    let chroma_width = geometry.coded_width() / chroma_subsample_x(config.chroma_sampling);
    let chroma_height = geometry.coded_height() / chroma_subsample_y(config.chroma_sampling);
    for y in (0..chroma_height).step_by(4) {
        for x in (0..chroma_width).step_by(4) {
            let first = x == 0 && y == 0;
            steps.push(VvcCodingTreeStep::ChromaTransformUnit {
                x,
                y,
                cb_coded: first && geometry.coded_width() <= 8,
                cr_coded: first,
            });
        }
    }

    steps
}

#[cfg(test)]
fn vvc_luma_partition_plan(geometry: VvcVideoGeometry) -> Vec<VvcLumaPartitionStep> {
    let coded = geometry.coded();
    let mut steps = Vec::new();
    append_vvc_luma_partition(
        &mut steps,
        0,
        0,
        coded.width,
        coded.height,
        VvcCodedGeometry {
            width: VVC_CURRENT_MAX_LUMA_LEAF_SIZE as usize,
            height: VVC_CURRENT_MAX_LUMA_LEAF_HEIGHT as usize,
        },
    );
    steps
}

#[cfg(test)]
fn append_vvc_luma_partition(
    steps: &mut Vec<VvcLumaPartitionStep>,
    x: usize,
    y: usize,
    width: usize,
    height: usize,
    max_leaf: VvcCodedGeometry,
) {
    if width > max_leaf.width || height > max_leaf.height {
        steps.push(VvcLumaPartitionStep::QuadSplit {
            x,
            y,
            width,
            height,
        });
        let child_width = width / 2;
        let child_height = height / 2;
        for child_y in [y, y + child_height] {
            for child_x in [x, x + child_width] {
                append_vvc_luma_partition(
                    steps,
                    child_x,
                    child_y,
                    child_width,
                    child_height,
                    max_leaf,
                );
            }
        }
    } else {
        steps.push(VvcLumaPartitionStep::Leaf {
            x,
            y,
            width,
            height,
        });
    }
}

fn vvc_cabac_bits(
    geometry: VvcVideoGeometry,
    color: Vvc4x4QuantizedColor,
    slice_config: VvcSliceSyntaxConfig,
) -> Vec<bool> {
    if let Some(params) = vvc_ctu_partition_params(geometry, color) {
        return vvc_ctu_partition_cabac_bits(params, slice_config);
    }
    unimplemented!(
        "VVC coding tree for coded geometry {}x{} must be generated from syntax parameters",
        geometry.coded_width(),
        geometry.coded_height()
    );
}

fn vvc_ctu_partition_params(
    geometry: VvcVideoGeometry,
    color: Vvc4x4QuantizedColor,
) -> Option<VvcCtuPartitionParams> {
    let coded = geometry.coded();
    if coded.width > VVC_CTU_SIZE
        || coded.height > VVC_CTU_SIZE
        || coded.width < 8
        || coded.height < 8
    {
        return None;
    }
    let chroma_sampling = ChromaSampling::Cs420;
    let half_ctu = VVC_CTU_SIZE / 2;
    if coded.width <= half_ctu && coded.height <= half_ctu {
        let chroma_tu_count = vvc_coding_tree_plan(geometry)
            .iter()
            .filter(|step| matches!(step, VvcCodingTreeStep::ChromaTransformUnit { .. }))
            .count();
        return Some(VvcCtuPartitionParams {
            root_width: VVC_CTU_SIZE,
            root_height: VVC_CTU_SIZE,
            visible_width: coded.width,
            visible_height: coded.height,
            chroma_sampling,
            chroma_tu_count,
            luma_dc_abs_level: color.luma_rem,
            luma_dc_negative: color.y < VVC_LUMA_DC_BASE as u8 && color.luma_rem != 0,
            cb_dc_abs_level: color.cb_rem,
            cb_dc_negative: color.u < 128 && color.cb_rem != 0,
        });
    }
    let chroma_tu_count = vvc_coding_tree_plan(geometry)
        .iter()
        .filter(|step| matches!(step, VvcCodingTreeStep::ChromaTransformUnit { .. }))
        .count();
    Some(VvcCtuPartitionParams {
        root_width: VVC_CTU_SIZE,
        root_height: VVC_CTU_SIZE,
        visible_width: coded.width,
        visible_height: coded.height,
        chroma_sampling,
        chroma_tu_count,
        luma_dc_abs_level: color.luma_rem,
        luma_dc_negative: color.y < VVC_LUMA_DC_BASE as u8 && color.luma_rem != 0,
        cb_dc_abs_level: color.cb_rem,
        cb_dc_negative: color.u < 128 && color.cb_rem != 0,
    })
}

fn vvc_anchor_luma_tu_size_from_partition(geometry: VvcVideoGeometry) -> VvcVideoGeometry {
    let params = VvcCtuPartitionParams {
        root_width: VVC_CTU_SIZE,
        root_height: VVC_CTU_SIZE,
        visible_width: geometry.coded_width(),
        visible_height: geometry.coded_height(),
        chroma_sampling: ChromaSampling::Cs420,
        chroma_tu_count: 0,
        luma_dc_abs_level: 0,
        luma_dc_negative: false,
        cb_dc_abs_level: 0,
        cb_dc_negative: false,
    };

    VvcCtuCabacOp::yuv420_ctu_partition(params)
        .into_iter()
        .find_map(|op| match op {
            VvcCtuCabacOp::LumaLeafWithSplitCtx { node, .. } => Some(VvcVideoGeometry {
                width: usize::from(node.width),
                height: usize::from(node.height),
            }),
            _ => None,
        })
        .unwrap_or(VvcVideoGeometry {
            width: VVC_CURRENT_MAX_LUMA_LEAF_SIZE as usize,
            height: VVC_CURRENT_MAX_LUMA_LEAF_HEIGHT as usize,
        })
}

fn vvc_ctu_partition_cabac_bits(
    params: VvcCtuPartitionParams,
    slice_config: VvcSliceSyntaxConfig,
) -> Vec<bool> {
    debug_assert!((8..=64).contains(&params.root_width));
    debug_assert!((8..=64).contains(&params.root_height));
    debug_assert!(params.visible_width >= 8 && params.visible_height >= 8);

    let mut cabac = VvcCabacEncoder::new();
    cabac.start();
    encode_ctu_partition_body(&mut cabac, params, slice_config);
    cabac.encode_bin_trm(true);
    cabac.finish()
}

struct VvcCtuCabacDump {
    symbols: Vec<VvcCabacDumpSymbol>,
    semantic_symbols: Vec<VvcCabacDumpSymbol>,
    context_events: Vec<VvcCabacDumpContextEvent>,
    bin_engine_events: Vec<cabac::VvcCabacDumpBinEngineEvent>,
    bits: Vec<bool>,
}

fn vvc_ctu_partition_cabac_dump(
    params: VvcCtuPartitionParams,
    slice_config: VvcSliceSyntaxConfig,
) -> VvcCtuCabacDump {
    debug_assert!((8..=64).contains(&params.root_width));
    debug_assert!((8..=64).contains(&params.root_height));
    debug_assert!(params.visible_width >= 8 && params.visible_height >= 8);

    let mut cabac = VvcCabacEncoder::new();
    cabac.start();
    encode_ctu_partition_body(&mut cabac, params, slice_config);
    cabac.encode_bin_trm(true);
    let semantic_symbols = cabac.semantic_symbols.clone();
    let context_events = cabac.context_events.clone();
    let bin_engine_events = cabac.bin_engine_events.clone();
    let symbols = cabac.dump_symbols.clone();
    let bits = cabac.finish();
    VvcCtuCabacDump {
        symbols,
        semantic_symbols,
        context_events,
        bin_engine_events,
        bits,
    }
}

fn vvc_cabac_vector_dump_json(
    geometry: VvcVideoGeometry,
    params: VvcCtuPartitionParams,
    symbols: &[VvcCabacDumpSymbol],
    semantic_symbols: &[VvcCabacDumpSymbol],
    context_events: &[VvcCabacDumpContextEvent],
    bin_engine_events: &[cabac::VvcCabacDumpBinEngineEvent],
    bits: &[bool],
) -> String {
    let mut json = String::new();
    json.push_str("{\"kind\":\"frameforge.vvc.cabac_vector.v1\"");
    json.push_str(&format!(",\"width\":{}", geometry.width));
    json.push_str(&format!(",\"height\":{}", geometry.height));
    json.push_str(",\"format\":\"yuv420p8\"");
    json.push_str(&format!(
        ",\"luma_dc_abs_level\":{}",
        params.luma_dc_abs_level
    ));
    json.push_str(&format!(
        ",\"luma_dc_negative\":{}",
        if params.luma_dc_negative {
            "true"
        } else {
            "false"
        }
    ));
    json.push_str(&format!(",\"cb_dc_abs_level\":{}", params.cb_dc_abs_level));
    json.push_str(&format!(
        ",\"cb_dc_negative\":{}",
        if params.cb_dc_negative {
            "true"
        } else {
            "false"
        }
    ));
    json.push_str(",\"symbol_record_bytes\":5");
    json.push_str(",\"symbol_encoding\":\"kind_u8_data_u32be_hex\"");
    json.push_str(&format!(",\"cabac_bit_len\":{}", bits.len()));
    json.push_str(",\"cabac_bytes_hex\":\"");
    append_hex_bytes(&mut json, bits);
    json.push_str("\",\"symbols_hex\":\"");
    append_symbol_records_hex(&mut json, symbols);
    json.push_str("\",\"semantic_symbols_hex\":\"");
    append_symbol_records_hex(&mut json, semantic_symbols);
    json.push_str("\",\"context_event_record_bytes\":7");
    json.push_str(
        ",\"context_event_encoding\":\"ctx_id_u8_bin_u8_range_u16be_lps_u16be_mps_u8_hex\"",
    );
    json.push_str(",\"context_events_hex\":\"");
    append_context_event_records_hex(&mut json, context_events);
    json.push_str("\",\"bin_engine_event_record_bytes\":20");
    json.push_str(",\"bin_engine_event_encoding\":\"kind_u8_bin_u8_lps_u16be_mps_u8_low_in_u32be_range_in_u16be_bits_left_in_u8_low_out_u32be_range_out_u16be_bits_left_out_u8_write_out_u8_hex\"");
    json.push_str(",\"bin_engine_events_hex\":\"");
    append_bin_engine_event_records_hex(&mut json, bin_engine_events);
    json.push_str("\"}\n");
    json
}

fn append_bin_engine_event_records_hex(
    out: &mut String,
    events: &[cabac::VvcCabacDumpBinEngineEvent],
) {
    for event in events {
        append_byte_hex(out, event.kind);
        append_byte_hex(out, u8::from(event.bin));
        for byte in event.lps.to_be_bytes() {
            append_byte_hex(out, byte);
        }
        append_byte_hex(out, u8::from(event.mps));
        for byte in event.low_in.to_be_bytes() {
            append_byte_hex(out, byte);
        }
        for byte in event.range_in.to_be_bytes() {
            append_byte_hex(out, byte);
        }
        append_byte_hex(out, event.bits_left_in);
        for byte in event.low_out.to_be_bytes() {
            append_byte_hex(out, byte);
        }
        for byte in event.range_out.to_be_bytes() {
            append_byte_hex(out, byte);
        }
        append_byte_hex(out, event.bits_left_out);
        append_byte_hex(out, u8::from(event.write_out));
    }
}

fn append_context_event_records_hex(out: &mut String, events: &[VvcCabacDumpContextEvent]) {
    for event in events {
        append_byte_hex(out, event.ctx_id);
        append_byte_hex(out, u8::from(event.bin));
        for byte in event.range.to_be_bytes() {
            append_byte_hex(out, byte);
        }
        for byte in event.lps.to_be_bytes() {
            append_byte_hex(out, byte);
        }
        append_byte_hex(out, u8::from(event.mps));
    }
}

fn append_hex_bytes(out: &mut String, bits: &[bool]) {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    for chunk in bits.chunks(8) {
        let mut byte = 0u8;
        for bit in chunk {
            byte = (byte << 1) | u8::from(*bit);
        }
        byte <<= 8 - chunk.len();
        out.push(HEX[(byte >> 4) as usize] as char);
        out.push(HEX[(byte & 0x0f) as usize] as char);
    }
}

fn append_symbol_records_hex(out: &mut String, symbols: &[VvcCabacDumpSymbol]) {
    for symbol in symbols {
        append_byte_hex(out, symbol.kind);
        for byte in symbol.data.to_be_bytes() {
            append_byte_hex(out, byte);
        }
    }
}

fn append_byte_hex(out: &mut String, byte: u8) {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    out.push(HEX[(byte >> 4) as usize] as char);
    out.push(HEX[(byte & 0x0f) as usize] as char);
}

fn encode_ctu_partition_body(
    cabac: &mut VvcCabacEncoder,
    params: VvcCtuPartitionParams,
    slice_config: VvcSliceSyntaxConfig,
) {
    let mut ctu = VvcCtuCabacGenerator::new(
        params.luma_dc_abs_level,
        params.luma_dc_negative,
        slice_config,
    );
    for op in VvcCtuCabacOp::yuv420_ctu_partition(params) {
        ctu.emit(cabac, op);
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[allow(dead_code)]
enum VvcTreeType {
    SingleTree,
    DualTreeLuma,
    DualTreeChroma,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum VvcPartSplit {
    None,
    Quad,
    HorizontalBinary,
    VerticalBinary,
    HorizontalTernary,
    VerticalTernary,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct VvcCodingTreeNode {
    x: u16,
    y: u16,
    width: u16,
    height: u16,
    cqt_depth: u8,
    mtt_depth: u8,
    implicit_mtt_depth: u8,
    tree_type: VvcTreeType,
    split_history: [VvcPartSplit; 2],
}

impl VvcCodingTreeNode {
    fn root(width: u16, height: u16, tree_type: VvcTreeType) -> Self {
        Self {
            x: 0,
            y: 0,
            width,
            height,
            cqt_depth: 0,
            mtt_depth: 0,
            implicit_mtt_depth: 0,
            tree_type,
            split_history: [VvcPartSplit::None; 2],
        }
    }

    fn with_split_at_current_depth(self, split: VvcPartSplit) -> [VvcPartSplit; 2] {
        let mut split_history = self.split_history;
        let depth = usize::from(self.cqt_depth + self.mtt_depth);
        if depth < split_history.len() {
            split_history[depth] = split;
        }
        split_history
    }

    fn qt_child(self, child_idx: u8) -> Self {
        debug_assert!(child_idx < 4);
        let half_width = self.width / 2;
        let half_height = self.height / 2;
        Self {
            x: self.x + u16::from(child_idx & 1) * half_width,
            y: self.y + u16::from(child_idx >> 1) * half_height,
            width: half_width,
            height: half_height,
            cqt_depth: self.cqt_depth + 1,
            mtt_depth: 0,
            implicit_mtt_depth: 0,
            tree_type: self.tree_type,
            split_history: self.with_split_at_current_depth(VvcPartSplit::Quad),
        }
    }

    fn mtt_child(self, vertical: bool, child_idx: u8) -> Self {
        debug_assert!(child_idx < 2);
        let width = if vertical { self.width / 2 } else { self.width };
        let height = if vertical {
            self.height
        } else {
            self.height / 2
        };
        Self {
            x: self.x + u16::from(vertical) * u16::from(child_idx) * width,
            y: self.y + u16::from(!vertical) * u16::from(child_idx) * height,
            width,
            height,
            cqt_depth: self.cqt_depth,
            mtt_depth: self.mtt_depth + 1,
            implicit_mtt_depth: self.implicit_mtt_depth,
            tree_type: self.tree_type,
            split_history: self.with_split_at_current_depth(if vertical {
                VvcPartSplit::VerticalBinary
            } else {
                VvcPartSplit::HorizontalBinary
            }),
        }
    }

    fn implicit_mtt_child(self, vertical: bool, child_idx: u8) -> Self {
        let mut child = self.mtt_child(vertical, child_idx);
        child.implicit_mtt_depth = self.implicit_mtt_depth + 1;
        child
    }

    #[allow(dead_code)]
    fn tt_child(self, vertical: bool, child_idx: u8) -> Self {
        debug_assert!(child_idx < 3);
        let quarter_width = self.width / 4;
        let quarter_height = self.height / 4;
        let (width, x_offset) = if vertical {
            let width = if child_idx == 1 {
                self.width / 2
            } else {
                quarter_width
            };
            let x_offset = match child_idx {
                0 => 0,
                1 => quarter_width,
                2 => 3 * quarter_width,
                _ => unreachable!(),
            };
            (width, x_offset)
        } else {
            (self.width, 0)
        };
        let (height, y_offset) = if vertical {
            (self.height, 0)
        } else {
            let height = if child_idx == 1 {
                self.height / 2
            } else {
                quarter_height
            };
            let y_offset = match child_idx {
                0 => 0,
                1 => quarter_height,
                2 => 3 * quarter_height,
                _ => unreachable!(),
            };
            (height, y_offset)
        };
        Self {
            x: self.x + x_offset,
            y: self.y + y_offset,
            width,
            height,
            cqt_depth: self.cqt_depth,
            mtt_depth: self.mtt_depth + 1,
            implicit_mtt_depth: self.implicit_mtt_depth,
            tree_type: self.tree_type,
            split_history: self.with_split_at_current_depth(if vertical {
                VvcPartSplit::VerticalTernary
            } else {
                VvcPartSplit::HorizontalTernary
            }),
        }
    }

    fn intersects_visible(self, visible_width: u16, visible_height: u16) -> bool {
        self.x < visible_width && self.y < visible_height
    }

    fn fits_visible(self, visible_width: u16, visible_height: u16) -> bool {
        self.x + self.width <= visible_width && self.y + self.height <= visible_height
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct VvcCodedNeighbour {
    width: u16,
    height: u16,
    qt_depth: u8,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct VvcSplitAvailability {
    can_no_split: bool,
    can_qt: bool,
    can_bt_horizontal: bool,
    can_bt_vertical: bool,
    can_tt_horizontal: bool,
    can_tt_vertical: bool,
}

impl VvcSplitAvailability {
    #[allow(dead_code)]
    fn qt_only(can_no_split: bool) -> Self {
        Self {
            can_no_split,
            can_qt: true,
            can_bt_horizontal: false,
            can_bt_vertical: false,
            can_tt_horizontal: false,
            can_tt_vertical: false,
        }
    }

    fn split_alternatives(self) -> u8 {
        u8::from(self.can_bt_vertical)
            + u8::from(self.can_bt_horizontal)
            + u8::from(self.can_tt_vertical)
            + u8::from(self.can_tt_horizontal)
            + (2 * u8::from(self.can_qt))
    }

    fn can_split(self) -> bool {
        self.can_qt
            || self.can_bt_horizontal
            || self.can_bt_vertical
            || self.can_tt_horizontal
            || self.can_tt_vertical
    }

    fn can_btt(self) -> bool {
        self.can_bt_horizontal
            || self.can_bt_vertical
            || self.can_tt_horizontal
            || self.can_tt_vertical
    }

    fn horizontal_alternatives(self) -> u8 {
        u8::from(self.can_bt_horizontal) + u8::from(self.can_tt_horizontal)
    }

    fn vertical_alternatives(self) -> u8 {
        u8::from(self.can_bt_vertical) + u8::from(self.can_tt_vertical)
    }

    fn can_horizontal_split(self) -> bool {
        self.can_bt_horizontal || self.can_tt_horizontal
    }

    fn can_vertical_split(self) -> bool {
        self.can_bt_vertical || self.can_tt_vertical
    }

    fn with_implicit_split(self, implicit_split: VvcPartSplit) -> Self {
        if implicit_split == VvcPartSplit::None {
            return self;
        }

        // ITU-T H.266 clause 6.4.1 / VTM QTBTPartitioner::canSplit(): when a
        // block crosses the picture boundary, no-split and ternary splits are
        // disabled; the implicit split direction is exposed as the only BT
        // alternative, while QT remains available when the partitioner permits
        // it or when no implicit BT can be represented.
        let can_bt_horizontal = implicit_split == VvcPartSplit::HorizontalBinary;
        let can_bt_vertical = implicit_split == VvcPartSplit::VerticalBinary;
        Self {
            can_no_split: false,
            can_qt: self.can_qt
                || (!can_bt_horizontal && !can_bt_vertical && implicit_split == VvcPartSplit::Quad),
            can_bt_horizontal,
            can_bt_vertical,
            can_tt_horizontal: false,
            can_tt_vertical: false,
        }
    }

    fn split_is_legal(self, split: VvcPartSplit) -> bool {
        match split {
            VvcPartSplit::None => self.can_no_split,
            VvcPartSplit::Quad => self.can_qt,
            VvcPartSplit::HorizontalBinary => self.can_bt_horizontal,
            VvcPartSplit::VerticalBinary => self.can_bt_vertical,
            VvcPartSplit::HorizontalTernary => self.can_tt_horizontal,
            VvcPartSplit::VerticalTernary => self.can_tt_vertical,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct VvcSplitCtxInput {
    node: VvcCodingTreeNode,
    left: Option<VvcCodedNeighbour>,
    above: Option<VvcCodedNeighbour>,
    availability: VvcSplitAvailability,
}

impl VvcSplitCtxInput {
    fn split_cu_flag_ctx(self) -> u8 {
        // ITU-T H.266 clause 9.3.4.2.2 / Table 133 derives ctxInc for
        // split_cu_flag from the actual left/above CU sizes in the current
        // channel plus the legal split alternatives returned by canSplit().
        let split_alternatives = self.availability.split_alternatives();
        debug_assert!(split_alternatives > 0);
        let ctx_set_idx = (split_alternatives - 1) / 2;
        let left_smaller = self
            .left
            .map(|left| left.height < self.node.height)
            .unwrap_or(false);
        let above_smaller = self
            .above
            .map(|above| above.width < self.node.width)
            .unwrap_or(false);
        u8::from(left_smaller) + u8::from(above_smaller) + (3 * ctx_set_idx)
    }

    fn split_qt_flag_ctx(self) -> u8 {
        // ITU-T H.266 clause 9.3.4.2.2 / Table 133 derives ctxInc for
        // split_qt_flag from neighbouring CU QT depth and the current QT-depth
        // context set. Keep neighbour availability as data instead of assuming
        // top-left-only CTUs.
        let left_deeper_qt = self
            .left
            .map(|left| left.qt_depth > self.node.cqt_depth)
            .unwrap_or(false);
        let above_deeper_qt = self
            .above
            .map(|above| above.qt_depth > self.node.cqt_depth)
            .unwrap_or(false);
        u8::from(left_deeper_qt)
            + u8::from(above_deeper_qt)
            + (3 * u8::from(self.node.cqt_depth >= 2))
    }

    fn mtt_vertical_ctx(self) -> u8 {
        // ITU-T H.266 clause 9.3.4.2.2 / Table 133 derives ctxInc for
        // mtt_split_cu_vertical_flag from the horizontal/vertical split
        // alternatives and, when tied, the relative depth implied by the
        // actual left/above CU dimensions.
        let num_hor = self.availability.horizontal_alternatives();
        let num_ver = self.availability.vertical_alternatives();
        match num_ver.cmp(&num_hor) {
            std::cmp::Ordering::Less => 3,
            std::cmp::Ordering::Greater => 4,
            std::cmp::Ordering::Equal => {
                let (Some(left), Some(above)) = (self.left, self.above) else {
                    return 0;
                };
                let dep_above = self.node.width / above.width.max(1);
                let dep_left = self.node.height / left.height.max(1);
                match dep_above.cmp(&dep_left) {
                    std::cmp::Ordering::Less => 1,
                    std::cmp::Ordering::Greater => 2,
                    std::cmp::Ordering::Equal => 0,
                }
            }
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct VvcSplitSyntaxDecision {
    split_input: VvcSplitCtxInput,
    selected_split: VvcPartSplit,
}

impl VvcSplitSyntaxDecision {
    fn new(split_input: VvcSplitCtxInput, selected_split: VvcPartSplit) -> Self {
        debug_assert!(
            split_input.availability.split_is_legal(selected_split),
            "illegal selected split {:?} for {:?}",
            selected_split,
            split_input
        );
        Self {
            split_input,
            selected_split,
        }
    }

    fn split_flag(self) -> Option<(u8, bool)> {
        let availability = self.split_input.availability;
        if availability.can_no_split && availability.can_split() {
            Some((
                self.split_input.split_cu_flag_ctx(),
                self.selected_split != VvcPartSplit::None,
            ))
        } else {
            None
        }
    }

    fn split_qt_flag(self) -> Option<(u8, bool)> {
        let availability = self.split_input.availability;
        if self.selected_split == VvcPartSplit::None {
            return None;
        }
        if availability.can_qt && availability.can_btt() {
            Some((
                self.split_input.split_qt_flag_ctx(),
                self.selected_split == VvcPartSplit::Quad,
            ))
        } else {
            None
        }
    }

    fn mtt_vertical_flag(self) -> Option<(u8, bool)> {
        let availability = self.split_input.availability;
        if matches!(self.selected_split, VvcPartSplit::None | VvcPartSplit::Quad) {
            return None;
        }
        let is_vertical = matches!(
            self.selected_split,
            VvcPartSplit::VerticalBinary | VvcPartSplit::VerticalTernary
        );
        if availability.can_vertical_split() && availability.can_horizontal_split() {
            Some((self.split_input.mtt_vertical_ctx(), is_vertical))
        } else {
            None
        }
    }

    fn mtt_binary_flag(self) -> Option<(u8, bool)> {
        let availability = self.split_input.availability;
        let is_vertical = match self.selected_split {
            VvcPartSplit::VerticalBinary | VvcPartSplit::VerticalTernary => true,
            VvcPartSplit::HorizontalBinary | VvcPartSplit::HorizontalTernary => false,
            VvcPartSplit::None | VvcPartSplit::Quad => return None,
        };
        let can_binary = if is_vertical {
            availability.can_bt_vertical
        } else {
            availability.can_bt_horizontal
        };
        let can_ternary = if is_vertical {
            availability.can_tt_vertical
        } else {
            availability.can_tt_horizontal
        };
        if can_binary && can_ternary {
            Some((
                VvcCtuCabacOp::mtt_binary_ctx(is_vertical, self.split_input.node.mtt_depth),
                matches!(
                    self.selected_split,
                    VvcPartSplit::HorizontalBinary | VvcPartSplit::VerticalBinary
                ),
            ))
        } else {
            None
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct VvcCodedCuRegion {
    x: u16,
    y: u16,
    width: u16,
    height: u16,
    qt_depth: u8,
}

impl VvcCodedCuRegion {
    fn from_leaf(node: VvcCodingTreeNode) -> Self {
        Self {
            x: node.x,
            y: node.y,
            width: node.width,
            height: node.height,
            qt_depth: node.cqt_depth,
        }
    }

    fn contains(self, x: u16, y: u16) -> bool {
        x >= self.x && x < self.x + self.width && y >= self.y && y < self.y + self.height
    }

    fn as_neighbour(self) -> VvcCodedNeighbour {
        VvcCodedNeighbour {
            width: self.width,
            height: self.height,
            qt_depth: self.qt_depth,
        }
    }
}

#[derive(Debug, Default, Clone)]
struct VvcCodedCuMap {
    regions: Vec<VvcCodedCuRegion>,
}

impl VvcCodedCuMap {
    fn record_leaf(&mut self, node: VvcCodingTreeNode) {
        self.regions.push(VvcCodedCuRegion::from_leaf(node));
    }

    fn left_neighbour(&self, node: VvcCodingTreeNode) -> Option<VvcCodedNeighbour> {
        node.x
            .checked_sub(1)
            .and_then(|x| self.neighbour_at(x, node.y))
    }

    fn above_neighbour(&self, node: VvcCodingTreeNode) -> Option<VvcCodedNeighbour> {
        node.y
            .checked_sub(1)
            .and_then(|y| self.neighbour_at(node.x, y))
    }

    fn neighbour_at(&self, x: u16, y: u16) -> Option<VvcCodedNeighbour> {
        self.regions
            .iter()
            .rev()
            .copied()
            .find(|region| region.contains(x, y))
            .map(VvcCodedCuRegion::as_neighbour)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct VvcCclmEligibilityInput {
    is_dual_tree: bool,
    ctu_size: u16,
    chroma_sampling: ChromaSampling,
    node: VvcCodingTreeNode,
    depth1_split: VvcPartSplit,
    depth2_split: VvcPartSplit,
    colocated_luma_depth1_split: VvcPartSplit,
    colocated_luma_uses_isp: bool,
}

impl VvcCclmEligibilityInput {
    fn allowed(self) -> bool {
        // VTM CodingUnit::checkCCLMAllowed implements the VVC dual-tree CCLM
        // restrictions. For CTU size 64/128, CCLM is legal only for specific
        // chroma split paths, then a luma-side guard disallows non-QT 64x64
        // luma splits and ISP. Keep every input explicit so future multi-CTU
        // and non-4:2:0 paths can replace these current subset values.
        if !self.is_dual_tree || self.ctu_size <= 32 {
            return true;
        }

        let chroma_path_allowed = match (self.depth1_split, self.depth2_split) {
            (VvcPartSplit::Quad, _)
            | (VvcPartSplit::HorizontalBinary, VvcPartSplit::VerticalBinary) => {
                self.chroma_sampling != ChromaSampling::Cs420
                    || (self.node.width <= 16 && self.node.height <= 16)
            }
            (VvcPartSplit::None, _) => {
                self.chroma_sampling != ChromaSampling::Cs420
                    || (self.node.width == 32 && self.node.height == 32)
            }
            (VvcPartSplit::HorizontalBinary, VvcPartSplit::None) => {
                self.chroma_sampling != ChromaSampling::Cs420
                    || (self.node.width == 32 && self.node.height == 16)
            }
            _ => false,
        };

        chroma_path_allowed
            && self.colocated_luma_depth1_split == VvcPartSplit::Quad
            && !self.colocated_luma_uses_isp
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct VvcPartitionCtx {
    visible_width: u16,
    visible_height: u16,
}

impl VvcPartitionCtx {
    fn luma(visible_width: u16, visible_height: u16) -> Self {
        Self {
            visible_width,
            visible_height,
        }
    }

    fn split_ctx_input_from_luma_map(
        self,
        node: VvcCodingTreeNode,
        availability: VvcSplitAvailability,
        coded_map: &VvcCodedCuMap,
    ) -> VvcSplitCtxInput {
        // ITU-T H.266 clause 9.3.4.2.2 derives split contexts from the CU
        // covering the left/above sample positions. Keep this tied to coded
        // traversal state instead of estimating neighbour dimensions.
        VvcSplitCtxInput {
            node,
            left: if node.x == 0 || node.y >= self.visible_height {
                None
            } else {
                coded_map.left_neighbour(node)
            },
            above: if node.y == 0 || node.x >= self.visible_width {
                None
            } else {
                coded_map.above_neighbour(node)
            },
            availability,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[allow(dead_code)]
struct VvcLastSigCoeffPrefixCtxInput {
    is_luma: bool,
    log2_tb_size: u8,
    bin_idx: u8,
}

#[allow(dead_code)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum VvcCtuCabacOp {
    QtSplit {
        node: VvcCodingTreeNode,
        split_input: VvcSplitCtxInput,
    },
    BtSplit {
        node: VvcCodingTreeNode,
        split_input: VvcSplitCtxInput,
        split: VvcPartSplit,
    },
    LumaLeafWithSplitCtx {
        node: VvcCodingTreeNode,
        split_input: VvcSplitCtxInput,
    },
    ChromaTree {
        node: VvcCodingTreeNode,
        visible_width: u16,
        visible_height: u16,
        chroma_sampling: ChromaSampling,
    },
}

impl VvcCtuCabacOp {
    fn yuv420_ctu_partition(params: VvcCtuPartitionParams) -> Vec<Self> {
        let root = VvcCodingTreeNode::root(
            params.root_width as u16,
            params.root_height as u16,
            VvcTreeType::DualTreeLuma,
        );
        let visible_chroma_width = params.visible_chroma_width();
        let visible_chroma_height = params.visible_chroma_height();
        let luma_ctx =
            VvcPartitionCtx::luma(params.visible_width as u16, params.visible_height as u16);
        let mut ops = Vec::new();
        let mut luma_cu_map = VvcCodedCuMap::default();
        Self::append_visible_luma_subtree(
            &mut ops,
            root,
            luma_ctx,
            VVC_CURRENT_MAX_LUMA_LEAF_SIZE,
            &mut luma_cu_map,
        );
        // VTM TypeDef.h TREE_C: separate chroma tree contains chroma and is
        // not split. The current dual-tree residual path attaches chroma CUs to
        // fixed luma regions and derives chroma sample coordinates from the
        // configured chroma subsampling instead of assuming 4:2:0 geometry.
        for node in params.current_chroma_tree_nodes() {
            ops.push(Self::ChromaTree {
                node,
                visible_width: visible_chroma_width,
                visible_height: visible_chroma_height,
                chroma_sampling: params.chroma_sampling,
            });
        }
        ops
    }

    fn append_visible_luma_subtree(
        ops: &mut Vec<Self>,
        node: VvcCodingTreeNode,
        partition_ctx: VvcPartitionCtx,
        max_leaf_size: u16,
        coded_map: &mut VvcCodedCuMap,
    ) {
        if !node.intersects_visible(partition_ctx.visible_width, partition_ctx.visible_height) {
            return;
        }
        if node.fits_visible(partition_ctx.visible_width, partition_ctx.visible_height)
            && Self::luma_leaf_allowed(node, max_leaf_size)
        {
            ops.push(Self::LumaLeafWithSplitCtx {
                node,
                split_input: partition_ctx.split_ctx_input_from_luma_map(
                    node,
                    Self::luma_split_availability(node),
                    coded_map,
                ),
            });
            coded_map.record_leaf(node);
            return;
        }

        if !node.fits_visible(partition_ctx.visible_width, partition_ctx.visible_height) {
            Self::append_implicit_boundary_luma_children(
                ops,
                node,
                partition_ctx,
                max_leaf_size,
                coded_map,
            );
            return;
        }

        debug_assert!(node.width > max_leaf_size || node.height > VVC_CURRENT_MAX_LUMA_LEAF_HEIGHT);
        if node.mtt_depth > 0 {
            Self::append_visible_luma_mtt_subtree(
                ops,
                node,
                partition_ctx,
                max_leaf_size,
                coded_map,
            );
            return;
        }
        let split_input = partition_ctx.split_ctx_input_from_luma_map(
            node,
            Self::luma_split_availability(node),
            coded_map,
        );
        ops.push(Self::QtSplit { node, split_input });
        for child_idx in 0..4 {
            Self::append_visible_luma_subtree(
                ops,
                node.qt_child(child_idx),
                partition_ctx,
                max_leaf_size,
                coded_map,
            );
        }
    }

    fn luma_leaf_allowed(node: VvcCodingTreeNode, max_leaf_size: u16) -> bool {
        (node.width <= max_leaf_size && node.height <= VVC_CURRENT_MAX_LUMA_LEAF_HEIGHT)
            || (node.mtt_depth > 0
                && ((node.width <= VVC_CURRENT_MAX_LUMA_BOUNDARY_BT_SIZE
                    && node.height <= VVC_CURRENT_MAX_LUMA_LEAF_HEIGHT)
                    || (node.height <= VVC_CURRENT_MAX_LUMA_BOUNDARY_BT_SIZE
                        && node.width <= max_leaf_size)))
    }

    fn append_visible_luma_mtt_subtree(
        ops: &mut Vec<Self>,
        node: VvcCodingTreeNode,
        partition_ctx: VvcPartitionCtx,
        max_leaf_size: u16,
        coded_map: &mut VvcCodedCuMap,
    ) {
        let vertical = node.width > max_leaf_size
            && (node.height <= max_leaf_size || node.width >= node.height);
        let split_input = partition_ctx.split_ctx_input_from_luma_map(
            node,
            Self::luma_split_availability(node),
            coded_map,
        );
        ops.push(Self::BtSplit {
            node,
            split_input,
            split: if vertical {
                VvcPartSplit::VerticalBinary
            } else {
                VvcPartSplit::HorizontalBinary
            },
        });
        for child_idx in 0..2 {
            Self::append_visible_luma_subtree(
                ops,
                node.mtt_child(vertical, child_idx),
                partition_ctx,
                max_leaf_size,
                coded_map,
            );
        }
    }

    fn append_implicit_boundary_luma_children(
        ops: &mut Vec<Self>,
        node: VvcCodingTreeNode,
        partition_ctx: VvcPartitionCtx,
        max_leaf_size: u16,
        coded_map: &mut VvcCodedCuMap,
    ) {
        let bottom_left_in_pic = node.x < partition_ctx.visible_width
            && node.y + node.height - 1 < partition_ctx.visible_height;
        let top_right_in_pic = node.x + node.width - 1 < partition_ctx.visible_width
            && node.y < partition_ctx.visible_height;
        let implicit_bt_allowed = node.width <= VVC_CURRENT_MAX_LUMA_BOUNDARY_BT_SIZE
            && node.height <= VVC_CURRENT_MAX_LUMA_BOUNDARY_BT_SIZE;
        if (!bottom_left_in_pic && !top_right_in_pic) || !implicit_bt_allowed {
            for child_idx in 0..4 {
                Self::append_visible_luma_subtree(
                    ops,
                    node.qt_child(child_idx),
                    partition_ctx,
                    max_leaf_size,
                    coded_map,
                );
            }
        } else if !bottom_left_in_pic {
            let split = VvcPartSplit::HorizontalBinary;
            let split_input = partition_ctx.split_ctx_input_from_luma_map(
                node,
                Self::luma_split_availability(node).with_implicit_split(split),
                coded_map,
            );
            ops.push(Self::BtSplit {
                node,
                split_input,
                split,
            });
            for child_idx in 0..2 {
                Self::append_visible_luma_subtree(
                    ops,
                    node.implicit_mtt_child(false, child_idx),
                    partition_ctx,
                    max_leaf_size,
                    coded_map,
                );
            }
        } else if !top_right_in_pic {
            let split = VvcPartSplit::VerticalBinary;
            let split_input = partition_ctx.split_ctx_input_from_luma_map(
                node,
                Self::luma_split_availability(node).with_implicit_split(split),
                coded_map,
            );
            ops.push(Self::BtSplit {
                node,
                split_input,
                split,
            });
            for child_idx in 0..2 {
                Self::append_visible_luma_subtree(
                    ops,
                    node.implicit_mtt_child(true, child_idx),
                    partition_ctx,
                    max_leaf_size,
                    coded_map,
                );
            }
        }
    }

    fn luma_split_availability(node: VvcCodingTreeNode) -> VvcSplitAvailability {
        debug_assert_eq!(node.tree_type, VvcTreeType::DualTreeLuma);
        // Approximation of VTM QTBTPartitioner::canSplit for the current
        // all-intra luma constraints. All dimensions are luma samples here.
        let allow_qt = node.mtt_depth == 0
            && node.width > VVC_CURRENT_MIN_LUMA_QT_SIZE
            && node.height > VVC_CURRENT_MIN_LUMA_QT_SIZE;
        let too_small_for_btt =
            node.width <= VVC_MIN_CODING_BLOCK_SIZE && node.height <= VVC_MIN_CODING_BLOCK_SIZE;
        let too_large_for_btt = (node.width > VVC_CURRENT_MAX_LUMA_BOUNDARY_BT_SIZE
            || node.height > VVC_CURRENT_MAX_LUMA_BOUNDARY_BT_SIZE)
            && (node.width > VVC_CURRENT_MAX_LUMA_BOUNDARY_BT_SIZE
                || node.height > VVC_CURRENT_MAX_LUMA_BOUNDARY_BT_SIZE);
        let max_btt_depth = 3 + node.implicit_mtt_depth;
        let can_btt = node.mtt_depth < max_btt_depth && !too_small_for_btt && !too_large_for_btt;
        let exceeds_bt_size = node.width > VVC_CURRENT_MAX_LUMA_BOUNDARY_BT_SIZE
            || node.height > VVC_CURRENT_MAX_LUMA_BOUNDARY_BT_SIZE;
        VvcSplitAvailability {
            can_no_split: true,
            can_qt: allow_qt,
            can_bt_horizontal: can_btt
                && !exceeds_bt_size
                && node.height > VVC_MIN_CODING_BLOCK_SIZE
                && !(node.width > VVC_MAX_TB_SIZEY && node.height <= VVC_MAX_TB_SIZEY),
            can_bt_vertical: can_btt
                && !exceeds_bt_size
                && node.width > VVC_MIN_CODING_BLOCK_SIZE
                && !(node.width <= VVC_MAX_TB_SIZEY && node.height > VVC_MAX_TB_SIZEY),
            can_tt_horizontal: can_btt
                && node.height > 2 * VVC_MIN_CODING_BLOCK_SIZE
                && node.height <= VVC_CURRENT_MAX_LUMA_BOUNDARY_BT_SIZE
                && node.width <= VVC_CURRENT_MAX_LUMA_BOUNDARY_BT_SIZE
                && node.width <= VVC_MAX_TB_SIZEY
                && node.height <= VVC_MAX_TB_SIZEY,
            can_tt_vertical: can_btt
                && node.width > 2 * VVC_MIN_CODING_BLOCK_SIZE
                && node.width <= VVC_CURRENT_MAX_LUMA_BOUNDARY_BT_SIZE
                && node.height <= VVC_CURRENT_MAX_LUMA_BOUNDARY_BT_SIZE
                && node.width <= VVC_MAX_TB_SIZEY
                && node.height <= VVC_MAX_TB_SIZEY,
        }
    }

    fn mtt_binary_ctx(vertical: bool, mtt_depth: u8) -> u8 {
        // ITU-T H.266 (V4) clause 9.3.4.2.1, Table 132:
        // ctxInc = (2 * mtt_split_cu_vertical_flag) + (mttDepth <= 1 ? 1 : 0).
        (2 * u8::from(vertical)) + u8::from(mtt_depth <= 1)
    }
}

#[derive(Debug, Clone)]
struct VvcCtuCabacGenerator {
    contexts: VvcCabacContexts,
    luma_dc_abs_level: u8,
    luma_dc_negative: bool,
    slice_config: VvcSliceSyntaxConfig,
}

impl VvcCtuCabacGenerator {
    fn new(
        luma_dc_abs_level: u8,
        luma_dc_negative: bool,
        slice_config: VvcSliceSyntaxConfig,
    ) -> Self {
        Self {
            contexts: VvcCabacContexts::new(),
            luma_dc_abs_level,
            luma_dc_negative,
            slice_config,
        }
    }

    fn emit(&mut self, cabac: &mut VvcCabacEncoder, op: VvcCtuCabacOp) {
        if std::env::var_os("FRAMEFORGE_CABAC_OP_TRACE").is_some() {
            eprintln!("FF_CABAC_OP {op:?}");
        }
        match op {
            VvcCtuCabacOp::QtSplit { node, split_input } => {
                self.emit_luma_split_cu_mode(cabac, node, split_input, VvcPartSplit::Quad)
            }
            VvcCtuCabacOp::BtSplit {
                node,
                split_input,
                split,
            } => self.emit_luma_split_cu_mode(cabac, node, split_input, split),
            VvcCtuCabacOp::LumaLeafWithSplitCtx { node, split_input } => {
                self.emit_luma_split_cu_mode(cabac, node, split_input, VvcPartSplit::None);
                self.emit_luma_multi_ref_line(cabac, node);
                self.emit_luma_intra_prediction_mode(cabac, node);
                self.emit_luma_residual(cabac, node);
            }
            VvcCtuCabacOp::ChromaTree {
                node,
                visible_width,
                visible_height,
                chroma_sampling,
            } => self.emit_chroma_tree(cabac, node, visible_width, visible_height, chroma_sampling),
        }
    }

    fn emit_luma_split_cu_mode(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        node: VvcCodingTreeNode,
        split_input: VvcSplitCtxInput,
        selected_split: VvcPartSplit,
    ) {
        debug_assert_eq!(node, split_input.node);
        debug_assert_eq!(node.tree_type, VvcTreeType::DualTreeLuma);
        // ITU-T H.266 clause 7.3.11.4 split_cu_mode() syntax order:
        // split_cu_flag, optional split_qt_flag, optional MTT direction, then
        // optional binary-vs-ternary flag. The helper derives bin presence from
        // canSplit() outputs before VTM comparison so context and syntax drift
        // remain visible in this model.
        let decision = VvcSplitSyntaxDecision::new(split_input, selected_split);
        if let Some((ctx, value)) = decision.split_flag() {
            self.contexts
                .encode(cabac, VvcCabacContext::SplitFlag(ctx), value);
        }
        if let Some((ctx, value)) = decision.split_qt_flag() {
            self.contexts
                .encode(cabac, VvcCabacContext::SplitQtFlag(ctx), value);
        }
        if let Some((ctx, value)) = decision.mtt_vertical_flag() {
            self.contexts
                .encode(cabac, VvcCabacContext::MttSplitCuVerticalFlag(ctx), value);
        }
        if let Some((ctx, value)) = decision.mtt_binary_flag() {
            self.contexts
                .encode(cabac, VvcCabacContext::MttSplitCuBinaryFlag(ctx), value);
        }
    }

    fn emit_luma_intra_prediction_mode(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        node: VvcCodingTreeNode,
    ) {
        debug_assert_eq!(node.tree_type, VvcTreeType::DualTreeLuma);
        // VVC 7.3.11.5 intra_luma_pred_modes. The current generated subset
        // uses the explicit remaining-mode branch so the following residual
        // syntax matches the decoder parser for the supported intra picture setup.
        // Future work should derive the selected mode from prediction costs.
        self.contexts
            .encode(cabac, VvcCabacContext::IntraLumaMpmFlag, false);
        cabac.encode_bins_ep(0b011010, 6);
    }

    fn emit_luma_multi_ref_line(&mut self, cabac: &mut VvcCabacEncoder, node: VvcCodingTreeNode) {
        debug_assert_eq!(node.tree_type, VvcTreeType::DualTreeLuma);
        // With sps_mrl_enabled_flag set, VVC extend_ref_line emits
        // MultiRefLineIdx(0) for intra luma CUs that are not on the first
        // luma line of the CTU. The current encoder always selects the first
        // reference line, so only the first MRL bin is needed.
        if self.slice_config.tools.mrl_enabled && node.y != 0 {
            self.contexts
                .encode(cabac, VvcCabacContext::MultiRefLineIdx(0), false);
        }
    }

    fn emit_luma_cbf(&mut self, cabac: &mut VvcCabacEncoder, node: VvcCodingTreeNode, cbf: bool) {
        debug_assert_eq!(node.tree_type, VvcTreeType::DualTreeLuma);
        // VVC 7.3.11.10 transform_unit emits tu_y_coded_flag / cbf_comp
        // through QtCbf[Y].
        self.contexts.encode(cabac, VvcCabacContext::QtCbfY(0), cbf);
    }

    fn emit_luma_residual(&mut self, cabac: &mut VvcCabacEncoder, node: VvcCodingTreeNode) {
        // The current residual subset anchors the input-derived DC level in
        // the first luma CU. Later CUs are reconstructed from intra prediction
        // until the software model grows a full per-CU prediction/residual loop.
        let anchor_cu = node.x == 0 && node.y == 0;
        let cbf = anchor_cu && self.luma_dc_abs_level != 0;
        self.emit_luma_cbf(cabac, node, cbf);
        if !cbf {
            return;
        }

        let log2_width = node.width.ilog2() as u8;
        let log2_height = node.height.ilog2() as u8;
        let stream = VvcResidualCabacSymbolStream::luma_dc_only(
            log2_width,
            log2_height,
            self.luma_dc_abs_level,
            self.luma_dc_negative,
        );
        let mut residual =
            VvcResidualCabacEncoder::new(&mut self.contexts, self.slice_config.residual_options());
        stream.emit(&mut residual, cabac);
    }

    fn emit_chroma_tree(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        node: VvcCodingTreeNode,
        visible_width: u16,
        visible_height: u16,
        chroma_sampling: ChromaSampling,
    ) {
        debug_assert_eq!(node.tree_type, VvcTreeType::DualTreeChroma);
        if !node.intersects_visible(visible_width, visible_height) {
            return;
        }
        self.emit_chroma_transform_only_leaf(cabac, node, chroma_sampling, 0);
    }

    fn emit_chroma_transform_only_leaf(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        node: VvcCodingTreeNode,
        chroma_sampling: ChromaSampling,
        cbf_cb_ctx: u8,
    ) {
        debug_assert_eq!(node.tree_type, VvcTreeType::DualTreeChroma);
        // VVC cu_pred_data() calls intra_chroma_pred_modes() for dual-tree
        // chroma intra CUs. VTM does not print a D_SYNTAX line for these bins,
        // so keep the syntax presence derived from the reader/writer code, not
        // from trace-line absence.
        if self.slice_config.tools.cclm_enabled && Self::chroma_cclm_allowed(node, chroma_sampling)
        {
            self.contexts
                .encode(cabac, VvcCabacContext::CclmModeFlag, false);
        }
        self.contexts
            .encode(cabac, VvcCabacContext::IntraChromaPredMode(0), false);
        // Chroma coefficient coding is not wired through the spec-shaped
        // residual encoder yet. Keep chroma residual disabled instead of
        // emitting a shortcut rem_abs payload that desynchronizes VTM.
        let cbf_cb = false;
        self.contexts
            .encode(cabac, VvcCabacContext::QtCbfCb(cbf_cb_ctx), cbf_cb);
        self.contexts
            .encode(cabac, VvcCabacContext::QtCbfCr(0), false);
    }

    fn chroma_cclm_allowed(node: VvcCodingTreeNode, chroma_sampling: ChromaSampling) -> bool {
        VvcCclmEligibilityInput {
            is_dual_tree: true,
            ctu_size: VVC_CTU_SIZE as u16,
            chroma_sampling,
            node,
            depth1_split: node.split_history[0],
            depth2_split: node.split_history[1],
            colocated_luma_depth1_split: VvcPartSplit::Quad,
            colocated_luma_uses_isp: false,
        }
        .allowed()
    }
}

#[cfg(test)]
mod tests;
