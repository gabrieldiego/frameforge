//! First-target VVC/H.266 placeholders.
//!
//! This module intentionally does not implement VVC syntax yet. Exact NAL unit
//! types, parameter sets, slice headers, CTU syntax, CABAC, transform/quant,
//! and reconstruction semantics must be added from the specification or another
//! clean-room source before FrameForge can emit a decodable VVC bitstream.

use crate::bitstream::insert_emulation_prevention_bytes;
use crate::bitstream::{rbsp_trailing_bits, BitWriter};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VvcSyntaxCode {
    Flag,
    U,
    Ue,
    Se,
    ObservedRegion,
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

    pub fn write_observed_region(&mut self, name: &'static str, value: u64, bit_count: u8) {
        assert!(
            bit_count <= 64,
            "observed region cannot write more than 64 bits"
        );
        self.push_field(name, VvcSyntaxCode::ObservedRegion, bit_count as usize);
        self.writer.write_bits(value, bit_count);
        self.bit_offset += bit_count as usize;
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
enum Toy4x4PictureKind {
    Idr,
    Cra,
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
    if params.frames == 0 {
        return Err("toy VVC encode expects at least one frame".to_string());
    }
    if params.frames > 2 {
        return Err("toy VVC encode currently supports at most two frames".to_string());
    }

    let mut units = Vec::with_capacity(params.frames + 2);
    units.push(toy_4x4_sps_unit());
    units.push(toy_4x4_pps_unit());
    for frame_idx in 0..params.frames {
        units.push(toy_4x4_slice_unit(frame_idx)?);
    }
    write_annex_b(&units)
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

fn toy_4x4_slice_unit(frame_idx: usize) -> Result<VvcNalUnit, String> {
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
        rbsp_payload: toy_4x4_slice_payload(picture_kind),
    })
}

fn toy_4x4_sps_payload() -> Vec<u8> {
    // TODO(vvc): Replace these observed VTM-compatible bit regions with named
    // SPS syntax fields from the VVC specification. This is intentionally a
    // bitstream generator, not an imported reference-code blob.
    let mut writer = VvcSyntaxWriter::new();
    writer.write_observed_region("sps_parameter_set_prefix", 0x000b_0200_8000_4244, 64);
    writer.write_observed_region("sps_profile_and_picture_region", 0xeed5_01f4_46e8_8468, 64);
    writer.write_observed_region("sps_tool_constraint_region", 0x8424_6136_28c5_4306, 64);
    writer.write_observed_region("sps_trailing_region", 0x80ab_8fe0_ac10_20, 56);
    debug_assert!(writer.is_byte_aligned());
    writer.into_bytes()
}

fn toy_4x4_pps_payload() -> Vec<u8> {
    // TODO(vvc): Replace these observed VTM-compatible bit regions with named
    // PPS syntax fields once the toy encoder owns the exact parameter-set syntax.
    let mut writer = VvcSyntaxWriter::new();
    writer.write_observed_region("pps_parameter_set_prefix", 0x0002_448a_4200_c7b2, 64);
    writer.write_observed_region("pps_picture_region", 0x1459_4594_5880, 48);
    debug_assert!(writer.is_byte_aligned());
    writer.into_bytes()
}

fn toy_4x4_slice_payload(picture_kind: Toy4x4PictureKind) -> Vec<u8> {
    // TODO(vvc): Split this into actual picture header, slice header, coding-tree,
    // CABAC, and rbsp_trailing_bits syntax. For now these named regions preserve
    // the minimal stream that VTM accepts for a black 4x4 YUV420p8 frame.
    let mut writer = VvcSyntaxWriter::new();
    writer.write_observed_region("slice_header_prefix", 0xc4, 8);
    match picture_kind {
        Toy4x4PictureKind::Idr => {
            writer.write_observed_region("idr_picture_order_region", 0x0070, 16);
        }
        Toy4x4PictureKind::Cra => {
            writer.write_observed_region("cra_picture_order_region", 0x0478, 16);
        }
    }
    writer.write_observed_region(
        "zero_residual_coding_tree_and_trailing_region",
        0x8062_f5b7_ebcb_1f80,
        64,
    );
    debug_assert!(writer.is_byte_aligned());
    writer.into_bytes()
}

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
        assert_eq!(bytes.len(), 74);
        let infos = parse_annex_b_nal_units(&bytes).unwrap();
        let types: Vec<u8> = infos.iter().map(|info| info.nal_unit_type).collect();
        assert_eq!(types, vec![15, 16, 8]);
        assert_eq!(infos[0].payload_len, 31);
        assert_eq!(infos[1].payload_len, 14);
        assert_eq!(infos[2].payload_len, 11);
    }

    #[test]
    fn parses_toy_black_4x4_two_frame_headers() {
        let bytes = toy_black_4x4_yuv420p8_annex_b(Toy4x4EncodeParams { frames: 2 }).unwrap();
        assert_eq!(bytes.len(), 91);
        let infos = parse_annex_b_nal_units(&bytes).unwrap();
        let types: Vec<u8> = infos.iter().map(|info| info.nal_unit_type).collect();
        assert_eq!(types, vec![15, 16, 8, 9]);
        assert_eq!(infos[3].offset, 78);
        assert_eq!(infos[3].payload_len, 11);
    }

    #[test]
    fn rejects_unsupported_toy_frame_count() {
        assert!(toy_black_4x4_yuv420p8_annex_b(Toy4x4EncodeParams { frames: 0 }).is_err());
        assert!(toy_black_4x4_yuv420p8_annex_b(Toy4x4EncodeParams { frames: 3 }).is_err());
    }
}
