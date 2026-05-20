#[derive(Debug, Default, Clone)]
pub struct BitWriter {
    bytes: Vec<u8>,
    current_byte: u8,
    bits_filled: u8,
}

impl BitWriter {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn write_bit(&mut self, bit: bool) {
        self.current_byte <<= 1;
        if bit {
            self.current_byte |= 1;
        }
        self.bits_filled += 1;

        if self.bits_filled == 8 {
            self.bytes.push(self.current_byte);
            self.current_byte = 0;
            self.bits_filled = 0;
        }
    }

    pub fn write_bool(&mut self, value: bool) {
        self.write_bit(value);
    }

    pub fn write_bits(&mut self, value: u64, bit_count: u8) {
        assert!(bit_count <= 64, "cannot write more than 64 bits at once");
        for bit_index in (0..bit_count).rev() {
            self.write_bit(((value >> bit_index) & 1) != 0);
        }
    }

    pub fn byte_align_zero(&mut self) {
        if self.bits_filled == 0 {
            return;
        }
        while self.bits_filled != 0 {
            self.write_bit(false);
        }
    }

    pub fn into_bytes(mut self) -> Vec<u8> {
        self.byte_align_zero();
        self.bytes
    }

    pub fn is_byte_aligned(&self) -> bool {
        self.bits_filled == 0
    }
}

pub fn rbsp_trailing_bits(writer: &mut BitWriter) {
    writer.write_bit(true);
    writer.byte_align_zero();
}

pub fn insert_emulation_prevention_bytes(rbsp: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(rbsp.len());
    let mut zero_count = 0usize;

    for &byte in rbsp {
        if zero_count >= 2 && byte <= 0x03 {
            out.push(0x03);
            zero_count = 0;
        }

        out.push(byte);
        if byte == 0 {
            zero_count += 1;
        } else {
            zero_count = 0;
        }
    }

    out
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NalUnitKind {
    /// Placeholder for a coded picture payload. Exact VVC NAL unit typing is TODO.
    CodedPicture,
    /// Placeholder parameter set category. Exact VPS/SPS/PPS syntax is TODO.
    ParameterSet,
    /// Non-codec project metadata payload, not a conforming video bitstream.
    FrameForgePlaceholder,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NalUnit {
    pub kind: NalUnitKind,
    pub temporal_id: u8,
    pub payload: Vec<u8>,
}

#[derive(Debug, Default)]
pub struct AnnexBWriter {
    units: Vec<NalUnit>,
}

impl AnnexBWriter {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn push(&mut self, unit: NalUnit) {
        self.units.push(unit);
    }

    pub fn into_bytes(self) -> Vec<u8> {
        let mut out = Vec::new();
        for unit in self.units {
            out.extend_from_slice(&[0x00, 0x00, 0x00, 0x01]);
            out.extend_from_slice(&placeholder_nal_header(unit.kind, unit.temporal_id));
            out.extend_from_slice(&insert_emulation_prevention_bytes(&unit.payload));
        }
        out
    }
}

fn placeholder_nal_header(kind: NalUnitKind, temporal_id: u8) -> [u8; 2] {
    // TODO(vvc): Replace with exact VVC forbidden_zero_bit, nuh_layer_id,
    // nal_unit_type, and nuh_temporal_id_plus1 packing.
    let kind_code = match kind {
        NalUnitKind::CodedPicture => 1,
        NalUnitKind::ParameterSet => 2,
        NalUnitKind::FrameForgePlaceholder => 63,
    };
    [kind_code, temporal_id & 0x07]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bit_packing_msb_first() {
        let mut writer = BitWriter::new();
        writer.write_bits(0b101, 3);
        writer.write_bits(0b10, 2);
        assert_eq!(writer.into_bytes(), vec![0b1011_0000]);
    }

    #[test]
    fn byte_alignment_writes_zero_padding() {
        let mut writer = BitWriter::new();
        writer.write_bits(0b1111, 4);
        writer.byte_align_zero();
        assert!(writer.is_byte_aligned());
        assert_eq!(writer.into_bytes(), vec![0b1111_0000]);
    }

    #[test]
    fn rbsp_trailing_bits_adds_stop_bit_and_padding() {
        let mut writer = BitWriter::new();
        writer.write_bits(0b1010, 4);
        rbsp_trailing_bits(&mut writer);
        assert_eq!(writer.into_bytes(), vec![0b1010_1000]);
    }

    #[test]
    fn emulation_prevention_inserts_after_two_zeroes() {
        let rbsp = [0x00, 0x00, 0x01, 0x11, 0x00, 0x00, 0x03];
        assert_eq!(
            insert_emulation_prevention_bytes(&rbsp),
            vec![0x00, 0x00, 0x03, 0x01, 0x11, 0x00, 0x00, 0x03, 0x03]
        );
    }
}
