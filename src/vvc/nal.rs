use crate::bitstream::insert_emulation_prevention_bytes;

use super::{VvcSyntaxRbsp, VvcSyntaxWriter};

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
