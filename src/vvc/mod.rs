//! First-target VVC/H.266 syntax experiments.
//!
//! This module contains a clean-room VVC path for small all-intra validation
//! streams across parameterized geometries. It is still intentionally
//! incomplete: CABAC, CTU syntax generation, transform/quant, prediction, and
//! reconstruction semantics need to keep converging toward real implementations
//! before FrameForge can encode arbitrary input pictures.

use std::io::{Cursor, ErrorKind, Read, Write};

use crate::picture::{ChromaSampling, Picture, PixelFormat, SampleBitDepth};

mod cabac;
mod header;
mod nal;
mod palette;
mod residual;
mod syntax;
use cabac::{
    encode_ctu_partition_body, VvcCabacContext, VvcCabacContexts, VvcCabacDumpContextEvent,
    VvcCabacDumpSymbol, VvcCabacEncoder, VvcCodingTreeNode, VvcCtuCabacOp, VvcCtuPartitionParams,
    VvcCtuPartitionShape, VvcLastSigCoeffPrefixCtxInput,
};
#[cfg(test)]
use cabac::{VvcCtuCabacGenerator, VvcQtSplitCtxInput, VvcSplitCtxInput, VvcTreeType};
use header::{
    vvc_poc_lsb_for_frame_idx, vvc_pps_unit, vvc_slice_unit, vvc_sps_unit, VvcPictureKind,
};
#[cfg(test)]
use header::{
    vvc_pps_rbsp, vvc_slice_payload, vvc_slice_rbsp, vvc_sps_payload, vvc_sps_rbsp,
    write_vvc_coding_tree_entropy,
};
pub use nal::{
    nal_unit_header_bytes, parse_annex_b_nal_units, write_annex_b, write_nal_unit_header,
    VvcNalHeader, VvcNalInfo, VvcNalUnit, VvcNalUnitType,
};
pub use palette::vvc_palette_444_cabac_dump_json;
use palette::vvc_palette_444_slice_unit;
#[cfg(test)]
use palette::{
    vvc_palette_444_binarized_syntax_bits, vvc_palette_444_context_audit_rows,
    vvc_palette_444_cu_syntax, vvc_palette_444_decode_reconstruction,
    vvc_palette_444_single_entry_syntax, vvc_palette_444_syntax_tokens,
    vvc_palette_run_copy_context_id_for_audit, VvcPalettePredictorMode, VvcPaletteTreeType,
};
pub use residual::quantize_vvc_color;
use residual::{
    quantize_vvc_frame, reconstruct_vvc_residual_frame, VvcQuantizedColor, VvcResidualCabacOptions,
    VVC_LUMA_DC_BASE,
};
#[cfg(test)]
use residual::{
    VvcResidualCabacEncoder, VvcResidualComponent, VvcResidualCtxConfig, VvcResidualPass1State,
    MAX_VVC_LUMA_TUS,
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

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VvcEncodeArtifacts {
    pub bitstream: Vec<u8>,
    pub reconstruction: Vec<u8>,
}

/// Luma coded-picture dimensions are rounded to this granularity before SPS/PPS
/// signaling and crop-offset derivation.
///
/// This is a deliberately narrow property of the current VVC validation path,
/// not a claim about all legal VVC profiles or future FrameForge codec paths.
pub const VVC_CODED_DIMENSION_GRANULARITY: usize = 8;
const VVC_CTU_SIZE: usize = 64;
const VVC_CURRENT_MIN_LUMA_CB_SIZE: u16 = 4;
const VVC_CURRENT_MAX_LUMA_LEAF_SIZE: u16 = 8;
const VVC_CURRENT_MAX_LUMA_LEAF_HEIGHT: u16 = VVC_CURRENT_MAX_LUMA_LEAF_SIZE;
const VVC_CURRENT_MAX_LUMA_BT_SIZE: u16 = VVC_CURRENT_MIN_LUMA_QT_SIZE << 2;
const VVC_CURRENT_MAX_LUMA_TT_SIZE: u16 = VVC_CURRENT_MIN_LUMA_QT_SIZE << 2;
const VVC_CURRENT_MAX_LUMA_MTT_DEPTH: u8 = 3;
const VVC_CURRENT_MAX_CHROMA_420_TB_SIZE: u16 = 32;
const VVC_CURRENT_MAX_CHROMA_420_BT_SIZE: u16 = VVC_CURRENT_MIN_CHROMA_420_QT_SIZE << 3;
const VVC_CURRENT_MAX_CHROMA_420_TT_SIZE: u16 = VVC_CURRENT_MIN_CHROMA_420_QT_SIZE << 2;
const VVC_CURRENT_MAX_CHROMA_420_MTT_DEPTH_WITH_BOUNDARY: u8 = 6;
const VVC_CURRENT_MIN_CHROMA_420_QT_SIZE: u16 = VVC_CURRENT_MIN_LUMA_QT_SIZE;
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
    pub const fn validation_minimum() -> Self {
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
pub struct VvcSampledColor {
    pub y: u8,
    pub u: u8,
    pub v: u8,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct VvcSampledFrame {
    geometry: VvcVideoGeometry,
    format: VvcPictureFormat,
    luma: Vec<u8>,
    cb: Vec<u8>,
    cr: Vec<u8>,
    chroma_len: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct VvcPictureFormat {
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
    palette_enabled: bool,
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
    tools: VvcSyntaxToolFlags,
    ref_pic_resampling_enabled: bool,
    entry_point_offsets_present: bool,
}

impl VvcSyntaxToolFlags {
    const fn yuv420_residual() -> Self {
        Self {
            palette_enabled: false,
            transform_skip_enabled: false,
            mts_enabled: false,
            explicit_mts_intra_enabled: false,
            lfnst_enabled: false,
            mrl_enabled: true,
            cclm_enabled: true,
            dependent_quantization_enabled: false,
            sign_data_hiding_enabled: false,
        }
    }

    const fn palette_444() -> Self {
        Self {
            palette_enabled: true,
            transform_skip_enabled: false,
            mts_enabled: false,
            explicit_mts_intra_enabled: false,
            lfnst_enabled: false,
            mrl_enabled: false,
            cclm_enabled: false,
            dependent_quantization_enabled: false,
            sign_data_hiding_enabled: false,
        }
    }

    const fn mts_enabled(self) -> bool {
        self.mts_enabled || self.explicit_mts_intra_enabled
    }
}

impl VvcSliceSyntaxConfig {
    const fn new(coding_tree: VvcCodingTreeConfig, tools: VvcSyntaxToolFlags) -> Self {
        Self {
            coding_tree,
            tools,
            ref_pic_resampling_enabled: true,
            entry_point_offsets_present: true,
        }
    }

    const fn yuv420_residual() -> Self {
        Self::new(
            VvcCodingTreeConfig::yuv420(),
            VvcSyntaxToolFlags::yuv420_residual(),
        )
    }

    const fn palette_444() -> Self {
        Self::new(
            VvcCodingTreeConfig {
                chroma_sampling: ChromaSampling::Cs444,
            },
            VvcSyntaxToolFlags::palette_444(),
        )
    }

    const fn for_picture_format(format: VvcPictureFormat) -> Self {
        // Current encoding-mode policy: the only implemented palette path is
        // 4:4:4, so 4:4:4 pictures select palette syntax. Keep this decision
        // behind a single helper so later work can replace the heuristic with
        // CU-level decisions, content analysis, or explicit encoder controls.
        match format.chroma_sampling {
            ChromaSampling::Cs444 => Self::palette_444(),
            _ => Self::yuv420_residual(),
        }
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

impl VvcSampledFrame {
    fn solid(color: VvcSampledColor) -> Self {
        Self {
            geometry: VvcVideoGeometry {
                width: 8,
                height: 8,
            },
            format: VvcPictureFormat {
                chroma_sampling: ChromaSampling::Cs420,
                bit_depth: SampleBitDepth::Eight,
            },
            luma: vec![color.y; 64],
            cb: vec![color.u; 16],
            cr: vec![color.v; 16],
            chroma_len: 16,
        }
    }

    fn sampled_color(&self) -> VvcSampledColor {
        VvcSampledColor {
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
            format: VvcPictureFormat {
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
        VvcSampledFrame::solid(VvcSampledColor { y: 0, u: 0, v: 0 }),
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
    Ok(
        vvc_yuv_encode_artifacts_from_input_with_limits(input, params, geometry, limits, format)?
            .bitstream,
    )
}

pub fn vvc_yuv_encode_artifacts_from_input_with_limits(
    input: &[u8],
    params: VvcEncodeParams,
    geometry: VvcVideoGeometry,
    limits: VvcVideoLimits,
    format: PixelFormat,
) -> Result<VvcEncodeArtifacts, String> {
    let mut reader = Cursor::new(input);
    let mut bitstream = Vec::new();
    let mut reconstruction = Vec::new();
    vvc_yuv_encode_stream_with_limits(
        &mut reader,
        &mut bitstream,
        Some(&mut reconstruction),
        params,
        geometry,
        limits,
        format,
    )?;
    Ok(VvcEncodeArtifacts {
        bitstream,
        reconstruction,
    })
}

pub fn vvc_yuv_encode_stream_with_limits<R: Read, W: Write>(
    input: &mut R,
    bitstream: &mut W,
    mut reconstruction: Option<&mut dyn Write>,
    params: VvcEncodeParams,
    geometry: VvcVideoGeometry,
    limits: VvcVideoLimits,
    format: PixelFormat,
) -> Result<(), String> {
    geometry.validate_against(limits)?;
    validate_vvc_frame_count(params)?;
    geometry.validate_shape()?;
    if !format.is_yuv() {
        return Err(format!("VVC input expects planar YUV format; got {format}"));
    }
    Picture::validate_shape(geometry.width, geometry.height, format)?;
    let frame_len = Picture::expected_len(geometry.width, geometry.height, format);
    let stream_format = VvcPictureFormat {
        chroma_sampling: format
            .chroma_sampling()
            .expect("YUV input has chroma sampling"),
        bit_depth: format.bit_depth(),
    };
    let slice_config = VvcSliceSyntaxConfig::for_picture_format(stream_format);
    write_annex_b_to(
        bitstream,
        &[vvc_sps_unit(geometry, slice_config), vvc_pps_unit(geometry)],
    )?;

    let mut frame_buf = vec![0; frame_len];
    for frame_idx in 0..params.frames {
        input.read_exact(&mut frame_buf).map_err(|err| {
            if err.kind() == ErrorKind::UnexpectedEof {
                format!(
                    "VVC input ended before frame {frame_idx}; expected {} frame(s) of {} bytes",
                    params.frames, frame_len
                )
            } else {
                format!("failed to read VVC input frame {frame_idx}: {err}")
            }
        })?;
        let source_frame =
            sample_vvc_yuv_frame(&frame_buf, VvcEncodeParams { frames: 1 }, geometry, format)?;
        if stream_format.chroma_sampling == ChromaSampling::Cs444 {
            if let Some(writer) = reconstruction.as_deref_mut() {
                writer
                    .write_all(&palette::vvc_palette_444_reconstruction_yuv(&source_frame))
                    .map_err(|err| {
                        format!("failed to write VVC reconstruction frame {frame_idx}: {err}")
                    })?;
            }
            write_annex_b_to(
                bitstream,
                &[vvc_palette_444_slice_unit(
                    frame_idx,
                    &source_frame,
                    slice_config,
                )?],
            )?;
            continue;
        }

        let compat_frame = source_frame.decoder_compat_frame();
        let quantized = quantize_vvc_frame(compat_frame.clone());
        let partition_params = vvc_ctu_partition_params(compat_frame.geometry, quantized)
            .ok_or_else(|| {
                format!(
                    "VVC reconstruction has no generated CTU path for coded geometry {}x{}",
                    compat_frame.geometry.coded_width(),
                    compat_frame.geometry.coded_height()
                )
            })?;
        if let Some(writer) = reconstruction.as_deref_mut() {
            writer
                .write_all(&reconstruct_vvc_residual_frame(
                    &compat_frame,
                    quantized,
                    partition_params,
                ))
                .map_err(|err| {
                    format!("failed to write VVC reconstruction frame {frame_idx}: {err}")
                })?;
        }
        write_annex_b_to(
            bitstream,
            &[vvc_slice_unit(
                frame_idx,
                compat_frame.geometry,
                quantized,
                slice_config,
            )?],
        )?;
    }

    let mut extra = [0; 1];
    match input.read(&mut extra) {
        Ok(0) => Ok(()),
        Ok(_) => Err(format!(
            "VVC input contains trailing bytes after {} frame(s)",
            params.frames
        )),
        Err(err) => Err(format!("failed to check VVC input length: {err}")),
    }
}

fn write_annex_b_to<W: Write>(output: &mut W, units: &[VvcNalUnit]) -> Result<(), String> {
    let bytes = write_annex_b(units)?;
    output
        .write_all(&bytes)
        .map_err(|err| format!("failed to write VVC Annex-B stream: {err}"))
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
    let color = quantize_vvc_frame(compat_frame.clone());
    let params = vvc_ctu_partition_params(compat_frame.geometry, color).ok_or_else(|| {
        format!(
            "VVC CABAC vector dump has no generated CTU path for coded geometry {}x{}",
            compat_frame.geometry.coded_width(),
            compat_frame.geometry.coded_height()
        )
    })?;
    let dump = vvc_ctu_partition_cabac_dump(params, VvcSliceSyntaxConfig::yuv420_residual());
    let mapped_context_symbols = dump
        .semantic_symbols
        .iter()
        .filter(|symbol| symbol.kind == 2)
        .count();
    if mapped_context_symbols != dump.context_bin_count {
        return Err(format!(
            "VVC CABAC vector dump used {} context bins but only {} have RTL context IDs; audit VvcCabacContext::rtl_context_id before using this as an RTL reference",
            dump.context_bin_count, mapped_context_symbols
        ));
    }
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
) -> Result<VvcSampledColor, String> {
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
) -> Result<VvcSampledFrame, String> {
    sample_vvc_yuv_frame_at(input, params, geometry, format, 0)
}

fn sample_vvc_yuv_frame_at(
    input: &[u8],
    params: VvcEncodeParams,
    geometry: VvcVideoGeometry,
    format: PixelFormat,
    frame_idx: usize,
) -> Result<VvcSampledFrame, String> {
    validate_vvc_frame_count(params)?;
    if frame_idx >= params.frames {
        return Err(format!(
            "VVC input requested frame {frame_idx}, but stream has {} frame(s)",
            params.frames
        ));
    }
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
    let frame_base = frame_len * frame_idx;

    let luma_samples = geometry.luma_samples();
    let mut luma = vec![0; luma_samples];
    let bytes_per_sample = format.bytes_per_sample();
    for (idx, sample) in luma.iter_mut().take(luma_samples).enumerate() {
        let raw = read_vvc_sample_raw(input, frame_base + idx * bytes_per_sample, format);
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
        let raw_cb = read_vvc_sample_raw(
            input,
            frame_base + u_offset + idx * bytes_per_sample,
            format,
        );
        let raw_cr = read_vvc_sample_raw(
            input,
            frame_base + v_offset + idx * bytes_per_sample,
            format,
        );
        cb[idx] = vvc_sample_to_8bit(raw_cb, format.bit_depth());
        cr[idx] = vvc_sample_to_8bit(raw_cr, format.bit_depth());
    }

    Ok(VvcSampledFrame {
        geometry,
        format: VvcPictureFormat {
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
    Ok(())
}

fn vvc_yuv420p8_annex_b(
    params: VvcEncodeParams,
    frame: VvcSampledFrame,
) -> Result<Vec<u8>, String> {
    vvc_annex_b(params, frame)
}

fn vvc_annex_b(params: VvcEncodeParams, frame: VvcSampledFrame) -> Result<Vec<u8>, String> {
    let geometry = frame.geometry;
    let quantized = quantize_vvc_frame(frame);
    vvc_annex_b_from_quantized(
        params,
        geometry,
        quantized,
        VvcPictureFormat {
            chroma_sampling: ChromaSampling::Cs420,
            bit_depth: SampleBitDepth::Eight,
        },
    )
}

fn vvc_annex_b_from_quantized(
    params: VvcEncodeParams,
    geometry: VvcVideoGeometry,
    quantized: VvcQuantizedColor,
    format: VvcPictureFormat,
) -> Result<Vec<u8>, String> {
    let quantized_frames = vec![quantized; params.frames];
    vvc_annex_b_from_quantized_frames(params, geometry, &quantized_frames, format)
}

fn vvc_annex_b_from_quantized_frames(
    params: VvcEncodeParams,
    geometry: VvcVideoGeometry,
    quantized_frames: &[VvcQuantizedColor],
    format: VvcPictureFormat,
) -> Result<Vec<u8>, String> {
    if quantized_frames.len() != params.frames {
        return Err(format!(
            "VVC residual encoder got {} frame(s), expected {}",
            quantized_frames.len(),
            params.frames
        ));
    }
    let mut units = Vec::with_capacity(params.frames + 3);
    let slice_config = VvcSliceSyntaxConfig::for_picture_format(format);
    units.push(vvc_sps_unit(geometry, slice_config));
    units.push(vvc_pps_unit(geometry));
    for (frame_idx, quantized) in quantized_frames.iter().copied().enumerate() {
        units.push(vvc_slice_unit(
            frame_idx,
            geometry,
            quantized,
            slice_config,
        )?);
    }
    write_annex_b(&units)
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
    color: VvcQuantizedColor,
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
    color: VvcQuantizedColor,
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
            luma_ac_levels: color.luma_ac_levels,
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
        luma_ac_levels: color.luma_ac_levels,
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
        luma_ac_levels: [0; 15],
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
    context_bin_count: usize,
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
    let context_bin_count = cabac.context_bin_count;
    let bin_engine_events = cabac.bin_engine_events.clone();
    let symbols = cabac.dump_symbols.clone();
    let bits = cabac.finish();
    VvcCtuCabacDump {
        symbols,
        semantic_symbols,
        context_events,
        context_bin_count,
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
    json.push_str(",\"context_id_bits\":10");
    json.push_str(",\"symbol_encoding\":\"kind_u8_data_u32be_hex\"");
    json.push_str(&format!(
        ",\"mapped_context_bin_count\":{}",
        context_events.len()
    ));
    json.push_str(&format!(",\"cabac_bit_len\":{}", bits.len()));
    json.push_str(",\"cabac_bytes_hex\":\"");
    append_hex_bytes(&mut json, bits);
    json.push_str("\",\"symbols_hex\":\"");
    append_symbol_records_hex(&mut json, symbols);
    json.push_str("\",\"semantic_symbols_hex\":\"");
    append_symbol_records_hex(&mut json, semantic_symbols);
    json.push_str("\",\"context_event_record_bytes\":8");
    json.push_str(
        ",\"context_event_encoding\":\"ctx_id_u16be_bin_u8_range_u16be_lps_u16be_mps_u8_hex\"",
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
        for byte in event.ctx_id.to_be_bytes() {
            append_byte_hex(out, byte);
        }
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

#[cfg(test)]
mod tests;
