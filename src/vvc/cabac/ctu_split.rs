use crate::picture::ChromaSampling;
use crate::vvc::{
    MAX_VVC_CHROMA_TUS, MAX_VVC_LUMA_TUS, VVC_CHROMA_AC_COEFFS_PER_TU, VVC_CTU_SIZE,
    VVC_CURRENT_ENCODER_CHROMA_420_TB_SIZE, VVC_CURRENT_MAX_CHROMA_420_BT_SIZE,
    VVC_CURRENT_MAX_CHROMA_420_MTT_DEPTH, VVC_CURRENT_MAX_CHROMA_420_TT_SIZE,
    VVC_CURRENT_MAX_LUMA_BT_SIZE, VVC_CURRENT_MAX_LUMA_LEAF_HEIGHT, VVC_CURRENT_MAX_LUMA_LEAF_SIZE,
    VVC_CURRENT_MAX_LUMA_MTT_DEPTH, VVC_CURRENT_MAX_LUMA_TT_SIZE,
    VVC_CURRENT_MIN_CHROMA_420_QT_SIZE, VVC_CURRENT_MIN_LUMA_CB_SIZE, VVC_CURRENT_MIN_LUMA_QT_SIZE,
    VVC_LUMA_AC_COEFFS_PER_TU,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::vvc) struct VvcCtuPartitionParams {
    pub(in crate::vvc) root_width: usize,
    pub(in crate::vvc) root_height: usize,
    pub(in crate::vvc) visible_width: usize,
    pub(in crate::vvc) visible_height: usize,
    pub(in crate::vvc) chroma_sampling: ChromaSampling,
    pub(in crate::vvc) chroma_tu_count: usize,
    pub(in crate::vvc) luma_tu_count: usize,
    pub(in crate::vvc) luma_tu_abs_levels: [u8; MAX_VVC_LUMA_TUS],
    pub(in crate::vvc) luma_tu_negative: [bool; MAX_VVC_LUMA_TUS],
    pub(in crate::vvc) luma_tu_ac_levels: [[i16; VVC_LUMA_AC_COEFFS_PER_TU]; MAX_VVC_LUMA_TUS],
    pub(in crate::vvc) cb_dc_abs_level: u8,
    pub(in crate::vvc) cb_dc_negative: bool,
    pub(in crate::vvc) cb_tu_dc_levels: [i16; MAX_VVC_CHROMA_TUS],
    pub(in crate::vvc) cr_tu_dc_levels: [i16; MAX_VVC_CHROMA_TUS],
    pub(in crate::vvc) cb_tu_ac_levels: [[i16; VVC_CHROMA_AC_COEFFS_PER_TU]; MAX_VVC_CHROMA_TUS],
    pub(in crate::vvc) cr_tu_ac_levels: [[i16; VVC_CHROMA_AC_COEFFS_PER_TU]; MAX_VVC_CHROMA_TUS],
}

impl VvcCtuPartitionParams {
    pub(in crate::vvc) fn shape(self) -> VvcCtuPartitionShape {
        VvcCtuPartitionShape {
            root_width: self.root_width as u16,
            root_height: self.root_height as u16,
            visible_width: self.visible_width as u16,
            visible_height: self.visible_height as u16,
            chroma_sampling: self.chroma_sampling,
        }
    }

    #[cfg(test)]
    pub(in crate::vvc) fn visible_chroma_width(self) -> u16 {
        // coding_tree() uses luma-coordinate cbWidth/cbHeight even for
        // DUAL_TREE_CHROMA. Chroma subsampling is applied by chroma syntax and
        // transform decisions below the tree, not by shrinking the tree root.
        self.visible_width as u16
    }

    #[cfg(test)]
    pub(in crate::vvc) fn visible_chroma_height(self) -> u16 {
        self.visible_height as u16
    }

    #[cfg(test)]
    pub(in crate::vvc) fn ctu_chroma_root(self) -> VvcCodingTreeNode {
        VvcCodingTreeNode::root(
            self.root_width as u16,
            self.root_height as u16,
            VvcTreeType::DualTreeChroma,
        )
    }
}

pub(in crate::vvc) fn vvc_chroma_420_transform_nodes(
    shape: VvcCtuPartitionShape,
) -> Vec<VvcCodingTreeNode> {
    let mut nodes = Vec::new();
    append_chroma_visible_qt_subtree(
        &mut nodes,
        VvcCodingTreeNode::root(
            shape.root_width,
            shape.root_height,
            VvcTreeType::DualTreeChroma,
        ),
        shape.visible_width,
        shape.visible_height,
    );
    nodes
}

fn append_chroma_visible_qt_subtree(
    nodes: &mut Vec<VvcCodingTreeNode>,
    node: VvcCodingTreeNode,
    visible_width: u16,
    visible_height: u16,
) {
    debug_assert_eq!(node.tree_type, VvcTreeType::DualTreeChroma);
    if !node.intersects_visible(visible_width, visible_height) {
        return;
    }
    if node.fits_visible(visible_width, visible_height) && chroma_leaf_allowed(node) {
        nodes.push(node);
        return;
    }

    if !node.fits_visible(visible_width, visible_height) {
        append_chroma_implicit_boundary_children(nodes, node, visible_width, visible_height);
        return;
    }

    let split = vvc_chroma_420_split_availability(node, visible_width, visible_height);
    if split.allow_qt {
        for child_idx in 0..4 {
            append_chroma_visible_qt_subtree(
                nodes,
                node.qt_child(child_idx),
                visible_width,
                visible_height,
            );
        }
    } else {
        let vertical = chroma_prefer_vertical_bt(node, split);
        for child_idx in 0..2 {
            append_chroma_visible_qt_subtree(
                nodes,
                node.mtt_child(vertical, child_idx),
                visible_width,
                visible_height,
            );
        }
    }
}

fn append_chroma_implicit_boundary_children(
    nodes: &mut Vec<VvcCodingTreeNode>,
    node: VvcCodingTreeNode,
    visible_width: u16,
    visible_height: u16,
) {
    let split = vvc_chroma_420_split_availability(node, visible_width, visible_height);
    if split.allow_qt {
        for child_idx in 0..4 {
            append_chroma_visible_qt_subtree(
                nodes,
                node.qt_child(child_idx),
                visible_width,
                visible_height,
            );
        }
        return;
    }
    match split.implicit_split {
        VvcPartSplit::Quad => {
            for child_idx in 0..4 {
                append_chroma_visible_qt_subtree(
                    nodes,
                    node.qt_child(child_idx),
                    visible_width,
                    visible_height,
                );
            }
        }
        VvcPartSplit::HorizontalBinary => {
            for child_idx in 0..2 {
                append_chroma_visible_qt_subtree(
                    nodes,
                    node.mtt_child_with_boundary_depth_offset(
                        false,
                        child_idx,
                        visible_width,
                        visible_height,
                    ),
                    visible_width,
                    visible_height,
                );
            }
        }
        VvcPartSplit::VerticalBinary => {
            for child_idx in 0..2 {
                append_chroma_visible_qt_subtree(
                    nodes,
                    node.mtt_child_with_boundary_depth_offset(
                        true,
                        child_idx,
                        visible_width,
                        visible_height,
                    ),
                    visible_width,
                    visible_height,
                );
            }
        }
        VvcPartSplit::None => {
            debug_assert!(
                !node.intersects_visible(visible_width, visible_height),
                "boundary chroma node must have an implicit split"
            );
        }
    }
}

fn chroma_leaf_allowed(node: VvcCodingTreeNode) -> bool {
    let chroma_width = vvc_chroma_420_width(node);
    let chroma_height = vvc_chroma_420_height(node);
    // H.266 7.3.11.10 permits transform_unit() after any legal coding-tree
    // leaf. The current residual hardware deliberately chooses legal splits
    // down to 8x8 luma-coordinate leaves, which are 4x4 chroma TUs in 4:2:0.
    // Split availability below still uses the SPS-derived max chroma TB size.
    chroma_width <= VVC_CURRENT_ENCODER_CHROMA_420_TB_SIZE
        && chroma_height <= VVC_CURRENT_ENCODER_CHROMA_420_TB_SIZE
}

pub(in crate::vvc) fn vvc_chroma_420_width(node: VvcCodingTreeNode) -> u16 {
    node.width / 2
}

pub(in crate::vvc) fn vvc_chroma_420_height(node: VvcCodingTreeNode) -> u16 {
    node.height / 2
}

fn chroma_implicit_split(
    node: VvcCodingTreeNode,
    visible_width: u16,
    visible_height: u16,
) -> VvcPartSplit {
    if node.fits_visible(visible_width, visible_height) {
        return VvcPartSplit::None;
    }

    let bottom_left_in_pic = node.x < visible_width && node.y + node.height - 1 < visible_height;
    let top_right_in_pic = node.x + node.width - 1 < visible_width && node.y < visible_height;
    let max_mtt_depth = VVC_CURRENT_MAX_CHROMA_420_MTT_DEPTH + node.depth_offset;
    let bt_allowed = node.width <= VVC_CURRENT_MAX_CHROMA_420_BT_SIZE
        && node.height <= VVC_CURRENT_MAX_CHROMA_420_BT_SIZE
        && node.mtt_depth < max_mtt_depth;
    let qt_allowed = node.width > VVC_CURRENT_MIN_CHROMA_420_QT_SIZE
        && node.height > VVC_CURRENT_MIN_CHROMA_420_QT_SIZE
        && node.mtt_depth == 0;

    // H.266 7.4.12.4 infers split_cu_flag for picture-boundary CUs. VTM's
    // QTBTPartitioner::getImplicitSplit implements the same 6.4.1/6.4.2
    // order: prefer QT when both BL/TR are outside and QT is legal, otherwise
    // use a boundary BT on the out-of-picture axis when available, with QT as
    // the fallback for any remaining boundary node.
    if !bottom_left_in_pic && !top_right_in_pic && qt_allowed {
        VvcPartSplit::Quad
    } else if !bottom_left_in_pic && bt_allowed && node.width <= VVC_CTU_SIZE as u16 {
        VvcPartSplit::HorizontalBinary
    } else if !top_right_in_pic && bt_allowed && node.height <= VVC_CTU_SIZE as u16 {
        VvcPartSplit::VerticalBinary
    } else if node.width > VVC_CTU_SIZE as u16 || node.height > VVC_CTU_SIZE as u16 {
        VvcPartSplit::Quad
    } else if !bottom_left_in_pic || !top_right_in_pic {
        VvcPartSplit::Quad
    } else {
        VvcPartSplit::None
    }
}

pub(in crate::vvc) fn vvc_chroma_420_split_availability(
    node: VvcCodingTreeNode,
    visible_width: u16,
    visible_height: u16,
) -> VvcChromaSplitAvailability {
    let chroma_width = vvc_chroma_420_width(node);
    let chroma_height = vvc_chroma_420_height(node);
    let chroma_area = chroma_width * chroma_height;
    let implicit_split = chroma_implicit_split(node, visible_width, visible_height);
    let max_mtt_depth = VVC_CURRENT_MAX_CHROMA_420_MTT_DEPTH + node.depth_offset;
    let mut can_no = true;
    let mut allow_qt =
        node.parent_split == VvcPartSplit::None || node.parent_split == VvcPartSplit::Quad;
    allow_qt &= node.width > VVC_CURRENT_MIN_CHROMA_420_QT_SIZE;
    allow_qt &= chroma_width > 4;

    // H.266 6.4.2/6.4.3 derive chroma MTT availability from the SPS chroma
    // MTT depth plus the implicit-boundary BT depthOffset carried by the node.
    // The size checks are in luma coordinates except for the dual-tree 4:2:0
    // chroma area/width guards.
    let mut can_btt = node.mtt_depth < max_mtt_depth;
    if can_btt
        && node.width <= VVC_CURRENT_MIN_LUMA_CB_SIZE
        && node.height <= VVC_CURRENT_MIN_LUMA_CB_SIZE
    {
        can_btt = false;
    }
    if can_btt
        && node.width > VVC_CURRENT_MAX_CHROMA_420_BT_SIZE
        && node.height > VVC_CURRENT_MAX_CHROMA_420_BT_SIZE
        && node.width > VVC_CURRENT_MAX_CHROMA_420_TT_SIZE
        && node.height > VVC_CURRENT_MAX_CHROMA_420_TT_SIZE
    {
        can_btt = false;
    }

    let mut allow_bt_horizontal = true;
    let mut allow_bt_vertical = true;
    let mut allow_tt_horizontal = true;
    let mut allow_tt_vertical = true;

    if implicit_split != VvcPartSplit::None {
        can_no = false;
        allow_tt_horizontal = false;
        allow_tt_vertical = false;
        allow_bt_horizontal = implicit_split == VvcPartSplit::HorizontalBinary;
        allow_bt_vertical = implicit_split == VvcPartSplit::VerticalBinary;
        if chroma_width == 4 {
            allow_bt_vertical = false;
        }
        if !allow_bt_horizontal && !allow_bt_vertical && !allow_qt {
            allow_qt = true;
        }
        return VvcChromaSplitAvailability {
            can_no,
            allow_qt,
            allow_bt_vertical,
            allow_bt_horizontal,
            allow_tt_vertical,
            allow_tt_horizontal,
            implicit_split,
        };
    }

    if !can_btt {
        allow_bt_horizontal = false;
        allow_bt_vertical = false;
        allow_tt_horizontal = false;
        allow_tt_vertical = false;
    }

    if node.width > VVC_CURRENT_MAX_CHROMA_420_BT_SIZE
        || node.height > VVC_CURRENT_MAX_CHROMA_420_BT_SIZE
    {
        allow_bt_horizontal = false;
        allow_bt_vertical = false;
    }
    if node.height <= VVC_CURRENT_MIN_LUMA_CB_SIZE
        || (node.width > VVC_CTU_SIZE as u16 && node.height <= VVC_CTU_SIZE as u16)
        || chroma_area <= 16
    {
        allow_bt_horizontal = false;
    }
    if node.width <= VVC_CURRENT_MIN_LUMA_CB_SIZE
        || (node.width <= VVC_CTU_SIZE as u16 && node.height > VVC_CTU_SIZE as u16)
        || chroma_area <= 16
        || chroma_width == 4
    {
        allow_bt_vertical = false;
    }

    if node.height <= 2 * VVC_CURRENT_MIN_LUMA_CB_SIZE
        || node.height > VVC_CURRENT_MAX_CHROMA_420_TT_SIZE
        || node.width > VVC_CURRENT_MAX_CHROMA_420_TT_SIZE
        || node.width > VVC_CTU_SIZE as u16
        || node.height > VVC_CTU_SIZE as u16
        || chroma_area <= 32
    {
        allow_tt_horizontal = false;
    }
    if node.width <= 2 * VVC_CURRENT_MIN_LUMA_CB_SIZE
        || node.width > VVC_CURRENT_MAX_CHROMA_420_TT_SIZE
        || node.height > VVC_CURRENT_MAX_CHROMA_420_TT_SIZE
        || node.width > VVC_CTU_SIZE as u16
        || node.height > VVC_CTU_SIZE as u16
        || chroma_area <= 32
        || chroma_width == 8
    {
        allow_tt_vertical = false;
    }

    VvcChromaSplitAvailability {
        can_no,
        allow_qt,
        allow_bt_vertical,
        allow_bt_horizontal,
        allow_tt_vertical,
        allow_tt_horizontal,
        implicit_split,
    }
}

fn chroma_prefer_vertical_bt(node: VvcCodingTreeNode, split: VvcChromaSplitAvailability) -> bool {
    if !split.allow_bt_vertical {
        return false;
    }
    if !split.allow_bt_horizontal {
        return true;
    }
    // H.266 6.4.1 supplies the available BT directions; this encoder's
    // residual policy chooses legal BT splits that drive both axes toward the
    // 8x8 luma-coordinate leaf used by the current hardware datapath.
    node.width >= node.height
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::vvc) struct VvcChromaSplitAvailability {
    pub(in crate::vvc) can_no: bool,
    pub(in crate::vvc) allow_qt: bool,
    pub(in crate::vvc) allow_bt_vertical: bool,
    pub(in crate::vvc) allow_bt_horizontal: bool,
    pub(in crate::vvc) allow_tt_vertical: bool,
    pub(in crate::vvc) allow_tt_horizontal: bool,
    pub(in crate::vvc) implicit_split: VvcPartSplit,
}

impl VvcChromaSplitAvailability {
    pub(in crate::vvc) fn can_split(self) -> bool {
        self.allow_qt || self.allow_btt()
    }

    pub(in crate::vvc) fn allow_btt(self) -> bool {
        self.allow_bt_vertical
            || self.allow_bt_horizontal
            || self.allow_tt_vertical
            || self.allow_tt_horizontal
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::vvc) struct VvcCtuPartitionShape {
    pub(in crate::vvc) root_width: u16,
    pub(in crate::vvc) root_height: u16,
    pub(in crate::vvc) visible_width: u16,
    pub(in crate::vvc) visible_height: u16,
    pub(in crate::vvc) chroma_sampling: ChromaSampling,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::vvc) enum VvcTreeType {
    SingleTree,
    DualTreeLuma,
    DualTreeChroma,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::vvc) enum VvcPartSplit {
    None,
    Quad,
    HorizontalBinary,
    VerticalBinary,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::vvc) struct VvcCodingTreeNode {
    pub(in crate::vvc) x: u16,
    pub(in crate::vvc) y: u16,
    pub(in crate::vvc) width: u16,
    pub(in crate::vvc) height: u16,
    pub(in crate::vvc) cqt_depth: u8,
    pub(in crate::vvc) mtt_depth: u8,
    pub(in crate::vvc) depth_offset: u8,
    pub(in crate::vvc) part_idx: u8,
    pub(in crate::vvc) parent_split: VvcPartSplit,
    pub(in crate::vvc) tree_type: VvcTreeType,
    pub(in crate::vvc) split_history: [VvcPartSplit; 2],
}

impl VvcCodingTreeNode {
    pub(in crate::vvc) fn root(width: u16, height: u16, tree_type: VvcTreeType) -> Self {
        Self {
            x: 0,
            y: 0,
            width,
            height,
            cqt_depth: 0,
            mtt_depth: 0,
            depth_offset: 0,
            part_idx: 0,
            parent_split: VvcPartSplit::None,
            tree_type,
            split_history: [VvcPartSplit::None; 2],
        }
    }

    fn with_split_at_current_depth(self, split: VvcPartSplit) -> [VvcPartSplit; 2] {
        let mut split_history = self.split_history;
        let depth = usize::from(self.cqt_depth + self.mtt_depth);
        if depth < split_history.len() {
            split_history[depth] = split;
        }
        split_history
    }

    pub(in crate::vvc) fn qt_child(self, child_idx: u8) -> Self {
        debug_assert!(child_idx < 4);
        let half_width = self.width / 2;
        let half_height = self.height / 2;
        Self {
            x: self.x + u16::from(child_idx & 1) * half_width,
            y: self.y + u16::from(child_idx >> 1) * half_height,
            width: half_width,
            height: half_height,
            cqt_depth: self.cqt_depth + 1,
            mtt_depth: 0,
            depth_offset: 0,
            part_idx: child_idx,
            parent_split: VvcPartSplit::Quad,
            tree_type: self.tree_type,
            split_history: self.with_split_at_current_depth(VvcPartSplit::Quad),
        }
    }

    pub(in crate::vvc) fn mtt_child(self, vertical: bool, child_idx: u8) -> Self {
        debug_assert!(child_idx < 2);
        let width = if vertical { self.width / 2 } else { self.width };
        let height = if vertical {
            self.height
        } else {
            self.height / 2
        };
        Self {
            x: self.x + u16::from(vertical) * u16::from(child_idx) * width,
            y: self.y + u16::from(!vertical) * u16::from(child_idx) * height,
            width,
            height,
            cqt_depth: self.cqt_depth,
            mtt_depth: self.mtt_depth + 1,
            depth_offset: self.depth_offset,
            part_idx: child_idx,
            parent_split: if vertical {
                VvcPartSplit::VerticalBinary
            } else {
                VvcPartSplit::HorizontalBinary
            },
            tree_type: self.tree_type,
            split_history: self.with_split_at_current_depth(if vertical {
                VvcPartSplit::VerticalBinary
            } else {
                VvcPartSplit::HorizontalBinary
            }),
        }
    }

    pub(in crate::vvc) fn mtt_child_with_boundary_depth_offset(
        self,
        vertical: bool,
        child_idx: u8,
        visible_width: u16,
        visible_height: u16,
    ) -> Self {
        let mut child = self.mtt_child(vertical, child_idx);
        // H.266 7.3.11.4 increments depthOffset for boundary BT splits that
        // reduce the out-of-picture axis: vertical BT when the parent extends
        // past the right picture boundary, horizontal BT when it extends past
        // the bottom picture boundary. 7.4.12.4 then adds depthOffset to
        // MaxMttDepth for split availability.
        let crosses_reduced_boundary = if vertical {
            self.x + self.width > visible_width
        } else {
            self.y + self.height > visible_height
        };
        child.depth_offset = self.depth_offset + u8::from(crosses_reduced_boundary);
        child
    }

    pub(in crate::vvc) fn intersects_visible(
        self,
        visible_width: u16,
        visible_height: u16,
    ) -> bool {
        self.x < visible_width && self.y < visible_height
    }

    pub(in crate::vvc) fn fits_visible(self, visible_width: u16, visible_height: u16) -> bool {
        self.x + self.width <= visible_width && self.y + self.height <= visible_height
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct VvcLumaNeighbourInfo {
    cb_width: u16,
    cb_height: u16,
    cqt_depth: u8,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct VvcLumaNeighbourState {
    width: u16,
    height: u16,
    valid: Vec<bool>,
    cb_width: Vec<u16>,
    cb_height: Vec<u16>,
    cqt_depth: Vec<u8>,
}

impl VvcLumaNeighbourState {
    fn new(width: u16, height: u16) -> Self {
        let samples = usize::from(width) * usize::from(height);
        Self {
            width,
            height,
            valid: vec![false; samples],
            cb_width: vec![0; samples],
            cb_height: vec![0; samples],
            cqt_depth: vec![0; samples],
        }
    }

    fn index(&self, x: u16, y: u16) -> Option<usize> {
        if x >= self.width || y >= self.height {
            return None;
        }
        Some(usize::from(y) * usize::from(self.width) + usize::from(x))
    }

    fn info_at(&self, x: u16, y: u16) -> Option<VvcLumaNeighbourInfo> {
        let index = self.index(x, y)?;
        self.valid[index].then_some(VvcLumaNeighbourInfo {
            cb_width: self.cb_width[index],
            cb_height: self.cb_height[index],
            cqt_depth: self.cqt_depth[index],
        })
    }

    fn left_of(&self, node: VvcCodingTreeNode) -> Option<VvcLumaNeighbourInfo> {
        node.x.checked_sub(1).and_then(|x| self.info_at(x, node.y))
    }

    fn above_of(&self, node: VvcCodingTreeNode) -> Option<VvcLumaNeighbourInfo> {
        node.y.checked_sub(1).and_then(|y| self.info_at(node.x, y))
    }

    fn mark_leaf(&mut self, node: VvcCodingTreeNode) {
        let end_x = (node.x + node.width).min(self.width);
        let end_y = (node.y + node.height).min(self.height);
        for y in node.y..end_y {
            for x in node.x..end_x {
                let index = self.index(x, y).expect("leaf coordinates are in range");
                self.valid[index] = true;
                self.cb_width[index] = node.width;
                self.cb_height[index] = node.height;
                self.cqt_depth[index] = node.cqt_depth;
            }
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::vvc) struct VvcSplitCtxInput {
    pub(in crate::vvc) available_left: bool,
    pub(in crate::vvc) available_above: bool,
    pub(in crate::vvc) condition_left: bool,
    pub(in crate::vvc) condition_above: bool,
    pub(in crate::vvc) allow_bt_vertical: bool,
    pub(in crate::vvc) allow_bt_horizontal: bool,
    pub(in crate::vvc) allow_tt_vertical: bool,
    pub(in crate::vvc) allow_tt_horizontal: bool,
    pub(in crate::vvc) allow_qt: bool,
}

impl VvcSplitCtxInput {
    fn has_mtt(self) -> bool {
        self.allow_bt_vertical
            || self.allow_bt_horizontal
            || self.allow_tt_vertical
            || self.allow_tt_horizontal
    }

    #[cfg(test)]
    pub(in crate::vvc) fn qt_split_without_neighbours() -> Self {
        Self {
            available_left: false,
            available_above: false,
            condition_left: false,
            condition_above: false,
            allow_bt_vertical: false,
            allow_bt_horizontal: false,
            allow_tt_vertical: false,
            allow_tt_horizontal: false,
            allow_qt: true,
        }
    }

    #[cfg(test)]
    pub(in crate::vvc) fn full_child_without_smaller_neighbours() -> Self {
        Self {
            available_left: false,
            available_above: false,
            condition_left: false,
            condition_above: false,
            allow_bt_vertical: true,
            allow_bt_horizontal: true,
            allow_tt_vertical: true,
            allow_tt_horizontal: true,
            allow_qt: true,
        }
    }

    #[cfg(test)]
    pub(in crate::vvc) fn full_child_with_deeper_neighbours(
        left_deeper: bool,
        above_deeper: bool,
    ) -> Self {
        Self {
            available_left: left_deeper,
            available_above: above_deeper,
            condition_left: left_deeper,
            condition_above: above_deeper,
            allow_bt_vertical: true,
            allow_bt_horizontal: true,
            allow_tt_vertical: true,
            allow_tt_horizontal: true,
            allow_qt: true,
        }
    }

    pub(in crate::vvc) fn split_cu_flag_ctx(self) -> u8 {
        // VVC 9.3.4.2.2 derives ctxInc for split_cu_flag as:
        //   condL + condA + ctxSetIdx * 3
        // with ctxSetIdx =
        //   (allowBtVer + allowBtHor + allowTtVer + allowTtHor
        //    + 2 * allowQt - 1) / 2.
        let split_alternatives = u8::from(self.allow_bt_vertical)
            + u8::from(self.allow_bt_horizontal)
            + u8::from(self.allow_tt_vertical)
            + u8::from(self.allow_tt_horizontal)
            + (2 * u8::from(self.allow_qt));
        debug_assert!(split_alternatives > 0);
        let ctx_set_idx = (split_alternatives - 1) / 2;
        u8::from(self.condition_left && self.available_left)
            + u8::from(self.condition_above && self.available_above)
            + (3 * ctx_set_idx)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::vvc) struct VvcQtSplitCtxInput {
    pub(in crate::vvc) available_left: bool,
    pub(in crate::vvc) available_above: bool,
    pub(in crate::vvc) left_deeper_qt: bool,
    pub(in crate::vvc) above_deeper_qt: bool,
    pub(in crate::vvc) cqt_depth: u8,
}

impl VvcQtSplitCtxInput {
    #[cfg(test)]
    pub(in crate::vvc) fn from_node_without_deeper_neighbours(node: VvcCodingTreeNode) -> Self {
        Self {
            available_left: false,
            available_above: false,
            left_deeper_qt: false,
            above_deeper_qt: false,
            cqt_depth: node.cqt_depth,
        }
    }

    #[cfg(test)]
    pub(in crate::vvc) fn from_node_with_deeper_neighbours(
        node: VvcCodingTreeNode,
        left_deeper_qt: bool,
        above_deeper_qt: bool,
    ) -> Self {
        Self {
            available_left: left_deeper_qt,
            available_above: above_deeper_qt,
            left_deeper_qt,
            above_deeper_qt,
            cqt_depth: node.cqt_depth,
        }
    }

    pub(in crate::vvc) fn split_qt_flag_ctx(self) -> u8 {
        // VVC 9.3.4.2.2 derives ctxInc for split_qt_flag as:
        //   (condL && availableL) + (condA && availableA) + ctxSetIdx * 3
        // where ctxSetIdx is cqtDepth >= 2.
        u8::from(self.left_deeper_qt && self.available_left)
            + u8::from(self.above_deeper_qt && self.available_above)
            + (3 * u8::from(self.cqt_depth >= 2))
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::vvc) enum VvcCtuCabacOp {
    QtSplit {
        node: VvcCodingTreeNode,
        split_ctx: u8,
        write_split_flag: bool,
        write_qt_flag: bool,
        qt_ctx: u8,
    },
    BtSplit {
        node: VvcCodingTreeNode,
        vertical: bool,
        split_ctx: u8,
        write_split_flag: bool,
        write_qt_flag: bool,
        qt_ctx: u8,
        write_mtt_vertical_flag: bool,
        mtt_vertical_ctx: u8,
        write_binary_flag: bool,
        mtt_binary_ctx: u8,
        mtt_binary_value: bool,
    },
    LumaLeafWithSplitCtx {
        node: VvcCodingTreeNode,
        write_split_flag: bool,
        split_ctx: u8,
    },
    ChromaTree {
        node: VvcCodingTreeNode,
        visible_width: u16,
        visible_height: u16,
    },
}

impl VvcCtuCabacOp {
    pub(in crate::vvc) fn yuv420_ctu_partition(params: VvcCtuPartitionParams) -> Vec<Self> {
        Self::intra_ctu_partition(params.shape(), VVC_CURRENT_MAX_LUMA_LEAF_SIZE)
    }

    pub(in crate::vvc) fn intra_ctu_partition(
        shape: VvcCtuPartitionShape,
        max_leaf_size: u16,
    ) -> Vec<Self> {
        let tree_type = match shape.chroma_sampling {
            ChromaSampling::Cs444 => VvcTreeType::SingleTree,
            ChromaSampling::Monochrome | ChromaSampling::Cs420 | ChromaSampling::Cs422 => {
                VvcTreeType::DualTreeLuma
            }
        };
        let root = VvcCodingTreeNode::root(shape.root_width, shape.root_height, tree_type);
        let mut ops = Vec::new();
        let mut neighbours = VvcLumaNeighbourState::new(shape.visible_width, shape.visible_height);
        Self::append_visible_luma_subtree(
            &mut ops,
            &mut neighbours,
            root,
            shape.visible_width,
            shape.visible_height,
            max_leaf_size,
        );
        if shape.chroma_sampling != ChromaSampling::Cs444
            && shape.chroma_sampling != ChromaSampling::Monochrome
        {
            ops.push(Self::ChromaTree {
                node: VvcCodingTreeNode::root(
                    shape.root_width,
                    shape.root_height,
                    VvcTreeType::DualTreeChroma,
                ),
                visible_width: shape.visible_width,
                visible_height: shape.visible_height,
            });
        }
        ops
    }

    fn append_visible_luma_subtree(
        ops: &mut Vec<Self>,
        neighbours: &mut VvcLumaNeighbourState,
        node: VvcCodingTreeNode,
        visible_width: u16,
        visible_height: u16,
        max_leaf_size: u16,
    ) {
        if !node.intersects_visible(visible_width, visible_height) {
            return;
        }
        if node.fits_visible(visible_width, visible_height)
            && Self::luma_leaf_allowed(node, max_leaf_size)
        {
            let split = Self::luma_split_availability(node, visible_width, visible_height);
            let write_split_flag = split.has_mtt() || split.allow_qt;
            ops.push(Self::LumaLeafWithSplitCtx {
                node,
                write_split_flag,
                split_ctx: if write_split_flag {
                    Self::luma_split_ctx(node, split, neighbours)
                } else {
                    0
                },
            });
            neighbours.mark_leaf(node);
            return;
        }

        if !node.fits_visible(visible_width, visible_height) {
            Self::append_implicit_boundary_luma_children(
                ops,
                neighbours,
                node,
                visible_width,
                visible_height,
                max_leaf_size,
            );
            return;
        }

        debug_assert!(node.width > max_leaf_size || node.height > VVC_CURRENT_MAX_LUMA_LEAF_HEIGHT);
        if node.mtt_depth > 0 {
            Self::append_visible_luma_mtt_subtree(
                ops,
                neighbours,
                node,
                visible_width,
                visible_height,
                max_leaf_size,
            );
            return;
        }
        let split = Self::luma_split_availability(node, visible_width, visible_height);
        ops.push(Self::QtSplit {
            node,
            split_ctx: Self::luma_split_ctx(node, split, neighbours),
            write_split_flag: true,
            write_qt_flag: split.allow_qt && split.has_mtt(),
            qt_ctx: Self::luma_qt_split_ctx(node, neighbours),
        });
        for child_idx in 0..4 {
            Self::append_visible_luma_subtree(
                ops,
                neighbours,
                node.qt_child(child_idx),
                visible_width,
                visible_height,
                max_leaf_size,
            );
        }
    }

    fn append_visible_luma_mtt_subtree(
        ops: &mut Vec<Self>,
        neighbours: &mut VvcLumaNeighbourState,
        node: VvcCodingTreeNode,
        visible_width: u16,
        visible_height: u16,
        max_leaf_size: u16,
    ) {
        let vertical = node.width > max_leaf_size
            && (node.height <= max_leaf_size || node.width >= node.height);
        let split = Self::luma_split_availability(node, visible_width, visible_height);
        let can_hor = split.allow_bt_horizontal || split.allow_tt_horizontal;
        let can_ver = split.allow_bt_vertical || split.allow_tt_vertical;
        let can_binary = if vertical {
            split.allow_bt_vertical
        } else {
            split.allow_bt_horizontal
        };
        let can_ternary = if vertical {
            split.allow_tt_vertical
        } else {
            split.allow_tt_horizontal
        };
        ops.push(Self::BtSplit {
            node,
            vertical,
            split_ctx: Self::luma_split_ctx(node, split, neighbours),
            write_split_flag: true,
            write_qt_flag: split.allow_qt && split.has_mtt(),
            qt_ctx: Self::luma_qt_split_ctx(node, neighbours),
            write_mtt_vertical_flag: can_hor && can_ver,
            mtt_vertical_ctx: Self::luma_mtt_vertical_ctx(node, split, neighbours),
            write_binary_flag: can_binary && can_ternary,
            mtt_binary_ctx: Self::mtt_binary_ctx(vertical, node.mtt_depth),
            mtt_binary_value: true,
        });
        for child_idx in 0..2 {
            Self::append_visible_luma_subtree(
                ops,
                neighbours,
                node.mtt_child_with_boundary_depth_offset(
                    vertical,
                    child_idx,
                    visible_width,
                    visible_height,
                ),
                visible_width,
                visible_height,
                max_leaf_size,
            );
        }
    }

    fn append_implicit_boundary_luma_children(
        ops: &mut Vec<Self>,
        neighbours: &mut VvcLumaNeighbourState,
        node: VvcCodingTreeNode,
        visible_width: u16,
        visible_height: u16,
        max_leaf_size: u16,
    ) {
        let bottom_left_in_pic =
            node.x < visible_width && node.y + node.height - 1 < visible_height;
        let top_right_in_pic = node.x + node.width - 1 < visible_width && node.y < visible_height;
        let split = Self::luma_split_availability(node, visible_width, visible_height);
        if !bottom_left_in_pic && !top_right_in_pic {
            for child_idx in 0..4 {
                Self::append_visible_luma_subtree(
                    ops,
                    neighbours,
                    node.qt_child(child_idx),
                    visible_width,
                    visible_height,
                    max_leaf_size,
                );
            }
        } else if !bottom_left_in_pic
            && top_right_in_pic
            && Self::boundary_qt_preferred(node, max_leaf_size)
        {
            ops.push(Self::QtSplit {
                node,
                split_ctx: Self::luma_split_ctx(node, split, neighbours),
                write_split_flag: false,
                write_qt_flag: split.allow_qt && split.has_mtt(),
                qt_ctx: Self::luma_qt_split_ctx(node, neighbours),
            });
            for child_idx in 0..4 {
                Self::append_visible_luma_subtree(
                    ops,
                    neighbours,
                    node.qt_child(child_idx),
                    visible_width,
                    visible_height,
                    max_leaf_size,
                );
            }
        } else if !bottom_left_in_pic && split.allow_bt_horizontal {
            let can_hor = split.allow_bt_horizontal || split.allow_tt_horizontal;
            let can_ver = split.allow_bt_vertical || split.allow_tt_vertical;
            ops.push(Self::BtSplit {
                node,
                vertical: false,
                split_ctx: Self::luma_split_ctx(node, split, neighbours),
                write_split_flag: false,
                write_qt_flag: split.allow_qt && split.has_mtt(),
                qt_ctx: Self::luma_qt_split_ctx(node, neighbours),
                write_mtt_vertical_flag: can_hor && can_ver,
                mtt_vertical_ctx: Self::luma_mtt_vertical_ctx(node, split, neighbours),
                write_binary_flag: split.allow_bt_horizontal && split.allow_tt_horizontal,
                mtt_binary_ctx: Self::mtt_binary_ctx(false, node.mtt_depth),
                mtt_binary_value: true,
            });
            for child_idx in 0..2 {
                Self::append_visible_luma_subtree(
                    ops,
                    neighbours,
                    node.mtt_child_with_boundary_depth_offset(
                        false,
                        child_idx,
                        visible_width,
                        visible_height,
                    ),
                    visible_width,
                    visible_height,
                    max_leaf_size,
                );
            }
        } else if !top_right_in_pic && split.allow_bt_vertical {
            let can_hor = split.allow_bt_horizontal || split.allow_tt_horizontal;
            let can_ver = split.allow_bt_vertical || split.allow_tt_vertical;
            ops.push(Self::BtSplit {
                node,
                vertical: true,
                split_ctx: Self::luma_split_ctx(node, split, neighbours),
                write_split_flag: false,
                write_qt_flag: split.allow_qt && split.has_mtt(),
                qt_ctx: Self::luma_qt_split_ctx(node, neighbours),
                write_mtt_vertical_flag: can_hor && can_ver,
                mtt_vertical_ctx: Self::luma_mtt_vertical_ctx(node, split, neighbours),
                write_binary_flag: split.allow_bt_vertical && split.allow_tt_vertical,
                mtt_binary_ctx: Self::mtt_binary_ctx(true, node.mtt_depth),
                mtt_binary_value: true,
            });
            for child_idx in 0..2 {
                Self::append_visible_luma_subtree(
                    ops,
                    neighbours,
                    node.mtt_child_with_boundary_depth_offset(
                        true,
                        child_idx,
                        visible_width,
                        visible_height,
                    ),
                    visible_width,
                    visible_height,
                    max_leaf_size,
                );
            }
        } else {
            for child_idx in 0..4 {
                Self::append_visible_luma_subtree(
                    ops,
                    neighbours,
                    node.qt_child(child_idx),
                    visible_width,
                    visible_height,
                    max_leaf_size,
                );
            }
        }
    }

    fn boundary_qt_preferred(node: VvcCodingTreeNode, max_leaf_size: u16) -> bool {
        Self::qt_flag_can_be_signaled(node)
            && node.width > max_leaf_size
            && node.height > VVC_CURRENT_MAX_LUMA_LEAF_HEIGHT
    }

    fn luma_split_ctx(
        node: VvcCodingTreeNode,
        mut split: VvcSplitCtxInput,
        neighbours: &VvcLumaNeighbourState,
    ) -> u8 {
        // H.266 9.3.4.2.2 Table 133 derives split_cu_flag condL from the
        // left neighbour CbHeight being smaller than the current cbHeight, and
        // condA from the above neighbour CbWidth being smaller than cbWidth.
        let left = neighbours.left_of(node);
        let above = neighbours.above_of(node);
        split.available_left = left.is_some();
        split.available_above = above.is_some();
        split.condition_left = left.is_some_and(|info| info.cb_height < node.height);
        split.condition_above = above.is_some_and(|info| info.cb_width < node.width);
        split.split_cu_flag_ctx()
    }

    fn luma_qt_split_ctx(node: VvcCodingTreeNode, neighbours: &VvcLumaNeighbourState) -> u8 {
        // H.266 9.3.4.2.2 Table 133 derives split_qt_flag condL/condA from
        // neighbouring CqtDepth being greater than the current cqtDepth.
        let left = neighbours.left_of(node);
        let above = neighbours.above_of(node);
        VvcQtSplitCtxInput {
            available_left: left.is_some(),
            available_above: above.is_some(),
            left_deeper_qt: left.is_some_and(|info| info.cqt_depth > node.cqt_depth),
            above_deeper_qt: above.is_some_and(|info| info.cqt_depth > node.cqt_depth),
            cqt_depth: node.cqt_depth,
        }
        .split_qt_flag_ctx()
    }

    fn luma_mtt_vertical_ctx(
        node: VvcCodingTreeNode,
        split: VvcSplitCtxInput,
        neighbours: &VvcLumaNeighbourState,
    ) -> u8 {
        // H.266 9.3.4.2.3 first compares the number of vertical-vs-horizontal
        // BT/TT choices. If tied, it uses left/above neighbouring block sizes.
        let vertical_choices =
            u8::from(split.allow_bt_vertical) + u8::from(split.allow_tt_vertical);
        let horizontal_choices =
            u8::from(split.allow_bt_horizontal) + u8::from(split.allow_tt_horizontal);
        if vertical_choices > horizontal_choices {
            return 4;
        }
        if vertical_choices < horizontal_choices {
            return 3;
        }
        let Some(above) = neighbours.above_of(node) else {
            return 0;
        };
        let Some(left) = neighbours.left_of(node) else {
            return 0;
        };
        let d_a = node.width / above.cb_width.max(1);
        let d_l = node.height / left.cb_height.max(1);
        if d_a == d_l {
            0
        } else if d_a < d_l {
            1
        } else {
            2
        }
    }

    fn luma_split_availability(
        node: VvcCodingTreeNode,
        visible_width: u16,
        visible_height: u16,
    ) -> VvcSplitCtxInput {
        // H.266 7.4.12.4 derives allowSplitQt/BT/TT by invoking 6.4.1,
        // 6.4.2 and 6.4.3. This implementation is intentionally written in
        // those terms so future SPS/profile changes update one availability
        // model instead of geometry-specific branches.
        let allow_qt = Self::qt_flag_can_be_signaled(node);
        let max_mtt_depth = VVC_CURRENT_MAX_LUMA_MTT_DEPTH + node.depth_offset;
        let allow_bt_vertical =
            Self::allow_luma_bt_split(node, true, visible_width, visible_height, max_mtt_depth);
        let allow_bt_horizontal =
            Self::allow_luma_bt_split(node, false, visible_width, visible_height, max_mtt_depth);
        let allow_tt_vertical =
            Self::allow_luma_tt_split(node, true, visible_width, visible_height, max_mtt_depth);
        let allow_tt_horizontal =
            Self::allow_luma_tt_split(node, false, visible_width, visible_height, max_mtt_depth);

        VvcSplitCtxInput {
            available_left: false,
            available_above: false,
            condition_left: false,
            condition_above: false,
            allow_bt_vertical,
            allow_bt_horizontal,
            allow_tt_vertical,
            allow_tt_horizontal,
            allow_qt,
        }
    }

    fn allow_luma_bt_split(
        node: VvcCodingTreeNode,
        vertical: bool,
        visible_width: u16,
        visible_height: u16,
        max_mtt_depth: u8,
    ) -> bool {
        // H.266 6.4.2, luma intra subset. MinBtSizeY is MinCbSizeY.
        let cb_size = if vertical { node.width } else { node.height };
        if cb_size <= VVC_CURRENT_MIN_LUMA_CB_SIZE {
            return false;
        }
        if node.width > VVC_CURRENT_MAX_LUMA_BT_SIZE
            || node.height > VVC_CURRENT_MAX_LUMA_BT_SIZE
            || node.mtt_depth >= max_mtt_depth
        {
            return false;
        }
        let crosses_right = node.x + node.width > visible_width;
        let crosses_bottom = node.y + node.height > visible_height;
        if vertical && crosses_bottom {
            return false;
        }
        if !vertical && crosses_right && !crosses_bottom {
            return false;
        }
        if crosses_right && crosses_bottom && node.width > VVC_CURRENT_MIN_LUMA_QT_SIZE {
            return false;
        }
        // The parallel ternary-split exclusion from H.266 6.4.2 is kept
        // explicit for future TT support. The current luma partitioner only
        // selects BT, so the previous split cannot be the parallel TT mode.
        let _part_idx = node.part_idx;
        true
    }

    fn allow_luma_tt_split(
        node: VvcCodingTreeNode,
        vertical: bool,
        visible_width: u16,
        visible_height: u16,
        max_mtt_depth: u8,
    ) -> bool {
        // H.266 6.4.3, luma intra subset. TT is not available for boundary
        // nodes, which is why boundary split syntax often infers the binary
        // flag rather than writing it.
        let cb_size = if vertical { node.width } else { node.height };
        if cb_size <= 2 * VVC_CURRENT_MIN_LUMA_CB_SIZE {
            return false;
        }
        if node.width > VVC_CURRENT_MAX_LUMA_TT_SIZE.min(64)
            || node.height > VVC_CURRENT_MAX_LUMA_TT_SIZE.min(64)
            || node.mtt_depth >= max_mtt_depth
            || node.x + node.width > visible_width
            || node.y + node.height > visible_height
        {
            return false;
        }
        true
    }

    fn luma_leaf_allowed(node: VvcCodingTreeNode, max_leaf_size: u16) -> bool {
        // The current residual path emits one transform_unit() per luma CU
        // leaf. Until transform-tree splitting is implemented inside larger
        // CUs, luma leaves must stay within the supported 8x8 TB subset.
        // Larger legal CUs will be re-enabled together with explicit TU
        // partitioning under coding_unit().
        node.width <= max_leaf_size && node.height <= VVC_CURRENT_MAX_LUMA_LEAF_HEIGHT
    }

    pub(in crate::vvc) fn mtt_binary_ctx(vertical: bool, mtt_depth: u8) -> u8 {
        // ITU-T H.266 clause 9.3.4.2.1, Table 132:
        // ctxInc = (2 * mtt_split_cu_vertical_flag) + (mttDepth <= 1 ? 1 : 0).
        (2 * u8::from(vertical)) + u8::from(mtt_depth <= 1)
    }

    pub(in crate::vvc) fn qt_flag_can_be_signaled(node: VvcCodingTreeNode) -> bool {
        let min_qt_size = match node.tree_type {
            VvcTreeType::SingleTree | VvcTreeType::DualTreeLuma => VVC_CURRENT_MIN_LUMA_QT_SIZE,
            VvcTreeType::DualTreeChroma => VVC_CURRENT_MIN_CHROMA_420_QT_SIZE,
        };
        node.mtt_depth == 0 && node.width > min_qt_size && node.height > min_qt_size
    }
}
