use crate::picture::ChromaSampling;

use super::super::{
    VvcCodingTreeNode, VvcCtuCabacOp, VvcCtuPartitionParams, VvcSampledFrame, VvcVideoGeometry,
};
use super::{reconstruct_vvc_luma_dc_residual_sample, VvcQuantizedColor, VVC_LUMA_DC_BASE};

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
    let mut anchor_leaf = true;
    for op in VvcCtuCabacOp::yuv420_ctu_partition(partition_params) {
        let VvcCtuCabacOp::LumaLeafWithSplitCtx { node, .. } = op else {
            continue;
        };
        if anchor_leaf {
            let predicted = predict_luma_leaf_sample(&luma, frame.geometry, node);
            let negative = quantized.y < VVC_LUMA_DC_BASE as u8 && quantized.luma_rem != 0;
            let residual = reconstruct_vvc_luma_dc_residual_sample(
                quantized.luma_rem,
                negative,
                node.width,
                node.height,
            );
            let sample = (i16::from(predicted) + residual).clamp(0, u8::MAX as i16) as u8;
            fill_visible_luma_node(&mut luma, frame.geometry, node, sample);
            anchor_leaf = false;
        } else {
            let sample = predict_luma_leaf_sample(&luma, frame.geometry, node);
            fill_visible_luma_node(&mut luma, frame.geometry, node, sample);
        }
    }

    // Chroma CBFs are currently emitted as false in the 4:2:0 path, so the
    // decoder-visible reconstruction is neutral intra prediction.
    let chroma_len = frame.geometry.luma_samples() / 4;
    let mut out = Vec::with_capacity(frame.geometry.luma_samples() + chroma_len * 2);
    out.extend_from_slice(&luma);
    out.extend(std::iter::repeat_n(128, chroma_len));
    out.extend(std::iter::repeat_n(128, chroma_len));
    out
}

fn predict_luma_leaf_sample(
    luma: &[u8],
    geometry: VvcVideoGeometry,
    node: VvcCodingTreeNode,
) -> u8 {
    // H.266 8.4.5 intra prediction uses neighbouring reconstructed reference
    // samples, with unavailable references initialized around the middle of
    // the sample range. The current encoder always signals the same explicit
    // luma angular mode, so a single representative neighbour is sufficient
    // for the solid-DC subset until per-sample intra prediction is implemented.
    let x = usize::from(node.x).min(geometry.width.saturating_sub(1));
    let y = usize::from(node.y).min(geometry.height.saturating_sub(1));
    if y > 0 {
        return luma[(y - 1) * geometry.width + x];
    }
    if x > 0 {
        return luma[y * geometry.width + x - 1];
    }
    128
}

fn fill_visible_luma_node(
    luma: &mut [u8],
    geometry: VvcVideoGeometry,
    node: VvcCodingTreeNode,
    sample: u8,
) {
    let start_x = usize::from(node.x);
    let start_y = usize::from(node.y);
    let end_x = (start_x + usize::from(node.width)).min(geometry.width);
    let end_y = (start_y + usize::from(node.height)).min(geometry.height);
    for y in start_y..end_y {
        let row = y * geometry.width;
        for x in start_x..end_x {
            luma[row + x] = sample;
        }
    }
}
