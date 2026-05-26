#[derive(Debug, Clone, Copy)]
pub(super) struct VvcCtxEvent {
    pub(super) lps: u16,
    pub(super) mps: bool,
}

pub(super) const VVC_CTX_EVENTS: [VvcCtxEvent; 19] = [
    VvcCtxEvent {
        lps: 146,
        mps: false,
    },
    VvcCtxEvent { lps: 81, mps: true },
    VvcCtxEvent {
        lps: 128,
        mps: true,
    },
    VvcCtxEvent { lps: 52, mps: true },
    VvcCtxEvent {
        lps: 160,
        mps: true,
    },
    VvcCtxEvent {
        lps: 129,
        mps: true,
    },
    VvcCtxEvent {
        lps: 24,
        mps: false,
    },
    VvcCtxEvent {
        lps: 58,
        mps: false,
    },
    VvcCtxEvent {
        lps: 29,
        mps: false,
    },
    VvcCtxEvent {
        lps: 172,
        mps: true,
    },
    VvcCtxEvent {
        lps: 107,
        mps: false,
    },
    VvcCtxEvent {
        lps: 136,
        mps: false,
    },
    VvcCtxEvent {
        lps: 128,
        mps: true,
    },
    VvcCtxEvent {
        lps: 125,
        mps: false,
    },
    VvcCtxEvent {
        lps: 184,
        mps: false,
    },
    VvcCtxEvent {
        lps: 112,
        mps: false,
    },
    VvcCtxEvent {
        lps: 28,
        mps: false,
    },
    VvcCtxEvent {
        lps: 67,
        mps: false,
    },
    VvcCtxEvent {
        lps: 26,
        mps: false,
    },
];

#[derive(Debug, Clone)]
pub(super) struct VvcCabacEncoder {
    pub(super) bits: Vec<bool>,
    pub(super) low: u32,
    pub(super) range: u32,
    pub(super) buffered_byte: u32,
    pub(super) num_buffered_bytes: u32,
    pub(super) bits_left: i32,
}

impl VvcCabacEncoder {
    pub(super) fn new() -> Self {
        Self {
            bits: Vec::new(),
            low: 0,
            range: 0,
            buffered_byte: 0,
            num_buffered_bytes: 0,
            bits_left: 0,
        }
    }

    pub(super) fn start(&mut self) {
        self.low = 0;
        self.range = 510;
        self.buffered_byte = 0xff;
        self.num_buffered_bytes = 0;
        self.bits_left = 23;
    }

    pub(super) fn encode_ctx_bins(&mut self, events: &[VvcCtxEvent], bins: &[bool]) {
        debug_assert_eq!(events.len(), bins.len());
        for (event, bin) in events.iter().zip(bins) {
            self.encode_bin(*bin, *event);
        }
    }

    pub(super) fn encode_bin(&mut self, bin: bool, event: VvcCtxEvent) {
        let lps = event.lps as u32;
        self.range -= lps;
        if bin != event.mps {
            let num_bits = renorm_bits(lps);
            self.bits_left -= num_bits as i32;
            self.low += self.range;
            self.low <<= num_bits;
            self.range = lps << num_bits;
            if self.bits_left < 12 {
                self.write_out();
            }
        } else if self.range < 256 {
            // VVC BinProbModel_Std::getRenormBitsRange() is fixed to 1 for
            // MPS renormalization. LPS renormalization still uses the table
            // equivalent implemented by renorm_bits().
            let num_bits = 1;
            self.bits_left -= num_bits;
            self.low <<= num_bits;
            self.range <<= num_bits;
            if self.bits_left < 12 {
                self.write_out();
            }
        }
    }

    pub(super) fn encode_bin_ep(&mut self, bin: bool) {
        self.low <<= 1;
        if bin {
            self.low += self.range;
        }
        self.bits_left -= 1;
        if self.bits_left < 12 {
            self.write_out();
        }
    }

    pub(super) fn encode_bins_ep(&mut self, bins: u32, num_bins: u32) {
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

    pub(super) fn encode_rem_abs_ep(&mut self, value: u32, rice_param: u32) {
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

    pub(super) fn encode_bin_trm(&mut self, bin: bool) {
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
        if self.bits_left < 12 {
            self.write_out();
        }
    }

    pub(super) fn finish(mut self) -> Vec<bool> {
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
