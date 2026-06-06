use super::ctu_split::{
    vvc_chroma_420_height, vvc_chroma_420_split_availability, vvc_chroma_420_width,
    VvcChromaSplitAvailability, VvcCodingTreeNode, VvcCtuCabacOp, VvcCtuPartitionParams,
    VvcPartSplit, VvcQtSplitCtxInput, VvcSplitCtxInput, VvcTreeType,
};
use super::{VvcCabacContext, VvcCabacContexts, VvcCabacEncoder};
use crate::vvc::residual::{VvcResidualCabacEncoder, VvcResidualCabacSymbolStream};
use crate::vvc::{
    VvcResidualComponent, VvcSliceSyntaxConfig, MAX_VVC_CHROMA_TUS, MAX_VVC_LUMA_TUS,
    VVC_CHROMA_AC_COEFFS_PER_TU, VVC_CHROMA_AC_POSITIONS_2X2,
    VVC_CURRENT_ENCODER_CHROMA_420_TB_SIZE, VVC_CURRENT_MAX_LUMA_MTT_DEPTH,
    VVC_LUMA_AC_COEFFS_PER_TU,
};

pub(in crate::vvc) fn encode_ctu_partition_body(
    cabac: &mut VvcCabacEncoder,
    params: VvcCtuPartitionParams,
    slice_config: VvcSliceSyntaxConfig,
) {
    let mut ctu = VvcCtuCabacGenerator::new(
        params.luma_tu_count,
        params.luma_tu_abs_levels,
        params.luma_tu_negative,
        params.luma_tu_ac_levels,
        params.chroma_tu_count,
        params.cb_tu_dc_levels,
        params.cr_tu_dc_levels,
        params.cb_tu_ac_levels,
        params.cr_tu_ac_levels,
        slice_config,
    );
    for op in VvcCtuCabacOp::yuv420_ctu_partition(params) {
        ctu.emit(cabac, op);
    }
}

#[derive(Debug, Clone)]
pub(in crate::vvc) struct VvcCtuCabacGenerator {
    contexts: VvcCabacContexts,
    luma_tu_count: usize,
    luma_tu_abs_levels: [u8; MAX_VVC_LUMA_TUS],
    luma_tu_negative: [bool; MAX_VVC_LUMA_TUS],
    luma_tu_ac_levels: [[i16; VVC_LUMA_AC_COEFFS_PER_TU]; MAX_VVC_LUMA_TUS],
    luma_tu_index: usize,
    chroma_tu_count: usize,
    cb_tu_dc_levels: [i16; MAX_VVC_CHROMA_TUS],
    cr_tu_dc_levels: [i16; MAX_VVC_CHROMA_TUS],
    cb_tu_ac_levels: [[i16; VVC_CHROMA_AC_COEFFS_PER_TU]; MAX_VVC_CHROMA_TUS],
    cr_tu_ac_levels: [[i16; VVC_CHROMA_AC_COEFFS_PER_TU]; MAX_VVC_CHROMA_TUS],
    chroma_tu_index: usize,
    slice_config: VvcSliceSyntaxConfig,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct VvcChromaNeighbourInfo {
    cb_width: u16,
    cb_height: u16,
    cqt_depth: u8,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct VvcChromaNeighbourState {
    width: u16,
    height: u16,
    valid: Vec<bool>,
    cb_width: Vec<u16>,
    cb_height: Vec<u16>,
    cqt_depth: Vec<u8>,
}

impl VvcChromaNeighbourState {
    fn new(visible_width: u16, visible_height: u16) -> Self {
        let width = visible_width / 2;
        let height = visible_height / 2;
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

    fn info_at(&self, x: u16, y: u16) -> Option<VvcChromaNeighbourInfo> {
        let index = self.index(x, y)?;
        self.valid[index].then_some(VvcChromaNeighbourInfo {
            cb_width: self.cb_width[index],
            cb_height: self.cb_height[index],
            cqt_depth: self.cqt_depth[index],
        })
    }

    fn left_of(&self, node: VvcCodingTreeNode) -> Option<VvcChromaNeighbourInfo> {
        let y = node.y / 2;
        (node.x / 2).checked_sub(1).and_then(|x| self.info_at(x, y))
    }

    fn above_of(&self, node: VvcCodingTreeNode) -> Option<VvcChromaNeighbourInfo> {
        let x = node.x / 2;
        (node.y / 2).checked_sub(1).and_then(|y| self.info_at(x, y))
    }

    fn mark_leaf(&mut self, node: VvcCodingTreeNode) {
        let start_x = node.x / 2;
        let start_y = node.y / 2;
        let end_x = (start_x + vvc_chroma_420_width(node)).min(self.width);
        let end_y = (start_y + vvc_chroma_420_height(node)).min(self.height);
        for y in start_y..end_y {
            for x in start_x..end_x {
                let index = self
                    .index(x, y)
                    .expect("chroma leaf coordinates are in range");
                self.valid[index] = true;
                self.cb_width[index] = vvc_chroma_420_width(node);
                self.cb_height[index] = vvc_chroma_420_height(node);
                self.cqt_depth[index] = node.cqt_depth;
            }
        }
    }
}

impl VvcCtuCabacGenerator {
    pub(in crate::vvc) fn new(
        luma_tu_count: usize,
        luma_tu_abs_levels: [u8; MAX_VVC_LUMA_TUS],
        luma_tu_negative: [bool; MAX_VVC_LUMA_TUS],
        luma_tu_ac_levels: [[i16; VVC_LUMA_AC_COEFFS_PER_TU]; MAX_VVC_LUMA_TUS],
        chroma_tu_count: usize,
        cb_tu_dc_levels: [i16; MAX_VVC_CHROMA_TUS],
        cr_tu_dc_levels: [i16; MAX_VVC_CHROMA_TUS],
        cb_tu_ac_levels: [[i16; VVC_CHROMA_AC_COEFFS_PER_TU]; MAX_VVC_CHROMA_TUS],
        cr_tu_ac_levels: [[i16; VVC_CHROMA_AC_COEFFS_PER_TU]; MAX_VVC_CHROMA_TUS],
        slice_config: VvcSliceSyntaxConfig,
    ) -> Self {
        Self {
            contexts: VvcCabacContexts::new(),
            luma_tu_count,
            luma_tu_abs_levels,
            luma_tu_negative,
            luma_tu_ac_levels,
            luma_tu_index: 0,
            chroma_tu_count,
            cb_tu_dc_levels,
            cr_tu_dc_levels,
            cb_tu_ac_levels,
            cr_tu_ac_levels,
            chroma_tu_index: 0,
            slice_config,
        }
    }

    pub(in crate::vvc) fn emit(&mut self, cabac: &mut VvcCabacEncoder, op: VvcCtuCabacOp) {
        if std::env::var_os("FRAMEFORGE_CABAC_OP_TRACE").is_some() {
            eprintln!("FF_CABAC_OP {op:?}");
        }
        match op {
            VvcCtuCabacOp::QtSplit {
                node,
                split_ctx,
                write_split_flag,
                write_qt_flag,
                qt_ctx,
            } => self.emit_qt_split(
                cabac,
                node,
                split_ctx,
                write_split_flag,
                write_qt_flag,
                qt_ctx,
            ),
            op @ VvcCtuCabacOp::BtSplit { .. } => self.emit_bt_split(cabac, op),
            VvcCtuCabacOp::LumaLeafWithSplitCtx {
                node,
                write_split_flag,
                split_ctx,
            } => {
                self.emit_luma_leaf_split_with_ctx(cabac, node, write_split_flag, split_ctx);
                self.emit_luma_multi_ref_line(cabac, node);
                self.emit_luma_intra_prediction_mode(cabac, node);
                self.emit_luma_residual(cabac, node);
            }
            VvcCtuCabacOp::ChromaTree {
                node,
                visible_width,
                visible_height,
            } => self.emit_chroma_tree(cabac, node, visible_width, visible_height),
        }
    }

    fn emit_bt_split(&mut self, cabac: &mut VvcCabacEncoder, op: VvcCtuCabacOp) {
        let VvcCtuCabacOp::BtSplit {
            node,
            vertical,
            split_ctx,
            write_split_flag,
            write_qt_flag,
            qt_ctx,
            write_mtt_vertical_flag,
            mtt_vertical_ctx,
            write_binary_flag,
            mtt_binary_ctx,
            mtt_binary_value,
        } = op
        else {
            unreachable!("emit_bt_split expects a binary split operation");
        };
        debug_assert!(node.cqt_depth >= 1 || node.mtt_depth > 0 || (node.x == 0 && node.y == 0));
        debug_assert_eq!(node.tree_type, VvcTreeType::DualTreeLuma);
        if write_split_flag {
            self.contexts
                .encode(cabac, VvcCabacContext::SplitFlag(split_ctx), true);
        }
        if write_qt_flag {
            self.contexts
                .encode(cabac, VvcCabacContext::SplitQtFlag(qt_ctx), false);
        }
        if write_mtt_vertical_flag {
            self.contexts.encode(
                cabac,
                VvcCabacContext::MttSplitCuVerticalFlag(mtt_vertical_ctx),
                vertical,
            );
        }
        if write_binary_flag {
            self.contexts.encode(
                cabac,
                VvcCabacContext::MttSplitCuBinaryFlag(mtt_binary_ctx),
                mtt_binary_value,
            );
        }
    }

    fn emit_qt_split(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        node: VvcCodingTreeNode,
        split_ctx: u8,
        write_split_flag: bool,
        write_qt_flag: bool,
        qt_ctx: u8,
    ) {
        debug_assert!(node.cqt_depth <= 3);
        debug_assert_eq!(node.mtt_depth, 0);
        debug_assert_eq!(node.tree_type, VvcTreeType::DualTreeLuma);
        // VVC 7.3.11.4 coding_tree emits split_cu_flag for QT-split luma
        // nodes. Some root-only geometries infer split_qt_flag, while boundary
        // constrained rectangular CTU views write it explicitly.
        if write_split_flag {
            self.contexts
                .encode(cabac, VvcCabacContext::SplitFlag(split_ctx), true);
        }
        if write_qt_flag {
            self.contexts
                .encode(cabac, VvcCabacContext::SplitQtFlag(qt_ctx), true);
        }
    }

    fn emit_luma_leaf_split_with_ctx(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        node: VvcCodingTreeNode,
        write_split_flag: bool,
        split_ctx: u8,
    ) {
        debug_assert!(node.cqt_depth >= 1 || node.mtt_depth > 0 || (node.x == 0 && node.y == 0));
        debug_assert!(node.mtt_depth <= VVC_CURRENT_MAX_LUMA_MTT_DEPTH + node.depth_offset);
        debug_assert_eq!(node.tree_type, VvcTreeType::DualTreeLuma);
        if !write_split_flag {
            return;
        }
        self.contexts
            .encode(cabac, VvcCabacContext::SplitFlag(split_ctx), false);
    }

    fn emit_luma_intra_prediction_mode(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        node: VvcCodingTreeNode,
    ) {
        debug_assert_eq!(node.tree_type, VvcTreeType::DualTreeLuma);
        // VVC 7.3.11.5 intra_luma_pred_modes. Select MPM index 1, which is
        // DC_IDX for the current all-intra non-angular neighbourhoods (see
        // VTM PU::getIntraMPMs). This keeps software reconstruction tied to a
        // simple, explicit prediction mode instead of an arbitrary remaining
        // mode.
        self.contexts
            .encode(cabac, VvcCabacContext::IntraLumaMpmFlag, true);
        self.contexts
            .encode(cabac, VvcCabacContext::IntraLumaPlanarFlag(1), true);
        cabac.encode_bin_ep(false);
    }

    fn emit_luma_multi_ref_line(&mut self, cabac: &mut VvcCabacEncoder, node: VvcCodingTreeNode) {
        debug_assert_eq!(node.tree_type, VvcTreeType::DualTreeLuma);
        // With sps_mrl_enabled_flag set, VVC extend_ref_line emits
        // MultiRefLineIdx(0) for intra luma CUs that are not on the first
        // luma line of the CTU. The current encoder always selects the first
        // reference line, so only the first MRL bin is needed.
        if self.slice_config.tools.mrl_enabled && node.y != 0 {
            self.contexts
                .encode(cabac, VvcCabacContext::MultiRefLineIdx(0), false);
        }
    }

    fn emit_luma_cbf(&mut self, cabac: &mut VvcCabacEncoder, node: VvcCodingTreeNode, cbf: bool) {
        debug_assert_eq!(node.tree_type, VvcTreeType::DualTreeLuma);
        // VVC 7.3.11.10 transform_unit emits tu_y_coded_flag / cbf_comp
        // through QtCbf[Y].
        self.contexts.encode(cabac, VvcCabacContext::QtCbfY(0), cbf);
    }

    fn emit_luma_residual(&mut self, cabac: &mut VvcCabacEncoder, node: VvcCodingTreeNode) {
        let tu_idx = self.luma_tu_index;
        self.luma_tu_index += 1;
        assert!(
            tu_idx < self.luma_tu_count,
            "missing luma TU coefficient data for coding-tree leaf {tu_idx}"
        );
        let dc_abs_level = self.luma_tu_abs_levels[tu_idx];
        let dc_negative = self.luma_tu_negative[tu_idx];
        let ac_levels = self.luma_tu_ac_levels[tu_idx];
        let has_ac = ac_levels.iter().any(|level| *level != 0);
        let cbf = dc_abs_level != 0 || has_ac;
        self.emit_luma_cbf(cabac, node, cbf);
        if !cbf {
            return;
        }

        let log2_width = node.width.ilog2() as u8;
        let log2_height = node.height.ilog2() as u8;
        let width = usize::from(node.width);
        let height = usize::from(node.height);
        let mut coeff_levels = vec![0; width * height];
        coeff_levels[0] = if dc_abs_level == 0 {
            0
        } else if dc_negative {
            -(dc_abs_level as i16)
        } else {
            dc_abs_level as i16
        };
        // The current transform side exposes the first 4x4 AC positions. Keep
        // them wired through the normal residual coefficient path even when
        // they are all zero; future transform work should only change the
        // coefficient values, not reselect a different CABAC writer.
        for (ac_idx, level) in ac_levels.iter().enumerate() {
            let local = ac_idx + 1;
            let x = local % 4;
            let y = local / 4;
            if x < width && y < height {
                coeff_levels[y * width + x] = *level;
            }
        }
        let stream =
            VvcResidualCabacSymbolStream::luma_coefficients(log2_width, log2_height, &coeff_levels);
        let mut residual =
            VvcResidualCabacEncoder::new(&mut self.contexts, self.slice_config.residual_options());
        stream.emit(&mut residual, cabac);
    }

    fn emit_chroma_tree(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        node: VvcCodingTreeNode,
        visible_width: u16,
        visible_height: u16,
    ) {
        debug_assert_eq!(node.tree_type, VvcTreeType::DualTreeChroma);
        let mut neighbours = VvcChromaNeighbourState::new(visible_width, visible_height);
        self.emit_chroma_visible_qt_subtree(
            cabac,
            node,
            visible_width,
            visible_height,
            4,
            &mut neighbours,
        );
    }

    fn emit_chroma_visible_qt_subtree(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        node: VvcCodingTreeNode,
        visible_width: u16,
        visible_height: u16,
        min_leaf_size: u16,
        neighbours: &mut VvcChromaNeighbourState,
    ) {
        debug_assert_eq!(node.tree_type, VvcTreeType::DualTreeChroma);
        if !node.intersects_visible(visible_width, visible_height) {
            return;
        }
        if node.fits_visible(visible_width, visible_height) && Self::chroma_leaf_allowed(node) {
            self.emit_chroma_transform_only_leaf(
                cabac,
                node,
                vvc_chroma_420_split_availability(node, visible_width, visible_height),
                0,
                neighbours,
            );
            return;
        }

        if !node.fits_visible(visible_width, visible_height) {
            self.emit_chroma_implicit_boundary_children(
                cabac,
                node,
                visible_width,
                visible_height,
                min_leaf_size,
                neighbours,
            );
            return;
        }

        let split = vvc_chroma_420_split_availability(node, visible_width, visible_height);
        if split.allow_qt {
            self.emit_chroma_visible_qt_split(cabac, node, split, neighbours);
            for child_idx in 0..4 {
                self.emit_chroma_visible_qt_subtree(
                    cabac,
                    node.qt_child(child_idx),
                    visible_width,
                    visible_height,
                    min_leaf_size,
                    neighbours,
                );
            }
        } else {
            // H.266 6.4.1 supplies the available MTT directions after QT is no
            // longer signaled. The current hardware residual subset chooses a
            // legal BT direction that drives the larger remaining axis toward
            // the 8x8 luma-coordinate leaf.
            let vertical = Self::chroma_prefer_vertical_bt(node, split);
            self.emit_chroma_visible_mtt_split(cabac, node, split, vertical, true, neighbours);
            for child_idx in 0..2 {
                self.emit_chroma_visible_qt_subtree(
                    cabac,
                    node.mtt_child(vertical, child_idx),
                    visible_width,
                    visible_height,
                    min_leaf_size,
                    neighbours,
                );
            }
        }
    }

    fn emit_chroma_implicit_boundary_children(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        node: VvcCodingTreeNode,
        visible_width: u16,
        visible_height: u16,
        min_leaf_size: u16,
        neighbours: &mut VvcChromaNeighbourState,
    ) {
        let split = vvc_chroma_420_split_availability(node, visible_width, visible_height);
        if split.allow_qt {
            if split.allow_btt() {
                self.contexts.encode(
                    cabac,
                    VvcCabacContext::SplitQtFlag(Self::chroma_qt_split_ctx(node, neighbours)),
                    true,
                );
            }
            for child_idx in 0..4 {
                self.emit_chroma_visible_qt_subtree(
                    cabac,
                    node.qt_child(child_idx),
                    visible_width,
                    visible_height,
                    min_leaf_size,
                    neighbours,
                );
            }
            return;
        }
        match split.implicit_split {
            VvcPartSplit::Quad => {
                for child_idx in 0..4 {
                    self.emit_chroma_visible_qt_subtree(
                        cabac,
                        node.qt_child(child_idx),
                        visible_width,
                        visible_height,
                        min_leaf_size,
                        neighbours,
                    );
                }
            }
            VvcPartSplit::HorizontalBinary | VvcPartSplit::VerticalBinary => {
                let vertical = split.implicit_split == VvcPartSplit::VerticalBinary;
                self.emit_chroma_boundary_bt_split(cabac, node, split, vertical, neighbours);
                for child_idx in 0..2 {
                    self.emit_chroma_visible_qt_subtree(
                        cabac,
                        node.mtt_child_with_boundary_depth_offset(
                            vertical,
                            child_idx,
                            visible_width,
                            visible_height,
                        ),
                        visible_width,
                        visible_height,
                        min_leaf_size,
                        neighbours,
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

    fn emit_chroma_visible_qt_split(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        node: VvcCodingTreeNode,
        split: VvcChromaSplitAvailability,
        neighbours: &VvcChromaNeighbourState,
    ) {
        let qt_ctx = Self::chroma_qt_split_ctx(node, neighbours);
        if split.can_no {
            self.contexts.encode(
                cabac,
                VvcCabacContext::SplitFlag(Self::chroma_split_ctx(node, split, neighbours)),
                true,
            );
        }
        if split.allow_btt() {
            self.contexts
                .encode(cabac, VvcCabacContext::SplitQtFlag(qt_ctx), true);
        }
    }

    fn emit_chroma_visible_mtt_split(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        node: VvcCodingTreeNode,
        split: VvcChromaSplitAvailability,
        vertical: bool,
        binary: bool,
        neighbours: &VvcChromaNeighbourState,
    ) {
        debug_assert!(!split.allow_qt || split.allow_btt());
        if split.can_no {
            self.contexts.encode(
                cabac,
                VvcCabacContext::SplitFlag(Self::chroma_split_ctx(node, split, neighbours)),
                true,
            );
        }
        if split.allow_qt {
            let qt_ctx = Self::chroma_qt_split_ctx(node, neighbours);
            self.contexts
                .encode(cabac, VvcCabacContext::SplitQtFlag(qt_ctx), false);
        }

        let can_hor = split.allow_bt_horizontal || split.allow_tt_horizontal;
        let can_ver = split.allow_bt_vertical || split.allow_tt_vertical;
        if can_ver && can_hor {
            self.contexts.encode(
                cabac,
                VvcCabacContext::MttSplitCuVerticalFlag(Self::chroma_mtt_vertical_ctx(
                    node, split, neighbours,
                )),
                vertical,
            );
        }

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
        if can_binary && can_ternary {
            self.contexts.encode(
                cabac,
                VvcCabacContext::MttSplitCuBinaryFlag(VvcCtuCabacOp::mtt_binary_ctx(
                    vertical,
                    node.mtt_depth,
                )),
                binary,
            );
        }
    }

    fn emit_chroma_boundary_bt_split(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        node: VvcCodingTreeNode,
        split: VvcChromaSplitAvailability,
        _vertical: bool,
        neighbours: &VvcChromaNeighbourState,
    ) {
        // H.266 7.3.11.4 still signals split_qt_flag for an implicit
        // boundary BT when both QT and BTT are available; split_cu_flag itself
        // is inferred by 7.4.12.4 and therefore not written.
        if split.allow_qt && split.allow_btt() {
            self.contexts.encode(
                cabac,
                VvcCabacContext::SplitQtFlag(Self::chroma_qt_split_ctx(node, neighbours)),
                false,
            );
        }
    }

    fn emit_chroma_residual(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        component: VvcResidualComponent,
        node: VvcCodingTreeNode,
        dc_level: i16,
        ac_levels: [i16; VVC_CHROMA_AC_COEFFS_PER_TU],
    ) {
        let width = usize::from(vvc_chroma_420_width(node));
        let height = usize::from(vvc_chroma_420_height(node));
        let mut coeff_levels = vec![0; width * height];
        coeff_levels[0] = dc_level;
        for (slot, level) in ac_levels.iter().enumerate() {
            let (x, y) = VVC_CHROMA_AC_POSITIONS_2X2[slot];
            if x < width && y < height {
                coeff_levels[y * width + x] = *level;
            }
        }
        let stream = VvcResidualCabacSymbolStream::chroma_coefficients(
            component,
            (width as u16).ilog2() as u8,
            (height as u16).ilog2() as u8,
            &coeff_levels,
        );
        let mut residual =
            VvcResidualCabacEncoder::new(&mut self.contexts, self.slice_config.residual_options());
        stream.emit(&mut residual, cabac);
    }

    fn emit_chroma_transform_only_leaf(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        node: VvcCodingTreeNode,
        split: VvcChromaSplitAvailability,
        cbf_cb_ctx: u8,
        neighbours: &mut VvcChromaNeighbourState,
    ) {
        debug_assert_eq!(node.tree_type, VvcTreeType::DualTreeChroma);
        if split.can_no && split.can_split() {
            self.contexts.encode(
                cabac,
                VvcCabacContext::SplitFlag(Self::chroma_split_ctx(node, split, neighbours)),
                false,
            );
        }
        if self.chroma_cclm_enabled(node) {
            self.contexts
                .encode(cabac, VvcCabacContext::CclmModeFlag, false);
        }
        self.contexts
            .encode(cabac, VvcCabacContext::IntraChromaPredMode(0), false);
        let tu_idx = self.chroma_tu_index;
        self.chroma_tu_index += 1;
        assert!(
            tu_idx < self.chroma_tu_count,
            "missing chroma TU coefficient data for coding-tree leaf {tu_idx}"
        );
        let cb_dc_level = self.cb_tu_dc_levels[tu_idx];
        let cr_dc_level = self.cr_tu_dc_levels[tu_idx];
        let cb_ac_levels = self.cb_tu_ac_levels[tu_idx];
        let cr_ac_levels = self.cr_tu_ac_levels[tu_idx];
        let cbf_cb = cb_dc_level != 0 || cb_ac_levels.iter().any(|level| *level != 0);
        let cbf_cr = cr_dc_level != 0 || cr_ac_levels.iter().any(|level| *level != 0);
        self.contexts
            .encode(cabac, VvcCabacContext::QtCbfCb(cbf_cb_ctx), cbf_cb);
        self.contexts
            .encode(cabac, VvcCabacContext::QtCbfCr(u8::from(cbf_cb)), cbf_cr);
        if cbf_cb {
            self.emit_chroma_residual(
                cabac,
                VvcResidualComponent::ChromaCb,
                node,
                cb_dc_level,
                cb_ac_levels,
            );
        }
        if cbf_cr {
            self.emit_chroma_residual(
                cabac,
                VvcResidualComponent::ChromaCr,
                node,
                cr_dc_level,
                cr_ac_levels,
            );
        }
        neighbours.mark_leaf(node);
    }

    fn chroma_leaf_allowed(node: VvcCodingTreeNode) -> bool {
        let chroma_width = vvc_chroma_420_width(node);
        let chroma_height = vvc_chroma_420_height(node);
        // H.266 7.3.11.10 transform_unit() is reached after the encoder's
        // chosen legal coding-tree split. The spec maximum for this SPS remains
        // MaxTbSizeY/SubWidthC by MaxTbSizeY/SubHeightC, but this hardware
        // residual subset chooses 8x8 luma-coordinate leaves so each 4:2:0
        // chroma TU is 4x4 samples and shares the luma TU cadence.
        chroma_width <= VVC_CURRENT_ENCODER_CHROMA_420_TB_SIZE
            && chroma_height <= VVC_CURRENT_ENCODER_CHROMA_420_TB_SIZE
    }

    fn chroma_cclm_enabled(&self, node: VvcCodingTreeNode) -> bool {
        if !self.slice_config.tools.cclm_enabled {
            return false;
        }
        // H.266 8.4.4 derives CclmEnabled from the dual-tree chroma partition
        // state for 64x64 CTUs. In the current CTU-local all-intra subset,
        // CtbLog2SizeY is 6 and sps_qtbtt_dual_tree_intra_flag is enabled, so
        // the relevant enabled cases are:
        // - an unsplit 64x64 chroma CTU,
        // - any chroma CU below a QT split of the root CTU,
        // - a 64x32 CU produced by root BT_HOR,
        // - future children below root BT_HOR followed by BT_VER.
        // The encoder still selects cclm_mode_flag = 0 whenever the flag is
        // present.
        (node.width == 64 && node.height == 64 && node.cqt_depth == 0 && node.mtt_depth == 0)
            || node.cqt_depth > 0
            || (node.split_history[0] == VvcPartSplit::HorizontalBinary
                && node.width == 64
                && node.height == 32)
            || (node.split_history[0] == VvcPartSplit::HorizontalBinary
                && node.split_history[1] == VvcPartSplit::VerticalBinary)
    }

    fn chroma_split_ctx(
        node: VvcCodingTreeNode,
        split: VvcChromaSplitAvailability,
        neighbours: &VvcChromaNeighbourState,
    ) -> u8 {
        // H.266 9.3.4.2.2 Table 133 derives chroma split_cu_flag condL from
        // the left chroma CU height being smaller than the current chroma CU
        // height, and condA from the above chroma CU width being smaller.
        let left = neighbours.left_of(node);
        let above = neighbours.above_of(node);
        VvcSplitCtxInput {
            available_left: left.is_some(),
            available_above: above.is_some(),
            condition_left: left.is_some_and(|info| info.cb_height < vvc_chroma_420_height(node)),
            condition_above: above.is_some_and(|info| info.cb_width < vvc_chroma_420_width(node)),
            allow_bt_vertical: split.allow_bt_vertical,
            allow_bt_horizontal: split.allow_bt_horizontal,
            allow_tt_vertical: split.allow_tt_vertical,
            allow_tt_horizontal: split.allow_tt_horizontal,
            allow_qt: split.allow_qt,
        }
        .split_cu_flag_ctx()
    }

    fn chroma_qt_split_ctx(node: VvcCodingTreeNode, neighbours: &VvcChromaNeighbourState) -> u8 {
        // H.266 9.3.4.2.2 Table 133 derives split_qt_flag condL/condA from
        // neighbouring chroma CqtDepth being greater than the current depth.
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

    fn chroma_mtt_vertical_ctx(
        node: VvcCodingTreeNode,
        split: VvcChromaSplitAvailability,
        neighbours: &VvcChromaNeighbourState,
    ) -> u8 {
        // H.266 9.3.4.2.3 first compares vertical-vs-horizontal BT/TT choices.
        // If tied, it uses the above chroma CU width and left chroma CU height.
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
        let d_a = vvc_chroma_420_width(node) / above.cb_width.max(1);
        let d_l = vvc_chroma_420_height(node) / left.cb_height.max(1);
        if d_a == d_l {
            0
        } else if d_a < d_l {
            1
        } else {
            2
        }
    }

    fn chroma_prefer_vertical_bt(
        node: VvcCodingTreeNode,
        split: VvcChromaSplitAvailability,
    ) -> bool {
        if !split.allow_bt_vertical {
            return false;
        }
        if !split.allow_bt_horizontal {
            return true;
        }
        node.width >= node.height
    }
}
