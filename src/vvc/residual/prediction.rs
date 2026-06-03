use super::super::{VvcCodingTreeNode, VvcVideoGeometry};

pub(in crate::vvc) fn predict_vvc_luma_dc_block(
    luma: &[u8],
    geometry: VvcVideoGeometry,
    node: VvcCodingTreeNode,
) -> Vec<u8> {
    predict_vvc_dc_block(
        luma,
        geometry.width,
        geometry.height,
        usize::from(node.x),
        usize::from(node.y),
        usize::from(node.width),
        usize::from(node.height),
    )
}

pub(in crate::vvc) fn predict_vvc_chroma_dc_block(
    chroma: &[u8],
    geometry: VvcVideoGeometry,
    node: VvcCodingTreeNode,
) -> Vec<u8> {
    predict_vvc_dc_block(
        chroma,
        geometry.width / 2,
        geometry.height / 2,
        usize::from(node.x / 2),
        usize::from(node.y / 2),
        usize::from(node.width / 2),
        usize::from(node.height / 2),
    )
}

fn predict_vvc_dc_block(
    plane: &[u8],
    plane_width: usize,
    plane_height: usize,
    start_x: usize,
    start_y: usize,
    width: usize,
    height: usize,
) -> Vec<u8> {
    let top = top_references(plane, plane_width, plane_height, start_x, start_y, width);
    let left = left_references(plane, plane_width, plane_height, start_x, start_y, height);
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
                prediction[y * width + x] = (val
                    + ((wl * (left_sample - val) + wt * (top_sample - val) + 32) >> 6))
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

pub(in crate::vvc) fn fill_visible_chroma_node(
    chroma: &mut [u8],
    geometry: VvcVideoGeometry,
    node: VvcCodingTreeNode,
    predicted: &[u8],
    residuals: &[i16],
) {
    let node_width = usize::from(node.width / 2);
    let start_x = usize::from(node.x / 2);
    let start_y = usize::from(node.y / 2);
    let chroma_width = geometry.width / 2;
    let chroma_height = geometry.height / 2;
    let end_x = (start_x + node_width).min(chroma_width);
    let end_y = (start_y + usize::from(node.height / 2)).min(chroma_height);
    for y in start_y..end_y {
        let row = y * chroma_width;
        let src_y = y - start_y;
        for x in start_x..end_x {
            let src_x = x - start_x;
            let idx = src_y * node_width + src_x;
            chroma[row + x] =
                (i16::from(predicted[idx]) + residuals[idx]).clamp(0, u8::MAX as i16) as u8;
        }
    }
}

fn top_references(
    plane: &[u8],
    plane_width: usize,
    plane_height: usize,
    start_x: usize,
    start_y: usize,
    width: usize,
) -> Vec<u8> {
    if start_y > 0 {
        let row = (start_y - 1) * plane_width;
        return (0..width)
            .map(|x| {
                let src_x = (start_x + x).min(plane_width.saturating_sub(1));
                plane[row + src_x]
            })
            .collect();
    }

    let fallback = if start_x > 0 && start_y < plane_height {
        plane[start_y * plane_width + start_x - 1]
    } else {
        128
    };
    vec![fallback; width]
}

fn left_references(
    plane: &[u8],
    plane_width: usize,
    plane_height: usize,
    start_x: usize,
    start_y: usize,
    height: usize,
) -> Vec<u8> {
    if start_x > 0 {
        return (0..height)
            .map(|y| {
                let src_y = (start_y + y).min(plane_height.saturating_sub(1));
                plane[src_y * plane_width + start_x - 1]
            })
            .collect();
    }

    let fallback = if start_y > 0 && start_x < plane_width {
        plane[(start_y - 1) * plane_width + start_x]
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
