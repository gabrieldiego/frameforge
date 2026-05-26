use crate::picture::{ChromaSampling, PixelFormat};

use super::{
    sample_vvc_yuv_frame, vvc_4x4_color_filler_unit, vvc_4x4_pps_unit, vvc_palette_444_sps_unit,
    write_annex_b, Vvc4x4PictureKind, Vvc4x4SampledColor, Vvc4x4SampledFrame, VvcCabacEncoder,
    VvcCabacProbModel, VvcEncodeParams, VvcNalUnit, VvcNalUnitType, VvcSyntaxWriter,
    VvcVideoGeometry,
};

const VVC_PALETTE_CTU_SIZE: u16 = 64;
const VVC_PALETTE_CU_SIZE: u16 = 8;

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
    pub(super) new_palette_entries: Vec<Vvc4x4SampledColor>,
    pub(super) current_palette_size: u8,
    pub(super) palette_escape_val_present_flag: bool,
    pub(super) max_palette_index: u8,
    pub(super) palette_indices: Vec<u8>,
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
    color: Vvc4x4SampledColor,
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

    let cabac_bits = vvc_palette_444_cabac_bits(&frame);
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
        "  \"cabac_hex\": \"{}\"\n",
        bytes_to_lower_hex(&cabac_bytes)
    ));
    json.push_str("}\n");
    Ok(json)
}

pub(super) fn vvc_palette_444_annex_b(
    params: VvcEncodeParams,
    frame: Vvc4x4SampledFrame,
) -> Result<Vec<u8>, String> {
    debug_assert_eq!(frame.format.chroma_sampling, ChromaSampling::Cs444);
    let mut units = Vec::with_capacity(params.frames + 3);
    let geometry = frame.geometry;
    units.push(vvc_palette_444_sps_unit(geometry));
    units.push(vvc_4x4_pps_unit(geometry));
    units.push(vvc_4x4_color_filler_unit(frame.sampled_color()));
    for frame_idx in 0..params.frames {
        units.push(vvc_palette_444_slice_unit(frame_idx, &frame)?);
    }
    write_annex_b(&units)
}

fn vvc_palette_444_slice_unit(
    frame_idx: usize,
    frame: &Vvc4x4SampledFrame,
) -> Result<VvcNalUnit, String> {
    let picture_kind = match frame_idx {
        0 => Vvc4x4PictureKind::Idr,
        1 => Vvc4x4PictureKind::Cra,
        _ => return Err(format!("unsupported VVC frame index {frame_idx}")),
    };

    Ok(VvcNalUnit {
        nal_unit_type: match picture_kind {
            Vvc4x4PictureKind::Idr => VvcNalUnitType::IdrNLp,
            Vvc4x4PictureKind::Cra => VvcNalUnitType::Cra,
        },
        layer_id: 0,
        temporal_id: 0,
        rbsp_payload: vvc_palette_444_slice_payload(picture_kind, frame),
    })
}

fn vvc_palette_444_slice_payload(
    picture_kind: Vvc4x4PictureKind,
    frame: &Vvc4x4SampledFrame,
) -> Vec<u8> {
    let mut writer = VvcSyntaxWriter::new();
    writer.write_flag("sh_picture_header_in_slice_header_flag", true);
    writer.write_flag("ph_gdr_or_irap_pic_flag", true);
    writer.write_flag("ph_non_ref_pic_flag", false);
    writer.write_flag("ph_gdr_pic_flag", false);
    writer.write_flag("ph_inter_slice_allowed_flag", false);
    writer.write_ue("ph_pic_parameter_set_id", 0);
    match picture_kind {
        Vvc4x4PictureKind::Idr => writer.write_u("ph_pic_order_cnt_lsb", 0, 8),
        Vvc4x4PictureKind::Cra => writer.write_u("ph_pic_order_cnt_lsb", 1, 8),
    }
    writer.write_flag("ph_partition_constraints_override_flag", false);
    writer.write_flag("ph_joint_cbcr_sign_flag", false);
    writer.write_flag("sh_no_output_of_prior_pics_flag", false);
    writer.write_se("sh_qp_delta", 0);
    writer.write_flag("sh_dep_quant_used_flag", true);
    writer.write_flag("cabac_alignment_one_bit", true);
    if picture_kind == Vvc4x4PictureKind::Cra {
        writer.write_flag("cabac_alignment_one_bit", true);
    }
    writer.byte_align_zero("cabac_alignment_zero_bit");
    write_vvc_palette_444_entropy(&mut writer, frame);
    writer.rbsp_trailing_bits();
    debug_assert!(writer.is_byte_aligned());
    writer.into_bytes()
}

fn write_vvc_palette_444_entropy(writer: &mut VvcSyntaxWriter, frame: &Vvc4x4SampledFrame) {
    writer.write_cabac_bits(
        "cabac_vvc_palette_444_tile_entry_bits",
        &vvc_palette_444_cabac_bits(frame),
    );
}

fn vvc_palette_444_cabac_bits(frame: &Vvc4x4SampledFrame) -> Vec<bool> {
    let mut cabac = VvcCabacEncoder::new();
    let mut ctx = VvcPaletteCabacContexts::new();
    let mut predictor_mode = VvcPalettePredictorMode::SignalNewEntry;
    cabac.start();
    append_vvc_palette_444_tree(
        &mut cabac,
        &mut ctx,
        frame,
        &mut predictor_mode,
        0,
        0,
        vvc_palette_root_size(frame.geometry),
    );
    cabac.encode_bin_trm(true);
    cabac.finish()
}

fn vvc_palette_root_size(geometry: VvcVideoGeometry) -> u16 {
    let _ = geometry;
    VVC_PALETTE_CTU_SIZE
}

fn append_vvc_palette_444_tree(
    cabac: &mut VvcCabacEncoder,
    ctx: &mut VvcPaletteCabacContexts,
    frame: &Vvc4x4SampledFrame,
    predictor_mode: &mut VvcPalettePredictorMode,
    origin_x: u16,
    origin_y: u16,
    size: u16,
) {
    if !vvc_palette_cu_origin_is_visible(frame.geometry, origin_x, origin_y) {
        return;
    }
    if size == VVC_PALETTE_CU_SIZE {
        if append_vvc_palette_444_8x8_cu_with_events(
            cabac,
            ctx,
            frame,
            origin_x,
            origin_y,
            *predictor_mode,
        ) {
            *predictor_mode = VvcPalettePredictorMode::SignalNewEntryAfterPredictor;
        }
        return;
    }

    append_vvc_palette_split(cabac, ctx, frame.geometry, origin_x, origin_y, size);
    let child_size = size / 2;
    for child in 0..4 {
        let x = origin_x + if child & 1 == 0 { 0 } else { child_size };
        let y = origin_y + if child < 2 { 0 } else { child_size };
        append_vvc_palette_444_tree(cabac, ctx, frame, predictor_mode, x, y, child_size);
    }
}

#[derive(Debug, Clone, Copy)]
enum VvcPaletteQtCtxBase {
    Large,
    Small,
}

fn append_vvc_palette_split(
    cabac: &mut VvcCabacEncoder,
    ctx: &mut VvcPaletteCabacContexts,
    geometry: VvcVideoGeometry,
    origin_x: u16,
    origin_y: u16,
    size: u16,
) {
    let split_cu_flag_present = (origin_x as usize + size as usize) <= geometry.coded_width()
        && (origin_y as usize + size as usize) <= geometry.coded_height();
    match size {
        64 => {
            if split_cu_flag_present {
                ctx.encode(cabac, VvcPaletteCtx::Split0, true);
            }
        }
        32 => {
            if split_cu_flag_present {
                ctx.encode(cabac, vvc_palette_split_ctx(origin_x, origin_y, 32), true);
            }
            ctx.encode(
                cabac,
                vvc_palette_split_qt_ctx(origin_x, origin_y, 32, VvcPaletteQtCtxBase::Large),
                true,
            );
        }
        16 => {
            if split_cu_flag_present {
                ctx.encode(cabac, vvc_palette_split_ctx(origin_x, origin_y, 16), true);
            }
            ctx.encode(
                cabac,
                vvc_palette_split_qt_ctx(origin_x, origin_y, 16, VvcPaletteQtCtxBase::Small),
                true,
            );
        }
        _ => unreachable!("palette coding tree currently recurses to palette CU leaves"),
    }
}

fn vvc_palette_position_ctx_index(x: u16, y: u16, step: u16) -> u8 {
    u8::from(x >= step) + u8::from(y >= step)
}

fn vvc_palette_split_ctx(x: u16, y: u16, step: u16) -> VvcPaletteCtx {
    match vvc_palette_position_ctx_index(x, y, step) {
        0 => VvcPaletteCtx::Split6,
        1 => VvcPaletteCtx::Split7,
        _ => VvcPaletteCtx::Split8,
    }
}

fn vvc_palette_split_qt_ctx(x: u16, y: u16, step: u16, base: VvcPaletteQtCtxBase) -> VvcPaletteCtx {
    match (base, vvc_palette_position_ctx_index(x, y, step)) {
        (VvcPaletteQtCtxBase::Large, 0) => VvcPaletteCtx::SplitQt9,
        (VvcPaletteQtCtxBase::Large, 1) => VvcPaletteCtx::SplitQt10,
        (VvcPaletteQtCtxBase::Large, _) => VvcPaletteCtx::SplitQt11,
        (VvcPaletteQtCtxBase::Small, 0) => VvcPaletteCtx::SplitQt12,
        (VvcPaletteQtCtxBase::Small, 1) => VvcPaletteCtx::SplitQt13,
        (VvcPaletteQtCtxBase::Small, _) => VvcPaletteCtx::SplitQt14,
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum VvcPalettePredictorMode {
    SignalNewEntry,
    SignalNewEntryAfterPredictor,
}

fn append_vvc_palette_444_8x8_cu_with_events(
    cabac: &mut VvcCabacEncoder,
    ctx: &mut VvcPaletteCabacContexts,
    frame: &Vvc4x4SampledFrame,
    origin_x: u16,
    origin_y: u16,
    predictor_mode: VvcPalettePredictorMode,
) -> bool {
    if !vvc_palette_cu_origin_is_visible(frame.geometry, origin_x, origin_y) {
        return false;
    }
    ctx.encode(cabac, VvcPaletteCtx::Split0, false);
    ctx.encode(cabac, VvcPaletteCtx::PltFlag, true);
    let syntax = vvc_palette_444_cu_syntax(frame, origin_x as usize, origin_y as usize);
    let palette_index_map = syntax.palette_indices.clone();
    let current_palette_size = syntax.current_palette_size;
    for token in vvc_palette_444_syntax_tokens(syntax, predictor_mode) {
        append_palette_syntax_token_cabac(cabac, token);
    }
    append_vvc_palette_444_index_map(cabac, ctx, current_palette_size, &palette_index_map);
    true
}

fn append_vvc_palette_444_index_map(
    cabac: &mut VvcCabacEncoder,
    ctx: &mut VvcPaletteCabacContexts,
    current_palette_size: u8,
    palette_indices: &[u8],
) {
    if current_palette_size <= 1 {
        return;
    }

    ctx.encode(cabac, VvcPaletteCtx::RotationFlag, false);
    let scan_positions = vvc_palette_horizontal_scan_positions(8, 8);
    let scan_indices: Vec<u8> = scan_positions
        .iter()
        .map(|&(x, y)| palette_indices[y * 8 + x])
        .collect();
    let mut prev_run_pos = 0usize;
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
                    VvcPaletteCtx::IdxRunModel(vvc_palette_copy_flag_ctx_id(dist)),
                    identity,
                );
            }
            if !identity || cur_pos == 0 {
                let (_, y) = scan_positions[cur_pos];
                let run_type_is_inferred_index = y == 0;
                prev_run_pos = cur_pos;
                if cur_pos != 0 && !run_type_is_inferred_index {
                    ctx.encode(cabac, VvcPaletteCtx::RunTypeFlag, false);
                }
            };
            prev_index = index;
        }

        for cur_pos in min_sub_pos..max_sub_pos {
            if run_copy_flags[cur_pos - min_sub_pos] {
                continue;
            }
            let index = scan_indices[cur_pos];
            let max_symbol = current_palette_size as u32 - u32::from(cur_pos > 0);
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

fn vvc_palette_copy_flag_ctx_id(dist: usize) -> u8 {
    match dist {
        0 => 0,
        1 => 1,
        2 => 2,
        3 => 3,
        _ => 4,
    }
}

fn vvc_palette_cu_origin_is_visible(
    geometry: VvcVideoGeometry,
    origin_x: u16,
    origin_y: u16,
) -> bool {
    (origin_x as usize) < geometry.width && (origin_y as usize) < geometry.height
}

#[derive(Debug, Clone, Copy)]
enum VvcPaletteCtx {
    Split0,
    Split6,
    Split7,
    Split8,
    SplitQt9,
    SplitQt10,
    SplitQt11,
    SplitQt12,
    SplitQt13,
    SplitQt14,
    PltFlag,
    RotationFlag,
    RunTypeFlag,
    IdxRunModel(u8),
}

#[derive(Debug, Clone)]
struct VvcPaletteCabacContexts {
    split0: VvcCabacProbModel,
    split6: VvcCabacProbModel,
    split7: VvcCabacProbModel,
    split8: VvcCabacProbModel,
    split_qt9: VvcCabacProbModel,
    split_qt10: VvcCabacProbModel,
    split_qt11: VvcCabacProbModel,
    split_qt12: VvcCabacProbModel,
    split_qt13: VvcCabacProbModel,
    split_qt14: VvcCabacProbModel,
    plt_flag: VvcCabacProbModel,
    rotation_flag: VvcCabacProbModel,
    run_type_flag: VvcCabacProbModel,
    idx_run_model: [VvcCabacProbModel; 5],
}

impl VvcPaletteCabacContexts {
    const DEFAULT_SLICE_QP: i32 = 32;

    fn new() -> Self {
        Self {
            split0: Self::model_from_init(19, 12),
            split6: Self::model_from_init(20, 5),
            split7: Self::model_from_init(30, 9),
            split8: Self::model_from_init(31, 9),
            split_qt9: Self::model_from_init(27, 0),
            split_qt10: Self::model_from_init(6, 8),
            split_qt11: Self::model_from_init(15, 8),
            split_qt12: Self::model_from_init(25, 12),
            split_qt13: Self::model_from_init(19, 12),
            split_qt14: Self::model_from_init(37, 8),
            plt_flag: Self::model_from_init(22, 1),
            rotation_flag: Self::model_from_init(90, 5),
            run_type_flag: Self::model_from_init(90, 9),
            idx_run_model: [
                Self::model_from_init(106, 9),
                Self::model_from_init(182, 6),
                Self::model_from_init(198, 9),
                Self::model_from_init(202, 10),
                Self::model_from_init(234, 5),
            ],
        }
    }

    fn model_from_init(init_value: u8, log2_window_size: u8) -> VvcCabacProbModel {
        VvcCabacProbModel::from_init_value(init_value, Self::DEFAULT_SLICE_QP, log2_window_size)
    }

    fn encode(&mut self, cabac: &mut VvcCabacEncoder, ctx: VvcPaletteCtx, bin: bool) {
        match ctx {
            VvcPaletteCtx::Split0 => self.split0.encode(cabac, bin),
            VvcPaletteCtx::Split6 => self.split6.encode(cabac, bin),
            VvcPaletteCtx::Split7 => self.split7.encode(cabac, bin),
            VvcPaletteCtx::Split8 => self.split8.encode(cabac, bin),
            VvcPaletteCtx::SplitQt9 => self.split_qt9.encode(cabac, bin),
            VvcPaletteCtx::SplitQt10 => self.split_qt10.encode(cabac, bin),
            VvcPaletteCtx::SplitQt11 => self.split_qt11.encode(cabac, bin),
            VvcPaletteCtx::SplitQt12 => self.split_qt12.encode(cabac, bin),
            VvcPaletteCtx::SplitQt13 => self.split_qt13.encode(cabac, bin),
            VvcPaletteCtx::SplitQt14 => self.split_qt14.encode(cabac, bin),
            VvcPaletteCtx::PltFlag => self.plt_flag.encode(cabac, bin),
            VvcPaletteCtx::RotationFlag => self.rotation_flag.encode(cabac, bin),
            VvcPaletteCtx::RunTypeFlag => self.run_type_flag.encode(cabac, bin),
            VvcPaletteCtx::IdxRunModel(ctx_id) => {
                self.idx_run_model[ctx_id as usize].encode(cabac, bin)
            }
        }
    }
}

#[cfg(test)]
pub(super) fn vvc_palette_444_single_entry_syntax(
    geometry: VvcVideoGeometry,
    color: Vvc4x4SampledColor,
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
    }
}

pub(super) fn vvc_palette_444_cu_syntax(
    frame: &Vvc4x4SampledFrame,
    origin_x: usize,
    origin_y: usize,
) -> VvcPalette444Syntax {
    let mut entries = Vec::new();
    let mut indices = Vec::new();
    let width = 8.min(frame.geometry.width.saturating_sub(origin_x));
    let height = 8.min(frame.geometry.height.saturating_sub(origin_y));

    for y_off in 0..height {
        for x_off in 0..width {
            let color = vvc_palette_444_sample_at(frame, origin_x + x_off, origin_y + y_off);
            let index = if let Some(index) = entries.iter().position(|entry| *entry == color) {
                index
            } else if entries.len() < 31 {
                entries.push(color);
                entries.len() - 1
            } else {
                // TODO: add palette escape coding for CUs with more than 31 colors.
                30
            };
            indices.push(index as u8);
        }
    }

    let current_palette_size = entries.len().max(1) as u8;
    let max_palette_index = current_palette_size.saturating_sub(1);
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
        palette_escape_val_present_flag: false,
        max_palette_index,
        palette_indices: if max_palette_index == 0 {
            Vec::new()
        } else {
            indices
        },
    }
}

fn vvc_palette_444_sample_at(frame: &Vvc4x4SampledFrame, x: usize, y: usize) -> Vvc4x4SampledColor {
    debug_assert_eq!(frame.format.chroma_sampling, ChromaSampling::Cs444);
    let sample_x = x.min(frame.geometry.width.saturating_sub(1));
    let sample_y = y.min(frame.geometry.height.saturating_sub(1));
    let index = sample_y * frame.geometry.width + sample_x;
    Vvc4x4SampledColor {
        y: frame.luma[index],
        u: frame.cb[index],
        v: frame.cr[index],
    }
}

fn vvc_palette_444_tile_entries(frame: &Vvc4x4SampledFrame) -> Vec<VvcPalette444TileEntry> {
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
    // CurrentPaletteEntries is derived from the single signalled entry. Since
    // MaxPaletteIndex is 0, palette_idx_idc is not present and each
    // PaletteIndexMap sample is inferred to 0. The picture reconstruction
    // process receives zero residual samples, so predSamples become recSamples.
    debug_assert_eq!(syntax.tree_type, VvcPaletteTreeType::SingleTree);
    debug_assert_eq!(syntax.start_comp, 0);
    debug_assert_eq!(syntax.num_comps, 3);
    debug_assert!(!syntax.palette_escape_val_present_flag);

    let samples = geometry.luma_samples();
    if syntax.max_palette_index == 0 {
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
    for index in syntax.palette_indices {
        let entry = syntax.new_palette_entries[index as usize];
        luma.push(entry.y);
        cb.push(entry.u);
        cr.push(entry.v);
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
