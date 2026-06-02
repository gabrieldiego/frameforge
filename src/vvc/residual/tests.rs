use super::super::*;
use super::*;
use crate::picture::{ChromaSampling, SampleBitDepth};

fn vvc_test_slice_config() -> VvcSliceSyntaxConfig {
    VvcSliceSyntaxConfig::yuv420_residual()
}

fn vvc_transform_block(dc_coeff: i16) -> VvcTransformBlock {
    VvcTransformBlock {
        dc_coeff,
        ac_coeffs: [0; 15],
    }
}

fn vvc_luma_8x8_transform_block(samples: [u8; 64]) -> VvcTransformBlock {
    let transform = transform_vvc_tu(VvcTransformComponent::Luma, 8, 8, &samples);
    vvc_transform_block(transform.dc_coeff)
}

fn vvc_solid_luma_8x8_transform_block(sample: u8) -> VvcTransformBlock {
    vvc_luma_8x8_transform_block([sample; 64])
}

fn vvc_quantized_block(
    reconstructed_dc_coeff: i16,
    abs_remainder: u8,
) -> VvcQuantizedTransformBlock {
    VvcQuantizedTransformBlock {
        reconstructed_dc_coeff,
        reconstructed_ac_coeffs: [0; 15],
        abs_remainder,
        ac_tokens: [0x40; 15],
    }
}

fn vvc_quantized_color_with_chroma(
    y: u8,
    luma_rem: u8,
    chroma: u8,
    chroma_residual: u8,
) -> VvcQuantizedColor {
    VvcQuantizedColor {
        y,
        u: chroma,
        v: chroma,
        luma_rem,
        luma_ac_levels: [0; 15],
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
    let black = quantize_vvc_luma_dc(vvc_solid_luma_8x8_transform_block(0));
    assert_eq!(black, vvc_quantized_block(-114, 16));

    let mid = quantize_vvc_luma_dc(vvc_solid_luma_8x8_transform_block(65));
    assert_eq!(mid, vvc_quantized_block(-50, 7));

    let white = quantize_vvc_luma_dc(vvc_solid_luma_8x8_transform_block(255));
    assert_eq!(white, vvc_quantized_block(0, 0));
}

#[test]
fn vvc_inverse_transform_reconstructs_solid_luma_block() {
    let quantized = vvc_quantized_block(-50, 7);
    assert_eq!(
        inverse_transform_vvc_luma_dc(quantized),
        VvcReconstructedLumaBlock { samples: [64; 16] }
    );
}

#[test]
fn vvc_color_quantization_uses_inverse_transform_reconstruction() {
    assert_eq!(
        quantize_vvc_color(VvcSampledColor { y: 65, u: 9, v: 7 }),
        vvc_quantized_color_with_chroma(64, 7, 8, 15)
    );
}

#[test]
fn vvc_frame_quantization_uses_anchor_tu_samples_for_dc() {
    let mut luma = [0; 64];
    luma[3] = 255;
    let ac_tokens = [0x40; 15];
    assert_eq!(
        quantize_vvc_frame(VvcSampledFrame {
            geometry: VvcVideoGeometry {
                width: 8,
                height: 8,
            },
            format: VvcPictureFormat {
                chroma_sampling: ChromaSampling::Cs420,
                bit_depth: SampleBitDepth::Eight,
            },
            luma: luma.to_vec(),
            cb: vec![9; 16],
            cr: vec![7; 16],
            chroma_len: 16,
        }),
        VvcQuantizedColor {
            y: 7,
            u: 8,
            v: 8,
            luma_rem: 15,
            luma_ac_levels: [0; 15],
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
    let frame = VvcSampledFrame {
        geometry: VvcVideoGeometry {
            width: 64,
            height: 64,
        },
        format: VvcPictureFormat {
            chroma_sampling: ChromaSampling::Cs420,
            bit_depth: SampleBitDepth::Eight,
        },
        luma: vec![64; 64 * 64],
        cb: vec![128; 32 * 32],
        cr: vec![192; 32 * 32],
        chroma_len: 32 * 32,
    };
    let color = quantize_vvc_frame(frame);
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
            width: 8,
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
            height: 8,
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
    assert_eq!(quantize_vvc_chroma(0, 0), 16);
    assert_eq!(reconstruct_vvc_chroma(16), 0);
    assert_eq!(quantize_vvc_chroma_sample(128), 0);
    assert_eq!(quantize_vvc_chroma(128, 192), 0);
    assert_eq!(reconstruct_vvc_chroma(0), 128);
}

#[test]
fn vvc_inverse_transform_reconstructs_quantized_ac_coefficients() {
    let mut block = vvc_quantized_block(-36, 5);
    block.reconstructed_ac_coeffs[2] = 128;
    block.ac_tokens[2] = 0x48;
    assert_eq!(inverse_transform_vvc_luma_dc(block).samples[3], 206);
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
    let black = quantize_vvc_luma_dc(vvc_solid_luma_8x8_transform_block(0));
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

    let white = quantize_vvc_luma_dc(vvc_solid_luma_8x8_transform_block(255));
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
fn vvc_residual_ac_symbol_stream_uses_spec_context_derivations() {
    let mut coeffs = vec![0; 64];
    coeffs[0] = 3;
    coeffs[1] = -2;
    let stream = VvcResidualCabacSymbolStream::luma_coefficients(3, 3, &coeffs);

    assert_eq!(stream.config.last_significant_x, 1);
    assert_eq!(stream.config.last_significant_y, 0);
    assert!(stream
        .symbols
        .contains(&VvcResidualCabacSymbol::SigCoeffFlag {
            x: 0,
            y: 0,
            significant: true,
        }));
    assert!(stream
        .symbols
        .contains(&VvcResidualCabacSymbol::AbsLevelGtxFlag {
            x: 1,
            y: 0,
            gtx_idx: 0,
            greater_than: true,
        }));
    assert!(stream
        .symbols
        .contains(&VvcResidualCabacSymbol::CoeffSignFlag {
            x: 1,
            y: 0,
            negative: true,
        }));

    // H.266 9.3.4.2.7 through 9.3.4.2.9: for the DC coefficient, the
    // non-zero AC neighbour at (1, 0) contributes to locNumSig and
    // locSumAbsPass1 before deriving sig/par/abs contexts.
    assert_eq!(stream.pass1_state.sig_coeff_flag_ctx_inc(0, 0), 9);
    assert_eq!(stream.pass1_state.par_level_flag_ctx_inc(0, 0), 17);
    assert_eq!(stream.pass1_state.abs_level_gtx_flag_ctx_inc(0, 0, 1), 49);
    assert_eq!(VvcCabacContext::SigCoeffFlag(9).init_value(), 37);
    assert_eq!(VvcCabacContext::ParLevelFlag(17).init_value(), 42);
    assert_eq!(VvcCabacContext::AbsLevelGtxFlag(49).init_value(), 19);

    let mut contexts = VvcCabacContexts::new();
    let mut cabac = VvcCabacEncoder::new();
    cabac.start();
    let mut residual =
        VvcResidualCabacEncoder::new(&mut contexts, vvc_test_slice_config().residual_options());
    stream.emit(&mut residual, &mut cabac);
    assert!(cabac.dump_symbols.iter().any(|symbol| symbol.kind == 3));
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
