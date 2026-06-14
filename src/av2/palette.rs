use super::Av2VideoGeometry;
use crate::picture::{Picture, PixelFormat};

pub(crate) const AV2_LUMA_PALETTE_MIN_COLORS: usize = 2;
pub(crate) const AV2_LUMA_PALETTE_MAX_COLORS: usize = 8;
pub(crate) const AV2_LUMA_PALETTE_BLOCK_SIZE: usize = 8;
const AV2_LUMA_PALETTE_BLOCK_SAMPLES: usize =
    AV2_LUMA_PALETTE_BLOCK_SIZE * AV2_LUMA_PALETTE_BLOCK_SIZE;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Av2LumaPaletteBlock444 {
    colors: Vec<u8>,
    indices: [u8; AV2_LUMA_PALETTE_BLOCK_SAMPLES],
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Av2LumaPalette444 {
    blocks: Vec<Av2LumaPaletteBlock444>,
    reconstruction: Vec<u8>,
    width: usize,
    height: usize,
    blocks_wide: usize,
    blocks_high: usize,
}

impl Av2LumaPalette444 {
    pub(crate) fn colors_for_block(&self, x0: usize, y0: usize) -> &[u8] {
        &self.block_for_origin(x0, y0).colors
    }

    pub(crate) fn color_count_for_block(&self, x0: usize, y0: usize) -> usize {
        self.colors_for_block(x0, y0).len()
    }

    pub(crate) fn index_at(&self, x: usize, y: usize) -> u8 {
        assert!(x < self.width && y < self.height);
        let block = self.block_for_origin(
            (x / AV2_LUMA_PALETTE_BLOCK_SIZE) * AV2_LUMA_PALETTE_BLOCK_SIZE,
            (y / AV2_LUMA_PALETTE_BLOCK_SIZE) * AV2_LUMA_PALETTE_BLOCK_SIZE,
        );
        let local_x = x % AV2_LUMA_PALETTE_BLOCK_SIZE;
        let local_y = y % AV2_LUMA_PALETTE_BLOCK_SIZE;
        block.indices[local_y * AV2_LUMA_PALETTE_BLOCK_SIZE + local_x]
    }

    pub(crate) fn reconstruction(&self) -> &[u8] {
        &self.reconstruction
    }

    fn block_for_origin(&self, x0: usize, y0: usize) -> &Av2LumaPaletteBlock444 {
        assert!(x0 < self.width && y0 < self.height);
        assert_eq!(x0 % AV2_LUMA_PALETTE_BLOCK_SIZE, 0);
        assert_eq!(y0 % AV2_LUMA_PALETTE_BLOCK_SIZE, 0);
        let block_x = x0 / AV2_LUMA_PALETTE_BLOCK_SIZE;
        let block_y = y0 / AV2_LUMA_PALETTE_BLOCK_SIZE;
        assert!(block_x < self.blocks_wide && block_y < self.blocks_high);
        &self.blocks[block_y * self.blocks_wide + block_x]
    }
}

pub(crate) fn build_luma_palette_444(
    frame: &[u8],
    geometry: Av2VideoGeometry,
) -> Result<Av2LumaPalette444, String> {
    let expected_len =
        Picture::expected_len(geometry.width, geometry.height, PixelFormat::Yuv444p8);
    if frame.len() != expected_len {
        return Err(format!(
            "AV2 yuv444p8 input length mismatch: expected {expected_len} byte(s), got {}",
            frame.len()
        ));
    }
    if geometry.width % AV2_LUMA_PALETTE_BLOCK_SIZE != 0
        || geometry.height % AV2_LUMA_PALETTE_BLOCK_SIZE != 0
    {
        return Err(format!(
            "AV2 luma palette path expects dimensions in {}-pixel units, got {}x{}",
            AV2_LUMA_PALETTE_BLOCK_SIZE, geometry.width, geometry.height
        ));
    }

    let plane_len = geometry.width * geometry.height;
    let y_plane = &frame[..plane_len];
    let blocks_wide = geometry.width / AV2_LUMA_PALETTE_BLOCK_SIZE;
    let blocks_high = geometry.height / AV2_LUMA_PALETTE_BLOCK_SIZE;
    let mut blocks = Vec::with_capacity(blocks_wide * blocks_high);
    let mut reconstruction = vec![0; expected_len];

    for block_y in 0..blocks_high {
        for block_x in 0..blocks_wide {
            let x0 = block_x * AV2_LUMA_PALETTE_BLOCK_SIZE;
            let y0 = block_y * AV2_LUMA_PALETTE_BLOCK_SIZE;
            let mut samples = [0u8; AV2_LUMA_PALETTE_BLOCK_SAMPLES];
            for local_y in 0..AV2_LUMA_PALETTE_BLOCK_SIZE {
                for local_x in 0..AV2_LUMA_PALETTE_BLOCK_SIZE {
                    let src_index = (y0 + local_y) * geometry.width + x0 + local_x;
                    samples[local_y * AV2_LUMA_PALETTE_BLOCK_SIZE + local_x] = y_plane[src_index];
                }
            }

            let block = build_luma_palette_block(&samples);
            for local_y in 0..AV2_LUMA_PALETTE_BLOCK_SIZE {
                for local_x in 0..AV2_LUMA_PALETTE_BLOCK_SIZE {
                    let local_index = local_y * AV2_LUMA_PALETTE_BLOCK_SIZE + local_x;
                    let dst_index = (y0 + local_y) * geometry.width + x0 + local_x;
                    reconstruction[dst_index] =
                        block.colors[usize::from(block.indices[local_index])];
                }
            }
            blocks.push(block);
        }
    }

    Ok(Av2LumaPalette444 {
        blocks,
        reconstruction,
        width: geometry.width,
        height: geometry.height,
        blocks_wide,
        blocks_high,
    })
}

fn build_luma_palette_block(
    samples: &[u8; AV2_LUMA_PALETTE_BLOCK_SAMPLES],
) -> Av2LumaPaletteBlock444 {
    let mut collected = Vec::with_capacity(AV2_LUMA_PALETTE_MAX_COLORS);
    for &sample in samples {
        if !collected.contains(&sample) && collected.len() < AV2_LUMA_PALETTE_MAX_COLORS {
            collected.push(sample);
        }
    }
    if collected.is_empty() {
        collected.push(0);
    }

    let target_colors = if collected.len() <= 2 {
        2
    } else if collected.len() <= 4 {
        4
    } else {
        AV2_LUMA_PALETTE_MAX_COLORS
    };

    let mut colors = collected;
    let mut candidate = 0u16;
    while colors.len() < target_colors {
        let sample = candidate as u8;
        if !colors.contains(&sample) {
            colors.push(sample);
        }
        candidate += 1;
    }
    colors.sort_unstable();

    let mut indices = [0u8; AV2_LUMA_PALETTE_BLOCK_SAMPLES];
    for (sample_index, &sample) in samples.iter().enumerate() {
        let index = colors
            .iter()
            .position(|&color| color == sample)
            .unwrap_or_else(|| {
                colors
                    .iter()
                    .enumerate()
                    .min_by_key(|(_, &color)| {
                        let delta = i16::from(sample) - i16::from(color);
                        delta.abs()
                    })
                    .map(|(index, _)| index)
                    .expect("AV2 palette always has at least one color")
            });
        indices[sample_index] = index as u8;
    }

    Av2LumaPaletteBlock444 { colors, indices }
}
