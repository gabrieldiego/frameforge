use super::*;

fn vvc_transform_block(dc_coeff: i16) -> Vvc4x4TransformBlock {
    Vvc4x4TransformBlock {
        dc_coeff,
        ac_coeffs: [0; 15],
    }
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
fn parses_vvc_black_4x4_one_frame_headers() {
    let bytes = vvc_black_yuv420p8_annex_b(VvcEncodeParams { frames: 1 }).unwrap();
    let infos = parse_annex_b_nal_units(&bytes).unwrap();
    let types: Vec<u8> = infos.iter().map(|info| info.nal_unit_type).collect();
    assert_eq!(types, vec![15, 16, 8]);
    assert_eq!(infos[0].payload_len, 31);
    assert_eq!(infos[1].payload_len, 14);
    assert!(infos[2].payload_len > 0);
    assert_eq!(
        infos[2].offset + 2 + infos[2].payload_len,
        bytes.len(),
        "single-frame stream should end at the IDR NAL payload boundary"
    );
}

#[test]
fn vvc_parameter_sets_are_generated_from_named_syntax() {
    assert_eq!(
        vvc_4x4_sps_payload(VvcVideoGeometry::four_by_four()),
        hex_bytes("000b020080004244eed501f446e884688424613628c5430680ab8fe0ac1020")
    );
    assert_eq!(
        vvc_4x4_pps_payload(VvcVideoGeometry::four_by_four()),
        hex_bytes("0002448a4200c7b2145945945880")
    );
}

#[test]
fn vvc_sps_can_signal_4x8_visible_geometry() {
    assert_eq!(
        vvc_4x4_sps_payload(VvcVideoGeometry {
            width: 4,
            height: 8,
        }),
        hex_bytes("000b020080004244ef5407d11ba211a2109184d8a3150c1a02ae3f82b04080")
    );
}

#[test]
fn vvc_sps_can_signal_8x4_visible_geometry() {
    assert_eq!(
        vvc_4x4_sps_payload(VvcVideoGeometry {
            width: 8,
            height: 4,
        }),
        hex_bytes("000b020080004244fb5407d11ba211a2109184d8a3150c1a02ae3f82b04080")
    );
}

#[test]
fn vvc_sps_can_signal_8x8_visible_geometry() {
    assert_eq!(
        vvc_4x4_sps_payload(VvcVideoGeometry {
            width: 8,
            height: 8,
        }),
        hex_bytes("000b020080004244fd501f446e884688424613628c5430680ab8fe0ac102")
    );
}

#[test]
fn vvc_parameter_sets_can_signal_16x16_visible_geometry() {
    let geometry = VvcVideoGeometry {
        width: 16,
        height: 16,
    };
    assert_eq!(
        vvc_4x4_sps_payload(geometry),
        hex_bytes("000b0200800041108fd501f446e884688424613628c5430680ab8fe0ac1020")
    );
    assert_eq!(
        vvc_4x4_pps_payload(geometry),
        hex_bytes("00011088a4200c7b214594594588")
    );
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
    let geometry = VvcVideoGeometry {
        width: 64,
        height: 64,
    };
    assert_eq!(
        vvc_4x4_sps_payload(geometry),
        hex_bytes("000b020080004041020fd501f446e884688424613628c5430680ab8fe0ac1020")
    );
    assert_eq!(
        vvc_4x4_pps_payload(geometry),
        hex_bytes("0000410208a4200c7b214594594588")
    );
}

#[test]
fn vvc_slice_header_is_generated_before_cabac_tokens() {
    let black = quantize_vvc_4x4_color(Vvc4x4SampledColor { y: 0, u: 0, v: 0 });
    let geometry = VvcVideoGeometry::four_by_four();
    let idr = vvc_4x4_slice_payload(Vvc4x4PictureKind::Idr, geometry, black);
    let cra = vvc_4x4_slice_payload(Vvc4x4PictureKind::Cra, geometry, black);
    assert!(idr.starts_with(&hex_bytes("c40070")));
    assert!(cra.starts_with(&hex_bytes("c40478")));
    assert!(idr.len() > 3);
    assert!(cra.len() > 3);
}

#[test]
fn vvc_solid_luma_transform_generates_dc_only() {
    assert_eq!(transform_vvc_4x4_luma([0; 16]), vvc_transform_block(-114));
    assert_eq!(transform_vvc_4x4_luma([64; 16]), vvc_transform_block(-50));
    assert_eq!(transform_vvc_4x4_luma([114; 16]), vvc_transform_block(0));
}

#[test]
fn vvc_luma_transform_dc_uses_all_samples() {
    let mut samples = [64; 16];
    samples[3] = 255;
    let mut ac_coeffs = [-12; 15];
    ac_coeffs[2] = 179;
    assert_eq!(
        transform_vvc_4x4_luma(samples),
        Vvc4x4TransformBlock {
            dc_coeff: -38,
            ac_coeffs
        }
    );
}

#[test]
fn vvc_luma_dc_quantization_matches_existing_ladder() {
    let black = quantize_vvc_4x4_luma_dc(transform_vvc_4x4_luma([0; 16]));
    assert_eq!(black, vvc_quantized_block(-114, 16));

    let mid = quantize_vvc_4x4_luma_dc(transform_vvc_4x4_luma([65; 16]));
    assert_eq!(mid, vvc_quantized_block(-50, 7));

    let white = quantize_vvc_4x4_luma_dc(transform_vvc_4x4_luma([255; 16]));
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
fn vvc_frame_quantization_uses_all_luma_samples_for_dc() {
    let mut luma = [64; 256];
    luma[3] = 255;
    let mut ac_tokens = [0x61; 15];
    ac_tokens[2] = 0x48;
    assert_eq!(
        quantize_vvc_4x4_frame(Vvc4x4SampledFrame {
            geometry: VvcVideoGeometry::four_by_four(),
            format: Vvc4x4PictureFormat {
                chroma_sampling: ChromaSampling::Cs420,
                bit_depth: SampleBitDepth::Eight,
            },
            luma: luma.to_vec(),
            cb: vec![9; 4],
            cr: vec![7; 4],
            chroma_len: 4,
        }),
        Vvc4x4QuantizedColor {
            y: 78,
            u: 8,
            v: 8,
            luma_rem: 5,
            luma_ac_tokens: ac_tokens,
            second_luma_rem: 5,
            second_luma_ac_tokens: ac_tokens,
            luma_tu_remainders: [5; MAX_VVC_LUMA_TUS],
            luma_tu_ac0_tokens: [0x61; MAX_VVC_LUMA_TUS],
            luma_tu_count: 1,
            cb_rem: 15,
            cr_rem: 15,
        }
    );
}

#[test]
fn vvc_residual_path_reads_first_implemented_cb_by_geometry_stride() {
    let luma: Vec<u8> = (0..256).map(|sample| sample as u8).collect();
    let frame = Vvc4x4SampledFrame {
        geometry: VvcVideoGeometry {
            width: 16,
            height: 16,
        },
        format: Vvc4x4PictureFormat {
            chroma_sampling: ChromaSampling::Cs420,
            bit_depth: SampleBitDepth::Eight,
        },
        luma,
        cb: vec![0; 64],
        cr: vec![0; 64],
        chroma_len: 64,
    };
    assert_eq!(
        first_residual_luma_block(&frame),
        [0, 1, 2, 3, 16, 17, 18, 19, 32, 33, 34, 35, 48, 49, 50, 51]
    );
}

#[test]
fn vvc_residual_path_juxtaposes_second_4x4_tu_by_geometry() {
    let luma: Vec<u8> = (0..256).map(|sample| sample as u8).collect();
    let wide = Vvc4x4SampledFrame {
        geometry: VvcVideoGeometry {
            width: 16,
            height: 8,
        },
        format: Vvc4x4PictureFormat {
            chroma_sampling: ChromaSampling::Cs420,
            bit_depth: SampleBitDepth::Eight,
        },
        luma: luma[..128].to_vec(),
        cb: vec![0; 32],
        cr: vec![0; 32],
        chroma_len: 32,
    };
    assert_eq!(
        second_residual_luma_block(&wide),
        Some([4, 5, 6, 7, 20, 21, 22, 23, 36, 37, 38, 39, 52, 53, 54, 55])
    );

    let tall = Vvc4x4SampledFrame {
        geometry: VvcVideoGeometry {
            width: 4,
            height: 8,
        },
        format: Vvc4x4PictureFormat {
            chroma_sampling: ChromaSampling::Cs420,
            bit_depth: SampleBitDepth::Eight,
        },
        luma: (0..32).map(|sample| sample as u8).collect(),
        cb: vec![0; 8],
        cr: vec![0; 8],
        chroma_len: 8,
    };
    assert_eq!(
        second_residual_luma_block(&tall),
        Some([16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31])
    );

    let single = Vvc4x4SampledFrame::solid(Vvc4x4SampledColor { y: 0, u: 0, v: 0 });
    assert_eq!(second_residual_luma_block(&single), None);
}

#[test]
fn vvc_frame_quantization_builds_full_64x64_luma_tu_metadata() {
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
    assert_eq!(color.luma_tu_count, 256);
    assert!(color.luma_tu_remainders[..color.luma_tu_count]
        .iter()
        .all(|rem| *rem == 7));
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
    write_vvc_coding_tree_entropy(&mut writer, geometry, black);
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
            !vvc_cabac_bits(geometry, black).is_empty(),
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
        black
    )
    .is_empty());
    assert!(!vvc_cabac_bits(
        VvcVideoGeometry {
            width: 64,
            height: 64
        },
        black
    )
    .is_empty());
    assert!(!vvc_cabac_bits(
        VvcVideoGeometry {
            width: 8,
            height: 8
        },
        black
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
            luma_leaf_count: 1,
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
            luma_leaf_count: 52,
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
            luma_leaf_count: 64,
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
            root_width: 32,
            root_height: 32,
            visible_width: 32,
            visible_height: 32,
            chroma_sampling: ChromaSampling::Cs420,
            luma_leaf_count: 1,
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
            root_width: 16,
            root_height: 16,
            visible_width: 16,
            visible_height: 16,
            chroma_sampling: ChromaSampling::Cs420,
            luma_leaf_count: 1,
            chroma_tu_count: 4,
            luma_dc_abs_level: 16,
            luma_dc_negative: true,
            cb_dc_abs_level: 16,
            cb_dc_negative: true,
        })
    );
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

    let mut disabled = VvcResidualCabacEncoder::new(
        &mut contexts,
        VvcResidualCabacOptions::current_intra_subset(),
    );
    disabled.emit_transform_skip_flag(&mut cabac, VvcResidualComponent::Luma, false);
    disabled.emit_mts_idx_zero(&mut cabac);
    disabled.emit_current_unused_tool_placeholders();
    assert!(cabac.bits.is_empty());

    let mut contexts = VvcCabacContexts::new();
    let mut cabac = VvcCabacEncoder::new();
    cabac.start();
    let mut enabled_options = VvcResidualCabacOptions::current_intra_subset();
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
    let mut residual = VvcResidualCabacEncoder::new(
        &mut contexts,
        VvcResidualCabacOptions::current_intra_subset(),
    );

    residual.emit_last_sig_coeff_prefixes_4x4(&mut cabac, VvcResidualComponent::Luma, 3, 0);
    residual.emit_sb_coded_flag(&mut cabac, &state, 0, 0, true);
    residual.emit_sig_coeff_flag(&mut cabac, &state, 0, 0, true);
    residual.emit_par_level_flag(&mut cabac, &state, 3, 3, false);
    residual.emit_abs_level_gtx_flag(&mut cabac, &state, 3, 3, 1, false);
    residual.emit_coeff_sign_flag(&mut cabac, &state, 3, 3, true);

    assert_ne!(contexts.last_sig_coeff_x_prefix[0].state(), initial_last_x0);
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
    let mut residual = VvcResidualCabacEncoder::new(
        &mut contexts,
        VvcResidualCabacOptions::current_intra_subset(),
    );
    residual.emit_coeff_sign_flag(&mut cabac, &state, 0, 0, true);

    assert_ne!(contexts.coeff_sign_flag[0].state(), initial_sign0);
}

#[test]
fn vvc_residual_symbol_stream_names_dc_only_luma_subset() {
    let stream = VvcResidualCabacSymbolStream::luma_4x4_dc_only(3, true);
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

    let zero = VvcResidualCabacSymbolStream::luma_4x4_dc_only(0, false);
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
    let stream = VvcResidualCabacSymbolStream::luma_4x4_dc_only(16, true);
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
    let black = quantize_vvc_4x4_luma_dc(transform_vvc_4x4_luma([0; 16]));
    let stream = VvcResidualCabacSymbolStream::from_quantized_luma_4x4_dc(black);
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

    let white = quantize_vvc_4x4_luma_dc(transform_vvc_4x4_luma([255; 16]));
    let white_stream = VvcResidualCabacSymbolStream::from_quantized_luma_4x4_dc(white);
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
    let stream = VvcResidualCabacSymbolStream::luma_4x4_dc_only(2, true);
    let mut contexts = VvcCabacContexts::new();
    let initial_last_x0 = contexts.last_sig_coeff_x_prefix[0].state();
    let initial_abs0 = contexts.abs_level_gtx_flag[0].state();

    let mut cabac = VvcCabacEncoder::new();
    cabac.start();
    let mut residual = VvcResidualCabacEncoder::new(
        &mut contexts,
        VvcResidualCabacOptions::current_intra_subset(),
    );
    stream.emit(&mut residual, &mut cabac);

    assert_ne!(contexts.last_sig_coeff_x_prefix[0].state(), initial_last_x0);
    assert_ne!(contexts.abs_level_gtx_flag[0].state(), initial_abs0);
}

#[test]
fn vvc_split_cu_flag_context_uses_spec_ctx_set_formula() {
    assert_eq!(VvcSplitCtxInput::qt_only_root().split_cu_flag_ctx(), 0);
    assert_eq!(
        VvcSplitCtxInput::full_child_without_smaller_neighbours().split_cu_flag_ctx(),
        6
    );
    assert_eq!(
        VvcSplitCtxInput {
            available_left: true,
            available_above: true,
            condition_left: true,
            condition_above: true,
            allow_bt_vertical: true,
            allow_bt_horizontal: true,
            allow_tt_vertical: true,
            allow_tt_horizontal: true,
            allow_qt: true,
        }
        .split_cu_flag_ctx(),
        8
    );
}

#[test]
fn vvc_split_qt_flag_context_uses_spec_depth_formula() {
    let root = VvcCodingTreeNode::root(64, 64, VvcTreeType::DualTreeLuma);
    assert_eq!(
        VvcQtSplitCtxInput::from_node_without_deeper_neighbours(root).split_qt_flag_ctx(),
        0
    );
    assert_eq!(
        VvcQtSplitCtxInput {
            available_left: true,
            available_above: true,
            left_deeper_qt: true,
            above_deeper_qt: true,
            cqt_depth: 2,
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
fn vvc_ctu_cabac_generator_names_64x64_operation_sequence() {
    let params = VvcCtuPartitionParams {
        root_width: 64,
        root_height: 64,
        visible_width: 64,
        visible_height: 64,
        chroma_sampling: ChromaSampling::Cs420,
        luma_leaf_count: 1,
        chroma_tu_count: 64,
        luma_dc_abs_level: 0,
        luma_dc_negative: false,
        cb_dc_abs_level: 0,
        cb_dc_negative: false,
    };
    let root = VvcCodingTreeNode::root(64, 64, VvcTreeType::DualTreeLuma);
    assert_eq!(
        VvcCtuCabacOp::yuv420_ctu_partition(params),
        vec![
            VvcCtuCabacOp::QtSplit {
                node: root,
                split_ctx: VvcSplitCtxInput::qt_only_root().split_cu_flag_ctx(),
                write_split_flag: false,
                write_qt_flag: false,
                qt_ctx: VvcQtSplitCtxInput::from_node_without_deeper_neighbours(root)
                    .split_qt_flag_ctx()
            },
            VvcCtuCabacOp::LumaLeafWithSplitCtx {
                node: root,
                split_ctx: VvcSplitCtxInput::qt_only_root().split_cu_flag_ctx()
            },
            VvcCtuCabacOp::ChromaTree {
                node: params.ctu_chroma_root(),
                visible_width: params.visible_chroma_width(),
                visible_height: params.visible_chroma_height()
            }
        ]
    );
}

#[test]
fn vvc_ctu_cabac_generator_names_rectangular_64_sample_operation_sequence() {
    let params = VvcCtuPartitionParams {
        root_width: 64,
        root_height: 64,
        visible_width: 64,
        visible_height: 32,
        chroma_sampling: ChromaSampling::Cs420,
        luma_leaf_count: 52,
        chroma_tu_count: 32,
        luma_dc_abs_level: 0,
        luma_dc_negative: false,
        cb_dc_abs_level: 0,
        cb_dc_negative: false,
    };
    let root = VvcCodingTreeNode::root(64, 64, VvcTreeType::DualTreeLuma);
    let ops = VvcCtuCabacOp::yuv420_ctu_partition(params);
    assert_eq!(
        ops.first(),
        Some(&VvcCtuCabacOp::QtSplit {
            node: root,
            split_ctx: VvcSplitCtxInput::qt_only_root().split_cu_flag_ctx(),
            write_split_flag: false,
            write_qt_flag: false,
            qt_ctx: VvcQtSplitCtxInput::from_node_without_deeper_neighbours(root)
                .split_qt_flag_ctx(),
        })
    );
    assert_eq!(
        ops.last(),
        Some(&VvcCtuCabacOp::ChromaTree {
            node: params.ctu_chroma_root(),
            visible_width: params.visible_chroma_width(),
            visible_height: params.visible_chroma_height(),
        })
    );
    assert_eq!(
        ops.iter()
            .filter(|op| {
                matches!(
                    op,
                    VvcCtuCabacOp::LumaLeaf { .. } | VvcCtuCabacOp::LumaLeafWithSplitCtx { .. }
                )
            })
            .count(),
        52
    );
    assert!(ops.iter().any(|op| matches!(
        op,
        VvcCtuCabacOp::BtSplit {
            node: VvcCodingTreeNode {
                width: 8,
                height: 8,
                ..
            },
            vertical: true,
            write_qt_flag: false,
            write_binary_flag: false,
            ..
        }
    )));
    assert!(ops.iter().any(|op| matches!(
        op,
        VvcCtuCabacOp::BtSplit {
            node: VvcCodingTreeNode {
                width: 4,
                height: 8,
                ..
            },
            vertical: false,
            write_qt_flag: false,
            write_binary_flag: false,
            ..
        }
    )));
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
    let via_body = vvc_ctu_partition_cabac_bits(params);

    let mut manual = VvcCabacEncoder::new();
    let mut ctu = VvcCtuCabacGenerator::new(
        params.luma_dc_abs_level,
        params.luma_dc_negative,
        params.cb_dc_abs_level,
        params.cb_dc_negative,
    );
    manual.start();
    for op in VvcCtuCabacOp::yuv420_ctu_partition(params) {
        ctu.emit(&mut manual, op);
    }
    manual.encode_bin_trm(true);
    assert_eq!(via_body, manual.finish());
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
        let bits = vvc_ctu_partition_cabac_bits(params);
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
            vvc_cabac_bits(geometry, black),
            vvc_ctu_partition_cabac_bits(params)
        );
    }
}

#[test]
fn vvc_luma_partition_plan_splits_64x64_into_32x32_leaves() {
    let plan = vvc_luma_partition_plan(VvcVideoGeometry {
        width: 64,
        height: 64,
    });
    assert_eq!(
        plan,
        vec![
            VvcLumaPartitionStep::QuadSplit {
                x: 0,
                y: 0,
                width: 64,
                height: 64
            },
            VvcLumaPartitionStep::Leaf {
                x: 0,
                y: 0,
                width: 32,
                height: 32
            },
            VvcLumaPartitionStep::Leaf {
                x: 32,
                y: 0,
                width: 32,
                height: 32
            },
            VvcLumaPartitionStep::Leaf {
                x: 0,
                y: 32,
                width: 32,
                height: 32
            },
            VvcLumaPartitionStep::Leaf {
                x: 32,
                y: 32,
                width: 32,
                height: 32
            },
        ]
    );
    assert_eq!(
        vvc_luma_partition_plan(VvcVideoGeometry {
            width: 32,
            height: 16
        }),
        vec![VvcLumaPartitionStep::Leaf {
            x: 0,
            y: 0,
            width: 32,
            height: 16
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
    let input = vec![0; Picture::expected_len(4, 4, PixelFormat::Yuv420p8) * 2];
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
    assert_eq!(infos[0].payload_len, 29);
    assert_eq!(infos[1].payload_len, 14);
}

#[test]
fn vvc_input_path_samples_first_yuv_values() {
    let mut input = solid_yuv420p8(64, 128, 192, 2);
    input[3] = 255;
    input[17] = 0;
    input[21] = 1;
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
    let second_frame = Picture::expected_len(4, 4, PixelFormat::Yuv420p8);
    input[second_frame] = 1;
    input[second_frame + 16] = 2;
    input[second_frame + 20] = 3;
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
    for (format, chroma_samples) in [(PixelFormat::Yuv422p8, 8), (PixelFormat::Yuv422p10, 8)] {
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
    let input = solid_yuv_planar_high(65, 128, 192, 8, 16, 1);
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
    input[17] = 0;
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
    let mut out = Vec::with_capacity(Picture::expected_len(4, 4, PixelFormat::Yuv420p8) * frames);
    for _ in 0..frames {
        out.extend(std::iter::repeat_n(y, 16));
        out.extend(std::iter::repeat_n(u, 4));
        out.extend(std::iter::repeat_n(v, 4));
    }
    out
}

fn solid_yuv420p_high(y: u8, u: u8, v: u8, bit_depth: u8, frames: usize) -> Vec<u8> {
    solid_yuv_planar_high(y, u, v, bit_depth, 4, frames)
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
            .repeat(16)
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
