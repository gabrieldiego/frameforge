use super::super::*;
use super::*;
use crate::picture::{ChromaSampling, SampleBitDepth};

fn vvc_test_slice_config() -> VvcSliceSyntaxConfig {
    VvcSliceSyntaxConfig::yuv420_residual()
}

fn vvc_luma_coefficients(width: usize, height: usize, entries: &[(usize, i16)]) -> Vec<i16> {
    let mut coeffs = vec![0; width * height];
    for (index, level) in entries {
        coeffs[*index] = *level;
    }
    coeffs
}

#[test]
fn vvc_solid_luma_8x8_transform_has_zero_ac() {
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
    let transform = transform_vvc_tu(VvcTransformComponent::Luma, 8, 8, &samples);
    assert_eq!(transform.dc_coeff, -47);
    assert_eq!(transform.ac_coeffs[2], 188);
    assert!(transform
        .ac_coeffs
        .iter()
        .enumerate()
        .filter(|(idx, _)| *idx != 2)
        .all(|(_, coeff)| *coeff == -3));
}

#[test]
fn vvc_transform_accepts_8x8_luma_and_4x4_chroma_tus() {
    let mut luma = vec![32; 8 * 8];
    luma[7] = 255;
    let luma_transform = transform_vvc_tu(VvcTransformComponent::Luma, 8, 8, &luma);
    assert_eq!(luma_transform.dc_coeff, -79);
    assert_eq!(luma_transform.ac_coeffs[6], 220);

    let mut cb = vec![128; 4 * 4];
    cb[5] = 0;
    let cb_transform = transform_vvc_tu(VvcTransformComponent::ChromaCb, 4, 4, &cb);
    assert_eq!(cb_transform.dc_coeff, -8);
    assert_eq!(cb_transform.ac_coeffs[4], -120);
}

#[test]
fn vvc_luma_residual_quantization_reconstructs_solid_residual() {
    let residuals = vec![-64; 8 * 8];
    let quantized = quantize_vvc_luma_residual_greedy(&residuals, 8, 8);
    assert!(quantized.reconstructed_dc_coeff < 0);
    assert!(quantized
        .reconstructed_ac_coeffs
        .iter()
        .all(|level| *level == 0));
    let mut levels = vec![0; 8 * 8];
    levels[0] = quantized.reconstructed_dc_coeff;
    let reconstructed = inverse_transform_vvc_luma_residual_levels(8, 8, &levels);
    let max_error = reconstructed
        .iter()
        .zip(residuals)
        .map(|(a, b)| (*a - b).abs())
        .max()
        .unwrap();
    assert!(max_error <= 2);
}

#[test]
fn vvc_color_quantization_uses_inverse_transform_reconstruction() {
    let color = quantize_vvc_color(VvcSampledColor { y: 65, u: 9, v: 7 });
    assert_eq!(color.u, 8);
    assert_eq!(color.v, 8);
    assert_eq!(color.cb_rem, 15);
    assert_eq!(color.cr_rem, 15);
    assert_eq!(color.luma_tu_count, 1);
    assert!(color.luma_tu_negative[0]);
    assert!(color.y.abs_diff(65) <= 2);
}

#[test]
fn vvc_frame_quantization_uses_leaf_samples_for_coefficients() {
    let mut luma = [0; 64];
    luma[3] = 255;
    let color = quantize_vvc_frame(VvcSampledFrame {
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
    });
    assert_eq!(color.luma_tu_count, 1);
    assert!(color.luma_tu_remainders[0] > 0);
    assert!(color.luma_tu_ac_levels[0].iter().any(|level| *level != 0));
    assert_eq!(color.cb_rem, 15);
    assert_eq!(color.cr_rem, 15);
}

#[test]
fn vvc_frame_quantization_builds_per_leaf_luma_tu_metadata() {
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
    assert_eq!(color.luma_tu_count, 64);
    assert!(color.luma_tu_remainders[0] > 0);
    assert_eq!(color.luma_tu_ac_levels[0], [0; VVC_LUMA_AC_COEFFS_PER_TU]);
}

#[test]
fn vvc_420_chroma_dc_residual_preserves_decoder_visible_color() {
    let frame = VvcSampledFrame {
        geometry: VvcVideoGeometry {
            width: 16,
            height: 16,
        },
        format: VvcPictureFormat {
            chroma_sampling: ChromaSampling::Cs420,
            bit_depth: SampleBitDepth::Eight,
        },
        luma: vec![128; 16 * 16],
        cb: vec![64; 8 * 8],
        cr: vec![192; 8 * 8],
        chroma_len: 8 * 8,
    };
    let quantized = quantize_vvc_frame(frame.clone());
    assert_eq!(quantized.chroma_tu_count, 4);
    assert!(quantized.cb_tu_dc_levels[0] < 0);
    assert!(quantized.cr_tu_dc_levels[0] > 0);

    let params = vvc_ctu_partition_params(frame.geometry, quantized).expect("16x16 params");
    let recon = reconstruct_vvc_residual_frame(&frame, quantized, params);
    let chroma = &recon[16 * 16..];
    assert!(chroma.iter().any(|sample| *sample != 128));
    assert!(chroma[..8 * 8]
        .iter()
        .all(|sample| sample.abs_diff(64) <= 3));
    assert!(chroma[8 * 8..]
        .iter()
        .all(|sample| sample.abs_diff(192) <= 3));
}

#[test]
fn vvc_420_chroma_dc_residual_predicts_from_prior_chroma_leaves() {
    let frame = VvcSampledFrame {
        geometry: VvcVideoGeometry {
            width: 64,
            height: 48,
        },
        format: VvcPictureFormat {
            chroma_sampling: ChromaSampling::Cs420,
            bit_depth: SampleBitDepth::Eight,
        },
        luma: vec![128; 64 * 48],
        cb: vec![64; 32 * 24],
        cr: vec![192; 32 * 24],
        chroma_len: 32 * 24,
    };
    let quantized = quantize_vvc_frame(frame.clone());
    assert_eq!(quantized.chroma_tu_count, 48);
    assert!(quantized.cb_tu_dc_levels[0] < 0);
    assert!(quantized.cr_tu_dc_levels[0] > 0);

    let params = vvc_ctu_partition_params(frame.geometry, quantized).expect("64x48 params");
    let recon = reconstruct_vvc_residual_frame(&frame, quantized, params);
    let chroma = &recon[64 * 48..];
    assert!(chroma[..32 * 24]
        .iter()
        .all(|sample| sample.abs_diff(64) <= 3));
    assert!(chroma[32 * 24..]
        .iter()
        .all(|sample| sample.abs_diff(192) <= 3));
}

#[test]
fn vvc_420_chroma_ac_residual_preserves_visible_chroma_variation() {
    let mut cb = vec![0; 8 * 8];
    let mut cr = vec![0; 8 * 8];
    for y in 0..8 {
        for x in 0..8 {
            cb[y * 8 + x] = if (x % 4) < 2 { 64 } else { 192 };
            cr[y * 8 + x] = if (y % 4) < 2 { 192 } else { 64 };
        }
    }
    let frame = VvcSampledFrame {
        geometry: VvcVideoGeometry {
            width: 16,
            height: 16,
        },
        format: VvcPictureFormat {
            chroma_sampling: ChromaSampling::Cs420,
            bit_depth: SampleBitDepth::Eight,
        },
        luma: vec![128; 16 * 16],
        cb,
        cr,
        chroma_len: 8 * 8,
    };
    let quantized = quantize_vvc_frame(frame.clone());
    assert_eq!(quantized.chroma_tu_count, 4);
    assert!(quantized
        .cb_tu_ac_levels
        .iter()
        .take(quantized.chroma_tu_count)
        .any(|levels| levels.iter().any(|level| *level != 0)));
    assert!(quantized
        .cr_tu_ac_levels
        .iter()
        .take(quantized.chroma_tu_count)
        .any(|levels| levels.iter().any(|level| *level != 0)));

    let params = vvc_ctu_partition_params(frame.geometry, quantized).expect("16x16 params");
    let recon = reconstruct_vvc_residual_frame(&frame, quantized, params);
    let chroma = &recon[16 * 16..];
    let cb_recon = &chroma[..8 * 8];
    let cr_recon = &chroma[8 * 8..];
    let cb_low: u32 = (0..8)
        .flat_map(|y| {
            (0..8)
                .filter(|x| (x % 4) < 2)
                .map(move |x| u32::from(cb_recon[y * 8 + x]))
        })
        .sum();
    let cb_high: u32 = (0..8)
        .flat_map(|y| {
            (0..8)
                .filter(|x| (x % 4) >= 2)
                .map(move |x| u32::from(cb_recon[y * 8 + x]))
        })
        .sum();
    let cr_high: u32 = (0..8)
        .filter(|y| (y % 4) < 2)
        .flat_map(|y| (0..8).map(move |x| u32::from(cr_recon[y * 8 + x])))
        .sum();
    let cr_low: u32 = (0..8)
        .filter(|y| (y % 4) >= 2)
        .flat_map(|y| (0..8).map(move |x| u32::from(cr_recon[y * 8 + x])))
        .sum();
    assert!(cb_high > cb_low);
    assert!(cr_high > cr_low);
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
fn vvc_residual_symbol_stream_names_single_nonzero_luma_coeff_subset() {
    let coeffs = vvc_luma_coefficients(8, 8, &[(0, -3)]);
    let stream = VvcResidualCabacSymbolStream::luma_coefficients(3, 3, &coeffs);
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
            VvcResidualCabacSymbol::CoeffSignPattern { bits: 1, count: 1 },
        ]
    );

    let zero_coeffs = vvc_luma_coefficients(8, 8, &[]);
    let zero = VvcResidualCabacSymbolStream::luma_coefficients(3, 3, &zero_coeffs);
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
fn vvc_residual_symbol_stream_scales_luma_tb_size() {
    let coeffs = vvc_luma_coefficients(32, 16, &[(0, 1)]);
    let stream = VvcResidualCabacSymbolStream::luma_coefficients(5, 4, &coeffs);
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
            VvcResidualCabacSymbol::CoeffSignPattern { bits: 0, count: 1 }
        ]
    );
}

#[test]
fn vvc_residual_symbol_stream_maps_large_abs_remainder_by_spec_order() {
    let coeffs = vvc_luma_coefficients(8, 8, &[(0, -16)]);
    let stream = VvcResidualCabacSymbolStream::luma_coefficients(3, 3, &coeffs);
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
        Some(&VvcResidualCabacSymbol::CoeffSignPattern { bits: 1, count: 1 })
    );
}

#[test]
fn vvc_residual_symbol_stream_can_be_derived_from_quantized_luma_coefficients() {
    let coeffs = vvc_luma_coefficients(8, 8, &[(0, -16)]);
    let stream = VvcResidualCabacSymbolStream::luma_coefficients(3, 3, &coeffs);
    assert_eq!(stream.pass1_state.abs_level_pass1_at(0, 0), 4);
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
        Some(&VvcResidualCabacSymbol::CoeffSignPattern { bits: 1, count: 1 })
    );

    let zero_coeffs = vvc_luma_coefficients(8, 8, &[]);
    let white_stream = VvcResidualCabacSymbolStream::luma_coefficients(3, 3, &zero_coeffs);
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
    let coeffs = vvc_luma_coefficients(8, 8, &[(0, -2)]);
    let stream = VvcResidualCabacSymbolStream::luma_coefficients(3, 3, &coeffs);
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
        .contains(&VvcResidualCabacSymbol::CoeffSignPattern {
            bits: 0b10,
            count: 2,
        }));
    let sign_tail = stream.symbols.last();
    assert_eq!(
        sign_tail,
        Some(&VvcResidualCabacSymbol::CoeffSignPattern {
            bits: 0b10,
            count: 2,
        })
    );
    assert!(!stream.symbols[..stream.symbols.len() - 1]
        .iter()
        .any(|symbol| matches!(symbol, VvcResidualCabacSymbol::CoeffSignPattern { .. })));

    // H.266 9.3.4.2.7 through 9.3.4.2.9: for the DC coefficient, the
    // non-zero AC neighbour at (1, 0) contributes to locNumSig and
    // locSumAbsPass1 before deriving sig/par/abs contexts.
    assert_eq!(stream.pass1_state.sig_coeff_flag_ctx_inc(0, 0), 9);
    assert_eq!(stream.pass1_state.par_level_flag_ctx_inc(0, 0), 17);
    assert_eq!(stream.pass1_state.abs_level_gtx_flag_ctx_inc(0, 0, 1), 49);
    assert_eq!(VvcCabacContext::SigCoeffFlag(9).init_value(), 37);
    assert_eq!(VvcCabacContext::ParLevelFlag(17).init_value(), 42);
    assert_eq!(VvcCabacContext::AbsLevelGtxFlag(49).init_value(), 19);

    let mut coeffs_with_remainder = vec![0; 64];
    coeffs_with_remainder[0] = 5;
    coeffs_with_remainder[1] = -2;
    let remainder_stream =
        VvcResidualCabacSymbolStream::luma_coefficients(3, 3, &coeffs_with_remainder);
    let first_remainder = remainder_stream
        .symbols
        .iter()
        .position(|symbol| matches!(symbol, VvcResidualCabacSymbol::AbsRemainder { .. }))
        .expect("expected a second-pass remainder symbol");
    let first_sign = remainder_stream
        .symbols
        .iter()
        .position(|symbol| matches!(symbol, VvcResidualCabacSymbol::CoeffSignPattern { .. }))
        .expect("expected sign symbols");
    assert!(first_remainder < first_sign);
    assert!(!remainder_stream.symbols[..first_remainder]
        .iter()
        .any(|symbol| matches!(symbol, VvcResidualCabacSymbol::CoeffSignPattern { .. })));

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
