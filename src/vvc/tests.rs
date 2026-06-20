use super::*;

fn vvc_test_slice_config() -> VvcSliceSyntaxConfig {
    VvcSliceSyntaxConfig::yuv420_residual()
}

fn vvc_named_field<'a>(rbsp: &'a VvcSyntaxRbsp, name: &str) -> Option<&'a VvcSyntaxField> {
    rbsp.fields.iter().find(|field| field.name == name)
}

fn vvc_field_present(rbsp: &VvcSyntaxRbsp, name: &str) -> bool {
    vvc_named_field(rbsp, name).is_some()
}

fn vvc_flag_value(rbsp: &VvcSyntaxRbsp, name: &str) -> Option<bool> {
    let field = vvc_named_field(rbsp, name)?;
    assert_eq!(field.code, VvcSyntaxCode::Flag, "{name} should be a flag");
    assert_eq!(field.bit_count, 1, "{name} should be one bit");
    let byte = rbsp.bytes[field.bit_offset / 8];
    let shift = 7 - (field.bit_offset % 8);
    Some(((byte >> shift) & 1) != 0)
}

fn vvc_field_bit(rbsp: &VvcSyntaxRbsp, bit_offset: usize) -> bool {
    let byte = rbsp.bytes[bit_offset / 8];
    let shift = 7 - (bit_offset % 8);
    ((byte >> shift) & 1) != 0
}

fn vvc_field_bits_value(rbsp: &VvcSyntaxRbsp, field: &VvcSyntaxField) -> u64 {
    let mut value = 0;
    for offset in field.bit_offset..field.bit_offset + field.bit_count {
        value = (value << 1) | u64::from(vvc_field_bit(rbsp, offset));
    }
    value
}

fn vvc_u_value(rbsp: &VvcSyntaxRbsp, name: &str) -> u64 {
    let field = vvc_named_field(rbsp, name).unwrap_or_else(|| panic!("missing {name}"));
    assert_eq!(field.code, VvcSyntaxCode::U, "{name} should be u(n)");
    vvc_field_bits_value(rbsp, field)
}

fn vvc_ue_value(rbsp: &VvcSyntaxRbsp, name: &str) -> u32 {
    let field = vvc_named_field(rbsp, name).unwrap_or_else(|| panic!("missing {name}"));
    assert_eq!(field.code, VvcSyntaxCode::Ue, "{name} should be ue(v)");
    let leading_zero_bits = (field.bit_count - 1) / 2;
    let code_bits = field.bit_count - leading_zero_bits;
    let mut code_num = 0;
    for offset in
        field.bit_offset + leading_zero_bits..field.bit_offset + leading_zero_bits + code_bits
    {
        code_num = (code_num << 1) | u32::from(vvc_field_bit(rbsp, offset));
    }
    code_num - 1
}

fn assert_vvc_flag(rbsp: &VvcSyntaxRbsp, name: &str, expected: bool) {
    assert_eq!(vvc_flag_value(rbsp, name), Some(expected), "{name}");
}

fn assert_vvc_field_absent(rbsp: &VvcSyntaxRbsp, name: &str) {
    assert!(!vvc_field_present(rbsp, name), "{name} should be gated off");
}

fn assert_vvc_parameter_sets_signal_geometry(geometry: VvcVideoGeometry) {
    let sps = vvc_sps_rbsp(geometry, vvc_test_slice_config());
    assert_eq!(
        vvc_ue_value(&sps, "sps_pic_width_max_in_luma_samples") as usize,
        geometry.coded_width()
    );
    assert_eq!(
        vvc_ue_value(&sps, "sps_pic_height_max_in_luma_samples") as usize,
        geometry.coded_height()
    );
    assert_eq!(
        vvc_ue_value(&sps, "sps_conf_win_right_offset"),
        geometry.crop_right(ChromaSampling::Cs420)
    );
    assert_eq!(
        vvc_ue_value(&sps, "sps_conf_win_bottom_offset"),
        geometry.crop_bottom(ChromaSampling::Cs420)
    );

    let pps = vvc_pps_rbsp(geometry);
    assert_eq!(
        vvc_ue_value(&pps, "pps_pic_width_in_luma_samples") as usize,
        geometry.coded_width()
    );
    assert_eq!(
        vvc_ue_value(&pps, "pps_pic_height_in_luma_samples") as usize,
        geometry.coded_height()
    );
}

fn assert_vvc_annex_b_has_min_picture_nals(bytes: &[u8], frames: usize) -> Vec<VvcNalInfo> {
    let infos = parse_annex_b_nal_units(bytes).unwrap();
    assert!(infos.len() >= 2 + frames);
    assert_eq!(infos[0].nal_unit_type, VvcNalUnitType::Sps as u8);
    assert_eq!(infos[1].nal_unit_type, VvcNalUnitType::Pps as u8);
    assert!(infos[0].payload_len > 0);
    assert!(infos[1].payload_len > 0);

    let picture_count = infos
        .iter()
        .filter(|info| {
            matches!(
                info.nal_unit_type,
                value if value == VvcNalUnitType::IdrNLp as u8
                    || value == VvcNalUnitType::IdrWRadl as u8
                    || value == VvcNalUnitType::Cra as u8
                    || value == VvcNalUnitType::Trail as u8
            )
        })
        .count();
    assert!(
        picture_count >= frames,
        "stream should contain at least one picture NAL per frame; got {picture_count} for {frames} frame(s)"
    );
    assert!(infos[2..].iter().all(|info| info.payload_len > 0));
    let last = infos.last().expect("stream has at least SPS/PPS");
    assert_eq!(
        last.offset + 2 + last.payload_len,
        bytes.len(),
        "stream should end at the last NAL payload boundary"
    );
    infos
}

fn count_vvc_picture_nals(infos: &[VvcNalInfo]) -> usize {
    infos
        .iter()
        .filter(|info| {
            matches!(
                info.nal_unit_type,
                value if value == VvcNalUnitType::IdrNLp as u8
                    || value == VvcNalUnitType::IdrWRadl as u8
                    || value == VvcNalUnitType::Cra as u8
                    || value == VvcNalUnitType::Trail as u8
            )
        })
        .count()
}

fn vvc_quantized_color(y: u8, luma_rem: u8) -> VvcQuantizedColor {
    VvcQuantizedColor {
        y,
        u: 0,
        v: 0,
        luma_tu_remainders: [luma_rem; MAX_VVC_LUMA_TUS],
        luma_tu_negative: [y < VVC_LUMA_DC_BASE as u8 && luma_rem != 0; MAX_VVC_LUMA_TUS],
        luma_tu_ac_levels: [[0; VVC_LUMA_AC_COEFFS_PER_TU]; MAX_VVC_LUMA_TUS],
        luma_tu_count: 1,
        chroma_tu_count: 0,
        cb_tu_dc_levels: [0; MAX_VVC_CHROMA_TUS],
        cr_tu_dc_levels: [0; MAX_VVC_CHROMA_TUS],
        cb_tu_ac_levels: [[0; VVC_CHROMA_AC_COEFFS_PER_TU]; MAX_VVC_CHROMA_TUS],
        cr_tu_ac_levels: [[0; VVC_CHROMA_AC_COEFFS_PER_TU]; MAX_VVC_CHROMA_TUS],
        cb_rem: 16,
        cr_rem: 16,
    }
}

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
fn rejects_invalid_layer_id() {
    let mut unit = VvcNalUnit::eos();
    unit.layer_id = 56;
    assert!(nal_unit_header_bytes(&unit).is_err());
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
fn parses_vvc_black_one_frame_headers() {
    let bytes = vvc_black_yuv420p8_annex_b(VvcEncodeParams { frames: 1 }).unwrap();
    assert_vvc_annex_b_has_min_picture_nals(&bytes, 1);
}

#[test]
fn vvc_parameter_sets_are_generated_from_named_syntax() {
    let geometry = VvcVideoGeometry::validation_minimum();
    let sps = vvc_sps_rbsp(geometry, vvc_test_slice_config());
    let pps = vvc_pps_rbsp(geometry);

    assert!(!sps.bytes.is_empty());
    assert!(!pps.bytes.is_empty());
    assert_eq!(vvc_u_value(&sps, "sps_chroma_format_idc"), 1);
    assert_eq!(vvc_u_value(&sps, "sps_log2_ctu_size_minus5"), 1);
    assert_vvc_parameter_sets_signal_geometry(geometry);
    assert_vvc_flag(&pps, "pps_no_pic_partition_flag", true);
    assert_vvc_flag(&pps, "pps_cabac_init_present_flag", false);
}

#[test]
fn vvc_multi_ctu_pps_signals_picture_header_placement_flags() {
    let single_ctu = vvc_pps_rbsp(VvcVideoGeometry {
        width: 64,
        height: 64,
    });
    assert_vvc_field_absent(&single_ctu, "pps_rpl_info_in_ph_flag");
    assert_vvc_field_absent(&single_ctu, "pps_sao_info_in_ph_flag");
    assert_vvc_field_absent(&single_ctu, "pps_alf_info_in_ph_flag");
    assert_vvc_field_absent(&single_ctu, "pps_qp_delta_info_in_ph_flag");

    let multi_ctu = vvc_pps_rbsp(VvcVideoGeometry {
        width: 128,
        height: 64,
    });
    assert_vvc_flag(&multi_ctu, "pps_no_pic_partition_flag", false);
    assert_vvc_flag(&multi_ctu, "pps_rpl_info_in_ph_flag", false);
    assert_vvc_flag(&multi_ctu, "pps_sao_info_in_ph_flag", false);
    assert_vvc_flag(&multi_ctu, "pps_alf_info_in_ph_flag", false);
    assert_vvc_flag(&multi_ctu, "pps_qp_delta_info_in_ph_flag", false);
}

#[test]
fn vvc_sps_can_signal_4x8_visible_geometry() {
    assert_vvc_parameter_sets_signal_geometry(VvcVideoGeometry {
        width: 4,
        height: 8,
    });
}

#[test]
fn vvc_sps_can_signal_8x4_visible_geometry() {
    assert_vvc_parameter_sets_signal_geometry(VvcVideoGeometry {
        width: 8,
        height: 4,
    });
}

#[test]
fn vvc_sps_can_signal_8x8_visible_geometry() {
    assert_vvc_parameter_sets_signal_geometry(VvcVideoGeometry {
        width: 8,
        height: 8,
    });
}

#[test]
fn vvc_parameter_sets_can_signal_16x16_visible_geometry() {
    assert_vvc_parameter_sets_signal_geometry(VvcVideoGeometry {
        width: 16,
        height: 16,
    });
}

#[test]
fn vvc_parameter_sets_can_signal_rectangular_16_sample_geometries() {
    let wide = VvcVideoGeometry {
        width: 16,
        height: 8,
    };
    let tall = VvcVideoGeometry {
        width: 8,
        height: 16,
    };
    assert_eq!(
        wide.coded(),
        VvcCodedGeometry {
            width: 16,
            height: 8
        }
    );
    assert_eq!(
        tall.coded(),
        VvcCodedGeometry {
            width: 8,
            height: 16
        }
    );
    assert_ne!(vvc_sps_payload(wide), vvc_sps_payload(tall));
    assert_ne!(
        vvc_sps_payload(wide),
        vvc_sps_payload(VvcVideoGeometry {
            width: 16,
            height: 16
        })
    );
}

#[test]
fn vvc_parameter_sets_can_signal_64x64_visible_geometry() {
    assert_vvc_parameter_sets_signal_geometry(VvcVideoGeometry {
        width: 64,
        height: 64,
    });
}

#[test]
fn vvc_sps_tool_flags_follow_the_active_slice_config() {
    let geometry = VvcVideoGeometry {
        width: 16,
        height: 16,
    };
    let rbsp = vvc_sps_rbsp(geometry, vvc_test_slice_config());

    assert_vvc_flag(&rbsp, "sps_ref_pic_resampling_enabled_flag", true);
    assert_vvc_flag(&rbsp, "sps_res_change_in_clvs_allowed_flag", false);
    assert_vvc_flag(&rbsp, "sps_entry_point_offsets_present_flag", true);
    assert_vvc_flag(&rbsp, "sps_transform_skip_enabled_flag", false);
    assert_vvc_field_absent(&rbsp, "sps_log2_transform_skip_max_size_minus2");
    assert_vvc_field_absent(&rbsp, "sps_bdpcm_enabled_flag");
    assert_vvc_flag(&rbsp, "sps_mts_enabled_flag", false);
    assert_vvc_field_absent(&rbsp, "sps_explicit_mts_intra_enabled_flag");
    assert_vvc_field_absent(&rbsp, "sps_explicit_mts_inter_enabled_flag");
    assert_vvc_flag(&rbsp, "sps_lfnst_enabled_flag", false);
    assert_vvc_flag(&rbsp, "sps_mrl_enabled_flag", true);
    assert_vvc_flag(&rbsp, "sps_cclm_enabled_flag", true);
    assert_vvc_flag(&rbsp, "sps_palette_enabled_flag", false);
    assert_vvc_flag(&rbsp, "sps_dep_quant_enabled_flag", false);
    assert_vvc_flag(&rbsp, "sps_sign_data_hiding_enabled_flag", false);

    assert_vvc_flag(&rbsp, "sps_temporal_mvp_enabled_flag", false);
    assert_vvc_field_absent(&rbsp, "sps_sbtmvp_enabled_flag");
    assert_vvc_flag(&rbsp, "sps_mmvd_enabled_flag", false);
    assert_vvc_field_absent(&rbsp, "sps_mmvd_fullpel_only_flag");
    assert_vvc_flag(&rbsp, "sps_affine_enabled_flag", false);
    assert_vvc_field_absent(&rbsp, "sps_five_minus_max_num_subblock_merge_cand");
    assert_vvc_field_absent(&rbsp, "sps_affine_type_flag");
    assert_vvc_field_absent(&rbsp, "sps_affine_prof_enabled_flag");
}

#[test]
fn vvc_sps_tool_flags_can_enable_gated_tools_from_one_config() {
    let geometry = VvcVideoGeometry {
        width: 16,
        height: 16,
    };
    let mut config = vvc_test_slice_config();
    config.tools.transform_skip_enabled = true;
    config.tools.explicit_mts_intra_enabled = true;
    config.tools.lfnst_enabled = true;
    config.tools.dependent_quantization_enabled = true;
    config.tools.sign_data_hiding_enabled = true;

    let rbsp = vvc_sps_rbsp(geometry, config);
    assert_vvc_flag(&rbsp, "sps_transform_skip_enabled_flag", true);
    assert_eq!(
        vvc_ue_value(&rbsp, "sps_log2_transform_skip_max_size_minus2"),
        1
    );
    assert_vvc_flag(&rbsp, "sps_bdpcm_enabled_flag", false);
    assert_vvc_flag(&rbsp, "sps_mts_enabled_flag", true);
    assert_vvc_flag(&rbsp, "sps_explicit_mts_intra_enabled_flag", true);
    assert_vvc_flag(&rbsp, "sps_explicit_mts_inter_enabled_flag", false);
    assert_vvc_flag(&rbsp, "sps_lfnst_enabled_flag", true);
    assert_vvc_flag(&rbsp, "sps_dep_quant_enabled_flag", true);
    assert_vvc_flag(&rbsp, "sps_sign_data_hiding_enabled_flag", true);

    let palette = VvcSliceSyntaxConfig::palette_444();
    let palette_rbsp = vvc_sps_rbsp(geometry, palette);
    assert_vvc_flag(&rbsp, "sps_qtbtt_dual_tree_intra_flag", true);
    assert_vvc_flag(&palette_rbsp, "sps_qtbtt_dual_tree_intra_flag", false);
    assert_eq!(vvc_u_value(&palette_rbsp, "sps_chroma_format_idc"), 3);
    assert_vvc_flag(&palette_rbsp, "sps_bdpcm_enabled_flag", true);
    assert_vvc_flag(&palette_rbsp, "sps_palette_enabled_flag", true);
    assert_eq!(
        vvc_ue_value(
            &palette_rbsp,
            "sps_internal_bit_depth_minus_input_bit_depth"
        ),
        0
    );
    assert_vvc_flag(&palette_rbsp, "sps_mrl_enabled_flag", false);
    assert_vvc_flag(&palette_rbsp, "sps_cclm_enabled_flag", false);
}

#[test]
fn vvc_slice_header_tool_flags_follow_the_active_slice_config() {
    let black = quantize_vvc_color(VvcSampledColor { y: 0, u: 0, v: 0 });
    let rbsp = vvc_slice_rbsp(
        VvcPictureKind::Idr,
        VvcVideoGeometry {
            width: 16,
            height: 16,
        },
        black,
        vvc_test_slice_config(),
    );

    assert_vvc_field_absent(&rbsp, "sh_dep_quant_used_flag");
    assert_vvc_field_absent(&rbsp, "sh_sign_data_hiding_used_flag");
}

#[test]
fn vvc_cabac_tool_flags_are_read_from_the_active_slice_config() {
    let black = quantize_vvc_color(VvcSampledColor { y: 0, u: 0, v: 0 });
    let geometry = VvcVideoGeometry {
        width: 16,
        height: 16,
    };
    let enabled = vvc_test_slice_config();
    let mut disabled_mrl = enabled;
    disabled_mrl.tools.mrl_enabled = false;

    assert_vvc_flag(
        &vvc_sps_rbsp(geometry, disabled_mrl),
        "sps_mrl_enabled_flag",
        false,
    );
    assert_ne!(
        vvc_cabac_bits(geometry, black, enabled),
        vvc_cabac_bits(geometry, black, disabled_mrl),
        "CABAC must consume the same slice tool flags that are written in SPS"
    );
}

#[test]
fn vvc_slice_header_is_generated_before_cabac_tokens() {
    let black = quantize_vvc_color(VvcSampledColor { y: 0, u: 0, v: 0 });
    let geometry = VvcVideoGeometry::validation_minimum();
    let idr = vvc_slice_rbsp(
        VvcPictureKind::Idr,
        geometry,
        black,
        vvc_test_slice_config(),
    );
    let cra = vvc_slice_rbsp(
        VvcPictureKind::Cra,
        geometry,
        black,
        vvc_test_slice_config(),
    );

    assert_eq!(idr.fields[0].name, "sh_picture_header_in_slice_header_flag");
    assert_eq!(cra.fields[0].name, "sh_picture_header_in_slice_header_flag");
    assert!(
        idr.fields
            .iter()
            .position(|field| field.code == VvcSyntaxCode::CabacToken)
            .unwrap()
            > 0
    );
    assert!(
        cra.fields
            .iter()
            .position(|field| field.code == VvcSyntaxCode::CabacToken)
            .unwrap()
            > 0
    );
    assert!(!idr.bytes.is_empty());
    assert!(!cra.bytes.is_empty());
}

#[test]
fn vvc_arithmetic_writer_generates_verified_luma_payloads() {
    let mut payloads = Vec::new();
    for luma_rem in 0..=16 {
        let color = vvc_quantized_color(0, luma_rem as u8);
        let payload = vvc_slice_payload(
            VvcPictureKind::Idr,
            VvcVideoGeometry::validation_minimum(),
            color,
            vvc_test_slice_config(),
        );
        assert!(!payload.is_empty());
        payloads.push(payload);
    }
    assert!(payloads.windows(2).all(|pair| pair[0] != pair[1]));
}

#[test]
fn vvc_coding_tree_entropy_is_generated_from_ctu_syntax() {
    let black = quantize_vvc_color(VvcSampledColor { y: 0, u: 0, v: 0 });
    let geometry = VvcVideoGeometry::validation_minimum();
    let mut writer = VvcSyntaxWriter::new();
    write_vvc_coding_tree_entropy(&mut writer, geometry, black, vvc_test_slice_config());
    let rbsp = writer.finish();
    assert!(!rbsp.bytes.is_empty());
    assert!(rbsp
        .fields
        .iter()
        .all(|field| field.code == VvcSyntaxCode::CabacToken));
    assert_eq!(rbsp.fields.len(), 1);
    assert!(rbsp.fields[0].bit_count > 0);
}

#[test]
fn vvc_cabac_bits_generate_ctu_bodies_for_small_and_edge_geometries() {
    let black = quantize_vvc_color(VvcSampledColor { y: 0, u: 0, v: 0 });
    for geometry in [
        VvcVideoGeometry {
            width: 16,
            height: 16,
        },
        VvcVideoGeometry {
            width: 16,
            height: 64,
        },
        VvcVideoGeometry {
            width: 64,
            height: 16,
        },
    ] {
        assert!(
            !vvc_cabac_bits(geometry, black, vvc_test_slice_config()).is_empty(),
            "{}x{} should be generated from the CTU path",
            geometry.width,
            geometry.height
        );
    }
    assert!(!vvc_cabac_bits(
        VvcVideoGeometry {
            width: 32,
            height: 32
        },
        black,
        vvc_test_slice_config()
    )
    .is_empty());
    assert!(!vvc_cabac_bits(
        VvcVideoGeometry {
            width: 64,
            height: 64
        },
        black,
        vvc_test_slice_config()
    )
    .is_empty());
    assert!(!vvc_cabac_bits(
        VvcVideoGeometry {
            width: 8,
            height: 8
        },
        black,
        vvc_test_slice_config()
    )
    .is_empty());
}

#[test]
fn vvc_coded_geometry_does_not_square_promote_even_visible_shapes_at_or_under_32() {
    assert_eq!(VVC_CODED_DIMENSION_GRANULARITY, 8);
    for height in (2..=32).step_by(2) {
        for width in (2..=32).step_by(2) {
            let geometry = VvcVideoGeometry { width, height };
            geometry
                .validate_against(VvcVideoLimits::max_64x64())
                .expect("valid even small geometry");
            let coded = geometry.coded();
            assert_eq!(coded.width, coded_canvas_dimension(width));
            assert_eq!(coded.height, coded_canvas_dimension(height));
        }
    }

    assert_eq!(
        (VvcVideoGeometry {
            width: 64,
            height: 24,
        })
        .coded(),
        VvcCodedGeometry {
            width: 64,
            height: 24,
        }
    );
    assert_eq!(
        (VvcVideoGeometry {
            width: 10,
            height: 18,
        })
        .coded(),
        VvcCodedGeometry {
            width: 16,
            height: 24,
        }
    );
}

#[test]
fn vvc_ctu_partition_params_are_geometry_derived() {
    let black = quantize_vvc_color(VvcSampledColor { y: 0, u: 0, v: 0 });
    for (width, height, luma_tu_count) in [
        (64, 64, 64),
        (64, 32, 32),
        (32, 64, 32),
        (32, 32, 16),
        (16, 16, 4),
    ] {
        let params = vvc_ctu_partition_params(VvcVideoGeometry { width, height }, black)
            .expect("partition parameters");
        assert_eq!(params.root_width, 64);
        assert_eq!(params.root_height, 64);
        assert_eq!(params.visible_width, width);
        assert_eq!(params.visible_height, height);
        assert_eq!(params.chroma_sampling, ChromaSampling::Cs420);
        assert_eq!(
            params.chroma_tu_count,
            vvc_chroma_420_transform_nodes(params.shape()).len()
        );
        assert_eq!(params.luma_tu_count, luma_tu_count);
        assert_eq!(params.luma_tu_abs_levels[0], black.luma_tu_remainders[0]);
        assert_eq!(
            params.luma_tu_abs_levels[luma_tu_count - 1],
            black.luma_tu_remainders[0]
        );
        assert_eq!(params.luma_tu_negative[0], black.luma_tu_negative[0]);
        assert!(params.luma_tu_negative[0]);
        assert_eq!(params.luma_tu_ac_levels[0], [0; VVC_LUMA_AC_COEFFS_PER_TU]);
        assert_eq!(params.cb_dc_abs_level, 16);
        assert!(params.cb_dc_negative);
    }
}

#[test]
fn vvc_ctu_partition_params_cover_all_8_sample_geometries_up_to_64() {
    let black = quantize_vvc_color(VvcSampledColor { y: 0, u: 0, v: 0 });
    for width in (8..=64).step_by(8) {
        for height in (8..=64).step_by(8) {
            let geometry = VvcVideoGeometry { width, height };
            let params = vvc_ctu_partition_params(geometry, black)
                .unwrap_or_else(|| panic!("missing CTU params for {width}x{height}"));
            assert_eq!(params.root_width, 64);
            assert_eq!(params.root_height, 64);
            assert_eq!(params.visible_width, width);
            assert_eq!(params.visible_height, height);
            assert_eq!(
                params.chroma_tu_count,
                vvc_chroma_420_transform_nodes(params.shape()).len()
            );
            assert_eq!(
                vvc_cabac_bits(geometry, black, vvc_test_slice_config()),
                vvc_ctu_partition_cabac_bits(params, vvc_test_slice_config())
            );
        }
    }
}

#[test]
fn vvc_contexts_derive_split_probability_from_init_tables() {
    let mut ctx = VvcCabacContexts::new();
    let split0 = &ctx.split_flag[0];
    assert!(!split0.mps());
    assert_eq!(split0.lps(510), 146);
    let initial_state = split0.state();

    let mut cabac = VvcCabacEncoder::new();
    cabac.start();
    ctx.encode(&mut cabac, VvcCabacContext::SplitFlag(0), true);
    assert!(ctx.split_flag[0].state() > initial_state);
}

#[test]
fn vvc_contexts_include_residual_init_tables() {
    assert_eq!(VvcCabacContext::TransformSkipFlag(0).init_value(), 25);
    assert_eq!(VvcCabacContext::TransformSkipFlag(0).log2_window_size(), 1);
    assert_eq!(VvcCabacContext::BdpcmMode(0).init_value(), 19);
    assert_eq!(VvcCabacContext::BdpcmMode(1).init_value(), 35);
    assert_eq!(VvcCabacContext::BdpcmMode(2).init_value(), 1);
    assert_eq!(VvcCabacContext::BdpcmMode(3).log2_window_size(), 0);
    assert_eq!(VvcCabacContext::MtsIdx(2).init_value(), 28);
    assert_eq!(VvcCabacContext::MtsIdx(2).log2_window_size(), 9);
    assert_eq!(VvcCabacContext::LastSigCoeffXPrefix(20).init_value(), 12);
    assert_eq!(
        VvcCabacContext::LastSigCoeffYPrefix(20).log2_window_size(),
        6
    );
    assert_eq!(VvcCabacContext::SbCodedFlag(6).init_value(), 38);
    assert_eq!(VvcCabacContext::SigCoeffFlag(62).init_value(), 38);
    assert_eq!(VvcCabacContext::ParLevelFlag(32).init_value(), 11);
    assert_eq!(VvcCabacContext::AbsLevelGtxFlag(31).init_value(), 46);
    assert_eq!(VvcCabacContext::AbsLevelGtxFlag(71).init_value(), 3);
    assert_eq!(VvcCabacContext::AbsLevelGtxFlag(71).log2_window_size(), 1);
    assert_eq!(VvcCabacContext::CoeffSignFlag(5).log2_window_size(), 8);

    let mut ctx = VvcCabacContexts::new();
    let initial_state = ctx.transform_skip_flag[0].state();
    let mut cabac = VvcCabacEncoder::new();
    cabac.start();
    ctx.encode(&mut cabac, VvcCabacContext::TransformSkipFlag(0), false);
    assert_ne!(ctx.transform_skip_flag[0].state(), initial_state);
}

#[test]
fn vvc_residual_contexts_have_rtl_ids_for_full_table_132_ranges() {
    let mut ids = std::collections::BTreeSet::new();

    for ctx in 0..=22 {
        let id = VvcCabacContext::LastSigCoeffXPrefix(ctx).rtl_context_id();
        assert!(id.is_some(), "missing last_sig_coeff_x_prefix({ctx})");
        assert!(ids.insert(id.unwrap()));

        let id = VvcCabacContext::LastSigCoeffYPrefix(ctx).rtl_context_id();
        assert!(id.is_some(), "missing last_sig_coeff_y_prefix({ctx})");
        assert!(ids.insert(id.unwrap()));
    }
    for ctx in 0..=6 {
        let id = VvcCabacContext::SbCodedFlag(ctx).rtl_context_id();
        assert!(id.is_some(), "missing sb_coded_flag({ctx})");
        assert!(ids.insert(id.unwrap()));
    }
    for ctx in 0..=62 {
        let id = VvcCabacContext::SigCoeffFlag(ctx).rtl_context_id();
        assert!(id.is_some(), "missing sig_coeff_flag({ctx})");
        assert!(ids.insert(id.unwrap()));
    }
    for ctx in 0..=32 {
        let id = VvcCabacContext::ParLevelFlag(ctx).rtl_context_id();
        assert!(id.is_some(), "missing par_level_flag({ctx})");
        assert!(ids.insert(id.unwrap()));
    }
    for ctx in 0..=71 {
        let id = VvcCabacContext::AbsLevelGtxFlag(ctx).rtl_context_id();
        assert!(id.is_some(), "missing abs_level_gtx_flag({ctx})");
        assert!(ids.insert(id.unwrap()));
    }

    assert_eq!(ids.len(), 221);
    assert_eq!(ids.last().copied(), Some(264));
}

#[test]
fn vvc_last_sig_chroma_prefix_ctx_uses_block_size_shift() {
    // H.266 9.3.4.2.4 defines chroma ctxShift as Clip3(0, 2,
    // (1 << Log2FullTbSize) >> 3). VTM CoeffCodingContext implements the same
    // rule as Clip3(0, 2, width >> 3), so 8x8 chroma bins 2 and 3 fold into
    // context 21 instead of walking past the 0..22 context table.
    assert_eq!(
        VvcLastSigCoeffPrefixCtxInput {
            is_luma: false,
            log2_tb_size: 2,
            bin_idx: 2,
        }
        .ctx_inc(),
        22
    );
    assert_eq!(
        VvcLastSigCoeffPrefixCtxInput {
            is_luma: false,
            log2_tb_size: 3,
            bin_idx: 3,
        }
        .ctx_inc(),
        21
    );
    assert_eq!(
        VvcLastSigCoeffPrefixCtxInput {
            is_luma: false,
            log2_tb_size: 4,
            bin_idx: 6,
        }
        .ctx_inc(),
        21
    );
}

#[test]
fn vvc_residual_cabac_encoder_labels_disabled_tool_paths() {
    let mut contexts = VvcCabacContexts::new();
    let mut cabac = VvcCabacEncoder::new();
    cabac.start();

    let mut disabled =
        VvcResidualCabacEncoder::new(&mut contexts, vvc_test_slice_config().residual_options());
    let state = VvcResidualPass1State::new(VvcResidualCtxConfig::luma_4x4_subset(0, 0));
    disabled.emit_default_tool_control_hooks(&mut cabac, &state);
    assert!(cabac.bits.is_empty());

    let mut contexts = VvcCabacContexts::new();
    let mut cabac = VvcCabacEncoder::new();
    cabac.start();
    let mut enabled_options = vvc_test_slice_config().residual_options();
    enabled_options.transform_skip_enabled = true;
    enabled_options.explicit_mts_intra_enabled = true;
    let initial_transform_skip_state = contexts.transform_skip_flag[0].state();
    let initial_mts_state = contexts.mts_idx[0].state();
    let mut enabled = VvcResidualCabacEncoder::new(&mut contexts, enabled_options);
    let state = VvcResidualPass1State::new(VvcResidualCtxConfig::luma_4x4_subset(0, 0));
    enabled.emit_default_tool_control_hooks(&mut cabac, &state);
    assert_ne!(
        contexts.transform_skip_flag[0].state(),
        initial_transform_skip_state
    );
    assert_ne!(contexts.mts_idx[0].state(), initial_mts_state);
}

#[test]
fn vvc_residual_cabac_encoder_emits_named_4x4_coefficient_bins() {
    let mut contexts = VvcCabacContexts::new();
    let initial_last_x0 = contexts.last_sig_coeff_x_prefix[0].state();
    let initial_last_y0 = contexts.last_sig_coeff_y_prefix[0].state();
    let initial_sig8 = contexts.sig_coeff_flag[8].state();
    let initial_par0 = contexts.par_level_flag[0].state();
    let initial_abs32 = contexts.abs_level_gtx_flag[32].state();
    let mut cabac = VvcCabacEncoder::new();
    cabac.start();
    let state = VvcResidualPass1State::new(VvcResidualCtxConfig::luma_4x4_subset(3, 3));
    let mut residual =
        VvcResidualCabacEncoder::new(&mut contexts, vvc_test_slice_config().residual_options());

    residual.emit_last_sig_coeff_prefixes_4x4(&mut cabac, VvcResidualComponent::Luma, 3, 0);
    residual.emit_sb_coded_flag(&mut cabac, &state, 0, 0, true);
    residual.emit_sig_coeff_flag(&mut cabac, &state, 0, 0, true);
    residual.emit_par_level_flag(&mut cabac, &state, 3, 3, false);
    residual.emit_abs_level_gtx_flag(&mut cabac, &state, 3, 3, 1, false);
    cabac.encode_bin_ep(true);

    assert_ne!(contexts.last_sig_coeff_x_prefix[3].state(), initial_last_x0);
    assert_ne!(contexts.last_sig_coeff_y_prefix[0].state(), initial_last_y0);
    assert_ne!(contexts.sig_coeff_flag[8].state(), initial_sig8);
    assert_ne!(contexts.par_level_flag[0].state(), initial_par0);
    assert_ne!(contexts.abs_level_gtx_flag[32].state(), initial_abs32);
}

#[test]
fn vvc_ctu_body_routes_ac_coefficients_without_a_feature_gate() {
    let neutral = quantize_vvc_color(VvcSampledColor {
        y: 128,
        u: 128,
        v: 128,
    });
    let mut params = vvc_ctu_partition_params(
        VvcVideoGeometry {
            width: 16,
            height: 16,
        },
        neutral,
    )
    .expect("16x16 partition parameters");
    assert_eq!(params.luma_tu_abs_levels[0], 0);

    let without_ac = vvc_ctu_partition_cabac_bits(params, vvc_test_slice_config());
    params.luma_tu_ac_levels[0][0] = 1;
    let with_ac = vvc_ctu_partition_cabac_bits(params, vvc_test_slice_config());

    assert_ne!(with_ac, without_ac);
}

#[test]
fn vvc_split_cu_flag_context_uses_spec_ctx_set_formula() {
    assert_eq!(
        VvcSplitCtxInput::qt_split_without_neighbours().split_cu_flag_ctx(),
        0
    );
    assert_eq!(
        VvcSplitCtxInput::full_child_without_smaller_neighbours().split_cu_flag_ctx(),
        6
    );
    assert_eq!(
        VvcSplitCtxInput::full_child_with_deeper_neighbours(true, true).split_cu_flag_ctx(),
        8
    );
}

#[test]
fn vvc_mtt_binary_flag_context_uses_table_132_formula() {
    // ITU-T H.266 (V4) clause 9.3.4.2.1, Table 132:
    // ctxInc = (2 * mtt_split_cu_vertical_flag) + (mttDepth <= 1 ? 1 : 0).
    assert_eq!(VvcCtuCabacOp::mtt_binary_ctx(false, 0), 1);
    assert_eq!(VvcCtuCabacOp::mtt_binary_ctx(false, 2), 0);
    assert_eq!(VvcCtuCabacOp::mtt_binary_ctx(true, 1), 3);
    assert_eq!(VvcCtuCabacOp::mtt_binary_ctx(true, 2), 2);

    assert_eq!(VvcCabacContext::MttSplitCuBinaryFlag(0).init_value(), 36);
    assert_eq!(VvcCabacContext::MttSplitCuBinaryFlag(1).init_value(), 45);
    assert_eq!(VvcCabacContext::MttSplitCuBinaryFlag(2).init_value(), 36);
    assert_eq!(VvcCabacContext::MttSplitCuBinaryFlag(3).init_value(), 45);
}

#[test]
fn vvc_split_qt_flag_context_uses_spec_depth_formula() {
    let root = VvcCodingTreeNode::root(64, 64, VvcTreeType::DualTreeLuma);
    assert_eq!(
        VvcQtSplitCtxInput::from_node_without_deeper_neighbours(root).split_qt_flag_ctx(),
        0
    );
    let child = root.qt_child(3).qt_child(3);
    assert_eq!(
        VvcQtSplitCtxInput::from_node_with_deeper_neighbours(child, true, true).split_qt_flag_ctx(),
        5
    );
}

#[test]
fn vvc_last_sig_prefix_context_uses_spec_geometry_formula() {
    assert_eq!(
        VvcLastSigCoeffPrefixCtxInput {
            is_luma: true,
            log2_tb_size: 2,
            bin_idx: 0,
        }
        .ctx_inc(),
        0
    );
    assert_eq!(
        VvcLastSigCoeffPrefixCtxInput {
            is_luma: true,
            log2_tb_size: 4,
            bin_idx: 3,
        }
        .ctx_inc(),
        7
    );
    assert_eq!(
        VvcLastSigCoeffPrefixCtxInput {
            is_luma: false,
            log2_tb_size: 3,
            bin_idx: 2,
        }
        .ctx_inc(),
        21
    );
}

#[test]
fn vvc_ctu_cabac_generator_uses_one_recursive_luma_base() {
    for (visible_width, visible_height) in [(16, 16), (32, 16), (16, 32), (32, 32), (64, 64)] {
        let params = VvcCtuPartitionParams {
            root_width: 64,
            root_height: 64,
            visible_width,
            visible_height,
            chroma_sampling: ChromaSampling::Cs420,
            chroma_tu_count: (visible_width * visible_height) / 16,
            luma_tu_count: 0,
            luma_tu_abs_levels: [0; MAX_VVC_LUMA_TUS],
            luma_tu_negative: [false; MAX_VVC_LUMA_TUS],
            luma_tu_ac_levels: [[0; VVC_LUMA_AC_COEFFS_PER_TU]; MAX_VVC_LUMA_TUS],
            cb_dc_abs_level: 0,
            cb_dc_negative: false,
            cb_tu_dc_levels: [0; MAX_VVC_CHROMA_TUS],
            cr_tu_dc_levels: [0; MAX_VVC_CHROMA_TUS],
            cb_tu_ac_levels: [[0; VVC_CHROMA_AC_COEFFS_PER_TU]; MAX_VVC_CHROMA_TUS],
            cr_tu_ac_levels: [[0; VVC_CHROMA_AC_COEFFS_PER_TU]; MAX_VVC_CHROMA_TUS],
        };
        let ops = VvcCtuCabacOp::yuv420_ctu_partition(params);
        let chroma_nodes: Vec<_> = ops
            .iter()
            .filter_map(|op| match op {
                VvcCtuCabacOp::ChromaTree {
                    node,
                    visible_width,
                    visible_height,
                } => {
                    assert_eq!(*visible_width, params.visible_chroma_width());
                    assert_eq!(*visible_height, params.visible_chroma_height());
                    Some(*node)
                }
                _ => None,
            })
            .collect();
        assert_eq!(chroma_nodes, vec![params.ctu_chroma_root()]);
        assert!(ops
            .iter()
            .any(|op| matches!(op, VvcCtuCabacOp::LumaLeafWithSplitCtx { .. })));
    }
}

#[test]
fn vvc_ctu_cabac_generator_is_embedded_in_ctu_body() {
    let black = quantize_vvc_color(VvcSampledColor { y: 0, u: 0, v: 0 });
    let params = vvc_ctu_partition_params(
        VvcVideoGeometry {
            width: 64,
            height: 64,
        },
        black,
    )
    .expect("64x64 partition parameters");
    let via_body = vvc_ctu_partition_cabac_bits(params, vvc_test_slice_config());

    let mut manual = VvcCabacEncoder::new();
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
        vvc_test_slice_config(),
    );
    manual.start();
    for op in VvcCtuCabacOp::yuv420_ctu_partition(params) {
        ctu.emit(&mut manual, op);
    }
    manual.encode_bin_trm(true);
    assert_eq!(via_body, manual.finish());
}

#[test]
fn vvc_boundary_partition_uses_qt_until_implicit_bt_is_allowed_for_thin_shapes() {
    let black = quantize_vvc_color(VvcSampledColor { y: 0, u: 0, v: 0 });
    for geometry in [
        VvcVideoGeometry {
            width: 64,
            height: 32,
        },
        VvcVideoGeometry {
            width: 32,
            height: 64,
        },
        VvcVideoGeometry {
            width: 64,
            height: 16,
        },
        VvcVideoGeometry {
            width: 16,
            height: 64,
        },
        VvcVideoGeometry {
            width: 64,
            height: 8,
        },
        VvcVideoGeometry {
            width: 8,
            height: 64,
        },
    ] {
        let params = vvc_ctu_partition_params(geometry, black).expect("thin rectangular params");
        let ops = VvcCtuCabacOp::yuv420_ctu_partition(params);
        assert!(
            !ops.iter().any(|op| matches!(
                op,
                VvcCtuCabacOp::BtSplit {
                    node,
                    write_split_flag: false,
                    ..
                } if node.x == 0 && node.y == 0 && node.width == 64 && node.height == 64
            )),
            "{geometry:?} must not force an implicit root BT before max-BT-size permits it"
        );
        assert!(
            !ops.iter().any(|op| matches!(
                op,
                VvcCtuCabacOp::BtSplit {
                    node,
                    write_qt_flag: true,
                    ..
                } if node.mtt_depth > 0
            )),
            "{geometry:?} must not signal split_qt_flag below a BT split"
        );
    }
}

#[test]
fn vvc_ctu_chroma_tree_uses_luma_coordinate_root() {
    for (chroma_sampling, expected_root, expected_visible) in [
        (ChromaSampling::Cs420, (64, 64), (64, 64)),
        (ChromaSampling::Cs422, (64, 64), (64, 64)),
        (ChromaSampling::Cs444, (64, 64), (64, 64)),
    ] {
        let params = VvcCtuPartitionParams {
            root_width: 64,
            root_height: 64,
            visible_width: 64,
            visible_height: 64,
            chroma_sampling,
            chroma_tu_count: 0,
            luma_tu_count: 0,
            luma_tu_abs_levels: [0; MAX_VVC_LUMA_TUS],
            luma_tu_negative: [false; MAX_VVC_LUMA_TUS],
            luma_tu_ac_levels: [[0; VVC_LUMA_AC_COEFFS_PER_TU]; MAX_VVC_LUMA_TUS],
            cb_dc_abs_level: 0,
            cb_dc_negative: false,
            cb_tu_dc_levels: [0; MAX_VVC_CHROMA_TUS],
            cr_tu_dc_levels: [0; MAX_VVC_CHROMA_TUS],
            cb_tu_ac_levels: [[0; VVC_CHROMA_AC_COEFFS_PER_TU]; MAX_VVC_CHROMA_TUS],
            cr_tu_ac_levels: [[0; VVC_CHROMA_AC_COEFFS_PER_TU]; MAX_VVC_CHROMA_TUS],
        };
        let root = params.ctu_chroma_root();
        assert_eq!((root.width, root.height), expected_root);
        assert_eq!(
            (
                params.visible_chroma_width(),
                params.visible_chroma_height()
            ),
            expected_visible
        );
        assert_eq!(root.tree_type, VvcTreeType::DualTreeChroma);
    }
}

#[test]
fn vvc_ctu_cabac_generator_handles_rectangular_64_sample_bodies() {
    let black = quantize_vvc_color(VvcSampledColor { y: 0, u: 0, v: 0 });
    for geometry in [
        VvcVideoGeometry {
            width: 64,
            height: 32,
        },
        VvcVideoGeometry {
            width: 32,
            height: 64,
        },
    ] {
        let params = vvc_ctu_partition_params(geometry, black).expect("rectangular params");
        let bits = vvc_ctu_partition_cabac_bits(params, vvc_test_slice_config());
        assert!(!bits.is_empty());
    }
}

#[test]
fn vvc_cabac_bits_uses_ctu_partition_generator_for_rectangular_bodies() {
    let black = quantize_vvc_color(VvcSampledColor { y: 0, u: 0, v: 0 });
    for geometry in [
        VvcVideoGeometry {
            width: 64,
            height: 32,
        },
        VvcVideoGeometry {
            width: 32,
            height: 64,
        },
    ] {
        let params = vvc_ctu_partition_params(geometry, black).expect("rectangular params");
        assert_eq!(
            vvc_cabac_bits(geometry, black, vvc_test_slice_config()),
            vvc_ctu_partition_cabac_bits(params, vvc_test_slice_config())
        );
    }
}

#[test]
fn vvc_luma_partition_plan_splits_to_8x8_leaves() {
    let plan = vvc_luma_partition_plan(VvcVideoGeometry {
        width: 64,
        height: 64,
    });
    let leaf_count = plan
        .iter()
        .filter(|step| matches!(step, VvcLumaPartitionStep::Leaf { .. }))
        .count();
    assert_eq!(leaf_count, 64);
    assert!(plan.iter().all(|step| match step {
        VvcLumaPartitionStep::Leaf { width, height, .. } => *width <= 8 && *height <= 8,
        VvcLumaPartitionStep::QuadSplit { .. } => true,
    }));
    assert!(plan.contains(&VvcLumaPartitionStep::Leaf {
        x: 56,
        y: 56,
        width: 8,
        height: 8,
    }));

    assert_eq!(
        vvc_luma_partition_plan(VvcVideoGeometry {
            width: 8,
            height: 8
        }),
        vec![VvcLumaPartitionStep::Leaf {
            x: 0,
            y: 0,
            width: 8,
            height: 8
        }]
    );
}

#[test]
fn vvc_coding_tree_plan_scales_chroma_blocks_with_geometry() {
    let mapped_8x8 = vvc_coding_tree_plan(VvcVideoGeometry {
        width: 8,
        height: 8,
    });
    assert_eq!(
        mapped_8x8,
        vec![
            VvcCodingTreeStep::LumaTransformUnit {
                width: 8,
                height: 8
            },
            VvcCodingTreeStep::ChromaTransformUnit {
                x: 0,
                y: 0,
                cb_coded: true,
                cr_coded: true
            }
        ]
    );

    let capacity_16x16 = vvc_coding_tree_plan(VvcVideoGeometry {
        width: 16,
        height: 16,
    });
    assert_eq!(capacity_16x16.len(), 5);
    assert_eq!(
        capacity_16x16[0],
        VvcCodingTreeStep::LumaTransformUnit {
            width: 16,
            height: 16
        }
    );
    assert_eq!(
        capacity_16x16[1],
        VvcCodingTreeStep::ChromaTransformUnit {
            x: 0,
            y: 0,
            cb_coded: false,
            cr_coded: true
        }
    );
    assert_eq!(
        capacity_16x16[4],
        VvcCodingTreeStep::ChromaTransformUnit {
            x: 4,
            y: 4,
            cb_coded: false,
            cr_coded: false
        }
    );

    let grid_64x64 = vvc_coding_tree_plan(VvcVideoGeometry {
        width: 64,
        height: 64,
    });
    assert_eq!(grid_64x64.len(), 65);
}

#[test]
fn vvc_coding_tree_plan_carries_chroma_sampling_parameter() {
    let geometry = VvcVideoGeometry {
        width: 16,
        height: 16,
    };
    let yuv420 = vvc_coding_tree_plan_with_config(geometry, VvcCodingTreeConfig::yuv420());
    let yuv444 = vvc_coding_tree_plan_with_config(
        geometry,
        VvcCodingTreeConfig {
            chroma_sampling: ChromaSampling::Cs444,
        },
    );
    assert_eq!(
        yuv420
            .iter()
            .filter(|step| matches!(step, VvcCodingTreeStep::ChromaTransformUnit { .. }))
            .count(),
        4
    );
    assert_eq!(
        yuv444
            .iter()
            .filter(|step| matches!(step, VvcCodingTreeStep::ChromaTransformUnit { .. }))
            .count(),
        16
    );
}

#[test]
fn parses_vvc_black_two_frame_headers() {
    let bytes = vvc_black_yuv420p8_annex_b(VvcEncodeParams { frames: 2 }).unwrap();
    assert_vvc_annex_b_has_min_picture_nals(&bytes, 2);
}

#[test]
fn vvc_input_path_accepts_black_yuv420p8_frames() {
    let input = vec![0; Picture::expected_len(8, 8, PixelFormat::Yuv420p8) * 2];
    let from_input =
        vvc_yuv420p8_annex_b_from_input(&input, VvcEncodeParams { frames: 2 }).unwrap();
    let generated = vvc_black_yuv420p8_annex_b(VvcEncodeParams { frames: 2 }).unwrap();
    assert_eq!(from_input, generated);
}

#[test]
fn vvc_input_path_accepts_4x8_yuv420p8_frames() {
    let input = vec![0; Picture::expected_len(4, 8, PixelFormat::Yuv420p8)];
    let bytes = vvc_yuv_annex_b_from_input(
        &input,
        VvcEncodeParams { frames: 1 },
        VvcVideoGeometry {
            width: 4,
            height: 8,
        },
        PixelFormat::Yuv420p8,
    )
    .unwrap();
    assert_vvc_annex_b_has_min_picture_nals(&bytes, 1);
}

#[test]
fn vvc_input_path_accepts_16x16_yuv444p8_frames() {
    let input = vec![0; Picture::expected_len(16, 16, PixelFormat::Yuv444p8)];
    let bytes = vvc_yuv_annex_b_from_input(
        &input,
        VvcEncodeParams { frames: 1 },
        VvcVideoGeometry {
            width: 16,
            height: 16,
        },
        PixelFormat::Yuv444p8,
    )
    .unwrap();
    assert_vvc_annex_b_has_min_picture_nals(&bytes, 1);
}

#[test]
fn vvc_input_path_samples_first_yuv_values() {
    let mut input = solid_yuv420p8(64, 128, 192, 2);
    input[3] = 255;
    input[65] = 0;
    input[81] = 1;
    let color = sample_vvc_first_yuv420p8(&input, VvcEncodeParams { frames: 2 }).unwrap();
    assert_eq!(
        color,
        VvcSampledColor {
            y: 64,
            u: 128,
            v: 192,
        }
    );
}

#[test]
fn vvc_input_path_samples_only_first_frame() {
    let mut input = solid_yuv420p8(64, 128, 192, 2);
    let second_frame = Picture::expected_len(8, 8, PixelFormat::Yuv420p8);
    input[second_frame] = 1;
    input[second_frame + 64] = 2;
    input[second_frame + 80] = 3;
    let color = sample_vvc_first_yuv420p8(&input, VvcEncodeParams { frames: 2 }).unwrap();
    assert_eq!(
        color,
        VvcSampledColor {
            y: 64,
            u: 128,
            v: 192,
        }
    );
}

#[test]
fn vvc_input_path_encodes_each_yuv420_frame_independently() {
    let frame_len = Picture::expected_len(8, 8, PixelFormat::Yuv420p8);
    let mut input = solid_yuv420p8(0, 128, 128, 1);
    input.extend_from_slice(&solid_yuv420p8(40, 128, 128, 1));
    input.extend_from_slice(&solid_yuv420p8(80, 128, 128, 1));

    let artifacts = vvc_yuv_encode_artifacts_from_input_with_limits(
        &input,
        VvcEncodeParams { frames: 3 },
        VvcVideoGeometry {
            width: 8,
            height: 8,
        },
        VvcVideoLimits::max_64x64(),
        PixelFormat::Yuv420p8,
    )
    .unwrap();
    assert_vvc_annex_b_has_min_picture_nals(&artifacts.bitstream, 3);
    assert_eq!(artifacts.reconstruction.len(), frame_len * 3);
    let reconstructed_luma: Vec<u8> = (0..3)
        .map(|frame_idx| artifacts.reconstruction[frame_idx * frame_len])
        .collect();
    assert_eq!(reconstructed_luma.len(), 3);
    assert!(reconstructed_luma.windows(2).all(|pair| pair[0] != pair[1]));
}

#[test]
fn vvc_bitstream_path_accepts_sampled_non_black_input() {
    let input = solid_yuv420p8(65, 128, 192, 1);
    let bytes = vvc_yuv420p8_annex_b_from_input(&input, VvcEncodeParams { frames: 1 }).unwrap();
    assert_vvc_annex_b_has_min_picture_nals(&bytes, 1);
}

#[test]
fn vvc_input_path_accepts_wider_yuv420p_formats() {
    let expected = vvc_yuv420p8_annex_b_from_input(
        &solid_yuv420p8(65, 128, 192, 1),
        VvcEncodeParams { frames: 1 },
    )
    .unwrap();
    for (format, bit_depth) in [
        (PixelFormat::Yuv420p10, 10),
        (PixelFormat::Yuv420p12, 12),
        (PixelFormat::Yuv420p16, 16),
    ] {
        let input = solid_yuv420p_high(65, 128, 192, bit_depth, 1);
        assert_eq!(
            vvc_yuv420p_annex_b_from_input(&input, VvcEncodeParams { frames: 1 }, format).unwrap(),
            expected
        );
    }
}

#[test]
fn vvc_input_path_accepts_supported_yuv_subsampling() {
    let expected = vvc_yuv420p8_annex_b_from_input(
        &solid_yuv420p8(65, 128, 192, 1),
        VvcEncodeParams { frames: 1 },
    )
    .unwrap();
    for (format, chroma_samples) in [(PixelFormat::Yuv422p8, 32), (PixelFormat::Yuv422p10, 32)] {
        let input =
            solid_yuv_planar_high(65, 128, 192, format.bit_depth().bits(), chroma_samples, 1);
        assert_eq!(
            vvc_default_yuv_annex_b_from_input(&input, VvcEncodeParams { frames: 1 }, format)
                .unwrap(),
            expected
        );
    }
}

#[test]
fn vvc_yuv444_input_routes_to_palette_path() {
    let input = solid_yuv_planar_high(65, 128, 192, 8, 64, 1);
    let bytes = vvc_default_yuv_annex_b_from_input(
        &input,
        VvcEncodeParams { frames: 1 },
        PixelFormat::Yuv444p8,
    )
    .unwrap();
    let transform_bytes = vvc_yuv420p8_annex_b_from_input(
        &solid_yuv420p8(65, 128, 192, 1),
        VvcEncodeParams { frames: 1 },
    )
    .unwrap();
    assert_vvc_annex_b_has_min_picture_nals(&bytes, 1);
    assert_ne!(bytes, transform_bytes);
    assert!(!bytes.windows(4).any(|window| window == b"FFPL"));
    assert!(!bytes.windows(4).any(|window| window == b"FFAC"));
}

#[test]
fn vvc_yuv444_palette_path_encodes_each_frame_independently() {
    let frame_len = Picture::expected_len(8, 8, PixelFormat::Yuv444p8);
    let mut input = solid_yuv_planar_high(10, 20, 30, 8, 64, 1);
    input.extend_from_slice(&solid_yuv_planar_high(40, 50, 60, 8, 64, 1));
    input.extend_from_slice(&solid_yuv_planar_high(70, 80, 90, 8, 64, 1));

    let artifacts = vvc_yuv_encode_artifacts_from_input_with_limits(
        &input,
        VvcEncodeParams { frames: 3 },
        VvcVideoGeometry {
            width: 8,
            height: 8,
        },
        VvcVideoLimits::max_64x64(),
        PixelFormat::Yuv444p8,
    )
    .unwrap();
    assert_vvc_annex_b_has_min_picture_nals(&artifacts.bitstream, 3);
    assert_eq!(artifacts.reconstruction.len(), input.len());
    assert_eq!(artifacts.reconstruction, input);
    assert_eq!(&artifacts.reconstruction[..frame_len], &input[..frame_len]);
    assert_eq!(
        &artifacts.reconstruction[frame_len..frame_len * 2],
        &input[frame_len..frame_len * 2]
    );
}

#[test]
fn vvc_input_path_emits_one_slice_per_ctu_for_larger_yuv420_picture() {
    let geometry = VvcVideoGeometry {
        width: 160,
        height: 120,
    };
    let input = solid_yuv420p8_geometry(geometry.width, geometry.height, 0, 0, 0, 1);

    let artifacts = vvc_yuv_encode_artifacts_from_input_with_limits(
        &input,
        VvcEncodeParams { frames: 1 },
        geometry,
        VvcVideoLimits {
            max_width: 1024,
            max_height: 512,
        },
        PixelFormat::Yuv420p8,
    )
    .unwrap();

    let infos = assert_vvc_annex_b_has_min_picture_nals(&artifacts.bitstream, 1);
    assert_eq!(infos[2].nal_unit_type, VvcNalUnitType::PictureHeader as u8);
    assert_eq!(
        count_vvc_picture_nals(&infos),
        vvc_picture_ctu_count(geometry)
    );
    assert_eq!(
        artifacts.reconstruction.len(),
        Picture::expected_len(geometry.width, geometry.height, PixelFormat::Yuv420p8)
    );
}

#[test]
fn vvc_input_path_emits_one_slice_per_ctu_for_larger_yuv444_palette_picture() {
    let geometry = VvcVideoGeometry {
        width: 128,
        height: 72,
    };
    let input = solid_yuv444p8_geometry(geometry.width, geometry.height, 20, 40, 60, 1);

    let artifacts = vvc_yuv_encode_artifacts_from_input_with_limits(
        &input,
        VvcEncodeParams { frames: 1 },
        geometry,
        VvcVideoLimits {
            max_width: 1024,
            max_height: 512,
        },
        PixelFormat::Yuv444p8,
    )
    .unwrap();

    let infos = assert_vvc_annex_b_has_min_picture_nals(&artifacts.bitstream, 1);
    assert_eq!(infos[2].nal_unit_type, VvcNalUnitType::PictureHeader as u8);
    assert_eq!(
        count_vvc_picture_nals(&infos),
        vvc_picture_ctu_count(geometry)
    );
    assert_eq!(artifacts.reconstruction, input);
}

#[test]
fn vvc_input_max_capacity_does_not_affect_encoded_stream() {
    let cases = [
        (
            VvcVideoGeometry {
                width: 160,
                height: 120,
            },
            PixelFormat::Yuv420p8,
            solid_yuv420p8_geometry(160, 120, 24, 128, 192, 1),
        ),
        (
            VvcVideoGeometry {
                width: 128,
                height: 72,
            },
            PixelFormat::Yuv444p8,
            solid_yuv444p8_geometry(128, 72, 24, 128, 192, 1),
        ),
    ];

    for (geometry, format, input) in cases {
        let exact_capacity = vvc_yuv_encode_artifacts_from_input_with_limits(
            &input,
            VvcEncodeParams { frames: 1 },
            geometry,
            VvcVideoLimits {
                max_width: geometry.width,
                max_height: geometry.height,
            },
            format,
        )
        .unwrap();

        let oversized_capacity = vvc_yuv_encode_artifacts_from_input_with_limits(
            &input,
            VvcEncodeParams { frames: 1 },
            geometry,
            VvcVideoLimits {
                max_width: 16_384,
                max_height: 8_192,
            },
            format,
        )
        .unwrap();

        assert_eq!(
            exact_capacity.bitstream, oversized_capacity.bitstream,
            "max capacity should not change the emitted stream for {geometry:?} {format:?}"
        );
        assert_eq!(
            exact_capacity.reconstruction, oversized_capacity.reconstruction,
            "max capacity should not change reconstruction for {geometry:?} {format:?}"
        );
    }
}

#[test]
fn vvc_palette_444_contexts_are_spec_audited() {
    let rows = vvc_palette_444_context_audit_rows();
    assert!(rows.contains(&("pred_mode_plt_flag[0]", 25, 1)));
    assert!(rows.contains(&("palette_transpose_flag[0]", 42, 5)));
    assert!(rows.contains(&("copy_above_palette_indices_flag[0]", 42, 9)));
    assert_eq!(
        rows.iter()
            .filter(|(name, _, _)| *name == "run_copy_flag")
            .count(),
        8
    );

    assert_eq!(vvc_palette_run_copy_context_id_for_audit(0, false), 0);
    assert_eq!(vvc_palette_run_copy_context_id_for_audit(3, false), 3);
    assert_eq!(vvc_palette_run_copy_context_id_for_audit(8, false), 4);
    assert_eq!(vvc_palette_run_copy_context_id_for_audit(0, true), 5);
    assert_eq!(vvc_palette_run_copy_context_id_for_audit(2, true), 6);
    assert_eq!(vvc_palette_run_copy_context_id_for_audit(8, true), 7);
    assert_eq!(VvcCabacContext::PredModePltFlag.rtl_context_id(), Some(42));
    assert_eq!(VvcCabacContext::RunCopyFlag(7).rtl_context_id(), Some(52));
}

#[test]
fn vvc_palette_444_syntax_uses_spec_single_entry_subset() {
    let geometry = VvcVideoGeometry {
        width: 16,
        height: 16,
    };
    let syntax = vvc_palette_444_single_entry_syntax(
        geometry,
        VvcSampledColor {
            y: 65,
            u: 128,
            v: 192,
        },
    );
    assert_eq!(syntax.tree_type, VvcPaletteTreeType::SingleTree);
    assert_eq!(syntax.cb_width, 16);
    assert_eq!(syntax.cb_height, 16);
    assert_eq!(syntax.start_comp, 0);
    assert_eq!(syntax.num_comps, 3);
    assert_eq!(syntax.max_num_palette_entries, 31);
    assert_eq!(syntax.num_predicted_palette_entries, 0);
    assert_eq!(syntax.num_signalled_palette_entries, 1);
    assert_eq!(syntax.current_palette_size, 1);
    assert!(!syntax.palette_escape_val_present_flag);
    assert_eq!(syntax.max_palette_index, 0);

    let bits = vvc_palette_444_binarized_syntax_bits(syntax.clone());
    assert_eq!(bits.len(), 28);
    assert_eq!(&bits[0..3], &[false, true, false]); // EG0 for value 1.

    let tokens =
        vvc_palette_444_syntax_tokens(syntax.clone(), VvcPalettePredictorMode::SignalNewEntry);
    let names: Vec<&str> = tokens.iter().map(|token| token.name).collect();
    assert_eq!(
        names,
        vec![
            "num_signalled_palette_entries",
            "new_palette_entries[0][i]",
            "new_palette_entries[1][i]",
            "new_palette_entries[2][i]",
            "palette_escape_val_present_flag",
        ]
    );

    let decoded = vvc_palette_444_decode_reconstruction(geometry, syntax);
    assert_eq!(decoded.luma, vec![65; geometry.luma_samples()]);
    assert_eq!(decoded.cb, vec![128; geometry.luma_samples()]);
    assert_eq!(decoded.cr, vec![192; geometry.luma_samples()]);
}

#[test]
fn vvc_palette_444_cu_syntax_carries_palette_indices_for_lossless_8x8() {
    let geometry = VvcVideoGeometry {
        width: 8,
        height: 8,
    };
    let mut luma = Vec::with_capacity(64);
    let mut cb = Vec::with_capacity(64);
    let mut cr = Vec::with_capacity(64);
    for idx in 0..64 {
        let even = idx % 2 == 0;
        luma.push(if even { 10 } else { 200 });
        cb.push(if even { 20 } else { 210 });
        cr.push(if even { 30 } else { 220 });
    }
    let frame = VvcSampledFrame {
        geometry,
        format: VvcPictureFormat {
            chroma_sampling: ChromaSampling::Cs444,
            bit_depth: SampleBitDepth::Eight,
        },
        luma: luma.clone(),
        cb: cb.clone(),
        cr: cr.clone(),
        chroma_len: 64,
    };

    let syntax = vvc_palette_444_cu_syntax(&frame, 0, 0);
    assert_eq!(syntax.num_signalled_palette_entries, 2);
    assert_eq!(syntax.current_palette_size, 2);
    assert_eq!(syntax.max_palette_index, 1);
    assert_eq!(syntax.palette_indices.len(), 64);

    let tokens =
        vvc_palette_444_syntax_tokens(syntax.clone(), VvcPalettePredictorMode::SignalNewEntry);
    assert_eq!(
        tokens
            .iter()
            .filter(|token| token.name == "palette_idx_idc")
            .count(),
        0
    );

    let decoded = vvc_palette_444_decode_reconstruction(geometry, syntax);
    assert_eq!(decoded.luma, luma);
    assert_eq!(decoded.cb, cb);
    assert_eq!(decoded.cr, cr);
}

#[test]
fn vvc_palette_444_cu_syntax_uses_escape_values_after_31_entries() {
    let geometry = VvcVideoGeometry {
        width: 8,
        height: 8,
    };
    let mut luma = Vec::with_capacity(64);
    let mut cb = Vec::with_capacity(64);
    let mut cr = Vec::with_capacity(64);
    for idx in 0..64 {
        luma.push((idx * 3 + 1) as u8);
        cb.push((idx * 5 + 7) as u8);
        cr.push((idx * 11 + 13) as u8);
    }
    let frame = VvcSampledFrame {
        geometry,
        format: VvcPictureFormat {
            chroma_sampling: ChromaSampling::Cs444,
            bit_depth: SampleBitDepth::Eight,
        },
        luma: luma.clone(),
        cb: cb.clone(),
        cr: cr.clone(),
        chroma_len: 64,
    };

    let syntax = vvc_palette_444_cu_syntax(&frame, 0, 0);
    assert_eq!(syntax.num_signalled_palette_entries, 31);
    assert_eq!(syntax.current_palette_size, 31);
    assert!(syntax.palette_escape_val_present_flag);
    assert_eq!(syntax.max_palette_index, 31);
    assert_eq!(syntax.palette_indices.len(), 64);
    assert_eq!(syntax.palette_indices[30], 30);
    assert_eq!(syntax.palette_indices[31], 31);
    let raw_escape_31 = VvcSampledColor {
        y: luma[31],
        u: cb[31],
        v: cr[31],
    };
    assert_eq!(syntax.palette_escape_values[31], Some(raw_escape_31));

    let decoded = vvc_palette_444_decode_reconstruction(geometry, syntax);
    assert_eq!(decoded.luma, luma);
    assert_eq!(decoded.cb, cb);
    assert_eq!(decoded.cr, cr);
}

#[test]
fn vvc_palette_444_uses_ibc_for_repeated_8x8_block() {
    let geometry = VvcVideoGeometry {
        width: 16,
        height: 8,
    };
    let mut luma = vec![0; geometry.luma_samples()];
    let mut cb = vec![0; geometry.luma_samples()];
    let mut cr = vec![0; geometry.luma_samples()];
    for y in 0..8 {
        for x in 0..8 {
            let base = y * 8 + x;
            let color_y = (base * 3 + 11) as u8;
            let color_cb = (base * 5 + 17) as u8;
            let color_cr = (base * 7 + 23) as u8;
            for block_x in [0, 8] {
                let dst = y * geometry.width + block_x + x;
                luma[dst] = color_y;
                cb[dst] = color_cb;
                cr[dst] = color_cr;
            }
        }
    }
    let frame = VvcSampledFrame {
        geometry,
        format: VvcPictureFormat {
            chroma_sampling: ChromaSampling::Cs444,
            bit_depth: SampleBitDepth::Eight,
        },
        luma: luma.clone(),
        cb: cb.clone(),
        cr: cr.clone(),
        chroma_len: geometry.luma_samples(),
    };

    let recon = vvc_palette_444_reconstruction_yuv(&frame);
    assert_eq!(recon, [luma, cb, cr].concat());

    let mut ibc_search = super::ibc::VvcIbcHashSearch::new();
    ibc_search.record_palette_8x8(&frame, 0, 0);
    let decision = ibc_search
        .decide_8x8(&frame, 8, 0)
        .expect("hash search should still find the repeated 8x8 block");
    assert_eq!(decision.ref_origin_x, 0);
    assert_eq!(decision.ref_origin_y, 0);
    assert_eq!(decision.mvd_x, -8);
    assert_eq!(decision.mvd_y, 0);

    let ctx_bins = vvc_palette_444_cabac_context_bins(&frame);
    assert!(
        ctx_bins.contains(&(
            VvcCabacContext::PredModeIbcFlag(0)
                .rtl_context_id()
                .unwrap(),
            true
        )),
        "exact-hash MODE_IBC should be emitted for repeated 4:4:4 8x8 CUs"
    );
}

#[test]
fn vvc_palette_444_uses_transform_skip_residual_for_left_ibc_delta() {
    let geometry = VvcVideoGeometry {
        width: 16,
        height: 8,
    };
    let mut luma = vec![80; geometry.luma_samples()];
    let mut cb = vec![90; geometry.luma_samples()];
    let mut cr = vec![100; geometry.luma_samples()];
    for y in 0..4 {
        for x in 0..4 {
            let dst = y * geometry.width + 8 + x;
            luma[dst] = 83;
            cb[dst] = 94;
            cr[dst] = 105;
        }
    }
    let frame = VvcSampledFrame {
        geometry,
        format: VvcPictureFormat {
            chroma_sampling: ChromaSampling::Cs444,
            bit_depth: SampleBitDepth::Eight,
        },
        luma: luma.clone(),
        cb: cb.clone(),
        cr: cr.clone(),
        chroma_len: geometry.luma_samples(),
    };

    assert_eq!(
        vvc_palette_444_reconstruction_yuv(&frame),
        [luma, cb, cr].concat()
    );

    let ctx_bins = vvc_palette_444_cabac_context_bins(&frame);
    assert!(
        ctx_bins.contains(&(
            VvcCabacContext::CuCodedFlag(0).rtl_context_id().unwrap(),
            true
        )),
        "IBC residual CU should signal transform_tree"
    );
    assert!(
        ctx_bins.contains(&(
            VvcCabacContext::TransformSkipFlag(0)
                .rtl_context_id()
                .unwrap(),
            true
        )),
        "luma residual should use transform_skip_flag=1"
    );
    assert!(
        ctx_bins.contains(&(
            VvcCabacContext::TransformSkipFlag(1)
                .rtl_context_id()
                .unwrap(),
            true
        )),
        "chroma residual should use transform_skip_flag=1"
    );
}

#[test]
fn vvc_palette_444_uses_horizontal_bdpcm_for_left_predicted_rows() {
    let geometry = VvcVideoGeometry {
        width: 16,
        height: 8,
    };
    let mut luma = vec![70; geometry.luma_samples()];
    let mut cb = vec![96; geometry.luma_samples()];
    let mut cr = vec![132; geometry.luma_samples()];
    for y in 0..4 {
        for x in 0..8 {
            let dst = y * geometry.width + 8 + x;
            let hold: u8 = if x < 4 { [1, 3, 6, 10][x] } else { 10 };
            luma[dst] = 70 + hold;
            cb[dst] = 96 + hold + 2;
            cr[dst] = 132 + hold + 4;
        }
    }
    let frame = VvcSampledFrame {
        geometry,
        format: VvcPictureFormat {
            chroma_sampling: ChromaSampling::Cs444,
            bit_depth: SampleBitDepth::Eight,
        },
        luma: luma.clone(),
        cb: cb.clone(),
        cr: cr.clone(),
        chroma_len: geometry.luma_samples(),
    };

    assert_eq!(
        vvc_palette_444_reconstruction_yuv(&frame),
        [luma, cb, cr].concat()
    );

    let ctx_bins = vvc_palette_444_cabac_context_bins(&frame);
    assert!(
        ctx_bins.contains(&(
            VvcCabacContext::BdpcmMode(0).rtl_context_id().unwrap(),
            true
        )),
        "BDPCM CU should signal intra_bdpcm_luma_flag=1"
    );
    assert!(
        ctx_bins.contains(&(
            VvcCabacContext::BdpcmMode(1).rtl_context_id().unwrap(),
            false
        )),
        "BDPCM CU should use horizontal luma direction"
    );
    assert!(
        ctx_bins.contains(&(
            VvcCabacContext::BdpcmMode(2).rtl_context_id().unwrap(),
            true
        )),
        "BDPCM CU should signal intra_bdpcm_chroma_flag=1"
    );
    assert!(
        !ctx_bins.contains(&(
            VvcCabacContext::TransformSkipFlag(0)
                .rtl_context_id()
                .unwrap(),
            true
        )),
        "BDPCM infers transform_skip_flag=1 instead of coding it"
    );
}

#[test]
fn vvc_input_path_changes_bitstream_from_sampled_color() {
    let mut input = solid_yuv420p8(65, 128, 192, 2);
    input[1] = 0;
    input[65] = 0;
    let from_input =
        vvc_yuv420p8_annex_b_from_input(&input, VvcEncodeParams { frames: 2 }).unwrap();
    let current_bitstream = vvc_black_yuv420p8_annex_b(VvcEncodeParams { frames: 2 }).unwrap();
    assert_ne!(from_input, current_bitstream);
}

#[test]
fn rejects_zero_vvc_frame_count() {
    assert!(vvc_black_yuv420p8_annex_b(VvcEncodeParams { frames: 0 }).is_err());
    let bytes = vvc_black_yuv420p8_annex_b(VvcEncodeParams { frames: 9 }).unwrap();
    assert_vvc_annex_b_has_min_picture_nals(&bytes, 9);
}

fn solid_yuv420p8(y: u8, u: u8, v: u8, frames: usize) -> Vec<u8> {
    solid_yuv420p8_geometry(8, 8, y, u, v, frames)
}

fn solid_yuv420p8_geometry(
    width: usize,
    height: usize,
    y: u8,
    u: u8,
    v: u8,
    frames: usize,
) -> Vec<u8> {
    let luma = width * height;
    let chroma = luma / 4;
    let mut out =
        Vec::with_capacity(Picture::expected_len(width, height, PixelFormat::Yuv420p8) * frames);
    for _ in 0..frames {
        out.extend(std::iter::repeat_n(y, luma));
        out.extend(std::iter::repeat_n(u, chroma));
        out.extend(std::iter::repeat_n(v, chroma));
    }
    out
}

fn solid_yuv444p8_geometry(
    width: usize,
    height: usize,
    y: u8,
    u: u8,
    v: u8,
    frames: usize,
) -> Vec<u8> {
    let samples = width * height;
    let mut out =
        Vec::with_capacity(Picture::expected_len(width, height, PixelFormat::Yuv444p8) * frames);
    for _ in 0..frames {
        out.extend(std::iter::repeat_n(y, samples));
        out.extend(std::iter::repeat_n(u, samples));
        out.extend(std::iter::repeat_n(v, samples));
    }
    out
}

fn solid_yuv420p_high(y: u8, u: u8, v: u8, bit_depth: u8, frames: usize) -> Vec<u8> {
    solid_yuv_planar_high(y, u, v, bit_depth, 16, frames)
}

fn solid_yuv_planar_high(
    y: u8,
    u: u8,
    v: u8,
    bit_depth: u8,
    chroma_samples: usize,
    frames: usize,
) -> Vec<u8> {
    let mut out = Vec::new();
    for _ in 0..frames {
        for sample in [y]
            .repeat(64)
            .into_iter()
            .chain([u].repeat(chroma_samples))
            .chain([v].repeat(chroma_samples))
        {
            let value = (sample as u16) << (bit_depth - 8);
            if bit_depth == 8 {
                out.push(sample);
            } else {
                out.extend(value.to_le_bytes());
            }
        }
    }
    out
}
