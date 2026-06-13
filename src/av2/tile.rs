use super::{Av2Black444MvpProfile, Av2VideoGeometry};
use crate::av2::entropy::{Av2EntropyPayload, Av2EntropyWriter};

const MVP_SUPERBLOCK_SIZE: usize = 64;
const TX4X4_PER_64X64_DIM: usize = 16;
const AVM_CDF_PROB_TOP: u16 = 32768;
const BLACK_LOSSLESS_DC_LEVEL: u16 = 512;
const NONZERO_NEGATIVE_DC_ENTROPY_CONTEXT: u8 = 15;

const fn avm_cdf2(a0: u16, p0: i16, p1: i16, p2: i16) -> [u16; 6] {
    [
        AVM_CDF_PROB_TOP - a0,
        0,
        0,
        (p0 + 2) as u16,
        (p1 + 3) as u16,
        (p2 + 4) as u16,
    ]
}

const fn avm_cdf4(a0: u16, a1: u16, a2: u16, p0: i16, p1: i16, p2: i16) -> [u16; 8] {
    [
        AVM_CDF_PROB_TOP - a0,
        AVM_CDF_PROB_TOP - a1,
        AVM_CDF_PROB_TOP - a2,
        0,
        0,
        (p0 + 3) as u16,
        (p1 + 4) as u16,
        (p2 + 5) as u16,
    ]
}

const fn avm_cdf5(a0: u16, a1: u16, a2: u16, a3: u16, p0: i16, p1: i16, p2: i16) -> [u16; 9] {
    [
        AVM_CDF_PROB_TOP - a0,
        AVM_CDF_PROB_TOP - a1,
        AVM_CDF_PROB_TOP - a2,
        AVM_CDF_PROB_TOP - a3,
        0,
        0,
        (p0 + 3) as u16,
        (p1 + 4) as u16,
        (p2 + 5) as u16,
    ]
}

const DEFAULT_DPCM_CDF: [u16; 6] = [16384, 0, 0, 2, 3, 4];
const DEFAULT_DO_SPLIT_64X64_CTX12_CDF: [u16; 6] = [
    AVM_CDF_PROB_TOP - 20492,
    0,
    0,
    2, // AVM_PARA2(0, 1, -1)
    4,
    3,
];
const DEFAULT_Y_MODE_SET_CDF: [u16; 8] = [
    AVM_CDF_PROB_TOP - 28863,
    AVM_CDF_PROB_TOP - 31022,
    AVM_CDF_PROB_TOP - 31724,
    0,
    0,
    4, // AVM_PARA4(1, 1, 1)
    5,
    6,
];
const DEFAULT_Y_MODE_IDX_CTX0_CDF: [u16; 12] = [
    AVM_CDF_PROB_TOP - 15175,
    AVM_CDF_PROB_TOP - 20075,
    AVM_CDF_PROB_TOP - 21728,
    AVM_CDF_PROB_TOP - 24098,
    AVM_CDF_PROB_TOP - 26405,
    AVM_CDF_PROB_TOP - 27655,
    AVM_CDF_PROB_TOP - 28860,
    0,
    0,
    3, // AVM_PARA8(0, -1, 0)
    3,
    5,
];
const DEFAULT_UV_MODE_CTX0_CDF: [u16; 12] = [
    AVM_CDF_PROB_TOP - 9363,
    AVM_CDF_PROB_TOP - 20957,
    AVM_CDF_PROB_TOP - 22865,
    AVM_CDF_PROB_TOP - 24753,
    AVM_CDF_PROB_TOP - 26411,
    AVM_CDF_PROB_TOP - 27983,
    AVM_CDF_PROB_TOP - 30428,
    0,
    0,
    2, // AVM_PARA8(-1, -1, -1)
    3,
    4,
];
const DEFAULT_TXB_SKIP_Y_TX4X4_CTX1_CDF: [u16; 6] = [
    AVM_CDF_PROB_TOP - 1099,
    0,
    0,
    3, // AVM_PARA2(1, 1, 1)
    4,
    5,
];
const DEFAULT_TXB_SKIP_Y_TX4X4_CTX3_CDF: [u16; 6] = avm_cdf2(7944, -1, 0, -1);
const DEFAULT_TXB_SKIP_Y_TX4X4_CTX5_CDF: [u16; 6] = avm_cdf2(29076, -1, -1, -1);
const DEFAULT_TXB_SKIP_U_TX4X4_CTX6_CDF: [u16; 6] = [
    AVM_CDF_PROB_TOP - 8898,
    0,
    0,
    2, // AVM_PARA2(0, 0, -1)
    3,
    3,
];
const DEFAULT_TXB_SKIP_U_TX4X4_CTX7_CDF: [u16; 6] = avm_cdf2(13655, 0, 0, -1);
const DEFAULT_TXB_SKIP_U_TX4X4_CTX8_CDF: [u16; 6] = avm_cdf2(22348, 0, 0, 0);
const DEFAULT_V_TXB_SKIP_TX4X4_CTX9_CDF: [u16; 6] = avm_cdf2(16384, 0, 0, 0);
const DEFAULT_V_TXB_SKIP_TX4X4_CTX10_CDF: [u16; 6] = avm_cdf2(16384, 0, 0, 0);
const DEFAULT_V_TXB_SKIP_TX4X4_CTX11_CDF: [u16; 6] = avm_cdf2(16384, 0, 0, 0);
const DEFAULT_EOB_MULTI16_Y_CTX0_CDF: [u16; 9] = avm_cdf5(1946, 3059, 6834, 15123, 0, -1, -1);
const DEFAULT_EOB_MULTI16_UV_CTX2_CDF: [u16; 9] = avm_cdf5(8000, 10366, 14466, 19569, -1, -1, -1);
const DEFAULT_COEFF_BASE_LF_EOB_Y_TX4X4_CTX0_CDF: [u16; 9] =
    avm_cdf5(27486, 31140, 31779, 32064, 0, -1, -2);
const DEFAULT_COEFF_BASE_LF_EOB_UV_CTX0_CDF: [u16; 9] =
    avm_cdf5(28950, 31443, 32009, 32257, 1, 0, 0);
const DEFAULT_COEFF_LPS_LF_CTX0_CDF: [u16; 8] = avm_cdf4(7943, 14193, 20775, -1, -1, -2);
const DEFAULT_DC_SIGN_Y_CTX0_CDF: [u16; 6] = avm_cdf2(15831, 1, 1, 1);
const DEFAULT_DC_SIGN_Y_CTX1_CDF: [u16; 6] = avm_cdf2(13632, 1, 0, 0);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Av2MvpBlockSize {
    Block64x64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Av2TileDecisionKind {
    PartitionNone,
    IntraLumaDc,
    IntraChromaDc,
    BlackDcResidualCoefficients,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Av2TileDecision {
    kind: Av2TileDecisionKind,
    row: usize,
    col: usize,
    block_size: Av2MvpBlockSize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct Av2Black444TilePlan {
    decisions: Vec<Av2TileDecision>,
}

pub(crate) fn av2_black_444_tile_entropy_payload(
    geometry: Av2VideoGeometry,
    profile: Av2Black444MvpProfile,
) -> Av2EntropyPayload {
    let plan = Av2Black444TilePlan::for_geometry(geometry, profile);
    let mut writer = Av2EntropyWriter::new();
    plan.write_entropy(&mut writer);
    writer.finish()
}

impl Av2Black444TilePlan {
    fn for_geometry(geometry: Av2VideoGeometry, profile: Av2Black444MvpProfile) -> Self {
        assert!(
            !profile.enable_sdp,
            "AV2 MVP tile plan expects a shared luma/chroma partition tree"
        );
        assert!(
            profile.disable_cdf_update,
            "AV2 MVP tile plan expects fixed frame-initial CDFs"
        );
        assert!(
            geometry.width <= MVP_SUPERBLOCK_SIZE && geometry.height <= MVP_SUPERBLOCK_SIZE,
            "AV2 MVP tile plan currently covers one 64x64 superblock"
        );
        assert!(
            geometry.width % 8 == 0 && geometry.height % 8 == 0,
            "AV2 MVP tile plan expects visible dimensions in 8-pixel units"
        );

        let mut plan = Self {
            decisions: Vec::new(),
        };
        if geometry.width == MVP_SUPERBLOCK_SIZE && geometry.height == MVP_SUPERBLOCK_SIZE {
            plan.visit_full_superblock();
        }
        plan
    }

    fn visit_full_superblock(&mut self) {
        let block_size = Av2MvpBlockSize::Block64x64;
        self.decisions.push(Av2TileDecision {
            kind: Av2TileDecisionKind::PartitionNone,
            row: 0,
            col: 0,
            block_size,
        });
        self.decisions.push(Av2TileDecision {
            kind: Av2TileDecisionKind::IntraLumaDc,
            row: 0,
            col: 0,
            block_size,
        });
        self.decisions.push(Av2TileDecision {
            kind: Av2TileDecisionKind::IntraChromaDc,
            row: 0,
            col: 0,
            block_size,
        });
        self.decisions.push(Av2TileDecision {
            kind: Av2TileDecisionKind::BlackDcResidualCoefficients,
            row: 0,
            col: 0,
            block_size,
        });
    }

    fn write_entropy(&self, writer: &mut Av2EntropyWriter) {
        for decision in &self.decisions {
            match decision.kind {
                Av2TileDecisionKind::PartitionNone => {
                    write_partition_none_64x64(writer, *decision);
                }
                Av2TileDecisionKind::IntraLumaDc => {
                    write_intra_luma_dc_64x64(writer, *decision);
                }
                Av2TileDecisionKind::IntraChromaDc => {
                    write_intra_chroma_dc_64x64(writer, *decision);
                }
                Av2TileDecisionKind::BlackDcResidualCoefficients => {
                    write_black_dc_residual_coefficients_64x64(writer, *decision);
                }
            }
        }
    }
}

fn write_partition_none_64x64(writer: &mut Av2EntropyWriter, decision: Av2TileDecision) {
    assert_eq!(decision.block_size, Av2MvpBlockSize::Block64x64);
    assert_eq!((decision.row, decision.col), (0, 0));

    let mut cdf = DEFAULT_DO_SPLIT_64X64_CTX12_CDF;
    // AV2 v1.0.0 Section 5.11.52 partition(): with 64x64 SBs in this AVM
    // branch, square split is not eligible below 128x128. The first full-SB
    // black stream therefore emits only do_split=0 using
    // default_do_split_cdf[SHARED_PART][ctx=12], matching AVM
    // write_partition()/read_partition() when above/left partition contexts
    // are zero at tile start.
    writer.write_symbol("tile.partition.do_split_64x64_ctx12", 0, &mut cdf, 2, false);
}

fn write_intra_luma_dc_64x64(writer: &mut Av2EntropyWriter, decision: Av2TileDecision) {
    assert_eq!(decision.block_size, Av2MvpBlockSize::Block64x64);
    assert_eq!((decision.row, decision.col), (0, 0));

    let mut dpcm_cdf = DEFAULT_DPCM_CDF;
    // AV2 v1.0.0 Section 5.11.55 intra_frame_mode_info(): lossless intra
    // blocks signal DPCM usage before luma mode. The MVP path keeps normal
    // intra prediction and emits use_dpcm_y=0.
    writer.write_symbol("tile.intra.use_dpcm_y", 0, &mut dpcm_cdf, 2, false);

    let mut mode_set_cdf = DEFAULT_Y_MODE_SET_CDF;
    // DC_PRED is mode index 0 in the non-directional mode set at tile start,
    // matching AVM write_intra_luma_mode()/read_intra_luma_mode() with
    // get_y_mode_idx_ctx()==0.
    writer.write_symbol(
        "tile.intra.y_mode_set_index",
        0,
        &mut mode_set_cdf,
        4,
        false,
    );

    let mut mode_idx_cdf = DEFAULT_Y_MODE_IDX_CTX0_CDF;
    writer.write_symbol("tile.intra.y_mode_idx_dc", 0, &mut mode_idx_cdf, 8, false);
}

fn write_intra_chroma_dc_64x64(writer: &mut Av2EntropyWriter, decision: Av2TileDecision) {
    assert_eq!(decision.block_size, Av2MvpBlockSize::Block64x64);
    assert_eq!((decision.row, decision.col), (0, 0));

    let mut dpcm_uv_cdf = DEFAULT_DPCM_CDF;
    // AV2 v1.0.0 Section 5.11.55 also signals chroma DPCM in lossless shared
    // tree blocks. The MVP path keeps normal chroma DC prediction.
    writer.write_symbol("tile.intra.use_dpcm_uv", 0, &mut dpcm_uv_cdf, 2, false);

    let mut uv_mode_cdf = DEFAULT_UV_MODE_CTX0_CDF;
    writer.write_symbol("tile.intra.uv_mode_idx_dc", 0, &mut uv_mode_cdf, 8, false);
}

fn write_black_dc_residual_coefficients_64x64(
    writer: &mut Av2EntropyWriter,
    decision: Av2TileDecision,
) {
    assert_eq!(decision.block_size, Av2MvpBlockSize::Block64x64);
    assert_eq!((decision.row, decision.col), (0, 0));

    // AV2 v1.0.0 Sections 5.11.55, 5.20.1 and the AVM
    // av2_read_coeffs_txb() lossless path force TX_4X4 for this intra block.
    // DC_PRED reconstructs 128 at frame/tile boundaries, so a black input
    // needs one negative DC coefficient per TXB. With qindex 0, dequant is 64
    // and the lossless 4x4 inverse WHT divides a DC-only coefficient by four;
    // level 512 therefore produces -128 at every sample after dequant.
    let mut y_above = [0u8; TX4X4_PER_64X64_DIM];
    let mut y_left = [0u8; TX4X4_PER_64X64_DIM];
    for row in 0..TX4X4_PER_64X64_DIM {
        for col in 0..TX4X4_PER_64X64_DIM {
            let skip_ctx = luma_txb_skip_context(y_above[col], y_left[row]);
            let dc_sign_ctx = dc_sign_context(y_above[col], y_left[row]);
            write_y_black_dc_txb(writer, skip_ctx, dc_sign_ctx);
            y_above[col] = NONZERO_NEGATIVE_DC_ENTROPY_CONTEXT;
            y_left[row] = NONZERO_NEGATIVE_DC_ENTROPY_CONTEXT;
        }
    }

    let mut u_above = [0u8; TX4X4_PER_64X64_DIM];
    let mut u_left = [0u8; TX4X4_PER_64X64_DIM];
    for row in 0..TX4X4_PER_64X64_DIM {
        for col in 0..TX4X4_PER_64X64_DIM {
            let skip_ctx = chroma_txb_skip_base_context(u_above[col], u_left[row]) + 6;
            write_u_black_dc_txb(writer, skip_ctx);
            u_above[col] = NONZERO_NEGATIVE_DC_ENTROPY_CONTEXT;
            u_left[row] = NONZERO_NEGATIVE_DC_ENTROPY_CONTEXT;
        }
    }

    let mut v_above = [0u8; TX4X4_PER_64X64_DIM];
    let mut v_left = [0u8; TX4X4_PER_64X64_DIM];
    for row in 0..TX4X4_PER_64X64_DIM {
        for col in 0..TX4X4_PER_64X64_DIM {
            let skip_ctx = chroma_txb_skip_base_context(v_above[col], v_left[row]) + 9;
            write_v_black_dc_txb(writer, skip_ctx);
            v_above[col] = NONZERO_NEGATIVE_DC_ENTROPY_CONTEXT;
            v_left[row] = NONZERO_NEGATIVE_DC_ENTROPY_CONTEXT;
        }
    }
}

fn write_y_black_dc_txb(writer: &mut Av2EntropyWriter, skip_ctx: u8, dc_sign_ctx: u8) {
    write_y_txb_nonzero(writer, skip_ctx);
    write_eob_one_y(writer);
    write_y_dc_level(writer, BLACK_LOSSLESS_DC_LEVEL);
    write_y_negative_dc_sign(writer, dc_sign_ctx);
    write_y_dc_high_range(writer, BLACK_LOSSLESS_DC_LEVEL);
}

fn write_u_black_dc_txb(writer: &mut Av2EntropyWriter, skip_ctx: u8) {
    write_u_txb_nonzero(writer, skip_ctx);
    write_eob_one_uv(writer);
    write_uv_dc_level(writer, BLACK_LOSSLESS_DC_LEVEL);
    writer.write_literal("tile.coeff.u.dc_sign_negative", 1, 1);
    write_uv_dc_high_range(writer, BLACK_LOSSLESS_DC_LEVEL);
}

fn write_v_black_dc_txb(writer: &mut Av2EntropyWriter, skip_ctx: u8) {
    write_v_txb_nonzero(writer, skip_ctx);
    write_eob_one_uv(writer);
    write_uv_dc_level(writer, BLACK_LOSSLESS_DC_LEVEL);
    writer.write_literal("tile.coeff.v.dc_sign_negative", 1, 1);
    write_uv_dc_high_range(writer, BLACK_LOSSLESS_DC_LEVEL);
}

fn write_y_txb_nonzero(writer: &mut Av2EntropyWriter, skip_ctx: u8) {
    let (name, mut cdf) = match skip_ctx {
        1 => (
            "tile.coeff.y.txb_nonzero_tx4x4_ctx1",
            DEFAULT_TXB_SKIP_Y_TX4X4_CTX1_CDF,
        ),
        3 => (
            "tile.coeff.y.txb_nonzero_tx4x4_ctx3",
            DEFAULT_TXB_SKIP_Y_TX4X4_CTX3_CDF,
        ),
        5 => (
            "tile.coeff.y.txb_nonzero_tx4x4_ctx5",
            DEFAULT_TXB_SKIP_Y_TX4X4_CTX5_CDF,
        ),
        _ => panic!("unsupported AV2 luma TXB skip context {skip_ctx}"),
    };
    writer.write_symbol(name, 0, &mut cdf, 2, false);
}

fn write_u_txb_nonzero(writer: &mut Av2EntropyWriter, skip_ctx: u8) {
    let (name, mut cdf) = match skip_ctx {
        6 => (
            "tile.coeff.u.txb_nonzero_tx4x4_ctx6",
            DEFAULT_TXB_SKIP_U_TX4X4_CTX6_CDF,
        ),
        7 => (
            "tile.coeff.u.txb_nonzero_tx4x4_ctx7",
            DEFAULT_TXB_SKIP_U_TX4X4_CTX7_CDF,
        ),
        8 => (
            "tile.coeff.u.txb_nonzero_tx4x4_ctx8",
            DEFAULT_TXB_SKIP_U_TX4X4_CTX8_CDF,
        ),
        _ => panic!("unsupported AV2 U TXB skip context {skip_ctx}"),
    };
    writer.write_symbol(name, 0, &mut cdf, 2, false);
}

fn write_v_txb_nonzero(writer: &mut Av2EntropyWriter, skip_ctx: u8) {
    let (name, mut cdf) = match skip_ctx {
        9 => (
            "tile.coeff.v.txb_nonzero_tx4x4_ctx9",
            DEFAULT_V_TXB_SKIP_TX4X4_CTX9_CDF,
        ),
        10 => (
            "tile.coeff.v.txb_nonzero_tx4x4_ctx10",
            DEFAULT_V_TXB_SKIP_TX4X4_CTX10_CDF,
        ),
        11 => (
            "tile.coeff.v.txb_nonzero_tx4x4_ctx11",
            DEFAULT_V_TXB_SKIP_TX4X4_CTX11_CDF,
        ),
        _ => panic!("unsupported AV2 V TXB skip context {skip_ctx}"),
    };
    writer.write_symbol(name, 0, &mut cdf, 2, false);
}

fn write_eob_one_y(writer: &mut Av2EntropyWriter) {
    let mut cdf = DEFAULT_EOB_MULTI16_Y_CTX0_CDF;
    writer.write_symbol("tile.coeff.y.eob_pt_tx4x4_eob1", 0, &mut cdf, 5, false);
}

fn write_eob_one_uv(writer: &mut Av2EntropyWriter) {
    let mut cdf = DEFAULT_EOB_MULTI16_UV_CTX2_CDF;
    writer.write_symbol("tile.coeff.uv.eob_pt_tx4x4_eob1", 0, &mut cdf, 5, false);
}

fn write_y_dc_level(writer: &mut Av2EntropyWriter, level: u16) {
    let mut base_cdf = DEFAULT_COEFF_BASE_LF_EOB_Y_TX4X4_CTX0_CDF;
    let base_symbol = usize::from(level.min(5) - 1);
    writer.write_symbol(
        "tile.coeff.y.dc_base_lf_eob_ctx0",
        base_symbol,
        &mut base_cdf,
        5,
        false,
    );

    if level > 4 {
        let mut low_cdf = DEFAULT_COEFF_LPS_LF_CTX0_CDF;
        let low_symbol = usize::from((level - 1 - 4).min(3));
        writer.write_symbol(
            "tile.coeff.y.dc_low_range_lf_ctx0",
            low_symbol,
            &mut low_cdf,
            4,
            false,
        );
    }
}

fn write_uv_dc_level(writer: &mut Av2EntropyWriter, level: u16) {
    let mut base_cdf = DEFAULT_COEFF_BASE_LF_EOB_UV_CTX0_CDF;
    let base_symbol = usize::from(level.min(5) - 1);
    writer.write_symbol(
        "tile.coeff.uv.dc_base_lf_eob_ctx0",
        base_symbol,
        &mut base_cdf,
        5,
        false,
    );
}

fn write_y_negative_dc_sign(writer: &mut Av2EntropyWriter, dc_sign_ctx: u8) {
    let (name, mut cdf) = match dc_sign_ctx {
        0 => (
            "tile.coeff.y.dc_sign_negative_ctx0",
            DEFAULT_DC_SIGN_Y_CTX0_CDF,
        ),
        1 => (
            "tile.coeff.y.dc_sign_negative_ctx1",
            DEFAULT_DC_SIGN_Y_CTX1_CDF,
        ),
        _ => panic!("unsupported AV2 luma DC sign context {dc_sign_ctx}"),
    };
    writer.write_symbol(name, 1, &mut cdf, 2, false);
}

fn write_y_dc_high_range(writer: &mut Av2EntropyWriter, level: u16) {
    if level > 7 {
        write_adaptive_high_range(writer, "tile.coeff.y.dc_high_range", u32::from(level - 8));
    }
}

fn write_uv_dc_high_range(writer: &mut Av2EntropyWriter, level: u16) {
    if level > 4 {
        write_adaptive_high_range(writer, "tile.coeff.uv.dc_high_range", u32::from(level - 5));
    }
}

fn write_adaptive_high_range(writer: &mut Av2EntropyWriter, name: &'static str, value: u32) {
    // AVM write_adaptive_hr() starts every TXB with hr_level_avg=0; the
    // resulting Rice parameter is m=1, k=2, cmax=5 for this DC-only path.
    write_truncated_rice(writer, name, value, 1, 2, 5);
}

fn write_truncated_rice(
    writer: &mut Av2EntropyWriter,
    name: &'static str,
    value: u32,
    m: u8,
    k: u8,
    cmax: u8,
) {
    let q = value >> m;
    if q >= u32::from(cmax) {
        writer.write_literal(name, 0, cmax);
        write_exp_golomb(writer, name, value - (u32::from(cmax) << m), k);
    } else {
        if q > 0 {
            writer.write_literal(name, 0, q as u8);
        }
        writer.write_literal(name, 1, 1);
        if m > 0 {
            writer.write_literal(name, value & ((1u32 << m) - 1), m);
        }
    }
}

fn write_exp_golomb(writer: &mut Av2EntropyWriter, name: &'static str, value: u32, k: u8) {
    let x = value + (1u32 << k);
    let length = (u32::BITS - x.leading_zeros()) as u8;
    assert!(length > k, "AV2 Exp-Golomb length must exceed order");
    writer.write_literal(name, 0, length - 1 - k);
    writer.write_literal(name, x, length);
}

fn luma_txb_skip_context(above: u8, left: u8) -> u8 {
    let top = (above & 7).min(4);
    let left = (left & 7).min(4);
    match (top, left) {
        (0, 0) => 1,
        (0, 1..=2) | (1..=2, 0) | (1, 1) => 2,
        (0, _) | (_, 0) | (1, 2..=3) | (2..=3, 1) | (2, 2) => 3,
        (1..=2, 4) | (4, 1..=2) | (2..=3, 3) | (3, 2..=3) => 4,
        _ => 5,
    }
}

fn chroma_txb_skip_base_context(above: u8, left: u8) -> u8 {
    u8::from(above != 0) + u8::from(left != 0)
}

fn dc_sign_context(above: u8, left: u8) -> u8 {
    let mut sign_sum = entropy_context_dc_sign(above) + entropy_context_dc_sign(left);
    sign_sum = sign_sum.clamp(-32, 32);
    match sign_sum {
        0 => 0,
        -32..=-1 => 1,
        1..=32 => 2,
        _ => unreachable!("AV2 DC sign sum was clamped before context lookup"),
    }
}

fn entropy_context_dc_sign(context: u8) -> i8 {
    match context >> 3 {
        0 => 0,
        1 => -1,
        2 => 1,
        _ => panic!("unsupported AV2 DC sign entropy context {context}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn av2_black_444_tile_plan_uses_single_64x64_leaf() {
        let plan = Av2Black444TilePlan::for_geometry(
            Av2VideoGeometry {
                width: 64,
                height: 64,
            },
            Av2Black444MvpProfile::current(),
        );

        let partition_none_count = plan
            .decisions
            .iter()
            .filter(|decision| decision.kind == Av2TileDecisionKind::PartitionNone)
            .count();
        let luma_leaf_count = plan
            .decisions
            .iter()
            .filter(|decision| decision.kind == Av2TileDecisionKind::IntraLumaDc)
            .count();

        assert_eq!(partition_none_count, 1);
        assert_eq!(luma_leaf_count, 1);
        assert!(plan.decisions.iter().any(|decision| {
            decision.kind == Av2TileDecisionKind::BlackDcResidualCoefficients
                && decision.row == 0
                && decision.col == 0
                && decision.block_size == Av2MvpBlockSize::Block64x64
        }));
    }

    #[test]
    fn av2_black_444_tile_payload_emits_root_partition_symbol() {
        let payload = av2_black_444_tile_entropy_payload(
            Av2VideoGeometry {
                width: 64,
                height: 64,
            },
            Av2Black444MvpProfile::current(),
        );

        for name in [
            "tile.partition.do_split_64x64_ctx12",
            "tile.intra.use_dpcm_y",
            "tile.intra.y_mode_set_index",
            "tile.intra.y_mode_idx_dc",
            "tile.intra.use_dpcm_uv",
            "tile.intra.uv_mode_idx_dc",
            "tile.coeff.y.txb_nonzero_tx4x4_ctx1",
            "tile.coeff.y.dc_base_lf_eob_ctx0",
            "tile.coeff.y.dc_sign_negative_ctx0",
            "tile.coeff.u.txb_nonzero_tx4x4_ctx6",
            "tile.coeff.u.dc_sign_negative",
            "tile.coeff.v.txb_nonzero_tx4x4_ctx9",
            "tile.coeff.v.dc_sign_negative",
        ] {
            assert!(
                payload.fields.iter().any(|field| field.name == name),
                "missing AV2 entropy field {name}"
            );
        }
        assert_eq!(
            payload
                .fields
                .iter()
                .filter(|field| field.name.starts_with("tile.coeff.y.txb_nonzero_tx4x4_ctx"))
                .count(),
            256
        );
        assert_eq!(
            payload
                .fields
                .iter()
                .filter(|field| field.name.starts_with("tile.coeff.u.txb_nonzero_tx4x4_ctx"))
                .count(),
            256
        );
        assert_eq!(
            payload
                .fields
                .iter()
                .filter(|field| field.name.starts_with("tile.coeff.v.txb_nonzero_tx4x4_ctx"))
                .count(),
            256
        );
        assert_eq!(payload.symbol_bits, 18694);
    }

    #[test]
    fn av2_black_444_tile_payload_keeps_boundary_partition_todo_explicit() {
        let payload = av2_black_444_tile_entropy_payload(
            Av2VideoGeometry {
                width: 16,
                height: 8,
            },
            Av2Black444MvpProfile::current(),
        );

        assert!(payload.fields.is_empty());
        assert_eq!(payload.symbol_bits, 0);
    }
}
