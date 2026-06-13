use super::{Av2Black444MvpProfile, Av2VideoGeometry};
use crate::av2::entropy::{Av2EntropyPayload, Av2EntropyWriter};

const MVP_SUPERBLOCK_SIZE: usize = 64;
const MI_SIZE: usize = 4;
const PARTITION_CONTEXT_DIM: usize = MVP_SUPERBLOCK_SIZE / MI_SIZE;
const TX4X4_MAX_BLOCK_DIM: usize = MVP_SUPERBLOCK_SIZE / 4;
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
const DEFAULT_FSC_MODE_CTX0_CDFS: [[u16; 6]; 6] = [
    avm_cdf2(30503, 0, 0, 1),
    avm_cdf2(31244, 0, 0, 1),
    avm_cdf2(32254, 1, 0, 1),
    avm_cdf2(32324, 1, 1, 1),
    avm_cdf2(32582, 1, 1, 1),
    avm_cdf2(32691, 1, 1, 1),
];
const DEFAULT_DO_SPLIT_CDFS: [[u16; 6]; 64] = [
    avm_cdf2(28084, 0, 0, 1),
    avm_cdf2(23755, 1, 1, 1),
    avm_cdf2(23634, 1, 1, 1),
    avm_cdf2(19368, 0, 0, 1),
    avm_cdf2(24961, 0, 0, 0),
    avm_cdf2(14941, 0, 0, -1),
    avm_cdf2(16154, 0, 0, -1),
    avm_cdf2(5905, 0, 0, 0),
    avm_cdf2(21934, 0, 0, 0),
    avm_cdf2(10440, -1, 0, -1),
    avm_cdf2(11984, -1, -1, -1),
    avm_cdf2(3474, 0, 0, 0),
    avm_cdf2(20492, 0, 1, -1),
    avm_cdf2(6963, 0, -1, -1),
    avm_cdf2(8099, -1, 0, -1),
    avm_cdf2(1529, 0, 0, 0),
    avm_cdf2(24117, 1, 1, -2),
    avm_cdf2(7871, 0, -2, 0),
    avm_cdf2(23604, 0, 0, -2),
    avm_cdf2(8429, -1, -1, 0),
    avm_cdf2(27356, 0, 0, -2),
    avm_cdf2(22441, 0, -1, -2),
    avm_cdf2(8897, -1, -1, -1),
    avm_cdf2(6811, -2, -2, -1),
    avm_cdf2(17592, 0, 1, -1),
    avm_cdf2(5648, -1, -1, -2),
    avm_cdf2(5339, -1, 0, -1),
    avm_cdf2(1082, -1, 0, -1),
    avm_cdf2(26143, 1, 0, -2),
    avm_cdf2(11379, 1, -2, 0),
    avm_cdf2(20142, 1, 1, 1),
    avm_cdf2(7401, 0, -1, 1),
    avm_cdf2(26235, 1, -1, -2),
    avm_cdf2(23674, 1, 0, 1),
    avm_cdf2(12441, 1, 0, -2),
    avm_cdf2(10482, 1, 0, 0),
    avm_cdf2(20663, 0, 0, 0),
    avm_cdf2(4192, -1, 0, -2),
    avm_cdf2(5274, -1, -1, 1),
    avm_cdf2(713, 0, 0, -1),
    avm_cdf2(28255, 1, 0, 0),
    avm_cdf2(27370, 1, 0, 0),
    avm_cdf2(23527, 0, 0, 0),
    avm_cdf2(20990, 0, 0, -1),
    avm_cdf2(26727, 0, 0, 0),
    avm_cdf2(21187, 0, 0, 0),
    avm_cdf2(25324, 0, 0, 0),
    avm_cdf2(17838, 0, 0, 0),
    avm_cdf2(26136, 0, 0, 0),
    avm_cdf2(16591, 0, -1, -1),
    avm_cdf2(19838, 0, 0, -1),
    avm_cdf2(10605, -1, -1, -1),
    avm_cdf2(22914, 0, 0, -1),
    avm_cdf2(12609, -1, -1, -1),
    avm_cdf2(11341, 0, 0, 0),
    avm_cdf2(4556, 0, 0, 0),
    avm_cdf2(24218, 0, 0, -1),
    avm_cdf2(13059, 0, -1, -2),
    avm_cdf2(15378, -1, -1, -2),
    avm_cdf2(5858, -1, -1, -2),
    avm_cdf2(21644, -1, -1, -2),
    avm_cdf2(7767, -1, -1, -1),
    avm_cdf2(8309, 0, -1, -1),
    avm_cdf2(1687, 0, 0, 0),
];
const DEFAULT_RECT_TYPE_CDFS: [[u16; 6]; 64] = [
    avm_cdf2(14644, 0, 0, 0),
    avm_cdf2(10173, 1, 0, 0),
    avm_cdf2(18529, 0, 0, 0),
    avm_cdf2(16071, 1, 1, 0),
    avm_cdf2(20263, 0, 0, -1),
    avm_cdf2(12813, 0, 0, -1),
    avm_cdf2(26612, 0, 0, 0),
    avm_cdf2(23277, 0, 0, -1),
    avm_cdf2(10594, 1, 0, -1),
    avm_cdf2(7000, 1, 0, 0),
    avm_cdf2(20002, 0, 0, -1),
    avm_cdf2(12889, 0, 0, -2),
    avm_cdf2(13854, 1, 0, -1),
    avm_cdf2(10750, 0, 0, -1),
    avm_cdf2(18380, 0, 0, -1),
    avm_cdf2(17505, 0, -1, -1),
    avm_cdf2(14430, 0, -1, -2),
    avm_cdf2(11554, 0, 0, -2),
    avm_cdf2(20078, 0, 0, -1),
    avm_cdf2(19097, 1, 0, -1),
    avm_cdf2(15278, 0, 0, -2),
    avm_cdf2(10137, 0, 0, -1),
    avm_cdf2(21921, 0, -1, -2),
    avm_cdf2(14621, 0, -1, -1),
    avm_cdf2(19330, 0, 0, -2),
    avm_cdf2(15921, 0, 0, -1),
    avm_cdf2(26218, 0, 0, -1),
    avm_cdf2(24318, 0, 0, -1),
    avm_cdf2(16384, 0, 0, 0),
    avm_cdf2(16384, 0, 0, 0),
    avm_cdf2(16384, 0, 0, 0),
    avm_cdf2(16384, 0, 0, 0),
    avm_cdf2(16384, 0, 0, 0),
    avm_cdf2(16384, 0, 0, 0),
    avm_cdf2(16384, 0, 0, 0),
    avm_cdf2(16384, 0, 0, 0),
    avm_cdf2(16066, 1, 0, 1),
    avm_cdf2(9225, 0, 0, -2),
    avm_cdf2(22849, -1, -1, -1),
    avm_cdf2(14817, 0, -2, -1),
    avm_cdf2(16384, 0, 0, 0),
    avm_cdf2(16384, 0, 0, 0),
    avm_cdf2(16384, 0, 0, 0),
    avm_cdf2(16384, 0, 0, 0),
    avm_cdf2(16384, 0, 0, 0),
    avm_cdf2(16384, 0, 0, 0),
    avm_cdf2(16384, 0, 0, 0),
    avm_cdf2(16384, 0, 0, 0),
    avm_cdf2(18543, 1, 0, 0),
    avm_cdf2(13210, 0, -2, 0),
    avm_cdf2(24367, -1, -1, -2),
    avm_cdf2(18417, -1, 0, 0),
    avm_cdf2(24701, 0, -1, -1),
    avm_cdf2(18911, 0, -1, -2),
    avm_cdf2(29590, 0, 0, -1),
    avm_cdf2(27778, 0, -1, -2),
    avm_cdf2(3400, 0, 0, -1),
    avm_cdf2(935, 1, 1, 0),
    avm_cdf2(10365, -1, -1, -2),
    avm_cdf2(1723, 0, 0, -1),
    avm_cdf2(16384, 0, 0, 0),
    avm_cdf2(16384, 0, 0, 0),
    avm_cdf2(16384, 0, 0, 0),
    avm_cdf2(16384, 0, 0, 0),
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
struct Av2MvpBlockSize {
    width: usize,
    height: usize,
}

impl Av2MvpBlockSize {
    const BLOCK_64X64: Self = Self {
        width: 64,
        height: 64,
    };

    fn new(width: usize, height: usize) -> Self {
        assert!(
            is_supported_mvp_block_size(width, height),
            "unsupported AV2 MVP block size {width}x{height}"
        );
        Self { width, height }
    }

    fn mi_width(self) -> usize {
        self.width / MI_SIZE
    }

    fn mi_height(self) -> usize {
        self.height / MI_SIZE
    }

    fn tx4x4_width(self) -> usize {
        self.width / 4
    }

    fn tx4x4_height(self) -> usize {
        self.height / 4
    }

    fn is_square(self) -> bool {
        self.width == self.height
    }

    fn is_tall(self) -> bool {
        self.height > self.width
    }

    fn is_wide(self) -> bool {
        self.width > self.height
    }

    fn is_partition_point(self) -> bool {
        // AVM is_partition_point() returns false for BLOCK_8X64 and
        // BLOCK_64X8 because they live past BLOCK_SIZES in the conversion
        // tables. The MVP path never creates 4xN leaves.
        !matches!((self.width, self.height), (8, 64) | (64, 8))
    }

    fn bsize_map(self) -> usize {
        match (self.width, self.height) {
            (8, 8) => 0,
            (8, 16) | (16, 8) | (16, 16) => 1,
            (16, 32) | (32, 16) | (32, 32) => 2,
            (32, 64) | (64, 32) | (64, 64) => 3,
            (8, 32) => 12,
            (32, 8) => 13,
            (16, 64) => 14,
            (64, 16) => 15,
            (8, 64) | (64, 8) => {
                panic!("AV2 8:1 leaves are not partition context points")
            }
            _ => unreachable!("unsupported AV2 MVP block size"),
        }
    }

    fn bsize_rect_map(self) -> usize {
        match (self.width, self.height) {
            (8, 8) | (16, 16) => 0,
            (8, 16) | (16, 32) => 1,
            (16, 8) | (32, 16) => 2,
            (32, 32) => 3,
            (32, 64) => 4,
            (64, 32) => 5,
            (64, 64) => 6,
            (8, 32) | (16, 64) => 13,
            (32, 8) | (64, 16) => 14,
            (8, 64) | (64, 8) => {
                panic!("AV2 8:1 leaves are not partition context points")
            }
            _ => unreachable!("unsupported AV2 MVP block size"),
        }
    }

    fn fsc_size_group(self) -> Option<usize> {
        // AV2 v1.0.0 allow_fsc_intra() permits intra FSC signalling when
        // enable_idtx_intra is active and both block dimensions are 4..=32.
        // The MVP always signals fsc_mode=0, but the syntax symbol is still
        // present for these block sizes.
        if self.width > 32 || self.height > 32 {
            return None;
        }
        Some(match (self.width, self.height) {
            (8, 8) => 2,
            (8, 16) | (16, 8) => 3,
            (16, 16) | (8, 32) | (32, 8) => 4,
            (16, 32) | (32, 16) | (32, 32) => 5,
            _ => unreachable!("unsupported AV2 MVP FSC block size"),
        })
    }

    fn subsize(self, partition: Av2MvpPartition) -> Option<Self> {
        let (width, height) = self.subsize_dims(partition)?;
        is_supported_mvp_block_size(width, height).then(|| Self::new(width, height))
    }

    fn subsize_dims(self, partition: Av2MvpPartition) -> Option<(usize, usize)> {
        if !self.is_partition_point() {
            return (partition == Av2MvpPartition::None).then_some((self.width, self.height));
        }
        match partition {
            Av2MvpPartition::None => Some((self.width, self.height)),
            Av2MvpPartition::Horz if self.height >= 8 => Some((self.width, self.height / 2)),
            Av2MvpPartition::Vert if self.width >= 8 => Some((self.width / 2, self.height)),
            _ => None,
        }
    }
}

fn is_supported_mvp_block_size(width: usize, height: usize) -> bool {
    matches!(
        (width, height),
        (8, 8)
            | (8, 16)
            | (16, 8)
            | (16, 16)
            | (16, 32)
            | (32, 16)
            | (32, 32)
            | (32, 64)
            | (64, 32)
            | (64, 64)
            | (8, 32)
            | (32, 8)
            | (16, 64)
            | (64, 16)
            | (8, 64)
            | (64, 8)
    )
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Av2MvpPartition {
    None,
    Horz,
    Vert,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Av2TileDecisionKind {
    Partition(Av2MvpPartition),
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
    visible_rows_mi: usize,
    visible_cols_mi: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct Av2PartitionContext {
    above: [u8; PARTITION_CONTEXT_DIM],
    left: [u8; PARTITION_CONTEXT_DIM],
}

impl Av2PartitionContext {
    fn new() -> Self {
        Self {
            above: [0; PARTITION_CONTEXT_DIM],
            left: [0; PARTITION_CONTEXT_DIM],
        }
    }

    fn raw_context(&self, row_mi: usize, col_mi: usize, block_size: Av2MvpBlockSize) -> usize {
        let above_shift = block_size.mi_width().ilog2().saturating_sub(1);
        let left_shift = block_size.mi_height().ilog2().saturating_sub(1);
        let above = (self.above[col_mi] >> above_shift) & 1;
        let left = (self.left[row_mi] >> left_shift) & 1;
        usize::from(left * 2 + above)
    }

    fn split_context(&self, row_mi: usize, col_mi: usize, block_size: Av2MvpBlockSize) -> usize {
        self.raw_context(row_mi, col_mi, block_size) + block_size.bsize_map() * 4
    }

    fn rect_context(&self, row_mi: usize, col_mi: usize, block_size: Av2MvpBlockSize) -> usize {
        self.raw_context(row_mi, col_mi, block_size) + block_size.bsize_rect_map() * 4
    }

    fn update_leaf(&mut self, row_mi: usize, col_mi: usize, block_size: Av2MvpBlockSize) {
        // AV2 v1.0.0 Section 9.3 partition context conversion tables, mirrored
        // from AVM partition_context_lookup[] and update_partition_context().
        let (above, left) = partition_context_lookup(block_size);
        for index in col_mi..(col_mi + block_size.mi_width()).min(PARTITION_CONTEXT_DIM) {
            self.above[index] = above;
        }
        for index in row_mi..(row_mi + block_size.mi_height()).min(PARTITION_CONTEXT_DIM) {
            self.left[index] = left;
        }
    }
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

        let visible_rows_mi = geometry.height / MI_SIZE;
        let visible_cols_mi = geometry.width / MI_SIZE;
        let mut plan = Self {
            decisions: Vec::new(),
            visible_rows_mi,
            visible_cols_mi,
        };
        let mut partition_context = Av2PartitionContext::new();
        plan.visit_block(
            0,
            0,
            Av2MvpBlockSize::BLOCK_64X64,
            visible_rows_mi,
            visible_cols_mi,
            &mut partition_context,
        );
        plan
    }

    fn visit_block(
        &mut self,
        row_mi: usize,
        col_mi: usize,
        block_size: Av2MvpBlockSize,
        visible_rows_mi: usize,
        visible_cols_mi: usize,
        partition_context: &mut Av2PartitionContext,
    ) {
        if row_mi >= visible_rows_mi || col_mi >= visible_cols_mi {
            return;
        }

        let partition =
            choose_partition(row_mi, col_mi, block_size, visible_rows_mi, visible_cols_mi);
        self.decisions.push(Av2TileDecision {
            kind: Av2TileDecisionKind::Partition(partition),
            row: row_mi,
            col: col_mi,
            block_size,
        });

        match partition {
            Av2MvpPartition::None => {
                self.visit_leaf(row_mi, col_mi, block_size);
                partition_context.update_leaf(row_mi, col_mi, block_size);
            }
            Av2MvpPartition::Horz => {
                let subsize = block_size
                    .subsize(partition)
                    .expect("AV2 MVP horizontal partition must have a subsize");
                self.visit_block(
                    row_mi,
                    col_mi,
                    subsize,
                    visible_rows_mi,
                    visible_cols_mi,
                    partition_context,
                );
                self.visit_block(
                    row_mi + block_size.mi_height() / 2,
                    col_mi,
                    subsize,
                    visible_rows_mi,
                    visible_cols_mi,
                    partition_context,
                );
            }
            Av2MvpPartition::Vert => {
                let subsize = block_size
                    .subsize(partition)
                    .expect("AV2 MVP vertical partition must have a subsize");
                self.visit_block(
                    row_mi,
                    col_mi,
                    subsize,
                    visible_rows_mi,
                    visible_cols_mi,
                    partition_context,
                );
                self.visit_block(
                    row_mi,
                    col_mi + block_size.mi_width() / 2,
                    subsize,
                    visible_rows_mi,
                    visible_cols_mi,
                    partition_context,
                );
            }
        }
    }

    fn visit_leaf(&mut self, row_mi: usize, col_mi: usize, block_size: Av2MvpBlockSize) {
        self.decisions.push(Av2TileDecision {
            kind: Av2TileDecisionKind::IntraLumaDc,
            row: row_mi,
            col: col_mi,
            block_size,
        });
        self.decisions.push(Av2TileDecision {
            kind: Av2TileDecisionKind::IntraChromaDc,
            row: row_mi,
            col: col_mi,
            block_size,
        });
        self.decisions.push(Av2TileDecision {
            kind: Av2TileDecisionKind::BlackDcResidualCoefficients,
            row: row_mi,
            col: col_mi,
            block_size,
        });
    }

    fn write_entropy(&self, writer: &mut Av2EntropyWriter) {
        let mut partition_context = Av2PartitionContext::new();
        let mut txb_contexts = Av2TxbEntropyContexts::new();
        for decision in &self.decisions {
            match decision.kind {
                Av2TileDecisionKind::Partition(partition) => {
                    write_partition(
                        writer,
                        *decision,
                        partition,
                        &partition_context,
                        self.visible_rows_mi,
                        self.visible_cols_mi,
                    );
                    if partition == Av2MvpPartition::None {
                        partition_context.update_leaf(
                            decision.row,
                            decision.col,
                            decision.block_size,
                        );
                    }
                }
                Av2TileDecisionKind::IntraLumaDc => {
                    write_intra_luma_dc(writer, *decision);
                }
                Av2TileDecisionKind::IntraChromaDc => {
                    write_intra_chroma_dc(writer, *decision);
                }
                Av2TileDecisionKind::BlackDcResidualCoefficients => {
                    write_black_dc_residual_coefficients(
                        writer,
                        *decision,
                        self.visible_rows_mi,
                        self.visible_cols_mi,
                        &mut txb_contexts,
                    );
                }
            }
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct Av2TxbEntropyContexts {
    y_above: [u8; TX4X4_MAX_BLOCK_DIM],
    y_left: [u8; TX4X4_MAX_BLOCK_DIM],
    u_above: [u8; TX4X4_MAX_BLOCK_DIM],
    u_left: [u8; TX4X4_MAX_BLOCK_DIM],
    v_above: [u8; TX4X4_MAX_BLOCK_DIM],
    v_left: [u8; TX4X4_MAX_BLOCK_DIM],
}

impl Av2TxbEntropyContexts {
    fn new() -> Self {
        Self {
            y_above: [0; TX4X4_MAX_BLOCK_DIM],
            y_left: [0; TX4X4_MAX_BLOCK_DIM],
            u_above: [0; TX4X4_MAX_BLOCK_DIM],
            u_left: [0; TX4X4_MAX_BLOCK_DIM],
            v_above: [0; TX4X4_MAX_BLOCK_DIM],
            v_left: [0; TX4X4_MAX_BLOCK_DIM],
        }
    }
}

fn choose_partition(
    row_mi: usize,
    col_mi: usize,
    block_size: Av2MvpBlockSize,
    visible_rows_mi: usize,
    visible_cols_mi: usize,
) -> Av2MvpPartition {
    if !block_size.is_partition_point() {
        return Av2MvpPartition::None;
    }
    let allowed = allowed_partitions(row_mi, col_mi, block_size, visible_rows_mi, visible_cols_mi);
    if let Some(forced) =
        forced_boundary_partition(row_mi, col_mi, block_size, visible_rows_mi, visible_cols_mi)
    {
        if allowed.contains(forced) {
            return forced;
        }
    }
    if let Some(only_allowed) = allowed.only() {
        return only_allowed;
    }
    if allowed.none {
        return Av2MvpPartition::None;
    }
    if should_reduce_height(row_mi, block_size, visible_rows_mi) && allowed.horz {
        Av2MvpPartition::Horz
    } else if should_reduce_width(col_mi, block_size, visible_cols_mi) && allowed.vert {
        Av2MvpPartition::Vert
    } else if allowed.horz {
        Av2MvpPartition::Horz
    } else if allowed.vert {
        Av2MvpPartition::Vert
    } else {
        Av2MvpPartition::None
    }
}

fn forced_boundary_partition(
    row_mi: usize,
    col_mi: usize,
    block_size: Av2MvpBlockSize,
    visible_rows_mi: usize,
    visible_cols_mi: usize,
) -> Option<Av2MvpPartition> {
    if !block_size.is_partition_point() {
        return Some(Av2MvpPartition::None);
    }

    let hbs_w = block_size.mi_width() / 2;
    let hbs_h = block_size.mi_height() / 2;
    let has_rows = row_mi + hbs_h < visible_rows_mi;
    let has_cols = col_mi + hbs_w < visible_cols_mi;
    if has_rows && has_cols {
        return None;
    }

    // AV2 v1.0.0 partition() boundary derivation, mirrored from AVM
    // av2_get_normative_forced_partition_type() and
    // is_partition_implied_at_boundary().
    if block_size.is_square() {
        Some(if has_rows && !has_cols {
            Av2MvpPartition::Vert
        } else {
            Av2MvpPartition::Horz
        })
    } else if block_size.is_tall() {
        if !has_rows {
            Some(Av2MvpPartition::Horz)
        } else {
            let sub_has_cols = col_mi + block_size.mi_width() / 4 < visible_cols_mi;
            (block_size.mi_width() >= 4 && !sub_has_cols).then_some(Av2MvpPartition::Horz)
        }
    } else {
        assert!(block_size.is_wide());
        if !has_cols {
            Some(Av2MvpPartition::Vert)
        } else {
            let sub_has_rows = row_mi + block_size.mi_height() / 4 < visible_rows_mi;
            (block_size.mi_height() >= 4 && !sub_has_rows).then_some(Av2MvpPartition::Vert)
        }
    }
}

fn should_reduce_height(
    row_mi: usize,
    block_size: Av2MvpBlockSize,
    visible_rows_mi: usize,
) -> bool {
    row_mi + block_size.mi_height() > visible_rows_mi
}

fn should_reduce_width(col_mi: usize, block_size: Av2MvpBlockSize, visible_cols_mi: usize) -> bool {
    col_mi + block_size.mi_width() > visible_cols_mi
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Av2AllowedPartitions {
    none: bool,
    horz: bool,
    vert: bool,
}

impl Av2AllowedPartitions {
    fn contains(self, partition: Av2MvpPartition) -> bool {
        match partition {
            Av2MvpPartition::None => self.none,
            Av2MvpPartition::Horz => self.horz,
            Av2MvpPartition::Vert => self.vert,
        }
    }

    fn only(self) -> Option<Av2MvpPartition> {
        let mut count = 0usize;
        let mut partition = Av2MvpPartition::None;
        for candidate in [
            Av2MvpPartition::None,
            Av2MvpPartition::Horz,
            Av2MvpPartition::Vert,
        ] {
            if self.contains(candidate) {
                count += 1;
                partition = candidate;
            }
        }
        (count == 1).then_some(partition)
    }
}

fn allowed_partitions(
    row_mi: usize,
    col_mi: usize,
    block_size: Av2MvpBlockSize,
    visible_rows_mi: usize,
    visible_cols_mi: usize,
) -> Av2AllowedPartitions {
    let has_rows = row_mi + block_size.mi_height() / 2 < visible_rows_mi;
    let has_cols = col_mi + block_size.mi_width() / 2 < visible_cols_mi;
    let mut allowed = Av2AllowedPartitions {
        none: has_rows && has_cols && partition_aspect_allowed(block_size, Av2MvpPartition::None),
        horz: block_size.subsize_dims(Av2MvpPartition::Horz).is_some()
            && rect_type_implied_by_bsize(block_size) != Some(Av2MvpPartition::Vert)
            && partition_aspect_allowed(block_size, Av2MvpPartition::Horz),
        vert: block_size.subsize_dims(Av2MvpPartition::Vert).is_some()
            && rect_type_implied_by_bsize(block_size) != Some(Av2MvpPartition::Horz)
            && partition_aspect_allowed(block_size, Av2MvpPartition::Vert),
    };
    if !allowed.none && !allowed.horz && !allowed.vert {
        allowed.none = true;
    }
    allowed
}

fn rect_type_implied_by_bsize(block_size: Av2MvpBlockSize) -> Option<Av2MvpPartition> {
    match (block_size.width, block_size.height) {
        (8, 32) | (16, 64) | (8, 64) => Some(Av2MvpPartition::Horz),
        (32, 8) | (64, 16) | (64, 8) => Some(Av2MvpPartition::Vert),
        _ => None,
    }
}

fn partition_aspect_allowed(block_size: Av2MvpBlockSize, partition: Av2MvpPartition) -> bool {
    let Some((width, height)) = block_size.subsize_dims(partition) else {
        return false;
    };
    let max_aspect_ratio = 8usize;
    if width > height * max_aspect_ratio || height > width * max_aspect_ratio {
        if partition == Av2MvpPartition::None {
            return false;
        }
        if width >= height * 8 || height >= width * 8 {
            return false;
        }
    }
    true
}

fn write_partition(
    writer: &mut Av2EntropyWriter,
    decision: Av2TileDecision,
    partition: Av2MvpPartition,
    partition_context: &Av2PartitionContext,
    visible_rows_mi: usize,
    visible_cols_mi: usize,
) {
    let allowed = allowed_partitions(
        decision.row,
        decision.col,
        decision.block_size,
        visible_rows_mi,
        visible_cols_mi,
    );
    if forced_boundary_partition(
        decision.row,
        decision.col,
        decision.block_size,
        visible_rows_mi,
        visible_cols_mi,
    )
    .is_some_and(|forced| forced == partition && allowed.contains(forced))
        || allowed.only().is_some()
    {
        return;
    }

    let do_split = partition != Av2MvpPartition::None;
    if allowed.none {
        let ctx = partition_context.split_context(decision.row, decision.col, decision.block_size);
        let mut cdf = DEFAULT_DO_SPLIT_CDFS[ctx];
        writer.write_symbol(
            "tile.partition.do_split",
            usize::from(do_split),
            &mut cdf,
            2,
            false,
        );
    } else {
        assert!(
            do_split,
            "AV2 do_split is implied when PARTITION_NONE is disallowed"
        );
    }
    if !do_split {
        return;
    }

    if allowed.horz && allowed.vert && rect_type_implied_by_bsize(decision.block_size).is_none() {
        let ctx = partition_context.rect_context(decision.row, decision.col, decision.block_size);
        let mut cdf = DEFAULT_RECT_TYPE_CDFS[ctx];
        writer.write_symbol(
            "tile.partition.rect_type",
            usize::from(partition == Av2MvpPartition::Vert),
            &mut cdf,
            2,
            false,
        );
    }
}

fn write_intra_luma_dc(writer: &mut Av2EntropyWriter, decision: Av2TileDecision) {
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

    if let Some(size_group) = decision.block_size.fsc_size_group() {
        let mut fsc_cdf = DEFAULT_FSC_MODE_CTX0_CDFS[size_group];
        writer.write_symbol("tile.intra.fsc_mode", 0, &mut fsc_cdf, 2, false);
    }
}

fn write_intra_chroma_dc(writer: &mut Av2EntropyWriter, _decision: Av2TileDecision) {
    let mut dpcm_uv_cdf = DEFAULT_DPCM_CDF;
    // AV2 v1.0.0 Section 5.11.55 also signals chroma DPCM in lossless shared
    // tree blocks. The MVP path keeps normal chroma DC prediction.
    writer.write_symbol("tile.intra.use_dpcm_uv", 0, &mut dpcm_uv_cdf, 2, false);

    let mut uv_mode_cdf = DEFAULT_UV_MODE_CTX0_CDF;
    writer.write_symbol("tile.intra.uv_mode_idx_dc", 0, &mut uv_mode_cdf, 8, false);
}

fn write_black_dc_residual_coefficients(
    writer: &mut Av2EntropyWriter,
    decision: Av2TileDecision,
    visible_rows_mi: usize,
    visible_cols_mi: usize,
    contexts: &mut Av2TxbEntropyContexts,
) {
    // AV2 v1.0.0 Sections 5.11.55, 5.20.1 and the AVM
    // av2_read_coeffs_txb() lossless path force TX_4X4 for this intra block.
    // DC_PRED reconstructs 128 at frame/tile boundaries, so a black input
    // needs one negative DC coefficient per TXB. With qindex 0, dequant is 64
    // and the lossless 4x4 inverse WHT divides a DC-only coefficient by four;
    // level 512 therefore produces -128 at every sample after dequant.
    // AV2 v1.0.0 decoding clips residual visits to the visible frame edge;
    // AVM does this through max_block_wide()/max_block_high() after setting
    // the nominal partition block. Match that by emitting only visible TXBs.
    let txb_width = decision
        .block_size
        .tx4x4_width()
        .min(visible_cols_mi.saturating_sub(decision.col));
    let txb_height = decision
        .block_size
        .tx4x4_height()
        .min(visible_rows_mi.saturating_sub(decision.row));
    for row in 0..txb_height {
        let abs_row = decision.row + row;
        for col in 0..txb_width {
            let abs_col = decision.col + col;
            let skip_ctx =
                luma_txb_skip_context(contexts.y_above[abs_col], contexts.y_left[abs_row]);
            let dc_sign_ctx = dc_sign_context(contexts.y_above[abs_col], contexts.y_left[abs_row]);
            write_y_black_dc_txb(writer, skip_ctx, dc_sign_ctx);
            contexts.y_above[abs_col] = NONZERO_NEGATIVE_DC_ENTROPY_CONTEXT;
            contexts.y_left[abs_row] = NONZERO_NEGATIVE_DC_ENTROPY_CONTEXT;
        }
    }

    for row in 0..txb_height {
        let abs_row = decision.row + row;
        for col in 0..txb_width {
            let abs_col = decision.col + col;
            let skip_ctx =
                chroma_txb_skip_base_context(contexts.u_above[abs_col], contexts.u_left[abs_row])
                    + 6;
            write_u_black_dc_txb(writer, skip_ctx);
            contexts.u_above[abs_col] = NONZERO_NEGATIVE_DC_ENTROPY_CONTEXT;
            contexts.u_left[abs_row] = NONZERO_NEGATIVE_DC_ENTROPY_CONTEXT;
        }
    }

    for row in 0..txb_height {
        let abs_row = decision.row + row;
        for col in 0..txb_width {
            let abs_col = decision.col + col;
            let skip_ctx =
                chroma_txb_skip_base_context(contexts.v_above[abs_col], contexts.v_left[abs_row])
                    + 9;
            write_v_black_dc_txb(writer, skip_ctx);
            contexts.v_above[abs_col] = NONZERO_NEGATIVE_DC_ENTROPY_CONTEXT;
            contexts.v_left[abs_row] = NONZERO_NEGATIVE_DC_ENTROPY_CONTEXT;
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

fn partition_context_lookup(block_size: Av2MvpBlockSize) -> (u8, u8) {
    match (block_size.width, block_size.height) {
        (8, 8) => (32 + 30, 32 + 30),
        (8, 16) => (32 + 30, 32 + 28),
        (16, 8) => (32 + 28, 32 + 30),
        (16, 16) => (32 + 28, 32 + 28),
        (16, 32) => (32 + 28, 32 + 24),
        (32, 16) => (32 + 24, 32 + 28),
        (32, 32) => (32 + 24, 32 + 24),
        (32, 64) => (32 + 24, 32 + 16),
        (64, 32) => (32 + 16, 32 + 24),
        (64, 64) => (32 + 16, 32 + 16),
        (8, 32) => (32 + 30, 32 + 24),
        (32, 8) => (32 + 24, 32 + 30),
        (16, 64) => (32 + 28, 32 + 16),
        (64, 16) => (32 + 16, 32 + 28),
        (8, 64) => (32 + 30, 32 + 16),
        (64, 8) => (32 + 16, 32 + 30),
        _ => unreachable!("unsupported AV2 MVP block size"),
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
            .filter(|decision| {
                decision.kind == Av2TileDecisionKind::Partition(Av2MvpPartition::None)
            })
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
                && decision.block_size == Av2MvpBlockSize::BLOCK_64X64
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
            "tile.partition.do_split",
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
    fn av2_black_444_tile_payload_supports_all_8_pixel_geometries() {
        for height in (8..=64).step_by(8) {
            for width in (8..=64).step_by(8) {
                let payload = av2_black_444_tile_entropy_payload(
                    Av2VideoGeometry { width, height },
                    Av2Black444MvpProfile::current(),
                );
                assert!(
                    payload
                        .fields
                        .iter()
                        .any(|field| field.name == "tile.intra.y_mode_idx_dc"),
                    "missing AV2 luma mode for {width}x{height}"
                );
                assert!(
                    payload
                        .fields
                        .iter()
                        .any(|field| field.name.starts_with("tile.coeff.y.txb_nonzero_tx4x4_ctx")),
                    "missing AV2 luma TXB residuals for {width}x{height}"
                );
            }
        }
    }

    #[test]
    fn av2_black_444_tile_payload_emits_boundary_partitions() {
        let payload = av2_black_444_tile_entropy_payload(
            Av2VideoGeometry {
                width: 16,
                height: 8,
            },
            Av2Black444MvpProfile::current(),
        );

        assert!(payload
            .fields
            .iter()
            .any(|field| field.name == "tile.partition.do_split"));
        assert!(payload.symbol_bits > 0);
    }
}
