use super::super::{
    chroma_subsample_x, chroma_subsample_y, vvc_anchor_luma_tu_size_from_partition,
    VvcPictureFormat, VvcSampledColor, VvcSampledFrame, VvcVideoGeometry,
};
use super::{
    inverse_transform_vvc_luma_dc, quantize_vvc_chroma_sample, quantize_vvc_luma_dc,
    reconstruct_vvc_chroma, transform_vvc_tu, VvcQuantizedColor, VvcQuantizedTransformBlock,
    VvcTransformBlock, VvcTransformComponent, VvcTuTransformBlock, MAX_VVC_LUMA_TUS,
    VVC_CHROMA_TU_SIZE,
};

pub fn quantize_vvc_color(color: VvcSampledColor) -> VvcQuantizedColor {
    quantize_vvc_frame(VvcSampledFrame::solid(color))
}

pub(in crate::vvc) fn quantize_vvc_frame(frame: VvcSampledFrame) -> VvcQuantizedColor {
    let quantized_luma = quantize_vvc_anchor_luma_tu(&frame);
    let reconstructed_luma = inverse_transform_vvc_luma_dc(quantized_luma);
    let chroma_transforms = transform_vvc_chroma_default_tus(&frame);
    let _observed_chroma_dc = (chroma_transforms.cb.dc_coeff, chroma_transforms.cr.dc_coeff);
    let color = frame.sampled_color();
    let cb_rem = quantize_vvc_chroma_sample(color.u);
    let cr_rem = quantize_vvc_chroma_sample(color.v);
    let reconstructed_cb = reconstruct_vvc_chroma(cb_rem);
    let reconstructed_cr = reconstruct_vvc_chroma(cr_rem);
    let luma_tu_remainders = [quantized_luma.abs_remainder; MAX_VVC_LUMA_TUS];
    let luma_tu_ac0_tokens = [quantized_luma.ac_tokens[0]; MAX_VVC_LUMA_TUS];
    VvcQuantizedColor {
        y: reconstructed_luma.samples[0],
        u: reconstructed_cb,
        v: reconstructed_cr,
        luma_rem: quantized_luma.abs_remainder,
        luma_ac_levels: quantized_luma.reconstructed_ac_coeffs,
        luma_ac_tokens: quantized_luma.ac_tokens,
        second_luma_rem: quantized_luma.abs_remainder,
        second_luma_ac_tokens: quantized_luma.ac_tokens,
        luma_tu_remainders,
        luma_tu_ac0_tokens,
        luma_tu_count: 1,
        cb_rem,
        cr_rem,
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct VvcChromaTransformDefaults {
    cb: VvcTuTransformBlock,
    cr: VvcTuTransformBlock,
}

fn transform_vvc_chroma_default_tus(frame: &VvcSampledFrame) -> VvcChromaTransformDefaults {
    let cb_samples = residual_chroma_tu_at(
        &frame.cb,
        frame.geometry,
        frame.format,
        0,
        0,
        VVC_CHROMA_TU_SIZE,
        VVC_CHROMA_TU_SIZE,
    );
    let cr_samples = residual_chroma_tu_at(
        &frame.cr,
        frame.geometry,
        frame.format,
        0,
        0,
        VVC_CHROMA_TU_SIZE,
        VVC_CHROMA_TU_SIZE,
    );
    VvcChromaTransformDefaults {
        cb: transform_vvc_tu(
            VvcTransformComponent::ChromaCb,
            VVC_CHROMA_TU_SIZE as u16,
            VVC_CHROMA_TU_SIZE as u16,
            &cb_samples,
        ),
        cr: transform_vvc_tu(
            VvcTransformComponent::ChromaCr,
            VVC_CHROMA_TU_SIZE as u16,
            VVC_CHROMA_TU_SIZE as u16,
            &cr_samples,
        ),
    }
}

fn quantize_vvc_anchor_luma_tu(frame: &VvcSampledFrame) -> VvcQuantizedTransformBlock {
    let size = vvc_anchor_luma_tu_size(frame.geometry);
    quantize_vvc_luma_tu_dc(frame, 0, 0, size.width, size.height)
}

pub(in crate::vvc) fn vvc_anchor_luma_tu_size(geometry: VvcVideoGeometry) -> VvcVideoGeometry {
    // ITU-T H.266 clause 7.3.11.10 defines transform_unit() syntax inside
    // coding_unit(). The residual anchor must therefore use the first luma
    // leaf produced by the same coding-tree partition generator that emits
    // tu_y_coded_flag and residual_coding(), not a fixed 8x8 fixture size.
    vvc_anchor_luma_tu_size_from_partition(geometry)
}

fn quantize_vvc_luma_tu_dc(
    frame: &VvcSampledFrame,
    origin_x: usize,
    origin_y: usize,
    width: usize,
    height: usize,
) -> VvcQuantizedTransformBlock {
    let samples = residual_luma_tu_at(frame, origin_x, origin_y, width, height);
    let transform = transform_vvc_tu(
        VvcTransformComponent::Luma,
        width as u16,
        height as u16,
        &samples,
    );
    let mut ac_coeffs = [0; 15];
    for (dst, src) in ac_coeffs
        .iter_mut()
        .zip(transform.ac_coeffs.iter().copied())
    {
        *dst = src;
    }
    quantize_vvc_luma_dc(VvcTransformBlock {
        dc_coeff: transform.dc_coeff,
        ac_coeffs,
    })
}

fn residual_luma_tu_at(
    frame: &VvcSampledFrame,
    origin_x: usize,
    origin_y: usize,
    width: usize,
    height: usize,
) -> Vec<u8> {
    let mut block = vec![0; width * height];
    let copy_width = width.min(frame.geometry.width.saturating_sub(origin_x));
    let copy_height = height.min(frame.geometry.height.saturating_sub(origin_y));
    for y in 0..copy_height {
        let src = (origin_y + y) * frame.geometry.width + origin_x;
        let dst = y * width;
        block[dst..dst + copy_width].copy_from_slice(&frame.luma[src..src + copy_width]);
    }
    block
}

fn residual_chroma_tu_at(
    samples: &[u8],
    geometry: VvcVideoGeometry,
    format: VvcPictureFormat,
    origin_x: usize,
    origin_y: usize,
    width: usize,
    height: usize,
) -> Vec<u8> {
    let chroma_width = geometry.width / chroma_subsample_x(format.chroma_sampling);
    let chroma_height = geometry.height / chroma_subsample_y(format.chroma_sampling);
    let mut block = vec![128; width * height];
    let copy_width = width.min(chroma_width.saturating_sub(origin_x));
    let copy_height = height.min(chroma_height.saturating_sub(origin_y));
    for y in 0..copy_height {
        let src = (origin_y + y) * chroma_width + origin_x;
        let dst = y * width;
        block[dst..dst + copy_width].copy_from_slice(&samples[src..src + copy_width]);
    }
    block
}
