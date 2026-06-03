use super::super::{VvcCodingTreeNode, VvcVideoGeometry};

pub(in crate::vvc) fn predict_vvc_luma_dc_block(
    luma: &[u8],
    geometry: VvcVideoGeometry,
    node: VvcCodingTreeNode,
) -> Vec<u8> {
    let width = usize::from(node.width);
    let height = usize::from(node.height);
    let top = luma_top_references(luma, geometry, node, width);
    let left = luma_left_references(luma, geometry, node, height);
    let dc = dc_prediction_value(&top, &left, width, height);
    let mut prediction = vec![dc; width * height];

    // VTM IntraPrediction::predIntraAng applies PDPC to DC mode when the
    // luma TU is at least MIN_TB_SIZEY in both dimensions and multiRefIdx is
    // zero. FrameForge currently always signals multiRefIdx = 0.
    if width >= 4 && height >= 4 {
        let scale = ((width.ilog2() as i32 - 2 + height.ilog2() as i32 - 2 + 2) >> 2) as u32;
        for y in 0..height {
            let wt = 32i32 >> ((y << 1) >> scale).min(31);
            let left_sample = i32::from(left[y]);
            for x in 0..width {
                let wl = 32i32 >> ((x << 1) >> scale).min(31);
                let top_sample = i32::from(top[x]);
                let val = i32::from(dc);
                prediction[y * width + x] =
                    (val + ((wl * (left_sample - val) + wt * (top_sample - val) + 32) >> 6))
                        .clamp(0, u8::MAX as i32) as u8;
            }
        }
    }

    prediction
}

pub(in crate::vvc) fn fill_visible_luma_node(
    luma: &mut [u8],
    geometry: VvcVideoGeometry,
    node: VvcCodingTreeNode,
    predicted: &[u8],
    residuals: &[i16],
) {
    let node_width = usize::from(node.width);
    let start_x = usize::from(node.x);
    let start_y = usize::from(node.y);
    let end_x = (start_x + node_width).min(geometry.width);
    let end_y = (start_y + usize::from(node.height)).min(geometry.height);
    for y in start_y..end_y {
        let row = y * geometry.width;
        let src_y = y - start_y;
        for x in start_x..end_x {
            let src_x = x - start_x;
            let idx = src_y * node_width + src_x;
            luma[row + x] =
                (i16::from(predicted[idx]) + residuals[idx]).clamp(0, u8::MAX as i16) as u8;
        }
    }
}

fn luma_top_references(
    luma: &[u8],
    geometry: VvcVideoGeometry,
    node: VvcCodingTreeNode,
    width: usize,
) -> Vec<u8> {
    let start_x = usize::from(node.x);
    let start_y = usize::from(node.y);
    if start_y > 0 {
        let row = (start_y - 1) * geometry.width;
        return (0..width)
            .map(|x| {
                let src_x = (start_x + x).min(geometry.width.saturating_sub(1));
                luma[row + src_x]
            })
            .collect();
    }

    let fallback = if start_x > 0 && start_y < geometry.height {
        luma[start_y * geometry.width + start_x - 1]
    } else {
        128
    };
    vec![fallback; width]
}

fn luma_left_references(
    luma: &[u8],
    geometry: VvcVideoGeometry,
    node: VvcCodingTreeNode,
    height: usize,
) -> Vec<u8> {
    let start_x = usize::from(node.x);
    let start_y = usize::from(node.y);
    if start_x > 0 {
        return (0..height)
            .map(|y| {
                let src_y = (start_y + y).min(geometry.height.saturating_sub(1));
                luma[src_y * geometry.width + start_x - 1]
            })
            .collect();
    }

    let fallback = if start_y > 0 && start_x < geometry.width {
        luma[(start_y - 1) * geometry.width + start_x]
    } else {
        128
    };
    vec![fallback; height]
}

fn dc_prediction_value(top: &[u8], left: &[u8], width: usize, height: usize) -> u8 {
    let mut sum = 0u32;
    if width >= height {
        sum += top.iter().map(|sample| u32::from(*sample)).sum::<u32>();
    }
    if width <= height {
        sum += left.iter().map(|sample| u32::from(*sample)).sum::<u32>();
    }
    let denom = if width == height {
        width << 1
    } else {
        width.max(height)
    } as u32;
    ((sum + (denom >> 1)) >> denom.ilog2()) as u8
}
