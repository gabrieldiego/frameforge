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
use cabac::{VvcCabacEncoder, VvcCtxEvent, VVC_CTX_EVENTS};
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
    first_residual_luma_block, inverse_transform_vvc_4x4_luma_dc, quantize_vvc_4x4_chroma,
    quantize_vvc_4x4_chroma_sample, quantize_vvc_4x4_luma_dc, reconstruct_vvc_4x4_chroma,
    second_residual_luma_block, transform_vvc_4x4_luma, Vvc4x4QuantizedTransformBlock,
    Vvc4x4ReconstructedLumaBlock, Vvc4x4TransformBlock, VvcResidualCabacSymbol,
    VvcResidualCtxConfig, VvcResidualLocalStats, VvcResidualPass1State, MAX_VVC_LUMA_TUS,
};
use residual::{
    quantize_vvc_4x4_frame, Vvc4x4QuantizedColor, VvcResidualCabacEncoder, VvcResidualCabacOptions,
    VvcResidualCabacSymbolStream, VvcResidualComponent, VVC_LUMA_DC_BASE,
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

impl Vvc4x4SampledFrame {
    fn solid(color: Vvc4x4SampledColor) -> Self {
        Self {
            geometry: VvcVideoGeometry::four_by_four(),
            format: Vvc4x4PictureFormat {
                chroma_sampling: ChromaSampling::Cs420,
                bit_depth: SampleBitDepth::Eight,
            },
            luma: vec![color.y; 16],
            cb: vec![color.u; 4],
            cr: vec![color.v; 4],
            chroma_len: 4,
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
enum VvcEntropyTokenKind {
    ContextBins {
        ctx_offset: usize,
        bins: &'static [bool],
    },
    RemAbsEp {
        component: VvcResidualComponent,
        value: u8,
        rice_param: u8,
    },
    SignEp {
        component: VvcResidualComponent,
        negative: bool,
    },
    Terminate,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct VvcEntropyToken {
    name: &'static str,
    kind: VvcEntropyTokenKind,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum VvcEntropyScheduleKind {
    Generated8x8,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum VvcCodingTreeBodyKind {
    Generated,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct VvcCodingTreeBody {
    kind: VvcCodingTreeBodyKind,
    coded: VvcCodedGeometry,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct VvcEntropySchedule {
    kind: VvcEntropyScheduleKind,
    tokens: Vec<VvcEntropyToken>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct VvcCtuPartitionParams {
    root_width: usize,
    root_height: usize,
    visible_width: usize,
    visible_height: usize,
    chroma_sampling: ChromaSampling,
    luma_leaf_count: usize,
    chroma_tu_count: usize,
    luma_dc_abs_level: u8,
    luma_dc_negative: bool,
}

impl VvcCtuPartitionParams {
    fn visible_chroma_width(self) -> u16 {
        (self.visible_width / chroma_subsample_x(self.chroma_sampling)) as u16
    }

    fn visible_chroma_height(self) -> u16 {
        (self.visible_height / chroma_subsample_y(self.chroma_sampling)) as u16
    }

    fn ctu_chroma_root(self) -> VvcCodingTreeNode {
        VvcCodingTreeNode::root(
            (VVC_CTU_SIZE / chroma_subsample_x(self.chroma_sampling)) as u16,
            (VVC_CTU_SIZE / chroma_subsample_y(self.chroma_sampling)) as u16,
            VvcTreeType::DualTreeChroma,
        )
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

pub fn skeleton_annex_b() -> Vec<u8> {
    let placeholder_rbsp = placeholder_rbsp();
    write_annex_b(&[
        VvcNalUnit {
            nal_unit_type: VvcNalUnitType::Vps,
            layer_id: 0,
            temporal_id: 0,
            rbsp_payload: placeholder_rbsp.clone(),
        },
        VvcNalUnit {
            nal_unit_type: VvcNalUnitType::Sps,
            layer_id: 0,
            temporal_id: 0,
            rbsp_payload: placeholder_rbsp.clone(),
        },
        VvcNalUnit {
            nal_unit_type: VvcNalUnitType::Pps,
            layer_id: 0,
            temporal_id: 0,
            rbsp_payload: placeholder_rbsp.clone(),
        },
        VvcNalUnit {
            nal_unit_type: VvcNalUnitType::IdrNLp,
            layer_id: 0,
            temporal_id: 0,
            rbsp_payload: placeholder_rbsp,
        },
        VvcNalUnit::eos(),
        VvcNalUnit::eob(),
    ])
    .expect("hard-coded skeleton NAL units should be valid")
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
        VvcVideoGeometry::four_by_four(),
        PixelFormat::Yuv420p8,
    )
}

pub fn vvc_yuv420p_annex_b_from_input(
    input: &[u8],
    params: VvcEncodeParams,
    format: PixelFormat,
) -> Result<Vec<u8>, String> {
    vvc_yuv_annex_b_from_input(input, params, VvcVideoGeometry::four_by_four(), format)
}

pub fn vvc_default_yuv_annex_b_from_input(
    input: &[u8],
    params: VvcEncodeParams,
    format: PixelFormat,
) -> Result<Vec<u8>, String> {
    vvc_yuv_annex_b_from_input(input, params, VvcVideoGeometry::four_by_four(), format)
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

pub fn sample_vvc_first_yuv420p8(
    input: &[u8],
    params: VvcEncodeParams,
) -> Result<Vvc4x4SampledColor, String> {
    Ok(sample_vvc_yuv_frame(
        input,
        params,
        VvcVideoGeometry::four_by_four(),
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

fn encode_vvc_coeff_token(negative: bool, magnitude: u8) -> u8 {
    0x40 | (u8::from(negative) << 5) | (magnitude & 0x1f)
}

fn vvc_4x4_sps_unit(geometry: VvcVideoGeometry) -> VvcNalUnit {
    vvc_sps_unit(geometry, VvcCodingTreeConfig::yuv420(), false)
}

fn vvc_palette_444_sps_unit(geometry: VvcVideoGeometry) -> VvcNalUnit {
    vvc_sps_unit(
        geometry,
        VvcCodingTreeConfig {
            chroma_sampling: ChromaSampling::Cs444,
        },
        true,
    )
}

fn vvc_sps_unit(
    geometry: VvcVideoGeometry,
    config: VvcCodingTreeConfig,
    palette_enabled: bool,
) -> VvcNalUnit {
    VvcNalUnit {
        nal_unit_type: VvcNalUnitType::Sps,
        layer_id: 0,
        temporal_id: 0,
        rbsp_payload: vvc_sps_payload(geometry, config, palette_enabled),
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
    vvc_sps_payload(geometry, VvcCodingTreeConfig::yuv420(), false)
}

fn vvc_sps_payload(
    geometry: VvcVideoGeometry,
    config: VvcCodingTreeConfig,
    palette_enabled: bool,
) -> Vec<u8> {
    let mut writer = VvcSyntaxWriter::new();
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
    writer.write_flag("sps_ref_pic_resampling_enabled_flag", true);
    writer.write_flag("sps_res_change_in_clvs_allowed_flag", false);
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
    writer.write_flag("sps_entry_point_offsets_present_flag", true);
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
    writer.write_flag("sps_transform_skip_enabled_flag", false);
    writer.write_flag("sps_mts_enabled_flag", false);
    writer.write_flag("sps_lfnst_enabled_flag", false);
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
    writer.write_flag("sps_temporal_mvp_enabled_flag", true);
    writer.write_flag("sps_sbtmvp_enabled_flag", true);
    writer.write_flag("sps_amvr_enabled_flag", true);
    writer.write_flag("sps_bdof_enabled_flag", false);
    writer.write_flag("sps_smvd_enabled_flag", false);
    writer.write_flag("sps_dmvr_enabled_flag", false);
    writer.write_flag("sps_mmvd_enabled_flag", true);
    writer.write_flag("sps_mmvd_fullpel_only_flag", true);
    writer.write_ue("sps_six_minus_max_num_merge_cand", 0);
    writer.write_flag("sps_sbt_enabled_flag", true);
    writer.write_flag("sps_affine_enabled_flag", true);
    writer.write_ue("sps_five_minus_max_num_subblock_merge_cand", 0);
    writer.write_flag("sps_affine_type_flag", true);
    writer.write_flag("sps_affine_amvr_enabled_flag", false);
    writer.write_flag("sps_affine_prof_enabled_flag", false);
    writer.write_flag("sps_bcw_enabled_flag", false);
    writer.write_flag("sps_ciip_enabled_flag", false);
    writer.write_flag("sps_gpm_enabled_flag", false);
    writer.write_ue("sps_log2_parallel_merge_level_minus2", 0);
    writer.write_flag("sps_isp_enabled_flag", false);
    writer.write_flag("sps_mrl_enabled_flag", true);
    writer.write_flag("sps_mip_enabled_flag", false);
    writer.write_flag("sps_cclm_enabled_flag", true);
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
    writer.write_flag("sps_dep_quant_enabled_flag", true);
    writer.write_flag("sps_sign_data_hiding_enabled_flag", false);
    writer.write_flag("sps_virtual_boundaries_enabled_flag", false);
    writer.write_flag("sps_timing_hrd_params_present_flag", false);
    writer.write_flag("sps_field_seq_flag", false);
    writer.write_flag("sps_vui_parameters_present_flag", false);
    writer.write_flag("sps_extension_present_flag", false);
    writer.rbsp_trailing_bits();
    debug_assert!(writer.is_byte_aligned());
    writer.into_bytes()
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
    writer.write_flag("pps_cabac_init_present_flag", true);
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
    writer.into_bytes()
}

fn vvc_4x4_slice_payload(
    picture_kind: Vvc4x4PictureKind,
    geometry: VvcVideoGeometry,
    color: Vvc4x4QuantizedColor,
) -> Vec<u8> {
    let mut writer = VvcSyntaxWriter::new();
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
    writer.write_flag("sh_dep_quant_used_flag", true);
    writer.write_flag("cabac_alignment_one_bit", true);
    if picture_kind == Vvc4x4PictureKind::Cra {
        writer.write_flag("cabac_alignment_one_bit", true);
    }
    writer.byte_align_zero("cabac_alignment_zero_bit");
    write_vvc_coding_tree_entropy(&mut writer, geometry, color);
    writer.rbsp_trailing_bits();
    debug_assert!(writer.is_byte_aligned());
    writer.into_bytes()
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
                const I_SLICE_INIT: [u8; 12] = [45, 45, 45, 45, 43, 37, 21, 22, 28, 29, 28, 29];
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
                const I_SLICE_INIT: [u8; 2] = [44, 34];
                I_SLICE_INIT[ctx as usize]
            }
            VvcCabacContext::QtCbfY(ctx) => {
                const I_SLICE_INIT: [u8; 4] = [15, 12, 5, 7];
                I_SLICE_INIT[ctx as usize]
            }
            VvcCabacContext::QtCbfCb(ctx) => {
                const I_SLICE_INIT: [u8; 2] = [12, 12];
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
                const LOG2_WINDOW: [u8; 2] = [5, 4];
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
        if std::env::var_os("FRAMEFORGE_CABAC_TRACE").is_some() {
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
                VvcCabacContext::IntraLumaPlanarFlag(idx) => {
                    &self.intra_luma_planar_flag[idx as usize]
                }
                VvcCabacContext::CclmModeFlag => &self.cclm_mode_flag,
                VvcCabacContext::IntraChromaPredMode(idx) => {
                    &self.intra_chroma_pred_mode[idx as usize]
                }
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
) {
    let bits = match vvc_coding_tree_body(geometry, color).kind {
        VvcCodingTreeBodyKind::Generated => vvc_cabac_bits(geometry, color),
    };
    writer.write_cabac_bits("cabac_vvc_quantized_residual_bits", &bits);
}

fn vvc_4x4_entropy_tokens(
    geometry: VvcVideoGeometry,
    color: Vvc4x4QuantizedColor,
) -> Vec<VvcEntropyToken> {
    vvc_entropy_schedule(geometry, color).tokens
}

fn vvc_entropy_schedule(
    geometry: VvcVideoGeometry,
    color: Vvc4x4QuantizedColor,
) -> VvcEntropySchedule {
    let _syntax_plan = vvc_coding_tree_plan(geometry);
    assert!(
        vvc_entropy_tokens_support_geometry(geometry),
        "non-8x8 entropy schedules require generated VVC syntax"
    );
    let kind = VvcEntropyScheduleKind::Generated8x8;

    VvcEntropySchedule {
        kind,
        tokens: vvc_8x8_mapped_entropy_tokens(color),
    }
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
            width: VVC_CTU_SIZE / 2,
            height: VVC_CTU_SIZE / 2,
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

fn vvc_8x8_mapped_entropy_tokens(color: Vvc4x4QuantizedColor) -> Vec<VvcEntropyToken> {
    let mut tokens = Vec::new();
    append_vvc_8x8_luma_tree_tokens(&mut tokens, color);
    append_vvc_4x4_chroma_tree_tokens(&mut tokens, color);
    tokens.push(VvcEntropyToken {
        name: "end_of_slice_segment_flag",
        kind: VvcEntropyTokenKind::Terminate,
    });
    tokens
}

fn append_vvc_8x8_luma_tree_tokens(tokens: &mut Vec<VvcEntropyToken>, color: Vvc4x4QuantizedColor) {
    tokens.extend([
        VvcEntropyToken {
            name: "split_cu_flag_luma_prefix",
            kind: VvcEntropyTokenKind::ContextBins {
                ctx_offset: 0,
                bins: &[false, true, false, true],
            },
        },
        VvcEntropyToken {
            name: "luma_intra_prediction_mode_prefix",
            kind: VvcEntropyTokenKind::ContextBins {
                ctx_offset: 4,
                bins: &[false, false, true, false],
            },
        },
        VvcEntropyToken {
            name: "luma_transform_unit_prefix",
            kind: VvcEntropyTokenKind::ContextBins {
                ctx_offset: 8,
                bins: &[true],
            },
        },
        VvcEntropyToken {
            name: "luma_abs_remainder",
            kind: VvcEntropyTokenKind::RemAbsEp {
                component: VvcResidualComponent::Luma,
                value: color.luma_rem,
                rice_param: 0,
            },
        },
        VvcEntropyToken {
            name: "luma_coeff_sign",
            kind: VvcEntropyTokenKind::SignEp {
                component: VvcResidualComponent::Luma,
                negative: true,
            },
        },
        VvcEntropyToken {
            name: "luma_residual_prefix",
            kind: VvcEntropyTokenKind::ContextBins {
                ctx_offset: 9,
                bins: &[true, false, true, true],
            },
        },
        VvcEntropyToken {
            name: "luma_residual_suffix",
            kind: VvcEntropyTokenKind::ContextBins {
                ctx_offset: 13,
                bins: &[true, false, false],
            },
        },
    ]);
}

fn append_vvc_4x4_chroma_tree_tokens(
    tokens: &mut Vec<VvcEntropyToken>,
    color: Vvc4x4QuantizedColor,
) {
    tokens.extend([
        VvcEntropyToken {
            name: "chroma_tree_prefix",
            kind: VvcEntropyTokenKind::ContextBins {
                ctx_offset: 16,
                bins: &[true, false, true],
            },
        },
        VvcEntropyToken {
            name: "cb_abs_remainder",
            kind: VvcEntropyTokenKind::RemAbsEp {
                component: VvcResidualComponent::ChromaCb,
                value: color.cb_rem,
                rice_param: 0,
            },
        },
        VvcEntropyToken {
            name: "cb_coeff_sign",
            kind: VvcEntropyTokenKind::SignEp {
                component: VvcResidualComponent::ChromaCb,
                negative: true,
            },
        },
    ]);
}

fn vvc_entropy_tokens_support_geometry(geometry: VvcVideoGeometry) -> bool {
    geometry.coded()
        == (VvcCodedGeometry {
            width: 8,
            height: 8,
        })
}

fn vvc_coding_tree_body(
    geometry: VvcVideoGeometry,
    _color: Vvc4x4QuantizedColor,
) -> VvcCodingTreeBody {
    let coded = geometry.coded();
    let kind = VvcCodingTreeBodyKind::Generated;
    VvcCodingTreeBody { kind, coded }
}

fn vvc_cabac_bits(geometry: VvcVideoGeometry, color: Vvc4x4QuantizedColor) -> Vec<bool> {
    if geometry.coded()
        != (VvcCodedGeometry {
            width: 8,
            height: 8,
        })
    {
        if let Some(params) = vvc_ctu_partition_params(geometry, color) {
            return vvc_ctu_partition_cabac_bits(params);
        }
        unimplemented!(
            "VVC coding tree for coded geometry {}x{} must be generated from syntax parameters",
            geometry.coded_width(),
            geometry.coded_height()
        );
    }

    let mut cabac = VvcCabacEncoder::new();
    cabac.start();
    for token in vvc_4x4_entropy_tokens(geometry, color) {
        match token.kind {
            VvcEntropyTokenKind::ContextBins { ctx_offset, bins } => {
                cabac.encode_ctx_bins(&VVC_CTX_EVENTS[ctx_offset..ctx_offset + bins.len()], bins);
            }
            VvcEntropyTokenKind::RemAbsEp {
                value, rice_param, ..
            } => {
                cabac.encode_rem_abs_ep(value as u32, rice_param as u32);
            }
            VvcEntropyTokenKind::SignEp { negative, .. } => {
                cabac.encode_bin_ep(negative);
            }
            VvcEntropyTokenKind::Terminate => {
                cabac.encode_bin_trm(true);
            }
        }
    }
    cabac.finish()
}

fn vvc_ctu_partition_params(
    geometry: VvcVideoGeometry,
    color: Vvc4x4QuantizedColor,
) -> Option<VvcCtuPartitionParams> {
    let coded = geometry.coded();
    if coded.width > VVC_CTU_SIZE
        || coded.height > VVC_CTU_SIZE
        || coded.width < 16
        || coded.height < 16
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
            root_width: coded.width,
            root_height: coded.height,
            visible_width: coded.width,
            visible_height: coded.height,
            chroma_sampling,
            luma_leaf_count: 1,
            chroma_tu_count,
            luma_dc_abs_level: color.luma_rem,
            luma_dc_negative: color.y < VVC_LUMA_DC_BASE as u8 && color.luma_rem != 0,
        });
    }
    if coded.width != VVC_CTU_SIZE && coded.height != VVC_CTU_SIZE {
        return None;
    }

    let luma_leaf_count = if coded.width == VVC_CTU_SIZE && coded.height == VVC_CTU_SIZE {
        1
    } else if coded.width == VVC_CTU_SIZE {
        // The top-right visible 16x16 corner uses horizontal BT splits on two
        // 8x16 halves to match the neighbour-derived partition constraints.
        52
    } else {
        // Rectangular 64-sample CTU views currently split each visible 16x16
        // area into position-dependent 8x8 edge patterns. The current 64x32
        // subset has one 7-leaf region, one 8-leaf region, and two 9-leaf
        // regions per visible half-CTU child.
        ((coded.width * coded.height) / (half_ctu * half_ctu)) * half_ctu
    };
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
        luma_leaf_count,
        chroma_tu_count,
        luma_dc_abs_level: color.luma_rem,
        luma_dc_negative: color.y < VVC_LUMA_DC_BASE as u8 && color.luma_rem != 0,
    })
}

fn vvc_ctu_partition_cabac_bits(params: VvcCtuPartitionParams) -> Vec<bool> {
    debug_assert!((16..=64).contains(&params.root_width));
    debug_assert!((16..=64).contains(&params.root_height));
    debug_assert!(
        (params.visible_width == params.root_width && params.visible_height == params.root_height)
            || params.visible_width == VVC_CTU_SIZE
            || params.visible_height == VVC_CTU_SIZE
    );
    debug_assert!(params.visible_width >= 16 && params.visible_height >= 16);
    debug_assert!(params.luma_leaf_count > 0);

    let mut cabac = VvcCabacEncoder::new();
    cabac.start();
    encode_ctu_partition_body(&mut cabac, params);
    cabac.encode_bin_trm(true);
    cabac.finish()
}

fn encode_ctu_partition_body(cabac: &mut VvcCabacEncoder, params: VvcCtuPartitionParams) {
    let mut ctu = VvcCtuCabacGenerator::new(params.luma_dc_abs_level, params.luma_dc_negative);
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
struct VvcCodingTreeNode {
    x: u16,
    y: u16,
    width: u16,
    height: u16,
    cqt_depth: u8,
    mtt_depth: u8,
    tree_type: VvcTreeType,
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
            tree_type,
        }
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
            tree_type: self.tree_type,
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
            tree_type: self.tree_type,
        }
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
            tree_type: self.tree_type,
        }
    }

    fn raster_child_idx(self) -> u8 {
        let col = u8::from(self.x != 0);
        let row = u8::from(self.y != 0);
        row * 2 + col
    }

    fn intersects_visible(self, visible_width: u16, visible_height: u16) -> bool {
        self.x < visible_width && self.y < visible_height
    }

    fn fits_visible(self, visible_width: u16, visible_height: u16) -> bool {
        self.x + self.width <= visible_width && self.y + self.height <= visible_height
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct VvcSplitCtxInput {
    available_left: bool,
    available_above: bool,
    condition_left: bool,
    condition_above: bool,
    allow_bt_vertical: bool,
    allow_bt_horizontal: bool,
    allow_tt_vertical: bool,
    allow_tt_horizontal: bool,
    allow_qt: bool,
}

impl VvcSplitCtxInput {
    fn qt_only_root() -> Self {
        Self {
            available_left: false,
            available_above: false,
            condition_left: false,
            condition_above: false,
            allow_bt_vertical: false,
            allow_bt_horizontal: false,
            allow_tt_vertical: false,
            allow_tt_horizontal: false,
            allow_qt: true,
        }
    }

    fn full_child_without_smaller_neighbours() -> Self {
        Self {
            available_left: false,
            available_above: false,
            condition_left: false,
            condition_above: false,
            allow_bt_vertical: true,
            allow_bt_horizontal: true,
            allow_tt_vertical: true,
            allow_tt_horizontal: true,
            allow_qt: true,
        }
    }

    fn bt_leaf_without_smaller_neighbours() -> Self {
        Self {
            available_left: false,
            available_above: false,
            condition_left: false,
            condition_above: false,
            allow_bt_vertical: true,
            allow_bt_horizontal: true,
            allow_tt_vertical: true,
            allow_tt_horizontal: true,
            allow_qt: false,
        }
    }

    fn single_bt_leaf_without_smaller_neighbours() -> Self {
        Self {
            available_left: false,
            available_above: false,
            condition_left: false,
            condition_above: false,
            allow_bt_vertical: true,
            allow_bt_horizontal: false,
            allow_tt_vertical: false,
            allow_tt_horizontal: false,
            allow_qt: false,
        }
    }

    fn bt_only_split_without_smaller_neighbours() -> Self {
        Self {
            available_left: false,
            available_above: false,
            condition_left: false,
            condition_above: false,
            allow_bt_vertical: true,
            allow_bt_horizontal: true,
            allow_tt_vertical: false,
            allow_tt_horizontal: false,
            allow_qt: false,
        }
    }

    fn bt_only_split_with_deeper_neighbours(left_deeper: bool, above_deeper: bool) -> Self {
        Self {
            available_left: left_deeper,
            available_above: above_deeper,
            condition_left: left_deeper,
            condition_above: above_deeper,
            allow_bt_vertical: true,
            allow_bt_horizontal: true,
            allow_tt_vertical: false,
            allow_tt_horizontal: false,
            allow_qt: false,
        }
    }

    fn mtt_only_split_with_deeper_neighbours(left_deeper: bool, above_deeper: bool) -> Self {
        Self {
            available_left: left_deeper,
            available_above: above_deeper,
            condition_left: left_deeper,
            condition_above: above_deeper,
            allow_bt_vertical: true,
            allow_bt_horizontal: true,
            allow_tt_vertical: false,
            allow_tt_horizontal: false,
            allow_qt: false,
        }
    }

    fn min_qt_leaf_with_deeper_neighbours(left_deeper: bool, above_deeper: bool) -> Self {
        Self {
            available_left: left_deeper,
            available_above: above_deeper,
            condition_left: left_deeper,
            condition_above: above_deeper,
            allow_bt_vertical: false,
            allow_bt_horizontal: false,
            allow_tt_vertical: false,
            allow_tt_horizontal: false,
            allow_qt: true,
        }
    }

    fn chroma_root_without_smaller_neighbours() -> Self {
        Self {
            available_left: false,
            available_above: false,
            condition_left: false,
            condition_above: false,
            allow_bt_vertical: true,
            allow_bt_horizontal: true,
            allow_tt_vertical: true,
            allow_tt_horizontal: true,
            allow_qt: false,
        }
    }

    fn full_child_with_deeper_neighbours(left_deeper: bool, above_deeper: bool) -> Self {
        Self {
            available_left: left_deeper,
            available_above: above_deeper,
            condition_left: left_deeper,
            condition_above: above_deeper,
            allow_bt_vertical: true,
            allow_bt_horizontal: true,
            allow_tt_vertical: true,
            allow_tt_horizontal: true,
            allow_qt: true,
        }
    }

    fn split_cu_flag_ctx(self) -> u8 {
        // VVC 9.3.4.2.2 derives ctxInc for split_cu_flag as:
        //   condL + condA + ctxSetIdx * 3
        // with ctxSetIdx =
        //   (allowBtVer + allowBtHor + allowTtVer + allowTtHor
        //    + 2 * allowQt - 1) / 2.
        let split_alternatives = u8::from(self.allow_bt_vertical)
            + u8::from(self.allow_bt_horizontal)
            + u8::from(self.allow_tt_vertical)
            + u8::from(self.allow_tt_horizontal)
            + (2 * u8::from(self.allow_qt));
        debug_assert!(split_alternatives > 0);
        let ctx_set_idx = (split_alternatives - 1) / 2;
        u8::from(self.condition_left && self.available_left)
            + u8::from(self.condition_above && self.available_above)
            + (3 * ctx_set_idx)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[allow(dead_code)]
struct VvcQtSplitCtxInput {
    available_left: bool,
    available_above: bool,
    left_deeper_qt: bool,
    above_deeper_qt: bool,
    cqt_depth: u8,
}

#[allow(dead_code)]
impl VvcQtSplitCtxInput {
    fn from_node_without_deeper_neighbours(node: VvcCodingTreeNode) -> Self {
        Self {
            available_left: false,
            available_above: false,
            left_deeper_qt: false,
            above_deeper_qt: false,
            cqt_depth: node.cqt_depth,
        }
    }

    fn from_node_with_deeper_neighbours(
        node: VvcCodingTreeNode,
        left_deeper_qt: bool,
        above_deeper_qt: bool,
    ) -> Self {
        Self {
            available_left: left_deeper_qt,
            available_above: above_deeper_qt,
            left_deeper_qt,
            above_deeper_qt,
            cqt_depth: node.cqt_depth,
        }
    }

    fn split_qt_flag_ctx(self) -> u8 {
        // VVC 9.3.4.2.2 derives ctxInc for split_qt_flag as:
        //   (condL && availableL) + (condA && availableA) + ctxSetIdx * 3
        // where ctxSetIdx is cqtDepth >= 2.
        u8::from(self.left_deeper_qt && self.available_left)
            + u8::from(self.above_deeper_qt && self.available_above)
            + (3 * u8::from(self.cqt_depth >= 2))
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
        split_ctx: u8,
        write_split_flag: bool,
        write_qt_flag: bool,
        qt_ctx: u8,
    },
    BtSplit {
        node: VvcCodingTreeNode,
        vertical: bool,
        split_ctx: u8,
        write_qt_flag: bool,
        qt_ctx: u8,
        write_mtt_vertical_flag: bool,
        mtt_vertical_ctx: u8,
        write_binary_flag: bool,
        mtt_binary_ctx: u8,
        mtt_binary_value: bool,
    },
    LumaLeaf {
        node: VvcCodingTreeNode,
    },
    LumaLeafWithSplitCtx {
        node: VvcCodingTreeNode,
        split_ctx: u8,
    },
    ChromaTree {
        node: VvcCodingTreeNode,
        visible_width: u16,
        visible_height: u16,
    },
}

impl VvcCtuCabacOp {
    fn yuv420_ctu_partition(params: VvcCtuPartitionParams) -> Vec<Self> {
        let root = VvcCodingTreeNode::root(
            params.root_width as u16,
            params.root_height as u16,
            VvcTreeType::DualTreeLuma,
        );
        let chroma = params.ctu_chroma_root();
        let mut ops = Vec::with_capacity(params.luma_leaf_count + 2);
        let root_split_ctx = VvcSplitCtxInput::qt_only_root().split_cu_flag_ctx();
        ops.push(Self::QtSplit {
            node: root,
            split_ctx: root_split_ctx,
            write_split_flag: false,
            write_qt_flag: false,
            qt_ctx: VvcQtSplitCtxInput::from_node_without_deeper_neighbours(root)
                .split_qt_flag_ctx(),
        });
        if params.visible_width == params.root_width && params.visible_height == params.root_height
        {
            let half_ctu = VVC_CTU_SIZE / 2;
            let split_ctx = if params.root_width <= half_ctu && params.root_height <= half_ctu {
                VvcSplitCtxInput::full_child_without_smaller_neighbours().split_cu_flag_ctx()
            } else {
                VvcSplitCtxInput::qt_only_root().split_cu_flag_ctx()
            };
            ops.push(Self::LumaLeafWithSplitCtx {
                node: root,
                split_ctx,
            });
        } else if params.visible_width <= VVC_CTU_SIZE / 2
            && params.visible_height <= VVC_CTU_SIZE / 2
        {
            Self::append_visible_qt_luma_subtree(
                &mut ops,
                root.qt_child(0),
                params.visible_width as u16,
                params.visible_height as u16,
                (VVC_CTU_SIZE / 2) as u16,
            );
        } else if params.visible_width == params.root_width {
            for child_idx in [0_u8, 1] {
                let child = root.qt_child(child_idx);
                let child_left_deeper = child.x > 0;
                let child_above_deeper = child.y > 0;
                ops.push(Self::QtSplit {
                    node: child,
                    split_ctx: VvcSplitCtxInput::full_child_with_deeper_neighbours(
                        child_left_deeper,
                        child_above_deeper,
                    )
                    .split_cu_flag_ctx(),
                    write_split_flag: true,
                    write_qt_flag: true,
                    qt_ctx: VvcQtSplitCtxInput::from_node_with_deeper_neighbours(
                        child,
                        child_left_deeper,
                        child_above_deeper,
                    )
                    .split_qt_flag_ctx(),
                });
                for grandchild_idx in 0..4 {
                    let grandchild = child.qt_child(grandchild_idx);
                    let left_deeper = grandchild.x > 0;
                    let above_deeper = grandchild.y > 0;
                    let split_ctx = VvcSplitCtxInput::full_child_with_deeper_neighbours(
                        left_deeper,
                        above_deeper,
                    )
                    .split_cu_flag_ctx();
                    let qt_ctx = VvcQtSplitCtxInput::from_node_with_deeper_neighbours(
                        grandchild,
                        left_deeper,
                        above_deeper,
                    )
                    .split_qt_flag_ctx();
                    if child_idx == 1 && grandchild_idx == 1 {
                        ops.push(Self::BtSplit {
                            node: grandchild,
                            vertical: true,
                            split_ctx,
                            write_qt_flag: true,
                            qt_ctx,
                            write_mtt_vertical_flag: true,
                            mtt_vertical_ctx: 0,
                            write_binary_flag: true,
                            mtt_binary_ctx: 2,
                            mtt_binary_value: true,
                        });
                        let left_bt = grandchild.mtt_child(true, 0);
                        ops.push(Self::BtSplit {
                            node: left_bt,
                            vertical: false,
                            split_ctx: 4,
                            write_qt_flag: false,
                            qt_ctx: 4,
                            write_mtt_vertical_flag: true,
                            mtt_vertical_ctx: 3,
                            write_binary_flag: true,
                            mtt_binary_ctx: 0,
                            mtt_binary_value: true,
                        });
                        for bt_child_idx in 0..2 {
                            ops.push(Self::LumaLeafWithSplitCtx {
                                node: left_bt.mtt_child(false, bt_child_idx),
                                split_ctx: if bt_child_idx == 0 { 0 } else { 1 },
                            });
                        }
                        let right_bt = grandchild.mtt_child(true, 1);
                        ops.push(Self::BtSplit {
                            node: right_bt,
                            vertical: false,
                            split_ctx: 4,
                            write_qt_flag: false,
                            qt_ctx: 3,
                            write_mtt_vertical_flag: true,
                            mtt_vertical_ctx: 3,
                            write_binary_flag: true,
                            mtt_binary_ctx: 0,
                            mtt_binary_value: true,
                        });
                        for bt_child_idx in 0..2 {
                            ops.push(Self::LumaLeafWithSplitCtx {
                                node: right_bt.mtt_child(false, bt_child_idx),
                                split_ctx: 0,
                            });
                        }
                        continue;
                    }
                    if child_idx == 1 && grandchild_idx == 3 {
                        ops.push(Self::BtSplit {
                            node: grandchild,
                            vertical: true,
                            split_ctx,
                            write_qt_flag: true,
                            qt_ctx: 4,
                            write_mtt_vertical_flag: true,
                            mtt_vertical_ctx: 0,
                            write_binary_flag: true,
                            mtt_binary_ctx: 2,
                            mtt_binary_value: true,
                        });
                        let left_bt = grandchild.mtt_child(true, 0);
                        ops.push(Self::BtSplit {
                            node: left_bt,
                            vertical: false,
                            split_ctx: 4,
                            write_qt_flag: false,
                            qt_ctx: 4,
                            write_mtt_vertical_flag: true,
                            mtt_vertical_ctx: 3,
                            write_binary_flag: true,
                            mtt_binary_ctx: 0,
                            mtt_binary_value: true,
                        });
                        for bt_child_idx in 0..2 {
                            ops.push(Self::LumaLeafWithSplitCtx {
                                node: left_bt.mtt_child(false, bt_child_idx),
                                split_ctx: 0,
                            });
                        }
                        let right_bt = grandchild.mtt_child(true, 1);
                        ops.push(Self::BtSplit {
                            node: right_bt,
                            vertical: false,
                            split_ctx: 4,
                            write_qt_flag: false,
                            qt_ctx: 3,
                            write_mtt_vertical_flag: true,
                            mtt_vertical_ctx: 3,
                            write_binary_flag: true,
                            mtt_binary_ctx: 0,
                            mtt_binary_value: true,
                        });
                        for bt_child_idx in 0..2 {
                            ops.push(Self::LumaLeafWithSplitCtx {
                                node: right_bt.mtt_child(false, bt_child_idx),
                                split_ctx: 0,
                            });
                        }
                        continue;
                    }
                    ops.push(Self::QtSplit {
                        node: grandchild,
                        split_ctx,
                        write_split_flag: true,
                        write_qt_flag: true,
                        qt_ctx,
                    });
                    for great_idx in 0..4 {
                        let leaf = grandchild.qt_child(great_idx);
                        if child_idx == 1 && grandchild_idx == 2 {
                            ops.push(Self::LumaLeafWithSplitCtx {
                                node: leaf,
                                split_ctx: if matches!(great_idx, 0 | 2) { 1 } else { 0 },
                            });
                            continue;
                        }
                        if great_idx == 2
                            && (matches!(grandchild_idx, 1 | 3)
                                || (child_idx == 1 && grandchild_idx == 0))
                        {
                            ops.push(Self::BtSplit {
                                node: leaf,
                                vertical: true,
                                split_ctx: VvcSplitCtxInput::bt_only_split_with_deeper_neighbours(
                                    true, true,
                                )
                                .split_cu_flag_ctx(),
                                write_qt_flag: false,
                                qt_ctx: VvcQtSplitCtxInput::from_node_without_deeper_neighbours(
                                    leaf,
                                )
                                .split_qt_flag_ctx(),
                                write_mtt_vertical_flag: true,
                                mtt_vertical_ctx: 0,
                                write_binary_flag: false,
                                mtt_binary_ctx: 3,
                                mtt_binary_value: true,
                            });
                            let left_half = leaf.mtt_child(true, 0);
                            ops.push(Self::LumaLeafWithSplitCtx {
                                node: left_half,
                                split_ctx: VvcSplitCtxInput::mtt_only_split_with_deeper_neighbours(
                                    false, true,
                                )
                                .split_cu_flag_ctx(),
                            });
                            ops.push(Self::LumaLeafWithSplitCtx {
                                node: leaf.mtt_child(true, 1),
                                split_ctx: VvcSplitCtxInput::mtt_only_split_with_deeper_neighbours(
                                    false, false,
                                )
                                .split_cu_flag_ctx(),
                            });
                            continue;
                        }
                        if great_idx == 3 && grandchild_idx <= 1 {
                            ops.push(Self::BtSplit {
                                node: leaf,
                                vertical: false,
                                split_ctx:
                                    VvcSplitCtxInput::bt_only_split_without_smaller_neighbours()
                                        .split_cu_flag_ctx(),
                                write_qt_flag: false,
                                qt_ctx: VvcQtSplitCtxInput::from_node_without_deeper_neighbours(
                                    leaf,
                                )
                                .split_qt_flag_ctx(),
                                write_mtt_vertical_flag: true,
                                mtt_vertical_ctx: 0,
                                write_binary_flag: false,
                                mtt_binary_ctx: 1,
                                mtt_binary_value: true,
                            });
                            for mtt_child_idx in 0..2 {
                                ops.push(Self::LumaLeaf {
                                    node: leaf.mtt_child(false, mtt_child_idx),
                                });
                            }
                            continue;
                        }
                        if great_idx == 3 && matches!(grandchild_idx, 2 | 3) {
                            ops.push(Self::BtSplit {
                                node: leaf,
                                vertical: false,
                                split_ctx:
                                    VvcSplitCtxInput::bt_only_split_without_smaller_neighbours()
                                        .split_cu_flag_ctx(),
                                write_qt_flag: false,
                                qt_ctx: VvcQtSplitCtxInput::from_node_without_deeper_neighbours(
                                    leaf,
                                )
                                .split_qt_flag_ctx(),
                                write_mtt_vertical_flag: true,
                                mtt_vertical_ctx: 0,
                                write_binary_flag: false,
                                mtt_binary_ctx: 1,
                                mtt_binary_value: true,
                            });
                            let top_half = leaf.mtt_child(false, 0);
                            ops.push(Self::LumaLeaf { node: top_half });
                            let bottom_half = leaf.mtt_child(false, 1);
                            ops.push(Self::BtSplit {
                                node: bottom_half,
                                vertical: true,
                                split_ctx:
                                    VvcSplitCtxInput::single_bt_leaf_without_smaller_neighbours()
                                        .split_cu_flag_ctx(),
                                write_qt_flag: false,
                                qt_ctx: VvcQtSplitCtxInput::from_node_without_deeper_neighbours(
                                    bottom_half,
                                )
                                .split_qt_flag_ctx(),
                                // For this constrained 8x4 node the split process infers the
                                // vertical split direction; no
                                // mtt_split_cu_vertical_flag bin is coded.
                                write_mtt_vertical_flag: false,
                                mtt_vertical_ctx: 4,
                                write_binary_flag: false,
                                mtt_binary_ctx: 3,
                                mtt_binary_value: true,
                            });
                            for mtt_child_idx in 0..2 {
                                ops.push(Self::LumaLeaf {
                                    node: bottom_half.mtt_child(true, mtt_child_idx),
                                });
                            }
                            continue;
                        }
                        if great_idx != 0 {
                            ops.push(Self::LumaLeaf { node: leaf });
                            continue;
                        }
                        let corner_split_ctx = if grandchild_idx == 3 {
                            VvcSplitCtxInput::bt_only_split_with_deeper_neighbours(true, false)
                                .split_cu_flag_ctx()
                        } else {
                            VvcSplitCtxInput::bt_only_split_without_smaller_neighbours()
                                .split_cu_flag_ctx()
                        };
                        ops.push(Self::BtSplit {
                            node: leaf,
                            vertical: true,
                            split_ctx: corner_split_ctx,
                            write_qt_flag: false,
                            qt_ctx: VvcQtSplitCtxInput::from_node_without_deeper_neighbours(leaf)
                                .split_qt_flag_ctx(),
                            write_mtt_vertical_flag: true,
                            mtt_vertical_ctx: if grandchild_idx == 3 { 2 } else { 0 },
                            write_binary_flag: false,
                            mtt_binary_ctx: 3,
                            mtt_binary_value: true,
                        });
                        let split_half_idx = match great_idx {
                            0 | 3 => 1,
                            1 | 2 => 0,
                            _ => unreachable!(),
                        };
                        for bt_child_idx in 0..2 {
                            let half = leaf.mtt_child(true, bt_child_idx);
                            if bt_child_idx == split_half_idx {
                                ops.push(Self::BtSplit {
                                    node: half,
                                    vertical: false,
                                    split_ctx:
                                        VvcSplitCtxInput::single_bt_leaf_without_smaller_neighbours(
                                        )
                                        .split_cu_flag_ctx(),
                                    write_qt_flag: false,
                                    qt_ctx:
                                        VvcQtSplitCtxInput::from_node_without_deeper_neighbours(
                                            half,
                                        )
                                        .split_qt_flag_ctx(),
                                    write_mtt_vertical_flag: false,
                                    mtt_vertical_ctx: 3,
                                    write_binary_flag: false,
                                    mtt_binary_ctx: 1,
                                    mtt_binary_value: true,
                                });
                                for mtt_child_idx in 0..2 {
                                    ops.push(Self::LumaLeaf {
                                        node: half.mtt_child(false, mtt_child_idx),
                                    });
                                }
                            } else {
                                ops.push(Self::LumaLeaf { node: half });
                            }
                        }
                    }
                }
            }
        } else if params.visible_height == params.root_height {
            for child_idx in [0_u8, 2] {
                let child = root.qt_child(child_idx);
                let child_left_deeper = child.x > 0;
                let child_above_deeper = child.y > 0;
                ops.push(Self::QtSplit {
                    node: child,
                    split_ctx: VvcSplitCtxInput::full_child_with_deeper_neighbours(
                        child_left_deeper,
                        child_above_deeper,
                    )
                    .split_cu_flag_ctx(),
                    write_split_flag: true,
                    write_qt_flag: true,
                    qt_ctx: VvcQtSplitCtxInput::from_node_with_deeper_neighbours(
                        child,
                        child_left_deeper,
                        child_above_deeper,
                    )
                    .split_qt_flag_ctx(),
                });
                for grandchild_idx in 0..4 {
                    let grandchild = child.qt_child(grandchild_idx);
                    let left_deeper = grandchild.x > 0;
                    let above_deeper = grandchild.y > 0;
                    let split_ctx = VvcSplitCtxInput::full_child_with_deeper_neighbours(
                        left_deeper,
                        above_deeper,
                    )
                    .split_cu_flag_ctx();
                    let qt_ctx = VvcQtSplitCtxInput::from_node_with_deeper_neighbours(
                        grandchild,
                        left_deeper,
                        above_deeper,
                    )
                    .split_qt_flag_ctx();
                    ops.push(Self::QtSplit {
                        node: grandchild,
                        split_ctx,
                        write_split_flag: true,
                        write_qt_flag: true,
                        qt_ctx,
                    });
                    for great_idx in 0..4 {
                        let leaf = grandchild.qt_child(great_idx);
                        if child_idx == 2 && grandchild_idx == 0 && great_idx == 1 {
                            ops.push(Self::BtSplit {
                                node: leaf,
                                vertical: true,
                                split_ctx: VvcSplitCtxInput::bt_only_split_with_deeper_neighbours(
                                    true, true,
                                )
                                .split_cu_flag_ctx(),
                                write_qt_flag: false,
                                qt_ctx: VvcQtSplitCtxInput::from_node_without_deeper_neighbours(
                                    leaf,
                                )
                                .split_qt_flag_ctx(),
                                write_mtt_vertical_flag: true,
                                mtt_vertical_ctx: 0,
                                write_binary_flag: false,
                                mtt_binary_ctx: 3,
                                mtt_binary_value: true,
                            });
                            ops.push(Self::LumaLeafWithSplitCtx {
                                node: leaf.mtt_child(true, 0),
                                split_ctx: VvcSplitCtxInput::mtt_only_split_with_deeper_neighbours(
                                    true, false,
                                )
                                .split_cu_flag_ctx(),
                            });
                            ops.push(Self::LumaLeafWithSplitCtx {
                                node: leaf.mtt_child(true, 1),
                                split_ctx:
                                    VvcSplitCtxInput::single_bt_leaf_without_smaller_neighbours()
                                        .split_cu_flag_ctx(),
                            });
                            continue;
                        }
                        if child_idx == 2 && grandchild_idx == 0 && great_idx == 3 {
                            ops.push(Self::BtSplit {
                                node: leaf,
                                vertical: true,
                                split_ctx: VvcSplitCtxInput::bt_only_split_with_deeper_neighbours(
                                    true, false,
                                )
                                .split_cu_flag_ctx(),
                                write_qt_flag: false,
                                qt_ctx: VvcQtSplitCtxInput::from_node_without_deeper_neighbours(
                                    leaf,
                                )
                                .split_qt_flag_ctx(),
                                write_mtt_vertical_flag: true,
                                mtt_vertical_ctx: 2,
                                write_binary_flag: false,
                                mtt_binary_ctx: 3,
                                mtt_binary_value: true,
                            });
                            let left_half = leaf.mtt_child(true, 0);
                            ops.push(Self::BtSplit {
                                node: left_half,
                                vertical: false,
                                split_ctx:
                                    VvcSplitCtxInput::single_bt_leaf_without_smaller_neighbours()
                                        .split_cu_flag_ctx(),
                                write_qt_flag: false,
                                qt_ctx: VvcQtSplitCtxInput::from_node_without_deeper_neighbours(
                                    left_half,
                                )
                                .split_qt_flag_ctx(),
                                write_mtt_vertical_flag: false,
                                mtt_vertical_ctx: 3,
                                write_binary_flag: false,
                                mtt_binary_ctx: 1,
                                mtt_binary_value: true,
                            });
                            for mtt_child_idx in 0..2 {
                                ops.push(Self::LumaLeaf {
                                    node: left_half.mtt_child(false, mtt_child_idx),
                                });
                            }
                            ops.push(Self::LumaLeafWithSplitCtx {
                                node: leaf.mtt_child(true, 1),
                                split_ctx: VvcSplitCtxInput::mtt_only_split_with_deeper_neighbours(
                                    true, false,
                                )
                                .split_cu_flag_ctx(),
                            });
                            continue;
                        }
                        if child_idx == 2 && grandchild_idx == 1 && great_idx == 0 {
                            ops.push(Self::BtSplit {
                                node: leaf,
                                vertical: true,
                                split_ctx: VvcSplitCtxInput::bt_only_split_with_deeper_neighbours(
                                    true, false,
                                )
                                .split_cu_flag_ctx(),
                                write_qt_flag: false,
                                qt_ctx: VvcQtSplitCtxInput::from_node_without_deeper_neighbours(
                                    leaf,
                                )
                                .split_qt_flag_ctx(),
                                write_mtt_vertical_flag: true,
                                mtt_vertical_ctx: 2,
                                write_binary_flag: false,
                                mtt_binary_ctx: 3,
                                mtt_binary_value: true,
                            });
                            ops.push(Self::LumaLeafWithSplitCtx {
                                node: leaf.mtt_child(true, 0),
                                split_ctx:
                                    VvcSplitCtxInput::single_bt_leaf_without_smaller_neighbours()
                                        .split_cu_flag_ctx(),
                            });
                            ops.push(Self::LumaLeafWithSplitCtx {
                                node: leaf.mtt_child(true, 1),
                                split_ctx:
                                    VvcSplitCtxInput::single_bt_leaf_without_smaller_neighbours()
                                        .split_cu_flag_ctx(),
                            });
                            continue;
                        }
                        if child_idx == 2 && grandchild_idx == 1 && great_idx == 2 {
                            ops.push(Self::LumaLeafWithSplitCtx {
                                node: leaf,
                                split_ctx: VvcSplitCtxInput::mtt_only_split_with_deeper_neighbours(
                                    true, false,
                                )
                                .split_cu_flag_ctx(),
                            });
                            continue;
                        }
                        if child_idx == 2 && grandchild_idx == 2 && great_idx == 1 {
                            ops.push(Self::BtSplit {
                                node: leaf,
                                vertical: true,
                                split_ctx: VvcSplitCtxInput::bt_only_split_with_deeper_neighbours(
                                    true, true,
                                )
                                .split_cu_flag_ctx(),
                                write_qt_flag: false,
                                qt_ctx: VvcQtSplitCtxInput::from_node_without_deeper_neighbours(
                                    leaf,
                                )
                                .split_qt_flag_ctx(),
                                write_mtt_vertical_flag: true,
                                mtt_vertical_ctx: 0,
                                write_binary_flag: false,
                                mtt_binary_ctx: 3,
                                mtt_binary_value: true,
                            });
                            ops.push(Self::LumaLeafWithSplitCtx {
                                node: leaf.mtt_child(true, 0),
                                split_ctx: VvcSplitCtxInput::mtt_only_split_with_deeper_neighbours(
                                    true, false,
                                )
                                .split_cu_flag_ctx(),
                            });
                            ops.push(Self::LumaLeafWithSplitCtx {
                                node: leaf.mtt_child(true, 1),
                                split_ctx:
                                    VvcSplitCtxInput::single_bt_leaf_without_smaller_neighbours()
                                        .split_cu_flag_ctx(),
                            });
                            continue;
                        }
                        if great_idx == 2 && matches!(grandchild_idx, 1 | 3) {
                            ops.push(Self::BtSplit {
                                node: leaf,
                                vertical: true,
                                split_ctx: VvcSplitCtxInput::bt_only_split_with_deeper_neighbours(
                                    true, true,
                                )
                                .split_cu_flag_ctx(),
                                write_qt_flag: false,
                                qt_ctx: VvcQtSplitCtxInput::from_node_without_deeper_neighbours(
                                    leaf,
                                )
                                .split_qt_flag_ctx(),
                                write_mtt_vertical_flag: true,
                                mtt_vertical_ctx: 0,
                                write_binary_flag: false,
                                mtt_binary_ctx: 3,
                                mtt_binary_value: true,
                            });
                            let left_half = leaf.mtt_child(true, 0);
                            ops.push(Self::LumaLeafWithSplitCtx {
                                node: left_half,
                                split_ctx: VvcSplitCtxInput::mtt_only_split_with_deeper_neighbours(
                                    false, true,
                                )
                                .split_cu_flag_ctx(),
                            });
                            ops.push(Self::LumaLeafWithSplitCtx {
                                node: leaf.mtt_child(true, 1),
                                split_ctx:
                                    VvcSplitCtxInput::single_bt_leaf_without_smaller_neighbours()
                                        .split_cu_flag_ctx(),
                            });
                            continue;
                        }
                        if great_idx == 3 && grandchild_idx <= 1 {
                            ops.push(Self::BtSplit {
                                node: leaf,
                                vertical: false,
                                split_ctx:
                                    VvcSplitCtxInput::bt_only_split_without_smaller_neighbours()
                                        .split_cu_flag_ctx(),
                                write_qt_flag: false,
                                qt_ctx: VvcQtSplitCtxInput::from_node_without_deeper_neighbours(
                                    leaf,
                                )
                                .split_qt_flag_ctx(),
                                write_mtt_vertical_flag: true,
                                mtt_vertical_ctx: 0,
                                write_binary_flag: false,
                                mtt_binary_ctx: 1,
                                mtt_binary_value: true,
                            });
                            for mtt_child_idx in 0..2 {
                                ops.push(Self::LumaLeaf {
                                    node: leaf.mtt_child(false, mtt_child_idx),
                                });
                            }
                            continue;
                        }
                        if child_idx == 2 && grandchild_idx == 3 && great_idx == 0 {
                            ops.push(Self::BtSplit {
                                node: leaf,
                                vertical: true,
                                split_ctx:
                                    VvcSplitCtxInput::single_bt_leaf_without_smaller_neighbours()
                                        .split_cu_flag_ctx(),
                                write_qt_flag: false,
                                qt_ctx: VvcQtSplitCtxInput::from_node_without_deeper_neighbours(
                                    leaf,
                                )
                                .split_qt_flag_ctx(),
                                write_mtt_vertical_flag: true,
                                mtt_vertical_ctx: 0,
                                write_binary_flag: false,
                                mtt_binary_ctx: 3,
                                mtt_binary_value: true,
                            });
                            ops.push(Self::LumaLeafWithSplitCtx {
                                node: leaf.mtt_child(true, 0),
                                split_ctx:
                                    VvcSplitCtxInput::single_bt_leaf_without_smaller_neighbours()
                                        .split_cu_flag_ctx(),
                            });
                            ops.push(Self::LumaLeafWithSplitCtx {
                                node: leaf.mtt_child(true, 1),
                                split_ctx:
                                    VvcSplitCtxInput::single_bt_leaf_without_smaller_neighbours()
                                        .split_cu_flag_ctx(),
                            });
                            continue;
                        }
                        if child_idx == 2 && grandchild_idx == 3 && great_idx == 1 {
                            ops.push(Self::LumaLeafWithSplitCtx {
                                node: leaf,
                                split_ctx:
                                    VvcSplitCtxInput::single_bt_leaf_without_smaller_neighbours()
                                        .split_cu_flag_ctx(),
                            });
                            continue;
                        }
                        if child_idx == 2 && grandchild_idx == 2 && great_idx == 3 {
                            ops.push(Self::BtSplit {
                                node: leaf,
                                vertical: false,
                                split_ctx: VvcSplitCtxInput::mtt_only_split_with_deeper_neighbours(
                                    true, false,
                                )
                                .split_cu_flag_ctx(),
                                write_qt_flag: false,
                                qt_ctx: VvcQtSplitCtxInput::from_node_without_deeper_neighbours(
                                    leaf,
                                )
                                .split_qt_flag_ctx(),
                                write_mtt_vertical_flag: true,
                                mtt_vertical_ctx: 2,
                                write_binary_flag: false,
                                mtt_binary_ctx: 1,
                                mtt_binary_value: true,
                            });
                            ops.push(Self::LumaLeafWithSplitCtx {
                                node: leaf.mtt_child(false, 0),
                                split_ctx: VvcSplitCtxInput::mtt_only_split_with_deeper_neighbours(
                                    true, false,
                                )
                                .split_cu_flag_ctx(),
                            });
                            ops.push(Self::LumaLeafWithSplitCtx {
                                node: leaf.mtt_child(false, 1),
                                split_ctx:
                                    VvcSplitCtxInput::single_bt_leaf_without_smaller_neighbours()
                                        .split_cu_flag_ctx(),
                            });
                            continue;
                        }
                        if great_idx == 3 && matches!(grandchild_idx, 2 | 3) {
                            ops.push(Self::BtSplit {
                                node: leaf,
                                vertical: false,
                                split_ctx:
                                    VvcSplitCtxInput::bt_only_split_without_smaller_neighbours()
                                        .split_cu_flag_ctx(),
                                write_qt_flag: false,
                                qt_ctx: VvcQtSplitCtxInput::from_node_without_deeper_neighbours(
                                    leaf,
                                )
                                .split_qt_flag_ctx(),
                                write_mtt_vertical_flag: true,
                                mtt_vertical_ctx: 0,
                                write_binary_flag: false,
                                mtt_binary_ctx: 1,
                                mtt_binary_value: true,
                            });
                            let top_half = leaf.mtt_child(false, 0);
                            ops.push(Self::LumaLeaf { node: top_half });
                            let bottom_half = leaf.mtt_child(false, 1);
                            ops.push(Self::BtSplit {
                                node: bottom_half,
                                vertical: true,
                                split_ctx:
                                    VvcSplitCtxInput::single_bt_leaf_without_smaller_neighbours()
                                        .split_cu_flag_ctx(),
                                write_qt_flag: false,
                                qt_ctx: VvcQtSplitCtxInput::from_node_without_deeper_neighbours(
                                    bottom_half,
                                )
                                .split_qt_flag_ctx(),
                                // For this constrained 8x4 node the split process infers the
                                // vertical split direction; no
                                // mtt_split_cu_vertical_flag bin is coded.
                                write_mtt_vertical_flag: false,
                                mtt_vertical_ctx: 4,
                                write_binary_flag: false,
                                mtt_binary_ctx: 3,
                                mtt_binary_value: true,
                            });
                            for mtt_child_idx in 0..2 {
                                ops.push(Self::LumaLeaf {
                                    node: bottom_half.mtt_child(true, mtt_child_idx),
                                });
                            }
                            continue;
                        }
                        if great_idx != 0 {
                            ops.push(Self::LumaLeaf { node: leaf });
                            continue;
                        }
                        let corner_split_ctx = if grandchild_idx == 3 {
                            VvcSplitCtxInput::bt_only_split_with_deeper_neighbours(true, false)
                                .split_cu_flag_ctx()
                        } else {
                            VvcSplitCtxInput::bt_only_split_without_smaller_neighbours()
                                .split_cu_flag_ctx()
                        };
                        ops.push(Self::BtSplit {
                            node: leaf,
                            vertical: true,
                            split_ctx: corner_split_ctx,
                            write_qt_flag: false,
                            qt_ctx: VvcQtSplitCtxInput::from_node_without_deeper_neighbours(leaf)
                                .split_qt_flag_ctx(),
                            write_mtt_vertical_flag: true,
                            mtt_vertical_ctx: if grandchild_idx == 3 { 2 } else { 0 },
                            write_binary_flag: false,
                            mtt_binary_ctx: 3,
                            mtt_binary_value: true,
                        });
                        let split_half_idx = match great_idx {
                            0 | 3 => 1,
                            1 | 2 => 0,
                            _ => unreachable!(),
                        };
                        for bt_child_idx in 0..2 {
                            let half = leaf.mtt_child(true, bt_child_idx);
                            if bt_child_idx == split_half_idx {
                                ops.push(Self::BtSplit {
                                    node: half,
                                    vertical: false,
                                    split_ctx:
                                        VvcSplitCtxInput::single_bt_leaf_without_smaller_neighbours(
                                        )
                                        .split_cu_flag_ctx(),
                                    write_qt_flag: false,
                                    qt_ctx:
                                        VvcQtSplitCtxInput::from_node_without_deeper_neighbours(
                                            half,
                                        )
                                        .split_qt_flag_ctx(),
                                    write_mtt_vertical_flag: false,
                                    mtt_vertical_ctx: 3,
                                    write_binary_flag: false,
                                    mtt_binary_ctx: 1,
                                    mtt_binary_value: true,
                                });
                                for mtt_child_idx in 0..2 {
                                    ops.push(Self::LumaLeaf {
                                        node: half.mtt_child(false, mtt_child_idx),
                                    });
                                }
                            } else {
                                ops.push(Self::LumaLeaf { node: half });
                            }
                        }
                    }
                }
            }
        }
        ops.push(Self::ChromaTree {
            node: chroma,
            visible_width: params.visible_chroma_width(),
            visible_height: params.visible_chroma_height(),
        });
        ops
    }

    fn append_visible_qt_luma_subtree(
        ops: &mut Vec<Self>,
        node: VvcCodingTreeNode,
        visible_width: u16,
        visible_height: u16,
        max_leaf_size: u16,
    ) {
        if !node.intersects_visible(visible_width, visible_height) {
            return;
        }
        if node.fits_visible(visible_width, visible_height)
            && node.width <= max_leaf_size
            && node.height <= max_leaf_size
        {
            ops.push(Self::LumaLeafWithSplitCtx {
                node,
                split_ctx: VvcSplitCtxInput::full_child_without_smaller_neighbours()
                    .split_cu_flag_ctx(),
            });
            return;
        }

        if !node.fits_visible(visible_width, visible_height) {
            for child_idx in 0..4 {
                Self::append_visible_qt_luma_subtree(
                    ops,
                    node.qt_child(child_idx),
                    visible_width,
                    visible_height,
                    max_leaf_size,
                );
            }
            return;
        }

        debug_assert!(node.width > 16 || node.height > 16);
        let left_deeper = false;
        let above_deeper = false;
        ops.push(Self::QtSplit {
            node,
            split_ctx: VvcSplitCtxInput::full_child_with_deeper_neighbours(
                left_deeper,
                above_deeper,
            )
            .split_cu_flag_ctx(),
            write_split_flag: true,
            write_qt_flag: true,
            qt_ctx: VvcQtSplitCtxInput::from_node_with_deeper_neighbours(
                node,
                left_deeper,
                above_deeper,
            )
            .split_qt_flag_ctx(),
        });
        for child_idx in 0..4 {
            Self::append_visible_qt_luma_subtree(
                ops,
                node.qt_child(child_idx),
                visible_width,
                visible_height,
                max_leaf_size,
            );
        }
    }
}

#[derive(Debug, Clone)]
struct VvcCtuCabacGenerator {
    contexts: VvcCabacContexts,
    luma_dc_abs_level: u8,
    luma_dc_negative: bool,
}

impl VvcCtuCabacGenerator {
    fn new(luma_dc_abs_level: u8, luma_dc_negative: bool) -> Self {
        Self {
            contexts: VvcCabacContexts::new(),
            luma_dc_abs_level,
            luma_dc_negative,
        }
    }

    fn emit(&mut self, cabac: &mut VvcCabacEncoder, op: VvcCtuCabacOp) {
        if std::env::var_os("FRAMEFORGE_CABAC_OP_TRACE").is_some() {
            eprintln!("FF_CABAC_OP {op:?}");
        }
        match op {
            VvcCtuCabacOp::QtSplit {
                node,
                split_ctx,
                write_split_flag,
                write_qt_flag,
                qt_ctx,
            } => self.emit_qt_split(
                cabac,
                node,
                split_ctx,
                write_split_flag,
                write_qt_flag,
                qt_ctx,
            ),
            op @ VvcCtuCabacOp::BtSplit { .. } => self.emit_bt_split(cabac, op),
            VvcCtuCabacOp::LumaLeaf { node } => {
                self.emit_luma_leaf_split(cabac, node);
                self.emit_luma_multi_ref_line(cabac, node);
                self.emit_luma_intra_prediction_mode(cabac, node);
                self.emit_luma_residual(cabac, node);
            }
            VvcCtuCabacOp::LumaLeafWithSplitCtx { node, split_ctx } => {
                self.emit_luma_leaf_split_with_ctx(cabac, node, split_ctx);
                self.emit_luma_multi_ref_line(cabac, node);
                self.emit_luma_intra_prediction_mode(cabac, node);
                self.emit_luma_residual(cabac, node);
            }
            VvcCtuCabacOp::ChromaTree {
                node,
                visible_width,
                visible_height,
            } => self.emit_chroma_tree(cabac, node, visible_width, visible_height),
        }
    }

    fn emit_bt_split(&mut self, cabac: &mut VvcCabacEncoder, op: VvcCtuCabacOp) {
        let VvcCtuCabacOp::BtSplit {
            node,
            vertical,
            split_ctx,
            write_qt_flag,
            qt_ctx,
            write_mtt_vertical_flag,
            mtt_vertical_ctx,
            write_binary_flag,
            mtt_binary_ctx,
            mtt_binary_value,
        } = op
        else {
            unreachable!("emit_bt_split expects a binary split operation");
        };
        debug_assert!(node.cqt_depth >= 1 || (node.x == 0 && node.y == 0));
        debug_assert_eq!(node.tree_type, VvcTreeType::DualTreeLuma);
        self.contexts
            .encode(cabac, VvcCabacContext::SplitFlag(split_ctx), true);
        if write_qt_flag {
            self.contexts
                .encode(cabac, VvcCabacContext::SplitQtFlag(qt_ctx), false);
        }
        if write_mtt_vertical_flag {
            self.contexts.encode(
                cabac,
                VvcCabacContext::MttSplitCuVerticalFlag(mtt_vertical_ctx),
                vertical,
            );
        }
        if write_binary_flag {
            self.contexts.encode(
                cabac,
                VvcCabacContext::MttSplitCuBinaryFlag(mtt_binary_ctx),
                mtt_binary_value,
            );
        }
    }

    fn emit_qt_split(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        node: VvcCodingTreeNode,
        split_ctx: u8,
        write_split_flag: bool,
        write_qt_flag: bool,
        qt_ctx: u8,
    ) {
        debug_assert!(node.cqt_depth <= 3);
        debug_assert_eq!(node.mtt_depth, 0);
        debug_assert_eq!(node.tree_type, VvcTreeType::DualTreeLuma);
        // VVC 7.3.11.4 coding_tree emits split_cu_flag for QT-split luma
        // nodes. Some root-only geometries infer split_qt_flag, while boundary
        // constrained rectangular CTU views write it explicitly.
        if write_split_flag {
            self.contexts
                .encode(cabac, VvcCabacContext::SplitFlag(split_ctx), true);
        }
        if write_qt_flag {
            self.contexts
                .encode(cabac, VvcCabacContext::SplitQtFlag(qt_ctx), true);
        }
    }

    fn emit_luma_leaf_split(&mut self, cabac: &mut VvcCabacEncoder, node: VvcCodingTreeNode) {
        debug_assert!(node.cqt_depth >= 1 || (node.x == 0 && node.y == 0));
        debug_assert!(node.mtt_depth <= 3);
        debug_assert_eq!(node.tree_type, VvcTreeType::DualTreeLuma);
        let _child_idx = node.raster_child_idx();
        if node.width == 4 && node.height == 4 {
            return;
        }
        // VVC 7.3.11.4 reaches coding_unit when split_cu_flag is false. The
        // split_cu_flag context index is derived from VVC 9.3.4.2.2 using the
        // split modes available for this CTU child.
        let split_ctx = if node.mtt_depth == 0 {
            if node.cqt_depth >= 3 {
                let left_deeper = !node.x.is_multiple_of(16);
                let above_deeper = !node.y.is_multiple_of(16);
                VvcSplitCtxInput::min_qt_leaf_with_deeper_neighbours(left_deeper, above_deeper)
                    .split_cu_flag_ctx()
            } else {
                VvcSplitCtxInput::full_child_without_smaller_neighbours().split_cu_flag_ctx()
            }
        } else if node.mtt_depth == 1 && node.width == 4 && node.height == 8 && node.x % 8 == 4 {
            VvcSplitCtxInput::mtt_only_split_with_deeper_neighbours(true, false).split_cu_flag_ctx()
        } else if node.width <= 4 || node.height <= 4 {
            VvcSplitCtxInput::single_bt_leaf_without_smaller_neighbours().split_cu_flag_ctx()
        } else {
            VvcSplitCtxInput::bt_leaf_without_smaller_neighbours().split_cu_flag_ctx()
        };
        self.contexts
            .encode(cabac, VvcCabacContext::SplitFlag(split_ctx), false);
    }

    fn emit_luma_leaf_split_with_ctx(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        node: VvcCodingTreeNode,
        split_ctx: u8,
    ) {
        debug_assert!(node.cqt_depth >= 1 || (node.x == 0 && node.y == 0));
        debug_assert!(node.mtt_depth <= 3);
        debug_assert_eq!(node.tree_type, VvcTreeType::DualTreeLuma);
        if node.width == 4 && node.height == 4 {
            return;
        }
        self.contexts
            .encode(cabac, VvcCabacContext::SplitFlag(split_ctx), false);
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
        if node.y != 0 {
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
        let cbf = self.luma_dc_abs_level != 0;
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
        let mut residual = VvcResidualCabacEncoder::new(
            &mut self.contexts,
            VvcResidualCabacOptions::current_intra_subset(),
        );
        stream.emit(&mut residual, cabac);
    }

    fn emit_chroma_tree(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        node: VvcCodingTreeNode,
        visible_width: u16,
        visible_height: u16,
    ) {
        debug_assert_eq!(node.tree_type, VvcTreeType::DualTreeChroma);
        if visible_width <= 16 && visible_height <= 16 {
            self.emit_chroma_visible_qt_subtree(cabac, node, visible_width, visible_height, 4);
            return;
        }
        if visible_width == node.width && visible_height * 2 == node.height {
            self.contexts
                .encode(cabac, VvcCabacContext::SplitQtFlag(0), false);
            self.emit_chroma_leaf_with_split_ctx(cabac, node.mtt_child(false, 0), 0, true, 1);
            return;
        }
        if visible_width * 2 == node.width && visible_height == node.height {
            self.contexts
                .encode(cabac, VvcCabacContext::SplitQtFlag(0), false);
            self.contexts
                .encode(cabac, VvcCabacContext::SplitFlag(0), true);
            self.contexts
                .encode(cabac, VvcCabacContext::MttSplitCuVerticalFlag(0), false);
            self.emit_chroma_leaf_without_cclm_with_split_ctx(
                cabac,
                node.mtt_child(false, 0),
                3,
                1,
            );
            self.emit_chroma_leaf_without_cclm_with_split_ctx(
                cabac,
                node.mtt_child(false, 1),
                3,
                1,
            );
            return;
        }
        let _ = (visible_width, visible_height);
        self.emit_chroma_leaf(cabac, node);
    }

    fn emit_chroma_leaf(&mut self, cabac: &mut VvcCabacEncoder, node: VvcCodingTreeNode) {
        self.emit_chroma_leaf_split(cabac, node);
        self.emit_chroma_dm_mode(cabac, node);
        self.emit_chroma_cbfs(cabac, node, false, false);
    }

    fn emit_chroma_visible_qt_subtree(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        node: VvcCodingTreeNode,
        visible_width: u16,
        visible_height: u16,
        min_leaf_size: u16,
    ) {
        debug_assert_eq!(node.tree_type, VvcTreeType::DualTreeChroma);
        if !node.intersects_visible(visible_width, visible_height) {
            return;
        }
        if node.fits_visible(visible_width, visible_height) && node.width == 8 && node.height == 8 {
            let split_ctx = if node.y >= 8 { 7 } else { 6 };
            self.contexts
                .encode(cabac, VvcCabacContext::SplitFlag(split_ctx), true);
            self.contexts
                .encode(cabac, VvcCabacContext::SplitQtFlag(3), false);
            self.contexts
                .encode(cabac, VvcCabacContext::MttSplitCuVerticalFlag(3), true);
            self.emit_chroma_transform_only_leaf_with_split_ctx(
                cabac,
                node.mtt_child(true, 0),
                0,
                0,
            );
            self.contexts
                .encode(cabac, VvcCabacContext::SplitFlag(0), true);
            self.emit_chroma_transform_only_leaf_with_split_ctx(
                cabac,
                node.mtt_child(true, 1).mtt_child(false, 0),
                0,
                0,
            );
            self.emit_chroma_transform_only_leaf_with_split_ctx(
                cabac,
                node.mtt_child(true, 1).mtt_child(false, 1),
                0,
                0,
            );
            return;
        }
        if node.fits_visible(visible_width, visible_height)
            && node.width <= min_leaf_size
            && node.height <= min_leaf_size
        {
            self.emit_chroma_transform_only_leaf_with_split_ctx(cabac, node, 0, 0);
            return;
        }

        if !node.fits_visible(visible_width, visible_height) {
            for child_idx in 0..4 {
                self.emit_chroma_visible_qt_subtree(
                    cabac,
                    node.qt_child(child_idx),
                    visible_width,
                    visible_height,
                    min_leaf_size,
                );
            }
            return;
        }

        self.emit_chroma_visible_qt_split(cabac, node);
        for child_idx in 0..4 {
            self.emit_chroma_visible_qt_subtree(
                cabac,
                node.qt_child(child_idx),
                visible_width,
                visible_height,
                min_leaf_size,
            );
        }
    }

    fn emit_chroma_visible_qt_split(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        node: VvcCodingTreeNode,
    ) {
        let split_ctx = if node.cqt_depth < 2 {
            0
        } else if node.y >= 8 {
            7
        } else {
            6
        };
        let qt_ctx = if node.cqt_depth >= 2 { 3 } else { 0 };
        self.contexts
            .encode(cabac, VvcCabacContext::SplitFlag(split_ctx), true);
        self.contexts
            .encode(cabac, VvcCabacContext::SplitQtFlag(qt_ctx), true);
    }

    fn emit_chroma_leaf_with_split_ctx(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        node: VvcCodingTreeNode,
        split_ctx: u8,
        cclm_mode: bool,
        cbf_cb_ctx: u8,
    ) {
        debug_assert_eq!(node.tree_type, VvcTreeType::DualTreeChroma);
        self.contexts
            .encode(cabac, VvcCabacContext::SplitFlag(split_ctx), false);
        self.contexts
            .encode(cabac, VvcCabacContext::CclmModeFlag, cclm_mode);
        self.contexts
            .encode(cabac, VvcCabacContext::IntraChromaPredMode(0), cclm_mode);
        self.contexts
            .encode(cabac, VvcCabacContext::QtCbfCb(cbf_cb_ctx), false);
        self.contexts
            .encode(cabac, VvcCabacContext::QtCbfCr(0), false);
    }

    fn emit_chroma_leaf_without_cclm_with_split_ctx(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        node: VvcCodingTreeNode,
        split_ctx: u8,
        cbf_cb_ctx: u8,
    ) {
        debug_assert_eq!(node.tree_type, VvcTreeType::DualTreeChroma);
        self.contexts
            .encode(cabac, VvcCabacContext::SplitFlag(split_ctx), false);
        self.contexts
            .encode(cabac, VvcCabacContext::IntraChromaPredMode(1), false);
        self.contexts
            .encode(cabac, VvcCabacContext::QtCbfCb(cbf_cb_ctx), false);
        self.contexts
            .encode(cabac, VvcCabacContext::QtCbfCr(0), false);
    }

    fn emit_chroma_transform_only_leaf_with_split_ctx(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        node: VvcCodingTreeNode,
        split_ctx: u8,
        cbf_cb_ctx: u8,
    ) {
        debug_assert_eq!(node.tree_type, VvcTreeType::DualTreeChroma);
        if node.width != 4 || node.height != 4 {
            self.contexts
                .encode(cabac, VvcCabacContext::SplitFlag(split_ctx), false);
        }
        self.contexts
            .encode(cabac, VvcCabacContext::CclmModeFlag, false);
        self.contexts
            .encode(cabac, VvcCabacContext::IntraChromaPredMode(1), false);
        self.contexts
            .encode(cabac, VvcCabacContext::QtCbfCb(cbf_cb_ctx), false);
        self.contexts
            .encode(cabac, VvcCabacContext::QtCbfCr(0), false);
    }

    fn emit_chroma_leaf_split(&mut self, cabac: &mut VvcCabacEncoder, node: VvcCodingTreeNode) {
        debug_assert_eq!(node.tree_type, VvcTreeType::DualTreeChroma);
        let split_ctx =
            VvcSplitCtxInput::chroma_root_without_smaller_neighbours().split_cu_flag_ctx();
        self.contexts
            .encode(cabac, VvcCabacContext::SplitFlag(split_ctx), false);
    }

    fn emit_chroma_cbfs(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        node: VvcCodingTreeNode,
        cbf_cb: bool,
        cbf_cr: bool,
    ) {
        debug_assert_eq!(node.tree_type, VvcTreeType::DualTreeChroma);
        self.contexts
            .encode(cabac, VvcCabacContext::QtCbfCb(0), cbf_cb);
        self.contexts
            .encode(cabac, VvcCabacContext::QtCbfCr(u8::from(cbf_cb)), cbf_cr);
    }

    fn emit_chroma_dm_mode(&mut self, cabac: &mut VvcCabacEncoder, node: VvcCodingTreeNode) {
        debug_assert_eq!(node.tree_type, VvcTreeType::DualTreeChroma);
        // For the current dual-tree 4:2:0 path, choose derived chroma mode:
        // CCLM disabled for this CU (cclm_mode_flag=0), then
        // intra_chroma_pred_mode=0 to select DM_CHROMA_IDX.
        self.contexts
            .encode(cabac, VvcCabacContext::CclmModeFlag, false);
        self.contexts
            .encode(cabac, VvcCabacContext::IntraChromaPredMode(1), false);
    }
}

fn placeholder_rbsp() -> Vec<u8> {
    // TODO(vvc): Replace this rbsp_trailing_bits-only payload with real VPS,
    // SPS, PPS, and slice RBSP syntax from a clean-room implementation.
    let mut writer = VvcSyntaxWriter::new();
    writer.rbsp_trailing_bits();
    writer.into_bytes()
}

#[cfg(test)]
mod tests;
