const CDF_PROB_TOP: u32 = 1 << 15;
const EC_PROB_SHIFT: u32 = 7;

const PROB_INC: [[i32; 16]; 15] = [
    [8, 0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
    [10, 5, 0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
    [12, 8, 4, 0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
    [12, 9, 6, 3, 0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
    [13, 10, 8, 5, 2, 0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
    [13, 11, 9, 6, 4, 2, 0, -1, -1, -1, -1, -1, -1, -1, -1, -1],
    [14, 12, 10, 8, 6, 4, 2, 0, -1, -1, -1, -1, -1, -1, -1, -1],
    [14, 12, 10, 8, 7, 5, 3, 1, 0, -1, -1, -1, -1, -1, -1, -1],
    [14, 12, 11, 9, 8, 6, 4, 3, 1, 0, -1, -1, -1, -1, -1, -1],
    [14, 13, 11, 10, 8, 7, 5, 4, 2, 1, 0, -1, -1, -1, -1, -1],
    [14, 13, 12, 10, 9, 8, 6, 5, 4, 2, 1, 0, -1, -1, -1, -1],
    [14, 13, 12, 11, 9, 8, 7, 6, 4, 3, 2, 1, 0, -1, -1, -1],
    [14, 13, 12, 11, 10, 9, 8, 6, 5, 4, 3, 2, 1, 0, -1, -1],
    [14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0, -1],
    [15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0],
];

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Av2EntropyCode {
    Literal,
    Symbol,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Av2EntropyField {
    pub name: &'static str,
    pub code: Av2EntropyCode,
    pub symbol_offset: usize,
    pub bit_count: usize,
    pub symbol: Option<usize>,
    pub literal_value: Option<u32>,
    pub fl: Option<u32>,
    pub fh: Option<u32>,
    pub fl_inc: Option<i32>,
    pub fh_inc: Option<i32>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Av2EntropyPayload {
    pub bytes: Vec<u8>,
    pub fields: Vec<Av2EntropyField>,
    pub symbol_bits: usize,
}

#[derive(Debug, Clone)]
pub struct Av2EntropyWriter {
    low: u64,
    rng: u32,
    cnt: i32,
    precarry: Vec<u16>,
    fields: Vec<Av2EntropyField>,
    symbol_bits: usize,
}

impl Av2EntropyWriter {
    pub fn new() -> Self {
        Self {
            low: 0,
            rng: 0x8000,
            cnt: -9,
            precarry: Vec::new(),
            fields: Vec::new(),
            symbol_bits: 0,
        }
    }

    pub fn write_literal(&mut self, name: &'static str, mut value: u32, mut bits: u8) {
        assert!(
            bits <= 32,
            "AV2 literal helper currently supports up to 32 bits"
        );
        // AV2 v1.0.0 Section 4.11.3: L(n) consumes n literal bits through the
        // arithmetic decoder. Encoder-side this mirrors AVM avm_write_literal().
        self.fields.push(Av2EntropyField {
            name,
            code: Av2EntropyCode::Literal,
            symbol_offset: self.symbol_bits,
            bit_count: bits as usize,
            symbol: None,
            literal_value: Some(value),
            fl: None,
            fh: None,
            fl_inc: None,
            fh_inc: None,
        });
        self.symbol_bits += bits as usize;
        while bits > 0 {
            let n = bits.min(8);
            let shift = bits - n;
            let chunk = (value >> shift) & ((1u32 << n) - 1);
            self.encode_literal_bypass(chunk, n);
            bits -= n;
            value &= (1u32 << bits) - 1;
        }
    }

    pub fn write_symbol(
        &mut self,
        name: &'static str,
        symbol: usize,
        cdf: &mut [u16],
        nsymbs: usize,
        update_cdf: bool,
    ) {
        assert!((2..=16).contains(&nsymbs), "AV2 CDF symbols must be 2..=16");
        assert!(symbol < nsymbs, "symbol out of CDF range");
        assert!(
            cdf.len() >= nsymbs + 4,
            "CDF must include adaptation entries"
        );
        // AV2 v1.0.0 Sections 4.11.2 and 8.3: S() reads a symbol using the
        // active CDF selected by the syntax process. Encoder-side this mirrors
        // AVM avm_write_symbol().
        let fl = if symbol > 0 {
            cdf[symbol - 1] as u32
        } else {
            CDF_PROB_TOP
        };
        let fh = cdf[symbol] as u32;
        let fl_inc = if fl < CDF_PROB_TOP {
            PROB_INC[nsymbs - 2][symbol.saturating_sub(1)]
        } else {
            0
        };
        let fh_inc = PROB_INC[nsymbs - 2][symbol];
        self.fields.push(Av2EntropyField {
            name,
            code: Av2EntropyCode::Symbol,
            symbol_offset: self.symbol_bits,
            bit_count: 1,
            symbol: Some(symbol),
            literal_value: None,
            fl: Some(fl),
            fh: Some(fh),
            fl_inc: Some(fl_inc),
            fh_inc: Some(fh_inc),
        });
        self.symbol_bits += 1;
        self.encode_cdf_q15(symbol, cdf, nsymbs);
        if update_cdf {
            update_cdf_counts(cdf, symbol, nsymbs);
        }
    }

    pub fn finish(mut self) -> Av2EntropyPayload {
        let mut e = ((self.low + 0x3fff) & !0x3fff) | 0x4000;
        let mut c = self.cnt;
        let mut s = c + 10;
        if s > 0 {
            let mut n = mask(c + 16);
            while s > 0 {
                self.precarry.push((e >> (c + 16)) as u16);
                e &= n;
                s -= 8;
                c -= 8;
                n >>= 8;
            }
        }

        let mut out = vec![0; self.precarry.len()];
        let mut carry = 0u16;
        for index in (0..self.precarry.len()).rev() {
            carry += self.precarry[index];
            out[index] = carry as u8;
            carry >>= 8;
        }

        Av2EntropyPayload {
            bytes: out,
            fields: self.fields,
            symbol_bits: self.symbol_bits,
        }
    }

    fn encode_literal_bypass(&mut self, value: u32, bits: u8) {
        assert!(
            bits <= 16,
            "AV2 bypass literal chunks are limited to 16 bits"
        );
        let low = (self.low << bits) + (self.rng as u64 * value as u64);
        self.normalize(low, self.rng, bits as i32);
    }

    fn encode_cdf_q15(&mut self, symbol: usize, icdf: &[u16], nsymbs: usize) {
        assert_eq!(
            icdf[nsymbs - 1],
            0,
            "last AV2 inverse CDF entry must be zero"
        );
        let fl = if symbol > 0 {
            icdf[symbol - 1] as u32
        } else {
            CDF_PROB_TOP
        };
        let fh = icdf[symbol] as u32;
        self.encode_q15(fl, fh, symbol, nsymbs);
    }

    fn encode_q15(&mut self, fl: u32, fh: u32, symbol: usize, nsymbs: usize) {
        assert!(fh <= fl, "AV2 inverse CDF must be monotonic");
        assert!(fl <= CDF_PROB_TOP, "AV2 inverse CDF exceeds Q15 top");
        let mut low = self.low;
        let mut rng = self.rng;
        if fl < CDF_PROB_TOP {
            let u = prob_scale(fl, rng, symbol.saturating_sub(1), nsymbs);
            let v = prob_scale(fh, rng, symbol, nsymbs);
            low += (rng - u) as u64;
            rng = u - v;
        } else {
            let v = prob_scale(fh, rng, symbol, nsymbs);
            rng -= v;
        }
        self.normalize(low, rng, 0);
    }

    fn normalize(&mut self, mut low: u64, rng: u32, bypass_bits: i32) {
        assert!(rng <= 65535, "AV2 range must fit 16 bits before normalize");
        let mut c = self.cnt;
        let d = if bypass_bits > 0 {
            c += bypass_bits;
            0
        } else {
            16 - ilog_nz(rng)
        };
        let mut s = c + d;
        if s >= 0 {
            c += 16;
            let mut m = mask(c);
            if s >= 8 {
                self.precarry.push((low >> c) as u16);
                low &= m;
                c -= 8;
                m >>= 8;
            }
            self.precarry.push((low >> c) as u16);
            s = c + d - 24;
            low &= m;
        }
        self.low = low << d;
        self.rng = rng << d;
        self.cnt = s;
    }
}

impl Default for Av2EntropyWriter {
    fn default() -> Self {
        Self::new()
    }
}

pub fn av2_empty_tile_entropy_payload() -> Av2EntropyPayload {
    // AV2 v1.0.0 Section 5.20.1 calls init_symbol(tileSize) before
    // decode_tile() and exit_symbol() afterward. This is the smallest possible
    // generated payload: no syntax decisions are emitted yet, but the range
    // writer still emits the exit-symbol terminating bit pattern.
    Av2EntropyWriter::new().finish()
}

pub fn av2_uniform_icdf(nsymbs: usize) -> Vec<u16> {
    assert!((2..=16).contains(&nsymbs), "AV2 CDF symbols must be 2..=16");
    let mut cdf = vec![0; nsymbs + 4];
    for index in 1..nsymbs {
        let cumulative = ((CDF_PROB_TOP as usize * index) / nsymbs) as u32;
        cdf[index - 1] = (CDF_PROB_TOP - cumulative) as u16;
    }
    cdf[nsymbs - 1] = 0;
    cdf
}

fn update_cdf_counts(cdf: &mut [u16], symbol: usize, nsymbs: usize) {
    let time_interval = if cdf[nsymbs] > 31 {
        2
    } else if cdf[nsymbs] > 15 {
        1
    } else {
        0
    };
    let rate = 2 + cdf[nsymbs + 1 + time_interval] as u32;
    let mut tmp = CDF_PROB_TOP as i32;
    for (index, value) in cdf.iter_mut().take(nsymbs - 1).enumerate() {
        if index == symbol {
            tmp = 0;
        }
        let current = *value as i32;
        if tmp < current {
            *value -= ((current - tmp) >> rate) as u16;
        } else {
            *value += ((tmp - current) >> rate) as u16;
        }
    }
    if cdf[nsymbs] < 32 {
        cdf[nsymbs] += 1;
    }
}

fn prob_scale(p: u32, rng: u32, symbol: usize, nsymbs: usize) -> u32 {
    let rr = rng >> 8;
    let mut pp = ((p >> EC_PROB_SHIFT) << 4) as i32;
    pp += PROB_INC[nsymbs - 2][symbol];
    (((rr as i32 * pp) >> 7) as u32) << 3
}

fn ilog_nz(value: u32) -> i32 {
    debug_assert!(value != 0);
    (u32::BITS - value.leading_zeros()) as i32
}

fn mask(bits: i32) -> u64 {
    if bits <= 0 {
        0
    } else if bits >= 64 {
        u64::MAX
    } else {
        (1u64 << bits) - 1
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn av2_entropy_writer_finalizes_empty_tile_payload() {
        let payload = av2_empty_tile_entropy_payload();

        assert_eq!(payload.bytes, vec![0x80]);
        assert_eq!(payload.symbol_bits, 0);
        assert!(payload.fields.is_empty());
    }

    #[test]
    fn av2_entropy_writer_encodes_literals_through_range_coder() {
        let mut writer = Av2EntropyWriter::new();
        writer.write_literal("tile.test_literal", 0b1010_0101, 8);
        let payload = writer.finish();

        assert!(!payload.bytes.is_empty());
        assert_eq!(payload.symbol_bits, 8);
        assert_eq!(payload.fields[0].name, "tile.test_literal");
        assert_eq!(payload.fields[0].code, Av2EntropyCode::Literal);
    }

    #[test]
    fn av2_entropy_writer_encodes_cdf_symbols_and_updates_counts() {
        let mut cdf = av2_uniform_icdf(2);
        let mut writer = Av2EntropyWriter::new();
        writer.write_symbol("tile.test_symbol", 0, &mut cdf, 2, true);
        let payload = writer.finish();

        assert!(!payload.bytes.is_empty());
        assert_eq!(payload.symbol_bits, 1);
        assert_eq!(payload.fields[0].code, Av2EntropyCode::Symbol);
        assert_eq!(cdf[2], 1);
    }
}
