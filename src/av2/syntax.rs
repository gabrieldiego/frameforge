use crate::bitstream::BitWriter;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Av2SyntaxCode {
    Flag,
    Literal,
    Uvlc,
    Quniform,
    TrailingBits,
    ByteAlignZero,
    TileEntropyPayload,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Av2SyntaxField {
    pub name: &'static str,
    pub code: Av2SyntaxCode,
    pub bit_offset: usize,
    pub bit_count: usize,
}

#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct Av2SyntaxPayload {
    pub bytes: Vec<u8>,
    pub fields: Vec<Av2SyntaxField>,
}

#[derive(Debug, Default, Clone)]
pub struct Av2SyntaxWriter {
    writer: BitWriter,
    fields: Vec<Av2SyntaxField>,
    bit_offset: usize,
}

impl Av2SyntaxWriter {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn write_flag(&mut self, name: &'static str, value: bool) {
        self.push_field(name, Av2SyntaxCode::Flag, 1);
        self.writer.write_bool(value);
        self.bit_offset += 1;
    }

    pub fn write_literal(&mut self, name: &'static str, value: u64, bit_count: u8) {
        assert!(bit_count <= 64, "literal cannot write more than 64 bits");
        if bit_count < 64 {
            assert!(
                value < (1u64 << bit_count),
                "value does not fit in literal({bit_count})"
            );
        }
        self.push_field(name, Av2SyntaxCode::Literal, bit_count as usize);
        self.writer.write_bits(value, bit_count);
        self.bit_offset += bit_count as usize;
    }

    pub fn write_uvlc(&mut self, name: &'static str, value: u32) {
        assert!(value != u32::MAX, "uvlc cannot encode UINT32_MAX");
        let code_num = value as u64 + 1;
        let bit_count = 64 - code_num.leading_zeros() as u8;
        let leading_zero_bits = bit_count - 1;
        let total_bits = (leading_zero_bits * 2) + 1;
        self.push_field(name, Av2SyntaxCode::Uvlc, total_bits as usize);
        for _ in 0..leading_zero_bits {
            self.writer.write_bit(false);
        }
        self.writer.write_bits(code_num, bit_count);
        self.bit_offset += total_bits as usize;
    }

    pub fn write_quniform(&mut self, name: &'static str, n: u16, value: u16) {
        if n <= 1 {
            return;
        }
        assert!(value < n, "quniform value must be lower than n");
        let l = 16 - n.leading_zeros() as u8;
        let m = (1u16 << l) - n;
        let bit_count = if value < m { l - 1 } else { l };
        self.push_field(name, Av2SyntaxCode::Quniform, bit_count as usize);
        if value < m {
            self.writer.write_bits(value as u64, l - 1);
        } else {
            self.writer
                .write_bits((m + ((value - m) >> 1)) as u64, l - 1);
            self.writer.write_bit(((value - m) & 1) != 0);
        }
        self.bit_offset += bit_count as usize;
    }

    pub fn trailing_bits(&mut self) {
        let bit_count = if self.writer.is_byte_aligned() {
            8
        } else {
            8 - (self.bit_offset % 8)
        };
        self.push_field("trailing_bits", Av2SyntaxCode::TrailingBits, bit_count);
        if self.writer.is_byte_aligned() {
            self.writer.write_bits(0x80, 8);
        } else {
            self.writer.write_bit(true);
            self.writer.byte_align_zero();
        }
        self.bit_offset += bit_count;
    }

    pub fn byte_align_zero(&mut self, name: &'static str) {
        let remainder = self.bit_offset % 8;
        if remainder == 0 {
            return;
        }
        let bit_count = 8 - remainder;
        self.push_field(name, Av2SyntaxCode::ByteAlignZero, bit_count);
        self.writer.byte_align_zero();
        self.bit_offset += bit_count;
    }

    pub fn finish(self) -> Av2SyntaxPayload {
        Av2SyntaxPayload {
            bytes: self.writer.into_bytes(),
            fields: self.fields,
        }
    }

    fn push_field(&mut self, name: &'static str, code: Av2SyntaxCode, bit_count: usize) {
        self.fields.push(Av2SyntaxField {
            name,
            code,
            bit_offset: self.bit_offset,
            bit_count,
        });
    }
}
