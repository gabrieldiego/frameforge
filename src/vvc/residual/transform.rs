use super::{
    Vvc4x4QuantizedTransformBlock, Vvc4x4ReconstructedLumaBlock, Vvc4x4TransformBlock,
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

pub(in crate::vvc) fn quantize_vvc_4x4_luma_dc(
    block: Vvc4x4TransformBlock,
) -> Vvc4x4QuantizedTransformBlock {
    let sample = (block.dc_coeff + VVC_LUMA_DC_BASE).clamp(0, u8::MAX as i16) as u8;
    let (reconstructed_sample, abs_remainder) = nearest_quantized_luma(sample);
    Vvc4x4QuantizedTransformBlock {
        reconstructed_dc_coeff: reconstructed_sample as i16 - VVC_LUMA_DC_BASE,
        reconstructed_ac_coeffs: [0; 15],
        abs_remainder,
        ac_tokens: [0x40; 15],
    }
}

pub(in crate::vvc) fn inverse_transform_vvc_4x4_luma_dc(
    block: Vvc4x4QuantizedTransformBlock,
) -> Vvc4x4ReconstructedLumaBlock {
    let sample = (block.reconstructed_dc_coeff + VVC_LUMA_DC_BASE).clamp(0, u8::MAX as i16) as u8;
    let mut samples = [sample; 16];
    for (dst, coeff) in samples
        .iter_mut()
        .skip(1)
        .zip(block.reconstructed_ac_coeffs)
    {
        *dst = (sample as i16 + coeff).clamp(0, u8::MAX as i16) as u8;
    }
    Vvc4x4ReconstructedLumaBlock { samples }
}

#[cfg(test)]
pub(in crate::vvc) fn quantize_vvc_4x4_chroma(u: u8, v: u8) -> u8 {
    quantize_vvc_4x4_chroma_sample(u).max(quantize_vvc_4x4_chroma_sample(v))
}

pub(in crate::vvc) fn quantize_vvc_4x4_chroma_sample(sample: u8) -> u8 {
    let mut best_rem = 0;
    let mut best_error = u16::MAX;
    for rem in 0..=16 {
        let value = reconstruct_vvc_4x4_chroma(rem);
        let error = sample.abs_diff(value) as u16;
        if error < best_error {
            best_rem = rem;
            best_error = error;
        }
    }
    best_rem
}

pub(in crate::vvc) fn reconstruct_vvc_4x4_chroma(chroma_residual: u8) -> u8 {
    (((16 - chroma_residual.min(16)) as u16 * 128 + 8) / 16) as u8
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
