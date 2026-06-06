use super::super::{
    chroma_subsample_x, chroma_subsample_y, vvc_chroma_420_transform_nodes, VvcCodingTreeNode,
    VvcCtuCabacOp, VvcCtuPartitionParams, VvcPictureFormat, VvcSampledColor, VvcSampledFrame,
    VvcVideoGeometry, VVC_CTU_SIZE,
};
use super::{
    fill_visible_chroma_node, fill_visible_luma_node, inverse_transform_vvc_chroma_residual_levels,
    predict_vvc_chroma_dc_block, predict_vvc_luma_dc_block, quantize_vvc_chroma_residual_greedy,
    quantize_vvc_chroma_sample, quantize_vvc_luma_residual_greedy, reconstruct_vvc_chroma,
    transform_vvc_tu, VvcQuantizedColor, VvcQuantizedTransformBlock, VvcTransformComponent,
    VvcTuTransformBlock, MAX_VVC_CHROMA_TUS, MAX_VVC_LUMA_TUS, VVC_CHROMA_AC_COEFFS_PER_TU,
    VVC_CHROMA_AC_POSITIONS_2X2, VVC_CHROMA_TU_SIZE,
};

pub fn quantize_vvc_color(color: VvcSampledColor) -> VvcQuantizedColor {
    quantize_vvc_frame(VvcSampledFrame::solid(color))
}

pub(in crate::vvc) fn quantize_vvc_frame(frame: VvcSampledFrame) -> VvcQuantizedColor {
    let mut luma_tu_remainders = [0; MAX_VVC_LUMA_TUS];
    let mut luma_tu_negative = [false; MAX_VVC_LUMA_TUS];
    let mut luma_tu_ac_levels = [[0; super::VVC_LUMA_AC_COEFFS_PER_TU]; MAX_VVC_LUMA_TUS];
    let mut reconstructed_luma = vec![128; frame.geometry.luma_samples()];
    let mut luma_tu_count = 0;
    let mut cb_tu_dc_levels = [0; MAX_VVC_CHROMA_TUS];
    let mut cr_tu_dc_levels = [0; MAX_VVC_CHROMA_TUS];
    let mut chroma_tu_count = 0;
    let mut cb_tu_ac_levels = [[0; VVC_CHROMA_AC_COEFFS_PER_TU]; MAX_VVC_CHROMA_TUS];
    let mut cr_tu_ac_levels = [[0; VVC_CHROMA_AC_COEFFS_PER_TU]; MAX_VVC_CHROMA_TUS];
    let mut reconstructed_cb = vec![128; frame.chroma_len];
    let mut reconstructed_cr = vec![128; frame.chroma_len];

    for node in vvc_luma_tu_nodes(frame.geometry, frame.format.chroma_sampling) {
        if luma_tu_count >= MAX_VVC_LUMA_TUS {
            break;
        }
        let predicted = predict_vvc_luma_dc_block(&reconstructed_luma, frame.geometry, node);
        let samples = residual_luma_tu_at(
            &frame,
            usize::from(node.x),
            usize::from(node.y),
            usize::from(node.width),
            usize::from(node.height),
        );
        let _observed_luma_transform = transform_vvc_tu(
            VvcTransformComponent::Luma,
            node.width,
            node.height,
            &samples,
        );
        let residuals: Vec<i16> = samples
            .iter()
            .zip(predicted.iter())
            .map(|(sample, predicted)| i16::from(*sample) - i16::from(*predicted))
            .collect();
        let quantized = quantize_vvc_luma_residual_greedy(&residuals, node.width, node.height);
        luma_tu_remainders[luma_tu_count] = quantized.abs_remainder;
        luma_tu_negative[luma_tu_count] =
            quantized.reconstructed_dc_coeff < 0 && quantized.abs_remainder != 0;
        luma_tu_ac_levels[luma_tu_count] = quantized.reconstructed_ac_coeffs;
        let coeff_levels = quantized_luma_coeff_levels(node.width, node.height, quantized);
        let reconstructed_residual = super::inverse_transform_vvc_luma_residual_levels(
            node.width,
            node.height,
            &coeff_levels,
        );
        fill_visible_luma_node(
            &mut reconstructed_luma,
            frame.geometry,
            node,
            &predicted,
            &reconstructed_residual,
        );
        luma_tu_count += 1;
    }

    for node in vvc_chroma_420_transform_nodes(chroma_partition_shape(frame.geometry)) {
        if chroma_tu_count >= MAX_VVC_CHROMA_TUS {
            break;
        }
        let chroma_x = usize::from(node.x / 2);
        let chroma_y = usize::from(node.y / 2);
        let chroma_width = usize::from(node.width / 2);
        let chroma_height = usize::from(node.height / 2);
        let cb_samples = residual_chroma_tu_at(
            &frame.cb,
            frame.geometry,
            frame.format,
            chroma_x,
            chroma_y,
            chroma_width,
            chroma_height,
        );
        let cr_samples = residual_chroma_tu_at(
            &frame.cr,
            frame.geometry,
            frame.format,
            chroma_x,
            chroma_y,
            chroma_width,
            chroma_height,
        );
        let cb_predicted = predict_vvc_chroma_dc_block(&reconstructed_cb, frame.geometry, node);
        let cr_predicted = predict_vvc_chroma_dc_block(&reconstructed_cr, frame.geometry, node);
        let cb_residuals: Vec<i16> = cb_samples
            .iter()
            .zip(cb_predicted.iter())
            .map(|(sample, predicted)| i16::from(*sample) - i16::from(*predicted))
            .collect();
        let cr_residuals: Vec<i16> = cr_samples
            .iter()
            .zip(cr_predicted.iter())
            .map(|(sample, predicted)| i16::from(*sample) - i16::from(*predicted))
            .collect();
        let cb_quantized = quantize_vvc_chroma_residual_greedy(
            &cb_residuals,
            chroma_width as u16,
            chroma_height as u16,
        );
        let cr_quantized = quantize_vvc_chroma_residual_greedy(
            &cr_residuals,
            chroma_width as u16,
            chroma_height as u16,
        );
        cb_tu_dc_levels[chroma_tu_count] = cb_quantized.reconstructed_dc_coeff;
        cr_tu_dc_levels[chroma_tu_count] = cr_quantized.reconstructed_dc_coeff;
        cb_tu_ac_levels[chroma_tu_count] =
            chroma_ac_subset_from_full_4x4(cb_quantized.reconstructed_ac_coeffs);
        cr_tu_ac_levels[chroma_tu_count] =
            chroma_ac_subset_from_full_4x4(cr_quantized.reconstructed_ac_coeffs);
        let cb_reconstructed_residual = inverse_transform_vvc_chroma_residual_levels(
            chroma_width as u16,
            chroma_height as u16,
            &quantized_chroma_coeff_levels(chroma_width as u16, chroma_height as u16, cb_quantized),
        );
        let cr_reconstructed_residual = inverse_transform_vvc_chroma_residual_levels(
            chroma_width as u16,
            chroma_height as u16,
            &quantized_chroma_coeff_levels(chroma_width as u16, chroma_height as u16, cr_quantized),
        );
        fill_visible_chroma_node(
            &mut reconstructed_cb,
            frame.geometry,
            node,
            &cb_predicted,
            &cb_reconstructed_residual,
        );
        fill_visible_chroma_node(
            &mut reconstructed_cr,
            frame.geometry,
            node,
            &cr_predicted,
            &cr_reconstructed_residual,
        );
        chroma_tu_count += 1;
    }

    let chroma_transforms = transform_vvc_chroma_default_tus(&frame);
    let _observed_chroma_dc = (chroma_transforms.cb.dc_coeff, chroma_transforms.cr.dc_coeff);
    let color = frame.sampled_color();
    let cb_rem = quantize_vvc_chroma_sample(color.u);
    let cr_rem = quantize_vvc_chroma_sample(color.v);
    let reconstructed_cb = reconstruct_vvc_chroma(cb_rem);
    let reconstructed_cr = reconstruct_vvc_chroma(cr_rem);
    VvcQuantizedColor {
        y: reconstructed_luma.first().copied().unwrap_or(128),
        u: reconstructed_cb,
        v: reconstructed_cr,
        luma_tu_remainders,
        luma_tu_negative,
        luma_tu_ac_levels,
        luma_tu_count,
        chroma_tu_count,
        cb_tu_dc_levels,
        cr_tu_dc_levels,
        cb_tu_ac_levels,
        cr_tu_ac_levels,
        cb_rem,
        cr_rem,
    }
}

fn chroma_partition_shape(geometry: VvcVideoGeometry) -> super::super::VvcCtuPartitionShape {
    VvcCtuPartitionParams {
        root_width: VVC_CTU_SIZE,
        root_height: VVC_CTU_SIZE,
        visible_width: geometry.coded_width(),
        visible_height: geometry.coded_height(),
        chroma_sampling: crate::picture::ChromaSampling::Cs420,
        chroma_tu_count: 0,
        luma_tu_count: 0,
        luma_tu_abs_levels: [0; MAX_VVC_LUMA_TUS],
        luma_tu_negative: [false; MAX_VVC_LUMA_TUS],
        luma_tu_ac_levels: [[0; super::VVC_LUMA_AC_COEFFS_PER_TU]; MAX_VVC_LUMA_TUS],
        cb_dc_abs_level: 0,
        cb_dc_negative: false,
        cb_tu_dc_levels: [0; MAX_VVC_CHROMA_TUS],
        cr_tu_dc_levels: [0; MAX_VVC_CHROMA_TUS],
        cb_tu_ac_levels: [[0; VVC_CHROMA_AC_COEFFS_PER_TU]; MAX_VVC_CHROMA_TUS],
        cr_tu_ac_levels: [[0; VVC_CHROMA_AC_COEFFS_PER_TU]; MAX_VVC_CHROMA_TUS],
    }
    .shape()
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

fn vvc_luma_tu_nodes(
    geometry: VvcVideoGeometry,
    chroma_sampling: crate::picture::ChromaSampling,
) -> Vec<VvcCodingTreeNode> {
    let params = VvcCtuPartitionParams {
        root_width: VVC_CTU_SIZE,
        root_height: VVC_CTU_SIZE,
        visible_width: geometry.coded_width(),
        visible_height: geometry.coded_height(),
        chroma_sampling,
        chroma_tu_count: 0,
        luma_tu_count: 0,
        luma_tu_abs_levels: [0; MAX_VVC_LUMA_TUS],
        luma_tu_negative: [false; MAX_VVC_LUMA_TUS],
        luma_tu_ac_levels: [[0; super::VVC_LUMA_AC_COEFFS_PER_TU]; MAX_VVC_LUMA_TUS],
        cb_dc_abs_level: 0,
        cb_dc_negative: false,
        cb_tu_dc_levels: [0; MAX_VVC_CHROMA_TUS],
        cr_tu_dc_levels: [0; MAX_VVC_CHROMA_TUS],
        cb_tu_ac_levels: [[0; VVC_CHROMA_AC_COEFFS_PER_TU]; MAX_VVC_CHROMA_TUS],
        cr_tu_ac_levels: [[0; VVC_CHROMA_AC_COEFFS_PER_TU]; MAX_VVC_CHROMA_TUS],
    };
    VvcCtuCabacOp::yuv420_ctu_partition(params)
        .into_iter()
        .filter_map(|op| match op {
            VvcCtuCabacOp::LumaLeafWithSplitCtx { node, .. } => Some(node),
            _ => None,
        })
        .collect()
}

fn quantized_luma_coeff_levels(
    width: u16,
    height: u16,
    block: VvcQuantizedTransformBlock,
) -> Vec<i16> {
    let mut levels = vec![0; usize::from(width) * usize::from(height)];
    levels[0] = block.reconstructed_dc_coeff;
    for y in 0..usize::from(height).min(4) {
        for x in 0..usize::from(width).min(4) {
            let coeff_index = y * usize::from(width) + x;
            if coeff_index == 0 {
                continue;
            }
            let ac_index = y * 4 + x - 1;
            levels[coeff_index] = block.reconstructed_ac_coeffs[ac_index];
        }
    }
    levels
}

fn quantized_chroma_coeff_levels(
    width: u16,
    height: u16,
    block: VvcQuantizedTransformBlock,
) -> Vec<i16> {
    let mut levels = vec![0; usize::from(width) * usize::from(height)];
    levels[0] = block.reconstructed_dc_coeff;
    for y in 0..usize::from(height).min(4) {
        for x in 0..usize::from(width).min(4) {
            let coeff_index = y * usize::from(width) + x;
            if coeff_index == 0 {
                continue;
            }
            let ac_index = y * 4 + x - 1;
            levels[coeff_index] = block.reconstructed_ac_coeffs[ac_index];
        }
    }
    levels
}

fn chroma_ac_subset_from_full_4x4(
    ac_levels: [i16; super::VVC_LUMA_AC_COEFFS_PER_TU],
) -> [i16; VVC_CHROMA_AC_COEFFS_PER_TU] {
    let mut subset = [0; VVC_CHROMA_AC_COEFFS_PER_TU];
    for (slot, (x, y)) in VVC_CHROMA_AC_POSITIONS_2X2.iter().copied().enumerate() {
        subset[slot] = ac_levels[y * 4 + x - 1];
    }
    subset
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
