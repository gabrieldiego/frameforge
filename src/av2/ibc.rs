use super::tile::av2_mvp_8x8_leaf_order_for_region;
use super::Av2VideoGeometry;
use crate::picture::{Picture, PixelFormat};

pub(crate) const AV2_IBC_HASH_BLOCK_SIZE: usize = 8;
const AV2_IBC_TILE_SIZE: usize = 64;
const AV2_IBC_HASH_OFFSET: u32 = 0x811c_9dc5;
const AV2_IBC_MAX_BVP_SIZE: usize = 4;
const AV2_IBC_DRL_IDX_ABOVE_8X8: u8 = 2;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Av2LocalIbcVector {
    SuperblockAbove,
    SuperblockDelayedLeft,
    Above8x8,
    Left8x8,
}

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
    copy_vector: Option<Av2LocalIbcVector>,
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
    let mut blocks = vec![
        Av2LocalIbcBlock444 {
            hash: 0,
            candidate_drl_idx: None,
            copy_vector: None,
        };
        blocks_wide * blocks_high
    ];
    for block_y in 0..blocks_high {
        for block_x in 0..blocks_wide {
            let x0 = block_x * AV2_IBC_HASH_BLOCK_SIZE;
            let y0 = block_y * AV2_IBC_HASH_BLOCK_SIZE;
            blocks[block_y * blocks_wide + block_x].hash = hash_yuv444_8x8(frame, geometry, x0, y0);
        }
    }

    let mut any_copy = false;
    let mut stats = Av2LocalIbcStats::default();
    let mut coded_blocks = vec![false; blocks_wide * blocks_high];

    for tile_y0 in (0..blocks_high).step_by(AV2_IBC_TILE_SIZE / AV2_IBC_HASH_BLOCK_SIZE) {
        for tile_x0 in (0..blocks_wide).step_by(AV2_IBC_TILE_SIZE / AV2_IBC_HASH_BLOCK_SIZE) {
            let tile_blocks_wide =
                (blocks_wide - tile_x0).min(AV2_IBC_TILE_SIZE / AV2_IBC_HASH_BLOCK_SIZE);
            let tile_blocks_high =
                (blocks_high - tile_y0).min(AV2_IBC_TILE_SIZE / AV2_IBC_HASH_BLOCK_SIZE);
            let leaf_order = av2_mvp_8x8_leaf_order_for_region(
                tile_blocks_wide * AV2_IBC_HASH_BLOCK_SIZE,
                tile_blocks_high * AV2_IBC_HASH_BLOCK_SIZE,
            );
            for (local_x0, local_y0) in leaf_order {
                let block_x = tile_x0 + local_x0 / AV2_IBC_HASH_BLOCK_SIZE;
                let block_y = tile_y0 + local_y0 / AV2_IBC_HASH_BLOCK_SIZE;
                visit_local_ibc_block(
                    &mut blocks,
                    &mut coded_blocks,
                    blocks_wide,
                    blocks_high,
                    block_x,
                    block_y,
                    &mut any_copy,
                    &mut stats,
                );
            }
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

fn visit_local_ibc_block(
    blocks: &mut [Av2LocalIbcBlock444],
    coded_blocks: &mut [bool],
    blocks_wide: usize,
    blocks_high: usize,
    block_x: usize,
    block_y: usize,
    any_copy: &mut bool,
    stats: &mut Av2LocalIbcStats,
) {
    let block_index = block_y * blocks_wide + block_x;
    let hash = blocks[block_index].hash;
    stats.total_blocks += 1;
    let x0 = block_x * AV2_IBC_HASH_BLOCK_SIZE;
    let y0 = block_y * AV2_IBC_HASH_BLOCK_SIZE;
    // AV2 v1.0.0 IntraBC syntax codes a block vector. The local MVP
    // search stores only 32-bit signatures. Its candidate list mirrors
    // the AVM mvref_common.c order used by setup_ref_mv_list() for
    // local 8x8 IntraBC: already-coded spatial IBC BVs are inserted
    // first, then AVM's default reference-BV entries fill the remaining
    // slots. This permits DRL 0/1 when a neighbor already carries the
    // desired {0,-8} or {-8,0} vector, while still using DRL 2/3 when
    // the defaults are unshifted.
    let left_in_same_tile = x0 % AV2_IBC_TILE_SIZE != 0;
    let above_in_same_tile = y0 % AV2_IBC_TILE_SIZE != 0;
    let tile_block_row = block_y % (AV2_IBC_TILE_SIZE / AV2_IBC_HASH_BLOCK_SIZE);
    let tile_block_rows =
        (AV2_IBC_TILE_SIZE / AV2_IBC_HASH_BLOCK_SIZE).min(blocks_high - (block_y - tile_block_row));
    let terminal_tile_row = tile_block_row + 1 == tile_block_rows;
    let default_above_bvp_supported = false;
    let default_left_bvp_supported = false;
    if left_in_same_tile {
        stats.blocks_with_left_in_tile += 1;
    }
    if above_in_same_tile {
        stats.blocks_with_above_in_tile += 1;
    }
    let above_index = block_y
        .checked_sub(1)
        .map(|above_y| above_y * blocks_wide + block_x);
    let left_index = block_x
        .checked_sub(1)
        .map(|left_x| block_y * blocks_wide + left_x);
    let bvp_stack = build_bvp_stack_8x8(
        blocks,
        coded_blocks,
        blocks_wide,
        blocks_high,
        block_x,
        block_y,
    );
    let above_drl_idx = bvp_stack
        .iter()
        .position(|candidate| *candidate == Av2LocalIbcVector::Above8x8)
        .map(|index| index as u8);
    let left_drl_idx = bvp_stack
        .iter()
        .position(|candidate| *candidate == Av2LocalIbcVector::Left8x8)
        .map(|index| index as u8);
    let fixed_drl_candidate_supported = above_drl_idx.is_some() || left_drl_idx.is_some();
    if fixed_drl_candidate_supported {
        stats.fixed_drl_supported_blocks += 1;
    }

    let raw_above_match = above_in_same_tile
        && above_index.is_some_and(|index| coded_blocks[index] && blocks[index].hash == hash);
    let raw_left_match = left_in_same_tile
        && left_index.is_some_and(|index| coded_blocks[index] && blocks[index].hash == hash);
    let left_reference_residual_coded =
        left_index.is_some_and(|index| blocks[index].copy_vector.is_none());
    let direct_above_match = raw_above_match && above_drl_idx.is_some();
    let direct_left_match =
        raw_left_match && left_reference_residual_coded && left_drl_idx.is_some();
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

    // AV2 v1.0.0 av2_is_dv_in_local_range()/setup_ref_mv_list(): a selected
    // IntraBC DRL index is only correct when the encoder mirrors AVM's
    // decoded-BV and pseudo-coded availability state. The hash-only MVP still
    // records raw matches for bitrate experiments, but keeps copy selection
    // disabled so REF reconstruction remains bit-exact.
    // TODO(av2 ibc): add decoded-BV tracking beside the hash table, then
    // re-enable direct above/left copy selection with REF round-trip tests.
    let above_match = default_above_bvp_supported
        && terminal_tile_row
        && direct_above_match
        && above_drl_idx == Some(AV2_IBC_DRL_IDX_ABOVE_8X8);
    // Top-row same-row copies can still be rejected by AVM for the current
    // partial-superblock partition state. Keep left-copy selection below the
    // first 8x8 row until the full is_mi_coded/pseudo-coded map is mirrored.
    // See the decoded-BV TODO above before re-enabling left-copy selection.
    let left_match = default_left_bvp_supported && direct_left_match && above_in_same_tile;
    let candidate = match (above_match, left_match) {
        (true, true) => {
            let above_idx = above_drl_idx.expect("above match has a DRL index");
            let left_idx = left_drl_idx.expect("left match has a DRL index");
            if above_idx <= left_idx {
                Some((above_idx, Av2LocalIbcVector::Above8x8))
            } else {
                Some((left_idx, Av2LocalIbcVector::Left8x8))
            }
        }
        (true, false) => Some((
            above_drl_idx.expect("above match has a DRL index"),
            Av2LocalIbcVector::Above8x8,
        )),
        (false, true) => Some((
            left_drl_idx.expect("left match has a DRL index"),
            Av2LocalIbcVector::Left8x8,
        )),
        (false, false) => None,
    };
    let (candidate_drl_idx, copy_vector) = if let Some((drl_idx, vector)) = candidate {
        match vector {
            Av2LocalIbcVector::Above8x8 => stats.selected_above_copy_blocks += 1,
            Av2LocalIbcVector::Left8x8 => stats.selected_left_copy_blocks += 1,
            _ => unreachable!("only direct 8x8 local BVs are selected"),
        }
        (Some(drl_idx), Some(vector))
    } else {
        (None, None)
    };
    *any_copy |= candidate_drl_idx.is_some();
    blocks[block_index].candidate_drl_idx = candidate_drl_idx;
    blocks[block_index].copy_vector = copy_vector;
    coded_blocks[block_index] = true;
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

fn build_bvp_stack_8x8(
    blocks: &[Av2LocalIbcBlock444],
    coded_blocks: &[bool],
    blocks_wide: usize,
    blocks_high: usize,
    block_x: usize,
    block_y: usize,
) -> Vec<Av2LocalIbcVector> {
    let mut stack = Vec::with_capacity(AV2_IBC_MAX_BVP_SIZE);
    // AV2 v1.0.0 setup_ref_mv_list() can scan several spatial IntraBC BVP
    // positions before appending default BVs. FrameForge's streaming hash path
    // intentionally keeps only direct left/above 8x8 candidates so the RTL can
    // decide a copy as soon as the current block hash is complete.
    for (row_mi_offset, col_mi_offset) in [(0, -1), (-1, 0)] {
        if let Some(index) = neighbor_index_for_mi_offset(
            blocks_wide,
            blocks_high,
            block_x,
            block_y,
            row_mi_offset,
            col_mi_offset,
        ) {
            if coded_blocks[index] {
                push_unique_spatial_bv(&mut stack, blocks[index].copy_vector);
            }
        }
    }
    for vector in [
        Av2LocalIbcVector::SuperblockAbove,
        Av2LocalIbcVector::SuperblockDelayedLeft,
        Av2LocalIbcVector::Above8x8,
        Av2LocalIbcVector::Left8x8,
    ] {
        if stack.len() >= AV2_IBC_MAX_BVP_SIZE {
            break;
        }
        // AVM add_to_ref_bv_list() intentionally does not de-duplicate the
        // default BVP entries. A duplicate later default is harmless because
        // the encoder always selects the first matching vector.
        stack.push(vector);
    }
    stack
}

fn push_unique_spatial_bv(stack: &mut Vec<Av2LocalIbcVector>, vector: Option<Av2LocalIbcVector>) {
    if stack.len() >= AV2_IBC_MAX_BVP_SIZE {
        return;
    }
    let Some(vector) = vector else {
        return;
    };
    if !stack.contains(&vector) {
        stack.push(vector);
    }
}

fn neighbor_index_for_mi_offset(
    blocks_wide: usize,
    blocks_high: usize,
    block_x: usize,
    block_y: usize,
    row_mi_offset: isize,
    col_mi_offset: isize,
) -> Option<usize> {
    let tile_block_x = block_x % (AV2_IBC_TILE_SIZE / AV2_IBC_HASH_BLOCK_SIZE);
    let tile_block_y = block_y % (AV2_IBC_TILE_SIZE / AV2_IBC_HASH_BLOCK_SIZE);
    let tile_origin_x = block_x - tile_block_x;
    let tile_origin_y = block_y - tile_block_y;
    let candidate_mi_col = (tile_block_x * 2) as isize + col_mi_offset;
    let candidate_mi_row = (tile_block_y * 2) as isize + row_mi_offset;
    if !(0..16).contains(&candidate_mi_col) || !(0..16).contains(&candidate_mi_row) {
        return None;
    }
    let candidate_block_x = tile_origin_x + (candidate_mi_col as usize / 2);
    let candidate_block_y = tile_origin_y + (candidate_mi_row as usize / 2);
    if candidate_block_x >= blocks_wide || candidate_block_y >= blocks_high {
        return None;
    }
    Some(candidate_block_y * blocks_wide + candidate_block_x)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn av2_local_ibc_hash_marks_repeated_left_8x8_block() {
        let geometry = Av2VideoGeometry {
            width: 16,
            height: 16,
        };
        let plane_len = geometry.width * geometry.height;
        let mut frame = vec![0; plane_len * 3];
        for plane in 0..3 {
            for y in 0..16 {
                for x in 0..8 {
                    let value = (plane * 29 + y * 11 + x * 7) as u8;
                    frame[plane * plane_len + y * geometry.width + x] = value;
                    frame[plane * plane_len + y * geometry.width + x + 8] =
                        if y >= 8 { value } else { value.wrapping_add(3) };
                }
            }
        }

        let ibc = build_local_ibc_444(&frame, geometry).expect("IBC hash map should build");
        assert_eq!(ibc.candidate_drl_idx(0, 0), None);
        assert_eq!(ibc.candidate_drl_idx(8, 0), None);
        // Partial-width left copies need decoded-BV tracking before the
        // hash-only path can guarantee the reference decoder copies the
        // immediate-left block.
        assert_eq!(ibc.candidate_drl_idx(8, 8), None);
        assert!(!ibc.any_copy());
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
        assert_eq!(ibc.candidate_drl_idx(0, 8), None);
        assert_eq!(ibc.stats.raw_above_hash_matches, 1);
        assert!(!ibc.any_copy());
    }

    #[test]
    fn av2_local_ibc_hash_reuses_adjacent_vertical_spatial_bvp() {
        let geometry = Av2VideoGeometry {
            width: 8,
            height: 24,
        };
        let plane_len = geometry.width * geometry.height;
        let mut frame = vec![0; plane_len * 3];
        for plane in 0..3 {
            for y in 0..8 {
                for x in 0..8 {
                    let value = (plane * 17 + y * 19 + x * 3) as u8;
                    for block in 0..3 {
                        frame[plane * plane_len + (y + block * 8) * geometry.width + x] = value;
                    }
                }
            }
        }

        let ibc = build_local_ibc_444(&frame, geometry).expect("IBC hash map should build");
        assert_eq!(ibc.candidate_drl_idx(0, 0), None);
        assert_eq!(ibc.candidate_drl_idx(0, 8), None);
        assert_eq!(ibc.candidate_drl_idx(0, 16), None);
        assert_eq!(ibc.stats.raw_above_hash_matches, 2);
    }

    #[test]
    fn av2_local_ibc_hash_reuses_adjacent_spatial_bvp() {
        let geometry = Av2VideoGeometry {
            width: 24,
            height: 16,
        };
        let plane_len = geometry.width * geometry.height;
        let mut frame = vec![0; plane_len * 3];
        for plane in 0..3 {
            for y in 0..16 {
                for x in 0..8 {
                    let value = (plane * 31 + y * 13 + x * 5) as u8;
                    for block in 0..3 {
                        frame[plane * plane_len + y * geometry.width + x + block * 8] = if y >= 8 {
                            value
                        } else {
                            value.wrapping_add(block as u8 + 1)
                        };
                    }
                }
            }
        }

        let ibc = build_local_ibc_444(&frame, geometry).expect("IBC hash map should build");
        assert_eq!(ibc.candidate_drl_idx(0, 0), None);
        assert_eq!(ibc.candidate_drl_idx(8, 0), None);
        assert_eq!(ibc.candidate_drl_idx(8, 8), None);
        assert_eq!(ibc.candidate_drl_idx(16, 8), None);
    }

    #[test]
    fn av2_local_ibc_hash_keeps_defaults_after_non_direct_spatial_bvp() {
        let geometry = Av2VideoGeometry {
            width: 32,
            height: 24,
        };
        let plane_len = geometry.width * geometry.height;
        let mut frame = vec![0; plane_len * 3];
        for plane in 0..3 {
            for y in 0..geometry.height {
                for x in 0..geometry.width {
                    frame[plane * plane_len + y * geometry.width + x] =
                        (plane * 41 + y * 17 + x * 9) as u8;
                }
            }
            for y in 8..16 {
                for x in 0..8 {
                    let value = (plane * 23 + y * 5 + x * 3) as u8;
                    frame[plane * plane_len + y * geometry.width + x] = value;
                    frame[plane * plane_len + y * geometry.width + x + 8] = value;
                }
            }
            for y in 16..24 {
                for x in 0..8 {
                    let value = (plane * 13 + y * 7 + x * 11) as u8;
                    frame[plane * plane_len + y * geometry.width + x + 8] = value;
                    frame[plane * plane_len + y * geometry.width + x + 16] = value;
                }
            }
        }

        let ibc = build_local_ibc_444(&frame, geometry).expect("IBC hash map should build");
        assert_eq!(ibc.candidate_drl_idx(8, 8), None);
        assert_eq!(ibc.candidate_drl_idx(16, 16), None);
        assert_eq!(ibc.stats.raw_left_hash_matches, 2);
    }

    #[test]
    fn av2_local_ibc_hash_allows_full_tile_bottom_row_without_adjacent_copy() {
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
