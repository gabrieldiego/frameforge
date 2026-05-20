//! First-target VVC/H.266 placeholders.
//!
//! This module intentionally does not implement VVC syntax yet. Exact NAL unit
//! types, parameter sets, slice headers, CTU syntax, CABAC, transform/quant,
//! and reconstruction semantics must be added from the specification or another
//! clean-room source before FrameForge can emit a decodable VVC bitstream.

use crate::bitstream::insert_emulation_prevention_bytes;
use crate::bitstream::{rbsp_trailing_bits, BitWriter};

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

    let mut units = Vec::with_capacity(params.frames * 3);
    for frame_idx in 0..params.frames {
        units.push(toy_4x4_sps_unit());
        units.push(toy_4x4_pps_unit());
        units.push(toy_4x4_slice_unit(frame_idx)?);
    }
    write_annex_b(&units)
}

fn toy_4x4_sps_unit() -> VvcNalUnit {
    VvcNalUnit {
        nal_unit_type: VvcNalUnitType::Sps,
        layer_id: 0,
        temporal_id: 0,
        rbsp_payload: collect_payload(31, toy_4x4_sps_payload_byte),
    }
}

fn toy_4x4_pps_unit() -> VvcNalUnit {
    VvcNalUnit {
        nal_unit_type: VvcNalUnitType::Pps,
        layer_id: 0,
        temporal_id: 0,
        rbsp_payload: collect_payload(14, toy_4x4_pps_payload_byte),
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
        rbsp_payload: collect_payload(11, |idx| toy_4x4_slice_payload_byte(idx, picture_kind)),
    })
}

fn collect_payload(len: usize, mut byte_at: impl FnMut(usize) -> u8) -> Vec<u8> {
    (0..len).map(&mut byte_at).collect()
}

fn toy_4x4_sps_payload_byte(index: usize) -> u8 {
    match index {
        0 => 0x00,
        1 => 0x0b,
        2 => 0x02,
        3 => 0x00,
        4 => 0x80,
        5 => 0x00,
        6 => 0x42,
        7 => 0x44,
        8 => 0xee,
        9 => 0xd5,
        10 => 0x01,
        11 => 0xf4,
        12 => 0x46,
        13 => 0xe8,
        14 => 0x84,
        15 => 0x68,
        16 => 0x84,
        17 => 0x24,
        18 => 0x61,
        19 => 0x36,
        20 => 0x28,
        21 => 0xc5,
        22 => 0x43,
        23 => 0x06,
        24 => 0x80,
        25 => 0xab,
        26 => 0x8f,
        27 => 0xe0,
        28 => 0xac,
        29 => 0x10,
        30 => 0x20,
        _ => 0x00,
    }
}

fn toy_4x4_pps_payload_byte(index: usize) -> u8 {
    match index {
        0 => 0x00,
        1 => 0x02,
        2 => 0x44,
        3 => 0x8a,
        4 => 0x42,
        5 => 0x00,
        6 => 0xc7,
        7 => 0xb2,
        8 => 0x14,
        9 => 0x59,
        10 => 0x45,
        11 => 0x94,
        12 => 0x58,
        13 => 0x80,
        _ => 0x00,
    }
}

fn toy_4x4_slice_payload_byte(index: usize, picture_kind: Toy4x4PictureKind) -> u8 {
    match index {
        0 => 0xc4,
        1 => match picture_kind {
            Toy4x4PictureKind::Idr => 0x00,
            Toy4x4PictureKind::Cra => 0x04,
        },
        2 => match picture_kind {
            Toy4x4PictureKind::Idr => 0x70,
            Toy4x4PictureKind::Cra => 0x78,
        },
        3 => 0x80,
        4 => 0x62,
        5 => 0xf5,
        6 => 0xb7,
        7 => 0xeb,
        8 => 0xcb,
        9 => 0x1f,
        10 => 0x80,
        _ => 0x00,
    }
}

fn placeholder_rbsp() -> Vec<u8> {
    // TODO(vvc): Replace this rbsp_trailing_bits-only payload with real VPS,
    // SPS, PPS, and slice RBSP syntax from a clean-room implementation.
    let mut writer = BitWriter::new();
    rbsp_trailing_bits(&mut writer);
    writer.into_bytes()
}

pub fn nal_unit_header_bytes(unit: &VvcNalUnit) -> Result<[u8; 2], String> {
    if unit.layer_id > 55 {
        return Err("VVC nuh_layer_id must be in the range 0..=55".to_string());
    }
    if unit.temporal_id > 6 {
        return Err("VVC temporal_id must be in the range 0..=6".to_string());
    }

    let word = ((unit.layer_id as u16) << 8)
        | ((unit.nal_unit_type as u16) << 3)
        | ((unit.temporal_id as u16) + 1);
    Ok(word.to_be_bytes())
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
        assert_eq!(bytes.len(), 148);
        let infos = parse_annex_b_nal_units(&bytes).unwrap();
        let types: Vec<u8> = infos.iter().map(|info| info.nal_unit_type).collect();
        assert_eq!(types, vec![15, 16, 8, 15, 16, 9]);
        assert_eq!(infos[3].offset, 78);
        assert_eq!(infos[5].payload_len, 11);
    }

    #[test]
    fn rejects_unsupported_toy_frame_count() {
        assert!(toy_black_4x4_yuv420p8_annex_b(Toy4x4EncodeParams { frames: 0 }).is_err());
        assert!(toy_black_4x4_yuv420p8_annex_b(Toy4x4EncodeParams { frames: 3 }).is_err());
    }
}
