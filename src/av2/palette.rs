use super::Av2VideoGeometry;
use crate::picture::{Picture, PixelFormat};

pub(crate) const AV2_LUMA_PALETTE_MIN_COLORS: usize = 2;
pub(crate) const AV2_LUMA_PALETTE_MAX_COLORS: usize = 8;
pub(crate) const AV2_LUMA_PALETTE_BLOCK_SIZE: usize = 8;
const AV2_LUMA_INTRA_TILE_SIZE: usize = 64;
const AV2_LUMA_INTRA_MODE_SWITCH_SAD_MARGIN: usize = 64;
const AV2_CHROMA_BDPCM_HORZ_SAD_BIAS: usize = 256;
const AV2_LUMA_PALETTE_BLOCK_SAMPLES: usize =
    AV2_LUMA_PALETTE_BLOCK_SIZE * AV2_LUMA_PALETTE_BLOCK_SIZE;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Av2LumaIntraMode {
    Dc,
    Vertical,
    Horizontal,
}

impl Av2LumaIntraMode {
    pub(crate) fn mode_index(self) -> usize {
        match self {
            Self::Dc => 0,
            Self::Vertical => 5,
            Self::Horizontal => 6,
        }
    }

    pub(crate) fn symbol_name(self) -> &'static str {
        match self {
            Self::Dc => "tile.intra.y_mode_idx_dc",
            Self::Vertical => "tile.intra.y_mode_idx_v",
            Self::Horizontal => "tile.intra.y_mode_idx_h",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Av2LumaPaletteBlock444 {
    colors: Vec<u8>,
    indices: [u8; AV2_LUMA_PALETTE_BLOCK_SAMPLES],
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Av2LumaPalette444 {
    blocks: Vec<Av2LumaPaletteBlock444>,
    luma_modes: Vec<Av2LumaIntraMode>,
    y_plane: Vec<u8>,
    luma_prediction: Vec<u8>,
    u_plane: Vec<u8>,
    v_plane: Vec<u8>,
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

    pub(crate) fn luma_mode_for_block(&self, x0: usize, y0: usize) -> Av2LumaIntraMode {
        self.luma_modes[self.block_index_for_origin(x0, y0)]
    }

    pub(crate) fn chroma_bdpcm_horz_for_block(&self, x0: usize, y0: usize) -> bool {
        let mut horz_score = 0usize;
        let mut vert_score = 0usize;
        for plane in [&self.u_plane, &self.v_plane] {
            let (plane_horz, plane_vert) = self.chroma_bdpcm_direction_scores(plane, x0, y0);
            horz_score += plane_horz;
            vert_score += plane_vert;
        }
        // AV2 v1.0.0 read_intra_uv_mode() signals one DPCM direction bit.
        // This hardware-oriented heuristic scores the legal H/V predictors
        // and applies a small horizontal bias measured to reduce aggregate
        // screen-content bitrate on the maintained screenshot multi-CTU set
        // without adding a coefficient-cost search to the RTL analyzer.
        horz_score <= vert_score + AV2_CHROMA_BDPCM_HORZ_SAD_BIAS
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

    pub(crate) fn y_sample(&self, x: usize, y: usize) -> u8 {
        self.luma_sample(&self.y_plane, x, y)
    }

    pub(crate) fn luma_prediction_sample(&self, x: usize, y: usize) -> u8 {
        self.luma_sample(&self.luma_prediction, x, y)
    }

    pub(crate) fn reconstruction(&self) -> &[u8] {
        &self.reconstruction
    }

    pub(crate) fn u_sample(&self, x: usize, y: usize) -> u8 {
        self.chroma_sample(&self.u_plane, x, y)
    }

    pub(crate) fn v_sample(&self, x: usize, y: usize) -> u8 {
        self.chroma_sample(&self.v_plane, x, y)
    }

    fn luma_sample(&self, plane: &[u8], x: usize, y: usize) -> u8 {
        assert!(x < self.width && y < self.height);
        plane[y * self.width + x]
    }

    fn chroma_sample(&self, plane: &[u8], x: usize, y: usize) -> u8 {
        assert!(x < self.width && y < self.height);
        plane[y * self.width + x]
    }

    fn chroma_bdpcm_direction_scores(&self, plane: &[u8], x0: usize, y0: usize) -> (usize, usize) {
        let tile_x0 = (x0 / AV2_LUMA_INTRA_TILE_SIZE) * AV2_LUMA_INTRA_TILE_SIZE;
        let tile_y0 = (y0 / AV2_LUMA_INTRA_TILE_SIZE) * AV2_LUMA_INTRA_TILE_SIZE;
        let mut horz_score = 0usize;
        let mut vert_score = 0usize;

        for txb_y in (0..AV2_LUMA_PALETTE_BLOCK_SIZE).step_by(4) {
            for txb_x in (0..AV2_LUMA_PALETTE_BLOCK_SIZE).step_by(4) {
                let txb_x0 = x0 + txb_x;
                let txb_y0 = y0 + txb_y;
                for local_y in 0..4 {
                    for local_x in 0..4 {
                        let x = txb_x0 + local_x;
                        let y = txb_y0 + local_y;
                        let sample = self.chroma_sample(plane, x, y);
                        let horz_pred = if local_x != 0 {
                            self.chroma_sample(plane, x - 1, y)
                        } else if txb_x0 != tile_x0 {
                            self.chroma_sample(plane, txb_x0 - 1, y)
                        } else if txb_y0 != tile_y0 {
                            self.chroma_sample(plane, txb_x0, txb_y0 - 1)
                        } else {
                            129
                        };
                        let vert_pred = if local_y != 0 {
                            self.chroma_sample(plane, x, y - 1)
                        } else if txb_y0 != tile_y0 {
                            self.chroma_sample(plane, x, txb_y0 - 1)
                        } else if txb_x0 != tile_x0 {
                            self.chroma_sample(plane, txb_x0 - 1, txb_y0)
                        } else {
                            127
                        };
                        horz_score += usize::from(sample.abs_diff(horz_pred));
                        vert_score += usize::from(sample.abs_diff(vert_pred));
                    }
                }
            }
        }

        (horz_score, vert_score)
    }

    fn block_for_origin(&self, x0: usize, y0: usize) -> &Av2LumaPaletteBlock444 {
        &self.blocks[self.block_index_for_origin(x0, y0)]
    }

    fn block_index_for_origin(&self, x0: usize, y0: usize) -> usize {
        assert!(x0 < self.width && y0 < self.height);
        assert_eq!(x0 % AV2_LUMA_PALETTE_BLOCK_SIZE, 0);
        assert_eq!(y0 % AV2_LUMA_PALETTE_BLOCK_SIZE, 0);
        let block_x = x0 / AV2_LUMA_PALETTE_BLOCK_SIZE;
        let block_y = y0 / AV2_LUMA_PALETTE_BLOCK_SIZE;
        assert!(block_x < self.blocks_wide && block_y < self.blocks_high);
        block_y * self.blocks_wide + block_x
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
    let u_plane = &frame[plane_len..2 * plane_len];
    let v_plane = &frame[2 * plane_len..3 * plane_len];
    let blocks_wide = geometry.width / AV2_LUMA_PALETTE_BLOCK_SIZE;
    let blocks_high = geometry.height / AV2_LUMA_PALETTE_BLOCK_SIZE;
    let mut blocks = Vec::with_capacity(blocks_wide * blocks_high);
    let mut luma_modes = Vec::with_capacity(blocks_wide * blocks_high);
    let mut luma_prediction = vec![0; plane_len];

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
            let mode = choose_luma_intra_mode(
                y_plane,
                geometry.width,
                x0,
                y0,
                block_x,
                block_y,
                blocks_wide,
                blocks_high,
                &luma_modes,
                &block,
            );
            for local_y in 0..AV2_LUMA_PALETTE_BLOCK_SIZE {
                for local_x in 0..AV2_LUMA_PALETTE_BLOCK_SIZE {
                    let dst_index = (y0 + local_y) * geometry.width + x0 + local_x;
                    luma_prediction[dst_index] = luma_intra_prediction_sample(
                        y_plane,
                        geometry.width,
                        x0,
                        y0,
                        local_x,
                        local_y,
                        &block,
                        mode,
                    );
                }
            }
            luma_modes.push(mode);
            blocks.push(block);
        }
    }
    // AV2 v1.0.0 Sections 5.20.5.5 and 5.20.8.1 code the luma intra mode
    // before optional DC_PRED palette syntax. The residual coefficient path
    // corrects any samples that are not represented exactly by the selected
    // predictor. Keep both the predictor and final reconstruction explicit so
    // high-color screen blocks cannot silently become lossy.
    let reconstruction = frame.to_vec();

    Ok(Av2LumaPalette444 {
        blocks,
        luma_modes,
        y_plane: y_plane.to_vec(),
        luma_prediction,
        u_plane: u_plane.to_vec(),
        v_plane: v_plane.to_vec(),
        reconstruction,
        width: geometry.width,
        height: geometry.height,
        blocks_wide,
        blocks_high,
    })
}

fn choose_luma_intra_mode(
    y_plane: &[u8],
    width: usize,
    x0: usize,
    y0: usize,
    block_x: usize,
    block_y: usize,
    blocks_wide: usize,
    blocks_high: usize,
    previous_modes: &[Av2LumaIntraMode],
    block: &Av2LumaPaletteBlock444,
) -> Av2LumaIntraMode {
    let mut best_mode = Av2LumaIntraMode::Dc;
    let mut best_sad = luma_prediction_sad(y_plane, width, x0, y0, block, best_mode);

    // AV2 tiles are independent in this MVP path. Do not borrow predictors
    // across 64x64 tile boundaries; the decoder has no reconstructed neighbor
    // there.
    let above_mode = (y0 % AV2_LUMA_INTRA_TILE_SIZE != 0)
        .then(|| previous_modes[(block_y - 1) * blocks_wide + block_x]);
    let left_mode = (x0 % AV2_LUMA_INTRA_TILE_SIZE != 0)
        .then(|| previous_modes[block_y * blocks_wide + block_x - 1]);

    // AV2 v1.0.0 Sections 5.20.5.5 and 5.20.5.6, implemented in AVM as
    // get_y_mode_idx_ctx()/get_y_intra_mode_set(), derive the y_mode_idx
    // context and mode list from above-right and bottom-left directional
    // neighbors. This first H/V path writes the non-directional-neighbor
    // context. Until ctx1/ctx2 are implemented, only allow V/H on a terminal
    // 8x8 tile leaf, where the directional mode cannot become a later block's
    // above-right or bottom-left context.
    let fixed_mode_ctx0 = above_mode.map_or(true, |mode| mode == Av2LumaIntraMode::Dc)
        && left_mode.map_or(true, |mode| mode == Av2LumaIntraMode::Dc);
    let terminal_tile_leaf = (block_x + 1 == blocks_wide
        || (x0 + AV2_LUMA_PALETTE_BLOCK_SIZE) % AV2_LUMA_INTRA_TILE_SIZE == 0)
        && (block_y + 1 == blocks_high
            || (y0 + AV2_LUMA_PALETTE_BLOCK_SIZE) % AV2_LUMA_INTRA_TILE_SIZE == 0);
    if fixed_mode_ctx0 && terminal_tile_leaf && above_mode == Some(Av2LumaIntraMode::Dc) {
        let sad = luma_prediction_sad(y_plane, width, x0, y0, block, Av2LumaIntraMode::Vertical);
        if sad + AV2_LUMA_INTRA_MODE_SWITCH_SAD_MARGIN < best_sad {
            best_sad = sad;
            best_mode = Av2LumaIntraMode::Vertical;
        }
    }
    if fixed_mode_ctx0 && terminal_tile_leaf && left_mode == Some(Av2LumaIntraMode::Dc) {
        let sad = luma_prediction_sad(y_plane, width, x0, y0, block, Av2LumaIntraMode::Horizontal);
        if sad + AV2_LUMA_INTRA_MODE_SWITCH_SAD_MARGIN < best_sad {
            best_mode = Av2LumaIntraMode::Horizontal;
        }
    }

    best_mode
}

fn luma_prediction_sad(
    y_plane: &[u8],
    width: usize,
    x0: usize,
    y0: usize,
    block: &Av2LumaPaletteBlock444,
    mode: Av2LumaIntraMode,
) -> usize {
    let mut sad = 0usize;
    for local_y in 0..AV2_LUMA_PALETTE_BLOCK_SIZE {
        for local_x in 0..AV2_LUMA_PALETTE_BLOCK_SIZE {
            let original = y_plane[(y0 + local_y) * width + x0 + local_x];
            let predicted =
                luma_intra_prediction_sample(y_plane, width, x0, y0, local_x, local_y, block, mode);
            sad += usize::from(original.abs_diff(predicted));
        }
    }
    sad
}

fn luma_intra_prediction_sample(
    y_plane: &[u8],
    width: usize,
    x0: usize,
    y0: usize,
    local_x: usize,
    local_y: usize,
    block: &Av2LumaPaletteBlock444,
    mode: Av2LumaIntraMode,
) -> u8 {
    match mode {
        Av2LumaIntraMode::Dc => {
            let local_index = local_y * AV2_LUMA_PALETTE_BLOCK_SIZE + local_x;
            block.colors[usize::from(block.indices[local_index])]
        }
        // AV2 v1.0.0 Section 5.20.7 residual syntax uses 4x4 TXBs here, and
        // AVM calls av2_predict_intra_block() for each TXB. The second 4x4 in
        // an 8x8 H/V leaf therefore predicts from the reconstructed inner
        // edge of the first 4x4, which is exact in this lossless path.
        Av2LumaIntraMode::Vertical => {
            let predictor_y = if local_y >= 4 { y0 + 3 } else { y0 - 1 };
            y_plane[predictor_y * width + x0 + local_x]
        }
        Av2LumaIntraMode::Horizontal => {
            let predictor_x = if local_x >= 4 { x0 + 3 } else { x0 - 1 };
            y_plane[(y0 + local_y) * width + predictor_x]
        }
    }
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
