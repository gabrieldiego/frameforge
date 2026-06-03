use super::{VvcQuantizedTransformBlock, VvcTransformComponent, VvcTuTransformBlock};

pub(in crate::vvc) const VVC_LUMA_DC_BASE: i16 = 114;
pub(in crate::vvc) const VVC_CHROMA_DC_BASE: i16 = 128;
const VVC_LUMA_DC_NUM: i32 = 5;
const VVC_LUMA_DC_DEN: i32 = 16;
const VVC_LUMA_AC_QUANT_SHIFT: u32 = 19;
const VVC_LUMA_AC_LEVEL_LIMIT: i16 = 2;
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
    debug_assert!([4, 8].contains(&width));
    debug_assert!([4, 8].contains(&height));

    let residual_sum: i32 = residuals.iter().map(|value| i32::from(*value)).sum();
    let residual_avg =
        div_round_nearest_i32(residual_sum, i32::from(width) * i32::from(height));
    let dc_level =
        div_round_nearest_i32(residual_avg * VVC_LUMA_DC_NUM, VVC_LUMA_DC_DEN)
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
    let width_usize = usize::from(width);
    let height_usize = usize::from(height);
    assert_eq!(coeff_levels.len(), width_usize * height_usize);
    debug_assert!([4, 8].contains(&width));
    debug_assert!([4, 8].contains(&height));

    let mut dequantized = vec![0; coeff_levels.len()];
    for (dst, level) in dequantized.iter_mut().zip(coeff_levels.iter().copied()) {
        *dst = dequantize_vvc_transform_level(level, width, height);
    }

    let mut vertical = vec![0; coeff_levels.len()];
    for x in 0..width_usize {
        for y in 0..height_usize {
            let mut sum = 0;
            for k in 0..height_usize {
                sum += dct2_value(height, k, y) * dequantized[k * width_usize + x];
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
                sum += dct2_value(width, k, x) * vertical[y * width_usize + k];
            }
            residuals[y * width_usize + x] = ((sum + residual_offset) >> residual_bd_shift) as i16;
        }
    }
    residuals
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
    level
        .clamp(
            i64::from(-VVC_LUMA_AC_LEVEL_LIMIT),
            i64::from(VVC_LUMA_AC_LEVEL_LIMIT),
        ) as i16
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

fn dequantize_vvc_transform_level(level: i16, tb_width: u16, tb_height: u16) -> i32 {
    if level == 0 {
        return 0;
    }

    let log2_width = tb_width.ilog2() as i32;
    let log2_height = tb_height.ilog2() as i32;
    let log2_sum = log2_width + log2_height;
    let rect_non_ts = (log2_sum & 1) as usize;
    let qp_y = 32i32;
    let level_scale = [[40, 57, 51, 57, 64, 72], [45, 64, 72, 80, 90, 102]];
    let ls = 16 * level_scale[rect_non_ts][(qp_y % 6) as usize] * (1 << (qp_y / 6));
    let bd_shift = 8 + rect_non_ts as i32 + (log2_sum / 2) + 10 - 15;
    let bd_offset = 1 << (bd_shift - 1);
    (i32::from(level) * ls + bd_offset) >> bd_shift
}

fn dct2_value(size: u16, k: usize, n: usize) -> i32 {
    match size {
        4 => VVC_DCT2_4[k][n],
        8 => VVC_DCT2_8[k][n],
        other => unimplemented!("DCT-II matrix size {other} is not wired yet"),
    }
}
