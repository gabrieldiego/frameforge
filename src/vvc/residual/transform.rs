use super::{VvcQuantizedTransformBlock, VvcTransformComponent, VvcTuTransformBlock};

pub(in crate::vvc) const VVC_LUMA_DC_BASE: i16 = 114;
pub(in crate::vvc) const VVC_CHROMA_DC_BASE: i16 = 128;
const VVC_LUMA_DC_NUM: i32 = 5;
const VVC_LUMA_DC_DEN: i32 = 16;
const VVC_LUMA_QP: i32 = 32;
const VVC_CHROMA_QP: i32 = 34;
const VVC_LUMA_AC_QUANT_SHIFT: u32 = 19;
const VVC_LUMA_AC_LEVEL_LIMIT: i16 = 2;
const VVC_CHROMA_DC_LEVEL_LIMIT: i16 = 255;
const VVC_CHROMA_AC_LEVEL_LIMIT: i16 = 2;
const VVC_DCT2_4: [[i32; 4]; 4] = [
    [64, 64, 64, 64],
    [83, 36, -36, -83],
    [64, -64, -64, 64],
    [36, -83, 83, -36],
];
const VVC_DCT2_8: [[i32; 8]; 8] = [
    [64, 64, 64, 64, 64, 64, 64, 64],
    // H.266 inverse DCT-II 8-point matrix, matching VTM
    // g_trCoreDCT2P8[TRANSFORM_INVERSE]. The 89 entries differ from the
    // older HEVC-style 87 values and are required for bit-exact decoder-side
    // reconstruction.
    [89, 75, 50, 18, -18, -50, -75, -89],
    [83, 36, -36, -83, -83, -36, 36, 83],
    [75, -18, -89, -50, 50, 89, 18, -75],
    [64, -64, -64, 64, 64, -64, -64, 64],
    [50, -89, 18, 75, -75, -18, 89, -50],
    [36, -83, 83, -36, -36, 83, -83, 36],
    [18, -50, 75, -89, 89, -75, 50, -18],
];
const VVC_DCT2_16_AC_ROWS_1_TO_3: [[i32; 16]; 3] = [
    [
        90, 87, 80, 70, 57, 43, 25, 9, -9, -25, -43, -57, -70, -80, -87, -90,
    ],
    [
        89, 75, 50, 18, -18, -50, -75, -89, -89, -75, -50, -18, 18, 50, 75, 89,
    ],
    [
        87, 57, 9, -43, -80, -90, -70, -25, 25, 70, 90, 80, 43, -9, -57, -87,
    ],
];
const VVC_DCT2_32_AC_ROWS_1_TO_3: [[i32; 32]; 3] = [
    [
        90, 90, 88, 85, 82, 78, 73, 67, 61, 54, 46, 38, 31, 22, 13, 4, -4, -13, -22, -31, -38, -46,
        -54, -61, -67, -73, -78, -82, -85, -88, -90, -90,
    ],
    [
        90, 87, 80, 70, 57, 43, 25, 9, -9, -25, -43, -57, -70, -80, -87, -90, -90, -87, -80, -70,
        -57, -43, -25, -9, 9, 25, 43, 57, 70, 80, 87, 90,
    ],
    [
        90, 82, 67, 46, 22, -4, -31, -54, -73, -85, -90, -88, -78, -61, -38, -13, 13, 38, 61, 78,
        88, 90, 85, 73, 54, 31, 4, -22, -46, -67, -82, -90,
    ],
];

pub(in crate::vvc) fn transform_vvc_tu(
    component: VvcTransformComponent,
    width: u16,
    height: u16,
    samples: &[u8],
) -> VvcTuTransformBlock {
    debug_assert!(width > 0);
    debug_assert!(height > 0);
    let sample_count = usize::from(width) * usize::from(height);
    assert_eq!(
        samples.len(),
        sample_count,
        "transform input must contain one sample per TU position"
    );
    let sum: u32 = samples.iter().map(|sample| u32::from(*sample)).sum();
    let dc_sample = ((sum + (sample_count as u32 / 2)) / sample_count as u32) as u8;
    let mut ac_coeffs = Vec::with_capacity(sample_count.saturating_sub(1));
    for sample in samples.iter().skip(1) {
        ac_coeffs.push(i16::from(*sample) - i16::from(dc_sample));
    }
    VvcTuTransformBlock {
        component,
        width,
        height,
        dc_coeff: i16::from(dc_sample) - component.dc_base(),
        ac_coeffs,
    }
}

pub(in crate::vvc) fn quantize_vvc_luma_residual_greedy(
    residuals: &[i16],
    width: u16,
    height: u16,
) -> VvcQuantizedTransformBlock {
    let coefficient_count = usize::from(width) * usize::from(height);
    assert_eq!(residuals.len(), coefficient_count);
    debug_assert!([4, 8, 16, 32].contains(&width));
    debug_assert!([4, 8, 16, 32].contains(&height));

    let residual_sum: i32 = residuals.iter().map(|value| i32::from(*value)).sum();
    let residual_avg = div_round_nearest_i32(residual_sum, i32::from(width) * i32::from(height));
    let dc_level = div_round_nearest_i32(residual_avg * VVC_LUMA_DC_NUM, VVC_LUMA_DC_DEN)
        .clamp(i32::from(i16::MIN), i32::from(i16::MAX)) as i16;

    let mut coeff_levels = vec![0; coefficient_count];
    coeff_levels[0] = dc_level;

    // The current residual_coding() writer is audited for the first 4x4
    // subblock. Keep AC search inside that area until scan-position suffixes
    // and sb_coded_flag generation are expanded for larger coefficient groups.
    for y in 0..usize::from(height).min(4) {
        for x in 0..usize::from(width).min(4) {
            let coeff_index = y * usize::from(width) + x;
            if coeff_index == 0 {
                continue;
            }
            coeff_levels[coeff_index] = quantize_direct_luma_ac_coeff(residuals, width, x, y);
        }
    }

    let mut ac_coeffs = [0; 15];
    for y in 0..usize::from(height).min(4) {
        for x in 0..usize::from(width).min(4) {
            let coeff_index = y * usize::from(width) + x;
            if coeff_index == 0 {
                continue;
            }
            let ac_index = y * 4 + x - 1;
            ac_coeffs[ac_index] = coeff_levels[coeff_index];
        }
    }
    let dc_level = coeff_levels[0];
    VvcQuantizedTransformBlock {
        reconstructed_dc_coeff: dc_level,
        reconstructed_ac_coeffs: ac_coeffs,
        abs_remainder: dc_level.unsigned_abs().min(u8::MAX as u16) as u8,
    }
}

pub(in crate::vvc) fn inverse_transform_vvc_luma_residual_levels(
    width: u16,
    height: u16,
    coeff_levels: &[i16],
) -> Vec<i16> {
    inverse_transform_vvc_residual_levels_with_qp(width, height, coeff_levels, VVC_LUMA_QP)
}

pub(in crate::vvc) fn inverse_transform_vvc_chroma_residual_levels(
    width: u16,
    height: u16,
    coeff_levels: &[i16],
) -> Vec<i16> {
    // Current SPS/PPS chroma QP mapping table maps slice QP 32 to chroma QP 34.
    inverse_transform_vvc_residual_levels_with_qp(width, height, coeff_levels, VVC_CHROMA_QP)
}

fn inverse_transform_vvc_residual_levels_with_qp(
    width: u16,
    height: u16,
    coeff_levels: &[i16],
    qp: i32,
) -> Vec<i16> {
    let width_usize = usize::from(width);
    let height_usize = usize::from(height);
    assert_eq!(coeff_levels.len(), width_usize * height_usize);
    debug_assert!([4, 8, 16, 32].contains(&width));
    debug_assert!([4, 8, 16, 32].contains(&height));

    let mut dequantized = vec![0; coeff_levels.len()];
    for (dst, level) in dequantized.iter_mut().zip(coeff_levels.iter().copied()) {
        *dst = dequantize_vvc_transform_level(level, width, height, qp);
    }

    let mut vertical = vec![0; coeff_levels.len()];
    for x in 0..width_usize {
        for y in 0..height_usize {
            let mut sum = 0;
            for k in 0..height_usize {
                let coeff = dequantized[k * width_usize + x];
                if coeff != 0 {
                    sum += dct2_value(height, k, y) * coeff;
                }
            }
            vertical[y * width_usize + x] = if height > 1 { (sum + 64) >> 7 } else { sum };
        }
    }

    let residual_bd_shift = if width > 1 && height > 1 {
        5 + 15 - 8
    } else {
        6 + 15 - 8
    };
    let residual_offset = 1 << (residual_bd_shift - 1);
    let mut residuals = vec![0; coeff_levels.len()];
    for y in 0..height_usize {
        for x in 0..width_usize {
            let mut sum = 0;
            for k in 0..width_usize {
                let coeff = vertical[y * width_usize + k];
                if coeff != 0 {
                    sum += dct2_value(width, k, x) * coeff;
                }
            }
            residuals[y * width_usize + x] = ((sum + residual_offset) >> residual_bd_shift) as i16;
        }
    }
    residuals
}

pub(in crate::vvc) fn quantize_vvc_chroma_residual_dc(
    residuals: &[i16],
    width: u16,
    height: u16,
) -> i16 {
    let coefficient_count = usize::from(width) * usize::from(height);
    assert_eq!(residuals.len(), coefficient_count);
    debug_assert!([4, 8, 16, 32].contains(&width));
    debug_assert!([4, 8, 16, 32].contains(&height));

    let residual_sum: i64 = residuals.iter().map(|value| i64::from(*value)).sum();
    let mut best_level = 0;
    let original_sse = residuals
        .iter()
        .map(|value| i64::from(*value) * i64::from(*value))
        .sum::<i64>();
    let mut best_sse = original_sse;

    for level in -VVC_CHROMA_DC_LEVEL_LIMIT..=VVC_CHROMA_DC_LEVEL_LIMIT {
        let reconstructed = i64::from(dc_only_residual_from_level(
            level,
            width,
            height,
            VVC_CHROMA_QP,
        ));
        let sample_count = coefficient_count as i64;
        let sse = original_sse + (sample_count * reconstructed * reconstructed)
            - (2 * reconstructed * residual_sum);
        if sse < best_sse {
            best_sse = sse;
            best_level = level;
        }
    }
    best_level
}

pub(in crate::vvc) fn quantize_vvc_chroma_residual_greedy(
    residuals: &[i16],
    width: u16,
    height: u16,
) -> VvcQuantizedTransformBlock {
    let coefficient_count = usize::from(width) * usize::from(height);
    assert_eq!(residuals.len(), coefficient_count);
    debug_assert!([4, 8, 16, 32].contains(&width));
    debug_assert!([4, 8, 16, 32].contains(&height));

    let mut coeff_levels = vec![0; coefficient_count];
    coeff_levels[0] = quantize_vvc_chroma_residual_dc(residuals, width, height);
    if residuals_have_ac_energy(residuals) {
        let mut best_sse =
            residual_sse_after_inverse_transform(residuals, width, height, &coeff_levels);
        for y in 0..usize::from(height).min(4) {
            for x in 0..usize::from(width).min(4) {
                let coeff_index = y * usize::from(width) + x;
                if coeff_index == 0 {
                    continue;
                }
                let mut best_level = 0;
                let mut local_best_sse = best_sse;
                for level in -VVC_CHROMA_AC_LEVEL_LIMIT..=VVC_CHROMA_AC_LEVEL_LIMIT {
                    coeff_levels[coeff_index] = level;
                    let sse = residual_sse_after_inverse_transform(
                        residuals,
                        width,
                        height,
                        &coeff_levels,
                    );
                    if sse < local_best_sse {
                        local_best_sse = sse;
                        best_level = level;
                    }
                }
                coeff_levels[coeff_index] = best_level;
                best_sse = local_best_sse;
            }
        }
    }

    let mut ac_coeffs = [0; 15];
    for y in 0..usize::from(height).min(4) {
        for x in 0..usize::from(width).min(4) {
            let coeff_index = y * usize::from(width) + x;
            if coeff_index == 0 {
                continue;
            }
            let ac_index = y * 4 + x - 1;
            ac_coeffs[ac_index] = coeff_levels[coeff_index];
        }
    }
    let dc_level = coeff_levels[0];
    VvcQuantizedTransformBlock {
        reconstructed_dc_coeff: dc_level,
        reconstructed_ac_coeffs: ac_coeffs,
        abs_remainder: dc_level.unsigned_abs().min(u8::MAX as u16) as u8,
    }
}

#[cfg(test)]
pub(in crate::vvc) fn quantize_vvc_chroma(u: u8, v: u8) -> u8 {
    quantize_vvc_chroma_sample(u).max(quantize_vvc_chroma_sample(v))
}

pub(in crate::vvc) fn quantize_vvc_chroma_sample(sample: u8) -> u8 {
    let mut best_rem = 0;
    let mut best_error = u16::MAX;
    for rem in 0..=16 {
        let value = reconstruct_vvc_chroma(rem);
        let error = sample.abs_diff(value) as u16;
        if error < best_error {
            best_rem = rem;
            best_error = error;
        }
    }
    best_rem
}

pub(in crate::vvc) fn reconstruct_vvc_chroma(chroma_residual: u8) -> u8 {
    (((16 - chroma_residual.min(16)) as u16 * 128 + 8) / 16) as u8
}

fn quantize_direct_luma_ac_coeff(residuals: &[i16], width: u16, kx: usize, ky: usize) -> i16 {
    let width_usize = usize::from(width);
    let height_usize = residuals.len() / width_usize;
    let mut acc = 0i64;
    for y in 0..height_usize {
        for x in 0..width_usize {
            acc += i64::from(residuals[y * width_usize + x])
                * i64::from(dct2_value(width, kx, x))
                * i64::from(dct2_value(height_usize as u16, ky, y));
        }
    }
    let level = div_round_nearest_i64(acc, 1i64 << VVC_LUMA_AC_QUANT_SHIFT);
    level.clamp(
        i64::from(-VVC_LUMA_AC_LEVEL_LIMIT),
        i64::from(VVC_LUMA_AC_LEVEL_LIMIT),
    ) as i16
}

fn residuals_have_ac_energy(residuals: &[i16]) -> bool {
    residuals
        .first()
        .is_some_and(|first| residuals.iter().any(|value| value != first))
}

fn residual_sse_after_inverse_transform(
    residuals: &[i16],
    width: u16,
    height: u16,
    coeff_levels: &[i16],
) -> i64 {
    let reconstructed =
        inverse_transform_vvc_residual_levels_with_qp(width, height, coeff_levels, VVC_CHROMA_QP);
    residuals
        .iter()
        .zip(reconstructed.iter())
        .map(|(target, reconstructed)| {
            let diff = i64::from(*target) - i64::from(*reconstructed);
            diff * diff
        })
        .sum()
}

fn div_round_nearest_i32(value: i32, divisor: i32) -> i32 {
    debug_assert!(divisor > 0);
    if value < 0 {
        -(((-value) + (divisor / 2)) / divisor)
    } else {
        (value + (divisor / 2)) / divisor
    }
}

fn div_round_nearest_i64(value: i64, divisor: i64) -> i64 {
    debug_assert!(divisor > 0);
    if value < 0 {
        -(((-value) + (divisor / 2)) / divisor)
    } else {
        (value + (divisor / 2)) / divisor
    }
}

fn dequantize_vvc_transform_level(level: i16, tb_width: u16, tb_height: u16, qp: i32) -> i32 {
    if level == 0 {
        return 0;
    }
    debug_assert!((0..=63).contains(&qp));

    let log2_width = tb_width.ilog2() as i32;
    let log2_height = tb_height.ilog2() as i32;
    let log2_sum = log2_width + log2_height;
    let rect_non_ts = (log2_sum & 1) as usize;
    let level_scale = [[40, 45, 51, 57, 64, 72], [57, 64, 72, 80, 90, 102]];
    let ls = 16 * level_scale[rect_non_ts][(qp % 6) as usize] * (1 << (qp / 6));
    let bd_shift = 8 + rect_non_ts as i32 + (log2_sum / 2) + 10 - 15;
    let bd_offset = 1 << (bd_shift - 1);
    (i32::from(level) * ls + bd_offset) >> bd_shift
}

fn dct2_value(size: u16, k: usize, n: usize) -> i32 {
    if k == 0 {
        return 64;
    }
    match size {
        4 => VVC_DCT2_4[k][n],
        8 => VVC_DCT2_8[k][n],
        16 if k <= 3 => VVC_DCT2_16_AC_ROWS_1_TO_3[k - 1][n],
        32 if k <= 3 => VVC_DCT2_32_AC_ROWS_1_TO_3[k - 1][n],
        16 | 32 => {
            unimplemented!("DCT-II AC subset for size {size} is not wired for coefficient {k}")
        }
        other => unimplemented!("DCT-II matrix size {other} is not wired yet"),
    }
}

fn dc_only_residual_from_level(level: i16, width: u16, height: u16, qp: i32) -> i16 {
    if level == 0 {
        return 0;
    }
    let dequantized = dequantize_vvc_transform_level(level, width, height, qp);
    let vertical = if height > 1 {
        (64 * dequantized + 64) >> 7
    } else {
        64 * dequantized
    };
    let residual_bd_shift = if width > 1 && height > 1 {
        5 + 15 - 8
    } else {
        6 + 15 - 8
    };
    let residual_offset = 1 << (residual_bd_shift - 1);
    ((64 * vertical + residual_offset) >> residual_bd_shift) as i16
}
