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
}
