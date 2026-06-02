use super::{
    VvcQuantizedTransformBlock, VvcReconstructedLumaBlock, VvcTransformBlock,
    VvcTransformComponent, VvcTuTransformBlock,
};

pub(in crate::vvc) const VVC_LUMA_DC_BASE: i16 = 114;
pub(in crate::vvc) const VVC_CHROMA_DC_BASE: i16 = 128;

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
    VvcTuTransformBlock {
        component,
        width,
        height,
        dc_coeff: i16::from(dc_sample) - component.dc_base(),
        ac_coeffs: vec![0; sample_count.saturating_sub(1)],
    }
}

pub(in crate::vvc) fn quantize_vvc_luma_dc(block: VvcTransformBlock) -> VvcQuantizedTransformBlock {
    let sample = (block.dc_coeff + VVC_LUMA_DC_BASE).clamp(0, u8::MAX as i16) as u8;
    let (reconstructed_sample, abs_remainder) = nearest_quantized_luma(sample);
    let reconstructed_ac_coeffs = block.ac_coeffs.map(|coeff| coeff.clamp(-255, 255));
    VvcQuantizedTransformBlock {
        reconstructed_dc_coeff: reconstructed_sample as i16 - VVC_LUMA_DC_BASE,
        reconstructed_ac_coeffs,
        abs_remainder,
        ac_tokens: [0x40; 15],
    }
}

pub(in crate::vvc) fn inverse_transform_vvc_luma_dc(
    block: VvcQuantizedTransformBlock,
) -> VvcReconstructedLumaBlock {
    let sample = (block.reconstructed_dc_coeff + VVC_LUMA_DC_BASE).clamp(0, u8::MAX as i16) as u8;
    let mut samples = [sample; 16];
    for (dst, coeff) in samples
        .iter_mut()
        .skip(1)
        .zip(block.reconstructed_ac_coeffs)
    {
        *dst = (sample as i16 + coeff).clamp(0, u8::MAX as i16) as u8;
    }
    VvcReconstructedLumaBlock { samples }
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

pub(in crate::vvc) fn reconstruct_vvc_luma_dc_residual_sample(
    abs_level: u8,
    negative: bool,
    tb_width: u16,
    tb_height: u16,
) -> i16 {
    if abs_level == 0 {
        return 0;
    }

    debug_assert!(tb_width.is_power_of_two());
    debug_assert!(tb_height.is_power_of_two());

    // H.266 clauses 8.7.3 and 8.7.4, restricted to the current 8-bit,
    // scaling-list-disabled, non-transform-skip, DCT-II residual path.
    let log2_width = tb_width.ilog2() as i32;
    let log2_height = tb_height.ilog2() as i32;
    let log2_sum = log2_width + log2_height;
    let rect_non_ts = (log2_sum & 1) as usize;
    let qp_y = 32i32;
    let level_scale = [[40, 57, 51, 57, 64, 72], [45, 64, 72, 80, 90, 102]];
    let ls = 16 * level_scale[rect_non_ts][(qp_y % 6) as usize] * (1 << (qp_y / 6));
    let bd_shift = 8 + rect_non_ts as i32 + (log2_sum / 2) + 10 - 15;
    let bd_offset = 1 << (bd_shift - 1);
    let signed_level = if negative {
        -(abs_level as i32)
    } else {
        abs_level as i32
    };
    let d = (signed_level * ls + bd_offset) >> bd_shift;

    // For the current DC-only subset, both inverse DCT-II passes use the DC
    // matrix value 64. This is the same path the decoder applies after
    // residual_coding() produces TransCoeffLevel[0][0].
    let e = d * 64;
    let g = if tb_height > 1 { (e + 64) >> 7 } else { e };
    let r = g * 64;
    let residual_bd_shift = if tb_width > 1 && tb_height > 1 {
        5 + 15 - 8
    } else {
        6 + 15 - 8
    };
    ((r + (1 << (residual_bd_shift - 1))) >> residual_bd_shift) as i16
}

fn nearest_quantized_luma(input: u8) -> (u8, u8) {
    let mut best_rem = 16;
    let mut best_error = u16::MAX;
    for rem in 0..=16 {
        let value = (((16 - rem) as u16 * 114 + 8) / 16) as u8;
        let error = input.abs_diff(value) as u16;
        if error < best_error {
            best_rem = rem;
            best_error = error;
        }
    }
    let reconstructed_value = (((16 - best_rem) as u16 * 114) / 16) as u8;
    (reconstructed_value, best_rem)
}
