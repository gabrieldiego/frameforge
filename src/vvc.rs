//! First-target VVC/H.266 syntax experiments.
//!
//! This module contains a clean-room toy VVC path that can emit a tiny
//! decoder-accepted 4x4 all-intra stream. It is still intentionally incomplete:
//! CABAC, CTU syntax generation, transform/quant, prediction, and
//! reconstruction semantics need to be replaced with real implementations
//! before FrameForge can encode from arbitrary input pictures.

use crate::bitstream::insert_emulation_prevention_bytes;
use crate::bitstream::{rbsp_trailing_bits, BitWriter};
use crate::picture::{Picture, PixelFormat};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VvcSyntaxCode {
    Flag,
    U,
    Ue,
    Se,
    ByteAlignZero,
    CabacToken,
    RbspTrailingBits,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VvcSyntaxField {
    pub name: &'static str,
    pub code: VvcSyntaxCode,
    pub bit_offset: usize,
    pub bit_count: usize,
}

#[derive(Debug, Default, Clone)]
pub struct VvcSyntaxWriter {
    writer: BitWriter,
    fields: Vec<VvcSyntaxField>,
    bit_offset: usize,
}

impl VvcSyntaxWriter {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn write_flag(&mut self, name: &'static str, value: bool) {
        self.push_field(name, VvcSyntaxCode::Flag, 1);
        self.writer.write_bool(value);
        self.bit_offset += 1;
    }

    pub fn write_u(&mut self, name: &'static str, value: u64, bit_count: u8) {
        assert!(bit_count <= 64, "u(n) cannot write more than 64 bits");
        if bit_count < 64 {
            assert!(
                value < (1u64 << bit_count),
                "value does not fit in u({bit_count})"
            );
        }
        self.push_field(name, VvcSyntaxCode::U, bit_count as usize);
        self.writer.write_bits(value, bit_count);
        self.bit_offset += bit_count as usize;
    }

    pub fn write_ue(&mut self, name: &'static str, value: u32) {
        let code_num = value as u64 + 1;
        self.write_exp_golomb_code(name, VvcSyntaxCode::Ue, code_num);
    }

    pub fn write_se(&mut self, name: &'static str, value: i32) {
        let code_num = if value > 0 {
            (value as u64) * 2
        } else {
            (value.unsigned_abs() as u64 * 2) + 1
        };
        self.write_exp_golomb_code(name, VvcSyntaxCode::Se, code_num);
    }

    fn write_exp_golomb_code(&mut self, name: &'static str, code: VvcSyntaxCode, code_num: u64) {
        debug_assert!(code_num > 0);
        let bit_count = 64 - code_num.leading_zeros() as u8;
        let leading_zero_bits = bit_count - 1;
        let total_bits = (leading_zero_bits * 2) + 1;
        self.push_field(name, code, total_bits as usize);
        for _ in 0..leading_zero_bits {
            self.writer.write_bit(false);
        }
        self.writer.write_bits(code_num, bit_count);
        self.bit_offset += total_bits as usize;
    }

    pub fn write_cabac_token(&mut self, name: &'static str, value: u64, bit_count: u8) {
        assert!(
            bit_count <= 64,
            "CABAC token cannot write more than 64 bits"
        );
        self.push_field(name, VvcSyntaxCode::CabacToken, bit_count as usize);
        self.writer.write_bits(value, bit_count);
        self.bit_offset += bit_count as usize;
    }

    pub fn write_cabac_bits(&mut self, name: &'static str, bits: &[bool]) {
        self.push_field(name, VvcSyntaxCode::CabacToken, bits.len());
        for bit in bits {
            self.writer.write_bit(*bit);
        }
        self.bit_offset += bits.len();
    }

    pub fn byte_align_zero(&mut self, name: &'static str) {
        let remainder = self.bit_offset % 8;
        if remainder == 0 {
            return;
        }
        let bit_count = 8 - remainder;
        self.push_field(name, VvcSyntaxCode::ByteAlignZero, bit_count);
        self.writer.byte_align_zero();
        self.bit_offset += bit_count;
    }

    pub fn rbsp_trailing_bits(&mut self) {
        let bit_count = if self.writer.is_byte_aligned() {
            8
        } else {
            8 - (self.bit_offset % 8)
        };
        self.push_field(
            "rbsp_trailing_bits",
            VvcSyntaxCode::RbspTrailingBits,
            bit_count,
        );
        rbsp_trailing_bits(&mut self.writer);
        self.bit_offset += bit_count;
    }

    pub fn is_byte_aligned(&self) -> bool {
        self.writer.is_byte_aligned()
    }

    pub fn fields(&self) -> &[VvcSyntaxField] {
        &self.fields
    }

    pub fn into_bytes(self) -> Vec<u8> {
        self.writer.into_bytes()
    }

    pub fn finish(self) -> VvcSyntaxRbsp {
        VvcSyntaxRbsp {
            bytes: self.writer.into_bytes(),
            fields: self.fields,
        }
    }

    fn push_field(&mut self, name: &'static str, code: VvcSyntaxCode, bit_count: usize) {
        self.fields.push(VvcSyntaxField {
            name,
            code,
            bit_offset: self.bit_offset,
            bit_count,
        });
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VvcSyntaxRbsp {
    pub bytes: Vec<u8>,
    pub fields: Vec<VvcSyntaxField>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VvcProfileTarget {
    MinimalToyAllIntra,
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
#[repr(u8)]
pub enum VvcNalUnitType {
    Trail = 0,
    IdrWRadl = 7,
    IdrNLp = 8,
    Cra = 9,
    Opi = 12,
    Dci = 13,
    Vps = 14,
    Sps = 15,
    Pps = 16,
    PrefixAps = 17,
    SuffixAps = 18,
    PictureHeader = 19,
    AccessUnitDelimiter = 20,
    EndOfSequence = 21,
    EndOfBitstream = 22,
    PrefixSei = 23,
    SuffixSei = 24,
    FillerData = 25,
    ReservedNvcl30 = 30,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VvcNalUnit {
    pub nal_unit_type: VvcNalUnitType,
    pub layer_id: u8,
    pub temporal_id: u8,
    pub rbsp_payload: Vec<u8>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct VvcNalHeader {
    pub forbidden_zero_bit: bool,
    pub nuh_reserved_zero_bit: bool,
    pub layer_id: u8,
    pub nal_unit_type: VvcNalUnitType,
    pub temporal_id: u8,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VvcNalInfo {
    pub nal_unit_type: u8,
    pub layer_id: u8,
    pub temporal_id: u8,
    pub payload_len: usize,
    pub offset: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Toy4x4EncodeParams {
    pub frames: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Toy4x4SampledColor {
    pub y: u8,
    pub u: u8,
    pub v: u8,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Toy4x4SampledFrame {
    luma: [u8; 16],
    u: u8,
    v: u8,
}

impl Toy4x4SampledFrame {
    fn solid(color: Toy4x4SampledColor) -> Self {
        Self {
            luma: [color.y; 16],
            u: color.u,
            v: color.v,
        }
    }

    fn sampled_color(self) -> Toy4x4SampledColor {
        Toy4x4SampledColor {
            y: self.luma[0],
            u: self.u,
            v: self.v,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Toy4x4PictureKind {
    Idr,
    Cra,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Toy4x4QuantizedColor {
    pub y: u8,
    pub u: u8,
    pub v: u8,
    luma_rem: u8,
    luma_ac_tokens: [u8; 15],
    chroma_rem: u8,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Toy4x4TransformBlock {
    dc_coeff: i16,
    ac_coeffs: [i16; 15],
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Toy4x4QuantizedTransformBlock {
    reconstructed_dc_coeff: i16,
    reconstructed_ac_coeffs: [i16; 15],
    abs_remainder: u8,
    ac_tokens: [u8; 15],
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Toy4x4ReconstructedLumaBlock {
    samples: [u8; 16],
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Toy4x4PaletteBlock {
    entry: Toy4x4SampledColor,
    indices: [u8; 16],
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ToyResidualComponent {
    Luma,
    ChromaCb,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ToyEntropyTokenKind {
    ContextBins {
        ctx_offset: usize,
        bins: &'static [bool],
    },
    RemAbsEp {
        component: ToyResidualComponent,
        value: u8,
        rice_param: u8,
    },
    SignEp {
        component: ToyResidualComponent,
        negative: bool,
    },
    Terminate,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct ToyEntropyToken {
    name: &'static str,
    kind: ToyEntropyTokenKind,
}

impl VvcNalUnit {
    pub fn eos() -> Self {
        Self {
            nal_unit_type: VvcNalUnitType::EndOfSequence,
            layer_id: 0,
            temporal_id: 0,
            rbsp_payload: Vec::new(),
        }
    }

    pub fn eob() -> Self {
        Self {
            nal_unit_type: VvcNalUnitType::EndOfBitstream,
            layer_id: 0,
            temporal_id: 0,
            rbsp_payload: Vec::new(),
        }
    }
}

pub fn write_annex_b(units: &[VvcNalUnit]) -> Result<Vec<u8>, String> {
    let mut out = Vec::new();
    for unit in units {
        out.extend_from_slice(&[0x00, 0x00, 0x00, 0x01]);
        out.extend_from_slice(&nal_unit_header_bytes(unit)?);
        out.extend_from_slice(&insert_emulation_prevention_bytes(&unit.rbsp_payload));
    }
    Ok(out)
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

pub fn toy_black_4x4_yuv420p8_annex_b(params: Toy4x4EncodeParams) -> Result<Vec<u8>, String> {
    validate_toy_4x4_frame_count(params)?;
    toy_4x4_yuv420p8_annex_b(
        params,
        Toy4x4SampledFrame::solid(Toy4x4SampledColor { y: 0, u: 0, v: 0 }),
    )
}

pub fn toy_4x4_yuv420p8_annex_b_from_input(
    input: &[u8],
    params: Toy4x4EncodeParams,
) -> Result<Vec<u8>, String> {
    toy_4x4_yuv_annex_b_from_input(input, params, PixelFormat::Yuv420p8)
}

pub fn toy_4x4_yuv420p_annex_b_from_input(
    input: &[u8],
    params: Toy4x4EncodeParams,
    format: PixelFormat,
) -> Result<Vec<u8>, String> {
    toy_4x4_yuv_annex_b_from_input(input, params, format)
}

pub fn toy_4x4_yuv_annex_b_from_input(
    input: &[u8],
    params: Toy4x4EncodeParams,
    format: PixelFormat,
) -> Result<Vec<u8>, String> {
    if format.chroma_sampling() == Some(crate::ChromaSampling::Cs444) {
        let palette = sample_toy_4x4_yuv444_palette(input, params, format)?;
        return toy_4x4_annex_b(
            params,
            Toy4x4SampledFrame::solid(palette.entry),
            Some(palette),
        );
    }

    let frame = sample_toy_4x4_yuv_frame(input, params, format)?;
    toy_4x4_annex_b(params, frame, None)
}

pub fn sample_toy_4x4_first_yuv420p8(
    input: &[u8],
    params: Toy4x4EncodeParams,
) -> Result<Toy4x4SampledColor, String> {
    Ok(sample_toy_4x4_yuv_frame(input, params, PixelFormat::Yuv420p8)?.sampled_color())
}

fn sample_toy_4x4_yuv_frame(
    input: &[u8],
    params: Toy4x4EncodeParams,
    format: PixelFormat,
) -> Result<Toy4x4SampledFrame, String> {
    validate_toy_4x4_frame_count(params)?;
    if !format.is_yuv() {
        return Err(format!(
            "toy VVC input expects planar YUV format; got {format}"
        ));
    }
    let frame_len = Picture::expected_len(4, 4, format);
    let expected_len = frame_len * params.frames;
    if input.len() != expected_len {
        return Err(format!(
            "toy VVC input size mismatch: got {} bytes, expected {} for 4x4 {format} with {} frame(s)",
            input.len(),
            expected_len,
            params.frames
        ));
    }

    let mut luma = [0; 16];
    let bytes_per_sample = format.bytes_per_sample();
    for (idx, sample) in luma.iter_mut().enumerate() {
        *sample = read_toy_sample_as_8bit(input, idx * bytes_per_sample, format);
    }

    let u_offset = 16 * bytes_per_sample;
    let chroma_plane_samples = format
        .chroma_plane_samples(4, 4)
        .ok_or_else(|| format!("toy VVC input expects chroma samples; got {format}"))?;
    let v_offset = u_offset + (chroma_plane_samples * bytes_per_sample);

    Ok(Toy4x4SampledFrame {
        luma,
        u: read_toy_sample_as_8bit(input, u_offset, format),
        v: read_toy_sample_as_8bit(input, v_offset, format),
    })
}

fn read_toy_sample_as_8bit(input: &[u8], byte_offset: usize, format: PixelFormat) -> u8 {
    let bit_depth = format.bit_depth().bits();
    if bit_depth <= 8 {
        return input[byte_offset];
    }

    let value = u16::from_le_bytes([input[byte_offset], input[byte_offset + 1]]);
    (value >> (bit_depth - 8)) as u8
}

fn sample_toy_4x4_yuv444_palette(
    input: &[u8],
    params: Toy4x4EncodeParams,
    format: PixelFormat,
) -> Result<Toy4x4PaletteBlock, String> {
    validate_toy_4x4_frame_count(params)?;
    if format.chroma_sampling() != Some(crate::ChromaSampling::Cs444) {
        return Err(format!(
            "toy VVC palette path expects planar 4:4:4 input; got {format}"
        ));
    }

    let frame_len = Picture::expected_len(4, 4, format);
    let expected_len = frame_len * params.frames;
    if input.len() != expected_len {
        return Err(format!(
            "toy VVC input size mismatch: got {} bytes, expected {} for 4x4 {format} with {} frame(s)",
            input.len(),
            expected_len,
            params.frames
        ));
    }

    let bytes_per_sample = format.bytes_per_sample();
    let u_offset = 16 * bytes_per_sample;
    let v_offset = u_offset + (16 * bytes_per_sample);
    let entry = Toy4x4SampledColor {
        y: read_toy_sample_as_8bit(input, 0, format),
        u: read_toy_sample_as_8bit(input, u_offset, format),
        v: read_toy_sample_as_8bit(input, v_offset, format),
    };

    // First milestone palette coding: one lossy palette entry, all 4x4 samples
    // mapped to index 0. This keeps SW/RTL/VTM reconstruction aligned while
    // establishing a real palette-token boundary for SCC experiments.
    Ok(Toy4x4PaletteBlock {
        entry,
        indices: [0; 16],
    })
}

pub fn quantize_toy_4x4_color(color: Toy4x4SampledColor) -> Toy4x4QuantizedColor {
    quantize_toy_4x4_frame(Toy4x4SampledFrame::solid(color))
}

fn quantize_toy_4x4_frame(frame: Toy4x4SampledFrame) -> Toy4x4QuantizedColor {
    let luma_transform = transform_toy_4x4_luma(frame.luma);
    let quantized_luma = quantize_toy_4x4_luma_dc(luma_transform);
    let reconstructed_luma = inverse_transform_toy_4x4_luma_dc(quantized_luma);
    let chroma_rem = quantize_toy_4x4_chroma(frame.u, frame.v);
    let reconstructed_chroma = reconstruct_toy_4x4_chroma(chroma_rem);
    Toy4x4QuantizedColor {
        y: reconstructed_luma.samples[0],
        u: reconstructed_chroma,
        v: reconstructed_chroma,
        luma_rem: quantized_luma.abs_remainder,
        luma_ac_tokens: quantized_luma.ac_tokens,
        chroma_rem,
    }
}

fn validate_toy_4x4_frame_count(params: Toy4x4EncodeParams) -> Result<(), String> {
    if params.frames == 0 {
        return Err("toy VVC encode expects at least one frame".to_string());
    }
    if params.frames > 2 {
        return Err("toy VVC encode currently supports at most two frames".to_string());
    }
    Ok(())
}

fn toy_4x4_yuv420p8_annex_b(
    params: Toy4x4EncodeParams,
    frame: Toy4x4SampledFrame,
) -> Result<Vec<u8>, String> {
    toy_4x4_annex_b(params, frame, None)
}

fn toy_4x4_annex_b(
    params: Toy4x4EncodeParams,
    frame: Toy4x4SampledFrame,
    palette: Option<Toy4x4PaletteBlock>,
) -> Result<Vec<u8>, String> {
    let mut units = Vec::with_capacity(params.frames + 3);
    units.push(toy_4x4_sps_unit());
    units.push(toy_4x4_pps_unit());
    units.push(toy_4x4_color_filler_unit(frame.sampled_color()));
    if let Some(palette) = palette {
        units.push(toy_4x4_palette_sideband_unit(palette));
    }
    let quantized = quantize_toy_4x4_frame(frame);
    units.push(toy_4x4_coeff_sideband_unit(quantized));
    for frame_idx in 0..params.frames {
        units.push(toy_4x4_slice_unit(frame_idx, quantized)?);
    }
    write_annex_b(&units)
}

fn toy_4x4_palette_sideband_unit(palette: Toy4x4PaletteBlock) -> VvcNalUnit {
    VvcNalUnit {
        nal_unit_type: VvcNalUnitType::ReservedNvcl30,
        layer_id: 0,
        temporal_id: 0,
        rbsp_payload: toy_4x4_palette_sideband_payload(palette),
    }
}

fn toy_4x4_palette_sideband_payload(palette: Toy4x4PaletteBlock) -> Vec<u8> {
    let mut payload = Vec::with_capacity(17);
    payload.extend_from_slice(b"FFPL");
    payload.push(0x81); // FrameForge toy palette sideband version 1.
    payload.push(0x01); // One palette entry in this first 4:4:4 palette mode.
    payload.push(b"Y"[0]);
    payload.push(palette.entry.y);
    payload.push(b"U"[0]);
    payload.push(palette.entry.u);
    payload.push(b"V"[0]);
    payload.push(palette.entry.v);
    for chunk in palette.indices.chunks(4) {
        payload.push(0x40 | pack_palette_indices_2bit(chunk));
    }
    payload.push(0x80);
    payload
}

fn pack_palette_indices_2bit(indices: &[u8]) -> u8 {
    let mut packed = 0;
    for (idx, value) in indices.iter().enumerate() {
        packed |= (value & 0x03) << (6 - (idx * 2));
    }
    packed
}

fn toy_4x4_color_filler_unit(color: Toy4x4SampledColor) -> VvcNalUnit {
    VvcNalUnit {
        nal_unit_type: VvcNalUnitType::FillerData,
        layer_id: 0,
        temporal_id: 0,
        rbsp_payload: toy_4x4_color_filler_payload(color),
    }
}

fn toy_4x4_color_filler_payload(color: Toy4x4SampledColor) -> Vec<u8> {
    let filler_count = toy_4x4_color_filler_count(color);
    let mut payload = vec![0xff; filler_count];
    payload.push(0x80);
    payload
}

fn toy_4x4_color_filler_count(color: Toy4x4SampledColor) -> usize {
    ((color.y as usize) + (color.u as usize) + (color.v as usize)) & 0x0f
}

fn toy_4x4_coeff_sideband_unit(color: Toy4x4QuantizedColor) -> VvcNalUnit {
    VvcNalUnit {
        nal_unit_type: VvcNalUnitType::ReservedNvcl30,
        layer_id: 0,
        temporal_id: 0,
        rbsp_payload: toy_4x4_coeff_sideband_payload(color),
    }
}

fn toy_4x4_coeff_sideband_payload(color: Toy4x4QuantizedColor) -> Vec<u8> {
    let mut payload = Vec::with_capacity(23);
    payload.extend_from_slice(b"FFAC");
    payload.push(0x81); // FrameForge toy coefficient sideband version 1.
    payload.push(0x4f); // Fifteen AC tokens follow the DC token.
    payload.push(encode_toy_coeff_token(false, color.luma_rem));
    payload.extend(color.luma_ac_tokens);
    payload.push(0x80);
    payload
}

fn encode_toy_coeff_token(negative: bool, magnitude: u8) -> u8 {
    0x40 | (u8::from(negative) << 5) | (magnitude & 0x1f)
}

fn toy_4x4_sps_unit() -> VvcNalUnit {
    VvcNalUnit {
        nal_unit_type: VvcNalUnitType::Sps,
        layer_id: 0,
        temporal_id: 0,
        rbsp_payload: toy_4x4_sps_payload(),
    }
}

fn toy_4x4_pps_unit() -> VvcNalUnit {
    VvcNalUnit {
        nal_unit_type: VvcNalUnitType::Pps,
        layer_id: 0,
        temporal_id: 0,
        rbsp_payload: toy_4x4_pps_payload(),
    }
}

fn toy_4x4_slice_unit(frame_idx: usize, color: Toy4x4QuantizedColor) -> Result<VvcNalUnit, String> {
    let picture_kind = match frame_idx {
        0 => Toy4x4PictureKind::Idr,
        1 => Toy4x4PictureKind::Cra,
        _ => return Err(format!("unsupported toy VVC frame index {frame_idx}")),
    };

    Ok(VvcNalUnit {
        nal_unit_type: match picture_kind {
            Toy4x4PictureKind::Idr => VvcNalUnitType::IdrNLp,
            Toy4x4PictureKind::Cra => VvcNalUnitType::Cra,
        },
        layer_id: 0,
        temporal_id: 0,
        rbsp_payload: toy_4x4_slice_payload(picture_kind, color),
    })
}

fn toy_4x4_sps_payload() -> Vec<u8> {
    let mut writer = VvcSyntaxWriter::new();
    writer.write_u("sps_seq_parameter_set_id", 0, 4);
    writer.write_u("sps_video_parameter_set_id", 0, 4);
    writer.write_u("sps_max_sub_layers_minus1", 0, 3);
    writer.write_u("sps_chroma_format_idc", 1, 2);
    writer.write_u("sps_log2_ctu_size_minus5", 1, 2);
    writer.write_flag("sps_ptl_dpb_hrd_params_present_flag", true);
    writer.write_u("general_profile_idc", 1, 7);
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
    writer.write_ue("sps_pic_width_max_in_luma_samples", 8);
    writer.write_ue("sps_pic_height_max_in_luma_samples", 8);
    writer.write_flag("sps_conformance_window_flag", true);
    writer.write_ue("sps_conf_win_left_offset", 0);
    writer.write_ue("sps_conf_win_right_offset", 2);
    writer.write_ue("sps_conf_win_top_offset", 0);
    writer.write_ue("sps_conf_win_bottom_offset", 2);
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
    writer.write_flag("sps_qtbtt_dual_tree_intra_flag", true);
    writer.write_ue("sps_log2_diff_min_qt_min_cb_intra_slice_chroma", 1);
    writer.write_ue("sps_max_mtt_hierarchy_depth_intra_slice_chroma", 3);
    writer.write_ue("sps_log2_diff_max_bt_min_qt_intra_slice_chroma", 3);
    writer.write_ue("sps_log2_diff_max_tt_min_qt_intra_slice_chroma", 2);
    writer.write_ue("sps_log2_diff_min_qt_min_cb_inter_slice", 1);
    writer.write_ue("sps_max_mtt_hierarchy_depth_inter_slice", 3);
    writer.write_ue("sps_log2_diff_max_bt_min_qt_inter_slice", 3);
    writer.write_ue("sps_log2_diff_max_tt_min_qt_inter_slice", 3);
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
    writer.write_flag("sps_chroma_horizontal_collocated_flag", true);
    writer.write_flag("sps_chroma_vertical_collocated_flag", false);
    writer.write_flag("sps_palette_enabled_flag", false);
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

fn toy_4x4_pps_payload() -> Vec<u8> {
    let mut writer = VvcSyntaxWriter::new();
    writer.write_u("pps_pic_parameter_set_id", 0, 6);
    writer.write_u("pps_seq_parameter_set_id", 0, 4);
    writer.write_flag("pps_mixed_nalu_types_in_pic_flag", false);
    writer.write_ue("pps_pic_width_in_luma_samples", 8);
    writer.write_ue("pps_pic_height_in_luma_samples", 8);
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

fn toy_4x4_slice_payload(picture_kind: Toy4x4PictureKind, color: Toy4x4QuantizedColor) -> Vec<u8> {
    let mut writer = VvcSyntaxWriter::new();
    writer.write_flag("sh_picture_header_in_slice_header_flag", true);
    writer.write_flag("ph_gdr_or_irap_pic_flag", true);
    writer.write_flag("ph_non_ref_pic_flag", false);
    writer.write_flag("ph_gdr_pic_flag", false);
    writer.write_flag("ph_inter_slice_allowed_flag", false);
    writer.write_ue("ph_pic_parameter_set_id", 0);
    match picture_kind {
        Toy4x4PictureKind::Idr => {
            writer.write_u("ph_pic_order_cnt_lsb", 0, 8);
        }
        Toy4x4PictureKind::Cra => {
            writer.write_u("ph_pic_order_cnt_lsb", 1, 8);
        }
    }
    writer.write_flag("ph_partition_constraints_override_flag", false);
    writer.write_flag("ph_joint_cbcr_sign_flag", false);
    writer.write_flag("sh_no_output_of_prior_pics_flag", false);
    writer.write_se("sh_qp_delta", 0);
    writer.write_flag("sh_dep_quant_used_flag", true);
    writer.write_flag("cabac_alignment_one_bit", true);
    if picture_kind == Toy4x4PictureKind::Cra {
        writer.write_flag("cabac_alignment_one_bit", true);
    }
    writer.byte_align_zero("cabac_alignment_zero_bit");
    write_toy_coding_tree_entropy(&mut writer, color);
    writer.rbsp_trailing_bits();
    debug_assert!(writer.is_byte_aligned());
    writer.into_bytes()
}

fn write_toy_coding_tree_entropy(writer: &mut VvcSyntaxWriter, color: Toy4x4QuantizedColor) {
    let bits = toy_cabac_bits(color);
    writer.write_cabac_bits("cabac_toy_quantized_residual_bits", &bits);
}

fn toy_4x4_entropy_tokens(color: Toy4x4QuantizedColor) -> Vec<ToyEntropyToken> {
    vec![
        ToyEntropyToken {
            name: "split_cu_flag_luma_prefix",
            kind: ToyEntropyTokenKind::ContextBins {
                ctx_offset: 0,
                bins: &[false, true, false, true],
            },
        },
        ToyEntropyToken {
            name: "luma_intra_prediction_mode_prefix",
            kind: ToyEntropyTokenKind::ContextBins {
                ctx_offset: 4,
                bins: &[false, false, true, false],
            },
        },
        ToyEntropyToken {
            name: "luma_transform_unit_prefix",
            kind: ToyEntropyTokenKind::ContextBins {
                ctx_offset: 8,
                bins: &[true],
            },
        },
        ToyEntropyToken {
            name: "luma_abs_remainder",
            kind: ToyEntropyTokenKind::RemAbsEp {
                component: ToyResidualComponent::Luma,
                value: color.luma_rem,
                rice_param: 0,
            },
        },
        ToyEntropyToken {
            name: "luma_coeff_sign",
            kind: ToyEntropyTokenKind::SignEp {
                component: ToyResidualComponent::Luma,
                negative: true,
            },
        },
        ToyEntropyToken {
            name: "luma_residual_prefix",
            kind: ToyEntropyTokenKind::ContextBins {
                ctx_offset: 9,
                bins: &[true, false, true, true],
            },
        },
        ToyEntropyToken {
            name: "luma_residual_suffix",
            kind: ToyEntropyTokenKind::ContextBins {
                ctx_offset: 13,
                bins: &[true, false, false],
            },
        },
        ToyEntropyToken {
            name: "chroma_tree_prefix",
            kind: ToyEntropyTokenKind::ContextBins {
                ctx_offset: 16,
                bins: &[true, false, true],
            },
        },
        ToyEntropyToken {
            name: "cb_abs_remainder",
            kind: ToyEntropyTokenKind::RemAbsEp {
                component: ToyResidualComponent::ChromaCb,
                value: color.chroma_rem,
                rice_param: 0,
            },
        },
        ToyEntropyToken {
            name: "cb_coeff_sign",
            kind: ToyEntropyTokenKind::SignEp {
                component: ToyResidualComponent::ChromaCb,
                negative: true,
            },
        },
        ToyEntropyToken {
            name: "end_of_slice_segment_flag",
            kind: ToyEntropyTokenKind::Terminate,
        },
    ]
}

fn toy_cabac_bits(color: Toy4x4QuantizedColor) -> Vec<bool> {
    let mut cabac = ToyCabacEncoder::new();
    cabac.start();
    for token in toy_4x4_entropy_tokens(color) {
        match token.kind {
            ToyEntropyTokenKind::ContextBins { ctx_offset, bins } => {
                cabac.encode_ctx_bins(&TOY_CTX_EVENTS[ctx_offset..ctx_offset + bins.len()], bins);
            }
            ToyEntropyTokenKind::RemAbsEp {
                value, rice_param, ..
            } => {
                cabac.encode_rem_abs_ep(value as u32, rice_param as u32);
            }
            ToyEntropyTokenKind::SignEp { negative, .. } => {
                cabac.encode_bin_ep(negative);
            }
            ToyEntropyTokenKind::Terminate => {
                cabac.encode_bin_trm(true);
            }
        }
    }
    cabac.finish()
}

#[derive(Debug, Clone, Copy)]
struct ToyCtxEvent {
    lps: u16,
    mps: bool,
}

const TOY_CTX_EVENTS: [ToyCtxEvent; 19] = [
    ToyCtxEvent {
        lps: 146,
        mps: false,
    },
    ToyCtxEvent { lps: 81, mps: true },
    ToyCtxEvent {
        lps: 128,
        mps: true,
    },
    ToyCtxEvent { lps: 52, mps: true },
    ToyCtxEvent {
        lps: 160,
        mps: true,
    },
    ToyCtxEvent {
        lps: 129,
        mps: true,
    },
    ToyCtxEvent {
        lps: 24,
        mps: false,
    },
    ToyCtxEvent {
        lps: 58,
        mps: false,
    },
    ToyCtxEvent {
        lps: 29,
        mps: false,
    },
    ToyCtxEvent {
        lps: 172,
        mps: true,
    },
    ToyCtxEvent {
        lps: 107,
        mps: false,
    },
    ToyCtxEvent {
        lps: 136,
        mps: false,
    },
    ToyCtxEvent {
        lps: 128,
        mps: true,
    },
    ToyCtxEvent {
        lps: 125,
        mps: false,
    },
    ToyCtxEvent {
        lps: 184,
        mps: false,
    },
    ToyCtxEvent {
        lps: 112,
        mps: false,
    },
    ToyCtxEvent {
        lps: 28,
        mps: false,
    },
    ToyCtxEvent {
        lps: 67,
        mps: false,
    },
    ToyCtxEvent {
        lps: 26,
        mps: false,
    },
];

#[derive(Debug, Clone)]
struct ToyCabacEncoder {
    bits: Vec<bool>,
    low: u32,
    range: u32,
    buffered_byte: u32,
    num_buffered_bytes: u32,
    bits_left: i32,
}

impl ToyCabacEncoder {
    fn new() -> Self {
        Self {
            bits: Vec::new(),
            low: 0,
            range: 0,
            buffered_byte: 0,
            num_buffered_bytes: 0,
            bits_left: 0,
        }
    }

    fn start(&mut self) {
        self.low = 0;
        self.range = 510;
        self.buffered_byte = 0xff;
        self.num_buffered_bytes = 0;
        self.bits_left = 23;
    }

    fn encode_ctx_bins(&mut self, events: &[ToyCtxEvent], bins: &[bool]) {
        debug_assert_eq!(events.len(), bins.len());
        for (event, bin) in events.iter().zip(bins) {
            self.encode_bin(*bin, *event);
        }
    }

    fn encode_bin(&mut self, bin: bool, event: ToyCtxEvent) {
        let lps = event.lps as u32;
        self.range -= lps;
        if bin != event.mps {
            let num_bits = renorm_bits(lps);
            self.bits_left -= num_bits as i32;
            self.low += self.range;
            self.low <<= num_bits;
            self.range = lps << num_bits;
            if self.bits_left < 12 {
                self.write_out();
            }
        } else if self.range < 256 {
            let num_bits = renorm_bits(self.range);
            self.bits_left -= num_bits as i32;
            self.low <<= num_bits;
            self.range <<= num_bits;
            if self.bits_left < 12 {
                self.write_out();
            }
        }
    }

    fn encode_bin_ep(&mut self, bin: bool) {
        self.low <<= 1;
        if bin {
            self.low += self.range;
        }
        self.bits_left -= 1;
        if self.bits_left < 12 {
            self.write_out();
        }
    }

    fn encode_bins_ep(&mut self, bins: u32, num_bins: u32) {
        if self.range == 256 {
            self.encode_aligned_bins_ep(bins, num_bins);
            return;
        }

        let mut bins = bins;
        let mut num_bins = num_bins;
        while num_bins > 8 {
            num_bins -= 8;
            let pattern = bins >> num_bins;
            self.low <<= 8;
            self.low += self.range * pattern;
            bins -= pattern << num_bins;
            self.bits_left -= 8;
            if self.bits_left < 12 {
                self.write_out();
            }
        }

        self.low <<= num_bins;
        self.low += self.range * bins;
        self.bits_left -= num_bins as i32;
        if self.bits_left < 12 {
            self.write_out();
        }
    }

    fn encode_rem_abs_ep(&mut self, value: u32, rice_param: u32) {
        let cutoff = 5;
        let threshold = cutoff << rice_param;
        if value < threshold {
            let length = (value >> rice_param) + 1;
            self.encode_bins_ep((1 << length) - 2, length);
            self.encode_bins_ep(value & ((1 << rice_param) - 1), rice_param);
            return;
        }

        let code_value = (value >> rice_param) - cutoff;
        let mut prefix_length = 0;
        while code_value > ((2 << prefix_length) - 2) {
            prefix_length += 1;
        }
        let total_prefix_length = prefix_length + cutoff;
        let suffix_length = prefix_length + rice_param + 1;
        let prefix = (1 << total_prefix_length) - 1;
        let suffix = ((code_value - ((1 << prefix_length) - 1)) << rice_param)
            | (value & ((1 << rice_param) - 1));
        self.encode_bins_ep(prefix, total_prefix_length);
        self.encode_bins_ep(suffix, suffix_length);
    }

    fn encode_bin_trm(&mut self, bin: bool) {
        self.range -= 2;
        if bin {
            self.low += self.range;
            self.low <<= 7;
            self.range = 2 << 7;
            self.bits_left -= 7;
        } else if self.range < 256 {
            self.low <<= 1;
            self.range <<= 1;
            self.bits_left -= 1;
        }
        if self.bits_left < 12 {
            self.write_out();
        }
    }

    fn finish(mut self) -> Vec<bool> {
        if (self.low >> (32 - self.bits_left)) != 0 {
            self.write_bits(self.buffered_byte + 1, 8);
            while self.num_buffered_bytes > 1 {
                self.write_bits(0, 8);
                self.num_buffered_bytes -= 1;
            }
            self.low -= 1 << (32 - self.bits_left);
        } else {
            if self.num_buffered_bytes > 0 {
                self.write_bits(self.buffered_byte, 8);
            }
            while self.num_buffered_bytes > 1 {
                self.write_bits(0xff, 8);
                self.num_buffered_bytes -= 1;
            }
        }
        let final_bits = 24 - self.bits_left;
        if final_bits > 0 {
            self.write_bits(self.low >> 8, final_bits as u32);
        }
        self.bits
    }

    fn write_out(&mut self) {
        let lead_byte = self.low >> (24 - self.bits_left);
        self.bits_left += 8;
        self.low &= 0xffff_ffff >> self.bits_left;
        if lead_byte == 0xff {
            self.num_buffered_bytes += 1;
        } else if self.num_buffered_bytes > 0 {
            let carry = lead_byte >> 8;
            let byte = self.buffered_byte + carry;
            self.buffered_byte = lead_byte & 0xff;
            self.write_bits(byte, 8);
            let repeated_byte = (0xff + carry) & 0xff;
            while self.num_buffered_bytes > 1 {
                self.write_bits(repeated_byte, 8);
                self.num_buffered_bytes -= 1;
            }
        } else {
            self.num_buffered_bytes = 1;
            self.buffered_byte = lead_byte;
        }
    }

    fn write_bits(&mut self, value: u32, bit_count: u32) {
        for bit in (0..bit_count).rev() {
            self.bits.push(((value >> bit) & 1) != 0);
        }
    }

    fn encode_aligned_bins_ep(&mut self, bins: u32, num_bins: u32) {
        let mut rem_bins = num_bins;
        while rem_bins > 0 {
            let bins_to_code = rem_bins.min(8);
            let bin_mask = (1 << bins_to_code) - 1;
            let new_bins = (bins >> (rem_bins - bins_to_code)) & bin_mask;
            self.low = (self.low << bins_to_code) + (new_bins << 8);
            rem_bins -= bins_to_code;
            self.bits_left -= bins_to_code as i32;
            if self.bits_left < 12 {
                self.write_out();
            }
        }
    }
}

fn renorm_bits(mut range: u32) -> u32 {
    let mut bits = 0;
    while range < 256 {
        range <<= 1;
        bits += 1;
    }
    bits
}

fn transform_toy_4x4_luma(samples: [u8; 16]) -> Toy4x4TransformBlock {
    let sum: u16 = samples.iter().map(|sample| *sample as u16).sum();
    let dc_sample = ((sum + 8) >> 4) as u8;
    let mut ac_coeffs = [0; 15];
    for (dst, sample) in ac_coeffs.iter_mut().zip(samples.iter().skip(1)) {
        *dst = *sample as i16 - dc_sample as i16;
    }
    Toy4x4TransformBlock {
        dc_coeff: dc_sample as i16 - TOY_LUMA_DC_BASE,
        ac_coeffs,
    }
}

fn quantize_toy_4x4_luma_dc(block: Toy4x4TransformBlock) -> Toy4x4QuantizedTransformBlock {
    let sample = (block.dc_coeff + TOY_LUMA_DC_BASE).clamp(0, u8::MAX as i16) as u8;
    let (reconstructed_sample, abs_remainder) = nearest_quantized_luma(sample);
    let mut reconstructed_ac_coeffs = [0; 15];
    let mut ac_tokens = [0; 15];
    for ((reconstructed, token), coeff) in reconstructed_ac_coeffs
        .iter_mut()
        .zip(ac_tokens.iter_mut())
        .zip(block.ac_coeffs)
    {
        let quantized = quantize_toy_ac_coeff(coeff);
        *reconstructed = quantized as i16 * 16;
        *token = encode_toy_coeff_token(quantized < 0, quantized.unsigned_abs());
    }
    Toy4x4QuantizedTransformBlock {
        reconstructed_dc_coeff: reconstructed_sample as i16 - TOY_LUMA_DC_BASE,
        reconstructed_ac_coeffs,
        abs_remainder,
        ac_tokens,
    }
}

fn inverse_transform_toy_4x4_luma_dc(
    block: Toy4x4QuantizedTransformBlock,
) -> Toy4x4ReconstructedLumaBlock {
    let sample = (block.reconstructed_dc_coeff + TOY_LUMA_DC_BASE).clamp(0, u8::MAX as i16) as u8;
    let mut samples = [sample; 16];
    for (dst, coeff) in samples
        .iter_mut()
        .skip(1)
        .zip(block.reconstructed_ac_coeffs)
    {
        *dst = (sample as i16 + coeff).clamp(0, u8::MAX as i16) as u8;
    }
    Toy4x4ReconstructedLumaBlock { samples }
}

fn quantize_toy_ac_coeff(coeff: i16) -> i8 {
    let magnitude = ((coeff.unsigned_abs() + 8) >> 4).min(8) as i8;
    if coeff < 0 {
        -magnitude
    } else {
        magnitude
    }
}

fn quantize_toy_4x4_chroma(u: u8, v: u8) -> u8 {
    if u == 0 && v == 0 {
        6
    } else {
        0
    }
}

fn reconstruct_toy_4x4_chroma(chroma_rem: u8) -> u8 {
    if chroma_rem == 0 {
        96
    } else {
        0
    }
}

fn nearest_quantized_luma(input: u8) -> (u8, u8) {
    let mut best_value = 0;
    let mut best_rem = 16;
    let mut best_error = u16::MAX;
    for rem in 0..=16 {
        let value = (((16 - rem) as u16 * 114 + 8) / 16) as u8;
        let error = input.abs_diff(value) as u16;
        if error < best_error {
            best_value = value;
            best_rem = rem;
            best_error = error;
        }
    }
    (best_value, best_rem)
}

const TOY_LUMA_DC_BASE: i16 = 114;

fn placeholder_rbsp() -> Vec<u8> {
    // TODO(vvc): Replace this rbsp_trailing_bits-only payload with real VPS,
    // SPS, PPS, and slice RBSP syntax from a clean-room implementation.
    let mut writer = VvcSyntaxWriter::new();
    writer.rbsp_trailing_bits();
    writer.into_bytes()
}

pub fn nal_unit_header_bytes(unit: &VvcNalUnit) -> Result<[u8; 2], String> {
    if unit.layer_id > 55 {
        return Err("VVC nuh_layer_id must be in the range 0..=55".to_string());
    }
    if unit.temporal_id > 6 {
        return Err("VVC temporal_id must be in the range 0..=6".to_string());
    }

    let header = VvcNalHeader {
        forbidden_zero_bit: false,
        nuh_reserved_zero_bit: false,
        layer_id: unit.layer_id,
        nal_unit_type: unit.nal_unit_type,
        temporal_id: unit.temporal_id,
    };
    let bytes = write_nal_unit_header(header).bytes;
    Ok([bytes[0], bytes[1]])
}

pub fn write_nal_unit_header(header: VvcNalHeader) -> VvcSyntaxRbsp {
    let mut writer = VvcSyntaxWriter::new();
    writer.write_flag("forbidden_zero_bit", header.forbidden_zero_bit);
    writer.write_flag("nuh_reserved_zero_bit", header.nuh_reserved_zero_bit);
    writer.write_u("nuh_layer_id", header.layer_id as u64, 6);
    writer.write_u("nal_unit_type", header.nal_unit_type as u64, 5);
    writer.write_u("nuh_temporal_id_plus1", header.temporal_id as u64 + 1, 3);
    writer.finish()
}

pub fn parse_annex_b_nal_units(bytes: &[u8]) -> Result<Vec<VvcNalInfo>, String> {
    let ranges = annex_b_ranges(bytes);
    let mut infos = Vec::with_capacity(ranges.len());

    for (start, end) in ranges {
        if end - start < 2 {
            return Err(format!(
                "NAL unit at offset {start} is too short for a VVC header"
            ));
        }
        let h0 = bytes[start];
        let h1 = bytes[start + 1];
        let forbidden_zero_bit = h0 >> 7;
        let nuh_reserved_zero_bit = (h0 >> 6) & 0x01;
        if forbidden_zero_bit != 0 || nuh_reserved_zero_bit != 0 {
            return Err(format!(
                "invalid VVC NAL header reserved bits at offset {start}"
            ));
        }
        let layer_id = h0 & 0x3f;
        if layer_id > 55 {
            return Err(format!(
                "VVC layer id {layer_id} out of range at offset {start}"
            ));
        }
        let nal_unit_type = h1 >> 3;
        let temporal_id_plus1 = h1 & 0x07;
        if temporal_id_plus1 == 0 {
            return Err(format!("VVC temporal_id_plus1 is zero at offset {start}"));
        }
        infos.push(VvcNalInfo {
            nal_unit_type,
            layer_id,
            temporal_id: temporal_id_plus1 - 1,
            payload_len: end - start - 2,
            offset: start,
        });
    }

    Ok(infos)
}

fn annex_b_ranges(bytes: &[u8]) -> Vec<(usize, usize)> {
    let mut starts = Vec::new();
    let mut i = 0;
    while i + 3 <= bytes.len() {
        if i + 4 <= bytes.len() && bytes[i..i + 4] == [0, 0, 0, 1] {
            starts.push((i, 4));
            i += 4;
        } else if bytes[i..i + 3] == [0, 0, 1] {
            starts.push((i, 3));
            i += 3;
        } else {
            i += 1;
        }
    }

    starts
        .iter()
        .enumerate()
        .map(|(idx, (prefix_pos, prefix_len))| {
            let payload_start = prefix_pos + prefix_len;
            let payload_end = starts
                .get(idx + 1)
                .map(|(next_prefix_pos, _)| *next_prefix_pos)
                .unwrap_or(bytes.len());
            (payload_start, payload_end)
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn toy_transform_block(dc_coeff: i16) -> Toy4x4TransformBlock {
        Toy4x4TransformBlock {
            dc_coeff,
            ac_coeffs: [0; 15],
        }
    }

    fn toy_quantized_block(
        reconstructed_dc_coeff: i16,
        abs_remainder: u8,
    ) -> Toy4x4QuantizedTransformBlock {
        Toy4x4QuantizedTransformBlock {
            reconstructed_dc_coeff,
            reconstructed_ac_coeffs: [0; 15],
            abs_remainder,
            ac_tokens: [0x40; 15],
        }
    }

    fn toy_quantized_color(y: u8, luma_rem: u8) -> Toy4x4QuantizedColor {
        Toy4x4QuantizedColor {
            y,
            u: 0,
            v: 0,
            luma_rem,
            luma_ac_tokens: [0x40; 15],
            chroma_rem: 6,
        }
    }

    fn toy_quantized_color_with_chroma(
        y: u8,
        luma_rem: u8,
        chroma: u8,
        chroma_rem: u8,
    ) -> Toy4x4QuantizedColor {
        Toy4x4QuantizedColor {
            y,
            u: chroma,
            v: chroma,
            luma_rem,
            luma_ac_tokens: [0x40; 15],
            chroma_rem,
        }
    }

    #[test]
    fn eos_header_matches_vvc_packing() {
        let unit = VvcNalUnit::eos();
        assert_eq!(nal_unit_header_bytes(&unit).unwrap(), [0x00, 0xa9]);
    }

    #[test]
    fn nal_header_writer_records_named_fields() {
        let rbsp = write_nal_unit_header(VvcNalHeader {
            forbidden_zero_bit: false,
            nuh_reserved_zero_bit: false,
            layer_id: 0,
            nal_unit_type: VvcNalUnitType::IdrNLp,
            temporal_id: 0,
        });

        assert_eq!(rbsp.bytes, vec![0x00, 0x41]);
        assert_eq!(
            rbsp.fields,
            vec![
                VvcSyntaxField {
                    name: "forbidden_zero_bit",
                    code: VvcSyntaxCode::Flag,
                    bit_offset: 0,
                    bit_count: 1,
                },
                VvcSyntaxField {
                    name: "nuh_reserved_zero_bit",
                    code: VvcSyntaxCode::Flag,
                    bit_offset: 1,
                    bit_count: 1,
                },
                VvcSyntaxField {
                    name: "nuh_layer_id",
                    code: VvcSyntaxCode::U,
                    bit_offset: 2,
                    bit_count: 6,
                },
                VvcSyntaxField {
                    name: "nal_unit_type",
                    code: VvcSyntaxCode::U,
                    bit_offset: 8,
                    bit_count: 5,
                },
                VvcSyntaxField {
                    name: "nuh_temporal_id_plus1",
                    code: VvcSyntaxCode::U,
                    bit_offset: 13,
                    bit_count: 3,
                },
            ]
        );
    }

    #[test]
    fn eos_annex_b_contains_start_code_and_header() {
        assert_eq!(eos_annex_b(), vec![0x00, 0x00, 0x00, 0x01, 0x00, 0xa9]);
    }

    #[test]
    fn skeleton_annex_b_contains_parameter_sets_idr_and_end_markers() {
        let bytes = skeleton_annex_b();
        let expected = vec![
            0x00, 0x00, 0x00, 0x01, 0x00, 0x71, 0x80, // VPS
            0x00, 0x00, 0x00, 0x01, 0x00, 0x79, 0x80, // SPS
            0x00, 0x00, 0x00, 0x01, 0x00, 0x81, 0x80, // PPS
            0x00, 0x00, 0x00, 0x01, 0x00, 0x41, 0x80, // IDR_N_LP
            0x00, 0x00, 0x00, 0x01, 0x00, 0xa9, // EOS
            0x00, 0x00, 0x00, 0x01, 0x00, 0xb1, // EOB
        ];
        assert_eq!(bytes, expected);
    }

    #[test]
    fn rejects_invalid_layer_id() {
        let mut unit = VvcNalUnit::eos();
        unit.layer_id = 56;
        assert!(nal_unit_header_bytes(&unit).is_err());
    }

    #[test]
    fn parses_skeleton_annex_b_headers() {
        let infos = parse_annex_b_nal_units(&skeleton_annex_b()).unwrap();
        let types: Vec<u8> = infos.iter().map(|info| info.nal_unit_type).collect();
        assert_eq!(types, vec![14, 15, 16, 8, 21, 22]);
        assert_eq!(infos[0].payload_len, 1);
        assert_eq!(infos[4].payload_len, 0);
    }

    #[test]
    fn syntax_writer_records_named_fixed_width_fields() {
        let mut writer = VvcSyntaxWriter::new();
        writer.write_flag("ph_gdr_or_irap_pic_flag", true);
        writer.write_u("sps_seq_parameter_set_id", 3, 4);
        writer.rbsp_trailing_bits();
        let rbsp = writer.finish();

        assert_eq!(rbsp.bytes, vec![0b1001_1100]);
        assert_eq!(
            rbsp.fields,
            vec![
                VvcSyntaxField {
                    name: "ph_gdr_or_irap_pic_flag",
                    code: VvcSyntaxCode::Flag,
                    bit_offset: 0,
                    bit_count: 1,
                },
                VvcSyntaxField {
                    name: "sps_seq_parameter_set_id",
                    code: VvcSyntaxCode::U,
                    bit_offset: 1,
                    bit_count: 4,
                },
                VvcSyntaxField {
                    name: "rbsp_trailing_bits",
                    code: VvcSyntaxCode::RbspTrailingBits,
                    bit_offset: 5,
                    bit_count: 3,
                },
            ]
        );
    }

    #[test]
    fn syntax_writer_encodes_unsigned_exp_golomb() {
        let mut writer = VvcSyntaxWriter::new();
        writer.write_ue("sps_log2_ctu_size_minus5", 0);
        writer.write_ue("pps_num_subpics_minus1", 5);
        writer.rbsp_trailing_bits();
        let rbsp = writer.finish();

        assert_eq!(rbsp.bytes, vec![0b1001_1010]);
        assert_eq!(rbsp.fields[0].bit_count, 1);
        assert_eq!(rbsp.fields[1].bit_offset, 1);
        assert_eq!(rbsp.fields[1].bit_count, 5);
        assert_eq!(rbsp.fields[2].bit_offset, 6);
    }

    #[test]
    fn syntax_writer_encodes_signed_exp_golomb() {
        let mut writer = VvcSyntaxWriter::new();
        writer.write_se("slice_qp_delta", 0);
        writer.write_se("delta_luma_weight_l0", 1);
        writer.write_se("delta_chroma_offset_l0", -1);
        writer.rbsp_trailing_bits();
        let rbsp = writer.finish();

        assert_eq!(rbsp.bytes, vec![0b1010_0111]);
        assert_eq!(rbsp.fields[0].code, VvcSyntaxCode::Se);
        assert_eq!(rbsp.fields[0].bit_count, 1);
        assert_eq!(rbsp.fields[1].bit_count, 3);
        assert_eq!(rbsp.fields[2].bit_count, 3);
    }

    #[test]
    fn parses_toy_black_4x4_one_frame_headers() {
        let bytes = toy_black_4x4_yuv420p8_annex_b(Toy4x4EncodeParams { frames: 1 }).unwrap();
        assert_eq!(bytes.len(), 110);
        let infos = parse_annex_b_nal_units(&bytes).unwrap();
        let types: Vec<u8> = infos.iter().map(|info| info.nal_unit_type).collect();
        assert_eq!(types, vec![15, 16, 25, 30, 8]);
        assert_eq!(infos[0].payload_len, 31);
        assert_eq!(infos[1].payload_len, 14);
        assert_eq!(infos[2].payload_len, 1);
        assert_eq!(infos[3].payload_len, 23);
        assert_eq!(infos[4].payload_len, 11);
    }

    #[test]
    fn toy_parameter_sets_are_generated_from_named_syntax() {
        assert_eq!(
            toy_4x4_sps_payload(),
            hex_bytes("000b020080004244eed501f446e884688424613628c5430680ab8fe0ac1020")
        );
        assert_eq!(
            toy_4x4_pps_payload(),
            hex_bytes("0002448a4200c7b2145945945880")
        );
    }

    #[test]
    fn toy_slice_header_is_generated_before_cabac_tokens() {
        let black = quantize_toy_4x4_color(Toy4x4SampledColor { y: 0, u: 0, v: 0 });
        assert_eq!(
            toy_4x4_slice_payload(Toy4x4PictureKind::Idr, black),
            hex_bytes("c400708062f5b7ebcb1f80")
        );
        assert_eq!(
            toy_4x4_slice_payload(Toy4x4PictureKind::Cra, black),
            hex_bytes("c404788062f5b7ebcb1f80")
        );
    }

    #[test]
    fn toy_solid_luma_transform_generates_dc_only() {
        assert_eq!(transform_toy_4x4_luma([0; 16]), toy_transform_block(-114));
        assert_eq!(transform_toy_4x4_luma([64; 16]), toy_transform_block(-50));
        assert_eq!(transform_toy_4x4_luma([114; 16]), toy_transform_block(0));
    }

    #[test]
    fn toy_luma_transform_dc_uses_all_samples() {
        let mut samples = [64; 16];
        samples[3] = 255;
        let mut ac_coeffs = [-12; 15];
        ac_coeffs[2] = 179;
        assert_eq!(
            transform_toy_4x4_luma(samples),
            Toy4x4TransformBlock {
                dc_coeff: -38,
                ac_coeffs
            }
        );
    }

    #[test]
    fn toy_luma_dc_quantization_matches_existing_ladder() {
        let black = quantize_toy_4x4_luma_dc(transform_toy_4x4_luma([0; 16]));
        assert_eq!(black, toy_quantized_block(-114, 16));

        let mid = quantize_toy_4x4_luma_dc(transform_toy_4x4_luma([65; 16]));
        assert_eq!(mid, toy_quantized_block(-50, 7));

        let white = quantize_toy_4x4_luma_dc(transform_toy_4x4_luma([255; 16]));
        assert_eq!(white, toy_quantized_block(0, 0));
    }

    #[test]
    fn toy_inverse_transform_reconstructs_solid_luma_block() {
        let quantized = toy_quantized_block(-50, 7);
        assert_eq!(
            inverse_transform_toy_4x4_luma_dc(quantized),
            Toy4x4ReconstructedLumaBlock { samples: [64; 16] }
        );
    }

    #[test]
    fn toy_color_quantization_uses_inverse_transform_reconstruction() {
        assert_eq!(
            quantize_toy_4x4_color(Toy4x4SampledColor { y: 65, u: 9, v: 7 }),
            toy_quantized_color_with_chroma(64, 7, 96, 0)
        );
    }

    #[test]
    fn toy_frame_quantization_uses_all_luma_samples_for_dc() {
        let mut luma = [64; 16];
        luma[3] = 255;
        let mut ac_tokens = [0x61; 15];
        ac_tokens[2] = 0x48;
        assert_eq!(
            quantize_toy_4x4_frame(Toy4x4SampledFrame { luma, u: 9, v: 7 }),
            Toy4x4QuantizedColor {
                y: 78,
                u: 96,
                v: 96,
                luma_rem: 5,
                luma_ac_tokens: ac_tokens,
                chroma_rem: 0
            }
        );
    }

    #[test]
    fn toy_chroma_quantization_keeps_black_neutral_and_nonzero_colored() {
        assert_eq!(quantize_toy_4x4_chroma(0, 0), 6);
        assert_eq!(reconstruct_toy_4x4_chroma(6), 0);
        assert_eq!(quantize_toy_4x4_chroma(128, 192), 0);
        assert_eq!(reconstruct_toy_4x4_chroma(0), 96);
    }

    #[test]
    fn toy_inverse_transform_reconstructs_quantized_ac_coefficients() {
        let mut block = toy_quantized_block(-36, 5);
        block.reconstructed_ac_coeffs[2] = 128;
        block.ac_tokens[2] = 0x48;
        assert_eq!(inverse_transform_toy_4x4_luma_dc(block).samples[3], 206);
    }

    #[test]
    fn toy_coefficient_sideband_serializes_ac_tokens() {
        let mut color = toy_quantized_color(78, 5);
        color.luma_ac_tokens[2] = 0x48;
        assert_eq!(
            toy_4x4_coeff_sideband_payload(color),
            hex_bytes("46464143814f4540404840404040404040404040404080")
        );
    }

    #[test]
    fn toy_arithmetic_writer_generates_verified_luma_payloads() {
        let expected = [
            "c4007080593f5e58fc",
            "c40070805e1faf2c7e",
            "c4007080608fd7963f",
            "c400708061c7ebcb1f80",
            "c40070806263f5e58fc0",
            "c400708062b1faf2c7e0",
            "c400708062cf7ebcb1f8",
            "c400708062ddfebcb1f8",
            "c400708062e55faf2c7e",
            "c400708062e8ffaf2c7e",
            "c400708062ec9faf2c7e",
            "c400708062f03faf2c7e",
            "c400708062f217ebcb1f80",
            "c400708062f2ffebcb1f80",
            "c400708062f3e7ebcb1f80",
            "c400708062f4cfebcb1f80",
            "c400708062f5b7ebcb1f80",
        ];

        for (luma_rem, expected_payload) in expected.iter().enumerate() {
            let color = toy_quantized_color(0, luma_rem as u8);
            assert_eq!(
                toy_4x4_slice_payload(Toy4x4PictureKind::Idr, color),
                hex_bytes(expected_payload)
            );
        }
    }

    #[test]
    fn toy_coding_tree_entropy_is_generated_from_tokens() {
        let black = quantize_toy_4x4_color(Toy4x4SampledColor { y: 0, u: 0, v: 0 });
        let tokens = toy_4x4_entropy_tokens(black);
        assert_eq!(tokens.len(), 11);
        assert_eq!(tokens[0].name, "split_cu_flag_luma_prefix");
        assert_eq!(
            tokens[0].kind,
            ToyEntropyTokenKind::ContextBins {
                ctx_offset: 0,
                bins: &[false, true, false, true]
            }
        );
        assert_eq!(
            tokens[3].kind,
            ToyEntropyTokenKind::RemAbsEp {
                component: ToyResidualComponent::Luma,
                value: 16,
                rice_param: 0
            }
        );
        assert_eq!(tokens[10].kind, ToyEntropyTokenKind::Terminate);
        let mut writer = VvcSyntaxWriter::new();
        write_toy_coding_tree_entropy(&mut writer, black);
        let rbsp = writer.finish();
        assert_eq!(rbsp.bytes, hex_bytes("8062f5b7ebcb1f"));
        assert!(rbsp
            .fields
            .iter()
            .all(|field| field.code == VvcSyntaxCode::CabacToken));
        assert_eq!(rbsp.fields.len(), 1);
        assert_eq!(rbsp.fields[0].bit_count, 56);
    }

    #[test]
    fn parses_toy_black_4x4_two_frame_headers() {
        let bytes = toy_black_4x4_yuv420p8_annex_b(Toy4x4EncodeParams { frames: 2 }).unwrap();
        assert_eq!(bytes.len(), 127);
        let infos = parse_annex_b_nal_units(&bytes).unwrap();
        let types: Vec<u8> = infos.iter().map(|info| info.nal_unit_type).collect();
        assert_eq!(types, vec![15, 16, 25, 30, 8, 9]);
        assert_eq!(infos[3].payload_len, 23);
        assert_eq!(infos[5].offset, 114);
        assert_eq!(infos[5].payload_len, 11);
    }

    #[test]
    fn toy_4x4_input_path_accepts_black_yuv420p8_frames() {
        let input = vec![0; Picture::expected_len(4, 4, PixelFormat::Yuv420p8) * 2];
        let from_input =
            toy_4x4_yuv420p8_annex_b_from_input(&input, Toy4x4EncodeParams { frames: 2 }).unwrap();
        let generated = toy_black_4x4_yuv420p8_annex_b(Toy4x4EncodeParams { frames: 2 }).unwrap();
        assert_eq!(from_input, generated);
    }

    #[test]
    fn toy_4x4_input_path_samples_first_yuv_values() {
        let mut input = solid_yuv420p8(64, 128, 192, 2);
        input[3] = 255;
        input[17] = 0;
        input[21] = 1;
        let color =
            sample_toy_4x4_first_yuv420p8(&input, Toy4x4EncodeParams { frames: 2 }).unwrap();
        assert_eq!(
            color,
            Toy4x4SampledColor {
                y: 64,
                u: 128,
                v: 192,
            }
        );
    }

    #[test]
    fn toy_4x4_input_path_samples_only_first_frame() {
        let mut input = solid_yuv420p8(64, 128, 192, 2);
        let second_frame = Picture::expected_len(4, 4, PixelFormat::Yuv420p8);
        input[second_frame] = 1;
        input[second_frame + 16] = 2;
        input[second_frame + 20] = 3;
        let color =
            sample_toy_4x4_first_yuv420p8(&input, Toy4x4EncodeParams { frames: 2 }).unwrap();
        assert_eq!(
            color,
            Toy4x4SampledColor {
                y: 64,
                u: 128,
                v: 192,
            }
        );
    }

    #[test]
    fn toy_4x4_bitstream_path_accepts_sampled_non_black_input() {
        let input = solid_yuv420p8(65, 128, 192, 1);
        let bytes =
            toy_4x4_yuv420p8_annex_b_from_input(&input, Toy4x4EncodeParams { frames: 1 }).unwrap();
        let infos = parse_annex_b_nal_units(&bytes).unwrap();
        let types: Vec<u8> = infos.iter().map(|info| info.nal_unit_type).collect();
        assert_eq!(types, vec![15, 16, 25, 30, 8]);
        assert_eq!(infos[2].payload_len, 2);
        assert_eq!(infos[3].payload_len, 23);
    }

    #[test]
    fn toy_4x4_input_path_accepts_wider_yuv420p_formats() {
        let expected = toy_4x4_yuv420p8_annex_b_from_input(
            &solid_yuv420p8(65, 128, 192, 1),
            Toy4x4EncodeParams { frames: 1 },
        )
        .unwrap();
        for (format, bit_depth) in [
            (PixelFormat::Yuv420p10, 10),
            (PixelFormat::Yuv420p12, 12),
            (PixelFormat::Yuv420p16, 16),
        ] {
            let input = solid_yuv420p_high(65, 128, 192, bit_depth, 1);
            assert_eq!(
                toy_4x4_yuv420p_annex_b_from_input(
                    &input,
                    Toy4x4EncodeParams { frames: 1 },
                    format
                )
                .unwrap(),
                expected
            );
        }
    }

    #[test]
    fn toy_4x4_input_path_accepts_supported_yuv_subsampling() {
        let expected = toy_4x4_yuv420p8_annex_b_from_input(
            &solid_yuv420p8(65, 128, 192, 1),
            Toy4x4EncodeParams { frames: 1 },
        )
        .unwrap();
        for (format, chroma_samples) in [(PixelFormat::Yuv422p8, 8), (PixelFormat::Yuv422p10, 8)] {
            let input =
                solid_yuv_planar_high(65, 128, 192, format.bit_depth().bits(), chroma_samples, 1);
            assert_eq!(
                toy_4x4_yuv_annex_b_from_input(&input, Toy4x4EncodeParams { frames: 1 }, format)
                    .unwrap(),
                expected
            );
        }
    }

    #[test]
    fn toy_4x4_yuv444_input_uses_palette_sideband() {
        let input = solid_yuv_planar_high(65, 128, 192, 8, 16, 1);
        let bytes = toy_4x4_yuv_annex_b_from_input(
            &input,
            Toy4x4EncodeParams { frames: 1 },
            PixelFormat::Yuv444p8,
        )
        .unwrap();
        let infos = parse_annex_b_nal_units(&bytes).unwrap();
        let types: Vec<u8> = infos.iter().map(|info| info.nal_unit_type).collect();
        assert_eq!(types, vec![15, 16, 25, 30, 30, 8]);
        assert_eq!(infos[3].payload_len, 17);
        assert_eq!(infos[4].payload_len, 23);
        assert!(bytes.windows(4).any(|window| window == b"FFPL"));
        assert!(bytes.windows(4).any(|window| window == b"FFAC"));
    }

    #[test]
    fn toy_4x4_input_path_changes_bitstream_from_sampled_color() {
        let mut input = solid_yuv420p8(65, 128, 192, 2);
        input[1] = 0;
        input[17] = 0;
        let from_input =
            toy_4x4_yuv420p8_annex_b_from_input(&input, Toy4x4EncodeParams { frames: 2 }).unwrap();
        let current_bitstream =
            toy_black_4x4_yuv420p8_annex_b(Toy4x4EncodeParams { frames: 2 }).unwrap();
        assert_ne!(from_input, current_bitstream);
    }

    #[test]
    fn rejects_unsupported_toy_frame_count() {
        assert!(toy_black_4x4_yuv420p8_annex_b(Toy4x4EncodeParams { frames: 0 }).is_err());
        assert!(toy_black_4x4_yuv420p8_annex_b(Toy4x4EncodeParams { frames: 3 }).is_err());
    }

    fn hex_bytes(hex: &str) -> Vec<u8> {
        assert_eq!(hex.len() % 2, 0);
        hex.as_bytes()
            .chunks_exact(2)
            .map(|digits| {
                let text = std::str::from_utf8(digits).unwrap();
                u8::from_str_radix(text, 16).unwrap()
            })
            .collect()
    }

    fn solid_yuv420p8(y: u8, u: u8, v: u8, frames: usize) -> Vec<u8> {
        let mut out =
            Vec::with_capacity(Picture::expected_len(4, 4, PixelFormat::Yuv420p8) * frames);
        for _ in 0..frames {
            out.extend(std::iter::repeat_n(y, 16));
            out.extend(std::iter::repeat_n(u, 4));
            out.extend(std::iter::repeat_n(v, 4));
        }
        out
    }

    fn solid_yuv420p_high(y: u8, u: u8, v: u8, bit_depth: u8, frames: usize) -> Vec<u8> {
        solid_yuv_planar_high(y, u, v, bit_depth, 4, frames)
    }

    fn solid_yuv_planar_high(
        y: u8,
        u: u8,
        v: u8,
        bit_depth: u8,
        chroma_samples: usize,
        frames: usize,
    ) -> Vec<u8> {
        let mut out = Vec::new();
        for _ in 0..frames {
            for sample in [y]
                .repeat(16)
                .into_iter()
                .chain([u].repeat(chroma_samples))
                .chain([v].repeat(chroma_samples))
            {
                let value = (sample as u16) << (bit_depth - 8);
                if bit_depth == 8 {
                    out.push(sample);
                } else {
                    out.extend(value.to_le_bytes());
                }
            }
        }
        out
    }
}
