use super::{Av2Black444MvpProfile, Av2VideoGeometry};
use crate::av2::entropy::{Av2EntropyPayload, Av2EntropyWriter};

const MVP_SUPERBLOCK_SIZE: usize = 64;
const MVP_LEAF_BLOCK_SIZE: usize = 8;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Av2MvpBlockSize {
    Block64x64,
    Block32x32,
    Block16x16,
    Block8x8,
}

impl Av2MvpBlockSize {
    fn pixels(self) -> usize {
        match self {
            Self::Block64x64 => 64,
            Self::Block32x32 => 32,
            Self::Block16x16 => 16,
            Self::Block8x8 => 8,
        }
    }

    fn split_child(self) -> Option<Self> {
        match self {
            Self::Block64x64 => Some(Self::Block32x32),
            Self::Block32x32 => Some(Self::Block16x16),
            Self::Block16x16 => Some(Self::Block8x8),
            Self::Block8x8 => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Av2TileDecisionKind {
    PartitionSplit,
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
    debug_assert!(
        !plan.decisions.is_empty(),
        "AV2 MVP tile plan must produce at least one 8x8 leaf"
    );

    // AV2 v1.0.0 Section 5.20.1 wraps decode_tile() in init_symbol() and
    // exit_symbol(). The plan above now describes the intended superblock,
    // partition, mode, and zero-coefficient traversal, but the CDF-backed S()
    // calls are still being ported from AVM bitstream.c/write_modes_sb(),
    // write_mb_modes_kf(), and encodetxb.c. Until those symbols are encoded,
    // emit only the generated range-coder terminator and let AVM reject the
    // stream at tile data rather than hiding a placeholder payload.
    Av2EntropyWriter::new().finish()
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
            geometry.width % MVP_LEAF_BLOCK_SIZE == 0 && geometry.height % MVP_LEAF_BLOCK_SIZE == 0,
            "AV2 MVP tile plan expects visible dimensions in 8-pixel units"
        );

        let mut plan = Self {
            decisions: Vec::new(),
        };
        plan.visit_block(0, 0, Av2MvpBlockSize::Block64x64, geometry);
        plan
    }

    fn visit_block(
        &mut self,
        row: usize,
        col: usize,
        block_size: Av2MvpBlockSize,
        geometry: Av2VideoGeometry,
    ) {
        if row >= geometry.height || col >= geometry.width {
            return;
        }

        if let Some(child_size) = block_size.split_child() {
            self.decisions.push(Av2TileDecision {
                kind: Av2TileDecisionKind::PartitionSplit,
                row,
                col,
                block_size,
            });

            let half = child_size.pixels();
            // AVM write_modes_sb()/decode_partition() visit PARTITION_SPLIT
            // children in top-left, top-right, bottom-left, bottom-right order.
            self.visit_block(row, col, child_size, geometry);
            self.visit_block(row, col + half, child_size, geometry);
            self.visit_block(row + half, col, child_size, geometry);
            self.visit_block(row + half, col + half, child_size, geometry);
        } else {
            self.decisions.push(Av2TileDecision {
                kind: Av2TileDecisionKind::IntraLumaDc,
                row,
                col,
                block_size,
            });
            self.decisions.push(Av2TileDecision {
                kind: Av2TileDecisionKind::IntraChromaDc,
                row,
                col,
                block_size,
            });
            self.decisions.push(Av2TileDecision {
                kind: Av2TileDecisionKind::ZeroTransformCoefficients,
                row,
                col,
                block_size,
            });
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn av2_black_444_tile_plan_uses_8x8_leaves() {
        let plan = Av2Black444TilePlan::for_geometry(
            Av2VideoGeometry {
                width: 64,
                height: 64,
            },
            Av2Black444MvpProfile::current(),
        );

        let split_count = plan
            .decisions
            .iter()
            .filter(|decision| decision.kind == Av2TileDecisionKind::PartitionSplit)
            .count();
        let luma_leaf_count = plan
            .decisions
            .iter()
            .filter(|decision| decision.kind == Av2TileDecisionKind::IntraLumaDc)
            .count();

        assert_eq!(split_count, 21);
        assert_eq!(luma_leaf_count, 64);
        assert!(plan.decisions.iter().any(|decision| {
            decision.kind == Av2TileDecisionKind::ZeroTransformCoefficients
                && decision.row == 56
                && decision.col == 56
                && decision.block_size == Av2MvpBlockSize::Block8x8
        }));
    }

    #[test]
    fn av2_black_444_tile_plan_clips_partial_superblock_geometry() {
        let plan = Av2Black444TilePlan::for_geometry(
            Av2VideoGeometry {
                width: 16,
                height: 8,
            },
            Av2Black444MvpProfile::current(),
        );

        let leaf_count = plan
            .decisions
            .iter()
            .filter(|decision| decision.kind == Av2TileDecisionKind::IntraLumaDc)
            .count();

        assert_eq!(leaf_count, 2);
        assert!(plan
            .decisions
            .iter()
            .all(|decision| decision.row < 8 && decision.col < 16));
    }
}
