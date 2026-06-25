use std::io::{Read, Write};

use crate::picture::{Picture, PixelFormat};

pub mod entropy;
mod ibc;
mod palette;
mod syntax;
mod tile;

use ibc::{Av2LocalIbc444, Av2LocalIbcStats};
use palette::Av2LumaPalette444;
use syntax::{Av2SyntaxPayload, Av2SyntaxWriter};
use tile::{
    av2_black_444_tile_entropy_payload_for_region, av2_black_tile_entropy_payload_for_region,
    av2_lossy_420_tile_entropy_payload_for_region,
    av2_luma_palette_444_tile_entropy_payload_for_region, Av2TileRegion,
};

pub const AV2_CODEC_NAME: &str = "av2";
pub const AV2_BITSTREAM_EXTENSION: &str = "av2";
pub const AV2_FIXED_BLACK_444_WIDTH: usize = 64;
pub const AV2_FIXED_BLACK_444_HEIGHT: usize = 64;

const AV2_PROFILE_BITS: u8 = 5;
const AV2_LEVEL_BITS: u8 = 5;
const AV2_SEQUENCE_PROFILE_CONFIGURABLE: u8 = 4;
const AV2_SEQUENCE_LEVEL_2_0: u8 = 0;
const AV2_CHROMA_FORMAT_420: u32 = 0;
const AV2_CHROMA_FORMAT_444: u32 = 2;
const AV2_BITDEPTH_INDEX_8BIT: u32 = 1;
const AV2_DELTA_DCQUANT_MIN: i8 = -23;
const AV2_MAX_MAX_IBC_DRL_BITS_MINUS_MIN_PLUS_ONE: u16 = 3;
const AV2_MVP_SUPERBLOCK_SIZE: usize = 64;
const AV2_TILE_SIZE_BYTES: usize = 4;
const AV2_MIN_TILE_SIZE_BYTES: usize = 1;
const AV2_MI_SIZE: usize = 4;
const AV2_MIB_SIZE_LOG2_64X64: u8 = 4;
const AV2_SEQ_MIB_SIZE_LOG2_64X64: u8 = 4;
const AV2_MAX_TILE_WIDTH: usize = 4096;
const AV2_MAX_TILE_AREA: usize = 4096 * 2304;
const AV2_MAX_TILE_COLS: usize = 64;
const AV2_MAX_TILE_ROWS: usize = 64;
const AV2_TILE_WIDTH_SCALING_LEVEL_2_0_TIER_0: usize = 4;
const AV2_TILE_AREA_SCALING_LEVEL_2_0_TIER_0: usize = 4;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Av2ChromaFormat {
    Yuv420,
    Yuv444,
}

impl Av2ChromaFormat {
    fn from_pixel_format(format: PixelFormat) -> Option<Self> {
        match format {
            PixelFormat::Yuv420p8 => Some(Self::Yuv420),
            PixelFormat::Yuv444p8 => Some(Self::Yuv444),
            _ => None,
        }
    }

    fn sequence_header_idc(self) -> u32 {
        match self {
            // AV2 v1.0.0 av2/common/blockd.h: CHROMA_FORMAT_420 is coded as
            // zero. This differs from the project-level AXI chroma_format_idc
            // register convention, which follows the older 1/2/3 sampling IDs.
            Self::Yuv420 => AV2_CHROMA_FORMAT_420,
            Self::Yuv444 => AV2_CHROMA_FORMAT_444,
        }
    }

    fn pixel_format(self) -> PixelFormat {
        match self {
            Self::Yuv420 => PixelFormat::Yuv420p8,
            Self::Yuv444 => PixelFormat::Yuv444p8,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Av2Black444MvpProfile {
    enable_sdp: bool,
    enable_ext_partitions: bool,
    enable_uneven_4way_partitions: bool,
    enable_intra_edge_filter: bool,
    enable_mrls: bool,
    enable_cfl_intra: bool,
    enable_mhccp: bool,
    enable_ibp: bool,
    enable_refmvbank: bool,
    is_drl_reorder_disable: bool,
    def_max_bvp_drl_bits_minus_min: u16,
    allow_frame_max_bvp_drl_bits: bool,
    enable_bawp: bool,
    enable_fsc: bool,
    enable_idtx_intra: bool,
    enable_chroma_dctonly: bool,
    enable_cctx: bool,
    disable_cdf_update: bool,
}

impl Av2Black444MvpProfile {
    fn current() -> Self {
        Self {
            // Keep the first tile payload on the shared luma/chroma tree. AVM
            // decode_partition() enters separate luma/chroma trees at 64x64
            // when SDP is enabled, which is unnecessary for the first black
            // 4:4:4 bring-up stream.
            enable_sdp: false,
            enable_ext_partitions: false,
            enable_uneven_4way_partitions: false,
            enable_intra_edge_filter: false,
            enable_mrls: false,
            enable_cfl_intra: false,
            enable_mhccp: false,
            enable_ibp: false,
            enable_refmvbank: false,
            is_drl_reorder_disable: true,
            def_max_bvp_drl_bits_minus_min: 0,
            allow_frame_max_bvp_drl_bits: false,
            enable_bawp: false,
            enable_fsc: false,
            // AVM read_sequence_transform_quant_entropy_group_tool_flags()
            // sets IDTX from this bit only when FSC is disabled.
            enable_idtx_intra: true,
            enable_chroma_dctonly: false,
            enable_cctx: false,
            // AV2 v1.0.0 tile_group_obu() calls init_symbol(tileSize) before
            // decode_tile(). Disabling CDF updates keeps this first generated
            // stream independent from traversal history while block syntax is
            // being ported.
            disable_cdf_update: true,
        }
    }

    fn with_local_ibc_candidates(mut self) -> Self {
        // AVM derives above/left 8x8 block vectors as default IntraBC BV
        // candidates 2 and 3 in mvref_common.c. AV2 sequence syntax stores
        // max_bvp_drl_bits minus MIN_MAX_IBC_DRL_BITS; value 2 therefore
        // permits DRL indices 0..3 without frame-level overrides.
        self.def_max_bvp_drl_bits_minus_min = 2;
        self
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Av2ObuType {
    SequenceHeader = 1,
    TemporalDelimiter = 2,
    ClosedLoopKey = 4,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Av2VideoGeometry {
    pub width: usize,
    pub height: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct Av2TileLayout {
    regions: Vec<Av2TileRegion>,
    cols: usize,
    rows: usize,
    log2_cols: u8,
    log2_rows: u8,
    min_log2_cols: u8,
    min_log2_rows: u8,
    max_log2_cols: u8,
    max_log2_rows: u8,
}

impl Av2TileLayout {
    fn for_geometry(geometry: Av2VideoGeometry) -> Self {
        let cols = geometry.width.div_ceil(AV2_MVP_SUPERBLOCK_SIZE);
        let rows = geometry.height.div_ceil(AV2_MVP_SUPERBLOCK_SIZE);
        let mut regions = Vec::with_capacity(cols * rows);
        for tile_row in 0..rows {
            let origin_y = tile_row * AV2_MVP_SUPERBLOCK_SIZE;
            let height = (geometry.height - origin_y).min(AV2_MVP_SUPERBLOCK_SIZE);
            for tile_col in 0..cols {
                let origin_x = tile_col * AV2_MVP_SUPERBLOCK_SIZE;
                let width = (geometry.width - origin_x).min(AV2_MVP_SUPERBLOCK_SIZE);
                regions.push(Av2TileRegion {
                    origin_x,
                    origin_y,
                    width,
                    height,
                });
            }
        }
        let limits = Av2TileLimits::for_geometry(geometry);
        let log2_cols = ceil_log2_usize(cols).max(limits.min_log2_cols);
        let min_log2_rows = limits.min_log2.saturating_sub(log2_cols);
        let log2_rows = ceil_log2_usize(rows).max(min_log2_rows);
        assert!(
            log2_cols <= limits.max_log2_cols,
            "AV2 MVP tile columns exceed the Level 2.0 tile limit"
        );
        assert!(
            log2_rows <= limits.max_log2_rows,
            "AV2 MVP tile rows exceed the Level 2.0 tile limit"
        );
        Self {
            regions,
            cols,
            rows,
            log2_cols,
            log2_rows,
            min_log2_cols: limits.min_log2_cols,
            min_log2_rows,
            max_log2_cols: limits.max_log2_cols,
            max_log2_rows: limits.max_log2_rows,
        }
    }

    fn tile_count(&self) -> usize {
        self.regions.len()
    }

    fn is_single_tile(&self) -> bool {
        self.tile_count() == 1
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Av2TileLimits {
    min_log2_cols: u8,
    max_log2_cols: u8,
    max_log2_rows: u8,
    min_log2: u8,
}

impl Av2TileLimits {
    fn for_geometry(geometry: Av2VideoGeometry) -> Self {
        assert!(
            AV2_SEQ_MIB_SIZE_LOG2_64X64 >= AV2_MIB_SIZE_LOG2_64X64
                && AV2_SEQ_MIB_SIZE_LOG2_64X64 - AV2_MIB_SIZE_LOG2_64X64 <= 1,
            "AV2 MVP only supports the AVM tile-limit scale used by 64x64 sequence superblocks"
        );
        let mi_cols = align_power_of_two(geometry.width, 3) / AV2_MI_SIZE;
        let mi_rows = align_power_of_two(geometry.height, 3) / AV2_MI_SIZE;
        let aligned_mi_cols = align_power_of_two(mi_cols, AV2_MIB_SIZE_LOG2_64X64 as usize);
        let aligned_mi_rows = align_power_of_two(mi_rows, AV2_MIB_SIZE_LOG2_64X64 as usize);
        let sb_cols = aligned_mi_cols >> AV2_MIB_SIZE_LOG2_64X64;
        let sb_rows = aligned_mi_rows >> AV2_MIB_SIZE_LOG2_64X64;
        let sb_size_log2 = AV2_MIB_SIZE_LOG2_64X64 + 2;
        let max_width_sb =
            (AV2_TILE_WIDTH_SCALING_LEVEL_2_0_TIER_0 * AV2_MAX_TILE_WIDTH) >> (sb_size_log2 + 2);
        let max_area_sb = (AV2_TILE_AREA_SCALING_LEVEL_2_0_TIER_0 * AV2_MAX_TILE_AREA)
            >> ((2 * sb_size_log2) + 2);
        let min_log2_cols = tile_log2(max_width_sb, sb_cols);
        let max_log2_cols = tile_log2(1, sb_cols.min(AV2_MAX_TILE_COLS));
        let max_log2_rows = tile_log2(1, sb_rows.min(AV2_MAX_TILE_ROWS));
        let min_log2 = tile_log2(max_area_sb, sb_cols * sb_rows).max(min_log2_cols);
        Self {
            min_log2_cols,
            max_log2_cols,
            max_log2_rows,
            min_log2,
        }
    }
}

fn align_power_of_two(value: usize, power: usize) -> usize {
    let alignment = 1usize << power;
    (value + alignment - 1) & !(alignment - 1)
}

fn tile_log2(block_size: usize, target: usize) -> u8 {
    assert!(block_size > 0);
    assert!(target > 0);
    let mut log2 = 0u8;
    while (block_size << log2) < target {
        log2 += 1;
    }
    log2
}

fn ceil_log2_usize(value: usize) -> u8 {
    assert!(value > 0);
    let mut bits = 0u8;
    let mut threshold = 1usize;
    while threshold < value {
        threshold <<= 1;
        bits += 1;
    }
    bits
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Av2EncodeParams {
    pub frames: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Av2EncodeRequest {
    pub params: Av2EncodeParams,
    pub geometry: Av2VideoGeometry,
    pub format: PixelFormat,
}

impl Av2EncodeRequest {
    pub fn validate(&self) -> Result<(), String> {
        if self.geometry.width == 0 || self.geometry.height == 0 {
            return Err("AV2 encode expects positive dimensions".to_string());
        }
        if self.params.frames == 0 {
            return Err("AV2 encode expects at least one frame".to_string());
        }
        if !self.format.is_yuv() {
            return Err(format!(
                "AV2 encode expects planar YUV input; got {}",
                self.format
            ));
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum Av2Mvp444FrameMode {
    Black,
    LumaPalette {
        palette: Av2LumaPalette444,
        ibc: Av2LocalIbc444,
    },
}

impl Av2Mvp444FrameMode {
    fn from_frame(frame: &[u8], geometry: Av2VideoGeometry) -> Result<Self, String> {
        let black = av2_black_444_reconstruction_for_geometry(geometry);
        if frame == black {
            return Ok(Self::Black);
        }
        Ok(Self::LumaPalette {
            palette: palette::build_luma_palette_444(frame, geometry)?,
            ibc: ibc::build_local_ibc_444(frame, geometry)?,
        })
    }

    fn allow_screen_content_tools(&self) -> bool {
        matches!(self, Self::LumaPalette { .. })
    }

    fn allow_intrabc(&self) -> bool {
        matches!(self, Self::LumaPalette { .. })
    }

    fn profile(&self) -> Av2Black444MvpProfile {
        let profile = Av2Black444MvpProfile::current();
        if self.allow_intrabc() {
            profile.with_local_ibc_candidates()
        } else {
            profile
        }
    }

    fn reconstruction(&self, geometry: Av2VideoGeometry) -> Vec<u8> {
        match self {
            Self::Black => av2_black_444_reconstruction_for_geometry(geometry),
            Self::LumaPalette { palette, .. } => palette.reconstruction().to_vec(),
        }
    }
}

pub fn av2_encode_fixed_black_444(
    input: &mut dyn Read,
    output: &mut dyn Write,
    recon: Option<&mut dyn Write>,
    request: Av2EncodeRequest,
) -> Result<(), String> {
    request.validate()?;
    let geometry = validate_mvp_request(request)?;
    let chroma_format = Av2ChromaFormat::from_pixel_format(request.format)
        .expect("validate_mvp_request accepts only supported AV2 chroma formats");

    let expected_len = Picture::expected_len(geometry.width, geometry.height, request.format);
    let mut frame = vec![0; expected_len];
    input
        .read_exact(&mut frame)
        .map_err(|err| format!("failed to read AV2 MVP input frame: {err}"))?;
    if chroma_format == Av2ChromaFormat::Yuv420 {
        let black = av2_black_reconstruction_for_geometry(geometry, chroma_format);
        let (bitstream, reconstruction) = if frame == black {
            (
                av2_black_bitstream_for_geometry(geometry, chroma_format),
                black,
            )
        } else {
            av2_lossy_420_bitstream_and_reconstruction_for_frame(geometry, &frame)
        };
        output
            .write_all(&bitstream)
            .map_err(|err| format!("failed to write AV2 bitstream: {err}"))?;
        if let Some(recon) = recon {
            recon
                .write_all(&reconstruction)
                .map_err(|err| format!("failed to write AV2 reconstruction: {err}"))?;
        }
        return Ok(());
    }

    let frame_mode = Av2Mvp444FrameMode::from_frame(&frame, geometry)?;

    let bitstream = av2_mvp_444_bitstream_for_mode(geometry, &frame_mode);
    output
        .write_all(&bitstream)
        .map_err(|err| format!("failed to write AV2 bitstream: {err}"))?;
    if let Some(recon) = recon {
        let reconstruction = frame_mode.reconstruction(geometry);
        recon
            .write_all(&reconstruction)
            .map_err(|err| format!("failed to write AV2 reconstruction: {err}"))?;
    }
    Ok(())
}

#[cfg(test)]
fn av2_black_444_bitstream_for_geometry(geometry: Av2VideoGeometry) -> Vec<u8> {
    av2_black_bitstream_for_geometry(geometry, Av2ChromaFormat::Yuv444)
}

fn av2_black_bitstream_for_geometry(
    geometry: Av2VideoGeometry,
    chroma_format: Av2ChromaFormat,
) -> Vec<u8> {
    let mut out = Vec::new();
    append_obu(
        &mut out,
        Av2ObuType::TemporalDelimiter,
        &Av2SyntaxPayload::default(),
    );
    append_obu(
        &mut out,
        Av2ObuType::SequenceHeader,
        &av2_mvp_sequence_header_payload(geometry, Av2Black444MvpProfile::current(), chroma_format),
    );
    append_obu(
        &mut out,
        Av2ObuType::ClosedLoopKey,
        &av2_black_closed_loop_key_payload(geometry, chroma_format),
    );
    out
}

fn av2_lossy_420_bitstream_and_reconstruction_for_frame(
    geometry: Av2VideoGeometry,
    frame: &[u8],
) -> (Vec<u8>, Vec<u8>) {
    let expected_len =
        Picture::expected_len(geometry.width, geometry.height, PixelFormat::Yuv420p8);
    assert_eq!(
        frame.len(),
        expected_len,
        "AV2 4:2:0 lossy input length must match geometry"
    );
    let mut reconstruction = vec![0; expected_len];
    let mut out = Vec::new();
    append_obu(
        &mut out,
        Av2ObuType::TemporalDelimiter,
        &Av2SyntaxPayload::default(),
    );
    append_obu(
        &mut out,
        Av2ObuType::SequenceHeader,
        &av2_mvp_sequence_header_payload(
            geometry,
            Av2Black444MvpProfile::current(),
            Av2ChromaFormat::Yuv420,
        ),
    );
    append_obu(
        &mut out,
        Av2ObuType::ClosedLoopKey,
        &av2_lossy_420_closed_loop_key_payload(geometry, frame, &mut reconstruction),
    );
    (out, reconstruction)
}

fn av2_mvp_444_bitstream_for_mode(
    geometry: Av2VideoGeometry,
    frame_mode: &Av2Mvp444FrameMode,
) -> Vec<u8> {
    let mut out = Vec::new();
    append_obu(
        &mut out,
        Av2ObuType::TemporalDelimiter,
        &Av2SyntaxPayload::default(),
    );
    append_obu(
        &mut out,
        Av2ObuType::SequenceHeader,
        &av2_mvp_444_sequence_header_payload(geometry, frame_mode.profile()),
    );
    append_obu(
        &mut out,
        Av2ObuType::ClosedLoopKey,
        &av2_mvp_444_closed_loop_key_payload(geometry, frame_mode),
    );
    out
}

pub fn av2_mvp_444_trace_jsonl_for_frame(
    frame: &[u8],
    request: Av2EncodeRequest,
) -> Result<String, String> {
    request.validate()?;
    let geometry = validate_mvp_request(request)?;
    let chroma_format = Av2ChromaFormat::from_pixel_format(request.format)
        .expect("validate_mvp_request accepts only supported AV2 chroma formats");
    if chroma_format == Av2ChromaFormat::Yuv420 {
        let black = av2_black_reconstruction_for_geometry(geometry, chroma_format);
        if frame != black {
            return av2_lossy_420_trace_jsonl_for_frame(geometry, frame);
        }
        return av2_black_trace_jsonl_for_chroma_format(geometry, chroma_format);
    }
    let frame_mode = Av2Mvp444FrameMode::from_frame(frame, geometry)?;
    av2_mvp_444_trace_jsonl_for_mode(geometry, &frame_mode)
}

pub fn av2_mvp_444_ibc_stats_json_for_frame(
    frame: &[u8],
    request: Av2EncodeRequest,
) -> Result<String, String> {
    request.validate()?;
    let geometry = validate_mvp_request(request)?;
    let chroma_format = Av2ChromaFormat::from_pixel_format(request.format)
        .expect("validate_mvp_request accepts only supported AV2 chroma formats");
    if chroma_format != Av2ChromaFormat::Yuv444 {
        return Err(format!(
            "AV2 IBC stats expect yuv444p8 input; got {}",
            request.format
        ));
    }

    let frame_mode = Av2Mvp444FrameMode::from_frame(frame, geometry)?;
    let (black_mode, allow_intrabc, stats) = match &frame_mode {
        Av2Mvp444FrameMode::Black => (true, false, Av2LocalIbcStats::default()),
        Av2Mvp444FrameMode::LumaPalette { ibc, .. } => (false, true, ibc.stats()),
    };

    Ok(format!(
        concat!(
            "{{\n",
            "  \"codec\": \"av2\",\n",
            "  \"tool\": \"local_hash_ibc\",\n",
            "  \"width\": {},\n",
            "  \"height\": {},\n",
            "  \"format\": \"{}\",\n",
            "  \"black_mode\": {},\n",
            "  \"allow_intrabc\": {},\n",
            "  \"total_blocks\": {},\n",
            "  \"blocks_with_above_in_tile\": {},\n",
            "  \"blocks_with_left_in_tile\": {},\n",
            "  \"fixed_drl_supported_blocks\": {},\n",
            "  \"raw_above_hash_matches\": {},\n",
            "  \"raw_left_hash_matches\": {},\n",
            "  \"direct_above_hash_matches\": {},\n",
            "  \"direct_left_hash_matches\": {},\n",
            "  \"above_hash_matches_blocked_by_fixed_drl_guard\": {},\n",
            "  \"left_hash_matches_blocked_by_fixed_drl_guard\": {},\n",
            "  \"above_hash_matches_blocked_by_copied_candidate\": {},\n",
            "  \"left_hash_matches_blocked_by_copied_candidate\": {},\n",
            "  \"selected_above_copy_blocks\": {},\n",
            "  \"selected_left_copy_blocks\": {},\n",
            "  \"selected_copy_blocks\": {}\n",
            "}}\n"
        ),
        geometry.width,
        geometry.height,
        request.format,
        black_mode,
        allow_intrabc,
        stats.total_blocks,
        stats.blocks_with_above_in_tile,
        stats.blocks_with_left_in_tile,
        stats.fixed_drl_supported_blocks,
        stats.raw_above_hash_matches,
        stats.raw_left_hash_matches,
        stats.direct_above_hash_matches,
        stats.direct_left_hash_matches,
        stats.above_hash_matches_blocked_by_fixed_drl_guard,
        stats.left_hash_matches_blocked_by_fixed_drl_guard,
        stats.above_hash_matches_blocked_by_copied_candidate,
        stats.left_hash_matches_blocked_by_copied_candidate,
        stats.selected_above_copy_blocks,
        stats.selected_left_copy_blocks,
        stats.selected_copy_blocks(),
    ))
}

pub fn av2_black_444_trace_jsonl(request: Av2EncodeRequest) -> Result<String, String> {
    request.validate()?;
    let geometry = validate_fixed_black_444_request(request)?;
    av2_mvp_444_trace_jsonl_for_mode(geometry, &Av2Mvp444FrameMode::Black)
}

fn av2_mvp_444_trace_jsonl_for_mode(
    geometry: Av2VideoGeometry,
    frame_mode: &Av2Mvp444FrameMode,
) -> Result<String, String> {
    let tile_layout = Av2TileLayout::for_geometry(geometry);
    let sequence = av2_mvp_444_sequence_header_payload(geometry, frame_mode.profile());
    let closed_loop_header = av2_mvp_444_closed_loop_key_header_payload(
        frame_mode.allow_screen_content_tools(),
        frame_mode.allow_intrabc(),
        &tile_layout,
    );
    let entropy = av2_tile_entropy_payloads_for_mode(&tile_layout, frame_mode);
    let mut lines = String::new();

    push_av2_trace_line(
        &mut lines,
        "obu",
        "obu.temporal_delimiter",
        "AV2 v1.0.0 Section 5.4 OBU syntax",
        "header+payload",
        0,
        16,
    );
    for field in &sequence.fields {
        push_av2_trace_line(
            &mut lines,
            "sequence_header",
            field.name,
            av2_spec_section_for_syntax_field(field.name),
            &format!("{:?}", field.code),
            field.bit_offset,
            field.bit_count,
        );
    }
    push_av2_trace_line(
        &mut lines,
        "obu",
        "obu.closed_loop_key",
        "AV2 v1.0.0 Sections 5.19 and 5.20.1 tile group syntax",
        "header",
        0,
        8,
    );
    for field in &closed_loop_header.fields {
        push_av2_trace_line(
            &mut lines,
            "closed_loop_key_header",
            field.name,
            av2_spec_section_for_syntax_field(field.name),
            &format!("{:?}", field.code),
            field.bit_offset,
            field.bit_count,
        );
    }
    for (tile_index, entropy) in entropy.iter().enumerate() {
        for field in &entropy.fields {
            push_av2_entropy_trace_line(&mut lines, tile_index, field);
        }
    }
    Ok(lines)
}

fn av2_black_trace_jsonl_for_chroma_format(
    geometry: Av2VideoGeometry,
    chroma_format: Av2ChromaFormat,
) -> Result<String, String> {
    let tile_layout = Av2TileLayout::for_geometry(geometry);
    let profile = Av2Black444MvpProfile::current();
    let sequence = av2_mvp_sequence_header_payload(geometry, profile, chroma_format);
    let closed_loop_header = av2_mvp_444_closed_loop_key_header_payload(false, false, &tile_layout);
    let entropy: Vec<_> = tile_layout
        .regions
        .iter()
        .map(|&region| av2_black_tile_entropy_payload_for_region(region, profile, chroma_format))
        .collect();
    let mut lines = String::new();

    push_av2_trace_line(
        &mut lines,
        "obu",
        "obu.temporal_delimiter",
        "AV2 v1.0.0 Section 5.4 OBU syntax",
        "header+payload",
        0,
        16,
    );
    for field in &sequence.fields {
        push_av2_trace_line(
            &mut lines,
            "sequence_header",
            field.name,
            av2_spec_section_for_syntax_field(field.name),
            &format!("{:?}", field.code),
            field.bit_offset,
            field.bit_count,
        );
    }
    push_av2_trace_line(
        &mut lines,
        "obu",
        "obu.closed_loop_key",
        "AV2 v1.0.0 Sections 5.19 and 5.20.1 tile group syntax",
        "header",
        0,
        8,
    );
    for field in &closed_loop_header.fields {
        push_av2_trace_line(
            &mut lines,
            "closed_loop_key_header",
            field.name,
            av2_spec_section_for_syntax_field(field.name),
            &format!("{:?}", field.code),
            field.bit_offset,
            field.bit_count,
        );
    }
    for (tile_index, entropy) in entropy.iter().enumerate() {
        for field in &entropy.fields {
            push_av2_entropy_trace_line(&mut lines, tile_index, field);
        }
    }
    Ok(lines)
}

fn av2_lossy_420_trace_jsonl_for_frame(
    geometry: Av2VideoGeometry,
    frame: &[u8],
) -> Result<String, String> {
    let expected_len =
        Picture::expected_len(geometry.width, geometry.height, PixelFormat::Yuv420p8);
    if frame.len() != expected_len {
        return Err(format!(
            "AV2 yuv420p8 trace input length mismatch: expected {expected_len}, got {}",
            frame.len()
        ));
    }
    let tile_layout = Av2TileLayout::for_geometry(geometry);
    let profile = Av2Black444MvpProfile::current();
    let sequence = av2_mvp_sequence_header_payload(geometry, profile, Av2ChromaFormat::Yuv420);
    let closed_loop_header = av2_mvp_444_closed_loop_key_header_payload(false, false, &tile_layout);
    let mut reconstruction = vec![0; expected_len];
    let entropy: Vec<_> = tile_layout
        .regions
        .iter()
        .map(|&region| {
            av2_lossy_420_tile_entropy_payload_for_region(
                region,
                profile,
                geometry,
                frame,
                &mut reconstruction,
            )
        })
        .collect();
    let mut lines = String::new();

    push_av2_trace_line(
        &mut lines,
        "obu",
        "obu.temporal_delimiter",
        "AV2 v1.0.0 Section 5.4 OBU syntax",
        "header+payload",
        0,
        16,
    );
    for field in &sequence.fields {
        push_av2_trace_line(
            &mut lines,
            "sequence_header",
            field.name,
            av2_spec_section_for_syntax_field(field.name),
            &format!("{:?}", field.code),
            field.bit_offset,
            field.bit_count,
        );
    }
    push_av2_trace_line(
        &mut lines,
        "obu",
        "obu.closed_loop_key",
        "AV2 v1.0.0 Sections 5.19 and 5.20.1 tile group syntax",
        "header",
        0,
        8,
    );
    for field in &closed_loop_header.fields {
        push_av2_trace_line(
            &mut lines,
            "closed_loop_key_header",
            field.name,
            av2_spec_section_for_syntax_field(field.name),
            &format!("{:?}", field.code),
            field.bit_offset,
            field.bit_count,
        );
    }
    for (tile_index, entropy) in entropy.iter().enumerate() {
        for field in &entropy.fields {
            push_av2_entropy_trace_line(&mut lines, tile_index, field);
        }
    }
    Ok(lines)
}

pub fn av2_black_64x64_444_reconstruction() -> Vec<u8> {
    av2_black_444_reconstruction_for_geometry(Av2VideoGeometry {
        width: 64,
        height: 64,
    })
}

pub fn av2_black_444_reconstruction(geometry: Av2VideoGeometry) -> Option<Vec<u8>> {
    validate_fixed_black_444_geometry(geometry).map(av2_black_444_reconstruction_for_geometry)
}

fn av2_black_444_reconstruction_for_geometry(geometry: Av2VideoGeometry) -> Vec<u8> {
    av2_black_reconstruction_for_geometry(geometry, Av2ChromaFormat::Yuv444)
}

fn av2_black_reconstruction_for_geometry(
    geometry: Av2VideoGeometry,
    chroma_format: Av2ChromaFormat,
) -> Vec<u8> {
    vec![
        0;
        Picture::expected_len(
            geometry.width,
            geometry.height,
            chroma_format.pixel_format(),
        )
    ]
}

fn validate_fixed_black_444_request(request: Av2EncodeRequest) -> Result<Av2VideoGeometry, String> {
    let geometry = validate_mvp_444_request(request)?;
    Ok(geometry)
}

fn validate_mvp_444_request(request: Av2EncodeRequest) -> Result<Av2VideoGeometry, String> {
    let geometry = validate_mvp_request(request)?;
    if request.format != PixelFormat::Yuv444p8 {
        return Err("AV2 4:4:4 MVP path only supports yuv444p8".to_string());
    }
    Ok(geometry)
}

fn validate_mvp_request(request: Av2EncodeRequest) -> Result<Av2VideoGeometry, String> {
    if request.params.frames != 1 || Av2ChromaFormat::from_pixel_format(request.format).is_none() {
        return Err(
            "AV2 MVP encoder only supports one yuv420p8 or yuv444p8 frame at 8-pixel geometry"
                .to_string(),
        );
    }
    validate_fixed_black_444_geometry(request.geometry)
        .ok_or_else(|| "AV2 MVP encoder only supports dimensions in 8-pixel steps".to_string())
}

fn validate_fixed_black_444_geometry(geometry: Av2VideoGeometry) -> Option<Av2VideoGeometry> {
    let supported = geometry.width >= 8
        && geometry.height >= 8
        && geometry.width % 8 == 0
        && geometry.height % 8 == 0;
    supported.then_some(geometry)
}

#[cfg(test)]
fn av2_black_444_sequence_header_payload(geometry: Av2VideoGeometry) -> Av2SyntaxPayload {
    av2_mvp_444_sequence_header_payload(geometry, Av2Black444MvpProfile::current())
}

fn av2_mvp_444_sequence_header_payload(
    geometry: Av2VideoGeometry,
    profile: Av2Black444MvpProfile,
) -> Av2SyntaxPayload {
    av2_mvp_sequence_header_payload(geometry, profile, Av2ChromaFormat::Yuv444)
}

fn av2_mvp_sequence_header_payload(
    geometry: Av2VideoGeometry,
    profile: Av2Black444MvpProfile,
    chroma_format: Av2ChromaFormat,
) -> Av2SyntaxPayload {
    let mut writer = Av2SyntaxWriter::new();
    let width_bits = av2_frame_dimension_bits(geometry.width);
    let height_bits = av2_frame_dimension_bits(geometry.height);

    // AV2 v1.0.0 sequence_header_obu(), mirrored from AVM
    // av2_write_sequence_header_obu().
    writer.write_uvlc("sequence_header.seq_header_id", 0);
    writer.write_literal(
        "sequence_header.seq_profile_idc",
        AV2_SEQUENCE_PROFILE_CONFIGURABLE as u64,
        AV2_PROFILE_BITS,
    );
    writer.write_flag("sequence_header.single_picture_header_flag", true);
    writer.write_literal(
        "sequence_header.seq_max_level_idx",
        AV2_SEQUENCE_LEVEL_2_0 as u64,
        AV2_LEVEL_BITS,
    );
    writer.write_uvlc(
        "sequence_header.seq_chroma_format_idc",
        chroma_format.sequence_header_idc(),
    );
    writer.write_uvlc("sequence_header.bitdepth_lut_idx", AV2_BITDEPTH_INDEX_8BIT);
    writer.write_literal(
        "sequence_header.num_bits_width_minus_1",
        (width_bits - 1) as u64,
        4,
    );
    writer.write_literal(
        "sequence_header.num_bits_height_minus_1",
        (height_bits - 1) as u64,
        4,
    );
    writer.write_literal(
        "sequence_header.max_frame_width_minus_1",
        (geometry.width - 1) as u64,
        width_bits,
    );
    writer.write_literal(
        "sequence_header.max_frame_height_minus_1",
        (geometry.height - 1) as u64,
        height_bits,
    );
    writer.write_flag("sequence_header.conf_win_enabled_flag", false);

    write_fixed_black_444_sequence_tools(&mut writer, profile);

    writer.write_flag("sequence_header.film_grain_params_present", false);
    writer.write_flag("sequence_header.seq_extension_present_flag", false);
    writer.trailing_bits();
    writer.finish()
}

fn av2_frame_dimension_bits(dimension: usize) -> u8 {
    assert!(dimension > 0, "AV2 frame dimension must be positive");
    let max_index = (dimension - 1) as u64;
    (64 - max_index.leading_zeros()) as u8
}

fn write_fixed_black_444_sequence_tools(
    writer: &mut Av2SyntaxWriter,
    profile: Av2Black444MvpProfile,
) {
    // AV2 v1.0.0 sequence_header() tool groups, mirrored from AVM
    // write_sequence_header(). Values are the fixed AVM choices for one
    // black yuv444p8 still picture in the minimum viable bitstream subset.
    writer.write_flag("sequence_partition.sb_size_is_256", false);
    writer.write_flag("sequence_partition.sb_size_is_128", false);
    writer.write_flag("sequence_partition.enable_sdp", profile.enable_sdp);
    writer.write_flag(
        "sequence_partition.enable_ext_partitions",
        profile.enable_ext_partitions,
    );
    if profile.enable_ext_partitions {
        writer.write_flag(
            "sequence_partition.enable_uneven_4way_partitions",
            profile.enable_uneven_4way_partitions,
        );
    }
    writer.write_flag("sequence_partition.max_pb_aspect_ratio_lt2", false);

    writer.write_flag("sequence_segment.enable_ext_seg", false);
    writer.write_flag("sequence_segment.seq_seg_info_present_flag", false);

    writer.write_flag("sequence_intra.enable_intra_dip", false);
    writer.write_flag(
        "sequence_intra.enable_intra_edge_filter",
        profile.enable_intra_edge_filter,
    );
    writer.write_flag("sequence_intra.enable_mrls", profile.enable_mrls);
    writer.write_flag("sequence_intra.enable_cfl_intra", profile.enable_cfl_intra);
    writer.write_literal("sequence_intra.cfl_ds_filter_index", 0, 2);
    writer.write_flag("sequence_intra.enable_mhccp", profile.enable_mhccp);
    writer.write_flag("sequence_intra.enable_ibp", profile.enable_ibp);

    writer.write_flag("sequence_inter.enable_refmvbank", profile.enable_refmvbank);
    writer.write_flag(
        "sequence_inter.is_drl_reorder_disable",
        profile.is_drl_reorder_disable,
    );
    if !profile.is_drl_reorder_disable {
        writer.write_flag("sequence_inter.enable_drl_reorder_constraint", false);
    }
    writer.write_quniform(
        "sequence_inter.def_max_bvp_drl_bits_minus_min",
        AV2_MAX_MAX_IBC_DRL_BITS_MINUS_MIN_PLUS_ONE,
        profile.def_max_bvp_drl_bits_minus_min,
    );
    writer.write_flag(
        "sequence_inter.allow_frame_max_bvp_drl_bits",
        profile.allow_frame_max_bvp_drl_bits,
    );
    writer.write_flag("sequence_inter.enable_bawp", profile.enable_bawp);

    writer.write_flag("sequence_transform.enable_fsc", profile.enable_fsc);
    if !profile.enable_fsc {
        writer.write_flag(
            "sequence_transform.enable_idtx_intra",
            profile.enable_idtx_intra,
        );
    }
    writer.write_flag("sequence_transform.enable_ist", false);
    writer.write_flag("sequence_transform.enable_inter_ist", false);
    writer.write_flag(
        "sequence_transform.enable_chroma_dctonly",
        profile.enable_chroma_dctonly,
    );
    writer.write_flag("sequence_transform.reduced_tx_part_set", false);
    writer.write_flag("sequence_transform.enable_cctx", profile.enable_cctx);
    writer.write_flag("sequence_transform.enable_tcq_nonzero", false);
    writer.write_flag("sequence_transform.enable_parity_hiding", false);
    writer.write_flag("sequence_transform.separate_uv_delta_q", false);
    writer.write_flag("sequence_transform.equal_ac_dc_q", true);
    writer.write_literal(
        "sequence_transform.base_uv_ac_delta_q_minus_min",
        (0 - AV2_DELTA_DCQUANT_MIN as i16) as u64,
        5,
    );
    writer.write_flag("sequence_transform.uv_ac_delta_q_enabled", false);

    writer.write_flag("sequence_filter.disable_loopfilters_across_tiles", false);
    writer.write_flag("sequence_filter.enable_cdef", false);
    writer.write_flag("sequence_filter.enable_gdf", false);
    writer.write_flag("sequence_filter.enable_restoration", false);
    writer.write_flag("sequence_filter.enable_ccso", false);
    writer.write_literal("sequence_filter.df_par_bits_minus2", 1, 2);

    writer.write_flag("sequence_tile_config.seq_tile_info_present_flag", false);
}

#[cfg(test)]
fn av2_black_444_closed_loop_key_header_payload() -> Av2SyntaxPayload {
    av2_mvp_444_closed_loop_key_header_payload(
        false,
        false,
        &Av2TileLayout::for_geometry(Av2VideoGeometry {
            width: 64,
            height: 64,
        }),
    )
}

fn av2_mvp_444_closed_loop_key_header_payload(
    allow_screen_content_tools: bool,
    allow_intrabc: bool,
    tile_layout: &Av2TileLayout,
) -> Av2SyntaxPayload {
    let profile = Av2Black444MvpProfile::current();
    let mut writer = Av2SyntaxWriter::new();

    // AV2 v1.0.0 tile_group_obu() for an OBU_CLOSED_LOOP_KEY.
    // The uncompressed header follows AVM write_tilegroup_header() and
    // write_uncompressed_header(). The tile entropy payload is generated by
    // the AV2 range writer below. FrameForge fixes the current MVP to uniform
    // 64x64 superblock tiles and 8x8 coding leaves; each tile resets the local
    // syntax contexts so no prediction state crosses superblock boundaries.
    writer.write_flag("tile_group.first_tile_group_in_frame", true);
    writer.write_uvlc("uncompressed_header.cur_mfh_id", 0);
    writer.write_uvlc("uncompressed_header.seq_header_id", 0);
    writer.write_flag(
        "uncompressed_header.allow_screen_content_tools",
        allow_screen_content_tools,
    );
    if allow_screen_content_tools {
        writer.write_flag("uncompressed_header.cur_frame_force_integer_mv", false);
    }
    writer.write_flag("uncompressed_header.allow_intrabc", allow_intrabc);
    if allow_intrabc {
        // AV2 v1.0.0 read_intrabc_params(): key frames signal global/local
        // availability after allow_intrabc. FrameForge's first IBC path is
        // local to the current 64x64 tile, so allow_global_intrabc is false
        // and allow_local_intrabc is inferred true by AVM.
        writer.write_flag("uncompressed_header.allow_global_intrabc", false);
    }
    writer.write_flag(
        "uncompressed_header.disable_cdf_update",
        profile.disable_cdf_update,
    );
    write_mvp_tile_info(&mut writer, tile_layout);
    writer.write_literal("quantization.base_qindex", 0, 8);
    writer.write_flag("segmentation.enabled", false);
    writer.write_flag("quantization_matrix.using_qmatrix", false);
    writer.write_literal("uncompressed_header.reduced_tx_set_used", 0, 2);
    if !tile_layout.is_single_tile() {
        // AV2 v1.0.0 tile_group_obu(): a single tile group covering all tiles
        // still emits tile_start_and_end_present_flag when tiles_log2 > 0.
        // AVM write_tilegroup_header() packs this immediately after
        // write_uncompressed_header(); the tile-group header byte count is
        // rounded up only after this flag has been written.
        writer.write_flag("tile_group.tile_start_and_end_present_flag", false);
    }
    writer.byte_align_zero("tile_group.header_byte_alignment");

    writer.finish()
}

fn write_mvp_tile_info(writer: &mut Av2SyntaxWriter, tile_layout: &Av2TileLayout) {
    writer.write_flag("tile_info.uniform_spacing_flag", true);
    write_uniform_tile_log2(
        writer,
        "tile_info.increment_log2_cols",
        "tile_info.stop_log2_cols",
        tile_layout.min_log2_cols,
        tile_layout.log2_cols,
        tile_layout.max_log2_cols,
    );
    write_uniform_tile_log2(
        writer,
        "tile_info.increment_log2_rows",
        "tile_info.stop_log2_rows",
        tile_layout.min_log2_rows,
        tile_layout.log2_rows,
        tile_layout.max_log2_rows,
    );
    if !tile_layout.is_single_tile() {
        writer.write_literal(
            "tile_info.tile_size_bytes_minus1",
            (AV2_TILE_SIZE_BYTES - 1) as u64,
            2,
        );
    }
}

fn write_uniform_tile_log2(
    writer: &mut Av2SyntaxWriter,
    increment_name: &'static str,
    stop_name: &'static str,
    min_log2: u8,
    target_log2: u8,
    max_log2: u8,
) {
    assert!(min_log2 <= target_log2);
    assert!(target_log2 <= max_log2);
    for _ in min_log2..target_log2 {
        writer.write_flag(increment_name, true);
    }
    if target_log2 < max_log2 {
        writer.write_flag(stop_name, false);
    }
}

#[cfg(test)]
fn av2_black_444_closed_loop_key_payload(geometry: Av2VideoGeometry) -> Av2SyntaxPayload {
    av2_mvp_444_closed_loop_key_payload(geometry, &Av2Mvp444FrameMode::Black)
}

fn av2_black_closed_loop_key_payload(
    geometry: Av2VideoGeometry,
    chroma_format: Av2ChromaFormat,
) -> Av2SyntaxPayload {
    let tile_layout = Av2TileLayout::for_geometry(geometry);
    let profile = Av2Black444MvpProfile::current();
    let mut payload = av2_mvp_444_closed_loop_key_header_payload(false, false, &tile_layout);
    let tile_payloads: Vec<_> = tile_layout
        .regions
        .iter()
        .map(|&region| av2_black_tile_entropy_payload_for_region(region, profile, chroma_format))
        .collect();
    let tile_payload = tile_group_payload_from_entropy(&tile_payloads);
    let bit_offset = payload.bytes.len() * 8;
    payload.fields.push(syntax::Av2SyntaxField {
        name: "tile_group.tile_entropy_payload",
        code: syntax::Av2SyntaxCode::TileEntropyPayload,
        bit_offset,
        bit_count: tile_payload.len() * 8,
    });
    payload.bytes.extend_from_slice(&tile_payload);
    payload
}

fn av2_lossy_420_closed_loop_key_payload(
    geometry: Av2VideoGeometry,
    frame: &[u8],
    reconstruction: &mut [u8],
) -> Av2SyntaxPayload {
    let tile_layout = Av2TileLayout::for_geometry(geometry);
    let profile = Av2Black444MvpProfile::current();
    let mut payload = av2_mvp_444_closed_loop_key_header_payload(false, false, &tile_layout);
    let tile_payloads: Vec<_> = tile_layout
        .regions
        .iter()
        .map(|&region| {
            av2_lossy_420_tile_entropy_payload_for_region(
                region,
                profile,
                geometry,
                frame,
                reconstruction,
            )
        })
        .collect();
    let tile_payload = tile_group_payload_from_entropy(&tile_payloads);
    let bit_offset = payload.bytes.len() * 8;
    payload.fields.push(syntax::Av2SyntaxField {
        name: "tile_group.tile_entropy_payload",
        code: syntax::Av2SyntaxCode::TileEntropyPayload,
        bit_offset,
        bit_count: tile_payload.len() * 8,
    });
    payload.bytes.extend_from_slice(&tile_payload);
    payload
}

fn av2_mvp_444_closed_loop_key_payload(
    geometry: Av2VideoGeometry,
    frame_mode: &Av2Mvp444FrameMode,
) -> Av2SyntaxPayload {
    let tile_layout = Av2TileLayout::for_geometry(geometry);
    let mut payload = av2_mvp_444_closed_loop_key_header_payload(
        frame_mode.allow_screen_content_tools(),
        frame_mode.allow_intrabc(),
        &tile_layout,
    );
    let tile_payload = tile_group_payload_from_entropy(&av2_tile_entropy_payloads_for_mode(
        &tile_layout,
        frame_mode,
    ));
    let bit_offset = payload.bytes.len() * 8;
    payload.fields.push(syntax::Av2SyntaxField {
        name: "tile_group.tile_entropy_payload",
        code: syntax::Av2SyntaxCode::TileEntropyPayload,
        bit_offset,
        bit_count: tile_payload.len() * 8,
    });
    payload.bytes.extend_from_slice(&tile_payload);
    payload
}

fn tile_group_payload_from_entropy(tile_payloads: &[entropy::Av2EntropyPayload]) -> Vec<u8> {
    if tile_payloads.len() == 1 {
        return tile_payloads[0].bytes.clone();
    }

    let mut out = Vec::new();
    for (tile_index, payload) in tile_payloads.iter().enumerate() {
        if tile_index + 1 != tile_payloads.len() {
            write_tile_size_prefix(payload.bytes.len(), &mut out);
        }
        out.extend_from_slice(&payload.bytes);
    }
    out
}

fn av2_tile_entropy_payloads_for_mode(
    tile_layout: &Av2TileLayout,
    frame_mode: &Av2Mvp444FrameMode,
) -> Vec<entropy::Av2EntropyPayload> {
    tile_layout
        .regions
        .iter()
        .map(|&region| av2_tile_entropy_payload_for_region(region, frame_mode))
        .collect()
}

fn av2_tile_entropy_payload_for_region(
    region: Av2TileRegion,
    frame_mode: &Av2Mvp444FrameMode,
) -> entropy::Av2EntropyPayload {
    match frame_mode {
        Av2Mvp444FrameMode::Black => {
            av2_black_444_tile_entropy_payload_for_region(region, Av2Black444MvpProfile::current())
        }
        Av2Mvp444FrameMode::LumaPalette { palette, ibc } => {
            if !frame_mode.allow_intrabc() && av2_luma_palette_region_is_black(palette, region) {
                av2_black_444_tile_entropy_payload_for_region(region, frame_mode.profile())
            } else {
                av2_luma_palette_444_tile_entropy_payload_for_region(
                    region,
                    frame_mode.profile(),
                    palette,
                    ibc,
                )
            }
        }
    }
}

fn av2_luma_palette_region_is_black(palette: &Av2LumaPalette444, region: Av2TileRegion) -> bool {
    for y in region.origin_y..(region.origin_y + region.height) {
        for x in region.origin_x..(region.origin_x + region.width) {
            if palette.y_sample(x, y) != 0
                || palette.u_sample(x, y) != 0
                || palette.v_sample(x, y) != 0
            {
                return false;
            }
        }
    }
    true
}

fn write_tile_size_prefix(tile_size: usize, out: &mut Vec<u8>) {
    let stored = tile_size
        .checked_sub(AV2_MIN_TILE_SIZE_BYTES)
        .expect("AV2 tile payload must not be empty");
    assert!(
        stored <= u32::MAX as usize,
        "AV2 MVP tile payload size prefix is limited to 32 bits"
    );
    out.extend_from_slice(&(stored as u32).to_le_bytes());
}

fn append_obu(out: &mut Vec<u8>, obu_type: Av2ObuType, payload: &Av2SyntaxPayload) {
    let header = av2_obu_header(obu_type);
    write_leb128((header.len() + payload.bytes.len()) as u32, out);
    out.extend_from_slice(&header);
    out.extend_from_slice(&payload.bytes);
}

fn av2_obu_header(obu_type: Av2ObuType) -> Vec<u8> {
    let mut writer = Av2SyntaxWriter::new();
    writer.write_flag("obu_header.obu_header_extension_flag", false);
    writer.write_literal("obu_header.obu_type", obu_type as u64, 5);
    writer.write_literal("obu_header.obu_tlayer_id", 0, 2);
    writer.finish().bytes
}

fn write_leb128(mut value: u32, out: &mut Vec<u8>) {
    loop {
        let mut byte = (value & 0x7f) as u8;
        value >>= 7;
        if value != 0 {
            byte |= 0x80;
        }
        out.push(byte);
        if value == 0 {
            break;
        }
    }
}

fn push_av2_trace_line(
    out: &mut String,
    phase: &str,
    name: &str,
    spec: &str,
    code: &str,
    bit_offset: usize,
    bit_count: usize,
) {
    out.push_str(&format!(
        "{{\"codec\":\"av2\",\"source\":\"software\",\"phase\":\"{}\",\"name\":\"{}\",\"spec\":\"{}\",\"code\":\"{}\",\"bit_offset\":{},\"bit_count\":{}}}\n",
        escape_json(phase),
        escape_json(name),
        escape_json(spec),
        escape_json(code),
        bit_offset,
        bit_count
    ));
}

fn push_av2_entropy_trace_line(
    out: &mut String,
    tile_index: usize,
    field: &entropy::Av2EntropyField,
) {
    let mut line = format!(
        "{{\"codec\":\"av2\",\"source\":\"software\",\"phase\":\"tile_entropy\",\"tile_index\":{},\"name\":\"{}\",\"spec\":\"{}\",\"code\":\"{}\",\"bit_offset\":{},\"bit_count\":{}",
        tile_index,
        escape_json(field.name),
        escape_json(av2_spec_section_for_entropy_field(field.name)),
        escape_json(&format!("{:?}", field.code)),
        field.symbol_offset,
        field.bit_count
    );
    if let Some(symbol) = field.symbol {
        line.push_str(&format!(",\"symbol\":{symbol}"));
    }
    if let Some(value) = field.literal_value {
        line.push_str(&format!(",\"literal_value\":{value}"));
    }
    if let Some(fl) = field.fl {
        line.push_str(&format!(",\"fl\":{fl}"));
    }
    if let Some(fh) = field.fh {
        line.push_str(&format!(",\"fh\":{fh}"));
    }
    if let Some(fl_inc) = field.fl_inc {
        line.push_str(&format!(",\"fl_inc\":{fl_inc}"));
    }
    if let Some(fh_inc) = field.fh_inc {
        line.push_str(&format!(",\"fh_inc\":{fh_inc}"));
    }
    line.push_str("}\n");
    out.push_str(&line);
}

fn av2_spec_section_for_syntax_field(name: &str) -> &'static str {
    if name.starts_with("sequence_header.") || name.starts_with("sequence_") {
        "AV2 v1.0.0 Section 5.4.1 sequence_header_obu()"
    } else if name.starts_with("tile_group.") || name.starts_with("uncompressed_header.") {
        "AV2 v1.0.0 Sections 5.19 and 5.20.1 tile_group_obu()"
    } else if name.starts_with("tile_info.")
        || name.starts_with("quantization.")
        || name.starts_with("segmentation.")
        || name.starts_with("quantization_matrix.")
    {
        "AV2 v1.0.0 Section 5.20.1 uncompressed header syntax"
    } else if name == "trailing_bits" {
        "AV2 v1.0.0 Section 5.4.1 trailing bits"
    } else {
        "AV2 v1.0.0 syntax"
    }
}

fn av2_spec_section_for_entropy_field(name: &str) -> &'static str {
    if name.starts_with("tile.partition.") {
        "AV2 v1.0.0 Section 5.20.3.2 partition()"
    } else if name.starts_with("tile.intrabc.") {
        "AV2 v1.0.0 Sections 5.20.5.1 and 5.20.5.3 intra block copy syntax"
    } else if name.starts_with("tile.intra.") {
        "AV2 v1.0.0 Sections 5.20.5.5 and 5.20.5.6 intra mode syntax"
    } else if name.starts_with("tile.palette.") {
        "AV2 v1.0.0 Sections 5.20.8.1 and 5.20.8.4 palette syntax"
    } else if name.starts_with("tile.coeff.") {
        "AV2 v1.0.0 Sections 5.20.7.23, 5.20.7.24, and 5.20.7.27 residual coefficient syntax"
    } else {
        "AV2 v1.0.0 tile entropy syntax"
    }
}

fn escape_json(value: &str) -> String {
    let mut out = String::new();
    for ch in value.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if c.is_control() => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::syntax::Av2SyntaxCode;
    use super::*;

    #[test]
    fn av2_accepts_basic_yuv_request_shape() {
        let request = Av2EncodeRequest {
            params: Av2EncodeParams { frames: 1 },
            geometry: Av2VideoGeometry {
                width: 64,
                height: 64,
            },
            format: PixelFormat::Yuv420p8,
        };

        assert!(request.validate().is_ok());
    }

    #[test]
    fn av2_fixed_black_444_emits_generated_obu_stream_and_reconstruction() {
        for geometry in supported_black_444_geometries() {
            let request = Av2EncodeRequest {
                params: Av2EncodeParams { frames: 1 },
                geometry,
                format: PixelFormat::Yuv444p8,
            };
            let input =
                av2_black_444_reconstruction(geometry).expect("supported AV2 fixed black geometry");
            let mut source = input.as_slice();
            let mut output = Vec::new();
            let mut recon = Vec::new();

            let result =
                av2_encode_fixed_black_444(&mut source, &mut output, Some(&mut recon), request);

            result.expect("AV2 OBU encode should succeed");
            assert_eq!(output, av2_black_444_bitstream_for_geometry(geometry));
            assert_eq!(&output[..2], &[0x01, 0x08]);
            assert_ne!(output, input);
            assert_eq!(recon, input);
        }
    }

    #[test]
    fn av2_fixed_black_420_emits_decodable_black_obu_stream() {
        let geometry = Av2VideoGeometry {
            width: 16,
            height: 16,
        };
        let request = Av2EncodeRequest {
            params: Av2EncodeParams { frames: 1 },
            geometry,
            format: PixelFormat::Yuv420p8,
        };
        let input =
            vec![0; Picture::expected_len(geometry.width, geometry.height, PixelFormat::Yuv420p8,)];
        let mut source = input.as_slice();
        let mut output = Vec::new();
        let mut recon = Vec::new();

        av2_encode_fixed_black_444(&mut source, &mut output, Some(&mut recon), request)
            .expect("AV2 4:2:0 black OBU encode should succeed");

        assert_ne!(output, input);
        assert_eq!(recon, input);
        let sequence = av2_mvp_sequence_header_payload(
            geometry,
            Av2Black444MvpProfile::current(),
            Av2ChromaFormat::Yuv420,
        );
        assert_has_field(
            &sequence,
            "sequence_header.seq_chroma_format_idc",
            Av2SyntaxCode::Uvlc,
            12,
            1,
        );
    }

    #[test]
    fn av2_yuv420_nonblack_uses_lossy_residual_reconstruction() {
        let geometry = Av2VideoGeometry {
            width: 8,
            height: 8,
        };
        let request = Av2EncodeRequest {
            params: Av2EncodeParams { frames: 1 },
            geometry,
            format: PixelFormat::Yuv420p8,
        };
        let mut input =
            vec![0; Picture::expected_len(geometry.width, geometry.height, PixelFormat::Yuv420p8,)];
        for (index, sample) in input.iter_mut().enumerate() {
            *sample = (17 + index * 5) as u8;
        }
        let mut source = input.as_slice();
        let mut output = Vec::new();
        let mut recon = Vec::new();

        av2_encode_fixed_black_444(&mut source, &mut output, Some(&mut recon), request)
            .expect("AV2 4:2:0 lossy residual encode should succeed");

        assert_ne!(
            output,
            av2_black_bitstream_for_geometry(geometry, Av2ChromaFormat::Yuv420)
        );
        assert_ne!(recon, input);
        assert_eq!(recon.len(), input.len());
        let trace = av2_mvp_444_trace_jsonl_for_frame(&input, request)
            .expect("AV2 4:2:0 lossy residual trace should be emitted");
        assert!(
            trace.contains("tile.coeff.y.txb_nonzero_tx4x4_ctx"),
            "non-black 4:2:0 inputs should emit residual coefficient syntax"
        );
    }

    #[test]
    fn av2_fixed_black_444_sequence_header_has_labeled_fields() {
        let payload = av2_black_444_sequence_header_payload(Av2VideoGeometry {
            width: 64,
            height: 64,
        });

        assert_eq!(
            payload.bytes,
            vec![0x92, 0x06, 0x95, 0x7f, 0xfc, 0x00, 0x01, 0x08, 0x06, 0xe0, 0x22]
        );
        assert_has_field(
            &payload,
            "sequence_header.seq_profile_idc",
            Av2SyntaxCode::Literal,
            1,
            5,
        );
        assert_has_field(
            &payload,
            "sequence_header.max_frame_width_minus_1",
            Av2SyntaxCode::Literal,
            26,
            6,
        );
        assert_has_field(
            &payload,
            "sequence_transform.base_uv_ac_delta_q_minus_min",
            Av2SyntaxCode::Literal,
            70,
            5,
        );
        assert_has_field(
            &payload,
            "trailing_bits",
            Av2SyntaxCode::TrailingBits,
            86,
            2,
        );
    }

    #[test]
    fn av2_fixed_black_444_closed_loop_key_labels_header_fields() {
        let payload = av2_black_444_closed_loop_key_header_payload();

        assert_eq!(payload.bytes, vec![0xe6, 0x00, 0x00]);
        assert_has_field(
            &payload,
            "tile_group.first_tile_group_in_frame",
            Av2SyntaxCode::Flag,
            0,
            1,
        );
        assert_has_field(
            &payload,
            "quantization.base_qindex",
            Av2SyntaxCode::Literal,
            7,
            8,
        );
    }

    #[test]
    fn av2_fixed_black_444_closed_loop_key_carries_generated_tile_entropy_payload() {
        let payload = av2_black_444_closed_loop_key_payload(Av2VideoGeometry {
            width: 64,
            height: 64,
        });

        assert_eq!(&payload.bytes[..3], &[0xe6, 0x00, 0x00]);
        assert!(payload.bytes.len() > 3);
        let entropy_field = payload
            .fields
            .iter()
            .find(|field| field.name == "tile_group.tile_entropy_payload")
            .expect("missing AV2 tile entropy payload field");
        assert_eq!(entropy_field.code, Av2SyntaxCode::TileEntropyPayload);
        assert_eq!(entropy_field.bit_offset, 24);
        assert_eq!(entropy_field.bit_count, (payload.bytes.len() - 3) * 8);
    }

    #[test]
    fn av2_luma_palette_444_accepts_two_luma_colors_with_zero_chroma() {
        let request = Av2EncodeRequest {
            params: Av2EncodeParams { frames: 1 },
            geometry: Av2VideoGeometry {
                width: AV2_FIXED_BLACK_444_WIDTH,
                height: AV2_FIXED_BLACK_444_HEIGHT,
            },
            format: PixelFormat::Yuv444p8,
        };
        let mut input = av2_black_64x64_444_reconstruction();
        let y_plane_len = AV2_FIXED_BLACK_444_WIDTH * AV2_FIXED_BLACK_444_HEIGHT;
        for sample in &mut input[y_plane_len / 2..y_plane_len] {
            *sample = 96;
        }
        let mut source = input.as_slice();
        let mut output = Vec::new();
        let mut recon = Vec::new();

        let result =
            av2_encode_fixed_black_444(&mut source, &mut output, Some(&mut recon), request);

        result.expect("two-color luma palette should encode");
        assert_ne!(
            output,
            av2_black_444_bitstream_for_geometry(request.geometry)
        );
        assert_eq!(recon, input);
    }

    #[test]
    fn av2_mvp_444_preserves_chroma_with_bdpcm_residuals() {
        let request = Av2EncodeRequest {
            params: Av2EncodeParams { frames: 1 },
            geometry: Av2VideoGeometry {
                width: AV2_FIXED_BLACK_444_WIDTH,
                height: AV2_FIXED_BLACK_444_HEIGHT,
            },
            format: PixelFormat::Yuv444p8,
        };
        let mut input = av2_black_64x64_444_reconstruction();
        let y_plane_len = AV2_FIXED_BLACK_444_WIDTH * AV2_FIXED_BLACK_444_HEIGHT;
        input[y_plane_len] = 1;
        let mut source = input.as_slice();
        let mut output = Vec::new();
        let mut recon = Vec::new();

        let result =
            av2_encode_fixed_black_444(&mut source, &mut output, Some(&mut recon), request);

        result.expect("content must not be rejected by the AV2 MVP path");
        assert_ne!(
            output,
            av2_black_444_bitstream_for_geometry(request.geometry)
        );
        assert_eq!(recon, input);
    }

    #[test]
    fn av2_mvp_444_can_select_vertical_chroma_bdpcm() {
        let request = Av2EncodeRequest {
            params: Av2EncodeParams { frames: 1 },
            geometry: Av2VideoGeometry {
                width: 8,
                height: 8,
            },
            format: PixelFormat::Yuv444p8,
        };
        let plane_len = request.geometry.width * request.geometry.height;
        let mut input = vec![0u8; plane_len * 3];
        for y in 0..8usize {
            for x in 0..8usize {
                let index = y * 8 + x;
                input[plane_len + index] = 48 + (x as u8 * 9);
                input[2 * plane_len + index] = 112 + (x as u8 * 13);
            }
        }
        let mut source = input.as_slice();
        let mut output = Vec::new();
        let mut recon = Vec::new();

        av2_encode_fixed_black_444(&mut source, &mut output, Some(&mut recon), request)
            .expect("vertical chroma BDPCM should encode");

        assert_eq!(recon, input);
        let trace = av2_mvp_444_trace_jsonl_for_frame(&input, request)
            .expect("AV2 trace should be emitted");
        assert!(
            trace.lines().any(|line| {
                line.contains("\"name\":\"tile.intra.dpcm_uv_horz\"")
                    && line.contains("\"symbol\":0")
            }),
            "vertical chroma BDPCM should signal dpcm_uv_horz=0"
        );
    }

    #[test]
    fn av2_mvp_444_preserves_over_limit_luma_colors_with_lossless_residual() {
        let request = Av2EncodeRequest {
            params: Av2EncodeParams { frames: 1 },
            geometry: Av2VideoGeometry {
                width: AV2_FIXED_BLACK_444_WIDTH,
                height: AV2_FIXED_BLACK_444_HEIGHT,
            },
            format: PixelFormat::Yuv444p8,
        };
        let mut input = av2_black_64x64_444_reconstruction();
        let y_plane_len = AV2_FIXED_BLACK_444_WIDTH * AV2_FIXED_BLACK_444_HEIGHT;
        for (index, sample) in input[..y_plane_len].iter_mut().enumerate() {
            *sample = (index & 0xff) as u8;
        }
        let mut source = input.as_slice();
        let mut output = Vec::new();
        let mut recon = Vec::new();

        let result =
            av2_encode_fixed_black_444(&mut source, &mut output, Some(&mut recon), request);

        result.expect("over-limit luma colors should encode through lossless residuals");
        assert_ne!(
            output,
            av2_black_444_bitstream_for_geometry(request.geometry)
        );
        assert_eq!(recon, input);
        let trace = av2_mvp_444_trace_jsonl_for_frame(&input, request)
            .expect("AV2 trace should be emitted");
        assert!(
            trace.contains("tile.coeff.y.txb_nonzero_tx4x4_ctx"),
            "over-limit luma palette blocks must emit lossless luma coefficient residuals"
        );
        assert!(recon[y_plane_len..].iter().all(|&sample| sample == 0));
    }

    #[test]
    fn av2_mvp_444_can_select_horizontal_luma_intra_prediction() {
        let request = Av2EncodeRequest {
            params: Av2EncodeParams { frames: 1 },
            geometry: Av2VideoGeometry {
                width: 16,
                height: 8,
            },
            format: PixelFormat::Yuv444p8,
        };
        let mut input = vec![0u8; 16 * 8 * 3];
        for y in 0..8usize {
            let edge = 16 + y as u8 * 28;
            input[y * 16 + 7] = edge;
            for x in 0..8usize {
                input[y * 16 + 8 + x] = edge + x as u8;
            }
        }
        let mut source = input.as_slice();
        let mut output = Vec::new();
        let mut recon = Vec::new();

        av2_encode_fixed_black_444(&mut source, &mut output, Some(&mut recon), request)
            .expect("horizontal intra luma prediction should encode");

        assert_eq!(recon, input);
        let trace = av2_mvp_444_trace_jsonl_for_frame(&input, request)
            .expect("AV2 trace should be emitted");
        assert!(
            trace.contains("tile.intra.y_mode_idx_h"),
            "horizontal luma intra prediction should be selected for the right block"
        );
    }

    #[test]
    fn av2_rejects_zero_frames() {
        let request = Av2EncodeRequest {
            params: Av2EncodeParams { frames: 0 },
            geometry: Av2VideoGeometry {
                width: 64,
                height: 64,
            },
            format: PixelFormat::Yuv420p8,
        };

        assert!(request.validate().is_err());
    }

    fn assert_has_field(
        payload: &Av2SyntaxPayload,
        name: &'static str,
        code: Av2SyntaxCode,
        bit_offset: usize,
        bit_count: usize,
    ) {
        assert!(
            payload.fields.iter().any(|field| {
                field.name == name
                    && field.code == code
                    && field.bit_offset == bit_offset
                    && field.bit_count == bit_count
            }),
            "missing AV2 syntax field {name} at bit {bit_offset} with {bit_count} bit(s)"
        );
    }

    fn supported_black_444_geometries() -> Vec<Av2VideoGeometry> {
        let mut geometries = Vec::new();
        for height in (8..=64).step_by(8) {
            for width in (8..=64).step_by(8) {
                geometries.push(Av2VideoGeometry { width, height });
            }
        }
        geometries
    }
}
