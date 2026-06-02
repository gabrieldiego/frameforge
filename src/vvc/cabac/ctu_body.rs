use super::ctu_split::{
    VvcCodingTreeNode, VvcCtuCabacOp, VvcCtuPartitionParams, VvcPartSplit, VvcQtSplitCtxInput,
    VvcSplitCtxInput, VvcTreeType,
};
use super::{VvcCabacContext, VvcCabacContexts, VvcCabacEncoder};
use crate::vvc::residual::{VvcResidualCabacEncoder, VvcResidualCabacSymbolStream};
use crate::vvc::{
    VvcSliceSyntaxConfig, VVC_CURRENT_MAX_CHROMA_420_BT_SIZE,
    VVC_CURRENT_MAX_CHROMA_420_MTT_DEPTH_WITH_BOUNDARY, VVC_CURRENT_MAX_CHROMA_420_TB_SIZE,
    VVC_CURRENT_MAX_CHROMA_420_TT_SIZE, VVC_CURRENT_MAX_LUMA_MTT_DEPTH,
    VVC_CURRENT_MIN_CHROMA_420_QT_SIZE,
};

pub(in crate::vvc) fn encode_ctu_partition_body(
    cabac: &mut VvcCabacEncoder,
    params: VvcCtuPartitionParams,
    slice_config: VvcSliceSyntaxConfig,
) {
    let mut ctu = VvcCtuCabacGenerator::new(
        params.luma_dc_abs_level,
        params.luma_dc_negative,
        params.luma_ac_levels,
        params.cb_dc_abs_level,
        params.cb_dc_negative,
        slice_config,
    );
    for op in VvcCtuCabacOp::yuv420_ctu_partition(params) {
        ctu.emit(cabac, op);
    }
}

#[derive(Debug, Clone)]
pub(in crate::vvc) struct VvcCtuCabacGenerator {
    contexts: VvcCabacContexts,
    luma_dc_abs_level: u8,
    luma_dc_negative: bool,
    luma_ac_levels: [i16; 15],
    cb_dc_abs_level: u8,
    cb_dc_negative: bool,
    slice_config: VvcSliceSyntaxConfig,
}

impl VvcCtuCabacGenerator {
    pub(in crate::vvc) fn new(
        luma_dc_abs_level: u8,
        luma_dc_negative: bool,
        luma_ac_levels: [i16; 15],
        cb_dc_abs_level: u8,
        cb_dc_negative: bool,
        slice_config: VvcSliceSyntaxConfig,
    ) -> Self {
        Self {
            contexts: VvcCabacContexts::new(),
            luma_dc_abs_level,
            luma_dc_negative,
            luma_ac_levels,
            cb_dc_abs_level,
            cb_dc_negative,
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
        // VVC 7.3.11.5 intra_luma_pred_modes. The current generated subset
        // uses the explicit remaining-mode branch so the following residual
        // syntax matches the decoder parser for the supported intra picture setup.
        // Future work should derive the selected mode from prediction costs.
        self.contexts
            .encode(cabac, VvcCabacContext::IntraLumaMpmFlag, false);
        cabac.encode_bins_ep(0b011010, 6);
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
        // The current residual subset anchors the input-derived coefficients in
        // the first luma CU. Later CUs are reconstructed from intra prediction
        // until the software model grows a full per-CU prediction/residual loop.
        let anchor_cu = node.x == 0 && node.y == 0;
        let has_ac = self.luma_ac_levels.iter().any(|level| *level != 0);
        let cbf = anchor_cu && (self.luma_dc_abs_level != 0 || has_ac);
        self.emit_luma_cbf(cabac, node, cbf);
        if !cbf {
            return;
        }

        let log2_width = node.width.ilog2() as u8;
        let log2_height = node.height.ilog2() as u8;
        let width = usize::from(node.width);
        let height = usize::from(node.height);
        let mut coeff_levels = vec![0; width * height];
        coeff_levels[0] = if self.luma_dc_abs_level == 0 {
            0
        } else if self.luma_dc_negative {
            -(self.luma_dc_abs_level as i16)
        } else {
            self.luma_dc_abs_level as i16
        };
        // The current transform side exposes the first 4x4 AC positions. Keep
        // them wired through the normal residual coefficient path even when
        // they are all zero; future transform work should only change the
        // coefficient values, not reselect a different CABAC writer.
        for (ac_idx, level) in self.luma_ac_levels.iter().enumerate() {
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
        self.emit_chroma_visible_qt_subtree(cabac, node, visible_width, visible_height, 4);
    }

    fn emit_chroma_visible_qt_subtree(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        node: VvcCodingTreeNode,
        visible_width: u16,
        visible_height: u16,
        min_leaf_size: u16,
    ) {
        debug_assert_eq!(node.tree_type, VvcTreeType::DualTreeChroma);
        if !node.intersects_visible(visible_width, visible_height) {
            return;
        }
        if node.fits_visible(visible_width, visible_height) && Self::chroma_leaf_allowed(node) {
            self.emit_chroma_transform_only_leaf(
                cabac,
                node,
                Self::chroma_split_availability(node),
                0,
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
            );
            return;
        }

        let split = Self::chroma_split_availability(node);
        if split.allow_qt {
            self.emit_chroma_visible_qt_split(cabac, node, split);
            for child_idx in 0..4 {
                self.emit_chroma_visible_qt_subtree(
                    cabac,
                    node.qt_child(child_idx),
                    visible_width,
                    visible_height,
                    min_leaf_size,
                );
            }
        } else {
            // H.266 6.4.1 disables QT for 4:2:0 chroma when cbWidth/SubWidthC
            // is less than or equal to 4. Tall 4xN chroma regions therefore
            // continue with MTT rather than a forced quadtree split.
            let vertical = false;
            self.emit_chroma_visible_mtt_split(cabac, node, split, vertical, true);
            for child_idx in 0..2 {
                self.emit_chroma_visible_qt_subtree(
                    cabac,
                    node.mtt_child(vertical, child_idx),
                    visible_width,
                    visible_height,
                    min_leaf_size,
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
    ) {
        let bottom_left_in_pic =
            node.x < visible_width && node.y + node.height - 1 < visible_height;
        let top_right_in_pic = node.x + node.width - 1 < visible_width && node.y < visible_height;
        if !bottom_left_in_pic && !top_right_in_pic {
            for child_idx in 0..4 {
                self.emit_chroma_visible_qt_subtree(
                    cabac,
                    node.qt_child(child_idx),
                    visible_width,
                    visible_height,
                    min_leaf_size,
                );
            }
        } else if !bottom_left_in_pic && Self::chroma_boundary_bt_allowed(node, false) {
            self.emit_chroma_boundary_bt_split(cabac, node, false);
            for child_idx in 0..2 {
                self.emit_chroma_visible_qt_subtree(
                    cabac,
                    node.mtt_child(false, child_idx),
                    visible_width,
                    visible_height,
                    min_leaf_size,
                );
            }
        } else if !top_right_in_pic && Self::chroma_boundary_bt_allowed(node, true) {
            self.emit_chroma_boundary_bt_split(cabac, node, true);
            for child_idx in 0..2 {
                self.emit_chroma_visible_qt_subtree(
                    cabac,
                    node.mtt_child(true, child_idx),
                    visible_width,
                    visible_height,
                    min_leaf_size,
                );
            }
        } else {
            for child_idx in 0..4 {
                self.emit_chroma_visible_qt_subtree(
                    cabac,
                    node.qt_child(child_idx),
                    visible_width,
                    visible_height,
                    min_leaf_size,
                );
            }
        }
    }

    fn chroma_boundary_bt_allowed(node: VvcCodingTreeNode, vertical: bool) -> bool {
        // Mirrors the luma boundary split audit using the chroma MaxBtSizeC
        // derived from the current SPS constraints. See H.266 6.4.2 and
        // 7.4.12.4; this is split availability, not the final leaf size.
        let _ = vertical;
        node.width <= VVC_CURRENT_MAX_CHROMA_420_BT_SIZE
            && node.height <= VVC_CURRENT_MAX_CHROMA_420_BT_SIZE
    }

    fn emit_chroma_visible_qt_split(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        node: VvcCodingTreeNode,
        split: VvcChromaSplitAvailability,
    ) {
        let qt_ctx = if node.cqt_depth >= 2 { 3 } else { 0 };
        self.contexts
            .encode(cabac, VvcCabacContext::SplitFlag(split.split_ctx()), true);
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
    ) {
        debug_assert!(!split.allow_qt || split.allow_btt());
        self.contexts
            .encode(cabac, VvcCabacContext::SplitFlag(split.split_ctx()), true);
        if split.allow_qt {
            let qt_ctx = if node.cqt_depth >= 2 { 3 } else { 0 };
            self.contexts
                .encode(cabac, VvcCabacContext::SplitQtFlag(qt_ctx), false);
        }

        let can_hor = split.allow_bt_horizontal || split.allow_tt_horizontal;
        let can_ver = split.allow_bt_vertical || split.allow_tt_vertical;
        if can_ver && can_hor {
            self.contexts
                .encode(cabac, VvcCabacContext::MttSplitCuVerticalFlag(3), vertical);
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
        _vertical: bool,
    ) {
        if !VvcCtuCabacOp::qt_flag_can_be_signaled(node) {
            return;
        }
        self.contexts.encode(
            cabac,
            VvcCabacContext::SplitQtFlag(
                VvcQtSplitCtxInput::from_node_without_deeper_neighbours(node).split_qt_flag_ctx(),
            ),
            false,
        );
    }

    fn emit_chroma_cb_residual(&mut self, cabac: &mut VvcCabacEncoder) {
        cabac.encode_rem_abs_ep(self.cb_dc_abs_level as u32, 0);
        cabac.encode_bin_ep(self.cb_dc_negative);
    }

    fn emit_chroma_transform_only_leaf(
        &mut self,
        cabac: &mut VvcCabacEncoder,
        node: VvcCodingTreeNode,
        split: VvcChromaSplitAvailability,
        cbf_cb_ctx: u8,
    ) {
        debug_assert_eq!(node.tree_type, VvcTreeType::DualTreeChroma);
        if split.can_split() {
            self.contexts
                .encode(cabac, VvcCabacContext::SplitFlag(split.split_ctx()), false);
        }
        if self.chroma_cclm_enabled(node) {
            self.contexts
                .encode(cabac, VvcCabacContext::CclmModeFlag, false);
        }
        self.contexts
            .encode(cabac, VvcCabacContext::IntraChromaPredMode(0), false);
        // Chroma coefficient coding is not wired through the spec-shaped
        // residual encoder yet. Keep chroma residual disabled instead of
        // emitting a shortcut rem_abs payload that desynchronizes VTM.
        let cbf_cb = false;
        self.contexts
            .encode(cabac, VvcCabacContext::QtCbfCb(cbf_cb_ctx), cbf_cb);
        self.contexts
            .encode(cabac, VvcCabacContext::QtCbfCr(0), false);
        if cbf_cb {
            self.emit_chroma_cb_residual(cabac);
        }
    }

    fn chroma_leaf_allowed(node: VvcCodingTreeNode) -> bool {
        let chroma_width = Self::chroma_420_width(node);
        let chroma_height = Self::chroma_420_height(node);
        // H.266 7.3.11.10/7.3.11.11 allows a chroma transform block up to
        // MaxTbSizeY/SubWidthC by MaxTbSizeY/SubHeightC. With
        // sps_max_luma_transform_size_64_flag = 1 and 4:2:0 sampling, this is
        // 32x32 chroma samples. The previous 4x4-era limit was an encoder
        // implementation detail, not a coding-tree constraint.
        chroma_width <= VVC_CURRENT_MAX_CHROMA_420_TB_SIZE
            && chroma_height <= VVC_CURRENT_MAX_CHROMA_420_TB_SIZE
    }

    fn chroma_cclm_enabled(&self, node: VvcCodingTreeNode) -> bool {
        if !self.slice_config.tools.cclm_enabled {
            return false;
        }
        // H.266 8.4.4 derives CclmEnabled from the dual-tree chroma partition
        // state for 64x64 CTUs. In the current single-CTU all-intra subset,
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

    fn chroma_split_availability(node: VvcCodingTreeNode) -> VvcChromaSplitAvailability {
        let chroma_width = Self::chroma_420_width(node);
        let chroma_height = Self::chroma_420_height(node);
        let chroma_area = chroma_width * chroma_height;
        // H.266 7.3.11.4 increases depthOffset for boundary BT splits. The
        // effective chroma MaxMttDepthC is therefore larger than the SPS base
        // value on thin pictures such as 8x64, and split_cu_flag can still be
        // present even when the raw mttDepth has reached 3.
        let under_mtt_depth = node.mtt_depth < VVC_CURRENT_MAX_CHROMA_420_MTT_DEPTH_WITH_BOUNDARY;
        let within_bt_size = node.width <= VVC_CURRENT_MAX_CHROMA_420_BT_SIZE
            && node.height <= VVC_CURRENT_MAX_CHROMA_420_BT_SIZE;
        let within_tt_size = node.width <= VVC_CURRENT_MAX_CHROMA_420_TT_SIZE
            && node.height <= VVC_CURRENT_MAX_CHROMA_420_TT_SIZE;
        let allow_qt = node.mtt_depth == 0 && chroma_width > 4;
        let allow_bt_horizontal = under_mtt_depth && within_bt_size && chroma_area > 16;
        let allow_bt_vertical = allow_bt_horizontal
            && chroma_width != 4
            && node.width > VVC_CURRENT_MIN_CHROMA_420_QT_SIZE;
        let allow_tt_horizontal = under_mtt_depth && within_tt_size && chroma_area > 32;
        let allow_tt_vertical = allow_tt_horizontal
            && chroma_width != 8
            && node.width > 2 * VVC_CURRENT_MIN_CHROMA_420_QT_SIZE;

        VvcChromaSplitAvailability {
            allow_qt,
            allow_bt_vertical,
            allow_bt_horizontal,
            allow_tt_vertical,
            allow_tt_horizontal,
        }
    }

    fn chroma_420_width(node: VvcCodingTreeNode) -> u16 {
        node.width / 2
    }

    fn chroma_420_height(node: VvcCodingTreeNode) -> u16 {
        node.height / 2
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct VvcChromaSplitAvailability {
    allow_qt: bool,
    allow_bt_vertical: bool,
    allow_bt_horizontal: bool,
    allow_tt_vertical: bool,
    allow_tt_horizontal: bool,
}

impl VvcChromaSplitAvailability {
    fn can_split(self) -> bool {
        self.allow_qt || self.allow_btt()
    }

    fn allow_btt(self) -> bool {
        self.allow_bt_vertical
            || self.allow_bt_horizontal
            || self.allow_tt_vertical
            || self.allow_tt_horizontal
    }

    fn split_ctx(self) -> u8 {
        VvcSplitCtxInput {
            available_left: false,
            available_above: false,
            condition_left: false,
            condition_above: false,
            allow_bt_vertical: self.allow_bt_vertical,
            allow_bt_horizontal: self.allow_bt_horizontal,
            allow_tt_vertical: self.allow_tt_vertical,
            allow_tt_horizontal: self.allow_tt_horizontal,
            allow_qt: self.allow_qt,
        }
        .split_cu_flag_ctx()
    }
}
