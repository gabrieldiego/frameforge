use super::Av2VideoGeometry;
use crate::picture::{Picture, PixelFormat};

pub(crate) const AV2_IBC_HASH_BLOCK_SIZE: usize = 8;
const AV2_IBC_TILE_SIZE: usize = 64;
const AV2_IBC_HASH_OFFSET: u32 = 0x811c_9dc5;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Av2LeftIbcBlock444 {
    hash: u32,
    use_left_copy: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Av2LeftIbc444 {
    blocks: Vec<Av2LeftIbcBlock444>,
    blocks_wide: usize,
    blocks_high: usize,
    any_left_copy: bool,
}

impl Av2LeftIbc444 {
    pub(crate) fn any_left_copy(&self) -> bool {
        self.any_left_copy
    }

    pub(crate) fn uses_left_copy(&self, x0: usize, y0: usize) -> bool {
        assert_eq!(x0 % AV2_IBC_HASH_BLOCK_SIZE, 0);
        assert_eq!(y0 % AV2_IBC_HASH_BLOCK_SIZE, 0);
        let block_x = x0 / AV2_IBC_HASH_BLOCK_SIZE;
        let block_y = y0 / AV2_IBC_HASH_BLOCK_SIZE;
        assert!(block_x < self.blocks_wide && block_y < self.blocks_high);
        self.blocks[block_y * self.blocks_wide + block_x].use_left_copy
    }
}

pub(crate) fn build_left_ibc_444(
    frame: &[u8],
    geometry: Av2VideoGeometry,
) -> Result<Av2LeftIbc444, String> {
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
    let mut blocks: Vec<Av2LeftIbcBlock444> = Vec::with_capacity(blocks_wide * blocks_high);
    let mut any_left_copy = false;

    for block_y in 0..blocks_high {
        for block_x in 0..blocks_wide {
            let x0 = block_x * AV2_IBC_HASH_BLOCK_SIZE;
            let y0 = block_y * AV2_IBC_HASH_BLOCK_SIZE;
            let hash = hash_yuv444_8x8(frame, geometry, x0, y0);
            // AV2 v1.0.0 IntraBC syntax codes a block vector, not samples.
            // FrameForge's first hardware-oriented search stores only one
            // 32-bit signature from the immediate left 8x8 block. Keeping the
            // match inside the 64x64 tile preserves the current independent
            // superblock-tile contract while staging a wider search window.
            let left_in_same_tile = x0 % AV2_IBC_TILE_SIZE != 0;
            let use_left_copy = if left_in_same_tile {
                blocks.last().is_some_and(|left| left.hash == hash)
            } else {
                false
            };
            any_left_copy |= use_left_copy;
            blocks.push(Av2LeftIbcBlock444 {
                hash,
                use_left_copy,
            });
        }
    }

    Ok(Av2LeftIbc444 {
        blocks,
        blocks_wide,
        blocks_high,
        any_left_copy,
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
    fn av2_left_ibc_hash_marks_repeated_left_8x8_block() {
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

        let ibc = build_left_ibc_444(&frame, geometry).expect("IBC hash map should build");
        assert!(!ibc.uses_left_copy(0, 0));
        assert!(ibc.uses_left_copy(8, 0));
        assert!(ibc.any_left_copy());
    }
}
