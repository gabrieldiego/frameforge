use super::{Av2Black444MvpProfile, Av2VideoGeometry};
use crate::av2::entropy::{Av2EntropyPayload, Av2EntropyWriter};

const MVP_SUPERBLOCK_SIZE: usize = 64;
const AVM_CDF_PROB_TOP: u16 = 32768;
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
const DEFAULT_TXB_SKIP_U_TX4X4_CTX6_CDF: [u16; 6] = [
    AVM_CDF_PROB_TOP - 8898,
    0,
    0,
    2, // AVM_PARA2(0, 0, -1)
    3,
    3,
];
const DEFAULT_V_TXB_SKIP_TX4X4_CTX3_CDF: [u16; 6] = [
    AVM_CDF_PROB_TOP - 180,
    0,
    0,
    0, // AVM_PARA2(-2, 0, 0)
    3,
    4,
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Av2MvpBlockSize {
    Block64x64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Av2TileDecisionKind {
    PartitionNone,
    IntraLumaDc,
    IntraChromaDc,
    ZeroTransformCoefficients,
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
            kind: Av2TileDecisionKind::ZeroTransformCoefficients,
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
                Av2TileDecisionKind::ZeroTransformCoefficients => {
                    write_zero_transform_coefficients_64x64(writer, *decision);
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

fn write_zero_transform_coefficients_64x64(
    writer: &mut Av2EntropyWriter,
    decision: Av2TileDecision,
) {
    assert_eq!(decision.block_size, Av2MvpBlockSize::Block64x64);
    assert_eq!((decision.row, decision.col), (0, 0));

    // AV2 v1.0.0 Sections 5.11.55 and 5.20.1 reach
    // read_coeffs_tx_intra_block() for this lossless non-FSC intra block.
    // AVM read_tx_size()/av2_get_tx_size() force TX_4X4, and
    // av2_read_sig_txtype()/av2_write_sig_txtype() signal eob==0 as the TXB
    // skip/all-zero symbol. With all-zero blocks, av2_set_entropy_contexts()
    // writes zero contexts back after every TXB, so the initial contexts repeat
    // for all 16x16 TX_4X4 blocks in each 64x64 4:4:4 plane.
    for _blk_row in 0..16 {
        for _blk_col in 0..16 {
            let mut y_cdf = DEFAULT_TXB_SKIP_Y_TX4X4_CTX1_CDF;
            writer.write_symbol(
                "tile.coeff.y.txb_all_zero_tx4x4_ctx1",
                1,
                &mut y_cdf,
                2,
                false,
            );
        }
    }

    for _blk_row in 0..16 {
        for _blk_col in 0..16 {
            let mut u_cdf = DEFAULT_TXB_SKIP_U_TX4X4_CTX6_CDF;
            writer.write_symbol(
                "tile.coeff.u.txb_all_zero_tx4x4_ctx6",
                1,
                &mut u_cdf,
                2,
                false,
            );
        }
    }

    for _blk_row in 0..16 {
        for _blk_col in 0..16 {
            let mut v_cdf = DEFAULT_V_TXB_SKIP_TX4X4_CTX3_CDF;
            writer.write_symbol(
                "tile.coeff.v.txb_all_zero_tx4x4_ctx3",
                1,
                &mut v_cdf,
                2,
                false,
            );
        }
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
            decision.kind == Av2TileDecisionKind::ZeroTransformCoefficients
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
            "tile.coeff.y.txb_all_zero_tx4x4_ctx1",
            "tile.coeff.u.txb_all_zero_tx4x4_ctx6",
            "tile.coeff.v.txb_all_zero_tx4x4_ctx3",
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
                .filter(|field| field.name == "tile.coeff.y.txb_all_zero_tx4x4_ctx1")
                .count(),
            256
        );
        assert_eq!(
            payload
                .fields
                .iter()
                .filter(|field| field.name == "tile.coeff.u.txb_all_zero_tx4x4_ctx6")
                .count(),
            256
        );
        assert_eq!(
            payload
                .fields
                .iter()
                .filter(|field| field.name == "tile.coeff.v.txb_all_zero_tx4x4_ctx3")
                .count(),
            256
        );
        assert_eq!(payload.symbol_bits, 774);
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
