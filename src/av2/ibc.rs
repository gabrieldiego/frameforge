use super::Av2VideoGeometry;
use crate::picture::{Picture, PixelFormat};

pub(crate) const AV2_IBC_HASH_BLOCK_SIZE: usize = 8;
const AV2_IBC_TILE_SIZE: usize = 64;
const AV2_IBC_HASH_OFFSET: u32 = 0x811c_9dc5;
pub(crate) const AV2_IBC_DRL_IDX_ABOVE_8X8: u8 = 2;
pub(crate) const AV2_IBC_DRL_IDX_LEFT_8X8: u8 = 3;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub(crate) struct Av2LocalIbcStats {
    pub(crate) total_blocks: usize,
    pub(crate) blocks_with_above_in_tile: usize,
    pub(crate) blocks_with_left_in_tile: usize,
    pub(crate) fixed_drl_supported_blocks: usize,
    pub(crate) raw_above_hash_matches: usize,
    pub(crate) raw_left_hash_matches: usize,
    pub(crate) direct_above_hash_matches: usize,
    pub(crate) direct_left_hash_matches: usize,
    pub(crate) above_hash_matches_blocked_by_fixed_drl_guard: usize,
    pub(crate) left_hash_matches_blocked_by_fixed_drl_guard: usize,
    pub(crate) above_hash_matches_blocked_by_copied_candidate: usize,
    pub(crate) left_hash_matches_blocked_by_copied_candidate: usize,
    pub(crate) selected_above_copy_blocks: usize,
    pub(crate) selected_left_copy_blocks: usize,
}

impl Av2LocalIbcStats {
    pub(crate) fn selected_copy_blocks(self) -> usize {
        self.selected_above_copy_blocks + self.selected_left_copy_blocks
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Av2LocalIbcBlock444 {
    hash: u32,
    candidate_drl_idx: Option<u8>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Av2LocalIbc444 {
    blocks: Vec<Av2LocalIbcBlock444>,
    blocks_wide: usize,
    blocks_high: usize,
    any_copy: bool,
    stats: Av2LocalIbcStats,
}

impl Av2LocalIbc444 {
    #[cfg(test)]
    pub(crate) fn any_copy(&self) -> bool {
        self.any_copy
    }

    pub(crate) fn candidate_drl_idx(&self, x0: usize, y0: usize) -> Option<u8> {
        assert_eq!(x0 % AV2_IBC_HASH_BLOCK_SIZE, 0);
        assert_eq!(y0 % AV2_IBC_HASH_BLOCK_SIZE, 0);
        let block_x = x0 / AV2_IBC_HASH_BLOCK_SIZE;
        let block_y = y0 / AV2_IBC_HASH_BLOCK_SIZE;
        assert!(block_x < self.blocks_wide && block_y < self.blocks_high);
        self.blocks[block_y * self.blocks_wide + block_x].candidate_drl_idx
    }

    pub(crate) fn stats(&self) -> Av2LocalIbcStats {
        self.stats
    }
}

pub(crate) fn build_local_ibc_444(
    frame: &[u8],
    geometry: Av2VideoGeometry,
) -> Result<Av2LocalIbc444, String> {
    let expected_len =
        Picture::expected_len(geometry.width, geometry.height, PixelFormat::Yuv444p8);
    if frame.len() != expected_len {
        return Err(format!(
            "AV2 IBC input length mismatch: expected {expected_len} byte(s), got {}",
            frame.len()
        ));
    }
    if geometry.width % AV2_IBC_HASH_BLOCK_SIZE != 0
        || geometry.height % AV2_IBC_HASH_BLOCK_SIZE != 0
    {
        return Err(format!(
            "AV2 IBC hash path expects dimensions in {}-pixel units, got {}x{}",
            AV2_IBC_HASH_BLOCK_SIZE, geometry.width, geometry.height
        ));
    }

    let blocks_wide = geometry.width / AV2_IBC_HASH_BLOCK_SIZE;
    let blocks_high = geometry.height / AV2_IBC_HASH_BLOCK_SIZE;
    let mut blocks: Vec<Av2LocalIbcBlock444> = Vec::with_capacity(blocks_wide * blocks_high);
    let mut any_copy = false;
    let mut stats = Av2LocalIbcStats::default();

    for block_y in 0..blocks_high {
        for block_x in 0..blocks_wide {
            stats.total_blocks += 1;
            let x0 = block_x * AV2_IBC_HASH_BLOCK_SIZE;
            let y0 = block_y * AV2_IBC_HASH_BLOCK_SIZE;
            let hash = hash_yuv444_8x8(frame, geometry, x0, y0);
            // AV2 v1.0.0 IntraBC syntax codes a block vector. The local MVP
            // search stores only 32-bit signatures and selects among the
            // default reference-BV stack entries from AVM mvref_common.c:
            // entry 2 is the above 8x8 block and entry 3 is the left 8x8
            // block for FrameForge's fixed 8x8 leaf path.
            let left_in_same_tile = x0 % AV2_IBC_TILE_SIZE != 0;
            let above_in_same_tile = y0 % AV2_IBC_TILE_SIZE != 0;
            if left_in_same_tile {
                stats.blocks_with_left_in_tile += 1;
            }
            if above_in_same_tile {
                stats.blocks_with_above_in_tile += 1;
            }
            let tile_right = ((x0 / AV2_IBC_TILE_SIZE) * AV2_IBC_TILE_SIZE + AV2_IBC_TILE_SIZE)
                .min(geometry.width);
            let tile_bottom = ((y0 / AV2_IBC_TILE_SIZE) * AV2_IBC_TILE_SIZE + AV2_IBC_TILE_SIZE)
                .min(geometry.height);
            let terminal_visible_leaf = x0 + AV2_IBC_HASH_BLOCK_SIZE == tile_right
                && y0 + AV2_IBC_HASH_BLOCK_SIZE == tile_bottom;
            // AV2/AVM derives the selected BV from the neighboring-mode BVP
            // stack. The full stack is not modeled yet, so keep fixed-DRL
            // copies in the subset validated against AVM: terminal leaves that
            // are not on the bottom row of a full 64x64 tile. A non-terminal
            // copy changes neighboring MB_MODE_INFO and shifts the BVP stack
            // for following leaves, so it must wait for a real stack model.
            let fixed_drl_candidate_supported = terminal_visible_leaf
                && (y0 % AV2_IBC_TILE_SIZE) + AV2_IBC_HASH_BLOCK_SIZE < AV2_IBC_TILE_SIZE;
            if fixed_drl_candidate_supported {
                stats.fixed_drl_supported_blocks += 1;
            }

            let above_index = block_y
                .checked_sub(1)
                .map(|above_y| above_y * blocks_wide + block_x);

            let raw_above_match =
                above_in_same_tile && above_index.is_some_and(|index| blocks[index].hash == hash);
            let raw_left_match =
                left_in_same_tile && blocks.last().is_some_and(|left| left.hash == hash);
            let direct_above_match = above_in_same_tile
                && above_index.is_some_and(|index| {
                    let above = blocks[index];
                    above.hash == hash && above.candidate_drl_idx.is_none()
                });
            let direct_left_match = left_in_same_tile
                && blocks
                    .last()
                    .is_some_and(|left| left.hash == hash && left.candidate_drl_idx.is_none());
            if raw_above_match {
                stats.raw_above_hash_matches += 1;
            }
            if raw_left_match {
                stats.raw_left_hash_matches += 1;
            }
            if direct_above_match {
                stats.direct_above_hash_matches += 1;
            } else if raw_above_match {
                stats.above_hash_matches_blocked_by_copied_candidate += 1;
            }
            if direct_left_match {
                stats.direct_left_hash_matches += 1;
            } else if raw_left_match {
                stats.left_hash_matches_blocked_by_copied_candidate += 1;
            }
            if direct_above_match && !fixed_drl_candidate_supported {
                stats.above_hash_matches_blocked_by_fixed_drl_guard += 1;
            }
            if direct_left_match && !fixed_drl_candidate_supported {
                stats.left_hash_matches_blocked_by_fixed_drl_guard += 1;
            }

            let above_match = fixed_drl_candidate_supported && direct_above_match;
            let left_match = fixed_drl_candidate_supported && direct_left_match;
            let candidate_drl_idx = if above_match {
                stats.selected_above_copy_blocks += 1;
                Some(AV2_IBC_DRL_IDX_ABOVE_8X8)
            } else if left_match {
                stats.selected_left_copy_blocks += 1;
                Some(AV2_IBC_DRL_IDX_LEFT_8X8)
            } else {
                None
            };
            any_copy |= candidate_drl_idx.is_some();
            blocks.push(Av2LocalIbcBlock444 {
                hash,
                candidate_drl_idx,
            });
        }
    }

    Ok(Av2LocalIbc444 {
        blocks,
        blocks_wide,
        blocks_high,
        any_copy,
        stats,
    })
}

fn hash_yuv444_8x8(frame: &[u8], geometry: Av2VideoGeometry, x0: usize, y0: usize) -> u32 {
    let plane_len = geometry.width * geometry.height;
    let mut hash = AV2_IBC_HASH_OFFSET;
    for plane in 0..3 {
        let base = plane * plane_len;
        for local_y in 0..AV2_IBC_HASH_BLOCK_SIZE {
            let row = y0 + local_y;
            for local_x in 0..AV2_IBC_HASH_BLOCK_SIZE {
                let col = x0 + local_x;
                // Keep the hash mixer multiplier-free so the AV2 RTL can make
                // the same exact-copy decision without adding a large datapath.
                hash ^= u32::from(frame[base + row * geometry.width + col]);
                hash ^= hash << 13;
                hash ^= hash >> 17;
                hash ^= hash << 5;
            }
        }
    }
    hash
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn av2_local_ibc_hash_marks_repeated_left_8x8_block() {
        let geometry = Av2VideoGeometry {
            width: 16,
            height: 8,
        };
        let plane_len = geometry.width * geometry.height;
        let mut frame = vec![0; plane_len * 3];
        for plane in 0..3 {
            for y in 0..8 {
                for x in 0..8 {
                    let value = (plane * 29 + y * 11 + x * 7) as u8;
                    frame[plane * plane_len + y * geometry.width + x] = value;
                    frame[plane * plane_len + y * geometry.width + x + 8] = value;
                }
            }
        }

        let ibc = build_local_ibc_444(&frame, geometry).expect("IBC hash map should build");
        assert_eq!(ibc.candidate_drl_idx(0, 0), None);
        assert_eq!(ibc.candidate_drl_idx(8, 0), Some(AV2_IBC_DRL_IDX_LEFT_8X8));
        assert!(ibc.any_copy());
    }

    #[test]
    fn av2_local_ibc_hash_marks_repeated_above_8x8_block() {
        let geometry = Av2VideoGeometry {
            width: 8,
            height: 16,
        };
        let plane_len = geometry.width * geometry.height;
        let mut frame = vec![0; plane_len * 3];
        for plane in 0..3 {
            for y in 0..8 {
                for x in 0..8 {
                    let value = (plane * 17 + y * 19 + x * 3) as u8;
                    frame[plane * plane_len + y * geometry.width + x] = value;
                    frame[plane * plane_len + (y + 8) * geometry.width + x] = value;
                }
            }
        }

        let ibc = build_local_ibc_444(&frame, geometry).expect("IBC hash map should build");
        assert_eq!(ibc.candidate_drl_idx(0, 0), None);
        assert_eq!(ibc.candidate_drl_idx(0, 8), Some(AV2_IBC_DRL_IDX_ABOVE_8X8));
        assert!(ibc.any_copy());
    }

    #[test]
    fn av2_local_ibc_hash_only_marks_terminal_tile_leaf() {
        let geometry = Av2VideoGeometry {
            width: 24,
            height: 8,
        };
        let plane_len = geometry.width * geometry.height;
        let mut frame = vec![0; plane_len * 3];
        for plane in 0..3 {
            for y in 0..8 {
                for x in 0..8 {
                    let value = (plane * 31 + y * 13 + x * 5) as u8;
                    for block in 0..3 {
                        frame[plane * plane_len + y * geometry.width + x + block * 8] = value;
                    }
                }
            }
        }

        let ibc = build_local_ibc_444(&frame, geometry).expect("IBC hash map should build");
        assert_eq!(ibc.candidate_drl_idx(0, 0), None);
        assert_eq!(ibc.candidate_drl_idx(8, 0), None);
        assert_eq!(ibc.candidate_drl_idx(16, 0), Some(AV2_IBC_DRL_IDX_LEFT_8X8));
    }

    #[test]
    fn av2_local_ibc_hash_skips_full_tile_bottom_row_until_bvp_stack_exists() {
        let geometry = Av2VideoGeometry {
            width: 16,
            height: 64,
        };
        let plane_len = geometry.width * geometry.height;
        let mut frame = vec![0; plane_len * 3];
        for plane in 0..3 {
            for y in 0..geometry.height {
                for x in 0..8 {
                    let value = (plane * 29 + y * 11 + x * 7) as u8;
                    frame[plane * plane_len + y * geometry.width + x] = value;
                    frame[plane * plane_len + y * geometry.width + x + 8] = if y >= 56 {
                        value
                    } else {
                        value.wrapping_add(13)
                    };
                }
            }
        }

        let ibc = build_local_ibc_444(&frame, geometry).expect("IBC hash map should build");
        assert_eq!(ibc.candidate_drl_idx(8, 56), None);
        assert!(!ibc.any_copy());
    }
}
