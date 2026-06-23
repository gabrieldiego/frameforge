use super::{VvcSampledFrame, VVC_CTU_SIZE};

const VVC_IBC_CU_SIZE: usize = 8;
const VVC_IBC_CUS_PER_CTU: usize =
    (VVC_CTU_SIZE / VVC_IBC_CU_SIZE) * (VVC_CTU_SIZE / VVC_IBC_CU_SIZE);
const VVC_IBC_HASH_OFFSET: u32 = 0x811c_9dc5;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct VvcIbcCuDecision {
    pub(super) origin_x: usize,
    pub(super) origin_y: usize,
    pub(super) ref_origin_x: usize,
    pub(super) ref_origin_y: usize,
    pub(super) bv_x: i16,
    pub(super) bv_y: i16,
    pub(super) mvd_x: i16,
    pub(super) mvd_y: i16,
    pub(super) pred_mode_ibc_ctx: u8,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct VvcIbcHashEntry {
    hash: u32,
    origin_x: usize,
    origin_y: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct VvcIbcBv {
    x: i16,
    y: i16,
}

#[derive(Debug, Clone)]
pub(super) struct VvcIbcHashSearch {
    entries: Vec<VvcIbcHashEntry>,
    ibc_mode_by_cu: [bool; VVC_IBC_CUS_PER_CTU],
    bv_by_cu: [VvcIbcBv; VVC_IBC_CUS_PER_CTU],
    hmvp: Vec<VvcIbcBv>,
}

impl VvcIbcHashSearch {
    pub(super) fn new() -> Self {
        Self {
            entries: Vec::with_capacity(VVC_IBC_CUS_PER_CTU),
            ibc_mode_by_cu: [false; VVC_IBC_CUS_PER_CTU],
            bv_by_cu: [VvcIbcBv { x: 0, y: 0 }; VVC_IBC_CUS_PER_CTU],
            hmvp: Vec::with_capacity(5),
        }
    }

    pub(super) fn decide_8x8(
        &self,
        frame: &VvcSampledFrame,
        origin_x: usize,
        origin_y: usize,
    ) -> Option<VvcIbcCuDecision> {
        if !vvc_ibc_full_8x8_is_visible(frame, origin_x, origin_y) {
            return None;
        }

        let hash = vvc_ibc_hash_8x8(frame, origin_x, origin_y);
        // H.266 8.6.2 allows only already-coded IBC predictors. Keep this
        // first hardware-oriented subset to three local exact-hash candidates
        // so the RTL can resolve a CU as soon as its TU samples arrive instead
        // of synthesizing a 64-way CTU hash search: A1, then B1, then B0.
        let reference = self.local_hash_candidate(origin_x, origin_y, hash)?;
        let predictor = self.bvp_for(origin_x, origin_y);
        let bv = VvcIbcBv {
            x: ((reference.origin_x as i16 - origin_x as i16) << 4),
            y: ((reference.origin_y as i16 - origin_y as i16) << 4),
        };
        let bvd = VvcIbcBv {
            x: bv.x - predictor.x,
            y: bv.y - predictor.y,
        };

        if (bvd.x & 15) != 0 || (bvd.y & 15) != 0 {
            return None;
        }
        let mvd = VvcIbcBv {
            x: bvd.x >> 4,
            y: bvd.y >> 4,
        };

        // H.266 7.3.11.8 codes lMvd before the IBC AMVR scaling specified by
        // H.266 Table 16. Our 8x8 hash search uses integer-sample BVs, so the
        // coded MVD is the 1/16-sample BVD divided by 16. The current CTU-local
        // table is far inside the [-2^17, 2^17-1] range, but keep the guard
        // here so a later picture-wide IBC virtual buffer has a clear failure
        // point.
        if !vvc_ibc_mvd_component_is_supported(mvd.x) || !vvc_ibc_mvd_component_is_supported(mvd.y)
        {
            return None;
        }

        Some(VvcIbcCuDecision {
            origin_x,
            origin_y,
            ref_origin_x: reference.origin_x,
            ref_origin_y: reference.origin_y,
            bv_x: bv.x,
            bv_y: bv.y,
            mvd_x: mvd.x,
            mvd_y: mvd.y,
            pred_mode_ibc_ctx: self.pred_mode_ibc_ctx(origin_x, origin_y),
        })
    }

    pub(super) fn decide_left_8x8(
        &self,
        frame: &VvcSampledFrame,
        origin_x: usize,
        origin_y: usize,
    ) -> Option<VvcIbcCuDecision> {
        if origin_x < VVC_IBC_CU_SIZE || !vvc_ibc_full_8x8_is_visible(frame, origin_x, origin_y) {
            return None;
        }

        let ref_origin_x = origin_x - VVC_IBC_CU_SIZE;
        let ref_origin_y = origin_y;
        let predictor = self.bvp_for(origin_x, origin_y);
        let bv = VvcIbcBv {
            x: -((VVC_IBC_CU_SIZE as i16) << 4),
            y: 0,
        };
        let bvd = VvcIbcBv {
            x: bv.x - predictor.x,
            y: bv.y - predictor.y,
        };

        if (bvd.x & 15) != 0 || (bvd.y & 15) != 0 {
            return None;
        }
        let mvd = VvcIbcBv {
            x: bvd.x >> 4,
            y: bvd.y >> 4,
        };

        if !vvc_ibc_mvd_component_is_supported(mvd.x) || !vvc_ibc_mvd_component_is_supported(mvd.y)
        {
            return None;
        }

        Some(VvcIbcCuDecision {
            origin_x,
            origin_y,
            ref_origin_x,
            ref_origin_y,
            bv_x: bv.x,
            bv_y: bv.y,
            mvd_x: mvd.x,
            mvd_y: mvd.y,
            pred_mode_ibc_ctx: self.pred_mode_ibc_ctx(origin_x, origin_y),
        })
    }

    pub(super) fn record_palette_8x8(
        &mut self,
        frame: &VvcSampledFrame,
        origin_x: usize,
        origin_y: usize,
    ) {
        self.record_mode(origin_x, origin_y, None);
        self.record_hash_if_full_visible(frame, origin_x, origin_y);
    }

    pub(super) fn record_ibc_8x8(&mut self, frame: &VvcSampledFrame, decision: VvcIbcCuDecision) {
        let bv = VvcIbcBv {
            x: decision.bv_x,
            y: decision.bv_y,
        };
        self.record_mode(decision.origin_x, decision.origin_y, Some(bv));
        self.record_hmvp(bv);
        self.record_hash_if_full_visible(frame, decision.origin_x, decision.origin_y);
    }

    pub(super) fn pred_mode_ibc_ctx(&self, origin_x: usize, origin_y: usize) -> u8 {
        let mut ctx = 0;
        if origin_x >= VVC_IBC_CU_SIZE {
            ctx += u8::from(self.ibc_mode_at(origin_x - VVC_IBC_CU_SIZE, origin_y));
        }
        if origin_y >= VVC_IBC_CU_SIZE {
            ctx += u8::from(self.ibc_mode_at(origin_x, origin_y - VVC_IBC_CU_SIZE));
        }
        ctx
    }

    fn bvp_for(&self, origin_x: usize, origin_y: usize) -> VvcIbcBv {
        // H.266 8.6.2.2 constructs the IBC BVP list as A1, B1, HMVP, then zero.
        // The current SPS sets MaxNumIbcMergeCand to 1, so only the first
        // available candidate is used and mvp_l0_flag is not present.
        if origin_x >= VVC_IBC_CU_SIZE {
            if let Some(bv) = self.ibc_bv_at(origin_x - VVC_IBC_CU_SIZE, origin_y) {
                return bv;
            }
        }
        if origin_y >= VVC_IBC_CU_SIZE {
            if let Some(bv) = self.ibc_bv_at(origin_x, origin_y - VVC_IBC_CU_SIZE) {
                return bv;
            }
        }
        self.hmvp.last().copied().unwrap_or(VvcIbcBv { x: 0, y: 0 })
    }

    fn record_mode(&mut self, origin_x: usize, origin_y: usize, bv: Option<VvcIbcBv>) {
        let Some(index) = vvc_ibc_cu_index(origin_x, origin_y) else {
            return;
        };
        self.ibc_mode_by_cu[index] = bv.is_some();
        self.bv_by_cu[index] = bv.unwrap_or(VvcIbcBv { x: 0, y: 0 });
    }

    fn record_hash_if_full_visible(
        &mut self,
        frame: &VvcSampledFrame,
        origin_x: usize,
        origin_y: usize,
    ) {
        if vvc_ibc_full_8x8_is_visible(frame, origin_x, origin_y) {
            self.entries.push(VvcIbcHashEntry {
                hash: vvc_ibc_hash_8x8(frame, origin_x, origin_y),
                origin_x,
                origin_y,
            });
        }
    }

    fn local_hash_candidate(
        &self,
        origin_x: usize,
        origin_y: usize,
        hash: u32,
    ) -> Option<VvcIbcHashEntry> {
        if origin_x >= VVC_IBC_CU_SIZE {
            if let Some(entry) = self.hash_entry_at(origin_x - VVC_IBC_CU_SIZE, origin_y) {
                if entry.hash == hash {
                    return Some(entry);
                }
            }
        }
        if origin_y >= VVC_IBC_CU_SIZE {
            if let Some(entry) = self.hash_entry_at(origin_x, origin_y - VVC_IBC_CU_SIZE) {
                if entry.hash == hash {
                    return Some(entry);
                }
            }
        }
        if origin_x >= VVC_IBC_CU_SIZE && origin_y >= VVC_IBC_CU_SIZE {
            if let Some(entry) =
                self.hash_entry_at(origin_x - VVC_IBC_CU_SIZE, origin_y - VVC_IBC_CU_SIZE)
            {
                if entry.hash == hash {
                    return Some(entry);
                }
            }
        }
        None
    }

    fn record_hmvp(&mut self, bv: VvcIbcBv) {
        if let Some(pos) = self.hmvp.iter().position(|entry| *entry == bv) {
            self.hmvp.remove(pos);
        } else if self.hmvp.len() == 5 {
            self.hmvp.remove(0);
        }
        self.hmvp.push(bv);
    }

    fn ibc_mode_at(&self, origin_x: usize, origin_y: usize) -> bool {
        vvc_ibc_cu_index(origin_x, origin_y)
            .map(|index| self.ibc_mode_by_cu[index])
            .unwrap_or(false)
    }

    fn ibc_bv_at(&self, origin_x: usize, origin_y: usize) -> Option<VvcIbcBv> {
        let index = vvc_ibc_cu_index(origin_x, origin_y)?;
        self.ibc_mode_by_cu[index].then_some(self.bv_by_cu[index])
    }

    fn hash_entry_at(&self, origin_x: usize, origin_y: usize) -> Option<VvcIbcHashEntry> {
        self.entries
            .iter()
            .find(|entry| entry.origin_x == origin_x && entry.origin_y == origin_y)
            .copied()
    }
}

fn vvc_ibc_full_8x8_is_visible(frame: &VvcSampledFrame, origin_x: usize, origin_y: usize) -> bool {
    origin_x + VVC_IBC_CU_SIZE <= frame.geometry.width
        && origin_y + VVC_IBC_CU_SIZE <= frame.geometry.height
}

fn vvc_ibc_cu_index(origin_x: usize, origin_y: usize) -> Option<usize> {
    let col = origin_x / VVC_IBC_CU_SIZE;
    let row = origin_y / VVC_IBC_CU_SIZE;
    if col < VVC_CTU_SIZE / VVC_IBC_CU_SIZE && row < VVC_CTU_SIZE / VVC_IBC_CU_SIZE {
        Some(row * (VVC_CTU_SIZE / VVC_IBC_CU_SIZE) + col)
    } else {
        None
    }
}

fn vvc_ibc_hash_8x8(frame: &VvcSampledFrame, origin_x: usize, origin_y: usize) -> u32 {
    let mut hash = VVC_IBC_HASH_OFFSET;
    // Mirror ff_vvc_ibc_hash_matcher.sv and the top-level TU stream contract:
    // one 8x8 luma block, then the colocated 8x8 Cb block, then Cr.
    for plane in [&frame.luma, &frame.cb, &frame.cr] {
        for y_off in 0..VVC_IBC_CU_SIZE {
            for x_off in 0..VVC_IBC_CU_SIZE {
                let sample_x = origin_x + x_off;
                let sample_y = origin_y + y_off;
                let index = sample_y * frame.geometry.width + sample_x;
                hash = vvc_ibc_hash_byte(hash, plane[index]);
            }
        }
    }
    hash
}

fn vvc_ibc_hash_byte(hash: u32, value: u8) -> u32 {
    let mixed = hash ^ u32::from(value);
    let mixed = mixed ^ mixed.wrapping_shl(13);
    let mixed = mixed ^ mixed.wrapping_shr(17);
    mixed ^ mixed.wrapping_shl(5)
}

fn vvc_ibc_mvd_component_is_supported(value: i16) -> bool {
    (-131_072..=131_071).contains(&i32::from(value))
}
