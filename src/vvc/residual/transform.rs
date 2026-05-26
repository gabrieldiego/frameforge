use super::{
    Vvc4x4QuantizedTransformBlock, Vvc4x4ReconstructedLumaBlock, Vvc4x4TransformBlock,
    VVC_RESIDUAL_LUMA_SAMPLES,
};
use crate::vvc::encode_vvc_coeff_token;

pub(in crate::vvc) const VVC_LUMA_DC_BASE: i16 = 114;

pub(in crate::vvc) fn transform_vvc_4x4_luma(
    samples: [u8; VVC_RESIDUAL_LUMA_SAMPLES],
) -> Vvc4x4TransformBlock {
    let sum: u16 = samples.iter().map(|sample| *sample as u16).sum();
    let dc_sample = ((sum + 8) >> 4) as u8;
    let mut ac_coeffs = [0; 15];
    for (dst, sample) in ac_coeffs.iter_mut().zip(samples.iter().skip(1)) {
        *dst = *sample as i16 - dc_sample as i16;
    }
    Vvc4x4TransformBlock {
        dc_coeff: dc_sample as i16 - VVC_LUMA_DC_BASE,
        ac_coeffs,
    }
}

pub(in crate::vvc) fn quantize_vvc_4x4_luma_dc(
    block: Vvc4x4TransformBlock,
) -> Vvc4x4QuantizedTransformBlock {
    let sample = (block.dc_coeff + VVC_LUMA_DC_BASE).clamp(0, u8::MAX as i16) as u8;
    let (reconstructed_sample, abs_remainder) = nearest_quantized_luma(sample);
    let mut reconstructed_ac_coeffs = [0; 15];
    let mut ac_tokens = [0; 15];
    for ((reconstructed, token), coeff) in reconstructed_ac_coeffs
        .iter_mut()
        .zip(ac_tokens.iter_mut())
        .zip(block.ac_coeffs)
    {
        let quantized = quantize_vvc_ac_coeff(coeff);
        *reconstructed = quantized as i16 * 16;
        *token = encode_vvc_coeff_token(quantized < 0, quantized.unsigned_abs());
    }
    Vvc4x4QuantizedTransformBlock {
        reconstructed_dc_coeff: reconstructed_sample as i16 - VVC_LUMA_DC_BASE,
        reconstructed_ac_coeffs,
        abs_remainder,
        ac_tokens,
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

fn quantize_vvc_ac_coeff(coeff: i16) -> i8 {
    let magnitude = ((coeff.unsigned_abs() + 8) >> 4).min(8) as i8;
    if coeff < 0 {
        -magnitude
    } else {
        magnitude
    }
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
