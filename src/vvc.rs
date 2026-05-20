//! First-target VVC/H.266 syntax experiments.
//!
//! This module contains a clean-room toy VVC path that can emit a tiny
//! decoder-accepted 4x4 all-intra stream. It is still intentionally incomplete:
//! CABAC, CTU syntax generation, transform/quant, prediction, and
//! reconstruction semantics need to be replaced with real implementations
//! before FrameForge can encode from arbitrary input pictures.

use crate::bitstream::insert_emulation_prevention_bytes;
use crate::bitstream::{rbsp_trailing_bits, BitWriter};
use crate::picture::{Picture, PixelFormat};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VvcSyntaxCode {
    Flag,
    U,
    Ue,
    Se,
    CabacPacket,
    RbspTrailingBits,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VvcSyntaxField {
    pub name: &'static str,
    pub code: VvcSyntaxCode,
    pub bit_offset: usize,
    pub bit_count: usize,
}

#[derive(Debug, Default, Clone)]
pub struct VvcSyntaxWriter {
    writer: BitWriter,
    fields: Vec<VvcSyntaxField>,
    bit_offset: usize,
}

impl VvcSyntaxWriter {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn write_flag(&mut self, name: &'static str, value: bool) {
        self.push_field(name, VvcSyntaxCode::Flag, 1);
        self.writer.write_bool(value);
        self.bit_offset += 1;
    }

    pub fn write_u(&mut self, name: &'static str, value: u64, bit_count: u8) {
        assert!(bit_count <= 64, "u(n) cannot write more than 64 bits");
        if bit_count < 64 {
            assert!(
                value < (1u64 << bit_count),
                "value does not fit in u({bit_count})"
            );
        }
        self.push_field(name, VvcSyntaxCode::U, bit_count as usize);
        self.writer.write_bits(value, bit_count);
        self.bit_offset += bit_count as usize;
    }

    pub fn write_ue(&mut self, name: &'static str, value: u32) {
        let code_num = value as u64 + 1;
        self.write_exp_golomb_code(name, VvcSyntaxCode::Ue, code_num);
    }

    pub fn write_se(&mut self, name: &'static str, value: i32) {
        let code_num = if value > 0 {
            (value as u64) * 2
        } else {
            (value.unsigned_abs() as u64 * 2) + 1
        };
        self.write_exp_golomb_code(name, VvcSyntaxCode::Se, code_num);
    }

    fn write_exp_golomb_code(&mut self, name: &'static str, code: VvcSyntaxCode, code_num: u64) {
        debug_assert!(code_num > 0);
        let bit_count = 64 - code_num.leading_zeros() as u8;
        let leading_zero_bits = bit_count - 1;
        let total_bits = (leading_zero_bits * 2) + 1;
        self.push_field(name, code, total_bits as usize);
        for _ in 0..leading_zero_bits {
            self.writer.write_bit(false);
        }
        self.writer.write_bits(code_num, bit_count);
        self.bit_offset += total_bits as usize;
    }

    pub fn write_cabac_packet(&mut self, name: &'static str, value: u64, bit_count: u8) {
        assert!(
            bit_count <= 64,
            "CABAC packet cannot write more than 64 bits"
        );
        self.push_field(name, VvcSyntaxCode::CabacPacket, bit_count as usize);
        self.writer.write_bits(value, bit_count);
        self.bit_offset += bit_count as usize;
    }

    pub fn rbsp_trailing_bits(&mut self) {
        let bit_count = if self.writer.is_byte_aligned() {
            8
        } else {
            8 - (self.bit_offset % 8)
        };
        self.push_field(
            "rbsp_trailing_bits",
            VvcSyntaxCode::RbspTrailingBits,
            bit_count,
        );
        rbsp_trailing_bits(&mut self.writer);
        self.bit_offset += bit_count;
    }

    pub fn is_byte_aligned(&self) -> bool {
        self.writer.is_byte_aligned()
    }

    pub fn fields(&self) -> &[VvcSyntaxField] {
        &self.fields
    }

    pub fn into_bytes(self) -> Vec<u8> {
        self.writer.into_bytes()
    }

    pub fn finish(self) -> VvcSyntaxRbsp {
        VvcSyntaxRbsp {
            bytes: self.writer.into_bytes(),
            fields: self.fields,
        }
    }

    fn push_field(&mut self, name: &'static str, code: VvcSyntaxCode, bit_count: usize) {
        self.fields.push(VvcSyntaxField {
            name,
            code,
            bit_offset: self.bit_offset,
            bit_count,
        });
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VvcSyntaxRbsp {
    pub bytes: Vec<u8>,
    pub fields: Vec<VvcSyntaxField>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VvcProfileTarget {
    MinimalToyAllIntra,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct VvcSubset {
    pub all_intra: bool,
    pub single_picture: bool,
    pub one_tile: bool,
    pub one_slice: bool,
}

impl Default for VvcSubset {
    fn default() -> Self {
        Self {
            all_intra: true,
            single_picture: true,
            one_tile: true,
            one_slice: true,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum VvcNalUnitType {
    Trail = 0,
    IdrWRadl = 7,
    IdrNLp = 8,
    Cra = 9,
    Opi = 12,
    Dci = 13,
    Vps = 14,
    Sps = 15,
    Pps = 16,
    PrefixAps = 17,
    SuffixAps = 18,
    PictureHeader = 19,
    AccessUnitDelimiter = 20,
    EndOfSequence = 21,
    EndOfBitstream = 22,
    PrefixSei = 23,
    SuffixSei = 24,
    FillerData = 25,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VvcNalUnit {
    pub nal_unit_type: VvcNalUnitType,
    pub layer_id: u8,
    pub temporal_id: u8,
    pub rbsp_payload: Vec<u8>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct VvcNalHeader {
    pub forbidden_zero_bit: bool,
    pub nuh_reserved_zero_bit: bool,
    pub layer_id: u8,
    pub nal_unit_type: VvcNalUnitType,
    pub temporal_id: u8,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VvcNalInfo {
    pub nal_unit_type: u8,
    pub layer_id: u8,
    pub temporal_id: u8,
    pub payload_len: usize,
    pub offset: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Toy4x4EncodeParams {
    pub frames: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Toy4x4SampledColor {
    pub y: u8,
    pub u: u8,
    pub v: u8,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Toy4x4PictureKind {
    Idr,
    Cra,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct ToyCabacPacket {
    name: &'static str,
    bits: u64,
    bit_count: u8,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ToyCodingTreeEvent {
    LumaSplitAndCuPrefix { irap_prefix: u8 },
    LumaIntraPrediction,
    LumaTransformUnitPrefix,
    LumaResidualPrefix,
    LumaResidualSuffixEp,
    ChromaTreePrefix,
    ChromaResidualPrefix,
    CabacAlignment,
}

impl VvcNalUnit {
    pub fn eos() -> Self {
        Self {
            nal_unit_type: VvcNalUnitType::EndOfSequence,
            layer_id: 0,
            temporal_id: 0,
            rbsp_payload: Vec::new(),
        }
    }

    pub fn eob() -> Self {
        Self {
            nal_unit_type: VvcNalUnitType::EndOfBitstream,
            layer_id: 0,
            temporal_id: 0,
            rbsp_payload: Vec::new(),
        }
    }
}

pub fn write_annex_b(units: &[VvcNalUnit]) -> Result<Vec<u8>, String> {
    let mut out = Vec::new();
    for unit in units {
        out.extend_from_slice(&[0x00, 0x00, 0x00, 0x01]);
        out.extend_from_slice(&nal_unit_header_bytes(unit)?);
        out.extend_from_slice(&insert_emulation_prevention_bytes(&unit.rbsp_payload));
    }
    Ok(out)
}

pub fn eos_annex_b() -> Vec<u8> {
    write_annex_b(&[VvcNalUnit::eos()]).expect("hard-coded EOS NAL should be valid")
}

pub fn skeleton_annex_b() -> Vec<u8> {
    let placeholder_rbsp = placeholder_rbsp();
    write_annex_b(&[
        VvcNalUnit {
            nal_unit_type: VvcNalUnitType::Vps,
            layer_id: 0,
            temporal_id: 0,
            rbsp_payload: placeholder_rbsp.clone(),
        },
        VvcNalUnit {
            nal_unit_type: VvcNalUnitType::Sps,
            layer_id: 0,
            temporal_id: 0,
            rbsp_payload: placeholder_rbsp.clone(),
        },
        VvcNalUnit {
            nal_unit_type: VvcNalUnitType::Pps,
            layer_id: 0,
            temporal_id: 0,
            rbsp_payload: placeholder_rbsp.clone(),
        },
        VvcNalUnit {
            nal_unit_type: VvcNalUnitType::IdrNLp,
            layer_id: 0,
            temporal_id: 0,
            rbsp_payload: placeholder_rbsp,
        },
        VvcNalUnit::eos(),
        VvcNalUnit::eob(),
    ])
    .expect("hard-coded skeleton NAL units should be valid")
}

pub fn toy_black_4x4_yuv420p8_annex_b(params: Toy4x4EncodeParams) -> Result<Vec<u8>, String> {
    validate_toy_4x4_frame_count(params)?;
    toy_4x4_yuv420p8_annex_b(params)
}

pub fn toy_4x4_yuv420p8_annex_b_from_input(
    input: &[u8],
    params: Toy4x4EncodeParams,
) -> Result<Vec<u8>, String> {
    validate_toy_4x4_frame_count(params)?;
    let color = sample_toy_4x4_first_yuv420p8(input, params)?;
    if color != (Toy4x4SampledColor { y: 0, u: 0, v: 0 }) {
        return Err(format!(
            "toy VVC bitstream generation currently supports only black after first-pixel sampling; got y={} u={} v={}",
            color.y, color.u, color.v
        ));
    }

    toy_4x4_yuv420p8_annex_b(params)
}

pub fn sample_toy_4x4_first_yuv420p8(
    input: &[u8],
    params: Toy4x4EncodeParams,
) -> Result<Toy4x4SampledColor, String> {
    validate_toy_4x4_frame_count(params)?;
    let frame_len = Picture::expected_len(4, 4, PixelFormat::Yuv420p8);
    let expected_len = frame_len * params.frames;
    if input.len() != expected_len {
        return Err(format!(
            "toy VVC input size mismatch: got {} bytes, expected {} for 4x4 yuv420p8 with {} frame(s)",
            input.len(),
            expected_len,
            params.frames
        ));
    }

    Ok(Toy4x4SampledColor {
        y: input[0],
        u: input[16],
        v: input[20],
    })
}

fn validate_toy_4x4_frame_count(params: Toy4x4EncodeParams) -> Result<(), String> {
    if params.frames == 0 {
        return Err("toy VVC encode expects at least one frame".to_string());
    }
    if params.frames > 2 {
        return Err("toy VVC encode currently supports at most two frames".to_string());
    }
    Ok(())
}

fn toy_4x4_yuv420p8_annex_b(params: Toy4x4EncodeParams) -> Result<Vec<u8>, String> {
    let mut units = Vec::with_capacity(params.frames + 2);
    units.push(toy_4x4_sps_unit());
    units.push(toy_4x4_pps_unit());
    for frame_idx in 0..params.frames {
        units.push(toy_4x4_slice_unit(frame_idx)?);
    }
    write_annex_b(&units)
}

fn toy_4x4_sps_unit() -> VvcNalUnit {
    VvcNalUnit {
        nal_unit_type: VvcNalUnitType::Sps,
        layer_id: 0,
        temporal_id: 0,
        rbsp_payload: toy_4x4_sps_payload(),
    }
}

fn toy_4x4_pps_unit() -> VvcNalUnit {
    VvcNalUnit {
        nal_unit_type: VvcNalUnitType::Pps,
        layer_id: 0,
        temporal_id: 0,
        rbsp_payload: toy_4x4_pps_payload(),
    }
}

fn toy_4x4_slice_unit(frame_idx: usize) -> Result<VvcNalUnit, String> {
    let picture_kind = match frame_idx {
        0 => Toy4x4PictureKind::Idr,
        1 => Toy4x4PictureKind::Cra,
        _ => return Err(format!("unsupported toy VVC frame index {frame_idx}")),
    };

    Ok(VvcNalUnit {
        nal_unit_type: match picture_kind {
            Toy4x4PictureKind::Idr => VvcNalUnitType::IdrNLp,
            Toy4x4PictureKind::Cra => VvcNalUnitType::Cra,
        },
        layer_id: 0,
        temporal_id: 0,
        rbsp_payload: toy_4x4_slice_payload(picture_kind),
    })
}

fn toy_4x4_sps_payload() -> Vec<u8> {
    let mut writer = VvcSyntaxWriter::new();
    writer.write_u("sps_seq_parameter_set_id", 0, 4);
    writer.write_u("sps_video_parameter_set_id", 0, 4);
    writer.write_u("sps_max_sub_layers_minus1", 0, 3);
    writer.write_u("sps_chroma_format_idc", 1, 2);
    writer.write_u("sps_log2_ctu_size_minus5", 1, 2);
    writer.write_flag("sps_ptl_dpb_hrd_params_present_flag", true);
    writer.write_u("general_profile_idc", 1, 7);
    writer.write_flag("general_tier_flag", false);
    writer.write_u("general_level_idc", 0, 8);
    writer.write_flag("ptl_frame_only_constraint_flag", true);
    writer.write_flag("ptl_multilayer_enabled_flag", false);
    writer.write_flag("gci_present_flag", false);
    for _ in 0..5 {
        writer.write_flag("gci_alignment_zero_bit", false);
    }
    writer.write_u("ptl_num_sub_profiles", 0, 8);
    writer.write_flag("sps_gdr_enabled_flag", false);
    writer.write_flag("sps_ref_pic_resampling_enabled_flag", true);
    writer.write_flag("sps_res_change_in_clvs_allowed_flag", false);
    writer.write_ue("sps_pic_width_max_in_luma_samples", 8);
    writer.write_ue("sps_pic_height_max_in_luma_samples", 8);
    writer.write_flag("sps_conformance_window_flag", true);
    writer.write_ue("sps_conf_win_left_offset", 0);
    writer.write_ue("sps_conf_win_right_offset", 2);
    writer.write_ue("sps_conf_win_top_offset", 0);
    writer.write_ue("sps_conf_win_bottom_offset", 2);
    writer.write_flag("sps_subpic_info_present_flag", false);
    writer.write_ue("sps_bitdepth_minus8", 0);
    writer.write_flag("sps_entropy_coding_sync_enabled_flag", false);
    writer.write_flag("sps_entry_point_offsets_present_flag", true);
    writer.write_u("sps_log2_max_pic_order_cnt_lsb_minus4", 4, 4);
    writer.write_flag("sps_poc_msb_cycle_flag", false);
    writer.write_u("sps_num_extra_ph_bytes", 0, 2);
    writer.write_u("sps_num_extra_sh_bytes", 0, 2);
    writer.write_ue("dpb_max_dec_pic_buffering_minus1[i]", 0);
    writer.write_ue("dpb_max_num_reorder_pics[i]", 0);
    writer.write_ue("dpb_max_latency_increase_plus1[i]", 0);
    writer.write_ue("sps_log2_min_luma_coding_block_size_minus2", 0);
    writer.write_flag("sps_partition_constraints_override_enabled_flag", true);
    writer.write_ue("sps_log2_diff_min_qt_min_cb_intra_slice_luma", 1);
    writer.write_ue("sps_max_mtt_hierarchy_depth_intra_slice_luma", 3);
    writer.write_ue("sps_log2_diff_max_bt_min_qt_intra_slice_luma", 2);
    writer.write_ue("sps_log2_diff_max_tt_min_qt_intra_slice_luma", 2);
    writer.write_flag("sps_qtbtt_dual_tree_intra_flag", true);
    writer.write_ue("sps_log2_diff_min_qt_min_cb_intra_slice_chroma", 1);
    writer.write_ue("sps_max_mtt_hierarchy_depth_intra_slice_chroma", 3);
    writer.write_ue("sps_log2_diff_max_bt_min_qt_intra_slice_chroma", 3);
    writer.write_ue("sps_log2_diff_max_tt_min_qt_intra_slice_chroma", 2);
    writer.write_ue("sps_log2_diff_min_qt_min_cb_inter_slice", 1);
    writer.write_ue("sps_max_mtt_hierarchy_depth_inter_slice", 3);
    writer.write_ue("sps_log2_diff_max_bt_min_qt_inter_slice", 3);
    writer.write_ue("sps_log2_diff_max_tt_min_qt_inter_slice", 3);
    writer.write_flag("sps_max_luma_transform_size_64_flag", true);
    writer.write_flag("sps_transform_skip_enabled_flag", false);
    writer.write_flag("sps_mts_enabled_flag", false);
    writer.write_flag("sps_lfnst_enabled_flag", false);
    writer.write_flag("sps_joint_cbcr_enabled_flag", true);
    writer.write_flag("sps_same_qp_table_for_chroma_flag", true);
    writer.write_se("sps_qp_table_starts_minus26", -9);
    writer.write_ue("sps_num_points_in_qp_table_minus1", 2);
    writer.write_ue("sps_delta_qp_in_val_minus1", 9);
    writer.write_ue("sps_delta_qp_diff_val", 5);
    writer.write_ue("sps_delta_qp_in_val_minus1", 4);
    writer.write_ue("sps_delta_qp_diff_val", 1);
    writer.write_ue("sps_delta_qp_in_val_minus1", 11);
    writer.write_ue("sps_delta_qp_diff_val", 12);
    writer.write_flag("sps_sao_enabled_flag", false);
    writer.write_flag("sps_alf_enabled_flag", false);
    writer.write_flag("sps_lmcs_enable_flag", false);
    writer.write_flag("sps_weighted_pred_flag", false);
    writer.write_flag("sps_weighted_bipred_flag", false);
    writer.write_flag("sps_long_term_ref_pics_flag", false);
    writer.write_flag("sps_idr_rpl_present_flag", false);
    writer.write_flag("sps_rpl1_same_as_rpl0_flag", true);
    writer.write_ue("sps_num_ref_pic_lists[0]", 1);
    writer.write_ue("num_ref_entries[listIdx][rplsIdx]", 0);
    writer.write_flag("sps_ref_wraparound_enabled_flag", false);
    writer.write_flag("sps_temporal_mvp_enabled_flag", true);
    writer.write_flag("sps_sbtmvp_enabled_flag", true);
    writer.write_flag("sps_amvr_enabled_flag", true);
    writer.write_flag("sps_bdof_enabled_flag", false);
    writer.write_flag("sps_smvd_enabled_flag", false);
    writer.write_flag("sps_dmvr_enabled_flag", false);
    writer.write_flag("sps_mmvd_enabled_flag", true);
    writer.write_flag("sps_mmvd_fullpel_only_flag", true);
    writer.write_ue("sps_six_minus_max_num_merge_cand", 0);
    writer.write_flag("sps_sbt_enabled_flag", true);
    writer.write_flag("sps_affine_enabled_flag", true);
    writer.write_ue("sps_five_minus_max_num_subblock_merge_cand", 0);
    writer.write_flag("sps_affine_type_flag", true);
    writer.write_flag("sps_affine_amvr_enabled_flag", false);
    writer.write_flag("sps_affine_prof_enabled_flag", false);
    writer.write_flag("sps_bcw_enabled_flag", false);
    writer.write_flag("sps_ciip_enabled_flag", false);
    writer.write_flag("sps_gpm_enabled_flag", false);
    writer.write_ue("sps_log2_parallel_merge_level_minus2", 0);
    writer.write_flag("sps_isp_enabled_flag", false);
    writer.write_flag("sps_mrl_enabled_flag", true);
    writer.write_flag("sps_mip_enabled_flag", false);
    writer.write_flag("sps_cclm_enabled_flag", true);
    writer.write_flag("sps_chroma_horizontal_collocated_flag", true);
    writer.write_flag("sps_chroma_vertical_collocated_flag", false);
    writer.write_flag("sps_palette_enabled_flag", false);
    writer.write_flag("sps_ibc_enabled_flag", false);
    writer.write_flag("sps_ladf_enabled_flag", false);
    writer.write_flag("sps_explicit_scaling_list_enabled_flag", false);
    writer.write_flag("sps_dep_quant_enabled_flag", true);
    writer.write_flag("sps_sign_data_hiding_enabled_flag", false);
    writer.write_flag("sps_virtual_boundaries_enabled_flag", false);
    writer.write_flag("sps_timing_hrd_params_present_flag", false);
    writer.write_flag("sps_field_seq_flag", false);
    writer.write_flag("sps_vui_parameters_present_flag", false);
    writer.write_flag("sps_extension_present_flag", false);
    writer.rbsp_trailing_bits();
    debug_assert!(writer.is_byte_aligned());
    writer.into_bytes()
}

fn toy_4x4_pps_payload() -> Vec<u8> {
    let mut writer = VvcSyntaxWriter::new();
    writer.write_u("pps_pic_parameter_set_id", 0, 6);
    writer.write_u("pps_seq_parameter_set_id", 0, 4);
    writer.write_flag("pps_mixed_nalu_types_in_pic_flag", false);
    writer.write_ue("pps_pic_width_in_luma_samples", 8);
    writer.write_ue("pps_pic_height_in_luma_samples", 8);
    writer.write_flag("pps_conformance_window_flag", false);
    writer.write_flag("pps_scaling_window_explicit_signalling_flag", false);
    writer.write_flag("pps_output_flag_present_flag", false);
    writer.write_flag("pps_no_pic_partition_flag", true);
    writer.write_flag("pps_subpic_id_mapping_present_flag", false);
    writer.write_flag("pps_cabac_init_present_flag", true);
    writer.write_ue("pps_num_ref_idx_default_active_minus1[0]", 3);
    writer.write_ue("pps_num_ref_idx_default_active_minus1[1]", 3);
    writer.write_flag("pps_rpl1_idx_present_flag", false);
    writer.write_flag("pps_weighted_pred_flag", false);
    writer.write_flag("pps_weighted_bipred_flag", false);
    writer.write_flag("pps_ref_wraparound_enabled_flag", false);
    writer.write_se("pps_init_qp_minus26", 6);
    writer.write_flag("pps_cu_qp_delta_enabled_flag", false);
    writer.write_flag("pps_chroma_tool_offsets_present_flag", true);
    writer.write_se("pps_cb_qp_offset", 0);
    writer.write_se("pps_cr_qp_offset", 0);
    writer.write_flag("pps_joint_cbcr_qp_offset_present_flag", true);
    writer.write_se("pps_joint_cbcr_qp_offset_value", -1);
    writer.write_flag("pps_slice_chroma_qp_offsets_present_flag", false);
    writer.write_flag("pps_cu_chroma_qp_offset_list_enabled_flag", false);
    writer.write_flag("pps_deblocking_filter_control_present_flag", true);
    writer.write_flag("pps_deblocking_filter_override_enabled_flag", false);
    writer.write_flag("pps_deblocking_filter_disabled_flag", false);
    writer.write_se("pps_beta_offset_div2", -2);
    writer.write_se("pps_tc_offset_div2", -5);
    writer.write_se("pps_cb_beta_offset_div2", -2);
    writer.write_se("pps_cb_tc_offset_div2", -5);
    writer.write_se("pps_cr_beta_offset_div2", -2);
    writer.write_se("pps_cr_tc_offset_div2", -5);
    writer.write_flag("pps_picture_header_extension_present_flag", false);
    writer.write_flag("pps_slice_header_extension_present_flag", false);
    writer.write_flag("pps_extension_flag", false);
    writer.rbsp_trailing_bits();
    debug_assert!(writer.is_byte_aligned());
    writer.into_bytes()
}

fn toy_4x4_slice_payload(picture_kind: Toy4x4PictureKind) -> Vec<u8> {
    let mut writer = VvcSyntaxWriter::new();
    writer.write_flag("sh_picture_header_in_slice_header_flag", true);
    writer.write_flag("ph_gdr_or_irap_pic_flag", true);
    writer.write_flag("ph_non_ref_pic_flag", false);
    writer.write_flag("ph_gdr_pic_flag", false);
    writer.write_flag("ph_inter_slice_allowed_flag", false);
    writer.write_ue("ph_pic_parameter_set_id", 0);
    match picture_kind {
        Toy4x4PictureKind::Idr => {
            writer.write_u("ph_pic_order_cnt_lsb", 0, 8);
        }
        Toy4x4PictureKind::Cra => {
            writer.write_u("ph_pic_order_cnt_lsb", 1, 8);
        }
    }
    writer.write_flag("ph_partition_constraints_override_flag", false);
    writer.write_flag("ph_joint_cbcr_sign_flag", false);
    writer.write_flag("sh_no_output_of_prior_pics_flag", false);
    writer.write_se("sh_qp_delta", 0);
    writer.write_flag("sh_dep_quant_used_flag", true);
    write_toy_coding_tree_entropy(&mut writer, picture_kind);
    debug_assert!(writer.is_byte_aligned());
    writer.into_bytes()
}

fn write_toy_coding_tree_entropy(writer: &mut VvcSyntaxWriter, picture_kind: Toy4x4PictureKind) {
    for event in toy_4x4_coding_tree_events(picture_kind) {
        let packet = toy_cabac_packet(event);
        writer.write_cabac_packet(packet.name, packet.bits, packet.bit_count);
    }
}

fn toy_4x4_coding_tree_events(picture_kind: Toy4x4PictureKind) -> [ToyCodingTreeEvent; 8] {
    let irap_prefix = match picture_kind {
        Toy4x4PictureKind::Idr => 0b1000,
        Toy4x4PictureKind::Cra => 0b1100,
    };

    [
        ToyCodingTreeEvent::LumaSplitAndCuPrefix { irap_prefix },
        ToyCodingTreeEvent::LumaIntraPrediction,
        ToyCodingTreeEvent::LumaTransformUnitPrefix,
        ToyCodingTreeEvent::LumaResidualPrefix,
        ToyCodingTreeEvent::LumaResidualSuffixEp,
        ToyCodingTreeEvent::ChromaTreePrefix,
        ToyCodingTreeEvent::ChromaResidualPrefix,
        ToyCodingTreeEvent::CabacAlignment,
    ]
}

fn toy_cabac_packet(event: ToyCodingTreeEvent) -> ToyCabacPacket {
    // TODO(vvc): Replace this packetizer with a real CABAC arithmetic engine.
    // The event sequence is the software/RTL boundary; these packet values keep
    // the current clean-room toy stream VTM-decodable while we grow the model.
    match event {
        ToyCodingTreeEvent::LumaSplitAndCuPrefix { irap_prefix } => ToyCabacPacket {
            name: "cabac_luma_split_cu_prefix",
            bits: irap_prefix as u64,
            bit_count: 4,
        },
        ToyCodingTreeEvent::LumaIntraPrediction => ToyCabacPacket {
            name: "cabac_luma_intra_prediction",
            bits: 0b0100,
            bit_count: 4,
        },
        ToyCodingTreeEvent::LumaTransformUnitPrefix => ToyCabacPacket {
            name: "cabac_luma_transform_unit_prefix",
            bits: 0x03,
            bit_count: 8,
        },
        ToyCodingTreeEvent::LumaResidualPrefix => ToyCabacPacket {
            name: "cabac_luma_residual_prefix",
            bits: 0x17ad,
            bit_count: 16,
        },
        ToyCodingTreeEvent::LumaResidualSuffixEp => ToyCabacPacket {
            name: "cabac_luma_residual_suffix_ep",
            bits: 0xbf5e,
            bit_count: 16,
        },
        ToyCodingTreeEvent::ChromaTreePrefix => ToyCabacPacket {
            name: "cabac_chroma_tree_prefix",
            bits: 0x58,
            bit_count: 8,
        },
        ToyCodingTreeEvent::ChromaResidualPrefix => ToyCabacPacket {
            name: "cabac_chroma_residual_prefix",
            bits: 0xfc,
            bit_count: 8,
        },
        ToyCodingTreeEvent::CabacAlignment => ToyCabacPacket {
            name: "cabac_alignment_zero_bits",
            bits: 0,
            bit_count: 5,
        },
    }
}

fn placeholder_rbsp() -> Vec<u8> {
    // TODO(vvc): Replace this rbsp_trailing_bits-only payload with real VPS,
    // SPS, PPS, and slice RBSP syntax from a clean-room implementation.
    let mut writer = VvcSyntaxWriter::new();
    writer.rbsp_trailing_bits();
    writer.into_bytes()
}

pub fn nal_unit_header_bytes(unit: &VvcNalUnit) -> Result<[u8; 2], String> {
    if unit.layer_id > 55 {
        return Err("VVC nuh_layer_id must be in the range 0..=55".to_string());
    }
    if unit.temporal_id > 6 {
        return Err("VVC temporal_id must be in the range 0..=6".to_string());
    }

    let header = VvcNalHeader {
        forbidden_zero_bit: false,
        nuh_reserved_zero_bit: false,
        layer_id: unit.layer_id,
        nal_unit_type: unit.nal_unit_type,
        temporal_id: unit.temporal_id,
    };
    let bytes = write_nal_unit_header(header).bytes;
    Ok([bytes[0], bytes[1]])
}

pub fn write_nal_unit_header(header: VvcNalHeader) -> VvcSyntaxRbsp {
    let mut writer = VvcSyntaxWriter::new();
    writer.write_flag("forbidden_zero_bit", header.forbidden_zero_bit);
    writer.write_flag("nuh_reserved_zero_bit", header.nuh_reserved_zero_bit);
    writer.write_u("nuh_layer_id", header.layer_id as u64, 6);
    writer.write_u("nal_unit_type", header.nal_unit_type as u64, 5);
    writer.write_u("nuh_temporal_id_plus1", header.temporal_id as u64 + 1, 3);
    writer.finish()
}

pub fn parse_annex_b_nal_units(bytes: &[u8]) -> Result<Vec<VvcNalInfo>, String> {
    let ranges = annex_b_ranges(bytes);
    let mut infos = Vec::with_capacity(ranges.len());

    for (start, end) in ranges {
        if end - start < 2 {
            return Err(format!(
                "NAL unit at offset {start} is too short for a VVC header"
            ));
        }
        let h0 = bytes[start];
        let h1 = bytes[start + 1];
        let forbidden_zero_bit = h0 >> 7;
        let nuh_reserved_zero_bit = (h0 >> 6) & 0x01;
        if forbidden_zero_bit != 0 || nuh_reserved_zero_bit != 0 {
            return Err(format!(
                "invalid VVC NAL header reserved bits at offset {start}"
            ));
        }
        let layer_id = h0 & 0x3f;
        if layer_id > 55 {
            return Err(format!(
                "VVC layer id {layer_id} out of range at offset {start}"
            ));
        }
        let nal_unit_type = h1 >> 3;
        let temporal_id_plus1 = h1 & 0x07;
        if temporal_id_plus1 == 0 {
            return Err(format!("VVC temporal_id_plus1 is zero at offset {start}"));
        }
        infos.push(VvcNalInfo {
            nal_unit_type,
            layer_id,
            temporal_id: temporal_id_plus1 - 1,
            payload_len: end - start - 2,
            offset: start,
        });
    }

    Ok(infos)
}

fn annex_b_ranges(bytes: &[u8]) -> Vec<(usize, usize)> {
    let mut starts = Vec::new();
    let mut i = 0;
    while i + 3 <= bytes.len() {
        if i + 4 <= bytes.len() && bytes[i..i + 4] == [0, 0, 0, 1] {
            starts.push((i, 4));
            i += 4;
        } else if bytes[i..i + 3] == [0, 0, 1] {
            starts.push((i, 3));
            i += 3;
        } else {
            i += 1;
        }
    }

    starts
        .iter()
        .enumerate()
        .map(|(idx, (prefix_pos, prefix_len))| {
            let payload_start = prefix_pos + prefix_len;
            let payload_end = starts
                .get(idx + 1)
                .map(|(next_prefix_pos, _)| *next_prefix_pos)
                .unwrap_or(bytes.len());
            (payload_start, payload_end)
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn eos_header_matches_vvc_packing() {
        let unit = VvcNalUnit::eos();
        assert_eq!(nal_unit_header_bytes(&unit).unwrap(), [0x00, 0xa9]);
    }

    #[test]
    fn nal_header_writer_records_named_fields() {
        let rbsp = write_nal_unit_header(VvcNalHeader {
            forbidden_zero_bit: false,
            nuh_reserved_zero_bit: false,
            layer_id: 0,
            nal_unit_type: VvcNalUnitType::IdrNLp,
            temporal_id: 0,
        });

        assert_eq!(rbsp.bytes, vec![0x00, 0x41]);
        assert_eq!(
            rbsp.fields,
            vec![
                VvcSyntaxField {
                    name: "forbidden_zero_bit",
                    code: VvcSyntaxCode::Flag,
                    bit_offset: 0,
                    bit_count: 1,
                },
                VvcSyntaxField {
                    name: "nuh_reserved_zero_bit",
                    code: VvcSyntaxCode::Flag,
                    bit_offset: 1,
                    bit_count: 1,
                },
                VvcSyntaxField {
                    name: "nuh_layer_id",
                    code: VvcSyntaxCode::U,
                    bit_offset: 2,
                    bit_count: 6,
                },
                VvcSyntaxField {
                    name: "nal_unit_type",
                    code: VvcSyntaxCode::U,
                    bit_offset: 8,
                    bit_count: 5,
                },
                VvcSyntaxField {
                    name: "nuh_temporal_id_plus1",
                    code: VvcSyntaxCode::U,
                    bit_offset: 13,
                    bit_count: 3,
                },
            ]
        );
    }

    #[test]
    fn eos_annex_b_contains_start_code_and_header() {
        assert_eq!(eos_annex_b(), vec![0x00, 0x00, 0x00, 0x01, 0x00, 0xa9]);
    }

    #[test]
    fn skeleton_annex_b_contains_parameter_sets_idr_and_end_markers() {
        let bytes = skeleton_annex_b();
        let expected = vec![
            0x00, 0x00, 0x00, 0x01, 0x00, 0x71, 0x80, // VPS
            0x00, 0x00, 0x00, 0x01, 0x00, 0x79, 0x80, // SPS
            0x00, 0x00, 0x00, 0x01, 0x00, 0x81, 0x80, // PPS
            0x00, 0x00, 0x00, 0x01, 0x00, 0x41, 0x80, // IDR_N_LP
            0x00, 0x00, 0x00, 0x01, 0x00, 0xa9, // EOS
            0x00, 0x00, 0x00, 0x01, 0x00, 0xb1, // EOB
        ];
        assert_eq!(bytes, expected);
    }

    #[test]
    fn rejects_invalid_layer_id() {
        let mut unit = VvcNalUnit::eos();
        unit.layer_id = 56;
        assert!(nal_unit_header_bytes(&unit).is_err());
    }

    #[test]
    fn parses_skeleton_annex_b_headers() {
        let infos = parse_annex_b_nal_units(&skeleton_annex_b()).unwrap();
        let types: Vec<u8> = infos.iter().map(|info| info.nal_unit_type).collect();
        assert_eq!(types, vec![14, 15, 16, 8, 21, 22]);
        assert_eq!(infos[0].payload_len, 1);
        assert_eq!(infos[4].payload_len, 0);
    }

    #[test]
    fn syntax_writer_records_named_fixed_width_fields() {
        let mut writer = VvcSyntaxWriter::new();
        writer.write_flag("ph_gdr_or_irap_pic_flag", true);
        writer.write_u("sps_seq_parameter_set_id", 3, 4);
        writer.rbsp_trailing_bits();
        let rbsp = writer.finish();

        assert_eq!(rbsp.bytes, vec![0b1001_1100]);
        assert_eq!(
            rbsp.fields,
            vec![
                VvcSyntaxField {
                    name: "ph_gdr_or_irap_pic_flag",
                    code: VvcSyntaxCode::Flag,
                    bit_offset: 0,
                    bit_count: 1,
                },
                VvcSyntaxField {
                    name: "sps_seq_parameter_set_id",
                    code: VvcSyntaxCode::U,
                    bit_offset: 1,
                    bit_count: 4,
                },
                VvcSyntaxField {
                    name: "rbsp_trailing_bits",
                    code: VvcSyntaxCode::RbspTrailingBits,
                    bit_offset: 5,
                    bit_count: 3,
                },
            ]
        );
    }

    #[test]
    fn syntax_writer_encodes_unsigned_exp_golomb() {
        let mut writer = VvcSyntaxWriter::new();
        writer.write_ue("sps_log2_ctu_size_minus5", 0);
        writer.write_ue("pps_num_subpics_minus1", 5);
        writer.rbsp_trailing_bits();
        let rbsp = writer.finish();

        assert_eq!(rbsp.bytes, vec![0b1001_1010]);
        assert_eq!(rbsp.fields[0].bit_count, 1);
        assert_eq!(rbsp.fields[1].bit_offset, 1);
        assert_eq!(rbsp.fields[1].bit_count, 5);
        assert_eq!(rbsp.fields[2].bit_offset, 6);
    }

    #[test]
    fn syntax_writer_encodes_signed_exp_golomb() {
        let mut writer = VvcSyntaxWriter::new();
        writer.write_se("slice_qp_delta", 0);
        writer.write_se("delta_luma_weight_l0", 1);
        writer.write_se("delta_chroma_offset_l0", -1);
        writer.rbsp_trailing_bits();
        let rbsp = writer.finish();

        assert_eq!(rbsp.bytes, vec![0b1010_0111]);
        assert_eq!(rbsp.fields[0].code, VvcSyntaxCode::Se);
        assert_eq!(rbsp.fields[0].bit_count, 1);
        assert_eq!(rbsp.fields[1].bit_count, 3);
        assert_eq!(rbsp.fields[2].bit_count, 3);
    }

    #[test]
    fn parses_toy_black_4x4_one_frame_headers() {
        let bytes = toy_black_4x4_yuv420p8_annex_b(Toy4x4EncodeParams { frames: 1 }).unwrap();
        assert_eq!(bytes.len(), 74);
        let infos = parse_annex_b_nal_units(&bytes).unwrap();
        let types: Vec<u8> = infos.iter().map(|info| info.nal_unit_type).collect();
        assert_eq!(types, vec![15, 16, 8]);
        assert_eq!(infos[0].payload_len, 31);
        assert_eq!(infos[1].payload_len, 14);
        assert_eq!(infos[2].payload_len, 11);
    }

    #[test]
    fn toy_parameter_sets_are_generated_from_named_syntax() {
        assert_eq!(
            toy_4x4_sps_payload(),
            hex_bytes("000b020080004244eed501f446e884688424613628c5430680ab8fe0ac1020")
        );
        assert_eq!(
            toy_4x4_pps_payload(),
            hex_bytes("0002448a4200c7b2145945945880")
        );
    }

    #[test]
    fn toy_slice_header_is_generated_before_cabac_packets() {
        assert_eq!(
            toy_4x4_slice_payload(Toy4x4PictureKind::Idr),
            hex_bytes("c400708062f5b7ebcb1f80")
        );
        assert_eq!(
            toy_4x4_slice_payload(Toy4x4PictureKind::Cra),
            hex_bytes("c404788062f5b7ebcb1f80")
        );
    }

    #[test]
    fn toy_coding_tree_entropy_is_packetized_from_events() {
        let events = toy_4x4_coding_tree_events(Toy4x4PictureKind::Idr);
        assert_eq!(events.len(), 8);
        assert_eq!(
            events[0],
            ToyCodingTreeEvent::LumaSplitAndCuPrefix {
                irap_prefix: 0b1000
            }
        );

        let packets: Vec<ToyCabacPacket> = events.iter().copied().map(toy_cabac_packet).collect();
        assert_eq!(packets[0].name, "cabac_luma_split_cu_prefix");
        assert_eq!(packets[0].bits, 0b1000);
        assert_eq!(packets[0].bit_count, 4);
        assert_eq!(packets[7].name, "cabac_alignment_zero_bits");
        assert_eq!(packets[7].bit_count, 5);

        let mut writer = VvcSyntaxWriter::new();
        write_toy_coding_tree_entropy(&mut writer, Toy4x4PictureKind::Idr);
        let rbsp = writer.finish();
        assert_eq!(rbsp.bytes, hex_bytes("840317adbf5e58fc00"));
        assert!(rbsp
            .fields
            .iter()
            .all(|field| field.code == VvcSyntaxCode::CabacPacket));
        assert_eq!(rbsp.fields.len(), 8);
    }

    #[test]
    fn parses_toy_black_4x4_two_frame_headers() {
        let bytes = toy_black_4x4_yuv420p8_annex_b(Toy4x4EncodeParams { frames: 2 }).unwrap();
        assert_eq!(bytes.len(), 91);
        let infos = parse_annex_b_nal_units(&bytes).unwrap();
        let types: Vec<u8> = infos.iter().map(|info| info.nal_unit_type).collect();
        assert_eq!(types, vec![15, 16, 8, 9]);
        assert_eq!(infos[3].offset, 78);
        assert_eq!(infos[3].payload_len, 11);
    }

    #[test]
    fn toy_4x4_input_path_accepts_black_yuv420p8_frames() {
        let input = vec![0; Picture::expected_len(4, 4, PixelFormat::Yuv420p8) * 2];
        let from_input =
            toy_4x4_yuv420p8_annex_b_from_input(&input, Toy4x4EncodeParams { frames: 2 }).unwrap();
        let generated = toy_black_4x4_yuv420p8_annex_b(Toy4x4EncodeParams { frames: 2 }).unwrap();
        assert_eq!(from_input, generated);
    }

    #[test]
    fn toy_4x4_input_path_samples_first_yuv_values() {
        let mut input = solid_yuv420p8(64, 128, 192, 2);
        input[3] = 255;
        input[17] = 0;
        input[21] = 1;
        let color =
            sample_toy_4x4_first_yuv420p8(&input, Toy4x4EncodeParams { frames: 2 }).unwrap();
        assert_eq!(
            color,
            Toy4x4SampledColor {
                y: 64,
                u: 128,
                v: 192,
            }
        );
    }

    #[test]
    fn toy_4x4_input_path_samples_only_first_frame() {
        let mut input = solid_yuv420p8(64, 128, 192, 2);
        let second_frame = Picture::expected_len(4, 4, PixelFormat::Yuv420p8);
        input[second_frame] = 1;
        input[second_frame + 16] = 2;
        input[second_frame + 20] = 3;
        let color =
            sample_toy_4x4_first_yuv420p8(&input, Toy4x4EncodeParams { frames: 2 }).unwrap();
        assert_eq!(
            color,
            Toy4x4SampledColor {
                y: 64,
                u: 128,
                v: 192,
            }
        );
    }

    #[test]
    fn toy_4x4_bitstream_path_rejects_non_black_solid_until_residuals_exist() {
        let input = solid_yuv420p8(64, 128, 192, 1);
        assert!(
            toy_4x4_yuv420p8_annex_b_from_input(&input, Toy4x4EncodeParams { frames: 1 }).is_err()
        );
    }

    #[test]
    fn rejects_unsupported_toy_frame_count() {
        assert!(toy_black_4x4_yuv420p8_annex_b(Toy4x4EncodeParams { frames: 0 }).is_err());
        assert!(toy_black_4x4_yuv420p8_annex_b(Toy4x4EncodeParams { frames: 3 }).is_err());
    }

    fn hex_bytes(hex: &str) -> Vec<u8> {
        assert_eq!(hex.len() % 2, 0);
        hex.as_bytes()
            .chunks_exact(2)
            .map(|digits| {
                let text = std::str::from_utf8(digits).unwrap();
                u8::from_str_radix(text, 16).unwrap()
            })
            .collect()
    }

    fn solid_yuv420p8(y: u8, u: u8, v: u8, frames: usize) -> Vec<u8> {
        let mut out =
            Vec::with_capacity(Picture::expected_len(4, 4, PixelFormat::Yuv420p8) * frames);
        for _ in 0..frames {
            out.extend(std::iter::repeat_n(y, 16));
            out.extend(std::iter::repeat_n(u, 4));
            out.extend(std::iter::repeat_n(v, 4));
        }
        out
    }
}
