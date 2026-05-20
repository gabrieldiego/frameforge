//! First-target VVC/H.266 placeholders.
//!
//! This module intentionally does not implement VVC syntax yet. Exact NAL unit
//! types, parameter sets, slice headers, CTU syntax, CABAC, transform/quant,
//! and reconstruction semantics must be added from the specification or another
//! clean-room source before FrameForge can emit a decodable VVC bitstream.

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
