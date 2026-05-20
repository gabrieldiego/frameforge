//! First-target VVC/H.266 placeholders.
//!
//! This module intentionally does not implement VVC syntax yet. Exact NAL unit
//! types, parameter sets, slice headers, CTU syntax, CABAC, transform/quant,
//! and reconstruction semantics must be added from the specification or another
//! clean-room source before FrameForge can emit a decodable VVC bitstream.

use crate::bitstream::insert_emulation_prevention_bytes;

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
    fn rejects_invalid_layer_id() {
        let mut unit = VvcNalUnit::eos();
        unit.layer_id = 56;
        assert!(nal_unit_header_bytes(&unit).is_err());
    }
}
