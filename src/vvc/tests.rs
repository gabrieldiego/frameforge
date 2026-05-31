use super::residual::vvc_anchor_luma_tu_size;
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

    let pps = vvc_4x4_pps_rbsp(geometry);
    assert_eq!(
        vvc_ue_value(&pps, "pps_pic_width_in_luma_samples") as usize,
        geometry.coded_width()
    );
    assert_eq!(
        vvc_ue_value(&pps, "pps_pic_height_in_luma_samples") as usize,
        geometry.coded_height()
    );
}

fn vvc_transform_block(dc_coeff: i16) -> Vvc4x4TransformBlock {
    Vvc4x4TransformBlock {
        dc_coeff,
        ac_coeffs: [0; 15],
    }
}

fn vvc_luma_8x8_transform_block(samples: [u8; 64]) -> Vvc4x4TransformBlock {
    let transform = transform_vvc_tu(VvcTransformComponent::Luma, 8, 8, &samples);
    vvc_transform_block(transform.dc_coeff)
}

fn vvc_solid_luma_8x8_transform_block(sample: u8) -> Vvc4x4TransformBlock {
    vvc_luma_8x8_transform_block([sample; 64])
}

fn vvc_quantized_block(
    reconstructed_dc_coeff: i16,
    abs_remainder: u8,
) -> Vvc4x4QuantizedTransformBlock {
    Vvc4x4QuantizedTransformBlock {
        reconstructed_dc_coeff,
        reconstructed_ac_coeffs: [0; 15],
        abs_remainder,
        ac_tokens: [0x40; 15],
    }
}

fn vvc_quantized_color(y: u8, luma_rem: u8) -> Vvc4x4QuantizedColor {
    Vvc4x4QuantizedColor {
        y,
        u: 0,
        v: 0,
        luma_rem,
        luma_ac_tokens: [0x40; 15],
        second_luma_rem: luma_rem,
        second_luma_ac_tokens: [0x40; 15],
        luma_tu_remainders: [luma_rem; MAX_VVC_LUMA_TUS],
        luma_tu_ac0_tokens: [0x40; MAX_VVC_LUMA_TUS],
        luma_tu_count: 1,
        cb_rem: 16,
        cr_rem: 16,
    }
}

fn vvc_quantized_color_with_chroma(
    y: u8,
    luma_rem: u8,
    chroma: u8,
    chroma_residual: u8,
) -> Vvc4x4QuantizedColor {
    Vvc4x4QuantizedColor {
        y,
        u: chroma,
        v: chroma,
        luma_rem,
        luma_ac_tokens: [0x40; 15],
        second_luma_rem: luma_rem,
        second_luma_ac_tokens: [0x40; 15],
        luma_tu_remainders: [luma_rem; MAX_VVC_LUMA_TUS],
        luma_tu_ac0_tokens: [0x40; MAX_VVC_LUMA_TUS],
        luma_tu_count: 1,
        cb_rem: chroma_residual,
        cr_rem: chroma_residual,
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
fn parses_vvc_black_4x4_one_frame_headers() {
    let bytes = vvc_black_yuv420p8_annex_b(VvcEncodeParams { frames: 1 }).unwrap();
    let infos = parse_annex_b_nal_units(&bytes).unwrap();
    let types: Vec<u8> = infos.iter().map(|info| info.nal_unit_type).collect();
    assert_eq!(types, vec![15, 16, 8]);
    assert!(infos[0].payload_len > 0);
    assert!(infos[1].payload_len > 0);
    assert!(infos[2].payload_len > 0);
    assert_eq!(
        infos[2].offset + 2 + infos[2].payload_len,
        bytes.len(),
        "single-frame stream should end at the IDR NAL payload boundary"
    );
}

#[test]
fn vvc_parameter_sets_are_generated_from_named_syntax() {
    let geometry = VvcVideoGeometry::four_by_four();
    let sps = vvc_sps_rbsp(geometry, vvc_test_slice_config());
    let pps = vvc_4x4_pps_rbsp(geometry);

    assert!(!sps.bytes.is_empty());
    assert!(!pps.bytes.is_empty());
    assert_eq!(vvc_u_value(&sps, "sps_chroma_format_idc"), 1);
    assert_eq!(vvc_u_value(&sps, "sps_log2_ctu_size_minus5"), 1);
    assert_vvc_parameter_sets_signal_geometry(geometry);
    assert_vvc_flag(&pps, "pps_no_pic_partition_flag", true);
    assert_vvc_flag(&pps, "pps_cabac_init_present_flag", false);
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
    assert_ne!(vvc_4x4_sps_payload(wide), vvc_4x4_sps_payload(tall));
    assert_ne!(
        vvc_4x4_sps_payload(wide),
        vvc_4x4_sps_payload(VvcVideoGeometry {
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

    assert_vvc_flag(&rbsp, "sps_ref_pic_resampling_enabled_flag", false);
    assert_vvc_field_absent(&rbsp, "sps_res_change_in_clvs_allowed_flag");
    assert_vvc_flag(&rbsp, "sps_entry_point_offsets_present_flag", false);
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
fn vvc_slice_header_tool_flags_follow_the_active_slice_config() {
    let black = quantize_vvc_4x4_color(Vvc4x4SampledColor { y: 0, u: 0, v: 0 });
    let rbsp = vvc_4x4_slice_rbsp(
        Vvc4x4PictureKind::Idr,
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
    let black = quantize_vvc_4x4_color(Vvc4x4SampledColor { y: 0, u: 0, v: 0 });
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
    let black = quantize_vvc_4x4_color(Vvc4x4SampledColor { y: 0, u: 0, v: 0 });
    let geometry = VvcVideoGeometry::four_by_four();
    let idr = vvc_4x4_slice_rbsp(
        Vvc4x4PictureKind::Idr,
        geometry,
        black,
        vvc_test_slice_config(),
    );
    let cra = vvc_4x4_slice_rbsp(
        Vvc4x4PictureKind::Cra,
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
fn vvc_solid_luma_8x8_transform_generates_dc_only() {
    for (sample, dc_coeff) in [(0, -114), (64, -50), (114, 0)] {
        assert_eq!(
            transform_vvc_tu(VvcTransformComponent::Luma, 8, 8, &[sample; 64]),
            VvcTuTransformBlock {
                component: VvcTransformComponent::Luma,
                width: 8,
                height: 8,
                dc_coeff,
                ac_coeffs: vec![0; 63],
            }
        );
    }
}

#[test]
fn vvc_luma_8x8_transform_dc_uses_all_samples() {
    let mut samples = [64; 64];
    samples[3] = 255;
    assert_eq!(
        transform_vvc_tu(VvcTransformComponent::Luma, 8, 8, &samples),
        VvcTuTransformBlock {
            component: VvcTransformComponent::Luma,
            width: 8,
            height: 8,
            dc_coeff: -47,
            ac_coeffs: vec![0; 63],
        }
    );
}

#[test]
fn vvc_dc_transform_accepts_8x8_luma_and_4x4_chroma_tus() {
    let mut luma = vec![32; 8 * 8];
    luma[7] = 255;
    assert_eq!(
        transform_vvc_tu(VvcTransformComponent::Luma, 8, 8, &luma),
        VvcTuTransformBlock {
            component: VvcTransformComponent::Luma,
            width: 8,
            height: 8,
            dc_coeff: -79,
            ac_coeffs: vec![0; 63],
        }
    );

    let mut cb = vec![128; 4 * 4];
    cb[5] = 0;
    assert_eq!(
        transform_vvc_tu(VvcTransformComponent::ChromaCb, 4, 4, &cb),
        VvcTuTransformBlock {
            component: VvcTransformComponent::ChromaCb,
            width: 4,
            height: 4,
            dc_coeff: -8,
            ac_coeffs: vec![0; 15],
        }
    );
}

#[test]
fn vvc_luma_dc_quantization_matches_existing_ladder() {
    let black = quantize_vvc_4x4_luma_dc(vvc_solid_luma_8x8_transform_block(0));
    assert_eq!(black, vvc_quantized_block(-114, 16));

    let mid = quantize_vvc_4x4_luma_dc(vvc_solid_luma_8x8_transform_block(65));
    assert_eq!(mid, vvc_quantized_block(-50, 7));

    let white = quantize_vvc_4x4_luma_dc(vvc_solid_luma_8x8_transform_block(255));
    assert_eq!(white, vvc_quantized_block(0, 0));
}

#[test]
fn vvc_inverse_transform_reconstructs_solid_luma_block() {
    let quantized = vvc_quantized_block(-50, 7);
    assert_eq!(
        inverse_transform_vvc_4x4_luma_dc(quantized),
        Vvc4x4ReconstructedLumaBlock { samples: [64; 16] }
    );
}

#[test]
fn vvc_color_quantization_uses_inverse_transform_reconstruction() {
    assert_eq!(
        quantize_vvc_4x4_color(Vvc4x4SampledColor { y: 65, u: 9, v: 7 }),
        vvc_quantized_color_with_chroma(64, 7, 8, 15)
    );
}

#[test]
fn vvc_frame_quantization_uses_anchor_tu_samples_for_dc() {
    let mut luma = [0; 64];
    luma[3] = 255;
    let ac_tokens = [0x40; 15];
    assert_eq!(
        quantize_vvc_4x4_frame(Vvc4x4SampledFrame {
            geometry: VvcVideoGeometry {
                width: 8,
                height: 8,
            },
            format: Vvc4x4PictureFormat {
                chroma_sampling: ChromaSampling::Cs420,
                bit_depth: SampleBitDepth::Eight,
            },
            luma: luma.to_vec(),
            cb: vec![9; 16],
            cr: vec![7; 16],
            chroma_len: 16,
        }),
        Vvc4x4QuantizedColor {
            y: 7,
            u: 8,
            v: 8,
            luma_rem: 15,
            luma_ac_tokens: ac_tokens,
            second_luma_rem: 15,
            second_luma_ac_tokens: ac_tokens,
            luma_tu_remainders: [15; MAX_VVC_LUMA_TUS],
            luma_tu_ac0_tokens: [0x40; MAX_VVC_LUMA_TUS],
            luma_tu_count: 1,
            cb_rem: 15,
            cr_rem: 15,
        }
    );
}

#[test]
fn vvc_frame_quantization_builds_anchor_luma_tu_metadata() {
    let frame = Vvc4x4SampledFrame {
        geometry: VvcVideoGeometry {
            width: 64,
            height: 64,
        },
        format: Vvc4x4PictureFormat {
            chroma_sampling: ChromaSampling::Cs420,
            bit_depth: SampleBitDepth::Eight,
        },
        luma: vec![64; 64 * 64],
        cb: vec![128; 32 * 32],
        cr: vec![192; 32 * 32],
        chroma_len: 32 * 32,
    };
    let color = quantize_vvc_4x4_frame(frame);
    assert_eq!(color.luma_tu_count, 1);
    assert_eq!(color.luma_tu_remainders[0], 7);
    assert_eq!(color.luma_tu_ac0_tokens[0], 0x40);
}

#[test]
fn vvc_anchor_luma_tu_size_follows_generated_partition_leaf() {
    assert_eq!(
        vvc_anchor_luma_tu_size(VvcVideoGeometry {
            width: 16,
            height: 8,
        }),
        VvcVideoGeometry {
            width: 16,
            height: 8,
        }
    );
    assert_eq!(
        vvc_anchor_luma_tu_size(VvcVideoGeometry {
            width: 8,
            height: 16,
        }),
        VvcVideoGeometry {
            width: 8,
            height: 16,
        }
    );
    assert_eq!(
        vvc_anchor_luma_tu_size(VvcVideoGeometry {
            width: 24,
            height: 16,
        }),
        VvcVideoGeometry {
            width: 8,
            height: 8,
        }
    );
}

#[test]
fn vvc_chroma_quantization_keeps_black_neutral_and_nonzero_colored() {
    assert_eq!(quantize_vvc_4x4_chroma(0, 0), 16);
    assert_eq!(reconstruct_vvc_4x4_chroma(16), 0);
    assert_eq!(quantize_vvc_4x4_chroma_sample(128), 0);
    assert_eq!(quantize_vvc_4x4_chroma(128, 192), 0);
    assert_eq!(reconstruct_vvc_4x4_chroma(0), 128);
}

#[test]
fn vvc_inverse_transform_reconstructs_quantized_ac_coefficients() {
    let mut block = vvc_quantized_block(-36, 5);
    block.reconstructed_ac_coeffs[2] = 128;
    block.ac_tokens[2] = 0x48;
    assert_eq!(inverse_transform_vvc_4x4_luma_dc(block).samples[3], 206);
}

#[test]
fn vvc_arithmetic_writer_generates_verified_luma_payloads() {
    let mut payloads = Vec::new();
    for luma_rem in 0..=16 {
        let color = vvc_quantized_color(0, luma_rem as u8);
        let payload = vvc_4x4_slice_payload(
            Vvc4x4PictureKind::Idr,
            VvcVideoGeometry::four_by_four(),
            color,
        );
        assert!(!payload.is_empty());
        payloads.push(payload);
    }
    assert!(payloads.windows(2).all(|pair| pair[0] != pair[1]));
}

#[test]
fn vvc_coding_tree_entropy_is_generated_from_ctu_syntax() {
    let black = quantize_vvc_4x4_color(Vvc4x4SampledColor { y: 0, u: 0, v: 0 });
    let geometry = VvcVideoGeometry::four_by_four();
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
    let black = quantize_vvc_4x4_color(Vvc4x4SampledColor { y: 0, u: 0, v: 0 });
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
    let black = quantize_vvc_4x4_color(Vvc4x4SampledColor { y: 0, u: 0, v: 0 });
    assert_eq!(
        vvc_ctu_partition_params(
            VvcVideoGeometry {
                width: 64,
                height: 64
            },
            black
        ),
        Some(VvcCtuPartitionParams {
            root_width: 64,
            root_height: 64,
            visible_width: 64,
            visible_height: 64,
            chroma_sampling: ChromaSampling::Cs420,
            chroma_tu_count: 64,
            luma_dc_abs_level: 16,
            luma_dc_negative: true,
            cb_dc_abs_level: 16,
            cb_dc_negative: true,
        })
    );
    assert_eq!(
        vvc_ctu_partition_params(
            VvcVideoGeometry {
                width: 64,
                height: 32
            },
            black
        ),
        Some(VvcCtuPartitionParams {
            root_width: 64,
            root_height: 64,
            visible_width: 64,
            visible_height: 32,
            chroma_sampling: ChromaSampling::Cs420,
            chroma_tu_count: 32,
            luma_dc_abs_level: 16,
            luma_dc_negative: true,
            cb_dc_abs_level: 16,
            cb_dc_negative: true,
        })
    );
    assert_eq!(
        vvc_ctu_partition_params(
            VvcVideoGeometry {
                width: 32,
                height: 64
            },
            black
        ),
        Some(VvcCtuPartitionParams {
            root_width: 64,
            root_height: 64,
            visible_width: 32,
            visible_height: 64,
            chroma_sampling: ChromaSampling::Cs420,
            chroma_tu_count: 32,
            luma_dc_abs_level: 16,
            luma_dc_negative: true,
            cb_dc_abs_level: 16,
            cb_dc_negative: true,
        })
    );
    assert_eq!(
        vvc_ctu_partition_params(
            VvcVideoGeometry {
                width: 32,
                height: 32
            },
            black
        ),
        Some(VvcCtuPartitionParams {
            root_width: 64,
            root_height: 64,
            visible_width: 32,
            visible_height: 32,
            chroma_sampling: ChromaSampling::Cs420,
            chroma_tu_count: 16,
            luma_dc_abs_level: 16,
            luma_dc_negative: true,
            cb_dc_abs_level: 16,
            cb_dc_negative: true,
        })
    );
    assert_eq!(
        vvc_ctu_partition_params(
            VvcVideoGeometry {
                width: 16,
                height: 16
            },
            black
        ),
        Some(VvcCtuPartitionParams {
            root_width: 64,
            root_height: 64,
            visible_width: 16,
            visible_height: 16,
            chroma_sampling: ChromaSampling::Cs420,
            chroma_tu_count: 4,
            luma_dc_abs_level: 16,
            luma_dc_negative: true,
            cb_dc_abs_level: 16,
            cb_dc_negative: true,
        })
    );
}

#[test]
fn vvc_ctu_partition_params_cover_all_8_sample_geometries_up_to_64() {
    let black = quantize_vvc_4x4_color(Vvc4x4SampledColor { y: 0, u: 0, v: 0 });
    for width in (8..=64).step_by(8) {
        for height in (8..=64).step_by(8) {
            let geometry = VvcVideoGeometry { width, height };
            let params = vvc_ctu_partition_params(geometry, black)
                .unwrap_or_else(|| panic!("missing CTU params for {width}x{height}"));
            assert_eq!(params.root_width, 64);
            assert_eq!(params.root_height, 64);
            assert_eq!(params.visible_width, width);
            assert_eq!(params.visible_height, height);
            assert_eq!(params.chroma_tu_count, (width * height) / 64);
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
fn vvc_residual_cabac_encoder_labels_disabled_tool_paths() {
    let mut contexts = VvcCabacContexts::new();
    let mut cabac = VvcCabacEncoder::new();
    cabac.start();

    let mut disabled =
        VvcResidualCabacEncoder::new(&mut contexts, vvc_test_slice_config().residual_options());
    disabled.emit_transform_skip_flag(&mut cabac, VvcResidualComponent::Luma, false);
    disabled.emit_mts_idx_zero(&mut cabac);
    disabled.emit_current_unused_tool_placeholders();
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
    enabled.emit_transform_skip_flag(&mut cabac, VvcResidualComponent::Luma, false);
    enabled.emit_mts_idx_zero(&mut cabac);
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
    let initial_sign0 = contexts.coeff_sign_flag[0].state();

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
    residual.emit_coeff_sign_flag(&mut cabac, &state, 3, 3, true);

    assert_ne!(contexts.last_sig_coeff_x_prefix[3].state(), initial_last_x0);
    assert_ne!(contexts.last_sig_coeff_y_prefix[0].state(), initial_last_y0);
    assert_ne!(contexts.sig_coeff_flag[8].state(), initial_sig8);
    assert_ne!(contexts.par_level_flag[0].state(), initial_par0);
    assert_ne!(contexts.abs_level_gtx_flag[32].state(), initial_abs32);
    assert_eq!(contexts.coeff_sign_flag[0].state(), initial_sign0);
}

#[test]
fn vvc_residual_cabac_encoder_context_codes_transform_skip_signs() {
    let mut config = VvcResidualCtxConfig::luma_4x4_subset(3, 3);
    config.transform_skip = true;
    config.ts_residual_coding_disabled = false;
    let state = VvcResidualPass1State::new(config);

    let mut contexts = VvcCabacContexts::new();
    let initial_sign0 = contexts.coeff_sign_flag[0].state();
    let mut cabac = VvcCabacEncoder::new();
    cabac.start();
    let mut residual =
        VvcResidualCabacEncoder::new(&mut contexts, vvc_test_slice_config().residual_options());
    residual.emit_coeff_sign_flag(&mut cabac, &state, 0, 0, true);

    assert_ne!(contexts.coeff_sign_flag[0].state(), initial_sign0);
}

#[test]
fn vvc_residual_symbol_stream_names_dc_only_luma_subset() {
    let stream = VvcResidualCabacSymbolStream::luma_dc_only(3, 3, 3, true);
    assert_eq!(stream.config.last_significant_x, 0);
    assert_eq!(stream.config.last_significant_y, 0);
    assert_eq!(
        stream.symbols,
        vec![
            VvcResidualCabacSymbol::LastSigCoeffXPrefix {
                bin_idx: 0,
                bin: false
            },
            VvcResidualCabacSymbol::LastSigCoeffYPrefix {
                bin_idx: 0,
                bin: false
            },
            VvcResidualCabacSymbol::AbsLevelGtxFlag {
                x: 0,
                y: 0,
                gtx_idx: 0,
                greater_than: true
            },
            VvcResidualCabacSymbol::ParLevelFlag {
                x: 0,
                y: 0,
                par_level: true
            },
            VvcResidualCabacSymbol::AbsLevelGtxFlag {
                x: 0,
                y: 0,
                gtx_idx: 1,
                greater_than: false
            },
            VvcResidualCabacSymbol::CoeffSignFlag {
                x: 0,
                y: 0,
                negative: true
            },
        ]
    );

    let zero = VvcResidualCabacSymbolStream::luma_dc_only(3, 3, 0, false);
    assert_eq!(zero.symbols.len(), 2);
    assert_eq!(
        zero.symbols.last(),
        Some(&VvcResidualCabacSymbol::LastSigCoeffYPrefix {
            bin_idx: 0,
            bin: false
        })
    );
}

#[test]
fn vvc_residual_symbol_stream_scales_dc_only_luma_tb_size() {
    let stream = VvcResidualCabacSymbolStream::luma_dc_only(5, 4, 1, false);
    assert_eq!(stream.config.log2_zo_tb_width, 5);
    assert_eq!(stream.config.log2_zo_tb_height, 4);
    assert_eq!(
        stream.symbols,
        vec![
            VvcResidualCabacSymbol::LastSigCoeffXPrefix {
                bin_idx: 0,
                bin: false
            },
            VvcResidualCabacSymbol::LastSigCoeffYPrefix {
                bin_idx: 0,
                bin: false
            },
            VvcResidualCabacSymbol::AbsLevelGtxFlag {
                x: 0,
                y: 0,
                gtx_idx: 0,
                greater_than: false
            },
            VvcResidualCabacSymbol::CoeffSignFlag {
                x: 0,
                y: 0,
                negative: false
            }
        ]
    );
}

#[test]
fn vvc_residual_symbol_stream_maps_large_dc_abs_remainder_by_spec_order() {
    let stream = VvcResidualCabacSymbolStream::luma_dc_only(3, 3, 16, true);
    assert!(stream
        .symbols
        .contains(&VvcResidualCabacSymbol::AbsLevelGtxFlag {
            x: 0,
            y: 0,
            gtx_idx: 1,
            greater_than: true
        }));
    assert!(stream
        .symbols
        .contains(&VvcResidualCabacSymbol::AbsRemainder {
            x: 0,
            y: 0,
            value: 6,
            rice_param: 0
        }));
    assert_eq!(
        stream.symbols.last(),
        Some(&VvcResidualCabacSymbol::CoeffSignFlag {
            x: 0,
            y: 0,
            negative: true
        })
    );
}

#[test]
fn vvc_residual_symbol_stream_can_be_derived_from_quantized_luma_block() {
    let black = quantize_vvc_4x4_luma_dc(vvc_solid_luma_8x8_transform_block(0));
    let stream = VvcResidualCabacSymbolStream::from_quantized_luma_dc(3, 3, black);
    assert_eq!(stream.pass1_state.abs_level_pass1_at(0, 0), 3);
    assert!(stream
        .symbols
        .contains(&VvcResidualCabacSymbol::AbsRemainder {
            x: 0,
            y: 0,
            value: 6,
            rice_param: 0
        }));
    assert_eq!(
        stream.symbols.last(),
        Some(&VvcResidualCabacSymbol::CoeffSignFlag {
            x: 0,
            y: 0,
            negative: true
        })
    );

    let white = quantize_vvc_4x4_luma_dc(vvc_solid_luma_8x8_transform_block(255));
    let white_stream = VvcResidualCabacSymbolStream::from_quantized_luma_dc(3, 3, white);
    assert_eq!(
        white_stream.symbols.last(),
        Some(&VvcResidualCabacSymbol::LastSigCoeffYPrefix {
            bin_idx: 0,
            bin: false
        })
    );
}

#[test]
fn vvc_residual_symbol_stream_emits_through_context_models() {
    let stream = VvcResidualCabacSymbolStream::luma_dc_only(3, 3, 2, true);
    let mut contexts = VvcCabacContexts::new();
    let initial_last_x0 = contexts.last_sig_coeff_x_prefix[3].state();
    let initial_abs0 = contexts.abs_level_gtx_flag[0].state();

    let mut cabac = VvcCabacEncoder::new();
    cabac.start();
    let mut residual =
        VvcResidualCabacEncoder::new(&mut contexts, vvc_test_slice_config().residual_options());
    stream.emit(&mut residual, &mut cabac);

    assert_ne!(contexts.last_sig_coeff_x_prefix[3].state(), initial_last_x0);
    assert_ne!(contexts.abs_level_gtx_flag[0].state(), initial_abs0);
}

#[test]
fn vvc_split_cu_flag_context_uses_spec_ctx_set_formula() {
    let root = VvcCodingTreeNode::root(64, 64, VvcTreeType::DualTreeLuma);
    assert_eq!(
        VvcSplitCtxInput {
            node: root,
            left: None,
            above: None,
            availability: VvcSplitAvailability::qt_only(true),
        }
        .split_cu_flag_ctx(),
        0
    );

    let child = root.qt_child(0);
    let full_availability = VvcSplitAvailability {
        can_no_split: true,
        can_qt: true,
        can_bt_horizontal: true,
        can_bt_vertical: true,
        can_tt_horizontal: true,
        can_tt_vertical: true,
    };
    assert_eq!(
        VvcSplitCtxInput {
            node: child,
            left: None,
            above: None,
            availability: full_availability,
        }
        .split_cu_flag_ctx(),
        6
    );
    assert_eq!(
        VvcSplitCtxInput {
            node: child,
            left: Some(VvcCodedNeighbour {
                width: 8,
                height: 8,
                qt_depth: 3,
            }),
            above: Some(VvcCodedNeighbour {
                width: 8,
                height: 8,
                qt_depth: 3,
            }),
            availability: full_availability,
        }
        .split_cu_flag_ctx(),
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
fn vvc_luma_split_context_uses_coded_neighbour_map() {
    let ctx = VvcPartitionCtx::luma(64, 64);
    let mut map = VvcCodedCuMap::default();
    let root = VvcCodingTreeNode::root(64, 64, VvcTreeType::DualTreeLuma);
    let top_left = root.qt_child(0).qt_child(0).qt_child(0);
    let top_right = VvcCodingTreeNode {
        x: 8,
        y: 0,
        width: 8,
        height: 8,
        cqt_depth: 3,
        mtt_depth: 0,
        implicit_mtt_depth: 0,
        tree_type: VvcTreeType::DualTreeLuma,
        split_history: [VvcPartSplit::Quad, VvcPartSplit::Quad],
    };
    let bottom_left = VvcCodingTreeNode {
        x: 0,
        y: 8,
        width: 8,
        height: 8,
        cqt_depth: 3,
        mtt_depth: 0,
        implicit_mtt_depth: 0,
        tree_type: VvcTreeType::DualTreeLuma,
        split_history: [VvcPartSplit::Quad, VvcPartSplit::Quad],
    };
    let lower_right = VvcCodingTreeNode {
        x: 8,
        y: 8,
        width: 8,
        height: 8,
        cqt_depth: 3,
        mtt_depth: 0,
        implicit_mtt_depth: 0,
        tree_type: VvcTreeType::DualTreeLuma,
        split_history: [VvcPartSplit::Quad, VvcPartSplit::Quad],
    };

    map.record_leaf(top_left);
    map.record_leaf(top_right);
    map.record_leaf(bottom_left);
    let input = ctx.split_ctx_input_from_luma_map(
        lower_right,
        VvcSplitAvailability {
            can_no_split: true,
            can_qt: false,
            can_bt_horizontal: true,
            can_bt_vertical: true,
            can_tt_horizontal: false,
            can_tt_vertical: false,
        },
        &map,
    );

    assert_eq!(
        input.left,
        Some(VvcCodedNeighbour {
            width: 8,
            height: 8,
            qt_depth: 3,
        })
    );
    assert_eq!(
        input.above,
        Some(VvcCodedNeighbour {
            width: 8,
            height: 8,
            qt_depth: 3,
        })
    );
}

#[test]
fn vvc_split_syntax_decision_follows_spec_bin_presence_order() {
    // ITU-T H.266 clause 7.3.11.4 split_cu_mode(): explicit split nodes code
    // split_cu_flag, split_qt_flag, MTT direction, then binary-vs-ternary only
    // when the corresponding alternatives are legal.
    let node = VvcCodingTreeNode::root(64, 64, VvcTreeType::DualTreeLuma).qt_child(0);
    let availability = VvcSplitAvailability {
        can_no_split: true,
        can_qt: true,
        can_bt_horizontal: true,
        can_bt_vertical: true,
        can_tt_horizontal: true,
        can_tt_vertical: true,
    };
    let input = VvcSplitCtxInput {
        node,
        left: None,
        above: None,
        availability,
    };
    let decision = VvcSplitSyntaxDecision::new(input, VvcPartSplit::HorizontalBinary);

    assert_eq!(decision.split_flag(), Some((6, true)));
    assert_eq!(decision.split_qt_flag(), Some((0, false)));
    assert_eq!(decision.mtt_vertical_flag(), Some((0, false)));
    assert_eq!(decision.mtt_binary_flag(), Some((1, true)));
}

#[test]
fn vvc_split_syntax_decision_models_implicit_boundary_bt() {
    // ITU-T H.266 clause 6.4.1 / split_cu_mode(): implicit boundary splits do
    // not code split_cu_flag; if QT and the implicit BT are both legal, only
    // split_qt_flag is coded before the BT direction is inferred.
    let node = VvcCodingTreeNode::root(64, 64, VvcTreeType::DualTreeLuma).qt_child(0);
    let availability = VvcSplitAvailability {
        can_no_split: true,
        can_qt: true,
        can_bt_horizontal: true,
        can_bt_vertical: true,
        can_tt_horizontal: true,
        can_tt_vertical: true,
    }
    .with_implicit_split(VvcPartSplit::HorizontalBinary);
    let input = VvcSplitCtxInput {
        node,
        left: None,
        above: None,
        availability,
    };
    let decision = VvcSplitSyntaxDecision::new(input, VvcPartSplit::HorizontalBinary);

    assert_eq!(decision.split_flag(), None);
    assert_eq!(decision.split_qt_flag(), Some((0, false)));
    assert_eq!(decision.mtt_vertical_flag(), None);
    assert_eq!(decision.mtt_binary_flag(), None);
}

#[test]
fn vvc_split_syntax_decision_omits_leaf_split_when_no_split_is_legal_only() {
    let node = VvcCodingTreeNode::root(4, 4, VvcTreeType::DualTreeLuma);
    let input = VvcSplitCtxInput {
        node,
        left: None,
        above: None,
        availability: VvcSplitAvailability {
            can_no_split: true,
            can_qt: false,
            can_bt_horizontal: false,
            can_bt_vertical: false,
            can_tt_horizontal: false,
            can_tt_vertical: false,
        },
    };
    let decision = VvcSplitSyntaxDecision::new(input, VvcPartSplit::None);

    assert_eq!(decision.split_flag(), None);
    assert_eq!(decision.split_qt_flag(), None);
    assert_eq!(decision.mtt_vertical_flag(), None);
    assert_eq!(decision.mtt_binary_flag(), None);
}

#[test]
fn vvc_split_qt_flag_context_uses_spec_depth_formula() {
    let root = VvcCodingTreeNode::root(64, 64, VvcTreeType::DualTreeLuma);
    assert_eq!(
        VvcSplitCtxInput {
            node: root,
            left: None,
            above: None,
            availability: VvcSplitAvailability::qt_only(true),
        }
        .split_qt_flag_ctx(),
        0
    );
    let child = root.qt_child(3).qt_child(3);
    assert_eq!(
        VvcSplitCtxInput {
            node: child,
            left: Some(VvcCodedNeighbour {
                width: 4,
                height: 4,
                qt_depth: 3,
            }),
            above: Some(VvcCodedNeighbour {
                width: 4,
                height: 4,
                qt_depth: 3,
            }),
            availability: VvcSplitAvailability::qt_only(true),
        }
        .split_qt_flag_ctx(),
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
        22
    );
}

#[test]
fn vvc_residual_sb_coded_context_keeps_regular_and_ts_paths_labelled() {
    let regular = VvcResidualPass1State::new(VvcResidualCtxConfig::luma_4x4_subset(3, 3));
    assert_eq!(regular.sb_coded_flag_ctx_inc(0, 0), 0);

    let mut chroma_config = VvcResidualCtxConfig::luma_4x4_subset(3, 3);
    chroma_config.component = VvcResidualComponent::ChromaCb;
    let chroma = VvcResidualPass1State::new(chroma_config);
    assert_eq!(chroma.sb_coded_flag_ctx_inc(0, 0), 2);

    let mut ts_config = VvcResidualCtxConfig::luma_4x4_subset(3, 3);
    ts_config.transform_skip = true;
    ts_config.ts_residual_coding_disabled = false;
    let mut transform_skip = VvcResidualPass1State::new(ts_config);
    transform_skip.set_sb_coded(0, 0, true);
    assert_eq!(transform_skip.sb_coded_flag_ctx_inc(1, 0), 5);
}

#[test]
fn vvc_residual_sig_coeff_context_uses_pass1_neighbour_state() {
    let mut state = VvcResidualPass1State::new(VvcResidualCtxConfig::luma_4x4_subset(3, 3));
    assert_eq!(state.sig_coeff_flag_ctx_inc(0, 0), 8);
    assert_eq!(state.sig_coeff_flag_ctx_inc(2, 1), 4);

    state.set_pass1_coeff(1, 0, 3, false);
    state.set_pass1_coeff(0, 1, 1, true);
    let stats = state.local_stats(0, 0);
    assert_eq!(
        stats,
        VvcResidualLocalStats {
            loc_num_sig: 2,
            loc_sum_abs_pass1: 4
        }
    );
    assert_eq!(state.sig_coeff_flag_ctx_inc(0, 0), 10);

    let mut chroma_config = VvcResidualCtxConfig::luma_4x4_subset(3, 3);
    chroma_config.component = VvcResidualComponent::ChromaCr;
    let chroma = VvcResidualPass1State::new(chroma_config);
    assert_eq!(chroma.sig_coeff_flag_ctx_inc(0, 0), 40);
}

#[test]
fn vvc_residual_level_contexts_follow_last_significant_position() {
    let mut state = VvcResidualPass1State::new(VvcResidualCtxConfig::luma_4x4_subset(3, 3));
    assert_eq!(state.par_level_flag_ctx_inc(3, 3), 0);
    assert_eq!(state.abs_level_gtx_flag_ctx_inc(3, 3, 0), 0);
    assert_eq!(state.abs_level_gtx_flag_ctx_inc(3, 3, 1), 32);
    assert_eq!(state.par_level_flag_ctx_inc(0, 0), 16);

    state.set_pass1_coeff(1, 0, 3, false);
    state.set_pass1_coeff(0, 1, 2, false);
    assert_eq!(state.par_level_flag_ctx_inc(0, 0), 19);

    let mut chroma_config = VvcResidualCtxConfig::luma_4x4_subset(1, 1);
    chroma_config.component = VvcResidualComponent::ChromaCb;
    let chroma = VvcResidualPass1State::new(chroma_config);
    assert_eq!(chroma.par_level_flag_ctx_inc(1, 1), 21);
    assert_eq!(chroma.par_level_flag_ctx_inc(0, 0), 27);
}

#[test]
fn vvc_residual_transform_skip_sign_context_is_separate_from_bypass_signs() {
    let mut config = VvcResidualCtxConfig::luma_4x4_subset(3, 3);
    config.transform_skip = true;
    config.ts_residual_coding_disabled = false;
    let mut state = VvcResidualPass1State::new(config);
    assert_eq!(state.coeff_sign_flag_ts_ctx_inc(0, 0), 0);

    state.set_pass1_coeff(0, 0, 1, false);
    state.set_pass1_coeff(1, 0, 1, false);
    assert_eq!(state.coeff_sign_flag_ts_ctx_inc(1, 1), 1);

    state.set_pass1_coeff(0, 1, 1, true);
    assert_eq!(state.coeff_sign_flag_ts_ctx_inc(1, 1), 0);
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
            luma_dc_abs_level: 0,
            luma_dc_negative: false,
            cb_dc_abs_level: 0,
            cb_dc_negative: false,
        };
        let ops = VvcCtuCabacOp::yuv420_ctu_partition(params);
        let chroma_nodes: Vec<_> = ops
            .iter()
            .filter_map(|op| match op {
                VvcCtuCabacOp::ChromaTree {
                    node,
                    visible_width,
                    visible_height,
                    chroma_sampling,
                } => {
                    assert_eq!(*visible_width, params.visible_chroma_width());
                    assert_eq!(*visible_height, params.visible_chroma_height());
                    assert_eq!(*chroma_sampling, params.chroma_sampling);
                    Some(*node)
                }
                _ => None,
            })
            .collect();
        assert_eq!(chroma_nodes, params.current_chroma_tree_nodes());
        assert!(ops
            .iter()
            .any(|op| matches!(op, VvcCtuCabacOp::LumaLeafWithSplitCtx { .. })));
    }
}

#[test]
fn vvc_ctu_cabac_generator_is_embedded_in_ctu_body() {
    let black = quantize_vvc_4x4_color(Vvc4x4SampledColor { y: 0, u: 0, v: 0 });
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
        params.luma_dc_abs_level,
        params.luma_dc_negative,
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
    let black = quantize_vvc_4x4_color(Vvc4x4SampledColor { y: 0, u: 0, v: 0 });
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
                    split_input,
                    ..
                } if node.x == 0
                    && node.y == 0
                    && node.width == 64
                    && node.height == 64
                    && !split_input.availability.can_no_split
            )),
            "{geometry:?} must not force an implicit root BT before max-BT-size permits it"
        );
        assert!(
            !ops.iter().any(|op| match op {
                VvcCtuCabacOp::BtSplit {
                    node,
                    split_input,
                    split,
                } if node.mtt_depth > 0 => {
                    VvcSplitSyntaxDecision::new(*split_input, *split)
                        .split_qt_flag()
                        .is_some()
                }
                _ => false,
            }),
            "{geometry:?} must not signal split_qt_flag below a BT split"
        );
    }
}

#[test]
fn vvc_current_chroma_tree_nodes_are_subsampling_derived() {
    for (chroma_sampling, expected_width, expected_height, expected_positions) in [
        (
            ChromaSampling::Cs420,
            16,
            16,
            vec![(0, 0), (16, 0), (0, 16), (16, 16)],
        ),
        (
            ChromaSampling::Cs422,
            16,
            32,
            vec![(0, 0), (16, 0), (0, 32), (16, 32)],
        ),
        (
            ChromaSampling::Cs444,
            32,
            32,
            vec![(0, 0), (32, 0), (0, 32), (32, 32)],
        ),
    ] {
        let params = VvcCtuPartitionParams {
            root_width: 64,
            root_height: 64,
            visible_width: 64,
            visible_height: 64,
            chroma_sampling,
            chroma_tu_count: 0,
            luma_dc_abs_level: 0,
            luma_dc_negative: false,
            cb_dc_abs_level: 0,
            cb_dc_negative: false,
        };
        let nodes = params.current_chroma_tree_nodes();
        assert_eq!(nodes.len(), expected_positions.len());
        for (node, (x, y)) in nodes.iter().zip(expected_positions) {
            assert_eq!((node.x, node.y), (x, y));
            assert_eq!((node.width, node.height), (expected_width, expected_height));
            assert_eq!(node.tree_type, VvcTreeType::DualTreeChroma);
            assert_eq!(node.split_history, [VvcPartSplit::Quad, VvcPartSplit::None]);
        }
    }

    let mono_params = VvcCtuPartitionParams {
        root_width: 64,
        root_height: 64,
        visible_width: 64,
        visible_height: 64,
        chroma_sampling: ChromaSampling::Monochrome,
        chroma_tu_count: 0,
        luma_dc_abs_level: 0,
        luma_dc_negative: false,
        cb_dc_abs_level: 0,
        cb_dc_negative: false,
    };
    assert!(mono_params.current_chroma_tree_nodes().is_empty());
}

#[test]
fn vvc_ctu_cabac_generator_handles_rectangular_64_sample_bodies() {
    let black = quantize_vvc_4x4_color(Vvc4x4SampledColor { y: 0, u: 0, v: 0 });
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
    let black = quantize_vvc_4x4_color(Vvc4x4SampledColor { y: 0, u: 0, v: 0 });
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
fn parses_vvc_black_4x4_two_frame_headers() {
    let bytes = vvc_black_yuv420p8_annex_b(VvcEncodeParams { frames: 2 }).unwrap();
    let infos = parse_annex_b_nal_units(&bytes).unwrap();
    let types: Vec<u8> = infos.iter().map(|info| info.nal_unit_type).collect();
    assert_eq!(types, vec![15, 16, 8, 9]);
    assert!(infos[2].payload_len > 0);
    assert!(infos[3].payload_len > 0);
    assert_eq!(
        infos[3].offset + 2 + infos[3].payload_len,
        bytes.len(),
        "two-frame stream should end at the second picture NAL payload boundary"
    );
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
    let infos = parse_annex_b_nal_units(&bytes).unwrap();
    let types: Vec<u8> = infos.iter().map(|info| info.nal_unit_type).collect();
    assert_eq!(types, vec![15, 16, 8]);
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
    let infos = parse_annex_b_nal_units(&bytes).unwrap();
    let types: Vec<u8> = infos.iter().map(|info| info.nal_unit_type).collect();
    assert_eq!(types, vec![15, 16, 8]);
    assert!(infos[0].payload_len > 0);
    assert!(infos[1].payload_len > 0);
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
        Vvc4x4SampledColor {
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
        Vvc4x4SampledColor {
            y: 64,
            u: 128,
            v: 192,
        }
    );
}

#[test]
fn vvc_bitstream_path_accepts_sampled_non_black_input() {
    let input = solid_yuv420p8(65, 128, 192, 1);
    let bytes = vvc_yuv420p8_annex_b_from_input(&input, VvcEncodeParams { frames: 1 }).unwrap();
    let infos = parse_annex_b_nal_units(&bytes).unwrap();
    let types: Vec<u8> = infos.iter().map(|info| info.nal_unit_type).collect();
    assert_eq!(types, vec![15, 16, 8]);
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
    let infos = parse_annex_b_nal_units(&bytes).unwrap();
    let types: Vec<u8> = infos.iter().map(|info| info.nal_unit_type).collect();
    assert_eq!(types, vec![15, 16, 8]);
    assert_ne!(bytes, transform_bytes);
    assert!(!bytes.windows(4).any(|window| window == b"FFPL"));
    assert!(!bytes.windows(4).any(|window| window == b"FFAC"));
}

#[test]
fn vvc_palette_444_syntax_uses_spec_single_entry_subset() {
    let geometry = VvcVideoGeometry {
        width: 16,
        height: 16,
    };
    let syntax = vvc_palette_444_single_entry_syntax(
        geometry,
        Vvc4x4SampledColor {
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
    let frame = Vvc4x4SampledFrame {
        geometry,
        format: Vvc4x4PictureFormat {
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
fn rejects_unsupported_vvc_frame_count() {
    assert!(vvc_black_yuv420p8_annex_b(VvcEncodeParams { frames: 0 }).is_err());
    assert!(vvc_black_yuv420p8_annex_b(VvcEncodeParams { frames: 3 }).is_err());
}

fn solid_yuv420p8(y: u8, u: u8, v: u8, frames: usize) -> Vec<u8> {
    let mut out = Vec::with_capacity(Picture::expected_len(8, 8, PixelFormat::Yuv420p8) * frames);
    for _ in 0..frames {
        out.extend(std::iter::repeat_n(y, 64));
        out.extend(std::iter::repeat_n(u, 16));
        out.extend(std::iter::repeat_n(v, 16));
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
