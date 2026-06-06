use crate::picture::ChromaSampling;

use super::super::{
    vvc_chroma_420_transform_nodes, VvcCodingTreeNode, VvcCtuCabacOp, VvcCtuPartitionParams,
    VvcSampledFrame,
};
use super::{
    fill_visible_chroma_node, fill_visible_luma_node, inverse_transform_vvc_chroma_residual_levels,
    inverse_transform_vvc_luma_residual_levels, predict_vvc_chroma_dc_block,
    predict_vvc_luma_dc_block, VvcQuantizedColor, VVC_LUMA_AC_COEFFS_PER_TU,
};

pub(in crate::vvc) fn reconstruct_vvc_residual_frame(
    frame: &VvcSampledFrame,
    quantized: VvcQuantizedColor,
    partition_params: VvcCtuPartitionParams,
) -> Vec<u8> {
    match frame.format.chroma_sampling {
        ChromaSampling::Cs420 => {
            reconstruct_vvc_residual_frame_420(frame, quantized, partition_params)
        }
        ChromaSampling::Cs444 => {
            unreachable!("4:4:4 pictures are reconstructed by the palette path for now")
        }
        other => {
            unimplemented!("residual reconstruction is not wired for {other:?}")
        }
    }
}

fn reconstruct_vvc_residual_frame_420(
    frame: &VvcSampledFrame,
    quantized: VvcQuantizedColor,
    partition_params: VvcCtuPartitionParams,
) -> Vec<u8> {
    let mut luma = vec![128; frame.geometry.luma_samples()];
    let mut tu_idx = 0;
    for op in VvcCtuCabacOp::yuv420_ctu_partition(partition_params) {
        let VvcCtuCabacOp::LumaLeafWithSplitCtx { node, .. } = op else {
            continue;
        };
        let predicted = predict_vvc_luma_dc_block(&luma, frame.geometry, node);
        let coeff_levels = quantized_luma_coeff_levels(node.width, node.height, quantized, tu_idx);
        let residuals =
            inverse_transform_vvc_luma_residual_levels(node.width, node.height, &coeff_levels);
        fill_visible_luma_node(&mut luma, frame.geometry, node, &predicted, &residuals);
        tu_idx += 1;
    }

    let chroma_len = frame.geometry.luma_samples() / 4;
    let chroma_width = frame.geometry.width / 2;
    let mut cb = vec![128; chroma_len];
    let mut cr = vec![128; chroma_len];
    for (tu_idx, node) in vvc_chroma_420_transform_nodes(partition_params.shape())
        .into_iter()
        .enumerate()
    {
        let cb_predicted = predict_vvc_chroma_dc_block(&cb, frame.geometry, node);
        let cb_residuals = inverse_transform_vvc_chroma_residual_levels(
            node.width / 2,
            node.height / 2,
            &quantized_chroma_coeff_levels(
                node,
                quantized.cb_tu_dc_levels[tu_idx],
                quantized.cb_tu_ac_levels[tu_idx],
            ),
        );
        fill_visible_chroma_node(&mut cb, frame.geometry, node, &cb_predicted, &cb_residuals);
        let cr_predicted = predict_vvc_chroma_dc_block(&cr, frame.geometry, node);
        let cr_residuals = inverse_transform_vvc_chroma_residual_levels(
            node.width / 2,
            node.height / 2,
            &quantized_chroma_coeff_levels(
                node,
                quantized.cr_tu_dc_levels[tu_idx],
                quantized.cr_tu_ac_levels[tu_idx],
            ),
        );
        fill_visible_chroma_node(&mut cr, frame.geometry, node, &cr_predicted, &cr_residuals);
    }

    let mut out = Vec::with_capacity(frame.geometry.luma_samples() + chroma_len * 2);
    out.extend_from_slice(&luma);
    out.extend_from_slice(&cb[..chroma_width * (frame.geometry.height / 2)]);
    out.extend_from_slice(&cr[..chroma_width * (frame.geometry.height / 2)]);
    out
}

fn quantized_chroma_coeff_levels(
    node: VvcCodingTreeNode,
    dc_level: i16,
    ac_levels: [i16; super::VVC_CHROMA_AC_COEFFS_PER_TU],
) -> Vec<i16> {
    let width = usize::from(node.width / 2);
    let height = usize::from(node.height / 2);
    let mut levels = vec![0; width * height];
    levels[0] = dc_level;
    for (slot, level) in ac_levels.iter().enumerate() {
        let (x, y) = super::VVC_CHROMA_AC_POSITIONS_2X2[slot];
        if x < width && y < height {
            levels[y * width + x] = *level;
        }
    }
    levels
}

fn quantized_luma_coeff_levels(
    width: u16,
    height: u16,
    quantized: VvcQuantizedColor,
    tu_idx: usize,
) -> Vec<i16> {
    let mut levels = vec![0; usize::from(width) * usize::from(height)];
    let abs_level = quantized.luma_tu_remainders[tu_idx];
    levels[0] = if abs_level == 0 {
        0
    } else if quantized.luma_tu_negative[tu_idx] {
        -(abs_level as i16)
    } else {
        abs_level as i16
    };
    let ac_levels = quantized.luma_tu_ac_levels[tu_idx];
    for y in 0..usize::from(height).min(4) {
        for x in 0..usize::from(width).min(4) {
            let coeff_index = y * usize::from(width) + x;
            if coeff_index == 0 {
                continue;
            }
            let ac_index = y * 4 + x - 1;
            debug_assert!(ac_index < VVC_LUMA_AC_COEFFS_PER_TU);
            levels[coeff_index] = ac_levels[ac_index];
        }
    }
    levels
}
