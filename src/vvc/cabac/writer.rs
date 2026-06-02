#[derive(Debug, Clone, Copy)]
pub(in crate::vvc) struct VvcCtxEvent {
    pub(in crate::vvc) lps: u16,
    pub(in crate::vvc) mps: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::vvc) struct VvcCabacDumpContextEvent {
    pub(in crate::vvc) ctx_id: u16,
    pub(in crate::vvc) bin: bool,
    pub(in crate::vvc) range: u16,
    pub(in crate::vvc) lps: u16,
    pub(in crate::vvc) mps: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::vvc) struct VvcCabacDumpBinEngineEvent {
    pub(in crate::vvc) kind: u8,
    pub(in crate::vvc) bin: bool,
    pub(in crate::vvc) lps: u16,
    pub(in crate::vvc) mps: bool,
    pub(in crate::vvc) low_in: u32,
    pub(in crate::vvc) range_in: u16,
    pub(in crate::vvc) bits_left_in: u8,
    pub(in crate::vvc) low_out: u32,
    pub(in crate::vvc) range_out: u16,
    pub(in crate::vvc) bits_left_out: u8,
    pub(in crate::vvc) write_out: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::vvc) struct VvcCabacDumpSymbol {
    pub(in crate::vvc) kind: u8,
    pub(in crate::vvc) data: u32,
}

impl VvcCabacDumpSymbol {
    const BIN_EP: u8 = 0;
    const BIN_TRM: u8 = 1;
    const BIN_CTX: u8 = 2;
    const BIN_CTX_DIRECT: u8 = 3;
    const BINS_EP: u8 = 4;

    fn bin_ep(bin: bool) -> Self {
        Self {
            kind: Self::BIN_EP,
            data: u32::from(bin),
        }
    }

    fn bin_trm(bin: bool) -> Self {
        Self {
            kind: Self::BIN_TRM,
            data: u32::from(bin),
        }
    }

    pub(in crate::vvc) fn bin_ctx(bin: bool, ctx_id: u16) -> Self {
        Self {
            kind: Self::BIN_CTX,
            data: u32::from(bin) | (u32::from(ctx_id) << 8),
        }
    }

    fn bin_ctx_direct(bin: bool, event: VvcCtxEvent) -> Self {
        Self {
            kind: Self::BIN_CTX_DIRECT,
            data: u32::from(bin) | (u32::from(event.lps) << 16) | (u32::from(event.mps) << 25),
        }
    }

    fn bins_ep(bins: u32, num_bins: u32) -> Self {
        Self {
            kind: Self::BINS_EP,
            data: (bins << 6) | num_bins,
        }
    }
}

#[derive(Debug, Clone)]
pub(in crate::vvc) struct VvcCabacEncoder {
    pub(in crate::vvc) bits: Vec<bool>,
    pub(in crate::vvc) dump_symbols: Vec<VvcCabacDumpSymbol>,
    pub(in crate::vvc) semantic_symbols: Vec<VvcCabacDumpSymbol>,
    pub(in crate::vvc) context_events: Vec<VvcCabacDumpContextEvent>,
    pub(in crate::vvc) context_bin_count: usize,
    pub(in crate::vvc) bin_engine_events: Vec<VvcCabacDumpBinEngineEvent>,
    pub(in crate::vvc) low: u32,
    pub(in crate::vvc) range: u32,
    pub(in crate::vvc) buffered_byte: u32,
    pub(in crate::vvc) num_buffered_bytes: u32,
    pub(in crate::vvc) bits_left: i32,
}

impl VvcCabacEncoder {
    pub(in crate::vvc) fn new() -> Self {
        Self {
            bits: Vec::new(),
            dump_symbols: Vec::new(),
            semantic_symbols: Vec::new(),
            context_events: Vec::new(),
            context_bin_count: 0,
            bin_engine_events: Vec::new(),
            low: 0,
            range: 0,
            buffered_byte: 0,
            num_buffered_bytes: 0,
            bits_left: 0,
        }
    }

    pub(in crate::vvc) fn start(&mut self) {
        self.low = 0;
        self.range = 510;
        self.buffered_byte = 0xff;
        self.num_buffered_bytes = 0;
        self.bits_left = 23;
    }

    pub(in crate::vvc) fn encode_bin(&mut self, bin: bool, event: VvcCtxEvent) {
        self.dump_symbols
            .push(VvcCabacDumpSymbol::bin_ctx_direct(bin, event));
        let low_in = self.low;
        let range_in = self.range as u16;
        let bits_left_in = self.bits_left as u8;
        let lps = event.lps as u32;
        self.range -= lps;
        if bin != event.mps {
            let num_bits = renorm_bits(lps);
            self.bits_left -= num_bits as i32;
            self.low += self.range;
            self.low <<= num_bits;
            self.range = lps << num_bits;
        } else if self.range < 256 {
            // VVC BinProbModel_Std::getRenormBitsRange() is fixed to 1 for
            // MPS renormalization. LPS renormalization still uses the table
            // equivalent implemented by renorm_bits().
            let num_bits = 1;
            self.bits_left -= num_bits;
            self.low <<= num_bits;
            self.range <<= num_bits;
        }
        let write_out = self.bits_left < 12;
        self.bin_engine_events.push(VvcCabacDumpBinEngineEvent {
            kind: VvcCabacDumpSymbol::BIN_CTX,
            bin,
            lps: event.lps,
            mps: event.mps,
            low_in,
            range_in,
            bits_left_in,
            low_out: self.low,
            range_out: self.range as u16,
            bits_left_out: self.bits_left as u8,
            write_out,
        });
        if write_out {
            self.write_out();
        }
    }

    pub(in crate::vvc) fn encode_bin_ep(&mut self, bin: bool) {
        self.dump_symbols.push(VvcCabacDumpSymbol::bin_ep(bin));
        self.semantic_symbols.push(VvcCabacDumpSymbol::bin_ep(bin));
        let low_in = self.low;
        let range_in = self.range as u16;
        let bits_left_in = self.bits_left as u8;
        self.low <<= 1;
        if bin {
            self.low += self.range;
        }
        self.bits_left -= 1;
        self.bin_engine_events.push(VvcCabacDumpBinEngineEvent {
            kind: VvcCabacDumpSymbol::BIN_EP,
            bin,
            lps: 0,
            mps: false,
            low_in,
            range_in,
            bits_left_in,
            low_out: self.low,
            range_out: self.range as u16,
            bits_left_out: self.bits_left as u8,
            write_out: self.bits_left < 12,
        });
        if self.bits_left < 12 {
            self.write_out();
        }
    }

    pub(in crate::vvc) fn encode_bins_ep(&mut self, bins: u32, num_bins: u32) {
        self.dump_symbols
            .push(VvcCabacDumpSymbol::bins_ep(bins, num_bins));
        self.semantic_symbols
            .push(VvcCabacDumpSymbol::bins_ep(bins, num_bins));
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

    pub(in crate::vvc) fn encode_rem_abs_ep(&mut self, value: u32, rice_param: u32) {
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

    pub(in crate::vvc) fn encode_bin_trm(&mut self, bin: bool) {
        self.dump_symbols.push(VvcCabacDumpSymbol::bin_trm(bin));
        self.semantic_symbols.push(VvcCabacDumpSymbol::bin_trm(bin));
        let low_in = self.low;
        let range_in = self.range as u16;
        let bits_left_in = self.bits_left as u8;
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
        let write_out = self.bits_left < 12;
        self.bin_engine_events.push(VvcCabacDumpBinEngineEvent {
            kind: VvcCabacDumpSymbol::BIN_TRM,
            bin,
            lps: 0,
            mps: false,
            low_in,
            range_in,
            bits_left_in,
            low_out: self.low,
            range_out: self.range as u16,
            bits_left_out: self.bits_left as u8,
            write_out,
        });
        if write_out {
            self.write_out();
        }
    }

    pub(in crate::vvc) fn finish(mut self) -> Vec<bool> {
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
