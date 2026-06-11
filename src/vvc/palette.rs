use crate::picture::{ChromaSampling, PixelFormat};

use super::{
    sample_vvc_yuv_frame, vvc_picture_ctu_count, vvc_poc_lsb_for_frame_idx, vvc_slice_address_bits,
    VvcCabacContext, VvcCabacContexts, VvcCabacEncoder, VvcCtuCabacOp, VvcCtuPartitionShape,
    VvcEncodeParams, VvcNalUnit, VvcPictureKind, VvcSampledColor, VvcSampledFrame,
    VvcSliceSyntaxConfig, VvcSyntaxWriter, VvcVideoGeometry, VVC_CTU_SIZE,
};

const VVC_PALETTE_CU_SIZE: u16 = 8;
const VVC_PALETTE_LOSSLESS_SLICE_QP: i32 = 4;
const VVC_PALETTE_LOSSLESS_SH_QP_DELTA: i32 = -28;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum VvcPaletteTreeType {
    SingleTree,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct VvcPalette444Syntax {
    pub(super) tree_type: VvcPaletteTreeType,
    pub(super) cb_width: usize,
    pub(super) cb_height: usize,
    pub(super) start_comp: u8,
    pub(super) num_comps: u8,
    pub(super) max_num_palette_entries: u8,
    pub(super) num_predicted_palette_entries: u8,
    pub(super) num_signalled_palette_entries: u8,
    pub(super) new_palette_entries: Vec<VvcSampledColor>,
    pub(super) current_palette_size: u8,
    pub(super) palette_escape_val_present_flag: bool,
    pub(super) max_palette_index: u8,
    pub(super) palette_indices: Vec<u8>,
    /// Raw PaletteEscapeVal samples from H.266 7.4.12.6. Palette slices use
    /// SliceQpY 4 so H.266 8.4.5.3 reconstructs these 8-bit values exactly.
    ///
    /// TODO(area): the RTL currently mirrors this as full-CU escape banks.
    /// Keep this semantic model simple, but use it as the reference for a
    /// later subset-streamed RTL path that feeds escape values directly to
    /// CABAC without storing every escaped component twice.
    pub(super) palette_escape_values: Vec<Option<VvcSampledColor>>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum VvcPaletteSyntaxTokenKind {
    Eg0 { value: u32 },
    FixedLength { value: u32, bit_count: u8 },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct VvcPaletteSyntaxToken {
    pub(super) name: &'static str,
    kind: VvcPaletteSyntaxTokenKind,
}

#[cfg(test)]
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct VvcPalette444DecodedPicture {
    pub(super) luma: Vec<u8>,
    pub(super) cb: Vec<u8>,
    pub(super) cr: Vec<u8>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct VvcPalette444TileEntry {
    x: usize,
    y: usize,
    color: VvcSampledColor,
}

pub fn vvc_palette_444_cabac_dump_json(
    input: &[u8],
    geometry: VvcVideoGeometry,
    format: PixelFormat,
) -> Result<String, String> {
    let params = VvcEncodeParams { frames: 1 };
    let frame = sample_vvc_yuv_frame(input, params, geometry, format)?;
    if frame.format.chroma_sampling != ChromaSampling::Cs444 {
        return Err(format!(
            "palette CABAC dump expects 4:4:4 input; got {format}"
        ));
    }

    let cabac = vvc_palette_444_cabac_encoder(&frame);
    let semantic_symbols = cabac.semantic_symbols.clone();
    let cabac_bits = cabac.finish();
    let cabac_bytes = bits_to_padded_bytes(&cabac_bits);
    let mut json = String::new();
    json.push_str("{\n");
    json.push_str("  \"kind\": \"frameforge.palette444_cabac.v1\",\n");
    json.push_str(&format!("  \"width\": {},\n", geometry.width));
    json.push_str(&format!("  \"height\": {},\n", geometry.height));
    json.push_str("  \"tile_size\": 8,\n");
    json.push_str("  \"entries\": [\n");
    let entries = vvc_palette_444_tile_entries(&frame);
    for (idx, entry) in entries.iter().enumerate() {
        let comma = if idx + 1 == entries.len() { "" } else { "," };
        json.push_str(&format!(
            "    {{\"x\": {}, \"y\": {}, \"value_y\": {}, \"value_cb\": {}, \"value_cr\": {}}}{}\n",
            entry.x, entry.y, entry.color.y, entry.color.u, entry.color.v, comma
        ));
    }
    json.push_str("  ],\n");
    json.push_str(&format!("  \"cabac_bit_len\": {},\n", cabac_bits.len()));
    json.push_str(&format!(
        "  \"cabac_hex\": \"{}\",\n",
        bytes_to_lower_hex(&cabac_bytes)
    ));
    json.push_str("  \"semantic_symbols\": [\n");
    for (idx, symbol) in semantic_symbols.iter().enumerate() {
        let comma = if idx + 1 == semantic_symbols.len() {
            ""
        } else {
            ","
        };
        json.push_str(&format!(
            "    {{\"kind\": {}, \"data\": {}}}{}\n",
            symbol.kind, symbol.data, comma
        ));
    }
    json.push_str("  ]\n");
    json.push_str("}\n");
    Ok(json)
}

pub(super) fn vvc_palette_444_reconstruction_yuv(frame: &VvcSampledFrame) -> Vec<u8> {
    debug_assert_eq!(frame.format.chroma_sampling, ChromaSampling::Cs444);
    let samples = frame.geometry.luma_samples();
    let mut luma = vec![0; samples];
    let mut cb = vec![0; samples];
    let mut cr = vec![0; samples];

    for origin_y in (0..frame.geometry.height).step_by(VVC_PALETTE_CU_SIZE as usize) {
        for origin_x in (0..frame.geometry.width).step_by(VVC_PALETTE_CU_SIZE as usize) {
            let syntax = vvc_palette_444_cu_syntax(frame, origin_x, origin_y);
            let width = syntax.cb_width;
            let height = syntax.cb_height;
            for y_off in 0..height {
                for x_off in 0..width {
                    let local = y_off * width + x_off;
                    let palette_index = syntax.palette_indices.get(local).copied().unwrap_or(0);
                    let color = if syntax.palette_escape_val_present_flag
                        && palette_index == syntax.max_palette_index
                    {
                        syntax.palette_escape_values[local]
                            .expect("escape-coded palette sample must carry raw component values")
                    } else {
                        syntax.new_palette_entries[palette_index as usize]
                    };
                    let dst = (origin_y + y_off) * frame.geometry.width + origin_x + x_off;
                    luma[dst] = color.y;
                    cb[dst] = color.u;
                    cr[dst] = color.v;
                }
            }
        }
    }

    [luma, cb, cr].concat()
}

pub(super) fn vvc_palette_444_ctu_slice_unit(
    frame_idx: usize,
    picture_geometry: VvcVideoGeometry,
    slice_address: usize,
    frame: &VvcSampledFrame,
    slice_config: VvcSliceSyntaxConfig,
) -> Result<VvcNalUnit, String> {
    let picture_kind = VvcPictureKind::for_frame_idx(frame_idx);
    let poc_lsb = vvc_poc_lsb_for_frame_idx(frame_idx);
    let slice_count = vvc_picture_ctu_count(picture_geometry);
    if slice_address >= slice_count {
        return Err(format!(
            "VVC palette slice address {slice_address} is outside the picture CTU/slice count {slice_count}"
        ));
    }

    Ok(VvcNalUnit {
        nal_unit_type: picture_kind.nal_unit_type(),
        layer_id: 0,
        temporal_id: 0,
        rbsp_payload: vvc_palette_444_slice_payload(
            picture_kind,
            poc_lsb,
            picture_geometry,
            slice_address,
            frame,
            slice_config,
        ),
    })
}

fn vvc_palette_444_slice_payload(
    picture_kind: VvcPictureKind,
    poc_lsb: u32,
    picture_geometry: VvcVideoGeometry,
    slice_address: usize,
    frame: &VvcSampledFrame,
    slice_config: VvcSliceSyntaxConfig,
) -> Vec<u8> {
    let mut writer = VvcSyntaxWriter::new();
    let tool_flags = slice_config.tools;
    let slice_count = vvc_picture_ctu_count(picture_geometry);
    let include_picture_header = slice_count == 1;
    writer.write_flag(
        "sh_picture_header_in_slice_header_flag",
        include_picture_header,
    );
    if include_picture_header {
        super::header::write_vvc_picture_header(&mut writer, picture_kind, poc_lsb, slice_config);
    }
    if slice_count > 1 {
        writer.write_u(
            "sh_slice_address",
            slice_address as u64,
            vvc_slice_address_bits(picture_geometry),
        );
    }
    writer.write_flag("sh_no_output_of_prior_pics_flag", false);
    // H.266 8.4.5.3 reconstructs palette_escape_val with levelScale[QP % 6].
    // The current PPS base QP is 32, so sh_qp_delta -28 gives SliceQpY 4 and
    // levelScale[4] == 64, making 8-bit escape samples reconstruct exactly.
    writer.write_se("sh_qp_delta", VVC_PALETTE_LOSSLESS_SH_QP_DELTA);
    if tool_flags.dependent_quantization_enabled {
        writer.write_flag("sh_dep_quant_used_flag", true);
    }
    if tool_flags.sign_data_hiding_enabled && !tool_flags.dependent_quantization_enabled {
        writer.write_flag("sh_sign_data_hiding_used_flag", true);
    }
    writer.write_flag("cabac_alignment_one_bit", true);
    if picture_kind.is_cra() {
        writer.write_flag("cabac_alignment_one_bit", true);
    }
    writer.byte_align_zero("cabac_alignment_zero_bit");
    write_vvc_palette_444_entropy(&mut writer, frame);
    writer.rbsp_trailing_bits();
    debug_assert!(writer.is_byte_aligned());
    writer.into_bytes()
}

fn write_vvc_palette_444_entropy(writer: &mut VvcSyntaxWriter, frame: &VvcSampledFrame) {
    writer.write_cabac_bits(
        "cabac_vvc_palette_444_tile_entry_bits",
        &vvc_palette_444_cabac_bits(frame),
    );
}

fn vvc_palette_444_cabac_bits(frame: &VvcSampledFrame) -> Vec<bool> {
    vvc_palette_444_cabac_encoder(frame).finish()
}

fn vvc_palette_444_cabac_encoder(frame: &VvcSampledFrame) -> VvcCabacEncoder {
    let mut cabac = VvcCabacEncoder::new();
    let mut ctx = VvcCabacContexts::with_slice_qp(VVC_PALETTE_LOSSLESS_SLICE_QP);
    let mut predictor_mode = VvcPalettePredictorMode::SignalNewEntry;
    cabac.start();
    let partition_shape = VvcCtuPartitionShape {
        root_width: VVC_CTU_SIZE as u16,
        root_height: VVC_CTU_SIZE as u16,
        visible_width: frame.geometry.coded_width() as u16,
        visible_height: frame.geometry.coded_height() as u16,
        chroma_sampling: frame.format.chroma_sampling,
    };
    for op in VvcCtuCabacOp::intra_ctu_partition(partition_shape, VVC_PALETTE_CU_SIZE) {
        append_vvc_palette_444_partition_op(&mut cabac, &mut ctx, frame, &mut predictor_mode, op);
    }
    cabac.encode_bin_trm(true);
    cabac
}

fn append_vvc_palette_444_partition_op(
    cabac: &mut VvcCabacEncoder,
    ctx: &mut VvcCabacContexts,
    frame: &VvcSampledFrame,
    predictor_mode: &mut VvcPalettePredictorMode,
    op: VvcCtuCabacOp,
) {
    match op {
        VvcCtuCabacOp::QtSplit {
            split_ctx,
            write_split_flag,
            write_qt_flag,
            qt_ctx,
            ..
        } => {
            // H.266 7.3.11.4 / 7.4.12.4: split_cu_flag and split_qt_flag
            // are only written when the split availability model has more
            // than one legal outcome. Boundary-only QT splits are inferred by
            // the decoder and must not consume CABAC bins.
            if write_split_flag {
                ctx.encode(cabac, VvcCabacContext::SplitFlag(split_ctx), true);
            }
            if write_qt_flag {
                ctx.encode(cabac, VvcCabacContext::SplitQtFlag(qt_ctx), true);
            }
        }
        VvcCtuCabacOp::BtSplit {
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
            ..
        } => {
            // The palette path uses the same CTU split availability and
            // context derivation as the audited residual path. Only the CU
            // payload below the leaf differs.
            if write_split_flag {
                ctx.encode(cabac, VvcCabacContext::SplitFlag(split_ctx), true);
            }
            if write_qt_flag {
                ctx.encode(cabac, VvcCabacContext::SplitQtFlag(qt_ctx), false);
            }
            if write_mtt_vertical_flag {
                ctx.encode(
                    cabac,
                    VvcCabacContext::MttSplitCuVerticalFlag(mtt_vertical_ctx),
                    vertical,
                );
            }
            if write_binary_flag {
                ctx.encode(
                    cabac,
                    VvcCabacContext::MttSplitCuBinaryFlag(mtt_binary_ctx),
                    mtt_binary_value,
                );
            }
        }
        VvcCtuCabacOp::LumaLeafWithSplitCtx {
            node,
            write_split_flag,
            split_ctx,
        } => {
            if append_vvc_palette_444_8x8_cu_with_events(
                cabac,
                ctx,
                frame,
                VvcPaletteCuEmitRequest {
                    origin_x: node.x,
                    origin_y: node.y,
                    write_split_flag,
                    split_ctx,
                    predictor_mode: *predictor_mode,
                },
            ) {
                *predictor_mode = VvcPalettePredictorMode::SignalNewEntryAfterPredictor;
            }
        }
        VvcCtuCabacOp::ChromaTree { .. } => {
            unreachable!("4:4:4 single-tree partitioning must not emit a chroma tree")
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum VvcPalettePredictorMode {
    SignalNewEntry,
    SignalNewEntryAfterPredictor,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct VvcPaletteCuEmitRequest {
    origin_x: u16,
    origin_y: u16,
    write_split_flag: bool,
    split_ctx: u8,
    predictor_mode: VvcPalettePredictorMode,
}

fn append_vvc_palette_444_8x8_cu_with_events(
    cabac: &mut VvcCabacEncoder,
    ctx: &mut VvcCabacContexts,
    frame: &VvcSampledFrame,
    request: VvcPaletteCuEmitRequest,
) -> bool {
    if !vvc_palette_cu_origin_is_visible(frame.geometry, request.origin_x, request.origin_y) {
        return false;
    }
    if request.write_split_flag {
        ctx.encode(cabac, VvcCabacContext::SplitFlag(request.split_ctx), false);
    }
    ctx.encode(cabac, VvcCabacContext::PredModePltFlag, true);
    let syntax =
        vvc_palette_444_cu_syntax(frame, request.origin_x as usize, request.origin_y as usize);
    let palette_index_map = syntax.palette_indices.clone();
    let palette_escape_values = syntax.palette_escape_values.clone();
    let max_palette_index = syntax.max_palette_index;
    let palette_escape_val_present_flag = syntax.palette_escape_val_present_flag;
    for token in vvc_palette_444_syntax_tokens(syntax, request.predictor_mode) {
        append_palette_syntax_token_cabac(cabac, token);
    }
    append_vvc_palette_444_index_map(
        cabac,
        ctx,
        max_palette_index,
        palette_escape_val_present_flag,
        &palette_index_map,
        &palette_escape_values,
    );
    true
}

fn append_vvc_palette_444_index_map(
    cabac: &mut VvcCabacEncoder,
    ctx: &mut VvcCabacContexts,
    max_palette_index: u8,
    palette_escape_val_present_flag: bool,
    palette_indices: &[u8],
    palette_escape_values: &[Option<VvcSampledColor>],
) {
    if max_palette_index == 0 {
        return;
    }

    ctx.encode(cabac, VvcCabacContext::PaletteTransposeFlag, false);
    let scan_positions = vvc_palette_horizontal_scan_positions(8, 8);
    let scan_indices: Vec<u8> = scan_positions
        .iter()
        .map(|&(x, y)| palette_indices[y * 8 + x])
        .collect();
    let mut prev_run_pos = 0usize;
    let mut previous_run_type_copy_above = false;
    let mut prev_index = 0u8;
    let mut run_copy_flags = [false; 16];

    for min_sub_pos in (0..scan_indices.len()).step_by(16) {
        let max_sub_pos = (min_sub_pos + 16).min(scan_indices.len());

        for cur_pos in min_sub_pos..max_sub_pos {
            let index = scan_indices[cur_pos];
            let identity = cur_pos > 0 && index == prev_index;
            run_copy_flags[cur_pos - min_sub_pos] = identity;
            if cur_pos > 0 {
                let dist = cur_pos - prev_run_pos - 1;
                ctx.encode(
                    cabac,
                    VvcCabacContext::RunCopyFlag(vvc_palette_run_copy_ctx_id(
                        dist,
                        previous_run_type_copy_above,
                    )),
                    identity,
                );
            }
            if !identity || cur_pos == 0 {
                let (_, y) = scan_positions[cur_pos];
                let run_type_is_inferred_index = y == 0;
                prev_run_pos = cur_pos;
                if cur_pos != 0 && !run_type_is_inferred_index {
                    ctx.encode(cabac, VvcCabacContext::CopyAbovePaletteIndicesFlag, false);
                }
                previous_run_type_copy_above = false;
            };
            prev_index = index;
        }

        for cur_pos in min_sub_pos..max_sub_pos {
            if run_copy_flags[cur_pos - min_sub_pos] {
                continue;
            }
            let index = scan_indices[cur_pos];
            let max_symbol = max_palette_index as u32 + 1 - u32::from(cur_pos > 0);
            if max_symbol <= 1 {
                continue;
            }
            let mut level = index as u32;
            if cur_pos > 0 {
                let previous = scan_indices[cur_pos - 1] as u32;
                debug_assert_ne!(level, previous);
                if level > previous {
                    level -= 1;
                }
            }
            encode_trunc_bin_code_ep(cabac, level, max_symbol);
        }

        if palette_escape_val_present_flag {
            for component in 0..3 {
                for cur_pos in min_sub_pos..max_sub_pos {
                    if scan_indices[cur_pos] != max_palette_index {
                        continue;
                    }
                    let (x, y) = scan_positions[cur_pos];
                    let sample = palette_escape_values[y * 8 + x]
                        .expect("escape-coded palette index must carry raw component values");
                    let value = match component {
                        0 => sample.y,
                        1 => sample.u,
                        _ => sample.v,
                    };
                    // H.266 7.3.11.6 writes palette_escape_val after each
                    // 16-sample palette-index subset for samples whose
                    // PaletteIndexMap equals MaxPaletteIndex. Per Table 130,
                    // palette_escape_val is bypass-coded; H.266 9.3.3 uses
                    // EG5 binarization for this syntax element.
                    encode_exp_golomb_ep(cabac, value as u32, 5);
                }
            }
        }
    }
}

fn vvc_palette_horizontal_scan_positions(width: usize, height: usize) -> Vec<(usize, usize)> {
    let mut scanned = Vec::with_capacity(width * height);
    for y in 0..height {
        if y % 2 == 0 {
            for x in 0..width {
                scanned.push((x, y));
            }
        } else {
            for x in (0..width).rev() {
                scanned.push((x, y));
            }
        }
    }
    scanned
}

fn vvc_palette_run_copy_ctx_id(dist: usize, previous_run_type_copy_above: bool) -> u8 {
    // H.266 9.3.4.2.11 and Table 134 derive run_copy_flag ctxInc from
    // binDist and PreviousRunType. The current encoder only selects index runs,
    // but keep the copy-above half labelled for the mixed palette path.
    match (previous_run_type_copy_above, dist) {
        (true, 0) => 5,
        (true, 1 | 2) => 6,
        (true, _) => 7,
        (false, 0) => 0,
        (false, 1) => 1,
        (false, 2) => 2,
        (false, 3) => 3,
        (false, _) => 4,
    }
}

#[cfg(test)]
pub(super) fn vvc_palette_run_copy_context_id_for_audit(
    dist: usize,
    previous_run_type_copy_above: bool,
) -> u8 {
    vvc_palette_run_copy_ctx_id(dist, previous_run_type_copy_above)
}

#[cfg(test)]
pub(super) fn vvc_palette_444_context_audit_rows() -> Vec<(&'static str, u8, u8)> {
    let mut rows = vec![
        (
            "pred_mode_plt_flag[0]",
            VvcCabacContext::PredModePltFlag.init_value(),
            VvcCabacContext::PredModePltFlag.log2_window_size(),
        ),
        (
            "palette_transpose_flag[0]",
            VvcCabacContext::PaletteTransposeFlag.init_value(),
            VvcCabacContext::PaletteTransposeFlag.log2_window_size(),
        ),
        (
            "copy_above_palette_indices_flag[0]",
            VvcCabacContext::CopyAbovePaletteIndicesFlag.init_value(),
            VvcCabacContext::CopyAbovePaletteIndicesFlag.log2_window_size(),
        ),
    ];
    for idx in 0..8 {
        let ctx = VvcCabacContext::RunCopyFlag(idx);
        rows.push(("run_copy_flag", ctx.init_value(), ctx.log2_window_size()));
    }
    rows
}

fn vvc_palette_cu_origin_is_visible(
    geometry: VvcVideoGeometry,
    origin_x: u16,
    origin_y: u16,
) -> bool {
    (origin_x as usize) < geometry.width && (origin_y as usize) < geometry.height
}

#[cfg(test)]
pub(super) fn vvc_palette_444_single_entry_syntax(
    geometry: VvcVideoGeometry,
    color: VvcSampledColor,
) -> VvcPalette444Syntax {
    // H.266 7.3.11.6, single-tree 4:4:4 subset:
    // - no predictor reuse because the initial predictor palette is empty,
    // - exactly one explicitly signalled palette entry,
    // - no escape-coded samples,
    // - MaxPaletteIndex == 0, so all sample indices are inferred as 0 and
    //   run/copy/index syntax is not present.
    VvcPalette444Syntax {
        tree_type: VvcPaletteTreeType::SingleTree,
        cb_width: geometry.width,
        cb_height: geometry.height,
        start_comp: 0,
        num_comps: 3,
        max_num_palette_entries: 31,
        num_predicted_palette_entries: 0,
        num_signalled_palette_entries: 1,
        new_palette_entries: vec![color],
        current_palette_size: 1,
        palette_escape_val_present_flag: false,
        max_palette_index: 0,
        palette_indices: Vec::new(),
        palette_escape_values: Vec::new(),
    }
}

pub(super) fn vvc_palette_444_cu_syntax(
    frame: &VvcSampledFrame,
    origin_x: usize,
    origin_y: usize,
) -> VvcPalette444Syntax {
    let mut entries = Vec::new();
    let mut indices = Vec::new();
    let mut escape_values = Vec::new();
    let width = 8.min(frame.geometry.width.saturating_sub(origin_x));
    let height = 8.min(frame.geometry.height.saturating_sub(origin_y));
    let mut has_escape = false;

    for y_off in 0..height {
        for x_off in 0..width {
            let color = vvc_palette_444_sample_at(frame, origin_x + x_off, origin_y + y_off);
            let (index, escape_value) =
                if let Some(index) = entries.iter().position(|entry| *entry == color) {
                    (index as u8, None)
                } else if entries.len() < 31 {
                    entries.push(color);
                    ((entries.len() - 1) as u8, None)
                } else {
                    // H.266 7.3.11.6 and 7.4.12.6 define
                    // MaxPaletteIndex as CurrentPaletteSize - 1 plus
                    // palette_escape_val_present_flag. PaletteEscapeVal itself
                    // is reconstructed through H.266 8.4.5.3. Palette slices
                    // deliberately use SliceQpY 4 so the levelScale equation
                    // is identity for 8-bit samples, preserving lossless
                    // 4:4:4 coding while keeping the simple first-31-colours
                    // palette heuristic.
                    has_escape = true;
                    (31, Some(color))
                };
            indices.push(index);
            escape_values.push(escape_value);
        }
    }

    if entries.is_empty() {
        entries.push(vvc_palette_444_sample_at(frame, origin_x, origin_y));
        indices.push(0);
        escape_values.push(None);
    }

    let current_palette_size = entries.len() as u8;
    let max_palette_index = current_palette_size.saturating_sub(1) + u8::from(has_escape);
    VvcPalette444Syntax {
        tree_type: VvcPaletteTreeType::SingleTree,
        cb_width: width,
        cb_height: height,
        start_comp: 0,
        num_comps: 3,
        max_num_palette_entries: 31,
        num_predicted_palette_entries: 0,
        num_signalled_palette_entries: current_palette_size,
        new_palette_entries: entries,
        current_palette_size,
        palette_escape_val_present_flag: has_escape,
        max_palette_index,
        palette_indices: if max_palette_index == 0 {
            Vec::new()
        } else {
            indices
        },
        palette_escape_values: if has_escape {
            escape_values
        } else {
            Vec::new()
        },
    }
}

fn vvc_palette_444_sample_at(frame: &VvcSampledFrame, x: usize, y: usize) -> VvcSampledColor {
    debug_assert_eq!(frame.format.chroma_sampling, ChromaSampling::Cs444);
    let sample_x = x.min(frame.geometry.width.saturating_sub(1));
    let sample_y = y.min(frame.geometry.height.saturating_sub(1));
    let index = sample_y * frame.geometry.width + sample_x;
    VvcSampledColor {
        y: frame.luma[index],
        u: frame.cb[index],
        v: frame.cr[index],
    }
}

fn vvc_palette_444_tile_entries(frame: &VvcSampledFrame) -> Vec<VvcPalette444TileEntry> {
    let mut entries = Vec::new();
    for y in (0..frame.geometry.height).step_by(8) {
        for x in (0..frame.geometry.width).step_by(8) {
            entries.push(VvcPalette444TileEntry {
                x,
                y,
                color: vvc_palette_444_sample_at(frame, x, y),
            });
        }
    }
    entries
}

fn bits_to_padded_bytes(bits: &[bool]) -> Vec<u8> {
    let mut bytes = Vec::with_capacity(bits.len().div_ceil(8));
    for chunk in bits.chunks(8) {
        let mut byte = 0u8;
        for bit in chunk {
            byte = (byte << 1) | u8::from(*bit);
        }
        byte <<= 8 - chunk.len();
        bytes.push(byte);
    }
    bytes
}

fn bytes_to_lower_hex(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        out.push(HEX[(byte >> 4) as usize] as char);
        out.push(HEX[(byte & 0x0f) as usize] as char);
    }
    out
}

#[cfg(test)]
pub(super) fn vvc_palette_444_binarized_syntax_bits(syntax: VvcPalette444Syntax) -> Vec<bool> {
    let mut bits = Vec::new();
    for token in vvc_palette_444_syntax_tokens(syntax, VvcPalettePredictorMode::SignalNewEntry) {
        append_palette_syntax_token_bits(&mut bits, token);
    }
    bits
}

#[cfg(test)]
pub(super) fn vvc_palette_444_decode_reconstruction(
    geometry: VvcVideoGeometry,
    syntax: VvcPalette444Syntax,
) -> VvcPalette444DecodedPicture {
    // H.266 8.4.5.3, restricted to the current SINGLE_TREE 4:4:4 subset:
    // PaletteIndexMap either selects CurrentPaletteEntries or, when equal to
    // MaxPaletteIndex with palette_escape_val_present_flag set, reconstructs
    // PaletteEscapeVal through equations (441)..(443). The encoder signals
    // SliceQpY 4 for palette slices, so raw 8-bit escape samples are lossless.
    debug_assert_eq!(syntax.tree_type, VvcPaletteTreeType::SingleTree);
    debug_assert_eq!(syntax.start_comp, 0);
    debug_assert_eq!(syntax.num_comps, 3);

    let samples = geometry.luma_samples();
    if syntax.max_palette_index == 0 && !syntax.palette_escape_val_present_flag {
        let entry = syntax.new_palette_entries[0];
        return VvcPalette444DecodedPicture {
            luma: vec![entry.y; samples],
            cb: vec![entry.u; samples],
            cr: vec![entry.v; samples],
        };
    }

    let mut luma = Vec::with_capacity(samples);
    let mut cb = Vec::with_capacity(samples);
    let mut cr = Vec::with_capacity(samples);
    for (sample_idx, index) in syntax.palette_indices.iter().enumerate() {
        let color = if syntax.palette_escape_val_present_flag && *index == syntax.max_palette_index
        {
            syntax.palette_escape_values[sample_idx]
                .expect("escape-coded palette sample must carry raw component values")
        } else {
            syntax.new_palette_entries[*index as usize]
        };
        luma.push(color.y);
        cb.push(color.u);
        cr.push(color.v);
    }
    VvcPalette444DecodedPicture { luma, cb, cr }
}

pub(super) fn vvc_palette_444_syntax_tokens(
    syntax: VvcPalette444Syntax,
    predictor_mode: VvcPalettePredictorMode,
) -> Vec<VvcPaletteSyntaxToken> {
    debug_assert_eq!(syntax.tree_type, VvcPaletteTreeType::SingleTree);
    debug_assert_eq!(syntax.start_comp, 0);
    debug_assert_eq!(syntax.num_comps, 3);
    debug_assert_eq!(syntax.max_num_palette_entries, 31);
    debug_assert_eq!(syntax.num_predicted_palette_entries, 0);
    debug_assert_eq!(
        syntax.current_palette_size,
        syntax.num_signalled_palette_entries
    );

    let mut tokens = Vec::new();
    if predictor_mode == VvcPalettePredictorMode::SignalNewEntryAfterPredictor {
        tokens.push(VvcPaletteSyntaxToken {
            name: "palette_predictor_run",
            // H.266 cu_palette_info/xDecodePLTPredIndicator: with a non-empty
            // previous palette, symbol 1 terminates prediction without reusing
            // entries. The following num_signalled_palette_entries then carries
            // this CU's fresh single-entry palette.
            kind: VvcPaletteSyntaxTokenKind::Eg0 { value: 1 },
        });
    }
    tokens.push(VvcPaletteSyntaxToken {
        name: "num_signalled_palette_entries",
        kind: VvcPaletteSyntaxTokenKind::Eg0 {
            value: syntax.num_signalled_palette_entries as u32,
        },
    });
    for entry in &syntax.new_palette_entries {
        tokens.push(VvcPaletteSyntaxToken {
            name: "new_palette_entries[0][i]",
            kind: VvcPaletteSyntaxTokenKind::FixedLength {
                value: entry.y as u32,
                bit_count: 8,
            },
        });
    }
    for entry in &syntax.new_palette_entries {
        tokens.push(VvcPaletteSyntaxToken {
            name: "new_palette_entries[1][i]",
            kind: VvcPaletteSyntaxTokenKind::FixedLength {
                value: entry.u as u32,
                bit_count: 8,
            },
        });
    }
    for entry in &syntax.new_palette_entries {
        tokens.push(VvcPaletteSyntaxToken {
            name: "new_palette_entries[2][i]",
            kind: VvcPaletteSyntaxTokenKind::FixedLength {
                value: entry.v as u32,
                bit_count: 8,
            },
        });
    }
    tokens.push(VvcPaletteSyntaxToken {
        name: "palette_escape_val_present_flag",
        kind: VvcPaletteSyntaxTokenKind::FixedLength {
            value: u32::from(syntax.palette_escape_val_present_flag),
            bit_count: 1,
        },
    });
    if syntax.max_palette_index > 0 {
        // Palette index maps are not a flat list of fixed-width EP bins in
        // VVC. They are written by append_vvc_palette_444_index_map() so the
        // context-coded copy flags and truncated index bins stay synchronized
        // with CABAC state.
    }
    tokens
}

#[cfg(test)]
fn append_palette_syntax_token_bits(bits: &mut Vec<bool>, token: VvcPaletteSyntaxToken) {
    match token.kind {
        VvcPaletteSyntaxTokenKind::Eg0 { value } => append_eg0_bits(bits, value),
        VvcPaletteSyntaxTokenKind::FixedLength { value, bit_count } => {
            append_fixed_bits(bits, value as u64, bit_count);
        }
    }
}

fn append_palette_syntax_token_cabac(cabac: &mut VvcCabacEncoder, token: VvcPaletteSyntaxToken) {
    match token.kind {
        VvcPaletteSyntaxTokenKind::Eg0 { value } => encode_exp_golomb_ep(cabac, value, 0),
        VvcPaletteSyntaxTokenKind::FixedLength { value, bit_count } => {
            cabac.encode_bins_ep(value, bit_count as u32);
        }
    }
}

fn encode_trunc_bin_code_ep(cabac: &mut VvcCabacEncoder, symbol: u32, num_symbols: u32) {
    debug_assert!(symbol < num_symbols);
    let thresh = 31 - num_symbols.leading_zeros();
    let val = 1 << thresh;
    let b = num_symbols - val;
    if symbol < val - b {
        cabac.encode_bins_ep(symbol, thresh);
    } else {
        cabac.encode_bins_ep(symbol + val - b, thresh + 1);
    }
}

fn encode_exp_golomb_ep(cabac: &mut VvcCabacEncoder, mut symbol: u32, mut count: u32) {
    let mut bins = 0;
    let mut num_bins = 0;
    while symbol >= (1 << count) {
        bins <<= 1;
        bins += 1;
        num_bins += 1;
        symbol -= 1 << count;
        count += 1;
    }
    bins <<= 1;
    num_bins += 1;
    cabac.encode_bins_ep(bins, num_bins);
    cabac.encode_bins_ep(symbol, count);
}

#[cfg(test)]
fn append_eg0_bits(bits: &mut Vec<bool>, value: u32) {
    let code_num = value + 1;
    let bit_count = 32 - code_num.leading_zeros();
    for _ in 0..bit_count - 1 {
        bits.push(false);
    }
    for bit in (0..bit_count).rev() {
        bits.push(((code_num >> bit) & 1) != 0);
    }
}

#[cfg(test)]
fn append_fixed_bits(bits: &mut Vec<bool>, value: u64, bit_count: u8) {
    for bit in (0..bit_count).rev() {
        bits.push(((value >> bit) & 1) != 0);
    }
}
