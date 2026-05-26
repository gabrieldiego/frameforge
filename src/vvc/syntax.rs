use crate::bitstream::{rbsp_trailing_bits, BitWriter};

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
